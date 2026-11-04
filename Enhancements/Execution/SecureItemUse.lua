local _, WSGS = ...
local Modules = WSGS.Private
local Secure = {}
Modules.Enhancements.SecureItemUse = Secure

-- Owns secure attributes and validation of the exact carried material. It does
-- not own application progress or interpret spellcast events.
function Secure:Configure(button, controller)
    if not button or InCombatLockdown() then return end
    local operation = controller and controller.state == "READY" and controller.prepared
    local actionType = operation and not operation.nativeProfession and "item" or nil
    button:SetAttribute("wsgs-type1", actionType)
    button:SetAttribute("type1", actionType)
    button:SetAttribute("item1", actionType and operation.material and
        string.format("%d %d", operation.material.bag, operation.material.bagSlot) or nil)
    button:SetAttribute("target-slot1", actionType and controller.inventorySlot or nil)
end

function Secure:Prepare(controller, operation, button)
    local material = operation.material
    if not material then return nil, "Prepared material location is unavailable" end
    local current = C_Container.GetContainerItemInfo(material.bag, material.bagSlot)
    if not current or current.itemID ~= material.id or current.isLocked then
        return nil, "Prepared material moved or became locked"
    end
    local location = ItemLocation:CreateFromBagAndSlot(material.bag, material.bagSlot)
    if C_Item.GetItemGUID(location) ~= material.guid then
        return nil, "Prepared material instance moved; rescan before retrying"
    end
    self:Configure(button, controller)
    local item = string.format("%d %d", material.bag, material.bagSlot)
    if button:GetAttribute("type1") ~= "item" or
        button:GetAttribute("target-slot1") ~= controller.inventorySlot or
        button:GetAttribute("item1") ~= item then
        return nil, "Secure action could not be prepared"
    end
    return true
end
