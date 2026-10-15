# Task 040: targeted code quality corrections

Implemented in the existing live-addon workspace by user confirmation. The requested `C:\WoWAddons\WoWSimGearSync` path was absent. The inspected baseline was `0fbe87f4fb58fd68c86ad672fdfdbf3c925c4502`; all three actionable findings still applied. The existing review report was untracked before this task and is left outside the correction commit.

SavedVariables remains enabled as `## SavedVariables: WSGSDB`, following the user's subsequent instruction. Interface remains 50504; AceDB profile and character scopes are unchanged.

## Corrections and contracts

| Finding | Root cause | Correction |
| --- | --- | --- |
| Paper-doll refresh | Most refresh reasons fell through an item-data `success`/relevance filter even though their payloads were ordinary events. | Explicit general-event allowlist, separate item-data event checks, and rejection of unrelated reasons. Visibility gating and the existing next-frame coalescer remain. |
| Pending verification | Previous pending operations survived a newly active build and were evaluated against its differences. Build IDs alone cannot identify reimports of the same specialization. | Bind controller lifetime to the actual active build table. On replacement, discard verification/controllers and button submission references before processing another plan, click, event, or timeout. Reject captures belonging to another equipment table. |
| Item-data subscribers | One requester string per ID replaced earlier subscribers; failures left local request flags set; the paper doll had no completion subscription. | One pending subscriber set per item ID, one actual load while pending, and the existing completion message once per distinct requester. Consumers clear flags on failures and successes. The paper doll redraws relevant successful completions. |

General paper-doll refresh reasons: `PLAYER_EQUIPMENT_CHANGED`, `BAG_UPDATE_DELAYED`, `ITEM_LOCK_CHANGED`, `SPELLS_CHANGED`, `SKILL_LINES_CHANGED`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, and `CURSOR_CHANGED`. `GET_ITEM_INFO_RECEIVED` and `ITEM_DATA_LOAD_RESULT` refresh reasons require successful, relevant item data. Unknown reasons do not refresh. No new polling, capture path, or timer was added. Existing `GetState` caching supplies rendering; combat/cursor-only updates reuse the capture and recalculate readiness.

`WSGS_EQUIPMENT_REFRESH_REQUESTED` retains its payload. `WSGS_BUILD_IMPORTED` retains its payload and now has an Actions consumer. `WSGS_ACTIONS_CHANGED` retains its payload and may carry `BUILD_REPLACED`. `WSGS_ITEM_DATA_RECEIVED` still carries `(itemID, success, requester)`, but emits once per distinct subscriber. Existing subscribers need no payload migration.

Equipment's broker now uses `ITEM_DATA_LOAD_RESULT` as its sole registered client completion event, matching the installed Classic `ItemEventListener`. Consuming both that event and `GET_ITEM_INFO_RECEIVED` could let duplicate notifications consume a later request. The UI still accepts legacy item-data refresh reasons from message senders. An immediate request API error sends the same completion message with `success=false`, releases subscribers, and returns the original error to the caller.

System completion traffic is filtered by the pending-ID map before any addon message, log, invalidation, or refresh. Distinct requester keys deduplicate subscriber notifications. Only multi-subscriber completions and failures produce the new diagnostic. Successful loads for equipped, target, or carried items invalidate the cached capture through the existing path; carried material data can change its use-spell index. Tooltip-only IDs outside the capture redraw names using cached equipment state. This avoids scanning for unrelated system loads while allowing material readiness to update when newly loaded data changes it.

Shopping List, Item Upgrades, and Paper Doll clear their local flags on either outcome. Only success schedules a completion redraw. Failures remain unknown/retryable and retry on a later normal refresh or panel reopening; no automatic failure retry loop runs. Equipment Inspector also clears its tinker-request suppression on failure. Successful tinker requests retain the prior suppression policy so a successfully loaded item with no mapped use spell does not produce repeated loads.

Target-only tooltip sections previously used `ipairs({nil, target})`, which stops before visiting the target. Paper Doll registration and Modification Tooltip measurement now use dense pairs. This permits uncached target-material requests and correct name measurement without changing tooltip content or layout rules.

## Pending operation behavior

Build replacement cancels addon verification only. It does not interrupt a spell, accept/close socketing, clear a client cursor, or issue another protected action. A same-specialization reimport is a replacement because SaveBuild installs a new build table. Renaming the existing table does not cancel it.

Cancellation logs the old/new build IDs, original inventory slot, serial, effect expectation, socket count, and target GUID under `[ACTION][CANCEL]`. Timer serials remain monotonically increasing, so an old timeout cannot classify a new controller. PreClick/PostClick callbacks retain their sequence. A click that first detects a replacement returns after clearing stale bookkeeping; a fresh plan is rendered through the existing refresh path.

Actions records the synchronous `UNIT_SPELLCAST_SENT` cast GUID for its submitting operation, including alternate socket recipes. Spell success/failure/interruption handling requires that GUID as well as the spell ID, so a cancelled cast's completion cannot be attributed to a later cast of the same recipe. This event signature was checked against the installed generated Unit documentation and Quartz's event handler.

For untagged equipment/bag/socket events, success still requires observed state, not the event itself. The verifier additionally checks that the comparison describes the captured submitted expectation. Additional sockets retain their captured required socket count and the comparator's count-based `MATCH` semantics; the operation's boolean `expected=true` is not used as a scalar socket count. No cast event alone declares success.

The addon cannot undo an action already accepted by the client. Its effect may appear after cancellation and affect the replacement build's next comparison. Finish or cancel any remaining Blizzard targeting/socket interaction through Blizzard's UI. The addon must never log the discarded operation as verified against the replacement build.

## Files changed

- `UI/Module.lua`: event categories and item-data completion consumer.
- `UI/PaperDoll.lua`: target-only tooltip item registration.
- `UI/ModificationTooltip.lua`: target-only tooltip width measurement.
- `Actions/Module.lua`: build-bound verification lifetime and cast correlation.
- `Actions/Handlers.lua`: submitted expectation guard and socket count capture.
- `EquipmentState.lua`: subscriber sets, deduplicated loading, authoritative completion, and concise multi-subscriber/failure diagnostics.
- `EquipmentInspector.lua`: release failed tinker item-data requests.
- `ShoppingList.lua` and `NPC/ItemUpgrades.lua`: release local flags on failure without changing auction or staging behavior.
- This implementation/validation note.

The existing large modules remain cohesive lifecycle owners. These changes do not justify new files for runtime logic, an execution framework, or a state-machine rewrite. Reforging, profession execution, equipment-set synchronization, weapon planning, ring/trinket assignment, and bag projections were not edited.

## Static validation

Available local tool: `C:\luacheck\luacheck.exe`, version 0.23.0. No compiler/parser packages or repository tooling were installed. Run these from the repository in PowerShell:

```powershell
$luaFiles = Get-ChildItem -Recurse -Filter '*.lua' |
    Where-Object { $_.FullName -notmatch '\\Libs\\' } |
    Select-Object -ExpandProperty FullName
& C:\luacheck\luacheck.exe --no-config --no-default-config --no-cache --std lua51 --no-global --no-unused-args --no-self --no-max-line-length --codes --no-color -- $luaFiles

$entries = @(Get-Content WoWSimGearSync.toc | Where-Object { $_ -match '\.lua$' })
& C:\luacheck\luacheck.exe --no-config --no-default-config --no-cache --std lua51 --only 0 --no-color -qq -- $entries
git diff --check
```

The broader analysis reports 0 errors and 11 warnings across 31 handwritten Lua files. The warnings are unchanged from HEAD: two trailing-whitespace warnings in Import/Specialization, one shadowed `value` parameter in each NPC module, and seven shadowed `self` parameters in UI/ImportDialog. WoW globals and unused event parameters are excluded intentionally. The errors-only pass covers all 43 TOC Lua entries, including libraries, and reports 0 errors.

Static TOC inspection confirmed that all 43 Lua paths exist, none are duplicated, and relevant producer/consumer dependencies load in order. Diff checks found no whitespace errors after working-copy line endings were made consistent. These checks do not execute addon code or prove secure client behavior. No automated tests, mocks, or harnesses were created or run.

## Required in-game validation

All checks below remain unperformed. Use the actual MoP Classic client with debug output enabled; watch for Lua errors and taint as well as visible results.

1. Open the paper doll with a matched target item whose enhancement material is missing. Acquire the required material without closing the view. Its next action should become ready, with the correct tooltip.
2. Move the material between bags/slots and lock/unlock it through ordinary client interactions. Readiness should refresh, and a subsequent click must use the current location or safely require a rescan. Check the Equip button if missing equipment is acquired too.
3. Enter combat with the paper doll visible, then leave. The Equip button should show combat blocking and restore appropriate readiness afterward. Slot secure actions must remain unavailable in combat without protected-operation errors.
4. Pick up an item onto the cursor, then return it. The Equip button should reflect the cursor blocker and recover. Try a slot action while holding the cursor item; the existing safety check must still block it.
5. Begin an enhancement or open socketing, then import a replacement build while verification is pending. Include reimporting the same specialization and changing to a different specialization. Expect one cancellation record per outstanding operation, containing its original GUID, slot, serial, and expectation. Finish/cancel any remaining Blizzard interaction manually.
6. For the same equipped instance, make the replacement request a different effect or gem. Let the old client action finish or fail, then submit the new action when the client permits it. The cancelled operation must never log VERIFIED; old cast results/timeouts must not complete or fail the new cast. Also exercise an additional socket: success still depends on sufficient observed socket count.
7. With Shopping List and Paper Doll open, choose a genuinely uncached required material. Let both consumers request it before completion. For deliberate manual diagnosis, use WowLua to call the real broker twice in the same callback with that ID and the existing requester strings `ShoppingList` and `PaperDoll:modification-tooltip`. Expect one `[STATE][ITEM_DATA]` completion with `subscribers=2` and both views updated. A cached item or synchronous completion may not exercise overlapping subscribers; do not count that as evidence of fanout.
8. Hover a modification icon whose target material name is uncached, including an Apply/unknown-current section. Keep the tooltip open while loading finishes. Its name and width should update without reopening the paper doll. Repeat after hiding the paper doll during a request; reopening should display available data.
9. Observe a genuine failed item-data request, or use the real request API with a known nonexistent positive item ID during manual client diagnosis. Do not inject completion events. Confirm the broker releases subscribers and the affected consumers' request flags clear. A subsequent explicit request or normal panel refresh must be able to request again. No repeated per-frame failure loop or permanent action failure should appear. A still-pending load must remain unknown rather than be declared failed merely due to delay.
10. At the reforge NPC, exercise normal native behavior and the installed ReforgeLite delegation. At the upgrade NPC, stage an item and purchase manually with Blizzard's button. Confirm normal selection, cost presentation, and post-change refresh. These execution paths were not modified, but their regressions require client evidence to rule out.

No live-client validation is claimed by this task.
