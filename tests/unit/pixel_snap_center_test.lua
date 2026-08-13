-- tests/unit/pixel_snap_center_test.lua
-- Run: lua tests/unit/pixel_snap_center_test.lua
--
-- Covers QUICore:PixelSnapCenter / PixelSnapRect (core/scaling.lua): CENTER
-- offsets must be shifted so both rect edges land on whole physical pixels
-- (rounding the center alone leaves edges on half-pixels for odd pixel
-- extents). Also pins equivalence with the dependency-injected copy in
-- cdm_reanchor_runtime.lua (SnapPlacementRect), so the two implementations
-- cannot silently drift.

local function fail(msg)
    print("FAIL: pixel_snap_center_test - " .. msg)
    os.exit(1)
end

local function noop() end

-- physicalHeight 1536 with frame scales 0.5 / 1 give exact binary pixel
-- sizes (px = 1 and px = 0.5), so tie cases (.5 edges) stay exact.
GetPhysicalScreenSize = function() return 2560, 1536 end
GetScreenWidth = function() return 1920 end
GetScreenHeight = function() return 1080 end
InCombatLockdown = function() return false end
issecretvalue = nil
Round = function(x) return math.floor(x + 0.5) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = noop } end }

local function NewFrame(scale)
    local f = { _scale = scale or 1 }
    f.GetEffectiveScale = function(self) return self._scale end
    return f
end

UIParent = NewFrame(1)

local ns = {
    Helpers = {
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
    },
    Addon = {},
}
_G.QUI = { QUICore = ns.Addon }

assert(loadfile("core/scaling.lua"))("QUI", ns)
local core = ns.Addon

if type(core.PixelSnapCenter) ~= "function" or type(core.PixelSnapRect) ~= "function" then
    fail("scaling.lua must expose PixelSnapCenter/PixelSnapRect")
end

local px1 = NewFrame(0.5)  -- px = 768 / (1536 * 0.5) = 1
local pxHalf = NewFrame(1) -- px = 768 / (1536 * 1)   = 0.5

if core:GetPixelSize(px1) ~= 1 then fail("px1 frame must resolve to pixel size 1") end
if core:GetPixelSize(pxHalf) ~= 0.5 then fail("pxHalf frame must resolve to pixel size 0.5") end

local function near(a, b) return math.abs(a - b) <= 1e-9 end

-- exact cases at px = 1
local c, e = core:PixelSnapCenter(-122.5, 44, px1)
if not (c == -122 and e == 44) then
    fail(("even extent at half-pixel center must shift onto the grid, got %s/%s"):format(c, e))
end
c, e = core:PixelSnapCenter(0, 41, px1)
if not (c == 0.5 and e == 41) then
    fail(("odd extent at integer center must shift onto a half-pixel, got %s/%s"):format(c, e))
end
c, e = core:PixelSnapCenter(7, 44, px1)
if not (c == 7 and e == 44) then
    fail("already-aligned input must pass through unchanged")
end
c, e = core:PixelSnapCenter(0, 41.3, px1)
if not (c == 0.5 and e == 41) then
    fail("fractional extent must round to whole pixels before snapping")
end

-- fractional pixel size (px = 0.5): edges must land on multiples of px
local centers = { -144.5, -122.5, -21.3, -0.5, 0, 0.5, 7.25, 10.1, 122.5 }
local extents = { 40, 41, 41.3, 44, 50.4 }
for _, frame in ipairs({ px1, pxHalf }) do
    local px = core:GetPixelSize(frame)
    for _, center in ipairs(centers) do
        for _, extent in ipairs(extents) do
            local sc, se = core:PixelSnapCenter(center, extent, frame)
            local lowGrid = (sc - se / 2) / px
            local highGrid = (sc + se / 2) / px
            if not near(lowGrid, Round(lowGrid)) or not near(highGrid, Round(highGrid)) then
                fail(("edges off grid: center=%s extent=%s px=%s -> %s..%s")
                    :format(center, extent, px, sc - se / 2, sc + se / 2))
            end
            if math.abs(sc - center) > px / 2 + 1e-9 then
                fail("snapped center must stay within half a pixel of the input")
            end
        end
    end
end

-- PixelSnapRect must be the per-axis composition of PixelSnapCenter
local x, y, w, h = core:PixelSnapRect(-21.3, 10.1, 41.3, 50.4, pxHalf)
local ex, ew = core:PixelSnapCenter(-21.3, 41.3, pxHalf)
local ey, eh = core:PixelSnapCenter(10.1, 50.4, pxHalf)
if not (x == ex and y == ey and w == ew and h == eh) then
    fail("PixelSnapRect must match per-axis PixelSnapCenter")
end

-- equivalence with cdm_reanchor_runtime.lua SnapPlacementRect (the
-- dependency-injected copy): same snapped rect for both axis formulas.
for _, frame in ipairs({ px1, pxHalf }) do
    local px = core:GetPixelSize(frame)
    local function pixelRound(v) return Round(v / px) * px end
    for _, center in ipairs(centers) do
        for _, extent in ipairs(extents) do
            local se = pixelRound(extent)
            local runtimeX = pixelRound(center - se / 2) + se / 2
            local runtimeY = pixelRound(center + se / 2) - se / 2
            local sc, sce = core:PixelSnapCenter(center, extent, frame)
            if not (near(runtimeX, sc) and near(runtimeY, sc) and near(se, sce)) then
                fail(("runtime SnapPlacementRect drift: center=%s extent=%s px=%s -> core %s vs runtime %s/%s")
                    :format(center, extent, px, sc, runtimeX, runtimeY))
            end
        end
    end
end

print("OK: pixel_snap_center_test")
