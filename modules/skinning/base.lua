---------------------------------------------------------------------------
-- QUI Skinning Base
-- Shared utilities for all skinning modules.
-- Loaded first via skinning.xml so all skinning files can reference ns.SkinBase.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local SkinBase = {}
ns.SkinBase = SkinBase

-- Weak-keyed table to store backdrop references WITHOUT writing to Blizzard frames
-- All code that previously used frame.quiBackdrop should use SkinBase.GetBackdrop(frame) instead
local frameBackdrops = Helpers.CreateStateTable()
local manualBackdropData = Helpers.CreateStateTable()
local DEFAULT_BACKDROP_TEXTURE = "Interface\\Buttons\\WHITE8x8"

---------------------------------------------------------------------------
-- GetPixelSize(frame, default)
-- Returns the pixel-perfect edge size for the given frame.
---------------------------------------------------------------------------
function SkinBase.GetPixelSize(frame, default)
    local core = Helpers.GetCore()
    if core and type(core.GetPixelSize) == "function" then
        local px = core:GetPixelSize(frame)
        if type(px) == "number" and px > 0 then
            return px
        end
    end
    return default or 1
end

---------------------------------------------------------------------------
-- GetSkinColors()
-- Returns accent + background colors: sr, sg, sb, sa, bgr, bgg, bgb, bga
---------------------------------------------------------------------------
function SkinBase.GetSkinColors(moduleSettings, prefix)
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColorWithOverride(moduleSettings, prefix)
    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

function SkinBase.GetSkinBarColor(moduleSettings, prefix)
    return Helpers.GetSkinBarColor(moduleSettings, prefix)
end

local function SetTextureColor(texture, r, g, b, a)
    if texture then
        texture:SetVertexColor(r or 1, g or 1, b or 1, a == nil and 1 or a)
    end
end

local function ManualSetBackdropColor(self, r, g, b, a)
    self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA = r, g, b, a
    local data = manualBackdropData[self]
    if data then
        SetTextureColor(data.bg, r, g, b, a)
    end
end

local function ManualSetBackdropBorderColor(self, r, g, b, a)
    self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA = r, g, b, a
    local data = manualBackdropData[self]
    if data then
        SetTextureColor(data.top, r, g, b, a)
        SetTextureColor(data.bottom, r, g, b, a)
        SetTextureColor(data.left, r, g, b, a)
        SetTextureColor(data.right, r, g, b, a)
    end
end

local function EnsureManualBackdrop(frame)
    local data = manualBackdropData[frame]
    if data then return data end

    data = {
        bg = frame:CreateTexture(nil, "BACKGROUND"),
        top = frame:CreateTexture(nil, "BORDER"),
        bottom = frame:CreateTexture(nil, "BORDER"),
        left = frame:CreateTexture(nil, "BORDER"),
        right = frame:CreateTexture(nil, "BORDER"),
    }
    manualBackdropData[frame] = data

    frame.SetBackdropColor = ManualSetBackdropColor
    frame.SetBackdropBorderColor = ManualSetBackdropBorderColor

    return data
end

local function ResetBorderTexture(texture, edgeFile, showBorder)
    texture:ClearAllPoints()
    if showBorder then
        texture:SetTexture(edgeFile)
        texture:Show()
    else
        texture:Hide()
    end
end

function SkinBase.ApplyTextureBackdrop(frame, bgFile, edgeFile, edgeSize, borderColor, bgColor)
    if not frame then return false end

    local data = EnsureManualBackdrop(frame)
    local px = Helpers.SafeToNumber(edgeSize, 1)
    if px < 0 then px = 0 end

    bgFile = bgFile or DEFAULT_BACKDROP_TEXTURE
    edgeFile = edgeFile or DEFAULT_BACKDROP_TEXTURE

    data.bg:ClearAllPoints()
    if bgFile then
        data.bg:SetTexture(bgFile)
        data.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
        data.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
        data.bg:Show()
    else
        data.bg:Hide()
    end

    local showBorder = edgeFile and px > 0
    ResetBorderTexture(data.top, edgeFile, showBorder)
    ResetBorderTexture(data.bottom, edgeFile, showBorder)
    ResetBorderTexture(data.left, edgeFile, showBorder)
    ResetBorderTexture(data.right, edgeFile, showBorder)

    if showBorder then
        data.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        data.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        data.top:SetHeight(px)

        data.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        data.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        data.bottom:SetHeight(px)

        data.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -px)
        data.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, px)
        data.left:SetWidth(px)

        data.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -px)
        data.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, px)
        data.right:SetWidth(px)
    end

    if bgColor then
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    else
        frame:SetBackdropColor(frame._quiBgR or 1, frame._quiBgG or 1, frame._quiBgB or 1, frame._quiBgA)
    end

    if borderColor then
        frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    else
        frame:SetBackdropBorderColor(frame._quiBorderR or 1, frame._quiBorderG or 1, frame._quiBorderB or 1, frame._quiBorderA)
    end

    frame:Show()
    return true
end

local function ApplySafeBackdrop(frame, backdropInfo, borderColor, bgColor)
    if not frame or not frame.SetBackdrop then return false end

    local core = Helpers.GetCore()
    local safeSetBackdrop = core and core.SafeSetBackdrop
    if type(safeSetBackdrop) == "function" then
        return safeSetBackdrop(frame, backdropInfo, borderColor, bgColor)
    end

    local ok = pcall(frame.SetBackdrop, frame, backdropInfo)
    if ok and backdropInfo then
        if borderColor then
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
        if bgColor then
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
        end
    end
    return ok
end

function SkinBase.SafeSetBackdrop(frame, backdropInfo, borderColor, bgColor)
    return ApplySafeBackdrop(frame, backdropInfo, borderColor, bgColor)
end

---------------------------------------------------------------------------
-- CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
-- Creates (or updates) a pixel-perfect QUI backdrop on the given frame.
-- Stores the backdrop in a local weak-keyed table (NOT on the frame itself)
-- to avoid tainting Blizzard frames in Midnight's taint model.
-- Use SkinBase.GetBackdrop(frame) to retrieve the backdrop.
---------------------------------------------------------------------------
function SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frameBackdrops[frame] then
        local backdrop = CreateFrame("Frame", nil, frame)
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:EnableMouse(false)
        frameBackdrops[frame] = backdrop
    end

    local backdrop = frameBackdrops[frame]
    local px = SkinBase.GetPixelSize(backdrop, 1)
    -- Store backup color fields so third-party frame cleanup recognizes this
    -- as a QUI-owned frame and skips it during orphan/NineSlice suppression.
    backdrop._quiBgR = bgr or 0.05
    backdrop._quiBgG = bgg or 0.05
    backdrop._quiBgB = bgb or 0.05
    backdrop._quiBgA = bga or 0.95
    backdrop._quiBorderR = sr or 0
    backdrop._quiBorderG = sg or 0
    backdrop._quiBorderB = sb or 0
    backdrop._quiBorderA = sa or 1
    SkinBase.ApplyTextureBackdrop(backdrop, DEFAULT_BACKDROP_TEXTURE, DEFAULT_BACKDROP_TEXTURE, px, {
        backdrop._quiBorderR, backdrop._quiBorderG, backdrop._quiBorderB, backdrop._quiBorderA,
    }, {
        backdrop._quiBgR, backdrop._quiBgG, backdrop._quiBgB, backdrop._quiBgA,
    })
end

---------------------------------------------------------------------------
-- ApplyFullBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
-- Applies a pixel-perfect backdrop directly to a BackdropTemplate frame.
-- Unlike CreateBackdrop, this sets the backdrop on the frame itself
-- (for frames that already have BackdropTemplate or are addon-owned).
---------------------------------------------------------------------------
function SkinBase.ApplyFullBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end
    local px = SkinBase.GetPixelSize(frame, 1)
    -- Store backup color fields so third-party frame cleanup recognizes this
    -- as a QUI-owned frame and skips it during orphan/NineSlice suppression.
    frame._quiBgR = bgr or 0.05
    frame._quiBgG = bgg or 0.05
    frame._quiBgB = bgb or 0.05
    frame._quiBgA = bga or 0.95
    frame._quiBorderR = sr or 0
    frame._quiBorderG = sg or 0
    frame._quiBorderB = sb or 0
    frame._quiBorderA = sa or 1
    ApplySafeBackdrop(frame, {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    }, {
        frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA,
    }, {
        frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA,
    })
end

---------------------------------------------------------------------------
-- GetBackdrop(frame)
-- Returns the QUI backdrop for a frame, or nil if none exists.
---------------------------------------------------------------------------
function SkinBase.GetBackdrop(frame)
    return frameBackdrops[frame]
end

---------------------------------------------------------------------------
-- Skinning state tracking (shared across all skinning modules)
-- Replaces frame.quiSkinned / frame.quiStyled / frame.quiBackdrop writes
-- which taint Blizzard frames in Midnight's taint model.
---------------------------------------------------------------------------
local skinnedFrames = Helpers.CreateStateTable()
local styledFrames = Helpers.CreateStateTable()

-- Mark a frame as skinned (replaces frame.quiSkinned = true)
function SkinBase.MarkSkinned(frame)
    skinnedFrames[frame] = true
end

-- Check if a frame has been skinned (replaces frame.quiSkinned check)
function SkinBase.IsSkinned(frame)
    return skinnedFrames[frame]
end

-- Mark a frame as styled (replaces frame.quiStyled = true)
function SkinBase.MarkStyled(frame)
    styledFrames[frame] = true
end

-- Check if a frame has been styled (replaces frame.quiStyled check)
function SkinBase.IsStyled(frame)
    return styledFrames[frame]
end

-- Store arbitrary per-frame data (replaces frame.quiXxx = value)
local frameData, getFrameData = Helpers.CreateStateTable()

function SkinBase.SetFrameData(frame, key, value)
    getFrameData(frame)[key] = value
end

function SkinBase.GetFrameData(frame, key)
    local data = frameData[frame]
    return data and data[key]
end

---------------------------------------------------------------------------
-- StripTextures(frame)
-- Hides all Texture regions on a frame (alpha → 0).
---------------------------------------------------------------------------
function SkinBase.StripTextures(frame)
    if not frame then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- HidePortraitFrameChrome(frame)
-- Hides every standard chrome region exposed by PortraitFrameTemplate
-- and ButtonFrameTemplate (and their NoCloseButton / Minimizable / Flat
-- variants).
--
-- Template inheritance per Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:
--   PortraitFrameBaseTemplate
--     ├── .NineSlice            (NineSlicePanelTemplate)
--     ├── .PortraitContainer    (portrait + CircleMask)
--     └── .TitleContainer       (TitleText, sometimes .TitleBg)
--   PortraitFrameTexturedBaseTemplate ← .Bg + .TopTileStreaks
--   ButtonFrameBaseTemplate           ← .Bg + .TopTileStreaks + .CloseButton
--   ButtonFrameTemplate               ← .Inset (InsetFrameTemplate)
--
-- `TopTileStreaks` is the diagonal-streak band across the top — easy to
-- miss because it draws at BORDER subLevel and only matters when the
-- other chrome is hidden. Calling this helper is the single source of
-- truth for "remove the Blizzard panel chrome on this frame".
---------------------------------------------------------------------------
function SkinBase.HidePortraitFrameChrome(frame)
    if not frame then return end

    -- PortraitFrame / ButtonFrame template regions.
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
    if frame.PortraitContainer then frame.PortraitContainer:Hide() end
    if frame.TitleContainer and frame.TitleContainer.TitleBg then
        frame.TitleContainer.TitleBg:Hide()
    end

    -- BasicFrameTemplate regions (per Blizzard_UIPanelTemplates/
    -- UIPanelTemplates.xml:550-636 — 8 corner/edge textures + TitleBg).
    -- BasicFrameTemplate is structurally distinct from PortraitFrameTemplate:
    -- no NineSlice, no TopTileStreaks. Used by GuildBank and several other
    -- secondary frames. Hiding both region sets is safe — :Hide() no-ops on
    -- missing regions and the names don't collide.
    if frame.TopLeftCorner then frame.TopLeftCorner:Hide() end
    if frame.TopRightCorner then frame.TopRightCorner:Hide() end
    if frame.BotLeftCorner then frame.BotLeftCorner:Hide() end
    if frame.BotRightCorner then frame.BotRightCorner:Hide() end
    if frame.TopBorder then frame.TopBorder:Hide() end
    if frame.BottomBorder then frame.BottomBorder:Hide() end
    if frame.LeftBorder then frame.LeftBorder:Hide() end
    if frame.RightBorder then frame.RightBorder:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end

    -- Legacy/derived names that several Blizzard frames still expose.
    if frame.Background then frame.Background:Hide() end
    if frame.portrait then frame.portrait:Hide() end

    -- ButtonFrameTemplate adds an Inset child with its own NineSlice/Bg.
    if frame.Inset then
        if frame.Inset.NineSlice then frame.Inset.NineSlice:Hide() end
        if frame.Inset.Bg then frame.Inset.Bg:Hide() end
    end
end

---------------------------------------------------------------------------
-- SkinCloseButton(closeButton)
-- Hides the Blizzard X chrome on a UIPanelCloseButton (or any of its
-- descendants: UIPanelCloseButtonDefaultAnchors, UIPanelCloseButtonNoScripts —
-- see Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:148-153) and
-- replaces it with a QUI accent backdrop + "×" label + hover hooks.
--
-- The Blizzard X graphic draws via the 4 button states
-- (Normal/Pushed/Highlight/Disabled), so hiding only .Border (a common
-- prior-art mistake — see commit ec36a542) leaves the X visible. This
-- helper hides all 5 layers.
--
-- Theme-aware: colors come from SkinBase.GetSkinColors() so live theme
-- changes propagate through OnEnter/OnLeave (which re-query on each fire).
--
-- Idempotent — flagged via SetFrameData(button, "closeStyled").
---------------------------------------------------------------------------
function SkinBase.SkinCloseButton(closeButton)
    if not closeButton or SkinBase.GetFrameData(closeButton, "closeStyled") then
        return
    end

    if closeButton.Border then closeButton.Border:SetAlpha(0) end
    if closeButton.GetNormalTexture and closeButton:GetNormalTexture() then
        closeButton:GetNormalTexture():SetAlpha(0)
    end
    if closeButton.GetPushedTexture and closeButton:GetPushedTexture() then
        closeButton:GetPushedTexture():SetAlpha(0)
    end
    if closeButton.GetHighlightTexture and closeButton:GetHighlightTexture() then
        closeButton:GetHighlightTexture():SetAlpha(0)
    end
    if closeButton.GetDisabledTexture and closeButton:GetDisabledTexture() then
        closeButton:GetDisabledTexture():SetAlpha(0)
    end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(closeButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    local label = closeButton:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    label:SetText("\195\151") -- UTF-8 "×" (U+00D7 MULTIPLICATION SIGN)
    label:SetTextColor(1, 1, 1, 1)
    SkinBase.SetFrameData(closeButton, "closeLabel", label)

    closeButton:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetBackdrop(self)
        if bd then
            local r, g, b, a = SkinBase.GetSkinColors()
            bd:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    closeButton:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetBackdrop(self)
        if bd then
            local r, g, b, a = SkinBase.GetSkinColors()
            bd:SetBackdropBorderColor(r, g, b, a)
        end
    end)

    SkinBase.SetFrameData(closeButton, "closeStyled", true)
end

---------------------------------------------------------------------------
-- Tab skinning — works for both PanelTabButtonTemplate (legacy global
-- FrameTab1..N pattern) and modern TabSystemTemplate tabs.
--
-- SkinTabButton(tab)              — visual base: strip Blizzard textures,
--                                    apply QUI backdrop with the conventional
--                                    bottom-merging tab inset, cache colors
--                                    for later RefreshTabSelected calls.
-- RefreshTabSelected(tab, owner)  — set the backdrop to selected vs
--                                    unselected colors based on tab state.
-- SkinTabGroup(tabs, owner)       — skin every tab in the list + hook each
--                                    OnClick to refresh the whole group's
--                                    selected/unselected coloring.
--
-- For owner detection: tab.IsSelected (TabSystem) is checked first, then
-- PanelTemplates_GetSelectedTab(owner) compared with tab:GetID(). Owner
-- can be nil if only the IsSelected path applies.
---------------------------------------------------------------------------
-- Belt-and-suspenders texture nuke: SetAlpha(0) + Hide() + SetTexture("").
-- Used on Blizzard tab textures because PanelTemplates_SelectTab/DeselectTab
-- (SharedUIPanelTemplates.lua:505,523) Show()/Hide() the named tab textures
-- on every tab switch — we need them gone regardless of which path Blizzard
-- runs through, and atlas-backed textures sometimes ignore the SetAlpha alone.
local function NukeTexture(t)
    if not t then return end
    if t.SetAlpha then t:SetAlpha(0) end
    if t.SetTexture then pcall(t.SetTexture, t, "") end
    if t.Hide then t:Hide() end
end

-- PanelTabButtonTemplate's twelve named texture regions
-- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:905-960).
local PANEL_TAB_TEXTURES = {
    "Left", "Middle", "Right",
    "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight",
    "LeftDisabled", "MiddleDisabled", "RightDisabled",
}

function SkinBase.SkinTabButton(tab)
    if not tab or SkinBase.IsStyled(tab) then return end

    -- Nuke each PanelTabButtonTemplate texture by name (atlas-backed; Show()
    -- by Blizzard tab-state code wouldn't otherwise affect our alpha=0).
    for _, name in ipairs(PANEL_TAB_TEXTURES) do
        NukeTexture(tab[name])
    end
    -- Catch-all for non-PanelTab variants (FriendsFrameTabTemplate, etc.)
    -- that may have differently-named regions.
    SkinBase.StripTextures(tab)
    local highlight = tab.GetHighlightTexture and tab:GetHighlightTexture()
    NukeTexture(highlight)

    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
    local bd = SkinBase.GetBackdrop(tab)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", 3, -3)
        bd:SetPoint("BOTTOMRIGHT", -3, 0)
        -- Keep backdrop at the tab's own frame level so it renders behind
        -- the tab's ButtonText fontstring. (NukeTexture above already
        -- triple-strikes the Blizzard textures so we don't need to raise
        -- the backdrop above them.)
    end

    -- Leave tab.Text untouched. Blizzard handles unselected/selected text
    -- color via PanelTemplates_SelectTab swapping font objects between
    -- GameFontNormalSmall (yellow) and GameFontHighlightSmall (white) —
    -- the character pane tabs (StyleCharacterFrameTab in frames/character.lua)
    -- intentionally don't override this and look right, so we match.

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor",   { bgr, bgg, bgb })
    SkinBase.MarkStyled(tab)
end

local function IsTabSelected(tab, owner)
    if tab.IsSelected and tab:IsSelected() then return true end
    if owner and PanelTemplates_GetSelectedTab and tab.GetID then
        local selected = PanelTemplates_GetSelectedTab(owner)
        if selected and tab:GetID() == selected then return true end
    end
    return false
end

function SkinBase.RefreshTabSelected(tab, owner)
    local bd = SkinBase.GetBackdrop(tab)
    local sc = SkinBase.GetFrameData(tab, "skinColor")
    local bg = SkinBase.GetFrameData(tab, "bgColor")
    if not bd or not sc or not bg then return end

    if IsTabSelected(tab, owner) then
        bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
        bd:SetBackdropColor(math.min(bg[1] + 0.10, 1), math.min(bg[2] + 0.10, 1), math.min(bg[3] + 0.10, 1), 1)
    else
        bd:SetBackdropBorderColor(sc[1] * 0.5, sc[2] * 0.5, sc[3] * 0.5, sc[4] * 0.6)
        bd:SetBackdropColor(bg[1], bg[2], bg[3], 0.7)
    end
    -- Text color intentionally left to Blizzard's font-object swap (see SkinTabButton).
end

function SkinBase.SkinTabGroup(tabs, owner)
    if not tabs or #tabs == 0 then return end

    for _, tab in ipairs(tabs) do
        SkinBase.SkinTabButton(tab)
    end

    local function refreshAll()
        for _, t in ipairs(tabs) do
            SkinBase.RefreshTabSelected(t, owner)
        end
    end

    for _, tab in ipairs(tabs) do
        if not SkinBase.GetFrameData(tab, "qTabSelHooked") then
            tab:HookScript("OnClick", refreshAll)
            SkinBase.SetFrameData(tab, "qTabSelHooked", true)
        end
    end

    refreshAll()
end

---------------------------------------------------------------------------
-- HookScrollBoxAcquired(scrollBox, callback)
-- Replaces the legacy `hooksecurefunc(scrollBox, "Update", …) +
-- C_Timer.After(0) + ForEachFrame` triad with the documented
-- `ScrollUtil.AddAcquiredFrameCallback` API (defined at
-- Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua:35).
--
-- The legacy pattern fires on every scroll Update — many times per second
-- during scrolling — and iterates every visible row each time. This helper
-- fires the callback exactly once per frame acquisition (first time the
-- frame is reused from the pool for a new piece of data), which is what
-- visual-only skinning needs.
--
-- TAINT SAFETY: Both the initial iterate-existing pass AND the per-
-- acquisition fire are deferred via C_Timer.After(0). The OnAcquiredFrame
-- callback fires synchronously from Blizzard's secure scroll context, and
-- creating Backdrop frames in that path can propagate taint. The defer
-- also gives Blizzard's initializer time to bind elementData to the row.
--
-- Idempotent — flagged via SetFrameData(scrollBox, "qScrollHooked").
---------------------------------------------------------------------------
function SkinBase.HookScrollBoxAcquired(scrollBox, callback)
    if not scrollBox or SkinBase.GetFrameData(scrollBox, "qScrollHooked") then return end
    if not ScrollUtil or not ScrollUtil.AddAcquiredFrameCallback then return end

    C_Timer.After(0, function()
        if scrollBox.ForEachFrame then
            pcall(scrollBox.ForEachFrame, scrollBox, callback)
        end
    end)

    ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, frame)
        C_Timer.After(0, function()
            callback(frame)
        end)
    end, scrollBox)

    SkinBase.SetFrameData(scrollBox, "qScrollHooked", true)
end

---------------------------------------------------------------------------
-- OnAddOnLoaded(addonName, callback, delay)
-- Idempotent helper for the canonical Blizzard-frame init pattern:
--   1. If addonName is already loaded, fire callback (optionally after delay).
--   2. Otherwise register ADDON_LOADED and fire on match, then unregister.
--
-- Replaces ~12 lines of boilerplate per skin file that did the same
-- ADDON_LOADED dance. Works for both LOD addons (Blizzard_MailFrame etc.)
-- and the always-loaded ones (Blizzard_UIPanels_Game), since the
-- already-loaded short-circuit fires immediately.
---------------------------------------------------------------------------
function SkinBase.OnAddOnLoaded(addonName, callback, delay)
    delay = delay or 0
    local function fire()
        if delay > 0 then
            C_Timer.After(delay, callback)
        else
            callback()
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addonName) then
        fire()
        return
    end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, name)
        if name == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            fire()
        end
    end)
end

---------------------------------------------------------------------------
-- SkinButtonFrameTemplate(frame)
-- One-call skinner for any frame that inherits PortraitFrameTemplate /
-- PortraitFrameTemplateNoCloseButton / ButtonFrameTemplate (or their
-- minimizable / flat variants). Composes the three primitive helpers:
--
--   1. HidePortraitFrameChrome — strip NineSlice, Bg, TopTileStreaks, etc.
--   2. CreateBackdrop          — apply the QUI accent backdrop using the
--                                current skin colors. Theme changes flow
--                                through because SkinBase.GetSkinColors() is
--                                queried at call time.
--   3. SkinCloseButton          — restyle frame.CloseButton if present.
--
-- This helper does NOT skin tabs, scroll regions, sub-panels, money frames,
-- or model-frame borders — those remain file-specific. It is the minimum
-- viable "make this frame look like QUI" call, intended for the ~17 daily-
-- use frames identified by the round-2 audit (Bank, Mail, Merchant,
-- GuildBank, Achievement, SpellBook, MacroFrame, ItemSocketing, etc.)
-- whose template inheritance gives them this shared chrome.
---------------------------------------------------------------------------
function SkinBase.SkinButtonFrameTemplate(frame)
    if not frame then return end
    SkinBase.HidePortraitFrameChrome(frame)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if frame.CloseButton then
        SkinBase.SkinCloseButton(frame.CloseButton)
    end
end

