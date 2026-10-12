local _, WSGS = ...
local Comparator = {}
WSGS.EquipmentComparator = Comparator
local fields = {"professionSocket", "gems", "enchant", "reforging", "upgradeStep", "tinker", "buckle"}
local socketDiagnostics = {}

local function requestedSocketCount(gems)
    local count = 0
    if type(gems) ~= "table" then
        return count
    end
    for index, gemID in ipairs(gems) do
        if type(gemID) == "number" and gemID > 0 then
            count = index
        end
    end
    return count
end

local function debugSocket(position, slotId, kind, eligible, targetCount, actualCount, difference)
    local signature = table.concat({kind, tostring(eligible), tostring(targetCount), tostring(actualCount),
                                    difference.state, difference.reason or difference.source or ""}, ":")
    if socketDiagnostics[position] == signature then
        return
    end
    socketDiagnostics[position] = signature
    WSGS:Debug(string.format(
        "[ACTION][PLAN] slot=%d type=%s eligible=%s targetSockets=%s equippedSockets=%s state=%s source=%s", slotId,
        kind, tostring(eligible), tostring(targetCount), tostring(actualCount), difference.state,
        difference.reason or difference.source or "target-versus-equipped socket count"))
end

local function scalar(expected, observed)
    if not observed or observed.status == "UNKNOWN" then
        return {
            state = "UNKNOWN",
            expected = expected,
            reason = observed and observed.reason or "Observation missing"
        }
    end
    if observed.status ~= "KNOWN" then
        return {
            state = "UNKNOWN",
            expected = expected,
            reason = "Required modification could not be observed"
        }
    end
    if type(expected) ~= type(observed.value) then
        return {
            state = "UNKNOWN",
            expected = expected,
            actual = observed.value,
            reason = "Modification representations have no verified conversion"
        }
    end
    return {
        state = expected == observed.value and "MATCH" or "MISMATCH",
        expected = expected,
        actual = observed.value,
        source = observed.source
    }
end

function Comparator:CompareSlot(target, current, position, currentPosition, context)
    local slot = WSGS.equipmentSlots[position]
    local result = {
        position = position,
        slotName = slot.name,
        targetSlotId = slot.id,
        currentPosition = currentPosition,
        currentSlotId = WSGS.equipmentSlots[currentPosition].id,
        fields = {}
    }
    local observations = current and current.observations or {}
    local item = observations.item
    local emptyTarget = target.empty or not target.id or target.id == 0
    if not item or item.status ~= "KNOWN" then
        result.fields.item = {
            state = "UNKNOWN",
            expected = target.id,
            reason = "Equipped item identity unknown"
        }
    else
        local matches = emptyTarget and item.present == false or not emptyTarget and item.value == target.id
        result.fields.item = {
            state = matches and "MATCH" or "MISMATCH",
            expected = target.id,
            actual = item.value,
            expectedEmpty = emptyTarget,
            actualEmpty = item.present == false
        }
    end
    for _, field in ipairs(fields) do
        local expected = target[field]
        local targetSource
        if field == "tinker" then
            expected, targetSource = target.tinker, target.tinker ~= nil and "SIMULATION" or nil
            if expected == nil then
                expected, targetSource =
                    WSGS.ModificationMaterials:RecommendedProfessionEnhancement(slot.id, context)
            end
        end
        if field == "professionSocket" then
            expected = nil
        elseif field == "buckle" then
            local buckle = WSGS.ModificationMaterials.actions.prerequisites.beltBuckle
            expected = slot.id == buckle.slot and requestedSocketCount(target.gems) > 0 or nil
        end
        local difference
        if field == "professionSocket" and not emptyTarget then
            local socket = WSGS.ModificationMaterials.actions.prerequisites.professionSockets[slot.id]
            local eligible = socket and context and context.professions and
                                 context.professions[socket.profession] ~= nil
            local targetCount = requestedSocketCount(target.gems)
            local socketCount = observations.socketCount
            local actualCount = socketCount and socketCount.status == "KNOWN" and socketCount.value or nil
            if not socket or targetCount == 0 then
                difference = {
                    state = "NOT_APPLICABLE",
                    reason = "Target does not require a profession socket"
                }
            elseif not eligible then
                difference = {
                    state = "NOT_APPLICABLE",
                    reason = "Character does not have " ..
                        (WSGS.ModificationMaterials.professionNames[socket.profession] or "the required profession")
                }
            elseif actualCount == nil then
                difference = {
                    state = "UNKNOWN",
                    expected = targetCount,
                    reason = socketCount and socketCount.reason or "Equipped socket count unavailable"
                }
            else
                difference = {
                    state = actualCount >= targetCount and "MATCH" or "MISMATCH",
                    expected = targetCount,
                    actual = actualCount,
                    source = "Imported gem count versus equipped socket count"
                }
            end
            if socket then
                debugSocket(position, slot.id, "PROFESSION_SOCKET", eligible, targetCount, actualCount, difference)
            end
        elseif field == "upgradeStep" and not emptyTarget then
            local eligibility = observations.upgradeEligibility
            local maximum = observations.upgradeMaximum
            difference = {
                state = "UNKNOWN",
                policy = "MAXIMUM",
                normalMaximum = 2,
                reason = "Upgrade eligibility and maximum are not established"
            }
            if result.fields.item.state ~= "MATCH" then
                difference.reason = "Target item is not confirmed in this slot"
            elseif eligibility and eligibility.status == "KNOWN" and eligibility.value == false then
                difference = {
                    state = "NOT_APPLICABLE",
                    policy = "MAXIMUM",
                    reason = "Item is known not to support upgrades"
                }
            elseif eligibility and eligibility.status == "KNOWN" and eligibility.value == true then
                if maximum and maximum.status == "KNOWN" and type(maximum.value) == "number" and maximum.value > 0 then
                    difference = scalar(maximum.value, observations.upgradeStep)
                    difference.policy = "MAXIMUM"
                    difference.remaining = observations.upgradeRemaining and observations.upgradeRemaining.value
                    difference.progressState = observations.upgradeState and observations.upgradeState.value
                else
                    difference.reason = "Upgradeable item maximum is unknown (normally 2)"
                end
            end
        elseif field == "buckle" and not emptyTarget and expected then
            local targetCount = requestedSocketCount(target.gems)
            local socketCount = observations.socketCount
            local actualCount = socketCount and socketCount.status == "KNOWN" and socketCount.value or nil
            if actualCount ~= nil then
                difference = {
                    state = actualCount >= targetCount and "MATCH" or "MISMATCH",
                    expected = targetCount,
                    actual = actualCount,
                    source = "Imported gem count versus equipped socket count"
                }
            else
                difference = {
                    state = "UNKNOWN",
                    expected = targetCount,
                    actual = nil,
                    reason = socketCount and socketCount.reason or "Equipped socket count is unavailable"
                }
            end
            debugSocket(position, slot.id, "BUCKLE", true, targetCount, actualCount, difference)
        elseif field == "tinker" and not emptyTarget and expected ~= nil and result.fields.item.state == "MATCH" and
            observations.tinker and observations.tinker.status == "KNOWN" and observations.tinker.different then
            difference = {
                state = "MISMATCH",
                expected = expected,
                actualSpellID = observations.tinker.spellId,
                actualSpellName = observations.tinker.spellName,
                source = observations.tinker.source
            }
        elseif emptyTarget or expected == nil or field == "gems" and next(expected) == nil then
            difference = {
                state = "NOT_APPLICABLE",
                reason = "Target does not specify this modification"
            }
        elseif result.fields.item.state ~= "MATCH" then
            difference = {
                state = "UNKNOWN",
                expected = expected,
                reason = "Target item is not confirmed in this slot"
            }
        elseif field == "gems" then
            difference = {
                state = "MATCH",
                sockets = {}
            }
            local gems = observations.gems
            for index, gem in ipairs(expected) do
                local observed = gems and gems.values and gems.values[index]
                local socket = scalar(gem, observed)
                difference.sockets[index] = socket
                if socket.state == "MISMATCH" then
                    difference.state = "MISMATCH"
                elseif socket.state == "UNKNOWN" and difference.state ~= "MISMATCH" then
                    difference.state = "UNKNOWN"
                end
            end
        else
            difference = scalar(expected, observations[field])
        end
        difference.targetSource = targetSource
        result.fields[field] = difference
    end
    return result
end

local function score(first, second)
    local items, modifications = 0, 0
    for _, slot in ipairs({first, second}) do
        if slot.fields.item.state == "MISMATCH" then
            items = items + 1
        end
        for _, field in ipairs(fields) do
            if slot.fields[field].state == "MISMATCH" then
                modifications = modifications + 1
            end
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
    local result = {
        profileId = profile.id,
        profileName = profile.name,
        slots = {},
        assignments = {},
        summary = {
            matched = 0,
            itemMismatches = 0,
            configurationMismatches = 0,
            unknown = 0
        }
    }
    for position = 1, 16 do
        local target = profile.equipment[position]
        if not target then
            return nil, "Imported build is missing equipment position " .. position .. "."
        end
        result.slots[position] =
            self:CompareSlot(target, snapshot.slots[position], position, position, snapshot.context)
        result.assignments[position] = position
    end
    for _, pair in ipairs({{11, 12}, {13, 14}}) do
        local a, b = pair[1], pair[2]
        local swappedA = self:CompareSlot(profile.equipment[a], snapshot.slots[b], a, b, snapshot.context)
        local swappedB = self:CompareSlot(profile.equipment[b], snapshot.slots[a], b, a, snapshot.context)
        local directItems, directMods = score(result.slots[a], result.slots[b])
        local swappedItems, swappedMods = score(swappedA, swappedB)
        local bothMatch =
            result.slots[a].fields.item.state == "MATCH" and result.slots[b].fields.item.state == "MATCH" and
                swappedA.fields.item.state == "MATCH" and swappedB.fields.item.state == "MATCH"
        if swappedItems < directItems or bothMatch and swappedMods < directMods then
            result.slots[a], result.slots[b] = swappedA, swappedB
            result.assignments[a], result.assignments[b] = b, a
        end
    end
    for _, slot in ipairs(result.slots) do
        local summary = result.summary
        if slot.fields.item.state == "MATCH" then
            summary.matched = summary.matched + 1
        elseif slot.fields.item.state == "MISMATCH" then
            summary.itemMismatches = summary.itemMismatches + 1
        else
            summary.unknown = summary.unknown + 1
        end
        for _, field in ipairs(fields) do
            local difference = slot.fields[field]
            if difference.state == "MISMATCH" then
                summary.configurationMismatches = summary.configurationMismatches + 1
            end
            if field == "gems" and difference.sockets then
                for _, socket in ipairs(difference.sockets) do
                    if socket.state == "UNKNOWN" then
                        summary.unknown = summary.unknown + 1
                    end
                end
            elseif difference.state == "UNKNOWN" then
                summary.unknown = summary.unknown + 1
            end
        end
    end
    return result
end
