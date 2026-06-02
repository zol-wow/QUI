-- tests/unit/profile_io_retired_general_keys_test.lua
-- Run: lua tests/unit/profile_io_retired_general_keys_test.lua
--
-- profile_io.lua's selective-skinning general-keys list carried 5 keys that v12
-- moved out of profile.general (skinLootWindow/...Spacing now live under the
-- loot/lootRoll top-level keys). They no longer exist in defaults, so
-- CopyGeneralKeys cloned nil for each on every selective skinning import/export —
-- dead list entries. Removed.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("core/profile_io.lua")
for _, k in ipairs({ "skinLootWindow", "skinLootUnderMouse", "skinLootHistory", "skinRollFrames", "skinRollSpacing" }) do
    assert(not src:find('"' .. k .. '"', 1, true),
        k .. " (retired general key) must be removed from profile_io.lua's skinning key list")
end

print("profile_io_retired_general_keys_test: OK")
