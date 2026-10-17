local _, WSGS = ...
local Gems = WSGS:NewModule("GemSocketing", "AceEvent-3.0")
local Internal = WSGS.ActionsInternal
Internal.GemExecution = Gems
local Equipment = WSGS:GetModule("Equipment")

-- One socket window, one batch. Equipment State owns planning observations;
-- this module owns proposals, native confirmations, and commit verification.
local function log(kind, entry, operation, event, detail, observed)
    WSGS:Debug(string.format(
        "[GEM][%s] item=%s slot=%s guid=%s socket=%s desired=%s observed=%s event=%s %s",
        kind, tostring(entry and entry.itemID), tostring(entry and entry.inventorySlot),
        tostring(entry and entry.guid), tostring(operation and operation.socket),
        tostring(operation and operation.expected), tostring(observed), tostring(event), detail or ""))
end

local function sameInstance(entry)
    if GetInventoryItemID("player", entry.inventorySlot) ~= entry.itemID then
        return false
    end
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromEquipmentSlot(entry.inventorySlot))
    return not entry.guid or ok and guid == entry.guid
end

function Gems:Publish(reason)
    local build = WSGS:GetActiveSimulationProfile()
    local state = build and Equipment:RefreshState(build, "GemSocketing:" .. reason)
    if WSGS.Actions then
        WSGS.Actions:Refresh(state)
        self:SendMessage("WSGS_ACTIONS_CHANGED", reason)
    end
    return state
end

function Gems:CloseWindow()
    self.closing = true
    pcall(C_ItemSocketInfo.CloseSocketInfo)
    if ItemSocketingFrame and ItemSocketingFrame:IsShown() then
        HideUIPanel(ItemSocketingFrame)
    end
    self.closing = nil
end

function Gems:ReturnCursor()
    if self.cursorGem then
        local kind, id = GetCursorInfo()
        if kind == "item" and id == self.cursorGem then
            ClearCursor()
        end
        self.cursorGem = nil
    end
end

function Gems:Stop(reason, event)
    local batch = self.batch
    if not batch then
        return
    end
    local entry = batch.current
    if reason then
        log("BLOCK", entry, entry and entry.pending, event, reason)
    end
    self.batch = nil
    self:ReturnCursor()
    self:CloseWindow()
    -- Blizzard can handle the same SOCKET_INFO_UPDATE after us and show the
    -- frame again. Finish UI cleanup once that event dispatch has returned.
    -- A newer socket interaction invalidates this cleanup, even outside WSGS.
    local windowGeneration = self.windowGeneration
    C_Timer.After(0, function()
        if not self.batch and self.windowGeneration == windowGeneration then
            self:CloseWindow()
        end
    end)
    self:Publish(event or "FINISHED")
    if reason and entry and WSGS.Actions and WSGS:GetActiveSimulationProfile() == batch.build then
        WSGS.Actions:GemSocketingFailed(entry.position, entry.pending or entry.operations[1], reason)
    end
end

function Gems:Watch(entry, phase)
    -- Diagnostic/cancellation deadline only. Never submit or retry from a timer.
    entry.watch = (entry.watch or 0) + 1
    local watch = entry.watch
    C_Timer.After(10, function()
        if self.batch and self.batch.current == entry and entry.phase == phase and entry.watch == watch then
            self:Stop("Socketing did not finish; recheck the item before retrying", "TIMEOUT")
        end
    end)
end

local function materialFor(state, operation, used)
    for _, location in ipairs(state.bagItemsById[operation.expected] or {}) do
        local info = C_Container.GetContainerItemInfo(location.bag, location.bagSlot)
        local key = location.key
        if info and info.itemID == operation.expected and not info.isLocked and
            math.min((location.count or 1) - (used[key] or 0), info.stackCount or 1) > 0 then
            used[key] = (used[key] or 0) + 1
            return location
        end
    end
end

function Gems:Validate(entry, state)
    local slot = state and state.slots[entry.position]
    if not slot or not state.comparison or slot.physicalInventorySlot ~= entry.inventorySlot or
        slot.comparison.fields.item.state ~= "MATCH" or slot.target.id ~= entry.itemID or
        not sameInstance(entry) then
        return nil, "The equipped target item or instance changed"
    end
    return slot.comparison.fields.gems
end

function Gems:CheckProposals(entry)
    local count = C_ItemSocketInfo.GetNumSockets()
    for socket in pairs(entry.staged) do
        if socket > count then
            return false
        end
    end
    for socket = 1, count do
        local link = C_ItemSocketInfo.GetNewSocketLink(socket)
        local decoded = WSGS.ItemLinkDecoder:Decode(link)
        if link and not decoded then
            return false
        end
        local proposed = decoded and decoded.id
        local expected = entry.staged[socket]
        if proposed ~= expected then
            return false
        end
    end
    return true
end

function Gems:Stage(entry)
    local state = self:Publish("STAGE_RECHECK")
    local field, problem = self:Validate(entry, state)
    if not field then
        return self:Stop(problem, "STAGE_RECHECK")
    end
    if CursorHasItem() or SpellIsTargeting() or InCombatLockdown() then
        return self:Stop("Finish the active cursor or combat interaction first", "STAGE_RECHECK")
    end
    local used = {}
    entry.staged, entry.phase = {}, "STAGING"
    for socket = 1, C_ItemSocketInfo.GetNumSockets() do
        if C_ItemSocketInfo.GetNewSocketLink(socket) then
            return self:Stop("The socket window already contains another proposal", "STAGE_RECHECK")
        end
    end
    for _, operation in ipairs(entry.operations) do
        entry.pending = operation
        local difference = field.sockets and field.sockets[operation.socket]
        local existingLink = C_ItemSocketInfo.GetExistingSocketLink(operation.socket)
        local decoded = WSGS.ItemLinkDecoder:Decode(existingLink)
        local existing = decoded and decoded.id or not existingLink and 0 or nil
        -- SocketInventoryItem locks its equipped item for the owned session.
        -- The pre-open lock check rejects unrelated locks; identity remains
        -- authoritative while we stage proposals in this window.
        if not sameInstance(entry) then
            return self:Stop("The equipped target item or instance changed", "STAGE")
        end
        if difference and difference.state == "MISMATCH" and difference.expected == operation.expected and
            operation.socket <= C_ItemSocketInfo.GetNumSockets() and existing == difference.actual then
            local material = materialFor(state, operation, used)
            if material then
                self.cursorGem = operation.expected
                C_Container.PickupContainerItem(material.bag, material.bagSlot)
                if not self.batch then
                    return
                end
                local kind, id = GetCursorInfo()
                if kind ~= "item" or id ~= operation.expected then
                    return self:Stop("The required gem could not be picked up", "STAGE")
                end
                C_ItemSocketInfo.ClickSocketButton(operation.socket)
                self:ReturnCursor()
                if not self.batch then
                    return
                end
                local proposedItem = WSGS.ItemLinkDecoder:Decode(C_ItemSocketInfo.GetNewSocketLink(operation.socket))
                local proposed = proposedItem and proposedItem.id
                if proposed ~= operation.expected or CursorHasItem() then
                    return self:Stop("The socket did not accept the required gem", "STAGE")
                end
                entry.staged[operation.socket] = operation.expected
                log("STAGE", entry, operation, "SOCKET_INFO_UPDATE", "result=proposed", proposed)
            else
                log("BLOCK", entry, operation, "STAGE", "reason=gem-missing-or-locked", difference.actual)
            end
        elseif not difference or difference.state ~= "MATCH" then
            log("BLOCK", entry, operation, "STAGE", "reason=socket-unavailable-or-unresolved", existing)
        end
    end
    if not next(entry.staged) then
        return self:NextItem("NO_AVAILABLE_GEMS")
    end
    if not self:CheckProposals(entry) or not sameInstance(entry) then
        return self:Stop("The socket proposals or target item changed", "COMMIT_RECHECK")
    end
    log("COMMIT", entry, entry.pending, "STAGED", "result=ready")
    entry.phase = "COMMITTING"
    self:Watch(entry, "COMMITTING")
    if C_ItemSocketInfo.GetSocketItemBoundTradeable() and C_ItemSocketInfo.HasBoundGemProposed() then
        C_Item.EndBoundTradeable("gem")
    else
        C_ItemSocketInfo.AcceptSockets()
    end
end

function Gems:NextItem(event)
    local batch = self.batch
    local previous = batch.current
    self:CloseWindow()
    -- A committed pass may release a stack that could not be staged twice.
    -- Replan only after verification; never resubmit a committed mismatch.
    if previous and previous.phase == "VERIFIED" and not previous.closed then
        local state = self:Publish("REMAINING_SOCKETS")
        local controller = Internal.Planner:Build(previous.position, state)
        local remaining = {}
        for _, operation in ipairs(controller.operations) do
            if operation.type == "GEM" and previous.targets[operation.socket] == operation.expected then
                remaining[#remaining + 1] = operation
            end
        end
        if #remaining > 0 and sameInstance(previous) then
            previous.operations = remaining
            previous.ready, previous.committed, previous.success = nil, nil, nil
            previous.confirmations, previous.confirmationPending = nil, nil
            previous.verification = {}
            return self:OpenItem(previous, event)
        end
    elseif previous and previous.closed then
        return self:Stop(nil, "CLOSED_AFTER_COMMIT")
    end
    batch.index = batch.index + 1
    local entry = batch.entries[batch.index]
    batch.current = entry
    if not entry then
        return self:Stop(nil, "BATCH_FINISHED")
    end
    self:OpenItem(entry, event)
end

function Gems:OpenItem(entry, event)
    local state = self:Publish("ITEM_RECHECK")
    local field = self:Validate(entry, state)
    if not field or not sameInstance(entry) or IsInventoryItemLocked(entry.inventorySlot) then
        log("BLOCK", entry, entry.operations[1], event, "reason=item-changed-or-locked")
        entry.phase = "SKIPPED"
        return self:NextItem("SKIPPED_ITEM")
    end
    if CursorHasItem() or SpellIsTargeting() or InCombatLockdown() then
        return self:Stop("Finish the active cursor or combat interaction first", event)
    end
    entry.phase = "OPENING"
    self:Watch(entry, "OPENING")
    self.opening = true
    local ok, problem = pcall(SocketInventoryItem, entry.inventorySlot)
    self.opening = nil
    if not ok then
        log("BLOCK", entry, entry.operations[1], event, "api=SocketInventoryItem error=" .. tostring(problem))
        return self:Stop("The item socket window could not be opened", event)
    end
end

function Gems:Step(event)
    local batch, entry = self.batch, self.batch.current
    if WSGS:GetActiveSimulationProfile() ~= batch.build then
        return self:Stop("The managed build changed", event)
    end
    if entry.error then
        return self:Stop(entry.error, event)
    end
    if not sameInstance(entry) then
        return self:Stop("The equipped target item or instance changed", event)
    end
    if entry.phase == "OPENING" and entry.ready then
        return self:Stage(entry)
    elseif entry.phase == "COMMITTING" and entry.confirmationPending then
        entry.confirmationPending = nil
        C_ItemSocketInfo.CompleteSocketing()
    elseif entry.phase == "VERIFYING" then
        local state = self:Publish("VERIFY")
        local field, problem = self:Validate(entry, state)
        if not field then
            return self:Stop(problem, event)
        end
        local verified = true
        for socket, expected in pairs(entry.staged) do
            local difference = field.sockets and field.sockets[socket]
            local matched = difference and difference.expected == expected and difference.state == "MATCH"
            verified = verified and matched
            local observed = difference and difference.actual
            local status = tostring(difference and difference.state) .. ":" .. tostring(observed)
            if entry.verification[socket] ~= status then
                entry.verification[socket] = status
                log("VERIFY", entry, {socket = socket, expected = expected}, event,
                    matched and "result=matched" or "result=awaiting-observation", observed)
            end
        end
        -- The session lock can remain until CloseWindow in NextItem. Native
        -- success plus authoritative gem observations confirm this commit.
        if verified and entry.success then
            entry.phase = "VERIFIED"
            return self:NextItem(event)
        end
    end
end

function Gems:Drive(event)
    self.dirty = true
    self.event = event
    if self.busy then
        return
    end
    self.busy = true
    while self.batch and self.dirty do
        self.dirty = nil
        local ok, problem = pcall(self.Step, self, self.event)
        if not ok then
            log("BLOCK", self.batch and self.batch.current, nil, event, "error=" .. tostring(problem))
            self:Stop("Socketing could not continue; recheck the item before retrying", event)
        end
    end
    self.busy = nil
end

function Gems:Start(position)
    if self.batch then
        return false, "Finish or cancel the active socketing batch first"
    end
    local build = WSGS:GetActiveSimulationProfile()
    local state = build and Equipment:RefreshState(build, "GemSocketing:PLAN")
    if not state or not state.comparison then
        return false, "Equipment information is not available yet"
    end
    if CursorHasItem() or SpellIsTargeting() then
        return false, "Place the held cursor item or finish targeting first"
    end
    if ItemSocketingFrame and ItemSocketingFrame:IsShown() then
        return false, "Finish or close the existing socket window first"
    end
    local entries = {}
    local requested = {}
    local controller = Internal.Planner:Build(position, state)
    local entry = {position = position, itemID = controller.target.id,
        inventorySlot = controller.inventorySlot, guid = controller.targetGuid,
        operations = {}, verification = {}, targets = {}}
    for _, operation in ipairs(controller.blocked) do
        if operation.type == "GEM" then
            log("BLOCK", entry, operation, "PLAN", "reason=" .. operation.reason)
        end
    end
    for _, operation in ipairs(controller.unknown) do
        if operation.type == "GEM" then
            log("BLOCK", entry, operation, "PLAN", "reason=unresolved " .. operation.reason)
            local id = operation.expected or controller.target.id
            if id and id > 0 and not requested[id] then
                requested[id] = true
                Equipment:RequestItemData(id, "GemSocketing")
            end
        end
    end
    local operations = entry.operations
    for _, operation in ipairs(controller.operations) do
        if operation.type == "GEM" then
            operations[#operations + 1] = operation
            if not C_Item.GetItemInfo(operation.expected) and not requested[operation.expected] then
                requested[operation.expected] = true
                Equipment:RequestItemData(operation.expected, "GemSocketing")
            end
        end
    end
    if #operations > 0 then
        entries[#entries + 1] = entry
        for _, operation in ipairs(operations) do
            entry.targets[operation.socket] = operation.expected
            log("PLAN", entry, operation, "CLICK", "result=eligible",
                controller.difference.fields.gems.sockets[operation.socket].actual)
        end
    end
    if #entries == 0 then
        return false, "No available gem changes"
    end
    self.batch = {build = build, entries = entries, index = 0, origin = position}
    self.event = "CLICK"
    self.busy = true
    local ok, problem = pcall(self.NextItem, self, "CLICK")
    self.busy = nil
    if not ok then
        log("BLOCK", self.batch and self.batch.current, nil, "CLICK", "error=" .. tostring(problem))
        self:Stop("The item socket window could not be opened", "CLICK")
    end
    if self.batch then
        self:Drive(self.event or "CLICK")
        if self.batch then
            self:Publish("STARTED")
        end
    end
    return true
end

function Gems:GetSlotState(position)
    local batch = self.batch
    local entry = batch and batch.current
    if not entry or position ~= entry.position and position ~= batch.origin then
        return
    end
    local text = entry.phase == "VERIFYING" and "Verifying installed gems..." or "Socketing managed gems..."
    return {state = "PENDING", pending = true, clickText = text,
        nextField = "gems", nextType = "GEM", reason = text}
end

function Gems:OnSocketEvent(event)
    local entry = self.batch and self.batch.current
    if not entry or self.closing then
        return
    end
    if event == "SOCKET_INFO_FAILURE" then
        return self:Stop("Blizzard socketing reported failure", event)
    elseif event == "SOCKET_INFO_CLOSE" then
        if entry.phase ~= "VERIFYING" then
            return self:Stop("The socket window was closed; socketing cancelled", event)
        end
        entry.closed = true
    elseif event == "SOCKET_INFO_UPDATE" then
        if entry.phase == "OPENING" and self.opening then
            entry.ready = true
        end
    elseif event == "SOCKET_INFO_ACCEPT" or event == "SOCKET_INFO_SUCCESS" then
        if entry.phase ~= "COMMITTING" and entry.phase ~= "VERIFYING" then
            return self:Stop("The socket window changed unexpectedly", event)
        end
        if entry.phase ~= "VERIFYING" then
            entry.phase, entry.committed = "VERIFYING", true
            self:Watch(entry, "VERIFYING")
            log("COMMIT", entry, entry.pending, event, "result=accepted")
        end
        entry.success = entry.success or event == "SOCKET_INFO_SUCCESS"
    elseif event == "SOCKET_INFO_BIND_CONFIRM" or event == "SOCKET_INFO_REFUNDABLE_CONFIRM" then
        entry.confirmations = entry.confirmations or {}
        if entry.confirmations[event] then
            return self:Stop("Blizzard did not accept the socket confirmation", event)
        end
        entry.confirmations[event] = true
        entry.phase = "COMMITTING"
        entry.confirmationPending = true
        -- Blizzard may show its dialog later in this event's dispatch. Only
        -- dismiss that stale UI here; completion runs in the event handler.
        C_Timer.After(0, function()
            StaticPopup_Hide(event == "SOCKET_INFO_BIND_CONFIRM" and "BIND_SOCKET" or "REFUNDABLE_SOCKET")
        end)
    end
    self:Drive(event)
end

function Gems:OnDisable()
    self:Stop("Socketing stopped", "DISABLED")
end

function Gems:WSGS_EQUIPMENT_STATE_INVALIDATED(_, event)
    if self.batch and (event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" or
        event == "ITEM_LOCK_CHANGED" or event == "ITEM_DATA_LOAD_RESULT") then
        self:Drive(event)
    end
end

function Gems:WSGS_BUILD_IMPORTED()
    self:Stop("The managed build changed", "BUILD_IMPORTED")
end

function Gems:UI_ERROR_MESSAGE(event, _, message)
    local entry = self.batch and self.batch.current
    if entry and (self.busy or entry.phase == "COMMITTING") then
        entry.error = type(message) == "string" and message or "Blizzard could not complete socketing"
        self:Drive(event)
    end
end

function Gems:OnEnable()
    self:RegisterEvent("SOCKET_INFO_UPDATE", "OnSocketEvent")
    self:RegisterEvent("SOCKET_INFO_ACCEPT", "OnSocketEvent")
    self:RegisterEvent("SOCKET_INFO_SUCCESS", "OnSocketEvent")
    self:RegisterEvent("SOCKET_INFO_FAILURE", "OnSocketEvent")
    self:RegisterEvent("SOCKET_INFO_CLOSE", "OnSocketEvent")
    self:RegisterEvent("SOCKET_INFO_BIND_CONFIRM", "OnSocketEvent")
    self:RegisterEvent("SOCKET_INFO_REFUNDABLE_CONFIRM", "OnSocketEvent")
    self:RegisterEvent("UI_ERROR_MESSAGE")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_INVALIDATED")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    hooksecurefunc("SocketInventoryItem", function()
        self.windowGeneration = (self.windowGeneration or 0) + 1
        if self.batch and not self.opening then
            self:Stop("Another socket interaction replaced the active item", "SocketInventoryItem")
        end
    end)
    hooksecurefunc(C_Container, "SocketContainerItem", function()
        self.windowGeneration = (self.windowGeneration or 0) + 1
        if self.batch then
            self:Stop("Another socket interaction replaced the active item", "SocketContainerItem")
        end
    end)
end
