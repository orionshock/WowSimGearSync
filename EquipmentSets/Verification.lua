local _, WSGS = ...
local Modules = WSGS.Private
local shirtSlot, tabardSlot = INVSLOT_BODY, INVSLOT_TABARD
local function shown(value) return value == nil and "nil" or tostring(value) end
local Store = Modules.EquipmentSets.Store
local Verification = {}
Modules.EquipmentSets.Verification = Verification
local function ignoredState(ignored)
    if not ignored then
        return "shirt=unknown tabard=unknown"
    end
    return string.format("shirt=%s tabard=%s", ignored[shirtSlot] and "ignored" or "included",
        ignored[tabardSlot] and "ignored" or "included")
end

function Verification:MatchesState(setID, state)
    local ok, itemIDs = pcall(C_EquipmentSet.GetItemIDs, setID)
    if not ok or type(itemIDs) ~= "table" then
        return nil, "Saved item IDs are unavailable."
    end
    local mismatches = {}
    for position, slot in ipairs(Modules.Equipment.Slots) do
        local expected = state.equipped[position].id or EQUIPMENT_SET_EMPTY_SLOT
        local actual = itemIDs[slot.id]
        if actual == nil then
            actual = EQUIPMENT_SET_EMPTY_SLOT
        end
        if actual ~= expected then
            mismatches[#mismatches + 1] = slot.id .. ":" .. shown(expected) .. "/" .. shown(actual)
        end
    end
    return #mismatches == 0, #mismatches > 0 and table.concat(mismatches, ",") or nil
end

function Verification:CheckSaved(profile, setID, state, eventSeen, desiredIcon, expectedIgnored, operation)
    local info = Store:ReadInfo(setID)
    if not info then
        return nil, "The saved set could not be found after synchronization."
    end
    if info.name ~= profile.name then
        return nil, "The client saved the set as '" .. info.name .. "' instead of '" .. profile.name .. "'."
    end
    local matches, difference = self:MatchesState(setID, state)
    local iconMatch = not desiredIcon or info.icon == desiredIcon
    local resultingIgnored, ignoredProblem = Store:ReadIgnoredSlots(setID)
    WSGS:Debug(string.format(
        "[SET][VERIFY] build=%s setID=%d nameMatch=yes itemsMatch=%s desiredIcon=%s savedIcon=%s iconMatch=%s eventSeen=%s differences=%s",
        shown(profile.name), setID, matches and "yes" or "no", shown(desiredIcon), shown(info.icon),
        desiredIcon and (iconMatch and "yes" or "no") or "not-required", eventSeen and "yes" or "no", shown(difference)))
    WSGS:Debug(string.format(
        "[SET][VERIFY] build=%s setID=%d operation=%s expectedIgnored=%s resultingIgnored=%s",
        shown(profile.name), setID, shown(operation), ignoredState(expectedIgnored), ignoredState(resultingIgnored)))
    if not matches then
        return nil, "Saved set contents did not match equipped items: " .. (difference or "unknown")
    end
    if not iconMatch then
        return nil, "The client did not preserve the requested equipment set icon."
    end
    if expectedIgnored and not resultingIgnored then
        return nil, "Saved Shirt and Tabard ignored state could not be verified: " .. ignoredProblem
    end
    if expectedIgnored and (resultingIgnored[shirtSlot] ~= expectedIgnored[shirtSlot] or
        resultingIgnored[tabardSlot] ~= expectedIgnored[tabardSlot]) then
        return nil, "The client did not preserve the managed Shirt and Tabard ignored state."
    end
    return true
end

