local _, WSGS = ...
local Modules = WSGS.Private
local Navigation = WSGS:NewModule("AuctionNavigation", "AceEvent-3.0")
Modules.Shopping.Navigation = Navigation
local function debug(category, text) WSGS:Debug("[SHOP][" .. category .. "] " .. text) end
function Navigation:SetOpen(open)
    self.open, self.pendingSearch = open, nil
end
function Navigation:Search(entry)
    local auctionFrame = _G.AuctionHouseFrame
    if not entry or not entry.name or not self.open or not auctionFrame or not auctionFrame:IsShown() then
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

function Navigation:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
    local pending = self.pendingSearch
    if not pending then
        return
    end
    self.pendingSearch = nil
    local auctionFrame = _G.AuctionHouseFrame
    if not self.open or not auctionFrame or not auctionFrame:IsShown() then
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

function Navigation:AUCTION_HOUSE_BROWSE_FAILURE()
    if self.pendingSearch then
        debug("SEARCH", string.format("item=%d name=%s phase=browse result=failed", self.pendingSearch.itemID,
            self.pendingSearch.name))
        self.pendingSearch = nil
    end
end


function Navigation:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")
end
