local _, WSGS = ...
local Modules = WSGS.Private
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")
local ldbObjectName = "WowSimGearSync"
local ldbObjectDefinition = {
    type = "launcher",
    label = ldbObjectName,
    icon = "Interface\\Icons\\INV_Chest_Plate04",
    OnClick = function(_, button)
        if button == "LeftButton" then
            WSGS.Views:ToggleEquipment()
        elseif button == "RightButton" then
            Settings.OpenToCategory(WSGS.optionsCategory)
        end
    end,
    OnTooltipShow = function(tooltip)
        local build = WSGS.Builds:GetActive()
        tooltip:AddLine(ldbObjectName)
        tooltip:AddLine(string.format(L["Active build: %s"], build and build.name or L["None"]), 1, 1, 1)
        tooltip:AddLine(L["Left-click: Toggle equipment view"], 0.8, 0.8, 0.8)
        tooltip:AddLine(L["Right-click: Open options"], 0.8, 0.8, 0.8)
    end
}

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
