-- tests/unit/provider_layout_position_only_guard_test.lua
-- Run: lua tests/unit/provider_layout_position_only_guard_test.lua
--
-- Every shared-provider mover that builds its body via a local MakeLayout must
-- short-circuit to Utils.MakeSuppressedProviderLayout(content) when Layout Mode
-- requests position-only rendering, so right-clicking the mover in Layout Mode
-- shows only Position + the "Open ... settings" link. The provider modules are
-- too heavy to load headless, so this is a source-pattern guard.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local files = {
    "modules/qol/settings/provider_panels.lua",        -- petWarning, missingRaidBuffs, xpTracker, ...
    "modules/dungeon/settings/mplus_timer_provider.lua",
    "modules/dungeon/settings/mplus_progress_provider.lua",
    "modules/utility/settings/ready_check_provider.lua",
    "modules/minimap/settings/minimap_providers.lua",
}

for _, path in ipairs(files) do
    local src = readAll(path)
    assert(src:find("MakeSuppressedProviderLayout", 1, true),
        path .. " MakeLayout must delegate to Utils.MakeSuppressedProviderLayout")
    assert(src:find("_layoutModePositionOnly", 1, true),
        path .. " MakeLayout must guard on _layoutModePositionOnly")
end

print("OK: provider_layout_position_only_guard_test")
