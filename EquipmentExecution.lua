local _, WSGS = ...
local Execution = {}
WSGS.EquipmentExecution = Execution

local function pickup(source)
    if source.bag ~= nil then C_Container.PickupContainerItem(source.bag, source.bagSlot)
    else PickupInventoryItem(WSGS.equipmentSlots[source.position].id) end
end

local function destinationHasSource(operation)
    if operation.kind ~= "EQUIP" or not operation.source.guid then return false end
    local location = ItemLocation:CreateFromEquipmentSlot(operation.slotId)
    local ok, guid = pcall(C_Item.GetItemGUID, location)
    return ok and guid == operation.source.guid
end

-- Called only synchronously by the Equip button's OnClick. Never from an event
-- or timer. Native cursor restrictions/confirmation dialogs remain authoritative.
function Execution:Perform(operation)
    if InCombatLockdown() or UnitAffectingCombat("player") then return false, "Cannot equip in combat." end
    if GetCursorInfo() then return false, "Place the held cursor item first." end
    -- An earlier operation can complete a later one (notably a MH/OH swap).
    -- The final scanner still verifies it independently.
    if destinationHasSource(operation) then return true, "SATISFIED" end
    local source = operation.source
    if source.bag ~= nil then
        local info = C_Container.GetContainerItemInfo(source.bag, source.bagSlot)
        if not info or info.isLocked then return false, "Source bag item is unavailable or locked." end
    elseif IsInventoryItemLocked(WSGS.equipmentSlots[source.position].id) then
        return false, "Source equipment is locked."
    end
    local location = source.bag ~= nil and ItemLocation:CreateFromBagAndSlot(source.bag, source.bagSlot)
        or ItemLocation:CreateFromEquipmentSlot(WSGS.equipmentSlots[source.position].id)
    local ok, guid = pcall(C_Item.GetItemGUID, location)
    if source.guid and (not ok or guid ~= source.guid) then return false, "Source instance changed; rescan required." end
    local link = source.bag ~= nil and C_Container.GetContainerItemLink(source.bag, source.bagSlot)
        or GetInventoryItemLink("player", WSGS.equipmentSlots[source.position].id)
    local decoded = WSGS.ItemLinkDecoder:Decode(link)
    if not decoded or decoded.payload ~= source.fingerprint then return false, "Source link changed; rescan required." end
    -- Secure item actions and /equipslot use this native direct path. A full
    -- link identifies the planned payload, and Planner enables it only when
    -- that fingerprint has one physical candidate. Unlike a cursor swap, the
    -- client can accept consecutive MH/OH requests from the same hardware click.
    if operation.kind == "EQUIP" and operation.direct then
        C_Item.EquipItemByName(link, operation.slotId)
        return true, "SUBMITTED"
    end
    if IsInventoryItemLocked(operation.slotId) then return false, "Equipment slot is locked." end
    if operation.kind == "UNEQUIP" then
        local destination = operation.destination
        if C_Container.GetContainerItemID(destination.bag, destination.bagSlot) then return false, "Bag space changed." end
        pickup(source)
        if not CursorHasItem() then return false, "Client did not pick up the off-hand item." end
        C_Container.PickupContainerItem(destination.bag, destination.bagSlot)
    else
        pickup(source)
        if not CursorHasItem() then return false, "Client did not pick up the planned item." end
        if not CursorCanGoInSlot(operation.slotId) then
            pickup(source) -- return the item to the now-empty source, within this click
            return false, "Client rejected this item for the destination slot."
        end
        PickupInventoryItem(operation.slotId)
        -- Return a displaced item to the source slot. Never destroy/clear a
        -- pre-existing cursor item and never issue a second equipment operation.
        if CursorHasItem() then pickup(source) end
    end
    if CursorHasItem() then return false, "Item remains on cursor; place it in a bag before retrying." end
    return true, "SUBMITTED" -- submission only; this is never treated as success
end
