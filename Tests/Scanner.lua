local _, WSGS = ...
local Tests = WSGS.Tests

Tests:Register("scanner", "Scanner", {
    { name = "16 equipment positions", run = function()
        local expected = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
        assert(#WSGS.equipmentSlots == 16)
        for position, id in ipairs(expected) do assert(WSGS.equipmentSlots[position].id == id, "Slot mapping differs") end
    end },
    { name = "Equipment snapshot created", run = function()
        local snapshot = WSGS.EquipmentScanner:Scan()
        assert(#snapshot.slots == 16)
        for position, slot in ipairs(snapshot.slots) do
            assert(slot.position == position and slot.slotId == WSGS.equipmentSlots[position].id)
            assert(slot.observations.item and slot.observations.upgradeEligibility)
            local id = GetInventoryItemID("player", slot.slotId)
            if id then assert(slot.id == id, "Snapshot item differs from equipped item") end
        end
    end },
    { name = "Repeated full and probe scans agree", run = function()
        local first, second = WSGS.EquipmentScanner:Scan(), WSGS.EquipmentScanner:Scan()
        local checked = 0
        for position, slot in ipairs(first.slots) do
            if slot.id then
                local single = WSGS.EquipmentScanner:Scan(position).slots[position]
                for _, field in ipairs({ "upgradeEligibility", "upgradeStep", "upgradeMaximum", "upgradeRemaining", "tinker", "buckle" }) do
                    local a, b, c = slot.observations[field], second.slots[position].observations[field], single.observations[field]
                    if a.status ~= "UNKNOWN" and b.status ~= "UNKNOWN" and c.status ~= "UNKNOWN" then
                        assert(a.status == b.status and a.status == c.status and a.value == b.value and a.value == c.value,
                            "Repeated observation differs at " .. position .. ": " .. field)
                        checked = checked + 1
                    end
                end
            end
        end
        if checked == 0 then return "SKIP", "No readable equipped modification observations" end
    end },
    { name = "Live upgrades reach comparator", run = function()
        local snapshot, profile = WSGS.EquipmentScanner:Scan(), { equipment = {} }
        for position, slot in ipairs(snapshot.slots) do profile.equipment[position] = { id = slot.id, empty = not slot.id } end
        local result = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
        local checked = 0
        for position, slot in ipairs(snapshot.slots) do
            local o, difference = slot.observations, result.slots[position].fields.upgradeStep
            if slot.id and o.upgradeEligibility.status == "KNOWN" then
                if o.upgradeEligibility.value == false then
                    assert(difference.state == "NOT_APPLICABLE")
                    checked = checked + 1
                elseif o.upgradeStep.status == "KNOWN" and o.upgradeMaximum.status == "KNOWN" then
                    local remaining = o.upgradeMaximum.value - o.upgradeStep.value
                    assert(difference.state == (remaining == 0 and "MATCH" or "MISMATCH"))
                    assert(difference.remaining == remaining)
                    checked = checked + 1
                end
            end
        end
        if checked == 0 then return "SKIP", "Upgrade tooltips unavailable" end
    end },
    { name = "95757 is not upgradeable when equipped", run = function()
        local snapshot = WSGS.EquipmentScanner:Scan()
        for _, slot in ipairs(snapshot.slots) do
            if slot.id == 95757 then
                local eligibility = slot.observations.upgradeEligibility
                if eligibility.status == "UNKNOWN" then return "SKIP", "Item tooltip unreadable" end
                assert(eligibility.status == "KNOWN" and eligibility.value == false)
                return
            end
        end
        return "SKIP", "Item 95757 not equipped"
    end },
    { name = "Glove tinker independent of enchant", run = function()
        local slot = WSGS.EquipmentScanner:Scan(7).slots[7]
        if not slot.id or slot.observations.tinker.status ~= "KNOWN" then return "SKIP", "No recognized glove tinker" end
        assert(slot.observations.tinker.spellId and slot.observations.enchant.status == "KNOWN")
        local _, spell = C_Item.GetItemSpell(slot.link)
        assert(slot.observations.tinker.spellId == spell)
    end },
    { name = "Live waist buckle evidence reaches comparator", run = function()
        local snapshot = WSGS.EquipmentScanner:Scan()
        for position, slot in ipairs(snapshot.slots) do
            if position ~= 8 then assert(slot.observations.buckle.status == "NOT_APPLICABLE") end
        end
        local waist = snapshot.slots[8]
        if not waist.id then return "SKIP", "No equipped waist item" end
        local observed = waist.observations.buckle
        if observed.status == "UNKNOWN" then return "SKIP", observed.reason end
        assert(observed.status == "KNOWN" and type(observed.value) == "boolean")
        local decoded = assert(WSGS.ItemLinkDecoder:Decode(waist.link))
        if decoded.gems.values[3].value > 0 then
            assert(observed.value == true)
        else
            local added = C_Item.GetItemNumAddedSockets(waist.link)
            assert(observed.value == (added > 0))
        end
        local profile = { equipment = {} }
        for position, slot in ipairs(snapshot.slots) do profile.equipment[position] = { id = slot.id, empty = not slot.id } end
        profile.equipment[8].gems = { 10, 20, 30 } -- ephemeral target; never imported/saved
        local result = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
        assert(result.slots[8].fields.buckle.state == (observed.value and "MATCH" or "MISMATCH"))
    end },
})
