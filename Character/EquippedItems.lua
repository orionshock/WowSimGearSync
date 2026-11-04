local _, WSGS = ...
local Modules = WSGS.Private
local Scanner = {}
Modules.Character.EquippedItems = Scanner

local function unknown(reason)
    return {
        status = "UNKNOWN",
        reason = reason
    }
end

function Scanner:Scan(onlyPosition)
    local snapshot = {
        capturedAt = time(),
        slots = {},
        context = Modules.Character.Professions:CharacterContext()
    }
    for position = onlyPosition or 1, onlyPosition or #WSGS.Equipment.Slots do
        local slot = WSGS.Equipment.Slots[position]
        local current = {
            position = position,
            slotId = slot.id,
            slotName = slot.name,
            observations = {}
        }
        snapshot.slots[position] = current
        local observations = current.observations
        local idOK, id = pcall(GetInventoryItemID, "player", slot.id)
        local linkOK, link = pcall(GetInventoryItemLink, "player", slot.id)
        if linkOK and type(link) == "string" then
            current.link = link
        end
        observations.link = current.link and {
            status = "KNOWN",
            value = current.link,
            source = "GetInventoryItemLink"
        } or unknown("Equipped link unavailable")
        if idOK and type(id) == "number" and id > 0 then
            current.id = id
            observations.item = {
                status = "KNOWN",
                value = id,
                present = true,
                source = "GetInventoryItemID"
            }
        elseif idOK and id == nil and linkOK and link == nil then
            observations.item = {
                status = "KNOWN",
                present = false,
                source = "GetInventoryItemID/GetInventoryItemLink"
            }
        else
            observations.item = unknown("Inventory identity unavailable or inconsistent")
        end
        local empty = observations.item.status == "KNOWN" and observations.item.present == false
        for _, field in ipairs({"enchant", "useSpell", "instance"}) do
            observations[field] = empty and {
                status = "NOT_APPLICABLE",
                reason = "Empty inventory slot"
            } or unknown("No verified equipped-item observation for this field")
        end
        if not empty then
            local ok, guid = pcall(function()
                return C_Item.GetItemGUID(ItemLocation:CreateFromEquipmentSlot(slot.id))
            end)
            if ok and type(guid) == "string" and guid ~= "" then
                observations.instance = {
                    status = "KNOWN",
                    value = guid,
                    source = "C_Item.GetItemGUID"
                }
            end
            observations.enchant = Modules.Character.Enchantment:Observe(current.link)
            for field, observed in pairs(Modules.Character.ProfessionEffects:Inspect(slot.id, current.link)) do
                observations[field] = observed
            end
        end
    end
    snapshot.context.titansGrip = C_SpellBook.IsSpellKnown(46917)
    for position, current in ipairs(snapshot.slots) do
        current.guid = current.observations.instance.status == "KNOWN" and current.observations.instance.value or nil
        current.equipLoc = current.id and select(4, C_Item.GetItemInfoInstant(current.link or current.id))
        current.locked = IsInventoryItemLocked(WSGS.Equipment.Slots[position].id)
    end
    return snapshot
end
