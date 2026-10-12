local _, WSGS = ...
-- Pure planner/state inputs. Never call Click or EquipmentExecution from tests.
local function item(id, key, location, enchant)
    return { id = id, key = key, guid = key, fingerprint = key, equipLoc = location,
        observations = { item = { status = "KNOWN", value = id, present = id ~= nil },
            enchant = { status = "KNOWN", value = enchant or 0 },
            upgradeEligibility = { status = "KNOWN", value = false } } }
end
local function scenario()
    local build = { equipment = {} }
    local snapshot = { slots = {}, context = { engineering = false, titansGrip = false } }
    local bags = { items = {}, free = {}, unreadable = 0 }
    for position = 1, 16 do
        build.equipment[position] = { id = 1000 + position }
        snapshot.slots[position] = item(1000 + position, "equipped:" .. position)
        snapshot.slots[position].position = position
    end
    snapshot.slots[15].equipLoc = "INVTYPE_WEAPONMAINHAND"
    snapshot.slots[16].equipLoc = "INVTYPE_SHIELD"
    return build, snapshot, bags
end
local function bag(bags, id, location, enchant)
    local candidate = item(id, "bag:" .. (#bags.items + 1), location, enchant)
    candidate.bag, candidate.bagSlot = 0, #bags.items + 1
    bags.items[#bags.items + 1] = candidate
    return candidate
end
local function replace(snapshot, position, id, location)
    snapshot.slots[position] = item(id, "replacement:" .. position, location)
    snapshot.slots[position].position = position
end
local function plan(build, snapshot, bags) return WSGS.EquipmentPlanner:Plan(build, snapshot, bags) end
local function pendingScenario()
    local build, snapshot, bags = scenario()
    replace(snapshot, 7, nil)
    local candidate = bag(bags, 1007, "INVTYPE_HAND")
    local operation = assert(plan(build, snapshot, bags).operations[1])
    local actions = WSGS.EquipmentActions:New()
    actions:Begin(operation, snapshot, 10)
    return build, snapshot, bags, candidate, actions
end
local function equipped(snapshot, bags, candidate)
    snapshot.slots[7] = candidate
    candidate.position, candidate.bag, candidate.bagSlot = 7, nil, nil
    bags.items = {}
end
WSGS.Tests:Register("equip", "Equipment planning and verification", {
    { name = "Matching gear stays equipped", run = function()
        local b, s, bags = scenario()
        local p = plan(b, s, bags)
        assert(#p.operations == 0 and #p.missing == 0 and #p.blocked == 0)
    end },
    { name = "Exact bag instance fills missing equipment", run = function()
        local b, s, bags = scenario()
        replace(s, 7, nil)
        local candidate = bag(bags, 1007, "INVTYPE_HAND")
        local p = plan(b, s, bags)
        assert(#p.operations == 1 and p.operations[1].source == candidate and p.operations[1].slotId == 10)
    end },
    { name = "Unavailable target is missing, never substituted", run = function()
        local b, s, bags = scenario()
        replace(s, 7, 999)
        bag(bags, 888, "INVTYPE_HAND")
        local p = plan(b, s, bags)
        assert(#p.operations == 0 and #p.missing == 1 and p.missing[1].id == 1007)
    end },
    { name = "One physical copy cannot satisfy two targets", run = function()
        local b, s, bags = scenario()
        b.equipment[11], b.equipment[12] = { id = 99 }, { id = 99 }
        bag(bags, 99, "INVTYPE_FINGER")
        local p = plan(b, s, bags)
        assert(#p.operations == 1 and #p.missing == 1)
    end },
    { name = "Duplicate copies use best distinct modification assignments", run = function()
        local b, s, bags = scenario()
        b.equipment[11], b.equipment[12] = { id = 99, enchant = 10 }, { id = 99, enchant = 20 }
        local second = bag(bags, 99, "INVTYPE_FINGER", 20)
        local first = bag(bags, 99, "INVTYPE_FINGER", 10)
        local p = plan(b, s, bags)
        assert(#p.operations == 2 and p.operations[1].source == first and p.operations[2].source == second)
    end },
    { name = "Unidentifiable identical copies are blocked", run = function()
        local b, s, bags = scenario()
        replace(s, 7, nil)
        local a, other = bag(bags, 1007, "INVTYPE_HAND"), bag(bags, 1007, "INVTYPE_HAND")
        a.guid, other.guid, a.fingerprint, other.fingerprint = nil, nil, "same", "same"
        local p = plan(b, s, bags)
        assert(#p.operations == 0 and #p.blocked > 0)
    end },
    { name = "Correctly equipped copy wins over better bag modifications", run = function()
        local b, s, bags = scenario()
        b.equipment[7].enchant = 10
        bag(bags, 1007, "INVTYPE_HAND", 10)
        assert(#plan(b, s, bags).operations == 0)
    end },
    { name = "Swapped rings and trinkets need no operations", run = function()
        local b, s, bags = scenario()
        s.slots[11], s.slots[12] = s.slots[12], s.slots[11]
        s.slots[13], s.slots[14] = s.slots[14], s.slots[13]
        local p = plan(b, s, bags)
        assert(#p.operations == 0 and p.assignments[11] == 12 and p.assignments[13] == 14)
    end },
    { name = "Locked and unreadable candidates never become actions", run = function()
        local b, s, bags = scenario()
        replace(s, 7, nil)
        local candidate = bag(bags, 1007, "INVTYPE_HAND")
        candidate.locked = true
        assert(#plan(b, s, bags).operations == 0)
        candidate.locked, candidate.fingerprint = false, nil
        assert(#plan(b, s, bags).operations == 0)
        candidate.fingerprint = candidate.key
        replace(s, 16, nil)
        bag(bags, 1016, "INVTYPE_SHIELD")
        s.slots[15].equipLoc = nil
        for _, operation in ipairs(plan(b, s, bags).operations) do
            assert(operation.position ~= 16, "Unreadable main-hand layout must block off-hand work")
        end
    end },
    { name = "Two-handed main hand clears off hand into general bag space first", run = function()
        local b, s, bags = scenario()
        b.equipment[15], b.equipment[16] = { id = 99 }, { empty = true }
        bag(bags, 99, "INVTYPE_2HWEAPON")
        bags.free[1] = { bag = 0, bagSlot = 9 }
        local p = plan(b, s, bags)
        assert(#p.operations == 1 and p.operations[1].kind == "UNEQUIP" and p.operations[1].slotId == 17)
        replace(s, 16, nil)
        p = plan(b, s, bags)
        assert(#p.operations == 1 and p.operations[1].position == 15)
    end },
    { name = "Missing two-handed target does not strip off hand", run = function()
        local b, s, bags = scenario()
        b.equipment[15], b.equipment[16] = { id = 99 }, { empty = true }
        bags.free[1] = { bag = 0, bagSlot = 9 }
        assert(#plan(b, s, bags).operations == 0)
    end },
    { name = "Weapon conflicts and full bags block unsafe operations", run = function()
        local b, s, bags = scenario()
        b.equipment[15] = { id = 99 }
        bag(bags, 99, "INVTYPE_2HWEAPON")
        local p = plan(b, s, bags)
        assert(#p.operations == 0 and #p.blocked > 0)
        b.equipment[16] = { empty = true }
        p = plan(b, s, bags)
        assert(#p.operations == 0 and #p.blocked > 0)
    end },
    { name = "Off hand waits for replacement of two-handed main hand", run = function()
        local b, s, bags = scenario()
        replace(s, 15, 99, "INVTYPE_2HWEAPON")
        replace(s, 16, nil)
        bag(bags, 1015, "INVTYPE_WEAPONMAINHAND")
        bag(bags, 1016, "INVTYPE_SHIELD")
        local p = plan(b, s, bags)
        assert(#p.operations == 1 and p.operations[1].position == 15)
        replace(s, 15, 1015, "INVTYPE_WEAPONMAINHAND")
        p = plan(b, s, bags)
        assert(#p.operations == 1 and p.operations[1].position == 16)
    end },
    { name = "Known Titans Grip permits a two-handed pair", run = function()
        local b, s, bags = scenario()
        b.equipment[15], b.equipment[16] = { id = 99 }, { id = 98 }
        bag(bags, 99, "INVTYPE_2HWEAPON")
        bag(bags, 98, "INVTYPE_2HWEAPON")
        s.context.titansGrip = true
        assert(#plan(b, s, bags).operations == 2)
    end },
    { name = "Submission alone never advances pending work", run = function()
        local b, s, bags, candidate, a = pendingScenario()
        equipped(s, bags, candidate)
        assert(a:Reconcile(b, s, bags, false, 11, "DEBOUNCE") == nil and a.state == "PENDING")
    end },
    { name = "Equipment event verifies intended GUID and completes", run = function()
        local b, s, bags, candidate, a = pendingScenario()
        equipped(s, bags, candidate)
        assert(a:Reconcile(b, s, bags, false, 11, "PLAYER_EQUIPMENT_CHANGED") == "VERIFIED")
        assert(not a.pending and a.state == "COMPLETE")
    end },
    { name = "Bag event re-arms only after verified equipment", run = function()
        local b, s, bags, candidate, a = pendingScenario()
        replace(s, 6, nil)
        bag(bags, 1006, "INVTYPE_WRIST")
        local remaining = bags.items[2]
        equipped(s, bags, candidate)
        bags.items[1] = remaining
        assert(a:Reconcile(b, s, bags, false, 11, "BAG_UPDATE_DELAYED") == "VERIFIED")
        assert(a.state == "NEXT" and #a.plan.operations == 1)
    end },
    { name = "Different instance with same ID is not verified", run = function()
        local b, s, bags, _, a = pendingScenario()
        s.slots[7] = item(1007, "wrong-guid", "INVTYPE_HAND")
        assert(a:Reconcile(b, s, bags, false, 11, "PLAYER_EQUIPMENT_CHANGED") == "FAILED")
        assert(a.state == "FAULT")
    end },
    { name = "Unexpected equipment change stops the operation", run = function()
        local b, s, bags, _, a = pendingScenario()
        replace(s, 7, 999)
        assert(a:Reconcile(b, s, bags, false, 11, "PLAYER_EQUIPMENT_CHANGED") == "FAILED")
    end },
    { name = "Timeout requires rescan instead of automatic retry", run = function()
        local b, s, bags, _, a = pendingScenario()
        assert(a:Reconcile(b, s, bags, false, 15, "DEADLINE") == "FAILED")
        assert(a.state == "FAULT" and not a.pending and #a.plan.operations == 1)
    end },
    { name = "Combat blocks actionable plans", run = function()
        local b, s, bags = scenario()
        replace(s, 7, nil)
        bag(bags, 1007, "INVTYPE_HAND")
        local a = WSGS.EquipmentActions:New()
        a:Reconcile(b, s, bags, true, 10, "PLAYER_REGEN_DISABLED")
        assert(a.state == "COMBAT" and #a.plan.operations == 1 and not a.pending)
        a:Reconcile(b, s, bags, false, 11, "PLAYER_REGEN_ENABLED")
        assert(a.state == "READY")
    end },
    { name = "Fingerprint verification requires source movement", run = function()
        local b, s, bags, candidate, a = pendingScenario()
        candidate.guid = nil
        s.slots[7] = item(1007, "other", "INVTYPE_HAND")
        s.slots[7].fingerprint = candidate.fingerprint
        assert(not a:Verify(a.pending.operation, s, bags))
        bags.items = {}
        assert(a:Verify(a.pending.operation, s, bags))
    end },
    { name = "Known gems and reforges rank duplicate candidates", run = function()
        local b, s, bags = scenario()
        replace(s, 7, nil)
        b.equipment[7].gems, b.equipment[7].reforging = { 76699 }, 167
        local wrong = bag(bags, 1007, "INVTYPE_HAND")
        local correct = bag(bags, 1007, "INVTYPE_HAND")
        wrong.observations.gems = { values = { { status = "KNOWN", value = 76667 } } }
        wrong.observations.reforging = { status = "KNOWN", value = 160 }
        correct.observations.gems = { values = { { status = "KNOWN", value = 76699 } } }
        correct.observations.reforging = { status = "KNOWN", value = 167 }
        assert(plan(b, s, bags).operations[1].source == correct)
    end },
    { name = "Off-hand removal requires empty equipment and intended bag instance", run = function()
        local _, s, bags = scenario()
        local source = s.slots[16]
        local operation = { kind = "UNEQUIP", source = source, position = 16,
            destination = { bag = 0, bagSlot = 9 } }
        local a = WSGS.EquipmentActions:New()
        replace(s, 16, nil)
        assert(not a:Verify(operation, s, bags))
        bags.items[1] = item(source.id, source.guid)
        bags.items[1].bag, bags.items[1].bagSlot = 0, 9
        assert(a:Verify(operation, s, bags))
    end },
    { name = "Missing imported build blocks planning", run = function()
        local _, s, bags = scenario()
        local p = plan(nil, s, bags)
        assert(#p.operations == 0 and #p.blocked == 1)
    end },
    { name = "Live carried inventory scan is read-only and location-specific", run = function()
        local snapshot = WSGS.EquipmentScanner:Scan()
        local bags = WSGS.EquipmentInventory:Scan(snapshot)
        assert(#snapshot.slots == 16 and type(bags.unreadable) == "number")
        if bags.unreadable > 0 then return "SKIP", "Carried item data is unavailable; retry after it loads." end
        local seen = {}
        for _, candidate in ipairs(bags.items) do
            assert(candidate.bag >= 0 and candidate.bag <= NUM_BAG_SLOTS and not seen[candidate.key])
            seen[candidate.key] = true
            assert(candidate.id == C_Container.GetContainerItemID(candidate.bag, candidate.bagSlot))
        end
    end },
})
