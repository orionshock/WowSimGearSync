local _, WSGS = ...

function WSGS:RegisterCommands()
    self.commandOptions = {
        type = "group", name = "WowSimGearSync", args = {
            import = {
                type = "execute", name = "Import", desc = "Toggle the WoW Sims import screen.", order = 0,
                func = function() self:ToggleWindow() end,
            },
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
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigCmd = LibStub("AceConfigCmd-3.0")
    AceConfig:RegisterOptionsTable("WowSimGearSync", self.commandOptions)
    AceConfigCmd:CreateChatCommand("wsgs", "WowSimGearSync")
end
