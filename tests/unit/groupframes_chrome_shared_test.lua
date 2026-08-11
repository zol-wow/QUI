-- tests/unit/groupframes_chrome_shared_test.lua
-- Run: lua tests/unit/groupframes_chrome_shared_test.lua
--
-- core/group_frame_chrome.lua is the ONE builder for a group frame's skeleton
-- and its settings styling: the live frames get it from DecorateGroupFrame, the
-- settings preview gets it from the preview driver. Two layers here:
--   1. Behavioral — drive Chrome.Apply on a mock frame and assert the geometry
--      and frame levels the whole suite depends on (the numbers that used to be
--      copied by hand into the preview and drifted).
--   2. Source pins — both consumers really call the shared builder and no
--      longer keep private copies of it.
-- luacheck: globals CreateFrame GetTime

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end

---------------------------------------------------------------------------
-- Widget stubs
---------------------------------------------------------------------------
local function NewRegion()
    local r = { points = {}, shown = true }
    function r:SetPoint(p, rel, rp, x, y) self.points[#self.points + 1] = { p = p, rel = rel, rp = rp, x = x, y = y } end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints() end
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetWidth(w) self.w = w end
    function r:SetHeight(h) self.h = h end
    function r:SetTexture(t) self.texture = t end
    function r:SetAtlas(a) self.atlas = a end
    function r:SetColorTexture(...) self.color = { ... } end
    function r:SetVertexColor(...) self.vertex = { ... } end
    function r:SetTexCoord() end
    function r:SetBlendMode() end
    function r:SetAlpha(a) self.alpha = a end
    function r:SetShown(v) self.shown = v and true or false end
    function r:SetFont() end
    function r:SetText(t) self.text = t end
    function r:SetJustifyH() end
    function r:SetJustifyV() end
    function r:SetTextColor(...) self.textColor = { ... } end
    function r:SetWordWrap() end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:GetStatusBarTexture() self._fill = self._fill or NewRegion(); return self._fill end
    return r
end

local frameCount = 0
local function NewFrame(_, _, parent)
    local f = NewRegion()
    frameCount = frameCount + 1
    f.parent = parent
    f.level = parent and ((parent.level or 0) + 1) or 0
    f.regions = {}
    function f:CreateTexture() local t = NewRegion(); self.regions[#self.regions + 1] = t; return t end
    function f:CreateFontString() local t = NewRegion(); self.regions[#self.regions + 1] = t; return t end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameStrata(s) self.strata = s end
    function f:GetFrameStrata() return self.strata or "MEDIUM" end
    function f:GetParent() return self.parent end
    function f:EnableMouse() end
    function f:SetBackdrop(bd)
        self.backdrop = bd
        if bd and bd.bgFile and not self.Center then self.Center = NewRegion() end
    end
    function f:SetBackdropColor(...) self.backdropColor = { ... } end
    function f:SetBackdropBorderColor(...) self.borderColor = { ... } end
    function f:SetStatusBarTexture(t) self.barTexture = t end
    function f:SetStatusBarColor(...) self.barColor = { ... } end
    function f:SetMinMaxValues(a, b) self.min, self.max = a, b end
    function f:SetValue(v) self.value = v end
    function f:SetOrientation(o) self.orientation = o end
    function f:SetReverseFill(v) self.reverse = v end
    function f:GetWidth() return self.w or 100 end
    function f:GetHeight() return self.h or 40 end
    return f
end

CreateFrame = NewFrame
GetTime = function() return 12345 end

local ns = {
    LSM = { Fetch = function(_, kind, name) return kind .. ":" .. tostring(name) end },
    Helpers = {
        GetSkinBorderColor = function() return 0.1, 0.2, 0.3, 1 end,
        ApplyFontWithFallback = function(fs, path, size, flags) fs.font = { path, size, flags } end,
    },
    Addon = {
        Pixels = function(_, n) return n end,
        PixelRound = function(_, n) return n end,
        GetPixelSize = function() return 1 end,
    },
}
assert(loadfile("core/group_frame_chrome.lua"))("QUI", ns)
local Chrome = assert(ns.QUI_GroupFrameChrome, "must publish ns.QUI_GroupFrameChrome")

local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name) else fails = fails + 1; print("FAIL  " .. name) end
end

---------------------------------------------------------------------------
-- 1. BEHAVIORAL
---------------------------------------------------------------------------
local VDB = {
    general = { borderSize = 1, font = "Quazii", texture = "Quazii v5", fontSize = 11 },
    health  = { healthFillDirection = "HORIZONTAL", healthAnchor = "BOTTOMRIGHT", healthOffsetY = 0 },
    power   = { showPowerBar = true, powerBarHeight = 4 },
    name    = { nameAnchor = "BOTTOMLEFT", nameOffsetY = 0, showLevel = true },
    indicators = {
        roleIconSize = 12, readyCheckSize = 16, summonSize = 20,
        threatFillOpacity = 0.23,
    },
    healer  = {
        targetHighlight = { fillOpacity = 0.17 },
        dispelOverlay = {
            borderSize = 3, fillOpacity = 0.2,
            showIcon = true, iconSize = 22, iconOpacity = 0.75,
            iconAnchor = "BOTTOMLEFT", iconOffsetX = 3, iconOffsetY = 4,
        },
    },
    portrait = { showPortrait = true, portraitSize = 30, portraitSide = "LEFT" },
    absorbs = {}, healAbsorbs = {}, healPrediction = {},
}

local frame = NewFrame("Button", nil, nil)
local geo = Chrome.Apply(frame, VDB)

check("returns the geometry the caller needs", type(geo) == "table"
    and geo.borderSize == 1 and geo.showPower == true and geo.isVertical == false)
-- bottomPad = powerHeight + separator(px) + border  (live formula)
check("bottomPad = power + separator + border", geo.bottomPad == 4 + 1 + 1
    and frame._bottomPad == geo.bottomPad)

check("builds the health bar as a child of the frame",
    frame.healthBar ~= nil and frame.healthBar.parent == frame)
check("overlay bars are children of the HEALTH bar",
    frame.healPredictionBar.parent == frame.healthBar
    and frame.absorbBar.parent == frame.healthBar
    and frame.healAbsorbBar.parent == frame.healthBar)
-- healthBar+1 belongs to tracked-aura health tint. The configured Back/Middle/
-- Front bars own the next three levels, with no tie against each other or text.
local hbLevel = frame.healthBar:GetFrameLevel()
check("overlay draw order is healthBar +2 / +3 / +4",
    frame.healPredictionBar:GetFrameLevel() == hbLevel + 2
    and frame.absorbBar:GetFrameLevel() == hbLevel + 3
    and frame.healAbsorbBar:GetFrameLevel() == hbLevel + 4)
check("text frame uses the collision-free shared level",
    frame._textFrame:GetFrameLevel() == frame:GetFrameLevel() + Chrome.LEVELS.TEXT)
check("name/level/health text all live on the text frame",
    frame.nameText ~= nil and frame.levelText ~= nil and frame.healthText ~= nil)
check("corner indicators live on the text frame too",
    frame.roleIcon ~= nil and frame.readyCheckIcon ~= nil and frame.resIcon ~= nil
    and frame.summonIcon ~= nil and frame.leaderIcon ~= nil and frame.targetMarker ~= nil
    and frame.phaseIcon ~= nil)
check("indicator sizes come from settings", frame.roleIcon.w == 12
    and frame.readyCheckIcon.w == 16 and frame.summonIcon.w == 20)
check("highlight/text/glow ladder has unique increasing frame levels",
    frame.healAbsorbBar:GetFrameLevel() < frame.threatBorder:GetFrameLevel()
    and frame.threatBorder:GetFrameLevel() == frame:GetFrameLevel() + Chrome.LEVELS.THREAT
    and frame.targetHighlight:GetFrameLevel() == frame:GetFrameLevel() + Chrome.LEVELS.TARGET
    and frame.dispelOverlay:GetFrameLevel() == frame:GetFrameLevel() + Chrome.LEVELS.DISPEL
    and frame._textFrame:GetFrameLevel() == frame:GetFrameLevel() + Chrome.LEVELS.TEXT
    and frame.dispelTypeIcons.Magic:GetFrameLevel() == frame:GetFrameLevel() + Chrome.LEVELS.DISPEL_ICON
    and frame.cleanseGlow:GetFrameLevel() == frame:GetFrameLevel() + Chrome.LEVELS.CLEANSE)
check("threat/target backdrops carry a real fill and configured opacity",
    frame.threatBorder.backdrop.bgFile ~= nil
    and frame.targetHighlight.backdrop.bgFile ~= nil
    and frame.threatBorder._fillOpacity == 0.23
    and frame.targetHighlight._fillOpacity == 0.17)
check("dispel overlay carries its 4 borders + fill",
    frame.dispelOverlay.borderTop and frame.dispelOverlay.borderBottom
    and frame.dispelOverlay.borderLeft and frame.dispelOverlay.borderRight
    and frame.dispelOverlay.fill ~= nil)
check("dispel type icon builds all five native atlases with shared geometry",
    frame.dispelTypeIcons.Magic:GetStatusBarTexture().atlas == "RaidFrame-Icon-DebuffMagic"
    and frame.dispelTypeIcons.Curse:GetStatusBarTexture().atlas == "RaidFrame-Icon-DebuffCurse"
    and frame.dispelTypeIcons.Disease:GetStatusBarTexture().atlas == "RaidFrame-Icon-DebuffDisease"
    and frame.dispelTypeIcons.Poison:GetStatusBarTexture().atlas == "RaidFrame-Icon-DebuffPoison"
    and frame.dispelTypeIcons.Bleed:GetStatusBarTexture().atlas == "RaidFrame-Icon-DebuffBleed"
    and frame.dispelTypeIcons.Magic.w == 22
    and frame.dispelTypeIcons.Magic.alpha == 0.75
    and frame.dispelTypeIcons.Magic.points[1].p == "BOTTOMLEFT"
    and frame.dispelTypeIcons.Magic.points[1].x == 3
    and frame.dispelTypeIcons.Magic.points[1].y == 4)
Chrome.ShowDispelTypeIcon(frame, "Bleed")
check("shared dispel icon selector shows only the requested type",
    frame.dispelTypeIcons.Bleed:IsShown()
    and not frame.dispelTypeIcons.Magic:IsShown()
    and not frame.dispelTypeIcons.Curse:IsShown()
    and not frame.dispelTypeIcons.Disease:IsShown()
    and not frame.dispelTypeIcons.Poison:IsShown())
check("portrait built when enabled", frame.portrait ~= nil and frame.portraitTexture ~= nil)

-- Idempotent: a second pass reuses every child (settings changes re-decorate).
local before = {
    hb = frame.healthBar, tf = frame._textFrame, ab = frame.absorbBar,
    magic = frame.dispelTypeIcons.Magic, bleed = frame.dispelTypeIcons.Bleed,
}
local created = frameCount
Chrome.Apply(frame, VDB)
check("re-apply reuses the existing children (no frame leak)",
    frame.healthBar == before.hb and frame._textFrame == before.tf
    and frame.absorbBar == before.ab
    and frame.dispelTypeIcons.Magic == before.magic
    and frame.dispelTypeIcons.Bleed == before.bleed
    and frameCount == created)

-- Vertical fill flips orientation + is reported back.
local vFrame = NewFrame("Button", nil, nil)
local vGeo = Chrome.Apply(vFrame, {
    general = VDB.general, power = { showPowerBar = false },
    health = { healthFillDirection = "VERTICAL" },
    name = {}, indicators = {}, healer = {}, portrait = {},
})
check("vertical fill direction reaches the health bar",
    vGeo.isVertical == true and vFrame.healthBar.orientation == "VERTICAL"
    and vFrame._isVerticalFill == true)
check("power bar off => bottomPad is just the border", vGeo.bottomPad == 1)

-- Per-unit power visibility (role filters) re-anchors the health bar.
local state = {}
local pad = Chrome.ResizeHealthForPower(frame, VDB, false, state)
check("ResizeHealthForPower drops the power gap for a filtered unit",
    pad == 1 and frame._bottomPad == 1)
check("dirty-check state is recorded", state.healthPowerShow == false
    and state.healthPowerBottom == 1)
local sameCall = Chrome.ResizeHealthForPower(frame, VDB, false, state)
check("repeat call with identical geometry short-circuits", sameCall == 1)

-- Pooled-frame regression: Apply rewrites the power gap from the GLOBAL
-- showPowerBar, so it must reseed the dirty-check state. Otherwise the SECOND
-- refresh of a role-filtered tile short-circuits the resize and the tile keeps
-- an empty power-bar gap (preview tiles are pooled; live frames re-decorate).
local pooled = NewFrame("Button", nil, nil)
local pooledState = {}
Chrome.Apply(pooled, VDB, pooledState)
Chrome.ResizeHealthForPower(pooled, VDB, false, pooledState)
check("first pass closes the gap for a filtered unit", pooled._bottomPad == 1)

Chrome.Apply(pooled, VDB, pooledState)   -- second refresh, same tile
check("re-apply restores the global power gap", pooled._bottomPad == 6)
Chrome.ResizeHealthForPower(pooled, VDB, false, pooledState)
check("second pass re-closes the gap (state was reseeded by Apply)",
    pooled._bottomPad == 1)
local pts = pooled.healthBar.points
check("health bar bottom anchor follows the reclaimed gap",
    pts[#pts].p == "BOTTOMRIGHT" and pts[#pts].y == 1)

-- BOTTOM-anchored text and icons must use the SAME pad as the health bar. The
-- build pass writes the GLOBAL power geometry; the per-unit role filter then
-- reclaims the gap, and everything anchored to the bottom has to follow -- or
-- the frame mixes a per-unit health bar with global-pad text.
local padded = NewFrame("Button", nil, nil)
local paddedState = {}
Chrome.Apply(padded, VDB, paddedState)
local function bottomY(region)
    for i = #region.points, 1, -1 do
        if region.points[i].p:find("BOTTOM") then return region.points[i].y end
    end
end
check("build pass anchors bottom text at the global pad", bottomY(padded.nameText) == 6
    and bottomY(padded.healthText) == 6)
check("build pass anchors the BOTTOM* indicator at the global pad",
    bottomY(padded.phaseIcon) == 2 + 6)

Chrome.ResizeHealthForPower(padded, VDB, false, paddedState)
check("filtered unit moves bottom text down with the health bar",
    bottomY(padded.nameText) == 1 and bottomY(padded.healthText) == 1)
check("filtered unit moves BOTTOM* indicators too", bottomY(padded.phaseIcon) == 2 + 1)
check("TOP-anchored icons are untouched by the pad",
    padded.roleIcon.points[#padded.roleIcon.points].y == -2)

-- Shared dispel tint paints all four borders + the fill.
Chrome.SetDispelBorderColor(frame.dispelOverlay, 0.2, 0.6, 1.0, 0.8)
check("dispel tint reaches every border and the fill",
    frame.dispelOverlay.borderTop:GetStatusBarTexture().vertex[1] == 0.2
    and frame.dispelOverlay.borderRight:GetStatusBarTexture().vertex[4] == 0.8
    and frame.dispelOverlay.fill.vertex ~= nil)

Chrome.SetBackdropOverlayColor(frame.threatBorder, 1, 0, 0, 0.8)
Chrome.SetBackdropOverlayColor(frame.targetHighlight, 1, 1, 1, 0.6)
check("threat/target tint helper applies border and configured fill alpha",
    frame.threatBorder.borderColor[4] == 0.8
    and frame.threatBorder.Center.vertex[4] == 0.23
    and frame.targetHighlight.borderColor[4] == 0.6
    and frame.targetHighlight.Center.vertex[4] == 0.17)

-- Frame dimensions: one tier table for the live header and the preview tiles.
check("dimension tiers map roster size the way the live header does",
    Chrome.DimensionMode(5, "party") == "party"
    and Chrome.DimensionMode(5) == "party"
    and Chrome.DimensionMode(15, "raid") == "small"
    and Chrome.DimensionMode(25, "raid") == "medium"
    and Chrome.DimensionMode(40, "raid") == "large"
    and Chrome.DimensionMode(5, "raid") == "small")
local dimVDB = { dimensions = { partyWidth = 210, smallRaidHeight = 33 } }
local w, h = Chrome.FrameDimensions(dimVDB, "party")
check("configured dimension wins, unset falls back to the live default",
    w == 210 and h == 40)
local sw, sh = Chrome.FrameDimensions(dimVDB, "small")
check("per-tier keys resolve independently", sw == 180 and sh == 33)
local dw, dh = Chrome.FrameDimensions(nil, "party")
check("no dimensions table = live defaults (200x40, not the old preview 150x80)",
    dw == 200 and dh == 40)

---------------------------------------------------------------------------
-- 2. SOURCE PINS — both consumers go through the shared builder
---------------------------------------------------------------------------
local live = readAll("QUI_GroupFrames/groupframes/groupframes.lua")
check("runtime DecorateGroupFrame calls the shared builder with its state table",
    live:find("Chrome.Apply(frame, vdb, GetFrameState(frame))", 1, true) ~= nil)
check("runtime keeps no private copy of the builder's helpers",
    live:find("local function ApplyOverlayBar", 1, true) == nil
    and live:find("local function GetCachedBackdrop", 1, true) == nil
    and live:find("local ANCHOR_MAP", 1, true) == nil)

local prev = readAll("QUI_GroupFrames/groupframes/settings/group_frames_preview_driver.lua")
check("preview driver calls the same builder, threading its state table",
    prev:find("Chrome.Apply(f, vdb, f._chromeState)", 1, true) ~= nil
    and prev:find("Chrome.ResizeHealthForPower(f, vdb, showPower", 1, true) ~= nil)
check("preview driver no longer re-implements the skeleton",
    prev:find("local function ApplyAppearance", 1, true) == nil
    and prev:find("local function ApplyHealthBar", 1, true) == nil
    and prev:find("local function PlaceIndicator", 1, true) == nil
    and prev:find("local function ApplyPortrait(", 1, true) == nil)
check("preview sizes tiles through the shared tier table (no private copy)",
    prev:find("Chrome.FrameDimensions(vdb, Chrome.DimensionMode(count, contextMode))", 1, true) ~= nil
    and prev:find("smallRaidWidth", 1, true) == nil)
-- The grid itself cannot be shared -- the live layout is produced by the secure
-- header, not by QUI code -- so pin the layout DEFAULTS the preview replicates
-- against the ones the live header math uses.
local liveSpacing = live:match("local spacing = layout and layout%.spacing or (%d+)")
local liveGroupSpacing = live:match("local groupSpacing = layout and layout%.groupSpacing or (%d+)")
local prevSpacing = prev:match("tonumber%(layout%.spacing%) or (%d+)")
local prevGroupSpacing = prev:match("tonumber%(layout%.groupSpacing%) or (%d+)")
check("preview grid spacing default matches the live header (" .. tostring(liveSpacing) .. ")",
    liveSpacing ~= nil and prevSpacing == liveSpacing)
check("preview group spacing default matches the live header (" .. tostring(liveGroupSpacing) .. ")",
    liveGroupSpacing ~= nil and prevGroupSpacing == liveGroupSpacing)

check("preview driver reads the live role/dispel palettes, not private copies",
    prev:find("ns.QUI_GroupFrameRoleAtlas", 1, true) ~= nil
    and prev:find("IL.DISPEL_DEFAULT_COLORS", 1, true) ~= nil)
check("runtime and preview both use shared full-frame tint helper",
    live:find("Chrome.SetBackdropOverlayColor(frame.threatBorder", 1, true) ~= nil
    and live:find("Chrome.SetBackdropOverlayColor(frame.targetHighlight", 1, true) ~= nil
    and prev:find("C.SetBackdropOverlayColor(tb", 1, true) ~= nil
    and prev:find("C.SetBackdropOverlayColor(th", 1, true) ~= nil)
local auraRender = readAll("QUI_GroupFrames/groupframes/groupframes_aura_render.lua")
local auraContainers = readAll("QUI_GroupFrames/groupframes/groupframes_auras.lua")
local targeted = readAll("QUI_GroupFrames/groupframes/groupframes_targeted_spells.lua")
local editMode = readAll("QUI_GroupFrames/groupframes/groupframes_editmode.lua")
check("runtime and both previews use the shared dispel-type icon helpers",
    live:find("Chrome.ShowDispelTypeIcon(frame, visualType)", 1, true) ~= nil
    and prev:find("C.ShowDispelTypeIcon(f, dispelType)", 1, true) ~= nil
    and editMode:find("Chrome.ApplyDispelIconLayout(frame, dsp)", 1, true) ~= nil
    and editMode:find("Chrome.ShowDispelTypeIcon(frame, sampleType)", 1, true) ~= nil)
check("aura, targeted-spell and Edit Mode layers consume the shared ladder",
    auraRender:find("CHROME_LEVELS.AURA_HOST", 1, true) ~= nil
    and auraRender:find("CHROME_LEVELS.AURA_BAR", 1, true) ~= nil
    and auraContainers:find("CHROME_LEVELS.AURA_HOST", 1, true) ~= nil
    and targeted:find("CHROME_LEVELS.TARGETED", 1, true) ~= nil
    and editMode:find("CHROME_LEVELS.TEXT", 1, true) ~= nil)
check("secure aura-container relevel never calls protected SetFrameLevel in combat",
    auraContainers:find("if not InCombatLockdown() then", 1, true) ~= nil
    and auraContainers:find("container:SetFrameLevel(desiredLevel)", 1, true) ~= nil
    and auraContainers:find("return container:GetFrameLevel() == desiredLevel", 1, true) ~= nil)

if fails > 0 then
    error(fails .. " failure(s) in groupframes_chrome_shared_test")
end
print("OK: groupframes_chrome_shared_test (all checks passed)")
