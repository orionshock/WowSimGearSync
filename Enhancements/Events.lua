local _, WSGS = ...
local Modules = WSGS.Private
local Events = WSGS:NewModule("EnhancementEvents", "AceEvent-3.0")
Modules.Enhancements.Events = Events
local context
function Events:Configure(callbacks) context = callbacks end
local function debug(category, text) WSGS:Debug("[ACTION][" .. category .. "] " .. text) end
local function valueText(value) return value == nil and "nil" or tostring(value) end

local function activeState()
    context.synchronizeBuild()
    local active, submitting
    for _, controller in pairs(context.controllers()) do
        if controller.state == "PENDING" or controller.submitting then
            active = true
        end
        if controller.submitting then
            submitting = true
        end
    end
    return active, submitting
end

local function logEvent(event, ...)
    local args = {}
    for index = 1, select("#", ...) do
        args[index] = valueText(select(index, ...))
    end
    debug("EVENT", string.format("event=%s args=%s", event, table.concat(args, ",")))
end

local function finishEvent(self, event, submitting, ...)
    logEvent(event, ...)
    if submitting then
        return
    end
    context.refresh(event)
end

local function handleActiveEvent(self, event, ...)
    local active, submitting = activeState()
    if not active then
        return
    end
    finishEvent(self, event, submitting, ...)
end

function Events:PLAYER_EQUIPMENT_CHANGED(event, inventorySlot, ...)
    local active, submitting = activeState()
    if not active then
        return
    end
    local relevant
    for _, controller in pairs(context.controllers()) do
        if (controller.pending or controller.submitting) and controller.inventorySlot == inventorySlot then
            relevant = true
            break
        end
    end
    if not relevant then
        return
    end
    finishEvent(self, event, submitting, inventorySlot, ...)
end

function Events:BAG_UPDATE_DELAYED(event, ...)
    handleActiveEvent(self, event, ...)
end

function Events:ITEM_LOCK_CHANGED(event, ...)
    handleActiveEvent(self, event, ...)
end

function Events:TRADE_SKILL_SHOW(event, ...)
    handleActiveEvent(self, event, ...)
end

function Events:TRADE_SKILL_LIST_UPDATE(event, ...)
    handleActiveEvent(self, event, ...)
end

function Events:PLAYER_REGEN_ENABLED(event, ...)
    handleActiveEvent(self, event, ...)
end

function Events:UNIT_SPELLCAST_SENT(event, unit, target, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    context.synchronizeBuild()
    for _, controller in pairs(context.controllers()) do
        local operation = controller.submitting
        if operation then
            local matches = operation.spellID == spellID
            if matches then
                operation.castGUID = castGUID
            end
        end
    end
end

local function handleSpellcastResult(self, event, failed, unit, castGUID, spellID, ...)
    local active, submitting = activeState()
    if not active or unit ~= "player" then
        return
    end
    local relevant, tradeSkillClosed
    for _, controller in pairs(context.controllers()) do
        local operation = controller.pending or controller.submitting
        if operation and operation.castGUID and operation.spellID == spellID and operation.castGUID == castGUID then
            relevant = true
            if failed then
                controller.failure = "Client spell cast failed or was interrupted"
            elseif not tradeSkillClosed and operation.nativeProfession and TradeSkillFrame and
                TradeSkillFrame:IsShown() then
                HideUIPanel(TradeSkillFrame)
                tradeSkillClosed = true
                debug("EVENT", string.format("event=%s slot=%d type=%s profession=%s tradeskill=closed", event,
                    controller.inventorySlot, operation.type, operation.professionName))
            end
        end
    end
    if not relevant then
        return
    end
    finishEvent(self, event, submitting, unit, castGUID, spellID, ...)
end

function Events:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID, ...)
    handleSpellcastResult(self, event, false, unit, castGUID, spellID, ...)
end

function Events:UNIT_SPELLCAST_FAILED(event, unit, castGUID, spellID, ...)
    handleSpellcastResult(self, event, true, unit, castGUID, spellID, ...)
end

function Events:UNIT_SPELLCAST_INTERRUPTED(event, unit, castGUID, spellID, ...)
    handleSpellcastResult(self, event, true, unit, castGUID, spellID, ...)
end

local function confirmApplication(self, event, api, ...)
    local active = activeState()
    if not active then
        return
    end
    local controller, operation
    for _, candidate in pairs(context.controllers()) do
        local candidateOperation = candidate.submitting
        if candidateOperation then
            controller, operation = candidate, candidateOperation
            break
        end
    end
    if not operation then
        return
    end
    logEvent(event, ...)
    local ok, problem = pcall(api)
    if ok then
        StaticPopup_Hide(event)
    end
    debug("EVENT", string.format("event=%s slot=%d type=%s confirm=%s", event, controller.inventorySlot,
        operation.type, ok and "accepted" or "failed"))
    if not ok then
        controller.failure = event .. " confirmation failed: " .. tostring(problem)
    end
end

function Events:REPLACE_ENCHANT(event, ...)
    confirmApplication(self, event, C_Item.ReplaceEnchant, ...)
end

function Events:BIND_ENCHANT(event, ...)
    confirmApplication(self, event, C_Item.BindEnchant, ...)
end

function Events:ACTION_WILL_BIND_ITEM(event, ...)
    confirmApplication(self, event, C_Item.ActionBindsItem, ...)
end

function Events:WSGS_EQUIPMENT_STATE_INVALIDATED(_, event, ...)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        self:PLAYER_EQUIPMENT_CHANGED(event, ...)
    elseif event == "BAG_UPDATE_DELAYED" then
        self:BAG_UPDATE_DELAYED(event, ...)
    elseif event == "ITEM_LOCK_CHANGED" then
        self:ITEM_LOCK_CHANGED(event, ...)
    end
end

function Events:WSGS_BUILD_IMPORTED()
    context.synchronizeBuild()
end

function Events:OnEnable()
    self:RegisterMessage("WSGS_EQUIPMENT_STATE_INVALIDATED")
    self:RegisterMessage("WSGS_BUILD_IMPORTED")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:RegisterEvent("UNIT_SPELLCAST_SENT")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:RegisterEvent("TRADE_SKILL_SHOW")
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    self:RegisterEvent("REPLACE_ENCHANT")
    self:RegisterEvent("BIND_ENCHANT")
    self:RegisterEvent("ACTION_WILL_BIND_ITEM")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end
