-- tests/unit/first_run_test.lua
-- Verifies fresh-install detection, the install gate, and the Run
-- orchestration (import engine + reload-prompt are stubbed/injected).
-- Run: lua tests/unit/first_run_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local FirstRun = ns.FirstRun

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

check("FirstRun module exists", type(FirstRun) == "table")

-- Constants -----------------------------------------------------------------
check("starter preset key is CocoProfile", FirstRun.STARTER_PRESET_KEY == "CocoProfile")
check("starter target is Default", FirstRun.STARTER_TARGET == "Default")

-- IsFreshInstall ------------------------------------------------------------
check("nil/nil -> fresh", FirstRun.IsFreshInstall(nil, nil) == true)
check("QUI_DB present -> not fresh", FirstRun.IsFreshInstall({}, nil) == false)
check("QuaziiUI_DB present -> not fresh", FirstRun.IsFreshInstall(nil, {}) == false)
check("both present -> not fresh", FirstRun.IsFreshInstall({}, {}) == false)

-- ShouldInstall -------------------------------------------------------------
check("fresh + nil marker -> install", FirstRun.ShouldInstall(true, nil) == true)
check("fresh + false marker -> install", FirstRun.ShouldInstall(true, false) == true)
check("fresh + true marker -> skip", FirstRun.ShouldInstall(true, true) == false)
check("not fresh -> skip", FirstRun.ShouldInstall(false, nil) == false)
check("nil fresh -> skip", FirstRun.ShouldInstall(nil, nil) == false)

-- Run: success path ---------------------------------------------------------
do
    local rec = {}
    local db = { global = {} }
    local ok = FirstRun.Run({
        freshInstall = true,
        db = db,
        importData = "COCO_DATA",
        importFn = function(data, target) rec.data = data; rec.target = target; return true, "ok" end,
        promptReload = function() rec.prompted = true end,
        notify = function(msg) rec.msg = msg end,
    })
    check("success returns true", ok == true)
    check("imports the coco data", rec.data == "COCO_DATA")
    check("imports into the Default profile", rec.target == "Default")
    check("marker set on success", db.global.firstRunComplete == true)
    check("reload popup shown on success", rec.prompted == true)
    check("notify called on success", type(rec.msg) == "string")
end

-- Run: success without a promptReload injected (must not error) -------------
do
    local db = { global = {} }
    local ok = FirstRun.Run({
        freshInstall = true,
        db = db,
        importData = "COCO_DATA",
        importFn = function() return true end,
        promptReload = nil,
        notify = function() end,
    })
    check("success returns true without promptReload", ok == true)
    check("marker still set without promptReload", db.global.firstRunComplete == true)
end

-- Run: import-failure path --------------------------------------------------
do
    local db = { global = {} }
    local prompted = false
    local ok = FirstRun.Run({
        freshInstall = true,
        db = db,
        importData = "BAD",
        importFn = function() return false, "parse error" end,
        promptReload = function() prompted = true end,
        notify = function() end,
    })
    check("failure returns false", ok == false)
    check("marker still set on failure", db.global.firstRunComplete == true)
    check("no reload popup on failure", prompted == false)
end

-- Run: missing import data --------------------------------------------------
do
    local db = { global = {} }
    local prompted = false
    local called = false
    local ok = FirstRun.Run({
        freshInstall = true,
        db = db,
        importData = nil,
        importFn = function() called = true; return true end,
        promptReload = function() prompted = true end,
        notify = function() end,
    })
    check("missing data returns false", ok == false)
    check("missing data does not call engine", called == false)
    check("missing data still seals marker", db.global.firstRunComplete == true)
    check("missing data does not show popup", prompted == false)
end

-- Run: empty-string import data ---------------------------------------------
do
    local db = { global = {} }
    local called = false
    local prompted = false
    local ok = FirstRun.Run({
        freshInstall = true,
        db = db,
        importData = "",
        importFn = function() called = true; return true end,
        promptReload = function() prompted = true end,
        notify = function() end,
    })
    check("empty data returns false", ok == false)
    check("empty data does not call engine", called == false)
    check("empty data still seals marker", db.global.firstRunComplete == true)
    check("empty data does not show popup", prompted == false)
end

-- Run: importFn missing / not a function ------------------------------------
do
    local db = { global = {} }
    local prompted = false
    local ok = FirstRun.Run({
        freshInstall = true,
        db = db,
        importData = "COCO_DATA",
        importFn = nil,
        promptReload = function() prompted = true end,
        notify = function() end,
    })
    check("no importFn returns false", ok == false)
    check("no importFn still seals marker", db.global.firstRunComplete == true)
    check("no importFn does not show popup", prompted == false)
end

-- Run: guard - not a fresh install ------------------------------------------
do
    local db = { global = {} }
    local called = false
    FirstRun.Run({
        freshInstall = false, db = db, importData = "X",
        importFn = function() called = true; return true end,
        promptReload = function() end, notify = function() end,
    })
    check("not fresh -> engine not called", called == false)
    check("not fresh -> marker untouched", db.global.firstRunComplete == nil)
end

-- Run: guard - marker already set -------------------------------------------
do
    local db = { global = { firstRunComplete = true } }
    local called = false
    FirstRun.Run({
        freshInstall = true, db = db, importData = "X",
        importFn = function() called = true; return true end,
        promptReload = function() end, notify = function() end,
    })
    check("marker set -> engine not called", called == false)
end

-- Run: defensive - missing db ----------------------------------------------
do
    check("nil deps returns false", FirstRun.Run(nil) == false)
    check("missing db returns false", FirstRun.Run({ freshInstall = true }) == false)
    check("db without global returns false", FirstRun.Run({ freshInstall = true, db = {} }) == false)
end

if failures > 0 then
    os.exit(1)
end
print("first_run_test: OK")
