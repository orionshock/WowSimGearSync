local _, WSGS = ...
local Materials = {}
WSGS.ModificationMaterials = Materials

Materials.beltBuckleItemID = 90046
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
    [4411] = 104338,
    [4412] = 104385,
    [4414] = 104389,
    [4415] = 104390,
    [4416] = 104391,
    [4417] = 104392,
    [4418] = 104393,
    [4419] = 104395,
    [4420] = 104397,
    [4421] = 104398,
    [4422] = 104401,
    [4423] = 104403,
    [4424] = 104404,
    [4426] = 104407,
    [4427] = 104408,
    [4428] = 104409,
    [4429] = 104414,
    [4430] = 104416,
    [4431] = 104417,
    [4432] = 104419,
    [4433] = 104420,
    [4441] = 104425,
    [4442] = 104427,
    [4443] = 104430,
    [4434] = 104445,
    [4444] = 104434,
    [4445] = 104440,
    [4446] = 104442
}

-- Enhancements whose usable material has a stable, locally verified item ID.
Materials.enchantItems = {
    [4803] = 83006,
    [4804] = 83007,
    [4805] = 87560,
    [4806] = 87559,
    [4822] = 83764,
    [4823] = 83765,
    [4824] = 83763,
    [4825] = 82445,
    [4826] = 82444,
    -- Secret inscriptions are finished BoP items. Their profession recipes
    -- create these items, so only already-carried copies use the item path.
    [4912] = 87581,
    [4913] = 87585,
    [4914] = 87584,
    [4915] = 87582
}

-- Direct item-targeting profession recipes only. Recipe creation of scrolls,
-- kits, spellthreads, inscriptions, or other intermediate items is excluded.
Materials.directEnhancements = {
    -- Tailoring: cloak embroideries and tailor-only leg spellthreads.
    [4892] = {
        profession = 197,
        spellID = 125481,
        slot = 15,
        reagents = {
            [38426] = 3
        }
    },
    [4893] = {
        profession = 197,
        spellID = 125482,
        slot = 15,
        reagents = {
            [38426] = 3
        }
    },
    [4894] = {
        profession = 197,
        spellID = 125483,
        slot = 15,
        reagents = {
            [38426] = 3
        }
    },
    [4895] = {
        profession = 197,
        spellID = 125496,
        slot = 7,
        reagents = {
            [38426] = 3
        }
    },
    [4896] = {
        profession = 197,
        spellID = 125497,
        slot = 7,
        reagents = {
            [38426] = 3
        }
    },
    -- Leatherworking: Fur Linings and leatherworker-only leg reinforcements.
    [4875] = {
        profession = 165,
        spellID = 124551,
        slot = 9,
        reagents = {
            [38426] = 1
        }
    },
    [4877] = {
        profession = 165,
        spellID = 124552,
        slot = 9,
        reagents = {
            [38426] = 1
        }
    },
    [4878] = {
        profession = 165,
        spellID = 124553,
        slot = 9,
        reagents = {
            [38426] = 1
        }
    },
    [4879] = {
        profession = 165,
        spellID = 124554,
        slot = 9,
        reagents = {
            [38426] = 1
        }
    },
    [4880] = {
        profession = 165,
        spellID = 124559,
        slot = 7,
        reagents = {
            [38426] = 1
        }
    },
    [4881] = {
        profession = 165,
        spellID = 124561,
        slot = 7,
        reagents = {
            [38426] = 1
        }
    },
    [4882] = {
        profession = 165,
        spellID = 124563,
        slot = 7,
        reagents = {
            [38426] = 1
        }
    },
    -- Enchanting: enchanter-only ring enchants.
    [4359] = {
        profession = 333,
        spellID = 103461,
        slots = {
            [11] = true,
            [12] = true
        },
        reagents = {
            [74249] = 2
        }
    },
    [4360] = {
        profession = 333,
        spellID = 103462,
        slots = {
            [11] = true,
            [12] = true
        },
        reagents = {
            [74249] = 2
        }
    },
    [4361] = {
        profession = 333,
        spellID = 103463,
        slots = {
            [11] = true,
            [12] = true
        },
        reagents = {
            [74249] = 2
        }
    },
    [4807] = {
        profession = 333,
        spellID = 103465,
        slots = {
            [11] = true,
            [12] = true
        },
        reagents = {
            [74249] = 2
        }
    }
}

Materials.directSockets = {
    [9] = {
        profession = 164,
        spellIDs = {113263, 55628},
        reagents = {
            [3466] = 4
        }
    },
    [10] = {
        profession = 164,
        spellIDs = {114112, 55641},
        reagents = {
            [3466] = 4
        }
    }
}

-- SpellItemEnchantment ID -> profession recipe and required carried reagents.
-- spellID is the application recipe, not the use spell observed after application.
Materials.tinkerRecipes = {
    [4223] = { -- Nitro Boosts (waist); equipped use spell 55004.
        spellID = 55016, -- Engineering recipe: Nitro Boosts.
        reagents = {
            [39690] = 6, -- Volatile Blasting Trigger.
            [39681] = 6 -- Handful of Cobalt Bolts.
        }
    },
    [4697] = { -- Phase Fingers (hands); equipped use spell 108788.
        spellID = 108789, -- Engineering recipe: Phase Fingers.
        reagents = {
            [90146] = 1 -- Tinker's Kit.
        }
    },
    [4698] = { -- Incendiary Fireworks Launcher (hands); equipped use spell 109076.
        spellID = 109077, -- Engineering recipe: Incendiary Fireworks Launcher.
        reagents = {
            [90146] = 1 -- Tinker's Kit.
        }
    },
    [4897] = { -- Goblin Glider (back); equipped use spell 126389.
        spellID = 126392, -- Engineering recipe: Goblin Glider.
        reagents = {
            [90146] = 1 -- Tinker's Kit.
        }
    },
    [4898] = { -- Synapse Springs (hands); equipped use spell 126734.
        spellID = 126731, -- Engineering recipe: Synapse Springs.
        reagents = {
            [90146] = 1 -- Tinker's Kit.
        }
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
