local _, WSGS = ...
local Inspector = {}
WSGS.EquipmentInspector = Inspector
local upgradeFields = { "upgradeEligibility", "upgradeStep", "upgradeMaximum", "upgradeRemaining", "upgradeState" }
-- Local MoP SpellItemEnchantment data corroborates the effects recognized by
-- CharacterStatsPaneImproved/newstats.lua; see docs/equipment-observations.txt.
local gloveTinkers = { [126734] = 4898, [108788] = 4697, [109076] = 4698 }

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
    local pattern, order, position = {}, {}, 1
    format = clean(format)
    while position <= #format do
        local tail = format:sub(position)
        local ordinal = tail:match("^%%([12])%$d")
        if ordinal then
            order[#order + 1] = tonumber(ordinal)
            pattern[#pattern + 1] = "(%d+)"
            position = position + 4
        elseif tail:sub(1, 2) == "%d" then
            order[#order + 1] = #order + 1
            pattern[#pattern + 1] = "(%d+)"
            position = position + 2
        elseif tail:sub(1, 2) == "%%" then
            pattern[#pattern + 1] = "%%"
            position = position + 2
        else
            if tail:sub(1, 1) == "%" then return nil end
            pattern[#pattern + 1] = tail:sub(1, 1):gsub("(%W)", "%%%1")
            position = position + 1
        end
    end
    if #order ~= 2 or order[1] == order[2] then return nil end
    return "^" .. table.concat(pattern) .. "$", order
end

function Inspector:Inspect(slotId, link)
    local result = {}
    for _, field in ipairs(upgradeFields) do result[field] = unknown("Upgrade tooltip unavailable or no authoritative upgrade line") end
    result.tinker = unknown("Engineering effect not established")
    local pattern, order = upgradePattern(ITEM_UPGRADE_TOOLTIP_FORMAT)
    if pattern then
        local ok, lines = pcall(function()
            if not self.tooltip then
                local tooltip = CreateFrame("GameTooltip", "WSGSEquipmentInspectionTooltip", nil, "GameTooltipTemplate")
                tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
                self.tooltip = tooltip
            end
            local tooltip = self.tooltip
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
                    if type(value) == "string" then text[#text + 1] = clean(value) end
                end
            end
            tooltip:Hide()
            return text
        end)
        if ok and lines then
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
            end
        end
    end
    if slotId == 10 then
        local ok, name, spellId = pcall(C_Item.GetItemSpell, link)
        if ok and gloveTinkers[spellId] then
            result.tinker = known(gloveTinkers[spellId], "C_Item.GetItemSpell / MoP SpellItemEnchantment mapping")
            result.tinker.spellId, result.tinker.spellName = spellId, name
        else
            result.tinker = unknown("No mapped engineering use spell; missing and uncached data are not distinguished")
            if ok then result.tinker.spellId, result.tinker.spellName = spellId, name end
        end
    end
    return result
end
