local _, WSGS = ...
local Equipment = WSGS:GetModule("Equipment")

-- Selected clicks use the ordinary planner and executor. Weapons remain a pair
-- because clearing/replacing the other hand can be required for a safe layout.
function Equipment:GetSlotEquipPlan(position, state)
    if self:PendingCount() > 0 then
        return nil, "Equipment changes are awaiting verification", "PENDING"
    end
    if WSGS.Actions.IsModificationPending() then
        return nil, "Finish the active modification first", "BLOCKED"
    end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        return nil, "Cannot equip in combat", "BLOCKED"
    end
    if GetCursorInfo() then
        return nil, "Place the held cursor item first", "BLOCKED"
    end
    if SpellIsTargeting() then
        return nil, "Finish or cancel the active item targeting first", "BLOCKED"
    end
    local slot = state and state.slots[position]
    local item = slot and slot.comparison and slot.comparison.fields.item
    if not item or item.state == "UNKNOWN" then
        return nil, "Equipped item identity is not available yet", "UNKNOWN"
    end
    if item.state == "MATCH" then
        return nil, "Target item is already equipped", "COMPLETE"
    end
    if slot.current.locked then
        return nil, "Equipped item is locked", "BLOCKED"
    end
    local plan = WSGS.EquipmentPlanner:Plan(state, position)
    local selected
    for _, operation in ipairs(plan.operations) do
        if operation.targetPosition == position then
            selected = operation
            break
        end
    end
    if selected then
        return plan, position >= 15 and "Click to equip the target weapon layout" or
            slot.target.empty and "Click to empty this slot" or "Click to equip the target item", "READY"
    end
    -- Classify the planner's rejected candidates using its existing capture.
    -- An unreadable occupied bag slot prevents a confirmed absence claim.
    local found, unlocked, unresolved = false, false, false
    for _, candidate in ipairs(state.bags.items) do
        if candidate.id == slot.target.id then
            found = true
            unlocked = unlocked or not candidate.locked
            unresolved = unresolved or not candidate.fingerprint or not candidate.equipLoc
        end
    end
    if found and not unlocked then
        return nil, "Target item is locked", "BLOCKED"
    end
    if unresolved or state.bags.unreadable > 0 then
        return nil, "Target item data is not available yet", "UNKNOWN"
    end
    for _, missing in ipairs(plan.missing) do
        if missing.position == position then
            return nil, "Target item not in your bags", "BLOCKED"
        end
    end
    local reason = plan.blocked[1] or "Target item cannot be safely assigned to this slot"
    -- The tooltip title supplies the name; avoid planner diagnostic item IDs.
    reason = reason:gsub("[Ii]tem %d+", "Target item")
    return nil, reason, "BLOCKED"
end
