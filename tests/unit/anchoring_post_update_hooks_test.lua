-- Static guard for the explicit post-update hook API on the anchoring module.
-- Asserts that the wrap-chain pattern has been replaced with idempotent
-- RegisterAnchoredFramesPostHook calls in the three integration files.
--
-- Plain Lua 5.1, file-driven (no harness). Run from repo root:
--   lua tests/unit/anchoring_post_update_hooks_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local function readFile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

local ANCHORING = "modules/layout/anchoring.lua"
local BIGWIGS = "modules/integrations/bigwigs.lua"
local ABILITYTIMELINE = "modules/integrations/abilitytimeline.lua"
local DANDERSFRAMES = "modules/integrations/dandersframes.lua"

local anchoringText = assert(readFile(ANCHORING), "cannot open " .. ANCHORING)
local bigwigsText = assert(readFile(BIGWIGS), "cannot open " .. BIGWIGS)
local abilityText = assert(readFile(ABILITYTIMELINE), "cannot open " .. ABILITYTIMELINE)
local dandersText = assert(readFile(DANDERSFRAMES), "cannot open " .. DANDERSFRAMES)

-- -------------------------------------------------------------------------
-- 1. anchoring.lua: declares RegisterAnchoredFramesPostHook and
--    RunAnchoredFramesPostHooks, and calls RunAnchoredFramesPostHooks inside
--    the canonical updater (after DebouncedReapplyOverrides).
-- -------------------------------------------------------------------------
check("anchoring.lua declares RegisterAnchoredFramesPostHook",
    anchoringText:find("function QUI_Anchoring.RegisterAnchoredFramesPostHook", 1, true) ~= nil)

check("anchoring.lua declares RunAnchoredFramesPostHooks",
    anchoringText:find("local function RunAnchoredFramesPostHooks", 1, true) ~= nil)

-- The call must appear AFTER DebouncedReapplyOverrides() inside the canonical updater.
local updaterStart = anchoringText:find("_G%.QUI_UpdateAnchoredFrames = function", 1)
check("anchoring.lua canonical updater exists", updaterStart ~= nil)
if updaterStart then
    -- Find the end of the updater function body (the closing "end" after the function)
    local updaterBody = anchoringText:sub(updaterStart)
    -- Find DebouncedReapplyOverrides and RunAnchoredFramesPostHooks positions within updater
    local reapplyPos = updaterBody:find("DebouncedReapplyOverrides()", 1, true)
    local runHooksPos = updaterBody:find("RunAnchoredFramesPostHooks(...)", 1, true)
    check("anchoring.lua canonical updater calls RunAnchoredFramesPostHooks",
        runHooksPos ~= nil)
    check("RunAnchoredFramesPostHooks called after DebouncedReapplyOverrides in updater",
        reapplyPos ~= nil and runHooksPos ~= nil and runHooksPos > reapplyPos)
end

-- -------------------------------------------------------------------------
-- 2. Exactly one _G.QUI_UpdateAnchoredFrames = assignment across all four files.
-- -------------------------------------------------------------------------
local function countAssignments(text)
    local count = 0
    for _ in text:gmatch("_G%.QUI_UpdateAnchoredFrames%s*=[^=]") do
        count = count + 1
    end
    return count
end

local totalAssignments = countAssignments(anchoringText)
    + countAssignments(bigwigsText)
    + countAssignments(abilityText)
    + countAssignments(dandersText)

check("exactly one _G.QUI_UpdateAnchoredFrames assignment across four files",
    totalAssignments == 1,
    ("expected 1, found %d"):format(totalAssignments))

-- -------------------------------------------------------------------------
-- 3. Each integration file uses RegisterAnchoredFramesPostHook with its
--    expected name, and does NOT contain the old rewrap pattern.
-- -------------------------------------------------------------------------

-- bigwigs.lua
check('bigwigs.lua calls RegisterAnchoredFramesPostHook("bigwigs", ...)',
    bigwigsText:find('RegisterAnchoredFramesPostHook("bigwigs"', 1, true) ~= nil)
check("bigwigs.lua does not assign _G.QUI_UpdateAnchoredFrames",
    countAssignments(bigwigsText) == 0)
check("bigwigs.lua does not use old rewrap (previousUpdateAnchoredFrames(...))",
    -- Old pattern: a local named previousUpdateAnchoredFrames called inside
    -- a function assigned to _G.QUI_UpdateAnchoredFrames
    bigwigsText:find("previousUpdateAnchoredFrames%(%.%.%.%)", 1, true) == nil)

-- abilitytimeline.lua
check('abilitytimeline.lua calls RegisterAnchoredFramesPostHook("abilitytimeline", ...)',
    abilityText:find('RegisterAnchoredFramesPostHook("abilitytimeline"', 1, true) ~= nil)
check("abilitytimeline.lua does not assign _G.QUI_UpdateAnchoredFrames",
    countAssignments(abilityText) == 0)
check("abilitytimeline.lua does not use old rewrap (previousUpdateAnchoredFrames(...))",
    abilityText:find("previousUpdateAnchoredFrames%(%.%.%.%)", 1, true) == nil)

-- dandersframes.lua
check('dandersframes.lua calls RegisterAnchoredFramesPostHook("dandersframes", ...)',
    dandersText:find('RegisterAnchoredFramesPostHook("dandersframes"', 1, true) ~= nil)
check("dandersframes.lua does not assign _G.QUI_UpdateAnchoredFrames",
    countAssignments(dandersText) == 0)
check("dandersframes.lua does not use old rewrap (previousUpdateAnchoredFrames(...))",
    dandersText:find("previousUpdateAnchoredFrames%(%.%.%.%)", 1, true) == nil)

print(("\n%d failure(s)"):format(failures))
print("OK: anchoring_post_update_hooks_test")
os.exit(failures == 0 and 0 or 1)
