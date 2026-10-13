local _, WSGS = ...
local Equipment = WSGS:NewModule("Equipment", "AceEvent-3.0")

local observationEvents = {
    PLAYER_EQUIPMENT_CHANGED = true,
    BAG_UPDATE_DELAYED = true,
    ITEM_LOCK_CHANGED = true,
    SPELLS_CHANGED = true,
    SKILL_LINES_CHANGED = true
}

local function shown(value)
    if value == nil or value == "" then
        return "nil"
    end
    return tostring(value)
end

local function indexBagItems(inventory)
    local byItem, counts = {}, {}
    for _, item in ipairs(inventory.items) do
        if item.id then
            byItem[item.id] = byItem[item.id] or {}
            byItem[item.id][#byItem[item.id] + 1] = item
            counts[item.id] = (counts[item.id] or 0) + (item.count or 1)
        end
    end
    return byItem, counts
end

local function buildIdentity(build)
    if not build then
        return nil
    end
    return {
        id = build.id,
        name = build.name,
        specialization = build.specialization and {
            id = build.specialization.id,
            name = build.specialization.name,
            class = build.specialization.class
        } or nil,
        equipmentSetID = build.equipmentSetID,
        equipmentSetName = build.equipmentSetName
    }
end

local function normalizedSlots(build, snapshot, comparison)
    local slots = {}
    for position = 1, 16 do
        local physical = comparison and comparison.assignments[position] or position
        slots[position] = {
            position = position,
            inventorySlot = WSGS.equipmentSlots[position].id,
            physicalPosition = physical,
            physicalInventorySlot = WSGS.equipmentSlots[physical].id,
            target = build and build.equipment and build.equipment[position] or nil,
            current = snapshot.slots[physical],
            comparison = comparison and comparison.slots[position] or nil
        }
    end
    return slots
end

local function assignmentText(comparison)
    if not comparison then
        return "unavailable"
    end
    return string.format("rings=%d/%d trinkets=%d/%d", comparison.assignments[11], comparison.assignments[12],
        comparison.assignments[13], comparison.assignments[14])
end

-- GetState returns a read-only capture with build identity, imported targets,
-- equipped observations, carried item indexes and counts, modification materials,
-- resolved physical assignments, per-slot comparisons, and summary results.
-- Equipment owns capture and invalidation; consumers must not mutate the value.
local function capture(build, consumer)
    local snapshot = WSGS.EquipmentScanner:Scan()
    local inventory = WSGS.EquipmentInventory:Scan(snapshot)
    local materials = WSGS.ModificationMaterials:ScanBags()
    local comparison, reason = WSGS.EquipmentComparator:Compare(build, snapshot)
    local byItem, counts = indexBagItems(inventory)
    local state = {
        capturedAt = snapshot.capturedAt,
        build = buildIdentity(build),
        target = build and build.equipment or nil,
        equipped = snapshot.slots,
        bags = inventory,
        bagItemsById = byItem,
        bagItemCounts = counts,
        materials = materials,
        context = snapshot.context,
        comparison = comparison,
        assignments = comparison and comparison.assignments or nil,
        reason = reason,
        slots = normalizedSlots(build, snapshot, comparison)
    }
    local equippedCount = 0
    for _, item in ipairs(state.equipped) do
        if item.id then
            equippedCount = equippedCount + 1
        end
    end
    WSGS:Debug(string.format(
        "[STATE][CAPTURE] build=%s consumer=%s equipped=%d bagItems=%d unreadable=%d",
        shown(state.build and state.build.name), shown(consumer), equippedCount, #inventory.items, inventory.unreadable))
    if comparison then
        WSGS:Debug(string.format(
            "[STATE][COMPARE] build=%s matched=%d itemMismatch=%d configMismatch=%d unknown=%d assignments=%s",
            shown(state.build.name), comparison.summary.matched, comparison.summary.itemMismatches,
            comparison.summary.configurationMismatches, comparison.summary.unknown, assignmentText(comparison)))
    else
        WSGS:Debug(string.format("[STATE][COMPARE] build=%s result=unavailable reason=%s",
            shown(state.build and state.build.name), shown(reason)))
    end
    return state
end

function Equipment:InvalidateState(reason, ...)
    local alreadyInvalid = self.stateInvalid
    self.stateInvalid = true
    if not alreadyInvalid then
        WSGS:Debug(string.format("[STATE][INVALIDATE] reason=%s", shown(reason)))
    end
    self:SendMessage("WSGS_EQUIPMENT_STATE_INVALIDATED", reason, ...)
end

function Equipment:RefreshState(build, consumer)
    local state = capture(build, consumer)
    self.equipmentState = state
    self.stateInvalid = false
    self.stateBuild = build
    self.stateSerial = (self.stateSerial or 0) + 1
    WSGS:Debug(string.format("[STATE][PUBLISH] serial=%d build=%s consumer=%s", self.stateSerial,
        shown(state.build and state.build.name), shown(consumer)))
    self:SendMessage("WSGS_EQUIPMENT_STATE_PUBLISHED", state, consumer)
    return state
end

function Equipment:GetState(build)
    if self.stateInvalid or not self.equipmentState or self.stateBuild ~= build then
        return self:RefreshState(build, "GetState")
    end
    return self.equipmentState
end

function Equipment:IsObservationEvent(event)
    return observationEvents[event] == true
end

local function itemIsRelevant(state, itemID)
    if not state or type(itemID) ~= "number" then
        return false
    end
    for position = 1, 16 do
        local target = state.target and state.target[position]
        local current = state.equipped[position]
        if (target and target.id == itemID) or (current and current.id == itemID) then
            return true
        end
    end
    return false
end

function Equipment:RequestItemData(itemID, requester)
    if type(itemID) ~= "number" or itemID <= 0 then
        return nil, "Item ID must be a positive number"
    end
    self.pendingItemData = self.pendingItemData or {}
    self.pendingItemData[itemID] = requester or true
    local ok, problem = pcall(C_Item.RequestLoadItemDataByID, itemID)
    if not ok then
        self.pendingItemData[itemID] = nil
        return nil, tostring(problem)
    end
    return true
end

function Equipment:OnItemDataEvent(event, itemID, success)
    if not self.pendingItemData or not self.pendingItemData[itemID] then
        return
    end
    local requester = self.pendingItemData[itemID]
    self.pendingItemData[itemID] = nil
    self:SendMessage("WSGS_ITEM_DATA_RECEIVED", itemID, success, requester)
    if not success or not itemIsRelevant(self.equipmentState, itemID) then
        return
    end
    self:InvalidateState(event, itemID, success)
    self:QueueRefresh(event, itemID, success)
end

function Equipment:WSGS_BUILD_IMPORTED(event)
    self:InvalidateState(event)
end

function Equipment:OnEnable()
    self.stateInvalid = true
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentStateEvent")
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnEquipmentStateEvent")
    self:RegisterEvent("ITEM_LOCK_CHANGED", "OnEquipmentStateEvent")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEquipmentStateEvent")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnEquipmentStateEvent")
    self:RegisterEvent("UI_ERROR_MESSAGE")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemDataEvent")
    self:RegisterEvent("ITEM_DATA_LOAD_RESULT", "OnItemDataEvent")
    self:RegisterEvent("SPELLS_CHANGED", "OnEquipmentStateEvent")
    self:RegisterEvent("SKILL_LINES_CHANGED", "OnEquipmentStateEvent")
    self:RegisterEvent("CURSOR_CHANGED", "OnEquipmentStateEvent")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
end
