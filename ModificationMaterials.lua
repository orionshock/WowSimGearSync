local _, WSGS = ...
local Materials = {}
WSGS.ModificationMaterials = Materials

Materials.beltBuckleItemID = 90046

-- SpellItemEnchantment ID -> the spell cast by the matching MoP scroll.
-- These are the MoP enchanting recipes' Enchant Item effects, not item IDs.
Materials.enchantApplications = {
    [4411] = 104338, [4412] = 104385, [4414] = 104389,
    [4415] = 104390, [4416] = 104391, [4417] = 104392,
    [4418] = 104393, [4419] = 104395, [4420] = 104397,
    [4421] = 104398, [4422] = 104401, [4423] = 104403,
    [4424] = 104404, [4426] = 104407, [4427] = 104408,
    [4428] = 104409, [4429] = 104414, [4430] = 104416,
    [4431] = 104417, [4432] = 104419, [4433] = 104420,
    [4441] = 104425, [4442] = 104427, [4443] = 104430,
    [4434] = 104445, [4444] = 104434, [4445] = 104440, [4446] = 104442,
}

-- Enhancements whose usable material has a stable, locally verified item ID.
Materials.enchantItems = {
    [4803] = 83006, [4804] = 83007, [4805] = 87560, [4806] = 87559,
    [4822] = 83764, [4823] = 83765, [4824] = 83763,
    [4825] = 82445, [4826] = 82444,
}

-- SpellItemEnchantment ID -> profession recipe and required carried reagents.
Materials.tinkerRecipes = {
    [4223] = { spellID = 55016, reagents = { [39690] = 6, [39681] = 6 } },
    [4697] = { spellID = 108789, reagents = { [90146] = 1 } },
    [4698] = { spellID = 109077, reagents = { [90146] = 1 } },
    [4897] = { spellID = 126392, reagents = { [90146] = 1 } },
    [4898] = { spellID = 126731, reagents = { [90146] = 1 } },
}

local function guidFor(bag, slot)
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(bag, slot))
    return ok and guid or nil
end

function Materials:ScanBags()
    local result = { byItem = {}, bySpell = {}, counts = {} }
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local location = { bag = bag, slot = slot, itemID = info.itemID,
                    guid = guidFor(bag, slot), locked = info.isLocked, link = info.hyperlink,
                    count = info.stackCount or 1 }
                result.counts[info.itemID] = (result.counts[info.itemID] or 0) + location.count
                if not result.byItem[info.itemID] or result.byItem[info.itemID].locked and not location.locked then
                    result.byItem[info.itemID] = location
                end
                local ok, _, spellID = pcall(C_Item.GetItemSpell, info.hyperlink or info.itemID)
                if ok and spellID then
                    location.spellID = spellID
                    if not result.bySpell[spellID] or result.bySpell[spellID].locked and not location.locked then
                        result.bySpell[spellID] = location
                    end
                end
            end
        end
    end
    return result
end

function Materials:ForGem(bags, itemID)
    return bags.byItem[itemID], itemID and (bags.counts[itemID] or 0) or 0
end

function Materials:ForBuckle(bags)
    local id = self.beltBuckleItemID
    return bags.byItem[id], bags.counts[id] or 0
end

function Materials:ForEnchant(bags, enchantID)
    local itemID = self.enchantItems[enchantID]
    if itemID then return bags.byItem[itemID], itemID, nil end
    local spellID = self.enchantApplications[enchantID]
    return spellID and bags.bySpell[spellID] or nil, itemID, spellID
end

function Materials:TinkerAvailability(bags, enchantID)
    local recipe = self.tinkerRecipes[enchantID]
    if not recipe then return nil, "No confirmed MoP tinker recipe mapping" end
    if not C_SpellBook.IsSpellKnown(recipe.spellID) then
        return nil, "Required Engineering recipe is not known"
    end
    for itemID, quantity in pairs(recipe.reagents) do
        if (bags.counts[itemID] or 0) < quantity then
            return nil, string.format("Missing item %d (%d required)", itemID, quantity)
        end
    end
    return recipe
end
