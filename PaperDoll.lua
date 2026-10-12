local _, WSGS = ...
local Doll = WSGS:NewModule("UI", "AceEvent-3.0")
Doll.events = { "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "SKILL_LINES_CHANGED" }
WSGS.PaperDoll = Doll
local fields = WSGS.SlotPresentation.fields
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
    for _, line in ipairs(WSGS.SlotActions:TooltipLines(button.position)) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function Doll:Render(profile, snapshot, comparison, reason)
    local frame = self:Create()
    self.profile, self.snapshot, self.comparison, self.error = profile, snapshot, comparison, reason
    WSGS.SlotActions:Refresh(profile, snapshot, comparison)
    if not frame.buildName:HasFocus() or frame.buildName.buildId ~= (profile and profile.id) then
        frame.buildName:SetText(profile and profile.name or "No active build")
    end
    frame.buildName.buildId = profile and profile.id
    if profile then frame.buildName:Enable() else frame.buildName:Disable() end
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
        local state = visualState(target, button.difference)
        button.visualState = state
        button.miniState:SetText(WSGS.SlotPresentation:MiniStates(button.difference,
            WSGS.SlotActions:ClickText(button.position)))
        local action = WSGS.SlotActions.controllers[position]
        local pending = action and action.state == "PENDING"
        button.icon:SetDesaturated(pending == true)
        if not InCombatLockdown() then button:Enable() end
    end
    if self.hovered and frame:IsShown() then self:ShowSlotTooltip(self.hovered) end
end

function Doll:UpdateEquipButton()
    if not self.frame then return end
    local actions = WSGS.EquipmentActions
    local labels = { READY="Equip", PENDING="Equipping",
        CURSOR="Blocked", COMBAT="Blocked", FAULT="Blocked", BLOCKED="Blocked", COMPLETE="Sync Set" }
    self.frame.equipButton:SetText(labels[actions.state] or "Blocked")
    self.frame.equipButton:SetEnabled(actions.state == "READY" or actions.state == "FAULT" or actions.state == "COMPLETE")
    local plan = actions.plan
    local counts = actions.batch and actions:OutcomeCounts()
    local note = actions.state == "CURSOR" and "Place the held cursor item first." or actions.state == "COMBAT" and "Cannot equip in combat." or actions.fault
        or counts and counts.STILL_PENDING > 0 and string.format("Equipping: %d/%d verified; %d target slot(s) unresolved.",
            counts.VERIFIED, actions.batch.total, plan and plan.unresolvedCount or counts.STILL_PENDING)
        or plan and (#plan.missing > 0 and ("Missing target items: " .. #plan.missing)
            or plan.blocked[1] or plan.unresolvedCount > 0 and (plan.unresolvedCount .. " target slot(s) unresolved.")) or ""
    self.frame.equipNote:SetText(note)
end

function Doll:CommitBuildName(character)
    local input = self.frame.buildName
    local build, reason = WSGS.ManagedBuilds:Rename(character, input.buildId, input:GetText())
    if build then
        self.profile = build
        input:SetText(build.name)
    else
        input:SetText(self.profile and self.profile.name or "No active build")
    end
    input:ClearFocus()
    return build, reason
end

function Doll:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local profile = WSGS:GetActiveSimulationProfile()
    if not profile then
        WSGS.EquipmentActions:Refresh(nil)
        self:Render(nil)
        return
    end
    local snapshot = WSGS.EquipmentScanner:Scan()
    local comparison, reason = WSGS.EquipmentComparator:Compare(profile, snapshot)
    WSGS.EquipmentActions:Refresh(profile, snapshot)
    self:Render(profile, snapshot, comparison, reason)
end

function Doll:QueueRefresh(event, itemId, success)
    if not self.frame or not self.frame:IsShown() then return end
    if event ~= "PLAYER_EQUIPMENT_CHANGED" and event ~= "SKILL_LINES_CHANGED" and (not success or not self.relevantItems[itemId]) then return end
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        self:Refresh()
    end)
end

function Doll:OnUIEvent(event, ...)
    self:QueueRefresh(event, ...)
end

function Doll:OnBuildImported()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function Doll:OnActionsChanged()
    self:QueueRefresh("PLAYER_EQUIPMENT_CHANGED")
end

function Doll:OnEquipmentStateChanged()
    self:UpdateEquipButton()
end

function Doll:OnEquipmentRefreshRequested()
    self:QueueRefresh("PLAYER_EQUIPMENT_CHANGED")
end

function Doll:OnEnable()
    for _, event in ipairs(self.events) do self:RegisterEvent(event, "OnUIEvent") end
    self:RegisterMessage("WSGS_BUILD_IMPORTED", "OnBuildImported")
    self:RegisterMessage("WSGS_ACTIONS_CHANGED", "OnActionsChanged")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_CHANGED", "OnEquipmentStateChanged")
    self:RegisterMessage("WSGS_EQUIPMENT_REFRESH_REQUESTED", "OnEquipmentRefreshRequested")
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
    frame.buildName = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.buildName:SetPoint("TOP", 0, -35)
    frame.buildName:SetSize(300, 24)
    frame.buildName:SetAutoFocus(false)
    frame.buildName:SetMaxBytes(80)
    frame.buildName:SetScript("OnEnter", function(input)
        GameTooltip:SetOwner(input, "ANCHOR_TOP")
        GameTooltip:AddLine("Build name")
        GameTooltip:AddLine("Enter saves; Escape or leaving the field cancels.", 1, 1, 1)
        GameTooltip:Show()
    end)
    frame.buildName:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.buildName:SetScript("OnEnterPressed", function()
        local build, reason = self:CommitBuildName(WSGS.db.char)
        if not build then WSGS:Print(reason) end
    end)
    frame.buildName:SetScript("OnEscapePressed", function(input)
        input:SetText(self.profile and self.profile.name or "No active build")
        input:ClearFocus()
    end)
    frame.buildName:SetScript("OnEditFocusLost", function(input)
        input:SetText(self.profile and self.profile.name or "No active build")
    end)
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
    equip:SetScript("OnClick", function() WSGS.EquipmentActions:Click() end)
    frame.equipButton = equip
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPRIGHT", -20, -90)
    note:SetWidth(440)
    note:SetJustifyH("RIGHT")
    frame.equipNote = note
    frame.slots = {}
    for position, slot in ipairs(WSGS.equipmentSlots) do
        local button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
        frame.slots[position] = button
        button.position = position
        button:SetSize(44, 44)
        local leftColumn = position <= 6 or position >= 15
        if leftColumn then
            local row = position <= 6 and position or position - 8
            button:SetPoint("TOPLEFT", 18, -112 - (row - 1) * 54)
        else
            button:SetPoint("TOPRIGHT", -18, -112 - (position - 7) * 54)
        end
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.quality = button:CreateTexture(nil, "OVERLAY")
        button.quality:SetTexture("Interface\\Common\\WhiteIconFrame")
        button.quality:SetAllPoints()
        button.miniState = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.miniState:SetWidth(240)
        if leftColumn then
            button.miniState:SetPoint("LEFT", button, "RIGHT", 8, 0)
            button.miniState:SetJustifyH("LEFT")
        else
            button.miniState:SetPoint("RIGHT", button, "LEFT", -8, 0)
            button.miniState:SetJustifyH("RIGHT")
        end
        button:SetScript("OnEnter", function(b) self.hovered = b; self:ShowSlotTooltip(b) end)
        button:SetScript("OnLeave", function() self.hovered = nil; GameTooltip:Hide() end)
        button:RegisterForClicks("LeftButtonUp")
        button:SetAttribute("useOnKeyDown", false)
        button:SetAttribute("_onstate-combat", [[
            if newstate == "combat" then
                self:SetAttribute("type1", nil)
            else
                self:SetAttribute("type1", self:GetAttribute("wsgs-type1"))
            end
        ]])
        RegisterStateDriver(button, "combat", "[combat] combat; nocombat")
        button:SetScript("PreClick", function(b) WSGS.SlotActions:PreClick(b.position, b) end)
        button:SetScript("PostClick", function(b) WSGS.SlotActions:PostClick(b.position, b) end)
        WSGS.SlotActions:RegisterButton(position, button)
    end
    local legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("CENTER", 0, 20)
    legend:SetWidth(150)
    legend:SetText("Hover a slot for details.")
    frame.helpHint = legend
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.summary:SetPoint("BOTTOM", 0, 30)
    frame.summary:SetWidth(610)
    frame:SetScript("OnShow", function()
        WSGS:RefreshEscapeWindow()
        self.requestedItems = {}
        self:Refresh()
    end)
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        frame.buildName:ClearFocus()
        WSGS:RefreshEscapeWindow()
        if self.hovered then GameTooltip:Hide(); self.hovered = nil end
    end)
    return frame
end
