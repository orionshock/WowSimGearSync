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

-- The import callback owns storage/notifications; this dialog owns presentation.
function WSGS:SubmitImport(frame, import)
    frame.importInput:ClearFocus()
    local profile, reason = import(frame.importInput:GetText())
    if not profile then
        frame.importStatus:SetText("Import failed: " .. reason)
        return nil, reason
    end
    frame:Hide()
    return profile
end

function WSGS:CreateWindow()
    local frame = CreateFrame("Frame", "WSGSMainWindow", UIParent, "PortraitFrameTemplate")
    table.insert(UISpecialFrames, "WSGSMainWindow")
    frame:Hide()
    frame:SetSize(640, 550)
    frame:SetPoint("CENTER")
    -- Keep the import dialog above the paper doll, which uses DIALOG.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetScript("OnMouseDown", function(self) self:Raise() end)
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
    frame:SetScript("OnShow", function(self)
        self:Raise()
        self.importStatus:SetText("")
        WSGS:Debug("Window opened.")
    end)
    frame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        WSGS:Debug("Window closed.")
    end)

    frame.TitleContainer.TitleText:SetText("WowSimGearSync - Import")
    frame.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -40)
    title:SetText("Import equipment")
    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPRIGHT", -30, -44)
    version:SetText("v" .. self.version)

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    inputLabel:SetPoint("TOPLEFT", 24, -78)
    inputLabel:SetText("Paste a complete WoW Sims API v3 JSON export:")
    local scroll = CreateFrame("ScrollFrame", "WSGSImportScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -102)
    scroll:SetSize(570, 340)
    local inputBackground = frame:CreateTexture(nil, "ARTWORK")
    inputBackground:SetAllPoints(scroll)
    inputBackground:SetColorTexture(0, 0, 0, 0.7)
    local input = CreateFrame("EditBox", nil, scroll)
    input:SetMultiLine(true)
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal)
    input:SetWidth(560)
    -- Multiline EditBox grows to its rendered text height. A guessed line
    -- height fights that layout, especially for wrapped/minified exports.
    input:SetHeight(1)
    input:SetMaxLetters(0)
    input:SetMaxBytes(1048576 + 1)
    input:SetTextInsets(5, 5, 5, 5)
    scroll:SetScrollChild(input)
    input:SetScript("OnEscapePressed", function() frame:Hide() end)
    ScrollingEdit_OnLoad(input)
    input:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    input:SetScript("OnUpdate", ScrollingEdit_OnUpdate)
    input:SetScript("OnTextChanged", function(self)
        scroll:UpdateScrollChildRect()
        local range = scroll:GetVerticalScrollRange()
        if scroll:GetVerticalScroll() > range then
            scroll:SetVerticalScroll(math.max(0, range))
        end
        -- Cursor scrolling runs on the next update, after text layout settles.
        self.handleCursorChange = true
    end)
    scroll:HookScript("OnSizeChanged", function(self, width)
        input:SetWidth(width - 10)
    end)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function()
        input:SetFocus()
    end)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", 24, -500)
    status:SetWidth(590)
    status:SetJustifyH("LEFT")
    status:SetTextColor(1, 0.35, 0.35)
    status:SetText("")
    local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(120, 28)
    importButton:SetPoint("TOPLEFT", 24, -460)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        WSGS:SubmitImport(frame, function(text) return WSGS:ImportEquipment(text) end)
    end)
    frame:HookScript("OnHide", function()
        input:ClearFocus()
    end)
    frame.importInput = input
    frame.importStatus = status

    -- Child controls consume mouse input; raise without replacing their handlers.
    for _, control in ipairs({ input, scroll, scroll.ScrollBar, importButton }) do
        control:HookScript("OnMouseDown", function() frame:Raise() end)
    end
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", importButton, "RIGHT", 12, 0)
    hint:SetText("Only equipment and build identification are retained.")

    self.window = frame
end
