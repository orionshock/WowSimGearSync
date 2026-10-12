local addonName, WSGS = ...

function WSGS:ToggleWindow()
    if not self.window then
        self:CreateWindow()
    end
    if self.window:IsShown() then
        self.window:Hide()
    else
        self.window:Show()
    end
end

function WSGS:CreateWindow()
    local frame = CreateFrame("Frame", "WSGSMainWindow", UIParent)
    frame:Hide()
    frame:SetSize(420, 220)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetScript("OnShow", function()
        WSGS:Debug("Window opened.")
    end)
    frame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        WSGS:Debug("Window closed.")
    end)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.06, 0.06, 0.08, 0.95)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText("WowSimGearSync " .. self.version)

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 20, -65)
    body:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    body:SetJustifyH("LEFT")
    body:SetText("Mists of Pandaria Classic\n\nFoundation ready.\nDrag this window to move it.\n/wsgs debug toggles debug messages.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    self.window = frame
end
