local _, WSGS = ...
local Modules = WSGS.Private
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")

function WSGS:RegisterOptionsPanel()
    local options = {
        type = "group",
        name = "WowSimGearSync",
        get = function(info)
            return WSGS.db.profile[info[#info]]
        end,
        set = function(info, enabled)
            WSGS.db.profile[info[#info]] = enabled
            WSGS.Character:Invalidate("OPTIONS_CHANGED")
            WSGS.Views:RefreshEquipment()
        end,
        args = {
            debug = {
                type = "toggle",
                name = L["Enable debug logging"],
                order = 1,
                width = "full"
            },
            equipmentSets = {
                type = "toggle",
                name = L["Create/update Equipment Manager sets"],
                desc = L["Save verified equipment using the active import's name. Other sets are left alone."],
                order = 2,
                width = "full"
            }
        }
    }
    LibStub("AceConfig-3.0"):RegisterOptionsTable("WowSimGearSyncOptions", options)
    local _, category = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("WowSimGearSyncOptions", "WowSimGearSync")
    self.optionsCategory = category
end
