local _, WSGS = ...
local Modules = WSGS.Private
local UI = WSGS:NewModule("Views", "AceEvent-3.0")
local Equipment = WSGS.Equipment
Modules.Views.Runtime = UI

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
    local build, reason = WSGS.Builds:Rename(input.build, input:GetText())
    if build then
        self.profile = build
        input:SetText(build.name)
    else
        WSGS:Print(reason)
        input:SetText(self.profile and self.profile.name or "No active build")
    end
    input:ClearFocus()
    return build, reason
end

function UI:RefreshPaperDoll()
    if not self.paperDoll or not self.paperDoll:IsShown() then
        return
    end
    local state = Equipment:GetState()
    self:RenderPaperDoll(state)
end

function UI:QueuePaperDollRefresh()
    if not self.paperDoll or not self.paperDoll:IsShown() then
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


function UI:WSGS_ITEM_DATA_RECEIVED(_, itemID, success, requester)
    if requester ~= "PaperDoll:target" and requester ~= "PaperDoll:modification-tooltip" then
        return
    end
    if self.requestedItems then self.requestedItems[itemID] = nil end
    if success and self.relevantItems and self.relevantItems[itemID] then
        self:QueuePaperDollRefresh()
    end
end

function UI:OnStateChanged(_, state)
    if self.paperDoll and self.paperDoll:IsShown() then
        self:RenderPaperDoll(state)
    end
end

function UI:OnEnable()
    self:RegisterMessage("WSGS_STATE_CHANGED", "OnStateChanged")
    self:RegisterMessage("WSGS_ACTIONS_CHANGED", "QueuePaperDollRefresh")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_CHANGED", "UpdateEquipButton")
    self:RegisterMessage("WSGS_ITEM_DATA_RECEIVED")
end

function UI:TogglePaperDoll()
    if not self.paperDoll and InCombatLockdown() then
        WSGS:Print("Open the equipment view after combat.")
        return
    end
    local frame = self:CreatePaperDoll()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
