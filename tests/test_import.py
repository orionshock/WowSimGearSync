"""Synthetic importer tests; client JSON API is mocked with Python's decoder.
Run: python tests/test_import.py --runtime-path <directory containing lupa>
Requires lupa with its Lua 5.1 runtime. No game-client execution is simulated.
"""
import argparse
import copy
import json
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--runtime-path')
args = parser.parse_args()
if args.runtime_path:
    sys.path.insert(0, args.runtime_path)
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
NUM_CHAT_WINDOWS = 10
frames = {}
function CreateFrame()
    local f = { scripts = {} }
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript(event, callback) self.scripts[event] = callback end
    frames[#frames + 1] = f
    return f
end
function GetRealmName() return "TestRealm" end
function UnitName() return "Tester" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitRace() return "Human", "Human" end
function UnitFactionGroup() return "Alliance" end
function GetLocale() return "enUS" end
function GetCurrentRegion() return 1 end
function time() return 1234567890 end
SlashCmdList = {}
chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, message) chat[#chat+1] = message end }
C_EncodingUtil = {}
WSGS = {}
''')

def to_lua(value):
    if isinstance(value, dict):
        return lua.table_from({key: to_lua(child) for key, child in value.items() if child is not None})
    if isinstance(value, list):
        return lua.table_from({i: to_lua(child) for i, child in enumerate(value, 1) if child is not None})
    return value

def decode(token):
    return to_lua(json.loads(token, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value))))
lua.globals().C_EncodingUtil.DeserializeJSON = decode
files = [line for line in (ROOT/'WoWSimGearSync.toc').read_text().splitlines()
         if line and not line.startswith('#')]
for file in files:
    path = ROOT / file.replace('\\', '/')
    source = path.read_text(encoding='utf-8-sig')
    lua.compile(source, name=file)('WoWSimGearSync', lua.globals().WSGS)
# Trigger real Core initialization and real bundled AceDB.
core_frame = lua.globals().frames[2]
core_frame.scripts.OnEvent(core_frame, 'ADDON_LOADED', 'WoWSimGearSync')
wsgs = lua.globals().WSGS
# Exercise quiet operation explicitly while preserving the developer's debug default.
wsgs.db.profile.debug = False
lua.execute('chat = {}')
fixture = json.loads((ROOT/'tests/fixtures/synthetic-paladin-v3.json').read_text())
checks = 0

def check(condition, message):
    global checks
    assert condition, message
    checks += 1

def import_doc(document, name=''):
    result = wsgs.ImportEquipment(wsgs, json.dumps(document), name)
    return result if isinstance(result, tuple) else (result, None)

def count_profiles():
    return len(list(wsgs.db.char.simulationProfiles))

profile, error = import_doc(fixture, 'Synthetic Retribution')
check(profile is not None and error is None, 'full fixture imports')
check(len(profile.equipment) == 16, 'all sixteen positions')
check(profile.equipment[4].tinker == 4898, 'numeric tinker')
check(profile.equipment[1].upgradeStep == 'UpgradeStepTwo', 'enum upgrade')
check(profile.equipment[8].upgradeStep == 2, 'numeric upgrade')
check(profile.equipment[1].reforging == 145, 'numeric reforge')
check(profile.equipment[1].gems[2] == 0, 'zero gem retained')
check(profile.equipment[3].enchant is None, 'missing enchant accepted')
check(profile.equipment[5].empty and profile.equipment[6].empty, 'object and null empty slots')
check(profile.equipment[2].id == profile.equipment[7].id == 1002, 'duplicate IDs keep order')
check(profile.equipment[4].slotId == 15 and profile.equipment[6].slotId == 9, 'back and wrist mappings')
check(profile.equipment[15].slotId == 16 and profile.equipment[16].slotId == 17, 'weapon mappings')
extra = profile.equipment[1].extraFields.future
check(extra.array is not None, 'unknown native table data retained')
second, _ = import_doc(fixture, 'Synthetic Retribution')
check(second.id != profile.id and count_profiles() == 2, 'same name creates distinct builds')
check(profile.metadata.importedAt == 1234567890 and profile.apiVersion == 3, 'metadata')
check(len(lua.globals().chat) == 0, 'debug off is silent')
lua.globals().SlashCmdList.ACECONSOLE_WSGS('debug')
check(wsgs.db.profile.debug, 'slash debug toggles')
short = copy.deepcopy(fixture)
short['player']['equipment']['items'] = []
empty, _ = import_doc(short)
check(empty.metadata.entryCount == 0 and len(empty.equipment) == 16, 'short arrays padded')
check(empty.name.startswith('Imported Build '), 'default name')

invalid = [[], {}, {'apiVersion': 2, 'player': fixture['player']},
           {'apiVersion': '3', 'player': fixture['player']}, {'apiVersion': 3},
           {'apiVersion': 3, 'player': {'class': 'ClassPaladin', 'equipment': {'items': {'invalid': 1}}}}]
for field, value in [('id', '100'), ('id', -1), ('id', 1.5), ('id', True),
                     ('enchant', []), ('gems', {'invalid': 1}), ('gems', ['1']),
                     ('reforging', False), ('upgradeStep', {}), ('tinker', False)]:
    doc = copy.deepcopy(fixture)
    doc['player']['equipment']['items'][0] = {field: value}
    invalid.append(doc)
doc = copy.deepcopy(fixture)
doc['player']['equipment']['items'].append({'id': 17})
invalid.append(doc)
doc = copy.deepcopy(fixture)
doc['player']['class'] = None
invalid.append(doc)
for doc in invalid:
    before = count_profiles()
    result, reason = import_doc(doc)
    check(result is None and isinstance(reason, str) and count_profiles() == before, 'invalid document is atomic')
for text in ['', '{', '{"a":1,}', '[1,]', '{"a":01}',
             '{"a":1.}', '{"a":1e}', '{"a":NaN}', '{"a":"\\q"}', '{} trailing',
             '{"a":"raw\nnewline"}', 'x'*1048577]:
    before = count_profiles()
    result, reason = wsgs.ImportEquipment(wsgs, text, '')
    check(result is None and reason and count_profiles() == before, 'malformed/resource-limited input is atomic')
# Native string escapes and exponent decoding.
value = decode('{"a":"\\u0041\\n\\\"", "b":1.25e2, "c":false}')
check(value.a == 'A\n"' and value.b == 125 and value.c is False, 'native scalar decoding')
# Long exports, native Unicode escapes, and optional string modifications.
long_doc = copy.deepcopy(fixture)
long_doc['player']['equipment']['items'][0]['futureLongValue'] = 'x' * 100000
long_doc['player']['equipment']['items'][0]['reforging'] = 'ReforgeCritToHaste'
long_profile, _ = import_doc(long_doc)
check(len(long_profile.equipment[1].extraFields.futureLongValue) == 100000, 'long input preserved')
check(long_profile.equipment[1].reforging == 'ReforgeCritToHaste', 'string reforge preserved')
before = count_profiles()
result, reason = import_doc(fixture, 'x'*81)
check(result is None and reason and count_profiles() == before, 'long names rejected atomically')
value = decode('{"text":"\\uD83D\\uDE00"}')
check(value.text == '\U0001f600', 'native Unicode surrogate decoding')
# Exact gear supplied by the user, in a synthetic full-export envelope.
user_gear = json.loads((ROOT/'tests/fixtures/user-paladin-equipment-v3.json').read_text(encoding='utf-8-sig'))
full_export = copy.deepcopy(user_gear)
full_export.update({'raidBuffs': {'bloodlust': True}, 'debuffs': {'weakenedArmor': True},
                    'tanks': [{'type': 'Player'}], 'partyBuffs': {},
                    'encounter': {'apiVersion': 3, 'duration': 620, 'targets': [{'id': 60999}]}})
full_export['player'].update({'name': 'Player', 'race': 'RaceBloodElf', 'talentsString': '313232',
    'glyphs': {'major1': 45744}, 'profession1': 'Engineering', 'profession2': 'Mining',
    'consumables': {'potId': 76090}, 'bonusStats': {'stats': [0]*23},
    'itemSwap': {'items': [{}]*16}, 'buffs': {'vigilanceCount': 2},
    'protectionPaladin': {'options': {'classOptions': {'seal': 'Insight'}}},
    'healingModel': {'hps': 58682},
    'rotation': {'type': 'TypeAPL', 'priorityList': [{'action': {'castSpell': {'spellId': {'spellId': 20925}}}}]*100}})
for text in [json.dumps(full_export, indent=2), json.dumps(full_export, separators=(',', ':'))]:
    imported = wsgs.ImportEquipment(wsgs, text, 'User Paladin')
    check(imported.metadata.entryCount == 16 and imported.metadata.equippedCount == 16, 'full export imports sixteen equipped items')
    check(len(imported.metadata.warnings) == 0, 'unrelated export sections do not generate warnings')
    for index, expected in enumerate(user_gear['player']['equipment']['items'], 1):
        for key, value in expected.items():
            actual = imported.equipment[index][key]
            if isinstance(value, list):
                actual = [actual[i] for i in range(1, len(actual)+1)]
            check(actual == value, 'user gear modifications and order retained')
    check(set(imported) == {'id', 'name', 'class', 'apiVersion', 'equipment', 'metadata', 'specialization'}, 'only gear and import identity retained')
    for field in ['rotation', 'talentsString', 'glyphs', 'itemSwap', 'raidBuffs', 'encounter', 'consumables']:
        check(imported[field] is None, 'non-equipment settings excluded')
# Specialization metadata and naming are independent of equipped items.
protected, _ = import_doc(user_gear)
check(protected.name == 'Paladin - Protection', 'detected spec supplies default name')
check(dict(protected.specialization) == {'class': 'Paladin', 'name': 'Protection', 'id': 66, 'source': 'player.protectionPaladin'}, 'normalized Protection identification only')
manual, _ = import_doc(user_gear, 'My Tank Set')
check(manual.name == 'My Tank Set', 'manual import name retained')
repeated, _ = import_doc(user_gear)
check(repeated.id != protected.id and repeated.name == protected.name, 'repeated detected imports remain distinct')
for field, expected_name, expected_id in [('holyPaladin', 'Holy', 65), ('retributionPaladin', 'Retribution', 70)]:
    doc = copy.deepcopy(user_gear)
    del doc['player']['protectionPaladin']
    doc['player'][field] = {}
    detected, _ = import_doc(doc)
    check(detected.specialization.name == expected_name and detected.specialization.id == expected_id, 'other Paladin specialization')
for change, source in [({'retributionPaladin': {}}, 'ambiguous'),
                       ({'protectionPaladin': False}, 'invalid'),
                       ({'class': 'ClassMage'}, 'invalid')]:
    doc = copy.deepcopy(user_gear)
    doc['player'].update(change)
    detected, _ = import_doc(doc)
    check(detected.specialization.name == 'Unspecified' and detected.specialization.id is None and detected.specialization.source == source, 'ambiguous or invalid spec is unspecified')
missing, _ = import_doc(fixture)
check(missing.specialization.name == 'Unspecified' and missing.specialization.source == 'missing', 'gear alone never establishes specialization')
numeric = copy.deepcopy(user_gear)
numeric['player']['class'] = 2
numeric_profile, _ = import_doc(numeric)
check(numeric_profile.specialization.id == 66, 'numeric schema class enum accepted')
# Cover each remaining class with an authoritative explicit field.
for class_name, field, name, spec_id in [
    ('ClassWarrior', 'protectionWarrior', 'Protection', 73),
    ('ClassHunter', 'beastMasteryHunter', 'Beast Mastery', 253),
    ('ClassRogue', 'combatRogue', 'Combat', 260),
    ('ClassPriest', 'disciplinePriest', 'Discipline', 256),
    ('ClassDeathKnight', 'frostDeathKnight', 'Frost', 251),
    ('ClassShaman', 'restorationShaman', 'Restoration', 264),
    ('ClassMage', 'frostMage', 'Frost', 64),
    ('ClassWarlock', 'afflictionWarlock', 'Affliction', 265),
    ('ClassMonk', 'mistweaverMonk', 'Mistweaver', 270),
    ('ClassDruid', 'guardianDruid', 'Guardian', 104),
]:
    doc = copy.deepcopy(fixture)
    doc['player']['class'] = class_name
    doc['player'][field] = {}
    detected, _ = import_doc(doc)
    check(detected.specialization.name == name and detected.specialization.id == spec_id and detected.specialization.source == 'player.' + field, 'explicit schema field for other class')
# Exercise the real name-suggestion method with a minimal EditBox test double.
name_input = lua.eval("function() local box = {text = ''}; function box:GetText() return self.text end; function box:SetText(text) self.text = text end; return box end")()
wsgs.UpdateSuggestedProfileName(wsgs, name_input, json.dumps(user_gear))
check(name_input.text == 'Paladin - Protection', 'UI populates name from pasted export')
retribution = copy.deepcopy(user_gear)
del retribution['player']['protectionPaladin']
retribution['player']['retributionPaladin'] = {}
wsgs.UpdateSuggestedProfileName(wsgs, name_input, json.dumps(retribution))
check(name_input.text == 'Paladin - Retribution', 'automatic name follows a new export')
name_input.text = 'Manually entered name'
wsgs.UpdateSuggestedProfileName(wsgs, name_input, json.dumps(user_gear))
check(name_input.text == 'Manually entered name', 'nonempty manually entered name never overwritten')
name_input.text = name_input.suggestedName
name_input.userEdited = True
wsgs.UpdateSuggestedProfileName(wsgs, name_input, json.dumps(user_gear))
check(name_input.text == 'Paladin - Retribution', 'user-owned name equal to old suggestion is preserved')
name_input.userEdited = False
wsgs.UpdateSuggestedProfileName(wsgs, name_input, json.dumps(fixture))
check(name_input.text == '', 'missing spec clears a stale automatic suggestion')
wsgs.UpdateSuggestedProfileName(wsgs, name_input, json.dumps(user_gear))
wsgs.UpdateSuggestedProfileName(wsgs, name_input, '{')
check(name_input.text == '', 'malformed paste clears automatic suggestion safely')
check(set(protected.specialization) == {'class', 'name', 'id', 'source'}, 'only essential specialization metadata retained')
check(protected.protectionPaladin is None and protected.rotation is None and protected.talentsString is None, 'spec options and talents not stored')
# Disabled SavedVariables means a reload starts with a new session database.
lua.execute('WSGSDB = nil')
core_frame.scripts.OnEvent(core_frame, 'ADDON_LOADED', 'WoWSimGearSync')
check(wsgs.db.profile.debug and count_profiles() == 0, 'new session resets builds and restores debug default')
check(not any(line.startswith('## SavedVariables:') for line in (ROOT/'WoWSimGearSync.toc').read_text().splitlines()), 'persistence disabled in manifest')
equipment_checks = lua.compile((ROOT/'tests/test_equipment.lua').read_text(encoding='utf-8-sig'), name='tests/test_equipment.lua')(wsgs)
# AceDB settings profiles vary independently from character-owned builds.
latest_id = wsgs.db.char.latestSimulationProfileId
previous_profile = wsgs.db.GetCurrentProfile(wsgs.db)
wsgs.db.profile.debug = False
wsgs.db.SetProfile(wsgs.db, 'Scope test')
check(wsgs.db.profile.debug, 'new AceDB profile inherits debug default')
check(wsgs.db.char.latestSimulationProfileId == latest_id, 'settings profile switch preserves character builds')
wsgs.db.SetProfile(wsgs.db, previous_profile)
check(not wsgs.db.profile.debug, 'previous settings profile retains its own debug value')
check(wsgs.db.char.simulationProfiles[latest_id] is not None, 'character collection independent of settings profile')
print(f'PASS: {checks} importer checks and {equipment_checks} equipment checks under {lua.eval("_VERSION")}; all TOC Lua files compile; real AceDB, mocked client APIs')
