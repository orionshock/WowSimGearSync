local _, WSGS = ...
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
-- Owns player-facing translation only. Scanner/comparator remain authoritative.
local Presentation = {}
WSGS.UI.SlotPresentation = Presentation

Presentation.fields = {"item", "enchant", "tinker"}
Presentation.modifications = {{
    key = "enchant", label = "Enchant", fields = {"enchant"},
    professionOnly = false, texture = 136244
}, {
    key = "tinker", label = "Profession Enhancement / Tinker", fields = {"tinker", "enchant"},
    professionOnly = true, texture = 136243
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
        text = name or "Required material",
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
        text = C_Spell.GetSpellName(spellID) or fallback or "Required enhancement",
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
        return spellValue(profession.spellID,
            "Profession enhancement")
    end
    local inventory = fieldName == "enchant" and catalog.inventory[effectID]
    if inventory then
        local itemID = inventory.itemID or inventory.purchasableItemID
        if itemID then
            return itemValue(itemID)
        end
        return spellValue(inventory.spellID, "Enchantment")
    end
    return {
        text = "Enhancement"
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

local function scalarTooltip(fieldName, field)
    local current = effectValue(fieldName, field.actual or field.actualSpellID, field)
    local target = effectValue(fieldName, field.expected, field)
    return {sections = {transition(field.state, current, target)}}
end

local function outstandingLine(fieldName, field, item, actionState)
    if item and item.state == "MISMATCH" then
        return "Target item must be equipped first."
    end
    if actionState and actionState.nextField == fieldName then
        if actionState.state == "BLOCKED" and actionState.reason then
            return WSGS:FormatPlayerReason(actionState.reason)
        elseif actionState.state == "PENDING" then
            return "Waiting for the item to update."
        end
    end
    if field.state == "UNKNOWN" then
        return WSGS:FormatPlayerReason(field.reason) or L["Item information isn't available yet."]
    end
end

function Presentation:IsConfigurationComplete(difference)
    local fields = difference and difference.fields
    if not fields then
        return false
    end
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
    if not item or item.state ~= "MATCH" then
        return result
    end
    for _, definition in ipairs(self.modifications) do
        local fieldName, field = fieldFor(definition, difference.fields)
        local state = field and presentationState(fieldName, field, item, actionState)
        if field and state ~= "MATCH" then
            local tooltip = scalarTooltip(fieldName, field)
            local outstanding = outstandingLine(fieldName, field, item, actionState)
            tooltip.note = outstanding
            local label = definition.label
            if definition.key == "tinker" then
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
    if #result == 0 and self:IsConfigurationComplete(difference) then
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
    local instruction = WSGS:FormatPlayerReason(actionState.clickText)
    if not target then
        return "No target item", 0.65, 0.65, 0.65, "Import a WoW Sims build"
    end
    if target.empty or not target.id or target.id == 0 then
        return "Empty slot", 0.65, 0.65, 0.65, instruction
    end
    local name, _, quality = C_Item.GetItemInfo(target.id)
    local color = quality and ITEM_QUALITY_COLORS[quality]
    return name or "Target item", color and color.r or 1, color and color.g or 1,
        color and color.b or 1, instruction
end
