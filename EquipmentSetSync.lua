local _, WSGS = ...
local Sync = WSGS:NewModule("EquipmentSets", "AceEvent-3.0")
WSGS.EquipmentSetSync = Sync

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
    WSGS:Debug(string.format("[SET][BLOCK] build=%s setID=%s reason=%s", shown(profile and profile.name),
        shown(profile and profile.equipmentSetID), reason))
    WSGS:Print("[SET] Equipment set not synchronized: " .. reason)
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
    local associated = setInfo(profile.equipmentSetID)
    if profile.equipmentSetID and not associated then
        WSGS:Debug(string.format("[SET][CHECK] build=%s staleSetID=%s decision=resolve-by-name", shown(profile.name),
            shown(profile.equipmentSetID)))
        profile.equipmentSetID, profile.equipmentSetName = nil, nil
    end
    local nameID = C_EquipmentSet.GetEquipmentSetID(profile.name)
    local nameMatch = setInfo(nameID)
    local exact = nameMatch and nameMatch.name == profile.name and nameMatch or nil
    if associated then
        if profile.equipmentSetName and associated.name ~= profile.equipmentSetName and associated.name ~= profile.name then
            return nil, "Associated set ID " .. associated.id .. " now belongs to '" .. associated.name .. "'."
        end
        if nameMatch and nameMatch.id ~= associated.id then
            return nil, "The name '" .. profile.name .. "' belongs to another equipment set."
        end
        return associated
    end
    if exact then
        profile.equipmentSetID, profile.equipmentSetName = exact.id, exact.name
        WSGS:Debug(string.format("[SET][CHECK] build=%s setID=%d decision=matched-exact-name", shown(profile.name),
            exact.id))
        return exact
    end
    if nameMatch then
        return nil, "The name '" .. profile.name .. "' conflicts with equipment set '" .. nameMatch.name .. "'."
    end
end

local function captureIgnoredSlots()
    local ignored = {}
    for slot = 1, 19 do
        ignored[slot] = C_EquipmentSet.IsSlotIgnoredForSave(slot)
    end
    return ignored
end

local function configureManagedSlots()
    C_EquipmentSet.ClearIgnoredSlotsForSave()
    C_EquipmentSet.IgnoreSlotForSave(4)
    C_EquipmentSet.IgnoreSlotForSave(18)
    C_EquipmentSet.IgnoreSlotForSave(19)
end

local function restoreIgnoredSlots(ignored)
    C_EquipmentSet.ClearIgnoredSlotsForSave()
    for slot = 1, 19 do
        if ignored[slot] then
            C_EquipmentSet.IgnoreSlotForSave(slot)
        end
    end
end

function Sync:CallSave(action, setID, name, icon)
    local ignored = captureIgnoredSlots()
    self.active = {
        eventSeen = false,
        action = action,
        setID = setID,
        name = name
    }
    local ok, problem = pcall(function()
        configureManagedSlots()
        if action == "CREATE" then
            C_EquipmentSet.CreateEquipmentSet(name, icon)
        else
            C_EquipmentSet.SaveEquipmentSet(setID, icon)
        end
    end)
    local restoreOK, restoreProblem = pcall(restoreIgnoredSlots, ignored)
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

function Sync:VerifySaved(profile, setID, state, eventSeen, desiredIcon)
    local info = setInfo(setID)
    if not info then
        return nil, "The saved set could not be found after synchronization."
    end
    if info.name ~= profile.name then
        return nil, "The client saved the set as '" .. info.name .. "' instead of '" .. profile.name .. "'."
    end
    local matches, difference = self:SetMatchesState(setID, state)
    local iconMatch = not desiredIcon or info.icon == desiredIcon
    WSGS:Debug(string.format(
        "[SET][VERIFY] build=%s setID=%d nameMatch=yes itemsMatch=%s desiredIcon=%s savedIcon=%s iconMatch=%s eventSeen=%s differences=%s",
        shown(profile.name), setID, matches and "yes" or "no", shown(desiredIcon), shown(info.icon),
        desiredIcon and (iconMatch and "yes" or "no") or "not-required", eventSeen and "yes" or "no", shown(difference)))
    if not matches then
        return nil, "Saved set contents did not match equipped items: " .. (difference or "unknown")
    end
    if not iconMatch then
        return nil, "The client did not apply the managed specialization icon."
    end
    profile.equipmentSetID, profile.equipmentSetName = setID, info.name
    return true
end

function Sync:Run(profile, state, batch)
    WSGS:Debug(string.format("[SET][CHECK] build=%s associatedSetID=%s decision=verify-equipment",
        shown(profile and profile.name), shown(profile and profile.equipmentSetID)))
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
    local comparison, problem = self:Check(profile, state, batch)
    if not comparison then
        return self:Block(profile, "Target equipment is not fully verified: " .. problem)
    end

    local icon, specID = specializationIcon(profile)
    WSGS:Debug(string.format("[SET][CHECK] build=%s specID=%s resolvedIcon=%s decision=%s", shown(profile.name),
        shown(specID), shown(icon), icon and "use-specialization-icon" or "preserve-existing-icon"))

    local set, resolveProblem = self:Resolve(profile)
    if resolveProblem then
        return self:Block(profile, resolveProblem)
    end
    if not set then
        if C_EquipmentSet.GetNumEquipmentSets() >= MAX_EQUIPMENT_SETS_PER_PLAYER then
            return self:Block(profile, "The Equipment Manager set limit has been reached.")
        end
        WSGS:Debug(string.format(
            "[SET][CREATE] build=%s setID=nil specID=%s icon=%s action=C_EquipmentSet.CreateEquipmentSet",
            shown(profile.name), shown(specID), shown(icon)))
        local ok, callProblem, eventSeen = self:CallSave("CREATE", nil, profile.name, icon)
        if not ok then
            return self:Block(profile, "CreateEquipmentSet failed: " .. callProblem)
        end
        local setID = C_EquipmentSet.GetEquipmentSetID(profile.name)
        if not setID then
            return self:Block(profile, "The created set was not returned by name lookup.")
        end
        local verified, verifyProblem = self:VerifySaved(profile, setID, state, eventSeen, icon)
        if not verified then
            return self:Block(profile, verifyProblem)
        end
        WSGS:Debug(string.format("[SET][CREATE] build=%s setID=%d result=verified", shown(profile.name), setID))
        return true
    end

    local changed, eventSeen = false, false
    local nameUpdate, iconUpdate = set.name ~= profile.name, icon and set.icon ~= icon or false
    WSGS:Debug(string.format(
        "[SET][CHECK] build=%s setID=%d specID=%s resolvedIcon=%s existingIcon=%s nameUpdate=%s iconUpdate=%s",
        shown(profile.name), set.id, shown(specID), shown(icon), shown(set.icon), nameUpdate and "yes" or "no",
        iconUpdate and "yes" or "no"))
    if nameUpdate or iconUpdate then
        local updatedIcon = icon or set.icon
        WSGS:Debug(string.format(
            "[SET][UPDATE] build=%s setID=%d action=C_EquipmentSet.ModifyEquipmentSet oldName=%s oldIcon=%s newIcon=%s",
            shown(profile.name), set.id, shown(set.name), shown(set.icon), shown(updatedIcon)))
        self.active = {
            eventSeen = false,
            action = "MODIFY",
            setID = set.id,
            name = profile.name
        }
        local ok, renameProblem = pcall(C_EquipmentSet.ModifyEquipmentSet, set.id, profile.name, updatedIcon)
        eventSeen = self.active.eventSeen
        self.active = nil
        if not ok then
            return self:Block(profile, "ModifyEquipmentSet failed: " .. tostring(renameProblem))
        end
        local renamed = setInfo(set.id)
        if not renamed or renamed.name ~= profile.name or icon and renamed.icon ~= icon then
            return self:Block(profile, "The client did not apply the managed set name or specialization icon.")
        end
        set, changed = renamed, true
    end

    local contentsMatch, difference = self:SetMatchesState(set.id, state)
    if contentsMatch == nil then
        return self:Block(profile, difference)
    end
    if not contentsMatch then
        WSGS:Debug(string.format(
            "[SET][UPDATE] build=%s setID=%d action=C_EquipmentSet.SaveEquipmentSet differences=%s",
            shown(profile.name), set.id, shown(difference)))
        local ok, callProblem, saveEvent = self:CallSave("UPDATE", set.id, profile.name, set.icon)
        eventSeen = eventSeen or saveEvent
        if not ok then
            return self:Block(profile, "SaveEquipmentSet failed: " .. callProblem)
        end
        changed = true
    end
    local verified, verifyProblem = self:VerifySaved(profile, set.id, state, eventSeen, icon)
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
