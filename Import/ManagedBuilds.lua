local _, WSGS = ...
local Import = WSGS.Import

function Import:SaveBuild(character, build)
    local specialization = build.specialization
    if not specialization or not specialization.id or specialization.class == "Unknown" then
        return nil, "Export must contain one recognizable specialization before importing."
    end
    local id = specialization.class .. ":" .. specialization.id
    local previous = character.simulationProfiles[id]
    build.id = id
    build.name = previous and previous.customName and previous.name or specialization.name
    build.customName = previous and previous.customName or false
    build.equipmentSetID = previous and previous.equipmentSetID or nil
    build.equipmentSetName = previous and previous.equipmentSetName or nil
    build.metadata.importedAt = time()
    build.metadata.addonVersion = WSGS.version
    build.metadata.source = "WoW Sims API v3"
    character.simulationProfiles[id] = build
    character.latestSimulationProfileId = id
    return build
end

function Import:RenameBuild(character, id, name)
    local build = character.simulationProfiles[id]
    if not build then
        return nil, "Select a build before renaming."
    end
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then
        return nil, "Build name cannot be empty."
    end
    if #name > 80 then
        return nil, "Build names must be at most 80 bytes."
    end
    build.name, build.customName = name, true
    return build
end
