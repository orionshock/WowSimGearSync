local _, WSGS = ...
local Actions = { events = { "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE", "GET_ITEM_INFO_RECEIVED",
    "ITEM_DATA_LOAD_RESULT", "SPELLS_CHANGED", "CURSOR_CHANGED" } }
WSGS.EquipmentActions = Actions
local verificationEvents = { PLAYER_EQUIPMENT_CHANGED=true, BAG_UPDATE_DELAYED=true, ITEM_LOCK_CHANGED=true }

function Actions:New()
    return setmetatable({}, { __index = self })
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
        if destination.observations.item.status ~= "KNOWN" or destination.id then return false end
        for _, item in ipairs(bags.items) do
            if item.bag == operation.destination.bag and item.bagSlot == operation.destination.bagSlot then
                if operation.source.guid then return item.guid == operation.source.guid end
                return item.fingerprint == operation.source.fingerprint
            end
        end
        return false
    end
    if destination.id ~= operation.id then return false end
    if operation.source.guid then return destination.guid == operation.source.guid end
    local oldSource = sourceAt(operation, snapshot, bags)
    return destination.fingerprint == operation.source.fingerprint
        and (not oldSource or oldSource.fingerprint ~= operation.source.fingerprint)
end

function Actions:BeginBatch(operations, snapshot, now)
    local batch = { records = {}, deadline = now + 4, total = #operations }
    for index, operation in ipairs(operations) do
        batch.records[index] = { operation = operation, status = "STILL_PENDING",
            beforeId = snapshot.slots[operation.position].id,
            beforeGUID = snapshot.slots[operation.position].guid }
    end
    self.batch, self.state, self.fault = batch, "PENDING", nil
    return batch
end

-- Retained as a narrow test seam for a one-operation batch.
function Actions:Begin(operation, snapshot, now)
    local batch = self:BeginBatch({ operation }, snapshot, now)
    self.pending = batch.records[1]
    return self.pending
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

-- Pure state transition used by live events and deterministic in-game tests.
-- No equipment APIs, character DB writes, callbacks, or actions are issued here.
function Actions:Reconcile(profile, snapshot, bags, combat, now, event)
    local final = self.batch and (now >= self.batch.deadline or event == "FINAL")
    if self.batch then
        for _, record in ipairs(self.batch.records) do
            if record.status ~= "VERIFIED" and (verificationEvents[event] or final)
                and self:Verify(record.operation, snapshot, bags) then
                record.status, record.reason = "VERIFIED", nil
            elseif record.status == "STILL_PENDING" then
                if record.error then
                    record.status, record.reason = "FAILED", record.error
                elseif verificationEvents[event] and wrongDestination(record, snapshot) then
                    record.status, record.reason = "FAILED", "A different item instance occupied the destination."
                elseif final then
                    record.status, record.reason = "FAILED", "Equipment change could not be verified."
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
        WSGS:Debug(string.format("[EQUIP] Verified: %d/%d; unresolved targets: %d",
            counts.VERIFIED, self.batch.total, self.plan.unresolvedCount))
    end
    if self.stateChanged then self.stateChanged() end
    return self.plan
end

function Actions:QueueRefresh(event)
    if verificationEvents[event] then self.verificationEvent = event end
    if self.isVisible and self.isVisible() and self.queueViewRefresh then
        self.queueViewRefresh()
        return
    end
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        if self.isVisible and self.isVisible() then self.refreshView()
        elseif self:PendingCount() > 0 then self:Refresh(WSGS:GetActiveSimulationProfile()) end
    end)
end

function Actions:Initialize()
    local listener = CreateFrame("Frame")
    self.listener = listener
    for _, event in ipairs(self.events) do listener:RegisterEvent(event) end
    listener:SetScript("OnEvent", function(_, event, _, message)
        if event == "UI_ERROR_MESSAGE" then
            local record = self.executingRecord or self.lastSubmittedRecord
            if record and record.status == "STILL_PENDING" then
                record.error = type(message) == "string" and message or "Client rejected the operation."
                self:QueueRefresh(event)
            end
            return
        end
        if self:PendingCount() > 0 or self.isVisible and self.isVisible() then self:QueueRefresh(event) end
    end)
end

local function blockRemaining(batch, first, reason)
    for index = first, #batch.records do
        local record = batch.records[index]
        if record.status == "STILL_PENDING" then
            record.status, record.reason = "BLOCKED", reason
        end
    end
end

-- Runs only from Click in production. Tests inject a non-equipping performer.
function Actions:SubmitBatch(batch, perform, cursorOccupied)
    cursorOccupied = cursorOccupied or GetCursorInfo
    for index, record in ipairs(batch.records) do
        self.executingRecord = record
        local ok, submitted, reason = pcall(perform, record.operation)
        self.executingRecord = nil
        if not ok then
            record.status, record.reason = "FAILED", tostring(submitted)
        elseif not submitted then
            record.status, record.reason = "BLOCKED", reason or "Client rejected the operation."
        elseif record.error then
            record.status, record.reason = "FAILED", record.error
        else
            record.submission = reason
            self.lastSubmittedRecord = record
        end
        if cursorOccupied() then
            blockRemaining(batch, index + 1, "An item remains on the cursor.")
            break
        end
    end
    self.executingRecord = nil
    return self:OutcomeCounts()
end

function Actions:Click()
    -- A terminal batch may be retried; an overlapping pending batch may not.
    if self:PendingCount() > 0 then return end
    self.fault, self.batch, self.pending = nil, nil, nil
    self:Refresh(WSGS:GetActiveSimulationProfile())
    if self.state ~= "READY" then
        WSGS:Print("[EQUIP] " .. (self.state == "COMBAT" and "Cannot equip in combat." or self.plan.blocked[1] or "No available equipment changes."))
        return
    end
    if GetCursorInfo() then WSGS:Print("[EQUIP] Place the held cursor item first."); return end
    for _, missing in ipairs(self.plan.missing) do
        WSGS:Debug("[EQUIP] Missing: item " .. missing.id .. " for " .. WSGS.equipmentSlots[missing.position].name)
    end
    local batch = self:BeginBatch(self.plan.operations, self.snapshot, GetTime())
    WSGS:Debug("[EQUIP] Attempting batch: " .. batch.total .. " operations")
    if self.stateChanged then self.stateChanged() end
    self:SubmitBatch(batch, function(operation)
        return WSGS.EquipmentExecution:Perform(operation)
    end)
    -- This immediate rescan only observes. Every protected action above ran in
    -- the original button callback.
    self:Refresh(WSGS:GetActiveSimulationProfile())
    C_Timer.After(4, function()
        if self.batch == batch and self:PendingCount() > 0 then
            self.verificationEvent = "FINAL"
            if self.isVisible and self.isVisible() then self.refreshView()
            else self:Refresh(WSGS:GetActiveSimulationProfile()) end
        end
    end)
end
