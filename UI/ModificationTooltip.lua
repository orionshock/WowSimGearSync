local _, WSGS = ...
local UI = WSGS.UI

local Tooltip = {}
UI.ModificationTooltip = Tooltip

local ICON_SIZE = 46
local ARROW_WIDTH, ARROW_HEIGHT = 26, 22
local PADDING = 12
local MAX_WIDTH = 440
local MIN_WIDTH = 180
local ARROW_TEXTURE = "Interface\\TalentFrame\\TalentFrame-Parts"

local function measuredWidth(frame, text)
    frame.measure:SetText(text or "")
    return frame.measure:GetStringWidth()
end

local function acquireText(frame)
    local index = frame.usedTexts + 1
    frame.usedTexts = index
    local text = frame.texts[index]
    if not text then
        text = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        frame.texts[index] = text
    end
    text:Show()
    text:ClearAllPoints()
    text:SetTextColor(1, 1, 1)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    return text
end

local function acquireRow(frame)
    local index = frame.usedRows + 1
    frame.usedRows = index
    local row = frame.rows[index]
    if not row then
        row = CreateFrame("Frame", nil, frame)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        row.text:SetJustifyH("LEFT")
        row.text:SetJustifyV("MIDDLE")
        frame.rows[index] = row
    end
    row:Show()
    row:ClearAllPoints()
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT")
    row.text:ClearAllPoints()
    row.text:SetTextColor(1, 1, 1)
    return row
end

local function acquireArrow(frame)
    local index = frame.usedArrows + 1
    frame.usedArrows = index
    local arrow = frame.arrows[index]
    if not arrow then
        arrow = frame:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(ARROW_TEXTURE)
        arrow:SetTexCoord(0.78515625, 0.99218750, 0.54687500, 0.58789063)
        arrow:SetSize(ARROW_WIDTH, ARROW_HEIGHT)
        frame.arrows[index] = arrow
    end
    arrow:Show()
    arrow:ClearAllPoints()
    return arrow
end

local function reset(frame)
    frame.usedTexts, frame.usedRows, frame.usedArrows = 0, 0, 0
    for _, text in ipairs(frame.texts) do
        text:Hide()
    end
    for _, row in ipairs(frame.rows) do
        row:Hide()
    end
    for _, arrow in ipairs(frame.arrows) do
        arrow:Hide()
    end
end

local function tooltipWidth(frame, status)
    local width = measuredWidth(frame, status.label) + PADDING * 2
    local tooltip = status.tooltip or {}
    for _, section in ipairs(tooltip.sections or {}) do
        width = math.max(width, measuredWidth(frame, section.label) + PADDING * 2)
        for _, value in ipairs({section.current, section.target}) do
            if value then
                local iconWidth = value.texture and ICON_SIZE + 8 or 0
                width = math.max(width, measuredWidth(frame, value.text) + iconWidth + PADDING * 2)
            end
        end
        if section.currentUnknown then
            width = math.max(width, measuredWidth(frame, "Current: Unknown") + PADDING * 2)
        elseif section.apply then
            width = math.max(width, measuredWidth(frame, "Apply") + PADDING * 2)
        end
    end
    if tooltip.note then
        width = math.max(width, measuredWidth(frame, tooltip.note) + PADDING * 2)
    end
    return math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.ceil(width)))
end

local function addText(frame, value, y, width, fontObject, red, green, blue)
    local text = acquireText(frame)
    text:SetFontObject(fontObject or GameTooltipText)
    text:SetText(value)
    text:SetTextColor(red or 1, green or 1, blue or 1)
    text:SetJustifyH("CENTER")
    text:SetWidth(width)
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
    local height = math.ceil(text:GetStringHeight())
    return y - height, text
end

local function addRow(frame, value, y, width)
    local row = acquireRow(frame)
    local availableWidth = width - PADDING * 2
    local iconWidth = value.texture and ICON_SIZE + 8 or 0
    local rowWidth = math.min(availableWidth, math.ceil(measuredWidth(frame, value.text) + iconWidth))
    local textWidth = rowWidth - iconWidth
    if value.texture then
        row.icon:SetTexture(value.texture)
        row.icon:Show()
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    else
        row.icon:Hide()
        row.text:SetPoint("LEFT", row, "LEFT")
    end
    row.text:SetWidth(textWidth)
    row.text:SetText(value.text or "Unknown")
    if value.color then
        row.text:SetTextColor(value.color[1], value.color[2], value.color[3])
    end
    local height = math.max(ICON_SIZE, math.ceil(row.text:GetStringHeight()))
    row:SetSize(rowWidth, height)
    row:SetPoint("TOP", frame, "TOP", 0, y)
    return y - height
end

function Tooltip:Create()
    if self.frame then
        return self.frame
    end
    local frame = CreateFrame("Frame", "WSGSModificationTooltip", UIParent, "TooltipBorderedFrameTemplate")
    self.frame = frame
    frame:Hide()
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame.texts, frame.rows, frame.arrows = {}, {}, {}
    frame.measure = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    frame.measure:Hide()
    return frame
end

function Tooltip:Show(icon, status)
    local frame = self:Create()
    reset(frame)
    local width = tooltipWidth(frame, status)
    local y = -PADDING
    y = addText(frame, status.label, y, width - PADDING * 2, GameTooltipHeaderText, 1, 1, 1) - 10

    local tooltip = status.tooltip or {}
    for sectionIndex, section in ipairs(tooltip.sections or {}) do
        if sectionIndex > 1 then
            y = y - 10
        end
        if section.label then
            y = addText(frame, section.label, y, width - PADDING * 2, GameTooltipTextSmall, 1, 0.82, 0) - 6
        end
        if section.currentUnknown then
            y = addText(frame, "Current: Unknown", y, width - PADDING * 2, GameTooltipText) - 6
        elseif section.apply then
            y = addText(frame, "Apply", y, width - PADDING * 2, GameTooltipText) - 6
        elseif section.current then
            y = addRow(frame, section.current, y, width) - 2
            local arrow = acquireArrow(frame)
            arrow:SetPoint("TOP", frame, "TOP", 0, y)
            y = y - ARROW_HEIGHT - 2
        end
        if section.target then
            y = addRow(frame, section.target, y, width)
        end
    end

    if tooltip.note then
        y = y - 10
        y = addText(frame, tooltip.note, y, width - PADDING * 2, GameTooltipText, 1, 0.35, 0.25)
    end
    frame:SetSize(width, math.max(32, -y + PADDING))
    frame:ClearAllPoints()
    local iconCenter = icon:GetCenter()
    local screenCenter = UIParent:GetWidth() / 2
    if iconCenter and iconCenter > screenCenter then
        frame:SetPoint("TOPRIGHT", icon, "TOPLEFT", -8, 0)
    else
        frame:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    end
    frame:Show()
end

function Tooltip:Hide()
    if self.frame then
        self.frame:Hide()
    end
end
