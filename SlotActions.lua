local _, WSGS = ...
local Actions = { controllers = {}, buttons = {}, serial = 0 }
WSGS.SlotActions = Actions

local colors = { WAITING_FOR_ITEM = "8cb3ff", READY = "4dff66", PENDING = "999999",
    BLOCKED = "ffb326", COMPLETE = "4dff66" }
local labels = { BUCKLE = "belt buckle", GEM = "gem", ENCHANT = "enchant", TINKER = "Engineering tinker" }

local function debug(category, text)
    WSGS:Debug("[ACTION][" .. category .. "] " .. text)
end

local function valueText(value)
    return value == nil and "nil" or tostring(value)
end

local function operationSatisfied(operation, difference)
    if not difference or difference.fields.item.state ~= "MATCH" then return false, "target item no longer equipped" end
    local field = difference.fields[operation.field]
    if operation.type == "GEM" then field = field and field.sockets and field.sockets[operation.socket] end
    if not field then return false, "comparison field unavailable" end
    return field.state == "MATCH", field.state .. (field.reason and ": " .. field.reason or "")
end

local function tinkerMacro(operation)
    if not operation or not operation.spellID or not operation.professionName then return nil end
    return string.format("/run CloseTradeSkill()\n/cast %s\n/run WoWSimGearSync_DoTinker(%d)",
        operation.professionName, operation.spellID)
end

local function recipeIDFromLink(link)
    return tonumber(link and (link:match("|Henchant:(%d+)") or link:match("|Hspell:(%d+)")))
end

function Actions:Refresh(profile, snapshot, comparison)
    if not profile or not snapshot or not comparison then
        self.controllers = {}
        for position in pairs(self.buttons) do self:ConfigureButton(position) end
        return
    end
    local bags = WSGS.ModificationMaterials:ScanBags()
    for position = 1, 16 do
        local previous = self.controllers[position]
        local built = WSGS.SlotActionPlanner:Build(position, profile, snapshot, comparison, bags)
        if previous and previous.pending then
            local sameInstance = previous.targetGuid == built.targetGuid
            local satisfied, detail = operationSatisfied(previous.pending, comparison.slots[position])
            if sameInstance and satisfied then
                debug("VERIFY", string.format("slot=%d type=%s expected=%s guid=%s result=MATCH",
                    previous.inventorySlot, previous.pending.type, valueText(previous.pending.expected), valueText(previous.targetGuid)))
                debug("DONE", string.format("slot=%d type=%s verified", previous.inventorySlot, previous.pending.type))
            elseif previous.failure or not sameInstance then
                built.state = "BLOCKED"
                built.reason = previous.failure or "Target item instance changed before verification"
                built.lastFailed = previous.pending
                debug("VERIFY", string.format("slot=%d type=%s expected=%s result=FAILED reason=%s",
                    previous.inventorySlot, previous.pending.type, valueText(previous.pending.expected), built.reason))
            else
                built.state, built.pending, built.startedAt = "PENDING", previous.pending, previous.startedAt
                built.reason = "Awaiting client verification: " .. detail
                built.serial = previous.serial
                built.timeoutScheduled = previous.timeoutScheduled
                built.lastVerificationDetail = detail
                if previous.lastVerificationDetail ~= detail then
                    debug("VERIFY", string.format("slot=%d type=%s expected=%s result=STILL_PENDING reason=%s",
                        previous.inventorySlot, previous.pending.type, valueText(previous.pending.expected), detail))
                end
            end
        elseif previous and previous.lastFailed and built.prepared then
            built.state, built.lastFailed = "BLOCKED", previous.lastFailed
            built.reason = previous.reason
        end
        self.controllers[position] = built
        local op = built.prepared or built.blocked[1]
        local signature = table.concat({ valueText(built.inventorySlot), built.state, op and op.type or "none",
            op and valueText(op.expected) or "nil", valueText(built.targetGuid), built.reason or op and op.reason or "none",
            valueText(op and op.material and op.material.bag), valueText(op and op.material and op.material.slot),
            valueText(op and op.targetSource) }, ":")
        local changed = self.planSignatures[position] ~= signature
        self.planSignatures[position] = signature
        if changed then debug("PLAN", string.format("slot=%d actualSlot=%d state=%s next=%s expected=%s guid=%s reason=%s",
            WSGS.equipmentSlots[position].id, built.inventorySlot, built.state, op and op.type or "none",
            op and valueText(op.expected) or "nil", valueText(built.targetGuid), built.reason or op and op.reason or "none")) end
        if changed and built.state == "READY" then
            debug("READY", string.format("slot=%d type=%s material=%s materialGuid=%s spell=%s spellName=%s guid=%s source=%s",
                built.inventorySlot, built.prepared.type, valueText(built.prepared.materialItemID),
                valueText(built.prepared.material and built.prepared.material.guid), valueText(built.prepared.spellID),
                valueText(built.prepared.spellName), valueText(built.targetGuid), valueText(built.prepared.targetSource)))
        elseif changed and built.state == "BLOCKED" then
            for _, blocked in ipairs(built.blocked) do
                debug("BLOCK", string.format("slot=%d type=%s expected=%s reason=%s", built.inventorySlot,
                    blocked.type, valueText(blocked.expected), blocked.reason or "unavailable"))
            end
            if #built.blocked == 0 then debug("BLOCK", string.format("slot=%d reason=%s", built.inventorySlot,
                built.reason or "unavailable")) end
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
    if not button or InCombatLockdown() then return end
    local controller = self.controllers[position]
    local operation = controller and controller.state == "READY" and controller.prepared
    local actionType = operation and operation.type ~= "GEM" and (operation.type == "TINKER" and "macro" or "item") or nil
    local macroText = actionType == "macro" and tinkerMacro(operation) or nil
    button:SetAttribute("wsgs-type1", actionType)
    button:SetAttribute("type1", actionType)
    button:SetAttribute("item1", actionType == "item" and operation.material
        and string.format("%d %d", operation.material.bag, operation.material.slot) or nil)
    button:SetAttribute("spell1", nil)
    button:SetAttribute("macrotext1", macroText)
    button:SetAttribute("target-slot1", actionType and controller.inventorySlot or nil)
end

function Actions:DoTinkerRecipe(recipeID)
    local controller, operation
    for _, candidate in pairs(self.controllers) do
        local submitting = candidate.submitting
        if submitting and submitting.type == "TINKER" and submitting.spellID == recipeID then
            controller, operation = candidate, submitting
            break
        end
    end
    if not operation then return end
    local professionName = GetTradeSkillLine()
    if professionName ~= operation.professionName then
        controller.failure = "Engineering recipe data did not open during the secure click"
        debug("BLOCK", string.format("slot=%d type=TINKER recipe=%d profession=%s reason=%s",
            controller.inventorySlot, recipeID, valueText(professionName), controller.failure))
        return
    end
    ExpandTradeSkillSubClass(0)
    local recipeIndex
    for index = 1, GetNumTradeSkills() do
        if recipeIDFromLink(GetTradeSkillRecipeLink(index)) == recipeID then
            recipeIndex = index
            break
        end
    end
    if not recipeIndex then
        controller.failure = "Engineering recipe is hidden or unavailable in the profession list"
        debug("BLOCK", string.format("slot=%d type=TINKER recipe=%d reason=%s",
            controller.inventorySlot, recipeID, controller.failure))
        return
    end
    debug("EXEC", string.format("slot=%d type=TINKER api=DoTradeSkill recipe=%d recipeIndex=%d",
        controller.inventorySlot, recipeID, recipeIndex))
    local ok, problem = pcall(DoTradeSkill, recipeIndex, 1)
    local targeting = SpellCanTargetItem() or SpellCanTargetItemID()
    debug("EXEC", string.format("slot=%d type=TINKER api=DoTradeSkill returned=%s targeting=%s",
        controller.inventorySlot, ok and "ok" or "error", targeting and "item" or "none"))
    if not ok then
        controller.failure = "DoTradeSkill failed: " .. tostring(problem)
    elseif not targeting then
        controller.failure = "DoTradeSkill did not begin item targeting"
    end
end

_G.WoWSimGearSync_DoTinker = function(recipeID)
    Actions:DoTinkerRecipe(recipeID)
end

function Actions:Rescan(reason)
    local profile = WSGS:GetActiveSimulationProfile()
    if not profile then return end
    local snapshot = WSGS.EquipmentScanner:Scan()
    local comparison = WSGS.EquipmentComparator:Compare(profile, snapshot)
    if comparison then self:Refresh(profile, snapshot, comparison, reason) end
    if self.refreshView then self.refreshView() end
end

function Actions:ScheduleTimeout(controller)
    if controller.timeoutScheduled then return end
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
    debug("EXEC", string.format("slot=%d type=%s submitted serial=%d; awaiting events",
        controller.inventorySlot, operation.type, controller.serial))
    if not waitForSocketAccept then self:ScheduleTimeout(controller) end
end

function Actions:Fail(controller, operation, reason)
    controller.state, controller.reason, controller.lastFailed = "BLOCKED", reason, operation
    controller.pending, controller.submitting = nil, nil
    debug("BLOCK", string.format("slot=%d type=%s reason=%s", controller.inventorySlot, operation.type, reason))
    if self.refreshView then self.refreshView() end
end

function Actions:PreClick(position, button)
    button.secureSubmission = nil
    local controller = self.controllers[position]
    if not controller then return end
    if controller.state == "BLOCKED" and controller.lastFailed then
        controller.lastFailed = nil
        self:Rescan("RETRY_CLICK")
        controller = self.controllers[position]
    end
    if controller.state ~= "READY" or not controller.prepared then return end
    local operation = controller.prepared
    if InCombatLockdown() then return self:Fail(controller, operation, "Action unavailable during combat lockdown") end
    if CursorHasItem() then return self:Fail(controller, operation, "Place the held cursor item first") end
    for otherPosition, other in pairs(self.controllers) do
        if otherPosition ~= position and operation.type == "GEM"
            and other.pending and other.pending.type == "GEM" then
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
    if IsInventoryItemLocked(controller.inventorySlot) then return self:Fail(controller, operation, "Target item is locked") end
    debug("EXEC", string.format("slot=%d type=%s material=%s materialGuid=%s spell=%s spellName=%s guid=%s phase=%s",
        controller.inventorySlot, operation.type, valueText(operation.materialItemID),
        valueText(operation.material and operation.material.guid), valueText(operation.spellID),
        valueText(operation.spellName), valueText(controller.targetGuid),
        operation.type == "GEM" and "socket" or "secure"))

    if operation.type == "GEM" then
        local ok, problem = pcall(SocketInventoryItem, controller.inventorySlot)
        if not ok then return self:Fail(controller, operation, "SocketInventoryItem failed: " .. tostring(problem)) end
        self:MarkPending(controller, operation, true)
        controller.reason = string.format("Use Blizzard Socketing: place item %d in socket %d, then apply", operation.materialItemID, operation.socket)
        if self.refreshView then self.refreshView() end
    else
        if operation.type ~= "TINKER" then
            local material = operation.material
            if not material then return self:Fail(controller, operation, "Prepared material location is unavailable") end
            local current = C_Container.GetContainerItemInfo(material.bag, material.slot)
            if not current or current.itemID ~= material.itemID or current.isLocked then
                return self:Fail(controller, operation, "Prepared material moved or became locked")
            end
            local guidOK, currentGuid = pcall(C_Item.GetItemGUID,
                ItemLocation:CreateFromBagAndSlot(material.bag, material.slot))
            if material.guid and (not guidOK or currentGuid ~= material.guid) then
                return self:Fail(controller, operation, "Prepared material instance moved; rescan before retrying")
            end
        end
        self:ConfigureButton(position)
        local expectedType = operation.type == "TINKER" and "macro" or "item"
        local expectedItem = operation.material
            and string.format("%d %d", operation.material.bag, operation.material.slot) or nil
        local expectedMacro = expectedType == "macro" and tinkerMacro(operation) or nil
        if button:GetAttribute("type1") ~= expectedType
            or button:GetAttribute("target-slot1") ~= controller.inventorySlot
            or expectedType == "item" and button:GetAttribute("item1") ~= expectedItem
            or expectedType == "macro" and button:GetAttribute("macrotext1") ~= expectedMacro then
            return self:Fail(controller, operation, "Secure action could not be prepared")
        end
        controller.submitting = operation
        button.secureSubmission = { controller = controller, operation = operation }
        debug("EXEC", string.format("slot=%d type=%s api=SecureActionButton:%s action=%s target-slot=%d",
            controller.inventorySlot, operation.type, expectedType,
            expectedType == "macro" and valueText(operation.spellName) or valueText(expectedItem),
            controller.inventorySlot))
    end
end

function Actions:PostClick(position, button)
    local submission = button.secureSubmission
    button.secureSubmission = nil
    if not submission then return end
    local controller, operation = submission.controller, submission.operation
    if controller.failure then
        return self:Fail(controller, operation, controller.failure)
    end
    self:MarkPending(controller, operation)
    self:ConfigureButton(position)
    if self.refreshView then self.refreshView() end
end

function Actions:TooltipLines(position)
    local controller = self.controllers[position]
    if not controller then return {} end
    local color = colors[controller.state] or "ffffff"
    local lines = { " ", "|cff" .. color .. "Action: " .. controller.state:gsub("_", " ") .. "|r" }
    local operation = controller.prepared or controller.pending or controller.blocked[1]
    if operation then
        local text = "Next: " .. labels[operation.type]
        if operation.type == "GEM" then text = text .. string.format(" %d in socket %d", operation.expected, operation.socket)
        elseif operation.expected then text = text .. " " .. tostring(operation.expected) end
        if operation.targetSource == "RECOMMENDED" then text = text .. " (recommended)"
        elseif operation.targetSource == "SIMULATION" then text = text .. " (simulation target)" end
        lines[#lines + 1] = text
        if operation.material then
            lines[#lines + 1] = string.format("Material: item %d at bag %d, slot %d", operation.material.itemID,
                operation.material.bag, operation.material.slot)
        elseif operation.spellID then
            lines[#lines + 1] = string.format("Recipe: %s (%d)", operation.spellName or "unavailable", operation.spellID)
        end
    end
    if controller.reason then lines[#lines + 1] = controller.reason end
    return lines
end

function Actions:ClickText(position)
    local controller = self.controllers[position]
    if not controller or controller.state == "WAITING_FOR_ITEM" then return nil end
    local operation = controller.prepared or controller.pending or controller.lastFailed or controller.blocked[1]
    local action = operation and labels[operation.type]
    if controller.state == "READY" and action then return "Click to apply " .. action end
    if controller.state == "PENDING" and action then return "Applying " .. action .. "..." end
    if controller.state == "BLOCKED" and controller.lastFailed and action then return "Click to retry " .. action end
    if controller.state == "BLOCKED" and action then return "Cannot apply " .. action end
    return "No action needed"
end

function Actions:OnEvent(event, ...)
    local active, submitting
    for _, controller in pairs(self.controllers) do
        if controller.state == "PENDING" or controller.submitting then active = true end
        if controller.submitting then submitting = true end
    end
    if not active and not (self.isVisible and self.isVisible()) then return end
    if active and event:find("^SOCKET_INFO_") then
        local socketing
        for _, controller in pairs(self.controllers) do
            if controller.pending and controller.pending.type == "GEM" then socketing = true; break end
        end
        if not socketing then return end
    elseif active and event:find("^UNIT_SPELLCAST_") then
        local unit, _, spellID = ...
        if unit ~= "player" then return end
        local relevant
        for _, controller in pairs(self.controllers) do
            local operation = controller.pending or controller.submitting
            if operation and operation.spellID == spellID then relevant = true; break end
        end
        if not relevant then return end
    elseif active and event == "PLAYER_EQUIPMENT_CHANGED" then
        local inventorySlot = ...
        local relevant
        for _, controller in pairs(self.controllers) do
            if (controller.pending or controller.submitting) and controller.inventorySlot == inventorySlot then
                relevant = true; break
            end
        end
        if not relevant then return end
    end
    local args = {}
    for index = 1, select("#", ...) do args[index] = valueText(select(index, ...)) end
    if active then debug("EVENT", string.format("event=%s args=%s", event, table.concat(args, ","))) end
    if event == "REPLACE_ENCHANT" or event == "BIND_ENCHANT" or event == "ACTION_WILL_BIND_ITEM" then
        local controller, operation
        for _, candidate in pairs(self.controllers) do
            local candidateOperation = candidate.submitting
            if candidateOperation and candidateOperation.type ~= "GEM" then
                controller, operation = candidate, candidateOperation
                break
            end
        end
        if not operation then return end
        local api = event == "REPLACE_ENCHANT" and C_Item.ReplaceEnchant
            or event == "BIND_ENCHANT" and C_Item.BindEnchant or C_Item.ActionBindsItem
        local ok, problem = pcall(api)
        debug("EVENT", string.format("event=%s slot=%d type=%s confirm=%s", event,
            controller.inventorySlot, operation.type, ok and "accepted" or "failed"))
        if not ok then controller.failure = event .. " confirmation failed: " .. tostring(problem) end
        return
    elseif event == "SOCKET_INFO_FAILURE" then
        for _, controller in pairs(self.controllers) do
            if controller.pending and controller.pending.type == "GEM" then controller.failure = "Blizzard socketing reported failure" end
        end
    elseif event == "SOCKET_INFO_ACCEPT" then
        for _, controller in pairs(self.controllers) do
            if controller.pending and controller.pending.type == "GEM" then self:ScheduleTimeout(controller) end
        end
    elseif event == "SOCKET_INFO_CLOSE" then
        for _, controller in pairs(self.controllers) do
            if controller.pending and controller.pending.type == "GEM" and not controller.timeoutScheduled then
                controller.failure = "Blizzard Socketing closed before the change was submitted"
            end
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, _, spellID = ...
        if unit == "player" then
            for _, controller in pairs(self.controllers) do
                local operation = controller.pending or controller.submitting
                if operation and operation.spellID == spellID then
                    controller.failure = "Client spell cast failed or was interrupted"
                end
            end
        end
    end
    if submitting then return end
    self:Rescan(event)
end

function Actions:Initialize()
    self.planSignatures = {}
    local frame = CreateFrame("Frame")
    self.frame = frame
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
        "SOCKET_INFO_UPDATE", "SOCKET_INFO_ACCEPT", "SOCKET_INFO_SUCCESS", "SOCKET_INFO_FAILURE", "SOCKET_INFO_CLOSE",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
        "REPLACE_ENCHANT", "BIND_ENCHANT", "ACTION_WILL_BIND_ITEM",
        "PLAYER_REGEN_ENABLED" }) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)
end
