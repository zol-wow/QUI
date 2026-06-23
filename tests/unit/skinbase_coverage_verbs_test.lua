-- tests/unit/skinbase_coverage_verbs_test.lua
-- Run: lua tests/unit/skinbase_coverage_verbs_test.lua
-- Covers the Stage-3 coverage verbs in core/uikit.lua:
--   SkinBase.SkinStatusBar  (flat fill + color + backdrop, idempotent)
--   SkinBase.SkinNextPrevButton (SkinButton + directional chevron glyph)
-- CreateBackdrop / SkinButton are spied after load so the test targets the
-- verbs' own logic.
-- luacheck: globals CreateFrame C_Timer hooksecurefunc STANDARD_TEXT_FONT

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

local function NewFontString()
    local fs = {}
    function fs:SetFont(f, s, fl) self.font, self.size, self.flags = f, s, fl end
    function fs:SetText(t) self.text = t end
    function fs:SetPoint() end
    function fs:SetTextColor(...) self.color = { ... } end
    return fs
end

local function NewBar()
    local b = { frameLevel = 2 }
    function b:SetStatusBarTexture(t) self.barTexture = t; return true end
    function b:SetStatusBarColor(r, g, bl, a) self.barColor = { r, g, bl, a } end
    function b:GetFrameLevel() return self.frameLevel end
    return b
end

local function NewButton()
    local b = {}
    function b:CreateFontString() return NewFontString() end
    return b
end

function CreateFrame() return { GetFrameLevel = function() return 1 end, SetAllPoints = function() end, SetFrameLevel = function() end, EnableMouse = function() end } end
C_Timer = { After = function(_, fn) fn() end }
local postHooks = {}
function hooksecurefunc(obj, method, fn)
    postHooks[obj] = postHooks[obj] or {}
    postHooks[obj][method] = fn
end

local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = function()
            local tbl = setmetatable({}, { __mode = "k" })
            local function get(key) local s = tbl[key]; if not s then s = {}; tbl[key] = s end; return s end
            return tbl, get
        end,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
        GetSkinBarColor = function() return 0.5, 0.55, 0.6, 1 end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}

assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

-- spies
local backdrops = {}
SkinBase.CreateBackdrop = function(frame) backdrops[#backdrops + 1] = frame end
local skinButtonCalls = {}
SkinBase.SkinButton = function(button, opts) skinButtonCalls[#skinButtonCalls + 1] = { button = button, opts = opts } end
local recolors = {}
SkinBase.SetBackdropColors = function(frame, borderColor) recolors[#recolors + 1] = { frame = frame, border = borderColor } end

-- ── SkinStatusBar ──────────────────────────────────────────────────────────
do
    local bar = NewBar()
    SkinBase.SkinStatusBar(bar)
    assert(bar.barTexture == "Interface\\Buttons\\WHITE8x8", "SkinStatusBar must apply a flat fill texture")
    assert(bar.barColor and math.abs(bar.barColor[1] - 0.5) < 1e-9, "SkinStatusBar must default fill color to GetSkinBarColor")
    assert(backdrops[#backdrops] == bar, "SkinStatusBar must create a QUI backdrop by default")
    assert(SkinBase.IsStyled(bar), "SkinStatusBar must MarkStyled")

    -- idempotent
    local n = #backdrops
    SkinBase.SkinStatusBar(bar)
    assert(#backdrops == n, "SkinStatusBar must be idempotent (IsStyled guard)")

    -- explicit color + backdrop=false
    local bar2 = NewBar()
    local b = #backdrops
    SkinBase.SkinStatusBar(bar2, { color = { 0.9, 0.1, 0.1, 1 }, backdrop = false })
    assert(math.abs(bar2.barColor[1] - 0.9) < 1e-9, "SkinStatusBar must honor an explicit fill color")
    assert(#backdrops == b, "SkinStatusBar{backdrop=false} must skip the backdrop")
end

-- ── SkinNextPrevButton ─────────────────────────────────────────────────────
do
    local prev = NewButton()
    SkinBase.SkinNextPrevButton(prev, "prev")
    local call = skinButtonCalls[#skinButtonCalls]
    assert(call.button == prev and call.opts and call.opts.strip == true, "SkinNextPrevButton must SkinButton{strip=true}")
    local glyph = SkinBase.GetFrameData(prev, "nextPrevGlyph")
    assert(glyph and glyph.text == "\226\151\132", "prev button must get the ◄ glyph")
    assert(glyph.font == "Interface\\QUIFont.ttf", "glyph must use the QUI font")

    local nxt = NewButton()
    SkinBase.SkinNextPrevButton(nxt, "right")
    assert(SkinBase.GetFrameData(nxt, "nextPrevGlyph").text == "\226\150\186", "next button must get the ► glyph")

    -- idempotent
    local n = #skinButtonCalls
    SkinBase.SkinNextPrevButton(prev, "prev")
    assert(#skinButtonCalls == n, "SkinNextPrevButton must be idempotent")
end

-- ── SkinCheckBox ───────────────────────────────────────────────────────────
do
    local function NewCheckTex() local t = { alpha = 1 }; function t:SetTexture() end; function t:SetAlpha(a) self.alpha = a end; function t:SetVertexColor(...) self.vertex = { ... } end; function t:SetDrawLayer(...) self.layer = { ... } end; return t end
    local check = { frameLevel = 2 }
    local normalTex, checkedTex = NewCheckTex(), NewCheckTex()
    function check:GetNormalTexture() return normalTex end
    function check:GetCheckedTexture() return checkedTex end
    function check:GetFrameLevel() return self.frameLevel end

    local b0 = #backdrops
    SkinBase.SkinCheckBox(check)
    assert(normalTex.alpha == 0, "SkinCheckBox must hide the box (normal) texture")
    assert(backdrops[#backdrops] == check, "SkinCheckBox must create a QUI backdrop box")
    assert(checkedTex.vertex ~= nil, "SkinCheckBox must accent-tint the check mark")
    assert(SkinBase.IsStyled(check), "SkinCheckBox must MarkStyled")
    SkinBase.SkinCheckBox(check)
    assert(#backdrops == b0 + 1, "SkinCheckBox must be idempotent (one backdrop only)")
end

-- ── HandleIconBorder ───────────────────────────────────────────────────────
do
    local quiBorder = {}
    local native = { alpha = 1 }
    function native:SetAlpha(a) self.alpha = a end
    function native:SetVertexColor() end
    function native:Hide() end
    local recBefore = #recolors
    SkinBase.HandleIconBorder(native, quiBorder, { defaultBorder = { 0, 0, 0, 1 } })
    assert(native.alpha == 0, "HandleIconBorder must hide the native ring")
    -- fire the SetVertexColor hook → mirror quality color onto the QUI border
    postHooks[native].SetVertexColor(native, 0.64, 0.21, 0.93, 1)
    assert(recolors[#recolors].frame == quiBorder and math.abs(recolors[#recolors].border[1] - 0.64) < 1e-9,
        "HandleIconBorder must mirror the SetVertexColor quality color onto the QUI border")
    -- fire Hide → revert to default
    postHooks[native].Hide(native)
    assert(recolors[#recolors].border[1] == 0, "HandleIconBorder must revert to defaultBorder when the ring hides")
    assert(#recolors > recBefore, "HandleIconBorder must recolor via SetBackdropColors")
    -- idempotent
    local hk = postHooks[native].SetVertexColor
    SkinBase.HandleIconBorder(native, quiBorder)
    assert(postHooks[native].SetVertexColor == hk, "HandleIconBorder must be idempotent (no re-hook)")
end

-- ── SkinTrimScrollBar ──────────────────────────────────────────────────────
do
    local function NewTex() local t = {}; function t:SetAlpha(a) self.alpha = a end; function t:SetColorTexture(...) self.color = { ... } end; function t:SetWidth(w) self.width = w end; return t end
    local sb = {}
    sb.Track, sb.Background, sb.ThumbTexture = NewTex(), NewTex(), NewTex()
    sb.ScrollUpButton = { SetAlpha = function(s, a) s.alpha = a end, SetSize = function(s, x, y) s.size = { x, y } end }
    sb.ScrollDownButton = { SetAlpha = function(s, a) s.alpha = a end, SetSize = function(s, x, y) s.size = { x, y } end }
    function sb:GetFrameLevel() return 1 end
    SkinBase.SkinTrimScrollBar(sb, { color = { 0.3, 0.4, 0.5 } })
    assert(sb.Track.alpha == 0 and sb.Background.alpha == 0, "SkinTrimScrollBar must hide track + background")
    assert(sb.ThumbTexture.color and math.abs(sb.ThumbTexture.color[1] - 0.3) < 1e-9, "SkinTrimScrollBar must color the thumb")
    assert(sb.ScrollUpButton.alpha == 0 and sb.ScrollDownButton.alpha == 0, "SkinTrimScrollBar must hide the arrow buttons")
end

-- ── SkinWindow (uniform window sequence) ───────────────────────────────────
do
    local calls = {}
    SkinBase.HidePortraitFrameChrome = function() calls.chrome = true end
    SkinBase.SkinCloseButton = function() calls.close = true end
    SkinBase.SkinFrameText = function() calls.font = true end
    SkinBase.LockFrameTextObjects = function() calls.lock = true end
    SkinBase.ApplyButtonFontObjectsDeep = function() calls.btnfont = true end
    SkinBase.SkinTabGroup = function() calls.tabs = true end
    SkinBase.SkinTrimScrollBar = function() calls.scroll = true end
    local bdCount = #backdrops

    local win = { CloseButton = {} }
    SkinBase.SkinWindow(win)
    assert(calls.chrome, "SkinWindow must hide portrait chrome")
    assert(#backdrops == bdCount + 1, "SkinWindow must create a backdrop by default")
    assert(calls.close, "SkinWindow must skin the close button when present")
    -- Static-text face now comes from the global font-object override (font_system.lua
    -- ApplyGlobalDefaultFont); SkinFrameText and LockFrameTextObjects are no longer
    -- called by SkinWindow — only ApplyButtonFontObjectsDeep for interactive swaps.
    assert(calls.btnfont, "SkinWindow must call ApplyButtonFontObjectsDeep for interactive font objects")
    assert(not calls.font, "SkinWindow must NOT call SkinFrameText (global object override owns static text)")
    assert(not calls.lock, "SkinWindow must NOT call LockFrameTextObjects (global object override owns static text)")

    -- opts: noBackdrop / noClose / noButtonFonts skip their steps; tabs + scrollBars opt-in
    calls = {}; local n2 = #backdrops
    SkinBase.SkinWindow({ CloseButton = {} }, { noBackdrop = true, noClose = true, noButtonFonts = true, tabs = {}, scrollBars = { {} } })
    assert(#backdrops == n2, "SkinWindow{noBackdrop} must skip the backdrop")
    assert(not calls.close, "SkinWindow{noClose} must skip the close button")
    assert(not calls.btnfont, "SkinWindow{noButtonFonts} must skip button font objects")
    assert(calls.tabs, "SkinWindow{tabs} must skin the tab group")
    assert(calls.scroll, "SkinWindow{scrollBars} must skin the scrollbars")
    -- SkinFrameText and LockFrameTextObjects are superseded by the global object override;
    -- they are never called by SkinWindow regardless of opts.
    assert(not calls.font, "SkinWindow must NOT call SkinFrameText (not even via opts)")
    assert(not calls.lock, "SkinWindow must NOT call LockFrameTextObjects (not even via opts)")
end

print("skinbase_coverage_verbs_test: OK")
