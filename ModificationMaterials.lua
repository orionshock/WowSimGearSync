local _, WSGS = ...
local Materials = {}
WSGS.ModificationMaterials = Materials

-- Item ID for the MoP belt buckle consumed by the bag-item action.
Materials.beltBuckleItemID = 90046 -- Living Steel Belt Buckle.

-- Blizzard profession skill-line ID -> player-facing profession name.
Materials.professionNames = {
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting"
}

-- SpellItemEnchantment ID -> the spell cast by the matching MoP scroll.
-- These are the MoP enchanting recipes' Enchant Item effects, not item IDs.
Materials.enchantApplications = {
    [4411] = 104338, -- Enchant Bracer - Mastery.
    [4412] = 104385, -- Enchant Bracer - Major Dodge.
    [4414] = 104389, -- Enchant Bracer - Super Intellect.
    [4415] = 104390, -- Enchant Bracer - Exceptional Strength.
    [4416] = 104391, -- Enchant Bracer - Greater Agility.
    [4417] = 104392, -- Enchant Chest - Super Resilience.
    [4418] = 104393, -- Enchant Chest - Mighty Spirit.
    [4419] = 104395, -- Enchant Chest - Glorious Stats.
    [4420] = 104397, -- Enchant Chest - Superior Stamina.
    [4421] = 104398, -- Enchant Cloak - Accuracy.
    [4422] = 104401, -- Enchant Cloak - Greater Protection.
    [4423] = 104403, -- Enchant Cloak - Superior Intellect.
    [4424] = 104404, -- Enchant Cloak - Superior Critical Strike.
    [4426] = 104407, -- Enchant Boots - Greater Haste.
    [4427] = 104408, -- Enchant Boots - Greater Precision.
    [4428] = 104409, -- Enchant Boots - Blurred Speed.
    [4429] = 104414, -- Enchant Boots - Pandaren's Step.
    [4430] = 104416, -- Enchant Gloves - Greater Haste.
    [4431] = 104417, -- Enchant Gloves - Superior Expertise.
    [4432] = 104419, -- Enchant Gloves - Super Strength.
    [4433] = 104420, -- Enchant Gloves - Superior Mastery.
    [4441] = 104425, -- Enchant Weapon - Windsong.
    [4442] = 104427, -- Enchant Weapon - Jade Spirit.
    [4443] = 104430, -- Enchant Weapon - Elemental Force.
    [4434] = 104445, -- Enchant Off-Hand - Major Intellect.
    [4444] = 104434, -- Enchant Weapon - Dancing Steel.
    [4445] = 104440, -- Enchant Weapon - Colossus.
    [4446] = 104442 -- Enchant Weapon - River's Song.
}

-- SpellItemEnchantment ID -> finished enhancement item ID.
-- These mappings bypass GetItemSpell discovery when the usable item is known.
Materials.enchantItems = {
    [4803] = 83006, -- Greater Tiger Fang Inscription.
    [4804] = 83007, -- Greater Tiger Claw Inscription.
    [4805] = 87560, -- Greater Crane Wing Inscription.
    [4806] = 87559, -- Greater Ox Horn Inscription.
    [4822] = 83764, -- Shadowleather Leg Armor.
    [4823] = 83765, -- Angerhide Leg Armor.
    [4824] = 83763, -- Ironscale Leg Armor.
    [4825] = 82445, -- Greater Cerulean Spellthread.
    [4826] = 82444, -- Greater Pearlescent Spellthread.
    -- Secret inscriptions are finished BoP items. Their profession recipes
    -- create these items, so only already-carried copies use the item path.
    [4912] = 87581, -- Secret Ox Horn Inscription.
    [4913] = 87585, -- Secret Tiger Fang Inscription.
    [4914] = 87584, -- Secret Tiger Claw Inscription.
    [4915] = 87582 -- Secret Crane Wing Inscription.
}

-- SpellItemEnchantment ID -> direct item-targeting profession recipe.
-- Recipe creation of scrolls, kits, spellthreads, inscriptions, or other
-- intermediate items is excluded from this table.
Materials.directEnhancements = {
    -- Tailoring: cloak embroideries and tailor-only leg spellthreads.
    [4892] = { -- Lightweave Embroidery.
        profession = 197, -- Tailoring skill line.
        spellID = 125481, -- Lightweave Embroidery recipe.
        slot = 15, -- Back inventory slot.
        reagents = {
            [38426] = 3 -- Eternium Thread.
        }
    },
    [4893] = { -- Darkglow Embroidery.
        profession = 197, -- Tailoring skill line.
        spellID = 125482, -- Darkglow Embroidery recipe.
        slot = 15, -- Back inventory slot.
        reagents = {
            [38426] = 3 -- Eternium Thread.
        }
    },
    [4894] = { -- Swordguard Embroidery.
        profession = 197, -- Tailoring skill line.
        spellID = 125483, -- Swordguard Embroidery recipe.
        slot = 15, -- Back inventory slot.
        reagents = {
            [38426] = 3 -- Eternium Thread.
        }
    },
    [4895] = { -- Master's Spellthread.
        profession = 197, -- Tailoring skill line.
        spellID = 125496, -- Master's Spellthread recipe.
        slot = 7, -- Legs inventory slot.
        reagents = {
            [38426] = 3 -- Eternium Thread.
        }
    },
    [4896] = { -- Sanctified Spellthread.
        profession = 197, -- Tailoring skill line.
        spellID = 125497, -- Sanctified Spellthread recipe.
        slot = 7, -- Legs inventory slot.
        reagents = {
            [38426] = 3 -- Eternium Thread.
        }
    },

    -- Leatherworking: Fur Linings and leatherworker-only leg reinforcements.
    [4875] = { -- Fur Lining - Agility.
        profession = 165, -- Leatherworking skill line.
        spellID = 124551, -- Fur Lining - Agility recipe.
        slot = 9, -- Wrist inventory slot.
        reagents = {
            [38426] = 1 -- Eternium Thread.
        }
    },
    [4877] = { -- Fur Lining - Intellect.
        profession = 165, -- Leatherworking skill line.
        spellID = 124552, -- Fur Lining - Intellect recipe.
        slot = 9, -- Wrist inventory slot.
        reagents = {
            [38426] = 1 -- Eternium Thread.
        }
    },
    [4878] = { -- Fur Lining - Stamina.
        profession = 165, -- Leatherworking skill line.
        spellID = 124553, -- Fur Lining - Stamina recipe.
        slot = 9, -- Wrist inventory slot.
        reagents = {
            [38426] = 1 -- Eternium Thread.
        }
    },
    [4879] = { -- Fur Lining - Strength.
        profession = 165, -- Leatherworking skill line.
        spellID = 124554, -- Fur Lining - Strength recipe.
        slot = 9, -- Wrist inventory slot.
        reagents = {
            [38426] = 1 -- Eternium Thread.
        }
    },
    [4880] = { -- Primal Leg Reinforcements.
        profession = 165, -- Leatherworking skill line.
        spellID = 124559, -- Primal Leg Reinforcements recipe.
        slot = 7, -- Legs inventory slot.
        reagents = {
            [38426] = 1 -- Eternium Thread.
        }
    },
    [4881] = { -- Draconic Leg Reinforcements.
        profession = 165, -- Leatherworking skill line.
        spellID = 124561, -- Draconic Leg Reinforcements recipe.
        slot = 7, -- Legs inventory slot.
        reagents = {
            [38426] = 1 -- Eternium Thread.
        }
    },
    [4882] = { -- Heavy Leg Reinforcements.
        profession = 165, -- Leatherworking skill line.
        spellID = 124563, -- Heavy Leg Reinforcements recipe.
        slot = 7, -- Legs inventory slot.
        reagents = {
            [38426] = 1 -- Eternium Thread.
        }
    },

    -- Enchanting: enchanter-only ring enchants.
    [4359] = { -- Enchant Ring - Greater Agility.
        profession = 333, -- Enchanting skill line.
        spellID = 103461, -- Greater Agility recipe.
        slots = {
            [11] = true, -- Finger 1 inventory slot.
            [12] = true -- Finger 2 inventory slot.
        },
        reagents = {
            [74249] = 2 -- Spirit Dust.
        }
    },
    [4360] = { -- Enchant Ring - Greater Intellect.
        profession = 333, -- Enchanting skill line.
        spellID = 103462, -- Greater Intellect recipe.
        slots = {
            [11] = true, -- Finger 1 inventory slot.
            [12] = true -- Finger 2 inventory slot.
        },
        reagents = {
            [74249] = 2 -- Spirit Dust.
        }
    },
    [4361] = { -- Enchant Ring - Greater Stamina.
        profession = 333, -- Enchanting skill line.
        spellID = 103463, -- Greater Stamina recipe.
        slots = {
            [11] = true, -- Finger 1 inventory slot.
            [12] = true -- Finger 2 inventory slot.
        },
        reagents = {
            [74249] = 2 -- Spirit Dust.
        }
    },
    [4807] = { -- Enchant Ring - Greater Strength.
        profession = 333, -- Enchanting skill line.
        spellID = 103465, -- Greater Strength recipe.
        slots = {
            [11] = true, -- Finger 1 inventory slot.
            [12] = true -- Finger 2 inventory slot.
        },
        reagents = {
            [74249] = 2 -- Spirit Dust.
        }
    }
}

-- Equipment inventory slot -> direct Blacksmithing socket recipes.
-- The first spell is the MoP recipe; the second is the legacy recipe accepted
-- for the same slot. Both consume four Strong Flux.
Materials.directSockets = {
    [9] = { -- Wrist: adds SpellItemEnchantment 3717.
        profession = 164, -- Blacksmithing skill line.
        spellIDs = {113263, 55628}, -- Socket Bracer recipes.
        reagents = {
            [3466] = 4 -- Strong Flux.
        }
    },
    [10] = { -- Hands: adds SpellItemEnchantment 3723.
        profession = 164, -- Blacksmithing skill line.
        spellIDs = {114112, 55641}, -- Socket Gloves recipes.
        reagents = {
            [3466] = 4 -- Strong Flux.
        }
    }
}

-- Reagent requirement shared by every supported direct Engineering tinker.
local tinkerReagents = {
    [90146] = 1 -- Tinker's Kit.
}

-- SpellItemEnchantment ID -> direct Engineering recipe.
-- spellID is the application recipe, not the use spell observed afterward.
Materials.tinkerRecipes = {
    [4223] = { -- Nitro Boosts (waist); equipped use spell 55004.
        spellID = 55016, -- Nitro Boosts recipe.
        reagents = tinkerReagents
    },
    [4697] = { -- Phase Fingers (hands); equipped use spell 108788.
        spellID = 108789, -- Phase Fingers recipe.
        reagents = tinkerReagents
    },
    [4698] = { -- Incendiary Fireworks Launcher (hands); equipped use spell 109076.
        spellID = 109077, -- Incendiary Fireworks Launcher recipe.
        reagents = tinkerReagents
    },
    [4897] = { -- Goblin Glider (back); equipped use spell 126389.
        spellID = 126392, -- Goblin Glider recipe.
        reagents = tinkerReagents
    },
    [4898] = { -- Synapse Springs (hands); equipped use spell 126734.
        spellID = 126731, -- Synapse Springs recipe.
        reagents = tinkerReagents
    }
}

local function guidFor(bag, slot)
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(bag, slot))
    return ok and guid or nil
end

function Materials:GetProfession(skillLineID)
    local first, second = GetProfessions()
    for _, professionIndex in pairs({first, second}) do
        local name, _, _, _, numSpells, spellOffset, skillLine = GetProfessionInfo(professionIndex)
        if skillLine == skillLineID then
            local spellBookIndex = type(numSpells) == "number" and numSpells > 0 and type(spellOffset) == "number" and
                                       spellOffset + 1 or nil
            return {
                name = name,
                index = professionIndex,
                skillLine = skillLine,
                spellBookIndex = spellBookIndex
            }
        end
    end
end

local function professionAvailability(bags, recipe, inventorySlot)
    if recipe.slot and recipe.slot ~= inventorySlot or recipe.slots and not recipe.slots[inventorySlot] then
        return nil, "Direct profession recipe is not valid for this equipment slot"
    end
    local profession = Materials:GetProfession(recipe.profession)
    if not profession then
        return nil, (Materials.professionNames[recipe.profession] or "Required profession") .. " is unavailable"
    end
    for itemID, quantity in pairs(recipe.reagents or {}) do
        if (bags.counts[itemID] or 0) < quantity then
            return nil, string.format("Missing item %d (%d required)", itemID, quantity)
        end
    end
    local spellID = recipe.spellID or recipe.spellIDs and recipe.spellIDs[1]
    return recipe, nil, C_Spell.GetSpellName(spellID), profession.name, profession.spellBookIndex
end

function Materials:ScanBags()
    local result = {
        byItem = {},
        bySpell = {},
        counts = {}
    }
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local location = {
                    bag = bag,
                    slot = slot,
                    itemID = info.itemID,
                    guid = guidFor(bag, slot),
                    locked = info.isLocked,
                    link = info.hyperlink,
                    count = info.stackCount or 1
                }
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
    if itemID then
        return bags.byItem[itemID], itemID, nil
    end
    local spellID = self.enchantApplications[enchantID]
    return spellID and bags.bySpell[spellID] or nil, itemID, spellID
end

function Materials:DirectEnhancementAvailability(bags, enchantID, inventorySlot)
    local recipe = self.directEnhancements[enchantID]
    if not recipe then
        return nil
    end
    return professionAvailability(bags, recipe, inventorySlot)
end

function Materials:SocketAvailability(bags, inventorySlot)
    local recipe = self.directSockets[inventorySlot]
    if not recipe then
        return nil, "No confirmed Blacksmithing socket recipe for this slot"
    end
    return professionAvailability(bags, recipe, inventorySlot)
end

function Materials:TinkerAvailability(bags, enchantID)
    local recipe = self.tinkerRecipes[enchantID]
    if not recipe then
        return nil, "No confirmed MoP tinker recipe mapping"
    end
    local recipeName = C_Spell.GetSpellName(recipe.spellID)
    local profession = self:GetProfession(202)
    if not profession then
        return nil, "Engineering profession is unavailable"
    end
    for itemID, quantity in pairs(recipe.reagents) do
        if (bags.counts[itemID] or 0) < quantity then
            return nil, string.format("Missing item %d (%d required)", itemID, quantity)
        end
    end
    return recipe, nil, recipeName, profession.name, profession.spellBookIndex
end
