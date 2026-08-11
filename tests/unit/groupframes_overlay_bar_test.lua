-- tests/unit/groupframes_overlay_bar_test.lua
-- Run: lua tests/unit/groupframes_overlay_bar_test.lua
-- Extracts ApplyOverlayBar from core/group_frame_chrome.lua (between its
-- QUI_TEST_EXTRACT sentinels) and drives it against mock widgets to verify the
-- config->widget mapping for texture, draw order, fill origin, spark and
-- outline. The chrome module is the ONE home of this function: the live frames
-- and the settings preview both style their overlay bars through it.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("core/group_frame_chrome.lua")
local fnStart = assert(source:find("local function ApplyOverlayBar", 1, true),
    "ApplyOverlayBar must exist")
local nl = assert(source:find("\n%-%- <<< QUI_TEST_EXTRACT ApplyOverlayBar", fnStart),
    "end sentinel must exist")
local fnSource = source:sub(fnStart, nl - 1)

local chunk = table.concat({
    "local function ApplyStatusBarTexture(bar, name) bar._tex = name end",
    fnSource,
    "return ApplyOverlayBar",
}, "\n")
local ApplyOverlayBar = assert(loadstring(chunk, "ApplyOverlayBar"))()

local function newTexture()
    local t = { points = {}, shown = false }
    function t:SetColorTexture(...) self.color = {...} end
    function t:SetVertexColor(...) self.vertex = {...} end
    function t:ClearAllPoints() self.points = {} end
    function t:SetPoint(...) table.insert(self.points, {...}) end
    function t:SetWidth(w) self.width = w end
    function t:SetHeight(h) self.height = h end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
end

local function newBar()
    local bar = { textures = {} }
    local fill = newTexture()
    function bar:GetStatusBarTexture() return fill end
    function bar:SetFrameLevel(l) self.level = l end
    function bar:SetFrameStrata(s) self.strata = s end
    function bar:ClearAllPoints() self.points = {} end
    function bar:SetAllPoints(o) self.allPoints = o end
    function bar:SetPoint(...) self.points = self.points or {}; table.insert(self.points, {...}) end
    function bar:SetReverseFill(v) self.reverse = v end
    function bar:SetOrientation(o) self.orient = o end
    function bar:CreateTexture(_, _) local t = newTexture(); table.insert(self.textures, t); return t end
    return bar
end

local function newHealth(level)
    local h = { _fill = newTexture() }
    function h:GetFrameLevel() return level end
    function h:GetFrameStrata() return "MEDIUM" end
    function h:GetStatusBarTexture() return self._fill end
    return h
end

-- explicit drawOrder + fillFrom=default (normal fill), horizontal, full overlay
local bar = newBar()
local health = newHealth(10)
ApplyOverlayBar(bar, { texture = "Foo", drawOrder = 3, fillFrom = "default" },
    health, false, { fillOrigin = true, drawOrderDefault = 2 })
assert(bar._tex == "Foo", "texture applied from settings")
assert(bar.level == 14, "healthBar+1 is reserved; level = health + drawOrder + 1")
assert(bar.strata == "MEDIUM", "strata mirrors health bar")
assert(bar.reverse == false, "fillFrom=default -> reverse false")
assert(bar.orient == "HORIZONTAL", "orientation horizontal")
assert(bar.allPoints == health, "overlay covers full health bar")

-- defaults path: no drawOrder/fillFrom in settings -> opts default + reverse
local bar2 = newBar()
ApplyOverlayBar(bar2, {}, newHealth(5), false, { fillOrigin = true, drawOrderDefault = 2 })
assert(bar2.level == 8, "drawOrderDefault used after the reserved tint level")
assert(bar2.reverse == true, "fillFrom default -> reverse true")

-- heal-prediction path: anchorToHealth, no reverse, edge-anchored via SetPoint
local bar3 = newBar()
ApplyOverlayBar(bar3, {}, newHealth(4), false, { drawOrderDefault = 1, anchorToHealth = true })
assert(bar3.level == 6, "healPred frame level follows the reserved tint level")
assert(bar3.reverse ~= true, "healPred is not reverse-filled")
assert(bar3.points and #bar3.points >= 2, "healPred anchored to health fill edge")

print("PASS: groupframes_overlay_bar core geometry")

-- Spark: created, colored, pinned to reverse leading edge (LEFT for horizontal reverse)
local sbar = newBar()
ApplyOverlayBar(sbar, { spark = true, sparkColor = { 1, 0, 0 } },
    newHealth(10), false, { fillOrigin = true, drawOrderDefault = 2 })
assert(sbar._quiSpark, "spark texture created")
assert(sbar._quiSpark.shown == true, "spark shown when enabled")
assert(sbar._quiSpark.vertex and sbar._quiSpark.vertex[1] == 1 and sbar._quiSpark.vertex[2] == 0,
    "spark tinted from sparkColor")
local hasLeft = false
for _, p in ipairs(sbar._quiSpark.points) do if p[1] == "LEFT" then hasLeft = true end end
assert(hasLeft, "spark pinned to reverse-fill leading edge (LEFT)")

-- Spark toggled off hides the cached texture (no re-create)
ApplyOverlayBar(sbar, { spark = false }, newHealth(10), false,
    { fillOrigin = true, drawOrderDefault = 2 })
assert(sbar._quiSpark.shown == false, "spark hidden when disabled")

print("PASS: groupframes_overlay_bar spark")

-- Outline: four edge textures created, colored, shown; toggled off hides them
local obar = newBar()
ApplyOverlayBar(obar, { outline = true, outlineColor = { 0, 0, 1, 1 } },
    newHealth(10), false, { fillOrigin = true, drawOrderDefault = 2 })
assert(obar._quiOutline, "outline table created")
assert(obar._quiOutline.top and obar._quiOutline.bottom
    and obar._quiOutline.left and obar._quiOutline.right, "four outline edges")
assert(obar._quiOutline.top.shown == true, "outline top shown")
assert(obar._quiOutline.top.color and obar._quiOutline.top.color[3] == 1, "outline color applied")

ApplyOverlayBar(obar, { outline = false }, newHealth(10), false,
    { fillOrigin = true, drawOrderDefault = 2 })
assert(obar._quiOutline.top.shown == false, "outline hidden when disabled")

print("PASS: groupframes_overlay_bar outline")

-- Detached mode: SetSize + SetPoint(anchor, frame, anchor, offX, offY); orientation from h>w.
local dbar = newBar()
if not dbar.SetSize then function dbar:SetSize(w, h) self.size = { w, h } end end
local frameSentinel = { __isFrame = true }
ApplyOverlayBar(dbar, { mode = "detached", width = 50, height = 6, anchor = "TOP", offsetX = 3, offsetY = -4 },
    newHealth(10), false, { fillOrigin = true, drawOrderDefault = 2, frame = frameSentinel })
assert(dbar.size and dbar.size[1] == 50 and dbar.size[2] == 6, "detached: SetSize(width,height)")
local dp
for _, p in ipairs(dbar.points) do if p[2] == frameSentinel then dp = p end end
assert(dp, "detached: SetPoint anchored to opts.frame")
assert(dp[1] == "TOP" and dp[3] == "TOP" and dp[4] == 3 and dp[5] == -4, "detached: anchor + offsets")
assert(dbar.orient == "HORIZONTAL", "detached wide bar: horizontal (w>h)")

-- Detached TALL bar (h>w) -> vertical orientation
local tbar = newBar()
if not tbar.SetSize then function tbar:SetSize(w, h) self.size = { w, h } end end
ApplyOverlayBar(tbar, { mode = "detached", width = 6, height = 40, anchor = "LEFT" },
    newHealth(10), false, { fillOrigin = true, drawOrderDefault = 2, frame = frameSentinel })
assert(tbar.orient == "VERTICAL", "detached tall bar: vertical (h>w)")

print("PASS: groupframes_overlay_bar detached")
