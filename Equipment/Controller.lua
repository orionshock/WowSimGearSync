local _, WSGS = ...
local Modules = WSGS.Private
local Actions = Modules.Equipment.Runtime
local verificationEvents = {
    PLAYER_EQUIPMENT_CHANGED = true,
    BAG_UPDATE_DELAYED = true,
    ITEM_LOCK_CHANGED = true
}

local function shown(value)
    if value == nil or value == "" then
        return "nil"
    end
    return tostring(value)
end

local function cursorState()
    local kind, id = GetCursorInfo()
    return kind and (shown(kind) .. ":" .. shown(id)) or "empty"
end

local function eventArguments(...)
    local values = {}
    for index = 1, select("#", ...) do
        values[index] = shown(select(index, ...))
    end
    return #values > 0 and table.concat(values, ",") or "none"
end

function Actions:PendingCount()
    return self.batch and self.batch:PendingCount() or 0
end

function Actions:Reconcile(state, snapshot, bags, combat, now, event)
    if self.batch then self.batch:Reconcile(snapshot, bags, now, event) end
    self.plan = Modules.Equipment.Planning:Plan(state)
    if self.batch and self:PendingCount() == 0 then
        local counts = self.batch:Counts()
        if counts.FAILED > 0 or counts.BLOCKED > 0 then
            self.fault = string.format("%d target slot(s) unresolved; %d failed, %d blocked.",
                self.plan.unresolvedCount, counts.FAILED, counts.BLOCKED)
        else
            self.fault = nil
        end
    end
    if self:PendingCount() > 0 then
        self.state = "PENDING"
    elseif combat then
        self.state = "COMBAT"
    elseif self.fault then
        self.state = "FAULT"
    elseif #self.plan.operations > 0 then
        self.state = "READY"
    elseif #self.plan.blocked > 0 or #self.plan.missing > 0 then
        self.state = "BLOCKED"
    else
        self.state = "COMPLETE"
    end
    return self.batch and self.batch:Counts() or nil
end

function Actions:UnresolvedSlots(state)
    local comparison = state.comparison
    local unresolved = {}
    if not comparison then
        return unresolved
    end
    for position, result in ipairs(comparison.slots) do
        if result.fields.item.state ~= "MATCH" then
            unresolved[#unresolved + 1] = WSGS.Equipment.Slots[position].id .. ":" .. result.fields.item.state
        end
    end
    return unresolved
end

function Actions:LogDone(state)
    if not self.batch or self.batch.summaryLogged or self:PendingCount() > 0 then
        return
    end
    local snapshot = {
        slots = state.equipped,
        context = state.context
    }
    self.batch.summaryLogged = true
    local counts, attempted = self.batch:Counts(), 0
    for _, record in ipairs(self.batch.records) do
        if record.attempted then
            attempted = attempted + 1
        end
        if not record.diagnosticLogged then
            local verified, reason = Modules.Equipment.Verification:Check(record.operation, snapshot, self.bags)
            self.batch:LogVerification(record, snapshot, verified,
                "classification=" .. record.status .. "; observed=" .. reason, "FINAL_RESCAN")
        end
    end
    local unresolved = self:UnresolvedSlots(state)
    WSGS:Debug(string.format(
        "[EQUIP][DONE] planned=%d attempted=%d verified=%d failed=%d blocked=%d pending=%d completed=%d actualUnresolved=%d slots=%s",
        self.batch.total, attempted, counts.VERIFIED, counts.FAILED, counts.BLOCKED, counts.STILL_PENDING,
        counts.VERIFIED + counts.FAILED + counts.BLOCKED, #unresolved,
        #unresolved > 0 and table.concat(unresolved, ",") or "none"))
    if not self.batch.setSyncAttempted and (not self.batch.selectedPosition or self.plan.unresolvedCount == 0) then
        self.batch.setSyncAttempted = true
        WSGS.EquipmentSets:SaveVerified(state, self.batch:Report())
    end
end

function Actions:Refresh(state)
    if not state then
        state = self:GetState(nil)
    end
    local snapshot = {
        slots = state.equipped,
        context = state.context
    }
    local bags = state.bags
    local before = self.batch and self.batch:Counts()
    local counts = self:Reconcile(state, snapshot, bags, InCombatLockdown() or UnitAffectingCombat("player"),
        GetTime(), self.verificationEvent)
    self.verificationEvent = nil
    self.snapshot, self.bags = snapshot, bags
    if self:PendingCount() == 0 and GetCursorInfo() and self.state ~= "COMBAT" and self.state ~= "FAULT" then
        self.state = "CURSOR"
    end
    if counts and before and counts.VERIFIED > before.VERIFIED then
        WSGS:Debug(string.format("[EQUIP][VERIFY] progress=%d/%d plannerUnresolved=%d", counts.VERIFIED,
            self.batch.total, self.plan.unresolvedCount))
    end
    self:LogDone(state)
    self:SendMessage("WSGS_EQUIPMENT_STATE_CHANGED")
    return self.plan
end

function Actions:QueueRefresh(event, ...)
    if verificationEvents[event] then
        self.verificationEvent = event
    end
    if self.refreshQueued then
        return
    end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        Modules.Reconcile()
    end)
end

function Actions:UI_ERROR_MESSAGE(event, ...)
    local active = self.batch and self:PendingCount() > 0
    if active then
        WSGS:Debug(string.format("[EQUIP][EVENT] name=%s args=%s", event, eventArguments(...)))
    end
    local _, message = ...
    if active then
        self.batch:OnError(type(message) == "string" and message or "Client rejected the operation.")
        self:QueueRefresh(event)
    end
end

function Actions:LogPlan(profile, plan)
    plan = plan or self.plan
    WSGS:Debug(string.format("[EQUIP][PLAN] click cursor=%s operations=%d unresolved=%d missing=%d blocked=%d",
        cursorState(), #plan.operations, plan.unresolvedCount, #plan.missing, #plan.blocked))
    local comparison = self.equipmentState and self.equipmentState.comparison
    local byTarget, missing = {}, {}
    for index, operation in ipairs(plan.operations) do
        byTarget[operation.targetPosition] = index
    end
    for _, item in ipairs(plan.missing) do
        missing[item.position] = item.id
    end
    for position, target in ipairs(profile.equipment) do
        local physical = comparison and comparison.assignments[position] or position
        local current = self.snapshot.slots[physical]
        local state = comparison and comparison.slots[position].fields.item.state or "UNKNOWN"
        local decision =
            byTarget[position] and ("operation:" .. byTarget[position]) or missing[position] and "missing" or state ==
                "MATCH" and "satisfied" or "excluded"
        local reason = byTarget[position] and "source selected" or missing[position] and "target instance not found" or
                           state == "MATCH" and "actual equipped item matches target" or (position == 15 or position == 16) and
                           "weapon operation excluded; see weapon decision and excluded reasons" or
                           "no safely executable source; see excluded reasons"
        WSGS:Debug(string.format(
            "[EQUIP][PLAN] pos=%d inv=%d name=%s physical=%d current=%s currentGUID=%s target=%s state=%s decision=%s reason=%s",
            position, WSGS.Equipment.Slots[position].id, WSGS.Equipment.Slots[position].name, physical,
            shown(current and current.id), shown(current and current.guid), shown(target and target.id), state,
            decision, reason))
    end
    for index, operation in ipairs(plan.operations) do
        local source = operation.source
        local sourceLocation = source.bag ~= nil and ("bag:" .. source.bag .. ":" .. source.bagSlot) or
                                   ("equipped:" .. shown(source.position))
        WSGS:Debug(string.format(
            "[EQUIP][PLAN] order=%d kind=%s targetPos=%d inv=%d item=%s GUID=%s source=%s equipLoc=%s API=%s", index,
            operation.kind, operation.targetPosition, operation.slotId, shown(operation.id), shown(source.guid),
            sourceLocation, shown(source.equipLoc), "cursor APIs"))
    end
    for _, item in ipairs(plan.missing) do
        WSGS:Debug(string.format(
            "[EQUIP][PLAN] excluded pos=%d inv=%d item=%s reason=not found in equipped gear or carried bags",
            item.position, WSGS.Equipment.Slots[item.position].id, shown(item.id)))
    end
    for _, reason in ipairs(plan.blocked) do
        WSGS:Debug("[EQUIP][PLAN] excluded reason=" .. reason)
    end
    local grip = self.snapshot.context and self.snapshot.context.titansGrip and "yes" or "no"
    for _, position in ipairs({15, 16}) do
        local target = profile.equipment[position]
        local current = self.snapshot.slots[position]
        local targetLoc = target and target.id and target.id > 0 and select(4, C_Item.GetItemInfoInstant(target.id))
        WSGS:Debug(string.format(
            "[EQUIP][PLAN] weapon=%s inv=%d current=%s currentType=%s target=%s targetType=%s titansGrip=%s operation=%s",
            position == 15 and "MH" or "OH", WSGS.Equipment.Slots[position].id, shown(current.id),
            shown(current.equipLoc), shown(target and target.id), shown(targetLoc), grip, shown(byTarget[position])))
    end
end

function Actions:Click(position)
    local reason = Modules.Availability:Reason()
    if reason then
        WSGS:Print("[EQUIP] " .. WSGS:FormatPlayerReason(reason))
        return
    end
    self.fault, self.batch = nil, nil
    local profile = WSGS.Builds:GetActive()
    local state = self:RefreshState(profile, position and "SlotEquipClick" or "GlobalEquipClick")
    self:Refresh(state)
    local operations, selectedPlan = self.plan.operations
    if position then
        local reason
        selectedPlan, reason = self:GetSlotEquipPlan(position, state)
        if not selectedPlan then
            WSGS:Print("[EQUIP] " .. WSGS:FormatPlayerReason(reason))
            self:SendMessage("WSGS_ACTIONS_CHANGED", "SLOT_EQUIP_RECHECK")
            return
        end
        operations = selectedPlan.operations
        WSGS:Debug(string.format("[EQUIP][PLAN] selected=%d operations=%d", position, #operations))
    end
    if profile then
        self:LogPlan(profile, selectedPlan)
    end
    if not position and self.state == "COMPLETE" then
        WSGS.EquipmentSets:SaveVerified(state)
        return
    end
    if not position and self.state ~= "READY" then
        WSGS:Print("[EQUIP] " .. WSGS:FormatPlayerReason(
            self.state == "COMBAT" and "Cannot equip in combat." or self.plan.blocked[1] or
                "No available equipment changes."))
        return
    end
    if GetCursorInfo() then
        WSGS:Print("[EQUIP] Place the held cursor item first.");
        return
    end
    local batch = Modules.Equipment.CreateBatch(operations, self.snapshot, GetTime())
    self.batch, self.state, self.fault = batch, "PENDING", nil
    batch.selectedPosition = position
    self:SendMessage("WSGS_EQUIPMENT_STATE_CHANGED")
    batch:Submit()
    for _, record in ipairs(batch.records) do
        if record.status == "FAILED" or record.status == "BLOCKED" then
            WSGS:Debug(string.format("[EQUIP][BLOCK] status=%s inv=%d reason=%s", record.status,
                record.operation.slotId, record.reason or "client rejection"))
        end
    end
    -- This immediate rescan only observes. Every protected action above ran in
    -- the original button callback.
    state = self:RefreshState(WSGS.Builds:GetActive(), "GlobalEquipImmediateVerify")
    self:Refresh(state)
    if position then
        self:SendMessage("WSGS_ACTIONS_CHANGED", "SLOT_EQUIP_SUBMITTED")
    end
    C_Timer.After(4, function()
        if self.batch == batch and self:PendingCount() > 0 then
            WSGS:Debug(string.format("[EQUIP][EVENT] name=VERIFY_TIMEOUT pending=%d", self:PendingCount()))
            self.verificationEvent = "FINAL"
            local finalState = self:RefreshState(WSGS.Builds:GetActive(), "GlobalEquipFinalVerify")
            self:Refresh(finalState)
        end
    end)
end

function Actions:GetStatus()
    local plan, batch = self.plan, self.batch
    local pendingSlots = {}
    for _, record in ipairs(batch and batch.records or {}) do
        if record.status == "STILL_PENDING" then pendingSlots[record.operation.targetPosition] = true end
    end
    return {
        state = self.state, fault = self.fault,
        counts = batch and batch:Counts() or nil,
        total = batch and batch.total or 0,
        unresolvedCount = plan and plan.unresolvedCount or 0,
        missingCount = plan and #plan.missing or 0,
        blocker = plan and plan.blocked[1], pendingSlots = pendingSlots
    }
end
