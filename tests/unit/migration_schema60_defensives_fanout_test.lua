-- tests/unit/migration_schema60_defensives_fanout_test.lua
-- Run: lua5.1 tests/unit/migration_schema60_defensives_fanout_test.lua
-- Schema 60 folds the shipped defensives strip and its override fan-out into
-- one pass. Numeric spec buckets REPLACE "*", so every existing non-empty
-- bucket receives a clone while deliberately empty buckets stay empty.
--   - a hand-built classify-equivalent strip blocks injection (no duplicate)
--   - the schema stamp is the one-shot: deletions after migration stick
local ns = dofile("tools/_addon_env.lua").LoadCore()
local M = ns.Migrations

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function countDefensives(bucket)
    local n = 0
    for _, e in ipairs(bucket or {}) do
        if type(e) == "table" and e.id == "defensives" then n = n + 1 end
    end
    return n
end

local function buildProfile(starEnabled)
    local defensives = {
        id = "defensives", mode = "filterStrip", auraType = "HELPFUL",
        enabled = starEnabled, filterMode = "classify",
        classifications = { bigDefensive = true, externalDefensive = true },
    }
    return {
        _schemaVersion = 47,
        quiGroupFrames = {
            party = { auras = { elementsSeeded = true, elements = {
                ["*"] = { defensives },
                [105] = { { id = 7, mode = "filterStrip", auraType = "HARMFUL", filterMode = "off" } },
                [106] = {},
            } } },
        },
    }
end

do -- legacy indicator folds into "*" and fans out without a later migration
    local p = {
        _schemaVersion = 47,
        quiGroupFrames = { party = {
            healer = { defensiveIndicator = { enabled = true } },
            auras = { elementsSeeded = true, elements = {
                ["*"] = { { id = "buffs", mode = "filterStrip" } },
                [105] = { { id = "custom", mode = "tracked", spells = { 123 } } },
            } },
        } },
    }
    M.RunOnProfile(p)
    local elements = p.quiGroupFrames.party.auras.elements
    check("fold adds defensives to '*'", countDefensives(elements["*"]) == 1)
    check("same fold pass fans defensives into spec", countDefensives(elements[105]) == 1)
    local clone
    for _, e in ipairs(elements[105]) do
        if e.id == "defensives" then clone = e break end
    end
    check("fan-out clone carries legacy enabled=true", clone and clone.enabled == true,
        clone and tostring(clone.enabled))
end

do -- numeric buckets are handled in the same pass as the fold
    local p = buildProfile(true)
    M.RunOnProfile(p)
    local elements = p.quiGroupFrames.party.auras.elements
    check("spec bucket got defensives", countDefensives(elements[105]) == 1, tostring(countDefensives(elements[105])))
    for _, e in ipairs(elements[105]) do
        if e.id == "defensives" then
            check("enabled mirrors '*' (true)", e.enabled == true, tostring(e.enabled))
            check("copy, not alias", e ~= elements["*"][1])
        end
    end
    check("empty numeric override remains empty", #elements[106] == 0, tostring(#elements[106]))
    check("'*' still has exactly one", countDefensives(elements["*"]) == 1)
    check("stamped 60", p._schemaVersion == 60, tostring(p._schemaVersion))
end

do -- disabled "*" defensives mirrors as disabled
    local p = buildProfile(false)
    M.RunOnProfile(p)
    for _, e in ipairs(p.quiGroupFrames.party.auras.elements[105]) do
        if e.id == "defensives" then
            check("enabled mirrors '*' (false)", e.enabled == false, tostring(e.enabled))
        end
    end
end

do -- hand-built classify-equivalent blocks injection
    local p = buildProfile(true)
    table.insert(p.quiGroupFrames.party.auras.elements[105], {
        id = 42, mode = "filterStrip", auraType = "HELPFUL", filterMode = "classify",
        classifications = { bigDefensive = true, externalDefensive = true },
    })
    M.RunOnProfile(p)
    check("no duplicate next to hand-built equivalent",
        countDefensives(p.quiGroupFrames.party.auras.elements[105]) == 0,
        tostring(countDefensives(p.quiGroupFrames.party.auras.elements[105])))
end

do -- one-shot: post-migration deletion sticks on the next run
    local p = buildProfile(true)
    M.RunOnProfile(p)
    local spec = p.quiGroupFrames.party.auras.elements[105]
    for i = #spec, 1, -1 do
        if spec[i].id == "defensives" then table.remove(spec, i) end
    end
    M.RunOnProfile(p)
    check("post-migration deletion sticks", countDefensives(spec) == 0, tostring(countDefensives(spec)))
end

print("migration_schema60_defensives_fanout_test " .. (failures == 0 and "OK" or "FAILED"))
os.exit(failures == 0 and 0 or 1)
