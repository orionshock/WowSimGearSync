local _, WSGS = ...
local Modules = WSGS.Private
local Import = WSGS:NewModule("Builds", "AceEvent-3.0")
Modules.Builds.Runtime = Import

local function importBuild(text)
    local document, reason = Modules.Builds.ExportV2:Deserialize(text)
    if not document then
        return nil, reason
    end
    local profile
    profile, reason = Modules.Builds.ExportV2:ValidateEquipment(document)
    if not profile then
        return nil, reason
    end
    profile.sourceJSON = text
    return Modules.Builds.ActiveBuild:SaveBuild(profile)
end

function WSGS.Builds:Import(text)
    WSGS:Debug("[IMPORT] Starting import")
    local profile, reason = importBuild(text)
    if not profile then
        WSGS:Debug("[IMPORT] Import failed: " .. reason)
        return nil, reason
    end
    WSGS:Debug("[IMPORT] API version: " .. profile.apiVersion)
    WSGS:Debug("[IMPORT] Equipment entries: " .. profile.metadata.entryCount)
    WSGS:Debug("[IMPORT] Profile saved: " .. profile.name)
    Import:SendMessage("WSGS_BUILD_IMPORTED", profile)
    return profile
end
