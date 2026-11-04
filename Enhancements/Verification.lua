local _, WSGS = ...
local Modules = WSGS.Private
local Verification = {}
Modules.Enhancements.Verification = Verification

function Verification:Check(operation, difference, targetInstanceMatches)
    if not difference then
        return false, "comparison unavailable"
    end
    local itemState = difference.fields.item.state
    if itemState ~= "MATCH" and (itemState ~= "UNKNOWN" or not targetInstanceMatches) then
        return false, "target item no longer equipped"
    end
    local field = difference.fields[operation.field]
    if not field then
        return false, "comparison field unavailable"
    end
    local expected = operation.expected
    if field.expected ~= expected then
        return false, "comparison no longer describes the submitted expectation", field.actual
    end
    return field.state == "MATCH", field.state .. (field.reason and ": " .. field.reason or ""),
        field.actual
end
