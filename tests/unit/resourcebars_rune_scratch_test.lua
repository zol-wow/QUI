-- tests/unit/resourcebars_rune_scratch_test.lua
-- Run: lua tests/unit/resourcebars_rune_scratch_test.lua
--
-- The rune refresh allocated readyList/cdList/per-rune records/a sort
-- closure/displayOrder/readyLookup/cdLookup on every RUNE_POWER_UPDATE
-- (continuous for DKs). It must reuse pooled records (runeScratch/runeOrder)
-- and a static total-order comparator (ready first stable by index, then
-- ascending remaining — table.sort is not stable, so the comparator carries
-- the index tiebreak).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_ResourceBars/resourcebars/resourcebars.lua")

assert(source:find("local function RuneDisplayLess(a, b)", 1, true),
    "static rune comparator must exist")
assert(source:find("local runeScratch = {}", 1, true),
    "pooled rune record scratch must exist")
assert(source:find("local runeOrder = {}", 1, true),
    "reusable rune order array must exist")
assert(source:find("table.sort(runeOrder, RuneDisplayLess)", 1, true),
    "rune ordering must sort the reused array with the static comparator")

assert(not source:find("local readyList = {}", 1, true),
    "per-refresh readyList allocation must be gone")
assert(not source:find("local displayOrder = {}", 1, true),
    "per-refresh displayOrder allocation must be gone")
assert(not source:find("local cdLookup = {}", 1, true),
    "per-refresh cdLookup allocation must be gone")

print("PASS resourcebars_rune_scratch_test")
