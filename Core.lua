local addonName, WSGS = ...
LibStub("AceAddon-3.0"):NewAddon(WSGS, addonName, "AceConsole-3.0", "AceEvent-3.0")

WSGS.version = "0.3.0"

local defaults = {
    profile = { recommendedEngineeringTinkers = true, debug = true, minimap = { hide = false, minimapPos = 225 } },
    char = { simulationProfiles = {} },
}

function WSGS:Print(message)
    local separator = message:sub(1, 1) == "[" and "" or " "
    DEFAULT_CHAT_FRAME:AddMessage("[WSGS]" .. separator .. message)
end

function WSGS:Debug(message)
    if self.db and self.db.profile.debug then self:Print(message) end
end

function WSGS:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("WSGSDB", defaults, true)
    self:RegisterCommands()
    self:InitializeLauncher()
    self.EquipmentSetSync:Initialize()
    self.EquipmentActions:Initialize()
    self:RegisterMessage("WSGS_BUILD_IMPORTED", function() self.PaperDoll:Refresh() end)
    self:Debug("Loaded version " .. self.version .. ".")
end

function WSGS:GetActiveSimulationProfile()
    local character = self.db.char
    return character.simulationProfiles[character.latestSimulationProfileId]
end
