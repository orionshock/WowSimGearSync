local _, WSGS = ...
local Doll = WSGS.PaperDoll

-- Exercise actual frames without changing builds/settings. Always restore the
-- previous UI presentation/visibility, including when an assertion fails.
local function withDoll(run)
    local frame = Doll:Create()
    local shown = frame:IsShown()
    local profile, snapshot, comparison, reason = Doll.profile, Doll.snapshot, Doll.comparison, Doll.error
    frame:Hide()
    local ok, outcome, detail = pcall(run, frame)
    frame:Hide()
    Doll:Render(profile, snapshot, comparison, reason)
    if shown then frame:Show() end
    if not ok then error(outcome, 0) end
    return outcome, detail
end

local function withImportWindow(run)
    if not WSGS.window then WSGS:CreateWindow() end
    local frame = WSGS.window
    local shown, text, errorText = frame:IsShown(), frame.importInput:GetText(), frame.importStatus:GetText()
    local ok, reason = pcall(run, frame)
    frame:Hide()
    frame.importInput:SetText(text)
    if shown then frame:Show() end
    frame.importStatus:SetText(errorText)
    if not ok then error(reason, 0) end
end

local function scenario()
    local document = C_EncodingUtil.DeserializeJSON(WSGS.Tests.referenceJSON)
    local reference = assert(WSGS:ValidateEquipment(document))
    local profile, snapshot = { name = "Synthetic UI binding", equipment = {} }, { slots = {} }
    for position, item in ipairs(reference.equipment) do
        profile.equipment[position] = { id = item.id }
        snapshot.slots[position] = { id = item.id, observations = {
            item = { status = "KNOWN", value = item.id, present = true },
            upgradeEligibility = { status = "KNOWN", value = false },
        } }
    end
    return profile, snapshot
end

WSGS.Tests:Register("ui", "UI", {
    { name = "Paper doll created with 16 reusable slot buttons", run = function()
        withDoll(function(frame)
            assert(Doll:Create() == frame and #frame.slots == 16)
            for position, button in ipairs(frame.slots) do
                assert(button:GetObjectType() == "Button" and button.position == position)
                assert(button.icon and button.quality and button.miniState)
                assert(not button.indicator)
            end
        end)
    end },
    { name = "Empty build prompts import and clears slots", run = function()
        withDoll(function(frame)
            Doll:Render(nil)
            assert(not Doll.profile and not Doll.comparison)
            assert(frame.buildName:GetText() == "No active build" and frame.summary:GetText():find("Import", 1, true))
            for _, button in ipairs(frame.slots) do assert(not button.target and button.visualState == "EMPTY") end
        end)
    end },
    { name = "Latest imported build selected", run = function()
        return withDoll(function(frame)
            local expected = WSGS:GetActiveSimulationProfile()
            if not expected then return "SKIP", "No imported build in this session" end
            frame:Show()
            assert(Doll.profile == expected and frame.buildName:GetText() == expected.name)
        end)
    end },
    { name = "Comparator result and visual states bound directly", run = function()
        withDoll(function(frame)
            local profile, snapshot = scenario()
            profile.equipment[3].enchant = 4803
            snapshot.slots[3].observations.enchant = { status = "KNOWN", value = 0 }
            snapshot.slots[4].observations.upgradeEligibility = { status = "UNKNOWN" }
            snapshot.slots[5].id = 95757
            snapshot.slots[5].observations.item.value = 95757
            local comparison = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
            Doll:Render(profile, snapshot, comparison)
            for position, button in ipairs(frame.slots) do
                assert(button.target == profile.equipment[position] and button.difference == comparison.slots[position])
                assert(button.current == snapshot.slots[comparison.assignments[position]])
            end
            assert(frame.slots[1].visualState == "MATCH" and frame.slots[3].visualState == "CONFIGURATION")
            assert(frame.slots[4].visualState == "UNKNOWN" and frame.slots[5].visualState == "MISMATCH")
        end)
    end },
    { name = "Resolved ring and trinket assignments displayed", run = function()
        withDoll(function(frame)
            local profile, snapshot = scenario()
            snapshot.slots[11], snapshot.slots[12] = snapshot.slots[12], snapshot.slots[11]
            snapshot.slots[13], snapshot.slots[14] = snapshot.slots[14], snapshot.slots[13]
            local comparison = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
            Doll:Render(profile, snapshot, comparison)
            for _, pair in ipairs({ {11,12}, {12,11}, {13,14}, {14,13} }) do
                local button = frame.slots[pair[1]]
                assert(comparison.assignments[pair[1]] == pair[2])
                assert(button.current == snapshot.slots[pair[2]] and button.difference.currentPosition == pair[2])
            end
        end)
    end },
    { name = "Visibility toggles without rebuilding frames", run = function()
        withDoll(function(frame)
            Doll:Toggle()
            assert(frame:IsShown())
            Doll:Toggle()
            assert(not frame:IsShown() and Doll.frame == frame)
            for _, event in ipairs(Doll.events) do assert(not frame:IsEventRegistered(event)) end
        end)
    end },
    { name = "Refresh events registered only while visible", run = function()
        withDoll(function(frame)
            frame:Show()
            for _, event in ipairs(Doll.events) do assert(frame:IsEventRegistered(event)) end
            assert(not frame:GetScript("OnUpdate"))
            frame:Hide()
            for _, event in ipairs(Doll.events) do assert(not frame:IsEventRegistered(event)) end
            local snapshot = Doll.snapshot
            Doll:Refresh()
            assert(Doll.snapshot == snapshot, "Closed doll scanned equipment")
        end)
    end },
    { name = "UI is read-only and launcher is registered", run = function()
        withDoll(function(frame)
            local before = {}
            for position, slot in ipairs(WSGS.equipmentSlots) do before[position] = GetInventoryItemID("player", slot.id) end
            assert(not frame.equipButton:IsEnabled())
            for _, button in ipairs(frame.slots) do
                assert(not button:GetScript("OnClick") and not button:GetScript("OnDragStart")
                    and not button:GetAttribute("type"))
            end
            frame:Show(); frame:Hide()
            for position, slot in ipairs(WSGS.equipmentSlots) do
                assert(before[position] == GetInventoryItemID("player", slot.id), "Equipped item changed")
            end
            assert(LibStub("LibDataBroker-1.1"):GetDataObjectByName("WowSimGearSync") == WSGS.launcher)
            assert(WSGS.launcher.type == "launcher" and LibStub("LibDBIcon-1.0"):IsRegistered("WowSimGearSync"))
        end)
    end },
    { name = "Mini states bind comparator results beside every slot", run = function()
        withDoll(function(frame)
            local profile, snapshot = scenario()
            profile.equipment[8].gems = { 10, 20, 30 }
            snapshot.slots[8].observations.buckle = { status = "KNOWN", value = false }
            local result = assert(WSGS.EquipmentComparator:Compare(profile, snapshot))
            Doll:Render(profile, snapshot, result)
            for _, button in ipairs(frame.slots) do
                assert(button.miniState:GetText() == WSGS.SlotPresentation:MiniStates(button.difference))
                assert(button.miniState:GetText():find("Equipped", 1, true))
            end
            assert(frame.slots[8].miniState:GetText():find("!Buckle", 1, true))
            assert(not frame.slots[1].miniState:GetText():find("Buckle", 1, true))
            local text = WSGS.SlotPresentation:MiniStates({ fields = {
                item = { state = "MISMATCH" }, gems = { state = "UNKNOWN" },
                enchant = { state = "NOT_APPLICABLE" },
            } })
            assert(text:find("|cffff4040!Equipped", 1, true) and text:find("Gemmed", 1, true))
            assert(not text:find("Enchant", 1, true) and not text:find("+", 1, true))
            local ordered = WSGS.SlotPresentation:MiniStates({ fields = {
                item = { state = "MATCH" }, upgradeStep = { state = "MATCH" },
                gems = { state = "MATCH" }, enchant = { state = "MATCH" },
                buckle = { state = "MATCH" }, tinker = { state = "MATCH" },
                reforging = { state = "MATCH" },
            } }):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            assert(ordered == "Equipped, Upgraded, Gemmed, Enchant, Buckle, Tinker, Reforged")
            assert(frame.helpHint:GetText() == "Hover a slot for details.")
        end)
    end },
    { name = "Normal tooltips are concise with upgrade progress and buckle", run = function()
        withDoll(function(frame)
            local profile, snapshot = scenario()
            profile.equipment[8].gems = { 10, 20, 30 }
            local o = snapshot.slots[8].observations
            o.buckle = { status = "KNOWN", value = false }
            o.upgradeEligibility = { status = "KNOWN", value = true }
            o.upgradeStep, o.upgradeMaximum = { status = "KNOWN", value = 0 }, { status = "KNOWN", value = 2 }
            Doll:Render(profile, snapshot, assert(WSGS.EquipmentComparator:Compare(profile, snapshot)))
            local text = table.concat(WSGS.SlotPresentation:TooltipLines(frame.slots[8], false), "\n")
            assert(text:find("Item: Matched", 1, true) and text:find("Buckle: Missing", 1, true))
            assert(text:find("Upgrade: 0/2 (2 remaining)", 1, true))
            for _, raw in ipairs({ "NOT_APPLICABLE", "UNKNOWN", "MISMATCH", "target=", "observed=", "Diagnostics:" }) do
                assert(not text:find(raw, 1, true))
            end
            local debug = table.concat(WSGS.SlotPresentation:TooltipLines(frame.slots[8], true), "\n")
            assert(debug:find("Diagnostics:", 1, true) and debug:find("Buckle: MISMATCH", 1, true))
            o.buckle.value = true
            Doll:Render(profile, snapshot, assert(WSGS.EquipmentComparator:Compare(profile, snapshot)))
            text = table.concat(WSGS.SlotPresentation:TooltipLines(frame.slots[8], false), "\n")
            assert(text:find("Buckle: Matched", 1, true))
        end)
    end },
    { name = "Successful import closes editor and selects temporary build", run = function()
        withImportWindow(function(frame)
            local character = { simulationProfiles = {} }
            frame:Show()
            frame.importInput:SetText(WSGS.Tests.referenceJSON)
            local build = assert(WSGS:SubmitImport(frame, function(text) return WSGS:ImportInto(character, text) end))
            assert(not frame:IsShown() and character.latestSimulationProfileId == build.id)
            assert(not frame.profileNameInput and not frame.importSummary)
        end)
    end },
    { name = "Failed import retains JSON and clears error on reopen", run = function()
        withImportWindow(function(frame)
            local character = { simulationProfiles = {} }
            frame:Show()
            frame.importInput:SetText("{broken")
            local build = WSGS:SubmitImport(frame, function(text) return WSGS:ImportInto(character, text) end)
            assert(not build and frame:IsShown() and frame.importInput:GetText() == "{broken")
            assert(frame.importStatus:GetText():find("Import failed:", 1, true))
            assert(next(character.simulationProfiles) == nil)
            frame:Hide(); frame:Show()
            assert(frame.importStatus:GetText() == "" and frame.importInput:GetText() == "{broken")
        end)
    end },
    { name = "Editable build name commits once and preserves identity", run = function()
        withDoll(function(frame)
            local character = { simulationProfiles = {} }
            local build = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
            local _, snapshot = scenario()
            Doll:Render(build, snapshot, assert(WSGS.EquipmentComparator:Compare(build, snapshot)))
            local name = frame.buildName
            assert(name:GetObjectType() == "EditBox" and name:GetText() == "Protection")
            name:SetText("Raid tank")
            assert(build.name == "Protection", "Partial edit saved")
            assert(Doll:CommitBuildName(character))
            assert(build.name == "Raid tank" and name:GetText() == "Raid tank" and build.id == "Paladin:66")
            name:SetText(" ")
            assert(not Doll:CommitBuildName(character))
            assert(name:GetText() == "Raid tank" and build.name == "Raid tank")
        end)
    end },
})
