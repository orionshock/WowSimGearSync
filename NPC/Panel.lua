local _, WSGS = ...

local Panel = {}
WSGS.NPCPanel = Panel

local WIDTH, ROW_HEIGHT = 286, 20
Panel.TRANSITION_ICON = "|TInterface\\Buttons\\UI-SpellbookIcon-NextPage-Up:16:16:0:0|t"

function Panel:Create(name, title)
    local frame = CreateFrame("Frame", name, UIParent, "TooltipBackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 12, -12)
    frame.title:SetText(title)

    frame.mode = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.mode:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.mode:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    frame.mode:SetJustifyH("LEFT")

    frame.rows = {}
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(true)

    frame.action = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.action:SetSize(150, 22)
    frame.action:SetPoint("BOTTOM", 0, 10)

    return frame
end
function Panel:Anchor(frame, owner)
    if not owner then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
    return true
end

function Panel:Render(frame, mode, rows, status, buttonText, enabled)
    frame.mode:SetText(mode or "")
    local top = -50
    for index, value in ipairs(rows or {}) do
        local row = frame.rows[index]
        if not row then
            row = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row:SetPoint("TOPLEFT", 12, top - ((index - 1) * ROW_HEIGHT))
            row:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
            row:SetJustifyH("LEFT")
            row:SetWordWrap(false)
            frame.rows[index] = row
        end
        row:SetText(value)
        row:Show()
    end
    for index = #(rows or {}) + 1, #frame.rows do
        frame.rows[index]:Hide()
    end
    local rowBottom = top - (#(rows or {}) * ROW_HEIGHT)
    frame.status:ClearAllPoints()
    frame.status:SetPoint("TOPLEFT", 12, rowBottom - 2)
    frame.status:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    frame.status:SetText(status or "")
    frame.action:SetText(buttonText or "Continue")
    frame.action:SetEnabled(enabled == true)
    frame:SetHeight(math.max(116, 82 + (#(rows or {}) * ROW_HEIGHT) + frame.status:GetStringHeight()))
end
