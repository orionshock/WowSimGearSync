local _, WSGS = ...
local Reforging = WSGS:NewModule("NPCReforging", "AceEvent-3.0")
local Equipment = WSGS:GetModule("Equipment")

local REFORGE_BASE, UNFORGE = 112, -1

local function debug(category, text)
    WSGS:Debug("[REFORGE][" .. category .. "] " .. text)
end
local function value(value)
    return value == nil and "nil" or tostring(value)
end

local function targetGuid(slot)
    local observed = slot and slot.current and slot.current.observations.instance
    return observed and observed.status == "KNOWN" and observed.value or nil
end

local function effectPair(effectID)
    local index = tonumber(effectID) and effectID - REFORGE_BASE or 0
    if index < 1 or index > 56 then
        return nil
    end
    local source = math.floor((index - 1) / 7) + 1
    local offset = ((index - 1) % 7) + 1
    local destination = offset >= source and offset + 1 or offset
    return source, destination
end

local function collect(state)
    local entries = {}
    if not state or not state.comparison then
        return entries
    end
    for position = 1, 16 do
        local slot = state.slots[position]
        local item = slot.comparison.fields.item
        local observed = slot.current and slot.current.observations.reforging
        if item.state == "MATCH" and observed and observed.status == "KNOWN" then
            local expected = tonumber(slot.target.reforging) or 0
            if observed.value ~= expected then
                entries[#entries + 1] = {
                    position = position,
                    inventorySlot = slot.physicalInventorySlot,
                    itemID = slot.target.id,
                    guid = targetGuid(slot),
                    expected = expected,
                    actual = observed.value,
                    name = WSGS.equipmentSlots[position].name
                }
            end
        end
    end
    return entries
end

function Reforging:GetRFL()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ReforgeLiteMopClassic")
    if not loaded then
        return nil, false
    end
    local addonTable = _G.ReforgeLiteMopClassic
    local rfl = type(addonTable) == "table" and addonTable.ReforgeLiteMopClassic or nil
    if not rfl or type(rfl.ValidateWoWSimsString) ~= "function" or
        type(rfl.ApplyWoWSimsImport) ~= "function" or type(rfl.DoReforge) ~= "function" or not rfl.pdb then
        return nil, true
    end
    return rfl, true
end

function Reforging:CreatePanel()
    if self.frame then
        return self.frame
    end
    local frame = WSGS.NPCPanel:Create("WSGSReforgingCompanion", "WowSimGearSync — Reforging")
    frame.action:SetScript("OnClick", function()
        self:Activate()
    end)
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", 2, 2)
    frame.close:SetScript("OnClick", function()
        self.dismissed = true
        frame:Hide()
    end)
    self.frame = frame
    return frame
end

function Reforging:Refresh(reason)
    if not self.open or self.dismissed then
        return
    end
    local frame = self:CreatePanel()
    local owner = _G.ReforgingFrame
    if not owner or not owner:IsShown() or not WSGS.NPCPanel:Anchor(frame, owner) then
        frame:Hide()
        return
    end
    local build = WSGS:GetActiveSimulationProfile()
    local state = build and Equipment:GetState(build) or nil
    local entries = collect(state)
    self.entries = entries
    local rows = {}
    for index, entry in ipairs(entries) do
        rows[index] = string.format("%s   %s → %s", entry.name, entry.actual == 0 and "None" or entry.actual,
            entry.expected == 0 and "None" or entry.expected)
    end
    local rfl, rflActive = self:GetRFL()
    local mode = rfl and "Executor: ReforgeLite (exact WoW Sims import)" or
                     (rflActive and "Executor: ReforgeLite integration unavailable" or
                         "Executor: WowSimGearSync native")
    local status
    if not build then
        status = "Import a WoW Sims build first."
    elseif #entries == 0 then
        status = "All managed reforges are complete."
    elseif rflActive and not rfl then
        status = "ReforgeLite is loaded, but its exact-import interface is unavailable."
    elseif rfl and not build.sourceJSON then
        status = "This build predates source-JSON preservation; import it again."
    elseif self.rflRunning then
        status = "ReforgeLite owns the active transaction batch."
    elseif self.blocker then
        status = self.blocker
    else
        status = string.format("%d reforge%s remaining.", #entries, #entries == 1 and "" or "s")
    end
    if self.rflRunning and #entries == 0 then
        self.rflRunning = nil
    end
    local enabled = build ~= nil and #entries > 0 and not self.rflRunning and
                        (self.pending ~= nil or not self.running) and
                        (not rflActive or (rfl ~= nil and build.sourceJSON ~= nil))
    WSGS.NPCPanel:Render(frame, mode, rows, status, rfl and "Apply with ReforgeLite" or
        (self.started and "Continue" or "Apply All"), enabled)
    frame:Show()
    debug("PLAN", string.format("reason=%s executor=%s remaining=%d pending=%s", value(reason),
        rfl and "RFL" or "NATIVE", #entries, self.pending and self.pending.serial or "none"))
end

function Reforging:Handoff(rfl, build)
    local signature = build.id .. "\031" .. build.sourceJSON
    if self.rflSignature == signature and rfl.methodWindow then
        rfl:ShowMethodWindow(true)
        debug("RFL", string.format("build=%s action=use-existing-exact-queue", build.name))
    else
        rfl:Show()
        if type(rfl.UpdateItems) == "function" then
            rfl:UpdateItems()
        end
        local ok, valid, imported = pcall(rfl.ValidateWoWSimsString, rfl, build.sourceJSON)
        if not ok or not valid then
            self.blocker = "ReforgeLite rejected the exact WoW Sims import."
            debug("BLOCK", string.format("executor=RFL result=%s reason=%s", value(valid), value(imported)))
            self:Refresh("rfl-rejected")
            return
        end
        local applied, problem = pcall(rfl.ApplyWoWSimsImport, rfl, imported, true)
        if not applied then
            self.blocker = "ReforgeLite import handoff failed: " .. tostring(problem)
            debug("BLOCK", "executor=RFL reason=" .. tostring(problem))
            self:Refresh("rfl-error")
            return
        end
        self.rflSignature = signature
        debug("RFL", string.format("build=%s entry=ValidateWoWSimsString/ApplyWoWSimsImport result=queued",
            build.name))
    end
    if not rfl.methodWindow or not rfl.methodWindow.reforge or not rfl.methodWindow.reforge:IsEnabled() then
        self.blocker = "ReforgeLite prepared the exact queue, but its Apply control is unavailable."
        debug("BLOCK", "executor=RFL reason=apply-control-disabled")
        self:Refresh("rfl-apply-disabled")
        return
    end
    local started, problem = pcall(rfl.DoReforge, rfl)
    if not started then
        self.blocker = "ReforgeLite could not start its queue: " .. tostring(problem)
        debug("BLOCK", "executor=RFL reason=" .. tostring(problem))
    else
        self.rflRunning = true
        debug("RFL", string.format("build=%s action=DoReforge result=started owner=ReforgeLite", build.name))
    end
    self:Refresh("rfl-execute")
end

function Reforging:Select(entry)
    if CursorHasItem() then
        return nil, "Place the held cursor item first"
    end
    if IsInventoryItemLocked(entry.inventorySlot) then
        return nil, "Item is locked"
    end
    PickupInventoryItem(entry.inventorySlot)
    C_Reforge.SetReforgeFromCursorItem()
    ClearCursor()
    local current, itemID, _, _, _, cost = C_Reforge.GetReforgeItemInfo()
    if itemID ~= entry.itemID then
        return nil, "Reforge NPC selected a different item"
    end
    return current, cost
end

function Reforging:ResolveOption(effectID)
    local wantedSource, wantedDestination = effectPair(effectID)
    if not wantedSource then
        return nil, "Unsupported WoW Sims reforge ID " .. tostring(effectID)
    end
    for _, source in ipairs(C_Reforge.GetSourceReforgeStats() or {}) do
        if source.stat == wantedSource then
            for _, destination in ipairs(C_Reforge.GetDestinationReforgeStats(source.stat, source.statReduction) or {}) do
                if destination.stat == wantedDestination then
                    return destination.reforgeID
                end
            end
        end
    end
    return nil, "The requested stat conversion is invalid for this item"
end

function Reforging:SubmitNext()
    local _, rflActive = self:GetRFL()
    if not self.open or rflActive then
        self.running = false
        return
    end
    local build = WSGS:GetActiveSimulationProfile()
    local state = build and Equipment:RefreshState(build, "NativeReforgePlan") or nil
    local entries = collect(state)
    self.entries = entries
    local entry
    for _, candidate in ipairs(entries) do
        if not self.skipped or not self.skipped[candidate.position] then
            entry = candidate
            break
        end
    end
    if not entry then
        self.running = false
        if #entries == 0 then
            self.started = nil
        elseif not self.blocker then
            self.blocker = "No remaining reforge can be submitted safely."
        end
        self:Refresh("complete")
        return
    end
    local current, costOrReason = self:Select(entry)
    if current == nil then
        self.skipped = self.skipped or {}
        self.skipped[entry.position] = costOrReason
        self.blocker = self.blocker or costOrReason
        debug("BLOCK", string.format("slot=%d item=%d guid=%s reason=%s", entry.inventorySlot, entry.itemID,
            value(entry.guid), costOrReason))
        return self:SubmitNext()
    end
    local transaction, expected
    if current > UNFORGE and entry.actual ~= 0 then
        transaction, expected = UNFORGE, 0
    elseif entry.expected == 0 then
        transaction, expected = UNFORGE, 0
    else
        transaction, costOrReason = self:ResolveOption(entry.expected)
        expected = entry.expected
        if not transaction then
            self.skipped = self.skipped or {}
            self.skipped[entry.position] = costOrReason
            self.blocker = self.blocker or costOrReason
            debug("BLOCK", string.format("slot=%d item=%d expected=%d reason=%s", entry.inventorySlot,
                entry.itemID, entry.expected, costOrReason))
            return self:SubmitNext()
        end
    end
    local cost = select(6, C_Reforge.GetReforgeItemInfo()) or 0
    if transaction ~= UNFORGE and GetMoney() < cost then
        self.skipped = self.skipped or {}
        self.skipped[entry.position] = "Insufficient gold"
        self.blocker = self.blocker or "Insufficient gold for one or more reforges."
        debug("BLOCK", string.format("slot=%d item=%d cost=%d money=%d", entry.inventorySlot, entry.itemID,
            cost, GetMoney()))
        return self:SubmitNext()
    end
    self.serial = (self.serial or 0) + 1
    self.pending = {
        serial = self.serial,
        position = entry.position,
        inventorySlot = entry.inventorySlot,
        itemID = entry.itemID,
        guid = entry.guid,
        expected = expected,
        finalTarget = entry.expected
    }
    debug("EXEC", string.format("serial=%d slot=%d item=%d guid=%s transaction=%d expected=%d cost=%d",
        self.serial, entry.inventorySlot, entry.itemID, value(entry.guid), transaction, expected, cost))
    local submitted, problem = pcall(C_Reforge.ReforgeItem, transaction)
    if not submitted then
        self.pending = nil
        self.running = false
        self.blocker = "Reforge transaction failed: " .. tostring(problem)
        debug("BLOCK", string.format("slot=%d item=%d reason=%s", entry.inventorySlot, entry.itemID,
            tostring(problem)))
    end
    self:Refresh("submitted")
end

function Reforging:VerifyPending(event)
    local pending = self.pending
    if not pending then
        return false
    end
    Equipment:InvalidateState(event)
    local build = WSGS:GetActiveSimulationProfile()
    local state = build and Equipment:RefreshState(build, "NativeReforgeVerify") or nil
    local slot = state and state.slots[pending.position]
    local observed = slot and slot.current and slot.current.observations.reforging
    local guid = targetGuid(slot)
    local actual = observed and observed.status == "KNOWN" and observed.value or nil
    local verified = guid == pending.guid and actual == pending.expected
    debug("VERIFY", string.format("serial=%d slot=%d item=%d guid=%s expected=%d observed=%s result=%s event=%s",
        pending.serial, pending.inventorySlot, pending.itemID, value(guid), pending.expected, value(actual),
        verified and "VERIFIED" or "DEFERRED", event))
    if verified then
        self.pending = nil
        self:SendMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED", "PLAYER_EQUIPMENT_CHANGED")
    end
    return verified
end

function Reforging:Activate()
    self.blocker = nil
    if InCombatLockdown() then
        self.blocker = "Reforging is unavailable during combat lockdown."
        return self:Refresh("combat")
    end
    local build = WSGS:GetActiveSimulationProfile()
    local rfl, rflActive = self:GetRFL()
    if rfl then
        return self:Handoff(rfl, build)
    end
    if rflActive then
        self.blocker = "ReforgeLite is loaded, but its exact-import interface is unavailable."
        debug("BLOCK", "executor=RFL reason=exact-import-interface-unavailable")
        return self:Refresh("rfl-interface-unavailable")
    end
    if self.pending then
        if not self:VerifyPending("CONTINUE_CLICK") then
            self.blocker = "The previous reforge has not been observed yet."
            return self:Refresh("still-pending")
        end
    end
    self.running = true
    self.started = true
    self.skipped = {}
    self:SubmitNext()
end

function Reforging:FORGE_MASTER_OPENED(event)
    self.open = true
    self.dismissed = false
    self.blocker, self.pending, self.running, self.started = nil, nil, false, nil
    C_Timer.After(0, function()
        self:Refresh(event)
    end)
end

function Reforging:FORGE_MASTER_ITEM_CHANGED(event)
    if not self.open then
        return
    end
    if not self.pending then
        Equipment:InvalidateState(event)
        self:SendMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED", "PLAYER_EQUIPMENT_CHANGED")
    end
    if self.pending and self:VerifyPending(event) and self.running then
        self:SubmitNext()
    else
        self:Refresh(event)
    end
end

function Reforging:FORGE_MASTER_CLOSED(event)
    if self.pending then
        debug("BLOCK", string.format("serial=%d reason=npc-closed", self.pending.serial))
    end
    self.open, self.pending, self.running, self.rflRunning, self.dismissed = false, nil, false, nil, false
    if self.frame then
        self.frame:Hide()
    end
end

function Reforging:UI_ERROR_MESSAGE(event, _, message)
    if not self.pending then
        return
    end
    local pending = self.pending
    self.pending, self.running = nil, false
    self.blocker = type(message) == "string" and message or "The client rejected the reforge."
    debug("BLOCK", string.format("serial=%d slot=%d item=%d reason=%s", pending.serial,
        pending.inventorySlot, pending.itemID, self.blocker))
    self:Refresh(event)
end

function Reforging:WSGS_BUILD_IMPORTED()
    self.rflSignature = nil
    self:Refresh("build-imported")
end

function Reforging:WSGS_EQUIPMENT_STATE_INVALIDATED(_, reason)
    if self.open and not self.pending and not self.running and
        (reason == "PLAYER_EQUIPMENT_CHANGED" or reason == "BAG_UPDATE_DELAYED") then
        C_Timer.After(0, function()
            self:Refresh(reason)
        end)
    end
end

function Reforging:OnEnable()
    self:RegisterEvent("FORGE_MASTER_OPENED")
    self:RegisterEvent("FORGE_MASTER_ITEM_CHANGED")
    self:RegisterEvent("FORGE_MASTER_CLOSED")
    self:RegisterEvent("UI_ERROR_MESSAGE")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_INVALIDATED")
end
