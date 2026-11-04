local _, WSGS = ...
local Modules = WSGS.Private
local shirtSlot, tabardSlot = INVSLOT_BODY, INVSLOT_TABARD
local function shown(value) return value == nil and "nil" or tostring(value) end
local Store = WSGS:NewModule("EquipmentSetStorage", "AceEvent-3.0")
Modules.EquipmentSets.Store = Store
function Store:ReadInfo(setID)
    if type(setID) ~= "number" then
        return nil
    end
    local ok, name, icon, returnedID = pcall(C_EquipmentSet.GetEquipmentSetInfo, setID)
    if not ok or type(name) ~= "string" or returnedID ~= setID then
        return nil
    end
    return {
        id = setID,
        name = name,
        icon = icon
    }
end

function Store:ReadIgnoredSlots(setID)
    local ok, ignored = pcall(C_EquipmentSet.GetIgnoredSlots, setID)
    if not ok or type(ignored) ~= "table" then
        return nil, "saved ignored-slot state is unavailable"
    end
    if type(ignored[shirtSlot]) ~= "boolean" or type(ignored[tabardSlot]) ~= "boolean" then
        return nil, "saved Shirt or Tabard ignored state is incomplete"
    end
    return {
        [shirtSlot] = ignored[shirtSlot],
        [tabardSlot] = ignored[tabardSlot]
    }
end

local function captureSaveSelection()
    local ignored = {}
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        ignored[slot] = C_EquipmentSet.IsSlotIgnoredForSave(slot)
    end
    return ignored
end

local function configureManagedSlots(ignored)
    C_EquipmentSet.ClearIgnoredSlotsForSave()
    if ignored[shirtSlot] then
        C_EquipmentSet.IgnoreSlotForSave(shirtSlot)
    end
    if ignored[tabardSlot] then
        C_EquipmentSet.IgnoreSlotForSave(tabardSlot)
    end
end

local function restoreSaveSelection(ignored)
    C_EquipmentSet.ClearIgnoredSlotsForSave()
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        if ignored[slot] then
            C_EquipmentSet.IgnoreSlotForSave(slot)
        end
    end
end

function Store:Save(action, setID, name, icon, managedIgnored)
    local saveSelection = captureSaveSelection()
    self.active = {
        eventSeen = false,
        action = action,
        setID = setID,
        name = name
    }
    local ok, problem = pcall(function()
        configureManagedSlots(managedIgnored)
        if action == "CREATE" then
            C_EquipmentSet.CreateEquipmentSet(name, icon)
        else
            C_EquipmentSet.SaveEquipmentSet(setID, icon)
        end
    end)
    local restoreOK, restoreProblem = pcall(restoreSaveSelection, saveSelection)
    local eventSeen = self.active.eventSeen
    self.active = nil
    if not ok then
        return nil, tostring(problem), eventSeen
    end
    if not restoreOK then
        return nil, "Could not restore Equipment Manager ignored slots: " .. tostring(restoreProblem), eventSeen
    end
    return true, nil, eventSeen
end

function Store:EQUIPMENT_SETS_CHANGED()
    if self.active then
        self.active.eventSeen = true
        WSGS:Debug(string.format("[SET][VERIFY] build=%s setID=%s event=EQUIPMENT_SETS_CHANGED action=%s",
            shown(self.active.name), shown(self.active.setID), shown(self.active.action)))
    end
end

function Store:OnEnable()
    self:RegisterEvent("EQUIPMENT_SETS_CHANGED")
end
