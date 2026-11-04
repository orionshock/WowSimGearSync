local _, WSGS = ...
local Modules = WSGS.Private
local Assignment = {}
Modules.Equipment.InstanceAssignment = Assignment
local locations = {
    [1] = {
        INVTYPE_HEAD = true
    },
    [2] = {
        INVTYPE_NECK = true
    },
    [3] = {
        INVTYPE_SHOULDER = true
    },
    [4] = {
        INVTYPE_CLOAK = true
    },
    [5] = {
        INVTYPE_CHEST = true,
        INVTYPE_ROBE = true
    },
    [6] = {
        INVTYPE_WRIST = true
    },
    [7] = {
        INVTYPE_HAND = true
    },
    [8] = {
        INVTYPE_WAIST = true
    },
    [9] = {
        INVTYPE_LEGS = true
    },
    [10] = {
        INVTYPE_FEET = true
    },
    [11] = {
        INVTYPE_FINGER = true
    },
    [12] = {
        INVTYPE_FINGER = true
    },
    [13] = {
        INVTYPE_TRINKET = true
    },
    [14] = {
        INVTYPE_TRINKET = true
    },
    [15] = {
        INVTYPE_WEAPON = true,
        INVTYPE_WEAPONMAINHAND = true,
        INVTYPE_2HWEAPON = true
    },
    [16] = {
        INVTYPE_WEAPON = true,
        INVTYPE_WEAPONOFFHAND = true,
        INVTYPE_SHIELD = true,
        INVTYPE_HOLDABLE = true,
        INVTYPE_2HWEAPON = true
    },
    [17] = {
        INVTYPE_RANGED = true,
        INVTYPE_RANGEDRIGHT = true,
        INVTYPE_THROWN = true,
        INVTYPE_RELIC = true
    }
}
local function present(target)
    return target and target.id and target.id > 0 and not target.empty
end

-- Ranking reuses actual comparator results, not a second modification comparator.
local function cost(target, candidate, position)
    local fields = Modules.Equipment.Comparison:CompareSlot(target, candidate, position, position).fields
    local field = fields.enchant
    return field.state == "MISMATCH" and 100 or field.state == "UNKNOWN" and 1 or 0
end

local function selected(context, position)
    return not context.selectedPosition or position == context.selectedPosition or
        (context.selectedPosition == 15 or context.selectedPosition == 16) and
            (position == 15 or position == 16)
end

local function collectCandidates(context)
    for _, item in ipairs(context.snapshot.slots) do
        context.candidates[#context.candidates + 1] = item
    end
    for _, item in ipairs(context.inventory.items) do
        context.candidates[#context.candidates + 1] = item
    end
end

-- The comparator has already resolved interchangeable ring/trinket positions.
-- Reserve those physical instances before looking for replacements so the
-- planner does not duplicate comparison policy or steal a matched instance.
local function reserveResolvedAssignments(context)
    local state, comparison, snapshot = context.state, context.comparison, context.snapshot
    for position, target in ipairs(state.target) do
        local physical = comparison.assignments[position]
        context.plan.assignments[position] = physical
        if present(target) then
            local current = snapshot.slots[physical]
            local itemState = comparison.slots[position].fields.item.state
            if itemState == "MATCH" then
                if current.guid then
                    context.used[current.guid] = true
                end
            elseif selected(context, position) then
                if itemState == "UNKNOWN" or current.locked then
                    context.plan.blocked[#context.plan.blocked + 1] = Modules.Equipment.Slots[position].name ..
                        ": equipped identity unavailable or locked."
                else
                    context.targetGroups[target.id] = context.targetGroups[target.id] or {}
                    context.targetGroups[target.id][#context.targetGroups[target.id] + 1] = {
                        position = position,
                        physical = physical,
                        target = target
                    }
                end
            end
        end
    end
end

local function matchTargetGroup(context, id, targets)
    local available = {}
    for _, item in ipairs(context.candidates) do
        if item.id == id and item.guid and not context.used[item.guid] then
            available[#available + 1] = item
        end
    end
    -- A valid equippable ID can occupy at most the two ring/trinket/weapon
    -- positions. Enumerating both assignments avoids greedy duplicate theft.
    if #targets > 2 then
        context.plan.blocked[#context.plan.blocked + 1] =
            "Item " .. id .. " requested in more than two incompatible positions."
        return
    end

    local best, bestScore, assigned = nil, math.huge, {}
    local function choose(index, score, reserved)
        if index > #targets then
            if score < bestScore then
                bestScore, best = score, {}
                for candidateIndex, candidate in pairs(assigned) do
                    best[candidateIndex] = candidate
                end
            end
            return
        end
        local target = targets[index]
        assigned[index] = nil
        choose(index + 1, score + 100000, reserved)
        for _, item in ipairs(available) do
            local key = item.guid
            if not reserved[key] and not item.locked and item.guid and
                locations[target.position][item.equipLoc] and
                (target.position ~= 16 or item.equipLoc ~= "INVTYPE_2HWEAPON" or context.snapshot.context and
                    context.snapshot.context.titansGrip) then
                reserved[key], assigned[index] = true, item
                choose(index + 1, score + cost(target.target, item, target.position), reserved)
                reserved[key], assigned[index] = nil, nil
            end
        end
    end
    choose(1, 0, {})

    local unique = {}
    for _, item in ipairs(available) do
        unique[item.guid] = true
    end
    local physicalCount = 0
    for _ in pairs(unique) do
        physicalCount = physicalCount + 1
    end
    local shortage = math.max(0, #targets - physicalCount)
    for index, target in ipairs(targets) do
        local item = best[index]
        if item then
            context.used[item.guid] = true
            context.plan.operations[#context.plan.operations + 1] = {
                kind = "EQUIP",
                source = item,
                position = target.physical,
                targetPosition = target.position,
                slotId = Modules.Equipment.Slots[target.physical].id,
                id = id
            }
        elseif shortage > 0 then
            shortage = shortage - 1
            context.plan.missing[#context.plan.missing + 1] = {
                position = target.position,
                id = id
            }
        else
            context.plan.blocked[#context.plan.blocked + 1] = Modules.Equipment.Slots[target.position].name ..
                                                                     ": item " .. id ..
                                                                     " is locked, unreadable, incompatible, or has ambiguous duplicate instances."
        end
    end
end

local function matchTargetInstances(context)
    for id, targets in pairs(context.targetGroups) do
        matchTargetGroup(context, id, targets)
    end
end


function Assignment:Apply(context)
    collectCandidates(context)
    reserveResolvedAssignments(context)
    matchTargetInstances(context)
end
