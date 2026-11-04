local _, WSGS = ...
local Internal = WSGS.ActionsInternal or {}
WSGS.ActionsInternal = Internal
local Execution = {}
Internal.ProfessionExecution = Execution

local function result(status, reason)
    return {status = status, reason = reason}
end

-- Protected crafting stays inside the slot's hardware click. Loading a
-- profession never queues a craft: the player clicks again once data is ready.
function Execution:Submit(request)
    local operation = request.operation
    local skillLine = operation.professionSkillLine
    local profession = WSGS.Professions:GetProfession(skillLine)
    if not profession then
        return result("FAILED", "Required profession is unavailable")
    end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    if not base or base.professionID ~= skillLine then
        local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
        if not ok or not opened then
            return result("FAILED", "Could not open " .. profession.name)
        end
    end
    if not C_TradeSkillUI.IsTradeSkillReady() then
        return result("UNRESOLVED", "Profession recipes are loading; click again when ready")
    end
    base = C_TradeSkillUI.GetBaseProfessionInfo()
    if not base or base.professionID ~= skillLine then
        return result("UNRESOLVED", "Required profession recipes are not available yet")
    end
    local info = C_TradeSkillUI.GetRecipeInfo(operation.spellID)
    if not info then
        return result("UNRESOLVED", "Recipe information is not available yet")
    end
    if not info.learned then
        return result("FAILED", "Required profession recipe is not learned")
    end
    if info.disabled or not info.craftable then
        return result("FAILED", info.disabledReason or "Profession recipe is not currently usable")
    end
    local schematic = C_TradeSkillUI.GetRecipeSchematic(info.recipeID, false)
    if schematic.recipeType ~= Enum.TradeskillRecipeType.Enchant then
        return result("FAILED", "Recipe does not apply an equipment enhancement")
    end
    local cooldown, _, charges = C_TradeSkillUI.GetRecipeCooldown(info.recipeID)
    if cooldown and cooldown > 0 and charges == 0 then
        return result("FAILED", "Profession recipe is on cooldown")
    end
    for _, requirement in ipairs(C_TradeSkillUI.GetRecipeRequirements(info.recipeID)) do
        if not requirement.met then
            return result("FAILED", "Required profession tool or location is unavailable")
        end
    end
    if C_TradeSkillUI.GetCraftableCount(info.recipeID) < 1 then
        return result("FAILED", "Required recipe materials are unavailable")
    end
    -- Quality and optional reagent allocation belongs to Blizzard's crafting UI.
    -- The catalog contains only direct enhancements without those allocations.
    if info.supportsQualities then
        return result("FAILED", "Choose reagent quality in the profession window")
    end
    local location = ItemLocation:CreateFromEquipmentSlot(request.inventorySlot)
    if not C_Item.DoesItemExist(location) or C_Item.GetItemID(location) ~= request.targetItemID or
        C_Item.GetItemGUID(location) ~= request.targetGUID then
        return result("FAILED", "The equipped target item or instance changed before application")
    end
    local acceptsTarget = false
    for _, guid in ipairs(C_TradeSkillUI.GetEnchantItems(info.recipeID)) do
        if guid == request.targetGUID then
            acceptsTarget = true
            break
        end
    end
    if not acceptsTarget then
        return result("FAILED", "Profession recipe cannot enhance this equipped item")
    end
    WSGS:Debug(string.format(
        "[ACTION][EXEC] slot=%d type=%s api=C_TradeSkillUI.CraftEnchant recipe=%d guid=%s",
        request.inventorySlot, operation.type, info.recipeID, request.targetGUID))
    local ok, problem = pcall(C_TradeSkillUI.CraftEnchant, info.recipeID, 1, nil, location)
    if not ok then
        return result("FAILED", "CraftEnchant failed: " .. tostring(problem))
    end
    return {
        status = "SUBMITTED",
        spellID = info.recipeID,
        spellName = info.name,
        professionName = profession.name,
        targetGUID = request.targetGUID
    }
end
