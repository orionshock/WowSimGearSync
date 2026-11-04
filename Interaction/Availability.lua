local _, WSGS = ...
local Modules = WSGS.Private
local Availability = {}
Modules.Availability = Availability
function Availability:Configure(equipmentPending, enhancementPending)
    self.equipmentPending, self.enhancementPending = equipmentPending, enhancementPending
end
function Availability:Reason()
    if InCombatLockdown() or UnitAffectingCombat("player") then
        return "Action unavailable during combat lockdown", "COMBAT"
    end
    if GetCursorInfo() then return "Place the held cursor item first", "CURSOR" end
    if SpellIsTargeting() then return "Finish or cancel the active item targeting first", "BLOCKED" end
    if self.equipmentPending() then return "Waiting for equipment to update", "PENDING" end
    if self.enhancementPending() then return "Finish the active modification first", "PENDING" end
end
