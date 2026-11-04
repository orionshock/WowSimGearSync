local _, WSGS = ...
local Modules = WSGS.Private
local Internal = Modules.Enhancements
local Registry = {
    handlers = {}
}
Internal.Handlers = Registry
local MaterialCatalog = Modules.Enhancements.Catalog

-- Inventory-slot capabilities in execution order. The imported target and the
-- comparator decide whether work exists; this table only selects its handler.
Registry.SlotHandlers = {
    [1] = {"ItemEnhancement"},
    [2] = {"ItemEnhancement"},
    [3] = {"ItemEnhancement", "ProfessionEnhancement"},
    [5] = {"ItemEnhancement"},
    [6] = {"ItemEnhancement", "ProfessionEnhancement"},
    [7] = {"ItemEnhancement", "ProfessionEnhancement"},
    [8] = {"ItemEnhancement"},
    [9] = {"ItemEnhancement", "ProfessionEnhancement"},
    [10] = {"ItemEnhancement", "ProfessionEnhancement"},
    [11] = {"ItemEnhancement", "ProfessionEnhancement"},
    [12] = {"ItemEnhancement", "ProfessionEnhancement"},
    [13] = {"ItemEnhancement"},
    [14] = {"ItemEnhancement"},
    [15] = {"ItemEnhancement", "ProfessionEnhancement"},
    [16] = {"ItemEnhancement"},
    [17] = {"ItemEnhancement"}
}

function Registry:ForSlot(inventorySlot)
    return self.SlotHandlers[inventorySlot] or {}
end
