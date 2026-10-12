local _, WSGS = ...
-- Owns player-facing translation only. Scanner/comparator remain authoritative.
local Presentation = {}
WSGS.SlotPresentation = Presentation
Presentation.fields = { "item", "upgradeStep", "gems", "enchant", "buckle", "tinker", "reforging" }
local labels = { item = "Item", gems = "Gems", enchant = "Enchant", reforging = "Reforge",
    upgradeStep = "Upgrade", tinker = "Tinker", buckle = "Buckle" }
local statusLabels = { item = "Equipped", upgradeStep = "Upgraded", gems = "Gemmed",
    enchant = "Enchant", buckle = "Buckle", tinker = "Tinker", reforging = "Reforged" }
local styles = {
    MATCH = { "4dff66", "" }, MISMATCH = { "ffb326", "!" },
    UNKNOWN = { "8cb3ff", "" }, NOT_APPLICABLE = { "999999", "" },
}

function Presentation:MiniStates(difference)
    if not difference then return "" end
    local badges = {}
    for _, field in ipairs(self.fields) do
        local value = difference.fields[field]
        if value and (field == "item" or value.state ~= "NOT_APPLICABLE") then
            local style = styles[value.state]
            local color = field == "item" and value.state == "MISMATCH" and "ff4040" or style[1]
            badges[#badges + 1] = "|cff" .. color .. style[2] .. statusLabels[field] .. "|r"
        end
    end
    return table.concat(badges, ", ")
end

local function itemText(item)
    if not item then return "Unavailable" end
    if item.empty or item.id == 0 or item.observations and item.observations.item.present == false then return "Empty" end
    if not item.id then return "Unknown" end
    local name = C_Item.GetItemInfo(item.link or item.id)
    return name or ("Item " .. item.id .. " (loading)")
end

function Presentation:TooltipLines(button, debug)
    local lines = { WSGS.equipmentSlots[button.position].name }
    if not button.target then
        lines[#lines + 1] = "Import a WoW Sims build to choose target equipment."
        return lines
    end
    lines[#lines + 1] = "Target: " .. itemText(button.target)
    lines[#lines + 1] = "Equipped: " .. itemText(button.current)
    local difference = button.difference
    if not difference then lines[#lines + 1] = "Comparison unavailable"; return lines end
    for _, field in ipairs(self.fields) do
        local value = difference.fields[field]
        if value and value.state ~= "NOT_APPLICABLE" then
            local text = value.state == "MATCH" and "Matched"
                or value.state == "MISMATCH" and (field == "item" and "Wrong or missing item" or "Pending")
                or "Unknown"
            if field == "buckle" and value.state == "MISMATCH" then text = "Missing" end
            if field == "upgradeStep" and type(value.actual) == "number" and type(value.expected) == "number" then
                text = string.format("%d/%d (%d remaining)", value.actual, value.expected,
                    math.max(0, value.expected - value.actual))
            end
            lines[#lines + 1] = labels[field] .. ": " .. text
                .. (value.targetSource == "RECOMMENDED" and " (recommended)" or "")
        end
    end
    if debug then
        lines[#lines + 1] = "Diagnostics: inventory slot " .. difference.currentSlotId
            .. (difference.currentPosition ~= button.position and " (resolved pair)" or "")
        for _, field in ipairs(self.fields) do
            local value = difference.fields[field]
            if value then
                lines[#lines + 1] = labels[field] .. ": " .. value.state
                    .. (value.source and " via " .. value.source or "")
                    .. (value.reason and " - " .. value.reason or "")
            end
        end
    end
    return lines
end
