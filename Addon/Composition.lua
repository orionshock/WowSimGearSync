local _, WSGS = ...
local Modules = WSGS.Private
local Equipment = Modules.Equipment.Runtime
local Enhancements = Modules.Enhancements.Runtime
local Character = Modules.Character.Runtime
local Builds = Modules.Builds.ActiveBuild
local Views = Modules.Views.Runtime

function WSGS.Builds:GetActive() return Builds:Get() end
function WSGS.Builds:Import(text) return Modules.Builds.Runtime:ImportEquipment(text) end
function WSGS.Builds:Rename(expectedBuild, name)
    return Builds:RenameBuild(expectedBuild, name)
end
function WSGS.Character:Refresh(reason) return Character:Refresh(reason) end
function WSGS.Character:GetSnapshot() return Character:GetSnapshot() end
function WSGS.Character:Invalidate(reason) Character:Invalidate(reason) end
function WSGS.Character:RequestItemData(itemID, requester)
    return Modules.Character.ItemData:RequestItemData(itemID, requester)
end
function WSGS.Equipment:GetState(refreshReason)
    if refreshReason then return Equipment:RefreshState(Builds:Get(), refreshReason) end
    return Equipment:GetState(Builds:Get())
end
function WSGS.Equipment:GetSlotState(position)
    local _, reason, status = Equipment:GetSlotEquipPlan(position, Equipment:GetState(Builds:Get()))
    return {state = status, clickText = reason}
end
function WSGS.Equipment:GetStatus() return Equipment:GetStatus() end
function WSGS.Equipment:EquipAll()
    Equipment:Click()
    Modules.Reconcile()
end
function WSGS.Equipment:EquipSlot(position)
    Equipment:Click(position)
    Modules.Reconcile()
end
function WSGS.Enhancements:GetSlotState(position) return Enhancements:GetSlotState(position) end
function WSGS.Enhancements:BindSlot(position, button) Enhancements:RegisterSlotButton(position, button) end
function WSGS.Enhancements:ObserveEffect(slot, observed)
    return Modules.Enhancements.Catalog:ObserveEffect(slot, observed)
end
function WSGS.Enhancements:Resolve(effectID) return Modules.Enhancements.Catalog:Resolve(effectID) end
function WSGS.EquipmentSets:SaveVerified(state, report)
    return Modules.EquipmentSets.Runtime:Synchronize(Builds:Get(), state, report)
end
function WSGS.Views:ToggleEquipment() Views:TogglePaperDoll() end
function WSGS.Views:ToggleImport() Views:ToggleImportDialog() end
function WSGS.Views:RefreshEquipment() Views:RefreshPaperDoll() end

function Modules.ScheduleReconcile(reason)
    Equipment:QueueRefresh(reason)
end

function Modules.Reconcile()
    local state = Equipment:GetState(Builds:Get())
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
