local _, WSGS = ...
local Internal = WSGS.ActionsInternal or {}
WSGS.ActionsInternal = Internal

local Presentation = {}
Internal.Presentation = Presentation

local colors = {
    WAITING_FOR_ITEM = "8cb3ff",
    READY = "4dff66",
    PENDING = "999999",
    UNKNOWN = "8cb3ff",
    BLOCKED = "ffb326",
    COMPLETE = "4dff66"
}

local labels = {
    BUCKLE = "belt buckle",
    GEM = "gem",
    ENCHANT = "enchant",
    PROFESSION_ENCHANT = "profession enhancement",
    PROFESSION_SOCKET = "Blacksmithing socket",
    TINKER = "Engineering tinker"
}

local function actionText(controller, operation)
    if not controller or controller.state == "WAITING_FOR_ITEM" then
        return nil
    end
    local action = operation and labels[operation.type]
    if controller.state == "READY" and action then
        return "Click to apply " .. action
    end
    if controller.state == "PENDING" and action then
        return "Applying " .. action .. "..."
    end
    if controller.state == "UNKNOWN" then
        return "Click to recheck"
    end
    if controller.state == "BLOCKED" and controller.lastFailed and action then
        return "Click to retry " .. action
    end
    if controller.state == "BLOCKED" and action then
        return "Cannot apply " .. action
    end
    return "No action needed"
end

local function tooltipLines(controller, operation)
    if not controller then
        return {}
    end
    local color = colors[controller.state] or "ffffff"
    local lines = {" ", "|cff" .. color .. "Action: " .. controller.state:gsub("_", " ") .. "|r"}
    if operation then
        local text = "Next: " .. labels[operation.type]
        if operation.type == "GEM" and operation.expected and operation.socket then
            text = text .. string.format(" %d in socket %d", operation.expected, operation.socket)
        elseif operation.expected then
            text = text .. " " .. tostring(operation.expected)
        end
        if operation.targetSource == "RECOMMENDED" then
            text = text .. " (recommended)"
        elseif operation.targetSource == "SIMULATION" then
            text = text .. " (simulation target)"
        end
        lines[#lines + 1] = text
        if operation.material then
            lines[#lines + 1] = string.format("Material: item %d at bag %d, slot %d", operation.material.itemID,
                operation.material.bag, operation.material.slot)
        elseif operation.spellID then
            lines[#lines + 1] = string.format("Recipe: %s (%d)", operation.spellName or "unavailable",
                operation.spellID)
        end
    end
    if controller.reason then
        lines[#lines + 1] = controller.reason
    end
    return lines
end

function Presentation:Build(controller, operation)
    return {
        state = controller and controller.state or "COMPLETE",
        pending = controller and controller.state == "PENDING" or false,
        clickText = actionText(controller, operation),
        tooltipLines = tooltipLines(controller, operation)
    }
end
