local _, WSGS = ...
local Engineering = {}
WSGS.Engineering = Engineering

-- Local MoP SpellItemEnchantment data; names/IDs are not inferred from tooltips.
Engineering.defaults = { [10] = 4898, [15] = 4897, [6] = 4223 }
Engineering.effects = {
    [10] = { [126734] = 4898, [108788] = 4697, [109076] = 4698 },
    [15] = { [126389] = 4897 },
    [6] = { [55004] = 4223 },
}

function Engineering:CharacterContext()
    local first, second = GetProfessions()
    local professions = {}
    for _, index in pairs({ first, second }) do
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
        if skillLine then professions[skillLine] = { name = name, rank = rank, maxRank = maxRank } end
    end
    local details = {}
    for skillLine, profession in pairs(professions) do
        details[#details + 1] = string.format("%s(%d)=%s/%s", profession.name or "unknown", skillLine,
            tostring(profession.rank), tostring(profession.maxRank))
    end
    table.sort(details)
    local signature = table.concat(details, ",")
    if self.professionSignature ~= signature then
        self.professionSignature = signature
        WSGS:Debug(string.format("[ACTION][PLAN] professions=%s engineering=%s blacksmithing=%s",
            signature ~= "" and signature or "none", tostring(professions[202] ~= nil),
            tostring(professions[164] ~= nil)))
    end
    return { engineering = professions[202] ~= nil, blacksmithing = professions[164] ~= nil,
        recommendedTinkers = WSGS.db.profile.recommendedEngineeringTinkers }
end

function Engineering:Target(item, slotId, context)
    if item.tinker ~= nil then return item.tinker, "SIMULATION" end
    if context and context.engineering and context.recommendedTinkers then
        return self.defaults[slotId], self.defaults[slotId] and "RECOMMENDED" or nil
    end
end
