-- tests/unit/bb_single_strip_test.lua
-- Run: lua5.1 tests/unit/bb_single_strip_test.lua
--
-- BB single-strip-per-section invariant (spec: docs/superpowers/specs/
-- 2026-07-09-bb-single-strip-design.md). Executable tests for the model
-- helper; source-text pins for the runtime/editor/mount wiring (those files
-- build WoW frames and cannot execute headless).
local ns = dofile("tools/_addon_env.lua").LoadCore()
local E = ns.AuraElements

local fails = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else fails = fails + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function Strip(auraType, id)
    local e = E.NewFilterStripElement(auraType)
    e.id = id
    return e
end
local function Store(bucket)
    return { elements = { ["*"] = bucket } }
end

-- Trim: keeps FIRST strip, drops later strips ------------------------------
do
    local store = Store({ Strip("HELPFUL", "a"), Strip("HELPFUL", "b"), Strip("HARMFUL", "c") })
    local changed = E.NormalizeSingleStripBucket(store, "HELPFUL")
    local bucket = store.elements["*"]
    check("trim: returns changed", changed == true)
    check("trim: one strip survives", #bucket == 1)
    check("trim: survivor is the FIRST strip", bucket[1] and bucket[1].id == "a")
end

-- Polarity + enabled forced on the survivor --------------------------------
do
    local s = Strip("HARMFUL", "a")
    s.enabled = false
    local store = Store({ s })
    local changed = E.NormalizeSingleStripBucket(store, "HELPFUL")
    check("force: returns changed", changed == true)
    check("force: auraType forced to HELPFUL", s.auraType == "HELPFUL")
    check("force: enabled forced true", s.enabled == true)
end

-- Non-strip elements untouched ----------------------------------------------
do
    local tracked = E.NewTrackedElement({ 12345 }, "icon")
    local store = Store({ Strip("HARMFUL", "a"), tracked, Strip("HARMFUL", "b") })
    E.NormalizeSingleStripBucket(store, "HARMFUL")
    local bucket = store.elements["*"]
    check("mixed: strip trimmed, tracked kept", #bucket == 2)
    check("mixed: strip first", bucket[1].id == "a")
    check("mixed: tracked survives", bucket[2] == tracked)
end

-- Idempotent ------------------------------------------------------------------
do
    local store = Store({ Strip("HELPFUL", "a"), Strip("HELPFUL", "b") })
    E.NormalizeSingleStripBucket(store, "HELPFUL")
    local changed = E.NormalizeSingleStripBucket(store, "HELPFUL")
    check("idempotent: second pass reports no change", changed == false)
end

-- Degenerate inputs tolerated -------------------------------------------------
do
    check("nil store tolerated", E.NormalizeSingleStripBucket(nil, "HELPFUL") == false)
    check("store without elements tolerated", E.NormalizeSingleStripBucket({}, "HELPFUL") == false)
    check("empty bucket tolerated", E.NormalizeSingleStripBucket(Store({}), "HELPFUL") == false)
    check("elements present but no \"*\" bucket tolerated",
        E.NormalizeSingleStripBucket({ elements = {} }, "HELPFUL") == false)
    check("nil auraType leaves polarity alone", (function()
        local s = Strip("HARMFUL", "a")
        E.NormalizeSingleStripBucket(Store({ s }), nil)
        return s.auraType == "HARMFUL"
    end)())
end

-- Source pins: runtime wiring ------------------------------------------------
local function read(p)
    local h = io.open(p, "rb")
    if not h then return nil end
    local s = h:read("*a")
    h:close()
    return s
end

do
    local bb = read("QUI_ActionBars/actionbars/buffborders.lua")
    check("BB runtime read", bb ~= nil)
    if bb then
        check("BB calls E.NormalizeSingleStripBucket on resolve",
            bb:find("E.NormalizeSingleStripBucket(store, auraType)", 1, true) ~= nil)
        check("BB threads HELPFUL into the buff resolve",
            bb:find('_buffStrips, "HELPFUL"', 1, true) ~= nil)
        check("BB threads HARMFUL into the debuff resolve",
            bb:find('_debuffStrips, "HARMFUL"', 1, true) ~= nil)
        check("no polarity-less ResolveStrips call remains",
            bb:find("_buffStrips)", 1, true) == nil and bb:find("_debuffStrips)", 1, true) == nil)
    end
end

-- Source pins: editor singleStrip mode ----------------------------------------
do
    local editor = read("QUI_Options/aura_elements_editor.lua")
    check("editor read", editor ~= nil)
    if editor then
        check("editor: singleStrip branch renders detail without list chrome",
            editor:find("caps.singleStrip", 1, true) ~= nil)
        check("editor: fixedAuraType suppresses the Aura Type dropdown",
            editor:find("caps.fixedAuraType", 1, true) ~= nil)
        check("editor: Element Enabled row gated off for singleStrip",
            editor:find("if not ctx.caps.singleStrip then", 1, true) ~= nil)
    end
end

-- Source pins: BB mount capabilities ------------------------------------------
do
    local mount = read("QUI_ActionBars/actionbars/settings/action_bars_buffdebuff_content.lua")
    check("BB mount read", mount ~= nil)
    if mount then
        check("mount: passes singleStrip capability",
            mount:find("singleStrip", 1, true) ~= nil)
        check("mount: buff zone fixes HELPFUL",
            mount:find('true, "HELPFUL"', 1, true) ~= nil)
        check("mount: debuff zone fixes HARMFUL",
            mount:find('false, "HARMFUL"', 1, true) ~= nil)
        check("mount: threads onLayoutChanged so sections below a resized editor reflow",
            mount:find("onLayoutChanged", 1, true) ~= nil)
    end
end

if fails > 0 then
    print(("%d failures"):format(fails))
    os.exit(1)
end
print("bb_single_strip_test: all checks passed")
