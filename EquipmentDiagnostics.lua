local _, WSGS = ...
local Equipment = WSGS:GetModule("Equipment")
local labels = {
    item = "Item",
    enchant = "Enchant",
    tinker = "Tinker"
}

function WSGS:CompareLatestEquipment()
    local profile = self:GetActiveSimulationProfile()
    if not profile then
        self:Print("[COMPARE] Import a WoW Sims build before comparing equipment.")
        return
    end
    local state = Equipment:GetState(profile)
    local result, reason = state.comparison, state.reason
    if not result then
        self:Print("[COMPARE] " .. reason);
        return
    end
    local summary = result.summary
    self:Print("[COMPARE] Profile: " .. profile.name)
    self:Print("[COMPARE] Equipment matched: " .. summary.matched .. "/16")
    self:Print("[COMPARE] Item mismatches: " .. summary.itemMismatches)
    self:Print("[COMPARE] Configuration mismatches: " .. summary.configurationMismatches)
    self:Print("[COMPARE] Unknown observations: " .. summary.unknown .. " (required fields)")
    if self.db.profile.debug then
        for _, slot in ipairs(result.slots) do
            local prefix = string.format("[SLOT:%02d] ", slot.position)
            self:Debug(prefix .. slot.slotName .. " (inventory " .. slot.currentSlotId ..
                           (slot.currentPosition ~= slot.position and "; inferred pair assignment)" or ")"))
            for _, field in ipairs({"item", "enchant", "tinker"}) do
                local difference = slot.fields[field]
                local detail = difference.actual ~= nil and " (observed " .. tostring(difference.actual) .. ")" or ""
                if difference.source then
                    detail = detail .. " via " .. difference.source
                end
                if difference.progressState then
                    detail = detail .. " " .. difference.progressState
                end
                if difference.remaining then
                    detail = detail .. " remaining=" .. difference.remaining
                end
                if difference.reason then
                    detail = detail .. " - " .. difference.reason
                end
                self:Debug(prefix .. labels[field] .. ": " .. difference.state .. detail)
            end
        end
    end
    return result
end

-- Read-only raw evidence; no assumptions about colon-delimited modification fields.
function WSGS:ProbeEquipment(position)
    if not self.equipmentSlots[position] then
        self:Print("[PROBE] Use an export position from 1 to 16.");
        return
    end
    local state = Equipment:RefreshState(self:GetActiveSimulationProfile(), "ProbeEquipment")
    local current = state.equipped[position]
    self:Print("[PROBE] " .. current.slotName .. " inventory=" .. current.slotId .. " item=" .. tostring(current.id))
    self:Print("[PROBE] Raw link: " ..
                   (current.link and (current.link:match("|H(item:[^|]+)|h") or current.link) or "unavailable"))
    for _, field in ipairs({"enchant", "tinker"}) do
        local observed = current.observations[field]
        self:Print(
            "[PROBE] " .. (labels[field] or field) .. ": " .. observed.status .. " " .. tostring(observed.value) ..
                (self.db.profile.debug and observed.source and " via " .. observed.source or ""))
    end
    if current.observations.tinker.spellId then
        self:Print("[PROBE] Item use spell: " .. current.observations.tinker.spellId .. " " ..
                       tostring(current.observations.tinker.spellName))
    end
    self:Print("[PROBE] GUID: " .. current.observations.instance.status .. " " ..
                   tostring(current.observations.instance.value))
end
