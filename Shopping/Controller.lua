local _, WSGS = ...
local Modules = WSGS.Private
local L = LibStub("AceLocale-3.0"):GetLocale("WowSimGearSync")
local Shopping = WSGS:NewModule("ShoppingList", "AceEvent-3.0")
Modules.Shopping.Runtime = Shopping
local Equipment = WSGS.Equipment

local function debug(category, text)
    WSGS:Debug("[SHOP][" .. category .. "] " .. text)
end

function Shopping:Refresh(state)
    if not self.auctionOpen or self.dismissed then
        return
    end
    local profile = WSGS.Builds:GetActive()
    if not profile then
        if self.requirementSignature ~= "no-build" then
            self.requirementSignature = "no-build"
            debug("BUILD", "build=nil entries=0 missing=0 reason=no-build")
        end
        self.panel:HidePanel("no-build")
        return
    end
    state = state or Equipment:GetState()
    local entries, total = Modules.Shopping.Requirements:Calculate(state)
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
        self.panel:HidePanel("empty")
        return
    end
    local auctionFrame = _G.AuctionHouseFrame
    if not auctionFrame or not auctionFrame:IsShown() then
        self.panel:HidePanel("auction-frame-unavailable")
        return
    end
    self.panel:Show(entries, auctionFrame)
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

function Shopping:AUCTION_HOUSE_SHOW()
    self.auctionOpen = true
    Modules.Shopping.Navigation:SetOpen(true)
    self.dismissed = false
    self.requirementSignature = nil
    self:QueueRefresh()
end

function Shopping:AUCTION_HOUSE_CLOSED()
    self.auctionOpen = false
    Modules.Shopping.Navigation:SetOpen(false)
    self.dismissed = false
    self.panel:HidePanel("auction-closed")
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
        self.panel:ItemDataReceived(itemID, success)
    end
end

function Shopping:OnEnable()
    self.panel = Modules.Views.CreateShoppingPanel({
        dismiss = function() self.dismissed = true end,
        search = function(entry) Modules.Shopping.Navigation:Search(entry) end,
        changed = function() self:QueueRefresh() end
    })
    self.auctionOpen = false
    Modules.Shopping.Navigation:SetOpen(false)
    self.dismissed = false
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterMessage("WSGS_STATE_CHANGED", "QueueRefresh")
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_INVALIDATED")
    self:RegisterMessage("WSGS_ITEM_DATA_RECEIVED")
end
