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
        return entries, state and 1 or 0
    end
    for position = 1, 16 do
        local slot = state.slots[position]
        local fields = slot and slot.comparison and slot.comparison.fields
        local managedItem = slot and slot.target and slot.target.id and slot.target.id > 0 and not slot.target.empty
        if managedItem and fields and fields.item.state == "UNKNOWN" then
            unresolved = unresolved + 1
        elseif managedItem and fields and fields.item.state == "MATCH" then
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

local function costKey(entry, step)
    return (entry.guid or (entry.itemID .. ":" .. entry.inventorySlot)) .. ":" .. (step or entry.current)
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
            currency and currency.name or "Required currency")
        diagnostic[#diagnostic + 1] = string.format("currency:%d=%d", required.currencyID, required.cost)
        if not currency or currency.quantity < required.cost then
            affordable = false
        end
    end
    for _, required in ipairs(cost.items) do
        local name = C_Item.GetItemInfo(required.itemID)
        parts[#parts + 1] = string.format("%d %s", required.cost, name or "Required material")
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
    return "Next: " .. table.concat(parts, ", "), affordable,
        table.concat(diagnostic, ",")
end

function Upgrades:CreatePanel()
    if self.frame then
        return self.frame
    end
    local frame = WSGS.NPCPanel:Create("WSGSItemUpgradeCompanion", "Item Upgrades", function()
        self.dismissed = true
    end)
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 12, 12)
    footer:SetPoint("BOTTOMRIGHT", -12, 12)
    footer:SetHeight(32)
    local line = footer:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.2)
    footer.label = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer.label:SetPoint("LEFT", 0, -5)
    footer.currencies = {}
    for index, currencyID in ipairs({395, 396}) do
        local currency = CreateFrame("Frame", nil, footer)
        currency:SetSize(82, 24)
        currency:SetPoint("BOTTOMRIGHT", (index - 2) * 86, 0)
        currency.icon = currency:CreateTexture(nil, "ARTWORK")
        currency.icon:SetSize(18, 18)
        currency.icon:SetPoint("RIGHT")
        currency.amount = currency:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        currency.amount:SetPoint("RIGHT", currency.icon, "LEFT", -4, 0)
        currency:EnableMouse(true)
        currency:SetScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetCurrencyByID(currencyID)
            GameTooltip:Show()
        end)
        currency:SetScript("OnLeave", function() GameTooltip:Hide() end)
        currency:SetScript("OnHide", function(owner)
            if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
        end)
        footer.currencies[currencyID] = currency
    end
    frame.currencyFooter = footer
    self.frame = frame
    return frame
end

function Upgrades:Refresh(reason, state)
    if not self.open or self.dismissed then
        return
    end
    local frame = self:CreatePanel()
    local owner = _G.ItemUpgradeFrame
    if not owner or not owner:IsShown() or not WSGS.NPCPanel:Anchor(frame, owner, true) then
        frame:Hide()
        return
    end
    local build = WSGS:GetActiveSimulationProfile()
    state = state or (build and Equipment:GetState(build))
    local entries, unresolved = collect(state)
    self.entries = entries
    if not build or #entries == 0 and unresolved == 0 then
        frame:Hide()
        return
    end
    if unresolved > 0 then
        for _, slot in ipairs(state.slots or {}) do
            local fields = slot.comparison and slot.comparison.fields
            local itemID = slot.target and slot.target.id
            if fields and (fields.item.state == "MATCH" or fields.item.state == "UNKNOWN") and
                itemID and itemID > 0 and not C_Item.GetItemInfo(itemID) and not self.requestedItems[itemID] then
                self.requestedItems[itemID] = true
                Equipment:RequestItemData(itemID, "ItemUpgradeStaging")
            end
        end
    end
    local rows = {}
    for index, entry in ipairs(entries) do
        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(entry.itemID)
        icon = icon or select(5, C_Item.GetItemInfoInstant(entry.itemID))
        local color = quality and ITEM_QUALITY_COLORS[quality]
        local cost, affordable = costPresentation(self.costs[costKey(entry)], state)
        rows[index] = {
            entry = entry,
            icon = icon,
            displayName = name or "Equipped item",
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
    if #entries == 0 and unresolved > 0 then
        status = "Loading item upgrade information..."
    elseif self.blocker then
        status = self.blocker
    elseif unresolved > 0 then
        status = "Some item information is still loading."
    end
    WSGS.NPCPanel:RenderItemList(frame, "Click to stage Item Upgrade", rows, status,
        function(row)
            self:Stage(row)
        end, nil, nil, frame.currencyFooter)
    self:RefreshTotals(frame, entries, unresolved)
    frame:Show()
    local signature = string.format("%s:%d:%d:%s", build and build.name or "none", #entries, unresolved,
        self.blocker or "")
    if signature ~= self.planSignature then
        self.planSignature = signature
        debug("PLAN", string.format("reason=%s build=%s items=%d unresolved=%d", value(reason),
            build and build.name or "nil", #entries, unresolved))
    end
end

function Upgrades:RefreshTotals(frame, entries, unresolved)
    local totals, incomplete = {[395] = 0, [396] = 0}, unresolved > 0
    for _, entry in ipairs(entries) do
        for step = entry.current, entry.maximum - 1 do
            local cost = self.costs[costKey(entry, step)]
            if cost then
                for _, currency in ipairs(cost.currencies) do
                    if totals[currency.currencyID] then
                        totals[currency.currencyID] = totals[currency.currencyID] + currency.cost
                    end
                end
            else
                incomplete = true
            end
        end
    end
    local footer = frame.currencyFooter
    footer.label:SetText(incomplete and "Known total" or "Total")
    for currencyID, total in pairs(totals) do
        local currency = footer.currencies[currencyID]
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        local basic = C_CurrencyInfo.GetBasicCurrencyInfo(currencyID)
        currency.icon:SetTexture(basic and basic.icon)
        currency.amount:SetText(BreakUpLargeNumbers(total))
        if info and info.quantity < total then
            currency.amount:SetTextColor(1, 0.25, 0.25)
        else
            currency.amount:SetTextColor(0.8, 0.8, 0.8)
        end
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
    for step = info.currUpgrade, info.maxUpgrade - 1 do
        local level = info.upgradeLevelInfos and info.upgradeLevelInfos[step + 2]
        self.costs[costKey(entry, step)] = captureCost(level)
    end
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
    if self.open then
        return self:QueueRefresh(event)
    end
    self.open = true
    self.dismissed = false
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
        (reason == "PLAYER_EQUIPMENT_CHANGED" or reason == "BAG_UPDATE_DELAYED" or
            reason == "ITEM_DATA_LOAD_RESULT") then
        self:QueueRefresh(reason)
    end
end

function Upgrades:WSGS_ITEM_DATA_RECEIVED(_, itemID, success, requester)
    if requester == "ItemUpgradeStaging" then
        self.requestedItems[itemID] = nil
        if success then
            self:QueueRefresh("item-data-received")
        end
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
