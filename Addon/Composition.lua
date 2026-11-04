local _, WSGS = ...
local Modules = WSGS.Private
local Equipment = Modules.Equipment.Runtime
local Enhancements = Modules.Enhancements.Runtime

function Modules.Reconcile()
    local state = WSGS.Equipment:GetState()
    Equipment:Refresh(state)
    Enhancements:Refresh(state)
    WSGS:SendMessage("WSGS_STATE_CHANGED", state)
    return state
end
local Shopping = Modules.Shopping.Runtime
Shopping:AttachPanel(Modules.Views.CreateShoppingPanel({
    dismiss = function() Shopping:Dismiss() end,
    search = function(entry) Modules.Shopping.Navigation:Search(entry) end,
    changed = function() Shopping:QueueRefresh() end
}))
Modules.Availability:Configure(
    function() return Equipment:PendingCount() > 0 end,
    function() return Enhancements.IsModificationPending() end)
WSGS.Private = nil
