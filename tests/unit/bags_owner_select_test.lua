-- tests/unit/bags_owner_select_test.lua
-- Run: lua tests/unit/bags_owner_select_test.lua
-- Pure parts of the owner selector: OwnerSelect.BuildOwnerList(keys,
-- currentKey) — the {key,label} entries the header menu renders. Order
-- follows the (already sorted) store keys; the logged-in owner is marked
-- "(current)" and PREPENDED when missing from keys (the selector is the
-- only way back to live mode); nil currentKey adds no mark and no prepend
-- (e.g. the guild window when the current guild has no cache record).
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- SetScript-recording frame fake (the gate-test idiom). owner_select
-- creates frames only inside Attach (runtime), so load time should never
-- need one — the fake guards against that ever changing silently.
_G.CreateFrame = function()
    local f = { _scripts = {} }
    function f.SetScript(self, which, fn) self._scripts[which] = fn end
    function f.GetScript(self, which) return self._scripts[which] end
    function f.SetSize() end
    function f.SetPoint() end
    function f.Hide() end
    function f.Show() end
    return f
end

local ns = loader.LoadAll()
ns.Helpers = { CreateDBGetter = function() return function() return {} end end }

(dofile("tests/helpers/locale.lua"))(ns)
local chunk = assert(loadfile("QUI_Bags/bags/views/owner_select.lua"))
chunk("QUI", ns)
local OwnerSelect = ns.Bags.OwnerSelect
assert(type(OwnerSelect.BuildOwnerList) == "function", "BuildOwnerList must be exported")
assert(type(OwnerSelect.Attach) == "function", "Attach must be exported")

-- Test 1: empty inputs → empty list (nil keys tolerated)
assert(#OwnerSelect.BuildOwnerList({}, nil) == 0, "empty keys must yield an empty list")
assert(#OwnerSelect.BuildOwnerList(nil, nil) == 0, "nil keys must yield an empty list")

-- Test 2: no currentKey → labels are the keys verbatim, order preserved
local list = OwnerSelect.BuildOwnerList({ "Alta-Realm", "Brin-Realm" }, nil)
assert(#list == 2, "two entries expected, got " .. #list)
assert(list[1].key == "Alta-Realm" and list[1].label == "Alta-Realm",
    "unmarked entries must carry the key as label")
assert(list[2].key == "Brin-Realm" and list[2].label == "Brin-Realm",
    "store key order must be preserved")

-- Test 3: currentKey in keys → marked "(current)" in place (no reorder)
list = OwnerSelect.BuildOwnerList({ "Alta-Realm", "Brin-Realm", "Cyx-Realm" }, "Brin-Realm")
assert(#list == 3, "marking must not change the count")
assert(list[2].key == "Brin-Realm" and list[2].label == "Brin-Realm (current)",
    "the current owner must be marked in place")
assert(list[1].label == "Alta-Realm" and list[3].label == "Cyx-Realm",
    "other entries must stay unmarked")

-- Test 4: currentKey missing from keys → prepended at index 1 with the mark
-- (the logged-in owner must stay selectable before its record lands)
list = OwnerSelect.BuildOwnerList({ "Alta-Realm", "Brin-Realm" }, "Zed-Realm")
assert(#list == 3, "the missing current owner must be prepended")
assert(list[1].key == "Zed-Realm" and list[1].label == "Zed-Realm (current)",
    "the prepended current owner must come first, marked")
assert(list[2].key == "Alta-Realm" and list[3].key == "Brin-Realm",
    "store keys must follow the prepended current owner unchanged")

-- Test 5: single key that IS the current owner → one marked entry (the
-- button hides at <2 owners — visibility is Attach's concern, the pure
-- builder never filters)
list = OwnerSelect.BuildOwnerList({ "Alta-Realm" }, "Alta-Realm")
assert(#list == 1 and list[1].label == "Alta-Realm (current)",
    "a lone current owner must still build one marked entry")

-- Test 6: prepend with empty keys → just the current owner
list = OwnerSelect.BuildOwnerList({}, "Alta-Realm")
assert(#list == 1 and list[1].key == "Alta-Realm"
    and list[1].label == "Alta-Realm (current)",
    "empty store + current owner must yield the prepended entry only")

print("OK: bags_owner_select_test")
