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
    local entries, unresolved = {}, 0
    if not state or not state.comparison then
        return entries, unresolved
    end
    for position = 1, 16 do
        local slot = state.slots[position]
        local fields = slot and slot.comparison and slot.comparison.fields
        if fields and fields.item.state == "MATCH" then
            local observations = slot.current and slot.current.observations
            local eligible = observedValue(observations and observations.upgradeEligibility)
            local current = observedValue(observations and observations.upgradeStep)
            local maximum = observedValue(observations and observations.upgradeMaximum)
            if eligible == true and type(current) == "number" and type(maximum) == "number" then
                if current < maximum then
                    entries[#entries + 1] = {
                        position = position,
                        inventorySlot = slot.physicalInventorySlot,
                        itemID = slot.target.id,
                        guid = observedValue(observations.instance),
                        current = current,
                        maximum = maximum,
                        slotName = WSGS.equipmentSlots[position].name
                    }
                end
            elseif eligible ~= false then
                unresolved = unresolved + 1
            end
        end
    end
    return entries, unresolved
end

local function costKey(entry)
    return (entry.guid or (entry.itemID .. ":" .. entry.inventorySlot)) .. ":" .. entry.current
end

local function captureCost(nextLevel)
    if not nextLevel then
        return nil
    end
    local result = {
        currencies = {},
        items = {},
        money = nextLevel.moneyCost,
        failureMessage = nextLevel.failureMessage
    }
    for _, cost in ipairs(nextLevel.currencyCostsToUpgrade or {}) do
        result.currencies[#result.currencies + 1] = {currencyID = cost.currencyID, cost = cost.cost}
    end
    for _, cost in ipairs(nextLevel.itemCostsToUpgrade or {}) do
        result.items[#result.items + 1] = {itemID = cost.itemID, cost = cost.cost}
    end
    return result
end

local function costPresentation(cost, state)
    if not cost then
        return "", nil, "unresolved"
    end
    local parts, diagnostic, affordable = {}, {}, true
    if cost.failureMessage and cost.failureMessage ~= "" then
        parts[#parts + 1] = cost.failureMessage
        affordable = false
    end
    for _, required in ipairs(cost.currencies) do
        local currency = C_CurrencyInfo.GetCurrencyInfo(required.currencyID)
        parts[#parts + 1] = string.format("%d %s", required.cost,
            currency and currency.name or "currency " .. required.currencyID)
        diagnostic[#diagnostic + 1] = string.format("currency:%d=%d", required.currencyID, required.cost)
        if not currency or currency.quantity < required.cost then
            affordable = false
        end
    end
    for _, required in ipairs(cost.items) do
        local name = C_Item.GetItemInfo(required.itemID)
        parts[#parts + 1] = string.format("%d %s", required.cost, name or "item " .. required.itemID)
        diagnostic[#diagnostic + 1] = string.format("item:%d=%d", required.itemID, required.cost)
        local count = state and state.bagItemCounts and state.bagItemCounts[required.itemID] or 0
        if count < required.cost then
            affordable = false
        end
    end
    if cost.money and cost.money > 0 then
        parts[#parts + 1] = GetCoinTextureString(cost.money)
        diagnostic[#diagnostic + 1] = "money=" .. cost.money
        if GetMoney() < cost.money then
            affordable = false
        end
    end
    if #parts == 0 then
        return "Next: No cost reported", affordable, "none"
    end
    return "Next: " .. table.concat(parts, ", ") .. (affordable and "" or " (unaffordable)"), affordable,
        table.concat(diagnostic, ",")
end

function Upgrades:CreatePanel()
    if self.frame then
        return self.frame
    end
    local frame = WSGS.NPCPanel:Create("WSGSItemUpgradeCompanion", "WowSimGearSync — Item Upgrades")
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
    local entries, unresolved = collect(state)
    self.entries = entries
    local rows = {}
    for index, entry in ipairs(entries) do
        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(entry.itemID)
        icon = icon or select(5, C_Item.GetItemInfoInstant(entry.itemID))
        local color = quality and ITEM_QUALITY_COLORS[quality]
        local cost, affordable = costPresentation(self.costs[costKey(entry)], state)
        rows[index] = {
            entry = entry,
            icon = icon,
            displayName = name or "Item " .. entry.itemID,
            r = color and color.r or 0.55,
            g = color and color.g or 0.7,
            b = color and color.b or 1,
            detail = string.format("%s   %d/%d %s %d/%d", entry.slotName, entry.current, entry.maximum,
                WSGS.NPCPanel.TRANSITION_ICON, entry.maximum, entry.maximum),
            cost = cost,
            affordable = affordable,
            enabled = true
        }
        if not name and not self.requestedItems[entry.itemID] then
            self.requestedItems[entry.itemID] = true
            Equipment:RequestItemData(entry.itemID, "ItemUpgradeStaging")
        end
    end
    local status
    if not build then
        status = "Import a WoW Sims build first."
    elseif #entries == 0 and unresolved > 0 then
        status = "Matching item upgrade information is still being resolved."
    elseif #entries == 0 then
        status = "All applicable items are fully upgraded."
    elseif self.blocker then
        status = self.blocker
    elseif unresolved > 0 then
        status = "Click an item to stage it. Some matching items are still being resolved."
    else
        status = "Click an item to stage it in Blizzard's upgrade window."
    end
    WSGS.NPCPanel:RenderItemList(frame, "Blizzard's Upgrade button completes the purchase.", rows, status,
        function(row)
            self:Stage(row)
        end)
    frame:Show()
    local signature = string.format("%s:%d:%d:%s", build and build.id or "none", #entries, unresolved,
        self.blocker or "")
    if signature ~= self.planSignature then
        self.planSignature = signature
        debug("PLAN", string.format("reason=%s build=%s items=%d unresolved=%d", value(reason),
            build and build.name or "nil", #entries, unresolved))
    end
end

function Upgrades:Stage(clicked)
    self.blocker = nil
    if not clicked or not self.open or not _G.ItemUpgradeFrame or not ItemUpgradeFrame:IsShown() then
        return
    end
    if CursorHasItem() then
        self.blocker = "Place the held cursor item first."
        debug("BLOCK", "reason=cursor-occupied")
        return self:Refresh("cursor-occupied")
    end
    if InCombatLockdown() then
        self.blocker = "Item staging is unavailable during combat lockdown."
        debug("BLOCK", "reason=combat-lockdown")
        return self:Refresh("combat")
    end
    local build = WSGS:GetActiveSimulationProfile()
    local state = build and Equipment:RefreshState(build, "ItemUpgradeStage") or nil
    local entries = collect(state)
    local entry
    for _, candidate in ipairs(entries) do
        if candidate.position == clicked.position then
            entry = candidate
            break
        end
    end
    if not entry or entry.itemID ~= clicked.itemID or entry.inventorySlot ~= clicked.inventorySlot or
        clicked.guid and entry.guid ~= clicked.guid then
        self.blocker = "The equipped item changed; choose it again from the refreshed list."
        debug("BLOCK", string.format("slot=%s item=%s guid=%s reason=identity-changed", value(clicked.inventorySlot),
            value(clicked.itemID), value(clicked.guid)))
        return self:Refresh("identity-changed", state)
    end
    local location = ItemLocation:CreateFromEquipmentSlot(entry.inventorySlot)
    if not C_ItemUpgrade.CanUpgradeItem(location) then
        self.blocker = "The client does not currently consider this item upgradeable."
        debug("BLOCK", string.format("slot=%d item=%d guid=%s reason=not-upgradeable", entry.inventorySlot,
            entry.itemID, value(entry.guid)))
        return self:Refresh("not-upgradeable", state)
    end
    if IsInventoryItemLocked(entry.inventorySlot) then
        self.blocker = "The item is locked; try again when it becomes available."
        debug("BLOCK", string.format("slot=%d item=%d guid=%s reason=item-locked", entry.inventorySlot,
            entry.itemID, value(entry.guid)))
        return self:Refresh("item-locked", state)
    end

    self.selecting = true
    local staged, stageProblem = pcall(function()
        C_ItemUpgrade.ClearItemUpgrade()
        PickupInventoryItem(entry.inventorySlot)
        C_ItemUpgrade.SetItemUpgradeFromCursorItem()
    end)
    ClearCursor()
    self.selecting = nil
    if not staged then
        self.blocker = "Blizzard's upgrade window could not stage the item."
        debug("BLOCK", string.format("slot=%d item=%d guid=%s reason=%s", entry.inventorySlot,
            entry.itemID, value(entry.guid), value(stageProblem)))
        return self:Refresh("staging-failed", state)
    end
    local info = C_ItemUpgrade.GetItemUpgradeItemInfo()
    local link = C_ItemUpgrade.GetItemHyperlink()
    local selectedID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if not info or selectedID ~= entry.itemID or info.currUpgrade ~= entry.current or
        info.maxUpgrade ~= entry.maximum then
        self.blocker = "Blizzard's upgrade window did not select the expected item."
        debug("BLOCK", string.format("slot=%d item=%d guid=%s selected=%s reason=selection-mismatch",
            entry.inventorySlot, entry.itemID, value(entry.guid), value(selectedID)))
        return self:Refresh("selection-mismatch", state)
    end
    local nextLevel = info.upgradeLevelInfos and info.upgradeLevelInfos[info.currUpgrade + 2]
    self.costs[costKey(entry)] = captureCost(nextLevel)
    local _, affordable, diagnostic = costPresentation(self.costs[costKey(entry)], state)
    debug("STAGE", string.format(
        "slot=%d item=%d guid=%s current=%d maximum=%d cost=%s affordable=%s result=selected api=C_ItemUpgrade.SetItemUpgradeFromCursorItem",
        entry.inventorySlot, entry.itemID, value(entry.guid), entry.current, entry.maximum, diagnostic,
        value(affordable)))
    self:Refresh("staged", state)
end

function Upgrades:QueueRefresh(reason, invalidate)
    if not self.open then
        return
    end
    self.refreshReason = reason
    self.refreshInvalidates = self.refreshInvalidates or invalidate
    if self.refreshQueued then
        return
    end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = nil
        if not self.open then
            return
        end
        local queuedReason = self.refreshReason
        local queuedInvalidates = self.refreshInvalidates
        self.refreshReason, self.refreshInvalidates = nil, nil
        if queuedInvalidates then
            Equipment:InvalidateState(queuedReason)
            self:SendMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED", "PLAYER_EQUIPMENT_CHANGED")
        end
        self.blocker = nil
        self:Refresh(queuedReason)
    end)
end

function Upgrades:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(event, interactionType)
    if interactionType ~= Enum.PlayerInteractionType.ItemUpgrade then
        return
    end
    self.open = true
    self.blocker = nil
    self.costs = {}
    self.requestedItems = {}
    self.planSignature = nil
    self:QueueRefresh(event)
end

function Upgrades:ITEM_UPGRADE_MASTER_SET_ITEM(event)
    if self.open and not self.selecting then
        self:QueueRefresh(event)
    end
end

function Upgrades:ITEM_UPGRADE_MASTER_UPDATE(event)
    self:QueueRefresh(event, true)
end

function Upgrades:ITEM_UPGRADE_FAILED(event, reason)
    if not self.open then
        return
    end
    self.blocker = type(reason) == "string" and reason or "Blizzard could not complete the upgrade."
    debug("BLOCK", "reason=" .. self.blocker)
    self:Refresh(event)
end

function Upgrades:CURRENCY_DISPLAY_UPDATE(event)
    self:QueueRefresh(event)
end

function Upgrades:PLAYER_MONEY(event)
    self:QueueRefresh(event)
end

function Upgrades:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(_, interactionType)
    if interactionType ~= Enum.PlayerInteractionType.ItemUpgrade then
        return
    end
    self.open = false
    self.selecting = nil
    self.refreshReason, self.refreshInvalidates = nil, nil
    if self.frame then
        self.frame:Hide()
    end
end

function Upgrades:WSGS_BUILD_IMPORTED()
    self.costs = {}
    self:QueueRefresh("build-imported")
end

function Upgrades:WSGS_EQUIPMENT_STATE_INVALIDATED(_, reason)
    if self.open and not self.selecting and
        (reason == "PLAYER_EQUIPMENT_CHANGED" or reason == "BAG_UPDATE_DELAYED") then
        self:QueueRefresh(reason)
    end
end

function Upgrades:WSGS_ITEM_DATA_RECEIVED(_, itemID, success, requester)
    if requester == "ItemUpgradeStaging" and success then
        self.requestedItems[itemID] = nil
        self:QueueRefresh("item-data-received")
    end
end

function Upgrades:OnEnable()
    self.open = false
    self.costs = {}
    self.requestedItems = {}
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    self:RegisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
    self:RegisterEvent("ITEM_UPGRADE_MASTER_UPDATE")
    self:RegisterEvent("ITEM_UPGRADE_FAILED")
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    self:RegisterEvent("PLAYER_MONEY")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_INVALIDATED")
    self:RegisterMessage("WSGS_ITEM_DATA_RECEIVED")
end
