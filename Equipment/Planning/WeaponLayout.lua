local _, WSGS = ...
local Modules = WSGS.Private
local Weapons = {}
Modules.Equipment.WeaponLayout = Weapons
local function present(target)
    return target and target.id and target.id > 0 and not target.empty
end

local function resolveWeaponDependencies(context)
    local state, snapshot, plan = context.state, context.snapshot, context.plan
    local main, off = state.target[15], state.target[16]
    local mainLoc, mainOperation -- supplied metadata only; no client calls in planner
    for _, operation in ipairs(plan.operations) do
        if operation.kind == "EQUIP" and operation.targetPosition == 15 then
            mainLoc, mainOperation = operation.source.equipLoc, operation
            break
        end
    end
    if not mainLoc and present(main) and snapshot.slots[15].id == main.id then
        mainLoc = snapshot.slots[15].equipLoc
    end

    local grip = snapshot.context and snapshot.context.titansGrip
    local currentMain, currentOff = snapshot.slots[15], snapshot.slots[16]
    local offUnequip
    for _, operation in ipairs(plan.operations) do
        if operation.kind == "UNEQUIP" and operation.position == 16 then
            offUnequip = operation
            break
        end
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
        if operation.position == 15 or operation.position == 16 then
            weaponWork = true
        end
    end
    if mainLoc == "INVTYPE_2HWEAPON" and not present(off) and currentOff.id and not offUnequip then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position == 15 or plan.operations[index].position == 16 then
                table.remove(plan.operations, index)
            end
        end
        plan.blocked[#plan.blocked + 1] = "Two-handed main hand waits until the off hand can be stored."
    elseif weaponWork and
        (mainLoc == "INVTYPE_2HWEAPON" and currentOff.observations.item.status ~= "KNOWN" or present(off) and
            not mainOperation and
            (currentMain.observations.item.status ~= "KNOWN" or currentMain.id and not currentMain.equipLoc)) then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position == 15 or plan.operations[index].position == 16 then
                table.remove(plan.operations, index)
            end
        end
        plan.blocked[#plan.blocked + 1] = "Weapon layout information is unavailable; rescan after item data loads."
    elseif mainLoc == "INVTYPE_2HWEAPON" and present(off) and not grip then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position == 15 or plan.operations[index].position == 16 then
                table.remove(plan.operations, index)
            end
        end
        plan.blocked[#plan.blocked + 1] = "Two-handed target conflicts with a non-empty off-hand target."
    elseif present(off) and currentMain.equipLoc == "INVTYPE_2HWEAPON" and not grip and not mainOperation then
        for index = #plan.operations, 1, -1 do
            if plan.operations[index].position == 16 then
                table.remove(plan.operations, index)
            end
        end
        plan.blocked[#plan.blocked + 1] = "Off hand waits until the two-handed main hand can be replaced."
    end
    context.mainLoc, context.mainOperation = mainLoc, mainOperation
end

local function orderOperations(context)
    -- Ordinary slots go first so a weapon rejection cannot prevent independent
    -- changes. For weapons, clear an unwanted off hand before a two-hander;
    -- otherwise replace the main hand before attempting the off hand.
    local offOperation
    for _, operation in ipairs(context.plan.operations) do
        if operation.kind == "EQUIP" and operation.position == 16 then
            offOperation = operation
            break
        end
    end
    local mainOperation = context.mainOperation
    local offUsesMain = offOperation and offOperation.source.bag == nil and offOperation.source.position == 15 and
                            not (mainOperation and mainOperation.source.bag == nil and mainOperation.source.position ==
                                16)
    local function order(operation)
        if operation.position < 15 or operation.position == 17 then
            return operation.position
        end
        if operation.kind == "UNEQUIP" and operation.position == 16 and context.mainLoc == "INVTYPE_2HWEAPON" then
            return 20
        end
        if operation == offOperation and offUsesMain then
            return 20
        end
        if operation.position == 15 then
            return 21
        end
        return 22
    end
    table.sort(context.plan.operations, function(a, b)
        local first, second = order(a), order(b)
        return first == second and a.position < b.position or first < second
    end)
end


function Weapons:Apply(context)
    if not context.selectedPosition or context.selectedPosition == 15 or context.selectedPosition == 16 then
        resolveWeaponDependencies(context)
    end
    orderOperations(context)
end
