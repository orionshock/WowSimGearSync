local _, WSGS = ...
local Doll = { events = { "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" } }
WSGS.PaperDoll = Doll
local fields = WSGS.SlotPresentation.fields
local appearance = {
    MATCH = { "=", 0.3, 1, 0.4 }, CONFIGURATION = { "~", 1, 0.7, 0.15 },
    MISMATCH = { "!", 1, 0.25, 0.25 }, UNKNOWN = { "?", 0.55, 0.7, 1 }, EMPTY = { "-", 0.6, 0.6, 0.6 },
}

-- Translate comparator states into presentation only; no item/modification
-- comparison or interchangeable-slot assignment is performed here.
local function visualState(target, difference)
    if not target or target.empty or not target.id or target.id == 0 then return "EMPTY" end
    if not difference or difference.fields.item.state == "UNKNOWN" then return "UNKNOWN" end
    if difference.fields.item.state == "MISMATCH" then return "MISMATCH" end
    local mismatch, unknown
    for _, field in ipairs(fields) do
        local state = difference.fields[field].state
        mismatch = mismatch or state == "MISMATCH"
        unknown = unknown or state == "UNKNOWN"
    end
    return mismatch and "CONFIGURATION" or unknown and "UNKNOWN" or "MATCH", unknown
end

function Doll:ShowSlotTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    for _, line in ipairs(WSGS.SlotPresentation:TooltipLines(button, WSGS.db.profile.debug)) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function Doll:Render(profile, snapshot, comparison, reason)
    local frame = self:Create()
    self.profile, self.snapshot, self.comparison, self.error = profile, snapshot, comparison, reason
    frame.buildName:SetText(profile and profile.name or "No active build")
    if not profile then frame.summary:SetText("Import a WoW Sims build to display target equipment.")
    elseif comparison then
        local s = comparison.summary
        frame.summary:SetText(string.format("Items matched: %d/16  |  Wrong items: %d\nConfiguration differences: %d  |  Unknown observations: %d",
            s.matched, s.itemMismatches, s.configurationMismatches, s.unknown))
    else frame.summary:SetText(reason or "Comparison unavailable") end
    self.relevantItems = {}
    for position, button in ipairs(frame.slots) do
        local target = profile and profile.equipment[position]
        local difference = comparison and comparison.slots[position]
        local current = snapshot and snapshot.slots[difference and difference.currentPosition or position]
        button.target, button.current, button.difference = target, current, difference
        for _, item in ipairs({ target or {}, current or {} }) do
            if item.id and item.id > 0 then self.relevantItems[item.id] = true end
        end
    end
    for _, button in ipairs(frame.slots) do
        local target = button.target
        local texture = select(2, GetInventorySlotInfo(WSGS.equipmentSlots[button.position].token))
        local quality
        if target and target.id and target.id > 0 then
            local name, _, rarity, _, _, _, _, _, _, cachedIcon = C_Item.GetItemInfo(target.id)
            quality = rarity
            texture = cachedIcon or select(5, C_Item.GetItemInfoInstant(target.id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
            if not name and frame:IsShown() and not self.requestedItems[target.id] then
                self.requestedItems[target.id] = true
                C_Item.RequestLoadItemDataByID(target.id)
            end
        end
        button.icon:SetTexture(texture)
        local color = quality and ITEM_QUALITY_COLORS[quality]
        button.quality:SetVertexColor(color and color.r or 0.5, color and color.g or 0.5, color and color.b or 0.5)
        local state, unknown = visualState(target, button.difference)
        button.visualState = state
        local style = appearance[state]
        button.indicator:SetText(style[1] .. (unknown and state == "CONFIGURATION" and "?" or ""))
        button.indicator:SetTextColor(style[2], style[3], style[4])
        button.miniState:SetText(WSGS.SlotPresentation:MiniStates(button.difference))
    end
    if self.hovered and frame:IsShown() then self:ShowSlotTooltip(self.hovered) end
end

function Doll:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local profile = WSGS:GetActiveSimulationProfile()
    if not profile then self:Render(nil); return end
    local snapshot = WSGS.EquipmentScanner:Scan()
    local comparison, reason = WSGS.EquipmentComparator:Compare(profile, snapshot)
    self:Render(profile, snapshot, comparison, reason)
end

function Doll:QueueRefresh(event, itemId, success)
    if not self.frame:IsShown() then return end
    if event ~= "PLAYER_EQUIPMENT_CHANGED" and (not success or not self.relevantItems[itemId]) then return end
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        self:Refresh()
    end)
end

function Doll:Toggle()
    local frame = self:Create()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function Doll:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "WSGSPaperDoll", UIParent, "PortraitFrameTemplate")
    self.frame, self.requestedItems, self.relevantItems = frame, {}, {}
    frame:Hide()
    frame:SetSize(650, 690)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
    frame.TitleContainer.TitleText:SetText("WowSimGearSync")
    frame.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Chest_Plate04")
    frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    table.insert(UISpecialFrames, "WSGSPaperDoll")
    frame.buildName = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.buildName:SetPoint("TOP", 0, -35)
    frame.buildName:SetWidth(510)
    local import = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    import:SetSize(100, 24)
    import:SetPoint("TOPLEFT", 70, -62)
    import:SetText("Import")
    import:SetScript("OnClick", function()
        if not WSGS.window then WSGS:CreateWindow() end
        WSGS.window:Show()
        WSGS.window:Raise()
    end)
    frame.importButton = import
    local equip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    equip:SetSize(100, 24)
    equip:SetPoint("TOPRIGHT", -40, -62)
    equip:SetText("Equip")
    equip:Disable()
    frame.equipButton = equip
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPRIGHT", -20, -90)
    note:SetText("Equip automation is not implemented.")
    frame.slots = {}
    for position, slot in ipairs(WSGS.equipmentSlots) do
        local button = CreateFrame("Button", nil, frame)
        frame.slots[position] = button
        button.position = position
        button:SetSize(44, 44)
        if position <= 6 then button:SetPoint("TOPLEFT", 18, -112 - (position - 1) * 54)
        elseif position <= 14 then button:SetPoint("TOPRIGHT", -18, -112 - (position - 7) * 54)
        else button:SetPoint("TOP", (position == 15 and -100 or 100), -548) end
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.quality = button:CreateTexture(nil, "OVERLAY")
        button.quality:SetTexture("Interface\\Common\\WhiteIconFrame")
        button.quality:SetAllPoints()
        local backdrop = button:CreateTexture(nil, "OVERLAY", nil, 1)
        backdrop:SetColorTexture(0, 0, 0, 0.85)
        backdrop:SetSize(21, 17)
        backdrop:SetPoint("BOTTOMRIGHT")
        button.indicator = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        button.indicator:SetPoint("BOTTOMRIGHT", -1, 1)
        button.miniState = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.miniState:SetWidth(position <= 14 and 240 or 180)
        if position <= 6 then
            button.miniState:SetPoint("LEFT", button, "RIGHT", 8, 0)
            button.miniState:SetJustifyH("LEFT")
        elseif position <= 14 then
            button.miniState:SetPoint("RIGHT", button, "LEFT", -8, 0)
            button.miniState:SetJustifyH("RIGHT")
        else
            button.miniState:SetPoint("TOP", button, "BOTTOM", 0, -4)
            button.miniState:SetJustifyH("CENTER")
        end
        button:SetScript("OnEnter", function(b) self.hovered = b; self:ShowSlotTooltip(b) end)
        button:SetScript("OnLeave", function() self.hovered = nil; GameTooltip:Hide() end)
        -- Deliberately no OnClick/drag/item-use handlers or secure equipment template.
    end
    local legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("CENTER", 0, 20)
    legend:SetWidth(150)
    legend:SetText("Hover a slot for details.")
    frame.helpHint = legend
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.summary:SetPoint("BOTTOM", 0, 30)
    frame.summary:SetWidth(610)
    frame:SetScript("OnEvent", function(_, ...) self:QueueRefresh(...) end)
    frame:SetScript("OnShow", function()
        self.requestedItems = {}
        for _, event in ipairs(self.events) do frame:RegisterEvent(event) end
        self:Refresh()
    end)
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        frame:UnregisterAllEvents()
        if self.hovered then GameTooltip:Hide(); self.hovered = nil end
    end)
    return frame
end
