local _, WSGS = ...
local Modules = WSGS.Private
local ItemData = WSGS:NewModule("ItemData", "AceEvent-3.0")
Modules.Character.ItemData = ItemData

function ItemData:RequestItemData(itemID, requester)
    if type(itemID) ~= "number" or itemID <= 0 then
        return nil, "Item ID must be a positive number"
    end
    self.pendingItemData = self.pendingItemData or {}
    requester = requester or true
    local subscribers = self.pendingItemData[itemID]
    if subscribers then
        subscribers[requester] = true
        return true
    end
    self.pendingItemData[itemID] = {[requester] = true}
    local ok, problem = pcall(C_Item.RequestLoadItemDataByID, itemID)
    if not ok then
        self:OnItemDataEvent("REQUEST_FAILED", itemID, false)
        return nil, tostring(problem)
    end
    return true
end

function ItemData:OnItemDataEvent(event, itemID, success)
    if not self.pendingItemData or not self.pendingItemData[itemID] then
        return
    end
    local subscribers = self.pendingItemData[itemID]
    self.pendingItemData[itemID] = nil
    local count = 0
    for requester in pairs(subscribers) do
        count = count + 1
        self:SendMessage("WSGS_ITEM_DATA_RECEIVED", itemID, success, requester)
    end
    if count > 1 or not success then
        WSGS:Debug(string.format("[STATE][ITEM_DATA] item=%d subscribers=%d success=%s event=%s", itemID,
            count, tostring(success), event))
    end

end


function ItemData:OnEnable()
    self:RegisterEvent("ITEM_DATA_LOAD_RESULT", "OnItemDataEvent")
end
