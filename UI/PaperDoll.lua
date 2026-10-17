local _, WSGS = ...
local UI = WSGS.UI
local Equipment = WSGS:GetModule("Equipment")

local Presentation = UI.SlotPresentation
local FRAME_WIDTH, FRAME_HEIGHT = 350, 550
local SLOT_SIDE_INSET, SLOT_TOP_OFFSET, SLOT_ROW_SPACING = 10, 104, 47
local equipButtonLabels = {
    READY = "Equip",
    PENDING = "Equipping",
    CURSOR = "Blocked",
    COMBAT = "Blocked",
    FAULT = "Blocked",
    BLOCKED = "Blocked",
    COMPLETE = "Sync Set"
}

function UI:ShowSlotTooltip(button)
    UI.ModificationTooltip:Hide()
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if Presentation:IsConfigurationComplete(button.difference) then
        local inventorySlot = button.difference.currentSlotId
        if not GameTooltip:SetInventoryItem("player", inventorySlot) then
            if button.current and button.current.link then
                GameTooltip:SetHyperlink(button.current.link)
            else
                GameTooltip:SetItemByID(button.target.id)
            end
        end
        GameTooltip:Show()
        return
    end
    local actionState = button.actionState or WSGS.Actions:GetSlotState(button.position)
    local item = button.difference and button.difference.fields.item
    if item and item.state ~= "MATCH" then
        local state = Equipment:GetState(WSGS:GetActiveSimulationProfile())
        local _, reason = Equipment:GetSlotEquipPlan(button.position, state)
        actionState = {clickText = reason}
    end
    local title, red, green, blue, action = Presentation:ItemTooltip(button.target, actionState)
    GameTooltip:AddLine(title, red, green, blue)
    if action then
        GameTooltip:AddLine(action, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function UI:ShowModificationTooltip(icon)
    local status = icon.presentation
    if status and icon.owner then
        local refreshed
        for _, current in ipairs(Presentation:ModificationIcons(icon.owner.difference, icon.owner.actionState)) do
            if current.key == status.key then
                refreshed = current
                break
            end
        end
        status, icon.presentation = refreshed, refreshed
    end
    if not status or status.state == "COMPLETE" then
        self.hoveredIcon = nil
        GameTooltip:Hide()
        UI.ModificationTooltip:Hide()
        return
    end
    GameTooltip:Hide()
    UI.ModificationTooltip:Show(icon, status)
end

local function registerTooltipItems(self, frame, status)
    local tooltip = status and status.tooltip
    for _, section in ipairs(tooltip and tooltip.sections or {}) do
        for _, value in ipairs({section.current or {}, section.target or {}}) do
            local itemID = value and value.itemID
            if itemID then
                self.relevantItems[itemID] = true
                if frame:IsShown() and not C_Item.GetItemInfo(itemID) and not self.requestedItems[itemID] then
                    self.requestedItems[itemID] = true
                    Equipment:RequestItemData(itemID, "PaperDoll:modification-tooltip")
                end
            end
        end
    end
end

function UI:RenderPaperDoll(state)
    local frame = self:CreatePaperDoll()
    local profile = state and state.build
    local comparison = state and state.comparison
    local reason = state and state.reason
    self.profile = profile
    if not frame.buildName:HasFocus() or frame.buildName.buildId ~= (profile and profile.id) then
        frame.buildName:SetText(profile and profile.name or "No active build")
    end
    frame.buildName.buildId = profile and profile.id
    if profile then
        frame.buildName:Enable()
    else
        frame.buildName:Disable()
    end
    if not profile then
        frame.summary:SetText("Import a WoW Sims build to display target equipment.")
    elseif comparison then
        local s = comparison.summary
        frame.summary:SetText(string.format(
            "Matched: %d/16  |  UnMatched: %d\nDifference: %d  |  Unknown: %d",
            s.matched, s.itemMismatches, s.configurationMismatches, s.unknown))
    else
        frame.summary:SetText(reason or "Comparison unavailable")
    end
    self.relevantItems = {}
    for position, button in ipairs(frame.slots) do
        local slotState = state and state.slots[position]
        local target = slotState and slotState.target
        local difference = slotState and slotState.comparison
        local current = slotState and slotState.current
        button.target, button.current, button.difference = target, current, difference
        for _, item in ipairs({target or {}, current or {}}) do
            if item.id and item.id > 0 then
                self.relevantItems[item.id] = true
            end
        end
    end
    for _, button in ipairs(frame.slots) do
        local target = button.target
        local texture = select(2, GetInventorySlotInfo(WSGS.equipmentSlots[button.position].token))
        local quality
        if target and target.id and target.id > 0 then
            local name, _, rarity, _, _, _, _, _, _, cachedIcon = C_Item.GetItemInfo(target.id)
            quality = rarity
            texture = cachedIcon or select(5, C_Item.GetItemInfoInstant(target.id)) or
                          "Interface\\Icons\\INV_Misc_QuestionMark"
            if not name and frame:IsShown() and not self.requestedItems[target.id] then
                self.requestedItems[target.id] = true
                Equipment:RequestItemData(target.id, "PaperDoll:target")
            end
        end
        button.icon:SetTexture(texture)
        local color = quality and ITEM_QUALITY_COLORS[quality]
        local item = button.difference and button.difference.fields.item
        if item and item.state == "MISMATCH" then
            button.quality:SetVertexColor(1, 0, 0)
        else
            button.quality:SetVertexColor(color and color.r or 0.5, color and color.g or 0.5, color and color.b or 0.5)
        end
        local actionState = WSGS.Actions:GetSlotState(button.position)
        for _, record in ipairs(Equipment.batch and Equipment.batch.records or {}) do
            if record.operation.targetPosition == button.position and record.status == "STILL_PENDING" then
                actionState.pending = true
                break
            end
        end
        button.actionState = actionState
        local statuses = Presentation:ModificationIcons(button.difference, actionState)
        for index, icon in ipairs(button.statusIcons) do
            local status = statuses[index]
            icon.presentation = status
            if status then
                registerTooltipItems(self, frame, status)
                icon.texture:SetTexture(status.texture)
                icon.texture:SetVertexColor(1, 1, 1)
                icon:Show()
            else
                icon:Hide()
            end
        end
        button.icon:SetDesaturated(actionState.pending)
        if not InCombatLockdown() then
            button:Enable()
        end
    end
    if self.hovered and frame:IsShown() then
        self:ShowSlotTooltip(self.hovered)
    elseif self.hoveredIcon then
        if self.hoveredIcon:IsShown() then
            self:ShowModificationTooltip(self.hoveredIcon)
        else
            self.hoveredIcon = nil
            UI.ModificationTooltip:Hide()
        end
    end
end

function UI:UpdateEquipButton()
    if not self.paperDoll then
        return
    end
    local actions = Equipment
    self.paperDoll.equipButton:SetText(equipButtonLabels[actions.state] or "Blocked")
    self.paperDoll.equipButton:SetEnabled(actions.state == "READY" or actions.state == "FAULT" or actions.state ==
                                              "COMPLETE")
    local plan = actions.plan
    local counts = actions.batch and actions:OutcomeCounts()
    local note = actions.state == "CURSOR" and "Place the held cursor item first." or actions.state == "COMBAT" and
                     "Cannot equip in combat." or actions.fault or counts and counts.STILL_PENDING > 0 and
                     string.format("Equipping: %d/%d verified; %d target slot(s) unresolved.", counts.VERIFIED,
            actions.batch.total, plan and plan.unresolvedCount or counts.STILL_PENDING) or plan and
                     (#plan.missing > 0 and ("Missing target items: " .. #plan.missing) or plan.blocked[1] or
                         plan.unresolvedCount > 0 and (plan.unresolvedCount .. " target slot(s) unresolved.")) or ""
    self.paperDoll.equipNote:SetText(note)
end

function UI:CreatePaperDoll()
    if self.paperDoll then
        return self.paperDoll
    end
    local frame = CreateFrame("Frame", "WSGSPaperDoll", UIParent, "PortraitFrameTemplate")
    self.paperDoll, self.requestedItems, self.relevantItems = frame, {}, {}
    frame:Hide()
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
    end)
    frame.TitleContainer.TitleText:SetText("WowSimGearSync")
    frame.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Chest_Plate04")
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.buildName = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.buildName:SetPoint("TOPRIGHT", -15, -35)
    frame.buildName:SetSize(200, 24)
    frame.buildName:SetAutoFocus(false)
    frame.buildName:SetMaxBytes(80)
    frame.buildName:SetScript("OnEnter", function(input)
        GameTooltip:SetOwner(input, "ANCHOR_TOP")
        GameTooltip:AddLine("Build name")
        GameTooltip:AddLine("Enter saves; Escape or leaving the field cancels.", 1, 1, 1)
        GameTooltip:Show()
    end)
    frame.buildName:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame.buildName:SetScript("OnEnterPressed", function()
        local build, reason = self:CommitBuildName()
        if not build then
            WSGS:Print(reason)
        end
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
    import:SetPoint("TOPLEFT", 44, -62)
    import:SetText("Import")
    import:SetScript("OnClick", function()
        self:ShowImportDialog()
    end)
    frame.importButton = import
    local equip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    equip:SetSize(100, 24)
    equip:SetPoint("TOPRIGHT", -44, -62)
    equip:SetText("Equip")
    equip:Disable()
    equip:SetScript("OnClick", function()
        Equipment:Click()
    end)
    frame.equipButton = equip
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPRIGHT", -18, -88)
    note:SetWidth(320)
    note:SetJustifyH("RIGHT")
    frame.equipNote = note
    frame.slots = {}
    for position in ipairs(WSGS.equipmentSlots) do
        local button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
        frame.slots[position] = button
        button.position = position
        button:SetSize(44, 44)
        local leftColumn = position <= 6 or position >= 15
        if leftColumn then
            local row = position <= 6 and position or position - 8
            button:SetPoint("TOPLEFT", SLOT_SIDE_INSET, -SLOT_TOP_OFFSET - (row - 1) * SLOT_ROW_SPACING)
        else
            button:SetPoint("TOPRIGHT", -SLOT_SIDE_INSET,
                -SLOT_TOP_OFFSET - (position - 7) * SLOT_ROW_SPACING)
        end
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.quality = button:CreateTexture(nil, "OVERLAY")
        button.quality:SetTexture("Interface\\Common\\WhiteIconFrame")
        button.quality:SetAllPoints()
        button.statusIcons = {}
        for index = 1, #Presentation.modifications do
            local statusIcon = CreateFrame("Frame", nil, frame)
            button.statusIcons[index] = statusIcon
            statusIcon.owner = button
            statusIcon:SetSize(18, 18)
            statusIcon:SetFrameLevel(button:GetFrameLevel() + 2)
            if index == 1 then
                if leftColumn then
                    statusIcon:SetPoint("LEFT", button, "RIGHT", 7, 0)
                else
                    statusIcon:SetPoint("RIGHT", button, "LEFT", -7, 0)
                end
            elseif leftColumn then
                statusIcon:SetPoint("LEFT", button.statusIcons[index - 1], "RIGHT", 0, 0)
            else
                statusIcon:SetPoint("RIGHT", button.statusIcons[index - 1], "LEFT", 0, 0)
            end
            statusIcon.texture = statusIcon:CreateTexture(nil, "ARTWORK")
            statusIcon.texture:SetAllPoints()
            statusIcon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            statusIcon:EnableMouse(true)
            statusIcon:SetScript("OnEnter", function(icon)
                self.hoveredIcon = icon
                self:ShowModificationTooltip(icon)
            end)
            statusIcon:SetScript("OnLeave", function()
                self.hoveredIcon = nil
                UI.ModificationTooltip:Hide()
            end)
            statusIcon:SetScript("OnHide", function(icon)
                if self.hoveredIcon == icon then
                    self.hoveredIcon = nil
                    UI.ModificationTooltip:Hide()
                end
            end)
            statusIcon:Hide()
        end
        button:SetScript("OnEnter", function(b)
            self.hovered = b;
            self:ShowSlotTooltip(b)
        end)
        button:SetScript("OnLeave", function()
            self.hovered = nil;
            GameTooltip:Hide()
        end)
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
        WSGS.Actions:RegisterSlotButton(position, button)
    end
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.summary:SetPoint("BOTTOM", 0, 20)
    frame.summary:SetWidth(330)
    frame:SetScript("OnShow", function()
        self:RefreshEscapeWindow()
        self.requestedItems = {}
        self:RefreshPaperDoll()
    end)
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        frame.buildName:ClearFocus()
        self:RefreshEscapeWindow()
        if self.hovered then
            GameTooltip:Hide();
            self.hovered = nil
        end
        UI.ModificationTooltip:Hide()
        if self.hoveredIcon then
            self.hoveredIcon = nil
        end
    end)
    return frame
end
