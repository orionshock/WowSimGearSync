local _, WSGS = ...
local Inventory = {}
WSGS.EquipmentInventory = Inventory

function Inventory:Scan()
    local result = {
        items = {},
        free = {},
        unreadable = 0,
        materials = {byItem = {}, bySpell = {}, counts = {}}
    }
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
                local materials = result.materials
                materials.counts[item.id] = (materials.counts[item.id] or 0) + item.count
                if not materials.byItem[item.id] or materials.byItem[item.id].locked and not item.locked then
                    materials.byItem[item.id] = item
                end
                local ok, _, spellID = pcall(C_Item.GetItemSpell, item.link or item.id)
                if ok and spellID then
                    item.spellID = spellID
                    if not materials.bySpell[spellID] or materials.bySpell[spellID].locked and not item.locked then
                        materials.bySpell[spellID] = item
                    end
                end
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
