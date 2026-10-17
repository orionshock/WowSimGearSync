# WowSimGearSync

WowSimGearSync helps bring your gear in line with a WoW Sims configuration in Mists of Pandaria Classic. It compares your equipment and helps you equip items, socket gems, apply enhancements, and reforge.

## Getting started

Export your WoW Sims configuration as JSON with Gear included, then paste it into `/wsgs import`. Open the equipment view with the WowSimGearSync launcher to see what needs changing.

Use Equip for the outfit, or click an individual slot to equip its target item. Once the correct gear is equipped, the modification icons show the remaining work. Hover for details and click an item to apply available gems or enhancements from your bags. Gemming works on one selected item per click.

WSGS keeps your latest import for each character, including across reloads. Importing another configuration replaces it.

## NPC assistants

At a reforging NPC, WSGS lists the needed stat changes and can apply them through its own reforging workflow or delegate to ReforgeLite.

At an Item Upgrade NPC, click an item in the companion panel to select it for upgrading. You still confirm the purchase in Blizzard's window.

At the Auction House, the Shopping List shows missing materials and opens the corresponding listings when clicked. Purchases remain up to you.

## Equipment Manager

The import's name is also its Equipment Manager set name. Edit it at the top of the equipment view to choose where WSGS saves the outfit once the target gear is equipped.

Using different names lets you keep separate Blizzard equipment sets while WSGS retains only your current import. Other named sets are left alone.

## Options

Open `/wsgs options` or right-click the launcher. You can toggle debug logging, Equipment Manager integration, and the Goblin Glider fallback for Engineers whose import omits a cloak tinker. Imported enhancements take priority.
