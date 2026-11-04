local _, WSGS = ...
local Modules = WSGS.Private
local Sync = {}
Modules.EquipmentSets.Runtime = Sync
local shirtSlot, tabardSlot = INVSLOT_BODY, INVSLOT_TABARD

local function shown(value)
    if value == nil or value == "" then
        return "nil"
    end
    return tostring(value)
end

local function specializationIcon(profile)
    local specID = profile and profile.specialization and profile.specialization.id
    if type(specID) ~= "number" then
        return nil, specID
    end
    local ok, returnedID, _, _, icon = pcall(GetSpecializationInfoByID, specID)
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
    for position = 1, #WSGS.Equipment.Slots do
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
            shown(profile.name), position, WSGS.Equipment.Slots[position].id, physical, shown(target.id),
            shown(current.id), shown(current.guid), itemMatch and "yes" or "no",
            instance and (instanceMatch and "yes" or "no") or "not-required", verified and "VERIFIED" or "BLOCKED"))
        if not verified then
            local reason = not itemMatch and ("item state " .. result.fields.item.state) or
                               "selected item instance is not equipped"
            failures[#failures + 1] = WSGS.Equipment.Slots[position].name .. " (" .. reason .. ")"
        end
    end
    if #failures > 0 then
        return nil, table.concat(failures, ", ")
    end
    return comparison
end

function Sync:Resolve(profile)
    local setID = C_EquipmentSet.GetEquipmentSetID(profile.name)
    local set = Modules.EquipmentSets.Store:ReadInfo(setID)
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
    if profile ~= WSGS.Builds:GetActive() or not state or state.target ~= profile.equipment then
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
        local ok, callProblem, eventSeen = Modules.EquipmentSets.Store:Save("CREATE", nil, profile.name, icon, createIgnored)
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
            Modules.EquipmentSets.Store:Save("CREATE_SAVE", setID, profile.name, icon, createIgnored)
        eventSeen = eventSeen or saveEvent
        if not saved then
            return self:Block(profile, "SaveEquipmentSet after creation failed: " .. saveProblem)
        end
        local verified, verifyProblem =
            Modules.EquipmentSets.Verification:CheckSaved(profile, setID, state, eventSeen, icon, createIgnored, "CREATE")
        if not verified then
            return self:Block(profile, verifyProblem)
        end
        WSGS:Debug(string.format("[SET][CREATE] build=%s setID=%d result=verified", shown(profile.name), setID))
        return true
    end

    local existingIgnored, ignoredProblem = Modules.EquipmentSets.Store:ReadIgnoredSlots(set.id)
    WSGS:Debug(string.format(
        "[SET][CHECK] build=%s setID=%d operation=UPDATE existingIgnored=%s resultingIgnored=%s",
        shown(profile.name), set.id, ignoredState(existingIgnored), ignoredState(existingIgnored)))
    local contentsMatch, difference = Modules.EquipmentSets.Verification:MatchesState(set.id, state)
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
            Modules.EquipmentSets.Store:Save("UPDATE", set.id, profile.name, set.icon, existingIgnored)
        eventSeen = eventSeen or saveEvent
        if not ok then
            return self:Block(profile, "SaveEquipmentSet failed: " .. callProblem)
        end
        changed, operation = true, "UPDATE"
    end
    local verified, verifyProblem =
        Modules.EquipmentSets.Verification:CheckSaved(profile, set.id, state, eventSeen, set.icon, existingIgnored, operation)
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
