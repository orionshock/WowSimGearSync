local _, WSGS = ...
local Modules = WSGS.Private
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
local UI = Modules.Views.Runtime
local Equipment = WSGS.Equipment

local FRAME_WIDTH, FRAME_HEIGHT = 350, 600
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
        GameTooltip:AddLine(L["Enter to save. Escape to cancel."], 1, 1, 1)
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
        Equipment:EquipAll()
    end)
    frame.equipButton = equip
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPRIGHT", -18, -88)
    note:SetWidth(320)
    note:SetJustifyH("RIGHT")
    frame.equipNote = note
    frame.slots = {}
    for position in ipairs(WSGS.Equipment.Slots) do
        frame.slots[position] = Modules.Views.SlotButton:Create(self, frame, position)
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
