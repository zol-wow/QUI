-- tests/unit/skyriding_getsettings_per_tick_test.lua
-- Run: lua tests/unit/skyriding_getsettings_per_tick_test.lua
--
-- Perf: the throttled OnUpdate handler fetches `settings` once (GetSettings is
-- Helpers.CreateDBGetter("skyriding"), a profile-chain walk), then calls three
-- animation-driven helpers EVERY tick — UpdateRechargeAnimation /
-- UpdateSecondWindRecharge / UpdateSpeed — each of which re-fetched settings
-- itself, so one tick walked the DB four times. This test pins the fix: each
-- helper accepts an optional `settings` arg and only falls back to GetSettings()
-- when none is passed, and OnUpdate threads its already-fetched local into all
-- three. Behaviour is identical (same settings object within a synchronous
-- tick); only the redundant re-fetches are removed.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_QoL/qol/skyriding.lua")

local perTickHelpers = {
    "UpdateRechargeAnimation",
    "UpdateSecondWindRecharge",
    "UpdateSpeed",
}

for _, fn in ipairs(perTickHelpers) do
    -- 1. Definition must accept an optional `settings` parameter.
    local def = "local function " .. fn .. "(settings)"
    assert(src:find(def, 1, true),
        fn .. " must accept an optional settings parameter (" .. def .. ")")

    -- 2. Body must reuse the passed-in settings, falling back to GetSettings()
    --    only when none was threaded in.
    local s = src:find(def, 1, true)
    local body = src:sub(s, s + 160)
    assert(body:find("settings = settings or GetSettings()", 1, true),
        fn .. " must fall back to GetSettings() only when no settings arg is passed")

    -- 3. The old unconditional re-fetch must be gone for this helper.
    assert(not src:find("local function " .. fn .. "()\n    local settings = GetSettings()", 1, true),
        fn .. " must no longer unconditionally call GetSettings()")

    -- 4. OnUpdate must thread its settings local into the per-tick call site
    --    (4-space indented standalone call — distinct from the definition line).
    assert(src:find("\n    " .. fn .. "(settings)\n", 1, true),
        "OnUpdate must call " .. fn .. "(settings), threading its fetched settings")
end

print("skyriding_getsettings_per_tick_test: OK")
