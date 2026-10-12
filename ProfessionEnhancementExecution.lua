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

local function fail(controller, operation, reason)
    controller.failure = reason
    debug("BLOCK", string.format("slot=%d handler=%s type=%s recipe=%s reason=%s", controller.inventorySlot,
        operation.handlerName or "unknown", operation.type, valueText(operation.spellID), reason))
end

function Execution:Submit(controller, operation)
    local skillLine = operation.professionSkillLine
    local profession = WSGS.ModificationMaterials:GetProfession(skillLine)
    if not profession then
        fail(controller, operation,
            (WSGS.ModificationMaterials.professionNames[skillLine] or "Required profession") .. " is unavailable")
        return
    end
    if not profession.spellBookIndex then
        fail(controller, operation, profession.name .. " profession spellbook action is unavailable")
        return
    end

    operation.professionName = profession.name
    operation.professionSpellIndex = profession.spellBookIndex
    CloseTradeSkill()
    debug("EXEC", string.format(
        "slot=%d handler=%s type=%s api=CastSpell profession=%s skillLine=%s spellBookIndex=%s recipe=%s effect=%s",
        controller.inventorySlot, operation.handlerName, operation.type, profession.name, valueText(skillLine),
        valueText(profession.spellBookIndex), valueText(operation.spellID), valueText(operation.expected)))

    local opened, openProblem = pcall(CastSpell, profession.spellBookIndex, BOOKTYPE_PROFESSION)
    local openedProfession = GetTradeSkillLine()
    debug("EXEC",
        string.format("slot=%d type=%s api=CastSpell result=%s openedProfession=%s error=%s", controller.inventorySlot,
            operation.type, opened and "ok" or "error", valueText(openedProfession),
            opened and "none" or valueText(openProblem)))
    if not opened then
        fail(controller, operation, "Opening " .. profession.name .. " failed: " .. tostring(openProblem))
        return
    end
    if openedProfession ~= profession.name then
        fail(controller, operation, profession.name .. " recipe data did not open during the click")
        return
    end

    ExpandTradeSkillSubClass(0)
    local candidates = {}
    for _, spellID in ipairs(operation.recipeSpellIDs or {operation.spellID}) do
        candidates[spellID] = true
    end
    local recipeIndex, recipeSpellID
    for index = 1, GetNumTradeSkills() do
        local spellID = recipeIDFromLink(GetTradeSkillRecipeLink(index))
        if candidates[spellID] then
            recipeIndex, recipeSpellID = index, spellID
            break
        end
    end
    if not recipeIndex then
        fail(controller, operation, "Required recipe is not learned, hidden, or unavailable in the profession list")
        return
    end

    operation.spellID = recipeSpellID
    operation.spellName = C_Spell.GetSpellName(recipeSpellID) or operation.spellName
    local _, skillType, numAvailable = GetTradeSkillInfo(recipeIndex)
    local missing = {}
    for reagentIndex = 1, GetTradeSkillNumReagents(recipeIndex) do
        local reagentName, _, required, carried = GetTradeSkillReagentInfo(recipeIndex, reagentIndex)
        if not carried or carried < required then
            missing[#missing + 1] = string.format("%s %s/%s", valueText(reagentName), valueText(carried),
                valueText(required))
        end
    end
    local tools, missingTools = {GetTradeSkillTools(recipeIndex)}, {}
    for index = 1, #tools, 2 do
        if tools[index + 1] == false then
            missingTools[#missingTools + 1] = valueText(tools[index])
        end
    end
    local cooldown = GetTradeSkillCooldown(recipeIndex)
    debug("EXEC",
        string.format(
            "slot=%d type=%s profession=%s recipe=%d recipeIndex=%d available=%s reagents=%s tools=%s cooldown=%s",
            controller.inventorySlot, operation.type, profession.name, recipeSpellID, recipeIndex,
            valueText(numAvailable), #missing == 0 and "ready" or table.concat(missing, ";"),
            #missingTools == 0 and "ready" or table.concat(missingTools, ";"), valueText(cooldown)))

    if skillType == "header" or skillType == "subheader" then
        fail(controller, operation, "Resolved profession entry is not an executable recipe")
        return
    end
    if #missing > 0 then
        fail(controller, operation, "Required recipe materials are unavailable: " .. table.concat(missing, ", "))
        return
    end
    if #missingTools > 0 then
        fail(controller, operation,
            "Required profession tool or location is unavailable: " .. table.concat(missingTools, ", "))
        return
    end
    if type(cooldown) == "number" and cooldown > 0 then
        fail(controller, operation, "Profession recipe is on cooldown")
        return
    end
    if type(numAvailable) == "number" and numAvailable < 1 then
        fail(controller, operation, "Profession recipe is not currently usable")
        return
    end
    if recipeIDFromLink(GetTradeSkillRecipeLink(recipeIndex)) ~= recipeSpellID then
        fail(controller, operation, "The expected profession recipe changed before application")
        return
    end
    local itemID = GetInventoryItemID("player", controller.inventorySlot)
    local guidOK, itemGUID = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromEquipmentSlot(controller.inventorySlot))
    if itemID ~= controller.target.id or not guidOK or itemGUID ~= controller.targetGuid then
        fail(controller, operation, "The equipped target item or instance changed before application")
        return
    end

    debug("EXEC",
        string.format("slot=%d type=%s api=DoTradeSkill recipe=%d recipeIndex=%d", controller.inventorySlot,
            operation.type, recipeSpellID, recipeIndex))
    local submitted, submitProblem = pcall(DoTradeSkill, recipeIndex, 1)
    local targeting = SpellCanTargetItem() or SpellCanTargetItemID()
    debug("EXEC",
        string.format("slot=%d type=%s api=DoTradeSkill returned=%s targeting=%s", controller.inventorySlot,
            operation.type, submitted and "ok" or "error", targeting and "item" or "none"))
    if not submitted then
        fail(controller, operation, "DoTradeSkill failed: " .. tostring(submitProblem))
        return
    end
    if not targeting then
        fail(controller, operation, "DoTradeSkill did not begin item targeting")
        return
    end

    debug("EXEC",
        string.format("slot=%d type=%s api=UseInventoryItem target-slot=%d guid=%s effect=%s", controller.inventorySlot,
            operation.type, controller.inventorySlot, valueText(controller.targetGuid), valueText(operation.expected)))
    local targeted, targetProblem = pcall(UseInventoryItem, controller.inventorySlot)
    local stillTargeting = SpellCanTargetItem() or SpellCanTargetItemID()
    debug("EXEC",
        string.format("slot=%d type=%s api=UseInventoryItem returned=%s targeting=%s", controller.inventorySlot,
            operation.type, targeted and "ok" or "error", stillTargeting and "item" or "none"))
    if not targeted then
        fail(controller, operation, "Targeting equipped item failed: " .. tostring(targetProblem))
        return
    end
    if stillTargeting then
        fail(controller, operation, "The client did not accept the equipped item target")
        return
    end
end
