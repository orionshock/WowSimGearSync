local _, WSGS = ...
local Modules = WSGS.Private
local Import = WSGS:NewModule("Import", "AceEvent-3.0")
Modules.Builds.Runtime = Import

function Import:ImportInto(character, text)
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
    return Modules.Builds.ActiveBuild:SaveBuild(character, profile)
end

function Import:ImportEquipment(text)
    WSGS:Debug("[IMPORT] Starting import")
    local profile, reason = self:ImportInto(WSGS.db.char, text)
    if not profile then
        WSGS:Debug("[IMPORT] Import failed: " .. reason)
        return nil, reason
    end
    WSGS:Debug("[IMPORT] API version: " .. profile.apiVersion)
    WSGS:Debug("[IMPORT] Equipment entries: " .. profile.metadata.entryCount)
    WSGS:Debug("[IMPORT] Profile saved: " .. profile.name)
    self:SendMessage("WSGS_BUILD_IMPORTED", profile)
    return profile
end
