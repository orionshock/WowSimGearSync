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
    frame:SetSize(640, 660)
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

    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 20, -58)
    nameLabel:SetText("Profile name (optional)")
    local nameInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameInput:SetSize(350, 24)
    nameInput:SetPoint("TOPLEFT", 25, -80)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxBytes(80)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    inputLabel:SetPoint("TOPLEFT", 20, -118)
    inputLabel:SetText("Paste a complete WoW Sims API v3 JSON export:")
    local scroll = CreateFrame("ScrollFrame", "WSGSImportScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -145)
    scroll:SetSize(570, 290)
    local inputBackground = scroll:CreateTexture(nil, "BACKGROUND")
    inputBackground:SetAllPoints()
    inputBackground:SetColorTexture(0, 0, 0, 0.7)
    local input = CreateFrame("EditBox", nil, scroll)
    input:SetMultiLine(true)
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal)
    input:SetWidth(560)
    input:SetHeight(290)
    input:SetMaxLetters(0)
    input:SetMaxBytes(1048576 + 1)
    input:SetTextInsets(5, 5, 5, 5)
    scroll:SetScrollChild(input)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnTextChanged", function(self)
        self:SetHeight(math.max(290, self:GetNumLines() * 16 + 20))
        scroll:UpdateScrollChildRect()
    end)
    input:SetScript("OnCursorChanged", function(self, x, y, width, height)
        local top = math.abs(y)
        local offset = scroll:GetVerticalScroll()
        if top < offset then
            scroll:SetVerticalScroll(top)
        elseif top + height > offset + scroll:GetHeight() then
            scroll:SetVerticalScroll(top + height - scroll:GetHeight())
        end
    end)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", 20, -485)
    status:SetWidth(590)
    status:SetJustifyH("LEFT")
    status:SetText("Ready to import. Each import creates a separate build for this session.")
    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 20, -550)
    summary:SetWidth(590)
    summary:SetJustifyH("LEFT")
    local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(120, 26)
    importButton:SetPoint("TOPLEFT", 20, -450)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        input:ClearFocus()
        nameInput:ClearFocus()
        local profile, reason = WSGS:ImportEquipment(input:GetText(), nameInput:GetText())
        if not profile then
            status:SetTextColor(1, 0.35, 0.35)
            status:SetText("Import failed: " .. reason)
            return
        end
        status:SetTextColor(0.4, 1, 0.4)
        local metadata = profile.metadata
        local message = string.format("Imported %s (%s): %d entries, %d equipped, %d warnings.",
            profile.name, tostring(profile.class), metadata.entryCount, metadata.equippedCount, #metadata.warnings)
        if #metadata.warnings > 0 then message = message .. "\n" .. metadata.warnings[1]:sub(1, 180) end
        status:SetText(message)
        local lines = {}
        for index, item in ipairs(profile.equipment) do
            local line = math.floor((index - 1) / 4) + 1
            local label = item.slotName .. ": " .. (item.empty and "empty" or tostring(item.id))
            lines[line] = lines[line] and (lines[line] .. " / " .. label) or label
        end
        summary:SetText(table.concat(lines, "\n"))
    end)
    frame:HookScript("OnHide", function()
        input:ClearFocus()
        nameInput:ClearFocus()
    end)
    frame.importInput = input
    frame.profileNameInput = nameInput
    frame.importStatus = status
    frame.importSummary = summary

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    self.window = frame
end
