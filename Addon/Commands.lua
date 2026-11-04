local _, WSGS = ...
local Modules = WSGS.Private
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
local commandOptions = {
    type = "group",
    name = "WowSimGearSync",
    args = {
        import = {
            type = "execute",
            name = "Import",
            desc = "Toggle the WoW Sims import screen.",
            order = 0,
            func = function()
                WSGS.Views:ToggleImport()
            end
        },
        debug = {
            type = "toggle",
            name = "Debug",
            desc = "Toggle diagnostic output.",
            order = 1,
            get = function()
                return WSGS.db.profile.debug
            end,
            set = function(_, enabled)
                WSGS.db.profile.debug = enabled
                WSGS:Print("Debug " .. (enabled and "enabled." or "disabled."))
            end
        },
        compare = {
            type = "execute",
            name = "Compare",
            desc = "Compare the latest imported build.",
            order = 2,
            func = function()
                WSGS:CompareLatestEquipment()
            end
        },
        probe = {
            type = "input",
            name = "Probe",
            desc = "Inspect an export position (1-17).",
            order = 3,
            get = function()
                return ""
            end,
            validate = function(_, value)
                local position = tonumber(value)
                if not position or position ~= math.floor(position) or position < 1 or position > #WSGS.Equipment.Slots then
                    return "Usage: /wsgs probe <export position 1-17>"
                end
                return true
            end,
            set = function(_, value)
                WSGS:ProbeEquipment(tonumber(value))
            end
        },
        options = {
            type = "execute",
            name = "Options",
            order = 5,
            func = function()
                Settings.OpenToCategory(WSGS.optionsCategory)
            end
        }
    }
}

function WSGS:RegisterAceConfig()
    LibStub("AceConfig-3.0"):RegisterOptionsTable("WowSimGearSync", commandOptions)
    LibStub("AceConfigCmd-3.0"):CreateChatCommand("wsgs", "WowSimGearSync")
    self:RegisterOptionsPanel()
end
