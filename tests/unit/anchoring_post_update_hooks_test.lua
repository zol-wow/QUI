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
local INTEGRATION_SHARED = "modules/integrations/integration_shared.lua"

local anchoringText = assert(readFile(ANCHORING), "cannot open " .. ANCHORING)
local bigwigsText = assert(readFile(BIGWIGS), "cannot open " .. BIGWIGS)
local abilityText = assert(readFile(ABILITYTIMELINE), "cannot open " .. ABILITYTIMELINE)
local dandersText = assert(readFile(DANDERSFRAMES), "cannot open " .. DANDERSFRAMES)
local sharedText = assert(readFile(INTEGRATION_SHARED), "cannot open " .. INTEGRATION_SHARED)

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
    + countAssignments(sharedText)

check("exactly one _G.QUI_UpdateAnchoredFrames assignment across integration files",
    totalAssignments == 1,
    ("expected 1 (anchoring.lua only), found %d"):format(totalAssignments))

-- -------------------------------------------------------------------------
-- 3. Each integration routes through the post-hook registry — either via the
--    shared MakeTryInstallAnchoredFramesHook factory (bigwigs, abilitytimeline)
--    or a direct RegisterAnchoredFramesPostHook call (dandersframes) — and no
--    integration file (nor the shared helper) reintroduces the _G wrap-chain.
-- -------------------------------------------------------------------------
local OLD_REWRAP = "previousUpdateAnchoredFrames%(%.%.%.%)"

-- integration_shared.lua: the factory must register via the post-hook API and
-- must NOT wrap _G.QUI_UpdateAnchoredFrames.
check("integration_shared.lua factory MakeTryInstallAnchoredFramesHook exists",
    sharedText:find("function IntegrationShared.MakeTryInstallAnchoredFramesHook", 1, true) ~= nil)
check("integration_shared.lua factory registers via RegisterAnchoredFramesPostHook",
    sharedText:find("RegisterAnchoredFramesPostHook(", 1, true) ~= nil)
check("integration_shared.lua does not assign _G.QUI_UpdateAnchoredFrames",
    countAssignments(sharedText) == 0)
check("integration_shared.lua does not use old rewrap",
    sharedText:find(OLD_REWRAP) == nil)

-- bigwigs.lua: uses the shared factory; no direct wrap.
check("bigwigs.lua installs via MakeTryInstallAnchoredFramesHook factory",
    bigwigsText:find('MakeTryInstallAnchoredFramesHook("QUI_BigWigs")', 1, true) ~= nil)
check("bigwigs.lua does not assign _G.QUI_UpdateAnchoredFrames",
    countAssignments(bigwigsText) == 0)
check("bigwigs.lua does not use old rewrap",
    bigwigsText:find(OLD_REWRAP) == nil)

-- abilitytimeline.lua: uses the shared factory; no direct wrap.
check("abilitytimeline.lua installs via MakeTryInstallAnchoredFramesHook factory",
    abilityText:find('MakeTryInstallAnchoredFramesHook("QUI_AbilityTimeline")', 1, true) ~= nil)
check("abilitytimeline.lua does not assign _G.QUI_UpdateAnchoredFrames",
    countAssignments(abilityText) == 0)
check("abilitytimeline.lua does not use old rewrap",
    abilityText:find(OLD_REWRAP) == nil)

-- dandersframes.lua: direct post-hook registration; no wrap.
check('dandersframes.lua calls RegisterAnchoredFramesPostHook("dandersframes", ...)',
    dandersText:find('RegisterAnchoredFramesPostHook("dandersframes"', 1, true) ~= nil)
check("dandersframes.lua does not assign _G.QUI_UpdateAnchoredFrames",
    countAssignments(dandersText) == 0)
check("dandersframes.lua does not use old rewrap",
    dandersText:find(OLD_REWRAP) == nil)

print(("\n%d failure(s)"):format(failures))
print("OK: anchoring_post_update_hooks_test")
os.exit(failures == 0 and 0 or 1)
