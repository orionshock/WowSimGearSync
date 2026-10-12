local _, WSGS = ...
local Actions = WSGS:NewModule("Actions", "AceEvent-3.0")
Actions.controllers, Actions.buttons, Actions.serial = {}, {}, 0
WSGS.SlotActions = Actions

local colors = {
    WAITING_FOR_ITEM = "8cb3ff",
    READY = "4dff66",
    PENDING = "999999",
    UNKNOWN = "8cb3ff",
    BLOCKED = "ffb326",
    COMPLETE = "4dff66"
}
local labels = {
    BUCKLE = "belt buckle",
    GEM = "gem",
    ENCHANT = "enchant",
    PROFESSION_ENCHANT = "profession enhancement",
    PROFESSION_SOCKET = "Blacksmithing socket",
    TINKER = "Engineering tinker"
}

local function debug(category, text)
    WSGS:Debug("[ACTION][" .. category .. "] " .. text)
end

local function valueText(value)
    return value == nil and "nil" or tostring(value)
end

local function operationSatisfied(operation, difference)
    return operation.handler:Verify({
        operation = operation,
        difference = difference
    })
end

function Actions:Refresh(profile, snapshot, comparison)
    if not profile or not snapshot or not comparison then
        self.controllers = {}
        for position in pairs(self.buttons) do
            self:ConfigureButton(position)
        end
        return
    end
    local bags = WSGS.ModificationMaterials:ScanBags()
    for position = 1, 16 do
        local previous = self.controllers[position]
        local built = WSGS.SlotActionPlanner:Build(position, profile, snapshot, comparison, bags)
        if previous and previous.pending then
            local sameInstance = previous.targetGuid == built.targetGuid
            local satisfied, detail, actual = operationSatisfied(previous.pending, comparison.slots[position])
            if sameInstance and satisfied then
                debug("VERIFY",
                    string.format("slot=%d handler=%s type=%s expected=%s actual=%s guid=%s result=MATCH",
                        previous.inventorySlot, previous.pending.handlerName, previous.pending.type,
                        valueText(previous.pending.expected), valueText(actual), valueText(previous.targetGuid)))
                debug("DONE",
                    string.format("slot=%d handler=%s type=%s verified", previous.inventorySlot,
                        previous.pending.handlerName, previous.pending.type))
            elseif previous.failure or not sameInstance then
                built.state = "BLOCKED"
                built.reason = previous.failure or "Target item instance changed before verification"
                built.lastFailed = previous.pending
                debug("VERIFY",
                    string.format("slot=%d handler=%s type=%s expected=%s result=FAILED reason=%s",
                        previous.inventorySlot, previous.pending.handlerName, previous.pending.type,
                        valueText(previous.pending.expected), built.reason))
            else
                built.state, built.pending, built.startedAt = "PENDING", previous.pending, previous.startedAt
                built.reason = "Awaiting client verification: " .. detail
                built.serial = previous.serial
                built.timeoutScheduled = previous.timeoutScheduled
                built.lastVerificationDetail = detail
                if previous.lastVerificationDetail ~= detail then
                    debug("VERIFY",
                        string.format("slot=%d handler=%s type=%s expected=%s actual=%s result=STILL_PENDING reason=%s",
                            previous.inventorySlot, previous.pending.handlerName, previous.pending.type,
                            valueText(previous.pending.expected), valueText(actual), detail))
                end
            end
        elseif previous and previous.lastFailed and built.prepared then
            built.state, built.lastFailed = "BLOCKED", previous.lastFailed
            built.reason = previous.reason
        end
        self.controllers[position] = built
        local op = built.prepared or built.unknown[1] or built.blocked[1]
        local signature = table.concat({valueText(built.inventorySlot), built.state, op and op.type or "none",
                                        op and valueText(op.expected) or "nil", valueText(built.targetGuid),
                                        built.reason or op and op.reason or "none",
                                        valueText(op and op.material and op.material.bag),
                                        valueText(op and op.material and op.material.slot),
                                        valueText(op and op.targetSource)}, ":")
        local changed = self.planSignatures[position] ~= signature
        self.planSignatures[position] = signature
        if changed then
            debug("PLAN",
                string.format("slot=%d actualSlot=%d state=%s handler=%s next=%s expected=%s guid=%s reason=%s",
                    WSGS.equipmentSlots[position].id, built.inventorySlot, built.state, op and op.handlerName or "none",
                    op and op.type or "none", op and valueText(op.expected) or "nil", valueText(built.targetGuid),
                    built.reason or op and op.reason or "none"))
        end
        if changed and built.state == "READY" then
            debug("READY", string.format(
                "slot=%d handler=%s type=%s material=%s materialGuid=%s profession=%s recipe=%s spellName=%s professionSpell=%s effect=%s guid=%s source=%s",
                built.inventorySlot, built.prepared.handlerName, built.prepared.type,
                valueText(built.prepared.materialItemID),
                valueText(built.prepared.material and built.prepared.material.guid),
                valueText(built.prepared.professionName), valueText(built.prepared.spellID),
                valueText(built.prepared.spellName), valueText(built.prepared.professionSpellIndex),
                valueText(built.prepared.expected), valueText(built.targetGuid), valueText(built.prepared.targetSource)))
        elseif changed and built.state == "BLOCKED" then
            for _, blocked in ipairs(built.blocked) do
                debug("BLOCK",
                    string.format("slot=%d handler=%s type=%s profession=%s recipe=%s expected=%s reason=%s",
                        built.inventorySlot, blocked.handlerName, blocked.type,
                        valueText(blocked.professionName or blocked.professionSkillLine), valueText(blocked.spellID),
                        valueText(blocked.expected), blocked.reason or "unavailable"))
            end
            if #built.blocked == 0 then
                debug("BLOCK", string.format("slot=%d reason=%s", built.inventorySlot, built.reason or "unavailable"))
            end
        end
        if changed and built.state == "UNKNOWN" then
            debug("PLAN",
                string.format("slot=%d handler=%s result=UNKNOWN reason=%s", built.inventorySlot,
                    op and op.handlerName or "none", built.reason or "incomplete client data"))
        end
        self:ConfigureButton(position)
    end
end

function Actions:RegisterButton(position, button)
    self.buttons[position] = button
    self:ConfigureButton(position)
end

function Actions:ConfigureButton(position)
    local button = self.buttons[position]
    if not button or InCombatLockdown() then
        return
    end
    local controller = self.controllers[position]
    local operation = controller and controller.state == "READY" and controller.prepared
    local actionType = operation and operation.type ~= "GEM" and not operation.nativeProfession and "item" or nil
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

function Actions:Rescan(reason)
    local profile = WSGS:GetActiveSimulationProfile()
    if not profile then
        return
    end
    local snapshot = WSGS.EquipmentScanner:Scan()
    local comparison = WSGS.EquipmentComparator:Compare(profile, snapshot)
    if comparison then
        self:Refresh(profile, snapshot, comparison, reason)
    end
    self:SendMessage("WSGS_ACTIONS_CHANGED", reason)
end

function Actions:ScheduleTimeout(controller)
    if controller.timeoutScheduled then
        return
    end
    controller.timeoutScheduled = true
    local serial = controller.serial
    C_Timer.After(8, function()
        local current = self.controllers[controller.position]
        if current and current.state == "PENDING" and current.serial == serial then
            debug("EVENT", string.format("slot=%d event=VERIFICATION_TIMEOUT serial=%d", current.inventorySlot, serial))
            current.failure = "Timed out without a verified item-state change"
            self:Rescan("VERIFICATION_TIMEOUT")
        end
    end)
end

function Actions:MarkPending(controller, operation, waitForSocketAccept)
    self.serial = self.serial + 1
    controller.state, controller.pending, controller.submitting = "PENDING", operation, nil
    controller.startedAt, controller.serial = GetTime(), self.serial
    debug("EXEC",
        string.format("slot=%d type=%s submitted serial=%d; awaiting events", controller.inventorySlot, operation.type,
            controller.serial))
    if not waitForSocketAccept then
        self:ScheduleTimeout(controller)
    end
end

function Actions:Fail(controller, operation, reason)
    controller.state, controller.reason, controller.lastFailed = "BLOCKED", reason, operation
    controller.pending, controller.submitting = nil, nil
    debug("BLOCK", string.format("slot=%d type=%s reason=%s", controller.inventorySlot, operation.type, reason))
    self:SendMessage("WSGS_ACTIONS_CHANGED", "FAILED")
end

function Actions:ApplyPrepared(context)
    local controller, operation, button = context.controller, context.operation, context.button
    if operation.method == "GEM" then
        local ok, problem = pcall(SocketInventoryItem, controller.inventorySlot)
        if not ok then
            self:Fail(controller, operation, "SocketInventoryItem failed: " .. tostring(problem));
            return
        end
        self:MarkPending(controller, operation, true)
        controller.reason = string.format("Use Blizzard Socketing: place item %d in socket %d, then apply",
            operation.materialItemID, operation.socket)
        self:SendMessage("WSGS_ACTIONS_CHANGED", "SOCKET_OPENED")
        return
    end
    if operation.method == "PROFESSION" then
        controller.submitting = operation
        button.secureSubmission = {
            controller = controller,
            operation = operation
        }
        debug("EXEC",
            string.format("slot=%d handler=%s api=native-click profession=%s recipe=%s effect=%s",
                controller.inventorySlot, operation.handlerName, valueText(operation.professionName),
                valueText(operation.spellID), valueText(operation.expected)))
        WSGS.ProfessionEnhancementExecution:Submit(controller, operation)
        return
    end
    local material = operation.material
    if not material then
        self:Fail(controller, operation, "Prepared material location is unavailable");
        return
    end
    local current = C_Container.GetContainerItemInfo(material.bag, material.slot)
    if not current or current.itemID ~= material.itemID or current.isLocked then
        self:Fail(controller, operation, "Prepared material moved or became locked")
        return
    end
    local guidOK, currentGuid =
        pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(material.bag, material.slot))
    if material.guid and (not guidOK or currentGuid ~= material.guid) then
        self:Fail(controller, operation, "Prepared material instance moved; rescan before retrying")
        return
    end
    self:ConfigureButton(controller.position)
    local expectedItem = string.format("%d %d", material.bag, material.slot)
    if button:GetAttribute("type1") ~= "item" or button:GetAttribute("target-slot1") ~= controller.inventorySlot or
        button:GetAttribute("item1") ~= expectedItem then
        self:Fail(controller, operation, "Secure action could not be prepared")
        return
    end
    controller.submitting = operation
    button.secureSubmission = {
        controller = controller,
        operation = operation
    }
    debug("EXEC",
        string.format("slot=%d handler=%s api=SecureActionButton:item action=%s target-slot=%d",
            controller.inventorySlot, operation.handlerName, expectedItem, controller.inventorySlot))
end

function Actions:PreClick(position, button)
    button.secureSubmission = nil
    local controller = self.controllers[position]
    if not controller then
        return
    end
    if controller.state == "BLOCKED" or controller.state == "UNKNOWN" then
        controller.lastFailed = nil
        self:Rescan("RETRY_CLICK")
        controller = self.controllers[position]
    end
    if controller.state ~= "READY" or not controller.prepared then
        return
    end
    local operation = controller.prepared
    if InCombatLockdown() then
        return self:Fail(controller, operation, "Action unavailable during combat lockdown")
    end
    if CursorHasItem() then
        return self:Fail(controller, operation, "Place the held cursor item first")
    end
    for otherPosition, other in pairs(self.controllers) do
        if otherPosition ~= position and operation.type == "GEM" and other.pending and other.pending.type == "GEM" then
            return self:Fail(controller, operation, "Finish the active Blizzard Socketing interaction first")
        end
    end
    if SpellIsTargeting() then
        return self:Fail(controller, operation, "Finish or cancel the active item-targeting cursor first")
    end
    local id = GetInventoryItemID("player", controller.inventorySlot)
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromEquipmentSlot(controller.inventorySlot))
    if id ~= controller.target.id or not ok or guid ~= controller.targetGuid then
        return self:Fail(controller, operation, "The equipped target item or instance changed; rescan before retrying")
    end
    if IsInventoryItemLocked(controller.inventorySlot) then
        return self:Fail(controller, operation, "Target item is locked")
    end
    debug("EXEC", string.format("slot=%d type=%s material=%s materialGuid=%s spell=%s spellName=%s guid=%s phase=%s",
        controller.inventorySlot, operation.type, valueText(operation.materialItemID),
        valueText(operation.material and operation.material.guid), valueText(operation.spellID),
        valueText(operation.spellName), valueText(controller.targetGuid), operation.type == "GEM" and "socket" or
            operation.nativeProfession and "native" or "secure"))

    debug("EXEC",
        string.format("slot=%d handler=%s check=READY method=%s", controller.inventorySlot, operation.handlerName,
            operation.method))
    operation.handler:Apply({
        actions = self,
        controller = controller,
        operation = operation,
        button = button
    })
end

function Actions:PostClick(position, button)
    local submission = button.secureSubmission
    button.secureSubmission = nil
    if not submission then
        return
    end
    local controller, operation = submission.controller, submission.operation
    if controller.failure then
        return self:Fail(controller, operation, controller.failure)
    end
    self:MarkPending(controller, operation)
    self:ConfigureButton(position)
    self:SendMessage("WSGS_ACTIONS_CHANGED", "PENDING")
end

function Actions:TooltipLines(position)
    local controller = self.controllers[position]
    if not controller then
        return {}
    end
    local color = colors[controller.state] or "ffffff"
    local lines = {" ", "|cff" .. color .. "Action: " .. controller.state:gsub("_", " ") .. "|r"}
    local operation = controller.prepared or controller.pending or controller.unknown[1] or controller.blocked[1]
    if operation then
        local text = "Next: " .. labels[operation.type]
        if operation.type == "GEM" and operation.expected and operation.socket then
            text = text .. string.format(" %d in socket %d", operation.expected, operation.socket)
        elseif operation.expected then
            text = text .. " " .. tostring(operation.expected)
        end
        if operation.targetSource == "RECOMMENDED" then
            text = text .. " (recommended)"
        elseif operation.targetSource == "SIMULATION" then
            text = text .. " (simulation target)"
        end
        lines[#lines + 1] = text
        if operation.material then
            lines[#lines + 1] = string.format("Material: item %d at bag %d, slot %d", operation.material.itemID,
                operation.material.bag, operation.material.slot)
        elseif operation.spellID then
            lines[#lines + 1] =
                string.format("Recipe: %s (%d)", operation.spellName or "unavailable", operation.spellID)
        end
    end
    if controller.reason then
        lines[#lines + 1] = controller.reason
    end
    return lines
end

function Actions:ClickText(position)
    local controller = self.controllers[position]
    if not controller or controller.state == "WAITING_FOR_ITEM" then
        return nil
    end
    local operation = controller.prepared or controller.pending or controller.lastFailed or controller.unknown[1] or
                          controller.blocked[1]
    local action = operation and labels[operation.type]
    if controller.state == "READY" and action then
        return "Click to apply " .. action
    end
    if controller.state == "PENDING" and action then
        return "Applying " .. action .. "..."
    end
    if controller.state == "UNKNOWN" then
        return "Click to recheck"
    end
    if controller.state == "BLOCKED" and controller.lastFailed and action then
        return "Click to retry " .. action
    end
    if controller.state == "BLOCKED" and action then
        return "Cannot apply " .. action
    end
    return "No action needed"
end

function Actions:ActiveState()
    local active, submitting
    for _, controller in pairs(self.controllers) do
        if controller.state == "PENDING" or controller.submitting then
            active = true
        end
        if controller.submitting then
            submitting = true
        end
    end
    return active, submitting
end

function Actions:LogEvent(event, ...)
    local args = {}
    for index = 1, select("#", ...) do
        args[index] = valueText(select(index, ...))
    end
    debug("EVENT", string.format("event=%s args=%s", event, table.concat(args, ",")))
end

function Actions:FinishEvent(event, submitting, ...)
    self:LogEvent(event, ...)
    if submitting then
        return
    end
    self:Rescan(event)
end

function Actions:HandleActiveEvent(event, ...)
    local active, submitting = self:ActiveState()
    if not active then
        return
    end
    self:FinishEvent(event, submitting, ...)
end

function Actions:HasPendingGem()
    for _, controller in pairs(self.controllers) do
        if controller.pending and controller.pending.type == "GEM" then
            return true
        end
    end
    return false
end

function Actions:HandleSocketEvent(event, ...)
    local active, submitting = self:ActiveState()
    if not active or not self:HasPendingGem() then
        return
    end
    self:FinishEvent(event, submitting, ...)
end

function Actions:PLAYER_EQUIPMENT_CHANGED(event, inventorySlot, ...)
    local active, submitting = self:ActiveState()
    if not active then
        return
    end
    local relevant
    for _, controller in pairs(self.controllers) do
        if (controller.pending or controller.submitting) and controller.inventorySlot == inventorySlot then
            relevant = true
            break
        end
    end
    if not relevant then
        return
    end
    self:FinishEvent(event, submitting, inventorySlot, ...)
end

function Actions:BAG_UPDATE_DELAYED(event, ...)
    self:HandleActiveEvent(event, ...)
end

function Actions:ITEM_LOCK_CHANGED(event, ...)
    self:HandleActiveEvent(event, ...)
end

function Actions:TRADE_SKILL_SHOW(event, ...)
    self:HandleActiveEvent(event, ...)
end

function Actions:TRADE_SKILL_UPDATE(event, ...)
    self:HandleActiveEvent(event, ...)
end

function Actions:PLAYER_REGEN_ENABLED(event, ...)
    self:HandleActiveEvent(event, ...)
end

function Actions:SOCKET_INFO_UPDATE(event, ...)
    self:HandleSocketEvent(event, ...)
end

function Actions:SOCKET_INFO_SUCCESS(event, ...)
    self:HandleSocketEvent(event, ...)
end

function Actions:SOCKET_INFO_ACCEPT(event, ...)
    local active, submitting = self:ActiveState()
    if not active or not self:HasPendingGem() then
        return
    end
    for _, controller in pairs(self.controllers) do
        if controller.pending and controller.pending.type == "GEM" then
            self:ScheduleTimeout(controller)
        end
    end
    self:FinishEvent(event, submitting, ...)
end

function Actions:SOCKET_INFO_FAILURE(event, ...)
    local active, submitting = self:ActiveState()
    if not active or not self:HasPendingGem() then
        return
    end
    for _, controller in pairs(self.controllers) do
        if controller.pending and controller.pending.type == "GEM" then
            controller.failure = "Blizzard socketing reported failure"
        end
    end
    self:FinishEvent(event, submitting, ...)
end

function Actions:SOCKET_INFO_CLOSE(event, ...)
    local active, submitting = self:ActiveState()
    if not active or not self:HasPendingGem() then
        return
    end
    for _, controller in pairs(self.controllers) do
        if controller.pending and controller.pending.type == "GEM" and not controller.timeoutScheduled then
            controller.failure = "Blizzard Socketing closed before the change was submitted"
        end
    end
    self:FinishEvent(event, submitting, ...)
end

function Actions:HandleSpellcastResult(event, failed, unit, castGUID, spellID, ...)
    local active, submitting = self:ActiveState()
    if not active or unit ~= "player" then
        return
    end
    local relevant, tradeSkillClosed
    for _, controller in pairs(self.controllers) do
        local operation = controller.pending or controller.submitting
        if operation and operation.spellID == spellID then
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
    self:FinishEvent(event, submitting, unit, castGUID, spellID, ...)
end

function Actions:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID, ...)
    self:HandleSpellcastResult(event, false, unit, castGUID, spellID, ...)
end

function Actions:UNIT_SPELLCAST_FAILED(event, unit, castGUID, spellID, ...)
    self:HandleSpellcastResult(event, true, unit, castGUID, spellID, ...)
end

function Actions:UNIT_SPELLCAST_INTERRUPTED(event, unit, castGUID, spellID, ...)
    self:HandleSpellcastResult(event, true, unit, castGUID, spellID, ...)
end

function Actions:ConfirmApplication(event, api, ...)
    local active = self:ActiveState()
    if not active then
        return
    end
    local controller, operation
    for _, candidate in pairs(self.controllers) do
        local candidateOperation = candidate.submitting
        if candidateOperation and candidateOperation.type ~= "GEM" then
            controller, operation = candidate, candidateOperation
            break
        end
    end
    if not operation then
        return
    end
    self:LogEvent(event, ...)
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
    self:ConfirmApplication(event, C_Item.ReplaceEnchant, ...)
end

function Actions:BIND_ENCHANT(event, ...)
    self:ConfirmApplication(event, C_Item.BindEnchant, ...)
end

function Actions:ACTION_WILL_BIND_ITEM(event, ...)
    self:ConfirmApplication(event, C_Item.ActionBindsItem, ...)
end

function Actions:OnEnable()
    self.planSignatures = {}
    for _, event in ipairs({"PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "SOCKET_INFO_UPDATE",
                            "SOCKET_INFO_ACCEPT", "SOCKET_INFO_SUCCESS", "SOCKET_INFO_FAILURE", "SOCKET_INFO_CLOSE",
                            "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
                            "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "REPLACE_ENCHANT", "BIND_ENCHANT",
                            "ACTION_WILL_BIND_ITEM", "PLAYER_REGEN_ENABLED"}) do
        self:RegisterEvent(event)
    end
end
