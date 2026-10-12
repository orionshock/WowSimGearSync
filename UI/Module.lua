local _, WSGS = ...
local UI = WSGS:NewModule("UI", "AceEvent-3.0")
WSGS.UI = UI

local refreshEvents = {"GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "SKILL_LINES_CHANGED"}

function UI:RefreshEscapeWindow()
    if not self.escapeWindowRegistered then
        table.insert(UISpecialFrames, "WSGSEscapeWindow")
        self.escapeWindowRegistered = true
    end
    _G.WSGSEscapeWindow = self.importDialog and self.importDialog:IsShown() and self.importDialog or self.paperDoll and
                              self.paperDoll:IsShown() and self.paperDoll or nil
end

function UI:CommitBuildName()
    local input = self.paperDoll.buildName
    local build, reason = WSGS.Import:RenameBuild(WSGS.db.char, input.buildId, input:GetText())
    if build then
        self.profile = build
        input:SetText(build.name)
    else
        input:SetText(self.profile and self.profile.name or "No active build")
    end
    input:ClearFocus()
    return build, reason
end

function UI:RefreshPaperDoll()
    if not self.paperDoll or not self.paperDoll:IsShown() then
        return
    end
    local profile, snapshot, comparison, reason = WSGS.EquipmentActions:RefreshCurrentBuild()
    self:RenderPaperDoll(profile, snapshot, comparison, reason)
end

function UI:QueuePaperDollRefresh(event, itemId, success)
    if not self.paperDoll or not self.paperDoll:IsShown() then
        return
    end
    if event ~= "PLAYER_EQUIPMENT_CHANGED" and event ~= "SKILL_LINES_CHANGED" and
        (not success or not self.relevantItems[itemId]) then
        return
    end
    if self.refreshQueued then
        return
    end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        self:RefreshPaperDoll()
    end)
end

function UI:OnUIEvent(event, ...)
    self:QueuePaperDollRefresh(event, ...)
end

function UI:WSGS_BUILD_IMPORTED()
    self:RefreshPaperDoll()
end

function UI:WSGS_ACTIONS_CHANGED()
    self:QueuePaperDollRefresh("PLAYER_EQUIPMENT_CHANGED")
end

function UI:WSGS_EQUIPMENT_STATE_CHANGED()
    self:UpdateEquipButton()
end

function UI:WSGS_EQUIPMENT_REFRESH_REQUESTED()
    self:QueuePaperDollRefresh("PLAYER_EQUIPMENT_CHANGED")
end

function UI:OnEnable()
    for _, event in ipairs(refreshEvents) do
        self:RegisterEvent(event, "OnUIEvent")
    end
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterMessage("WSGS_ACTIONS_CHANGED")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_CHANGED")
    self:RegisterMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED")
end

function UI:TogglePaperDoll()
    local frame = self:CreatePaperDoll()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
