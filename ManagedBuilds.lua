local _, WSGS = ...
local Builds = {}
WSGS.ManagedBuilds = Builds

-- Own specialization identity, replacement and naming policy independently of UI/DB.
function Builds:Save(character, build)
    local spec = build.specialization
    if not spec or not spec.id or spec.class == "Unknown" then
        return nil, "Export must contain one recognizable specialization before importing."
    end
    local id = spec.class .. ":" .. spec.id
    local previous = character.simulationProfiles[id]
    build.id = id
    build.name = previous and previous.customName and previous.name or spec.name
    build.customName = previous and previous.customName or false
    build.metadata.importedAt = time()
    build.metadata.addonVersion = WSGS.version
    build.metadata.source = "WoW Sims API v3"
    character.simulationProfiles[id] = build
    character.latestSimulationProfileId = id
    return build
end

function Builds:Rename(character, id, name)
    local build = character.simulationProfiles[id]
    if not build then return nil, "Select a build before renaming." end
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil, "Build name cannot be empty." end
    if #name > 80 then return nil, "Build names must be at most 80 bytes." end
    build.name, build.customName = name, true
    return build
end
