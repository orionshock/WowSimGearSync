local _, WSGS = ...
local Planner = {}
WSGS.EquipmentPlanner = Planner
local locations = {
    [1] = {INVTYPE_HEAD=true}, [2] = {INVTYPE_NECK=true}, [3] = {INVTYPE_SHOULDER=true},
    [4] = {INVTYPE_CLOAK=true}, [5] = {INVTYPE_CHEST=true,INVTYPE_ROBE=true},
    [6] = {INVTYPE_WRIST=true}, [7] = {INVTYPE_HAND=true}, [8] = {INVTYPE_WAIST=true},
    [9] = {INVTYPE_LEGS=true}, [10] = {INVTYPE_FEET=true},
    [11] = {INVTYPE_FINGER=true}, [12] = {INVTYPE_FINGER=true},
    [13] = {INVTYPE_TRINKET=true}, [14] = {INVTYPE_TRINKET=true},
    [15] = {INVTYPE_WEAPON=true,INVTYPE_WEAPONMAINHAND=true,INVTYPE_2HWEAPON=true},
    [16] = {INVTYPE_WEAPON=true,INVTYPE_WEAPONOFFHAND=true,INVTYPE_SHIELD=true,INVTYPE_HOLDABLE=true,INVTYPE_2HWEAPON=true},
}
local function identity(item) return item.guid or item.key end
local function present(target) return target and target.id and target.id > 0 and not target.empty end

-- Ranking reuses actual comparator results, not a second modification comparator.
local function cost(target, candidate, position)
    local fields = WSGS.EquipmentComparator:CompareSlot(target, candidate, position, position).fields
    local result = 0
    for _, name in ipairs({"gems", "enchant", "reforging"}) do
        local field = fields[name]
        if name == "gems" and field.sockets then
            for _, socket in ipairs(field.sockets) do
                result = result + (socket.state == "MISMATCH" and 100 or socket.state == "UNKNOWN" and 1 or 0)
            end
        else result = result + (field.state == "MISMATCH" and 100 or field.state == "UNKNOWN" and 1 or 0) end
    end
    return result
end

function Planner:Plan(profile, snapshot, inventory)
    local plan = { operations = {}, missing = {}, blocked = {}, assignments = {} }
    local comparison, reason = WSGS.EquipmentComparator:Compare(profile, snapshot)
    if not comparison then plan.blocked[1] = reason; return plan end
    local used, candidates, counts, groups = {}, {}, {}, {}
    for position, item in ipairs(snapshot.slots) do
        item.position = position
        candidates[#candidates + 1] = item
    end
    for _, item in ipairs(inventory.items) do candidates[#candidates + 1] = item end
    for _, item in ipairs(candidates) do
        if item.id and item.fingerprint then counts[item.fingerprint] = (counts[item.fingerprint] or 0) + 1 end
    end
    -- Reserve every correctly equipped physical instance first, using the
    -- comparator's resolved ring/trinket mapping, even if modifications differ.
    for position, target in ipairs(profile.equipment) do
        local physical = comparison.assignments[position]
        plan.assignments[position] = physical
        if present(target) then
            local current = snapshot.slots[physical]
            if comparison.slots[position].fields.item.state == "MATCH" then
                used[identity(current)] = true
            elseif comparison.slots[position].fields.item.state == "UNKNOWN" or current.locked then
                plan.blocked[#plan.blocked + 1] = WSGS.equipmentSlots[position].name .. ": equipped identity unavailable or locked."
            else
                groups[target.id] = groups[target.id] or {}
                groups[target.id][#groups[target.id] + 1] = { position = position, physical = physical, target = target }
            end
        end
    end
    for id, targets in pairs(groups) do
        local available = {}
        for _, item in ipairs(candidates) do
            if item.id == id and not used[identity(item)] then available[#available + 1] = item end
        end
        -- A valid equippable ID can occupy at most the two ring/trinket/weapon
        -- positions. Enumerating both assignments avoids greedy duplicate theft.
        if #targets > 2 then
            plan.blocked[#plan.blocked + 1] = "Item " .. id .. " requested in more than two incompatible positions."
        else
            local best, bestScore, assigned = nil, math.huge, {}
            local function choose(index, score, reserved)
                if index > #targets then
                    if score < bestScore then
                        bestScore, best = score, {}
                        for i, candidate in pairs(assigned) do best[i] = candidate end
                    end
                    return
                end
                local target = targets[index]
                assigned[index] = nil
                choose(index + 1, score + 100000, reserved)
                for _, item in ipairs(available) do
                    local key = identity(item)
                    if not reserved[key] and not item.locked and item.fingerprint
                        and locations[target.position][item.equipLoc]
                        and (target.position ~= 16 or item.equipLoc ~= "INVTYPE_2HWEAPON"
                            or snapshot.context and snapshot.context.titansGrip)
                        and (item.guid or counts[item.fingerprint] == 1) then
                        reserved[key], assigned[index] = true, item
                        choose(index + 1, score + cost(target.target, item, target.position), reserved)
                        reserved[key], assigned[index] = nil, nil
                    end
                end
            end
            choose(1, 0, {})
            local unique = {}
            for _, item in ipairs(available) do unique[identity(item)] = true end
            local physicalCount = 0
            for _ in pairs(unique) do physicalCount = physicalCount + 1 end
            local shortage = math.max(0, #targets - physicalCount)
            for index, target in ipairs(targets) do
                local item = best[index]
                if item then
                    used[identity(item)] = true
                    plan.operations[#plan.operations + 1] = { kind = "EQUIP", source = item, position = target.physical,
                        targetPosition = target.position, slotId = WSGS.equipmentSlots[target.physical].id, id = id }
                elseif shortage > 0 then
                    shortage = shortage - 1
                    plan.missing[#plan.missing + 1] = { position = target.position, id = id }
                else
                    plan.blocked[#plan.blocked + 1] = WSGS.equipmentSlots[target.position].name ..
                        ": item " .. id .. " is locked, unreadable, incompatible, or has ambiguous duplicate instances."
                end
            end
        end
    end
    table.sort(plan.operations, function(a,b) return a.position < b.position end)
    local main, off = profile.equipment[15], profile.equipment[16]
    local mainLoc -- supplied metadata only; no client calls in planner
    for _, item in ipairs(candidates) do
        if present(main) and item.id == main.id and item.equipLoc then mainLoc = item.equipLoc; break end
    end
    local mainAvailable = snapshot.slots[15].id == (main and main.id)
    for _, operation in ipairs(plan.operations) do
        if operation.position == 15 then mainAvailable = true end
    end
    local grip = snapshot.context and snapshot.context.titansGrip
    local currentMain, currentOff = snapshot.slots[15], snapshot.slots[16]
    local weaponWork
    for _, operation in ipairs(plan.operations) do
        if operation.position >= 15 then weaponWork = true end
    end
    if weaponWork and (mainLoc == "INVTYPE_2HWEAPON" and currentOff.observations.item.status ~= "KNOWN"
        or present(off) and (currentMain.observations.item.status ~= "KNOWN"
            or currentMain.id and not currentMain.equipLoc)) then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position >= 15 then table.remove(plan.operations, index) end
        end
        plan.blocked[#plan.blocked + 1] = "Weapon layout information is unavailable; rescan after item data loads."
    elseif mainLoc == "INVTYPE_2HWEAPON" and present(off) and not grip then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position >= 15 then table.remove(plan.operations, index) end
        end
        plan.blocked[#plan.blocked + 1] = "Two-handed target conflicts with a non-empty off-hand target."
    elseif mainLoc == "INVTYPE_2HWEAPON" and not present(off) and currentOff.id and mainAvailable then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position >= 15 then table.remove(plan.operations, index) end
        end
        if inventory.free[1] and not currentOff.locked and (currentOff.guid or currentOff.fingerprint) then
            table.insert(plan.operations, 1, { kind = "UNEQUIP", source = currentOff, destination = inventory.free[1],
                position = 16, slotId = 17, id = currentOff.id })
        else plan.blocked[#plan.blocked + 1] = "Clear off hand first: an unlocked item and empty general bag slot are required." end
    elseif currentMain.equipLoc == "INVTYPE_2HWEAPON" and not grip then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position == 16 then
                table.remove(plan.operations, index)
                plan.blocked[#plan.blocked + 1] = "Off hand waits until the two-handed main hand is replaced."
            end
        end
    end
    return plan
end
