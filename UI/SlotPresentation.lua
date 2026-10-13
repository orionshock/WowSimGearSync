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
    label = "Item Upgrade",
    fields = {"upgradeStep"},
    texture = 237585
}, {
    key = "reforging",
    label = "Reforge",
    fields = {"reforging"},
    texture = 459028
}}

Presentation.complete = {
    key = "complete",
    label = "Configuration complete",
    texture = "Interface\\RaidFrame\\ReadyCheck-Ready"
}

local function itemValue(itemID, emptyText)
    if type(itemID) ~= "number" then
        return {
            text = "Unknown"
        }
    end
    if itemID == 0 then
        return {
            text = emptyText or "None",
            absent = true
        }
    end
    local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
    local color = quality and ITEM_QUALITY_COLORS[quality]
    return {
        text = name or ("Item " .. itemID),
        texture = texture or select(5, C_Item.GetItemInfoInstant(itemID)),
        itemID = itemID,
        color = color and {color.r, color.g, color.b} or nil
    }
end

local function spellValue(spellID, fallback)
    if type(spellID) ~= "number" then
        return {
            text = fallback or "Unknown"
        }
    end
    return {
        text = C_Spell.GetSpellName(spellID) or fallback or ("Spell " .. spellID),
        texture = C_Spell.GetSpellTexture(spellID),
        spellID = spellID
    }
end

local function effectValue(fieldName, effectID, difference)
    if type(effectID) ~= "number" then
        return {
            text = "Unknown"
        }
    end
    if effectID == 0 then
        return {
            text = "None",
            absent = true
        }
    end
    if fieldName == "tinker" and difference and difference.actualSpellID == effectID then
        return spellValue(effectID, difference.actualSpellName)
    end
    local catalog = WSGS.ModificationMaterials.actions
    local profession = catalog.profession[effectID]
    if profession then
        return spellValue(profession.spellID or profession.spellIDs and profession.spellIDs[1],
            "Effect ID " .. effectID)
    end
    local inventory = fieldName == "enchant" and catalog.inventory[effectID]
    if inventory then
        local itemID = inventory.itemID or inventory.purchasableItemID
        if itemID then
            return itemValue(itemID)
        end
        return spellValue(inventory.spellID, "Effect ID " .. effectID)
    end
    return {
        text = (fieldName == "reforging" and "Reforge ID " or "Effect ID ") .. effectID
    }
end

local function transition(state, current, target, label)
    local result = {
        label = label,
        target = target
    }
    if state == "UNKNOWN" then
        result.currentUnknown = true
    elseif not current or current.absent then
        result.apply = true
    else
        result.current = current
    end
    return result
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

local function presentationState(fieldName, field, item, actionState)
    if field.state == "MATCH" then
        return "MATCH"
    end
    if item and item.state == "MISMATCH" then
        return "BLOCKED"
    end
    if actionState and actionState.state == "BLOCKED" and actionState.nextField == fieldName then
        return "BLOCKED"
    end
    if field.state == "MISMATCH" then
        return "INCOMPLETE"
    end
    return "UNKNOWN"
end

local function socketTooltip(fieldName, field, inventorySlot)
    local target
    if fieldName == "buckle" then
        target = itemValue(WSGS.ModificationMaterials.actions.prerequisites.beltBuckle.itemID)
    elseif fieldName == "professionSocket" then
        local definition = WSGS.ModificationMaterials.actions.prerequisites.professionSockets[inventorySlot]
        if definition and definition.spellIDs then
            target = spellValue(definition.spellIDs[1], "Prismatic Socket")
        end
    end
    target = target or {
        text = "Prismatic Socket"
    }
    return {
        sections = {transition(field.actual == nil and "UNKNOWN" or field.state, nil, target)}
    }
end

local function gemTooltip(field)
    local sections = {}
    for socket, difference in ipairs(field.sockets or {}) do
        if difference.state ~= "MATCH" then
            sections[#sections + 1] = transition(difference.state, itemValue(difference.actual, "Empty"),
                itemValue(difference.expected, "Empty"), "Socket " .. socket)
        end
    end
    if #sections == 0 and type(field.expected) == "table" then
        for socket, gemID in ipairs(field.expected) do
            sections[#sections + 1] = transition("UNKNOWN", nil, itemValue(gemID, "Empty"), "Socket " .. socket)
        end
    end
    return {
        sections = sections
    }
end

local function scalarTooltip(fieldName, field)
    local current, target
    if fieldName == "upgradeStep" then
        local maximum = type(field.expected) == "number" and field.expected or nil
        current = type(field.actual) == "number" and maximum and {
            text = string.format("%d/%d", field.actual, maximum),
            texture = 237585
        } or nil
        target = {
            text = maximum and string.format("%d/%d", maximum, maximum) or "Maximum",
            texture = 237585
        }
    elseif fieldName == "reforging" then
        current = effectValue(fieldName, field.actual, field)
        target = effectValue(fieldName, field.expected, field)
        current.texture, target.texture = 459028, 459028
    else
        current = effectValue(fieldName, field.actual or field.actualSpellID, field)
        target = effectValue(fieldName, field.expected, field)
    end
    return {
        sections = {transition(field.state, current, target)}
    }
end

local function outstandingLine(fieldName, field, item, actionState)
    if item and item.state == "MISMATCH" then
        return "Target item must be equipped first."
    end
    if actionState and actionState.nextField == fieldName then
        if actionState.state == "BLOCKED" and actionState.reason then
            return actionState.reason
        elseif actionState.state == "PENDING" then
            return "Awaiting client verification."
        end
    end
    if field.state == "UNKNOWN" then
        return field.reason or "Current configuration is temporarily unavailable."
    end
end

local function configurationComplete(fields)
    if not fields.item or fields.item.state ~= "MATCH" then
        return false
    end
    for _, fieldName in ipairs(Presentation.fields) do
        if fieldName ~= "item" then
            local field = fields[fieldName]
            if not field or field.state ~= "MATCH" and field.state ~= "NOT_APPLICABLE" then
                return false
            end
        end
    end
    return true
end

function Presentation:ModificationIcons(difference, actionState)
    local result = {}
    if not difference or not difference.fields then
        return result
    end
    local item = difference.fields.item
    for _, definition in ipairs(self.modifications) do
        local fieldName, field = fieldFor(definition, difference.fields)
        local state = field and presentationState(fieldName, field, item, actionState)
        if field and state ~= "MATCH" then
            local tooltip
            if definition.key == "additionalSocket" then
                tooltip = socketTooltip(fieldName, field, difference.currentSlotId)
            elseif definition.key == "gems" then
                tooltip = gemTooltip(field)
            else
                tooltip = scalarTooltip(fieldName, field)
            end
            local outstanding = outstandingLine(fieldName, field, item, actionState)
            tooltip.note = outstanding
            local label = definition.label
            if definition.key == "additionalSocket" and fieldName == "buckle" then
                label = "Belt Buckle"
            elseif definition.key == "tinker" then
                label = fieldName == "tinker" and "Tinker" or "Profession Enhancement"
            end
            result[#result + 1] = {
                key = definition.key,
                label = label,
                texture = definition.texture,
                state = state,
                tooltip = tooltip
            }
        end
    end
    if #result == 0 and configurationComplete(difference.fields) then
        result[1] = {
            key = self.complete.key,
            label = self.complete.label,
            texture = self.complete.texture,
            state = "COMPLETE",
            tooltip = {
                sections = {}
            }
        }
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
