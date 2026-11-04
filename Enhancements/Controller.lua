local _, WSGS = ...
local Modules = WSGS.Private
local Actions = WSGS:NewModule("Actions", "AceEvent-3.0")
local Equipment = Modules.Equipment.Runtime
Modules.Enhancements.Runtime = Actions

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
    local button = buttons[position]
    if not button or InCombatLockdown() then
        return
    end
    local controller = controllers[position]
    local operation = controller and controller.state == "READY" and controller.prepared
    local actionType = operation and
        not operation.nativeProfession and "item" or nil
    button:SetAttribute("wsgs-type1", actionType)
    button:SetAttribute("type1", actionType)
    button:SetAttribute("item1",
        actionType == "item" and operation.material and
            string.format("%d %d", operation.material.bag, operation.material.bagSlot) or nil)
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
        Actions:SendMessage("WSGS_ACTIONS_CHANGED", "BUILD_REPLACED")
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
        Modules.Equipment.Slots[position].id, controller.inventorySlot, controller.state,
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
    for position = 1, #Modules.Equipment.Slots do
        rebuildController(position, state)
    end
end

function Actions:GetSlotState(position)
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
        Pending:MarkUnknown( controller, operation, result.reason)
        return false
    end
    if not result or result.status ~= "SUBMITTED" then
        button.wsgsSubmission = nil
        Pending:Fail( controller, operation, result and result.reason or "Profession execution returned no result",
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
    local operation = request.operation
    local material = operation.material
    if not material then
        Pending:Fail( controller, operation, "Prepared material location is unavailable", "OPERATION")
        return false
    end
    local current = C_Container.GetContainerItemInfo(material.bag, material.bagSlot)
    if not current or current.itemID ~= material.itemID or current.isLocked then
        Pending:Fail( controller, operation, "Prepared material moved or became locked", "OPERATION")
        return false
    end
    local guidOK, currentGuid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(material.bag,
        material.bagSlot))
    if material.guid and (not guidOK or currentGuid ~= material.guid) then
        Pending:Fail( controller, operation, "Prepared material instance moved; rescan before retrying", "OPERATION")
        return false
    end
    configureButton(controller.position)
    local expectedItem = string.format("%d %d", material.bag, material.bagSlot)
    if button:GetAttribute("type1") ~= "item" or button:GetAttribute("target-slot1") ~= controller.inventorySlot or
        button:GetAttribute("item1") ~= expectedItem then
        Pending:Fail( controller, operation, "Secure action could not be prepared", "OPERATION")
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
    if request.method == "PROFESSION" then
        return submitProfession(self, controller, request, button)
    end
    if request.method == "ITEM" then
        return submitItem(self, controller, request, button)
    end
    Pending:Fail( controller, request.operation, "Prepared action has no supported execution method")
    return false
end

local function validateClick(controller, operation, position)
    if InCombatLockdown() then
        return "Action unavailable during combat lockdown"
    end
    if CursorHasItem() then
        return "Place the held cursor item first"
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
    for _, controller in pairs(controllers) do
        if controller.pending or controller.submitting then
            return true
        end
    end
    return false
end

function Actions:ActivateSlot(position, button)
    button.wsgsSubmission = nil
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
        Pending:Fail( controller, operation, problem)
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
        Pending:Fail( controller, operation, controller.failure)
        return
    end
    Pending:MarkPending( controller, operation)
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

function Actions:TRADE_SKILL_LIST_UPDATE(event, ...)
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
        if candidateOperation then
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
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    self:RegisterEvent("REPLACE_ENCHANT")
    self:RegisterEvent("BIND_ENCHANT")
    self:RegisterEvent("ACTION_WILL_BIND_ITEM")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

Pending = Internal.CreatePendingApplication({
    synchronizeBuild = synchronizeBuild,
    controllerAt = function(position) return controllers[position] end,
    refresh = function(reason) refreshFromClient(Actions, reason) end,
    changed = function(reason) Actions:SendMessage("WSGS_ACTIONS_CHANGED", reason) end
})
