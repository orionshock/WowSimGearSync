local _, WSGS = ...
local Execution = {}
WSGS.ProfessionEnhancementExecution = Execution

local function debug(category, text)
    WSGS:Debug("[ACTION][" .. category .. "] " .. text)
end

local function valueText(value)
    return value == nil and "nil" or tostring(value)
end

local function recipeIDFromLink(link)
    return tonumber(link and (link:match("|Henchant:(%d+)") or link:match("|Hspell:(%d+)")))
end

function Execution:Submit(controller, operation)
    CloseTradeSkill()
    debug("EXEC", string.format("slot=%d type=%s api=CastSpell profession=%s spellBookIndex=%d recipe=%s effect=%s",
        controller.inventorySlot, operation.type, operation.professionName, operation.professionSpellIndex,
        valueText(operation.spellID), valueText(operation.expected)))
    local opened, openProblem = pcall(CastSpell, operation.professionSpellIndex, BOOKTYPE_PROFESSION)
    if not opened then
        controller.failure = "Opening " .. operation.professionName .. " failed: " .. tostring(openProblem)
        return
    end
    local professionName = GetTradeSkillLine()
    if professionName ~= operation.professionName then
        controller.failure = operation.professionName .. " recipe data did not open during the click"
        debug("BLOCK", string.format("slot=%d type=%s recipe=%s profession=%s reason=%s",
            controller.inventorySlot, operation.type, valueText(operation.spellID),
            valueText(professionName), controller.failure))
        return
    end
    ExpandTradeSkillSubClass(0)
    local candidates = {}
    for _, spellID in ipairs(operation.recipeSpellIDs or { operation.spellID }) do candidates[spellID] = true end
    local recipeIndex, recipeSpellID
    for index = 1, GetNumTradeSkills() do
        local spellID = recipeIDFromLink(GetTradeSkillRecipeLink(index))
        if candidates[spellID] then
            recipeIndex, recipeSpellID = index, spellID
            break
        end
    end
    if not recipeIndex then
        controller.failure = "Required recipe is not learned, hidden, or unavailable in the profession list"
        debug("BLOCK", string.format("slot=%d type=%s recipe=%s reason=%s",
            controller.inventorySlot, operation.type, valueText(operation.spellID), controller.failure))
        return
    end
    operation.spellID = recipeSpellID
    operation.spellName = C_Spell.GetSpellName(recipeSpellID) or operation.spellName
    local _, skillType, numAvailable = GetTradeSkillInfo(recipeIndex)
    local missing = {}
    for reagentIndex = 1, GetTradeSkillNumReagents(recipeIndex) do
        local reagentName, _, required, carried = GetTradeSkillReagentInfo(recipeIndex, reagentIndex)
        if not carried or carried < required then
            missing[#missing + 1] = string.format("%s %s/%s", valueText(reagentName),
                valueText(carried), valueText(required))
        end
    end
    local tools = { GetTradeSkillTools(recipeIndex) }
    local missingTools = {}
    for index = 1, #tools, 2 do
        if tools[index + 1] == false then missingTools[#missingTools + 1] = valueText(tools[index]) end
    end
    local cooldown = GetTradeSkillCooldown(recipeIndex)
    debug("EXEC", string.format(
        "slot=%d type=%s profession=%s recipe=%d recipeIndex=%d available=%s reagents=%s tools=%s cooldown=%s",
        controller.inventorySlot, operation.type, operation.professionName, recipeSpellID, recipeIndex,
        valueText(numAvailable), #missing == 0 and "ready" or table.concat(missing, ";"),
        #missingTools == 0 and "ready" or table.concat(missingTools, ";"), valueText(cooldown)))
    if skillType == "header" or skillType == "subheader" then
        controller.failure = "Resolved profession entry is not an executable recipe"
        return
    elseif #missing > 0 then
        controller.failure = "Required recipe materials are unavailable: " .. table.concat(missing, ", ")
        return
    elseif #missingTools > 0 then
        controller.failure = "Required profession tool or location is unavailable: " .. table.concat(missingTools, ", ")
        return
    elseif type(cooldown) == "number" and cooldown > 0 then
        controller.failure = "Profession recipe is on cooldown"
        return
    elseif type(numAvailable) == "number" and numAvailable < 1 then
        controller.failure = "Profession recipe is not currently usable"
        return
    end
    SelectTradeSkill(recipeIndex)
    if GetTradeSkillSelectionIndex() ~= recipeIndex
        or recipeIDFromLink(GetTradeSkillRecipeLink(recipeIndex)) ~= recipeSpellID then
        controller.failure = "The expected profession recipe could not be selected"
        return
    end
    debug("EXEC", string.format("slot=%d type=%s api=DoTradeSkill recipe=%d recipeIndex=%d",
        controller.inventorySlot, operation.type, recipeSpellID, recipeIndex))
    local ok, problem = pcall(DoTradeSkill, recipeIndex, 1)
    local targeting = SpellCanTargetItem() or SpellCanTargetItemID()
    debug("EXEC", string.format("slot=%d type=%s api=DoTradeSkill returned=%s targeting=%s",
        controller.inventorySlot, operation.type, ok and "ok" or "error", targeting and "item" or "none"))
    if not ok then
        controller.failure = "DoTradeSkill failed: " .. tostring(problem)
    elseif not targeting then
        controller.failure = "DoTradeSkill did not begin item targeting"
    else
        debug("EXEC", string.format("slot=%d type=%s api=UseInventoryItem target-slot=%d guid=%s effect=%s",
            controller.inventorySlot, operation.type, controller.inventorySlot,
            valueText(controller.targetGuid), valueText(operation.expected)))
        local targeted, targetProblem = pcall(UseInventoryItem, controller.inventorySlot)
        local stillTargeting = SpellCanTargetItem() or SpellCanTargetItemID()
        debug("EXEC", string.format("slot=%d type=%s api=UseInventoryItem returned=%s targeting=%s",
            controller.inventorySlot, operation.type, targeted and "ok" or "error",
            stillTargeting and "item" or "none"))
        if not targeted then
            controller.failure = "Targeting equipped item failed: " .. tostring(targetProblem)
        elseif stillTargeting then
            controller.failure = "The client did not accept the equipped item target"
        end
    end
end

