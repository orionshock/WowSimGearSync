local _, WSGS = ...
local Modules = WSGS.Private
local Inspector = {}
Modules.Character.ProfessionEffects = Inspector
local MaterialCatalog = Modules.Enhancements.Catalog

WSGS:RegisterMessage("WSGS_ITEM_DATA_RECEIVED", function(_, itemID, success, requester)
    if requester == "EquipmentInspector:tinker" and not success and Inspector.requestedTinkerItems then
        Inspector.requestedTinkerItems[itemID] = nil
    end
end)

local function unknown(reason)
    return {
        status = "UNKNOWN",
        reason = reason
    }
end
local function known(value, source)
    return {
        status = "KNOWN",
        value = value,
        source = source
    }
end
function Inspector:Inspect(slotId, link)
    local result = {}
    result.tinker = unknown("Profession effect not established")
    local _, _, supportedProfessionSlot = MaterialCatalog:ProfessionEffect(slotId)
    if supportedProfessionSlot then
        local ok, name, spellId = pcall(C_Item.GetItemSpell, link)
        local requestedItemData = false
        local effect, skillLine = MaterialCatalog:ProfessionEffect(slotId, spellId)
        if ok and effect and effect.effectID then
            result.tinker = known(effect.effectID, "C_Item.GetItemSpell / profession effect mapping")
        elseif ok and effect and effect.different then
            result.tinker = {
                status = "KNOWN",
                different = true,
                spellId = spellId,
                spellName = name,
                source = "C_Item.GetItemSpell / known alternate profession effect"
            }
        else
            result.tinker = unknown(not ok and "C_Item.GetItemSpell failed" or not spellId and
                                        "C_Item.GetItemSpell returned nil" or
                                        "Equipped item use spell is not mapped for this profession slot")
        end
        if ok then
            result.tinker.spellId, result.tinker.spellName = spellId, name
        end
        if ok and not spellId then
            local itemID = C_Item.GetItemID(ItemLocation:CreateFromEquipmentSlot(slotId))
            self.requestedTinkerItems = self.requestedTinkerItems or {}
            if itemID and not self.requestedTinkerItems[itemID] then
                self.requestedTinkerItems[itemID] = true
                requestedItemData = true
                Modules.Character.ItemData:RequestItemData(itemID, "EquipmentInspector:tinker")
            end
        end
        local rawLink = type(link) == "string" and (link:match("|H(item:[^|]+)|h") or link) or tostring(link)
        local mapped = effect and (effect.effectID or effect.name or effect.different)
        local signature = table.concat({rawLink, tostring(ok), tostring(spellId), tostring(name), tostring(skillLine),
                                        tostring(mapped), tostring(requestedItemData), result.tinker.status,
                                        tostring(result.tinker.value)}, ":")
        self.tinkerDiagnostics = self.tinkerDiagnostics or {}
        if self.tinkerDiagnostics[slotId] ~= signature then
            self.tinkerDiagnostics[slotId] = signature
            WSGS:Debug(string.format(
                "[ACTION][VERIFY] slot=%d type=TINKER profession=%s item=%s getItemSpell=%s spellID=%s spellName=%s mapped=%s itemDataRequested=%s result=%s observed=%s reason=%s",
                slotId, tostring(skillLine), rawLink, ok and "ok" or "error", tostring(spellId), tostring(name),
                tostring(mapped), tostring(requestedItemData), result.tinker.status,
                tostring(result.tinker.value or result.tinker.spellId), result.tinker.reason or "none"))
        end
    else
        result.tinker = {
            status = "NOT_APPLICABLE",
            reason = "Not a supported profession-effect slot"
        }
    end
    return result
end
