local _, WSGS = ...
local UI = WSGS:NewModule("UI", "AceEvent-3.0")
local Equipment = WSGS:GetModule("Equipment")
WSGS.UI = UI

local refreshEvents = {
    PLAYER_EQUIPMENT_CHANGED = true,
    BAG_UPDATE_DELAYED = true,
    ITEM_LOCK_CHANGED = true,
    SPELLS_CHANGED = true,
    SKILL_LINES_CHANGED = true,
    PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true,
    CURSOR_CHANGED = true
}
local itemDataEvents = {GET_ITEM_INFO_RECEIVED = true, ITEM_DATA_LOAD_RESULT = true}

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
    local state = Equipment:RefreshCurrentBuild()
    self:RenderPaperDoll(state)
end

function UI:QueuePaperDollRefresh(event, itemId, success)
    if not self.paperDoll or not self.paperDoll:IsShown() then
        return
    end
    if not refreshEvents[event] and
        (not itemDataEvents[event] or not success or not self.relevantItems[itemId]) then
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


function UI:WSGS_BUILD_IMPORTED()
    self:RefreshPaperDoll()
end

function UI:WSGS_ACTIONS_CHANGED()
    self:QueuePaperDollRefresh("PLAYER_EQUIPMENT_CHANGED")
end

function UI:WSGS_EQUIPMENT_STATE_CHANGED()
    self:UpdateEquipButton()
end

function UI:WSGS_EQUIPMENT_REFRESH_REQUESTED(_, event, ...)
    self:QueuePaperDollRefresh(event, ...)
end

function UI:WSGS_ITEM_DATA_RECEIVED(_, itemID, success, requester)
    if requester ~= "PaperDoll:target" and requester ~= "PaperDoll:modification-tooltip" then
        return
    end
    self.requestedItems[itemID] = nil
    if success then
        self:QueuePaperDollRefresh("ITEM_DATA_LOAD_RESULT", itemID, true)
    end
end

function UI:OnEnable()
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterMessage("WSGS_ACTIONS_CHANGED")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_CHANGED")
    self:RegisterMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED")
    self:RegisterMessage("WSGS_ITEM_DATA_RECEIVED")
end

function UI:TogglePaperDoll()
    local frame = self:CreatePaperDoll()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
