local addonName, WSGS = ...
LibStub("AceAddon-3.0"):NewAddon(WSGS, addonName, "AceConsole-3.0", "AceEvent-3.0")

WSGS.version = "0.3.0"

local defaults = {
    profile = { debug = true },
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
    self:Debug("Loaded version " .. self.version .. ".")
end
