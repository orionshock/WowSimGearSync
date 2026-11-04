local _, WSGS = ...
local Modules = WSGS.Private
local Catalog = Modules.Enhancements.Catalog

local tinkerReagents = {[90146] = 1}
Catalog.profession = {
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
            reagents = tinkerReagents
        },
        [4898] = { -- Synapse Springs (hands); equipped use spell 126734.
            profession = 202, -- Engineering skill line.
            spellID = 126731, -- Synapse Springs recipe.
            slot = 10, -- Hands inventory slot.
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
