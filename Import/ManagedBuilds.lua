local _, WSGS = ...
local Import = WSGS.Import

function Import:SaveBuild(character, build)
    local specialization = build.specialization
    if not specialization or not specialization.id or specialization.class == "Unknown" then
        return nil, "Export must contain one recognizable specialization before importing."
    end
    build.name = specialization.name
    build.metadata.importedAt = time()
    build.metadata.addonVersion = WSGS.version
    build.metadata.source = "WoW Sims API v3"
    character.activeImport = build
    return build
end

function Import:RenameBuild(character, expectedBuild, name)
    local build = character.activeImport
    if not build or build ~= expectedBuild then
        return nil, "Select a build before renaming."
    end
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then
        return nil, "Build name cannot be empty."
    end
    if strlenutf8(name) > 16 then
        return nil, "Equipment set names must be at most 16 characters."
    end
    build.name = name
    WSGS:GetModule("Equipment"):InvalidateState("BUILD_RENAMED")
    return build
end
