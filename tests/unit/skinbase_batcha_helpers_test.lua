-- tests/unit/skinbase_batcha_helpers_test.lua
-- Run: lua tests/unit/skinbase_batcha_helpers_test.lua
-- Covers the Batch-A shared engine additions in core/uikit.lua:
--   SkinBase.HoverBrightenColor / SkinBase.HOVER_BRIGHTEN
--   SkinBase.StripTexturesExcept
--   SkinBase.KillNineSlice (incl. durable OnShow re-hide + idempotency)
-- luacheck: globals CreateFrame C_Timer hooksecurefunc

local function NewTexture()
    local t = { alpha = 1, visible = true }
    function t:SetAlpha(a) self.alpha = a end
    function t:SetTexture(f) self.file = f; self.setTextureCalls = (self.setTextureCalls or 0) + 1; return true end
    function t:SetShown(s) self.visible = s end
    function t:Show() self.visible = true end
    function t:Hide() self.visible = false end
    function t:IsShown() return self.visible end
    function t:IsObjectType(objType) return objType == "Texture" end
    return t
end

local function NewFrame()
    local f = { textures = {}, alpha = 1, shown = true, scripts = {} }
    function f:GetRegions() return unpack(self.textures) end
    function f:GetNumRegions() return #self.textures end
    function f:Hide() self.shown = false end
    function f:Show() self.shown = true end
    function f:SetAlpha(a) self.alpha = a end
    function f:HookScript(event, fn) self.scripts[event] = fn end
    return f
end

function CreateFrame(_, _, parent) return NewFrame(parent) end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end

local ns = {
    Helpers = {
        CHROME = {
            BORDER_PX = 1,
            BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 },
            BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03,
            DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } },
        },
        CreateStateTable = function()
            local tbl = setmetatable({}, { __mode = "k" })
            local function get(key)
                local s = tbl[key]
                if not s then s = {}; tbl[key] = s end
                return s
            end
            return tbl, get
        end,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
        GetSkinBarColor = function() return 0.5, 0.5, 0.5, 1 end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}

assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

-- ── HoverBrightenColor / HOVER_BRIGHTEN ────────────────────────────────────
assert(SkinBase.HOVER_BRIGHTEN == 1.3, "HOVER_BRIGHTEN must be exposed as 1.3")
do
    local r, g, b, a = SkinBase.HoverBrightenColor(0.5, 0.4, 0.2, 0.8)
    assert(math.abs(r - 0.65) < 1e-9, "HoverBrightenColor must brighten r by 1.3")
    assert(math.abs(g - 0.52) < 1e-9, "HoverBrightenColor must brighten g by 1.3")
    assert(math.abs(b - 0.26) < 1e-9, "HoverBrightenColor must brighten b by 1.3")
    assert(a == 0.8, "HoverBrightenColor must pass alpha through unchanged")
    -- clamp to 1
    local cr = SkinBase.HoverBrightenColor(0.9, 0, 0, 1)
    assert(cr == 1, "HoverBrightenColor must clamp brightened channel to 1")
    -- custom factor
    local _, fg = SkinBase.HoverBrightenColor(0, 0.5, 0, 1, 2)
    assert(fg == 1, "HoverBrightenColor must honor a custom factor (0.5*2=1)")
    -- nil channels coerce to 0, not error
    local nr = SkinBase.HoverBrightenColor(nil, nil, nil, nil)
    assert(nr == 0, "HoverBrightenColor must treat nil channels as 0")
end

-- ── StripTexturesExcept ────────────────────────────────────────────────────
do
    local frame = NewFrame()
    local keep, drop1, drop2 = NewTexture(), NewTexture(), NewTexture()
    frame.textures = { keep, drop1, drop2 }
    local preserve = { [keep] = true }
    SkinBase.StripTexturesExcept(frame, preserve)
    assert(keep.alpha == 1, "StripTexturesExcept must NOT touch preserved regions")
    assert(drop1.alpha == 0 and drop2.alpha == 0, "StripTexturesExcept must hide non-preserved regions")

    -- nil preserve == StripTextures (strip everything)
    local f2 = NewFrame()
    local a, b = NewTexture(), NewTexture()
    f2.textures = { a, b }
    SkinBase.StripTexturesExcept(f2)
    assert(a.alpha == 0 and b.alpha == 0, "StripTexturesExcept with nil preserve must strip all textures")

    -- nil frame is a no-op (no error)
    SkinBase.StripTexturesExcept(nil, nil)
end

-- ── KillNineSlice ──────────────────────────────────────────────────────────
do
    local ns9 = NewFrame()
    -- child regions returned by GetRegions
    local childTex = NewTexture()
    ns9.textures = { childTex }
    -- named parts as fields
    local tl, center = NewTexture(), NewTexture()
    ns9.TopLeftCorner = tl
    ns9.Center = center

    SkinBase.KillNineSlice(ns9)
    assert(ns9.shown == false, "KillNineSlice must hide the NineSlice frame")
    assert(ns9.alpha == 0, "KillNineSlice must zero the NineSlice alpha")
    assert(childTex.visible == false, "KillNineSlice must hide child Texture regions")
    assert(childTex.file == nil and childTex.setTextureCalls == 1, "KillNineSlice must SetTexture(nil) on child regions (never SetAtlas)")
    assert(tl.visible == false and center.visible == false, "KillNineSlice must hide named NineSlice parts")
    assert(tl.setTextureCalls == 1 and center.setTextureCalls == 1, "KillNineSlice must clear named parts via SetTexture(nil)")
    assert(ns9.scripts.OnShow == nil, "KillNineSlice without durable must NOT install an OnShow hook")

    -- durable installs an OnShow re-hide and is idempotent
    local d = NewFrame()
    SkinBase.KillNineSlice(d, true)
    assert(type(d.scripts.OnShow) == "function", "KillNineSlice(durable) must install an OnShow re-hide")
    d.shown = true
    d.scripts.OnShow(d) -- simulate Blizzard re-show
    assert(d.shown == false, "durable OnShow hook must re-hide the frame on re-show")

    local firstHook = d.scripts.OnShow
    SkinBase.KillNineSlice(d, true) -- second call: idempotent, must not re-hook
    assert(d.scripts.OnShow == firstHook, "KillNineSlice(durable) must be idempotent (no duplicate OnShow hook)")

    -- nil arg is a no-op
    SkinBase.KillNineSlice(nil)
end

print("skinbase_batcha_helpers_test: OK")
