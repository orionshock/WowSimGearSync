local _, WSGS = ...

-- Native decoding handles JSON syntax and escapes. This structural adapter keeps
-- array/object/null distinctions that ordinary Lua tables cannot represent.
local JSON = { null = {} }
WSGS.JSON = JSON
local objectMeta, arrayMeta = { kind = "object" }, { kind = "array" }

function JSON.Kind(value)
    if value == JSON.null then return "null" end
    local meta = type(value) == "table" and getmetatable(value)
    return meta and meta.kind or type(value)
end

function JSON.Decode(text)
    if type(text) ~= "string" or #text == 0 then
        return nil, "Paste a WoW Sims JSON export first."
    end
    if #text > 1048576 then return nil, "Export exceeds the 1 MiB import limit." end
    if not C_EncodingUtil or not C_EncodingUtil.DeserializeJSON then
        return nil, "This client does not provide C_EncodingUtil.DeserializeJSON."
    end
    local position, length = 1, #text
    local function fail(message)
        error(message .. " at byte " .. position .. ".", 0)
    end
    local function whitespace()
        local _, last = text:find("^[ \t\r\n]*", position)
        position = (last or position - 1) + 1
    end
    local function native(token, expected)
        local ok, value = pcall(C_EncodingUtil.DeserializeJSON, token)
        if not ok or type(value) ~= expected then fail("Invalid JSON " .. expected) end
        return value
    end
    local function readString()
        local start = position
        position = position + 1
        while position <= length do
            local char = text:sub(position, position)
            if char == '"' then
                position = position + 1
                return native(text:sub(start, position - 1), "string")
            elseif char == "\\" then
                position = position + 2
            else
                if char:byte() < 32 then fail("Unescaped control character") end
                position = position + 1
            end
        end
        fail("Unterminated JSON string")
    end
    local readValue
    readValue = function(depth)
        if depth > 64 then fail("JSON nesting exceeds 64 levels") end
        whitespace()
        local char = text:sub(position, position)
        if char == '"' then return readString() end
        if char == "{" or char == "[" then
            local isObject = char == "{"
            local result = setmetatable({}, isObject and objectMeta or arrayMeta)
            local close = isObject and "}" or "]"
            local index = 0
            position = position + 1
            whitespace()
            if text:sub(position, position) == close then
                position = position + 1
                return result
            end
            while true do
                local key
                if isObject then
                    if text:sub(position, position) ~= '"' then fail("Expected object key") end
                    key = readString()
                    if result[key] ~= nil then fail("Duplicate JSON object key") end
                    whitespace()
                    if text:sub(position, position) ~= ":" then fail("Expected colon") end
                    position = position + 1
                else
                    index = index + 1
                    key = index
                end
                result[key] = readValue(depth + 1)
                whitespace()
                char = text:sub(position, position)
                position = position + 1
                if char == close then return result end
                if char ~= "," then fail("Expected comma or closing delimiter") end
                whitespace()
            end
        end
        local token = text:match("^[^,%]%}%s]+", position)
        if not token then fail("Expected JSON value") end
        position = position + #token
        if token == "null" then return JSON.null end
        if token == "true" then return true end
        if token == "false" then return false end
        -- Explicit JSON number grammar, including fraction and exponent rules.
        local integer, suffix = token:match("^(-?%d+)(.*)$")
        if not integer or integer:match("^-?0%d") then fail("Invalid JSON value") end
        if suffix:sub(1, 1) == "." then
            suffix = suffix:match("^%.%d+(.*)$")
            if not suffix then fail("Invalid fraction") end
        end
        if suffix ~= "" and not suffix:match("^[eE][+-]?%d+$") then fail("Invalid exponent") end
        local number = native(token, "number")
        if number ~= number or math.abs(number) == math.huge then fail("Non-finite number") end
        return number
    end
    local ok, value = pcall(function()
        local result = readValue(0)
        whitespace()
        if position <= length then fail("Unexpected trailing JSON data") end
        return result
    end)
    if not ok then return nil, value end
    return value
end
