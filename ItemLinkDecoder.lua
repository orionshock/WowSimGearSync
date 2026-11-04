local _, WSGS = ...
local Decoder = {}
WSGS.ItemLinkDecoder = Decoder

-- Only identity and enchantment are consumed on Forever.
-- Field indices exclude the literal "item" prefix.
function Decoder:Decode(link)
    if type(link) ~= "string" then
        return nil, "Item link unavailable"
    end
    local payload = link:match("^(item:[^|%s]+)$") or link:match("^|c%x%x%x%x%x%x%x%x|H(item:[^|]+)|h.-|h|r$") or
                        link:match("^|H(item:[^|]+)|h.-|h$")
    if not payload then
        return nil, "Malformed item link"
    end
    local fields = {}
    -- The delimiter iterator preserves internal AND trailing empty positions.
    for value in (payload:sub(6) .. ":"):gmatch("(.-):") do
        fields[#fields + 1] = value
    end
    local id = tonumber(fields[1])
    if not fields[1] or not fields[1]:match("^%d+$") or not id or id <= 0 or id > 9007199254740991 then
        return nil, "Malformed item ID"
    end
    if #fields < 2 then
        return nil, "Item link lacks the verified modification fields"
    end
    local function observed(index)
        local raw = fields[index]
        if raw == "" then
            return {
                status = "KNOWN",
                value = 0,
                absent = true,
                source = "item-link field " .. index
            }
        end
        if not raw or not raw:match("^%d+$") then
            return nil
        end
        local value = tonumber(raw)
        if not value or value > 9007199254740991 then
            return nil
        end
        return {
            status = "KNOWN",
            value = value,
            absent = value == 0,
            source = "item-link field " .. index
        }
    end
    local result = {
        id = id,
        payload = payload,
        enchant = observed(2)
    }
    if not result.enchant then
        return nil, "Malformed enchant field"
    end
    return result
end
