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
function WSGS.Character:Refresh(reason)
    local snapshot = Modules.Character.EquippedItems:Scan()
    snapshot.bags = Modules.Character.CarriedItems:Scan()
    snapshot.materials = snapshot.bags.materials
    Character.snapshot = snapshot
    Character.invalid = false
    WSGS:Debug(string.format("[CHARACTER][CAPTURE] reason=%s bags=%d unreadable=%d",
        tostring(reason), #snapshot.bags.items, snapshot.bags.unreadable))
    return snapshot
end

function WSGS.Character:GetSnapshot()
    if Character.invalid or not Character.snapshot then
        return WSGS.Character:Refresh("INVALIDATED")
    end
    return Character.snapshot
end

function WSGS.Character:Invalidate(event, ...)
    Character.invalid = true
    Character:SendMessage("WSGS_CHARACTER_INVALIDATED", event, ...)
end

function Character:WSGS_ITEM_DATA_RECEIVED(_, itemID, success)
    if success then
        WSGS.Character:Invalidate("ITEM_DATA_LOAD_RESULT", itemID, success)
    end
end

function Character:OnEnable()
    self.invalid = true
    for _, event in ipairs(observationEvents) do
        self:RegisterEvent(event, WSGS.Character.Invalidate, WSGS.Character)
    end
    self:RegisterMessage("WSGS_ITEM_DATA_RECEIVED")
end
