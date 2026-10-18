local _, WSGS = ...

local Panel = {}
WSGS.NPCPanel = Panel

local WIDTH, ITEM_ROW_HEIGHT = 286, 52
Panel.TRANSITION_ICON = "|TInterface\\Buttons\\UI-SpellbookIcon-NextPage-Up:16:16:0:0|t"

function Panel:Create(name, title, onDismiss)
    local frame = CreateFrame("Frame", name, UIParent, "TooltipBackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", 12, -12)
    frame.title:SetText(title)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -28, 0)
    frame.title:SetJustifyH("LEFT")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetSize(24, 24)
    frame.close:SetPoint("TOPRIGHT", 2, 2)
    frame.close:SetScript("OnClick", function()
        onDismiss()
        frame:Hide()
    end)

    frame.mode = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.mode:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.mode:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    frame.mode:SetJustifyH("LEFT")

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(true)

    frame.action = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.action:SetSize(150, 22)
    frame.action:SetPoint("BOTTOM", 0, 10)

    return frame
end
function Panel:Anchor(frame, owner, matchHeight)
    if not owner then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, matchHeight and -4 or 0)
    if matchHeight then
        frame:SetPoint("BOTTOMLEFT", owner, "BOTTOMRIGHT", 6, 4)
    end
    return true
end

local function createItemRow(frame, index)
    local row = CreateFrame("Button", nil, frame.itemContent)
    row:SetHeight(ITEM_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ITEM_ROW_HEIGHT))
    row:SetPoint("RIGHT", frame.itemContent, "RIGHT", 0, 0)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(38, 38)
    row.icon:SetPoint("TOPLEFT", 2, -7)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(true)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.detail:SetJustifyH("LEFT")
    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cost:SetPoint("TOPLEFT", row.detail, "BOTTOMLEFT", 0, -1)
    row.cost:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.cost:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(clicked)
        if frame.itemRowClick then
            frame.itemRowClick(clicked.entry)
        end
    end)
    frame.itemRows[index] = row
    return row
end

local function updateItemScroll(scroll)
    local content = scroll:GetScrollChild()
    content:SetWidth(scroll:GetWidth())
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
    ScrollFrame_OnScrollRangeChanged(scroll)
end

function Panel:RenderItemList(frame, mode, entries, status, onClick, buttonText, enabled, footer)
    frame.mode:ClearAllPoints()
    frame.mode:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.mode:SetPoint("TOPRIGHT", frame.title, "BOTTOMRIGHT", 16, -6)
    frame.mode:SetText(mode or "")
    frame.itemRows = frame.itemRows or {}
    frame.itemRowClick = onClick
    frame.status:ClearAllPoints()
    local statusInset = footer and 0 or 12
    local statusOffset = footer and 8 or buttonText and 40 or 12
    frame.status:SetPoint("BOTTOMLEFT", footer or frame, footer and "TOPLEFT" or "BOTTOMLEFT",
        statusInset, statusOffset)
    frame.status:SetPoint("BOTTOMRIGHT", footer or frame, footer and "TOPRIGHT" or "BOTTOMRIGHT",
        -statusInset, statusOffset)
    frame.status:SetText(WSGS:FormatPlayerReason(status) or "")
    if not frame.itemScroll then
        frame.itemScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.itemScroll:SetPoint("TOPLEFT", frame.mode, "BOTTOMLEFT", -2, -8)
        frame.itemScroll:SetPoint("BOTTOMRIGHT", frame.status, "TOPRIGHT", -16, 8)
        frame.itemScroll.scrollBarHideable = true
        frame.itemScroll.ScrollBar.scrollStep = ITEM_ROW_HEIGHT
        frame.itemScroll:EnableMouseWheel(true)
        frame.itemScroll:SetScript("OnMouseWheel", ScrollFrameTemplate_OnMouseWheel)
        frame.itemContent = CreateFrame("Frame", nil, frame.itemScroll)
        frame.itemContent:SetSize(WIDTH - 48, 1)
        frame.itemScroll:SetScrollChild(frame.itemContent)
        frame.itemScroll:SetScript("OnSizeChanged", updateItemScroll)
    end
    frame.action:SetShown(buttonText ~= nil)
    if buttonText then
        frame.action:SetText(buttonText)
        frame.action:SetEnabled(enabled == true)
    end
    frame.itemContent:SetWidth(frame.itemScroll:GetWidth())
    local contentHeight = 0
    for index, entry in ipairs(entries or {}) do
        local row = frame.itemRows[index] or createItemRow(frame, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -contentHeight)
        row:SetPoint("RIGHT", frame.itemContent, "RIGHT", 0, 0)
        row.entry = entry.entry
        row.icon:SetTexture(entry.icon)
        row.name:SetText(entry.displayName)
        row.name:SetTextColor(entry.r or 1, entry.g or 1, entry.b or 1)
        row.detail:SetText(entry.detail)
        row.cost:SetText(entry.cost or "")
        row:SetHeight(math.max(ITEM_ROW_HEIGHT, math.ceil(row.name:GetStringHeight() +
            row.detail:GetStringHeight() + row.cost:GetStringHeight() + 17)))
        contentHeight = contentHeight + row:GetHeight()
        if entry.affordable == false then
            row.cost:SetTextColor(1, 0.25, 0.25)
        else
            row.cost:SetTextColor(0.8, 0.8, 0.8)
        end
        row:SetEnabled(entry.enabled ~= false)
        row:Show()
    end
    for index = #(entries or {}) + 1, #frame.itemRows do
        frame.itemRows[index]:Hide()
    end
    frame.itemContent:SetHeight(math.max(1, contentHeight))
    frame.itemScroll:SetShown(#(entries or {}) > 0)
    updateItemScroll(frame.itemScroll)
end
