local _, WSGS = ...
local Modules = WSGS.Private
local Materials = {}
Modules.Enhancements.Catalog = Materials

-- Blizzard profession skill-line ID -> player-facing profession name.
Materials.professionNames = {
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting"
}

function Materials:ProfessionEffect(inventorySlot, useSpellID)
    local supportedSkillLine
    for skillLine, slots in pairs(self.equippedProfessionEffects) do
        local effects = slots[inventorySlot]
        if effects then
            supportedSkillLine = skillLine
            if effects[useSpellID] then
                return effects[useSpellID], skillLine, true
            end
        end
    end
    return nil, supportedSkillLine, supportedSkillLine ~= nil
end

local function professionAvailability(bags, recipe, inventorySlot, professions)
    if recipe.slot and recipe.slot ~= inventorySlot or recipe.slots and not recipe.slots[inventorySlot] then
        return nil, "Direct profession recipe is not valid for this equipment slot"
    end
    local profession = professions[recipe.profession]
    if not profession then
        return nil, (Materials.professionNames[recipe.profession] or "Required profession") .. " is unavailable"
    end
    for itemID, quantity in pairs(recipe.reagents or {}) do
        if (bags.counts[itemID] or 0) < quantity then
            return nil, string.format("Not enough %s in your bags (%d required)",
                C_Item.GetItemInfo(itemID) or "required reagent", quantity)
        end
    end
    local spellID = recipe.spellID
    return recipe, nil, C_Spell.GetSpellName(spellID), profession.name
end

function Materials:ForInventoryEnhancement(bags, enchantID)
    local definition = self.inventory[enchantID]
    if not definition then
        return nil
    end
    if definition.itemID then
        return bags.byItem[definition.itemID], definition.itemID, nil
    end
    return bags.bySpell[definition.spellID], nil, definition.spellID
end

function Materials:ProfessionEnhancementAvailability(bags, enchantID, inventorySlot, professions)
    local recipe = self.profession[enchantID]
    if not recipe then
        return nil, "No confirmed direct profession enhancement mapping"
    end
    return professionAvailability(bags, recipe, inventorySlot, professions)
end

function WSGS.Enhancements:Resolve(effectID)
    if Materials.profession[effectID] then return Materials.profession[effectID], "PROFESSION" end
    if Materials.inventory[effectID] then return Materials.inventory[effectID], "ITEM" end
end

function WSGS.Enhancements:ObserveEffect(inventorySlot, observed)
    if not observed or observed.status ~= "KNOWN" then
        return {status = "UNKNOWN", reason = observed and observed.reason or "Item use spell unavailable"}
    end
    local effect, _, supported = Materials:ProfessionEffect(inventorySlot, observed.spellId)
    if not supported then return {status = "NOT_APPLICABLE", reason = "Not a supported profession-effect slot"} end
    if effect and effect.effectID then
        return {status = "KNOWN", value = effect.effectID, source = "Equipped use spell mapping"}
    end
    if effect and effect.different then
        return {status = "KNOWN", different = true, spellId = observed.spellId,
            spellName = observed.spellName, source = "Known alternate equipped use spell"}
    end
    return {status = "UNKNOWN", reason = "Equipped item use spell is not mapped for this profession slot"}
end
