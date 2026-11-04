local L = LibStub("AceLocale-3.0"):NewLocale("WowSimGearSync", "enUS", true)
if not L then return end

-- Register other locales after this file and before Core.lua in the TOC.
-- Use the same English keys; AceLocale falls back to enUS for missing entries.
L["Enable debug logging"] = true
L["Create/update Equipment Manager sets"] = true
L["Save verified equipment using the active import's name. Other sets are left alone."] = true
L["Left-click: Toggle equipment view"] = true
L["Right-click: Open options"] = true
L["Active build: %s"] = true
L["None"] = true

L["Not enough gold."] = true
L["Shopping List"] = true
L["× %d"] = true
L["Import WoW Sims Gear"] = true
L["Paste your WoW Sims gear export."] = true
L["Import a WoW Sims build to get started."] = true
L["Enter to save. Escape to cancel."] = true
L["Item is locked. Try again shortly."] = true
L["Equipped item changed. Select it again."] = true
L["Total"] = true
L["Known total"] = true
L["Waiting for equipment to update"] = true
L["Click to equip target weapons"] = true
L["Item information isn't available yet."] = true
