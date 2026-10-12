local addonName, WSGS = ...

WSGS.version = "0.3.0"

local defaults = {
    global = {
        settings = { debug = false },
        simulationProfiles = {},
    },
}

function WSGS:Print(message)
    local separator = message:sub(1, 1) == "[" and "" or " "
    DEFAULT_CHAT_FRAME:AddMessage("[WSGS]" .. separator .. message)
end

function WSGS:Debug(message)
    if self.db and self.db.global.settings.debug then
        self:Print(message)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "PLAYER_LOGIN" then
        -- Register after Blizzard has created the chat edit boxes.
        LibStub("AceTab-3.0"):RegisterTabCompletion(
            "WSGS commands", "^/[wW][sS][gG][sS]%s+", { "debug", "compare", "probe" }, true
        )
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end
    if loadedAddon ~= addonName then
        return
    end

    WSGS.db = LibStub("AceDB-3.0"):New("WSGSDB", defaults, true)
    LibStub("AceConsole-3.0"):RegisterChatCommand("wsgs", function(message)
        WSGS:HandleCommand(message)
    end)
    self:UnregisterEvent("ADDON_LOADED")
    WSGS:Debug("Loaded version " .. WSGS.version .. ".")
end)

function WSGS:HandleCommand(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "" then
        WSGS:ToggleWindow()
    elseif command == "debug" then
        WSGS.db.global.settings.debug = not WSGS.db.global.settings.debug
        WSGS:Print("Debug " .. (WSGS.db.global.settings.debug and "enabled." or "disabled."))
    elseif command == "compare" then
        self:CompareLatestEquipment()
    elseif command:match("^probe%s+%d+$") then
        self:ProbeEquipment(tonumber(command:match("%d+$")))
    else
        WSGS:Print("Usage: /wsgs, /wsgs debug, /wsgs compare, or /wsgs probe <export position>")
    end
end
