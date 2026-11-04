# Module ownership

The addon targets WoW Forever's retail client contracts directly. Source files
are grouped by feature ownership. Public interfaces live on the addon namespace;
implementation files capture their own feature tables during loading.

## Loading and composition

`Bootstrap.lua` creates the Ace addon, public feature tables, and a temporary
`WSGS.Private` registry. The TOC loads implementations in dependency order.
`Addon/Composition.lua` runs last. It binds the public interfaces, connects
runtime reconciliation and interaction policy, constructs the shopping view,
and removes `WSGS.Private` from the addon namespace.

This is explicit Lua composition. There is no dynamic loader, dependency
container, plugin framework, cross-client adapter, or compatibility alias.

Files within one feature may use that feature's private implementation tables.
Other features use the public interfaces. Composition may access all private
implementations because wiring them is its responsibility. The shared
`WSGS.Equipment.Slots` table is read-only domain metadata, not runtime state.

## Owners

| Folder | Responsibility |
| --- | --- |
| `Addon/` | Startup, settings, slash commands, launcher, and composition. |
| `Builds/` | API v2 decoding and validation, specialization recognition, active import storage and renaming. |
| `Character/` | Equipped and carried observations, professions, item loading, capture caching and invalidation. |
| `Equipment/` | Comparison, instance assignment, bag destinations, weapon dependencies, equipment execution and status. |
| `Enhancements/` | Enhancement definitions, rules, application planning, pending lifecycle, secure item use, crafting and confirmation events. |
| `EquipmentSets/` | Verified set synchronization, ignored-slot preservation, native save calls and saved-result verification. |
| `Shopping/` | Material requirements, auction navigation and shopping runtime orchestration. |
| `Interaction/` | Combat, cursor, targeting and pending-operation exclusion policy. |
| `Views/` | Windows, slot widgets, renderers, tooltips and player-facing explanations. |
| `Diagnostics/` | Structured output, comparison reports and raw equipment probes. |
| `Localization/` | Localized player-facing strings. |
| `Libs/` | Bundled upstream libraries. |

## Public interfaces

| Module | Interface |
| --- | --- |
| Builds | `GetActive()`, `Import(text)`, `Rename(expectedBuild, name)` |
| Character | `GetSnapshot()`, `Refresh(reason)`, `Invalidate(reason)`, `RequestItemData(id, requester)` |
| Equipment | `GetState(refreshReason)`, `GetStatus()`, `GetSlotState(position)`, `EquipAll()`, `EquipSlot(position)` |
| Enhancements | `GetSlotState(position)`, `BindSlot(position, button)`, `Resolve(effectID)`, `ObserveEffect(slot, observation)` |
| EquipmentSets | `SaveVerified(state, executionReport)` |
| Views | `ToggleEquipment()`, `ToggleImport()`, `RefreshEquipment()` |

Getters return read-only-by-contract data. Callers must not mutate captures,
active builds, slot metadata, or catalog definitions. Execution reports contain
copied verification facts, not live batch records. Changes to the active build
must go through the Builds interface.

`Equipment:GetSlotState` describes equipment intent; enhancement slot state
describes application intent. Neither exposes its planner or execution records.
A reason passed to `Equipment:GetState` requests a fresh client observation;
ordinary rendering uses the cached state without that argument.

## Observation and reconciliation

1. Character receives a client observation event and invalidates its capture.
2. Equipment invalidates the build-specific comparison and queues reconciliation.
3. Composition obtains the current capture and derives equipment state.
4. Equipment and enhancements reconcile their independent execution lifecycles.
5. Composition publishes `WSGS_STATE_CHANGED` with the derived state.
6. Visible views render; shopping calculates missing materials when open.

Character captures no active build or operation progress. One carried-bag scan
produces candidates, free general bag slots, item-ID indexes, material counts,
and use-spell indexes. Equipment and shopping reuse these observations.
Equipment interpretation owns build-specific comparison caching.

Character records raw item use spells. Enhancements owns the translation from
those spells to installed enhancement identities. This prevents character
capture from depending on enhancement policy.

Native enhancement events request coalesced reconciliation. Retry clicks and
verification timeouts may explicitly request a fresh observation. Rendering
never advances an execution lifecycle or initiates a protected action.

## Execution lifecycles

Equipment's batch module owns its submission records, deadline, error attribution,
counts and reconciliation. Verification compares item IDs and instance GUIDs.
Inventory actions own native cursor operations and revalidate the chosen source
immediately before moving it. Instance assignment, bag destinations and weapon
layout are separate planning policies; they do not call the client.

Enhancement rules produce plain operation descriptions without handler objects.
PendingApplication owns submission serials, timeout observation, completion,
failure and build replacement. SecureItemUse owns secure button attributes and
exact carried-material validation. ProfessionCraft owns recipe-ID queries and
native crafting. Events owns spellcast correlation and native confirmation events.
The controller owns the active build's per-slot application sessions and click
routing. At roughly 320 lines it remains cohesive; its lifecycle, executors,
event registrations and rule implementations are elsewhere.

Interaction availability prevents equipment and enhancement submissions from
overlapping. Protected equipment moves and crafting stay in the originating
hardware click. Timers observe and reconcile; they never continue a protected
queue. Opening a profession while its recipes load requires another player click.

EquipmentSets verifies the active target and execution report before saving.
SaveSelection restores the user's ignored-slot selection even when a save fails.
Its separate verification module checks the persisted set contents and metadata.

## Views

Equipment's Window builds its frame, SlotButton builds secure slot widgets,
Render updates their display, and Presentation translates domain observations
into icons and tooltips. The import dialog and shopping panel own their own frames.
Shopping's panel receives callbacks from composition rather than reaching into
its controller. Auction navigation owns pending searches and browse-result events.
Views inspect presentation status, never live equipment batch records.

## Validation

There are no automated tests or mock-client suites. Static checks cover Lua
syntax, unresolved-name changes, public interface references, TOC completeness,
and load order. Client validation should cover:

- API v2 imports with all 17 positions, including ranged/relic equipment.
- Duplicate rings and trinkets, unavailable item data and locked materials.
- Main-hand/off-hand dependencies and general bag-space allocation.
- Batch completion, client errors, timeouts and imports during pending work.
- Scroll application, profession loading, crafting and native confirmations.
- Combat transitions, held items and spell-targeting exclusion.
- Equipment Manager saves and preservation of shirt/tabard ignored state.
- Auction searches, changing bag counts and opening/closing every window.

The enhancement ID datasets still require verification against Forever game data.
Source modularity does not establish recipe availability or import-schema details
beyond the supplied API v2 example.
