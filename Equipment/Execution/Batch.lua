local _, WSGS = ...
local Modules = WSGS.Private
local verificationEvents = {PLAYER_EQUIPMENT_CHANGED = true, BAG_UPDATE_DELAYED = true, ITEM_LOCK_CHANGED = true}
local function shown(value) return value == nil and "nil" or tostring(value) end
local function cursorState()
    local kind, id = GetCursorInfo()
    return kind and (shown(kind) .. ":" .. shown(id)) or "empty"
end
local Batch = {}
Batch.__index = Batch
function Modules.Equipment.CreateBatch(operations, snapshot, now)
    local self = setmetatable({records = {}, deadline = now + 4, total = #operations}, Batch)
    for index, operation in ipairs(operations) do
        self.records[index] = {
            operation = operation, status = "STILL_PENDING", index = index,
            beforeId = snapshot.slots[operation.position].id,
            beforeGUID = snapshot.slots[operation.position].guid
        }
    end
    return self
end
function Batch:PendingCount()
    local count = 0
    for _, record in ipairs(self.records) do
        if record.status == "STILL_PENDING" then
            count = count + 1
        end
    end
    return count
end

function Batch:Counts()
    local counts = {
        VERIFIED = 0,
        FAILED = 0,
        BLOCKED = 0,
        STILL_PENDING = 0
    }
    for _, record in ipairs(self.records) do
        counts[record.status] = counts[record.status] + 1
    end
    return counts
end

function Batch:LogVerification(record, snapshot, verified, reason, event)
    local operation = record.operation
    local observed = snapshot.slots[operation.position]
    local expected = operation.kind == "UNEQUIP" and "empty" or shown(operation.id)
    local instanceMatch = observed.guid == operation.source.guid and "yes" or "no"
    local weapon = operation.position == 15 and "MH" or operation.position == 16 and "OH" or "no"
    WSGS:Debug(string.format(
        "[EQUIP][VERIFY] op=%d weapon=%s inv=%d intended=%s intendedGUID=%s observed=%s observedGUID=%s instanceMatch=%s event=%s decision=%s reason=%s",
        record.index, weapon, operation.slotId, expected, shown(operation.source.guid), shown(observed.id),
        shown(observed.guid), instanceMatch, shown(event), record.status, reason))
    record.diagnosticLogged = true
end

function Batch:Reconcile(snapshot, bags, now, event)
    local final = (now >= self.deadline or event == "FINAL")
    if self then
        for _, record in ipairs(self.records) do
            if record.status ~= "VERIFIED" and (verificationEvents[event] or final) then
                local verified, reason = Modules.Equipment.Verification:Check(record.operation, snapshot, bags)
                if verified then
                    record.status, record.reason = "VERIFIED", reason
                elseif record.status == "STILL_PENDING" then
                    if record.error then
                        record.status, record.reason = "FAILED", record.error
                    elseif verificationEvents[event] and Modules.Equipment.Verification:UnexpectedDestination(record, snapshot) then
                        record.status, record.reason = "FAILED", "A different item instance occupied the destination."
                    elseif final then
                        record.status, record.reason = "FAILED", "Equipment change could not be verified: " .. reason
                    else
                        record.reason = reason
                    end
                end
                self:LogVerification(record, snapshot, verified, "classification=" .. record.status .. "; reason=" ..
                    (record.reason or reason) .. "; observed=" .. reason, event)
            elseif record.status == "STILL_PENDING" then
                if record.error then
                    record.status, record.reason = "FAILED", record.error
                end
            end
        end
    end
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
function Batch:Submit()
    local batch = self
    for index, record in ipairs(batch.records) do
        record.attempted = true
        self.executingRecord = record
        local ok, submitted, reason = pcall(Modules.Equipment.InventoryActions.Perform, Modules.Equipment.InventoryActions, record.operation,
            index, batch.total)
        self.executingRecord = nil
        if not ok then
            record.status, record.reason = "FAILED", tostring(submitted)
            WSGS:Debug(string.format("[EQUIP][BLOCK] op=%d inv=%d luaError=%s", index, record.operation.slotId,
                record.reason))
        elseif not submitted then
            record.status, record.reason = "BLOCKED", reason or "Client rejected the operation."
        elseif record.error then
            record.status, record.reason = "FAILED", record.error
        else
            record.submission = reason
            self.lastSubmittedRecord = record
        end
        if GetCursorInfo() then
            WSGS:Debug(string.format("[EQUIP][BLOCK] op=%d cursor=%s reason=item remains on cursor", index,
                cursorState()))
            blockRemaining(batch, index + 1, "An item remains on the cursor.")
            break
        end
    end
    self.executingRecord = nil
    return self:Counts()
end


function Batch:OnError(message)
    local record = self.executingRecord or self.lastSubmittedRecord
    if record and record.status == "STILL_PENDING" then record.error = message end
end
