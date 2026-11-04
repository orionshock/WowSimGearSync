local _, WSGS = ...
local Modules = WSGS.Private
local Effects = {}
Modules.Character.ProfessionEffects = Effects
function Effects:Inspect(slotId, link)
    local location = ItemLocation:CreateFromEquipmentSlot(slotId)
    if not C_Item.IsItemDataCached(location) then
        local itemID = C_Item.GetItemID(location)
        if itemID then WSGS.Character:RequestItemData(itemID, "Character:use-spell") end
        return {useSpell = {status = "UNKNOWN", reason = "Item use spell data is loading"}}
    end
    local ok, name, spellID = pcall(C_Item.GetItemSpell, link)
    if not ok then return {useSpell = {status = "UNKNOWN", reason = "C_Item.GetItemSpell failed"}} end
    return {useSpell = {status = "KNOWN", spellId = spellID, spellName = name,
        source = "C_Item.GetItemSpell"}}
end
