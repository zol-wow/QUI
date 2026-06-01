-- tests/unit/helpers_deepcopy_consolidation_test.lua
-- Run: lua tests/unit/helpers_deepcopy_consolidation_test.lua
--
-- The codebase had many near-identical local deep-copy implementations. These
-- files must now route through the single canonical ns.Helpers.DeepCopy instead
-- of defining their own, so behaviour (incl. cycle safety) lives in one place.
--
-- Deliberately NOT included: core/migrations.lua (its CloneValue stays local —
-- adding a seen-map would change shared-subtable identity in the saved-variable
-- transform path) and the shallow CopyTable in provider/surface_features (their
-- non-table input returns {}, which differs from Helpers.ShallowCopy passthrough).

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local files = {
    "core/compatibility.lua",
    "core/profile_io.lua",
    "core/settings/pins.lua",
    "core/settings/pins_ui.lua",
    "modules/dungeon/mplus_timer.lua",
    "modules/groupframes/groupframes_clickcast.lua",
    "modules/groupframes/settings/group_frames_schema.lua",
}

for _, path in ipairs(files) do
    local src = readAll(path)
    assert(src:find("ns.Helpers.DeepCopy", 1, true),
        path .. " must route its deep copy through ns.Helpers.DeepCopy")
    assert(not src:find("local function DeepCopy(", 1, true),
        path .. " must not define its own local DeepCopy")
    assert(not src:find("local function CloneValue(", 1, true),
        path .. " must not define its own local CloneValue")
end

print("helpers_deepcopy_consolidation_test: OK")
