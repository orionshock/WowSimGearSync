local _, WSGS = ...
local Modules = WSGS.Private
local function debug(category, text)
    WSGS:Debug("[ACTION][" .. category .. "] " .. text)
end
local function valueText(value)
    return value == nil and "nil" or tostring(value)
end
local function sameOperation(left, right)
    return left and right and left.handlerName == right.handlerName and left.type == right.type and
               left.field == right.field and left.expected == right.expected
end


-- The callbacks preserve ownership: timers can request a new observation, but
-- never submit another protected action.
function Modules.Enhancements.CreatePendingApplication(context)
    local Pending = {serial = 0}
function Pending:Carry(previous, built, difference)
    if not previous then
        return built
    end
    if previous.pending then
        local sameInstance = previous.targetGuid == built.targetGuid
        local satisfied, detail, actual = Modules.Enhancements.Verification:Check(previous.pending, difference, sameInstance)
        if sameInstance and satisfied then
            debug("VERIFY", string.format(
                "slot=%d serial=%d handler=%s type=%s expected=%s actual=%s guid=%s result=VERIFIED",
                previous.inventorySlot, previous.serial, previous.pending.handlerName, previous.pending.type,
                valueText(previous.pending.expected), valueText(actual), valueText(previous.targetGuid)))
            debug("DONE", string.format("slot=%d serial=%d type=%s next=%s", previous.inventorySlot,
                previous.serial, previous.pending.type, built.prepared and built.prepared.type or "none"))
        elseif previous.failure or not sameInstance then
            built.state = "BLOCKED"
            built.reason = previous.failure or "Target item instance changed before verification"
            built.lastFailed = previous.pending
            debug("VERIFY", string.format("slot=%d handler=%s type=%s expected=%s result=FAILED reason=%s",
                previous.inventorySlot, previous.pending.handlerName, previous.pending.type,
                valueText(previous.pending.expected), built.reason))
        else
            built.state = "PENDING"
            built.pending = previous.pending
            built.startedAt = previous.startedAt
            built.serial = previous.serial
            built.timeoutScheduled = previous.timeoutScheduled
            built.lastVerificationDetail = detail
            built.reason = "Awaiting client verification: " .. detail
            if previous.lastVerificationDetail ~= detail then
                debug("VERIFY", string.format(
                    "slot=%d serial=%d handler=%s type=%s expected=%s actual=%s guid=%s result=STILL_PENDING reason=%s",
                    previous.inventorySlot, previous.serial, previous.pending.handlerName, previous.pending.type,
                    valueText(previous.pending.expected), valueText(actual), valueText(previous.targetGuid), detail))
            end
        end
    elseif previous.lastFailed and built.prepared and
        (previous.failureScope ~= "OPERATION" or sameOperation(previous.lastFailed, built.prepared)) then
        built.state = "BLOCKED"
        built.lastFailed = previous.lastFailed
        built.failureScope = previous.failureScope
        built.reason = previous.reason
    elseif previous.lastFailed and built.prepared then
        debug("PLAN", string.format("slot=%d failed=%s fallback=%s decision=use-next-ready", built.inventorySlot,
            previous.lastFailed.type, built.prepared.type))
    end
    return built
end

function Pending:Schedule(controller)
    if controller.timeoutScheduled then
        return
    end
    controller.timeoutScheduled = true
    local pendingSerial = controller.serial
    C_Timer.After(8, function()
        context.synchronizeBuild()
        local current = context.controllerAt(controller.position)
        if not current or current.state ~= "PENDING" or current.serial ~= pendingSerial then
            return
        end
        debug("EVENT", string.format("slot=%d event=VERIFICATION_TIMEOUT serial=%d phase=rescan",
            current.inventorySlot, pendingSerial))
        context.refresh("VERIFICATION_TIMEOUT_RESCAN")
        C_Timer.After(0, function()
            context.synchronizeBuild()
            current = context.controllerAt(controller.position)
            if not current or current.state ~= "PENDING" or current.serial ~= pendingSerial then
                return
            end
            context.refresh("VERIFICATION_TIMEOUT_FINAL_RESCAN")
            current = context.controllerAt(controller.position)
            if current and current.state == "PENDING" and current.serial == pendingSerial then
                self:Fail(current, current.pending, "Timed out without a verified item-state change")
            end
        end)
    end)
end

function Pending:MarkPending(controller, operation)
    self.serial = self.serial + 1
    controller.state = "PENDING"
    controller.pending = operation
    controller.submitting = nil
    controller.startedAt = GetTime()
    controller.serial = self.serial
    debug("EXEC", string.format("slot=%d type=%s submitted serial=%d; awaiting events", controller.inventorySlot,
        operation.type, controller.serial))
    self:Schedule(controller)
end

function Pending:Fail(controller, operation, reason, scope)
    controller.state = "BLOCKED"
    controller.reason = reason
    controller.lastFailed = operation
    controller.failureScope = scope or "SLOT"
    controller.pending = nil
    controller.submitting = nil
    debug("BLOCK", string.format("slot=%d type=%s scope=%s reason=%s", controller.inventorySlot, operation.type,
        controller.failureScope, reason))
    context.changed("FAILED")
end

function Pending:MarkUnknown(controller, operation, reason)
    operation.reason = reason
    controller.state = "UNKNOWN"
    controller.reason = reason
    controller.prepared = nil
    controller.pending = nil
    controller.submitting = nil
    controller.lastFailed = nil
    controller.unknown = {operation}
    debug("PLAN", string.format("slot=%d handler=%s result=UNKNOWN reason=%s", controller.inventorySlot,
        operation.handlerName, reason))
    context.changed("UNRESOLVED")
end
    return Pending
end
