local _, WSGS = ...
local Comparator = {}
WSGS.EquipmentComparator = Comparator
local fields = { "gems", "enchant", "reforging", "upgradeStep", "tinker" }

local function scalar(expected, observed)
    if not observed or observed.status == "UNKNOWN" then
        return { state = "UNKNOWN", expected = expected, reason = observed and observed.reason or "Observation missing" }
    end
    if observed.status ~= "KNOWN" then
        return { state = "UNKNOWN", expected = expected, reason = "Required modification could not be observed" }
    end
    if type(expected) ~= type(observed.value) then
        return { state = "UNKNOWN", expected = expected, actual = observed.value,
            reason = "Modification representations have no verified conversion" }
    end
    return { state = expected == observed.value and "MATCH" or "MISMATCH",
        expected = expected, actual = observed.value, source = observed.source }
end

local function compareSlot(target, current, position, currentPosition)
    local slot = WSGS.equipmentSlots[position]
    local result = { position = position, slotName = slot.name, targetSlotId = slot.id,
        currentPosition = currentPosition, currentSlotId = WSGS.equipmentSlots[currentPosition].id, fields = {} }
    local observations = current and current.observations or {}
    local item = observations.item
    local emptyTarget = target.empty or not target.id or target.id == 0
    if not item or item.status ~= "KNOWN" then
        result.fields.item = { state = "UNKNOWN", expected = target.id, reason = "Equipped item identity unknown" }
    else
        local matches = emptyTarget and item.present == false or not emptyTarget and item.value == target.id
        result.fields.item = { state = matches and "MATCH" or "MISMATCH", expected = target.id,
            actual = item.value, expectedEmpty = emptyTarget, actualEmpty = item.present == false }
    end
    for _, field in ipairs(fields) do
        local expected = target[field]
        local difference
        if field == "upgradeStep" and not emptyTarget then
            local eligibility = observations.upgradeEligibility
            local maximum = observations.upgradeMaximum
            difference = { state = "UNKNOWN", policy = "MAXIMUM", normalMaximum = 2,
                reason = "Upgrade eligibility and maximum are not established" }
            if result.fields.item.state ~= "MATCH" then
                difference.reason = "Target item is not confirmed in this slot"
            elseif eligibility and eligibility.status == "KNOWN" and eligibility.value == false then
                difference = { state = "NOT_APPLICABLE", policy = "MAXIMUM", reason = "Item is known not to support upgrades" }
            elseif eligibility and eligibility.status == "KNOWN" and eligibility.value == true then
                if maximum and maximum.status == "KNOWN" and type(maximum.value) == "number" and maximum.value > 0 then
                    difference = scalar(maximum.value, observations.upgradeStep)
                    difference.policy = "MAXIMUM"
                else
                    difference.reason = "Upgradeable item maximum is unknown (normally 2)"
                end
            end
        elseif emptyTarget or expected == nil or field == "gems" and next(expected) == nil then
            difference = { state = "NOT_APPLICABLE", reason = "Target does not specify this modification" }
        elseif result.fields.item.state ~= "MATCH" then
            difference = { state = "UNKNOWN", expected = expected, reason = "Target item is not confirmed in this slot" }
        elseif field == "gems" then
            difference = { state = "MATCH", sockets = {} }
            local gems = observations.gems
            for index, gem in ipairs(expected) do
                local observed = gems and gems.values and gems.values[index]
                local socket = scalar(gem, observed)
                difference.sockets[index] = socket
                if socket.state == "MISMATCH" then difference.state = "MISMATCH"
                elseif socket.state == "UNKNOWN" and difference.state ~= "MISMATCH" then difference.state = "UNKNOWN" end
            end
        else
            difference = scalar(expected, observations[field])
        end
        result.fields[field] = difference
    end
    return result
end

local function score(first, second)
    local items, modifications = 0, 0
    for _, slot in ipairs({ first, second }) do
        if slot.fields.item.state == "MISMATCH" then items = items + 1 end
        for _, field in ipairs(fields) do
            if slot.fields[field].state == "MISMATCH" then modifications = modifications + 1 end
        end
    end
    return items, modifications
end

function Comparator:Compare(profile, snapshot)
    if type(profile) ~= "table" or type(profile.equipment) ~= "table" then
        return nil, "Import a WoW Sims build before comparing equipment."
    end
    if type(snapshot) ~= "table" or type(snapshot.slots) ~= "table" then
        return nil, "Equipment snapshot is unavailable."
    end
    local result = { profileId = profile.id, profileName = profile.name, slots = {}, assignments = {},
        summary = { matched = 0, itemMismatches = 0, configurationMismatches = 0, unknown = 0 } }
    for position = 1, 16 do
        local target = profile.equipment[position]
        if not target then return nil, "Imported build is missing equipment position " .. position .. "." end
        result.slots[position] = compareSlot(target, snapshot.slots[position], position, position)
        result.assignments[position] = position
    end
    for _, pair in ipairs({ { 11, 12 }, { 13, 14 } }) do
        local a, b = pair[1], pair[2]
        local swappedA = compareSlot(profile.equipment[a], snapshot.slots[b], a, b)
        local swappedB = compareSlot(profile.equipment[b], snapshot.slots[a], b, a)
        local directItems, directMods = score(result.slots[a], result.slots[b])
        local swappedItems, swappedMods = score(swappedA, swappedB)
        local bothMatch = result.slots[a].fields.item.state == "MATCH" and result.slots[b].fields.item.state == "MATCH"
            and swappedA.fields.item.state == "MATCH" and swappedB.fields.item.state == "MATCH"
        if swappedItems < directItems or bothMatch and swappedMods < directMods then
            result.slots[a], result.slots[b] = swappedA, swappedB
            result.assignments[a], result.assignments[b] = b, a
        end
    end
    for _, slot in ipairs(result.slots) do
        local summary = result.summary
        if slot.fields.item.state == "MATCH" then summary.matched = summary.matched + 1
        elseif slot.fields.item.state == "MISMATCH" then summary.itemMismatches = summary.itemMismatches + 1
        else summary.unknown = summary.unknown + 1 end
        for _, field in ipairs(fields) do
            local difference = slot.fields[field]
            if difference.state == "MISMATCH" then summary.configurationMismatches = summary.configurationMismatches + 1 end
            if field == "gems" and difference.sockets then
                for _, socket in ipairs(difference.sockets) do
                    if socket.state == "UNKNOWN" then summary.unknown = summary.unknown + 1 end
                end
            elseif difference.state == "UNKNOWN" then summary.unknown = summary.unknown + 1 end
        end
    end
    return result
end
