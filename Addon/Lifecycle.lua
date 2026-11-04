local addonName, WSGS = ...
local Modules = WSGS.Private
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")

local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
WSGS.version = version and not version:find("@", 1, true) and version or "Development"

local defaults = {
    profile = {
        equipmentSets = true,
        debug = false,
        minimap = {
            hide = true,
            minimapPos = 225
        }
    },
    char = {}
}

function WSGS:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("WSGSDB", defaults, true)
    self:RegisterAceConfig()
    self:RegisterDBIcon()
    local clientVersion, build, _, interface = GetBuildInfo()
    self:Debug(string.format("[CLIENT] version=%s build=%s interface=%s addon=%s",
        clientVersion, build, tostring(interface), self.version))
end
