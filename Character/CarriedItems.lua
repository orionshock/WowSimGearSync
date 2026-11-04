local _, WSGS = ...
local Inventory = {}
WSGS.EquipmentInventory = Inventory

function Inventory:Scan(equipment)
    local result = {
        items = {},
        free = {},
        unreadable = 0
    }
    equipment.context = equipment.context or {}
    equipment.context.titansGrip = C_SpellBook.IsSpellKnown(46917)
    for position, current in ipairs(equipment.slots) do
        current.guid = current.observations.instance.status == "KNOWN" and current.observations.instance.value or nil
        current.equipLoc = current.id and select(4, C_Item.GetItemInfoInstant(current.link or current.id))
        current.locked = IsInventoryItemLocked(WSGS.equipmentSlots[position].id)
    end
    -- Carried bags, including the reagent bag; never bank or account storage.
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local item = {
                    id = info.itemID,
                    link = info.hyperlink,
                    bag = bag,
                    bagSlot = slot,
                    count = info.stackCount or 1,
                    locked = info.isLocked,
                    observations = {}
                }
                local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(bag, slot))
                if ok and type(guid) == "string" and guid ~= "" then
                    item.guid = guid
                end
                item.equipLoc = (item.link or item.id) and select(4, C_Item.GetItemInfoInstant(item.link or item.id))
                item.observations = {
                    item = {status = "KNOWN", value = item.id, present = true},
                    enchant = WSGS.ItemEnchantment:Observe(item.link)
                }
                if not item.guid then
                    result.unreadable = result.unreadable + 1
                end
                result.items[#result.items + 1] = item
            elseif C_Container.GetContainerItemID(bag, slot) then
                result.unreadable = result.unreadable + 1
            elseif family == 0 then
                result.free[#result.free + 1] = {
                    bag = bag,
                    bagSlot = slot
                }
            end
        end
    end
    return result
end
