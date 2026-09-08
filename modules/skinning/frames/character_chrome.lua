-- Character window chrome owner (ns.CharacterChrome).
--
-- Two profile gates touch the Character window: general.skinCharacterFrame
-- (Blizzard-surface skin) and character.enabled (the QUI enhancement pane).
-- Before this file each side built its own shell, tabs, close button and
-- popouts, so the combinations disagreed (dark backdrop under Blizzard slot
-- art, red close X, native stats pane at full alpha). This module is the ONE
-- writer for the shared chrome; both consumers ask it instead of drawing.
--
-- Ownership matrix (skinCharacterFrame x character.enabled):
--   off/off  stock Blizzard, no QUI writes.
--   off/on   enhancement fallback shell via EnsureShell; tabs/close/scroll here.
--   on/off   shell + tabs + close here; native slots/stats pane get a
--            chrome-only skin (slot borders, skinned close, legible stats pane).
--   on/on    full redesign; enhancement delegates all chrome via SetExtended.
--
-- Taint rules: no custom fields on Blizzard frames (SkinBase.SetFrameData),
-- hooks via hooksecurefunc/HookScript only, error dispatch through ns.SafeCall.
local _, ns = ...
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local UIKit = ns.UIKit
local GetCore = Helpers.GetCore

local function CJKFont(fs, p, s, f)
    if Helpers and Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local function GeneralFontFace()
    return (Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or STANDARD_TEXT_FONT
end

local CharacterChrome = {}
ns.CharacterChrome = CharacterChrome

local CONFIG = {
    PANEL_WIDTH_EXTENSION = 55,
    PANEL_HEIGHT_EXTENSION = 50,
    POPOUT_WIDTH = 205,
    POPOUT_HEIGHT = 400,
    POPOUT_GAP = 10,
    FLYOUT_WIDTH = 450,
    FLYOUT_HEIGHT = 600,
    FLYOUT_GAP = 5,
    FLYOUT_GUTTER = 14,
    TRIGGER_WIDTH = 118,
    TRIGGER_HEIGHT = 20,
    SCROLL_STEP = 30,
}
CharacterChrome.CONFIG = CONFIG

local GetSkinColors = Helpers.CreateSkinColorGetter("characterFrame")

-- Border colour as TEXT colour, luminance-floored (a black / hidden border
-- must not turn titles black or invisible).
local function GetTextAccent()
    local profile = Helpers.GetProfile and Helpers.GetProfile()
    return SkinBase.GetSkinTextAccent(profile and profile.general, "characterFrame")
end
CharacterChrome.GetTextAccent = GetTextAccent

local TOKEN_FALLBACK = {
    tabSelectedText = { 1, 1, 1, 1 },
    tabNormal = { 1, 1, 1, 0.55 },
    tabHover = { 1, 1, 1, 0.85 },
    disabled = { 1, 1, 1, 0.30 },
    bgContent = { 1, 1, 1, 0.02 },
}

local function Token(name)
    local gui = _G.QUI and _G.QUI.GUI
    local colors = gui and gui.Colors
    return (colors and colors[name]) or TOKEN_FALLBACK[name] or TOKEN_FALLBACK.tabSelectedText
end
CharacterChrome.Token = Token

---------------------------------------------------------------------------
-- Gates and ownership
---------------------------------------------------------------------------
local function GetProfile()
    local core = GetCore()
    return core and core.db and core.db.profile
end

local function IsSkinOn()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return false end
    local profile = GetProfile()
    local general = profile and profile.general
    return (general and general.skinCharacterFrame) and true or false
end

local function IsEnhancementOn()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return false end
    local profile = GetProfile()
    local character = profile and profile.character
    return not (character and character.enabled == false)
end

-- Pure resolver so tests can drive all four combinations without a profile.
function CharacterChrome.ResolveOwnership(skinOn, enhancementOn)
    skinOn = skinOn and true or false
    enhancementOn = enhancementOn and true or false
    local shell = "none"
    if skinOn then
        shell = "skin"
    elseif enhancementOn then
        shell = "enhancement"
    end
    return {
        skin = skinOn,
        enhancement = enhancementOn,
        shell = shell,
        tabs = skinOn or enhancementOn,
        close = skinOn or enhancementOn,
        popouts = skinOn or enhancementOn,
        halfSkinned = skinOn and not enhancementOn,
        slots = enhancementOn and "enhancement" or (skinOn and "chrome" or "none"),
        statsPane = enhancementOn and "enhancement" or (skinOn and "chrome" or "native"),
    }
end

function CharacterChrome.GetOwnership()
    return CharacterChrome.ResolveOwnership(IsSkinOn(), IsEnhancementOn())
end

-- True when the SKIN gate draws the shell (the enhancement then delegates its
-- background through SetExtended instead of building a fallback).
function CharacterChrome.OwnsShell()
    return CharacterChrome.GetOwnership().shell == "skin"
end

---------------------------------------------------------------------------
-- Native stats pane (mask for the enhancement, legible chrome-only otherwise)
---------------------------------------------------------------------------
local function MaskNativeStatsPane()
    if not CharacterStatsPane then return end
    ns.SafeCallMethod("best-effort-style", CharacterStatsPane, "SetAlpha", 0)
    ns.SafeCallMethodIfPresent("best-effort-style", CharacterStatsPane, "EnableMouse", false)
    if CharacterStatsPane.ClassBackground then
        ns.SafeCallMethod("best-effort-style", CharacterStatsPane.ClassBackground, "SetAlpha", 0)
    end
end

local function RestoreNativeStatsPane()
    if not CharacterStatsPane then return end
    ns.SafeCallMethod("best-effort-style", CharacterStatsPane, "SetAlpha", 1)
    ns.SafeCallMethodIfPresent("best-effort-style", CharacterStatsPane, "EnableMouse", true)
    if CharacterStatsPane.ClassBackground then
        ns.SafeCallMethod("best-effort-style", CharacterStatsPane.ClassBackground, "SetAlpha", 1)
    end
end

local function SkinStatRow(statFrame)
    if not statFrame then return end
    if statFrame.Background then statFrame.Background:SetAlpha(0) end
    if statFrame.Label then
        SkinBase.SkinFontString(statFrame.Label, { size = 11, color = Token("tabHover") })
    end
    if statFrame.Value then
        SkinBase.SkinFontString(statFrame.Value, { size = 11, color = Token("tabSelectedText") })
    end
    SkinBase.SetFrameData(statFrame, "qCharChromeStatRow", true)
end

local function SkinStatCategory(category)
    if not category then return end
    if category.Background then category.Background:SetAlpha(0) end
    if category.Title then
        local r, g, b = GetTextAccent()
        SkinBase.SkinFontString(category.Title, { size = 12, color = { r, g, b, 1 } })
    end
end

local statRowHookInstalled = false

-- Chrome-only stats pane: Blizzard keeps rendering the rows, we make them
-- legible on the dark shell (fonts + no parchment atlases). Row fonts ride a
-- post-hook on the label writer so pooled rows are covered as they appear.
local function ApplyNativeStatsPaneChrome()
    if not CharacterStatsPane then return end
    RestoreNativeStatsPane()
    if CharacterStatsPane.ClassBackground then
        ns.SafeCallMethod("best-effort-style", CharacterStatsPane.ClassBackground, "SetAlpha", 0)
    end
    SkinStatCategory(CharacterStatsPane.ItemLevelCategory)
    SkinStatCategory(CharacterStatsPane.AttributesCategory)
    SkinStatCategory(CharacterStatsPane.EnhancementsCategory)
    local ilvlFrame = CharacterStatsPane.ItemLevelFrame
    if ilvlFrame then
        if ilvlFrame.Background then ilvlFrame.Background:SetAlpha(0) end
        if ilvlFrame.Value then
            SkinBase.SkinFontString(ilvlFrame.Value, { size = 15, outline = "OUTLINE", color = Token("tabSelectedText") })
        end
    end
    local pool = CharacterStatsPane.statsFramePool
    if pool and pool.EnumerateActive then
        for statFrame in pool:EnumerateActive() do
            SkinStatRow(statFrame)
        end
    end
    if not statRowHookInstalled and type(_G.PaperDollFrame_SetLabelAndText) == "function" then
        statRowHookInstalled = true
        hooksecurefunc("PaperDollFrame_SetLabelAndText", function(statFrame)
            if not CharacterChrome.GetOwnership().halfSkinned then return end
            if SkinBase.GetFrameData(statFrame, "qCharChromeStatRow") then return end
            SkinStatRow(statFrame)
        end)
    end
end

---------------------------------------------------------------------------
-- Shell (background + Blizzard decoration hiding)
---------------------------------------------------------------------------
local shell = nil
local nineSliceHooked = Helpers.CreateStateTable()

local function HideNineSlice(nineSlice, permanent)
    if not nineSlice then return end
    nineSlice:Hide()
    nineSlice:SetAlpha(0)
    if permanent and not nineSliceHooked[nineSlice] then
        hooksecurefunc(nineSlice, "Show", function(self) self:Hide(); self:SetAlpha(0) end)
        nineSliceHooked[nineSlice] = true
    end
end

local ApplyHalfSkinnedChrome

-- Hides the portrait frame art behind the shell. `permanent` (skin owner)
-- pins the nine slices hidden; the enhancement fallback re-shows native
-- chrome on the Reputation/Currency tabs, so it gets a one-shot hide.
local function HideBlizzardDecorations(permanent)
    if not CharacterFrame then return end
    if permanent then
        SkinBase.HidePortraitFrameChrome(CharacterFrame)
        HideNineSlice(CharacterFrameInset and CharacterFrameInset.NineSlice, true)
        HideNineSlice(CharacterFrameInsetRight and CharacterFrameInsetRight.NineSlice, true)
    elseif CharacterFrame.Background then
        -- Fallback shell: hide only what the enhancement re-shows on the
        -- Reputation / Currency tabs (portrait, background, nine slice, bg).
        CharacterFrame.Background:Hide()
    end
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    HideNineSlice(CharacterFrame.NineSlice, permanent)
    if CharacterFrameBg then CharacterFrameBg:Hide() end

    local ownership = CharacterChrome.GetOwnership()
    if ownership.statsPane == "enhancement" then
        local mask = ns.QUI_MaskNativeStatsPane or MaskNativeStatsPane
        mask()
    elseif ownership.statsPane == "chrome" then
        ApplyHalfSkinnedChrome()
    else
        RestoreNativeStatsPane()
    end
end

local function ApplyShellColors()
    if not shell then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    SkinBase.ApplyPixelBackdrop(shell, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
end

-- opts.extended: true = reach past the frame for the enhancement layout,
-- false = hug CharacterFrame, nil = keep the current anchoring.
function CharacterChrome.EnsureShell(opts)
    local ownership = CharacterChrome.GetOwnership()
    if ownership.shell == "none" or not CharacterFrame then return nil end

    if not shell then
        shell = CreateFrame("Frame", "QUI_CharacterFrameBg_Skin", CharacterFrame, "BackdropTemplate")
        shell:SetFrameStrata("BACKGROUND")
        shell:SetFrameLevel(0)
        shell:EnableMouse(false)
        shell:SetAllPoints(CharacterFrame)
    end
    ApplyShellColors()

    if opts and opts.extended ~= nil then
        shell:ClearAllPoints()
        if opts.extended then
            shell:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
            shell:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT",
                CONFIG.PANEL_WIDTH_EXTENSION, -CONFIG.PANEL_HEIGHT_EXTENSION)
        else
            shell:SetAllPoints(CharacterFrame)
        end
    end

    shell:Show()
    HideBlizzardDecorations(ownership.shell == "skin")
    return shell
end

function CharacterChrome.SetExtended(extended)
    return CharacterChrome.EnsureShell({ extended = extended and true or false })
end

function CharacterChrome.GetShell()
    return shell
end

---------------------------------------------------------------------------
-- Tabs, close button, scrollbars
---------------------------------------------------------------------------
function CharacterChrome.StyleTabs()
    if not CharacterFrame or not CharacterChrome.GetOwnership().tabs then return end
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("CharacterFrame", 3), CharacterFrame, { font = true })
end

local closeButtons = Helpers.CreateStateTable()

function CharacterChrome.StyleCloseButton(button, opts)
    if not button or not SkinBase.SkinChromeCloseButton then return end
    opts = opts or {}
    SkinBase.SkinChromeCloseButton(button, {
        stateKey = "characterChromeClose",
        font = GeneralFontFace(),
        fontFlags = "OUTLINE",
        fontSize = opts.fontSize,
        textColor = Token("tabHover"),
        accentColor = function() local r, g, b = GetTextAccent(); return r, g, b, 1 end,
        borderColor = function() local r, g, b = GetSkinColors(); return r, g, b, 1 end,
        bgColor = function() local _, _, _, _, bgr, bgg, bgb, bga = GetSkinColors(); return bgr, bgg, bgb, bga end,
        insetPixels = 2,
    })
    closeButtons[button] = true
end

-- Thumb colour is the shared scrollThumb role; never the skin bar colour.
function CharacterChrome.StyleScrollbar(scrollBar)
    if not scrollBar then return end
    SkinBase.SkinTrimScrollBar(scrollBar)
end

-- Shared scroll contract for QUI-owned ScrollFrames in the Character window:
-- eased wheel (step 30) + the thin proportional scrollbar. Returns
-- { controller, bar }.
function CharacterChrome.AttachScroll(scrollFrame, opts)
    if not scrollFrame then return nil end
    opts = opts or {}
    local controller = UIKit.AttachSmoothScroll(scrollFrame, {
        step = opts.step or CONFIG.SCROLL_STEP,
        getRange = opts.getRange,
        onPosition = opts.onPosition,
    })
    local bar = UIKit.CreateScrollBar(scrollFrame, {
        parent = opts.parent,
        anchor = opts.anchor,
        offsetX = opts.offsetX or 0,
        insetTop = opts.insetTop or 0,
        insetBottom = opts.insetBottom or 0,
        getRange = opts.getRange,
        frameLevel = opts.frameLevel,
    })
    return { controller = controller, bar = bar }
end

---------------------------------------------------------------------------
-- Popouts (equipment manager / titles side panels)
---------------------------------------------------------------------------
local popouts = Helpers.CreateStateTable()

local function ApplyPopoutChrome(popup)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    SkinBase.ApplyPixelBackdrop(popup, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    if popup.title then
        CJKFont(popup.title, GeneralFontFace(), 14, "")
        popup.title:SetTextColor(GetTextAccent())
    end
    if popup.closeButton then
        CharacterChrome.StyleCloseButton(popup.closeButton)
    end
end

-- opts: name (global name), width, height, parent, point {p, rel, rp, x, y},
-- close (default true). No Blizzard dialog textures are ever applied.
function CharacterChrome.CreatePopout(title, opts)
    opts = opts or {}
    local popup = CreateFrame("Frame", opts.name, opts.parent or UIParent, "BackdropTemplate")
    popup:SetSize(opts.width or CONFIG.POPOUT_WIDTH, opts.height or CONFIG.POPOUT_HEIGHT)
    if opts.point then
        popup:SetPoint(opts.point[1], opts.point[2], opts.point[3], opts.point[4] or 0, opts.point[5] or 0)
    elseif CharacterFrame then
        popup:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", CONFIG.PANEL_WIDTH_EXTENSION + CONFIG.POPOUT_GAP, 0)
    end
    popup:SetFrameStrata("DIALOG")
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:Hide()

    local titleText = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    titleText:SetPoint("TOP", popup, "TOP", 0, -12)
    titleText:SetText(title or "")
    popup.title = titleText

    if opts.close ~= false then
        local close = CreateFrame("Button", nil, popup)
        close:SetSize(20, 20)
        close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() popup:Hide() end)
        popup.closeButton = close
    end

    ApplyPopoutChrome(popup)
    popouts[popup] = true
    if opts.name then _G[opts.name] = popup end
    return popup
end

function CharacterChrome.RefreshPopout(popup)
    if not popup then return end
    if not popouts[popup] then popouts[popup] = true end
    ApplyPopoutChrome(popup)
end

function CharacterChrome.IsPopout(popup)
    return popup ~= nil and popouts[popup] == true
end

---------------------------------------------------------------------------
-- Settings flyout (one builder, two instances: Character and Inspect)
---------------------------------------------------------------------------
local flyouts = Helpers.CreateStateTable()

local function ApplyFlyoutGlow(glow)
    local gr, gg, gb = GetTextAccent()
    local ok = false
    if glow.SetGradient and CreateColor then
        ok = ns.SafeCall("best-effort-style", function()
            glow:SetGradient("HORIZONTAL", CreateColor(gr, gg, gb, 0.06), CreateColor(gr, gg, gb, 0))
        end)
    end
    if not ok then
        glow:SetColorTexture(gr, gg, gb, 0.04)
    end
end

local function ApplyFlyoutChrome(flyout)
    local sr, sg, sb, _, bgr, bgg, bgb = GetSkinColors()
    SkinBase.ApplyChromeBackdrop(flyout.panel, {
        withBackground = true,
        borderColor = { sr, sg, sb, 1 },
        bgColor = { bgr, bgg, bgb, 0.97 },
    })
    SkinBase.ApplyChromeBackdrop(flyout.trigger, {
        withBackground = true,
        borderColor = { sr, sg, sb, 1 },
        bgColor = { bgr, bgg, bgb, 0.9 },
    })
    if flyout.title then
        flyout.title:SetTextColor(GetTextAccent())
    end
    if flyout.glow then ApplyFlyoutGlow(flyout.glow) end
    if flyout.closeButton then CharacterChrome.StyleCloseButton(flyout.closeButton) end
    if flyout.scroll and flyout.scroll.bar then flyout.scroll.bar:Retint() end
end

local function SetPixelSize(frame, width, height)
    local core = ns.Addon
    if core and core.SetPixelPerfectSize then
        core:SetPixelPerfectSize(frame, width, height)
    else
        frame:SetSize(width, height)
    end
end

-- opts: title, provider(ctx) -> final y (content bottom, negative), name
-- (panel global name), triggerName, triggerPoint {p, rel, rp, x, y},
-- extension (how far the owner's shell reaches past the parent's right edge).
-- Trigger width, flyout offset and scrolling all come from here so the two
-- instances cannot drift apart again.
function CharacterChrome.CreateSettingsFlyout(parent, opts)
    if not parent then return nil end
    opts = opts or {}
    local flyout = { parent = parent, built = false }

    local gearBtn = CreateFrame("Button", opts.triggerName, parent, "BackdropTemplate")
    SetPixelSize(gearBtn, opts.triggerWidth or CONFIG.TRIGGER_WIDTH, CONFIG.TRIGGER_HEIGHT)
    local tp = opts.triggerPoint
    if tp then
        gearBtn:SetPoint(tp[1], tp[2] or parent, tp[3] or tp[1], tp[4] or 0, tp[5] or 0)
    else
        gearBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 6, -6)
    end
    gearBtn:SetFrameStrata("HIGH")
    gearBtn:SetFrameLevel(100)
    flyout.trigger = gearBtn

    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetSize(14, 14)
    gearIcon:SetPoint("LEFT", gearBtn, "LEFT", 5, 0)
    gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")

    local gearLabel = gearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gearLabel:SetPoint("LEFT", gearIcon, "RIGHT", 4, 0)
    gearLabel:SetPoint("RIGHT", gearBtn, "RIGHT", -6, 0)
    gearLabel:SetJustifyH("LEFT")
    CJKFont(gearLabel, GeneralFontFace(), 12, "")
    gearLabel:SetText(ns.L and ns.L["Settings"] or "Settings")
    local idle = Token("tabHover")
    gearLabel:SetTextColor(idle[1], idle[2], idle[3], idle[4] or 0.85)
    flyout.triggerLabel = gearLabel

    gearBtn:SetScript("OnEnter", function(self)
        local r, g, b = GetTextAccent()
        SkinBase.SetBackdropColors(self, { r, g, b, 1 })
        local hover = Token("tabSelectedText")
        gearLabel:SetTextColor(hover[1], hover[2], hover[3], hover[4] or 1)
    end)
    gearBtn:SetScript("OnLeave", function(self)
        local r, g, b = GetSkinColors()
        SkinBase.SetBackdropColors(self, { r, g, b, 1 })
        local rest = Token("tabHover")
        gearLabel:SetTextColor(rest[1], rest[2], rest[3], rest[4] or 0.85)
    end)

    local panel = CreateFrame("Frame", opts.name, parent, "BackdropTemplate")
    panel:SetSize(CONFIG.FLYOUT_WIDTH, CONFIG.FLYOUT_HEIGHT)
    panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", (opts.extension or 0) + CONFIG.FLYOUT_GAP, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(200)
    panel:EnableMouse(true)
    panel:Hide()
    flyout.panel = panel

    local contentBg = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    SkinBase.SetInsetPixelPoints(contentBg, panel, 1)
    local bgContent = Token("bgContent")
    contentBg:SetColorTexture(bgContent[1], bgContent[2], bgContent[3], bgContent[4] or 0.02)
    UIKit.DisablePixelSnap(contentBg)

    local glow = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    SkinBase.SetInsetPixelPoints(glow, panel, 1)
    glow:SetTexture("Interface\\BUTTONS\\WHITE8x8")
    flyout.glow = glow
    panel:HookScript("OnShow", function() ApplyFlyoutGlow(glow) end)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", panel, "TOP", 0, -8)
    CJKFont(title, GeneralFontFace(), 14, "")
    title:SetText(opts.title or "")
    flyout.title = title

    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    flyout.closeButton = closeBtn

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONFIG.FLYOUT_GUTTER, 40)
    flyout.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(CONFIG.FLYOUT_WIDTH - 5 - CONFIG.FLYOUT_GUTTER - 2)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    flyout.scrollChild = scrollChild

    flyout.scroll = CharacterChrome.AttachScroll(scrollFrame, {
        parent = panel,
        anchor = scrollFrame,
        offsetX = 6,
    })

    ApplyFlyoutChrome(flyout)

    local PAD, FORM_ROW = 8, 28
    local rowIdx = 0
    local ctx = {
        panel = panel,
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        PAD = PAD,
        FORM_ROW = FORM_ROW,
        y = -5,
    }
    function ctx.ResetRows() rowIdx = 0 end
    function ctx.PlaceRow(widget, currentY)
        widget:SetPoint("TOPLEFT", PAD, currentY)
        widget:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        rowIdx = rowIdx + 1
        if (rowIdx % 2) == 0 then
            local rowBg = scrollChild:CreateTexture(nil, "BACKGROUND")
            rowBg:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, currentY)
            rowBg:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
            rowBg:SetHeight(FORM_ROW)
            local c = Token("bgContent")
            rowBg:SetColorTexture(c[1], c[2], c[3], c[4] or 0.02)
            UIKit.DisablePixelSnap(rowBg)
        end
        return currentY - FORM_ROW
    end
    function ctx.HookShow(fn) panel:HookScript("OnShow", fn) end
    function ctx.Hide() panel:Hide() end
    function ctx.Show() panel:Show() end
    function ctx.Reopen()
        panel:Hide()
        C_Timer.After(0, function() panel:Show() end)
    end
    flyout.ctx = ctx

    function flyout.Build()
        if flyout.built then return true end
        local GUI = _G.QUI and _G.QUI.GUI
        if GUI and type(GUI.EnsureWidgetAPI) == "function" then
            GUI = GUI:EnsureWidgetAPI()
        end
        if not (GUI and type(GUI.HasWidgetAPI) == "function" and GUI:HasWidgetAPI()) then
            return false
        end
        flyout.built = true
        ctx.GUI = GUI
        local finalY = ctx.y
        if type(opts.provider) == "function" then
            finalY = opts.provider(ctx) or finalY
        end
        scrollChild:SetHeight(math.abs(finalY) + 20)
        if flyout.scroll and flyout.scroll.bar then flyout.scroll.bar:Update() end
        return true
    end

    function flyout.Toggle()
        if panel:IsShown() then
            panel:Hide()
            return
        end
        flyout.Build()
        panel:Show()
    end

    function flyout.RefreshTheme()
        ApplyFlyoutChrome(flyout)
    end

    gearBtn:SetScript("OnClick", flyout.Toggle)
    if parent.HookScript then
        parent:HookScript("OnHide", function() panel:Hide() end)
    end

    flyouts[flyout] = true
    return flyout
end

---------------------------------------------------------------------------
-- Half-skinned mode (skin on, enhancement off): chrome-only slots
---------------------------------------------------------------------------
local SLOT_NAMES = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
    "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
    "CharacterTabardSlot", "CharacterWristSlot", "CharacterHandsSlot",
    "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
}

local slotBorders = Helpers.CreateStateTable()
local slotRingHooked = Helpers.CreateStateTable()
local halfSkinDecor = {
    "PaperDollInnerBorderBottom", "PaperDollInnerBorderBottom2",
    "PaperDollInnerBorderBottomLeft", "PaperDollInnerBorderBottomRight",
    "PaperDollInnerBorderLeft", "PaperDollInnerBorderRight",
    "PaperDollInnerBorderTop", "PaperDollInnerBorderTopLeft",
    "PaperDollInnerBorderTopRight",
}

local function EnsureSlotBorder(slot)
    local border = slotBorders[slot]
    local sr, sg, sb = GetSkinColors()
    if not border then
        border = CreateFrame("Frame", nil, slot, "BackdropTemplate")
        border:SetFrameLevel(slot:GetFrameLevel() + 10)
        SkinBase.SetExpandedPixelPoints(border, slot, 1)
        slotBorders[slot] = border
    end
    SkinBase.ApplyPixelBackdrop(border, 1, false, false, { sr, sg, sb, 1 })
    border:Show()
    return border
end

function CharacterChrome.GetSlotBorder(slot)
    return slot and slotBorders[slot] or nil
end

local function HideSlotRing(slotName)
    local ring = _G[slotName .. "Frame"]
    if not ring then return end
    ring:Hide()
    if not slotRingHooked[ring] then
        hooksecurefunc(ring, "Show", function(self)
            if CharacterChrome.GetOwnership().halfSkinned then self:Hide() end
        end)
        slotRingHooked[ring] = true
    end
end

ApplyHalfSkinnedChrome = function()
    if not CharacterChrome.GetOwnership().halfSkinned then return end
    for _, slotName in ipairs(SLOT_NAMES) do
        local slot = _G[slotName]
        if slot then
            EnsureSlotBorder(slot)
            HideSlotRing(slotName)
            local icon = slot.icon or slot.Icon
            if icon and icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end
    end
    for _, name in ipairs(halfSkinDecor) do
        local tex = _G[name]
        if tex then tex:Hide() end
    end
    if PaperDollSidebarTabs then
        if PaperDollSidebarTabs.DecorLeft then PaperDollSidebarTabs.DecorLeft:Hide() end
        if PaperDollSidebarTabs.DecorRight then PaperDollSidebarTabs.DecorRight:Hide() end
    end
    if CharacterFrame and CharacterFrame.CloseButton then
        CharacterChrome.StyleCloseButton(CharacterFrame.CloseButton)
    end
    ApplyNativeStatsPaneChrome()
end
CharacterChrome.ApplyHalfSkinnedChrome = ApplyHalfSkinnedChrome

---------------------------------------------------------------------------
-- EquipmentFlyout (chrome only: backdrop, slot borders, navigation)
---------------------------------------------------------------------------
local flyoutButtonBorders = Helpers.CreateStateTable()

local function SkinEquipmentFlyoutButton(button)
    if not button then return end
    local sr, sg, sb = GetSkinColors()
    local border = flyoutButtonBorders[button]
    if not border then
        local normal = button.GetNormalTexture and button:GetNormalTexture()
        if normal then normal:SetAlpha(0) end
        local icon = button.icon or button.Icon
        if icon and icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        border = CreateFrame("Frame", nil, button, "BackdropTemplate")
        border:SetFrameLevel(button:GetFrameLevel() + 2)
        SkinBase.SetExpandedPixelPoints(border, button, 1)
        flyoutButtonBorders[button] = border
    end
    SkinBase.ApplyPixelBackdrop(border, 1, false, false, { sr, sg, sb, 1 })
end

local function HideFlyoutBackgrounds(buttonFrame)
    if not buttonFrame then return end
    local count = tonumber(buttonFrame.numBGs) or 0
    for i = 1, math.max(count, 1) do
        local tex = buttonFrame["bg" .. i]
        if tex then tex:SetAlpha(0) end
    end
end

local function RefreshEquipmentFlyoutChrome()
    local flyout = _G.EquipmentFlyoutFrame
    if not flyout or not SkinBase.GetFrameData(flyout, "qCharChromeFlyout") then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    if flyout.buttonFrame then
        SkinBase.CreateBackdrop(flyout.buttonFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        HideFlyoutBackgrounds(flyout.buttonFrame)
    end
    if flyout.NavigationFrame then
        SkinBase.CreateBackdrop(flyout.NavigationFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if type(flyout.buttons) == "table" then
        for _, button in ipairs(flyout.buttons) do
            SkinEquipmentFlyoutButton(button)
        end
    end
end

local function SkinEquipmentFlyout()
    local flyout = _G.EquipmentFlyoutFrame
    if not flyout or SkinBase.GetFrameData(flyout, "qCharChromeFlyout") then return end
    SkinBase.SetFrameData(flyout, "qCharChromeFlyout", true)

    local buttonFrame = flyout.buttonFrame
    if buttonFrame and buttonFrame.HookScript then
        buttonFrame:HookScript("OnShow", function()
            if not CharacterChrome.GetOwnership().skin then return end
            RefreshEquipmentFlyoutChrome()
        end)
    end
    local nav = flyout.NavigationFrame
    if nav then
        if nav.BottomBackground then nav.BottomBackground:SetAlpha(0) end
        if nav.PrevButton and SkinBase.SkinNextPrevButton then SkinBase.SkinNextPrevButton(nav.PrevButton, "prev") end
        if nav.NextButton and SkinBase.SkinNextPrevButton then SkinBase.SkinNextPrevButton(nav.NextButton, "next") end
        SkinBase.ApplyButtonFontObjectsDeep(nav, 1)
    end
    RefreshEquipmentFlyoutChrome()
end

---------------------------------------------------------------------------
-- Theme refresh + lifecycle
---------------------------------------------------------------------------
function CharacterChrome.RefreshTheme()
    local ownership = CharacterChrome.GetOwnership()
    if ownership.shell ~= "none" and shell then ApplyShellColors() end
    if ownership.tabs then CharacterChrome.StyleTabs() end
    if ownership.close and CharacterFrame and CharacterFrame.CloseButton then
        CharacterChrome.StyleCloseButton(CharacterFrame.CloseButton)
    end
    for button in pairs(closeButtons) do
        if button ~= (CharacterFrame and CharacterFrame.CloseButton) then
            CharacterChrome.StyleCloseButton(button)
        end
    end
    for popup in pairs(popouts) do ApplyPopoutChrome(popup) end
    for flyout in pairs(flyouts) do ApplyFlyoutChrome(flyout) end
    if ownership.halfSkinned then ApplyHalfSkinnedChrome() end
    if ownership.skin then RefreshEquipmentFlyoutChrome() end
end

local initialized = false

-- Two-phase apply: everything cheap happens here at login while the window is
-- hidden (shell, tabs, close, half-skin borders, sub-surface hooks). OnShow
-- only re-anchors the shell so ScrollBox data render is never blocked.
function CharacterChrome.Initialize()
    if initialized or not CharacterFrame then return initialized end
    local ownership = CharacterChrome.GetOwnership()
    if ownership.shell == "none" and not ownership.tabs then return false end
    initialized = true

    if ownership.shell == "skin" then
        CharacterChrome.EnsureShell({ extended = false })
    end
    CharacterChrome.StyleTabs()
    if ownership.close and CharacterFrame.CloseButton then
        CharacterChrome.StyleCloseButton(CharacterFrame.CloseButton)
    end
    if ownership.halfSkinned then ApplyHalfSkinnedChrome() end
    if ownership.skin then SkinEquipmentFlyout() end

    if ownership.shell == "skin" then
        local function HugFrame()
            if CharacterChrome.OwnsShell() then CharacterChrome.SetExtended(false) end
        end
        if ReputationFrame and ReputationFrame.HookScript then
            ReputationFrame:HookScript("OnShow", HugFrame)
        end
        if TokenFrame and TokenFrame.HookScript then
            TokenFrame:HookScript("OnShow", HugFrame)
        end
        if PaperDollFrame and PaperDollFrame.HookScript then
            PaperDollFrame:HookScript("OnShow", function()
                if CharacterChrome.OwnsShell() and not CharacterChrome.GetOwnership().enhancement then
                    CharacterChrome.SetExtended(false)
                end
            end)
        end
        CharacterFrame:HookScript("OnShow", function()
            C_Timer.After(0, function()
                if not CharacterChrome.OwnsShell() then return end
                if not (PaperDollFrame and PaperDollFrame:IsShown()) then
                    CharacterChrome.SetExtended(false)
                end
            end)
        end)
    end
    return true
end

function CharacterChrome.IsInitialized()
    return initialized
end

do
    local gui = _G.QUI and _G.QUI.GUI
    if gui and type(gui.OnAccentChanged) == "function" then
        gui:OnAccentChanged(function() CharacterChrome.RefreshTheme() end)
    end
end

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        CharacterChrome.Initialize()
    end)
end
