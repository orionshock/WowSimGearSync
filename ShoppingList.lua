local _, WSGS = ...
local Shopping = WSGS:NewModule("ShoppingList", "AceEvent-3.0")
local Equipment = WSGS:GetModule("Equipment")
local Materials = WSGS.ModificationMaterials

local PANEL_WIDTH, MAX_PANEL_HEIGHT = 260, 320
local ROW_HEIGHT = 38

local function updateScroll(scroll)
    scroll:GetScrollChild():SetWidth(scroll:GetWidth())
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
    ScrollFrame_OnScrollRangeChanged(scroll)
end

local function debug(category, text)
    WSGS:Debug("[SHOP][" .. category .. "] " .. text)
end

local function addRequirement(requirements, itemID, quantity)
    if type(itemID) == "number" and itemID > 0 and type(quantity) == "number" and quantity > 0 then
        requirements[itemID] = (requirements[itemID] or 0) + quantity
    end
end

local function professionDefinitionApplies(state, definition, inventorySlot)
    local professions = state.context and state.context.professions
    local validSlot = definition.slot == inventorySlot or definition.slots and definition.slots[inventorySlot]
    return validSlot and professions and professions[definition.profession] ~= nil
end

local function addProfessionReagents(requirements, state, definition, inventorySlot)
    if not definition or not professionDefinitionApplies(state, definition, inventorySlot) then
        return
    end
    for itemID, quantity in pairs(definition.reagents or {}) do
        addRequirement(requirements, itemID, quantity)
    end
end

local function collectSlotRequirements(requirements, state, slot)
    if not slot then
        return
    end
    local difference = slot.comparison
    if not difference or difference.fields.item.state ~= "MATCH" then
        return
    end
    local fields = difference.fields
    local gems = fields.gems
    for _, socket in ipairs(gems and gems.sockets or {}) do
        if socket.state == "MISMATCH" and type(socket.expected) == "number" and socket.expected > 0 then
            addRequirement(requirements, socket.expected, 1)
        end
    end

    local enchant = fields.enchant
    if enchant and enchant.state == "MISMATCH" then
        local inventory = Materials.actions.inventory[enchant.expected]
        if inventory and inventory.purchasable ~= false then
            addRequirement(requirements, inventory.itemID or inventory.purchasableItemID, 1)
        else
            addProfessionReagents(requirements, state, Materials.actions.profession[enchant.expected],
                difference.currentSlotId)
        end
    end

    local tinker = fields.tinker
    if tinker and tinker.state == "MISMATCH" then
        addProfessionReagents(requirements, state, Materials.actions.profession[tinker.expected],
            difference.currentSlotId)
    end

    local professionSocket = fields.professionSocket
    if professionSocket and professionSocket.state == "MISMATCH" then
        addProfessionReagents(requirements, state,
            Materials.actions.prerequisites.professionSockets[difference.currentSlotId], difference.currentSlotId)
    end

    local buckle = fields.buckle
    if buckle and buckle.state == "MISMATCH" then
        addRequirement(requirements, Materials.actions.prerequisites.beltBuckle.itemID, 1)
    end
end

function Shopping:BuildRequirements(state)
    local requirements = {}
    if not state or not state.build or not state.comparison then
        return {}
    end
    for position = 1, 16 do
        collectSlotRequirements(requirements, state, state.slots[position])
    end

    local entries, total = {}, 0
    for itemID, required in pairs(requirements) do
        local missing = required - ((state.bagItemCounts and state.bagItemCounts[itemID]) or 0)
        if missing > 0 then
            entries[#entries + 1] = {
                itemID = itemID,
                quantity = missing
            }
            total = total + missing
        end
    end
    table.sort(entries, function(left, right)
        return left.itemID < right.itemID
    end)
    return entries, total
end

function Shopping:HidePanel(reason)
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
        debug("HIDE", "reason=" .. tostring(reason))
    end
end

function Shopping:CreatePanel()
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
    title:SetText("WowSimGearSync — Shopping")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        self.dismissed = true
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

function Shopping:CreateRow(index)
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
        self:Search(clicked.entry)
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

function Shopping:Render(entries)
    local frame = self:CreatePanel()
    frame.content:SetWidth(frame.scroll:GetWidth())
    local contentHeight = 0
    for index, entry in ipairs(entries) do
        local row = self:CreateRow(index)
        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(entry.itemID)
        icon = icon or select(5, C_Item.GetItemInfoInstant(entry.itemID))
        entry.name = name
        row.entry = entry
        row.quantity:SetText("Need: " .. entry.quantity)
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
            Equipment:RequestItemData(entry.itemID, "ShoppingList")
        end
    end
    for index = #entries + 1, #frame.rows do
        frame.rows[index]:Hide()
    end
    frame:SetHeight(math.min(contentHeight + 44, MAX_PANEL_HEIGHT))
    frame.content:SetHeight(math.max(1, contentHeight))
    updateScroll(frame.scroll)
end

function Shopping:Refresh(state)
    if not self.auctionOpen or self.dismissed then
        return
    end
    local profile = WSGS:GetActiveSimulationProfile()
    if not profile then
        if self.requirementSignature ~= "no-build" then
            self.requirementSignature = "no-build"
            debug("BUILD", "build=nil entries=0 missing=0 reason=no-build")
        end
        self:HidePanel("no-build")
        return
    end
    state = state or Equipment:GetState(profile)
    local entries, total = self:BuildRequirements(state)
    local signatureParts = {}
    for _, entry in ipairs(entries) do
        signatureParts[#signatureParts + 1] = entry.itemID .. ":" .. entry.quantity
    end
    local signature = table.concat(signatureParts, ",")
    if self.requirementSignature ~= signature then
        self.requirementSignature = signature
        debug("BUILD", string.format("build=%s entries=%d missing=%d", state.build.name, #entries, total))
    end
    if #entries == 0 then
        self:HidePanel("empty")
        return
    end
    local auctionFrame = _G.AuctionHouseFrame
    if not auctionFrame or not auctionFrame:IsShown() then
        self:HidePanel("auction-frame-unavailable")
        return
    end
    self:Render(entries)
    local frame = self.frame
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", auctionFrame, "TOPRIGHT", 6, 0)
    if not frame:IsShown() then
        frame:Show()
        debug("SHOW", string.format("entries=%d missing=%d", #entries, total))
    end
end

function Shopping:QueueRefresh()
    if not self.auctionOpen or self.dismissed or self.refreshQueued then
        return
    end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        self:Refresh()
    end)
end

function Shopping:Search(entry)
    local auctionFrame = _G.AuctionHouseFrame
    if not entry or not entry.name or not self.auctionOpen or not auctionFrame or not auctionFrame:IsShown() then
        return
    end
    auctionFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
    if not auctionFrame:SetSearchText(entry.name) then
        return
    end
    self.pendingSearch = {
        itemID = entry.itemID,
        name = entry.name
    }
    auctionFrame.SearchBar:StartSearch()
    debug("SEARCH", string.format(
        "item=%d name=%s quantity=%d phase=browse api=AuctionHouseFrame.SearchBar:StartSearch", entry.itemID,
        entry.name, entry.quantity))
end

function Shopping:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
    local pending = self.pendingSearch
    if not pending then
        return
    end
    self.pendingSearch = nil
    local auctionFrame = _G.AuctionHouseFrame
    if not self.auctionOpen or not auctionFrame or not auctionFrame:IsShown() then
        return
    end
    for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        if result.itemKey and result.itemKey.itemID == pending.itemID then
            auctionFrame:SelectBrowseResult(result)
            debug("SEARCH", string.format(
                "item=%d name=%s phase=open-page api=AuctionHouseFrame.SelectBrowseResult", pending.itemID,
                pending.name))
            return
        end
    end
    debug("SEARCH", string.format("item=%d name=%s phase=browse result=no-exact-item", pending.itemID,
        pending.name))
end

function Shopping:AUCTION_HOUSE_BROWSE_FAILURE()
    if self.pendingSearch then
        debug("SEARCH", string.format("item=%d name=%s phase=browse result=failed", self.pendingSearch.itemID,
            self.pendingSearch.name))
        self.pendingSearch = nil
    end
end

function Shopping:AUCTION_HOUSE_SHOW()
    self.auctionOpen = true
    self.dismissed = false
    self.requestedItems = {}
    self.requirementSignature = nil
    self.pendingSearch = nil
    self:QueueRefresh()
end

function Shopping:AUCTION_HOUSE_CLOSED()
    self.auctionOpen = false
    self.dismissed = false
    self.pendingSearch = nil
    self:HidePanel("auction-closed")
end

function Shopping:WSGS_BUILD_IMPORTED()
    self:QueueRefresh()
end

function Shopping:WSGS_EQUIPMENT_STATE_INVALIDATED(_, reason)
    if reason == "BAG_UPDATE_DELAYED" then
        self:QueueRefresh()
    end
end

function Shopping:WSGS_ITEM_DATA_RECEIVED(_, itemID, success, requester)
    if requester == "ShoppingList" then
        self.requestedItems[itemID] = nil
        if success then
            self:QueueRefresh()
        end
    end
end

function Shopping:OnEnable()
    self.auctionOpen = false
    self.dismissed = false
    self.requestedItems = {}
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_INVALIDATED")
    self:RegisterMessage("WSGS_ITEM_DATA_RECEIVED")
end
