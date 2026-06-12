-- tests/unit/alts_equipment_view_test.lua
-- Run: lua tests/unit/alts_equipment_view_test.lua
-- Covers the PURE parts of the equipment tab:
--   EquipmentView.BuildSlotRows (order, optional-slot elision)
--   EquipmentView.BuildColumns  (name sort, key fallback)
-- The frame-building Builder is NOT exercised (no WoW frame API headless).

local ns = {}
ns.Helpers = {
    GetGeneralFont        = function() return "Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "" end,
}
ns.Storage = { Store = {}, Bus = {} }

-- equipment.lua calls Alts.Window.RegisterTab at file end; stub it.
ns.Alts = { Window = { RegisterTab = function() end } }

assert(loadfile("QUI_Alts/alts/views/equipment.lua"))("QUI", ns)

local EV = ns.Alts.EquipmentView
assert(EV, "EquipmentView exported")

---------------------------------------------------------------------------
-- BuildSlotRows
---------------------------------------------------------------------------
do
    -- no char has shirt(4)/ranged(18)/tabard(19) → those rows elided
    local chars = {
        a = { equipped = { slots = { [1] = { itemID = 1 }, [16] = { itemID = 2 } } } },
        b = { equipped = { slots = { [2] = { itemID = 3 } } } },
    }
    local rows = EV.BuildSlotRows(chars)
    assert(#rows == 16, "16 mandatory slots: " .. #rows)
    assert(rows[1].slot == 1 and rows[1].label == "Head", "first row Head")
    for _, r in ipairs(rows) do
        assert(r.slot ~= 4 and r.slot ~= 18 and r.slot ~= 19, "optional slots elided")
    end

    -- a tabard on ONE char brings the row back for all
    chars.b.equipped.slots[19] = { itemID = 9 }
    rows = EV.BuildSlotRows(chars)
    assert(#rows == 17, "tabard row restored: " .. #rows)
    local found
    for _, r in ipairs(rows) do
        if r.slot == 19 then found = r.label end
    end
    assert(found == "Tabard", "tabard labeled")

    -- phase-1 record shape (equipped = {} without .slots) must not error
    local legacy = { c = { equipped = {} }, d = {} }
    rows = EV.BuildSlotRows(legacy)
    assert(#rows == 16, "legacy/empty records → mandatory slots only")
end

---------------------------------------------------------------------------
-- BuildColumns
---------------------------------------------------------------------------
do
    local chars = {
        ["Zed-Realm"] = { name = "Zed" },
        ["Abe-Realm"] = {},               -- no name → key fallback
    }
    local cols = EV.BuildColumns(chars)
    assert(#cols == 2, "two columns")
    assert(cols[1].key == "Abe-Realm" and cols[1].name == "Abe-Realm", "key fallback + sort")
    assert(cols[2].name == "Zed", "rec.name used")

    assert(#EV.BuildColumns({}) == 0, "empty chars → no columns")
    assert(#EV.BuildColumns(nil) == 0, "nil chars → no columns")
end

print("OK alts_equipment_view_test")
