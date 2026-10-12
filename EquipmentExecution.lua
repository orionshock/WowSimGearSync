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

local function logResult(operation, index, ok, reason)
    WSGS:Debug(string.format("[EQUIP][EXEC] op=%s result=%s reason=%s cursorAfter=%s itemAfter=%s",
        shown(index), ok and "SUBMITTED" or "REJECTED", reason, cursorState(),
        shown(GetInventoryItemID("player", operation.slotId))))
    if not ok then
        WSGS:Debug(string.format("[EQUIP][BLOCK] op=%s inv=%d reason=%s",
            shown(index), operation.slotId, reason))
    end
end

-- Called only synchronously by the Equip button's OnClick. Never from an event
-- or timer. Native cursor restrictions/confirmation dialogs remain authoritative.
function Execution:Perform(operation, index, total)
    local source, before = operation.source, GetInventoryItemID("player", operation.slotId)
    local sourceInfo = source.bag ~= nil and C_Container.GetContainerItemInfo(source.bag, source.bagSlot)
    local sourceLocked = source.bag ~= nil and (not sourceInfo or sourceInfo.isLocked)
        or source.bag == nil and IsInventoryItemLocked(WSGS.equipmentSlots[source.position].id)
    local destinationLocked = IsInventoryItemLocked(operation.slotId)
    WSGS:Debug(string.format("[EQUIP][EXEC] op=%s/%s kind=%s source=%s item=%s GUID=%s destInv=%d API=%s cursorBefore=%s itemBefore=%s sourceLocked=%s destLocked=%s",
        shown(index), shown(total), operation.kind, sourceLocation(source), shown(source.id or operation.id),
        shown(source.guid), operation.slotId, operation.direct and "C_Item.EquipItemByName" or "cursor APIs",
        cursorState(), shown(before), shown(sourceLocked and true or false),
        shown(destinationLocked and true or false)))

    if InCombatLockdown() or UnitAffectingCombat("player") then
        local reason = "Cannot equip in combat."
        logResult(operation, index, false, reason)
        return false, reason
    end
    if GetCursorInfo() then
        local reason = "Place the held cursor item first."
        logResult(operation, index, false, reason)
        return false, reason
    end
    if destinationHasSource(operation) then
        logResult(operation, index, true, "SATISFIED")
        return true, "SATISFIED"
    end
    if source.bag ~= nil then
        local info = C_Container.GetContainerItemInfo(source.bag, source.bagSlot)
        if not info or info.isLocked then
            local reason = "Source bag item is unavailable or locked."
            logResult(operation, index, false, reason)
            return false, reason
        end
    elseif IsInventoryItemLocked(WSGS.equipmentSlots[source.position].id) then
        local reason = "Source equipment is locked."
        logResult(operation, index, false, reason)
        return false, reason
    end

    local location = source.bag ~= nil and ItemLocation:CreateFromBagAndSlot(source.bag, source.bagSlot)
        or ItemLocation:CreateFromEquipmentSlot(WSGS.equipmentSlots[source.position].id)
    local guidOK, guid = pcall(C_Item.GetItemGUID, location)
    if source.guid and (not guidOK or guid ~= source.guid) then
        local reason = "Source instance changed; rescan required."
        logResult(operation, index, false, reason)
        return false, reason
    end
    local link = source.bag ~= nil and C_Container.GetContainerItemLink(source.bag, source.bagSlot)
        or GetInventoryItemLink("player", WSGS.equipmentSlots[source.position].id)
    local decoded = WSGS.ItemLinkDecoder:Decode(link)
    if not decoded or decoded.payload ~= source.fingerprint then
        local reason = "Source link changed; rescan required."
        logResult(operation, index, false, reason)
        return false, reason
    end

    if operation.kind == "EQUIP" and operation.direct then
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=C_Item.EquipItemByName linkItem=%s destInv=%d",
            shown(index), shown(operation.id), operation.slotId))
        C_Item.EquipItemByName(link, operation.slotId)
        logResult(operation, index, true, "SUBMITTED")
        return true, "SUBMITTED"
    end
    if IsInventoryItemLocked(operation.slotId) then
        local reason = "Equipment slot is locked."
        logResult(operation, index, false, reason)
        return false, reason
    end

    if operation.kind == "UNEQUIP" then
        local destination = operation.destination
        if C_Container.GetContainerItemID(destination.bag, destination.bagSlot) then
            local reason = "Bag space changed."
            logResult(operation, index, false, reason)
            return false, reason
        end
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=PickupInventoryItem sourceInv=%d",
            shown(index), WSGS.equipmentSlots[source.position].id))
        pickup(source)
        if not CursorHasItem() then
            local reason = "Client did not pick up the off-hand item."
            logResult(operation, index, false, reason)
            return false, reason
        end
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=C_Container.PickupContainerItem destBag=%d destSlot=%d",
            shown(index), destination.bag, destination.bagSlot))
        C_Container.PickupContainerItem(destination.bag, destination.bagSlot)
    else
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=%s source=%s",
            shown(index), source.bag ~= nil and "C_Container.PickupContainerItem" or "PickupInventoryItem",
            sourceLocation(source)))
        pickup(source)
        if not CursorHasItem() then
            local reason = "Client did not pick up the planned item."
            logResult(operation, index, false, reason)
            return false, reason
        end
        if not CursorCanGoInSlot(operation.slotId) then
            pickup(source)
            local reason = "Client rejected this item for the destination slot."
            logResult(operation, index, false, reason)
            return false, reason
        end
        WSGS:Debug(string.format("[EQUIP][EXEC] op=%s call=PickupInventoryItem destInv=%d",
            shown(index), operation.slotId))
        PickupInventoryItem(operation.slotId)
        if CursorHasItem() then pickup(source) end
    end
    if CursorHasItem() then
        local reason = "Item remains on cursor; place it in a bag before retrying."
        logResult(operation, index, false, reason)
        return false, reason
    end
    logResult(operation, index, true, "SUBMITTED")
    return true, "SUBMITTED"
end
