local _, WSGS = ...
local Actions = WSGS:NewModule("Equipment", "AceEvent-3.0")
Actions.events = { "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE", "GET_ITEM_INFO_RECEIVED",
    "ITEM_DATA_LOAD_RESULT", "SPELLS_CHANGED", "CURSOR_CHANGED" }
WSGS.EquipmentActions = Actions
local verificationEvents = { PLAYER_EQUIPMENT_CHANGED=true, BAG_UPDATE_DELAYED=true, ITEM_LOCK_CHANGED=true }

local function shown(value)
    if value == nil or value == "" then return "nil" end
    return tostring(value)
end

local function cursorState()
    local kind, id = GetCursorInfo()
    return kind and (shown(kind) .. ":" .. shown(id)) or "empty"
end

local function eventArguments(...)
    local values = {}
    for index = 1, select("#", ...) do values[index] = shown(select(index, ...)) end
    return #values > 0 and table.concat(values, ",") or "none"
end

local function sourceAt(operation, snapshot, bags)
    local source = operation.source
    if source.bag == nil then return snapshot.slots[source.position] end
    for _, item in ipairs(bags.items) do
        if item.bag == source.bag and item.bagSlot == source.bagSlot then return item end
    end
end

function Actions:Verify(operation, snapshot, bags)
    local destination = snapshot.slots[operation.position]
    if operation.kind == "UNEQUIP" then
        if destination.observations.item.status ~= "KNOWN" then
            return false, "destination identity is unknown", destination
        end
        if destination.id then return false, "destination is not empty", destination end
        for _, item in ipairs(bags.items) do
            if item.bag == operation.destination.bag and item.bagSlot == operation.destination.bagSlot then
                if operation.source.guid then
                    return item.guid == operation.source.guid,
                        item.guid == operation.source.guid and "destination is empty and intended instance is in the planned bag slot"
                            or "planned bag slot contains a different instance", destination
                end
                return item.fingerprint == operation.source.fingerprint,
                    item.fingerprint == operation.source.fingerprint
                        and "destination is empty and intended fingerprint is in the planned bag slot"
                        or "planned bag slot contains a different fingerprint", destination
            end
        end
        return false, "planned bag destination is empty or unreadable", destination
    end
    if destination.id ~= operation.id then return false, "observed item ID does not match target", destination end
    if operation.source.guid then
        return destination.guid == operation.source.guid,
            destination.guid == operation.source.guid and "observed item ID and instance match target"
                or "observed item ID matches but instance GUID does not", destination
    end
    local oldSource = sourceAt(operation, snapshot, bags)
    if destination.fingerprint ~= operation.source.fingerprint then
        return false, "observed item ID matches but fingerprint does not", destination
    end
    if oldSource and oldSource.fingerprint == operation.source.fingerprint then
        return false, "matching fingerprint remains at the planned source", destination
    end
    return true, "observed item ID and fingerprint match and source moved", destination
end

function Actions:BeginBatch(operations, snapshot, now)
    local batch = { records = {}, deadline = now + 4, total = #operations }
    for index, operation in ipairs(operations) do
        batch.records[index] = { operation = operation, status = "STILL_PENDING", index = index,
            beforeId = snapshot.slots[operation.position].id,
            beforeGUID = snapshot.slots[operation.position].guid }
    end
    self.batch, self.state, self.fault = batch, "PENDING", nil
    return batch
end

function Actions:PendingCount()
    local count = 0
    for _, record in ipairs(self.batch and self.batch.records or {}) do
        if record.status == "STILL_PENDING" then count = count + 1 end
    end
    return count
end

function Actions:OutcomeCounts()
    local counts = { VERIFIED=0, FAILED=0, BLOCKED=0, STILL_PENDING=0 }
    for _, record in ipairs(self.batch and self.batch.records or {}) do
        counts[record.status] = counts[record.status] + 1
    end
    return counts
end

local function wrongDestination(record, snapshot)
    local operation = record.operation
    if operation.kind == "UNEQUIP" then return false end
    local destination = snapshot.slots[operation.position]
    if destination.id and destination.id ~= record.beforeId and destination.id ~= operation.id then return true end
    return operation.source.guid and destination.id == operation.id and destination.guid
        and destination.guid ~= operation.source.guid and destination.guid ~= record.beforeGUID
end

function Actions:LogVerification(record, snapshot, verified, reason, event)
    local operation = record.operation
    local observed = snapshot.slots[operation.position]
    local expected = operation.kind == "UNEQUIP" and "empty" or shown(operation.id)
    local instanceMatch = operation.source.guid and observed.guid == operation.source.guid
        and "yes" or operation.source.guid and "no" or "fingerprint"
    local weapon = operation.position == 15 and "MH" or operation.position == 16 and "OH" or "no"
    WSGS:Debug(string.format("[EQUIP][VERIFY] op=%d weapon=%s inv=%d intended=%s intendedGUID=%s observed=%s observedGUID=%s instanceMatch=%s event=%s decision=%s reason=%s",
        record.index, weapon, operation.slotId, expected, shown(operation.source.guid), shown(observed.id),
        shown(observed.guid), instanceMatch, shown(event), record.status, reason))
    record.diagnosticLogged = true
end

function Actions:Reconcile(profile, snapshot, bags, combat, now, event)
    local final = self.batch and (now >= self.batch.deadline or event == "FINAL")
    if self.batch then
        for _, record in ipairs(self.batch.records) do
            if record.status ~= "VERIFIED" and (verificationEvents[event] or final) then
                local verified, reason = self:Verify(record.operation, snapshot, bags)
                if verified then
                    record.status, record.reason = "VERIFIED", reason
                elseif record.status == "STILL_PENDING" then
                    if record.error then
                        record.status, record.reason = "FAILED", record.error
                    elseif verificationEvents[event] and wrongDestination(record, snapshot) then
                        record.status, record.reason = "FAILED", "A different item instance occupied the destination."
                    elseif final then
                        record.status, record.reason = "FAILED", "Equipment change could not be verified: " .. reason
                    else
                        record.reason = reason
                    end
                end
                self:LogVerification(record, snapshot, verified,
                    "classification=" .. record.status .. "; reason=" .. (record.reason or reason)
                        .. "; observed=" .. reason, event)
            elseif record.status == "STILL_PENDING" then
                if record.error then
                    record.status, record.reason = "FAILED", record.error
                end
            end
        end
        if self:PendingCount() == 0 then
            self.pending = nil
        end
    end
    self.plan = WSGS.EquipmentPlanner:Plan(profile, snapshot, bags)
    if self.batch and self:PendingCount() == 0 then
        local counts = self:OutcomeCounts()
        if counts.FAILED > 0 or counts.BLOCKED > 0 then
            self.fault = string.format("%d target slot(s) unresolved; %d failed, %d blocked.",
                self.plan.unresolvedCount, counts.FAILED, counts.BLOCKED)
        else self.fault = nil end
    end
    if self:PendingCount() > 0 then self.state = "PENDING"
    elseif combat then self.state = "COMBAT"
    elseif self.fault then self.state = "FAULT"
    elseif #self.plan.operations > 0 then self.state = "READY"
    elseif #self.plan.blocked > 0 or #self.plan.missing > 0 then self.state = "BLOCKED"
    else self.state = "COMPLETE" end
    return self.batch and self:OutcomeCounts() or nil
end

function Actions:ReadNow()
    local snapshot = WSGS.EquipmentScanner:Scan()
    local bags = WSGS.EquipmentInventory:Scan(snapshot)
    return snapshot, bags
end

function Actions:UnresolvedSlots(profile, snapshot)
    local comparison = WSGS.EquipmentComparator:Compare(profile, snapshot)
    local unresolved = {}
    if not comparison then return unresolved end
    for position, result in ipairs(comparison.slots) do
        if result.fields.item.state ~= "MATCH" then
            unresolved[#unresolved + 1] = WSGS.equipmentSlots[position].id .. ":" .. result.fields.item.state
        end
    end
    return unresolved
end

function Actions:LogDone(profile, snapshot)
    if not self.batch or self.batch.summaryLogged or self:PendingCount() > 0 then return end
    self.batch.summaryLogged = true
    local counts, attempted = self:OutcomeCounts(), 0
    for _, record in ipairs(self.batch.records) do
        if record.attempted then attempted = attempted + 1 end
        if not record.diagnosticLogged then
            local verified, reason = self:Verify(record.operation, snapshot, self.bags)
            self:LogVerification(record, snapshot, verified,
                "classification=" .. record.status .. "; observed=" .. reason, "FINAL_RESCAN")
        end
    end
    local unresolved = self:UnresolvedSlots(profile, snapshot)
    WSGS:Debug(string.format("[EQUIP][DONE] planned=%d attempted=%d verified=%d failed=%d blocked=%d pending=%d completed=%d actualUnresolved=%d slots=%s",
        self.batch.total, attempted, counts.VERIFIED, counts.FAILED, counts.BLOCKED, counts.STILL_PENDING,
        counts.VERIFIED + counts.FAILED + counts.BLOCKED, #unresolved,
        #unresolved > 0 and table.concat(unresolved, ",") or "none"))
    if not self.batch.setSyncAttempted then
        self.batch.setSyncAttempted = true
        WSGS.EquipmentSetSync:Synchronize(profile, snapshot, self.batch)
    end
end

function Actions:Refresh(profile, snapshot)
    local bags
    if snapshot then bags = WSGS.EquipmentInventory:Scan(snapshot)
    else snapshot, bags = self:ReadNow() end
    local before = self.batch and self:OutcomeCounts()
    local counts = self:Reconcile(profile, snapshot, bags,
        InCombatLockdown() or UnitAffectingCombat("player"), GetTime(), self.verificationEvent)
    self.verificationEvent = nil
    self.snapshot, self.bags = snapshot, bags
    if self:PendingCount() == 0 and GetCursorInfo() and self.state ~= "COMBAT" and self.state ~= "FAULT" then
        self.state = "CURSOR"
    end
    if counts and before and counts.VERIFIED > before.VERIFIED then
        WSGS:Debug(string.format("[EQUIP][VERIFY] progress=%d/%d plannerUnresolved=%d",
            counts.VERIFIED, self.batch.total, self.plan.unresolvedCount))
    end
    self:LogDone(profile, snapshot)
    self:SendMessage("WSGS_EQUIPMENT_STATE_CHANGED")
    return self.plan
end

function Actions:QueueRefresh(event)
    if verificationEvents[event] then self.verificationEvent = event end
    self:SendMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED", event)
    if self:PendingCount() == 0 then return end
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        if self:PendingCount() > 0 then self:Refresh(WSGS:GetActiveSimulationProfile()) end
    end)
end

function Actions:OnRuntimeEvent(event, ...)
    local active = self.batch and self:PendingCount() > 0
    if active and (verificationEvents[event] or event == "UI_ERROR_MESSAGE") then
        WSGS:Debug(string.format("[EQUIP][EVENT] name=%s args=%s", event, eventArguments(...)))
    end
    if event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        local record = self.executingRecord or self.lastSubmittedRecord
        if record and record.status == "STILL_PENDING" then
            record.error = type(message) == "string" and message or "Client rejected the operation."
            WSGS:Debug(string.format("[EQUIP][BLOCK] op=%d inv=%d reason=%s",
                record.index, record.operation.slotId, record.error))
            self:QueueRefresh(event)
        end
        return
    end
    self:QueueRefresh(event)
end

function Actions:OnEnable()
    for _, event in ipairs(self.events) do self:RegisterEvent(event, "OnRuntimeEvent") end
end

local function blockRemaining(batch, first, reason)
    for index = first, #batch.records do
        local record = batch.records[index]
        if record.status == "STILL_PENDING" then
            record.status, record.reason = "BLOCKED", reason
        end
    end
end

-- Runs only from Click. Every protected API call remains in the hardware event.
function Actions:SubmitBatch(batch)
    for index, record in ipairs(batch.records) do
        record.attempted = true
        self.executingRecord = record
        local ok, submitted, reason = pcall(WSGS.EquipmentExecution.Perform,
            WSGS.EquipmentExecution, record.operation, index, batch.total)
        self.executingRecord = nil
        if not ok then
            record.status, record.reason = "FAILED", tostring(submitted)
            WSGS:Debug(string.format("[EQUIP][BLOCK] op=%d inv=%d luaError=%s",
                index, record.operation.slotId, record.reason))
        elseif not submitted then
            record.status, record.reason = "BLOCKED", reason or "Client rejected the operation."
        elseif record.error then
            record.status, record.reason = "FAILED", record.error
        else
            record.submission = reason
            self.lastSubmittedRecord = record
        end
        if GetCursorInfo() then
            WSGS:Debug(string.format("[EQUIP][BLOCK] op=%d cursor=%s reason=item remains on cursor",
                index, cursorState()))
            blockRemaining(batch, index + 1, "An item remains on the cursor.")
            break
        end
    end
    self.executingRecord = nil
    return self:OutcomeCounts()
end

function Actions:LogPlan(profile)
    WSGS:Debug(string.format("[EQUIP][PLAN] click cursor=%s operations=%d unresolved=%d missing=%d blocked=%d",
        cursorState(), #self.plan.operations, self.plan.unresolvedCount, #self.plan.missing, #self.plan.blocked))
    local comparison = WSGS.EquipmentComparator:Compare(profile, self.snapshot)
    local byTarget, missing = {}, {}
    for index, operation in ipairs(self.plan.operations) do byTarget[operation.targetPosition] = index end
    for _, item in ipairs(self.plan.missing) do missing[item.position] = item.id end
    for position, target in ipairs(profile.equipment) do
        local physical = comparison and comparison.assignments[position] or position
        local current = self.snapshot.slots[physical]
        local state = comparison and comparison.slots[position].fields.item.state or "UNKNOWN"
        local decision = byTarget[position] and ("operation:" .. byTarget[position])
            or missing[position] and "missing" or state == "MATCH" and "satisfied" or "excluded"
        local reason = byTarget[position] and "source selected"
            or missing[position] and "target instance not found"
            or state == "MATCH" and "actual equipped item matches target"
            or position >= 15 and "weapon operation excluded; see weapon decision and excluded reasons"
            or "no safely executable source; see excluded reasons"
        WSGS:Debug(string.format("[EQUIP][PLAN] pos=%d inv=%d name=%s physical=%d current=%s currentGUID=%s target=%s state=%s decision=%s reason=%s",
            position, WSGS.equipmentSlots[position].id, WSGS.equipmentSlots[position].name, physical,
            shown(current and current.id), shown(current and current.guid), shown(target and target.id), state, decision, reason))
    end
    for index, operation in ipairs(self.plan.operations) do
        local source = operation.source
        local sourceLocation = source.bag ~= nil and ("bag:" .. source.bag .. ":" .. source.bagSlot)
            or ("equipped:" .. shown(source.position))
        WSGS:Debug(string.format("[EQUIP][PLAN] order=%d kind=%s targetPos=%d inv=%d item=%s GUID=%s source=%s equipLoc=%s API=%s",
            index, operation.kind, operation.targetPosition, operation.slotId, shown(operation.id), shown(source.guid),
            sourceLocation, shown(source.equipLoc), operation.direct and "C_Item.EquipItemByName" or "cursor APIs"))
    end
    for _, item in ipairs(self.plan.missing) do
        WSGS:Debug(string.format("[EQUIP][PLAN] excluded pos=%d inv=%d item=%s reason=not found in equipped gear or carried bags",
            item.position, WSGS.equipmentSlots[item.position].id, shown(item.id)))
    end
    for _, reason in ipairs(self.plan.blocked) do WSGS:Debug("[EQUIP][PLAN] excluded reason=" .. reason) end
    local grip = self.snapshot.context and self.snapshot.context.titansGrip and "yes" or "no"
    for _, position in ipairs({15, 16}) do
        local target = profile.equipment[position]
        local current = self.snapshot.slots[position]
        local targetLoc = target and target.id and target.id > 0 and select(4, C_Item.GetItemInfoInstant(target.id))
        WSGS:Debug(string.format("[EQUIP][PLAN] weapon=%s inv=%d current=%s currentType=%s target=%s targetType=%s titansGrip=%s operation=%s",
            position == 15 and "MH" or "OH", WSGS.equipmentSlots[position].id, shown(current.id),
            shown(current.equipLoc), shown(target and target.id), shown(targetLoc), grip, shown(byTarget[position])))
    end
end

function Actions:Click()
    -- A terminal batch may be retried; an overlapping pending batch may not.
    if self:PendingCount() > 0 then return end
    self.fault, self.batch, self.pending = nil, nil, nil
    local profile = WSGS:GetActiveSimulationProfile()
    self:Refresh(profile)
    if profile then self:LogPlan(profile) end
    if self.state == "COMPLETE" then
        WSGS.EquipmentSetSync:Synchronize(profile, self.snapshot)
        return
    end
    if self.state ~= "READY" then
        WSGS:Print("[EQUIP] " .. (self.state == "COMBAT" and "Cannot equip in combat." or self.plan.blocked[1] or "No available equipment changes."))
        return
    end
    if GetCursorInfo() then WSGS:Print("[EQUIP] Place the held cursor item first."); return end
    local batch = self:BeginBatch(self.plan.operations, self.snapshot, GetTime())
    self:SendMessage("WSGS_EQUIPMENT_STATE_CHANGED")
    self:SubmitBatch(batch)
    for _, record in ipairs(batch.records) do
        if record.status == "FAILED" or record.status == "BLOCKED" then
            WSGS:Debug(string.format("[EQUIP][BLOCK] status=%s inv=%d reason=%s",
                record.status, record.operation.slotId, record.reason or "client rejection"))
        end
    end
    -- This immediate rescan only observes. Every protected action above ran in
    -- the original button callback.
    self:Refresh(WSGS:GetActiveSimulationProfile())
    C_Timer.After(4, function()
        if self.batch == batch and self:PendingCount() > 0 then
            WSGS:Debug(string.format("[EQUIP][EVENT] name=VERIFY_TIMEOUT pending=%d", self:PendingCount()))
            self.verificationEvent = "FINAL"
            self:Refresh(WSGS:GetActiveSimulationProfile())
        end
    end)
end
