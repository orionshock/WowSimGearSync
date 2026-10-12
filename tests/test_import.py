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
    return len(list(wsgs.db['global'].simulationProfiles))

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
check(wsgs.db['global'].settings.debug, 'slash debug toggles')
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
# Disabled SavedVariables means a reload starts with a new session database.
lua.execute('WSGSDB = nil')
core_frame.scripts.OnEvent(core_frame, 'ADDON_LOADED', 'WoWSimGearSync')
check(not wsgs.db['global'].settings.debug and count_profiles() == 0, 'new session resets builds and debug')
check(not any(line.startswith('## SavedVariables:') for line in (ROOT/'WoWSimGearSync.toc').read_text().splitlines()), 'persistence disabled in manifest')
print(f'PASS: {checks} checks under {lua.eval("_VERSION")}; all TOC Lua files compile; real AceDB, mocked native JSON API')
