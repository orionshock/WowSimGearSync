local _, WSGS = ...
local Inspector = {}
WSGS.EquipmentInspector = Inspector
local upgradeFields = { "upgradeEligibility", "upgradeStep", "upgradeMaximum", "upgradeRemaining", "upgradeState" }
local function unknown(reason)
    return { status = "UNKNOWN", reason = reason }
end
local function known(value, source)
    return { status = "KNOWN", value = value, source = source }
end
local function clean(text)
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- Compile the authoritative localized format literally; no English or numeric
-- fallback. Positional %1$d/%2$d placeholders may reorder current/maximum.
local function upgradePattern(format)
    if type(format) ~= "string" then return nil end
    local pattern, order, position, valid = {}, {}, 1, true
    format = clean(format)
    local function literal(text)
        if text:find("%", 1, true) then valid = false end
        return (text:gsub("(%W)", function(character) return "%" .. character end))
    end
    -- Function replacements return captures literally, without gsub interpreting
    -- the percent sign in (%d+) as a replacement escape.
    format:gsub("()%%([12]?)(%$?)([%%d])()", function(first, ordinal, dollar, kind, after)
        pattern[#pattern + 1] = literal(format:sub(position, first - 1))
        if kind == "%" and ordinal == "" and dollar == "" then
            pattern[#pattern + 1] = "%%"
        elseif kind == "d" and ((ordinal == "" and dollar == "")
            or (ordinal ~= "" and dollar == "$")) then
            order[#order + 1] = tonumber(ordinal) or (#order + 1)
            pattern[#pattern + 1] = "(%d+)"
        else
            valid = false
        end
        position = after
        return ""
    end)
    pattern[#pattern + 1] = literal(format:sub(position))
    if not valid then return nil end
    if #order ~= 2 or order[1] == order[2] then return nil end
    return "^" .. table.concat(pattern) .. "$", order
end

function Inspector:Inspect(slotId, link)
    local result = {}
    for _, field in ipairs(upgradeFields) do result[field] = unknown("Upgrade tooltip unavailable, unreadable, or inconsistent") end
    result.tinker = unknown("Engineering effect not established")
    local populatedTooltip = false
    local pattern, order = upgradePattern(ITEM_UPGRADE_TOOLTIP_FORMAT)
    if pattern then
        local ok, lines = pcall(function()
            if not self.tooltip then
                local tooltip = CreateFrame("GameTooltip", "WSGSEquipmentInspectionTooltip", nil, "GameTooltipTemplate")
                self.tooltip = tooltip
            end
            local tooltip = self.tooltip
            -- Hide ends the previous inspection; establish ownership for every
            -- item, including subsequent slots in a complete equipment scan.
            tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
            tooltip:ClearLines()
            local hasItem = tooltip:SetInventoryItem("player", slotId)
            if not hasItem then tooltip:Hide(); return nil end
            local _, tooltipLink = tooltip:GetItem()
            local expected = WSGS.ItemLinkDecoder:Decode(link)
            local actual = WSGS.ItemLinkDecoder:Decode(tooltipLink)
            if not expected or not actual or expected.payload ~= actual.payload then
                tooltip:Hide()
                return nil
            end
            local text = {}
            for _, region in ipairs({ tooltip:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    local value = region:GetText()
                    if type(value) == "string" and value:find("%S") then text[#text + 1] = clean(value) end
                end
            end
            tooltip:Hide()
            return text
        end)
        if ok and lines and #lines > 0 then
            populatedTooltip = true
            local current, maximum, conflict
            for _, text in ipairs(lines) do
                local a, b = text:match(pattern)
                if a and b then
                    local values = {}
                    values[order[1]], values[order[2]] = tonumber(a), tonumber(b)
                    local now, total = values[1], values[2]
                    if total <= 0 or now > total or (current and (current ~= now or maximum ~= total)) then
                        conflict = true
                    else current, maximum = now, total end
                end
            end
            if current and not conflict then
                local source = "GameTooltip:SetInventoryItem / ITEM_UPGRADE_TOOLTIP_FORMAT"
                result.upgradeEligibility = known(true, source)
                result.upgradeStep = known(current, source)
                result.upgradeMaximum = known(maximum, source)
                result.upgradeRemaining = known(maximum - current, source)
                result.upgradeState = known(current == maximum and "FULLY_UPGRADED"
                    or current == 0 and "UNUPGRADED" or "PARTIALLY_UPGRADED", source)
            elseif not current and not conflict then
                -- Confirmed MoP behavior: populated tooltips always show an
                -- upgrade line for eligible items, including 0/max and max/max.
                local source = "GameTooltip:SetInventoryItem / no upgrade line"
                result.upgradeEligibility = known(false, source)
                result.upgradeState = known("NOT_UPGRADEABLE", source)
                for _, field in ipairs({ "upgradeStep", "upgradeMaximum", "upgradeRemaining" }) do
                    result[field] = { status = "NOT_APPLICABLE", reason = "Item does not support upgrades", source = source }
                end
            end
        end
    end
    local effects = WSGS.Engineering.effects[slotId]
    if effects then
        local ok, name, spellId = pcall(C_Item.GetItemSpell, link)
        if ok and effects[spellId] then
            result.tinker = known(effects[spellId], "C_Item.GetItemSpell / MoP SpellItemEnchantment mapping")
        elseif ok and not spellId and not name and populatedTooltip and C_Item.GetItemInfo(link) then
            result.tinker = known(0, "Cached item and populated inventory tooltip / no item use spell")
        else
            result.tinker = unknown("Use spell unmapped or item information unavailable")
        end
        if ok then result.tinker.spellId, result.tinker.spellName = spellId, name end
    else
        result.tinker = { status = "NOT_APPLICABLE", reason = "Not a supported engineering slot" }
    end
    return result
end
