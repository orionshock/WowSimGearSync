# WowSimGearSync

WowSimGearSync helps bring your gear in line with a WoW Sims configuration in WoW Forever, using its retail client APIs. It compares your equipment and helps you equip items and apply enhancements.

Target client: WoW Forever 1.60.1 (interface 16001). This branch uses retail APIs directly and has no Classic compatibility path.

## Getting started

Export your WoW Sims configuration as JSON with Gear included, then paste it into `/wsgs import`. Open the equipment view with the WowSimGearSync launcher to see what needs changing.

Use Equip for the outfit, or click an individual slot to equip its target item. Once the correct gear is equipped, the modification icons show the remaining work. Hover for details and click an item to apply available enhancements from your bags.

WSGS keeps your latest import for each character, including across reloads. Importing another configuration replaces it.

## Shopping list

Gems, additional gem sockets, reforging, and item upgrades are not part of the Forever implementation.

At the Auction House, the Shopping List shows missing materials and opens the corresponding listings when clicked. Purchases remain up to you.

Profession recipes load asynchronously. If a click opens a profession before its data is ready, click the item again once loading finishes. Crafting is never deferred to a timer or event.

Imports use the supplied WoW Sims API v2 format with 17 equipment positions, including ranged weapons and relics. Enhancement mappings still need verification against Forever game data; recipe execution checks the client's learned recipes and target eligibility.

## Equipment Manager

The import's name is also its Equipment Manager set name. Edit it at the top of the equipment view to choose where WSGS saves the outfit once the target gear is equipped.

Using different names lets you keep separate Blizzard equipment sets while WSGS retains only your current import. Other named sets are left alone.

## Options

Open `/wsgs options` or right-click the launcher. You can toggle debug logging and Equipment Manager integration. Profession enhancements must be explicitly included in the import.

## Development layout

Production code is grouped by feature ownership. `Bootstrap.lua` loads first; `Addon/Composition.lua` wires the modules last.
