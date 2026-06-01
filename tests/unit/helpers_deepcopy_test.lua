-- tests/unit/helpers_deepcopy_test.lua
-- Run: lua tests/unit/helpers_deepcopy_test.lua
--
-- Canonical deep/shallow copy helpers. The codebase had 5+ near-identical local
-- DeepCopy/CloneValue implementations; one (migrations.lua) lacked a cycle guard
-- and would stack-overflow on a self-referential table. This pins the shared
-- Helpers.DeepCopy / Helpers.ShallowCopy behaviour so the duplicates can be
-- routed through it: deep independence, cycle safety, shared-reference identity,
-- and non-table passthrough.

function LibStub() return nil end

local ns = {}
assert(loadfile("core/utils.lua"))("QUI", ns)
local H = ns.Helpers

local DeepCopy = assert(H.DeepCopy, "Helpers.DeepCopy should be exported")
local ShallowCopy = assert(H.ShallowCopy, "Helpers.ShallowCopy should be exported")

-- Non-tables pass through unchanged.
assert(DeepCopy(5) == 5, "number passthrough")
assert(DeepCopy("x") == "x", "string passthrough")
assert(DeepCopy(nil) == nil, "nil passthrough")
assert(DeepCopy(true) == true, "boolean passthrough")

-- Deep independence: every level is cloned, values preserved.
local orig = { a = 1, nested = { b = 2, list = { 3, 4 } } }
local copy = DeepCopy(orig)
assert(copy ~= orig, "copy must be a new table")
assert(copy.nested ~= orig.nested, "nested tables must be cloned")
assert(copy.nested.list ~= orig.nested.list, "deeply nested tables must be cloned")
assert(copy.a == 1 and copy.nested.b == 2 and copy.nested.list[1] == 3, "values preserved")
copy.nested.b = 99
copy.nested.list[1] = 99
assert(orig.nested.b == 2, "mutating the copy must not affect the original")
assert(orig.nested.list[1] == 3, "mutating a deep copy must not affect the original")

-- Cycle safety: a self-referential table must not stack-overflow, and the cycle
-- must be preserved by reference rather than expanded infinitely.
local cyclic = { name = "root" }
cyclic.self = cyclic
local cc = DeepCopy(cyclic)
assert(cc ~= cyclic, "cyclic copy is a new table")
assert(cc.self == cc, "cycle preserved by reference")
assert(cc.name == "root", "cyclic copy keeps scalar fields")

-- Shared subtable referenced by two keys is copied once (identity preserved).
local shared = { x = 1 }
local src = { a = shared, b = shared }
local d = DeepCopy(src)
assert(d.a == d.b, "shared subtables copied once (identity preserved)")
assert(d.a ~= shared, "shared subtable is still a copy, not the original")

-- ShallowCopy: new top-level table, nested tables shared.
local s = ShallowCopy(orig)
assert(s ~= orig, "shallow copy is a new table")
assert(s.nested == orig.nested, "shallow copy shares nested tables by reference")
assert(s.a == 1, "shallow copy preserves top-level values")
assert(ShallowCopy(7) == 7, "shallow copy of a non-table returns it as-is")

print("helpers_deepcopy_test: OK")
