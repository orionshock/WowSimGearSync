local _, WSGS = ...
local Upgrades = WSGS:NewModule("NPCItemUpgrades", "AceEvent-3.0")
local Equipment = WSGS:GetModule("Equipment")

local function debug(category, text)
    WSGS:Debug("[UPGRADE][" .. category .. "] " .. text)
end
local function value(value)
    return value == nil and "nil" or tostring(value)
end

local function observedValue(observation)
    return observation and observation.status == "KNOWN" and observation.value or nil
end

local function collect(state)
    local entries = {}
    if not state or not state.comparison then
        return entries
    end
    for position = 1, 16 do
        local slot = state.slots[position]
        local fields = slot.comparison.fields
        local current = observedValue(slot.current and slot.current.observations.upgradeStep)
        local maximum = observedValue(slot.current and slot.current.observations.upgradeMaximum)
        local guid = observedValue(slot.current and slot.current.observations.instance)
        if fields.item.state == "MATCH" and fields.upgradeStep.state == "MISMATCH" and current and maximum and
            current < maximum then
            entries[#entries + 1] = {
                position = position,
                inventorySlot = slot.physicalInventorySlot,
                itemID = slot.target.id,
                guid = guid,
                current = current,
                maximum = maximum,
                name = WSGS.equipmentSlots[position].name
            }
        end
    end
    return entries
end

function Upgrades:CreatePanel()
    if self.frame then
        return self.frame
    end
    local frame = WSGS.NPCPanel:Create("WSGSItemUpgradeCompanion", "WowSimGearSync — Item Upgrades")
    frame.action:SetScript("OnClick", function()
        self:Activate()
    end)
    self.frame = frame
    return frame
end

function Upgrades:Refresh(reason, state)
    if not self.open then
        return
    end
    local frame = self:CreatePanel()
    local owner = _G.ItemUpgradeFrame
    if not owner or not owner:IsShown() or not WSGS.NPCPanel:Anchor(frame, owner) then
        frame:Hide()
        return
    end
    local build = WSGS:GetActiveSimulationProfile()
    state = state or (build and Equipment:GetState(build))
    local entries = collect(state)
    self.entries = entries
    local rows = {}
    for index, entry in ipairs(entries) do
        rows[index] = string.format("%s   %d/%d %s %d/%d", entry.name, entry.current, entry.maximum,
            WSGS.NPCPanel.TRANSITION_ICON, entry.maximum, entry.maximum)
    end
    local status
    if not build then
        status = "Import a WoW Sims build first."
    elseif #entries == 0 then
        status = "All eligible managed items are at maximum."
    elseif self.blocker then
        status = self.blocker
    elseif self.pending then
        status = "Waiting for the previous paid upgrade to be observed. " .. (self.lastCostLabel or "")
    else
        local steps = 0
        for _, entry in ipairs(entries) do
            steps = steps + entry.maximum - entry.current
        end
        status = string.format("%d item%s, %d paid step%s remaining. Each step requires a click.", #entries,
            #entries == 1 and "" or "s", steps, steps == 1 and "" or "s")
    end
    local enabled = build and (#entries > 0 or self.pending ~= nil)
    WSGS.NPCPanel:Render(frame, "Native executor — verified one paid step per click", rows, status,
        self.started and "Continue" or "Upgrade All", enabled)
    frame:Show()
    debug("PLAN", string.format("reason=%s items=%d pending=%s", value(reason), #entries,
        self.pending and self.pending.serial or "none"))
end

function Upgrades:Select(entry)
    if CursorHasItem() then
        return nil, "Place the held cursor item first"
    end
    local location = ItemLocation:CreateFromEquipmentSlot(entry.inventorySlot)
    if not C_ItemUpgrade.CanUpgradeItem(location) then
        return nil, "The client reports this item is not upgradeable"
    end
    if IsInventoryItemLocked(entry.inventorySlot) then
        return nil, "Item is locked"
    end
    C_ItemUpgrade.ClearItemUpgrade()
    PickupInventoryItem(entry.inventorySlot)
    C_ItemUpgrade.SetItemUpgradeFromCursorItem()
    ClearCursor()
    local info = C_ItemUpgrade.GetItemUpgradeItemInfo()
    local link = C_ItemUpgrade.GetItemHyperlink()
    local selectedID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if not info or selectedID ~= entry.itemID then
        return nil, "Item Upgrade NPC selected a different item"
    end
    return info
end

local function costProblem(nextLevel, state)
    if not nextLevel then
        return "The next upgrade level is unavailable"
    end
    if nextLevel.failureMessage and nextLevel.failureMessage ~= "" then
        return nextLevel.failureMessage
    end
    for _, cost in ipairs(nextLevel.currencyCostsToUpgrade or {}) do
        local currency = C_CurrencyInfo.GetCurrencyInfo(cost.currencyID)
        if not currency or currency.quantity < cost.cost then
            return "Insufficient " .. (currency and currency.name or "currency")
        end
    end
    for _, cost in ipairs(nextLevel.itemCostsToUpgrade or {}) do
        local count = state and state.bagItemCounts and state.bagItemCounts[cost.itemID] or 0
        if count < cost.cost then
            local name = C_Item.GetItemInfo(cost.itemID)
            return "Insufficient " .. (name or "item " .. cost.itemID)
        end
    end
    if nextLevel.moneyCost and GetMoney() < nextLevel.moneyCost then
        return "Insufficient gold"
    end
end

local function costText(nextLevel)
    local parts = {}
    for _, cost in ipairs(nextLevel.currencyCostsToUpgrade or {}) do
        parts[#parts + 1] = string.format("currency:%d=%d", cost.currencyID, cost.cost)
    end
    for _, cost in ipairs(nextLevel.itemCostsToUpgrade or {}) do
        parts[#parts + 1] = string.format("item:%d=%d", cost.itemID, cost.cost)
    end
    if nextLevel.moneyCost and nextLevel.moneyCost > 0 then
        parts[#parts + 1] = "money=" .. nextLevel.moneyCost
    end
    return #parts > 0 and table.concat(parts, ",") or "none"
end

local function costLabel(nextLevel)
    local parts = {}
    for _, cost in ipairs(nextLevel.currencyCostsToUpgrade or {}) do
        local currency = C_CurrencyInfo.GetCurrencyInfo(cost.currencyID)
        parts[#parts + 1] = string.format("%d %s", cost.cost, currency and currency.name or
            "currency " .. cost.currencyID)
    end
    for _, cost in ipairs(nextLevel.itemCostsToUpgrade or {}) do
        local name = C_Item.GetItemInfo(cost.itemID)
        parts[#parts + 1] = string.format("%d %s", cost.cost, name or "item " .. cost.itemID)
    end
    if nextLevel.moneyCost and nextLevel.moneyCost > 0 then
        parts[#parts + 1] = GetCoinTextureString(nextLevel.moneyCost)
    end
    return #parts > 0 and "Cost: " .. table.concat(parts, ", ") or "Cost: none"
end

function Upgrades:VerifyPending(event)
    local pending = self.pending
    if not pending then
        return false
    end
    Equipment:InvalidateState(event)
    local build = WSGS:GetActiveSimulationProfile()
    local state = build and Equipment:RefreshState(build, "ItemUpgradeVerify") or nil
    local slot = state and state.slots[pending.position]
    local actual = observedValue(slot and slot.current and slot.current.observations.upgradeStep)
    local guid = observedValue(slot and slot.current and slot.current.observations.instance)
    local verified = guid == pending.guid and actual and actual >= pending.expected
    debug("VERIFY", string.format("serial=%d slot=%d item=%d guid=%s expected=%d observed=%s result=%s event=%s",
        pending.serial, pending.inventorySlot, pending.itemID, value(guid), pending.expected, value(actual),
        verified and "VERIFIED" or "DEFERRED", event))
    if verified then
        self.pending = nil
        self:SendMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED", "PLAYER_EQUIPMENT_CHANGED")
    end
    self:Refresh(event, state)
    return verified
end

function Upgrades:Activate()
    self.blocker = nil
    if InCombatLockdown() then
        self.blocker = "Item upgrading is unavailable during combat lockdown."
        return self:Refresh("combat")
    end
    if self.pending then
        if not self:VerifyPending("CONTINUE_CLICK") then
            self.blocker = "The previous paid upgrade has not been observed; no new charge was submitted."
            return self:Refresh("still-pending")
        end
    end
    local build = WSGS:GetActiveSimulationProfile()
    local state = build and Equipment:RefreshState(build, "ItemUpgradeClick") or nil
    local entries = collect(state)
    if not entries[1] then
        return self:Refresh("complete", state)
    end
    local entry, info, nextLevel, firstProblem
    for _, candidate in ipairs(entries) do
        self.selecting = true
        local selected, problem = self:Select(candidate)
        self.selecting = nil
        if selected and selected.currUpgrade == candidate.current and selected.maxUpgrade == candidate.maximum then
            local candidateLevel = selected.upgradeLevelInfos and selected.upgradeLevelInfos[selected.currUpgrade + 2]
            problem = costProblem(candidateLevel, state)
            if not problem then
                entry, info, nextLevel = candidate, selected, candidateLevel
                self.lastCostLabel = costLabel(candidateLevel)
                break
            end
        elseif selected then
            problem = "Upgrade progress changed while preparing the item"
        end
        firstProblem = firstProblem or problem
        debug("BLOCK", string.format("slot=%d item=%d guid=%s reason=%s action=skip", candidate.inventorySlot,
            candidate.itemID, value(candidate.guid), value(problem)))
    end
    if not entry then
        self.blocker = firstProblem or "No remaining item can be upgraded safely."
        return self:Refresh("no-affordable-item", state)
    end
    self.serial = (self.serial or 0) + 1
    self.pending = {
        serial = self.serial,
        position = entry.position,
        inventorySlot = entry.inventorySlot,
        itemID = entry.itemID,
        guid = entry.guid,
        expected = info.currUpgrade + 1
    }
    self.started = true
    debug("EXEC", string.format("serial=%d slot=%d item=%d guid=%s current=%d expected=%d maximum=%d cost=%s api=C_ItemUpgrade.UpgradeItem(1)",
        self.serial, entry.inventorySlot, entry.itemID, value(entry.guid), info.currUpgrade,
        self.pending.expected, info.maxUpgrade, costText(nextLevel)))
    local ok, callProblem = pcall(C_ItemUpgrade.UpgradeItem, 1)
    if not ok then
        self.pending = nil
        self.blocker = "Upgrade transaction failed: " .. tostring(callProblem)
        debug("BLOCK", "reason=" .. tostring(callProblem))
    end
    self:Refresh("submitted")
end

function Upgrades:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(event, interactionType)
    if interactionType ~= Enum.PlayerInteractionType.ItemUpgrade then
        return
    end
    self.open = true
    self.pending, self.blocker, self.started = nil, nil, nil
    self.lastCostLabel = nil
    C_Timer.After(0, function()
        self:Refresh(event)
    end)
end

function Upgrades:ITEM_UPGRADE_MASTER_SET_ITEM(event)
    if self.open and not self.selecting then
        self:Refresh(event)
    end
end

function Upgrades:ITEM_UPGRADE_MASTER_UPDATE(event)
    if not self.open then
        return
    end
    if self.pending then
        self:VerifyPending(event)
    else
        Equipment:InvalidateState(event)
        self:SendMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED", "PLAYER_EQUIPMENT_CHANGED")
        self:Refresh(event)
    end
end

function Upgrades:ITEM_UPGRADE_FAILED(event, reason)
    if not self.open then
        return
    end
    local pending = self.pending
    self.pending = nil
    self.blocker = type(reason) == "string" and reason or "The client rejected the upgrade."
    debug("BLOCK", string.format("serial=%s reason=%s", pending and pending.serial or "none", self.blocker))
    self:Refresh(event)
end

function Upgrades:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(_, interactionType)
    if interactionType ~= Enum.PlayerInteractionType.ItemUpgrade then
        return
    end
    if self.pending then
        debug("BLOCK", string.format("serial=%d reason=npc-closed", self.pending.serial))
    end
    self.open, self.pending = false, nil
    if self.frame then
        self.frame:Hide()
    end
end

function Upgrades:WSGS_BUILD_IMPORTED()
    self:Refresh("build-imported")
end

function Upgrades:WSGS_EQUIPMENT_STATE_INVALIDATED(_, reason)
    if self.open and not self.pending and not self.selecting and
        (reason == "PLAYER_EQUIPMENT_CHANGED" or reason == "BAG_UPDATE_DELAYED") then
        C_Timer.After(0, function()
            self:Refresh(reason)
        end)
    end
end

function Upgrades:OnEnable()
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    self:RegisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
    self:RegisterEvent("ITEM_UPGRADE_MASTER_UPDATE")
    self:RegisterEvent("ITEM_UPGRADE_FAILED")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_INVALIDATED")
end
