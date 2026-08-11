-- tests/unit/aura_filter_canonicalize_test.lua
-- Wave 4 Task 4 (4a): property tests for core/aura_elements.lua's
-- E.CanonicalizeFilterString + its internal validity guard.
--
-- "C-probe" cross-check (per the aura-filter-expansion validator+C-probe
-- pattern this task was told to reuse): rather than trust our own local
-- mirror of the engine's grammar, this file loads the REAL vendored
-- AuraUtil.IsValidFilterString (tests/framexml/.../Blizzard_FrameXMLUtil/
-- AuraUtil.lua) and asserts our canonicalization preserves ITS verdict, not
-- just our own. Only the AuraFilters/CreateFilterString/IsValidFilterString
-- slice is loaded (the full file pulls in CVarCallbackRegistry machinery
-- that has nothing to do with filter-string validation) — same slice-load
-- technique as tests/unit/test_form_slider_init.lua's generator-preamble cut.
--
-- Run: lua5.1 tests/unit/aura_filter_canonicalize_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

----------------------------------------------------------------------------
-- Load the real engine validator (TableUtil -> EnumUtil -> AuraUtil slice).
-- string.split needs a WoW-faithful implementation: delimiter argument is a
-- SET of characters (each char is its own delimiter), consecutive
-- delimiters produce EMPTY pieces (not skipped) — verified against the
-- AuraUtil.lua doc comment at :292-294 ("skipping empty components as
-- strsplit's tokenizer doesn't skip chains of delimiters" — i.e. the
-- SPLITTER doesn't skip them, IsValidFilterString's caller does).
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
-- string.split is a WoW-provided extension to the stdlib string table (not
-- stock Lua 5.1) — luacheck flags the field as undefined on both the
-- global-lib and the vendored AuraUtil.lua source that calls it; both are
-- correct-as-written, so silence the two resulting warnings by name.
-- luacheck: ignore 142/string 143/string
string.split = function(delimiters, str)
    return (table.unpack or unpack)(wowSplit(delimiters, str))
end

-- Self-check the split stub against the exact case AuraUtil.lua's own
-- comment documents, BEFORE trusting it for the real cross-check below.
do
    local pieces = { string.split("| ", "HELPFUL | RAID") }
    check("string.split stub: pipe+space delimiter set, empties preserved",
        #pieces == 4 and pieces[1] == "HELPFUL" and pieces[2] == "" and pieces[3] == ""
        and pieces[4] == "RAID", table.concat(pieces, "/"))
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
check("E.CanonicalizeFilterString exported", type(E.CanonicalizeFilterString) == "function")
check("E.IsKnownFilterString exported", type(E.IsKnownFilterString) == "function")

local Canon = E.CanonicalizeFilterString

----------------------------------------------------------------------------
-- Cross-check helper: both the real engine validator AND our own guard must
-- agree that canonicalization never changes IsValidFilterString's verdict.
----------------------------------------------------------------------------
local function checkPreservesValidity(raw)
    local canonical = Canon(raw)
    local rawValid = RealIsValid(raw)
    local canonValid = RealIsValid(canonical)
    check(("validity preserved (real engine validator): %q -> %q"):format(raw, canonical),
        rawValid == canonValid,
        ("raw=%s canonical=%s"):format(tostring(rawValid), tostring(canonValid)))
end

----------------------------------------------------------------------------
-- Idempotence: Canonicalize(Canonicalize(x)) == Canonicalize(x)
----------------------------------------------------------------------------
do
    local samples = {
        "HELPFUL|RAID", "HARMFUL|RAID|CROWD_CONTROL", "HELPFUL|!CANCELABLE",
        "HELPFUL|RAID|!CANCELABLE|!PLAYER", "HELPFUL", "HARMFUL",
        "HELPFUL | RAID | PLAYER", "HELPFUL|RAID|RAID", -- duplicate token
        "", "HELPFUL|BOGUS", "HELPFUL|!", "helpful|raid", -- invalid/edge inputs
    }
    for _, s in ipairs(samples) do
        local once = Canon(s)
        local twice = Canon(once)
        check(("idempotent: %q"):format(s), once == twice,
            ("once=%q twice=%q"):format(tostring(once), tostring(twice)))
    end
end

----------------------------------------------------------------------------
-- Order-insensitivity: every permutation of a token set canonicalizes to
-- the SAME string (sorted-within-commutative-scopes convention, matching
-- CompileFilters' existing polarity-first / requires-sorted / !excludes-
-- sorted output shape).
----------------------------------------------------------------------------
do
    local permutations = {
        "HELPFUL|RAID|PLAYER", "RAID|HELPFUL|PLAYER", "PLAYER|RAID|HELPFUL",
        "PLAYER|HELPFUL|RAID",
    }
    local want = "HELPFUL|PLAYER|RAID"
    for _, s in ipairs(permutations) do
        check(("order-insensitive: %q -> %q"):format(s, want), Canon(s) == want, Canon(s))
    end

    -- Whitespace variants of the same set collapse identically too.
    local wsVariants = { "HELPFUL | RAID | PLAYER", "HELPFUL   RAID  PLAYER", "HELPFUL|RAID PLAYER" }
    for _, s in ipairs(wsVariants) do
        check(("whitespace-insensitive: %q -> %q"):format(s, want), Canon(s) == want, Canon(s))
    end

    -- Tri-state tokens sort WITHIN their own scope (requires, then
    -- !excludes), independent of input order.
    local triPermutations = {
        "HELPFUL|RAID|!CANCELABLE|!PLAYER", "HELPFUL|!PLAYER|RAID|!CANCELABLE",
        "!CANCELABLE|!PLAYER|RAID|HELPFUL", "!PLAYER|HELPFUL|!CANCELABLE|RAID",
    }
    local triWant = "HELPFUL|RAID|!CANCELABLE|!PLAYER"
    for _, s in ipairs(triPermutations) do
        check(("tri-state order-insensitive: %q -> %q"):format(s, triWant), Canon(s) == triWant, Canon(s))
    end
end

----------------------------------------------------------------------------
-- Tri-state preservation: require vs exclude never cross buckets, and the
-- SAME token required+excluded simultaneously (contradictory but
-- structurally valid per the engine) keeps BOTH — canonicalization must not
-- invent a "resolution" that isn't there.
----------------------------------------------------------------------------
do
    check("tri-state: require-only", Canon("HELPFUL|RAID|PLAYER") == "HELPFUL|PLAYER|RAID")
    check("tri-state: exclude-only keeps polarity lead",
        Canon("HELPFUL|!CANCELABLE") == "HELPFUL|!CANCELABLE")
    check("tri-state: mixed require+exclude, requires before excludes",
        Canon("HELPFUL|!PLAYER|RAID") == "HELPFUL|RAID|!PLAYER")
    check("tri-state: same token required AND excluded — both survive independently",
        Canon("HELPFUL|RAID|!RAID") == "HELPFUL|RAID|!RAID")
    check("tri-state: no polarity token still buckets require/exclude correctly",
        Canon("RAID|!CANCELABLE") == "RAID|!CANCELABLE")
end

----------------------------------------------------------------------------
-- Dedup: exact-duplicate tokens (require or exclude) collapse to one.
----------------------------------------------------------------------------
do
    check("dedup: duplicate require token", Canon("HELPFUL|RAID|RAID|PLAYER") == "HELPFUL|PLAYER|RAID")
    check("dedup: duplicate exclude token", Canon("HELPFUL|!CANCELABLE|!CANCELABLE") == "HELPFUL|!CANCELABLE")
end

----------------------------------------------------------------------------
-- Validity preservation — cross-checked against the REAL engine validator.
----------------------------------------------------------------------------
do
    -- Valid inputs (various order/whitespace): must stay valid after canon.
    for _, s in ipairs({
        "HELPFUL|RAID", "RAID|HELPFUL|!CANCELABLE", "HELPFUL | RAID | PLAYER",
        "HARMFUL|CROWD_CONTROL", "HELPFUL", "HARMFUL|RAID|RAID",
    }) do
        checkPreservesValidity(s)
    end

    -- Invalid inputs: must STAY invalid (passthrough, not "repaired" into
    -- validity) — this is the specific invariant the brief calls out as a
    -- canonicalization bug if violated.
    for _, s in ipairs({
        "HELPFUL|BOGUS",       -- unknown token
        "HELPFUL|!",           -- bare negation
        "!",                   -- bare negation, no other content
    }) do
        checkPreservesValidity(s)
        check(("invalid input passes through UNCHANGED: %q"):format(s), Canon(s) == s, Canon(s))
    end

    -- Case-only-invalid input: documented, deliberate scope limit (see
    -- core/aura_elements.lua comment above CanonicalizeFilterString) — the
    -- function does NOT case-fold raw text to manufacture validity, so this
    -- one is passthrough too, NOT "HELPFUL|RAID".
    check("case-invalid input is NOT case-folded into validity",
        Canon("helpful|raid") == "helpful|raid", Canon("helpful|raid"))
    checkPreservesValidity("helpful|raid")

    -- Whitespace-class trap (review counterexample): the engine's delimiter
    -- set is the LITERAL pair "|" and space — NOT the %s class. A tab (or
    -- newline) is component TEXT to the engine, so "HELPFUL\tRAID" is ONE
    -- unknown component = INVALID raw. Canonicalization must NOT treat the
    -- tab as a separator (a %s tokenizer would re-emit "HELPFUL|RAID",
    -- flipping invalid -> valid): the guard must reject these and the
    -- function must pass them through unchanged, preserving invalidity per
    -- the REAL validator.
    for _, s in ipairs({ "HELPFUL\tRAID", "HELPFUL\nRAID", "HELPFUL\t|RAID" }) do
        check(("tab/newline is NOT a delimiter — guard rejects: %q"):format(s),
            E.IsKnownFilterString(s) == false)
        check(("tab/newline-bearing input passes through UNCHANGED: %q"):format(s),
            Canon(s) == s, Canon(s))
        checkPreservesValidity(s)
    end

    -- Empty string: the real engine validator quirk-accepts "" as valid
    -- (no components to reject); our function passes it through unchanged,
    -- which trivially preserves whatever the real validator says about it.
    checkPreservesValidity("")
end

----------------------------------------------------------------------------
-- Mutation-verify: assertions specific enough that plausible one-line
-- mutations to CanonicalizeFilterString/IsKnownFilterString fail at least
-- one check above.
--   - drop `table.sort(req)`            -> order-insensitivity fails
--   - drop `table.sort(exc)`            -> tri-state order-insensitivity fails
--   - swap negated/non-negated bucket   -> tri-state preservation fails
--   - drop the dedup `Seen` guards      -> dedup fails
--   - drop the IsKnownFilterString guard (canonicalize unconditionally)
--     -> "helpful|raid" would become "HELPFUL|RAID" (case-invalid input NOT
--        case-folded check fails) AND "HELPFUL|!" would lose its bare "!"
--        (invalid-input-unchanged check fails)
--   - drop the bare-"!" rejection in IsKnownFilterString -> "HELPFUL|!"
--     would canonicalize (dropping the malformed component), flipping
--     invalid raw -> valid canonical (validity-preservation check fails)
--   - widen the tokenizer delimiter set from the engine's literal "[^| ]+"
--     to the %s class "[^|%s]+" (in either function) -> the tab/newline
--     trap cases fail: the guard would accept "HELPFUL\tRAID" and Canon
--     would re-emit it as "HELPFUL|RAID" (guard-rejects + passthrough +
--     validity-preservation checks all fail)
--   - swap polarity-first ordering      -> permutation-target string check
--     ("HELPFUL|PLAYER|RAID") fails since polarity would sort into the
--     middle alphabetically instead of leading
----------------------------------------------------------------------------
check("mutation-guard: polarity leads even when alphabetically NOT first",
    Canon("RAID|PLAYER|HELPFUL") == "HELPFUL|PLAYER|RAID")

print("aura_filter_canonicalize_test " .. (failures == 0 and "OK" or "FAILED"))
os.exit(failures == 0 and 0 or 1)
