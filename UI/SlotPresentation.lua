local _, WSGS = ...
-- Owns player-facing translation only. Scanner/comparator remain authoritative.
local Presentation = {}
WSGS.UI.SlotPresentation = Presentation

Presentation.fields = {"item", "upgradeStep", "professionSocket", "gems", "enchant", "buckle", "tinker",
                       "reforging"}

-- Fixed presentation order. These are legacy artwork paths/file IDs available
-- in the MoP Classic client, not modern profession atlas replacements.
Presentation.modifications = {{
    key = "additionalSocket",
    label = "Additional Socket",
    fields = {"professionSocket", "buckle"},
    texture = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"
}, {
    key = "gems",
    label = "Gems",
    fields = {"gems"},
    texture = 134071 -- INV_Misc_Gem_01 / Jewelcrafting.
}, {
    key = "enchant",
    label = "Enchant",
    fields = {"enchant"},
    professionOnly = false,
    texture = 136244 -- Trade_Engraving / Enchanting.
}, {
    key = "tinker",
    label = "Profession Enhancement / Tinker",
    fields = {"tinker", "enchant"},
    professionOnly = true,
    texture = 136243 -- Trade_Engineering.
}, {
    key = "upgradeStep",
    label = "Upgrade",
    fields = {"upgradeStep"},
    texture = 237585
}, {
    key = "reforging",
    label = "Reforge",
    fields = {"reforging"},
    texture = 459028
}}

Presentation.colors = {
    MATCH = {0.30, 1.00, 0.40},
    INCOMPLETE = {1.00, 0.70, 0.15},
    BLOCKED = {1.00, 0.25, 0.25},
    UNKNOWN = {0.55, 0.70, 1.00}
}

local function itemName(itemID, emptyText)
    if type(itemID) ~= "number" then
        return "Unknown"
    end
    if itemID == 0 then
        return emptyText or "None"
    end
    return C_Item.GetItemInfo(itemID) or ("Item " .. itemID)
end

local function effectName(field, effectID, difference)
    if type(effectID) ~= "number" then
        return "Unknown"
    end
    if effectID == 0 then
        return "None"
    end
    if field == "tinker" and difference and difference.actualSpellID == effectID and difference.actualSpellName then
        return difference.actualSpellName
    end
    local catalog = WSGS.ModificationMaterials.actions
    local definition = catalog.profession[effectID] or field == "enchant" and catalog.inventory[effectID]
    local spellID = definition and (definition.spellID or definition.spellIDs and definition.spellIDs[1])
    local name = spellID and C_Spell.GetSpellName(spellID)
    return name or (field == "reforging" and "Reforge ID " or "Effect ID ") .. effectID
end

local function addPair(lines, current, target)
    lines[#lines + 1] = "Current: " .. current
    lines[#lines + 1] = "Target: " .. target
end

local function fieldFor(definition, fields)
    for _, name in ipairs(definition.fields) do
        local field = fields[name]
        local professionEnhancement = name == "enchant" and field and field.expected and
                                            WSGS.ModificationMaterials.actions.profession[field.expected] ~= nil or false
        local selected = name ~= "enchant" or definition.professionOnly == nil or
                             definition.professionOnly == professionEnhancement
        if selected and field and field.state ~= "NOT_APPLICABLE" then
            return name, field
        end
    end
end

local function fieldMatches(definition, fieldName)
    if not fieldName then
        return false
    end
    for _, candidate in ipairs(definition.fields) do
        if candidate == fieldName then
            return true
        end
    end
    return false
end

local function presentationState(definition, field, item, actionState)
    if item and item.state == "MISMATCH" then
        return "BLOCKED"
    end
    if actionState and actionState.state == "BLOCKED" and fieldMatches(definition, actionState.nextField) then
        return "BLOCKED"
    end
    if field.state == "MATCH" then
        return "MATCH"
    end
    if field.state == "MISMATCH" then
        return "INCOMPLETE"
    end
    return "UNKNOWN"
end

local function socketLines(fieldName, field)
    local lines = {}
    local present = field.state == "MATCH"
    if fieldName == "buckle" then
        lines[1] = "Belt Buckle"
    elseif fieldName == "professionSocket" then
        lines[1] = "Blacksmithing Socket"
    end
    addPair(lines, present and "Present" or field.actual == nil and "Unknown" or "Missing",
        present and "Present" or "Prismatic Socket")
    return lines
end

local function gemLines(field)
    local lines = {}
    for socket, difference in ipairs(field.sockets or {}) do
        lines[#lines + 1] = "Socket " .. socket
        addPair(lines, itemName(difference.actual, "Empty"), itemName(difference.expected, "Empty"))
    end
    if #lines == 0 and type(field.expected) == "table" then
        for socket, gemID in ipairs(field.expected) do
            lines[#lines + 1] = "Socket " .. socket
            addPair(lines, "Unknown", itemName(gemID, "Empty"))
        end
    end
    if #lines == 0 then
        addPair(lines, "Unknown", "Configured gems")
    end
    return lines
end

local function scalarLines(fieldName, field)
    local lines = {}
    if fieldName == "upgradeStep" then
        local maximum = type(field.expected) == "number" and field.expected or nil
        local current = type(field.actual) == "number" and maximum and string.format("%d/%d", field.actual, maximum) or
                            "Unknown"
        local target = maximum and string.format("%d/%d", maximum, maximum) or "Maximum"
        addPair(lines, current, target)
    elseif fieldName == "reforging" then
        addPair(lines, effectName(fieldName, field.actual, field), effectName(fieldName, field.expected, field))
    else
        local current = field.actualSpellName or effectName(fieldName, field.actual or field.actualSpellID, field)
        addPair(lines, current, effectName(fieldName, field.expected, field))
        if fieldName == "tinker" and field.targetSource then
            lines[#lines + 1] = field.targetSource == "RECOMMENDED" and "Source: Recommended Engineering default" or
                                    "Source: WoW Sims export"
        end
    end
    return lines
end

local function outstandingLine(definition, field, item, actionState)
    if item and item.state == "MISMATCH" then
        return "Target item must be equipped first."
    end
    if actionState and fieldMatches(definition, actionState.nextField) then
        if actionState.state == "BLOCKED" and actionState.reason then
            return actionState.reason
        elseif actionState.state == "PENDING" then
            return "Awaiting client verification."
        end
    end
    if field.state == "UNKNOWN" then
        return field.reason or "Current configuration is temporarily unavailable."
    end
    if field.state == "MISMATCH" then
        return "Configuration incomplete."
    end
end

function Presentation:ModificationIcons(difference, actionState)
    local result = {}
    if not difference or not difference.fields then
        return result
    end
    local item = difference.fields.item
    for _, definition in ipairs(self.modifications) do
        local fieldName, field = fieldFor(definition, difference.fields)
        if field then
            local lines
            if definition.key == "additionalSocket" then
                lines = socketLines(fieldName, field)
            elseif definition.key == "gems" then
                lines = gemLines(field)
            else
                lines = scalarLines(fieldName, field)
            end
            if definition.key == "tinker" and fieldName == "enchant" then
                lines[#lines + 1] = "Source: WoW Sims export"
            end
            local outstanding = outstandingLine(definition, field, item, actionState)
            if outstanding then
                lines[#lines + 1] = outstanding
            end
            result[#result + 1] = {
                key = definition.key,
                label = definition.label,
                texture = definition.texture,
                state = presentationState(definition, field, item, actionState),
                lines = lines
            }
        end
    end
    return result
end

function Presentation:ItemTooltip(target, actionState)
    if not target then
        return "No target item", 0.65, 0.65, 0.65, "Import a WoW Sims build"
    end
    if target.empty or not target.id or target.id == 0 then
        return "Empty slot", 0.65, 0.65, 0.65, actionState.clickText
    end
    local name, _, quality = C_Item.GetItemInfo(target.id)
    local color = quality and ITEM_QUALITY_COLORS[quality]
    return name or ("Item " .. target.id), color and color.r or 1, color and color.g or 1,
        color and color.b or 1, actionState.clickText
end
