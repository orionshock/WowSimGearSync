local _, WSGS = ...
local Internal = WSGS.ActionsInternal or {}
WSGS.ActionsInternal = Internal
local Registry = {
    handlers = {}
}
Internal.Handlers = Registry
local MaterialCatalog = WSGS.ModificationMaterials

-- Inventory-slot capabilities in execution order. The imported target and the
-- comparator decide whether work exists; this table only selects its handler.
Registry.SlotHandlers = {
    [1] = {"ItemEnhancement"},
    [2] = {"ItemEnhancement"},
    [3] = {"ItemEnhancement", "ProfessionEnhancement"},
    [5] = {"ItemEnhancement"},
    [6] = {"ItemEnhancement", "ProfessionEnhancement"},
    [7] = {"ItemEnhancement", "ProfessionEnhancement"},
    [8] = {"ItemEnhancement"},
    [9] = {"ItemEnhancement", "ProfessionEnhancement"},
    [10] = {"ItemEnhancement", "ProfessionEnhancement"},
    [11] = {"ItemEnhancement", "ProfessionEnhancement"},
    [12] = {"ItemEnhancement", "ProfessionEnhancement"},
    [13] = {"ItemEnhancement"},
    [14] = {"ItemEnhancement"},
    [15] = {"ItemEnhancement", "ProfessionEnhancement"},
    [16] = {"ItemEnhancement"},
    [17] = {"ItemEnhancement"}
}

local function verify(context)
    local operation, difference = context.operation, context.difference
    if not difference then
        return false, "comparison unavailable"
    end
    local itemState = difference.fields.item.state
    if itemState ~= "MATCH" and (itemState ~= "UNKNOWN" or not context.targetInstanceMatches) then
        return false, "target item no longer equipped"
    end
    local field = difference.fields[operation.field]
    if not field then
        return false, "comparison field unavailable"
    end
    local expected = operation.expected
    if field.expected ~= expected then
        return false, "comparison no longer describes the submitted expectation", field.actual
    end
    return field.state == "MATCH", field.state .. (field.reason and ": " .. field.reason or ""),
        field.actual
end

local ItemEnhancement = {}
function ItemEnhancement:Check(context)
    local field = context.fields.enchant
    if not field or MaterialCatalog.actions.profession[field.expected] then
        return {}
    end
    if field.state ~= "MISMATCH" and field.state ~= "UNKNOWN" then
        return {}
    end
    return {{
        handler = self,
        handlerName = "ItemEnhancement",
        type = "ENCHANT",
        field = "enchant",
        expected = field.expected,
        unresolved = field.state == "UNKNOWN",
        reason = field.reason
    }}
end
function ItemEnhancement:Prepare(context, operation)
    if operation.unresolved then
        return nil, operation.reason or "Enhancement state is unknown", true
    end
    local material, fixedItemID, spellID = MaterialCatalog:ForInventoryEnhancement(context.bags, operation.expected)
    operation.material, operation.materialItemID = material, fixedItemID or material and material.itemID
    operation.spellID, operation.method = spellID or material and material.spellID, "ITEM"
    if not MaterialCatalog.actions.inventory[operation.expected] then
        return nil, "Required enchantment material is not yet known"
    end
    if not material then
        return nil, "Not in your bags"
    end
    if material.locked then
        return nil, "Enhancement item is locked"
    end
    return operation
end
ItemEnhancement.Verify = verify

local ProfessionEnhancement = {}
function ProfessionEnhancement:Check(context)
    local results, enchant = {}, context.fields.enchant
    if enchant and MaterialCatalog.actions.profession[enchant.expected] and
        (enchant.state == "MISMATCH" or enchant.state == "UNKNOWN") then
        results[#results + 1] = {
            handler = self,
            handlerName = "ProfessionEnhancement",
            type = "PROFESSION_ENCHANT",
            field = "enchant",
            expected = enchant.expected,
            unresolved = enchant.state == "UNKNOWN",
            reason = enchant.reason
        }
    end
    local tinker = context.fields.tinker
    if tinker and tinker.expected ~= nil and (tinker.state == "MISMATCH" or tinker.state == "UNKNOWN") then
        results[#results + 1] = {
            handler = self,
            handlerName = "ProfessionEnhancement",
            type = "TINKER",
            field = "tinker",
            expected = tinker.expected,
            observationUnknown = tinker.state == "UNKNOWN",
            reason = tinker.reason
        }
    end
    return results
end
function ProfessionEnhancement:Prepare(context, operation)
    local mapping = MaterialCatalog.actions.profession[operation.expected]
    local recipe, reason, recipeName, professionName =
        MaterialCatalog:ProfessionEnhancementAvailability(context.bags, operation.expected,
            context.inventorySlot, context.professions)
    operation.professionSkillLine = mapping and mapping.profession
    operation.spellID, operation.spellName = recipe and recipe.spellID, recipeName
    operation.professionName = professionName
    operation.nativeProfession, operation.method = true, "PROFESSION"
    if reason then
        return nil, reason
    end
    return operation
end
ProfessionEnhancement.Verify = verify

Registry.handlers.ItemEnhancement = ItemEnhancement
Registry.handlers.ProfessionEnhancement = ProfessionEnhancement

function Registry:ForSlot(inventorySlot)
    return self.SlotHandlers[inventorySlot] or {}
end
