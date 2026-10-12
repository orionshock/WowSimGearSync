local _, WSGS = ...
local Internal = WSGS.ActionsInternal or {}
WSGS.ActionsInternal = Internal

local Execution = {}
Internal.ProfessionExecution = Execution

local function debug(category, text)
    WSGS:Debug("[ACTION][" .. category .. "] " .. text)
end

local function valueText(value)
    return value == nil and "nil" or tostring(value)
end

local function recipeIDFromLink(link)
    return tonumber(link and (link:match("|Henchant:(%d+)") or link:match("|Hspell:(%d+)")))
end

local function result(status, reason)
    return {
        status = status,
        reason = reason
    }
end

local function failed(reason)
    return result("FAILED", reason)
end

local function unresolved(reason)
    return result("UNRESOLVED", reason)
end

local function openProfession(request, operation, profession, skillLine)
    CloseTradeSkill()
    debug("EXEC", string.format(
        "slot=%d handler=%s type=%s api=CastSpell profession=%s skillLine=%s spellBookIndex=%s recipe=%s effect=%s",
        request.inventorySlot, operation.handlerName, operation.type, profession.name, valueText(skillLine),
        valueText(profession.spellBookIndex), valueText(operation.spellID), valueText(operation.expected)))

    local opened, problem = pcall(CastSpell, profession.spellBookIndex, BOOKTYPE_PROFESSION)
    local openedProfession = GetTradeSkillLine()
    debug("EXEC", string.format("slot=%d type=%s api=CastSpell result=%s openedProfession=%s error=%s",
        request.inventorySlot, operation.type, opened and "ok" or "error", valueText(openedProfession),
        opened and "none" or valueText(problem)))
    if not opened then
        return nil, "Opening " .. profession.name .. " failed: " .. tostring(problem)
    end
    if openedProfession ~= profession.name then
        return nil, profession.name .. " recipe data did not open during the click"
    end
    return true
end

local function showAllRecipes(request, operation)
    local previousNameFilter = GetTradeSkillItemNameFilter()
    SetTradeSkillItemNameFilter("")
    for index = GetNumTradeSkills(), 1, -1 do
        local _, skillType, _, isExpanded = GetTradeSkillInfo(index)
        if skillType == "header" and not isExpanded then
            ExpandTradeSkillSubClass(index)
        end
    end
    debug("EXEC", string.format("slot=%d type=%s nameFilter=cleared previousName=%s entries=%d",
        request.inventorySlot, operation.type, valueText(previousNameFilter), GetNumTradeSkills()))
end

local function resolveRecipe(request, operation)
    showAllRecipes(request, operation)
    local candidates = {}
    for _, spellID in ipairs(operation.recipeSpellIDs or {operation.spellID}) do
        candidates[spellID] = true
    end
    for index = 1, GetNumTradeSkills() do
        local spellID = recipeIDFromLink(GetTradeSkillRecipeLink(index))
        if candidates[spellID] then
            return index, spellID
        end
    end
    return nil, nil, "Required recipe did not appear in the unfiltered profession list"
end

local function missingReagents(recipeIndex)
    local missing = {}
    for reagentIndex = 1, GetTradeSkillNumReagents(recipeIndex) do
        local name, _, required, carried = GetTradeSkillReagentInfo(recipeIndex, reagentIndex)
        if not carried or carried < required then
            missing[#missing + 1] = string.format("%s %s/%s", valueText(name), valueText(carried),
                valueText(required))
        end
    end
    return missing
end

local function missingTools(recipeIndex)
    local tools = {GetTradeSkillTools(recipeIndex)}
    local missing = {}
    for index = 1, #tools, 2 do
        if tools[index + 1] == false then
            missing[#missing + 1] = valueText(tools[index])
        end
    end
    return missing
end

local function inspectRecipe(request, operation, profession, recipeIndex, recipeSpellID)
    local spellName = C_Spell.GetSpellName(recipeSpellID) or operation.spellName
    local _, skillType, numAvailable = GetTradeSkillInfo(recipeIndex)
    local reagents = missingReagents(recipeIndex)
    local tools = missingTools(recipeIndex)
    local cooldown = GetTradeSkillCooldown(recipeIndex)
    debug("EXEC", string.format(
        "slot=%d type=%s profession=%s recipe=%d recipeIndex=%d available=%s reagents=%s tools=%s cooldown=%s",
        request.inventorySlot, operation.type, profession.name, recipeSpellID, recipeIndex, valueText(numAvailable),
        #reagents == 0 and "ready" or table.concat(reagents, ";"),
        #tools == 0 and "ready" or table.concat(tools, ";"), valueText(cooldown)))

    if skillType == "header" or skillType == "subheader" then
        return nil, "Resolved profession entry is not an executable recipe"
    end
    if #reagents > 0 then
        return nil, "Required recipe materials are unavailable: " .. table.concat(reagents, ", ")
    end
    if #tools > 0 then
        return nil, "Required profession tool or location is unavailable: " .. table.concat(tools, ", ")
    end
    if type(cooldown) == "number" and cooldown > 0 then
        return nil, "Profession recipe is on cooldown"
    end
    if type(numAvailable) == "number" and numAvailable < 1 then
        return nil, "Profession recipe is not currently usable"
    end
    if recipeIDFromLink(GetTradeSkillRecipeLink(recipeIndex)) ~= recipeSpellID then
        return nil, "The expected profession recipe changed before application"
    end
    return spellName
end

local function validateTarget(request)
    local itemID = GetInventoryItemID("player", request.inventorySlot)
    local guidOK, itemGUID = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromEquipmentSlot(request.inventorySlot))
    if itemID ~= request.targetItemID or not guidOK or itemGUID ~= request.targetGUID then
        return nil, "The equipped target item or instance changed before application"
    end
    return true
end

local function applyRecipe(request, operation, recipeIndex, recipeSpellID)
    debug("EXEC", string.format("slot=%d type=%s api=DoTradeSkill recipe=%d recipeIndex=%d", request.inventorySlot,
        operation.type, recipeSpellID, recipeIndex))
    local submitted, submitProblem = pcall(DoTradeSkill, recipeIndex, 1)
    local targeting = SpellCanTargetItem() or SpellCanTargetItemID()
    debug("EXEC", string.format("slot=%d type=%s api=DoTradeSkill returned=%s targeting=%s", request.inventorySlot,
        operation.type, submitted and "ok" or "error", targeting and "item" or "none"))
    if not submitted then
        return nil, "DoTradeSkill failed: " .. tostring(submitProblem)
    end
    if not targeting then
        return nil, "DoTradeSkill did not begin item targeting"
    end

    debug("EXEC", string.format("slot=%d type=%s api=UseInventoryItem target-slot=%d guid=%s effect=%s",
        request.inventorySlot, operation.type, request.inventorySlot, valueText(request.targetGUID),
        valueText(operation.expected)))
    local targeted, targetProblem = pcall(UseInventoryItem, request.inventorySlot)
    local stillTargeting = SpellCanTargetItem() or SpellCanTargetItemID()
    debug("EXEC", string.format("slot=%d type=%s api=UseInventoryItem returned=%s targeting=%s",
        request.inventorySlot, operation.type, targeted and "ok" or "error", stillTargeting and "item" or "none"))
    if not targeted then
        return nil, "Targeting equipped item failed: " .. tostring(targetProblem)
    end
    if stillTargeting then
        return nil, "The client did not accept the equipped item target"
    end
    return true
end

function Execution:Submit(request)
    local operation = request.operation
    local skillLine = operation.professionSkillLine
    local profession = WSGS.ModificationMaterials:GetProfession(skillLine)
    if not profession then
        return failed((WSGS.ModificationMaterials.professionNames[skillLine] or "Required profession") ..
                          " is unavailable")
    end
    if not profession.spellBookIndex then
        return failed(profession.name .. " profession spellbook action is unavailable")
    end

    local opened, problem = openProfession(request, operation, profession, skillLine)
    if not opened then
        return failed(problem)
    end
    local recipeIndex, recipeSpellID, recipeProblem = resolveRecipe(request, operation)
    if not recipeIndex then
        return unresolved(recipeProblem)
    end
    local spellName, inspectionProblem = inspectRecipe(request, operation, profession, recipeIndex, recipeSpellID)
    if not spellName then
        return failed(inspectionProblem)
    end
    local targetValid, targetProblem = validateTarget(request)
    if not targetValid then
        return failed(targetProblem)
    end
    local submitted, submitProblem = applyRecipe(request, operation, recipeIndex, recipeSpellID)
    if not submitted then
        return failed(submitProblem)
    end

    return {
        status = "SUBMITTED",
        spellID = recipeSpellID,
        spellName = spellName,
        professionName = profession.name,
        professionSpellIndex = profession.spellBookIndex,
        recipeIndex = recipeIndex,
        targetGUID = request.targetGUID
    }
end
