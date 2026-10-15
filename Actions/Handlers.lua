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
    [1] = {"Gems", "ItemEnhancement"},
    [2] = {"Gems", "ItemEnhancement"},
    [3] = {"Gems", "ItemEnhancement", "ProfessionEnhancement"},
    [5] = {"Gems", "ItemEnhancement"},
    [6] = {"AdditionalSockets", "Gems", "ItemEnhancement", "ProfessionEnhancement"},
    [7] = {"Gems", "ItemEnhancement", "ProfessionEnhancement"},
    [8] = {"Gems", "ItemEnhancement"},
    [9] = {"AdditionalSockets", "Gems", "ItemEnhancement", "ProfessionEnhancement"},
    [10] = {"AdditionalSockets", "Gems", "ItemEnhancement", "ProfessionEnhancement"},
    [11] = {"Gems", "ItemEnhancement", "ProfessionEnhancement"},
    [12] = {"Gems", "ItemEnhancement", "ProfessionEnhancement"},
    [13] = {"Gems", "ItemEnhancement"},
    [14] = {"Gems", "ItemEnhancement"},
    [15] = {"Gems", "ItemEnhancement", "ProfessionEnhancement"},
    [16] = {"Gems", "ItemEnhancement"},
    [17] = {"Gems", "ItemEnhancement"}
}

local function valueText(value)
    return value == nil and "nil" or tostring(value)
end

local function executionRequest(context, method)
    return {
        method = method,
        operation = context.operation,
        inventorySlot = context.inventorySlot,
        targetItemID = context.target.id,
        targetGUID = context.targetGuid
    }
end

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
    if operation.type == "GEM" then
        field = field and field.sockets and field.sockets[operation.socket]
    end
    if not field then
        return false, "comparison field unavailable"
    end
    local expected = operation.expectedCount or operation.expected
    if field.expected ~= expected then
        return false, "comparison no longer describes the submitted expectation", field.actual
    end
    return field.state == "MATCH", field.state .. (field.reason and ": " .. field.reason or ""),
        field.actualCount or field.actual
end

local AdditionalSockets = {}
function AdditionalSockets:Check(context)
    local results = {}
    for _, definition in ipairs({{
        field = "professionSocket",
        type = "PROFESSION_SOCKET"
    }, {
        field = "buckle",
        type = "BUCKLE"
    }}) do
        local difference = context.fields[definition.field]
        if difference and (difference.state == "MISMATCH" or difference.state == "UNKNOWN") then
            results[#results + 1] = {
                handler = self,
                handlerName = "AdditionalSockets",
                type = definition.type,
                field = definition.field,
                expected = true,
                expectedCount = difference.expected,
                unresolved = difference.state == "UNKNOWN",
                reason = difference.reason
            }
        end
    end
    return results
end
function AdditionalSockets:Prepare(context, operation)
    if operation.unresolved then
        return nil, operation.reason or "Additional socket state is unknown", true
    end
    if operation.type == "BUCKLE" then
        local material, _, definition = MaterialCatalog:ForBuckle(context.bags)
        operation.material = material
        operation.materialItemID = definition.itemID
        operation.spellID = material and material.spellID
        operation.method = "ITEM"
        if not material then
            return nil, string.format("Belt buckle item %d is not in carried bags", definition.itemID)
        end
        if material.locked then
            return nil, "Belt buckle is locked"
        end
        return operation
    end
    local mapping = MaterialCatalog.actions.prerequisites.professionSockets[context.inventorySlot]
    local recipe, reason, recipeName, professionName, professionSpellIndex =
        MaterialCatalog:SocketAvailability(context.bags, context.inventorySlot)
    operation.spellID = recipe and (recipe.spellID or recipe.spellIDs and recipe.spellIDs[1])
    operation.recipeSpellIDs = recipe and recipe.spellIDs
    operation.spellName, operation.professionName = recipeName, professionName
    operation.professionSpellIndex = professionSpellIndex
    operation.professionSkillLine = mapping and mapping.profession
    operation.nativeProfession, operation.method = true, "PROFESSION"
    if reason then
        return nil, reason
    end
    return operation
end
function AdditionalSockets:Apply(context)
    return executionRequest(context, context.operation.method)
end
AdditionalSockets.Verify = verify

local Gems = {}
function Gems:Check(context)
    local results, field = {}, context.fields.gems
    if not field then
        return results
    end
    if field.sockets then
        for socket, difference in ipairs(field.sockets) do
            if difference.state == "MISMATCH" or difference.state == "UNKNOWN" then
                results[#results + 1] = {
                    handler = self,
                    handlerName = "Gems",
                    type = "GEM",
                    field = "gems",
                    socket = socket,
                    expected = difference.expected,
                    unresolved = difference.state == "UNKNOWN",
                    reason = difference.reason
                }
            end
        end
    elseif field.state == "UNKNOWN" then
        results[#results + 1] = {
            handler = self,
            handlerName = "Gems",
            type = "GEM",
            field = "gems",
            unresolved = true,
            reason = field.reason
        }
    end
    return results
end
function Gems:Prepare(context, operation)
    if operation.unresolved then
        return nil, operation.reason or "Gem state is unknown", true
    end
    if not operation.expected or operation.expected == 0 then
        return nil, "An installed gem cannot be removed without a replacement"
    end
    if context.additionalSocketMissing and
        (not context.availableSocketCount or operation.socket > context.availableSocketCount) then
        return nil, "Required additional socket must be applied before this gem"
    end
    local material, count = MaterialCatalog:ForGem(context.bags, operation.expected)
    operation.material, operation.materialItemID, operation.available = material, operation.expected, count
    operation.method = "GEM"
    if not material then
        return nil, "Gem item " .. valueText(operation.expected) .. " is not in carried bags"
    end
    if material.locked then
        return nil, "Gem is locked"
    end
    return operation
end
function Gems:Apply(context)
    return executionRequest(context, "GEM")
end
Gems.Verify = verify

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
        return nil, "No confirmed material mapping for enchant " .. valueText(operation.expected)
    end
    if not material then
        return nil, "Required enhancement item is not in carried bags"
    end
    if material.locked then
        return nil, "Enhancement item is locked"
    end
    return operation
end
function ItemEnhancement:Apply(context)
    return executionRequest(context, "ITEM")
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
            reason = tinker.reason,
            targetSource = tinker.targetSource
        }
    end
    return results
end
function ProfessionEnhancement:Prepare(context, operation)
    local mapping = MaterialCatalog.actions.profession[operation.expected]
    local recipe, reason, recipeName, professionName, professionSpellIndex =
        MaterialCatalog:ProfessionEnhancementAvailability(context.bags, operation.expected,
            context.inventorySlot)
    operation.professionSkillLine = mapping and mapping.profession
    operation.spellID, operation.spellName = recipe and recipe.spellID, recipeName
    operation.professionName, operation.professionSpellIndex = professionName, professionSpellIndex
    operation.nativeProfession, operation.method = true, "PROFESSION"
    if reason then
        return nil, reason
    end
    return operation
end
function ProfessionEnhancement:Apply(context)
    return executionRequest(context, "PROFESSION")
end
ProfessionEnhancement.Verify = verify

Registry.handlers.AdditionalSockets = AdditionalSockets
Registry.handlers.Gems = Gems
Registry.handlers.ItemEnhancement = ItemEnhancement
Registry.handlers.ProfessionEnhancement = ProfessionEnhancement

function Registry:ForSlot(inventorySlot)
    return self.SlotHandlers[inventorySlot] or {}
end
