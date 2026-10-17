local L = LibStub("AceLocale-3.0"):NewLocale("WowSimGearSync", "enUS", true)
if not L then return end

-- Register other locales after this file and before Core.lua in the TOC.
-- Use the same English keys; AceLocale falls back to enUS for missing entries.
L["Enable debug logging"] = true
L["Default Engineering cloak: Goblin Glider"] = true
L["Create/update Equipment Manager sets"] = true
L["Use Goblin Glider when your import omits a cloak tinker. Imported enhancements take priority."] = true
L["Save verified equipment using the active import's name. Other sets are left alone."] = true
L["Left-click: Toggle equipment view"] = true
L["Right-click: Open options"] = true
L["Active build: %s"] = true
L["None"] = true
