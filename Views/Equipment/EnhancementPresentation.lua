local _, WSGS = ...
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
local Internal = WSGS.ActionsInternal or {}
WSGS.ActionsInternal = Internal

local Presentation = {}
Internal.Presentation = Presentation

local labels = {
    ENCHANT = "enchant",
    PROFESSION_ENCHANT = "profession enhancement",
    TINKER = "Engineering tinker"
}

local function operationName(operation)
    if not operation then
        return nil
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
        local blocker = controller.reason or operation and operation.reason or "Modification blocked"
        return blocker
    end
    return "Configuration complete"
end

function Presentation:Build(controller, operation)
    local clickText = actionText(controller, operation)
    return {
        state = controller and controller.state or "COMPLETE",
        pending = controller and controller.state == "PENDING" or false,
        clickText = clickText,
        nextField = operation and operation.field or nil,
        nextType = operation and operation.type or nil,
        reason = controller and (controller.reason or operation and operation.reason) or nil
    }
end
