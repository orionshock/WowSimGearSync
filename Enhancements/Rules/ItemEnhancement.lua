local _, WSGS = ...
local Modules = WSGS.Private
local MaterialCatalog = Modules.Enhancements.Catalog
local ItemEnhancement = {}
function ItemEnhancement:Check(context)
    local field = context.fields.enchant
    if not field or MaterialCatalog.profession[field.expected] then
        return {}
    end
    if field.state ~= "MISMATCH" and field.state ~= "UNKNOWN" then
        return {}
    end
    return {{
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
    operation.material, operation.materialItemID = material, fixedItemID or material and material.id
    operation.spellID, operation.method = spellID or material and material.spellID, "ITEM"
    if not MaterialCatalog.inventory[operation.expected] then
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

Modules.Enhancements.Handlers.handlers.ItemEnhancement = ItemEnhancement
