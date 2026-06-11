-- tests/unit/bags_search_compiler_test.lua
-- Run: lua tests/unit/bags_search_compiler_test.lua
local loader = dofile("tests/helpers/load_bags_data.lua")
local ns = loader.LoadAll()
local chunk = assert(loadfile("QUI_Bags/bags/search/compiler.lua"))
chunk("QUI", ns)
local Compiler = ns.Bags.Search

-- NIL sentinel: Lua table literals drop nil values, so Dnil({field=NIL}) explicitly nils a base field.
-- D(over) is a convenience alias that delegates to Dnil for non-nil overrides.
local NIL = {}
local function Dnil(over)
    local d = { name = "Linen Cloth", quality = 1, classID = 7, subClassID = 5,
                equipLoc = "", ilvl = 5, count = 20, isBound = false, itemID = 2589, expacID = 0 }
    for k, v in pairs(over or {}) do
        if v == NIL then d[k] = nil else d[k] = v end
    end
    return d
end
local function D(over) return Dnil(over) end

-- Test 1: empty/whitespace query matches everything
assert(Compiler.Compile("")(D()) == true, "empty query must match")
assert(Compiler.Compile("   ")(D()) == true, "blank query must match")

-- Test 2: name substring, case-insensitive
assert(Compiler.Compile("linen")(D()) == true, "substring match failed")
assert(Compiler.Compile("LINEN")(D()) == true, "case-insensitive failed")
assert(Compiler.Compile("silk")(D()) == false, "non-match failed")
assert(Compiler.Compile("linen")(Dnil({ name = NIL })) == nil, "missing name must be pending (nil)")

-- Test 3: quality keywords
assert(Compiler.Compile("uncommon")(D({ quality = 2 })) == true, "quality keyword failed")
assert(Compiler.Compile("epic")(D({ quality = 2 })) == false, "quality non-match failed")
assert(Compiler.Compile("poor")(D({ quality = 0 })) == true, "poor failed")

-- Test 4: class keywords
assert(Compiler.Compile("reagent")(D({ classID = 7 })) == true, "tradegoods=reagent failed")
assert(Compiler.Compile("gear")(D({ classID = 4, equipLoc = "INVTYPE_HEAD" })) == true, "armor=gear failed")
assert(Compiler.Compile("equipment")(D({ classID = 2 })) == true, "weapon=equipment failed")
assert(Compiler.Compile("quest")(D({ classID = 12 })) == true, "quest class failed")
assert(Compiler.Compile("junk")(D({ quality = 0 })) == true, "junk=poor failed")
assert(Compiler.Compile("soulbound")(D({ isBound = true })) == true, "soulbound failed")
assert(Compiler.Compile("pet")(D({ classID = 17 })) == true, "battlepet failed")

-- Test 5: equip slot keywords
assert(Compiler.Compile("head")(D({ equipLoc = "INVTYPE_HEAD" })) == true, "slot keyword failed")
assert(Compiler.Compile("trinket")(D({ equipLoc = "INVTYPE_TRINKET" })) == true, "trinket failed")
assert(Compiler.Compile("head")(D({ equipLoc = "INVTYPE_FEET" })) == false, "slot non-match failed")

-- Test 6: expansion keywords
assert(Compiler.Compile("classic")(D({ expacID = 0 })) == true, "classic expac failed")
assert(Compiler.Compile("midnight")(D({ expacID = 11 })) == true, "midnight expac failed")
assert(Compiler.Compile("classic")(Dnil({ expacID = NIL })) == nil, "missing expac must be pending")

-- Test 7: numeric ilvl
assert(Compiler.Compile("<400")(D({ ilvl = 350 })) == true, "< failed")
assert(Compiler.Compile(">400")(D({ ilvl = 350 })) == false, "> failed")
assert(Compiler.Compile("=350")(D({ ilvl = 350 })) == true, "= failed")
assert(Compiler.Compile("300-400")(D({ ilvl = 350 })) == true, "range failed")
assert(Compiler.Compile("300-340")(D({ ilvl = 350 })) == false, "range exclusion failed")
assert(Compiler.Compile("<400")(Dnil({ ilvl = NIL })) == nil, "missing ilvl must be pending")

-- Test 8: operators ~ & |
assert(Compiler.Compile("~linen")(D()) == false, "negation failed")
assert(Compiler.Compile("~silk")(D()) == true, "negation pass failed")
assert(Compiler.Compile("linen&reagent")(D()) == true, "AND failed")
assert(Compiler.Compile("linen&epic")(D()) == false, "AND short failed")
assert(Compiler.Compile("silk|linen")(D()) == true, "OR failed")
assert(Compiler.Compile("silk|wool")(D()) == false, "OR none failed")
assert(Compiler.Compile("silk|linen&reagent")(D()) == true, "precedence (& binds tighter) failed")
-- bare spaces between terms = AND
assert(Compiler.Compile("linen reagent")(D()) == true, "space-AND failed")
assert(Compiler.Compile("linen epic")(D()) == false, "space-AND short failed")

-- Test 9: pending propagation — AND with one pending and one false is false;
-- AND with one pending and one true is pending; OR with pending+true is true
-- Base record: quality=1 (common), so "epic" is false. expacID=0, but we need it nil.
-- epic&classic: epic=false, classic=pending(expacID nil) → false&pending = false
assert(Compiler.Compile("epic&classic")(Dnil({ expacID = NIL })) == false, "false&pending must be false")
-- linen&classic: linen=true (name="Linen Cloth"), classic=pending → true&pending = pending
assert(Compiler.Compile("linen&classic")(Dnil({ expacID = NIL })) == nil, "true&pending must be pending")
-- linen|classic: linen=true, classic=pending → true|pending = true
assert(Compiler.Compile("linen|classic")(Dnil({ expacID = NIL })) == true, "true|pending must be true")

-- Test 10: compile is cached (same query returns same matcher)
assert(Compiler.Compile("linen") == Compiler.Compile("linen"), "matcher cache failed")

-- Test 11: deliberate tradeoffs + grammar edges pinned
assert(Compiler.Compile("bag")(Dnil({ name = "Bag of Marbles", equipLoc = "" })) == false,
       "slot keyword must shadow name substring")
assert(Compiler.Compile("~classic")(Dnil({ expacID = NIL })) == nil, "~pending must stay pending")
assert(Compiler.Compile("~~linen")(D()) == true, "double negation failed")
assert(Compiler.Compile("trash")(Dnil({ quality = 0 })) == true, "trash alias failed")
assert(Compiler.Compile("  linen  ") == Compiler.Compile("linen"), "trim-cache identity failed")
assert(Compiler.Compile("linen|")(D()) == true, "trailing pipe failed")
assert(Compiler.Compile("silk||wool")(D()) == false, "double pipe must not match-all")
assert(Compiler.Compile("linen reagent|epic")(D()) == true, "AND inside first or-group failed")

print("OK: bags_search_compiler_test")
