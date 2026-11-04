local _, WSGS = ...
local Modules = WSGS.Private
local Requirements = {}
Modules.Shopping.Requirements = Requirements
local function addRequirement(requirements, itemID, quantity)
    if type(itemID) == "number" and itemID > 0 and type(quantity) == "number" and quantity > 0 then
        requirements[itemID] = (requirements[itemID] or 0) + quantity
    end
end

local function professionDefinitionApplies(state, definition, inventorySlot)
    local professions = state.context and state.context.professions
    local validSlot = definition.slot == inventorySlot or definition.slots and definition.slots[inventorySlot]
    return validSlot and professions and professions[definition.profession] ~= nil
end

local function addProfessionReagents(requirements, state, definition, inventorySlot)
    if not definition or not professionDefinitionApplies(state, definition, inventorySlot) then
        return
    end
    for itemID, quantity in pairs(definition.reagents or {}) do
        addRequirement(requirements, itemID, quantity)
    end
end

local function collectSlotRequirements(requirements, state, slot)
    if not slot then
        return
    end
    local difference = slot.comparison
    if not difference or difference.fields.item.state ~= "MATCH" then
        return
    end
    local fields = difference.fields
    local enchant = fields.enchant
    if enchant and enchant.state == "MISMATCH" then
        local definition, method = WSGS.Enhancements:Resolve(enchant.expected)
        if definition and method == "ITEM" and definition.purchasable ~= false then
            addRequirement(requirements, definition.itemID or definition.purchasableItemID, 1)
        elseif method == "PROFESSION" then
            addProfessionReagents(requirements, state, definition, difference.currentSlotId)
        end
    end

    local tinker = fields.tinker
    if tinker and tinker.state == "MISMATCH" then
        addProfessionReagents(requirements, state, (WSGS.Enhancements:Resolve(tinker.expected)),
            difference.currentSlotId)
    end
end

function Requirements:Calculate(state)
    local requirements = {}
    if not state or not state.build or not state.comparison then
        return {}
    end
    for position = 1, #WSGS.Equipment.Slots do
        collectSlotRequirements(requirements, state, state.slots[position])
    end

    local entries, total = {}, 0
    for itemID, required in pairs(requirements) do
        local missing = required - ((state.bagItemCounts and state.bagItemCounts[itemID]) or 0)
        if missing > 0 then
            entries[#entries + 1] = {
                itemID = itemID,
                quantity = missing
            }
            total = total + missing
        end
    end
    table.sort(entries, function(left, right)
        return left.itemID < right.itemID
    end)
    return entries, total
end
