-- Comparator fixtures describe the scanner contract, not unverified client APIs.
local WSGS = ...
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function known(value)
    return { status = "KNOWN", value = value, present = value ~= nil, source = "synthetic observation" }
end
local function setup()
    local profile = { id = "test", name = "Test build", equipment = {} }
    local snapshot = { slots = {} }
    for position, slot in ipairs(WSGS.equipmentSlots) do
        profile.equipment[position] = { id = 1000 + position }
        snapshot.slots[position] = { id = 1000 + position, observations = { item = known(1000 + position) } }
    end
    return profile, snapshot
end
local function compare(profile, snapshot)
    return assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
end
local profile, snapshot = setup()
local result = compare(profile, snapshot)
check(result.summary.matched == 16, "all sixteen exact items")
for index = 1, 16 do check(result.slots[index].currentSlotId == WSGS.equipmentSlots[index].id, "slot mapping") end
snapshot.slots[1].observations.item = known(999)
profile.equipment[1].enchant = 10
snapshot.slots[1].observations.enchant = known(10)
result = compare(profile, snapshot)
check(result.slots[1].fields.item.state == "MISMATCH", "wrong item")
check(result.slots[1].fields.enchant.state == "UNKNOWN", "wrong item modifications never match")
profile, snapshot = setup()
profile.equipment[1] = { empty = true }
check(compare(profile, snapshot).slots[1].fields.item.state == "MISMATCH", "empty target versus equipped")
snapshot.slots[1].observations.item = known(nil)
check(compare(profile, snapshot).slots[1].fields.item.state == "MATCH", "both empty")
profile.equipment[1] = { id = 1001 }
check(compare(profile, snapshot).slots[1].fields.item.state == "MISMATCH", "empty current versus target")
profile, snapshot = setup()
profile.equipment[1].gems = { 20, 21 }
snapshot.slots[1].observations.gems = { values = { known(20), known(21) } }
check(compare(profile, snapshot).slots[1].fields.gems.state == "MATCH", "multiple gems")
snapshot.slots[1].observations.gems.values[2] = known(0)
check(compare(profile, snapshot).slots[1].fields.gems.state == "MISMATCH", "positively observed missing gem")
snapshot.slots[1].observations.gems.values[2] = { status = "UNKNOWN" }
check(compare(profile, snapshot).slots[1].fields.gems.state == "UNKNOWN", "unknown gems")
snapshot.slots[1].observations.gems.values[1] = known(22)
result = compare(profile, snapshot)
check(result.slots[1].fields.gems.state == "MISMATCH" and result.summary.unknown == 1, "known gem difference and unknown socket both retained")
for _, field in ipairs({ "enchant", "reforging", "upgradeStep", "tinker" }) do
    profile, snapshot = setup()
    profile.equipment[1][field] = 2
    snapshot.slots[1].observations[field] = known(2)
    check(compare(profile, snapshot).slots[1].fields[field].state == "MATCH", field .. " matches")
    snapshot.slots[1].observations[field] = known(3)
    check(compare(profile, snapshot).slots[1].fields[field].state == "MISMATCH", field .. " differs")
    snapshot.slots[1].observations[field] = { status = "UNKNOWN" }
    check(compare(profile, snapshot).slots[1].fields[field].state == "UNKNOWN", field .. " unknown")
    profile.equipment[1][field] = nil
    check(compare(profile, snapshot).slots[1].fields[field].state == "NOT_APPLICABLE", field .. " omitted")
end
profile, snapshot = setup()
profile.equipment[1].upgradeStep = "UpgradeStepTwo"
snapshot.slots[1].observations.upgradeStep = known(2)
check(compare(profile, snapshot).slots[1].fields.upgradeStep.state == "MATCH", "schema upgrade enum normalized")
profile.equipment[1].tinker = "UnmappedTinker"
snapshot.slots[1].observations.tinker = known(4898)
check(compare(profile, snapshot).slots[1].fields.tinker.state == "UNKNOWN", "unmapped representation unknown")
for _, pair in ipairs({ {11, 12}, {13, 14} }) do
    profile, snapshot = setup()
    local a, b = pair[1], pair[2]
    snapshot.slots[a], snapshot.slots[b] = snapshot.slots[b], snapshot.slots[a]
    result = compare(profile, snapshot)
    check(result.summary.matched == 16 and result.assignments[a] == b and result.assignments[b] == a, "swapped pair")
end
profile, snapshot = setup()
profile.equipment[11].id, profile.equipment[12].id = 900, 900
profile.equipment[11].enchant, profile.equipment[12].enchant = 1, 2
snapshot.slots[11].observations = { item = known(900), enchant = known(2) }
snapshot.slots[12].observations = { item = known(900), enchant = known(1) }
result = compare(profile, snapshot)
check(result.assignments[11] == 12 and result.assignments[12] == 11 and result.summary.configurationMismatches == 0, "identical rings scored by modifications")
snapshot.slots[12].observations.item = known(901)
result = compare(profile, snapshot)
check(result.summary.itemMismatches == 1 and result.assignments[11] ~= result.assignments[12], "duplicate target IDs cannot reuse instance")
profile, snapshot = setup()
snapshot.slots[1] = nil
check(compare(profile, snapshot).slots[1].fields.item.state == "UNKNOWN", "incomplete snapshot")
local value, reason = WSGS.EquipmentComparator:Compare(nil, snapshot)
check(not value and reason, "missing profile")

-- Scanner APIs are mocked only to their locally documented signatures.
local idCalls, linkCalls, gemCalls = {}, {}, 0
function GetInventoryItemID(unit, slot)
    idCalls[slot] = (idCalls[slot] or 0) + 1
    if slot == 2 then return nil end
    if slot == 3 then error("item not readable") end
    return 2000 + slot
end
function GetInventoryItemLink(unit, slot)
    linkCalls[slot] = (linkCalls[slot] or 0) + 1
    if slot == 2 or slot == 5 then return nil end
    return "|cffffffff|Hitem:" .. (2000 + slot) .. ":0|h[Test]|h|r"
end
C_Item = {}
ItemLocation = { CreateFromEquipmentSlot = function(self, slot) return { slot = slot } end }
function C_Item.GetItemGUID(location) return "SyntheticGUID-" .. location.slot end
function C_Item.GetItemGem(link, index)
    gemCalls = gemCalls + 1
    if index == 1 then return "Test Gem", "|cffffffff|Hitem:95344:0|h[Gem]|h|r" end
    return nil -- No assumption about why this result is nil.
end
local scanned = WSGS.EquipmentScanner:Scan()
check(#scanned.slots == 16, "scanner sixteen positions")
for index, slot in ipairs(WSGS.equipmentSlots) do
    check(scanned.slots[index].position == index and scanned.slots[index].slotId == slot.id, "scanner explicit mapping")
    check(idCalls[slot.id] == 1 and linkCalls[slot.id] == 1, "one identity and link read per slot")
end
check(scanned.slots[2].observations.item.present == false, "known empty inventory slot")
check(scanned.slots[2].observations.gems.status == "NOT_APPLICABLE", "empty slot modifications not applicable")
check(scanned.slots[3].observations.item.status == "UNKNOWN", "read failure does not become empty")
check(scanned.slots[5].id == 2005 and scanned.slots[5].observations.link.status == "UNKNOWN", "uncached link preserves known ID")
check(scanned.slots[1].observations.gems.values[1].value == 95344, "positive gem link observed")
check(scanned.slots[1].observations.gems.values[2].status == "UNKNOWN", "nil gem never assumed zero")
for _, field in ipairs({ "enchant", "reforging", "upgradeStep", "tinker" }) do
    check(scanned.slots[1].observations[field].status == "UNKNOWN", "unverified modification stays unknown")
end
check(gemCalls == 42, "gem queries bounded and skipped without link")
C_Item.GetItemGem = function() error("uncached") end
C_Item.GetItemGUID = function() error("unavailable identity") end
scanned = WSGS.EquipmentScanner:Scan()
check(scanned.slots[1].observations.gems.values[1].status == "UNKNOWN" and scanned.slots[1].observations.instance.status == "UNKNOWN", "uncached gem/identity errors handled")
-- Compare summary is concise by default; detailed slots are debug-only.
WSGS.db.char.simulationProfiles = {}
WSGS.db.char.latestSimulationProfileId = nil
chat = {}
SlashCmdList.ACECONSOLE_WSGS("compare")
check(#chat == 1 and chat[1]:find("Import a WoW Sims build"), "no build diagnostic")
local decoded = { apiVersion = 3, player = { class = "ClassPaladin", equipment = { items = {} } } }
for index = 1, 16 do decoded.player.equipment.items[index] = { id = 2000 + WSGS.equipmentSlots[index].id } end
local imported = assert(WSGS:ValidateEquipment(decoded))
imported.id, imported.name = "diagnostic", "Diagnostic build"
WSGS.db.char.simulationProfiles.diagnostic = imported
WSGS.db.char.latestSimulationProfileId = "diagnostic"
WSGS.db.profile.debug = false
chat = {}
SlashCmdList.ACECONSOLE_WSGS("compare")
check(#chat == 5, "only summary by default")
WSGS.db.profile.debug = true
chat = {}
SlashCmdList.ACECONSOLE_WSGS("compare")
check(#chat == 117, "debug emits sixteen slot detail blocks")
-- Focused probes read only the requested physical slot.
local before = {}
for slot, count in pairs(idCalls) do before[slot] = count end
WSGS:ProbeEquipment(7)
for slot, count in pairs(idCalls) do
    check(count == before[slot] + (slot == 10 and 1 or 0), "probe scans only gloves")
end
profile, snapshot = setup()
result = compare(profile, snapshot)
check(result.assignments[11] == 11 and result.assignments[13] == 13, "equal scores keep physical assignment")
-- Successful imports choose the latest build; failures leave that choice intact.
local latest = assert(WSGS:ImportEquipment('{"apiVersion":3,"player":{"class":"ClassPaladin","equipment":{"items":[]}}}', "Latest"))
check(WSGS.db.char.latestSimulationProfileId == latest.id, "new import is latest")
WSGS:ImportEquipment("{", "Invalid")
check(WSGS.db.char.latestSimulationProfileId == latest.id, "failed import does not change latest")
return checks
