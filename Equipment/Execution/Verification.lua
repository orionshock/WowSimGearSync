local _, WSGS = ...
local Modules = WSGS.Private
local Verification = {}
Modules.Equipment.Verification = Verification
function Verification:Check(operation, snapshot, bags)
    local destination = snapshot.slots[operation.position]
    if operation.kind == "UNEQUIP" then
        if destination.observations.item.status ~= "KNOWN" then
            return false, "destination identity is unknown", destination
        end
        if destination.id then
            return false, "destination is not empty", destination
        end
        for _, item in ipairs(bags.items) do
            if item.bag == operation.destination.bag and item.bagSlot == operation.destination.bagSlot then
                return item.guid == operation.source.guid,
                    item.guid == operation.source.guid and
                        "destination is empty and intended instance is in the planned bag slot" or
                        "planned bag slot contains a different instance", destination
            end
        end
        return false, "planned bag destination is empty or unreadable", destination
    end
    if destination.id ~= operation.id then
        return false, "observed item ID does not match target", destination
    end
    return destination.guid == operation.source.guid,
        destination.guid == operation.source.guid and "observed item ID and instance match target" or
            "observed item ID matches but instance GUID does not", destination
end

function Verification:UnexpectedDestination(record, snapshot)
    local operation = record.operation
    if operation.kind == "UNEQUIP" then
        return false
    end
    local destination = snapshot.slots[operation.position]
    if destination.id and destination.id ~= record.beforeId and destination.id ~= operation.id then
        return true
    end
    return operation.source.guid and destination.id == operation.id and destination.guid and destination.guid ~=
               operation.source.guid and destination.guid ~= record.beforeGUID
end

