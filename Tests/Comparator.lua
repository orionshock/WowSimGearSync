local _, WSGS = ...
-- Deterministic domain tests use synthetic snapshots, never replace client APIs.
local function scenario()
    local profile, snapshot = { equipment = {} }, { slots = {} }
    for position = 1, 16 do
        profile.equipment[position] = { id = 1000 + position }
        snapshot.slots[position] = { observations = {
            item = { status = "KNOWN", value = 1000 + position, present = true },
            upgradeEligibility = { status = "KNOWN", value = false },
        } }
    end
    return profile, snapshot
end
local function compare(profile, snapshot) return assert(WSGS.EquipmentComparator:Compare(profile, snapshot)) end
WSGS.Tests:Register("comparator", "Comparator", {
    { name = "Exact items and nonupgradeable gear", run = function()
        local profile, snapshot = scenario()
        local result = compare(profile, snapshot)
        assert(result.summary.matched == 16 and result.summary.itemMismatches == 0 and result.summary.unknown == 0)
        assert(result.slots[14].fields.upgradeStep.state == "NOT_APPLICABLE")
    end },
    { name = "0/2, 1/2, 2/2 and actual maximum", run = function()
        for _, pair in ipairs({ {0,2}, {1,2}, {2,2}, {1,4}, {4,4} }) do
            local profile, snapshot = scenario()
            local o = snapshot.slots[3].observations
            o.upgradeEligibility = { status = "KNOWN", value = true }
            o.upgradeStep = { status = "KNOWN", value = pair[1] }
            o.upgradeMaximum = { status = "KNOWN", value = pair[2] }
            o.upgradeRemaining = { status = "KNOWN", value = pair[2] - pair[1] }
            local field = compare(profile, snapshot).slots[3].fields.upgradeStep
            assert(field.state == (pair[1] == pair[2] and "MATCH" or "MISMATCH"))
            assert(field.expected == pair[2] and field.remaining == pair[2] - pair[1])
        end
    end },
    { name = "Unknown observations never mismatch", run = function()
        local profile, snapshot = scenario()
        profile.equipment[3].enchant = 4803
        snapshot.slots[3].observations.upgradeEligibility = { status = "UNKNOWN" }
        local fields = compare(profile, snapshot).slots[3].fields
        assert(fields.upgradeStep.state == "UNKNOWN" and fields.enchant.state == "UNKNOWN")
    end },
    { name = "Wrong item blocks modification matches", run = function()
        local profile, snapshot = scenario()
        profile.equipment[3].enchant = 4803
        snapshot.slots[3].observations.item.value = 99999
        snapshot.slots[3].observations.enchant = { status = "KNOWN", value = 4803 }
        local fields = compare(profile, snapshot).slots[3].fields
        assert(fields.item.state == "MISMATCH" and fields.enchant.state == "UNKNOWN" and fields.upgradeStep.state == "UNKNOWN")
    end },
    { name = "Swapped rings and trinkets are bijective", run = function()
        local profile, snapshot = scenario()
        snapshot.slots[11], snapshot.slots[12] = snapshot.slots[12], snapshot.slots[11]
        snapshot.slots[13], snapshot.slots[14] = snapshot.slots[14], snapshot.slots[13]
        local result = compare(profile, snapshot)
        assert(result.summary.matched == 16)
        assert(result.assignments[11] == 12 and result.assignments[12] == 11
            and result.assignments[13] == 14 and result.assignments[14] == 13)
    end },
    { name = "Duplicate rings prefer matching modifications", run = function()
        local profile, snapshot = scenario()
        profile.equipment[11], profile.equipment[12] = { id = 1001, enchant = 10 }, { id = 1001, enchant = 20 }
        for position = 11, 12 do snapshot.slots[position].observations.item.value = 1001 end
        snapshot.slots[11].observations.enchant = { status = "KNOWN", value = 20 }
        snapshot.slots[12].observations.enchant = { status = "KNOWN", value = 10 }
        local result = compare(profile, snapshot)
        assert(result.assignments[11] == 12 and result.assignments[12] == 11)
        assert(result.slots[11].fields.enchant.state == "MATCH" and result.slots[12].fields.enchant.state == "MATCH")
    end },
    { name = "Captured links preserve gems and reforges", run = function()
        local profile, snapshot = scenario()
        profile.equipment[3] = { id = 99027, reforging = 167, gems = {76699,76699} }
        local decoded = assert(WSGS.ItemLinkDecoder:Decode("item:99027:4803:76699:76699:::::90:160:66::::::::"))
        snapshot.slots[3].observations.item.value = decoded.id
        snapshot.slots[3].observations.gems, snapshot.slots[3].observations.reforging = decoded.gems, decoded.reforging
        local fields = compare(profile, snapshot).slots[3].fields
        assert(fields.reforging.state == "MISMATCH" and fields.gems.state == "MATCH")
        local cloak = assert(WSGS.ItemLinkDecoder:Decode("item:102250:4424:76667::::::90:131:66::::::::"))
        profile.equipment[4] = { id = 102250, gems = {76699} }
        snapshot.slots[4].observations.item.value = cloak.id
        snapshot.slots[4].observations.gems = cloak.gems
        assert(compare(profile, snapshot).slots[4].fields.gems.state == "MISMATCH")
    end },
    { name = "Empty target and missing profile", run = function()
        local profile, snapshot = scenario()
        profile.equipment[16] = { empty = true }
        snapshot.slots[16].observations.item = { status = "KNOWN", present = false }
        assert(compare(profile, snapshot).slots[16].fields.item.state == "MATCH")
        local result, reason = WSGS.EquipmentComparator:Compare(nil, snapshot)
        assert(not result and reason)
    end },
    { name = "Required waist buckle matches and missing buckle counts", run = function()
        for _, present in ipairs({ true, false }) do
            local profile, snapshot = scenario()
            profile.equipment[8].gems = { 10, 20, 30 }
            local decoded = assert(WSGS.ItemLinkDecoder:Decode("item:1008::10:20:30::::90:0"))
            snapshot.slots[8].observations.gems = decoded.gems
            snapshot.slots[8].observations.buckle = { status = "KNOWN", value = present }
            local result = compare(profile, snapshot)
            assert(result.slots[8].fields.buckle.state == (present and "MATCH" or "MISMATCH"))
            assert(result.summary.configurationMismatches == (present and 0 or 1))
        end
    end },
    { name = "Buckle is waist-only and third gem must be populated", run = function()
        local profile, snapshot = scenario()
        profile.equipment[1].gems = { 10, 20, 30 }
        profile.equipment[8].gems = { 10, 20, 0 }
        local result = compare(profile, snapshot)
        assert(result.slots[1].fields.buckle.state == "NOT_APPLICABLE")
        assert(result.slots[8].fields.buckle.state == "NOT_APPLICABLE")
        profile.equipment[8].gems[3] = 30
        assert(compare(profile, snapshot).slots[8].fields.buckle.state == "UNKNOWN")
        snapshot.slots[8].observations.item.value = 99999
        snapshot.slots[8].observations.buckle = { status = "KNOWN", value = true }
        assert(compare(profile, snapshot).slots[8].fields.buckle.state == "UNKNOWN")
    end },
    { name = "Recommended Engineering glove cloak and waist defaults", run = function()
        local profile, snapshot = scenario()
        snapshot.context = { engineering = true, recommendedTinkers = true }
        for position, id in pairs({ [7] = 4898, [4] = 4897, [8] = 4223 }) do
            snapshot.slots[position].observations.tinker = { status = "KNOWN", value = id }
        end
        local result = compare(profile, snapshot)
        for position, id in pairs({ [7] = 4898, [4] = 4897, [8] = 4223 }) do
            local value = result.slots[position].fields.tinker
            assert(value.state == "MATCH" and value.expected == id and value.targetSource == "RECOMMENDED")
            assert(profile.equipment[position].tinker == nil, "Recommendation changed imported data")
        end
    end },
    { name = "Explicit simulation tinkers override recommendations", run = function()
        local profile, snapshot = scenario()
        snapshot.context = { engineering = true, recommendedTinkers = true }
        profile.equipment[7].tinker = 4697
        snapshot.slots[7].observations.tinker = { status = "KNOWN", value = 4697 }
        local value = compare(profile, snapshot).slots[7].fields.tinker
        assert(value.expected == 4697 and value.state == "MATCH" and value.targetSource == "SIMULATION")
    end },
    { name = "Non-Engineers and disabled recommendations have no defaults", run = function()
        for _, context in ipairs({
            { engineering = false, recommendedTinkers = true },
            { engineering = true, recommendedTinkers = false },
        }) do
            local profile, snapshot = scenario()
            snapshot.context = context
            local result = compare(profile, snapshot)
            for _, position in ipairs({4,7,8}) do assert(result.slots[position].fields.tinker.state == "NOT_APPLICABLE") end
            profile.equipment[7].tinker = 4898
            assert(compare(profile, snapshot).slots[7].fields.tinker.expected == 4898)
        end
    end },
    { name = "Missing defaults are actionable but unknowns never mismatch", run = function()
        local profile, snapshot = scenario()
        snapshot.context = { engineering = true, recommendedTinkers = true }
        for _, position in ipairs({4,7,8}) do snapshot.slots[position].observations.tinker = { status = "KNOWN", value = 0 } end
        assert(compare(profile, snapshot).summary.configurationMismatches == 3)
        snapshot.slots[4].observations.tinker = { status = "UNKNOWN" }
        local result = compare(profile, snapshot)
        assert(result.slots[4].fields.tinker.state == "UNKNOWN" and result.summary.configurationMismatches == 2)
        snapshot.slots[7].observations.item.value = 99999
        assert(compare(profile, snapshot).slots[7].fields.tinker.state == "UNKNOWN")
    end },
    { name = "Waist buckle and tinker remain independent", run = function()
        local profile, snapshot = scenario()
        snapshot.context = { engineering = true, recommendedTinkers = true }
        profile.equipment[8].gems = { 10, 20, 30 }
        local o = snapshot.slots[8].observations
        o.gems = { values = { {status="KNOWN",value=10}, {status="KNOWN",value=20}, {status="KNOWN",value=30} } }
        o.buckle, o.tinker = { status = "KNOWN", value = true }, { status = "KNOWN", value = 0 }
        local fields = compare(profile, snapshot).slots[8].fields
        assert(fields.buckle.state == "MATCH" and fields.tinker.state == "MISMATCH")
        o.buckle.value, o.tinker.value = false, 4223
        fields = compare(profile, snapshot).slots[8].fields
        assert(fields.buckle.state == "MISMATCH" and fields.tinker.state == "MATCH")
    end },
})
