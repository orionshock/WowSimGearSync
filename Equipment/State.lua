local _, WSGS = ...
local Modules = WSGS.Private
local Equipment = WSGS:NewModule("Equipment", "AceEvent-3.0")
Modules.Equipment.Runtime = Equipment

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
        name = build.name,
        specialization = build.specialization and {
            id = build.specialization.id,
            name = build.specialization.name,
            class = build.specialization.class
        } or nil
    }
end

local function normalizedSlots(build, snapshot, comparison)
    local slots = {}
    for position = 1, #WSGS.Equipment.Slots do
        local physical = comparison and comparison.assignments[position] or position
        slots[position] = {
            position = position,
            inventorySlot = WSGS.Equipment.Slots[position].id,
            physicalPosition = physical,
            physicalInventorySlot = WSGS.Equipment.Slots[physical].id,
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
    local snapshot = Modules.Character.Runtime:GetSnapshot()
    local inventory = snapshot.bags
    local materials = snapshot.materials
    local comparison, reason = Modules.Equipment.Comparison:Compare(build, snapshot)
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
    Modules.Character.Runtime:Refresh(consumer)
    local state = capture(build, consumer)
    self.equipmentState = state
    self.stateInvalid = false
    self.stateBuild = build
    return state
end

function Equipment:GetState(build)
    if self.stateInvalid or not self.equipmentState or self.stateBuild ~= build then
        self.equipmentState = capture(build, "GetState")
        self.stateInvalid = false
        self.stateBuild = build
    end
    return self.equipmentState
end

function Equipment:WSGS_CHARACTER_INVALIDATED(_, reason, ...)
    self:InvalidateState(reason, ...)
    self:QueueRefresh(reason, ...)
end

function Equipment:WSGS_BUILD_IMPORTED(event)
    self:InvalidateState(event)
    self:QueueRefresh(event)
end

function Equipment:OnEnable()
    self.stateInvalid = true
    self:RegisterMessage("WSGS_CHARACTER_INVALIDATED")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterMessage("WSGS_BUILD_RENAMED", "WSGS_BUILD_IMPORTED")
    self:RegisterEvent("UI_ERROR_MESSAGE")
    self:QueueRefresh("INITIALIZE")
end
