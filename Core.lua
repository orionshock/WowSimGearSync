local addonName, WSGS = ...

WSGS.version = "0.1.1"

local defaults = {
    global = {
        settings = { debug = false },
        simulationProfiles = {},
    },
}

function WSGS:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("[WSGS] " .. message)
end

function WSGS:Debug(message)
    if self.db and self.db.global.settings.debug then
        self:Print(message)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= addonName then
        return
    end

    if type(WSGSDB) ~= "table" then
        WSGSDB = {}
    end
    -- The foundation used root settings/profiles before AceDB owned this table.
    -- Move simulation data out of AceDB's reserved profiles key exactly once.
    if type(WSGSDB.settings) == "table" then
        if type(WSGSDB.global) ~= "table" then
            WSGSDB.global = {}
        end
        WSGSDB.global.settings = WSGSDB.settings
        if type(WSGSDB.profiles) == "table" then
            WSGSDB.global.simulationProfiles = WSGSDB.profiles
        end
        WSGSDB.settings = nil
        WSGSDB.profiles = nil
    end
    WSGS.db = LibStub("AceDB-3.0"):New("WSGSDB", defaults, true)
    self:UnregisterEvent("ADDON_LOADED")
    WSGS:Debug("Loaded version " .. WSGS.version .. ".")
end)

SLASH_WSGS1 = "/wsgs"
SlashCmdList.WSGS = function(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "" then
        WSGS:ToggleWindow()
    elseif command == "debug" then
        WSGS.db.global.settings.debug = not WSGS.db.global.settings.debug
        WSGS:Print("Debug " .. (WSGS.db.global.settings.debug and "enabled." or "disabled."))
    else
        WSGS:Print("Usage: /wsgs or /wsgs debug")
    end
end
