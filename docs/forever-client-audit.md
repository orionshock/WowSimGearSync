# Forever client audit

Target: installed `wowf` 1.60.1.70755, interface 16001. API evidence comes from
`_forever_/BlizzardInterfaceCode/Interface/AddOns`, including its Camelot variants.
The export format is WoW Sims API v2, verified against the supplied Forever export. There is no
Classic client fallback, saved-data migration, or cross-client API adapter.

| File | Retail client decision |
| --- | --- |
| `WowSimGearSync.toc` | Target interface 16001; load the enchantment reader instead of the general link decoder. |
| `Core.lua` | Keep retail Settings and addon metadata APIs; log the actual client build; remove automatic cloak enhancement policy. |
| `Options.lua` | Keep Settings registration through AceConfig; remove the automatic MoP cloak recommendation. |
| `EquipmentSlots.lua` | Map all 17 v2 export positions, including ranged/relic, to client inventory slots; shirt and tabard remain unmanaged. |
| `ItemLinkDecoder.lua` | Remove; client item IDs and GUIDs replace its identity and fingerprint responsibilities. |
| `ItemEnchantment.lua` | Read only the permanent-enchant field. The supplied C_Item API has no permanent-enchant getter. |
| `EquipmentScanner.lua` | Observe inventory identity and GUIDs directly; enchantment parsing cannot invalidate item identity. |
| `EquipmentInspector.lua` | Read item use spells through C_Item; request item data using the native inventory item ID. |
| `EquipmentInventory.lua` | Scan all carried bag slots, including the reagent bag; require GUIDs for equipment candidates. |
| `EquipmentComparator.lua` | Compare explicit enhancement targets; remove inferred MoP cloak targets. |
| `EquipmentPlanner.lua` | Assign native item GUIDs; remove fingerprint counts and the link-based direct-equip shortcut. |
| `EquipmentExecution.lua` | Move the selected bag/equipment instance using cursor APIs after checking its GUID. |
| `EquipmentActions.lua` | Verify equipped and stored instances by GUID only. |
| `EquipmentSlotActions.lua` | Treat an unavailable GUID as unresolved item data. |
| `EquipmentSetSync.lua` | Save the ranged/relic slot; use client equipped-slot bounds and GetSpecializationInfoByID. |
| `EquipmentState.lua` | Keep ITEM_DATA_LOAD_RESULT; invalidate on recipe-data and specialization changes. |
| `EquipmentDiagnostics.lua` | Keep read-only observations; remove recommendation-source diagnostics. |
| `ModificationMaterials.lua` | Scan the reagent bag; remove profession spellbook indexes and automatic cloak policy. |
| `ShoppingList.lua` | Keep the retail AuctionHouseFrame browse/search flow, verified against the supplied Shared UI source. |
| `Actions/Handlers.lua` | Prepare recipe spell IDs without spellbook positions or alternate Classic recipe IDs. |
| `Actions/Planner.lua` | Keep enhancement-only operation planning and native target GUIDs. |
| `Actions/ProfessionExecution.lua` | Use C_TradeSkillUI.OpenTradeSkill, recipe-ID queries, target eligibility, and CraftEnchant with an ItemLocation. |
| `Actions/Module.lua` | Use TRADE_SKILL_LIST_UPDATE; remove obsolete spellbook and recipe-alias state. |
| `Actions/Presentation.lua` | Keep enhancement instructions; no client API adaptation needed. |
| `Import/Module.lua` | Validate API v2 and 17 equipment positions; unsupported fields are discarded, not stored for compatibility. |
| `Import/Specialization.lua` | Read simulation oneof fields from the supplied v2 format; client API selection is separate. |
| `Import/ManagedBuilds.lua` | Keep per-character imports and Equipment Manager name validation. |
| `UI/Module.lua` | Refresh on retail recipe and specialization events; prevent first-time protected frame creation in combat. |
| `UI/PaperDoll.lua` | Keep retail portrait and secure action templates; target-slot item use is supported by SecureTemplates.lua. |
| `UI/SlotPresentation.lua` | Use a single recipe spell ID for profession enhancements. |
| `UI/ModificationTooltip.lua` | Replace the old talent-frame texture coordinates with a retail atlas used by Camelot UI. |
| `UI/ImportDialog.lua` | Keep retail portrait frame and scrolling edit box APIs. |
| `Localization/enUS.lua` | Remove obsolete automatic cloak and upgrade strings. |
| `Libs/` | Inspect loaded API usage and parse syntax; retain bundled upstream code. No new library compatibility patches. |
| `.github/workflows/release.yml`, `.pkgmeta` | Keep packaging behavior; the TOC supplies the client interface version. |
| `AGENTS.md`, `README.md` | Document the Forever client target and direct retail API policy. |

## Evidence and limits

- `Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`: native item identity,
  links, GUIDs, data loading; no direct permanent-enchant getter.
- `Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua` and
  `TradeSkillUITypesDocumentation.lua`: recipe info, schematics, enchanting targets,
  profession opening, and CraftEnchant's item-location parameter.
- `Blizzard_ProfessionsTemplates/Blizzard_ProfessionsTransaction.lua`: native
  CraftEnchant call with an ItemLocation, not an indexed DoTradeSkill call.
- `Blizzard_Professions/Blizzard_ProfessionsCrafting.lua`: learned/usable recipe,
  requirements, material, and cooldown checks.
- `Blizzard_FrameXML/SecureTemplates.lua`: secure item use and target-slot support.
- `Blizzard_FrameXML/Mainline/EquipmentManager.lua`: all carried bag slots.
- `Blizzard_UIPanels_Game/Camelot/PaperDollFrame.xml` and `PaperDollFrame.lua`:
  ranged/relic slot support; the supplied v2 export includes position 17.
- `Blizzard_SharedXML/UnitUtil.lua`: GetSpecializationInfoByID.
- `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua`: browse selection
  and search text handling.

The UI source establishes client contracts, not Forever's available items,
recipes, or the full simulation schema. Existing enhancement ID mappings require in-client
game-data verification. Direct crafting rejects unlearned recipes, invalid targets,
and recipes requiring quality allocation; those use Blizzard's profession UI.

No automated tests or mock client were added. Lua syntax and TOC references are
checked statically. In-client validation remains necessary for import, duplicate
item moves, two-handed weapons, set saves, scroll application, direct profession
enhancement, auction searches, and combat restrictions.
