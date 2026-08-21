-- tests/unit/aura_elements_model_test.lua
-- Run: lua5.1 tests/unit/aura_elements_model_test.lua
-- REAL unit tests (core/aura_elements.lua is pure Lua — no frame APIs).
local ns = dofile("tools/_addon_env.lua").LoadCore()
local E = ns.AuraElements

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

-- Constructors -----------------------------------------------------------
do
    local e = E.NewFilterStripElement("HARMFUL")
    check("strip: mode/auraType", e.mode == "filterStrip" and e.auraType == "HARMFUL")
    check("strip: HARMFUL default classifications lack raidInCombat (HELPFUL-only token)",
        e.classifications.raid == true and e.classifications.raidInCombat == nil)
    check("strip: new sort fields", e.sortRule == "INDEX" and e.sortReverse == false)
    check("strip: rightClickCancel defaults true", e.rightClickCancel == true)
    -- Wave 4 Task 2d: dedupeDefensives had zero runtime consumers (re-verified
    -- repo-wide grep) and is removed from the constructor. Absent-key
    -- convention: existing stores carrying the stale key are untouched, but
    -- nothing new should seed it.
    check("strip: no longer seeds dedupeDefensives", e.dedupeDefensives == nil)
    check("strip: duration sub-table", type(e.duration) == "table" and e.duration.show == true
        and e.duration.fontSize == 9 and e.duration.anchor == "CENTER")
    check("strip: stack sub-table", type(e.stack) == "table" and e.stack.show == true
        and e.stack.anchor == "BOTTOMRIGHT")
    local t = E.NewTrackedElement({ 12345 }, "bar")
    check("tracked: auraType field present (slots need polarity)", t.auraType == "HELPFUL")
    check("tracked: displayType honored", t.displayType == "bar")
    check("tracked: bar dims seeded", t.bar and t.bar.thickness == 12 and t.bar.length == 48)
    local m = E.NewMissingRaidBuffElement()
    check("mrb: mode", m.mode == "missingRaidBuff")
end

do
    local oldRuntime, oldSpellData = ns.CDMAuraRuntime, ns.CDMSpellData
    ns.CDMAuraRuntime = {
        ResolveAbilityAuraSpellID = function(spellID)
            if spellID == 100 then return 200, true end
            return spellID, false
        end,
    }
    ns.CDMSpellData = {
        GetAuraIDsForSpell = function(_, spellID)
            if spellID == 100 then return { 200, 300 } end
            if spellID == 101 then return { 101, 301 } end
            return nil
        end,
    }
    local tracked = E.NewTrackedElement({ 100 }, "icon")
    local linkedTracked = E.NewTrackedElement({ 101 }, "icon")
    local candidates = E.TrackedSpellCandidates(100)
    check("tracked: new entries store the mapped applied-aura ID", tracked.spells[1] == 200)
    check("tracked: fallback skips the ability ID in linked aura candidates", linkedTracked.spells[1] == 301)
    check("tracked: runtime candidates retain ability and linked aura IDs",
        candidates[100] == true and candidates[200] == true and candidates[300] == true)
    local legacy = { mode = "tracked", spells = { 100 }, onlyMineSpells = { [100] = true } }
    E.NormalizeElement(legacy)
    check("tracked: normalization migrates legacy spell and per-spell gate IDs",
        legacy.spells[1] == 200 and legacy.onlyMineSpells[200] == true)
    ns.CDMAuraRuntime, ns.CDMSpellData = oldRuntime, oldSpellData
end

-- Validate ---------------------------------------------------------------
do
    check("validate: strip needs polarity", E.Validate({ mode = "filterStrip", auraType = "HELPFUL" }) == true)
    check("validate: strip rejects bad polarity", E.Validate({ mode = "filterStrip", auraType = "ALL" }) == false)
    check("validate: tracked needs spells", E.Validate({ mode = "tracked", displayType = "icon", spells = {} }) == false)
    check("validate: tracked ok", E.Validate({ mode = "tracked", displayType = "square", spells = { 1 } }) == true)
    check("validate: unknown mode rejected", E.Validate({ mode = "wat" }) == false)
    check("validate: non-table rejected", E.Validate(nil) == false)
end

-- CompileFilters ---------------------------------------------------------
do
    -- Wave 4 Task 2b: classification EXCLUSIVITY. Priority order (fixed,
    -- matches the editor's HELPFUL_CLASSIFICATIONS/HARMFUL_CLASSIFICATIONS
    -- checkbox order): raid > raidInCombat > cancelable > notCancelable >
    -- bigDefensive > externalDefensive (HELPFUL); raid > crowdControl
    -- (HARMFUL). Every category ranked BELOW another ENABLED category gains
    -- a `!TOKEN` negation of it, so the same aura can't double-render across
    -- two ticked categories.
    local e = E.NewFilterStripElement("HELPFUL")
    e.filterMode = "classify"
    e.classifications = { raid = true, raidInCombat = true, cancelable = true }
    local fs = E.CompileFilters(e)
    table.sort(fs)
    check("compile: helpful classifications gain higher-priority negations",
        table.concat(fs, ",") ==
        "HELPFUL|CANCELABLE|!RAID|!RAID_IN_COMBAT,HELPFUL|RAID,HELPFUL|RAID_IN_COMBAT|!RAID",
        table.concat(fs, ","))

    -- `important` (68675 re-add) is the LAST-ranked HELPFUL category. Two
    -- things must hold, and they are the reason the rank is pinned here: it
    -- inherits the negation of every enabled category above it, and adding it
    -- leaves those categories' own strings byte-identical to what shipped.
    local imp = E.NewFilterStripElement("HELPFUL")
    imp.filterMode = "classify"
    imp.classifications = { bigDefensive = true, important = true }
    local ifs = E.CompileFilters(imp)
    table.sort(ifs)
    check("compile: important ranks last and inherits higher-priority negations",
        table.concat(ifs, ",") ==
        "HELPFUL|BIG_DEFENSIVE,HELPFUL|IMPORTANT|!BIG_DEFENSIVE",
        table.concat(ifs, ","))
    imp.classifications = { important = true }
    local ifsSolo = E.CompileFilters(imp)
    check("compile: important alone → HELPFUL|IMPORTANT",
        #ifsSolo == 1 and ifsSolo[1] == "HELPFUL|IMPORTANT", table.concat(ifsSolo, ","))

    -- Same category on HARMFUL, also ranked last there.
    local impH = E.NewFilterStripElement("HARMFUL")
    impH.filterMode = "classify"
    impH.classifications = { crowdControl = true, important = true }
    local ihfs = E.CompileFilters(impH)
    table.sort(ihfs)
    check("compile: important on HARMFUL ranks below crowdControl",
        table.concat(ihfs, ",") ==
        "HARMFUL|CROWD_CONTROL,HARMFUL|IMPORTANT|!CROWD_CONTROL",
        table.concat(ihfs, ","))

    local d = E.NewFilterStripElement("HARMFUL")
    d.filterMode = "classify"
    d.classifications = { raid = true, dispellable = true, crowdControl = true }
    local dfs = E.CompileFilters(d)
    table.sort(dfs)
    -- 68675: "dispellable by me" = HARMFUL|RAID (RAID_PLAYER_DISPELLABLE
    -- widened to anyone-in-raid), so raid + dispellable now compile to the
    -- SAME string and dedup onto one group.
    check("compile: harmful never emits RAID_IN_COMBAT (C API hard-errors on that combo); "
        .. "crowdControl (ranked) negates raid; dispellable dedups onto raid (both HARMFUL|RAID)",
        table.concat(dfs, ",") ==
        "HARMFUL|CROWD_CONTROL|!RAID,HARMFUL|RAID",
        table.concat(dfs, ","))

    local off = E.NewFilterStripElement("HELPFUL")
    off.filterMode = "off"
    check("compile: off mode → empty (caller uses base polarity)", #E.CompileFilters(off) == 0)

    -- "flags" = the legacy buffborders/UF AND-composition: enabled raw tokens
    -- joined onto ONE string, sorted for determinism.
    local flags = E.NewFilterStripElement("HELPFUL")
    flags.filterMode = "flags"
    flags.filterFlags = { PLAYER = true, CANCELABLE = true, RAID = false }
    local ffs = E.CompileFilters(flags)
    check("compile: flags mode AND-composes one string",
        #ffs == 1 and ffs[1] == "HELPFUL|CANCELABLE|PLAYER", tostring(ffs[1]))
    flags.filterFlags = {}
    check("compile: flags mode with nothing enabled → empty (bare polarity fallback)",
        #E.CompileFilters(flags) == 0)

    -- Out-of-set tokens are DROPPED, never emitted: the container's
    -- AddAuraGroup asserts AuraUtil.IsValidFilterString, and the C-side
    -- GetUnitAuras probe doesn't reject unknown components (live PTR error
    -- "Unknown aura filter component: 'modifiers'" from a corrupted store).
    flags.filterFlags = { PLAYER = true, modifiers = true }
    local dropped = E.CompileFilters(flags)
    check("compile: flags mode drops out-of-set tokens",
        #dropped == 1 and dropped[1] == "HELPFUL|PLAYER", tostring(dropped[1]))
    flags.filterFlags = { modifiers = true, exclusive = true }
    check("compile: flags mode with ONLY out-of-set tokens → empty (bare polarity fallback)",
        #E.CompileFilters(flags) == 0)

    -- 68675 tokens: IMPORTANT and DISPELLABLE are engine-valid now — they
    -- must compile, not silently drop.
    flags.filterFlags = { IMPORTANT = true }
    local imp = E.CompileFilters(flags)
    check("compile: 68675 IMPORTANT token accepted",
        #imp == 1 and imp[1] == "HELPFUL|IMPORTANT", tostring(imp[1]))
    local harm = E.NewFilterStripElement("HARMFUL")
    harm.filterMode = "flags"
    harm.filterFlags = { DISPELLABLE = true }
    local disp = E.CompileFilters(harm)
    check("compile: 68675 DISPELLABLE token accepted",
        #disp == 1 and disp[1] == "HARMFUL|DISPELLABLE", tostring(disp[1]))
    check("valid tokens: new 68675 entries known to the canonicalizer",
        E.IsKnownFilterString("HELPFUL|IMPORTANT") and E.IsKnownFilterString("HARMFUL|DISPELLABLE"))

    -- Non-negatable tokens (engine ignores their "!" form; absence already
    -- excludes the category): an "exclude" tri-state compiles to OMISSION,
    -- never to a dead "!INCLUDE_NAME_PLATE_ONLY" component.
    harm.filterFlags = { PLAYER = true, INCLUDE_NAME_PLATE_ONLY = "exclude" }
    local nneg = E.CompileFilters(harm)
    check("compile: excluded non-negatable token omitted (not emitted as !TOKEN)",
        #nneg == 1 and nneg[1] == "HARMFUL|PLAYER", tostring(nneg[1]))
    harm.filterFlags = { INCLUDE_NAME_PLATE_ONLY = true }
    local npReq = E.CompileFilters(harm)
    check("compile: non-negatable token still REQUIRABLE",
        #npReq == 1 and npReq[1] == "HARMFUL|INCLUDE_NAME_PLATE_ONLY", tostring(npReq[1]))

    -- Legacy UF fallback: helpful/harmful master toggles stored as raid/raidInCombat.
    local legacy = E.NewFilterStripElement("HELPFUL")
    legacy.filterMode = "classify"
    legacy.classifications = { helpful = true }
    local lfs = E.CompileFilters(legacy)
    table.sort(lfs)
    check("compile: 'helpful' master key expands to RAID + RAID_IN_COMBAT",
        table.concat(lfs, ",") == "HELPFUL|RAID,HELPFUL|RAID_IN_COMBAT", table.concat(lfs, ","))

    -- Split keys stay INDEPENDENT of the master alias: {raid=true} alone must
    -- NOT promote to RAID_IN_COMBAT (the merged map carries split keys, so no
    -- master fallback read — regression from the Task 2 review).
    local split = E.NewFilterStripElement("HELPFUL")
    split.filterMode = "classify"
    split.classifications = { raid = true }
    local sfs = E.CompileFilters(split)
    check("compile: {raid=true} alone emits ONLY HELPFUL|RAID",
        #sfs == 1 and sfs[1] == "HELPFUL|RAID", table.concat(sfs, ","))
end

-- CompileCandidateFilters --------------------------------------------------
do
    local e = E.NewFilterStripElement("HELPFUL")
    check("candidates: default nil (no restrictions)", E.CompileCandidateFilters(e) == nil)

    e.onlyMine = true
    local cf = E.CompileCandidateFilters(e)
    check("candidates: onlyMine → isFromPlayerOrPlayerPet", cf and cf.isFromPlayerOrPlayerPet == true)

    e.hidePermanent = true
    cf = E.CompileCandidateFilters(e)
    check("candidates: hidePermanent → maxDuration cap", cf and cf.maxDuration == 999999)

    e.filterMode = "whitelist"
    e.whitelist = { [17] = true, [42] = true }
    cf = E.CompileCandidateFilters(e)
    check("candidates: whitelist → includeSpellIDs map", cf and cf.includeSpellIDs
        and cf.includeSpellIDs[17] == true and cf.includeSpellIDs[42] == true)

    local b = E.NewFilterStripElement("HARMFUL")
    b.blacklist = { [99] = true }
    cf = E.CompileCandidateFilters(b)
    check("candidates: blacklist → excludeSpellIDs map", cf and cf.excludeSpellIDs and cf.excludeSpellIDs[99] == true)

    -- filterMode "off" must NOT emit includeSpellIDs even if a stale whitelist table exists.
    local off = E.NewFilterStripElement("HELPFUL")
    off.filterMode = "off"
    off.whitelist = { [5] = true }
    cf = E.CompileCandidateFilters(off)
    check("candidates: off mode ignores whitelist", cf == nil or cf.includeSpellIDs == nil)
end

-- NormalizeElement (legacy flat duration fields → duration{}) --------------
do
    local legacy = {
        id = "debuffs", mode = "filterStrip", auraType = "HARMFUL", enabled = true,
        showDurationText = true, durationFontSize = 9, durationAnchor = "BOTTOM",
        durationOffsetX = 0, durationOffsetY = -6, durationColor = { 1, 1, 1, 1 },
        durationUseTimeColor = true, showDurationColor = true, showExpiringPulse = true,
    }
    E.NormalizeElement(legacy)
    check("normalize: duration{} built from flat fields", legacy.duration
        and legacy.duration.show == true and legacy.duration.fontSize == 9
        and legacy.duration.anchor == "BOTTOM" and legacy.duration.offsetY == -6)
    check("normalize: flat duration fields pruned", legacy.showDurationText == nil
        and legacy.durationFontSize == nil and legacy.durationAnchor == nil
        and legacy.durationUseTimeColor == nil and legacy.showExpiringPulse == nil)
    check("normalize: stack{} seeded when absent", legacy.stack and legacy.stack.anchor == "BOTTOMRIGHT")
    check("normalize: idempotent", (function()
        E.NormalizeElement(legacy)
        return legacy.duration.fontSize == 9
    end)())
end

-- EnsureSeeded / buckets ---------------------------------------------------
do
    local function defaultBucket()
        return { { id = "seeded", mode = "filterStrip", auraType = "HARMFUL", enabled = true } }
    end
    local auras = {}
    E.EnsureSeeded(auras, defaultBucket)
    check("seed: '*' bucket created once", auras.elements and auras.elements["*"]
        and auras.elements["*"][1].id == "seeded")
    check("seed: flag set", auras.elementsSeeded == true)
    auras.elements["*"] = {}
    E.EnsureSeeded(auras, defaultBucket)
    check("seed: emptied bucket stays empty (flag, not presence)", #auras.elements["*"] == 0)

    local flat = { elementsSeeded = true, elements = { ["*"] = {
        { mode = "filterStrip", auraType = "HELPFUL", enabled = true },   -- no id
        { id = "dup", mode = "filterStrip", auraType = "HELPFUL" },
        { id = "dup", mode = "filterStrip", auraType = "HARMFUL" },
    } } }
    E.EnsureSeeded(flat, defaultBucket)
    local seen = {}
    local allUnique = true
    for _, e in ipairs(flat.elements["*"]) do
        if not e.id or seen[e.id] then allUnique = false end
        seen[e.id or ""] = true
    end
    check("seed: id backfill + dedupe", allUnique)

    -- Fixed-id strips (defensives/encounterBoss) recur across spec buckets
    -- by DESIGN — uniqueness is per bucket, so the backfill must not rename
    -- a spec-bucket clone (a rename orphans FindBossStrip-style lookups and
    -- spawns a duplicate strip on the next write).
    local cross = { elementsSeeded = true, elements = {
        ["*"]  = { { id = "encounterBoss", mode = "filterStrip", auraType = "HARMFUL" } },
        [268]  = { { id = "encounterBoss", mode = "filterStrip", auraType = "HARMFUL" } },
    } }
    E.EnsureSeeded(cross, defaultBucket)
    check("seed: cross-bucket fixed id preserved",
        cross.elements["*"][1].id == "encounterBoss"
        and cross.elements[268][1].id == "encounterBoss")
end

-- ActiveElementsForSpec ----------------------------------------------------
do
    local auras = { elements = {
        ["*"] = { { id = "a", enabled = true }, { id = "b", enabled = false } },
        [268] = { { id = "c", enabled = true } },
    } }
    local base = E.ActiveElementsForSpec(auras, nil)
    check("active: '*' bucket, disabled filtered", #base == 1 and base[1].id == "a")
    local spec = E.ActiveElementsForSpec(auras, 268)
    check("active: spec bucket OVERRIDES (never union)", #spec == 1 and spec[1].id == "c")
    local scratch = {}
    E.ActiveElementsForSpec(auras, nil, scratch)
    check("active: reusable out-array", #scratch == 1 and scratch[1].id == "a")
end

-- Spec-override engine (load-bearing for GF; deep-copy contract) ------------
do
    -- generated-form id ("e<N>") — the clone re-keys these; fixed semantic
    -- ids are covered in the next block.
    local auras = { elements = { ["*"] = {
        { id = "e9", mode = "filterStrip", auraType = "HELPFUL", enabled = true,
          classifications = { raid = true }, whitelist = { [7] = true } },
    } } }
    E.EnableSpecOverride(auras, 268)
    check("override: bucket created", type(auras.elements[268]) == "table" and #auras.elements[268] == 1)
    check("override: HasSpecOverride true", E.HasSpecOverride(auras.elements, 268) == true)
    check("override: '*' key never overrides", E.HasSpecOverride(auras.elements, "*") == false)
    local src, copy = auras.elements["*"][1], auras.elements[268][1]
    check("override: generated id re-keyed fresh", copy.id ~= src.id)
    check("override: DEEP copy — no table aliasing",
        copy.classifications ~= src.classifications and copy.whitelist ~= src.whitelist)
    copy.classifications.raid = false
    check("override: mutating the copy leaves '*' intact", src.classifications.raid == true)
    E.EnableSpecOverride(auras, 268)
    check("override: enable is idempotent (no clobber)", auras.elements[268][1] == copy)
    E.DisableSpecOverride(auras, 268)
    check("override: disable deletes the bucket (inherits '*')", auras.elements[268] == nil)
    E.DisableSpecOverride(auras, "*")
    check("override: disable('*') is a guarded no-op", auras.elements["*"] ~= nil)
end

-- Spec-override clone: fixed semantic ids survive (2026-07 re-review). The
-- encounters page looks strips up by id ("encounterBoss"/"defensives") PER
-- BUCKET — re-keying the clone orphans it from that lookup (page reports
-- "Off") and the next write spawns a duplicate strip.
do
    local auras = { elements = { ["*"] = {
        { id = "encounterBoss", mode = "filterStrip", auraType = "HARMFUL", enabled = true },
        { id = "defensives", mode = "filterStrip", auraType = "HELPFUL", enabled = true },
        { id = "e7", mode = "tracked", displayType = "icon", spells = { 774 }, enabled = true },
    } } }
    E.EnableSpecOverride(auras, 268)
    local bucket = auras.elements[268]
    local byId = {}
    for _, e in ipairs(bucket) do byId[e.id] = e end
    check("override clone: encounterBoss id preserved", byId.encounterBoss ~= nil)
    check("override clone: defensives id preserved", byId.defensives ~= nil)
    check("override clone: generated id re-keyed", byId.e7 == nil)
    check("override clone: still 3 elements", #bucket == 3, tostring(#bucket))
    check("override clone: fixed-id element is a deep copy",
        byId.encounterBoss ~= auras.elements["*"][1])
end

-- EffectiveOnlyMine: per-spell override beats the element default, including
-- an explicit false (the `~= nil` check, not truthiness, is the contract).
do
    local e = { onlyMine = true, onlyMineSpells = { [10] = false, [20] = true } }
    check("onlyMine: explicit per-spell FALSE overrides element true", E.EffectiveOnlyMine(e, 10) == false)
    check("onlyMine: per-spell true honored", E.EffectiveOnlyMine(e, 20) == true)
    check("onlyMine: unlisted spell falls back to element", E.EffectiveOnlyMine(e, 30) == true)
    check("onlyMine: no override table falls back", E.EffectiveOnlyMine({ onlyMine = false }, 10) == false)
end

-- Flags mode polarity guard: HELPFUL-only tokens never reach a HARMFUL string
-- (HARMFUL|RAID_IN_COMBAT hard-errors in C_UnitAuras.GetUnitAuras).
do
    local d = E.NewFilterStripElement("HARMFUL")
    d.filterMode = "flags"
    d.filterFlags = { PLAYER = true, RAID_IN_COMBAT = true }
    local fs = E.CompileFilters(d)
    check("flags: HARMFUL drops HELPFUL-only tokens", #fs == 1 and fs[1] == "HARMFUL|PLAYER", tostring(fs[1]))
    d.filterFlags = { RAID_IN_COMBAT = true }
    check("flags: HARMFUL with only invalid tokens → empty (bare polarity fallback)",
        #E.CompileFilters(d) == 0)
    local b = E.NewFilterStripElement("HELPFUL")
    b.filterMode = "flags"
    b.filterFlags = { RAID_IN_COMBAT = true }
    check("flags: HELPFUL keeps RAID_IN_COMBAT", E.CompileFilters(b)[1] == "HELPFUL|RAID_IN_COMBAT")
end

-- NormalizeElement edge branches --------------------------------------------
do
    local hidden = { mode = "filterStrip", auraType = "HELPFUL", showDurationText = false }
    E.NormalizeElement(hidden)
    check("normalize: showDurationText=false → duration.show false", hidden.duration.show == false)
    -- Legacy GF editor spelling: without this heal, a classified strip
    -- compiles {} → bare polarity → shows EVERYTHING (silent regression).
    local legacyMode = { mode = "filterStrip", auraType = "HARMFUL",
                         filterMode = "classification", classifications = { raid = true } }
    E.NormalizeElement(legacyMode)
    check("normalize: legacy 'classification' → canonical 'classify'", legacyMode.filterMode == "classify")
    check("normalize: healed strip still compiles its classifications",
        E.CompileFilters(legacyMode)[1] == "HARMFUL|RAID")
    local tracked = { mode = "tracked", displayType = "icon", spells = { 1 } }
    E.NormalizeElement(tracked)
    check("normalize: tracked gains auraType default", tracked.auraType == "HELPFUL")
end

-- EnsureSeeded advances idCounter past persisted eN ids (fresh ids never collide)
do
    local auras = { elementsSeeded = true, elements = { ["*"] = {
        { id = "e9000", mode = "filterStrip", auraType = "HELPFUL" },
    } } }
    E.EnsureSeeded(auras, nil)
    local fresh = E.NewFilterStripElement("HELPFUL")
    check("seed: idCounter advanced past persisted eN ids",
        tonumber(fresh.id:match("^e(%d+)$")) > 9000, tostring(fresh.id))
end

-- Filter expansion: new model fields + normalization ----------------------
do
    local e = E.NewFilterStripElement("HELPFUL")
    check("strip: dispel filter defaults", e.dispelFilterMode == "off" and type(e.dispelTypes) == "table")
    check("strip: maxDurationSec defaults 0", e.maxDurationSec == 0)

    local legacy = { mode = "filterStrip", auraType = "HELPFUL",
        filterFlags = { PLAYER = 1, RAID = true, CANCELABLE = "exclude", BAD = false } }
    E.NormalizeElement(legacy)
    check("normalize: dispel/maxDuration seeded", legacy.dispelFilterMode == "off"
        and type(legacy.dispelTypes) == "table" and legacy.maxDurationSec == 0)
    check("normalize: filterFlags values coerced to true/'exclude'/absent",
        legacy.filterFlags.PLAYER == true and legacy.filterFlags.RAID == true
        and legacy.filterFlags.CANCELABLE == "exclude" and legacy.filterFlags.BAD == nil)
end

-- Filter expansion: tri-state flags compile ------------------------------
do
    local e = E.NewFilterStripElement("HELPFUL")
    e.filterMode = "flags"
    e.filterFlags = { PLAYER = true, RAID = true }
    local out = E.CompileFilters(e)
    check("flags: legacy require-only output unchanged", #out == 1 and out[1] == "HELPFUL|PLAYER|RAID")

    e.filterFlags = { RAID = true, CANCELABLE = "exclude", PLAYER = "exclude" }
    out = E.CompileFilters(e)
    check("flags: excludes negated, sorted, after requires",
        #out == 1 and out[1] == "HELPFUL|RAID|!CANCELABLE|!PLAYER")

    e.filterFlags = { CANCELABLE = "exclude" }
    out = E.CompileFilters(e)
    check("flags: exclude-only keeps polarity lead", #out == 1 and out[1] == "HELPFUL|!CANCELABLE")

    local h = E.NewFilterStripElement("HARMFUL")
    h.filterMode = "flags"
    h.filterFlags = { RAID_IN_COMBAT = "exclude", RAID = true }
    out = E.CompileFilters(h)
    check("flags: HELPFUL-only token dropped both directions on HARMFUL",
        #out == 1 and out[1] == "HARMFUL|RAID")

    h.filterFlags = {}
    check("flags: empty set compiles to no strings", #E.CompileFilters(h) == 0)

    -- v51 repair invariant: out-of-set tokens never reach the engine, in
    -- EITHER direction (a negated unknown token still hard-errors AddAuraGroup).
    local w = E.NewFilterStripElement("HELPFUL")
    w.filterMode = "flags"
    w.filterFlags = { modifiers = true, exclusive = "exclude", RAID = true }
    out = E.CompileFilters(w)
    check("flags: out-of-set tokens dropped both directions",
        #out == 1 and out[1] == "HELPFUL|RAID")
end

-- Filter expansion: candidateFilters compile ------------------------------
do
    local e = E.NewFilterStripElement("HARMFUL")
    e.dispelFilterMode = "include"
    e.dispelTypes = { Magic = true, Poison = false }
    local cf = E.CompileCandidateFilters(e)
    check("cf: dispel include set", cf ~= nil and cf.includeDispelTypes ~= nil
        and cf.includeDispelTypes.Magic == true and cf.includeDispelTypes.Poison == nil
        and cf.excludeDispelTypes == nil)

    e.dispelFilterMode = "exclude"
    cf = E.CompileCandidateFilters(e)
    check("cf: dispel exclude set", cf ~= nil and cf.excludeDispelTypes ~= nil
        and cf.excludeDispelTypes.Magic == true and cf.includeDispelTypes == nil)

    e.dispelTypes = { Magic = false }
    cf = E.CompileCandidateFilters(e)
    check("cf: empty enabled dispel set is inert", cf == nil)

    -- "mine" sentinel (legacy "dispellable" preset SVs + the manual
    -- dispel-type UI): resolves player capability at compile time via
    -- ns.QUI_DispelRoles. The preset itself now compiles to the engine's
    -- HARMFUL|RAID classification instead (68675 player-dispellable).
    local m = E.NewFilterStripElement("HARMFUL")
    m.dispelFilterMode = "include"
    m.dispelTypes = "mine"
    check("model: 'mine' sentinel stored", m.dispelTypes == "mine", tostring(m.dispelTypes))

    local prevDR = ns.QUI_DispelRoles
    ns.QUI_DispelRoles = { PlayerDispelSchools = function() return { Magic = true, Poison = true } end }
    cf = E.CompileCandidateFilters(m)
    check("cf: 'mine' sentinel resolves capability schools",
        cf ~= nil and cf.includeDispelTypes ~= nil
        and cf.includeDispelTypes.Magic == true and cf.includeDispelTypes.Poison == true
        and cf.includeDispelTypes.Curse == nil and cf.includeDispelTypes.Disease == nil)

    -- A dispel-less class (empty capability) must match NOTHING — an empty
    -- include set would emit no filter at all and broaden to every debuff.
    ns.QUI_DispelRoles = { PlayerDispelSchools = function() return {} end }
    cf = E.CompileCandidateFilters(m)
    local firstKey = cf and cf.includeDispelTypes and next(cf.includeDispelTypes)
    check("cf: empty capability -> match-nothing include set",
        firstKey == "QUI-none"
        and next(cf.includeDispelTypes, firstKey) == nil,
        tostring(firstKey))

    -- Missing module (or a resolve error): fall back to the 4 base schools.
    ns.QUI_DispelRoles = nil
    cf = E.CompileCandidateFilters(m)
    check("cf: missing module -> 4-school fallback",
        cf ~= nil and cf.includeDispelTypes ~= nil
        and cf.includeDispelTypes.Magic and cf.includeDispelTypes.Curse
        and cf.includeDispelTypes.Disease and cf.includeDispelTypes.Poison)
    ns.QUI_DispelRoles = prevDR

    local d = E.NewFilterStripElement("HELPFUL")
    d.maxDurationSec = 90
    d.hidePermanent = true
    cf = E.CompileCandidateFilters(d)
    check("cf: maxDurationSec wins over hidePermanent", cf ~= nil and cf.maxDuration == 90)
    d.maxDurationSec = 0
    cf = E.CompileCandidateFilters(d)
    check("cf: hidePermanent alone still emits 999999", cf ~= nil and cf.maxDuration == 999999)

    local g = E.NewFilterStripElement("HELPFUL")
    g.gateStealable = true; g.gateBossAura = true; g.gatePriorityAura = true
    g.gateRoleAura = true; g.gateBossOrRoleAura = true
    cf = E.CompileCandidateFilters(g)
    check("cf: gates map to true-only engine fields", cf ~= nil
        and cf.isStealable == true and cf.isBossAura == true and cf.isPriorityAura == true
        and cf.isRoleAura == true and cf.isBossOrRoleAura == true)

    local off = E.NewFilterStripElement("HELPFUL")
    off.gateStealable = false
    cf = E.CompileCandidateFilters(off)
    check("cf: false gates emit nothing (engine rejects false)", cf == nil)

    local plain = E.NewFilterStripElement("HELPFUL")
    check("cf: untouched element still compiles to nil", E.CompileCandidateFilters(plain) == nil)
end

-- NOT_CANCELABLE engine-removal heal ---------------------------------------
-- The engine dropped NOT_CANCELABLE from AuraUtil.AuraFilters (build 68569);
-- the replacement is CANCELABLE excluded ("!CANCELABLE").
do
    -- (a) NormalizeElement heals a legacy require into CANCELABLE="exclude"
    -- and drops the dead token.
    local legacy = { mode = "filterStrip", auraType = "HELPFUL",
        filterFlags = { NOT_CANCELABLE = true } }
    E.NormalizeElement(legacy)
    check("heal: NOT_CANCELABLE require -> CANCELABLE exclude",
        legacy.filterFlags.CANCELABLE == "exclude", tostring(legacy.filterFlags.CANCELABLE))
    check("heal: NOT_CANCELABLE removed", legacy.filterFlags.NOT_CANCELABLE == nil)

    -- (b) An existing CANCELABLE value is never clobbered — the legacy token
    -- just drops.
    local conflict = { mode = "filterStrip", auraType = "HELPFUL",
        filterFlags = { NOT_CANCELABLE = true, CANCELABLE = true } }
    E.NormalizeElement(conflict)
    check("heal: existing CANCELABLE value not clobbered",
        conflict.filterFlags.CANCELABLE == true, tostring(conflict.filterFlags.CANCELABLE))
    check("heal: NOT_CANCELABLE removed even when CANCELABLE already set",
        conflict.filterFlags.NOT_CANCELABLE == nil)

    -- (c) Unhealed direct compile: NOT_CANCELABLE is no longer in
    -- VALID_FILTER_TOKENS, so a raw filterFlags table carrying it emits NO
    -- string for that token (CompileFilters drops out-of-set tokens).
    local raw = E.NewFilterStripElement("HELPFUL")
    raw.filterMode = "flags"
    raw.filterFlags = { NOT_CANCELABLE = "exclude" }
    check("heal: unhealed NOT_CANCELABLE compiles to nothing (dropped token)",
        #E.CompileFilters(raw) == 0)

    -- (d) Classify mode: notCancelable now compiles to "HELPFUL|!CANCELABLE"
    -- (helpful=false to isolate — the 'helpful' master key would otherwise
    -- also emit RAID/RAID_IN_COMBAT).
    local classify = E.NewFilterStripElement("HELPFUL")
    classify.filterMode = "classify"
    classify.classifications = { helpful = false, notCancelable = true }
    local cfs = E.CompileFilters(classify)
    check("heal: classify notCancelable compiles to HELPFUL|!CANCELABLE",
        #cfs == 1 and cfs[1] == "HELPFUL|!CANCELABLE", table.concat(cfs, ","))
end

do
    local legacy = { mode = "filterStrip", auraType = "HARMFUL",
        filterFlags = { INCLUDE_NAME_PLATE_ONLY = true } }
    E.NormalizeElement(legacy)
    check("heal: INCLUDE_NAME_PLATE_ONLY require -> nameplateOnly true",
        legacy.nameplateOnly == true, tostring(legacy.nameplateOnly))
    check("heal: INCLUDE_NAME_PLATE_ONLY removed",
        legacy.filterFlags.INCLUDE_NAME_PLATE_ONLY == nil)
    check("heal: nameplateOnly no longer forces Custom…",
        E.DeriveWhatToShow(legacy) == "all", tostring(E.DeriveWhatToShow(legacy)))

    local cfs2 = E.CompileFilters(legacy)
    local tokenCount = 0
    for _, fs in ipairs(cfs2) do
        for component in fs:gmatch("[^| ]+") do
            if component == "INCLUDE_NAME_PLATE_ONLY" then tokenCount = tokenCount + 1 end
        end
    end
    check("heal: compiled filter carries the token exactly once",
        tokenCount == 1, tostring(tokenCount))

    local preset = { mode = "filterStrip", auraType = "HARMFUL", nameplateOnly = false,
        filterFlags = { INCLUDE_NAME_PLATE_ONLY = true } }
    E.NormalizeElement(preset)
    check("heal: existing nameplateOnly value not clobbered",
        preset.nameplateOnly == false, tostring(preset.nameplateOnly))
    check("heal: INCLUDE_NAME_PLATE_ONLY removed even when nameplateOnly already set",
        preset.filterFlags.INCLUDE_NAME_PLATE_ONLY == nil)

    local excluded = { mode = "filterStrip", auraType = "HARMFUL",
        filterFlags = { INCLUDE_NAME_PLATE_ONLY = "exclude" } }
    E.NormalizeElement(excluded)
    check("heal: INCLUDE_NAME_PLATE_ONLY exclude drops inert, does not force nameplateOnly",
        excluded.filterFlags.INCLUDE_NAME_PLATE_ONLY == nil and excluded.nameplateOnly == nil,
        tostring(excluded.nameplateOnly))
end

do
    local folded = { duration = { pandemicColor = { 0.9, 0.1, 0.1 } } }
    E.NormalizeElement(folded)
    check("pandemic fold: duration.pandemicColor scrubbed", folded.duration.pandemicColor == nil)
    check("pandemic fold: color seeds pandemicGlow",
        type(folded.pandemicGlow) == "table" and folded.pandemicGlow.color[1] == 0.9
            and folded.pandemicGlow.color[2] == 0.1 and folded.pandemicGlow.color[4] == 1)

    local kept = { duration = { pandemicColor = { 0.9, 0.1, 0.1 } },
        pandemicGlow = { color = { 0.2, 0.2, 1, 1 } } }
    E.NormalizeElement(kept)
    check("pandemic fold: existing pandemicGlow not clobbered",
        kept.pandemicGlow.color[1] == 0.2 and kept.duration.pandemicColor == nil)

    local plain = { duration = { show = true } }
    E.NormalizeElement(plain)
    check("pandemic fold: no old key means no seeded glow", plain.pandemicGlow == nil)
end

print("aura_elements_model_test " .. (failures == 0 and "OK" or "FAILED"))
os.exit(failures == 0 and 0 or 1)
