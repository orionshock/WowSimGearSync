local _, WSGS = ...

local supported = { id = true, enchant = true, gems = true, reforging = true,
    upgradeStep = true, tinker = true }

local function identifier(value)
    return type(value) == "number" and value >= 0 and value <= 9007199254740991
        and value == math.floor(value)
end

local function modification(value)
    return identifier(value) or (type(value) == "string" and value ~= "")
end

local function arrayLength(value)
    if type(value) ~= "table" then return nil end
    local length = 0
    for key in pairs(value) do
        if not identifier(key) or key < 1 then return nil end
        length = math.max(length, key)
    end
    return length
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

function WSGS:ValidateEquipment(document)
    if type(document) ~= "table" then return nil, "Expected a top-level JSON object." end
    if document.apiVersion ~= 3 then return nil, "Only numeric apiVersion 3 is supported." end
    if type(document.player) ~= "table" then return nil, "Missing player object." end
    -- Full simulation exports also contain buffs, rotations, encounter data,
    -- talents, and other player options. Only equipment enters the stored build.
    local player = document.player
    if not ((type(player.class) == "string" and player.class:match("%S"))
        or (identifier(player.class) and player.class > 0)) then
        return nil, "player.class must be a class name or positive numeric identifier."
    end
    if type(player.equipment) ~= "table" then return nil, "Missing player.equipment object." end
    local items = player.equipment.items
    local entryCount = arrayLength(items)
    if not entryCount then return nil, "player.equipment.items must be an array." end
    if entryCount > 16 then return nil, "Equipment contains more than 16 entries." end
    local equipment, warnings, equipped = {}, {}, 0
    for index = 1, 16 do
        local item = items[index]
        local slot = self.equipmentSlots[index]
        local normalized = { slotId = slot.id, slotName = slot.name, empty = true }
        equipment[index] = normalized
        if item ~= nil then
            if type(item) ~= "table" then return nil, "Item " .. index .. " must be an object or null." end
            for key, value in pairs(item) do
                if type(key) ~= "string" then return nil, "Item " .. index .. " must be an object." end
                local problem
                if key == "id" then
                    if not identifier(value) then problem = "id must be a non-negative integer" end
                elseif key == "gems" then
                    if not arrayLength(value) then
                        problem = "gems must be an array"
                    else
                        for gemIndex = 1, arrayLength(value) do
                            local gem = value[gemIndex]
                            if not identifier(gem) then problem = "gem IDs must be non-negative integers" end
                        end
                    end
                elseif supported[key] and not modification(value) then
                    problem = key .. " must be a non-negative integer or non-empty string"
                end
                if problem then return nil, "Item " .. index .. ": " .. problem .. "." end
                if supported[key] then
                    if key == "gems" then
                        normalized.gems = {}
                        for gemIndex, gem in ipairs(value) do normalized.gems[gemIndex] = gem end
                    else
                        normalized[key] = value
                    end
                else
                    normalized.extraFields = normalized.extraFields or {}
                    normalized.extraFields[key] = copy(value)
                    warnings[#warnings + 1] = "Item " .. index .. ": retained unsupported field " .. key:sub(1, 80) .. "."
                end
            end
            normalized.empty = not item.id or item.id == 0
            if not normalized.empty then equipped = equipped + 1 end
            if normalized.empty and next(item) then
                warnings[#warnings + 1] = "Item " .. index .. " has no equipped item ID."
            end
        end
    end
    if entryCount < 16 then warnings[#warnings + 1] = "Missing trailing positions were padded as empty." end
    return { class = player.class, specialization = self:DetectSpecialization(player), apiVersion = document.apiVersion, equipment = equipment,
        metadata = { entryCount = entryCount, equippedCount = equipped, warnings = warnings, schemaVersion = 1 } }
end

function WSGS:ImportEquipment(text, requestedName)
    self:Debug("[IMPORT] Starting import")
    local document, reason
    if type(text) ~= "string" or not text:match("%S") then
        reason = "Paste a WoW Sims JSON export first."
    elseif #text > 1048576 then
        reason = "Export exceeds the 1 MiB import limit."
    elseif not text:match("^%s*{") then
        reason = "Expected a top-level JSON object."
    else
        local ok, result = pcall(C_EncodingUtil.DeserializeJSON, text)
        if ok and type(result) == "table" then
            document = result
        else
            reason = "Invalid JSON. Check the complete export and try again."
        end
    end
    local profile
    if document then profile, reason = self:ValidateEquipment(document) end
    if not profile then
        self:Debug("[IMPORT] Import failed: " .. reason)
        return nil, reason
    end
    local name = (requestedName or ""):match("^%s*(.-)%s*$")
    if #name > 80 then
        local reason = "Profile names must be at most 80 bytes."
        self:Debug("[IMPORT] Import failed: " .. reason)
        return nil, reason
    end
    local global = self.db.global
    local sequence = global.nextSimulationProfileId or 1
    while global.simulationProfiles["import-" .. sequence] do sequence = sequence + 1 end
    profile.id = "import-" .. sequence
    local spec = profile.specialization
    local suggestion = spec.id and (spec.class .. " - " .. spec.name)
    profile.name = name ~= "" and name or suggestion or "Imported Build " .. sequence
    profile.metadata.importedAt = time()
    profile.metadata.addonVersion = self.version
    profile.metadata.source = "WoW Sims API v3"
    global.simulationProfiles[profile.id] = profile
    global.nextSimulationProfileId = sequence + 1
    global.latestSimulationProfileId = profile.id
    self:Debug("[IMPORT] API version: " .. profile.apiVersion)
    self:Debug("[IMPORT] Equipment entries: " .. profile.metadata.entryCount)
    self:Debug("[IMPORT] Profile saved: " .. profile.name)
    return profile
end
