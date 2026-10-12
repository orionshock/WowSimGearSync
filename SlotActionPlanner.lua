local _, WSGS = ...
local Planner = {}
WSGS.SlotActionPlanner = Planner

local function valueText(value)
    return value == nil and "nil" or tostring(value)
end

local function targetGuid(current)
    local observed = current and current.observations and current.observations.instance
    return observed and observed.status == "KNOWN" and observed.value or nil
end

local function addOperation(controller, operation, reason)
    if reason then
        operation.reason = reason
        controller.blocked[#controller.blocked + 1] = operation
    else
        controller.operations[#controller.operations + 1] = operation
    end
end

function Planner:Build(position, profile, snapshot, comparison, bags)
    local target, difference = profile.equipment[position], comparison.slots[position]
    local current = snapshot.slots[difference.currentPosition]
    local controller = { position = position, inventorySlot = difference.currentSlotId,
        currentPosition = difference.currentPosition, target = target, difference = difference,
        targetGuid = targetGuid(current), operations = {}, blocked = {} }
    if difference.fields.item.state ~= "MATCH" then
        controller.state = "WAITING_FOR_ITEM"
        controller.reason = difference.fields.item.reason or "Equip the target item first"
        return controller
    end
    if target.empty or not target.id or target.id == 0 then
        controller.state = "COMPLETE"
        return controller
    end
    local fields = difference.fields
    local modificationsRemain = false
    for _, field in ipairs({ "buckle", "gems", "enchant", "tinker" }) do
        local observed = fields[field]
        if observed and (observed.state == "MISMATCH" or observed.state == "UNKNOWN") then
            modificationsRemain = true
        end
    end
    if not modificationsRemain then
        controller.state = "COMPLETE"
        return controller
    end
    if not controller.targetGuid then
        controller.state, controller.reason = "BLOCKED", "Equipped item instance could not be verified"
        return controller
    end

    local buckleMissing = position == 8 and fields.buckle and fields.buckle.state == "MISMATCH"
    if buckleMissing then
        local material = WSGS.ModificationMaterials:ForBuckle(bags)
        addOperation(controller, { type = "BUCKLE", field = "buckle", expected = true, material = material,
            materialItemID = WSGS.ModificationMaterials.beltBuckleItemID, spellID = material and material.spellID },
            not material and "Living Steel Belt Buckle (item 90046) is not in carried bags"
                or material.locked and "Belt buckle is locked")
    elseif fields.buckle and fields.buckle.state == "UNKNOWN" then
        addOperation(controller, { type = "BUCKLE", field = "buckle", expected = true },
            fields.buckle.reason or "Buckle state is unknown")
    end

    local gemField = fields.gems
    if gemField and gemField.sockets then
        for socket, observed in ipairs(gemField.sockets) do
            if observed.state == "MISMATCH" then
                local gemID = observed.expected
                local material, count = WSGS.ModificationMaterials:ForGem(bags, gemID)
                local reason = (not gemID or gemID == 0) and "An installed gem cannot be removed without a replacement"
                    or buckleMissing and "Required belt buckle must be applied first"
                    or not material and string.format("Gem item %s is not in carried bags", valueText(gemID))
                    or material.locked and "Gem is locked" or nil
                addOperation(controller, { type = "GEM", field = "gems", socket = socket,
                    expected = gemID, material = material, materialItemID = gemID, available = count }, reason)
            elseif observed.state == "UNKNOWN" then
                addOperation(controller, { type = "GEM", field = "gems", socket = socket,
                    expected = observed.expected }, observed.reason or "Socket state is unknown")
            end
        end
    elseif gemField and gemField.state == "UNKNOWN" then
        addOperation(controller, { type = "GEM", field = "gems" }, gemField.reason or "Gem state is unknown")
    end

    if fields.enchant and fields.enchant.state == "MISMATCH" then
        local enchantID = fields.enchant.expected
        local material, fixedItemID, spellID = WSGS.ModificationMaterials:ForEnchant(bags, enchantID)
        local reason = not WSGS.ModificationMaterials.enchantItems[enchantID]
                and not WSGS.ModificationMaterials.enchantApplications[enchantID]
                and "No confirmed material mapping for enchant " .. valueText(enchantID)
            or not material and "Required enchant material is not in carried bags"
            or material.locked and "Enchant material is locked" or nil
        addOperation(controller, { type = "ENCHANT", field = "enchant", expected = enchantID,
            material = material, materialItemID = fixedItemID or material and material.itemID,
            spellID = spellID or material and material.spellID }, reason)
    elseif fields.enchant and fields.enchant.state == "UNKNOWN" then
        addOperation(controller, { type = "ENCHANT", field = "enchant", expected = fields.enchant.expected },
            fields.enchant.reason or "Enchant state is unknown")
    end

    if fields.tinker and fields.tinker.state == "MISMATCH" then
        local recipe, reason = WSGS.ModificationMaterials:TinkerAvailability(bags, fields.tinker.expected)
        addOperation(controller, { type = "TINKER", field = "tinker", expected = fields.tinker.expected,
            spellID = recipe and recipe.spellID, targetSource = fields.tinker.targetSource }, reason)
    elseif fields.tinker and fields.tinker.state == "UNKNOWN" then
        addOperation(controller, { type = "TINKER", field = "tinker", expected = fields.tinker.expected,
            targetSource = fields.tinker.targetSource }, fields.tinker.reason or "Tinker state is unknown")
    end

    controller.prepared = controller.operations[1]
    if controller.prepared then controller.state = "READY"
    elseif #controller.blocked > 0 then controller.state, controller.reason = "BLOCKED", controller.blocked[1].reason
    else controller.state = "COMPLETE" end
    return controller
end
