local _, WSGS = ...
local Import = WSGS.Import

-- Player oneof fields from the WoW Sims MoP protobuf schema. Numeric IDs are
-- Blizzard specialization IDs, not simulation enum values.
local classes = {
    { "Warrior", 1, { { "armsWarrior", "Arms", 71 }, { "furyWarrior", "Fury", 72 }, { "protectionWarrior", "Protection", 73 } } },
    { "Paladin", 2, { { "holyPaladin", "Holy", 65 }, { "protectionPaladin", "Protection", 66 }, { "retributionPaladin", "Retribution", 70 } } },
    { "Hunter", 3, { { "beastMasteryHunter", "Beast Mastery", 253 }, { "marksmanshipHunter", "Marksmanship", 254 }, { "survivalHunter", "Survival", 255 } } },
    { "Rogue", 4, { { "assassinationRogue", "Assassination", 259 }, { "combatRogue", "Combat", 260 }, { "subtletyRogue", "Subtlety", 261 } } },
    { "Priest", 5, { { "disciplinePriest", "Discipline", 256 }, { "holyPriest", "Holy", 257 }, { "shadowPriest", "Shadow", 258 } } },
    { "Death Knight", 6, { { "bloodDeathKnight", "Blood", 250 }, { "frostDeathKnight", "Frost", 251 }, { "unholyDeathKnight", "Unholy", 252 } } },
    { "Shaman", 7, { { "elementalShaman", "Elemental", 262 }, { "enhancementShaman", "Enhancement", 263 }, { "restorationShaman", "Restoration", 264 } } },
    { "Mage", 8, { { "arcaneMage", "Arcane", 62 }, { "fireMage", "Fire", 63 }, { "frostMage", "Frost", 64 } } },
    { "Warlock", 9, { { "afflictionWarlock", "Affliction", 265 }, { "demonologyWarlock", "Demonology", 266 }, { "destructionWarlock", "Destruction", 267 } } },
    { "Monk", 10, { { "brewmasterMonk", "Brewmaster", 268 }, { "mistweaverMonk", "Mistweaver", 270 }, { "windwalkerMonk", "Windwalker", 269 } } },
    { "Druid", 11, { { "balanceDruid", "Balance", 102 }, { "feralDruid", "Feral", 103 }, { "guardianDruid", "Guardian", 104 }, { "restorationDruid", "Restoration", 105 } } },
}

function Import:DetectSpecialization(player)
    local className, match, count, invalid = "Unknown", nil, 0, false
    for _, class in ipairs(classes) do
        local enumName = "Class" .. class[1]:gsub(" ", "")
        local matchesClass = player.class == enumName or player.class == class[2]
        if matchesClass then className = class[1] end
        for _, specialization in ipairs(class[3]) do
            if player[specialization[1]] ~= nil then
                count = count + 1
                local value = player[specialization[1]]
                if type(value) ~= "table" then
                    invalid = true
                else
                    for key in pairs(value) do
                        if type(key) ~= "string" then invalid = true end
                    end
                end
                if not matchesClass then invalid = true end
                match = {
                    class = class[1],
                    name = specialization[2],
                    id = specialization[3],
                    source = "player." .. specialization[1],
                }
            end
        end
    end
    if count == 1 and not invalid then return match end
    local source = count > 1 and "ambiguous" or (invalid and "invalid" or "missing")
    return { class = className, name = "Unspecified", source = source }
end
