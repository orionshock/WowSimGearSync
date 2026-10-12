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
    local engineering = false
    for _, index in pairs({ first, second }) do
        if select(7, GetProfessionInfo(index)) == 202 then engineering = true end
    end
    return { engineering = engineering, recommendedTinkers = WSGS.db.profile.recommendedEngineeringTinkers }
end

function Engineering:Target(item, slotId, context)
    if item.tinker ~= nil then return item.tinker, "SIMULATION" end
    if context and context.engineering and context.recommendedTinkers then
        return self.defaults[slotId], self.defaults[slotId] and "RECOMMENDED" or nil
    end
end
