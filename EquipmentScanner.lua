local _, WSGS = ...
local Scanner = {}
WSGS.EquipmentScanner = Scanner
local Prerequisites = WSGS.ModificationMaterials.actions.prerequisites

local function unknown(reason)
    return {
        status = "UNKNOWN",
        reason = reason
    }
end

-- Confirmed event names for consumers; the scanner itself owns no listeners.
Scanner.rescanEvents = {"PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT"}

function Scanner:Scan(onlyPosition)
    local snapshot = {
        capturedAt = time(),
        slots = {},
        context = WSGS.ModificationMaterials:CharacterContext()
    }
    for position = onlyPosition or 1, onlyPosition or 16 do
        local slot = WSGS.equipmentSlots[position]
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
        for _, field in ipairs({"enchant", "gems", "reforging", "upgradeStep", "upgradeEligibility", "upgradeMaximum",
                                "upgradeRemaining", "upgradeState", "tinker", "buckle", "professionSocket",
                                "socketCount", "instance"}) do
            observations[field] = empty and {
                status = "NOT_APPLICABLE",
                reason = "Empty inventory slot"
            } or unknown("No verified equipped-item observation for this field")
        end
        if slot.id ~= Prerequisites.beltBuckle.slot then
            observations.buckle = {
                status = "NOT_APPLICABLE"
            }
        end
        if not Prerequisites.professionSockets[slot.id] then
            observations.professionSocket = {
                status = "NOT_APPLICABLE"
            }
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
            local decoded, reason = WSGS.ItemLinkDecoder:Decode(current.link)
            if decoded and observations.item.status == "KNOWN" and decoded.id == current.id then
                observations.enchant = decoded.enchant
                observations.gems = decoded.gems
                observations.reforging = decoded.reforging
                local socketOK, nativeSockets = pcall(C_Item.GetItemNumSockets, current.link)
                local addedOK, addedSockets = pcall(C_Item.GetItemNumAddedSockets, current.link)
                if socketOK and type(nativeSockets) == "number" and nativeSockets >= 0 and addedOK and
                    type(addedSockets) == "number" and addedSockets >= 0 then
                    observations.socketCount = {
                        status = "KNOWN",
                        value = nativeSockets + addedSockets,
                        native = nativeSockets,
                        added = addedSockets,
                        source = "C_Item.GetItemNumSockets + C_Item.GetItemNumAddedSockets"
                    }
                else
                    observations.socketCount = unknown("Equipped socket count unavailable")
                end
                if Prerequisites.professionSockets[slot.id] then
                    local ok, added = pcall(C_Item.GetItemNumAddedSockets, current.link)
                    if ok and type(added) == "number" and added >= 0 then
                        observations.professionSocket = {
                            status = "KNOWN",
                            value = added > 0,
                            count = added,
                            source = "C_Item.GetItemNumAddedSockets"
                        }
                    else
                        observations.professionSocket = unknown("Added profession socket count unavailable")
                    end
                end
                if slot.id == Prerequisites.beltBuckle.slot then
                    local third = decoded.gems.values[3]
                    if third.status == "KNOWN" and third.value > 0 then
                        observations.buckle = {
                            status = "KNOWN",
                            value = true,
                            source = "Populated third waist gem position"
                        }
                    else
                        -- Empty gem fields do not establish whether an empty socket exists.
                        local ok, added = pcall(function()
                            if not C_Item.GetItemInfo(current.link) then
                                return nil
                            end
                            return C_Item.GetItemNumAddedSockets(current.link)
                        end)
                        if ok and type(added) == "number" and added >= 0 then
                            observations.buckle = {
                                status = "KNOWN",
                                value = added > 0,
                                source = "C_Item.GetItemNumAddedSockets"
                            }
                        else
                            observations.buckle = unknown(
                                "Added waist sockets unavailable; empty gem fields are inconclusive")
                        end
                    end
                end
                for field, observed in pairs(WSGS.EquipmentInspector:Inspect(slot.id, current.link)) do
                    observations[field] = observed
                end
            else
                local problem = reason or "Item link and inventory item identity do not agree"
                for _, field in ipairs({"enchant", "gems", "reforging"}) do
                    observations[field] = unknown(problem)
                end
            end
        end
    end
    return snapshot
end
