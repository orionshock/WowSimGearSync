local _, WSGS = ...
local function decode()
    local document = C_EncodingUtil.DeserializeJSON(WSGS.Tests.referenceJSON)
    assert(type(document) == "table", "Native JSON decoder did not return a document")
    return document
end
WSGS.Tests:Register("importer", "Importer", {
    { name = "Native JSON decoder and Paladin reference", run = function()
        local profile = assert(WSGS:ValidateEquipment(decode()))
        assert(#profile.equipment == 16 and profile.metadata.entryCount == 16)
        assert(profile.specialization.name == "Protection" and profile.specialization.id == 66)
        assert(profile.equipment[3].id == 99027 and profile.equipment[7].enchant == 4430
            and profile.equipment[7].tinker == 4898)
    end },
    { name = "Gear-only normalization does not save builds", run = function()
        local document = decode()
        document.player.rotation, document.raidBuffs = { type = "TypeAPL" }, { bloodlust = true }
        document.player.talentsString = "313232"
        local before, latest = 0, WSGS.db.char.latestSimulationProfileId
        for _ in pairs(WSGS.db.char.simulationProfiles) do before = before + 1 end
        local profile = assert(WSGS:ValidateEquipment(document))
        assert(not profile.rotation and not profile.raidBuffs and not profile.talentsString and not profile.player)
        local after = 0
        for _ in pairs(WSGS.db.char.simulationProfiles) do after = after + 1 end
        assert(before == after and latest == WSGS.db.char.latestSimulationProfileId)
    end },
    { name = "Optional fields, empty positions and duplicate IDs", run = function()
        local document = decode()
        document.player.equipment.items = { {id=99027}, {}, {id=99027,gems={76699,0}} }
        local profile = assert(WSGS:ValidateEquipment(document))
        assert(profile.equipment[1].id == profile.equipment[3].id and profile.equipment[2].empty)
        assert(profile.equipment[3].gems[2] == 0 and profile.equipment[16].empty)
    end },
    { name = "Invalid version, schema and modifications rejected", run = function()
        local document = decode()
        document.apiVersion = 4
        assert(not WSGS:ValidateEquipment(document))
        assert(not WSGS:ValidateEquipment({ apiVersion=3, player={class="ClassPaladin"} }))
        document = decode()
        document.player.equipment.items[1].id = "99029"
        assert(not WSGS:ValidateEquipment(document))
        document = decode()
        document.player.equipment.items[1].gems = "bad"
        assert(not WSGS:ValidateEquipment(document))
    end },
    { name = "Malformed JSON cannot become equipment", run = function()
        -- The native decoder may return a table for malformed input. A table
        -- alone is not an equipment build: use the production schema validator.
        local character = WSGS.db.char
        local builds, latest = character.simulationProfiles, character.latestSimulationProfileId
        local before = {}
        for id, build in pairs(builds) do before[id] = build end
        local ok, document = pcall(C_EncodingUtil.DeserializeJSON, "{broken")
        if ok then
            local build, reason = WSGS:ValidateEquipment(document)
            assert(not build and reason, "Malformed JSON validated as equipment")
        end
        -- Do not call ImportEquipment: this test exercises its decode/validate
        -- path without entering the save stage or substituting a database.
        assert(character.simulationProfiles == builds and character.latestSimulationProfileId == latest,
            "Import tracking changed")
        for id, build in pairs(builds) do assert(before[id] == build, "Build added or replaced") end
        for id, build in pairs(before) do assert(builds[id] == build, "Build removed or replaced") end
    end },
    { name = "Unknown item fields retained", run = function()
        local document = decode()
        document.player.equipment.items[1].futureModification = { value = 12 }
        local profile = assert(WSGS:ValidateEquipment(document))
        assert(profile.equipment[1].extraFields.futureModification.value == 12)
        assert(#profile.metadata.warnings > 0)
    end },
    { name = "Missing and ambiguous specialization stay unspecified", run = function()
        local document = decode()
        document.player.protectionPaladin = nil
        assert(not assert(WSGS:ValidateEquipment(document)).specialization.id)
        document.player.protectionPaladin, document.player.retributionPaladin = {}, {}
        assert(not assert(WSGS:ValidateEquipment(document)).specialization.id)
    end },
    { name = "First import creates and selects a specialization build", run = function()
        local character = { simulationProfiles = {} }
        local build = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
        assert(build.id == "Paladin:66" and build.name == "Protection")
        assert(character.simulationProfiles[build.id] == build and character.latestSimulationProfileId == build.id)
    end },
    { name = "Reimport replaces equipment without duplicate builds", run = function()
        local character = { simulationProfiles = {} }
        local first = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
        local json = WSGS.Tests.referenceJSON:gsub('"id":99029', '"id":100584')
        local second = assert(WSGS:ImportInto(character, json))
        assert(first ~= second and first.id == second.id and second.equipment[1].id == 100584)
        local count = 0
        for _ in pairs(character.simulationProfiles) do count = count + 1 end
        assert(count == 1)
    end },
    { name = "Committed custom name survives reimport", run = function()
        local character = { simulationProfiles = {} }
        local first = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
        assert(WSGS.ManagedBuilds:Rename(character, first.id, "  Raid tank  "))
        local second = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
        assert(second.name == "Raid tank" and second.customName and second.specialization.id == 66)
    end },
    { name = "Different specializations keep separate managed builds", run = function()
        local character = { simulationProfiles = {} }
        local first = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
        local second = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON:gsub("protectionPaladin", "retributionPaladin")))
        assert(first.id ~= second.id and character.simulationProfiles[first.id] == first)
        assert(second.id == "Paladin:70" and second.name == "Retribution")
    end },
    { name = "Invalid import preserves existing managed build and selection", run = function()
        local character = { simulationProfiles = {} }
        local first = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
        local result, reason = WSGS:ImportInto(character, "{broken")
        assert(not result and reason and character.simulationProfiles[first.id] == first)
        assert(character.latestSimulationProfileId == first.id)
    end },
    { name = "Unknown or ambiguous specialization cannot replace builds", run = function()
        local character = { simulationProfiles = {} }
        local first = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
        for _, source in ipairs({ "missing", "ambiguous" }) do
            local document = decode()
            if source == "missing" then document.player.protectionPaladin = nil
            else document.player.retributionPaladin = {} end
            local candidate = assert(WSGS:ValidateEquipment(document))
            assert(not WSGS.ManagedBuilds:Save(character, candidate))
            assert(character.simulationProfiles[first.id] == first and character.latestSimulationProfileId == first.id)
        end
    end },
    { name = "Empty and overlong names cannot replace a valid name", run = function()
        local character = { simulationProfiles = {} }
        local first = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
        assert(not WSGS.ManagedBuilds:Rename(character, first.id, "   "))
        assert(not WSGS.ManagedBuilds:Rename(character, first.id, string.rep("x", 81)))
        assert(first.name == "Protection" and not first.customName and first.id == "Paladin:66")
    end },
})
