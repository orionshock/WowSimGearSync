local addonName, WSGS = ...

WSGS.version = "0.1.0"

function WSGS:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("[WSGS] " .. message)
end

function WSGS:Debug(message)
    if self.db and self.db.settings.debug then
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
    if type(WSGSDB.settings) ~= "table" then
        WSGSDB.settings = {}
    end
    if type(WSGSDB.settings.debug) ~= "boolean" then
        WSGSDB.settings.debug = false
    end
    if type(WSGSDB.profiles) ~= "table" then
        WSGSDB.profiles = {}
    end
    WSGS.db = WSGSDB
    self:UnregisterEvent("ADDON_LOADED")
    WSGS:Debug("Loaded version " .. WSGS.version .. ".")
end)

SLASH_WSGS1 = "/wsgs"
SlashCmdList.WSGS = function(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "" then
        WSGS:ToggleWindow()
    elseif command == "debug" then
        WSGS.db.settings.debug = not WSGS.db.settings.debug
        WSGS:Print("Debug " .. (WSGS.db.settings.debug and "enabled." or "disabled."))
    else
        WSGS:Print("Usage: /wsgs or /wsgs debug")
    end
end
