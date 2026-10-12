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

-- Own only automatically generated names; any user edit gives control to them.
function WSGS:UpdateSuggestedProfileName(nameInput, text)
    if nameInput.userEdited or (nameInput:GetText() ~= "" and nameInput:GetText() ~= nameInput.suggestedName) then
        return
    end
    local suggestion = ""
    if #text <= 1048576 then
        local ok, document = pcall(C_EncodingUtil.DeserializeJSON, text)
        if ok and type(document) == "table" and document.apiVersion == 3 and type(document.player) == "table" then
            local spec = self:DetectSpecialization(document.player)
            if spec.id then suggestion = spec.class .. " - " .. spec.name end
        end
    end
    nameInput.suggestedName = suggestion
    if nameInput:GetText() ~= suggestion then nameInput:SetText(suggestion) end
end

function WSGS:CreateWindow()
    local frame = CreateFrame("Frame", "WSGSMainWindow", UIParent, "PortraitFrameTemplate")
    table.insert(UISpecialFrames, "WSGSMainWindow")
    frame:Hide()
    frame:SetSize(640, 660)
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

    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 24, -76)
    nameLabel:SetText("Profile name (optional)")
    local nameInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameInput:SetSize(540, 24)
    nameInput:SetPoint("TOPLEFT", 29, -98)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxBytes(80)
    nameInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self.userEdited = true end
    end)
    nameInput:SetScript("OnEscapePressed", function() frame:Hide() end)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    inputLabel:SetPoint("TOPLEFT", 24, -136)
    inputLabel:SetText("Paste a complete WoW Sims API v3 JSON export:")
    local scroll = CreateFrame("ScrollFrame", "WSGSImportScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -160)
    scroll:SetSize(570, 282)
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
    local suggestionDelay
    input:SetScript("OnUpdate", function(self, elapsed)
        ScrollingEdit_OnUpdate(self, elapsed)
        if suggestionDelay then
            suggestionDelay = suggestionDelay - elapsed
            if suggestionDelay <= 0 then
                suggestionDelay = nil
                WSGS:UpdateSuggestedProfileName(nameInput, self:GetText())
            end
        end
    end)
    input:SetScript("OnTextChanged", function(self)
        suggestionDelay = 0.25
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
    status:SetPoint("TOPLEFT", 24, -505)
    status:SetWidth(590)
    status:SetJustifyH("LEFT")
    status:SetText("Ready to import. Each import creates a separate build for this session.")
    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 24, -570)
    summary:SetWidth(590)
    summary:SetJustifyH("LEFT")
    local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(120, 28)
    importButton:SetPoint("TOPLEFT", 24, -460)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        input:ClearFocus()
        nameInput:ClearFocus()
        WSGS:UpdateSuggestedProfileName(nameInput, input:GetText())
        local profile, reason = WSGS:ImportEquipment(input:GetText(), nameInput:GetText())
        if not profile then
            status:SetTextColor(1, 0.35, 0.35)
            status:SetText("Import failed: " .. reason)
            return
        end
        status:SetTextColor(0.4, 1, 0.4)
        local metadata = profile.metadata
        local message = string.format("Imported %s (%s): %d entries, %d equipped, %d warnings.",
            profile.name, profile.specialization.class .. " - " .. profile.specialization.name, metadata.entryCount, metadata.equippedCount, #metadata.warnings)
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

    -- Child controls consume mouse input; raise without replacing their handlers.
    for _, control in ipairs({ nameInput, input, scroll, scroll.ScrollBar, importButton }) do
        control:HookScript("OnMouseDown", function() frame:Raise() end)
    end
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", importButton, "RIGHT", 12, 0)
    hint:SetText("Only equipment and build identification are retained.")

    self.window = frame
end
