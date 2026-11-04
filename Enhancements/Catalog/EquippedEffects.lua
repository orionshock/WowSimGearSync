local _, WSGS = ...
local Modules = WSGS.Private
local Catalog = Modules.Enhancements.Catalog

Catalog.equippedProfessionEffects = {
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
            [55001] = {different = true, name = "Parachute"} -- Alternate parachute effect.
        }
    }
}
