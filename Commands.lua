local addonName, WSGS = ...

function WSGS:RegisterCommands()
    self.commandOptions = {
        type = "group", name = "WowSimGearSync", args = {
            debug = {
                type = "toggle", name = "Debug", desc = "Toggle diagnostic output.", order = 1,
                get = function() return self.db.profile.debug end,
                set = function(_, enabled)
                    self.db.profile.debug = enabled
                    self:Print("Debug " .. (enabled and "enabled." or "disabled."))
                end,
            },
            compare = {
                type = "execute", name = "Compare", desc = "Compare the latest imported build.", order = 2,
                validate = function(info)
                    if info.input:match("^%S+%s+%S") then return "Usage: /wsgs compare" end
                    return true
                end,
                func = function() self:CompareLatestEquipment() end,
            },
            probe = {
                type = "input", name = "Probe", desc = "Inspect an export position (1-16).", order = 3,
                get = function() return "" end,
                validate = function(_, value)
                    local position = tonumber(value)
                    if not position or position ~= math.floor(position) or position < 1 or position > 16 then
                        return "Usage: /wsgs probe <export position 1-16>"
                    end
                    return true
                end,
                set = function(_, value) self:ProbeEquipment(tonumber(value)) end,
            },
            test = {
                type = "input", name = "Test", desc = "Run all, scanner, comparator, or importer tests.", order = 4,
                get = function() return "" end,
                validate = function(_, value)
                    if value == "" or value == "all" or self.Tests.suites[value] then return true end
                    return "Use all, scanner, comparator, or importer."
                end,
                set = function(_, value) self.Tests:Run(value) end,
            },
        },
    }
    -- Register once; AceConsole owns the slash command and AceConfigCmd parses
    -- every nonempty invocation. Root behavior is the documented AceConfig adapter.
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, self.commandOptions)
    self:RegisterChatCommand("wsgs", "ChatCommand")
end

function WSGS:ChatCommand(input)
    input = (input or ""):match("^%s*(.-)%s*$"):lower():gsub("%s+", " ")
    if input == "" then self:ToggleWindow(); return end
    LibStub("AceConfigCmd-3.0"):HandleCommand("wsgs", addonName, input)
end

function WSGS:RegisterCommandCompletion()
    -- Local AceConfigCmd advertises completion but never calls AceTab. Register
    -- actual chat EditBox hooks via AceTab, with phrase candidates for arguments.
    local candidates = {}
    for command in pairs(self.commandOptions.args) do candidates[#candidates + 1] = command end
    for _, suite in ipairs({ "all", "scanner", "comparator", "importer" }) do
        candidates[#candidates + 1] = "test " .. suite
    end
    for position = 1, 16 do candidates[#candidates + 1] = "probe " .. position end
    LibStub("AceTab-3.0"):RegisterTabCompletion(
        "WSGS commands", "^/[wW][sS][gG][sS]%s+", candidates, true
    )
end
