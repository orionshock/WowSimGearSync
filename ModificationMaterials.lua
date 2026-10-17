local _, WSGS = ...
local Materials = {}
WSGS.ModificationMaterials = Materials

-- Blizzard profession skill-line ID -> player-facing profession name.
Materials.professionNames = {
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting"
}

-- Reagent requirement shared by every supported direct Engineering tinker.
local tinkerReagents = {
    [90146] = 1 -- Tinker's Kit.
}

-- Modification data follows execution priority:
--   1. prerequisites create sockets needed by later gem actions;
--   2. inventory entries resolve finished enhancement items carried in bags;
--   3. profession entries are applied directly from an open profession window.
-- Entries within each section are clustered by profession for maintenance.
Materials.actions = {
    prerequisites = {
        -- Blacksmithing-created item; usable by any character from bags.
        beltBuckle = {
            itemID = 90046, -- Living Steel Belt Buckle.
            slot = 6 -- Waist inventory slot.
        },

        -- Blacksmithing: direct recipes that create an additional socket.
        professionSockets = {
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
    },

    -- SpellItemEnchantment ID -> finished bag item or its item-use spell.
    -- A spellID locates the matching carried scroll through C_Item.GetItemSpell.
    inventory = {
        -- Enchanting: conventional enchant scrolls.
        [4411] = {spellID = 104338, purchasableItemID = 74700}, -- Enchant Bracer - Mastery.
        [4412] = {spellID = 104385, purchasableItemID = 74701}, -- Enchant Bracer - Major Dodge.
        [4414] = {spellID = 104389, purchasableItemID = 74703}, -- Enchant Bracer - Super Intellect.
        [4415] = {spellID = 104390, purchasableItemID = 74704}, -- Enchant Bracer - Exceptional Strength.
        [4416] = {spellID = 104391, purchasableItemID = 74705}, -- Enchant Bracer - Greater Agility.
        [4417] = {spellID = 104392, purchasableItemID = 74706}, -- Enchant Chest - Super Resilience.
        [4418] = {spellID = 104393, purchasableItemID = 74707}, -- Enchant Chest - Mighty Spirit.
        [4419] = {spellID = 104395, purchasableItemID = 74708}, -- Enchant Chest - Glorious Stats.
        [4420] = {spellID = 104397, purchasableItemID = 74709}, -- Enchant Chest - Superior Stamina.
        [4421] = {spellID = 104398, purchasableItemID = 74710}, -- Enchant Cloak - Accuracy.
        [4422] = {spellID = 104401, purchasableItemID = 74711}, -- Enchant Cloak - Greater Protection.
        [4423] = {spellID = 104403, purchasableItemID = 74712}, -- Enchant Cloak - Superior Intellect.
        [4424] = {spellID = 104404, purchasableItemID = 74713}, -- Enchant Cloak - Superior Critical Strike.
        [4426] = {spellID = 104407, purchasableItemID = 74715}, -- Enchant Boots - Greater Haste.
        [4427] = {spellID = 104408, purchasableItemID = 74716}, -- Enchant Boots - Greater Precision.
        [4428] = {spellID = 104409, purchasableItemID = 74717}, -- Enchant Boots - Blurred Speed.
        [4429] = {spellID = 104414, purchasableItemID = 74718}, -- Enchant Boots - Pandaren's Step.
        [4430] = {spellID = 104416, purchasableItemID = 74719}, -- Enchant Gloves - Greater Haste.
        [4431] = {spellID = 104417, purchasableItemID = 74720}, -- Enchant Gloves - Superior Expertise.
        [4432] = {spellID = 104419, purchasableItemID = 74721}, -- Enchant Gloves - Super Strength.
        [4433] = {spellID = 104420, purchasableItemID = 74722}, -- Enchant Gloves - Superior Mastery.
        [4434] = {spellID = 104445, purchasableItemID = 74729}, -- Enchant Off-Hand - Major Intellect.
        [4441] = {spellID = 104425, purchasableItemID = 74723}, -- Enchant Weapon - Windsong.
        [4442] = {spellID = 104427, purchasableItemID = 74724}, -- Enchant Weapon - Jade Spirit.
        [4443] = {spellID = 104430, purchasableItemID = 74725}, -- Enchant Weapon - Elemental Force.
        [4444] = {spellID = 104434, purchasableItemID = 74726}, -- Enchant Weapon - Dancing Steel.
        [4445] = {spellID = 104440, purchasableItemID = 74727}, -- Enchant Weapon - Colossus.
        [4446] = {spellID = 104442, purchasableItemID = 74728}, -- Enchant Weapon - River's Song.

        -- Inscription: finished shoulder inscriptions carried in bags.
        [4803] = {itemID = 83006}, -- Greater Tiger Fang Inscription.
        [4804] = {itemID = 83007}, -- Greater Tiger Claw Inscription.
        [4805] = {itemID = 87560}, -- Greater Crane Wing Inscription.
        [4806] = {itemID = 87559}, -- Greater Ox Horn Inscription.
        [4912] = {itemID = 87581, purchasable = false}, -- Secret Ox Horn Inscription (self-only).
        [4913] = {itemID = 87585, purchasable = false}, -- Secret Tiger Fang Inscription (self-only).
        [4914] = {itemID = 87584, purchasable = false}, -- Secret Tiger Claw Inscription (self-only).
        [4915] = {itemID = 87582, purchasable = false}, -- Secret Crane Wing Inscription (self-only).

        -- Leatherworking: finished leg armor carried in bags.
        [4822] = {itemID = 83764}, -- Shadowleather Leg Armor.
        [4823] = {itemID = 83765}, -- Angerhide Leg Armor.
        [4824] = {itemID = 83763}, -- Ironscale Leg Armor.

        -- Tailoring: finished spellthreads carried in bags.
        [4825] = {itemID = 82445}, -- Greater Cerulean Spellthread.
        [4826] = {itemID = 82444} -- Greater Pearlescent Spellthread.
    },

    -- SpellItemEnchantment ID -> recipe applied directly from a profession.
    profession = {
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
        },

        -- Engineering: direct tinkers.
        [4223] = { -- Nitro Boosts (waist); equipped use spell 55004.
            profession = 202, -- Engineering skill line.
            spellID = 55016, -- Nitro Boosts recipe.
            slot = 6, -- Waist inventory slot.
            recommended = true,
            reagents = tinkerReagents
        },
        [4697] = { -- Phase Fingers (hands); equipped use spell 108788.
            profession = 202, -- Engineering skill line.
            spellID = 108789, -- Phase Fingers recipe.
            slot = 10, -- Hands inventory slot.
            reagents = tinkerReagents
        },
        [4698] = { -- Incendiary Fireworks Launcher (hands); equipped use spell 109076.
            profession = 202, -- Engineering skill line.
            spellID = 109077, -- Incendiary Fireworks Launcher recipe.
            slot = 10, -- Hands inventory slot.
            reagents = tinkerReagents
        },
        [4897] = { -- Goblin Glider (back); equipped use spell 126389.
            profession = 202, -- Engineering skill line.
            spellID = 126392, -- Goblin Glider recipe.
            slot = 15, -- Back inventory slot.
            recommended = true,
            presumedWhenOmitted = true, -- Engineers default to Goblin Glider when the import has no cloak tinker.
            reagents = tinkerReagents
        },
        [4898] = { -- Synapse Springs (hands); equipped use spell 126734.
            profession = 202, -- Engineering skill line.
            spellID = 126731, -- Synapse Springs recipe.
            slot = 10, -- Hands inventory slot.
            recommended = true,
            reagents = tinkerReagents
        },

        -- Leatherworking: Fur Linings and self-only leg reinforcements.
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

        -- Tailoring: cloak embroideries and self-only leg spellthreads.
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
        }
    }
}

-- Profession skill line -> equipment slot -> equipped-item use spell.
-- These observations identify profession effects already present on equipment;
-- they do not make an effect available for application.
Materials.equippedProfessionEffects = {
    -- Engineering.
    [202] = {
        [6] = { -- Waist.
            [55004] = {effectID = 4223}, -- Nitro Boosts.
            [131459] = {effectID = 5000} -- Watergliding Jets.
        },
        [10] = { -- Hands.
            [126734] = {effectID = 4898}, -- Synapse Springs.
            [108788] = {effectID = 4697}, -- Phase Fingers.
            [109076] = {effectID = 4698} -- Incendiary Fireworks Launcher.
        },
        [15] = { -- Back.
            [126389] = {effectID = 4897}, -- Goblin Glider.
            [55001] = {different = true, name = "Parachute"} -- Flexweave/Springy alternate; Goblin Glider takes precedence.
        }
    }
}

local function guidFor(bag, slot)
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(bag, slot))
    return ok and guid or nil
end

function Materials:ScanProfessions()
    local first, second = GetProfessions()
    local professions = {}
    for _, professionIndex in pairs({first, second}) do
        local name, _, rank, maxRank, numSpells, spellOffset, skillLine = GetProfessionInfo(professionIndex)
        if skillLine then
            professions[skillLine] = {
                name = name,
                index = professionIndex,
                rank = rank,
                maxRank = maxRank,
                skillLine = skillLine,
                spellBookIndex = type(numSpells) == "number" and numSpells > 0 and type(spellOffset) == "number" and
                    spellOffset + 1 or nil
            }
        end
    end
    return professions
end

function Materials:GetProfession(skillLineID)
    return self:ScanProfessions()[skillLineID]
end

function Materials:CharacterContext()
    local professions = self:ScanProfessions()
    local details = {}
    for skillLine, profession in pairs(professions) do
        details[#details + 1] = string.format("%s(%d)=%s/%s", profession.name or "unknown", skillLine,
            tostring(profession.rank), tostring(profession.maxRank))
    end
    table.sort(details)
    local signature = table.concat(details, ",")
    if self.professionSignature ~= signature then
        self.professionSignature = signature
        WSGS:Debug("[ACTION][PLAN] professions=" .. (signature ~= "" and signature or "none"))
    end
    return {
        professions = professions,
        recommendedProfessionEnhancements = WSGS.db.profile.recommendedEngineeringTinkers
    }
end

function Materials:RecommendedProfessionEnhancement(inventorySlot, context)
    if not context then
        return nil
    end
    for effectID, definition in pairs(self.actions.profession) do
        local validSlot = definition.slot == inventorySlot or definition.slots and definition.slots[inventorySlot]
        local enabled = definition.presumedWhenOmitted or context.recommendedProfessionEnhancements
        if definition.recommended and enabled and validSlot and context.professions[definition.profession] then
            return effectID, "RECOMMENDED"
        end
    end
end

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
    local definition = self.actions.prerequisites.beltBuckle
    return bags.byItem[definition.itemID], bags.counts[definition.itemID] or 0, definition
end

function Materials:ForInventoryEnhancement(bags, enchantID)
    local definition = self.actions.inventory[enchantID]
    if not definition then
        return nil
    end
    if definition.itemID then
        return bags.byItem[definition.itemID], definition.itemID, nil
    end
    return bags.bySpell[definition.spellID], nil, definition.spellID
end

function Materials:SocketAvailability(bags, inventorySlot, professions)
    local recipe = self.actions.prerequisites.professionSockets[inventorySlot]
    if not recipe then
        return nil, "No confirmed Blacksmithing socket recipe for this slot"
    end
    return professionAvailability(bags, recipe, inventorySlot, professions)
end

function Materials:ProfessionEnhancementAvailability(bags, enchantID, inventorySlot, professions)
    local recipe = self.actions.profession[enchantID]
    if not recipe then
        return nil, "No confirmed direct profession enhancement mapping"
    end
    return professionAvailability(bags, recipe, inventorySlot, professions)
end
