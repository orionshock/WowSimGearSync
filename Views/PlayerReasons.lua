local _, WSGS = ...
local Modules = WSGS.Private
local playerReasons = {
    ["Awaiting client verification."] = "Waiting for the item to update.",
    ["Equipped item instance is not available yet"] = "Equipped item information is not available yet",
    ["Equipped item identity is not available yet"] = "Equipped item information is not available yet",
    ["Equipped item identity unknown"] = "Equipped item information is not available yet",
    ["Target item is not confirmed in this slot"] = "Equip the target item first",
    ["Modification representations have no verified conversion"] = "This enhancement could not be identified",
    ["Required modification could not be observed"] = "Enhancement information is not available yet",
    ["No confirmed direct profession enhancement mapping"] = "This profession enhancement is not supported yet",
    ["No confirmed Blacksmithing socket recipe for this slot"] = "No supported socket recipe for this slot",
    ["Required enchantment material is not yet known"] = "The material for this enchantment is not known yet",
    ["No verified equipped-item observation for this field"] = "Item information is not available yet",
    ["Profession effect not established"] = "Profession enhancement information is not available yet",
    ["C_Item.GetItemSpell returned nil"] = "Profession enhancement information is not available yet",
    ["C_Item.GetItemSpell failed"] = "Profession enhancement information could not be read",
    ["Equipped item use spell is not mapped for this profession slot"] = "This profession enhancement could not be identified",
    ["Equipment snapshot is unavailable."] = "Equipment information is not available yet.",
    ["Only numeric player.apiVersion 2 is supported."] = "Unsupported character export format. Export your gear again from WoW Sims.",
    ["Only numeric apiVersion 2 is supported."] = "Unsupported export format. Export your gear again from WoW Sims.",
    ["Missing player object."] = "The export is missing character information.",
    ["Missing player.equipment object."] = "The export is missing gear. Include Gear when exporting from WoW Sims.",
    ["player.equipment.items must be an array."] = "The exported gear list is invalid. Export it again from WoW Sims.",
    ["player.class must be a class name or positive numeric identifier."] = "The export contains invalid class information.",
    ["Required recipe did not appear in the unfiltered profession list"] = "The required recipe is not available in your profession window",
    ["Resolved profession entry is not an executable recipe"] = "The required profession recipe cannot be used",
    ["The equipped target item or instance changed before application"] = "The equipped item changed; select it again",
}

function WSGS:FormatPlayerReason(reason)
    if not reason then
        return nil
    end
    if playerReasons[reason] then
        return playerReasons[reason]
    end
    for diagnostic, text in pairs(playerReasons) do
        local first, last = reason:find(diagnostic, 1, true)
        if first then
            reason = reason:sub(1, first - 1) .. text .. reason:sub(last + 1)
        end
    end
    return (reason:gsub("item (%d+) is ", function(itemID)
        return (C_Item.GetItemInfo(tonumber(itemID)) or "Target item") .. " is "
    end):gsub("Item (%d+) requested", function(itemID)
        return (C_Item.GetItemInfo(tonumber(itemID)) or "Target item") .. " requested"
    end):gsub("Associated set ID %d+", "The associated equipment set")
        :gsub("item state MISMATCH", "wrong item equipped")
        :gsub("item state UNKNOWN", "item information unavailable")
        :gsub("selected item instance is not equipped", "selected item is not equipped")
        :gsub("ambiguous duplicate instances", "duplicates that cannot be safely distinguished")
        :gsub("target slot%(s%) unresolved", "items still need attention")
        :gsub("Equipment Manager API error:", "Equipment Manager could not save the set:")
        :gsub("instance changed; rescan required", "item changed; try again")
        :gsub("combat lockdown", "combat")
        :gsub("could not stage the item", "could not select the item")
        :gsub("Item staging is unavailable", "Item selection is unavailable")
        :gsub("CraftEnchant failed:", "Crafting failed:"))
end
