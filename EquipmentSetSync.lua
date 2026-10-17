local _, WSGS = ...
local Sync = WSGS:NewModule("EquipmentSets", "AceEvent-3.0")
WSGS.EquipmentSetSync = Sync
local shirtSlot, rangedSlot, tabardSlot = INVSLOT_BODY, INVSLOT_RANGED, INVSLOT_TABARD

local function shown(value)
    if value == nil or value == "" then
        return "nil"
    end
    return tostring(value)
end

local function setInfo(setID)
    if type(setID) ~= "number" then
        return nil
    end
    local ok, name, icon, returnedID = pcall(C_EquipmentSet.GetEquipmentSetInfo, setID)
    if not ok or type(name) ~= "string" or returnedID ~= setID then
        return nil
    end
    return {
        id = setID,
        name = name,
        icon = icon
    }
end

local function specializationIcon(profile)
    local specID = profile and profile.specialization and profile.specialization.id
    if type(specID) ~= "number" then
        return nil, specID
    end
    local ok, returnedID, _, _, icon = pcall(GetSpecializationInfoForSpecID, specID)
    if not ok or returnedID ~= specID or type(icon) ~= "number" or icon <= 0 then
        return nil, specID
    end
    return icon, specID
end

function Sync:Block(profile, reason)
    WSGS:Debug(string.format("[SET][BLOCK] build=%s reason=%s", shown(profile and profile.name), reason))
    WSGS:Print("[SET] Equipment set not saved: " .. WSGS:FormatPlayerReason(reason))
    return nil, reason
end

function Sync:Check(profile, state, batch)
    local comparison = state and state.comparison
    if not comparison then
        return nil, state and state.reason or "Equipment State is unavailable."
    end
    local instanceByTarget = {}
    for _, record in ipairs(batch and batch.records or {}) do
        local operation = record.operation
        if operation.kind == "EQUIP" and operation.source.guid then
            instanceByTarget[operation.targetPosition] = {
                guid = operation.source.guid,
                position = operation.position
            }
        end
    end
    local failures = {}
    for position = 1, 16 do
        local target = profile.equipment[position]
        local result = comparison.slots[position]
        local physical = comparison.assignments[position]
        local current = state.equipped[physical]
        local itemMatch = result.fields.item.state == "MATCH"
        local instance = instanceByTarget[position]
        local instanceMatch = not instance or state.equipped[instance.position].guid == instance.guid
        local verified = itemMatch and instanceMatch
        WSGS:Debug(string.format(
            "[SET][CHECK] build=%s pos=%d inv=%d physical=%d target=%s observed=%s GUID=%s itemMatch=%s instanceMatch=%s result=%s",
            shown(profile.name), position, WSGS.equipmentSlots[position].id, physical, shown(target.id),
            shown(current.id), shown(current.guid), itemMatch and "yes" or "no",
            instance and (instanceMatch and "yes" or "no") or "not-required", verified and "VERIFIED" or "BLOCKED"))
        if not verified then
            local reason = not itemMatch and ("item state " .. result.fields.item.state) or
                               "selected item instance is not equipped"
            failures[#failures + 1] = WSGS.equipmentSlots[position].name .. " (" .. reason .. ")"
        end
    end
    if #failures > 0 then
        return nil, table.concat(failures, ", ")
    end
    return comparison
end

function Sync:Resolve(profile)
    local setID = C_EquipmentSet.GetEquipmentSetID(profile.name)
    local set = setInfo(setID)
    if setID and (not set or set.name ~= profile.name) then
        return nil, "The equipment set name could not be verified."
    end
    return set
end

local function ignoredState(ignored)
    if not ignored then
        return "shirt=unknown tabard=unknown"
    end
    return string.format("shirt=%s tabard=%s", ignored[shirtSlot] and "ignored" or "included",
        ignored[tabardSlot] and "ignored" or "included")
end

local function readSetIgnoredSlots(setID)
    local ok, ignored = pcall(C_EquipmentSet.GetIgnoredSlots, setID)
    if not ok or type(ignored) ~= "table" then
        return nil, "saved ignored-slot state is unavailable"
    end
    if type(ignored[shirtSlot]) ~= "boolean" or type(ignored[tabardSlot]) ~= "boolean" then
        return nil, "saved Shirt or Tabard ignored state is incomplete"
    end
    return {
        [shirtSlot] = ignored[shirtSlot],
        [tabardSlot] = ignored[tabardSlot]
    }
end

local function captureSaveSelection()
    local ignored = {}
    for slot = 1, 19 do
        ignored[slot] = C_EquipmentSet.IsSlotIgnoredForSave(slot)
    end
    return ignored
end

local function configureManagedSlots(ignored)
    C_EquipmentSet.ClearIgnoredSlotsForSave()
    C_EquipmentSet.IgnoreSlotForSave(rangedSlot)
    if ignored[shirtSlot] then
        C_EquipmentSet.IgnoreSlotForSave(shirtSlot)
    end
    if ignored[tabardSlot] then
        C_EquipmentSet.IgnoreSlotForSave(tabardSlot)
    end
end

local function restoreSaveSelection(ignored)
    C_EquipmentSet.ClearIgnoredSlotsForSave()
    for slot = 1, 19 do
        if ignored[slot] then
            C_EquipmentSet.IgnoreSlotForSave(slot)
        end
    end
end

function Sync:CallSave(action, setID, name, icon, managedIgnored)
    local saveSelection = captureSaveSelection()
    self.active = {
        eventSeen = false,
        action = action,
        setID = setID,
        name = name
    }
    local ok, problem = pcall(function()
        configureManagedSlots(managedIgnored)
        if action == "CREATE" then
            C_EquipmentSet.CreateEquipmentSet(name, icon)
        else
            C_EquipmentSet.SaveEquipmentSet(setID, icon)
        end
    end)
    local restoreOK, restoreProblem = pcall(restoreSaveSelection, saveSelection)
    local eventSeen = self.active.eventSeen
    self.active = nil
    if not ok then
        return nil, tostring(problem), eventSeen
    end
    if not restoreOK then
        return nil, "Could not restore Equipment Manager ignored slots: " .. tostring(restoreProblem), eventSeen
    end
    return true, nil, eventSeen
end

function Sync:SetMatchesState(setID, state)
    local ok, itemIDs = pcall(C_EquipmentSet.GetItemIDs, setID)
    if not ok or type(itemIDs) ~= "table" then
        return nil, "Saved item IDs are unavailable."
    end
    local mismatches = {}
    for position, slot in ipairs(WSGS.equipmentSlots) do
        local expected = state.equipped[position].id or EQUIPMENT_SET_EMPTY_SLOT or 0
        local actual = itemIDs[slot.id]
        if actual == nil then
            actual = EQUIPMENT_SET_EMPTY_SLOT or 0
        end
        if actual ~= expected then
            mismatches[#mismatches + 1] = slot.id .. ":" .. shown(expected) .. "/" .. shown(actual)
        end
    end
    return #mismatches == 0, #mismatches > 0 and table.concat(mismatches, ",") or nil
end

function Sync:VerifySaved(profile, setID, state, eventSeen, desiredIcon, expectedIgnored, operation)
    local info = setInfo(setID)
    if not info then
        return nil, "The saved set could not be found after synchronization."
    end
    if info.name ~= profile.name then
        return nil, "The client saved the set as '" .. info.name .. "' instead of '" .. profile.name .. "'."
    end
    local matches, difference = self:SetMatchesState(setID, state)
    local iconMatch = not desiredIcon or info.icon == desiredIcon
    local resultingIgnored, ignoredProblem = readSetIgnoredSlots(setID)
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

function Sync:Run(profile, state, batch)
    if not WSGS.db.profile.equipmentSets then
        return true
    end
    WSGS:Debug(string.format("[SET][CHECK] build=%s decision=verify-equipment", shown(profile and profile.name)))
    if not profile or type(profile.name) ~= "string" or profile.name == "" then
        return self:Block(profile, "The managed build has no usable name.")
    end
    if strlenutf8(profile.name) > 16 then
        return self:Block(profile,
            "Equipment Manager names are limited to 16 characters; rename the managed build before synchronizing.")
    end
    if not C_EquipmentSet.CanUseEquipmentSets() then
        return self:Block(profile, "Equipment Manager is unavailable for this character.")
    end
    if profile ~= WSGS:GetActiveSimulationProfile() or not state or state.target ~= profile.equipment then
        return self:Block(profile, "The active import changed; verify its equipment again.")
    end
    for _, record in ipairs(batch and batch.records or {}) do
        if record.status ~= "VERIFIED" then
            return self:Block(profile, "Equipment changes are not fully verified yet.")
        end
    end
    local comparison, problem = self:Check(profile, state, batch)
    if not comparison then
        return self:Block(profile, "Target equipment is not fully verified: " .. problem)
    end

    local set, resolveProblem = self:Resolve(profile)
    if resolveProblem then
        return self:Block(profile, resolveProblem)
    end
    if not set then
        local icon, specID = specializationIcon(profile)
        if C_EquipmentSet.GetNumEquipmentSets() >= MAX_EQUIPMENT_SETS_PER_PLAYER then
            return self:Block(profile, "The Equipment Manager set limit has been reached.")
        end
        local createIgnored = {
            [shirtSlot] = true,
            [tabardSlot] = true
        }
        WSGS:Debug(string.format(
            "[SET][CREATE] build=%s setID=nil specID=%s icon=%s action=C_EquipmentSet.CreateEquipmentSet existingIgnored=%s resultingIgnored=%s",
            shown(profile.name), shown(specID), shown(icon), ignoredState(nil), ignoredState(createIgnored)))
        local ok, callProblem, eventSeen = self:CallSave("CREATE", nil, profile.name, icon, createIgnored)
        if not ok then
            return self:Block(profile, "CreateEquipmentSet failed: " .. callProblem)
        end
        local setID = C_EquipmentSet.GetEquipmentSetID(profile.name)
        if not setID then
            return self:Block(profile, "The created set was not returned by name lookup.")
        end
        WSGS:Debug(string.format(
            "[SET][CREATE] build=%s setID=%d action=C_EquipmentSet.SaveEquipmentSet reason=apply-ignored-slots resultingIgnored=%s",
            shown(profile.name), setID, ignoredState(createIgnored)))
        local saved, saveProblem, saveEvent =
            self:CallSave("CREATE_SAVE", setID, profile.name, icon, createIgnored)
        eventSeen = eventSeen or saveEvent
        if not saved then
            return self:Block(profile, "SaveEquipmentSet after creation failed: " .. saveProblem)
        end
        local verified, verifyProblem =
            self:VerifySaved(profile, setID, state, eventSeen, icon, createIgnored, "CREATE")
        if not verified then
            return self:Block(profile, verifyProblem)
        end
        WSGS:Debug(string.format("[SET][CREATE] build=%s setID=%d result=verified", shown(profile.name), setID))
        return true
    end

    local existingIgnored, ignoredProblem = readSetIgnoredSlots(set.id)
    WSGS:Debug(string.format(
        "[SET][CHECK] build=%s setID=%d operation=UPDATE existingIgnored=%s resultingIgnored=%s",
        shown(profile.name), set.id, ignoredState(existingIgnored), ignoredState(existingIgnored)))
    local contentsMatch, difference = self:SetMatchesState(set.id, state)
    if contentsMatch == nil then
        return self:Block(profile, difference)
    end
    if not contentsMatch and not existingIgnored then
        return self:Block(profile, "Cannot update equipment without preserving Shirt and Tabard: " .. ignoredProblem)
    end
    local changed, eventSeen = false, false
    local operation = "CHECK"

    if not contentsMatch then
        WSGS:Debug(string.format(
            "[SET][UPDATE] build=%s setID=%d action=C_EquipmentSet.SaveEquipmentSet differences=%s existingIgnored=%s resultingIgnored=%s",
            shown(profile.name), set.id, shown(difference), ignoredState(existingIgnored), ignoredState(existingIgnored)))
        local ok, callProblem, saveEvent =
            self:CallSave("UPDATE", set.id, profile.name, set.icon, existingIgnored)
        eventSeen = eventSeen or saveEvent
        if not ok then
            return self:Block(profile, "SaveEquipmentSet failed: " .. callProblem)
        end
        changed, operation = true, "UPDATE"
    end
    local verified, verifyProblem =
        self:VerifySaved(profile, set.id, state, eventSeen, set.icon, existingIgnored, operation)
    if not verified then
        return self:Block(profile, verifyProblem)
    end
    WSGS:Debug(string.format("[SET][UPDATE] build=%s setID=%d result=%s", shown(profile.name), set.id,
        changed and "verified" or "already-current"))
    return true
end

function Sync:Synchronize(profile, state, batch)
    local ok, result, reason = pcall(self.Run, self, profile, state, batch)
    if not ok then
        return self:Block(profile, "Equipment Manager API error: " .. tostring(result))
    end
    return result, reason
end

function Sync:EQUIPMENT_SETS_CHANGED()
    if self.active then
        self.active.eventSeen = true
        WSGS:Debug(string.format("[SET][VERIFY] build=%s setID=%s event=EQUIPMENT_SETS_CHANGED action=%s",
            shown(self.active.name), shown(self.active.setID), shown(self.active.action)))
    end
end

function Sync:OnEnable()
    self:RegisterEvent("EQUIPMENT_SETS_CHANGED")
end
