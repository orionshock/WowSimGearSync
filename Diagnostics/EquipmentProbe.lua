local _, WSGS = ...
local Equipment = WSGS.Equipment
local labels = {enchant = "Enchant", useSpell = "Item use spell"}

-- Read-only raw evidence; no assumptions about colon-delimited modification fields.
function WSGS:ProbeEquipment(position)
    if not WSGS.Equipment.Slots[position] then
        self:Print("[PROBE] Use an export position from 1 to 17.");
        return
    end
    local state = Equipment:GetState("ProbeEquipment")
    local current = state.equipped[position]
    self:Print("[PROBE] " .. current.slotName .. " inventory=" .. current.slotId .. " item=" .. tostring(current.id))
    self:Print("[PROBE] Raw link: " ..
                   (current.link and (current.link:match("|H(item:[^|]+)|h") or current.link) or "unavailable"))
    for _, field in ipairs({"enchant", "useSpell"}) do
        local observed = current.observations[field]
        self:Print(
            "[PROBE] " .. (labels[field] or field) .. ": " .. observed.status .. " " .. tostring(observed.value) ..
                (self.db.profile.debug and observed.source and " via " .. observed.source or ""))
    end
    if current.observations.useSpell.spellId then
        self:Print("[PROBE] Item use spell: " .. current.observations.useSpell.spellId .. " " ..
                       tostring(current.observations.useSpell.spellName))
    end
    self:Print("[PROBE] GUID: " .. current.observations.instance.status .. " " ..
                   tostring(current.observations.instance.value))
end
