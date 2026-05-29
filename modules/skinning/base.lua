---------------------------------------------------------------------------
-- QUI Skinning Base
-- Shared utilities for all skinning modules.
-- Loaded first via skinning.xml so all skinning files can reference ns.SkinBase.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local SkinBase = {}
ns.SkinBase = SkinBase

-- Weak-keyed table to store backdrop references WITHOUT writing to Blizzard frames
-- All code that previously used frame.quiBackdrop should use SkinBase.GetBackdrop(frame) instead
local frameBackdrops = Helpers.CreateStateTable()
local manualBackdropData = Helpers.CreateStateTable()
local expandedPointData = Helpers.CreateStateTable()
local insetPointData = Helpers.CreateStateTable()
local customInsetPointData = Helpers.CreateStateTable()
local pixelPointData = Helpers.CreateStateTable()
local pixelBackdropData = Helpers.CreateStateTable()
local DEFAULT_BACKDROP_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Shared color deltas for widget skinning (single source of truth — replaces
-- the magic numbers previously copy-pasted across frame skin files).
local BG_BOOST_BUTTON = 0.07
local BG_BOOST_ROW = 0.03
local HOVER_BRIGHTEN = 1.3

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

local function RefreshExpandedPixelPoints(region)
    local data = expandedPointData[region]
    if not data or not data.relativeTo then return end
    local offset = (data.pixels or 1) * SkinBase.GetPixelSize(region, 1)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", data.relativeTo, "TOPLEFT", -offset, offset)
    region:SetPoint("BOTTOMRIGHT", data.relativeTo, "BOTTOMRIGHT", offset, -offset)
end

function SkinBase.SetExpandedPixelPoints(region, relativeTo, pixels)
    if not region or not relativeTo then return end
    local data = expandedPointData[region]
    if not data then
        data = {}
        expandedPointData[region] = data
    end
    data.relativeTo = relativeTo
    data.pixels = pixels or 1
    RefreshExpandedPixelPoints(region)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(region, "skinningExpandedPixelPoints", RefreshExpandedPixelPoints)
        data.registered = true
    end
end

local function RefreshInsetPixelPoints(region)
    local data = insetPointData[region]
    if not data or not data.relativeTo then return end
    local inset = (data.pixels or 1) * SkinBase.GetPixelSize(region, 1)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", data.relativeTo, "TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", data.relativeTo, "BOTTOMRIGHT", -inset, inset)
end

function SkinBase.SetInsetPixelPoints(region, relativeTo, pixels)
    if not region or not relativeTo then return end
    local data = insetPointData[region]
    if not data then
        data = {}
        insetPointData[region] = data
    end
    data.relativeTo = relativeTo
    data.pixels = pixels or 1
    RefreshInsetPixelPoints(region)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(region, "skinningInsetPixelPoints", RefreshInsetPixelPoints)
        data.registered = true
    end
end

local function RefreshCustomInsetPixelPoints(region)
    local data = customInsetPointData[region]
    if not data or not data.relativeTo then return end
    local px = SkinBase.GetPixelSize(region, 1)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", data.relativeTo, "TOPLEFT", (data.left or 0) * px, -(data.top or 0) * px)
    region:SetPoint("BOTTOMRIGHT", data.relativeTo, "BOTTOMRIGHT", -(data.right or 0) * px, (data.bottom or 0) * px)
end

function SkinBase.SetPixelInsetPoints(region, relativeTo, left, top, right, bottom)
    if not region or not relativeTo then return end
    local data = customInsetPointData[region]
    if not data then
        data = {}
        customInsetPointData[region] = data
    end
    data.relativeTo = relativeTo
    data.left = left or 0
    data.top = top or 0
    data.right = right or 0
    data.bottom = bottom or 0
    RefreshCustomInsetPixelPoints(region)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(region, "skinningPixelInsetPoints", RefreshCustomInsetPixelPoints)
        data.registered = true
    end
end

local function RefreshPixelPoint(region)
    local data = pixelPointData[region]
    if not data then return end
    local px = SkinBase.GetPixelSize(region, 1)
    region:ClearAllPoints()
    region:SetPoint(
        data.point,
        data.relativeTo,
        data.relativePoint,
        (data.xPixels or 0) * px,
        (data.yPixels or 0) * px
    )
end

function SkinBase.SetPixelPoint(region, point, relativeTo, relativePoint, xPixels, yPixels)
    if not region or not point then return end
    local data = pixelPointData[region]
    if not data then
        data = {}
        pixelPointData[region] = data
    end
    data.point = point
    data.relativeTo = relativeTo
    data.relativePoint = relativePoint
    data.xPixels = xPixels or 0
    data.yPixels = yPixels or 0
    RefreshPixelPoint(region)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(region, "skinningPixelPoint", RefreshPixelPoint)
        data.registered = true
    end
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

local function SetTextureSource(texture, file)
    if not texture then return end
    if file == DEFAULT_BACKDROP_TEXTURE and texture.SetColorTexture then
        return
    end
    texture:SetTexture(file)
end

local function SetTextureColor(texture, file, r, g, b, a)
    if texture then
        local colorA = a == nil and 1 or a
        if file == DEFAULT_BACKDROP_TEXTURE and texture.SetColorTexture then
            texture:SetColorTexture(r or 1, g or 1, b or 1, colorA)
        else
            texture:SetVertexColor(r or 1, g or 1, b or 1, colorA)
        end
    end
end

local function ManualSetBackdropColor(self, r, g, b, a)
    self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA = r, g, b, a
    local data = manualBackdropData[self]
    if data then
        SetTextureColor(data.bg, data.bgFile, r, g, b, a)
    end
end

local function ManualSetBackdropBorderColor(self, r, g, b, a)
    self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA = r, g, b, a
    local data = manualBackdropData[self]
    if data then
        SetTextureColor(data.top, data.edgeFile, r, g, b, a)
        SetTextureColor(data.bottom, data.edgeFile, r, g, b, a)
        SetTextureColor(data.left, data.edgeFile, r, g, b, a)
        SetTextureColor(data.right, data.edgeFile, r, g, b, a)
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
        SetTextureSource(texture, edgeFile)
        texture:Show()
    else
        texture:Hide()
    end
end

function SkinBase.ApplyTextureBackdrop(frame, bgFile, edgeFile, edgeSize, borderColor, bgColor, bgInset)
    if not frame then return false end

    local data = EnsureManualBackdrop(frame)
    local px = Helpers.SafeToNumber(edgeSize, 1)
    if px < 0 then px = 0 end
    local inset = bgInset
    if inset == nil then inset = px end

    if bgFile ~= false then
        bgFile = bgFile or DEFAULT_BACKDROP_TEXTURE
    end
    if edgeFile ~= false then
        edgeFile = edgeFile or DEFAULT_BACKDROP_TEXTURE
    end
    data.bgFile = bgFile
    data.edgeFile = edgeFile

    data.bg:ClearAllPoints()
    if bgFile then
        SetTextureSource(data.bg, bgFile)
        data.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        data.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
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

local function RefreshPixelBackdrop(frame)
    local data = pixelBackdropData[frame]
    if not data then return end

    local edgeSize = (data.borderPixels or 1) * SkinBase.GetPixelSize(frame, 1)
    local bgInset = 0
    if data.withInsets then
        local insetPixels = data.insetPixels
        if insetPixels == nil then
            insetPixels = data.borderPixels or 1
        end
        bgInset = insetPixels * SkinBase.GetPixelSize(frame, 1)
    end
    local backdropInfo = {
        edgeFile = data.edgeFile or DEFAULT_BACKDROP_TEXTURE,
        edgeSize = edgeSize,
    }

    if data.withBackground then
        backdropInfo.bgFile = data.bgFile or DEFAULT_BACKDROP_TEXTURE
        if data.withInsets then
            backdropInfo.insets = { left = bgInset, right = bgInset, top = bgInset, bottom = bgInset }
        end
    end

    local bgColor = data.bgColor
    if not bgColor and frame._quiBgR ~= nil then
        bgColor = { frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA }
    end
    local borderColor = data.borderColor
    if not borderColor and frame._quiBorderR ~= nil then
        borderColor = { frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA }
    end

    if frame.SetBackdrop and frame.SetBackdropColor and frame.SetBackdropBorderColor then
        ApplySafeBackdrop(frame, backdropInfo, borderColor, bgColor)
    else
        local bgFile = data.withBackground and (data.bgFile or DEFAULT_BACKDROP_TEXTURE) or false
        local edgeFile = edgeSize > 0 and (data.edgeFile or DEFAULT_BACKDROP_TEXTURE) or false
        SkinBase.ApplyTextureBackdrop(frame, bgFile, edgeFile, edgeSize, borderColor, bgColor, bgInset)
    end
end

function SkinBase.ApplyPixelBackdrop(frame, borderPixels, withBackground, withInsets, borderColor, bgColor, bgFile, edgeFile, insetPixels)
    if not frame then return end
    local data = pixelBackdropData[frame]
    if not data then
        data = {}
        pixelBackdropData[frame] = data
    end

    data.borderPixels = borderPixels or 1
    data.withBackground = withBackground and true or false
    data.withInsets = withInsets and true or false
    data.borderColor = borderColor
    data.bgColor = bgColor
    data.bgFile = bgFile
    data.edgeFile = edgeFile
    data.insetPixels = insetPixels

    RefreshPixelBackdrop(frame)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(frame, "skinningPixelBackdrop", RefreshPixelBackdrop)
        data.registered = true
    end
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
    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true, {
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
    SkinBase.ApplyPixelBackdrop(frame, 1, true, true, {
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
-- SkinTab(tab, owner, opts)       — skin one tab; opts.hover wires a
--                                    brighten-on-enter + selected-state
--                                    restore-on-leave (used for pooled tabs).
-- SkinTabGroup(tabs, owner, opts) — skin every tab + hook each OnClick to
--                                    refresh the group; also registers the
--                                    owner for programmatic-switch refresh
--                                    (PanelTemplates_SetTab / TabSystem:SetTab).
--                                    opts.hover applies SkinTab hover to all.
-- RefreshTabGroup(tabs, owner)    — theme refresh: re-store colors then
--                                    re-apply selected/unselected visuals.
--
-- For owner detection (IsTabSelected): tab.IsSelected is checked first, then
-- owner.TabSystem:GetSelectedTab() vs tab.tabID, then
-- PanelTemplates_GetSelectedTab(owner) vs tab:GetID(), then a
-- tab.SelectedTexture:IsShown() fallback. Owner can be nil if only the
-- IsSelected path applies.
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

-- Re-apply the global QUI font to a tab's label when the tab opted in via
-- opts.font. Blizzard re-applies a font OBJECT (face + color) on every
-- selection change, so this runs from RefreshTabSelected as well as on skin.
local function ReapplyTabFont(tab)
    if not SkinBase.GetFrameData(tab, "skinTabFont") then return end
    local fs = tab.Text or (tab.GetFontString and tab:GetFontString())
    SkinBase.SkinFontString(fs)
end

function SkinBase.SkinTabButton(tab, opts)
    if not tab or SkinBase.IsStyled(tab) then return end
    opts = opts or {}

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
        SkinBase.SetPixelInsetPoints(bd, tab, 3, 3, 3, 0)
        -- Keep backdrop at the tab's own frame level so it renders behind
        -- the tab's ButtonText fontstring. (NukeTexture above already
        -- triple-strikes the Blizzard textures so we don't need to raise
        -- the backdrop above them.)
    end

    -- Tab text: by default leave it to Blizzard, which swaps font objects
    -- between GameFontNormalSmall (yellow/unselected) and GameFontHighlightSmall
    -- (white/selected) via PanelTemplates_SelectTab. Most QUI frames (e.g. the
    -- character pane) intentionally keep that. opts.font opts a caller in to the
    -- global QUI font + themed text instead; because Blizzard re-swaps the font
    -- object on selection change, RefreshTabSelected re-applies it (the backdrop
    -- still signals which tab is selected).
    if opts.font then
        SkinBase.SetFrameData(tab, "skinTabFont", true)
        ReapplyTabFont(tab)
    end

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor",   { bgr, bgg, bgb })
    SkinBase.MarkStyled(tab)
end

local function IsTabSelected(tab, owner)
    if tab.IsSelected and tab:IsSelected() then return true end
    if owner then
        local tabSystem = owner.TabSystem
        if tabSystem and tabSystem.GetSelectedTab and tab.tabID then
            if tab.tabID == tabSystem:GetSelectedTab() then return true end
        end
        if PanelTemplates_GetSelectedTab and tab.GetID then
            local selected = PanelTemplates_GetSelectedTab(owner)
            if selected and tab:GetID() == selected then return true end
        end
    end
    if tab.SelectedTexture and tab.SelectedTexture.IsShown and tab.SelectedTexture:IsShown() then
        return true
    end
    return false
end

function SkinBase.RefreshTabSelected(tab, owner)
    -- Re-assert the QUI font first (Blizzard's selected/unselected font-object
    -- swap would otherwise revert opted-in tabs on every tab change).
    ReapplyTabFont(tab)

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
end

-- Tab hover: brighten border on enter, restore selected-state coloring on
-- leave. The enter half mirrors the widget HoverEnter (defined later in the
-- file), but tabs need a selected-state-aware leave (RefreshTabSelected) rather
-- than the plain border reset, so this pair lives here as its own small unit.
local function TabHoverEnter(self)
    local bd = SkinBase.GetBackdrop(self)
    local sc = SkinBase.GetFrameData(self, "skinColor")
    if bd and sc then
        bd:SetBackdropBorderColor(
            math.min(sc[1] * HOVER_BRIGHTEN, 1),
            math.min(sc[2] * HOVER_BRIGHTEN, 1),
            math.min(sc[3] * HOVER_BRIGHTEN, 1),
            sc[4])
    end
end

-- Programmatic tab-switch dispatch: one global PanelTemplates_SetTab hook plus
-- a per-TabSystem SetTab hook, both dispatching to the owner's refresh closure.
local ownerTabRefreshers = Helpers.CreateStateTable()
local panelSetTabHooked = false
local function RegisterOwnerTabRefresh(owner, refreshAll)
    ownerTabRefreshers[owner] = refreshAll
    if not panelSetTabHooked and PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", function(frame)
            local fn = ownerTabRefreshers[frame]
            if fn then C_Timer.After(0, fn) end
        end)
        panelSetTabHooked = true
    end
    local tabSystem = owner.TabSystem
    if tabSystem and tabSystem.SetTab and not SkinBase.GetFrameData(tabSystem, "qTabSysHooked") then
        hooksecurefunc(tabSystem, "SetTab", function()
            C_Timer.After(0, function()
                local fn = ownerTabRefreshers[owner]
                if fn then fn() end
            end)
        end)
        SkinBase.SetFrameData(tabSystem, "qTabSysHooked", true)
    end
end

-- SkinTab(tab, owner, opts) — skin one tab; opts.hover wires brighten-on-enter
-- with selected-state restore on leave. Use directly for pooled tabs.
function SkinBase.SkinTab(tab, owner, opts)
    if not tab then return end
    opts = opts or {}
    SkinBase.SkinTabButton(tab, opts)
    if opts.hover and not SkinBase.GetFrameData(tab, "qTabHoverHooked") then
        tab:HookScript("OnEnter", TabHoverEnter)
        tab:HookScript("OnLeave", function(self) SkinBase.RefreshTabSelected(self, owner) end)
        SkinBase.SetFrameData(tab, "qTabHoverHooked", true)
    end
end

function SkinBase.SkinTabGroup(tabs, owner, opts)
    if not tabs or #tabs == 0 then return end
    opts = opts or {}

    for _, tab in ipairs(tabs) do
        SkinBase.SkinTab(tab, owner, opts)
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

    if owner then
        RegisterOwnerTabRefresh(owner, refreshAll)
    end

    refreshAll()
end

-- RefreshTabGroup(tabs, owner) — theme refresh: re-store colors from
-- GetSkinColors() then re-apply selected/unselected visuals.
function SkinBase.RefreshTabGroup(tabs, owner)
    if not tabs then return end
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    for _, tab in ipairs(tabs) do
        SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
        SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })
    end
    for _, tab in ipairs(tabs) do
        SkinBase.RefreshTabSelected(tab, owner)
    end
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
-- Generic widget hover (accent-brighten border on enter, restore on leave).
-- Reads colors from SkinBase weak state so live theme changes propagate.
---------------------------------------------------------------------------
local function HoverEnter(self)
    local bd = SkinBase.GetBackdrop(self)
    local sc = SkinBase.GetFrameData(self, "skinColor")
    if bd and sc then
        bd:SetBackdropBorderColor(
            math.min(sc[1] * HOVER_BRIGHTEN, 1),
            math.min(sc[2] * HOVER_BRIGHTEN, 1),
            math.min(sc[3] * HOVER_BRIGHTEN, 1),
            sc[4])
    end
end

local function HoverLeave(self)
    local bd = SkinBase.GetBackdrop(self)
    local sc = SkinBase.GetFrameData(self, "skinColor")
    if bd and sc then
        bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
    end
end

local function AttachHover(frame)
    if SkinBase.GetFrameData(frame, "qHoverHooked") then return end
    frame:HookScript("OnEnter", HoverEnter)
    frame:HookScript("OnLeave", HoverLeave)
    SkinBase.SetFrameData(frame, "qHoverHooked", true)
end

---------------------------------------------------------------------------
-- SkinFontString(fontString, opts)
-- Apply the global QUI font (face + outline) and a themed text color to a
-- fontstring (or an EditBox / any object exposing SetFont). This is the single
-- source of truth for "make this label use the QUI font/color", mirroring the
-- peer convention in statustracking.lua (default near-white text).
--   opts.size    : size override (default: keep the fontstring's current size)
--   opts.outline : outline override (default: Helpers.GetGeneralFontOutline())
--   opts.color   : { r, g, b, a } text color (default: near-white 0.95)
-- No-ops on nil or objects without SetFont, so callers can pass optional fields
-- directly. Idempotent in effect (re-applying the same font/color is harmless),
-- which matters for labels Blizzard re-skins on state changes.
---------------------------------------------------------------------------
function SkinBase.SkinFontString(fontString, opts)
    if not fontString or not fontString.SetFont then return end
    opts = opts or {}

    local font = (Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or STANDARD_TEXT_FONT
    local outline = opts.outline
    if outline == nil then
        outline = (Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or ""
    end

    local size = opts.size
    if not size and fontString.GetFont then
        local _, curSize = fontString:GetFont()
        size = curSize
    end
    size = size or 12

    fontString:SetFont(font, size, outline)

    if fontString.SetTextColor then
        local c = opts.color
        if type(c) == "table" then
            fontString:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            fontString:SetTextColor(0.95, 0.95, 0.95, 1)
        end
    end
end

-- Resolve a frame's primary label fontstring (button text / editbox).
local function GetLabelFontString(frame)
    if not frame then return nil end
    if frame.GetFontString then
        local fs = frame:GetFontString()
        if fs then return fs end
    end
    return frame.Text
end

---------------------------------------------------------------------------
-- SkinButton(button, opts)
--   opts.strip   : StripTextures instead of hiding named Left/Right/Middle/
--                  Center (use for WowStyle1-style buttons).
--   opts.bgBoost : background lighten amount (default BG_BOOST_BUTTON).
--   opts.hover   : attach hover hooks (default true).
---------------------------------------------------------------------------
function SkinBase.SkinButton(button, opts)
    if not button or SkinBase.IsStyled(button) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    local boost = opts.bgBoost or BG_BOOST_BUTTON

    if opts.strip then
        SkinBase.StripTextures(button)
    else
        if button.Left then button.Left:SetAlpha(0) end
        if button.Right then button.Right:SetAlpha(0) end
        if button.Middle then button.Middle:SetAlpha(0) end
        if button.Center then button.Center:SetAlpha(0) end
    end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end

    SkinBase.CreateBackdrop(button, sr, sg, sb, sa,
        math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), 1)
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(button, "skinKind", "button")
    SkinBase.SetFrameData(button, "bgBoost", boost)
    -- opt-in: restyle the label with the global QUI font (default off so the
    -- many shared SkinButton callers keep Blizzard fonts unless they ask).
    -- Flagged so RefreshWidget re-applies it on live font/theme changes.
    if opts.font then
        SkinBase.SetFrameData(button, "skinFont", true)
        SkinBase.SetFrameData(button, "skinFontColor", opts.fontColor)
        SkinBase.SkinFontString(GetLabelFontString(button), { color = opts.fontColor })
    end
    if opts.hover ~= false then AttachHover(button) end
    SkinBase.MarkStyled(button)
end

---------------------------------------------------------------------------
-- SkinEditBox(editBox) — strip Blizzard textures + QUI backdrop (no boost).
---------------------------------------------------------------------------
function SkinBase.SkinEditBox(editBox, opts)
    if not editBox or SkinBase.IsStyled(editBox) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.StripTextures(editBox)
    SkinBase.CreateBackdrop(editBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinBase.SetFrameData(editBox, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(editBox, "skinKind", "editbox")
    -- opt-in: restyle the input text with the global QUI font.
    if opts.font then
        SkinBase.SetFrameData(editBox, "skinFont", true)
        SkinBase.SetFrameData(editBox, "skinFontColor", opts.fontColor)
        SkinBase.SkinFontString(editBox, { color = opts.fontColor })
    end
    SkinBase.MarkStyled(editBox)
end

---------------------------------------------------------------------------
-- SkinScrollRow(row, opts)
--   opts.bgBoost        : default BG_BOOST_ROW
--   opts.borderAlphaMult: default 0.5
--   opts.bgAlpha        : default 0.6
--   opts.hover          : default true
---------------------------------------------------------------------------
function SkinBase.SkinScrollRow(row, opts)
    if not row or SkinBase.IsStyled(row) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    local boost = opts.bgBoost or BG_BOOST_ROW
    local borderAlphaMult = opts.borderAlphaMult or 0.5
    local bgAlpha = opts.bgAlpha or 0.6

    SkinBase.StripTextures(row)
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * borderAlphaMult,
        math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), bgAlpha)
    SkinBase.SetFrameData(row, "skinColor", { sr, sg, sb, sa * borderAlphaMult })
    SkinBase.SetFrameData(row, "skinKind", "row")
    SkinBase.SetFrameData(row, "bgBoost", boost)
    SkinBase.SetFrameData(row, "bgAlpha", bgAlpha)
    SkinBase.SetFrameData(row, "borderAlphaMult", borderAlphaMult)
    if opts.hover ~= false then AttachHover(row) end
    SkinBase.MarkStyled(row)
end

---------------------------------------------------------------------------
-- SkinDropdown(dropdown, opts)
--   opts.keepArrow     : hide NineSlice/NormalTexture/HighlightTexture but
--                        leave dropdown.Arrow visible.
--   opts.noStrip       : do NOT strip textures (preserves child controls such
--                        as a clear-filter "X").
--   opts.bgBoost       : default BG_BOOST_BUTTON.
--   opts.insetY        : inset the backdrop vertically by N px.
--   opts.belowChildren : backdrop frame level = max(0, dropdown level - 1).
--   opts.hover         : default true.
---------------------------------------------------------------------------
function SkinBase.SkinDropdown(dropdown, opts)
    if not dropdown or SkinBase.IsStyled(dropdown) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    local boost = opts.bgBoost or BG_BOOST_BUTTON

    if opts.noStrip then
        -- preserve all child textures
    elseif opts.keepArrow then
        if dropdown.NineSlice then dropdown.NineSlice:SetAlpha(0) end
        if dropdown.NormalTexture then dropdown.NormalTexture:SetAlpha(0) end
        if dropdown.HighlightTexture then dropdown.HighlightTexture:SetAlpha(0) end
    else
        SkinBase.StripTextures(dropdown)
    end

    SkinBase.CreateBackdrop(dropdown, sr, sg, sb, sa,
        math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), 1)
    local bd = SkinBase.GetBackdrop(dropdown)
    if bd then
        if opts.insetY then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", 0, -opts.insetY)
            bd:SetPoint("BOTTOMRIGHT", 0, opts.insetY)
        end
        if opts.belowChildren then
            bd:SetFrameLevel(math.max(0, dropdown:GetFrameLevel() - 1))
        end
    end
    SkinBase.SetFrameData(dropdown, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(dropdown, "bgColor", { bgr, bgg, bgb })
    SkinBase.SetFrameData(dropdown, "skinKind", "dropdown")
    SkinBase.SetFrameData(dropdown, "bgBoost", boost)
    if opts.hover ~= false then AttachHover(dropdown) end
    SkinBase.MarkStyled(dropdown)
end

---------------------------------------------------------------------------
-- SkinListContainer(list, rowStyler)
-- Hide NineSlice/Background, strip textures, hide the scrollbar background,
-- and style pooled rows via HookScrollBoxAcquired.
---------------------------------------------------------------------------
function SkinBase.SkinListContainer(list, rowStyler)
    if not list or SkinBase.IsStyled(list) then return end
    if list.NineSlice then list.NineSlice:Hide() end
    if list.BackgroundNineSlice then list.BackgroundNineSlice:Hide() end
    if list.Background and list.Background.SetAlpha then list.Background:SetAlpha(0) end
    SkinBase.StripTextures(list)
    if list.ScrollBox and rowStyler then
        SkinBase.HookScrollBoxAcquired(list.ScrollBox, rowStyler)
    end
    if list.ScrollBar and list.ScrollBar.Background then
        list.ScrollBar.Background:Hide()
    end
    SkinBase.MarkStyled(list)
end

---------------------------------------------------------------------------
-- RefreshWidget(frame) — re-derive colors from GetSkinColors() by skinKind,
-- re-apply to the QUI backdrop, and refresh stored "skinColor" so a later
-- hover uses the new colors. Handles button/dropdown/editbox/row. Tabs are
-- refreshed via RefreshTabGroup (they need owner context).
---------------------------------------------------------------------------
function SkinBase.RefreshWidget(frame)
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local kind = SkinBase.GetFrameData(frame, "skinKind")
    if not kind then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    if kind == "button" or kind == "dropdown" then
        local boost = SkinBase.GetFrameData(frame, "bgBoost") or BG_BOOST_BUTTON
        bd:SetBackdropColor(math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), 1)
        bd:SetBackdropBorderColor(sr, sg, sb, sa)
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa })
        if kind == "dropdown" then
            SkinBase.SetFrameData(frame, "bgColor", { bgr, bgg, bgb })
        end
    elseif kind == "editbox" then
        bd:SetBackdropColor(bgr, bgg, bgb, bga)
        bd:SetBackdropBorderColor(sr, sg, sb, sa)
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa })
    elseif kind == "row" then
        local boost = SkinBase.GetFrameData(frame, "bgBoost") or BG_BOOST_ROW
        local bgAlpha = SkinBase.GetFrameData(frame, "bgAlpha") or 0.6
        local mult = SkinBase.GetFrameData(frame, "borderAlphaMult") or 0.5
        bd:SetBackdropColor(math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), bgAlpha)
        bd:SetBackdropBorderColor(sr, sg, sb, sa * mult)
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa * mult })
    end

    -- Re-apply the global QUI font on live font/theme changes for widgets that
    -- opted in at skin time (SkinButton/SkinEditBox {font=true}).
    if SkinBase.GetFrameData(frame, "skinFont") then
        local color = SkinBase.GetFrameData(frame, "skinFontColor")
        local target = (kind == "editbox") and frame or GetLabelFontString(frame)
        SkinBase.SkinFontString(target, { color = color })
    end
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
