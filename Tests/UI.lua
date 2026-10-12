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
    { name = "Empty build clears previous comparison and slot data", run = function()
        withDoll(function(frame)
            Doll:Render(nil)
            assert(not Doll.profile and not Doll.comparison)
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
    { name = "Visibility toggles open and closed", run = function()
        withDoll(function(frame)
            Doll:Toggle()
            assert(frame:IsShown())
            Doll:Toggle()
            assert(not frame:IsShown())
            for _, event in ipairs(Doll.events) do assert(not frame:IsEventRegistered(event)) end
        end)
    end },
    { name = "Refresh events registered only while visible", run = function()
        withDoll(function(frame)
            frame:Show()
            for _, event in ipairs(Doll.events) do assert(frame:IsEventRegistered(event)) end
            frame:Hide()
            for _, event in ipairs(Doll.events) do assert(not frame:IsEventRegistered(event)) end
            local snapshot = Doll.snapshot
            Doll:Refresh()
            assert(Doll.snapshot == snapshot, "Closed doll scanned equipment")
        end)
    end },
    { name = "Opening and closing the UI does not change equipment", run = function()
        withDoll(function(frame)
            local before = {}
            for position, slot in ipairs(WSGS.equipmentSlots) do before[position] = GetInventoryItemID("player", slot.id) end
            frame:Show(); frame:Hide()
            for position, slot in ipairs(WSGS.equipmentSlots) do
                assert(before[position] == GetInventoryItemID("player", slot.id), "Equipped item changed")
            end
        end)
    end },
    { name = "Successful import closes editor and selects temporary build", run = function()
        withImportWindow(function(frame)
            local character = { simulationProfiles = {} }
            frame:Show()
            frame.importInput:SetText(WSGS.Tests.referenceJSON)
            local build = assert(WSGS:SubmitImport(frame, function(text) return WSGS:ImportInto(character, text) end))
            assert(not frame:IsShown() and character.latestSimulationProfileId == build.id)
        end)
    end },
    { name = "Failed import retains JSON and clears error on reopen", run = function()
        withImportWindow(function(frame)
            local character = { simulationProfiles = {} }
            local previous = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
            local builds, selected = character.simulationProfiles, character.latestSimulationProfileId
            local function unchangedBuild()
                assert(character.simulationProfiles == builds and builds[previous.id] == previous,
                    "Failed import replaced the existing managed build")
                assert(character.latestSimulationProfileId == selected,
                    "Failed import changed the selected managed build")
                local count = 0
                for _ in pairs(builds) do count = count + 1 end
                assert(count == 1, "Failed import added a managed build")
            end
            frame:Show()
            frame.importInput:SetText("{broken")
            local build = WSGS:SubmitImport(frame, function(text) return WSGS:ImportInto(character, text) end)
            assert(not build, "Malformed JSON imported successfully")
            assert(frame:IsShown(), "Failed import closed the dialog")
            assert(frame.importInput:GetText() == "{broken", "Failed import altered the pasted JSON")
            local errorText = frame.importStatus:GetText()
            assert(errorText and errorText:match("%S"),
                "Failed import did not display a readable error: " .. tostring(errorText))
            unchangedBuild()
            frame:Hide(); frame:Show()
            assert(frame:IsShown(), "Import dialog did not reopen")
            -- A cleared FontString may return nil rather than an empty string.
            errorText = frame.importStatus:GetText()
            assert((errorText or "") == "", "Reopening retained an error: " .. tostring(errorText))
            assert(frame.importInput:GetText() == "{broken", "Reopening altered the pasted JSON")
            unchangedBuild()
        end)
    end },
    { name = "Editable build name commits once and preserves identity", run = function()
        withDoll(function(frame)
            local character = { simulationProfiles = {} }
            local build = assert(WSGS:ImportInto(character, WSGS.Tests.referenceJSON))
            local _, snapshot = scenario()
            Doll:Render(build, snapshot, assert(WSGS.EquipmentComparator:Compare(build, snapshot)))
            local name = frame.buildName
            assert(name:GetText() == build.name, "Selected build name was not bound to the editor")
            name:SetText("Raid tank")
            assert(build.name == "Protection", "Partial edit saved")
            assert(Doll:CommitBuildName(character))
            assert(build.name == "Raid tank" and name:GetText() == "Raid tank" and build.id == "Paladin:66")
            name:SetText(" ")
            assert(not Doll:CommitBuildName(character))
            assert(name:GetText() == "Raid tank" and build.name == "Raid tank")
        end)
    end },
    { name = "Native special-window alias closes import before paper doll", run = function()
        withDoll(function(doll)
            withImportWindow(function(frame)
                doll:Show(); frame:Show()
                local count = 0
                for _, name in pairs(UISpecialFrames) do
                    if name == "WSGSEscapeWindow" then count = count + 1 end
                    assert(name ~= "WSGSMainWindow" and name ~= "WSGSPaperDoll",
                        "Both windows still have independent Escape entries")
                end
                assert(count == 1 and _G.WSGSEscapeWindow == frame, "Top window alias is incorrect")
                -- Exercise exactly Blizzard's per-entry Hide path, without
                -- calling CloseSpecialWindows and closing unrelated user UIs.
                local top = _G.WSGSEscapeWindow
                top:Hide()
                assert(not frame:IsShown() and doll:IsShown(), "First Escape did not preserve the paper doll")
                assert(_G.WSGSEscapeWindow == doll, "Escape alias did not advance to the paper doll")
                top = _G.WSGSEscapeWindow
                top:Hide()
                assert(not doll:IsShown() and not _G.WSGSEscapeWindow, "Second Escape did not close the paper doll")
            end)
        end)
    end },
    { name = "Focused editor Escape after failure preserves underlying doll", run = function()
        withDoll(function(doll)
            withImportWindow(function(frame)
                doll:Show(); frame:Show()
                local character = { simulationProfiles = {} }
                frame.importInput:SetText("{broken")
                assert(not WSGS:SubmitImport(frame, function(text) return WSGS:ImportInto(character, text) end))
                frame.importInput:SetFocus()
                assert(frame.importInput:HasFocus(), "JSON editor did not receive focus")
                frame.importInput:GetScript("OnEscapePressed")(frame.importInput)
                assert(not frame:IsShown() and doll:IsShown(), "Focused Escape closed the wrong windows")
                assert(frame.importInput:GetText() == "{broken", "Focused Escape changed the JSON")
                assert(_G.WSGSEscapeWindow == doll, "Focused Escape did not advance the native alias")
            end)
        end)
    end },
    { name = "Import-only and doll-only Escape registration", run = function()
        withDoll(function(doll)
            withImportWindow(function(frame)
                doll:Hide(); frame:Show()
                assert(_G.WSGSEscapeWindow == frame, "Import-only Escape target missing")
                _G.WSGSEscapeWindow:Hide()
                assert(not frame:IsShown() and not _G.WSGSEscapeWindow, "Import-only Escape failed")
                doll:Show()
                assert(_G.WSGSEscapeWindow == doll, "Doll-only Escape target missing")
                _G.WSGSEscapeWindow:Hide()
                assert(not doll:IsShown() and not _G.WSGSEscapeWindow, "Doll-only Escape failed")
                WSGS:ToggleWindow()
                assert(frame:IsShown() and _G.WSGSEscapeWindow == frame, "Import toggle did not open the dialog")
                WSGS:ToggleWindow()
                assert(not frame:IsShown() and not _G.WSGSEscapeWindow, "Import toggle did not close the dialog")
                frame:Show()
                frame.CloseButton:GetScript("OnClick")(frame.CloseButton)
                assert(not frame:IsShown() and not _G.WSGSEscapeWindow, "Import close button failed")
                doll:Show()
                doll.CloseButton:GetScript("OnClick")(doll.CloseButton)
                assert(not doll:IsShown() and not _G.WSGSEscapeWindow, "Paper doll close button failed")
            end)
        end)
    end },
})
