local addonName, WSGS = ...
LibStub("AceAddon-3.0"):NewAddon(WSGS, addonName, "AceConsole-3.0", "AceEvent-3.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")

WSGS.version = "0.3.0"

local defaults = {
    profile = {
        recommendedEngineeringTinkers = true,
        debug = true,
        minimap = {
            hide = true,
            minimapPos = 225
        }
    },
    char = {
        simulationProfiles = {}
    }
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
        engineering = {
            type = "toggle",
            name = "Engineering defaults",
            order = 5,
            desc = "Recommend glove and waist tinkers when the export omits them; Goblin Glider is always presumed.",
            get = function()
                return WSGS.db.profile.recommendedEngineeringTinkers
            end,
            set = function(_, enabled)
                WSGS.db.profile.recommendedEngineeringTinkers = enabled
                WSGS.UI:RefreshPaperDoll()
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
            WSGS.UI:ToggleImportDialog()
        end
    end,
    OnTooltipShow = function(tooltip)
        local build = WSGS:GetActiveSimulationProfile()
        tooltip:AddLine(ldbObjectName)
        tooltip:AddLine("Active build: " .. (build and build.name or "None"), 1, 1, 1)
        tooltip:AddLine("Left-click: Toggle equipment view", 0.8, 0.8, 0.8)
        tooltip:AddLine("Right-click: Toggle import window", 0.8, 0.8, 0.8)
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

function WSGS:RegisterAceConfig()
    LibStub("AceConfig-3.0"):RegisterOptionsTable("WowSimGearSync", commandOptions)
    LibStub("AceConfigCmd-3.0"):CreateChatCommand("wsgs", "WowSimGearSync")
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
    local character = self.db.char
    return character.simulationProfiles[character.latestSimulationProfileId]
end
