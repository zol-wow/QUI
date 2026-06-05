local ADDON_NAME, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- READY CHECK FRAME SKINNING
-- QUI skinning for ReadyCheckFrame
---------------------------------------------------------------------------

local FONT_FLAGS = "OUTLINE"
local OWNED_TEXTURE_KEY = "readyCheckOwnedTexture"
local TEXTURE_BACKDROP_KEY = "readyCheckTextureBackdrop"

---------------------------------------------------------------------------
-- POSITION SAVING/LOADING
---------------------------------------------------------------------------

local function GetSettings()
    local core = GetCore()
    if core and core.db and core.db.profile and core.db.profile.general then
        return core.db.profile.general
    end
    return nil
end

-- Legacy position helpers removed — frameAnchoring system handles positioning.

---------------------------------------------------------------------------
-- HELPER FUNCTIONS
---------------------------------------------------------------------------

local function Pixel(frame)
    local UIKit = ns.UIKit
    if UIKit and UIKit.Pixels then
        return UIKit.Pixels(1, frame)
    end
    return 1
end

local function ColorTexture(texture, r, g, b, a)
    if not texture then return end
    texture:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    if ns.UIKit and ns.UIKit.DisablePixelSnap then
        ns.UIKit.DisablePixelSnap(texture)
    end
end

local function SetTextureBackdropLayout(parent, parts)
    if not parent or not parts then return end

    local px = Pixel(parent)
    parts.bg:ClearAllPoints()
    parts.bg:SetAllPoints(parent)

    parts.top:ClearAllPoints()
    parts.top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    parts.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    parts.top:SetHeight(px)

    parts.bottom:ClearAllPoints()
    parts.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    parts.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    parts.bottom:SetHeight(px)

    parts.left:ClearAllPoints()
    parts.left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    parts.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    parts.left:SetWidth(px)

    parts.right:ClearAllPoints()
    parts.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    parts.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    parts.right:SetWidth(px)
end

local function MarkOwnedTexture(texture)
    if texture then
        SkinBase.SetFrameData(texture, OWNED_TEXTURE_KEY, true)
    end
    return texture
end

local function EnsureTextureBackdrop(parent, owner)
    if not parent or not owner then return nil end

    local parts = SkinBase.GetFrameData(owner, TEXTURE_BACKDROP_KEY)
    if parts then
        SetTextureBackdropLayout(parent, parts)
        return parts
    end

    parts = {
        bg = MarkOwnedTexture(parent:CreateTexture(nil, "BACKGROUND", nil, -8)),
        top = MarkOwnedTexture(parent:CreateTexture(nil, "BORDER", nil, 7)),
        bottom = MarkOwnedTexture(parent:CreateTexture(nil, "BORDER", nil, 7)),
        left = MarkOwnedTexture(parent:CreateTexture(nil, "BORDER", nil, 7)),
        right = MarkOwnedTexture(parent:CreateTexture(nil, "BORDER", nil, 7)),
    }

    SetTextureBackdropLayout(parent, parts)
    SkinBase.SetFrameData(owner, TEXTURE_BACKDROP_KEY, parts)

    -- Re-lay out whenever the effective scale changes. The 1px edge size is in
    -- frame units, so a layout computed once at ADDON_LOADED goes sub-pixel
    -- (edges drop out) when the final UI scale lands after login. The shared
    -- backdrop paths get this via RefreshPixelBackdrop; owned textures must
    -- register for the same scale-refresh pass explicitly.
    local UIKit = ns.UIKit
    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(owner, TEXTURE_BACKDROP_KEY, function()
            SetTextureBackdropLayout(parent, parts)
        end)
    end
    return parts
end

local function ApplyTextureBackdrop(parts, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not parts then return end

    ColorTexture(parts.bg, bgr, bgg, bgb, bga)
    for _, edge in ipairs({ parts.top, parts.bottom, parts.left, parts.right }) do
        ColorTexture(edge, sr, sg, sb, sa)
    end
end

-- Re-assert the QUI font/color on a button's label.
-- Blizzard reapplies the button's font object (face + color) when the popup is
-- shown and on enable/disable; that overwrites the styling we set at skin time
-- and can leave the Ready / Not Ready label unrendered. Re-running this from the
-- button's OnShow/OnEnable/OnDisable keeps the label styled and visible — the
-- same state-refresh approach the StaticPopup skin (popups.lua) uses.
local function RestyleButtonText(button)
    local text = button and button.GetFontString and button:GetFontString()
    if not text or not text.SetFont then return end
    local font = (ns.Helpers and ns.Helpers.GetGeneralFont and ns.Helpers.GetGeneralFont()) or STANDARD_TEXT_FONT
    text:SetFont(font, 12, FONT_FLAGS)
    if text.SetDrawLayer then text:SetDrawLayer("OVERLAY", 7) end
    if text.SetTextColor then text:SetTextColor(0.9, 0.9, 0.9, 1) end
end

-- Style a button with QUI look
local function SkinButton(button, sr, sg, sb, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsSkinned(button) then return end

    -- Hide default button textures
    if button.Left then button.Left:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end
    if button.LeftSeparator then button.LeftSeparator:SetAlpha(0) end
    if button.RightSeparator then button.RightSeparator:SetAlpha(0) end

    -- Hide NineSlice if present
    if button.NineSlice then button.NineSlice:SetAlpha(0) end

    -- Strip other textures
    for _, region in ipairs({button:GetRegions()}) do
        if region:GetObjectType() == "Texture" then
            local drawLayer = region:GetDrawLayer()
            if drawLayer == "BACKGROUND" then
                region:SetAlpha(0)
            end
        end
    end

    local btnBgr = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)  -- Slightly lighter for buttons
    local btnBgg = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgb = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
    ApplyTextureBackdrop(EnsureTextureBackdrop(button, button), sr, sg, sb, 1, btnBgr, btnBgg, btnBgb, bga)

    -- Store colors for hover effects (in local weak-keyed table via SkinBase)
    SkinBase.SetFrameData(button, "normalBg", { btnBgr, btnBgg, btnBgb, bga })
    SkinBase.SetFrameData(button, "hoverBg", { math.min(btnBgr + 0.1, 1), math.min(btnBgg + 0.1, 1), math.min(btnBgb + 0.1, 1), bga })
    SkinBase.SetFrameData(button, "borderColor", { sr, sg, sb, 1 })

    -- Hover effects
    button:HookScript("OnEnter", function(self)
        local backdrop = SkinBase.GetFrameData(self, TEXTURE_BACKDROP_KEY)
        local hoverBg = SkinBase.GetFrameData(self, "hoverBg")
        local borderColor = SkinBase.GetFrameData(self, "borderColor")
        if backdrop and hoverBg and borderColor then
            ApplyTextureBackdrop(backdrop, borderColor[1], borderColor[2], borderColor[3], borderColor[4],
                hoverBg[1], hoverBg[2], hoverBg[3], hoverBg[4])
        end
    end)
    button:HookScript("OnLeave", function(self)
        local backdrop = SkinBase.GetFrameData(self, TEXTURE_BACKDROP_KEY)
        local normalBg = SkinBase.GetFrameData(self, "normalBg")
        local borderColor = SkinBase.GetFrameData(self, "borderColor")
        if backdrop and normalBg and borderColor then
            ApplyTextureBackdrop(backdrop, borderColor[1], borderColor[2], borderColor[3], borderColor[4],
                normalBg[1], normalBg[2], normalBg[3], normalBg[4])
        end
    end)

    -- Style the label, and re-assert it whenever the button is shown or its
    -- enabled state changes — Blizzard reapplies the button's font object on
    -- those, which can otherwise leave the Ready / Not Ready label unrendered.
    RestyleButtonText(button)
    button:HookScript("OnShow", RestyleButtonText)
    button:HookScript("OnEnable", RestyleButtonText)
    button:HookScript("OnDisable", RestyleButtonText)

    SkinBase.MarkSkinned(button)
end

-- Update button colors (for live refresh)
local function RefreshButtonColors(button, sr, sg, sb, bgr, bgg, bgb, bga)
    local backdrop = button and SkinBase.GetFrameData(button, TEXTURE_BACKDROP_KEY)
    if not backdrop then return end

    local btnBgr = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgg = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgb = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)

    SkinBase.SetFrameData(button, "normalBg", { btnBgr, btnBgg, btnBgb, bga })
    SkinBase.SetFrameData(button, "hoverBg", { math.min(btnBgr + 0.1, 1), math.min(btnBgg + 0.1, 1), math.min(btnBgb + 0.1, 1), bga })
    SkinBase.SetFrameData(button, "borderColor", { sr, sg, sb, 1 })

    ApplyTextureBackdrop(backdrop, sr, sg, sb, 1, btnBgr, btnBgg, btnBgb, bga)
end

---------------------------------------------------------------------------
-- HIDE BLIZZARD DECORATIONS
---------------------------------------------------------------------------

local function HideBlizzardDecorations()
    local frame = _G.ReadyCheckFrame
    local listenerFrame = _G.ReadyCheckListenerFrame
    if not frame then return end

    -- Hide portrait texture
    if _G.ReadyCheckPortrait then
        _G.ReadyCheckPortrait:SetAlpha(0)
    end

    -- The main decorations are on ReadyCheckListenerFrame
    if listenerFrame then
        -- Hide NineSlice border (the main frame decoration)
        if listenerFrame.NineSlice then
            listenerFrame.NineSlice:SetAlpha(0)
        end

        -- Hide PortraitContainer (gold circle frame)
        if listenerFrame.PortraitContainer then
            listenerFrame.PortraitContainer:SetAlpha(0)
        end

        -- Hide TitleContainer (header bar with "Ready Check" text)
        if listenerFrame.TitleContainer then
            listenerFrame.TitleContainer:SetAlpha(0)
        end

        -- Hide background texture
        if listenerFrame.Bg then
            listenerFrame.Bg:SetAlpha(0)
        end

        -- Hide all textures on listener frame
        for _, region in ipairs({listenerFrame:GetRegions()}) do
            if region:GetObjectType() == "Texture" then
                if not SkinBase.GetFrameData(region, OWNED_TEXTURE_KEY) then
                    region:SetAlpha(0)
                end
            end
        end
    end

    -- Also hide any textures directly on ReadyCheckFrame
    for _, region in ipairs({frame:GetRegions()}) do
        if region:GetObjectType() == "Texture" then
            if not SkinBase.GetFrameData(region, OWNED_TEXTURE_KEY) then
                region:SetAlpha(0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- MAIN SKINNING FUNCTION
---------------------------------------------------------------------------

local function SkinReadyCheckFrame()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or settings.skinReadyCheck == false then return end

    local frame = _G.ReadyCheckFrame
    local listenerFrame = _G.ReadyCheckListenerFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    -- Get colors
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "readyCheck")

    -- Hide Blizzard decorations
    HideBlizzardDecorations()

    local targetFrame = listenerFrame or frame
    ApplyTextureBackdrop(EnsureTextureBackdrop(targetFrame, frame), sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Skin Yes/No buttons and re-center them
    local yesButton = _G.ReadyCheckFrameYesButton
    local noButton = _G.ReadyCheckFrameNoButton

    if yesButton then
        SkinButton(yesButton, sr, sg, sb, bgr, bgg, bgb, bga)
        yesButton:ClearAllPoints()
        yesButton:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOM", -5, 12)
    end
    if noButton then
        SkinButton(noButton, sr, sg, sb, bgr, bgg, bgb, bga)
        noButton:ClearAllPoints()
        noButton:SetPoint("BOTTOMLEFT", targetFrame, "BOTTOM", 5, 12)
    end

    -- Style and re-center the main text (was offset for portrait)
    local text = _G.ReadyCheckFrameText
    if text then
        text:ClearAllPoints()
        text:SetPoint("TOP", targetFrame, "TOP", 0, -30)
        text:SetFont(STANDARD_TEXT_FONT, 12, FONT_FLAGS)
        if text.SetDrawLayer then text:SetDrawLayer("OVERLAY", 5) end
        text:SetTextColor(0.9, 0.9, 0.9, 1)
    end

    -- Create custom title (hide Blizzard's, make our own)
    if not SkinBase.GetFrameData(frame, "title") then
        local title = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", targetFrame, "TOP", 0, -8)
        title:SetFont(STANDARD_TEXT_FONT, 13, FONT_FLAGS)
        if title.SetDrawLayer then title:SetDrawLayer("OVERLAY", 7) end
        SkinBase.SetFrameData(frame, "title", title)
    end
    SkinBase.GetFrameData(frame, "title"):SetText("Ready Check")
    SkinBase.GetFrameData(frame, "title"):SetTextColor(sr, sg, sb, 1)  -- Use skin color for title

    -- Hook Show to reapply hiding and restore position (Blizzard may reset)
    -- TAINT SAFETY: Use hooksecurefunc + C_Timer.After(0) to break taint chain from secure context.
    hooksecurefunc(frame, "Show", function(self)
        C_Timer.After(0, function()
            HideBlizzardDecorations()
            -- Reapply frameAnchoring position (Blizzard resets on Show)
            -- Skip if in combat — ReadyCheckFrame is protected, can't reposition
            if not InCombatLockdown() and _G.QUI_ApplyFrameAnchor then
                _G.QUI_ApplyFrameAnchor("readyCheck")
            end
        end)
    end)

    -- Make frame movable (only when unlocked)
    -- Defer to post-combat if in lockdown so skinning can still proceed
    local function EnableDragging()
        if InCombatLockdown() then
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                EnableDragging()
            end)
            return
        end
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
    end
    EnableDragging()
    frame:HookScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        if SkinBase.GetFrameData(self, "unlocked") then
            self:StartMoving()
        end
    end)
    frame:HookScript("OnDragStop", function(self)
        if InCombatLockdown() then return end
        if SkinBase.GetFrameData(self, "unlocked") then
            self:StopMovingOrSizing()
        end
    end)

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

---------------------------------------------------------------------------
-- LIVE COLOR REFRESH
---------------------------------------------------------------------------

local function RefreshReadyCheckColors()
    local frame = _G.ReadyCheckFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end

    local settings = GetSettings()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "readyCheck")

    ApplyTextureBackdrop(SkinBase.GetFrameData(frame, TEXTURE_BACKDROP_KEY), sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Update title color
    local title = SkinBase.GetFrameData(frame, "title")
    if title then
        title:SetTextColor(sr, sg, sb, 1)
    end

    -- Update buttons
    RefreshButtonColors(_G.ReadyCheckFrameYesButton, sr, sg, sb, bgr, bgg, bgb, bga)
    RefreshButtonColors(_G.ReadyCheckFrameNoButton, sr, sg, sb, bgr, bgg, bgb, bga)
end

-- Expose refresh function globally (required for live preview)
_G.QUI_RefreshReadyCheckColors = RefreshReadyCheckColors

if ns.Registry then
    ns.Registry:Register("skinReadyCheck", {
        refresh = _G.QUI_RefreshReadyCheckColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local Helpers = ns.Helpers
if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "readyCheck", label = "Ready Check", category = "Skinning", prefix = "readyCheck",
        db = function(p) return p.general end,
        refresh = function() if _G.QUI_RefreshReadyCheckColors then _G.QUI_RefreshReadyCheckColors() end end,
        legacy = { override = "readyCheckBorderOverride", useClass = "readyCheckBorderUseClassColor" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= ADDON_NAME then
        return
    end
    if event == "ADDON_LOADED" then
        self:UnregisterEvent("ADDON_LOADED")
    end
    if _G.ReadyCheckFrame then
        SkinReadyCheckFrame()
    end
end)
