local _, WSGS = ...
local Modules = WSGS.Private
local SlotButton = {}
Modules.Views.SlotButton = SlotButton
local SLOT_SIDE_INSET, SLOT_TOP_OFFSET, SLOT_ROW_SPACING = 10, 104, 47
local Presentation = Modules.Views.Runtime.SlotPresentation
function SlotButton:Create(owner, frame, position)
        local button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
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
                owner.hoveredIcon = icon
                owner:ShowModificationTooltip(icon)
            end)
            statusIcon:SetScript("OnLeave", function()
                owner.hoveredIcon = nil
                owner.ModificationTooltip:Hide()
            end)
            statusIcon:SetScript("OnHide", function(icon)
                if owner.hoveredIcon == icon then
                    owner.hoveredIcon = nil
                    owner.ModificationTooltip:Hide()
                end
            end)
            statusIcon:Hide()
        end
        button:SetScript("OnEnter", function(b)
            owner.hovered = b;
            owner:ShowSlotTooltip(b)
        end)
        button:SetScript("OnLeave", function()
            owner.hovered = nil;
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
        WSGS.Enhancements:BindSlot(position, button)
    return button
end
