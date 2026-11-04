local _, WSGS = ...
local Enchantment = {}
WSGS.ItemEnchantment = Enchantment

-- Retail exposes item identity through C_Item, but no permanent-enchant getter.
-- Only the enchantment field is read; the rest of the hyperlink is opaque.
function Enchantment:Observe(link)
    local raw = type(link) == "string" and link:match("|Hitem:%d+:([^:|]*):")
    if type(raw) ~= "string" or raw ~= "" and not raw:match("^%d+$") then
        return {status = "UNKNOWN", reason = "Permanent enchantment is unavailable in the item link"}
    end
    local enchantID = raw == "" and 0 or tonumber(raw)
    return {
        status = "KNOWN",
        value = enchantID,
        source = "Retail item hyperlink enchantment field"
    }
end
