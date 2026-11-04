local _, WSGS = ...
local Modules = WSGS.Private
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
local function debug(category, text) WSGS:Debug("[SHOP][" .. category .. "] " .. text) end
local PANEL_WIDTH, MAX_PANEL_HEIGHT = 260, 320
local ROW_HEIGHT = 38

local function updateScroll(scroll)
    scroll:GetScrollChild():SetWidth(scroll:GetWidth())
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
    ScrollFrame_OnScrollRangeChanged(scroll)
end


function Modules.Views.CreateShoppingPanel(callbacks)
    local Panel = {requestedItems = {}}
function Panel:HidePanel(reason)
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
        debug("HIDE", "reason=" .. tostring(reason))
    end
end

function Panel:CreatePanel()
    if self.frame then
        return self.frame
    end
    local frame = CreateFrame("Frame", "WSGSShoppingList", UIParent, "TooltipBackdropTemplate")
    frame:Hide()
    frame:SetSize(PANEL_WIDTH, 100)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 12, -11)
    title:SetPoint("RIGHT", frame, "RIGHT", -28, 0)
    title:SetJustifyH("LEFT")
    title:SetText(L["Shopping List"])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        callbacks.dismiss()
        self:HidePanel("manual")
    end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -34)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_WIDTH - 42, 1)
    scroll:SetScrollChild(content)
    scroll.scrollBarHideable = true
    scroll.ScrollBar.scrollStep = ROW_HEIGHT
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", ScrollFrameTemplate_OnMouseWheel)
    scroll:SetScript("OnSizeChanged", updateScroll)

    frame.rows = {}
    frame.content = content
    frame.scroll = scroll
    self.frame = frame
    return frame
end

function Panel:CreateRow(index)
    local frame = self:CreatePanel()
    if frame.rows[index] then
        return frame.rows[index]
    end
    local row = CreateFrame("Button", nil, frame.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("TOPLEFT", 0, -6)
    row.quantity = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -3, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(true)
    row.quantity:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.quantity:SetPoint("RIGHT", row, "RIGHT", -3, 0)
    row.quantity:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(clicked)
        callbacks.search(clicked.entry)
    end)
    row:SetScript("OnEnter", function(hovered)
        if hovered.entry then
            GameTooltip:SetOwner(hovered, "ANCHOR_RIGHT")
            if hovered.entry.name then
                GameTooltip:SetItemByID(hovered.entry.itemID)
            else
                GameTooltip:ClearLines()
                GameTooltip:AddLine("Loading item information...")
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row:SetScript("OnHide", function(hidden)
        if GameTooltip:IsOwned(hidden) then
            GameTooltip:Hide()
        end
    end)
    frame.rows[index] = row
    return row
end

function Panel:Render(entries)
    local frame = self:CreatePanel()
    frame.content:SetWidth(frame.scroll:GetWidth())
    local contentHeight = 0
    for index, entry in ipairs(entries) do
        local row = self:CreateRow(index)
        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(entry.itemID)
        icon = icon or select(5, C_Item.GetItemInfoInstant(entry.itemID))
        entry.name = name
        row.entry = entry
        row.quantity:SetText(string.format(L["× %d"], entry.quantity))
        row.name:SetText(name or "Required material")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -contentHeight)
        row:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
        row:SetHeight(math.max(ROW_HEIGHT, math.ceil(row.name:GetStringHeight() +
            row.quantity:GetStringHeight() + 14)))
        contentHeight = contentHeight + row:GetHeight()
        row.icon:SetTexture(icon)
        local color = quality and ITEM_QUALITY_COLORS[quality]
        row.name:SetTextColor(color and color.r or 0.55, color and color.g or 0.7, color and color.b or 1)
        row:SetEnabled(name ~= nil)
        row:Show()
        if GameTooltip:IsOwned(row) then
            if name then
                GameTooltip:SetItemByID(entry.itemID)
            else
                GameTooltip:ClearLines()
                GameTooltip:AddLine("Loading item information...")
            end
            GameTooltip:Show()
        end
        if (not name or not icon) and not self.requestedItems[entry.itemID] then
            self.requestedItems[entry.itemID] = true
            WSGS.Character:RequestItemData(entry.itemID, "ShoppingList")
        end
    end
    for index = #entries + 1, #frame.rows do
        frame.rows[index]:Hide()
    end
    frame:SetHeight(math.min(contentHeight + 44, MAX_PANEL_HEIGHT))
    frame.content:SetHeight(math.max(1, contentHeight))
    updateScroll(frame.scroll)
end


function Panel:Show(entries, owner)
    self:Render(entries)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
    self.frame:Show()
end
function Panel:ItemDataReceived(itemID, success)
    self.requestedItems[itemID] = nil
    if success then callbacks.changed() end
end
    return Panel
end
