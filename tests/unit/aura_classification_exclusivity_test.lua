-- tests/unit/aura_classification_exclusivity_test.lua
-- Wave 4 Task 2b: classification-mode EXCLUSIVITY. Before this task,
-- "classify" mode's OR fan-out built one group per ticked category with no
-- relationship between them — an aura matching two ticked categories (e.g. a
-- big-defensive that is also cancelable) rendered in BOTH groups, each at the
-- element's full maxIcons. E.CompileFilters (core/aura_elements.lua) now
-- gives the editor's fixed priority order (matches
-- HELPFUL_CLASSIFICATIONS/HARMFUL_CLASSIFICATIONS in
-- QUI_Options/aura_elements_editor.lua) teeth: every category appends
-- `!TOKEN` negations of every HIGHER-priority ENABLED category.
--
-- This file asserts, string-level:
--   1) each compiled category string embeds the expected negations;
--   2) every compiled string validates against the REAL vendored engine
--      grammar (AuraUtil.IsValidFilterString), not just our own mirror;
--   3) a probe aura tagged with TWO categories' tokens matches exactly ONE
--      of the compiled group filters — never zero, never both.
-- Honest caveat (repeated at point of use below): (3) is a string-level
-- simulation of the engine's AND-of-components matching rule, verified
-- against the vendored grammar's ACCEPT/REJECT verdict only. Whether the
-- real C-side aura-filter evaluator matches auras identically is IN-GAME
-- PENDING — this file cannot execute WoW's live filter engine headless.
--
-- Run: lua5.1 tests/unit/aura_classification_exclusivity_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

----------------------------------------------------------------------------
-- Load the REAL engine validator (same slice-load technique as
-- aura_filter_canonicalize_test.lua — see that file for the string.split
-- WoW-faithful stub rationale).
----------------------------------------------------------------------------
local function wowSplit(delimiters, str)
    local classPattern = "[^" .. delimiters:gsub("(%W)", "%%%1") .. "]*"
    local out = {}
    local pos, len = 1, #str
    while true do
        local s, e = str:find(classPattern, pos)
        out[#out + 1] = str:sub(s, e)
        pos = e + 2
        if pos > len + 1 then break end
    end
    return out
end
-- luacheck: ignore 142/string 143/string
string.split = function(delimiters, str)
    return (table.unpack or unpack)(wowSplit(delimiters, str))
end

assert(loadfile("tests/framexml/Interface/AddOns/Blizzard_SharedXMLBase/TableUtil.lua"))()
assert(loadfile("tests/framexml/Interface/AddOns/Blizzard_SharedXMLBase/EnumUtil.lua"))()

local AURAUTIL_PATH = "tests/framexml/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua"
local START_MARKER = "AuraUtil.AuraFilters ="
local END_MARKER = "AuraUtil.DispellableDebuffTypes ="
local fh = assert(io.open(AURAUTIL_PATH, "rb"))
local auraUtilSrc = fh:read("*a"); fh:close()
local sIdx = assert(auraUtilSrc:find(START_MARKER, 1, true), "AuraFilters start marker not found — AuraUtil.lua changed shape")
local eIdx = assert(auraUtilSrc:find(END_MARKER, 1, true), "DispellableDebuffTypes end marker not found — AuraUtil.lua changed shape")
_G.AuraUtil = {}
assert((loadstring or load)(auraUtilSrc:sub(sIdx, eIdx - 1), "@AuraUtil-slice"))()
local RealIsValid = AuraUtil.IsValidFilterString
check("real engine validator loaded", type(RealIsValid) == "function")

----------------------------------------------------------------------------
-- Load the module under test.
----------------------------------------------------------------------------
local ns = dofile("tools/_addon_env.lua").LoadCore()
local E = ns.AuraElements

----------------------------------------------------------------------------
-- String-level probe simulator: a minimal, LOCAL mirror of the engine's
-- AND-of-components matching rule (polarity ignored here — auraType is
-- matched by the caller separately). NOT the real engine; exists only to
-- give the "matches exactly one group" assertion below teeth beyond eyeballing
-- the strings. tags is a { [TOKEN] = true } set describing a hypothetical
-- aura's AuraFilters-relevant flags.
----------------------------------------------------------------------------
local function ProbeMatches(filterString, tags)
    for component in filterString:gmatch("[^| ]+") do
        local negated = component:sub(1, 1) == "!"
        local tok = negated and component:sub(2) or component
        if tok ~= "HELPFUL" and tok ~= "HARMFUL" then
            if negated then
                if tags[tok] then return false end
            else
                if not tags[tok] then return false end
            end
        end
    end
    return true
end

local function countMatches(groups, tags)
    local n = 0
    for _, fs in ipairs(groups) do
        if ProbeMatches(fs, tags) then n = n + 1 end
    end
    return n
end

----------------------------------------------------------------------------
-- 1) HELPFUL: cancelable (rank 3) ranks above bigDefensive (rank 5) in the
--    fixed priority order — bigDefensive must embed !CANCELABLE.
----------------------------------------------------------------------------
do
    local e = E.NewFilterStripElement("HELPFUL")
    e.filterMode = "classify"
    e.classifications = { cancelable = true, bigDefensive = true }
    local fs = E.CompileFilters(e)
    check("exclusivity: two groups emitted", #fs == 2, tostring(#fs))

    local byToken = {}
    for _, s in ipairs(fs) do
        if s:find("CANCELABLE", 1, true) and not s:find("BIG_DEFENSIVE", 1, true) then
            byToken.cancelable = s
        elseif s:find("BIG_DEFENSIVE", 1, true) then
            byToken.bigDefensive = s
        end
    end
    check("exclusivity: higher-priority (cancelable) carries NO negation",
        byToken.cancelable == "HELPFUL|CANCELABLE", tostring(byToken.cancelable))
    check("exclusivity: lower-priority (bigDefensive) embeds !CANCELABLE negation",
        byToken.bigDefensive == "HELPFUL|BIG_DEFENSIVE|!CANCELABLE", tostring(byToken.bigDefensive))

    for _, s in ipairs(fs) do
        check(("exclusivity: %q validates against the REAL engine grammar"):format(s), RealIsValid(s) == true)
        local canonical = E.CanonicalizeFilterString(s)
        check(("exclusivity: %q canonicalization preserves validity"):format(s),
            RealIsValid(canonical) == RealIsValid(s))
    end

    -- Probe: an aura that is BOTH cancelable and a big defensive must match
    -- exactly ONE compiled group (the higher-priority one) — never both,
    -- never neither. String-level simulation only; see file header caveat.
    local probeTags = { CANCELABLE = true, BIG_DEFENSIVE = true }
    check("exclusivity: dual-tagged probe aura matches EXACTLY ONE group filter",
        countMatches(fs, probeTags) == 1, tostring(countMatches(fs, probeTags)))
    check("exclusivity: probe matches the higher-priority (cancelable) group",
        ProbeMatches(byToken.cancelable, probeTags) == true)
    check("exclusivity: probe does NOT match the lower-priority (bigDefensive) group",
        ProbeMatches(byToken.bigDefensive, probeTags) == false)

    -- Control: an aura tagged ONLY bigDefensive (not cancelable) still
    -- matches the bigDefensive group — exclusivity narrows the OVERLAP, it
    -- does not hide non-overlapping members of the lower-priority category.
    local soloTags = { BIG_DEFENSIVE = true }
    check("exclusivity: solo-tagged probe (bigDefensive only) still matches its own group",
        countMatches(fs, soloTags) == 1 and ProbeMatches(byToken.bigDefensive, soloTags))
end

----------------------------------------------------------------------------
-- 2) HARMFUL: raid (rank 1) ranks above crowdControl (rank 2).
----------------------------------------------------------------------------
do
    local d = E.NewFilterStripElement("HARMFUL")
    d.filterMode = "classify"
    d.classifications = { raid = true, crowdControl = true }
    local dfs = E.CompileFilters(d)
    check("exclusivity (harmful): two groups emitted", #dfs == 2, tostring(#dfs))

    local byToken = {}
    for _, s in ipairs(dfs) do
        if s == "HARMFUL|RAID" then byToken.raid = s
        elseif s:find("CROWD_CONTROL", 1, true) then byToken.cc = s end
    end
    check("exclusivity (harmful): raid (higher priority) carries no negation",
        byToken.raid == "HARMFUL|RAID", tostring(byToken.raid))
    check("exclusivity (harmful): crowdControl embeds !RAID negation",
        byToken.cc == "HARMFUL|CROWD_CONTROL|!RAID", tostring(byToken.cc))

    for _, s in ipairs(dfs) do
        check(("exclusivity (harmful): %q validates against the REAL engine grammar"):format(s), RealIsValid(s) == true)
    end

    local probeTags = { RAID = true, CROWD_CONTROL = true }
    check("exclusivity (harmful): dual-tagged probe matches EXACTLY ONE group",
        countMatches(dfs, probeTags) == 1, tostring(countMatches(dfs, probeTags)))
end

----------------------------------------------------------------------------
-- 3) Legacy/unranked keys (dispellable — never editor-reachable, see
--    core/aura_elements.lua's priority-list comment) stay UNCHANGED: bare,
--    no negations contributed either direction.
----------------------------------------------------------------------------
do
    local d = E.NewFilterStripElement("HARMFUL")
    d.filterMode = "classify"
    d.classifications = { raid = true, dispellable = true }
    local dfs = E.CompileFilters(d)
    -- 68675: "dispellable by me" compiles to HARMFUL|RAID (same string as
    -- the raid key — see aura_elements DEBUFF_CLASSIFICATION_MAP), so the
    -- unranked key still contributes bare and UNNEGATED, deduping onto the
    -- raid group rather than emitting a second string.
    local hasBareRaid, hasNegated = false, false
    for _, s in ipairs(dfs) do
        if s == "HARMFUL|RAID" then hasBareRaid = true end
        if s:find("!", 1, true) then hasNegated = true end
    end
    check("legacy key: dispellable compiles bare (no negation of/from raid)",
        hasBareRaid and not hasNegated, table.concat(dfs, ","))
end

----------------------------------------------------------------------------
-- 4) Complementary categories must NOT poison lower-priority filters
--    (review fix). cancelable (CANCELABLE) + notCancelable (!CANCELABLE) are
--    literal complements: together they exhaust the domain — every aura
--    matches exactly one of the two. A category ranked BELOW both would
--    inherit CANCELABLE required AND excluded on the same string
--    ("HELPFUL|BIG_DEFENSIVE|CANCELABLE|!CANCELABLE"): syntactically valid,
--    semantically unsatisfiable — a dead engine group that silently renders
--    zero icons. CompileFilters must SKIP emitting such a group entirely,
--    which is semantically exact (not lossy): any aura the lower category
--    could show is already claimed by one of the two complement groups.
----------------------------------------------------------------------------
local function hasContradiction(fs)
    local reqSet, excSet = {}, {}
    for component in fs:gmatch("[^| ]+") do
        if component:sub(1, 1) == "!" then excSet[component:sub(2)] = true
        else reqSet[component] = true end
    end
    for tok in pairs(reqSet) do
        if excSet[tok] then return true end
    end
    return false
end

do
    -- (a) both complements + a lower category → the lower category emits NO
    -- group string at all (not a contradictory one, not a partial one).
    local e = E.NewFilterStripElement("HELPFUL")
    e.filterMode = "classify"
    e.classifications = { cancelable = true, notCancelable = true, bigDefensive = true }
    local fs = E.CompileFilters(e)
    check("complements: both + bigDefensive → exactly 2 groups (dead group skipped)",
        #fs == 2, table.concat(fs, "  "))
    local sawBigDef = false
    for _, s in ipairs(fs) do
        if s:find("BIG_DEFENSIVE", 1, true) then sawBigDef = true end
        check(("complements: emitted string %q has no token both required and excluded"):format(s),
            not hasContradiction(s))
        check(("complements: emitted string %q still validates"):format(s), RealIsValid(s) == true)
    end
    check("complements: NO string mentions BIG_DEFENSIVE (unsatisfiable group skipped)", not sawBigDef)
    table.sort(fs)
    check("complements: the two complement groups themselves are unchanged",
        fs[1] == "HELPFUL|!CANCELABLE" and fs[2] == "HELPFUL|CANCELABLE", table.concat(fs, "  "))

    -- (b) both complements alone → two groups, unchanged.
    local b = E.NewFilterStripElement("HELPFUL")
    b.filterMode = "classify"
    b.classifications = { cancelable = true, notCancelable = true }
    local bfs = E.CompileFilters(b)
    table.sort(bfs)
    check("complements: both alone → two groups, unchanged",
        #bfs == 2 and bfs[1] == "HELPFUL|!CANCELABLE" and bfs[2] == "HELPFUL|CANCELABLE",
        table.concat(bfs, "  "))

    -- (c) externalDefensive shares the same accumulator mechanism (it ranks
    -- below both complements too) — same skip applies.
    local c = E.NewFilterStripElement("HELPFUL")
    c.filterMode = "classify"
    c.classifications = { cancelable = true, notCancelable = true, externalDefensive = true }
    local cfs = E.CompileFilters(c)
    local sawExtDef = false
    for _, s in ipairs(cfs) do
        if s:find("EXTERNAL_DEFENSIVE", 1, true) then sawExtDef = true end
    end
    check("complements: both + externalDefensive → externalDefensive group skipped too",
        #cfs == 2 and not sawExtDef, table.concat(cfs, "  "))

    -- Control: WITHOUT the complement pair, a lower category still emits its
    -- (negation-bearing, satisfiable) group — the guard must not over-fire.
    local ctrl = E.NewFilterStripElement("HELPFUL")
    ctrl.filterMode = "classify"
    ctrl.classifications = { raid = true, cancelable = true, bigDefensive = true }
    local cofs = E.CompileFilters(ctrl)
    local ctrlBigDef = false
    for _, s in ipairs(cofs) do
        if s == "HELPFUL|BIG_DEFENSIVE|!CANCELABLE|!RAID" then ctrlBigDef = true end
        check(("complements control: %q is contradiction-free"):format(s), not hasContradiction(s))
    end
    check("complements control: no complement pair → bigDefensive group still emitted",
        #cofs == 3 and ctrlBigDef, table.concat(cofs, "  "))

    -- Property sweep: NO combination of ranked categories may ever emit a
    -- string with a token both required and excluded (2^6 = 64 combos).
    local keys = { "raid", "raidInCombat", "cancelable", "notCancelable", "bigDefensive", "externalDefensive" }
    local bad = nil
    for mask = 0, 2 ^ #keys - 1 do
        local cls = {}
        for i, k in ipairs(keys) do
            if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then cls[k] = true end
        end
        local p = E.NewFilterStripElement("HELPFUL")
        p.filterMode = "classify"
        p.classifications = cls
        for _, s in ipairs(E.CompileFilters(p)) do
            if hasContradiction(s) then bad = s end
        end
    end
    check("complements property: no HELPFUL classify combo (all 64) emits a contradictory string",
        bad == nil, tostring(bad))
end

----------------------------------------------------------------------------
-- 5) Cross-file priority-order pin (review fix). BUFF/DEBUFF_CLASSIFICATION_
--    PRIORITY (core/aura_elements.lua) are hand-duplicated from the editor's
--    HELPFUL/HARMFUL_CLASSIFICATIONS checkbox lists (QUI_Options/
--    aura_elements_editor.lua) — the exclusivity scheme's "first ticked
--    category wins" promise only holds while the two stay in the SAME order.
--    Source-text pin: extract both orders and assert element-wise equality,
--    so a future reorder of either side fails loudly here instead of
--    silently changing which category claims the overlap.
----------------------------------------------------------------------------
do
    local function readAll(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
    end
    local coreSrc = readAll("core/aura_elements.lua")
    local editorSrc = readAll("QUI_Options/aura_elements_editor.lua")

    local function extractPriority(src, name)
        local body = src:match("local " .. name .. " = {(.-)}")
        assert(body, name .. " table not found — aura_elements.lua changed shape")
        local keys = {}
        for k in body:gmatch('"([%w_]+)"') do keys[#keys + 1] = k end
        return keys
    end
    local function extractEditorKeys(src, name)
        local body = src:match("local " .. name .. " = {(.-)\n}")
        assert(body, name .. " table not found — aura_elements_editor.lua changed shape")
        local keys = {}
        for k in body:gmatch('key%s*=%s*"([%w_]+)"') do keys[#keys + 1] = k end
        return keys
    end
    local function sameOrder(a, b)
        if #a ~= #b then return false end
        for i = 1, #a do
            if a[i] ~= b[i] then return false end
        end
        return true
    end

    local buffPrio = extractPriority(coreSrc, "BUFF_CLASSIFICATION_PRIORITY")
    local helpfulEditor = extractEditorKeys(editorSrc, "HELPFUL_CLASSIFICATIONS")
    check("priority pin: BUFF_CLASSIFICATION_PRIORITY is non-empty", #buffPrio > 0)
    check("priority pin: core BUFF priority order == editor HELPFUL checkbox order",
        sameOrder(buffPrio, helpfulEditor),
        table.concat(buffPrio, ",") .. " vs " .. table.concat(helpfulEditor, ","))

    local debuffPrio = extractPriority(coreSrc, "DEBUFF_CLASSIFICATION_PRIORITY")
    local harmfulEditor = extractEditorKeys(editorSrc, "HARMFUL_CLASSIFICATIONS")
    check("priority pin: DEBUFF_CLASSIFICATION_PRIORITY is non-empty", #debuffPrio > 0)
    check("priority pin: core DEBUFF priority order == editor HARMFUL checkbox order",
        sameOrder(debuffPrio, harmfulEditor),
        table.concat(debuffPrio, ",") .. " vs " .. table.concat(harmfulEditor, ","))
end

print("aura_classification_exclusivity_test " .. (failures == 0 and "OK" or "FAILED"))
os.exit(failures == 0 and 0 or 1)
