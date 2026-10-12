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

function Actions:Begin(operation, snapshot, now)
    self.pending = { operation = operation, deadline = now + 4,
        beforeId = snapshot.slots[operation.position].id,
        beforeGUID = snapshot.slots[operation.position].guid }
    self.nextClickAt, self.state = now + 0.4, "PENDING"
    return self.pending
end

-- Pure state transition used by live events and deterministic in-game tests.
-- No equipment APIs, character DB writes, callbacks, or actions are issued here.
function Actions:Reconcile(profile, snapshot, bags, combat, now, event)
    local outcome
    if self.pending then
        local pending, operation = self.pending, self.pending.operation
        if verificationEvents[event] and self:Verify(operation, snapshot, bags) then
            self.pending, self.completedClick, outcome = nil, true, "VERIFIED"
        elseif now >= pending.deadline then
            self.pending = nil
            self.fault = pending.error or "Equipment change could not be verified. Click to rescan; no automatic retry."
            outcome = "FAILED"
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            local destination = snapshot.slots[operation.position]
            if destination.id and destination.id ~= pending.beforeId and destination.id ~= operation.id then
                self.pending, self.fault, outcome = nil, "Unexpected equipment change; click to rescan.", "FAILED"
            elseif operation.source.guid and destination.id == operation.id and destination.guid
                and destination.guid ~= operation.source.guid and destination.guid ~= pending.beforeGUID then
                self.pending, self.fault, outcome = nil, "A different item instance was equipped; click to rescan.", "FAILED"
            end
        end
    end
    self.plan = WSGS.EquipmentPlanner:Plan(profile, snapshot, bags)
    if self.pending then self.state = "PENDING"
    elseif combat then self.state = "COMBAT"
    elseif self.fault then self.state = "FAULT"
    elseif now < (self.nextClickAt or 0) then self.state = "COOLDOWN"
    elseif #self.plan.operations > 0 then self.state = self.completedClick and "NEXT" or "READY"
    elseif #self.plan.blocked > 0 then self.state = "BLOCKED"
    else self.state = "COMPLETE" end
    return outcome
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
    local pending = self.pending
    local outcome = self:Reconcile(profile, snapshot, bags,
        InCombatLockdown() or UnitAffectingCombat("player"), GetTime(), self.verificationEvent)
    self.verificationEvent = nil
    self.snapshot = snapshot
    if not self.pending and GetCursorInfo() and self.state ~= "COMBAT" and self.state ~= "FAULT" then
        self.state = "CURSOR"
    end
    if outcome == "VERIFIED" then
        WSGS:Debug("[EQUIP] Verified: item " .. pending.operation.id ..
            (pending.operation.kind == "UNEQUIP" and " stored in bags" or " equipped"))
        WSGS:Debug("[EQUIP] Remaining: " .. #self.plan.operations .. " operations")
    elseif outcome == "FAILED" then WSGS:Print("[EQUIP] " .. self.fault) end
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
        elseif self.pending then self:Refresh(WSGS:GetActiveSimulationProfile()) end
    end)
end

function Actions:Initialize()
    local listener = CreateFrame("Frame")
    self.listener = listener
    for _, event in ipairs(self.events) do listener:RegisterEvent(event) end
    listener:SetScript("OnEvent", function(_, event, _, message)
        if event == "UI_ERROR_MESSAGE" then
            if self.pending then self.pending.error = type(message) == "string" and message or "Client rejected the operation." end
            return
        end
        if self.pending or self.isVisible and self.isVisible() then self:QueueRefresh(event) end
    end)
end

function Actions:Click()
    -- Double clicks cannot submit a second operation while one is pending.
    if self.pending or GetTime() < (self.nextClickAt or 0) then return end
    if self.fault then
        self.fault = nil
        self:Refresh(WSGS:GetActiveSimulationProfile())
        WSGS:Print("[EQUIP] Rescanned. Review the plan and click again to equip.")
        return
    end
    self:Refresh(WSGS:GetActiveSimulationProfile())
    if self.state ~= "READY" and self.state ~= "NEXT" then
        WSGS:Print("[EQUIP] " .. (self.state == "COMBAT" and "Cannot equip in combat." or self.plan.blocked[1] or "No available equipment changes."))
        return
    end
    if GetCursorInfo() then WSGS:Print("[EQUIP] Place the held cursor item first."); return end
    local operation = self.plan.operations[1]
    for _, missing in ipairs(self.plan.missing) do
        WSGS:Debug("[EQUIP] Missing: item " .. missing.id .. " for " .. WSGS.equipmentSlots[missing.position].name)
    end
    WSGS:Debug("[EQUIP] Planned: " .. #self.plan.operations .. " operations")
    if operation.source.bag ~= nil then
        WSGS:Debug("[EQUIP] Target found: item " .. operation.id .. " in bag " .. operation.source.bag .. " slot " .. operation.source.bagSlot)
    end
    local pending = self:Begin(operation, self.snapshot, GetTime())
    if self.stateChanged then self.stateChanged() end
    WSGS:Debug("[EQUIP] Attempting: inventory slot " .. operation.slotId)
    local ok, submitted, reason = pcall(WSGS.EquipmentExecution.Perform, WSGS.EquipmentExecution, operation)
    if not ok or not submitted then
        pending.error = ok and reason or tostring(submitted)
        WSGS:Print("[EQUIP] " .. pending.error)
    end
    -- Single-shot observation/debounce deadlines. Neither callback equips.
    C_Timer.After(0.4, function() self:QueueRefresh("DEBOUNCE") end)
    C_Timer.After(4, function()
        if self.pending == pending then
            if self.isVisible and self.isVisible() then self.refreshView()
            else self:Refresh(WSGS:GetActiveSimulationProfile()) end
        end
    end)
end
