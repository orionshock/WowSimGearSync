# WowSimGearSync

WowSimGearSync (WSGS) takes a WoW Sims gear configuration and helps you match your character's equipment, gems, enhancements, and reforges to it. It supports Mists of Pandaria Classic, Interface 50504.

## How it works

Export your configuration from WoW Sims as JSON with Gear included. Open `/wsgs import`, paste the export, and click Import. A successful import closes and clears the editor. If the import fails, your current configuration and pasted text stay intact.

Left-click the WowSimGearSync launcher in your broker display to open the equipment view. Right-click it to open the addon's options in WoW's options window. The minimap launcher is hidden by default.

The equipment view shows your target gear and the changes it needs. Equip the target items, apply available modifications, then visit the reforging and upgrade NPCs for the remaining work. With Equipment Manager integration enabled, Equip also saves the outfit once WSGS verifies that all target items are equipped. It does not wait for every enhancement or upgrade to be finished.

## Equipment and modifications

### Equip the target gear first

Each slot displays the imported item's icon. A red border means you are wearing a different item or the slot is empty. Hover for the reason it cannot be equipped, or click the slot to equip the target from your bags. Modification icons stay hidden until the correct item is equipped.

The Equip button attempts all available target equipment changes in one click. Individual slot clicks focus on that slot; weapon changes may also need the other weapon slot. WSGS accounts for swapped rings and trinkets, and checks the result before reporting completion.

Matching items show their remaining modification icons. Hover an icon to compare the current and required modification. Fully configured items show a completion check and their normal Blizzard item tooltip.

### Gems, enchants, and profession enhancements

Once any required extra socket is present, click an item that needs gems to socket its available target gems. WSGS handles replacements and socket confirmations, including repeated gems taken from the same stack. Each gemming click works on one selected item.

Other item clicks apply the next available supported enhancement, using carried enchant items or a profession recipe. Supported work includes Engineering tinkers, Tailoring embroidery and spellthread, Leatherworking enhancements, Enchanting ring enchants, belt buckles, and Blacksmithing sockets. You need the appropriate profession and materials. WSGS can apply finished Inscription shoulder enhancement items from your bags; it does not craft them for you.

Missing materials, locked items, combat, or an occupied cursor can block an action. Unavailable item information remains unresolved until the client can supply it. WSGS waits for the equipped item to show the expected change before reporting success.

### Reforging and upgrades

At a reforging NPC, the companion panel lists the items and stat conversions still needed. Apply All runs the native reforging workflow. With a supported ReforgeLite installed, Send to ReforgeLite passes your original WoW Sims configuration to ReforgeLite and starts its reforging workflow instead.

At an Item Upgrade NPC, the companion lists matching items that have upgrades remaining. Click a row to select that item in Blizzard's upgrade window. Review the cost and click Blizzard's Upgrade button yourself. WSGS compares upgradeable items against their maximum upgrade level, even if the export specifies a lower level.

### Missing materials at the Auction House

The Shopping List appears beside the Auction House with missing gems, supported enhancement items, and profession reagents for your matching equipped gear. It combines quantities across slots and subtracts what you already carry. Click a row to search for that exact item and open its listing. You choose and purchase the auctions yourself.

## Active import and Equipment Manager

WSGS keeps one active import per character and saves it across reloads and relogs. A successful new import replaces it and resets its name to the imported specialization, such as Protection. WSGS does not retain alternate imports or an import history.

Edit the name at the top of the equipment view and press Enter to save it. Names can contain up to 16 characters. This name also determines the exact Equipment Manager set WSGS creates or updates.

For example, name one import Prot-DPS and sync it. Import another Protection configuration, rename it Prot-Defensive, and sync again. Both Blizzard sets remain, while WSGS retains only the second import. Changing the active name does not rename or delete the earlier set.

WSGS updates only the set with the exact chosen name. Updates preserve its icon and shirt/tabard settings. New sets use the specialization icon and ignore shirt and tabard. Equipment must match before WSGS saves a set.

## Options

Open `/wsgs options`, right-click the launcher, or select WowSimGearSync in WoW's addon options.

- Enable debug logging: off by default. Shows detailed diagnostics in chat. Important errors remain visible with logging off.
- Default Engineering cloak: Goblin Glider: on by default. Engineers get a Goblin Glider target when the import omits the cloak tinker. Turn it off to leave an omitted cloak tinker unspecified.
- Create/update Equipment Manager sets: on by default. Turn it off to keep equipping and modifying gear without saving sets. Existing sets remain untouched.

Explicitly imported enhancements take priority over the cloak fallback. Gloves and belts follow the import without added defaults. Options persist across reloads and relogs.

## Important behavior

WSGS requires the exact target item ID. It does not substitute an item because its stats, appearance, or name seem equivalent. Keep the target equipment and required materials in your bags; bank contents are not available for these actions.

Reforging can spend gold after you start it. Auction purchases and upgrade currency spending remain under your control. WSGS does not buy auctions or press the Upgrade button.
