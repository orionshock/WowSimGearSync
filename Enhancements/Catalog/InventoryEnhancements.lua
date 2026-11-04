local _, WSGS = ...
local Modules = WSGS.Private
local Catalog = Modules.Enhancements.Catalog

Catalog.inventory = {
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
}
