local WSGS, document = ...
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local currentLink = "|cffa335ee|Hitem:99002:4430:76699:76699:76699:::90:137:66::::::::|h[Gloves]|h|r"
local tooltipLines, available, tooltipLink = {}, true, currentLink
local spellId = 126734
local tooltip = {}
function tooltip:SetOwner() end
function tooltip:ClearLines() end
function tooltip:Hide() end
function tooltip:SetInventoryItem(unit, slot) assert(unit == "player" and (slot == 10 or slot == 3)); return available end
function tooltip:GetItem() return "Gloves", tooltipLink end
function tooltip:GetRegions()
    local regions = {}
    for _, text in ipairs(tooltipLines) do
        local line = text
        regions[#regions + 1] = { GetObjectType = function() return "FontString" end, GetText = function() return line end }
    end
    return unpack(regions)
end
WSGS.EquipmentInspector.tooltip = tooltip
ITEM_UPGRADE_TOOLTIP_FORMAT = "Upgrade Level: %d/%d" -- Confirmed MoP Classic runtime format.
C_Item.GetItemSpell = function(link)
    assert(link == currentLink)
    if spellId then return "Synthetic spell name", spellId end
end
function GetInventoryItemID(unit, slot) if slot == 10 then return 99002 end end
function GetInventoryItemLink(unit, slot) if slot == 10 then return currentLink end end
local profile = assert(WSGS:ValidateEquipment(document))
local function scanCompare()
    local snapshot = WSGS.EquipmentScanner:Scan(7)
    return snapshot.slots[7].observations, assert(WSGS.EquipmentComparator:Compare(profile, snapshot)).slots[7].fields
end
for _, data in ipairs({ {2, 2, "FULLY_UPGRADED", "MATCH"}, {1, 2, "PARTIALLY_UPGRADED", "MISMATCH"},
    {0, 2, "UNUPGRADED", "MISMATCH"}, {1, 4, "PARTIALLY_UPGRADED", "MISMATCH"}, {4, 4, "FULLY_UPGRADED", "MATCH"} }) do
    tooltipLines = { "Gloves", string.format(ITEM_UPGRADE_TOOLTIP_FORMAT, data[1], data[2]) }
    local observations, differences = scanCompare()
    check(observations.upgradeStep.value == data[1] and observations.upgradeMaximum.value == data[2], "actual tooltip current/maximum")
    check(observations.upgradeRemaining.value == data[2] - data[1] and observations.upgradeState.value == data[3], "remaining and progress classification")
    check(differences.upgradeStep.state == data[4] and differences.upgradeStep.expected == data[2], "maximum policy from observed tooltip")
end
-- Actual shoulder tooltip supplied by live MoP Classic testing.
local gloveLink = currentLink
currentLink = "item:99027:4803:76699:76699:::::90:160:66::::::::"
tooltipLink = currentLink
tooltipLines = { "Shoulderguards of Winged Triumph", "Celestial", "Item Level 536", "Upgrade Level: 2/2" }
local shoulders = WSGS.EquipmentInspector:Inspect(3, currentLink)
check(shoulders.upgradeStep.value == 2 and shoulders.upgradeMaximum.value == 2
    and shoulders.upgradeRemaining.value == 0, "actual shoulder tooltip parses fully upgraded progress")
local shoulderSnapshot = WSGS.EquipmentScanner:Scan()
shoulderSnapshot.slots[3].id = 99027
shoulders.item = { status = "KNOWN", value = 99027 }
shoulderSnapshot.slots[3].observations = shoulders
local shoulderResult = assert(WSGS.EquipmentComparator:Compare(profile, shoulderSnapshot))
check(shoulderResult.slots[3].fields.upgradeStep.state == "MATCH", "actual shoulder maximum upgrade matches")
currentLink, tooltipLink = gloveLink, gloveLink
tooltipLines = { "Upgrade Level: 4/4" }
local observations, differences = scanCompare()
check(observations.enchant.value == 4430 and observations.tinker.value == 4898, "conventional enchant and tinker coexist")
check(differences.enchant.state == "MATCH" and differences.tinker.state == "MATCH", "fixture enchant/tinker compare separately")
check(observations.tinker.source:find("C_Item.GetItemSpell", 1, true), "tinker method recorded")
spellId = 108788
observations, differences = scanCompare()
check(observations.tinker.value == 4697 and differences.tinker.state == "MISMATCH", "Phase Fingers differs from Synapse Springs")
spellId = 109076
check(WSGS.EquipmentInspector:Inspect(10, currentLink).tinker.value == 4698, "Incendiary Fireworks mapping")
spellId = nil
observations, differences = scanCompare()
check(observations.tinker.status == "UNKNOWN" and differences.tinker.state == "UNKNOWN", "missing effect is not fabricated absence")
spellId = 12345
check(WSGS.EquipmentInspector:Inspect(10, currentLink).tinker.status == "UNKNOWN", "unmapped use effect not confused with engineering")
spellId = 126734
for _, lines in ipairs({ {}, { "", "   " }, { "Upgrade Level: 3/2" },
    { "Upgrade Level: 0/0" }, { "Upgrade Level: 1/2", "Upgrade Level: 2/2" } }) do
    tooltipLines = lines
    check(WSGS.EquipmentInspector:Inspect(10, currentLink).upgradeEligibility.status == "UNKNOWN", "empty/malformed/conflicting tooltip stays unknown")
end
tooltipLines = { "|cffff0000Upgrade Level: 1/4|r" }
check(WSGS.EquipmentInspector:Inspect(10, currentLink).upgradeMaximum.value == 4, "color markers do not affect authoritative pattern")
ITEM_UPGRADE_TOOLTIP_FORMAT = "Niveau (total %2$d): %1$d"
tooltipLines = { "Niveau (total 4): 1" }
check(WSGS.EquipmentInspector:Inspect(10, currentLink).upgradeStep.value == 1, "literal localized punctuation and reordered placeholders")
ITEM_UPGRADE_TOOLTIP_FORMAT = nil
check(WSGS.EquipmentInspector:Inspect(10, currentLink).upgradeStep.status == "UNKNOWN", "no English fallback without client format")
ITEM_UPGRADE_TOOLTIP_FORMAT = "Upgrade Level: %d/%d"
tooltipLines = { "Upgrade Level: 2/2" }
available = false
check(WSGS.EquipmentInspector:Inspect(10, currentLink).upgradeStep.status == "UNKNOWN", "uncached tooltip not authoritative")
available = true
tooltipLink = "item:99999:0:::::::90:0"
check(WSGS.EquipmentInspector:Inspect(10, currentLink).upgradeStep.status == "UNKNOWN", "stale tooltip rejected")
tooltipLink = currentLink
local original = profile.equipment[7].id
profile.equipment[7].id = 99999
observations, differences = scanCompare()
check(differences.tinker.state == "UNKNOWN" and differences.upgradeStep.state == "UNKNOWN", "incorrect target item blocks modification matches")
profile.equipment[7].id = original
-- Confirmed missing tinker remains a normalized contract only; a missing
-- use spell cannot distinguish absent and uncached effects.
local snapshot = WSGS.EquipmentScanner:Scan(7)
snapshot.slots[7].observations.upgradeEligibility = { status = "KNOWN", value = false, source = "synthetic contract" }
snapshot.slots[7].observations.tinker = { status = "KNOWN", value = 0, source = "synthetic contract" }
local result = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
check(result.slots[7].fields.upgradeStep.state == "NOT_APPLICABLE", "known nonupgradeable contract")
check(result.slots[7].fields.tinker.state == "MISMATCH", "positively known absent tinker contract")
C_Item.GetItemSpell = function() error("uncached") end
check(WSGS.EquipmentInspector:Inspect(10, currentLink).tinker.status == "UNKNOWN", "item spell errors safe")
-- Exercise command paths with the reusable tooltip lifecycle used by the
-- local CharacterStatsPaneImproved scanner: ownership must be set after Hide.
local originalCreateFrame = CreateFrame
local originalCharacter, originalSettings = WSGS.db.char, WSGS.db.profile
local equipment = {
    [1] = { id = 99029, link = "item:99029:0:95344:76667:::::90:0:66::::::::", lines = { "Head", "Upgrade Level: 1/2" } },
    [3] = { id = 99027, link = "item:99027:4803:76699:76699:::::90:160:66::::::::",
        lines = { "Shoulderguards of Winged Triumph", "Celestial", "Item Level 536", "Upgrade Level: 2/2" } },
}
local reusable = { owned = false }
function reusable:SetOwner() self.owned = true end
function reusable:ClearLines() self.item = nil end
function reusable:Hide() self.owned = false end
function reusable:SetInventoryItem(unit, slot)
    assert(unit == "player")
    if not self.owned then return false end
    self.item = equipment[slot]
    return self.item ~= nil and not self.item.unavailable
end
function reusable:GetItem() return "Equipped item", self.item and self.item.link end
function reusable:GetRegions()
    local regions = {}
    for _, text in ipairs(self.item and self.item.lines or {}) do
        local line = text
        regions[#regions + 1] = { GetObjectType = function() return "FontString" end,
            GetText = function() return line end }
    end
    return unpack(regions)
end
CreateFrame = function(kind) assert(kind == "GameTooltip"); return reusable end
GetInventoryItemID = function(unit, slot) return equipment[slot] and equipment[slot].id end
GetInventoryItemLink = function(unit, slot) return equipment[slot] and equipment[slot].link end
C_Item.GetItemSpell = function() end
WSGS.db.char = { simulationProfiles = { regression = profile }, latestSimulationProfileId = "regression" }
WSGS.db.profile = { debug = true }
profile.name = "Upgrade lifecycle regression"
local function freshTooltip()
    WSGS.EquipmentInspector.tooltip = nil
    reusable.owned, reusable.item = false, nil
end
local function assertUpgrade(result, state, remaining, maximum)
    local difference = result.slots[3].fields.upgradeStep
    check(result.slots[3].fields.item.state == "MATCH", "shoulder item survives complete scan")
    check(difference.state == state, "complete command path upgrade state: " .. state)
    if remaining ~= nil then
        check(difference.remaining == remaining and difference.expected == maximum,
            "complete command path preserves actual maximum and remaining")
    end
end
for _, data in ipairs({ {2, 2, "MATCH", 0}, {1, 2, "MISMATCH", 1},
    {0, 2, "MISMATCH", 2}, {1, 4, "MISMATCH", 3}, {4, 4, "MATCH", 0} }) do
    equipment[3].lines[4] = string.format(ITEM_UPGRADE_TOOLTIP_FORMAT, data[1], data[2])
    freshTooltip()
    -- Compare must work without a prior probe, including earlier equipped slots.
    assertUpgrade(WSGS:CompareLatestEquipment(), data[3], data[4], data[2])
    local single = WSGS.EquipmentScanner:Scan(3).slots[3].observations
    check(single.upgradeStep.status == "KNOWN" and single.upgradeStep.value == data[1]
        and single.upgradeMaximum.value == data[2], "single-slot and complete scan observations agree")
    WSGS:ProbeEquipment(3)
    assertUpgrade(WSGS:CompareLatestEquipment(), data[3], data[4], data[2])
    assertUpgrade(WSGS:CompareLatestEquipment(), data[3], data[4], data[2])
    freshTooltip()
    WSGS:ProbeEquipment(3)
    assertUpgrade(WSGS:CompareLatestEquipment(), data[3], data[4], data[2])
end
equipment[3].lines[4] = nil
freshTooltip()
assertUpgrade(WSGS:CompareLatestEquipment(), "NOT_APPLICABLE")
WSGS:ProbeEquipment(3)
assertUpgrade(WSGS:CompareLatestEquipment(), "NOT_APPLICABLE")
equipment[3].lines = {}
assertUpgrade(WSGS:CompareLatestEquipment(), "UNKNOWN")
equipment[3].lines = { "", "   " }
assertUpgrade(WSGS:CompareLatestEquipment(), "UNKNOWN")
equipment[3].lines[4] = "Upgrade Level: 2/2"
equipment[3].unavailable = true
assertUpgrade(WSGS:CompareLatestEquipment(), "UNKNOWN")
equipment[3].unavailable = nil
equipment[3].id, equipment[3].link = 99999, "item:99999:4803:76699:76699:::::90:160:66::::::::"
local wrong = WSGS:CompareLatestEquipment().slots[3].fields
check(wrong.item.state == "MISMATCH" and wrong.upgradeStep.state == "UNKNOWN"
    and wrong.enchant.state == "UNKNOWN", "wrong equipped item cannot match modifications")
-- Runtime-confirmed non-upgradeable example; all other tooltip lines are
-- synthetic. No item-specific exception exists in production code.
local originalTrinket = profile.equipment[14]
profile.equipment[14] = { id = 95757 }
equipment[14] = { id = 95757, link = "item:95757:0:::::::90:0:66::::::::",
    lines = { "Primordius' Talisman of Rage", "Item Level 502" } }
local function assertTrinket(state)
    local comparison = WSGS:CompareLatestEquipment()
    check(comparison.slots[14].fields.upgradeStep.state == state, "95757 complete comparison: " .. state)
end
freshTooltip()
assertTrinket("NOT_APPLICABLE")
local trinket = WSGS.EquipmentScanner:Scan(14).slots[14].observations
check(trinket.upgradeEligibility.status == "KNOWN" and trinket.upgradeEligibility.value == false
    and trinket.upgradeState.value == "NOT_UPGRADEABLE", "95757 populated tooltip proves ineligibility")
check(trinket.upgradeStep.status == "NOT_APPLICABLE" and trinket.upgradeMaximum.status == "NOT_APPLICABLE"
    and trinket.upgradeRemaining.status == "NOT_APPLICABLE", "nonupgradeable progress is not fabricated zero")
WSGS:ProbeEquipment(14)
assertTrinket("NOT_APPLICABLE")
assertTrinket("NOT_APPLICABLE")
equipment[14].lines = {}
assertTrinket("UNKNOWN")
equipment[14].lines = { "Primordius' Talisman of Rage" }
equipment[14].unavailable = true
assertTrinket("UNKNOWN")
equipment[14].unavailable = nil
local setInventory = reusable.SetInventoryItem
reusable.SetInventoryItem = function() error("tooltip unavailable") end
assertTrinket("UNKNOWN")
reusable.SetInventoryItem = setInventory
profile.equipment[14] = { id = 99999 }
assertTrinket("UNKNOWN")
profile.equipment[14] = originalTrinket
CreateFrame = originalCreateFrame
WSGS.db.char, WSGS.db.profile = originalCharacter, originalSettings
WSGS.EquipmentInspector.tooltip = nil
return checks
