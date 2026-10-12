local _, WSGS = ...
local Actions = { controllers = {}, serial = 0 }
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

function Actions:Refresh(profile, snapshot, comparison)
    if not profile or not snapshot or not comparison then
        self.controllers = {}
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
                debug("VERIFY", string.format("slot=%d type=%s expected=%s result=STILL_PENDING reason=%s",
                    previous.inventorySlot, previous.pending.type, valueText(previous.pending.expected), detail))
            end
        elseif previous and previous.continuation then
            if previous.targetGuid ~= built.targetGuid then
                built.state, built.lastFailed = "BLOCKED", previous.continuation
                built.reason = "Target item instance changed before the prepared action was applied"
            elseif previous.failure then
                built.state, built.lastFailed = "BLOCKED", previous.continuation
                built.reason = previous.failure
            else
                built.state, built.continuation = "READY", previous.continuation
                built.prepared = previous.continuation
                built.reason = "Click again to apply the prepared action to this equipped item"
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
            debug("READY", string.format("slot=%d type=%s material=%s materialGuid=%s spell=%s guid=%s source=%s",
                built.inventorySlot, built.prepared.type, valueText(built.prepared.materialItemID),
                valueText(built.prepared.material and built.prepared.material.guid), valueText(built.prepared.spellID),
                valueText(built.targetGuid), valueText(built.prepared.targetSource)))
        elseif changed and built.state == "BLOCKED" then
            for _, blocked in ipairs(built.blocked) do
                debug("BLOCK", string.format("slot=%d type=%s expected=%s reason=%s", built.inventorySlot,
                    blocked.type, valueText(blocked.expected), blocked.reason or "unavailable"))
            end
            if #built.blocked == 0 then debug("BLOCK", string.format("slot=%d reason=%s", built.inventorySlot,
                built.reason or "unavailable")) end
        end
    end
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
    controller.state, controller.pending, controller.continuation = "PENDING", operation, nil
    controller.startedAt, controller.serial = GetTime(), self.serial
    debug("EXEC", string.format("slot=%d type=%s submitted serial=%d; awaiting events",
        controller.inventorySlot, operation.type, controller.serial))
    if not waitForSocketAccept then self:ScheduleTimeout(controller) end
end

function Actions:Fail(controller, operation, reason)
    controller.state, controller.reason, controller.lastFailed = "BLOCKED", reason, operation
    controller.pending, controller.continuation = nil, nil
    debug("BLOCK", string.format("slot=%d type=%s reason=%s", controller.inventorySlot, operation.type, reason))
    if self.refreshView then self.refreshView() end
end

function Actions:Click(position)
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
        if otherPosition ~= position and other.continuation then
            return self:Fail(controller, operation, "Finish the prepared action on another slot first")
        end
        if otherPosition ~= position and operation.type == "GEM"
            and other.pending and other.pending.type == "GEM" then
            return self:Fail(controller, operation, "Finish the active Blizzard Socketing interaction first")
        end
    end
    if not controller.continuation and SpellIsTargeting() then
        return self:Fail(controller, operation, "Finish or cancel the active item-targeting cursor first")
    end
    local id = GetInventoryItemID("player", controller.inventorySlot)
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromEquipmentSlot(controller.inventorySlot))
    if id ~= controller.target.id or not ok or guid ~= controller.targetGuid then
        return self:Fail(controller, operation, "The equipped target item or instance changed; rescan before retrying")
    end
    if IsInventoryItemLocked(controller.inventorySlot) then return self:Fail(controller, operation, "Target item is locked") end
    debug("EXEC", string.format("slot=%d type=%s material=%s materialGuid=%s spell=%s guid=%s phase=%s",
        controller.inventorySlot, operation.type, valueText(operation.materialItemID),
        valueText(operation.material and operation.material.guid), valueText(operation.spellID), valueText(controller.targetGuid),
        controller.continuation and "target" or "prepare"))

    if controller.continuation then
        if not SpellIsTargeting() then return self:Fail(controller, operation, "Client item-targeting cursor is no longer active") end
        local ok, problem = pcall(UseInventoryItem, controller.inventorySlot)
        if not ok then return self:Fail(controller, operation, "UseInventoryItem failed: " .. tostring(problem)) end
        self:MarkPending(controller, operation)
    elseif operation.type == "GEM" then
        local ok, problem = pcall(SocketInventoryItem, controller.inventorySlot)
        if not ok then return self:Fail(controller, operation, "SocketInventoryItem failed: " .. tostring(problem)) end
        self:MarkPending(controller, operation, true)
        controller.reason = string.format("Use Blizzard Socketing: place item %d in socket %d, then apply", operation.materialItemID, operation.socket)
    elseif operation.type == "TINKER" then
        local ok, problem = pcall(CastSpellByID, operation.spellID)
        if not ok then return self:Fail(controller, operation, "CastSpellByID failed: " .. tostring(problem)) end
        controller.continuation, controller.state = operation, "READY"
        controller.reason = "Click this slot again while the item-targeting cursor is active"
    else
        local material = operation.material
        if not material then return self:Fail(controller, operation, "Prepared material location is unavailable") end
        local current = C_Container.GetContainerItemInfo(material.bag, material.slot)
        if not current or current.itemID ~= material.itemID or current.isLocked then
            return self:Fail(controller, operation, "Prepared material moved or became locked")
        end
        local ok, problem = pcall(C_Container.UseContainerItem, material.bag, material.slot)
        if not ok then return self:Fail(controller, operation, "UseContainerItem failed: " .. tostring(problem)) end
        controller.continuation, controller.state = operation, "READY"
        controller.reason = "Click this slot again while the item-targeting cursor is active"
    end
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
        elseif operation.spellID then lines[#lines + 1] = "Spell: " .. operation.spellID end
    end
    if controller.reason then lines[#lines + 1] = controller.reason end
    return lines
end

function Actions:OnEvent(event, ...)
    local active
    for _, controller in pairs(self.controllers) do
        if controller.state == "PENDING" or controller.continuation then active = true; break end
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
            local operation = controller.pending or controller.continuation
            if operation and operation.spellID == spellID then relevant = true; break end
        end
        if not relevant then return end
    elseif active and event == "PLAYER_EQUIPMENT_CHANGED" then
        local inventorySlot = ...
        local relevant
        for _, controller in pairs(self.controllers) do
            if (controller.pending or controller.continuation) and controller.inventorySlot == inventorySlot then
                relevant = true; break
            end
        end
        if not relevant then return end
    end
    local args = {}
    for index = 1, select("#", ...) do args[index] = valueText(select(index, ...)) end
    if active then debug("EVENT", string.format("event=%s args=%s", event, table.concat(args, ","))) end
    if event == "SOCKET_INFO_FAILURE" then
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
                local operation = controller.pending or controller.continuation
                if operation and operation.spellID == spellID then
                    controller.failure = "Client spell cast failed or was interrupted"
                end
            end
        end
    end
    self:Rescan(event)
end

function Actions:Initialize()
    self.planSignatures = {}
    local frame = CreateFrame("Frame")
    self.frame = frame
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
        "SOCKET_INFO_UPDATE", "SOCKET_INFO_ACCEPT", "SOCKET_INFO_SUCCESS", "SOCKET_INFO_FAILURE", "SOCKET_INFO_CLOSE",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "PLAYER_REGEN_ENABLED" }) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)
end
