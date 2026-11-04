local _, WSGS = ...
local Modules = WSGS.Private
Modules.Availability:Configure(
    function() return Modules.Equipment.Runtime:PendingCount() > 0 end,
    function() return Modules.Enhancements.Runtime.IsModificationPending() end)
