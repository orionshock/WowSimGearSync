# Forever client audit

Target: installed `wowf` 1.60.1.70755, interface 16001. Client-contract evidence
comes from `_forever_/BlizzardInterfaceCode/Interface/AddOns`, including its
Camelot variants. Imports use the supplied WoW Sims API v2 format: 17 equipment
positions, including ranged/relic equipment. No Classic compatibility path or
saved-data migration is provided.

The current file layout and module contracts are documented in
[architecture.md](architecture.md).

| Source evidence | Implementation |
| --- | --- |
| ItemDocumentation: item IDs, GUIDs, links, cache state and load completion | `Character/EquippedItems.lua`, `CarriedItems.lua`, `ItemData.lua`, `ProfessionEffects.lua` |
| No direct permanent-enchant getter in C_Item | `Character/Enchantment.lua` reads only the permanent-enchant field. |
| TradeSkillUIDocumentation and TradeSkillUITypesDocumentation | `Enhancements/Execution/ProfessionCraft.lua` uses recipe IDs, native eligibility and an item-location target. |
| ProfessionsTemplates/Blizzard_ProfessionsTransaction.lua | Direct CraftEnchant calls use ItemLocation, not indexed DoTradeSkill calls. |
| Professions/Blizzard_ProfessionsCrafting.lua | Learned, usable, material, cooldown and target checks precede crafting. |
| FrameXML/SecureTemplates.lua | `Enhancements/Execution/SecureItemUse.lua` uses secure item and target-slot attributes. |
| FrameXML/Mainline/EquipmentManager.lua | Capture scans all carried bags, including the reagent bag. |
| UIPanels_Game/Camelot/PaperDollFrame.xml and PaperDollFrame.lua | Slot 17 in the export maps to client ranged/relic inventory slot 18. |
| SharedXML/UnitUtil.lua | `EquipmentSets/Synchronize.lua` uses GetSpecializationInfoByID. |
| AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua | `Shopping/AuctionNavigation.lua` uses browse selection and search text handling. |

The UI source establishes client contracts, not Forever's full item, recipe or
simulation datasets. Enhancement mappings require in-client game-data verification.
Direct crafting rejects unlearned recipes, invalid targets and recipes requiring
quality allocation. The client still owns protected-action and purchase rules.

Static validation covers syntax and source wiring. Actual import, equipment,
crafting, confirmation, set-saving and auction behavior must be validated in the
Forever client using the scenarios in the architecture document.
