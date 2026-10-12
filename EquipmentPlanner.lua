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
    local plan = { operations = {}, missing = {}, blocked = {}, assignments = {}, unresolvedCount = 0 }
    local comparison, reason = WSGS.EquipmentComparator:Compare(profile, snapshot)
    if not comparison then plan.blocked[1] = reason; return plan end
    for _, slot in ipairs(comparison.slots) do
        if slot.fields.item.state ~= "MATCH" then plan.unresolvedCount = plan.unresolvedCount + 1 end
    end
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
    local main, off = profile.equipment[15], profile.equipment[16]
    local mainLoc, mainOperation -- supplied metadata only; no client calls in planner
    for _, operation in ipairs(plan.operations) do
        if operation.targetPosition == 15 then
            mainLoc, mainOperation = operation.source.equipLoc, operation
            break
        end
    end
    if not mainLoc and present(main) and snapshot.slots[15].id == main.id then
        mainLoc = snapshot.slots[15].equipLoc
    end
    local freeIndex = 1
    for position, target in ipairs(profile.equipment) do
        if not present(target) then
            local current = snapshot.slots[position]
            if current.observations.item.status ~= "KNOWN" then
                plan.blocked[#plan.blocked + 1] = WSGS.equipmentSlots[position].name .. ": equipped identity is unavailable."
            elseif current.id then
                local destination = inventory.free[freeIndex]
                if current.locked or not (current.guid or current.fingerprint) then
                    plan.blocked[#plan.blocked + 1] = WSGS.equipmentSlots[position].name .. ": equipped item is locked or unreadable."
                elseif not destination then
                    plan.blocked[#plan.blocked + 1] = WSGS.equipmentSlots[position].name .. ": no empty general bag slot is available."
                else
                    freeIndex = freeIndex + 1
                    plan.operations[#plan.operations + 1] = { kind = "UNEQUIP", source = current,
                        destination = destination, position = position, targetPosition = position,
                        slotId = WSGS.equipmentSlots[position].id, id = current.id }
                end
            end
        end
    end
    local grip = snapshot.context and snapshot.context.titansGrip
    local currentMain, currentOff = snapshot.slots[15], snapshot.slots[16]
    local offUnequip
    for _, operation in ipairs(plan.operations) do
        if operation.kind == "UNEQUIP" and operation.position == 16 then offUnequip = operation; break end
    end
    local mainReady = present(main) and currentMain.id == main.id or mainOperation
    if not present(off) and currentOff.id and not mainReady then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].kind == "UNEQUIP" and plan.operations[index].position == 16 then
                table.remove(plan.operations, index)
                plan.blocked[#plan.blocked + 1] = "Off hand waits until the target main hand is available."
            end
        end
    end
    local weaponWork
    for _, operation in ipairs(plan.operations) do
        if operation.position >= 15 then weaponWork = true end
    end
    if mainLoc == "INVTYPE_2HWEAPON" and not present(off) and currentOff.id and not offUnequip then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position >= 15 then table.remove(plan.operations, index) end
        end
        plan.blocked[#plan.blocked + 1] = "Two-handed main hand waits until the off hand can be stored."
    elseif weaponWork and (mainLoc == "INVTYPE_2HWEAPON" and currentOff.observations.item.status ~= "KNOWN"
        or present(off) and not mainOperation and (currentMain.observations.item.status ~= "KNOWN"
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
    elseif present(off) and currentMain.equipLoc == "INVTYPE_2HWEAPON" and not grip and not mainOperation then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position == 16 then table.remove(plan.operations, index) end
        end
        plan.blocked[#plan.blocked + 1] = "Off hand waits until the two-handed main hand can be replaced."
    end
    -- Ordinary slots go first so a weapon rejection cannot prevent independent
    -- changes. For weapons, clear an unwanted off hand before a two-hander;
    -- otherwise replace the main hand before attempting the off hand.
    local offOperation
    for _, operation in ipairs(plan.operations) do
        if operation.kind == "EQUIP" and operation.position == 16 then offOperation = operation; break end
    end
    local offUsesMain = offOperation and offOperation.source.bag == nil and offOperation.source.position == 15
        and not (mainOperation and mainOperation.source.bag == nil and mainOperation.source.position == 16)
    local function order(operation)
        if operation.position < 15 then return operation.position end
        if operation.kind == "UNEQUIP" and operation.position == 16 and mainLoc == "INVTYPE_2HWEAPON" then return 20 end
        if operation == offOperation and offUsesMain then return 20 end
        if operation.position == 15 then return 21 end
        return 22
    end
    table.sort(plan.operations, function(a, b)
        local first, second = order(a), order(b)
        return first == second and a.position < b.position or first < second
    end)
    return plan
end
