local _, WSGS = ...
local Actions = WSGS:NewModule("Actions", "AceEvent-3.0")
local Equipment = WSGS:GetModule("Equipment")
WSGS.Actions = Actions

local Internal = WSGS.ActionsInternal
WSGS.ActionsInternal = nil
local controllers, buttons, planSignatures = {}, {}, {}
local serial = 0
local controllerBuild

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

local function operationSatisfied(operation, difference, targetInstanceMatches)
    return operation.handler.Verify({
        operation = operation,
        difference = difference,
        targetInstanceMatches = targetInstanceMatches
    })
end

local function sameOperation(left, right)
    return left and right and left.handlerName == right.handlerName and left.type == right.type and
               left.field == right.field and left.socket == right.socket and left.expected == right.expected and
               left.expectedCount == right.expectedCount
end

local function configureButton(position)
    local button = buttons[position]
    if not button or InCombatLockdown() then
        return
    end
    local controller = controllers[position]
    local operation = controller and controller.state == "READY" and controller.prepared
    local actionType = not Internal.GemExecution.batch and operation and operation.type ~= "GEM" and
        not operation.nativeProfession and "item" or nil
    button:SetAttribute("wsgs-type1", actionType)
    button:SetAttribute("type1", actionType)
    button:SetAttribute("item1",
        actionType == "item" and operation.material and
            string.format("%d %d", operation.material.bag, operation.material.slot) or nil)
    button:SetAttribute("spell1", nil)
    button:SetAttribute("macrotext1", nil)
    button:SetAttribute("action1", nil)
    button:SetAttribute("target-slot1", actionType and controller.inventorySlot or nil)
end

local function synchronizeBuild()
    local build = WSGS:GetActiveSimulationProfile()
    if controllerBuild == build then
        return false
    end
    local previousBuild = controllerBuild
    for _, controller in pairs(controllers) do
        local operation = controller.pending or controller.submitting
        if operation then
            debug("CANCEL", string.format(
                "build=%s nextBuild=%s slot=%d serial=%s type=%s expected=%s count=%s guid=%s reason=build-replaced verification-only",
                valueText(previousBuild and previousBuild.id), valueText(build and build.id),
                controller.inventorySlot, valueText(controller.serial), operation.type,
                valueText(operation.expected), valueText(operation.expectedCount), valueText(controller.targetGuid)))
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
        Actions:SendMessage("WSGS_ACTIONS_CHANGED", "BUILD_REPLACED")
    end
    return true
end

local function carryPending(previous, built, difference)
    if not previous then
        return built
    end
    if previous.pending then
        local sameInstance = previous.targetGuid == built.targetGuid
        local satisfied, detail, actual = operationSatisfied(previous.pending, difference, sameInstance)
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

local function controllerSignature(controller)
    local operation = selectedOperation(controller)
    return table.concat({valueText(controller.inventorySlot), controller.state, operation and operation.type or "none",
                         operation and valueText(operation.expected) or "nil", valueText(controller.targetGuid),
                         controller.reason or operation and operation.reason or "none",
                         valueText(operation and operation.material and operation.material.bag),
                         valueText(operation and operation.material and operation.material.slot),
                         valueText(operation and operation.targetSource)}, ":"), operation
end

local function logPlan(position, controller)
    local signature, operation = controllerSignature(controller)
    local changed = planSignatures[position] ~= signature
    planSignatures[position] = signature
    if not changed then
        return
    end
    debug("PLAN", string.format("slot=%d actualSlot=%d state=%s handler=%s next=%s expected=%s guid=%s reason=%s",
        WSGS.equipmentSlots[position].id, controller.inventorySlot, controller.state,
        operation and operation.handlerName or "none", operation and operation.type or "none",
        operation and valueText(operation.expected) or "nil", valueText(controller.targetGuid),
        controller.reason or operation and operation.reason or "none"))
    if controller.state == "READY" then
        local prepared = controller.prepared
        debug("READY", string.format(
            "slot=%d handler=%s type=%s material=%s materialGuid=%s profession=%s recipe=%s spellName=%s professionSpell=%s effect=%s guid=%s source=%s",
            controller.inventorySlot, prepared.handlerName, prepared.type, valueText(prepared.materialItemID),
            valueText(prepared.material and prepared.material.guid), valueText(prepared.professionName),
            valueText(prepared.spellID), valueText(prepared.spellName), valueText(prepared.professionSpellIndex),
            valueText(prepared.expected), valueText(controller.targetGuid), valueText(prepared.targetSource)))
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
    built = carryPending(previous, built, state.comparison.slots[position])
    controllers[position] = built
    logPlan(position, built)
    configureButton(position)
end

function Actions:Refresh(state)
    synchronizeBuild()
    if not state or not state.build or not state.comparison or not controllerBuild or
        state.target ~= controllerBuild.equipment then
        controllers = {}
        for position in pairs(buttons) do
            configureButton(position)
        end
        return
    end
    for position = 1, 16 do
        rebuildController(position, state)
    end
end

function Actions:GetSlotState(position)
    local gemState = Internal.GemExecution:GetSlotState(position)
    if gemState then
        return gemState
    end
    local controller = controllers[position]
    return Internal.Presentation:Build(controller, selectedOperation(controller))
end

local function refreshFromClient(self, reason)
    local profile = WSGS:GetActiveSimulationProfile()
    if not profile then
        return
    end
    local state = Equipment:RefreshState(profile, "SlotActions:" .. tostring(reason))
    if state.comparison then
        self:Refresh(state)
    end
    self:SendMessage("WSGS_ACTIONS_CHANGED", reason)
end

local fail

local function scheduleTimeout(self, controller)
    if controller.timeoutScheduled then
        return
    end
    controller.timeoutScheduled = true
    local pendingSerial = controller.serial
    C_Timer.After(8, function()
        synchronizeBuild()
        local current = controllers[controller.position]
        if not current or current.state ~= "PENDING" or current.serial ~= pendingSerial then
            return
        end
        debug("EVENT", string.format("slot=%d event=VERIFICATION_TIMEOUT serial=%d phase=rescan",
            current.inventorySlot, pendingSerial))
        refreshFromClient(self, "VERIFICATION_TIMEOUT_RESCAN")
        C_Timer.After(0, function()
            synchronizeBuild()
            current = controllers[controller.position]
            if not current or current.state ~= "PENDING" or current.serial ~= pendingSerial then
                return
            end
            refreshFromClient(self, "VERIFICATION_TIMEOUT_FINAL_RESCAN")
            current = controllers[controller.position]
            if current and current.state == "PENDING" and current.serial == pendingSerial then
                fail(self, current, current.pending, "Timed out without a verified item-state change")
            end
        end)
    end)
end

local function markPending(self, controller, operation, waitForSocketAccept)
    serial = serial + 1
    controller.state = "PENDING"
    controller.pending = operation
    controller.submitting = nil
    controller.startedAt = GetTime()
    controller.serial = serial
    debug("EXEC", string.format("slot=%d type=%s submitted serial=%d; awaiting events", controller.inventorySlot,
        operation.type, controller.serial))
    if not waitForSocketAccept then
        scheduleTimeout(self, controller)
    end
end

fail = function(self, controller, operation, reason, scope)
    controller.state = "BLOCKED"
    controller.reason = reason
    controller.lastFailed = operation
    controller.failureScope = scope or "SLOT"
    controller.pending = nil
    controller.submitting = nil
    debug("BLOCK", string.format("slot=%d type=%s scope=%s reason=%s", controller.inventorySlot, operation.type,
        controller.failureScope, reason))
    self:SendMessage("WSGS_ACTIONS_CHANGED", "FAILED")
end

local function markUnknown(self, controller, operation, reason)
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
    self:SendMessage("WSGS_ACTIONS_CHANGED", "UNRESOLVED")
end
local function submitGem(self, controller, request, button)
    local started, problem = Internal.GemExecution:Start(controller.position)
    -- A synchronous completion can prepare an enchant during this PreClick.
    -- Keep this hardware click dedicated to the gem batch.
    if not InCombatLockdown() then
        button:SetAttribute("type1", nil)
    end
    if not started then
        fail(self, controller, request.operation, problem, "OPERATION")
    end
    return started
end

function Actions:GemSocketingFailed(position, operation, reason)
    local controller = controllers[position]
    if controller and operation then
        fail(self, controller, operation, reason, "OPERATION")
    end
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
        markUnknown(self, controller, operation, result.reason)
        return false
    end
    if not result or result.status ~= "SUBMITTED" then
        button.wsgsSubmission = nil
        fail(self, controller, operation, result and result.reason or "Profession execution returned no result",
            "OPERATION")
        return false
    end
    operation.spellID = result.spellID
    operation.spellName = result.spellName
    operation.professionName = result.professionName
    operation.professionSpellIndex = result.professionSpellIndex
    operation.executionToken = result
    return true
end

local function submitItem(self, controller, request, button)
    local operation = request.operation
    local material = operation.material
    if not material then
        fail(self, controller, operation, "Prepared material location is unavailable", "OPERATION")
        return false
    end
    local current = C_Container.GetContainerItemInfo(material.bag, material.slot)
    if not current or current.itemID ~= material.itemID or current.isLocked then
        fail(self, controller, operation, "Prepared material moved or became locked", "OPERATION")
        return false
    end
    local guidOK, currentGuid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(material.bag,
        material.slot))
    if material.guid and (not guidOK or currentGuid ~= material.guid) then
        fail(self, controller, operation, "Prepared material instance moved; rescan before retrying", "OPERATION")
        return false
    end
    configureButton(controller.position)
    local expectedItem = string.format("%d %d", material.bag, material.slot)
    if button:GetAttribute("type1") ~= "item" or button:GetAttribute("target-slot1") ~= controller.inventorySlot or
        button:GetAttribute("item1") ~= expectedItem then
        fail(self, controller, operation, "Secure action could not be prepared", "OPERATION")
        return false
    end
    controller.submitting = operation
    button.wsgsSubmission = {
        position = controller.position,
        operation = operation
    }
    debug("EXEC", string.format("slot=%d handler=%s api=SecureActionButton:item action=%s target-slot=%d",
        controller.inventorySlot, operation.handlerName, expectedItem, controller.inventorySlot))
    return true
end

local function submitRequest(self, controller, request, button)
    if request.method == "GEM" then
        return submitGem(self, controller, request, button)
    end
    if request.method == "PROFESSION" then
        return submitProfession(self, controller, request, button)
    end
    if request.method == "ITEM" then
        return submitItem(self, controller, request, button)
    end
    fail(self, controller, request.operation, "Prepared action has no supported execution method")
    return false
end

local function activeModificationAtOtherPosition(position)
    for otherPosition, other in pairs(controllers) do
        if otherPosition ~= position and (other.pending or other.submitting) then
            return true
        end
    end
    return false
end

local function validateClick(controller, operation, position)
    if InCombatLockdown() then
        return "Action unavailable during combat lockdown"
    end
    if CursorHasItem() then
        return "Place the held cursor item first"
    end
    if operation.type == "GEM" and activeModificationAtOtherPosition(position) then
        return "Finish the active modification first"
    end
    if SpellIsTargeting() then
        return "Finish or cancel the active item-targeting cursor first"
    end
    local id = GetInventoryItemID("player", controller.inventorySlot)
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromEquipmentSlot(controller.inventorySlot))
    if id ~= controller.target.id or not ok or guid ~= controller.targetGuid then
        return "The equipped target item or instance changed; rescan before retrying"
    end
    if IsInventoryItemLocked(controller.inventorySlot) then
        return "Target item is locked"
    end
end

function Actions.IsModificationPending()
    if Internal.GemExecution.batch then
        return true
    end
    for _, controller in pairs(controllers) do
        if controller.pending or controller.submitting then
            return true
        end
    end
    return false
end

function Actions:ActivateSlot(position, button)
    button.wsgsSubmission = nil
    if Internal.GemExecution.batch then
        if not InCombatLockdown() then
            button:SetAttribute("type1", nil)
        end
        return
    end
    if synchronizeBuild() then
        return
    end
    local controller = controllers[position]
    if not controller then
        return
    end
    if controller.difference.fields.item.state ~= "MATCH" then
        if not InCombatLockdown() then
            button:SetAttribute("type1", nil)
        end
        Equipment:Click(position)
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
        fail(self, controller, operation, problem)
        return
    end
    debug("EXEC", string.format(
        "slot=%d type=%s material=%s materialGuid=%s spell=%s spellName=%s guid=%s phase=%s",
        controller.inventorySlot, operation.type, valueText(operation.materialItemID),
        valueText(operation.material and operation.material.guid), valueText(operation.spellID),
        valueText(operation.spellName), valueText(controller.targetGuid), operation.type == "GEM" and "socket" or
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
        fail(self, controller, operation, controller.failure)
        return
    end
    markPending(self, controller, operation)
    configureButton(position)
    self:SendMessage("WSGS_ACTIONS_CHANGED", "PENDING")
end

function Actions:RegisterSlotButton(position, button)
    buttons[position] = button
    button:SetScript("PreClick", function(clicked)
        self:ActivateSlot(position, clicked)
    end)
    button:SetScript("PostClick", function(clicked)
        finishActivation(self, position, clicked)
    end)
    configureButton(position)
end

local function activeState()
    synchronizeBuild()
    local active, submitting
    for _, controller in pairs(controllers) do
        if controller.state == "PENDING" or controller.submitting then
            active = true
        end
        if controller.submitting then
            submitting = true
        end
    end
    return active, submitting
end

local function logEvent(event, ...)
    local args = {}
    for index = 1, select("#", ...) do
        args[index] = valueText(select(index, ...))
    end
    debug("EVENT", string.format("event=%s args=%s", event, table.concat(args, ",")))
end

local function finishEvent(self, event, submitting, ...)
    logEvent(event, ...)
    if submitting then
        return
    end
    refreshFromClient(self, event)
end

local function handleActiveEvent(self, event, ...)
    local active, submitting = activeState()
    if not active then
        return
    end
    finishEvent(self, event, submitting, ...)
end

function Actions:PLAYER_EQUIPMENT_CHANGED(event, inventorySlot, ...)
    local active, submitting = activeState()
    if not active then
        return
    end
    local relevant
    for _, controller in pairs(controllers) do
        if (controller.pending or controller.submitting) and controller.inventorySlot == inventorySlot then
            relevant = true
            break
        end
    end
    if not relevant then
        return
    end
    finishEvent(self, event, submitting, inventorySlot, ...)
end

function Actions:BAG_UPDATE_DELAYED(event, ...)
    handleActiveEvent(self, event, ...)
end

function Actions:ITEM_LOCK_CHANGED(event, ...)
    handleActiveEvent(self, event, ...)
end

function Actions:TRADE_SKILL_SHOW(event, ...)
    handleActiveEvent(self, event, ...)
end

function Actions:TRADE_SKILL_UPDATE(event, ...)
    handleActiveEvent(self, event, ...)
end

function Actions:PLAYER_REGEN_ENABLED(event, ...)
    handleActiveEvent(self, event, ...)
end

function Actions:UNIT_SPELLCAST_SENT(event, unit, target, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    synchronizeBuild()
    for _, controller in pairs(controllers) do
        local operation = controller.submitting
        if operation then
            local matches = operation.spellID == spellID
            for _, recipeSpellID in ipairs(operation.recipeSpellIDs or {}) do
                matches = matches or recipeSpellID == spellID
            end
            if matches then
                operation.castGUID = castGUID
            end
        end
    end
end

local function handleSpellcastResult(self, event, failed, unit, castGUID, spellID, ...)
    local active, submitting = activeState()
    if not active or unit ~= "player" then
        return
    end
    local relevant, tradeSkillClosed
    for _, controller in pairs(controllers) do
        local operation = controller.pending or controller.submitting
        if operation and operation.castGUID and operation.spellID == spellID and operation.castGUID == castGUID then
            relevant = true
            if failed then
                controller.failure = "Client spell cast failed or was interrupted"
            elseif not tradeSkillClosed and operation.nativeProfession and TradeSkillFrame and
                TradeSkillFrame:IsShown() then
                HideUIPanel(TradeSkillFrame)
                tradeSkillClosed = true
                debug("EVENT", string.format("event=%s slot=%d type=%s profession=%s tradeskill=closed", event,
                    controller.inventorySlot, operation.type, operation.professionName))
            end
        end
    end
    if not relevant then
        return
    end
    finishEvent(self, event, submitting, unit, castGUID, spellID, ...)
end

function Actions:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID, ...)
    handleSpellcastResult(self, event, false, unit, castGUID, spellID, ...)
end

function Actions:UNIT_SPELLCAST_FAILED(event, unit, castGUID, spellID, ...)
    handleSpellcastResult(self, event, true, unit, castGUID, spellID, ...)
end

function Actions:UNIT_SPELLCAST_INTERRUPTED(event, unit, castGUID, spellID, ...)
    handleSpellcastResult(self, event, true, unit, castGUID, spellID, ...)
end

local function confirmApplication(self, event, api, ...)
    local active = activeState()
    if not active then
        return
    end
    local controller, operation
    for _, candidate in pairs(controllers) do
        local candidateOperation = candidate.submitting
        if candidateOperation and candidateOperation.type ~= "GEM" then
            controller, operation = candidate, candidateOperation
            break
        end
    end
    if not operation then
        return
    end
    logEvent(event, ...)
    local ok, problem = pcall(api)
    if ok then
        StaticPopup_Hide(event)
    end
    debug("EVENT", string.format("event=%s slot=%d type=%s confirm=%s", event, controller.inventorySlot,
        operation.type, ok and "accepted" or "failed"))
    if not ok then
        controller.failure = event .. " confirmation failed: " .. tostring(problem)
    end
end

function Actions:REPLACE_ENCHANT(event, ...)
    confirmApplication(self, event, C_Item.ReplaceEnchant, ...)
end

function Actions:BIND_ENCHANT(event, ...)
    confirmApplication(self, event, C_Item.BindEnchant, ...)
end

function Actions:ACTION_WILL_BIND_ITEM(event, ...)
    confirmApplication(self, event, C_Item.ActionBindsItem, ...)
end

function Actions:WSGS_EQUIPMENT_STATE_INVALIDATED(_, event, ...)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        self:PLAYER_EQUIPMENT_CHANGED(event, ...)
    elseif event == "BAG_UPDATE_DELAYED" then
        self:BAG_UPDATE_DELAYED(event, ...)
    elseif event == "ITEM_LOCK_CHANGED" then
        self:ITEM_LOCK_CHANGED(event, ...)
    end
end

function Actions:WSGS_BUILD_IMPORTED()
    synchronizeBuild()
end

function Actions:OnEnable()
    planSignatures = {}
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_INVALIDATED")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:RegisterEvent("UNIT_SPELLCAST_SENT")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:RegisterEvent("TRADE_SKILL_SHOW")
    self:RegisterEvent("TRADE_SKILL_UPDATE")
    self:RegisterEvent("REPLACE_ENCHANT")
    self:RegisterEvent("BIND_ENCHANT")
    self:RegisterEvent("ACTION_WILL_BIND_ITEM")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end
