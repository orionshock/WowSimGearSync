local _, WSGS = ...
local Internal = WSGS.ActionsInternal or {}
WSGS.ActionsInternal = Internal

local Presentation = {}
Internal.Presentation = Presentation

local labels = {
    BUCKLE = "belt buckle",
    GEM = "gem",
    ENCHANT = "enchant",
    PROFESSION_ENCHANT = "profession enhancement",
    PROFESSION_SOCKET = "Prismatic Socket",
    TINKER = "Engineering tinker"
}

local function itemName(itemID, fallback)
    if type(itemID) ~= "number" or itemID <= 0 then
        return fallback
    end
    return C_Item.GetItemInfo(itemID) or fallback or "Required material"
end

local function operationName(operation)
    if not operation then
        return nil
    end
    if operation.type == "GEM" then
        return itemName(operation.expected, "Required gem")
    end
    if operation.type == "BUCKLE" then
        return itemName(operation.materialItemID, "belt buckle")
    end
    if operation.type == "PROFESSION_SOCKET" then
        return labels.PROFESSION_SOCKET
    end
    if operation.spellName then
        return operation.spellName
    end
    local spellName = operation.spellID and C_Spell.GetSpellName(operation.spellID)
    return spellName or labels[operation.type] or "modification"
end

local function clickInstruction(operation)
    local name = operationName(operation)
    if not operation then
        return nil
    elseif operation.type == "GEM" then
        return "Insert " .. name
    elseif operation.type == "PROFESSION_SOCKET" then
        return "Add " .. name
    end
    return "Apply " .. name
end

local function actionText(controller, operation)
    if not controller then
        return "Click to recheck"
    end
    if controller.state == "WAITING_FOR_ITEM" then
        return "Target item must be equipped before modifications are available"
    end
    local instruction = clickInstruction(operation)
    if controller.state == "READY" and instruction then
        return "Click: " .. instruction
    end
    if controller.state == "PENDING" and instruction then
        return instruction .. "..."
    end
    if controller.state == "UNKNOWN" then
        return "Click to recheck"
    end
    if controller.state == "BLOCKED" then
        return controller.reason or operation and operation.reason or "Modification blocked"
    end
    for _, fieldName in ipairs({"upgradeStep", "reforging"}) do
        local field = controller.difference and controller.difference.fields[fieldName]
        if field and (field.state == "MISMATCH" or field.state == "UNKNOWN") then
            return "No click action available"
        end
    end
    return "Configuration complete"
end

function Presentation:Build(controller, operation)
    local clickText = actionText(controller, operation)
    return {
        state = controller and controller.state or "COMPLETE",
        pending = controller and controller.state == "PENDING" or false,
        clickText = clickText,
        tooltipLines = {clickText},
        nextField = operation and operation.field or nil,
        nextType = operation and operation.type or nil,
        reason = controller and (controller.reason or operation and operation.reason) or nil
    }
end
