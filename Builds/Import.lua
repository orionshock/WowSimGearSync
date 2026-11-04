local _, WSGS = ...
local Modules = WSGS.Private
local Import = WSGS:NewModule("Import", "AceEvent-3.0")
Modules.Builds.Runtime = Import

local supportedFields = {
    id = true,
    enchant = true,
    tinker = true
}

local function isIdentifier(value)
    return type(value) == "number" and value >= 0 and value <= 9007199254740991 and value == math.floor(value)
end

local function arrayLength(value)
    if type(value) ~= "table" then
        return nil
    end
    local length = 0
    for key in pairs(value) do
        if not isIdentifier(key) or key < 1 then
            return nil
        end
        length = math.max(length, key)
    end
    return length
end

function Import:ValidateEquipment(document)
    if type(document) ~= "table" then
        return nil, "Expected a top-level JSON object."
    end
    if document.apiVersion ~= 2 then
        return nil, "Only numeric apiVersion 2 is supported."
    end
    if type(document.player) ~= "table" then
        return nil, "Missing player object."
    end

    local player = document.player
    if player.apiVersion ~= 2 then
        return nil, "Only numeric player.apiVersion 2 is supported."
    end
    if not ((type(player.class) == "string" and player.class:match("%S")) or
        (isIdentifier(player.class) and player.class > 0)) then
        return nil, "player.class must be a class name or positive numeric identifier."
    end
    if type(player.equipment) ~= "table" then
        return nil, "Missing player.equipment object."
    end
    local items = player.equipment.items
    local entryCount = arrayLength(items)
    if not entryCount then
        return nil, "player.equipment.items must be an array."
    end
    if entryCount > #Modules.Equipment.Slots then
        return nil, "Equipment contains more than 17 entries."
    end

    local equipment, warnings, equipped = {}, {}, 0
    for index = 1, #Modules.Equipment.Slots do
        local item = items[index]
        local slot = Modules.Equipment.Slots[index]
        local normalized = {
            slotId = slot.id,
            slotName = slot.name,
            empty = true
        }
        equipment[index] = normalized
        if item ~= nil then
            if type(item) ~= "table" then
                return nil, "Item " .. index .. " must be an object or null."
            end
            for key, value in pairs(item) do
                if type(key) ~= "string" then
                    return nil, "Item " .. index .. " must be an object."
                end
                local problem
                if key == "id" then
                    if not isIdentifier(value) then
                        problem = "id must be a non-negative integer"
                    end
                elseif supportedFields[key] and not isIdentifier(value) then
                    problem = key .. " must be a non-negative integer"
                end
                if problem then
                    return nil, "Item " .. index .. ": " .. problem .. "."
                end
                if supportedFields[key] then
                    normalized[key] = value
                else
                    warnings[#warnings + 1] = "Item " .. index .. ": ignored unsupported field " .. key:sub(1, 80) ..
                                                  "."
                end
            end
            normalized.empty = not item.id or item.id == 0
            if not normalized.empty then
                equipped = equipped + 1
            end
            if normalized.empty and next(item) then
                warnings[#warnings + 1] = "Item " .. index .. " has no equipped item ID."
            end
        end
    end
    if entryCount < #Modules.Equipment.Slots then
        warnings[#warnings + 1] = "Missing trailing positions were padded as empty."
    end
    return {
        class = player.class,
        specialization = self:DetectSpecialization(player),
        apiVersion = document.apiVersion,
        equipment = equipment,
        metadata = {
            entryCount = entryCount,
            equippedCount = equipped,
            warnings = warnings,
            schemaVersion = 1
        }
    }
end

function Import:Deserialize(text)
    if type(text) ~= "string" or not text:match("%S") then
        return nil, "Paste a WoW Sims JSON export first."
    end
    if #text > 1048576 then
        return nil, "Export exceeds the 1 MiB import limit."
    end
    if not text:match("^%s*{") then
        return nil, "Expected a top-level JSON object."
    end
    local ok, document = pcall(C_EncodingUtil.DeserializeJSON, text)
    if not ok or type(document) ~= "table" then
        return nil, "Invalid JSON. Check the complete export and try again."
    end
    return document
end

function Import:ImportInto(character, text)
    local document, reason = self:Deserialize(text)
    if not document then
        return nil, reason
    end
    local profile
    profile, reason = self:ValidateEquipment(document)
    if not profile then
        return nil, reason
    end
    profile.sourceJSON = text
    return self:SaveBuild(character, profile)
end

function Import:ImportEquipment(text)
    WSGS:Debug("[IMPORT] Starting import")
    local profile, reason = self:ImportInto(WSGS.db.char, text)
    if not profile then
        WSGS:Debug("[IMPORT] Import failed: " .. reason)
        return nil, reason
    end
    WSGS:Debug("[IMPORT] API version: " .. profile.apiVersion)
    WSGS:Debug("[IMPORT] Equipment entries: " .. profile.metadata.entryCount)
    WSGS:Debug("[IMPORT] Profile saved: " .. profile.name)
    self:SendMessage("WSGS_BUILD_IMPORTED", profile)
    return profile
end
