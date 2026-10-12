local _, WSGS = ...
local Planner = {}
WSGS.SlotActionPlanner = Planner

local function targetGuid(current)
    local observed = current and current.observations and current.observations.instance
    return observed and observed.status == "KNOWN" and observed.value or nil
end

local function classify(controller, operation, prepared, reason, retryable)
    operation.reason = reason
    if prepared then
        controller.operations[#controller.operations + 1] = prepared
    elseif retryable then
        controller.unknown[#controller.unknown + 1] = operation
    else
        controller.blocked[#controller.blocked + 1] = operation
    end
end

function Planner:Build(position, profile, snapshot, comparison, bags)
    local target, difference = profile.equipment[position], comparison.slots[position]
    local current = snapshot.slots[difference.currentPosition]
    local controller = {
        position = position,
        inventorySlot = difference.currentSlotId,
        currentPosition = difference.currentPosition,
        target = target,
        difference = difference,
        targetGuid = targetGuid(current),
        operations = {},
        blocked = {},
        unknown = {}
    }
    if difference.fields.item.state ~= "MATCH" then
        controller.state = "WAITING_FOR_ITEM"
        controller.reason = difference.fields.item.reason or "Equip the target item first"
        return controller
    end
    if target.empty or not target.id or target.id == 0 then
        controller.state = "COMPLETE"
        return controller
    end
    local modificationsRemain = false
    for _, field in ipairs({"professionSocket", "buckle", "gems", "enchant", "tinker"}) do
        local observed = difference.fields[field]
        if observed and (observed.state == "MISMATCH" or observed.state == "UNKNOWN") then
            modificationsRemain = true
        end
    end
    if not modificationsRemain then
        controller.state = "COMPLETE"
        return controller
    end
    if not controller.targetGuid then
        controller.state, controller.reason = "UNKNOWN", "Equipped item instance is not available yet"
        return controller
    end

    local context = {
        position = position,
        inventorySlot = controller.inventorySlot,
        target = target,
        fields = difference.fields,
        bags = bags,
        controller = controller
    }
    local professionSocket = difference.fields.professionSocket
    local buckle = difference.fields.buckle
    context.additionalSocketMissing = professionSocket and professionSocket.state == "MISMATCH" or
                                          buckle and buckle.state == "MISMATCH"
    context.availableSocketCount = professionSocket and professionSocket.actual or buckle and buckle.actual
    for _, handlerName in ipairs(WSGS.SlotActionHandlers:ForSlot(controller.inventorySlot)) do
        local handler = WSGS.SlotActionHandlers.handlers[handlerName]
        for _, operation in ipairs(handler:Check(context)) do
            local prepared, reason, retryable = handler:Prepare(context, operation)
            classify(controller, operation, prepared, reason, retryable)
        end
    end

    controller.prepared = controller.operations[1]
    if controller.prepared then
        controller.state = "READY"
    elseif #controller.unknown > 0 then
        controller.state, controller.reason = "UNKNOWN", controller.unknown[1].reason
    elseif #controller.blocked > 0 then
        controller.state, controller.reason = "BLOCKED", controller.blocked[1].reason
    else
        controller.state = "COMPLETE"
    end
    return controller
end
