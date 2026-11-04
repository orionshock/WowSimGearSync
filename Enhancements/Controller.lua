local _, WSGS = ...
local Modules = WSGS.Private
local Controller = WSGS:NewModule("Enhancements", "AceEvent-3.0")
local Equipment = WSGS.Equipment
Modules.Enhancements.Runtime = Controller

local Internal = Modules.Enhancements
local controllers, buttons, planSignatures = {}, {}, {}
local controllerBuild
local Pending

local function debug(category, text)
    WSGS:Debug("[ACTION][" .. category .. "] " .. text)
end

local function valueText(value)
    return value == nil and "nil" or tostring(value)
end

local function selectedOperation(controller)
    return controller and (controller.prepared or controller.pending or controller.lastFailed or controller.unknown[1] or
               controller.blocked[1])
end

local function configureButton(position)
    Internal.SecureItemUse:Configure(buttons[position], controllers[position])
end

local function synchronizeBuild()
    local build = WSGS.Builds:GetActive()
    if controllerBuild == build then
        return false
    end
    local previousBuild = controllerBuild
    for _, controller in pairs(controllers) do
        local operation = controller.pending or controller.submitting
        if operation then
            debug("CANCEL", string.format(
                "build=%s nextBuild=%s slot=%d serial=%s type=%s expected=%s guid=%s reason=build-replaced verification-only",
                valueText(previousBuild and previousBuild.name), valueText(build and build.name),
                controller.inventorySlot, valueText(controller.serial), operation.type,
                valueText(operation.expected), valueText(controller.targetGuid)))
        end
    end
    -- A new table also identifies a reimport of the same specialization. Do not
    -- cancel any client cast/cursor; discard only our old verification records.
    controllers, planSignatures = {}, {}
    controllerBuild = build
    for position, button in pairs(buttons) do
        button.wsgsSubmission = nil
        configureButton(position)
    end
    if previousBuild then
        Controller:SendMessage("WSGS_ACTIONS_CHANGED", "BUILD_REPLACED")
    end
    return true
end

local function controllerSignature(controller)
    local operation = selectedOperation(controller)
    return table.concat({valueText(controller.inventorySlot), controller.state, operation and operation.type or "none",
                         operation and valueText(operation.expected) or "nil", valueText(controller.targetGuid),
                         controller.reason or operation and operation.reason or "none",
                         valueText(operation and operation.material and operation.material.bag),
                         valueText(operation and operation.material and operation.material.bagSlot)}, ":"), operation
end

local function logPlan(position, controller)
    local signature, operation = controllerSignature(controller)
    local changed = planSignatures[position] ~= signature
    planSignatures[position] = signature
    if not changed then
        return
    end
    debug("PLAN", string.format("slot=%d actualSlot=%d state=%s handler=%s next=%s expected=%s guid=%s reason=%s",
        WSGS.Equipment.Slots[position].id, controller.inventorySlot, controller.state,
        operation and operation.handlerName or "none", operation and operation.type or "none",
        operation and valueText(operation.expected) or "nil", valueText(controller.targetGuid),
        controller.reason or operation and operation.reason or "none"))
    if controller.state == "READY" then
        local prepared = controller.prepared
        debug("READY", string.format(
            "slot=%d handler=%s type=%s material=%s materialGuid=%s profession=%s recipe=%s spellName=%s effect=%s guid=%s",
            controller.inventorySlot, prepared.handlerName, prepared.type, valueText(prepared.materialItemID),
            valueText(prepared.material and prepared.material.guid), valueText(prepared.professionName),
            valueText(prepared.spellID), valueText(prepared.spellName),
            valueText(prepared.expected), valueText(controller.targetGuid)))
        return
    end
    if controller.state == "BLOCKED" then
        for _, blocked in ipairs(controller.blocked) do
            debug("BLOCK", string.format("slot=%d handler=%s type=%s profession=%s recipe=%s expected=%s reason=%s",
                controller.inventorySlot, blocked.handlerName, blocked.type,
                valueText(blocked.professionName or blocked.professionSkillLine), valueText(blocked.spellID),
                valueText(blocked.expected), blocked.reason or "unavailable"))
        end
        if #controller.blocked == 0 then
            debug("BLOCK", string.format("slot=%d reason=%s", controller.inventorySlot,
                controller.reason or "unavailable"))
        end
        return
    end
    if controller.state == "UNKNOWN" then
        debug("PLAN", string.format("slot=%d handler=%s result=UNKNOWN reason=%s", controller.inventorySlot,
            operation and operation.handlerName or "none", controller.reason or "incomplete client data"))
    end
end

local function rebuildController(position, state)
    local previous = controllers[position]
    local built = Internal.Planner:Build(position, state)
    built = Pending:Carry(previous, built, state.comparison.slots[position])
    controllers[position] = built
    logPlan(position, built)
    configureButton(position)
end

function Controller:Refresh(state)
    synchronizeBuild()
    if not state or not state.build or not state.comparison or not controllerBuild or
        state.target ~= controllerBuild.equipment then
        controllers = {}
        for position in pairs(buttons) do
            configureButton(position)
        end
        return
    end
    for position = 1, #WSGS.Equipment.Slots do
        rebuildController(position, state)
    end
end

function WSGS.Enhancements:GetSlotState(position)
    local controller = controllers[position]
    return Internal.Presentation:Build(controller, selectedOperation(controller))
end

local function refreshFromClient(self, reason)
    local profile = WSGS.Builds:GetActive()
    if not profile then
        return
    end
    local state = Equipment:GetState("SlotActions:" .. tostring(reason))
    if state.comparison then
        self:Refresh(state)
    end
    self:SendMessage("WSGS_ACTIONS_CHANGED", reason)
end

local function submitProfession(self, controller, request, button)
    local operation = request.operation
    controller.submitting = operation
    button.wsgsSubmission = {
        position = controller.position,
        operation = operation
    }
    debug("EXEC", string.format("slot=%d handler=%s api=native-click profession=%s recipe=%s effect=%s",
        controller.inventorySlot, operation.handlerName, valueText(operation.professionName),
        valueText(operation.spellID), valueText(operation.expected)))
    local result = Internal.ProfessionExecution:Submit(request)
    if result and result.status == "UNRESOLVED" then
        button.wsgsSubmission = nil
        Pending:MarkUnknown(controller, operation, result.reason)
        return false
    end
    if not result or result.status ~= "SUBMITTED" then
        button.wsgsSubmission = nil
        Pending:Fail(controller, operation, result and result.reason or "Profession execution returned no result",
            "OPERATION")
        return false
    end
    operation.spellID = result.spellID
    operation.spellName = result.spellName
    operation.professionName = result.professionName
    operation.executionToken = result
    return true
end

local function submitItem(self, controller, request, button)
    local ok, reason = Internal.SecureItemUse:Prepare(controller, request.operation, button)
    if not ok then
        Pending:Fail(controller, request.operation, reason, "OPERATION")
        return false
    end
    controller.submitting = request.operation
    button.wsgsSubmission = {position = controller.position, operation = request.operation}
    return true
end

local function submitRequest(self, controller, request, button)
    if request.method == "PROFESSION" then
        return submitProfession(self, controller, request, button)
    end
    if request.method == "ITEM" then
        return submitItem(self, controller, request, button)
    end
    Pending:Fail(controller, request.operation, "Prepared action has no supported execution method")
    return false
end

local function validateClick(controller, operation, position)
    local reason = Modules.Availability:Reason()
    if reason then return reason end
    local id = GetInventoryItemID("player", controller.inventorySlot)
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromEquipmentSlot(controller.inventorySlot))
    if id ~= controller.target.id or not ok or guid ~= controller.targetGuid then
        return "The equipped target item or instance changed; rescan before retrying"
    end
    if IsInventoryItemLocked(controller.inventorySlot) then
        return "Target item is locked"
    end
end

function Controller.IsModificationPending()
    for _, controller in pairs(controllers) do
        if controller.pending or controller.submitting then
            return true
        end
    end
    return false
end

function Controller:ActivateSlot(position, button)
    button.wsgsSubmission = nil
    if synchronizeBuild() then
        return
    end
    local controller = controllers[position]
    if not controller then
        if not InCombatLockdown() then button:SetAttribute("type1", nil) end
        return
    end
    if controller.difference.fields.item.state ~= "MATCH" then
        if not InCombatLockdown() then
            button:SetAttribute("type1", nil)
        end
        Equipment:Equip(position)
        -- Equipment events can prepare a modification synchronously. This
        -- hardware click belongs only to equipment, even if the new item matches.
        if not InCombatLockdown() then
            button:SetAttribute("type1", nil)
        end
        return
    end
    if controller.state == "BLOCKED" or controller.state == "UNKNOWN" then
        controller.lastFailed = nil
        refreshFromClient(self, "RETRY_CLICK")
        controller = controllers[position]
    end
    if not controller or controller.state ~= "READY" or not controller.prepared then
        return
    end
    local operation = controller.prepared
    local problem = validateClick(controller, operation, position)
    if problem then
        Pending:Fail(controller, operation, problem)
        return
    end
    debug("EXEC", string.format(
        "slot=%d type=%s material=%s materialGuid=%s spell=%s spellName=%s guid=%s phase=%s",
        controller.inventorySlot, operation.type, valueText(operation.materialItemID),
        valueText(operation.material and operation.material.guid), valueText(operation.spellID),
        valueText(operation.spellName), valueText(controller.targetGuid),
        operation.nativeProfession and "native" or "secure"))
    debug("EXEC", string.format("slot=%d handler=%s check=READY method=%s", controller.inventorySlot,
        operation.handlerName, operation.method))
    local request = {
        method = operation.method,
        operation = operation,
        inventorySlot = controller.inventorySlot,
        targetItemID = controller.target.id,
        targetGUID = controller.targetGuid
    }
    submitRequest(self, controller, request, button)
end

local function finishActivation(self, position, button)
    synchronizeBuild()
    local submission = button.wsgsSubmission
    button.wsgsSubmission = nil
    if not submission then
        configureButton(position)
        return
    end
    local controller = controllers[submission.position]
    local operation = submission.operation
    if not controller or controller.submitting ~= operation then
        return
    end
    if controller.failure then
        Pending:Fail(controller, operation, controller.failure)
        return
    end
    Pending:MarkPending(controller, operation)
    configureButton(position)
    self:SendMessage("WSGS_ACTIONS_CHANGED", "PENDING")
end

function WSGS.Enhancements:BindSlot(position, button)
    buttons[position] = button
    button:SetScript("PreClick", function(clicked)
        Controller:ActivateSlot(position, clicked)
    end)
    button:SetScript("PostClick", function(clicked)
        finishActivation(Controller, position, clicked)
    end)
    configureButton(position)
end

Pending = Internal.CreatePendingApplication({
    synchronizeBuild = synchronizeBuild,
    controllerAt = function(position) return controllers[position] end,
    refresh = function(reason) refreshFromClient(Controller, reason) end,
    changed = function(reason) Controller:SendMessage("WSGS_ACTIONS_CHANGED", reason) end
})

Internal.Events:Configure({
    synchronizeBuild = synchronizeBuild,
    controllers = function() return controllers end,
    refresh = Modules.RequestReconcile
})
