local _, WSGS = ...
local Modules = WSGS.Private
local Effects = {}
Modules.Character.ProfessionEffects = Effects
function Effects:Inspect(slotId, link)
    local ok, name, spellID = pcall(C_Item.GetItemSpell, link)
    if not ok then return {useSpell = {status = "UNKNOWN", reason = "C_Item.GetItemSpell failed"}} end
    return {useSpell = {status = "KNOWN", spellId = spellID, spellName = name,
        source = "C_Item.GetItemSpell"}}
end
