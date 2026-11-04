local _, WSGS = ...
local Modules = WSGS.Private
local Planner = {}
Modules.Equipment.Planning = Planner
local function captureInputs(state, selectedPosition)
    local context = {
        state = state,
        selectedPosition = selectedPosition,
        snapshot = {
            slots = state.equipped,
            context = state.context
        },
        inventory = state.bags,
        comparison = state.comparison,
        candidates = {},
        used = {},
        targetGroups = {},
        plan = {
            operations = {},
            missing = {},
            blocked = {},
            assignments = {},
            unresolvedCount = 0
        }
    }
    if context.comparison then
        for _, slot in ipairs(context.comparison.slots) do
            if slot.fields.item.state ~= "MATCH" then
                context.plan.unresolvedCount = context.plan.unresolvedCount + 1
            end
        end
    end
    return context
end

function Planner:Plan(state, selectedPosition)
    local context = captureInputs(state, selectedPosition)
    if not context.comparison then
        context.plan.blocked[1] = state.reason
        return context.plan
    end
    Modules.Equipment.InstanceAssignment:Apply(context)
    Modules.Equipment.BagDestinations:Apply(context)
    Modules.Equipment.WeaponLayout:Apply(context)
    return context.plan
end
