local _, WSGS = ...
local Modules = WSGS.Private
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
local UI = Modules.Views.Runtime
local Equipment = WSGS.Equipment
local Presentation = UI.SlotPresentation
local equipButtonLabels = {
    READY = "Equip",
    PENDING = "Equipping",
    CURSOR = "Blocked",
    COMBAT = "Blocked",
    FAULT = "Blocked",
    BLOCKED = "Blocked",
    COMPLETE = "Sync Set"
}

function UI:ShowSlotTooltip(button)
    UI.ModificationTooltip:Hide()
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if Presentation:IsConfigurationComplete(button.difference) then
        local inventorySlot = button.difference.currentSlotId
        if not GameTooltip:SetInventoryItem("player", inventorySlot) then
            if button.current and button.current.link then
                GameTooltip:SetHyperlink(button.current.link)
            else
                GameTooltip:SetItemByID(button.target.id)
            end
        end
        GameTooltip:Show()
        return
    end
    local actionState = button.actionState or WSGS.Enhancements:GetSlotState(button.position)
    local item = button.difference and button.difference.fields.item
    if item and item.state ~= "MATCH" then
        actionState = Equipment:GetSlotState(button.position)
    end
    local title, red, green, blue, action = Presentation:ItemTooltip(button.target, actionState)
    GameTooltip:AddLine(title, red, green, blue)
    if action then
        GameTooltip:AddLine(action, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function UI:ShowModificationTooltip(icon)
    local status = icon.presentation
    if status and icon.owner then
        local refreshed
        for _, current in ipairs(Presentation:ModificationIcons(icon.owner.difference, icon.owner.actionState)) do
            if current.key == status.key then
                refreshed = current
                break
            end
        end
        status, icon.presentation = refreshed, refreshed
    end
    if not status or status.state == "COMPLETE" then
        self.hoveredIcon = nil
        GameTooltip:Hide()
        UI.ModificationTooltip:Hide()
        return
    end
    GameTooltip:Hide()
    UI.ModificationTooltip:Show(icon, status)
end

local function registerTooltipItems(self, frame, status)
    local tooltip = status and status.tooltip
    for _, section in ipairs(tooltip and tooltip.sections or {}) do
        for _, value in ipairs({section.current or {}, section.target or {}}) do
            local itemID = value and value.itemID
            if itemID then
                self.relevantItems[itemID] = true
                if frame:IsShown() and not C_Item.GetItemInfo(itemID) and not self.requestedItems[itemID] then
                    self.requestedItems[itemID] = true
                    WSGS.Character:RequestItemData(itemID, "PaperDoll:modification-tooltip")
                end
            end
        end
    end
end

function UI:RenderPaperDoll(state)
    local frame = self:CreatePaperDoll()
    local equipmentStatus = Equipment:GetStatus()
    local profile = state and state.build
    local comparison = state and state.comparison
    local reason = state and state.reason
    self.profile = profile
    if not frame.buildName:HasFocus() or frame.buildName.build ~= WSGS.Builds:GetActive() then
        frame.buildName:SetText(profile and profile.name or "No active build")
    end
    frame.buildName.build = WSGS.Builds:GetActive()
    if profile then
        frame.buildName:Enable()
    else
        frame.buildName:Disable()
    end
    if not profile then
        frame.summary:SetText(L["Import a WoW Sims build to get started."])
    elseif comparison then
        local s = comparison.summary
        frame.summary:SetText(string.format(
            "Equipped: %d/%d  |  To equip: %d\nEnhancements needed: %d  |  Unknown: %d",
            s.matched, #WSGS.Equipment.Slots, s.itemMismatches, s.configurationMismatches, s.unknown))
    else
        frame.summary:SetText(reason or "Comparison unavailable")
    end
    self.relevantItems = {}
    for position, button in ipairs(frame.slots) do
        local slotState = state and state.slots[position]
        local target = slotState and slotState.target
        local difference = slotState and slotState.comparison
        local current = slotState and slotState.current
        button.target, button.current, button.difference = target, current, difference
        for _, item in ipairs({target or {}, current or {}}) do
            if item.id and item.id > 0 then
                self.relevantItems[item.id] = true
            end
        end
    end
    for _, button in ipairs(frame.slots) do
        local target = button.target
        local texture = select(2, GetInventorySlotInfo(WSGS.Equipment.Slots[button.position].token))
        local quality
        if target and target.id and target.id > 0 then
            local name, _, rarity, _, _, _, _, _, _, cachedIcon = C_Item.GetItemInfo(target.id)
            quality = rarity
            texture = cachedIcon or select(5, C_Item.GetItemInfoInstant(target.id)) or
                          "Interface\\Icons\\INV_Misc_QuestionMark"
            if not name and frame:IsShown() and not self.requestedItems[target.id] then
                self.requestedItems[target.id] = true
                WSGS.Character:RequestItemData(target.id, "PaperDoll:target")
            end
        end
        button.icon:SetTexture(texture)
        local color = quality and ITEM_QUALITY_COLORS[quality]
        local item = button.difference and button.difference.fields.item
        if item and item.state == "MISMATCH" then
            button.quality:SetVertexColor(1, 0, 0)
        else
            button.quality:SetVertexColor(color and color.r or 0.5, color and color.g or 0.5, color and color.b or 0.5)
        end
        local actionState = WSGS.Enhancements:GetSlotState(button.position)
        actionState.pending = actionState.pending or equipmentStatus.pendingSlots[button.position] or false
        button.actionState = actionState
        local statuses = Presentation:ModificationIcons(button.difference, actionState)
        for index, icon in ipairs(button.statusIcons) do
            local status = statuses[index]
            icon.presentation = status
            if status then
                registerTooltipItems(self, frame, status)
                icon.texture:SetTexture(status.texture)
                icon.texture:SetVertexColor(1, 1, 1)
                icon:Show()
            else
                icon:Hide()
            end
        end
        button.icon:SetDesaturated(actionState.pending)
        if not InCombatLockdown() then
            button:Enable()
        end
    end
    if self.hovered and frame:IsShown() then
        self:ShowSlotTooltip(self.hovered)
    elseif self.hoveredIcon then
        if self.hoveredIcon:IsShown() then
            self:ShowModificationTooltip(self.hoveredIcon)
        else
            self.hoveredIcon = nil
            UI.ModificationTooltip:Hide()
        end
    end
end

function UI:UpdateEquipButton()
    if not self.paperDoll then
        return
    end
    local actions = Equipment:GetStatus()
    self.paperDoll.equipButton:SetText(equipButtonLabels[actions.state] or "Blocked")
    self.paperDoll.equipButton:SetEnabled(actions.state == "READY" or actions.state == "FAULT" or actions.state ==
                                              "COMPLETE")
    local counts = actions.counts
    local note = actions.state == "CURSOR" and "Place the held cursor item first." or actions.state == "COMBAT" and
                     "Cannot equip in combat." or actions.fault or counts and counts.STILL_PENDING > 0 and
                     string.format("Equipping: %d/%d verified; %d target slot(s) unresolved.", counts.VERIFIED,
            actions.total, actions.unresolvedCount) or
                     (actions.missingCount > 0 and ("Missing target items: " .. actions.missingCount) or actions.blocker or
                         actions.unresolvedCount > 0 and (actions.unresolvedCount .. " target slot(s) unresolved.")) or ""
    self.paperDoll.equipNote:SetText(WSGS:FormatPlayerReason(note))
end
