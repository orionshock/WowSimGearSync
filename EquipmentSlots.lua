local _, WSGS = ...

-- WoW Sims index -> MoP inventory slot ID. Shirt/tabard/ranged are excluded.
WSGS.equipmentSlots = {
    { name = "Head", id = 1 }, { name = "Neck", id = 2 },
    { name = "Shoulder", id = 3 }, { name = "Back", id = 15 },
    { name = "Chest", id = 5 }, { name = "Wrist", id = 9 },
    { name = "Hands", id = 10 }, { name = "Waist", id = 6 },
    { name = "Legs", id = 7 }, { name = "Feet", id = 8 },
    { name = "Finger 1", id = 11 }, { name = "Finger 2", id = 12 },
    { name = "Trinket 1", id = 13 }, { name = "Trinket 2", id = 14 },
    { name = "Main hand", id = 16 }, { name = "Off hand", id = 17 },
}
