local _, WSGS = ...
local Modules = WSGS.Private
local Equipment = WSGS.Equipment
local labels = {
    item = "Item",
    enchant = "Enchant",
    tinker = "Tinker",
    useSpell = "Item use spell"
}

function WSGS:CompareLatestEquipment()
    local profile = WSGS.Builds:GetActive()
    if not profile then
        self:Print("[COMPARE] Import a WoW Sims build before comparing equipment.")
        return
    end
    local state = Equipment:GetState()
    local result, reason = state.comparison, state.reason
    if not result then
        self:Print("[COMPARE] " .. reason);
        return
    end
    local summary = result.summary
    self:Print("[COMPARE] Profile: " .. profile.name)
    self:Print("[COMPARE] Equipment matched: " .. summary.matched .. "/" .. #WSGS.Equipment.Slots)
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
