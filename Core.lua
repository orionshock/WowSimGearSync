local addonName, WSGS = ...
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
LibStub("AceAddon-3.0"):NewAddon(WSGS, addonName, "AceConsole-3.0", "AceEvent-3.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")

local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
WSGS.version = version and not version:find("@", 1, true) and version or "Development"

local defaults = {
    profile = {
        engineeringCloakFallback = true,
        equipmentSets = true,
        debug = false,
        minimap = {
            hide = true,
            minimapPos = 225
        }
    },
    char = {}
}

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
                WSGS.UI:ToggleImportDialog()
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
            desc = "Inspect an export position (1-16).",
            order = 3,
            get = function()
                return ""
            end,
            validate = function(_, value)
                local position = tonumber(value)
                if not position or position ~= math.floor(position) or position < 1 or position > 16 then
                    return "Usage: /wsgs probe <export position 1-16>"
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

local ldbObjectName = "WowSimGearSync"
local ldbObjectDefinition = {
    type = "launcher",
    label = ldbObjectName,
    icon = "Interface\\Icons\\INV_Chest_Plate04",
    OnClick = function(_, button)
        if button == "LeftButton" then
            WSGS.UI:TogglePaperDoll()
        elseif button == "RightButton" then
            Settings.OpenToCategory(WSGS.optionsCategory)
        end
    end,
    OnTooltipShow = function(tooltip)
        local build = WSGS:GetActiveSimulationProfile()
        tooltip:AddLine(ldbObjectName)
        tooltip:AddLine(string.format(L["Active build: %s"], build and build.name or L["None"]), 1, 1, 1)
        tooltip:AddLine(L["Left-click: Toggle equipment view"], 0.8, 0.8, 0.8)
        tooltip:AddLine(L["Right-click: Open options"], 0.8, 0.8, 0.8)
    end
}

function WSGS:Print(message)
    local separator = message:sub(1, 1) == "[" and "" or " "
    DEFAULT_CHAT_FRAME:AddMessage("[WSGS]" .. separator .. message)
end

function WSGS:Debug(message)
    if self.db and self.db.profile.debug then
        self:Print(message)
    end
end

-- Translate diagnostic reasons only where they are shown to the player.
-- Keep the original reasons on operations and in structured debug output.
local playerReasons = {
    ["Awaiting client verification."] = "Waiting for the item to update.",
    ["Equipped item instance is not available yet"] = "Equipped item information is not available yet",
    ["Equipped item identity is not available yet"] = "Equipped item information is not available yet",
    ["Equipped item identity unknown"] = "Equipped item information is not available yet",
    ["Upgrade tooltip unavailable, unreadable, or inconsistent"] = "Upgrade information is not available yet",
    ["Upgrade eligibility and maximum are not established"] = "Upgrade information is not available yet",
    ["Target item is not confirmed in this slot"] = "Equip the target item first",
    ["Modification representations have no verified conversion"] = "This enhancement could not be identified",
    ["Required modification could not be observed"] = "Enhancement information is not available yet",
    ["No confirmed direct profession enhancement mapping"] = "This profession enhancement is not supported yet",
    ["No confirmed Blacksmithing socket recipe for this slot"] = "No supported socket recipe for this slot",
    ["Required enchantment material is not yet known"] = "The material for this enchantment is not known yet",
    ["No verified equipped-item observation for this field"] = "Item information is not available yet",
    ["Profession effect not established"] = "Profession enhancement information is not available yet",
    ["C_Item.GetItemSpell returned nil"] = "Profession enhancement information is not available yet",
    ["C_Item.GetItemSpell failed"] = "Profession enhancement information could not be read",
    ["Equipped item use spell is not mapped for this profession slot"] = "This profession enhancement could not be identified",
    ["Equipment snapshot is unavailable."] = "Equipment information is not available yet.",
    ["Only numeric apiVersion 3 is supported."] = "Unsupported export format. Export your gear again from WoW Sims.",
    ["Missing player object."] = "The export is missing character information.",
    ["Missing player.equipment object."] = "The export is missing gear. Include Gear when exporting from WoW Sims.",
    ["player.equipment.items must be an array."] = "The exported gear list is invalid. Export it again from WoW Sims.",
    ["player.class must be a class name or positive numeric identifier."] = "The export contains invalid class information.",
    ["Required recipe did not appear in the unfiltered profession list"] = "The required recipe is not available in your profession window",
    ["Resolved profession entry is not an executable recipe"] = "The required profession recipe cannot be used",
    ["DoTradeSkill did not begin item targeting"] = "The recipe did not let you select an item",
    ["The equipped target item or instance changed before application"] = "The equipped item changed; select it again",
    ["ReforgeLite is loaded, but its exact-import interface is unavailable."] = "ReforgeLite cannot accept this build. Check that it is up to date.",
    ["ReforgeLite prepared the exact queue, but its Apply control is unavailable."] = "ReforgeLite's Apply button is unavailable.",
    ["No remaining reforge can be submitted safely."] = "The remaining reforges cannot be applied right now."
}

function WSGS:FormatPlayerReason(reason)
    if not reason then
        return nil
    end
    if playerReasons[reason] then
        return playerReasons[reason]
    end
    for diagnostic, text in pairs(playerReasons) do
        local first, last = reason:find(diagnostic, 1, true)
        if first then
            reason = reason:sub(1, first - 1) .. text .. reason:sub(last + 1)
        end
    end
    return (reason:gsub("item (%d+) is ", function(itemID)
        return (C_Item.GetItemInfo(tonumber(itemID)) or "Target item") .. " is "
    end):gsub("Item (%d+) requested", function(itemID)
        return (C_Item.GetItemInfo(tonumber(itemID)) or "Target item") .. " requested"
    end):gsub("Associated set ID %d+", "The associated equipment set")
        :gsub("item state MISMATCH", "wrong item equipped")
        :gsub("item state UNKNOWN", "item information unavailable")
        :gsub("selected item instance is not equipped", "selected item is not equipped")
        :gsub("ambiguous duplicate instances", "duplicates that cannot be safely distinguished")
        :gsub("target slot%(s%) unresolved", "items still need attention")
        :gsub("Equipment Manager API error:", "Equipment Manager could not save the set:")
        :gsub("instance changed; rescan required", "item changed; try again")
        :gsub("Upgrade eligibility", "Upgrade availability")
        :gsub("combat lockdown", "combat")
        :gsub("could not stage the item", "could not select the item")
        :gsub("Item staging is unavailable", "Item selection is unavailable")
        :gsub("DoTradeSkill failed:", "Crafting failed:")
        :gsub("Reforge transaction failed:", "Reforging failed:")
        :gsub("ReforgeLite import handoff failed:", "Could not send this build to ReforgeLite:")
        :gsub("ReforgeLite could not start its queue:", "ReforgeLite could not apply the reforges:"))
end

function WSGS:RegisterAceConfig()
    LibStub("AceConfig-3.0"):RegisterOptionsTable("WowSimGearSync", commandOptions)
    LibStub("AceConfigCmd-3.0"):CreateChatCommand("wsgs", "WowSimGearSync")
    self:RegisterOptionsPanel()
end

function WSGS:RefreshDBIconSettings()
    LibDBIcon:Refresh(ldbObjectName, self.db.profile.minimap)
end

function WSGS:RegisterDBIcon()
    self.ldbObject = LibDataBroker:NewDataObject(ldbObjectName, ldbObjectDefinition)
    LibDBIcon:Register(ldbObjectName, self.ldbObject, self.db.profile.minimap)
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshDBIconSettings")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshDBIconSettings")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshDBIconSettings")
end

function WSGS:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("WSGSDB", defaults, true)
    self:RegisterAceConfig()
    self:RegisterDBIcon()
    self:Debug("Loaded version " .. self.version .. ".")
end

function WSGS:GetActiveSimulationProfile()
    return self.db.char.activeImport
end
