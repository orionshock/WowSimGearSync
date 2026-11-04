local _, WSGS = ...
local Modules = WSGS.Private
local Character = WSGS:NewModule("Character", "AceEvent-3.0")
Modules.Character.Runtime = Character
local observationEvents = {
    "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
    "SPELLS_CHANGED", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED"
}

-- Captures facts only. Imported targets and operation lifecycles belong to
-- their consumers. Every consumer shares the same capture until invalidated.
function Character:Refresh(reason)
    local snapshot = Modules.Character.EquippedItems:Scan()
    snapshot.bags = Modules.Character.CarriedItems:Scan()
    snapshot.materials = snapshot.bags.materials
    self.snapshot = snapshot
    self.invalid = false
    WSGS:Debug(string.format("[CHARACTER][CAPTURE] reason=%s bags=%d unreadable=%d",
        tostring(reason), #snapshot.bags.items, snapshot.bags.unreadable))
    return snapshot
end

function Character:GetSnapshot()
    if self.invalid or not self.snapshot then
        return self:Refresh("INVALIDATED")
    end
    return self.snapshot
end

function Character:Invalidate(event, ...)
    self.invalid = true
    self:SendMessage("WSGS_CHARACTER_INVALIDATED", event, ...)
end

function Character:WSGS_ITEM_DATA_RECEIVED(_, itemID, success)
    if success then
        self:Invalidate("ITEM_DATA_LOAD_RESULT", itemID, success)
    end
end

function Character:OnEnable()
    self.invalid = true
    for _, event in ipairs(observationEvents) do
        self:RegisterEvent(event, "Invalidate")
    end
    self:RegisterMessage("WSGS_ITEM_DATA_RECEIVED")
end
