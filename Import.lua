local _, WSGS = ...
local JSON = WSGS.JSON

-- WoW Sims index -> MoP inventory slot ID. Shirt/tabard/ranged are excluded.
WSGS.equipmentSlots = {
    { name = "Head", id = 1 }, { name = "Neck", id = 2 },
    { name = "Shoulder", id = 3 }, { name = "Back", id = 15 },
    { name = "Chest", id = 5 }, { name = "Wrist", id = 9 },
    { name = "Hands", id = 10 }, { name = "Waist", id = 6 },
    { name = "Legs", id = 7 }, { name = "Feet", id = 8 },
    { name = "Finger 1", id = 11 }, { name = "Finger 2", id = 12 },
    { name = "Trinket 1", id = 13 }, { name = "Trinket 2", id = 14 },
    { name = "Main hand", id = 16 }, { name = "Off hand", id = 17 },
}
local supported = { id = true, enchant = true, gems = true, reforging = true,
    upgradeStep = true, tinker = true }

local function identifier(value)
    return type(value) == "number" and value >= 0 and value <= 9007199254740991
        and value == math.floor(value)
end

local function modification(value)
    return identifier(value) or (type(value) == "string" and value ~= "")
end

-- Unknown JSON values use tagged plain tables so null/empty-array distinctions
-- survive SavedVariables serialization without relying on metatables.
local function preserve(value)
    local kind = JSON.Kind(value)
    if kind == "null" then return { jsonType = "null" } end
    if kind == "array" or kind == "object" then
        local result = { jsonType = kind, value = {} }
        for key, child in pairs(value) do result.value[key] = preserve(child) end
        return result
    end
    return value
end

function WSGS:ValidateEquipment(document)
    if JSON.Kind(document) ~= "object" then return nil, "Expected a top-level JSON object." end
    if document.apiVersion ~= 3 then return nil, "Only numeric apiVersion 3 is supported." end
    if JSON.Kind(document.player) ~= "object" then return nil, "Missing player object." end
    local player = document.player
    if not ((type(player.class) == "string" and player.class:match("%S"))
        or (identifier(player.class) and player.class > 0)) then
        return nil, "player.class must be a class name or positive numeric identifier."
    end
    if JSON.Kind(player.equipment) ~= "object" then return nil, "Missing player.equipment object." end
    local items = player.equipment.items
    if JSON.Kind(items) ~= "array" then return nil, "player.equipment.items must be an array." end
    if #items > 16 then return nil, "Equipment contains more than 16 entries." end
    local equipment, warnings, equipped = {}, {}, 0
    for index = 1, 16 do
        local item = items[index]
        local slot = self.equipmentSlots[index]
        local normalized = { slotId = slot.id, slotName = slot.name, empty = true }
        equipment[index] = normalized
        if item ~= nil and item ~= JSON.null then
            if JSON.Kind(item) ~= "object" then return nil, "Item " .. index .. " must be an object or null." end
            for key, value in pairs(item) do
                local problem
                if key == "id" then
                    if not identifier(value) then problem = "id must be a non-negative integer" end
                elseif key == "gems" then
                    if JSON.Kind(value) ~= "array" then
                        problem = "gems must be an array"
                    else
                        for _, gem in ipairs(value) do
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
                    normalized.extraFields[key] = preserve(value)
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
    if #items < 16 then warnings[#warnings + 1] = "Missing trailing positions were padded as empty." end
    return { class = player.class, apiVersion = document.apiVersion, equipment = equipment,
        metadata = { entryCount = #items, equippedCount = equipped, warnings = warnings, schemaVersion = 1 } }
end

function WSGS:ImportEquipment(text, requestedName)
    self:Debug("[IMPORT] Starting import")
    local document, reason = JSON.Decode(text)
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
    profile.name = name ~= "" and name or "Imported Build " .. sequence
    profile.metadata.importedAt = time()
    profile.metadata.addonVersion = self.version
    profile.metadata.source = "WoW Sims API v3"
    global.simulationProfiles[profile.id] = profile
    global.nextSimulationProfileId = sequence + 1
    self:Debug("[IMPORT] API version: " .. profile.apiVersion)
    self:Debug("[IMPORT] Equipment entries: " .. profile.metadata.entryCount)
    self:Debug("[IMPORT] Profile saved: " .. profile.name)
    return profile
end
