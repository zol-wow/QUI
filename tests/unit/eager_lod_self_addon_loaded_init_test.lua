-- tests/unit/eager_lod_self_addon_loaded_init_test.lua
-- Run: lua tests/unit/eager_lod_self_addon_loaded_init_test.lua
--
-- Regression guard for the "Eager-LOD self-ADDON_LOADED init is DEAD" class.
--
-- These modules live in QUI_QoL, which the core eager-LoadAddOn's from OnEnable.
-- A module's own ADDON_LOADED self-event is NOT delivered to a handler it
-- registers during that load, so any init gated on `arg == ADDON_NAME` never
-- runs (in-game report: combat timer / brez counter / crosshair / reticle etc.
-- "enabled but never appear in an encounter"). Init must instead run via
-- ns.WhenLoggedIn (fires immediately for a post-login LOD load).
--
-- This guards the files that were converted away from the dead pattern. Each
-- MUST install its init via ns.WhenLoggedIn and MUST NOT gate init on its own
-- ADDON_LOADED ("~= ADDON_NAME"). The behavioral counterpart for the combat
-- timer is combattimer_login_init_test.lua.

local files = {
    "QUI_QoL/qol/combattimer.lua",
    "QUI_QoL/dungeon/brez_counter.lua",
    "QUI_QoL/combat/combattext.lua",
    "QUI_QoL/qol/actiontracker.lua",
    "QUI_QoL/qol/crosshair.lua",
    "QUI_QoL/qol/reticle.lua",
}

local function read(path)
    local f = assert(io.open(path, "r"), "could not open " .. path)
    local body = f:read("*a")
    f:close()
    return body
end

for _, path in ipairs(files) do
    local body = read(path)

    assert(body:find("ns.WhenLoggedIn(", 1, true),
        path .. " must install its init via ns.WhenLoggedIn (eager-LOD modules never receive their own ADDON_LOADED)")

    assert(not body:find("~= ADDON_NAME", 1, true),
        path .. " must NOT gate init on its own ADDON_LOADED (`~= ADDON_NAME`); that branch is dead in an eager-LOD sub-addon")
end

print("OK: eager_lod_self_addon_loaded_init_test (" .. #files .. " files)")
