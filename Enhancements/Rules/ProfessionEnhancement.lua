local _, WSGS = ...
local Modules = WSGS.Private
local MaterialCatalog = Modules.Enhancements.Catalog
local ProfessionEnhancement = {}
function ProfessionEnhancement:Check(context)
    local results, enchant = {}, context.fields.enchant
    if enchant and MaterialCatalog.profession[enchant.expected] and
        (enchant.state == "MISMATCH" or enchant.state == "UNKNOWN") then
        results[#results + 1] = {
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
    local mapping = MaterialCatalog.profession[operation.expected]
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

Modules.Enhancements.Handlers.handlers.ProfessionEnhancement = ProfessionEnhancement
