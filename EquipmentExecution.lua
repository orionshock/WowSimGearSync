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

local function shown(value)
    if value == nil or value == "" then return "nil" end
    return tostring(value)
end

local function cursorState()
    local kind, id = GetCursorInfo()
    return kind and (shown(kind) .. ":" .. shown(id)) or "empty"
end

local function sourceLocation(source)
    if source.bag ~= nil then return "bag:" .. source.bag .. ":" .. source.bagSlot end
    return "equipped:" .. shown(source.position)
end

-- Called only synchronously by the Equip button's OnClick. Never from an event
-- or timer. Native cursor restrictions/confirmation dialogs remain authoritative.
function Execution:Perform(operation, index, total)
    local source, before = operation.source, GetInventoryItemID("player", operation.slotId)
    local sourceInfo = source.bag ~= nil and C_Container.GetContainerItemInfo(source.bag, source.bagSlot)
    local sourceLocked = source.bag ~= nil
        and (not sourceInfo or sourceInfo.isLocked)
        or source.bag == nil and IsInventoryItemLocked(WSGS.equipmentSlots[source.position].id)
    local destinationLocked = IsInventoryItemLocked(operation.slotId)
    WSGS:Debug(string.format("[EQUIP][EXEC] op=%s/%s kind=%s source=%s item=%s GUID=%s destInv=%d API=%s cursorBefore=%s itemBefore=%s sourceLocked=%s destLocked=%s",
        shown(index), shown(total), operation.kind, sourceLocation(source), shown(source.id or operation.id), shown(source.guid),
        operation.slotId, operation.direct and "C_Item.EquipItemByName" or "cursor APIs", cursorState(), shown(before),
        shown(sourceLocked and true or false), shown(destinationLocked and true or false)))
    local function finish(ok, reason)
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s result=%s reason=%s cursorAfter=%s itemAfter=%s",
            shown(index), ok and "SUBMITTED" or "REJECTED", reason, cursorState(),
            shown(GetInventoryItemID("player", operation.slotId))))
        if not ok then WSGS:Debug(string.format("[EQUIP][BLOCK] op=%s inv=%d reason=%s", shown(index), operation.slotId, reason)) end
        return ok, reason
    end
    if InCombatLockdown() or UnitAffectingCombat("player") then return finish(false, "Cannot equip in combat.") end
    if GetCursorInfo() then return finish(false, "Place the held cursor item first.") end
    -- An earlier operation can complete a later one (notably a MH/OH swap).
    -- The final scanner still verifies it independently.
    if destinationHasSource(operation) then return finish(true, "SATISFIED") end
    if source.bag ~= nil then
        local info = C_Container.GetContainerItemInfo(source.bag, source.bagSlot)
        if not info or info.isLocked then return finish(false, "Source bag item is unavailable or locked.") end
    elseif IsInventoryItemLocked(WSGS.equipmentSlots[source.position].id) then
        return finish(false, "Source equipment is locked.")
    end
    local location = source.bag ~= nil and ItemLocation:CreateFromBagAndSlot(source.bag, source.bagSlot)
        or ItemLocation:CreateFromEquipmentSlot(WSGS.equipmentSlots[source.position].id)
    local ok, guid = pcall(C_Item.GetItemGUID, location)
    if source.guid and (not ok or guid ~= source.guid) then return finish(false, "Source instance changed; rescan required.") end
    local link = source.bag ~= nil and C_Container.GetContainerItemLink(source.bag, source.bagSlot)
        or GetInventoryItemLink("player", WSGS.equipmentSlots[source.position].id)
    local decoded = WSGS.ItemLinkDecoder:Decode(link)
    if not decoded or decoded.payload ~= source.fingerprint then return finish(false, "Source link changed; rescan required.") end
    -- Secure item actions and /equipslot use this native direct path. A full
    -- link identifies the planned payload, and Planner enables it only when
    -- that fingerprint has one physical candidate. Unlike a cursor swap, the
    -- client can accept consecutive MH/OH requests from the same hardware click.
    if operation.kind == "EQUIP" and operation.direct then
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=C_Item.EquipItemByName linkItem=%s destInv=%d",
            shown(index), shown(operation.id), operation.slotId))
        C_Item.EquipItemByName(link, operation.slotId)
        return finish(true, "SUBMITTED")
    end
    if IsInventoryItemLocked(operation.slotId) then return finish(false, "Equipment slot is locked.") end
    if operation.kind == "UNEQUIP" then
        local destination = operation.destination
        if C_Container.GetContainerItemID(destination.bag, destination.bagSlot) then return finish(false, "Bag space changed.") end
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=PickupInventoryItem sourceInv=%d",
            shown(index), WSGS.equipmentSlots[source.position].id))
        pickup(source)
        if not CursorHasItem() then return finish(false, "Client did not pick up the off-hand item.") end
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=C_Container.PickupContainerItem destBag=%d destSlot=%d",
            shown(index), destination.bag, destination.bagSlot))
        C_Container.PickupContainerItem(destination.bag, destination.bagSlot)
    else
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=%s source=%s",
            shown(index), source.bag ~= nil and "C_Container.PickupContainerItem" or "PickupInventoryItem",
            sourceLocation(source)))
        pickup(source)
        if not CursorHasItem() then return finish(false, "Client did not pick up the planned item.") end
        if not CursorCanGoInSlot(operation.slotId) then
            pickup(source) -- return the item to the now-empty source, within this click
            return finish(false, "Client rejected this item for the destination slot.")
        end
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=PickupInventoryItem destInv=%d",
            shown(index), operation.slotId))
        PickupInventoryItem(operation.slotId)
        -- Return a displaced item to the source slot. Never destroy/clear a
        -- pre-existing cursor item and never issue a second equipment operation.
        if CursorHasItem() then pickup(source) end
    end
    if CursorHasItem() then return finish(false, "Item remains on cursor; place it in a bag before retrying.") end
    return finish(true, "SUBMITTED") -- submission only; this is never treated as success
end
