local _, WSGS = ...
local Tests = { suites = {}, order = { "scanner", "comparator", "importer" } }
WSGS.Tests = Tests

function Tests:Register(name, title, cases)
    assert(not self.suites[name], "Duplicate test suite: " .. name)
    self.suites[name] = { title = title, cases = cases }
end

function Tests:Run(name)
    name = name == "" and "all" or name or "all"
    local selected = name == "all" and self.order or { name }
    if name ~= "all" and not self.suites[name] then
        WSGS:Print("[TEST] Unknown suite. Use all, scanner, comparator, or importer.")
        return
    end
    local totals = { passed = 0, failed = 0, skipped = 0 }
    for _, suiteName in ipairs(selected) do
        local suite = self.suites[suiteName]
        WSGS:Print("[TEST] " .. suite.title)
        for _, case in ipairs(suite.cases) do
            local ok, outcome, reason = pcall(case.run)
            local status
            if not ok or outcome == false then
                totals.failed = totals.failed + 1
                status = "FAIL"
                reason = not ok and tostring(outcome) or reason
            elseif outcome == "SKIP" then
                totals.skipped = totals.skipped + 1
                status = "SKIP"
            else
                totals.passed = totals.passed + 1
                status = "PASS"
            end
            -- Keep errors one line and bounded; never dump an export.
            local detail = reason and (" - " .. tostring(reason):gsub("[\r\n]", " "):sub(1, 220)) or ""
            WSGS:Print("[TEST] " .. status .. ": " .. case.name .. detail)
        end
    end
    WSGS:Print(string.format("[TEST] Results: %d passed, %d failed, %d skipped",
        totals.passed, totals.failed, totals.skipped))
    return totals
end
