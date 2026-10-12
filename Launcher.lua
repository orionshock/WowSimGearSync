local _, WSGS = ...
local name = "WowSimGearSync"
local icon = "Interface\\Icons\\INV_Chest_Plate04"

function WSGS:InitializeLauncher()
    self.launcher = LibStub("LibDataBroker-1.1"):NewDataObject(name, {
        type = "launcher", label = name, icon = icon,
        OnClick = function(_, button)
            if button == "LeftButton" then self.PaperDoll:Toggle()
            elseif button == "RightButton" then self:ToggleWindow() end
        end,
        OnTooltipShow = function(tooltip)
            local build = self:GetActiveSimulationProfile()
            tooltip:AddLine(name)
            tooltip:AddLine("Active build: " .. (build and build.name or "None"), 1, 1, 1)
            tooltip:AddLine("Left-click: Toggle equipment view", 0.8, 0.8, 0.8)
            tooltip:AddLine("Right-click: Toggle import window", 0.8, 0.8, 0.8)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register(name, self.launcher, self.db.profile.minimap)
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshLauncherSettings")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshLauncherSettings")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshLauncherSettings")
end

function WSGS:RefreshLauncherSettings()
    LibStub("LibDBIcon-1.0"):Refresh(name, self.db.profile.minimap)
end
