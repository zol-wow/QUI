-- tests/unit/cdm_reanchor_viewer_glue_test.lua
-- Run: lua tests/unit/cdm_reanchor_viewer_glue_test.lua
--
-- Root cause under test (utility combat-start snap): the Blizzard
-- Essential/Utility viewers sit at their NATIVE mid-screen Edit-Mode position
-- at alpha-1 (the viewer-level park was retired), so any item frame Blizzard
-- lays out before QUI claims it renders mid-screen. The reference re-anchor
-- addon glues the viewer's rect onto the addon container (viewer TL/BR ->
-- container TL/BR, re-asserted whenever Blizzard moves the viewer), so
-- Blizzard's own grid layout lands icons ON the QUI container -- there is no
-- mid-screen landing spot at all. This test drives that glue.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_hooks.lua", "cdm_reanchor_hooks.lua")("QUI", ns)
local H = assert(ns.CDMReanchorHooks, "CDMReanchorHooks should be exported")

local function makeViewer(name)
    return {
        name = name,
        points = {},
        cleared = 0,
        ClearAllPoints = function(self)
            self.cleared = self.cleared + 1
            self.points = {}
        end,
        SetPoint = function(self, point, relativeTo, relativePoint, x, y)
            self.points[#self.points + 1] = {
                point = point, relativeTo = relativeTo,
                relativePoint = relativePoint, x = x, y = y,
            }
        end,
    }
end

local function makeHarness(canWriteRef)
    local t = { hookInstalls = {} }
    local function fakeHook(owner, method, fn)
        t.hookInstalls[#t.hookInstalls + 1] = { owner = owner, method = method, fn = fn }
    end
    t.viewers = {
        essential = makeViewer("EssentialViewer"),
        utility = makeViewer("UtilityViewer"),
        buff = makeViewer("BuffViewer"),
    }
    t.containers = { essential = { name = "cE" }, utility = { name = "cU" }, buff = { name = "cB" } }
    t.hooks = H.New({
        refresh = function() end,
        keys = { "essential", "utility", "buff" },
        hooksecurefunc = fakeHook,
        schedule = function() end,
    })
    t.hooks:InstallViewerGlue(
        function(key) return t.viewers[key] end,
        function(key) return t.containers[key] end,
        { essential = true, utility = true },
        function() return canWriteRef.value end)
    return t
end

local function assertGlued(viewer, container, label)
    assert(#viewer.points == 2, label .. ": exactly two glue points")
    local tl, br = viewer.points[1], viewer.points[2]
    assert(tl.point == "TOPLEFT" and tl.relativeTo == container
        and tl.relativePoint == "TOPLEFT" and tl.x == 0 and tl.y == 0,
        label .. ": TOPLEFT pinned to container TOPLEFT")
    assert(br.point == "BOTTOMRIGHT" and br.relativeTo == container
        and br.relativePoint == "BOTTOMRIGHT" and br.x == 0 and br.y == 0,
        label .. ": BOTTOMRIGHT pinned to container BOTTOMRIGHT")
end

local function findHook(t, owner, method)
    for i = 1, #t.hookInstalls do
        local h = t.hookInstalls[i]
        if h.owner == owner and h.method == method then return h.fn end
    end
    return nil
end

-- 1) Install glues opted-in viewers immediately (writable), skips others.
do
    local canWrite = { value = true }
    local t = makeHarness(canWrite)
    assertGlued(t.viewers.essential, t.containers.essential, "essential at install")
    assertGlued(t.viewers.utility, t.containers.utility, "utility at install")
    assert(#t.viewers.buff.points == 0 and t.viewers.buff.cleared == 0,
        "buff viewer is NOT glued (cdm_buff_layout owns its anchoring)")
    assert(findHook(t, t.viewers.essential, "SetPoint"), "SetPoint re-glue hook on essential viewer")
    assert(findHook(t, t.viewers.utility, "SetPoint"), "SetPoint re-glue hook on utility viewer")
    assert(not findHook(t, t.viewers.buff, "SetPoint"), "no glue hook on buff viewer")
end

-- 2) Blizzard moving the viewer (SetPoint with a foreign relativeTo)
--    triggers an immediate re-glue; QUI's own glue call does not recurse.
do
    local canWrite = { value = true }
    local t = makeHarness(canWrite)
    local viewer, container = t.viewers.utility, t.containers.utility
    local hookFn = assert(findHook(t, viewer, "SetPoint"))

    -- simulate Blizzard/EditMode re-anchoring the viewer somewhere else
    local uiParent = { name = "UIParent" }
    viewer.points = { { point = "CENTER", relativeTo = uiParent } }
    local clearedBefore = viewer.cleared
    hookFn(viewer, "CENTER", uiParent)
    assert(viewer.cleared == clearedBefore + 1, "foreign SetPoint re-clears the viewer")
    assertGlued(viewer, container, "utility after foreign SetPoint")

    -- our own glue SetPoint (relativeTo == container) must not re-enter
    clearedBefore = viewer.cleared
    hookFn(viewer, "TOPLEFT", container)
    assert(viewer.cleared == clearedBefore, "own glue SetPoint does not recurse")
end

-- 3) Combat gate: no viewer writes while canWrite() is false; the missed glue
--    is recovered by ReassertViewerGlue() (PLAYER_REGEN_ENABLED path).
do
    local canWrite = { value = false }
    local t = makeHarness(canWrite)
    assert(#t.viewers.utility.points == 0 and t.viewers.utility.cleared == 0,
        "no viewer anchor writes while combat-locked")
    local hookFn = assert(findHook(t, t.viewers.utility, "SetPoint"),
        "re-glue hook still installed while combat-locked")
    hookFn(t.viewers.utility, "CENTER", { name = "UIParent" })
    assert(t.viewers.utility.cleared == 0, "re-glue hook respects the combat gate")

    canWrite.value = true
    t.hooks:ReassertViewerGlue()
    assertGlued(t.viewers.utility, t.containers.utility, "utility after ReassertViewerGlue")
    assertGlued(t.viewers.essential, t.containers.essential, "essential after ReassertViewerGlue")
end

-- 4) Missed initial glue (container not created yet at hook-install time, or
--    combat-locked install on a /reload) must be retried by a later
--    InstallViewerGlue call (RefreshReanchorRuntimeHooks re-runs on retry
--    paths) -- a peaceful login must not stay unglued until first combat end.
do
    local canWrite = { value = true }
    local t = { hookInstalls = {} }
    local function fakeHook(owner, method, fn)
        t.hookInstalls[#t.hookInstalls + 1] = { owner = owner, method = method, fn = fn }
    end
    local viewer = makeViewer("UtilityViewer")
    local container = nil -- not created yet
    local hooks = H.New({
        refresh = function() end,
        keys = { "utility" },
        hooksecurefunc = fakeHook,
        schedule = function() end,
    })
    local function install()
        hooks:InstallViewerGlue(
            function() return viewer end,
            function() return container end,
            { utility = true },
            function() return canWrite.value end)
    end
    install()
    assert(#viewer.points == 0, "no glue writes while the container is missing")

    container = { name = "cU" }
    install()
    assertGlued(viewer, container, "utility after retry with the container present")

    -- hook must not have been installed twice: exactly one SetPoint hook
    local n = 0
    for i = 1, #t.hookInstalls do
        if t.hookInstalls[i].owner == viewer and t.hookInstalls[i].method == "SetPoint" then
            n = n + 1
        end
    end
    assert(n == 1, "re-running InstallViewerGlue must not stack SetPoint hooks")
end

-- 5) cdm_containers must wire the glue: install alongside InstallViewerHooks
--    and re-assert on PLAYER_REGEN_ENABLED.
do
    local f = assert(io.open("QUI_CDM/cdm/cdm_containers.lua", "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    assert(src:find("InstallViewerGlue", 1, true),
        "cdm_containers must install the viewer glue")
    assert(src:find("ReassertViewerGlue", 1, true),
        "cdm_containers must re-assert the glue after combat")
end

print("OK: cdm_reanchor_viewer_glue_test")
