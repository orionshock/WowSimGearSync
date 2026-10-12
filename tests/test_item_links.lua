local WSGS, document = ...
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local cloak = "item:102250:4424:76667::::::90:131:66::::::::"
local shoulders = "item:99027:4803:76699:76699:::::90:160:66::::::::"
local decoder = WSGS.ItemLinkDecoder
local decoded = assert(decoder:Decode(cloak))
check(decoded.id == 102250 and decoded.enchant.value == 4424, "live cloak ID/enchant")
check(decoded.gems.values[1].value == 76667 and decoded.gems.values[2].value == 0, "live cloak gem/empty position")
check(decoded.reforging.value == 131 and decoded.playerLevel.value == 90, "live cloak reforge/level")
check(decoded.specialization == nil and decoded.upgradeStep == nil and decoded.tinker == nil, "field eleven not interpreted")
decoded = assert(decoder:Decode(shoulders))
check(decoded.id == 99027 and decoded.enchant.value == 4803, "live shoulders ID/enchant")
check(decoded.gems.values[1].value == 76699 and decoded.gems.values[2].value == 76699, "live shoulders repeated gems")
check(decoded.gems.values[3].value == 0 and decoded.gems.values[4].value == 0 and decoded.reforging.value == 160, "live shoulders empty positions retain reforge offset")
local full = "|cffa335ee|H" .. shoulders .. "|h[Shoulders]|h|r"
check(assert(decoder:Decode(full)).reforging.value == 160, "full colored item link")
check(assert(decoder:Decode("|H" .. cloak .. "|h[Cloak]|h")).id == 102250, "uncolored item link")
local absent = assert(decoder:Decode("item:123::::::::90:0"))
check(absent.enchant.status == "KNOWN" and absent.enchant.value == 0 and absent.enchant.absent, "unenchanted link has known absence")
check(absent.gems.values[4].status == "KNOWN" and absent.gems.values[4].value == 0, "fourth gem field retained")
for _, link in ipairs({ "", "garbage", "item:123", "item:123:", "item:abc::::::::90:0",
    "item:123:abc:::::::90:0", "item:123:0:abc::::::90:0", "item:123::::::::90:abc",
    "|Hitem:123:0|h[Broken]", "item:123:0:-1::::::90:0" }) do
    local value, reason = decoder:Decode(link)
    check(not value and reason, "malformed or insufficient links rejected")
end
check(decoder:Decode(nil) == nil, "missing link rejected")
local links = { [3] = full, [15] = "|cffa335ee|H" .. cloak .. "|h[Cloak]|h|r" }
function GetInventoryItemID(unit, slot)
    if slot == 3 then return 99027 elseif slot == 15 then return 102250 end
end
function GetInventoryItemLink(unit, slot) return links[slot] end
local snapshot = WSGS.EquipmentScanner:Scan()
local profile = assert(WSGS:ValidateEquipment(document))
local result = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
check(result.slots[4].fields.gems.state == "MISMATCH", "actual cloak gem mismatch")
check(result.slots[4].fields.gems.sockets[1].expected == 76699 and result.slots[4].fields.gems.sockets[1].actual == 76667, "cloak gem difference retained")
check(result.slots[3].fields.reforging.state == "MISMATCH", "actual shoulders reforge mismatch")
check(result.slots[3].fields.reforging.expected == 167 and result.slots[3].fields.reforging.actual == 160, "shoulder reforge values retained")
check(result.slots[4].fields.reforging.state == "MATCH" and result.slots[3].fields.enchant.state == "MATCH", "confirmed matching modifications")
check(result.slots[3].fields.upgradeStep.state == "UNKNOWN" and snapshot.slots[3].observations.tinker.status == "UNKNOWN", "upgrade and tinker not guessed from field eleven")
profile.equipment[3].reforging = nil
profile.equipment[3].enchant = nil
profile.equipment[3].upgradeStep = nil
result = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
check(result.slots[3].fields.reforging.state == "NOT_APPLICABLE" and result.slots[3].fields.enchant.state == "NOT_APPLICABLE", "omitted properties do not imply removal")
check(result.slots[3].fields.upgradeStep.state == "UNKNOWN" and result.slots[3].fields.upgradeStep.policy == "MAXIMUM", "upgrade policy without exported upgradeStep")
local observations = snapshot.slots[3].observations
observations.upgradeEligibility = { status = "KNOWN", value = false }
check(WSGS.EquipmentComparator:Compare(profile, snapshot).slots[3].fields.upgradeStep.state == "NOT_APPLICABLE", "nonupgradeable equipment excluded")
observations.upgradeEligibility = { status = "KNOWN", value = true }
check(WSGS.EquipmentComparator:Compare(profile, snapshot).slots[3].fields.upgradeStep.state == "UNKNOWN", "eligible item with unknown maximum remains unknown")
observations.upgradeMaximum = { status = "KNOWN", value = 2 }
observations.upgradeStep = { status = "KNOWN", value = 1 }
result = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
check(result.slots[3].fields.upgradeStep.state == "MISMATCH" and result.slots[3].fields.upgradeStep.expected == 2, "normal maximum two policy")
observations.upgradeMaximum.value = 4
observations.upgradeStep.value = 2
check(WSGS.EquipmentComparator:Compare(profile, snapshot).slots[3].fields.upgradeStep.expected == 4, "observed maximum overrides normal two hint")
observations.upgradeStep.value = 4
check(WSGS.EquipmentComparator:Compare(profile, snapshot).slots[3].fields.upgradeStep.state == "MATCH", "observed maximum reached")
local fourGems = assert(decoder:Decode("item:123:0:10::12:13:::90:0"))
check(fourGems.gems.values[2].value == 0 and fourGems.gems.values[3].value == 12 and fourGems.gems.values[4].value == 13, "interior empty gem does not shift later positions")
profile.equipment[3].gems = { 76699, 76699, 0, 13 }
result = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
check(result.slots[3].fields.gems.sockets[3].state == "MATCH" and result.slots[3].fields.gems.sockets[4].state == "MISMATCH", "all four explicitly specified gem positions compared")
profile.equipment[3].gems = { 76699 }
check(WSGS.EquipmentComparator:Compare(profile, snapshot).slots[3].fields.gems.state == "MATCH", "unspecified later gems do not imply removal")
profile.equipment[3].enchant = 0
check(WSGS.EquipmentComparator:Compare(profile, snapshot).slots[3].fields.enchant.state == "MISMATCH", "explicit absent enchant versus observed enchant")
-- Malformed, missing, and inconsistent links never imply removal.
for _, link in ipairs({ "broken", "item:99027:4803", cloak }) do
    links[3] = link
    local scanned = WSGS.EquipmentScanner:Scan(3)
    check(scanned.slots[3].observations.enchant.status == "UNKNOWN" and scanned.slots[3].observations.reforging.status == "UNKNOWN" and scanned.slots[3].observations.gems.status == "UNKNOWN", "unreadable/mismatched link modifications unknown")
end
links[3] = nil
check(WSGS.EquipmentScanner:Scan(3).slots[3].observations.enchant.status == "UNKNOWN", "missing link enchant unknown")
return checks
