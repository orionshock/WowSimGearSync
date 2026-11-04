local _, WSGS = ...
local Modules = WSGS.Private
local Destinations = {}
Modules.Equipment.BagDestinations = Destinations
local function present(target)
    return target and target.id and target.id > 0 and not target.empty
end

local function selected(context, position)
    return not context.selectedPosition or position == context.selectedPosition or
        (context.selectedPosition == 15 or context.selectedPosition == 16) and
            (position == 15 or position == 16)
end

function Destinations:Apply(context)
    local freeIndex = 1
    for position, target in ipairs(context.state.target) do
        if selected(context, position) and not present(target) then
            local current = context.snapshot.slots[position]
            if current.observations.item.status ~= "KNOWN" then
                context.plan.blocked[#context.plan.blocked + 1] = WSGS.Equipment.Slots[position].name ..
                                                                         ": equipped identity is unavailable."
            elseif current.id then
                local destination = context.inventory.free[freeIndex]
                if current.locked or not current.guid then
                    context.plan.blocked[#context.plan.blocked + 1] = WSGS.Equipment.Slots[position].name ..
                                                                             ": equipped item is locked or unreadable."
                elseif not destination then
                    context.plan.blocked[#context.plan.blocked + 1] = WSGS.Equipment.Slots[position].name ..
                                                                             ": no empty general bag slot is available."
                else
                    freeIndex = freeIndex + 1
                    context.plan.operations[#context.plan.operations + 1] = {
                        kind = "UNEQUIP",
                        source = current,
                        destination = destination,
                        position = position,
                        targetPosition = position,
                        slotId = WSGS.Equipment.Slots[position].id,
                        id = current.id
                    }
                end
            end
        end
    end
end
