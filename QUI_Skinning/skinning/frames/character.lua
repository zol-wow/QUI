local addonName, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local UIKit = ns.UIKit

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- CHARACTER FRAME SKINNING
-- Skins CharacterFrame including Character, Reputation, and Currency tabs
---------------------------------------------------------------------------

-- Module reference
local CharacterSkinning = {}
-- Configuration constants (centralized for easy adjustment)
local CONFIG = {
    PANEL_WIDTH_EXTENSION = 55,   -- Extra width for stats panel
    PANEL_HEIGHT_EXTENSION = 50,  -- Extra height for stats panel
}

-- Static colors (text only - bg/border from QUI skin system)
local COLORS = {
    text = { 0.9, 0.9, 0.9, 1 },
}

-- Module state
local customBg = nil

-- TAINT SAFETY: Store per-frame state in weak-keyed tables instead of writing
-- properties to Blizzard frames, which taints them in Midnight (12.0)
local iconBorders = Helpers.CreateStateTable()       -- CurrencyIcon/entry.icon → border frame
local skinnedEntries = Helpers.CreateStateTable()    -- entry → true
local titleHighlights = Helpers.CreateStateTable()   -- button → highlight texture

---------------------------------------------------------------------------
-- Helper: Get skin colors from QUI system
---------------------------------------------------------------------------
local GetSkinColors = Helpers.CreateSkinColorGetter("characterFrame")

local GetFontPath = Helpers.GetGeneralFont

-- Pixel-backdrop application + live recolor route through the canonical SkinBase
-- engine (pixelBackdropData + the shared "skinningPixelBackdrop" scale-refresh).
-- These thin local shims keep the existing call sites unchanged while removing
-- the former divergent local engine (its own pixelBackdropState table, a
-- "characterFramePixelBackdrop" refresh tag, and a bare-setter twin). The
-- canonical RefreshPixelBackdrop re-derives edgeSize from SkinBase.GetPixelSize
-- on every scale refresh and renders via the SAME snapped 4-texture
-- ApplyTextureBackdrop path (render path #3), so scroll-row elements created
-- during ScrollBox acquire (before effective scale resolves) still re-hug the
-- bar/icon at fractional UI scale — the property the local engine existed for.
local function ApplyPixelBackdrop(frame, borderPixels, withBackground, withInsets, borderColor, bgColor)
    SkinBase.ApplyPixelBackdrop(frame, borderPixels, withBackground, withInsets, borderColor, bgColor)
end

-- Live-recolor a frame skinned via ApplyPixelBackdrop. Routes through
-- SkinBase.SetBackdropColors so the new color persists across the next scale
-- refresh (a bare SetBackdrop*Color is discarded when RefreshPixelBackdrop
-- rebuilds from the persisted data).
local function SetPixelBackdropColors(frame, borderColor, bgColor)
    SkinBase.SetBackdropColors(frame, borderColor, bgColor)
end

-- Expand a frame `pixels` beyond `relativeTo` on every side. Delegates to the
-- shared SkinBase helper, which registers a scale refresh so the offset tracks
-- effective scale. Scroll-row elements (rep-bar backdrops, currency/equip icon
-- borders) are created during ScrollBox acquire before the row's effective
-- scale resolves; the local ApplyPixelBackdrop re-derives its edgeSize on every
-- scale-refresh, so the expansion MUST refresh on the same broadcast (and from
-- the same core:GetPixelSize basis SkinBase.GetPixelSize wraps) or edge size and
-- expansion diverge and the border bleeds inside the bar/icon.
local SetExpandedPixelPoints = SkinBase.SetExpandedPixelPoints

---------------------------------------------------------------------------
-- Helper: Style a thin QUI scrollbar
---------------------------------------------------------------------------
-- Delegates to the shared SkinBase.SkinTrimScrollBar (promoted from this very
-- function). Kept as a thin local so the existing (scrollBar, r, g, b) call
-- sites stay unchanged.
local function StyleThinScrollBar(scrollBar, r, g, b)
    SkinBase.SkinTrimScrollBar(scrollBar, { color = r and { r, g, b } or nil })
end

---------------------------------------------------------------------------
-- Helper: Check if skinning is enabled
---------------------------------------------------------------------------
local function IsSkinningEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinCharacterFrame
end

local function IsCharacterPaneEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.character
    return not (settings and settings.enabled == false)
end

local function MaskNativeStatsPane()
    if not CharacterStatsPane then return end
    pcall(CharacterStatsPane.Show, CharacterStatsPane)
    pcall(CharacterStatsPane.SetAlpha, CharacterStatsPane, 0)
    if CharacterStatsPane.EnableMouse then
        pcall(CharacterStatsPane.EnableMouse, CharacterStatsPane, false)
    end
    if CharacterStatsPane.ClassBackground then
        pcall(CharacterStatsPane.ClassBackground.SetAlpha, CharacterStatsPane.ClassBackground, 0)
    end
end

local function RestoreNativeStatsPane()
    if not CharacterStatsPane then return end
    pcall(CharacterStatsPane.SetAlpha, CharacterStatsPane, 1)
    if CharacterStatsPane.EnableMouse then
        pcall(CharacterStatsPane.EnableMouse, CharacterStatsPane, true)
    end
    if CharacterStatsPane.ClassBackground then
        pcall(CharacterStatsPane.ClassBackground.SetAlpha, CharacterStatsPane.ClassBackground, 1)
    end
end

---------------------------------------------------------------------------
-- Create/update the custom background frame
---------------------------------------------------------------------------
local function CreateOrUpdateBackground()
    if not CharacterFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    if not customBg then
        customBg = CreateFrame("Frame", "QUI_CharacterFrameBg_Skin", CharacterFrame, "BackdropTemplate")
        customBg:SetFrameStrata("BACKGROUND")
        customBg:SetFrameLevel(0)
        customBg:EnableMouse(false)  -- Don't steal clicks
    end

    -- Local ApplyPixelBackdrop already persists+renders these colors via the file's own
    -- backdrop subsystem; the global Helpers.SetFrameBackdrop* pair wrote a _quiBg*/_quiBorder*
    -- cache the local RefreshPixelBackdrop never reads, so it was redundant on the create path.
    ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })

    return customBg
end

---------------------------------------------------------------------------
-- Hide Blizzard decorative elements on CharacterFrame
-- NineSlice borders are hooked once so Blizzard cannot re-show them.
---------------------------------------------------------------------------
-- Weak-keyed (matches the other per-frame side tables above) so hooked NineSlice
-- frames can still be garbage-collected; a plain table would pin them forever.
local nineSliceHooked = Helpers.CreateStateTable()

local function HideNineSlice(nineSlice)
    if not nineSlice then return end
    nineSlice:Hide()
    nineSlice:SetAlpha(0)
    if not nineSliceHooked[nineSlice] then
        hooksecurefunc(nineSlice, "Show", function(self) self:Hide(); self:SetAlpha(0) end)
        nineSliceHooked[nineSlice] = true
    end
end

local function HideBlizzardDecorations()
    -- Cover all standard ButtonFrameTemplate chrome — picks up TopTileStreaks
    -- and TitleContainer.TitleBg that prior code missed.
    SkinBase.HidePortraitFrameChrome(CharacterFrame)
    -- Then upgrade the NineSlice hides with the re-show hook (defends against
    -- Blizzard re-showing the NineSlice after a layout pass).
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    HideNineSlice(CharacterFrame.NineSlice)
    HideNineSlice(CharacterFrameInset and CharacterFrameInset.NineSlice)
    HideNineSlice(CharacterFrameInsetRight and CharacterFrameInsetRight.NineSlice)
    if CharacterFrameBg then CharacterFrameBg:Hide() end
    -- Mask the native stats pane only while the replacement stats panel is
    -- enabled. With the replacement off, Blizzard's own stats must remain
    -- readable even if the surrounding frame skin is still enabled.
    if IsCharacterPaneEnabled() then
        MaskNativeStatsPane()
    else
        RestoreNativeStatsPane()
    end
end

---------------------------------------------------------------------------
-- API: Set background extended mode (called by qui_character.lua)
---------------------------------------------------------------------------
local function SetCharacterFrameBgExtended(extended)
    if not customBg then
        CreateOrUpdateBackground()
    end
    if not customBg then return end

    customBg:ClearAllPoints()

    if extended then
        customBg:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
        customBg:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT",
            CONFIG.PANEL_WIDTH_EXTENSION, -CONFIG.PANEL_HEIGHT_EXTENSION)
    else
        customBg:SetAllPoints(CharacterFrame)
    end

    customBg:Show()
    HideBlizzardDecorations()
end

---------------------------------------------------------------------------
-- Skin bottom tabs: Character, Reputation, Currency
---------------------------------------------------------------------------
-- Routes through the canonical SkinBase.SkinTabGroup. The former private
-- StyleCharacterFrameTab + UpdateCharacterFrameTabSelectedState pair was a
-- byte-for-byte fork of SkinTabButton + RefreshTabSelected (same ClampAllTextures
-- + CreateBackdrop(...,0.9) + SetPixelInsetPoints(3,3,3,0) + RegisterTabArtClamp
-- body, same selected/unselected color math) that silently drifted from every
-- other frame's tabs. font=true opts into the QUI tab font + the canonical
-- selected/unselected label recolor (now promoted into RefreshTabSelected, so it
-- is identical across CharacterFrame, InspectFrame, AH, merchant, etc.).
-- SkinTabGroup is idempotent and installs the PanelTemplates_SetTab / TabSystem
-- selection dispatch itself, so re-calling it on each render pass is cheap.
local function SkinCharacterFrameTabs()
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("CharacterFrame", 3), CharacterFrame, { font = true })
end

-- Skin a top-level entry header: name font/color plus collapse-icon atlas hooks
local function SkinEntryHeader(child, fontPath, sr, sg, sb)
    if child.Name then
        CJKFont(child.Name, fontPath, 13, "")
        child.Name:SetTextColor(sr, sg, sb, 1)
    end

    -- Suppress Blizzard's category-header art. ReputationHeaderTemplate
    -- (ReputationFrame.xml) draws Options_ListExpand Left/Middle in BACKGROUND
    -- and HighlightLeft/HighlightMiddle in HIGHLIGHT — the bar behind the
    -- category name + its hover fill. SetAlpha(0) keeps them invisible even when
    -- the HIGHLIGHT layer auto-shows on mouseover. Right/HighlightRight are
    -- repurposed below as the collapse arrow, so they stay.
    if child.Left then child.Left:SetAlpha(0) end
    if child.Middle then child.Middle:SetAlpha(0) end
    if child.HighlightLeft then child.HighlightLeft:SetAlpha(0) end
    if child.HighlightMiddle then child.HighlightMiddle:SetAlpha(0) end

    -- Currency headers (ListHeaderThreeSliceMixin) re-assert Blizzard's title
    -- color via CheckHighlightTitle on every SetHeaderText (expand/collapse) and
    -- on mouseover, clobbering a one-shot Name:SetTextColor. Feed QUI color into
    -- that mechanism so Blizzard's own re-color uses it. (Reputation headers use
    -- a plain SetText with no re-color, so the SetTextColor above sticks there.)
    if child.SetTitleColor and CreateColor then
        local titleColor = CreateColor(sr, sg, sb, 1)
        child:SetTitleColor(false, titleColor)
        child:SetTitleColor(true, titleColor)
        if child.CheckHighlightTitle then child:CheckHighlightTitle() end
    end

    -- Replace collapse icons
    local function UpdateCollapseIcon(texture, atlas)
        if not atlas or atlas == "Options_ListExpand_Right" or atlas == "Options_ListExpand_Right_Expanded" then
            if child.IsCollapsed and child:IsCollapsed() then
                texture:SetAtlas("Soulbinds_Collection_CategoryHeader_Expand", true)
            else
                texture:SetAtlas("Soulbinds_Collection_CategoryHeader_Collapse", true)
            end
        end
    end

    UpdateCollapseIcon(child.Right)
    UpdateCollapseIcon(child.HighlightRight)
    hooksecurefunc(child.Right, "SetAtlas", UpdateCollapseIcon)
    hooksecurefunc(child.HighlightRight, "SetAtlas", UpdateCollapseIcon)
end

-- Skin a collapse toggle button: swap its normal/pushed atlas with the header state
local function SkinToggleCollapseButton(ToggleCollapseButton)
    if ToggleCollapseButton and ToggleCollapseButton.RefreshIcon then
        local function UpdateToggleButton(button)
            local header = button.GetHeader and button:GetHeader()
            if not header then return end
            if header:IsCollapsed() then
                button:GetNormalTexture():SetAtlas("Gamepad_Expand", true)
                button:GetPushedTexture():SetAtlas("Gamepad_Expand", true)
            else
                button:GetNormalTexture():SetAtlas("Gamepad_Collapse", true)
                button:GetPushedTexture():SetAtlas("Gamepad_Collapse", true)
            end
        end
        hooksecurefunc(ToggleCollapseButton, "RefreshIcon", UpdateToggleButton)
        UpdateToggleButton(ToggleCollapseButton)
    end
end

---------------------------------------------------------------------------
-- Skin individual reputation entry/header
---------------------------------------------------------------------------
local function SkinReputationEntry(child)
    if skinnedEntries[child] then return end

    local sr, sg, sb, sa = GetSkinColors()
    local fontPath = GetFontPath()

    -- Skin top-level headers (expansion names)
    if child.Right then
        SkinEntryHeader(child, fontPath, sr, sg, sb)
    end

    -- Skin reputation bar
    local ReputationBar = child.Content and child.Content.ReputationBar
    if ReputationBar then
        ReputationBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        -- The solid fill rasterizes away at fractional UI scale without opting
        -- out of texel snapping (DisablePixelSnap also covers the bar's fill
        -- texture). Matches StyleThinScrollBar's thumb handling.
        UIKit.DisablePixelSnap(ReputationBar)

        -- Suppress Blizzard's ornate end-cap art + black fill backing.
        -- ReputationBarTemplate (ReputationFrame.xml) draws LeftTexture/RightTexture
        -- (UI-Character-ReputationBar) and a Background (BLACK_FONT_COLOR); the mixin
        -- never re-shows them, so hiding once is durable. Our backdrop replaces both.
        if ReputationBar.LeftTexture then
            ReputationBar.LeftTexture:SetTexture(nil)
            ReputationBar.LeftTexture:Hide()
        end
        if ReputationBar.RightTexture then
            ReputationBar.RightTexture:SetTexture(nil)
            ReputationBar.RightTexture:Hide()
        end
        if ReputationBar.Background then
            ReputationBar.Background:Hide()
        end

        if ReputationBar.BarText then
            CJKFont(ReputationBar.BarText, fontPath, 10, "")
            ReputationBar.BarText:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3], 1)
        end

        -- Create backdrop for rep bar
        if not SkinBase.GetFrameData(ReputationBar, "backdrop") then
            local backdrop = CreateFrame("Frame", nil, ReputationBar:GetParent(), "BackdropTemplate")
            -- Sit one level BELOW the bar: the bar's WHITE8x8 fill (filled portion)
            -- draws over the backdrop's dark fill (which now backs the empty portion,
            -- since we hide the native Background), and the expanded border ring sits
            -- outside the bar rect so it renders on all four sides without the
            -- same-level draw-order race that occluded it before.
            backdrop:SetFrameLevel(math.max(0, ReputationBar:GetFrameLevel() - 1))
            local dr, dg, db, da = SkinBase.GetDepthColor("ROW")
            SetExpandedPixelPoints(backdrop, ReputationBar, SkinBase.CHROME.BORDER_PX)
            ApplyPixelBackdrop(backdrop, SkinBase.CHROME.BORDER_PX, true, false, { sr, sg, sb, 1 }, { dr, dg, db, da })
            backdrop:Show()
            SkinBase.SetFrameData(ReputationBar, "backdrop", backdrop)
        end

        if child.Content.Name then
            CJKFont(child.Content.Name, fontPath, 11, "")
        end
    end

    -- Skin collapse button
    SkinToggleCollapseButton(child.ToggleCollapseButton)

    skinnedEntries[child] = true
end

---------------------------------------------------------------------------
-- Skin individual currency entry/header
---------------------------------------------------------------------------
local function SkinCurrencyEntry(child)
    if skinnedEntries[child] then return end

    local sr, sg, sb, sa = GetSkinColors()
    local fontPath = GetFontPath()

    -- Skin top-level headers
    if child.Right then
        SkinEntryHeader(child, fontPath, sr, sg, sb)
    end

    -- Style currency icon
    local CurrencyIcon = child.Content and child.Content.CurrencyIcon
    if CurrencyIcon then
        CurrencyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        if not iconBorders[CurrencyIcon] then
            local border = CreateFrame("Frame", nil, CurrencyIcon:GetParent(), "BackdropTemplate")
            local drawLayer = CurrencyIcon.GetDrawLayer and CurrencyIcon:GetDrawLayer()
            border:SetFrameLevel((drawLayer == "OVERLAY") and child:GetFrameLevel() + 2 or child:GetFrameLevel() + 1)
            SetExpandedPixelPoints(border, CurrencyIcon, 1)
            ApplyPixelBackdrop(border, 1, false, false, { sr, sg, sb, 1 })
            iconBorders[CurrencyIcon] = border
        end
    end

    -- Style name and count
    if child.Content then
        if child.Content.Name then
            CJKFont(child.Content.Name, fontPath, 11, "")
        end
        if child.Content.Count then
            CJKFont(child.Content.Count, fontPath, 11, "")
        end
    end

    -- Skin collapse button
    SkinToggleCollapseButton(child.ToggleCollapseButton)

    skinnedEntries[child] = true
end

---------------------------------------------------------------------------
-- Main skinning setup
---------------------------------------------------------------------------
local function SetupCharacterFrameSkinning()
    if not IsSkinningEnabled() then return end
    if not CharacterFrame then return end

    -- Create initial background (non-extended for Rep/Currency default)
    CreateOrUpdateBackground()

    -- Immediately hide Blizzard decorations and hook NineSlice Show
    HideBlizzardDecorations()
    SkinCharacterFrameTabs()

    -- ScrollBox row skinning — fires once per frame acquisition vs. once per
    -- Update tick, so debouncing is no longer needed.
    if ReputationFrame and ReputationFrame.ScrollBox then
        SkinBase.HookScrollBoxAcquired(ReputationFrame.ScrollBox, function(row)
            if IsSkinningEnabled() then
                SkinReputationEntry(row)
                SkinBase.LockPooledRowText(row, 4)
            end
        end)
    end
    -- The reputation detail popout (ReputationDetailFrame) holds buttons like
    -- "View Renown" whose HighlightFont OBJECT the engine swaps on hover with no
    -- setter call. Drive the popout's button font objects (guarded; created on demand).
    if ReputationFrame and ReputationFrame.ReputationDetailFrame and SkinBase.ApplyButtonFontObjectsDeep then
        SkinBase.ApplyButtonFontObjectsDeep(ReputationFrame.ReputationDetailFrame, 2)
    end
    if TokenFrame and TokenFrame.ScrollBox then
        SkinBase.HookScrollBoxAcquired(TokenFrame.ScrollBox, function(row)
            if IsSkinningEnabled() then
                SkinCurrencyEntry(row)
                SkinBase.LockPooledRowText(row, 4)
            end
        end)
        -- TokenEntryMixin:Initialize re-SetTexture's CurrencyIcon on every bind,
        -- resetting our texcoord crop; re-apply after it (acquire fires only once).
        if _G.TokenEntryMixin and _G.TokenEntryMixin.Initialize
            and not SkinBase.GetFrameData(TokenFrame, "qTokenIconHooked") then
            hooksecurefunc(_G.TokenEntryMixin, "Initialize", function(self)
                if not IsSkinningEnabled() then return end
                local icon = self.Content and self.Content.CurrencyIcon
                if icon then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            end)
            SkinBase.SetFrameData(TokenFrame, "qTokenIconHooked", true)
        end
    end

    -- Handle tab switching - show background and hide decorations
    if ReputationFrame then
        ReputationFrame:HookScript("OnShow", function()
            if IsSkinningEnabled() then
                SetCharacterFrameBgExtended(false)
            end
        end)
        -- Handle hotkey open
        if ReputationFrame:IsShown() then
            SetCharacterFrameBgExtended(false)
        end
    end

    if TokenFrame then
        TokenFrame:HookScript("OnShow", function()
            if IsSkinningEnabled() then
                SetCharacterFrameBgExtended(false)
            end
        end)
        -- Handle hotkey open
        if TokenFrame:IsShown() then
            SetCharacterFrameBgExtended(false)
        end
    end

    -- Handle Character tab (PaperDollFrame) - show background without extension
    -- (qui_character.lua will extend if character pane customization is enabled)
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            if IsSkinningEnabled() then
                -- Check if character pane customization will handle extension
                local core = GetCore()
                local charSettings = core and core.db and core.db.profile and core.db.profile.character
                -- Default to true if setting not found (matches qui_character.lua defaults)
                local charPaneEnabled = charSettings and charSettings.enabled
                if charPaneEnabled == nil then charPaneEnabled = true end

                if not charPaneEnabled then
                    -- Character pane disabled - skinning handles bg at normal size
                    SetCharacterFrameBgExtended(false)
                end
                -- If charPaneEnabled, qui_character.lua will call SetCharacterFrameBgExtended(true)
            end
        end)
        -- Handle if already shown
        if PaperDollFrame:IsShown() then
            local core = GetCore()
            local charSettings = core and core.db and core.db.profile and core.db.profile.character
            -- Default to true if setting not found (matches qui_character.lua defaults)
            local charPaneEnabled = charSettings and charSettings.enabled
            if charPaneEnabled == nil then charPaneEnabled = true end
            if not charPaneEnabled then
                SetCharacterFrameBgExtended(false)
            end
        end
    end

    -- Handle CharacterFrame open when PaperDoll not shown (hotkey to Rep/Currency)
    CharacterFrame:HookScript("OnShow", function()
        C_Timer.After(0.01, function()
            if IsSkinningEnabled() then
                SkinCharacterFrameTabs()
                if not (PaperDollFrame and PaperDollFrame:IsShown()) then
                    SetCharacterFrameBgExtended(false)
                end
            end
        end)
    end)
end

---------------------------------------------------------------------------
-- Refresh colors on already-skinned elements (for live preview)
---------------------------------------------------------------------------
-- Forward declarations for refresh functions (defined below)
local RefreshEquipmentManagerColors
local RefreshTitlePaneColors

local function RefreshCharacterFrameColors()
    if not IsSkinningEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    -- Update main background
    if customBg then
        ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    SkinCharacterFrameTabs()

    -- Update reputation entries
    if ReputationFrame and ReputationFrame.ScrollBox then
        ReputationFrame.ScrollBox:ForEachFrame(function(child)
            if not skinnedEntries[child] then return end
            if child.Right and child.Name then
                child.Name:SetTextColor(sr, sg, sb, 1)
            end
            local ReputationBar = child.Content and child.Content.ReputationBar
            local repBd = ReputationBar and SkinBase.GetFrameData(ReputationBar, "backdrop")
            if repBd then
                SetPixelBackdropColors(repBd, { sr, sg, sb, 1 })
            end
        end)
    end

    -- Update currency entries
    if TokenFrame and TokenFrame.ScrollBox then
        TokenFrame.ScrollBox:ForEachFrame(function(child)
            if not skinnedEntries[child] then return end
            if child.Right and child.Name then
                child.Name:SetTextColor(sr, sg, sb, 1)
            end
            local CurrencyIcon = child.Content and child.Content.CurrencyIcon
            if CurrencyIcon and iconBorders[CurrencyIcon] then
                SetPixelBackdropColors(iconBorders[CurrencyIcon], { sr, sg, sb, 1 })
            end
        end)
    end

    -- Update Equipment Manager (function defined below, called via forward reference)
    if RefreshEquipmentManagerColors then RefreshEquipmentManagerColors() end

    -- Update Title Pane (function defined below, called via forward reference)
    if RefreshTitlePaneColors then RefreshTitlePaneColors() end
end

---------------------------------------------------------------------------
-- EQUIPMENT MANAGER SKINNING
---------------------------------------------------------------------------

local function RestyleEquipmentSetEntryText(entry)
    local text = entry and entry.text
    if not text then return end
    CJKFont(text, GetFontPath(), 11, "")
    if text.SetTextColor then
        text:SetTextColor(0.9, 0.9, 0.9, 1)
    end
end

-- Skin individual equipment set entry
local function SkinEquipmentSetEntry(entry)
    if not entry then return end
    RestyleEquipmentSetEntryText(entry)
    if skinnedEntries[entry] then return end

    local sr, sg, sb, sa = GetSkinColors()

    -- Style the icon with a border
    if entry.icon and not iconBorders[entry.icon] then
        entry.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = CreateFrame("Frame", nil, entry, "BackdropTemplate")
        SetExpandedPixelPoints(border, entry.icon, 1)
        ApplyPixelBackdrop(border, 1, false, false, { sr, sg, sb, 1 })
        iconBorders[entry.icon] = border
    end

    -- Style highlight/selection
    if entry.SelectedBar then
        entry.SelectedBar:SetColorTexture(sr, sg, sb, 0.3)
    end
    if entry.HighlightBar then
        entry.HighlightBar:SetColorTexture(sr, sg, sb, 0.15)
    end

    skinnedEntries[entry] = true
end

-- Style Equip/Save buttons
local function StyleEquipMgrButton(btn)
    if not btn or skinnedEntries[btn] then return end

    local sr, sg, sb, sa = GetSkinColors()

    -- Store original width
    local origWidth = btn:GetWidth()

    -- Remove Blizzard textures
    if btn:GetNormalTexture() then btn:GetNormalTexture():SetTexture(nil) end
    if btn:GetHighlightTexture() then btn:GetHighlightTexture():SetTexture(nil) end
    if btn:GetPushedTexture() then btn:GetPushedTexture():SetTexture(nil) end
    if btn:GetDisabledTexture() then btn:GetDisabledTexture():SetTexture(nil) end

    -- Skip buttons that don't have BackdropTemplate — Mixin() from addon context
    -- would taint the frame permanently in Midnight's taint model.
    if not btn.SetBackdrop then
        return
    end
    ApplyPixelBackdrop(btn, 1, true, false, { sr, sg, sb, 0.5 }, { 0.15, 0.15, 0.15, 1 })

    -- Style text via the button's font OBJECTS so the QUI font survives hover
    -- (HighlightFont) and disable (DisabledFont — SaveSet is disabled with no set
    -- selected); a plain SetFont would be clobbered by Blizzard's font object.
    SkinBase.ApplyButtonFontObjects(btn, { size = 11, color = { 0.9, 0.9, 0.9, 1 }, disabledColor = { 0.5, 0.5, 0.5, 1 } })

    -- Restore width
    btn:SetWidth(origWidth)

    -- Hover effects (capture colors at hook time for consistency). Route through
    -- SetPixelBackdropColors so a scale refresh mid-hover keeps the hover border
    -- instead of rebuilding from the stale creation-time state color.
    btn:HookScript("OnEnter", function(self)
        local r, g, b = GetSkinColors()
        SetPixelBackdropColors(self, { r, g, b, 1 })
    end)
    btn:HookScript("OnLeave", function(self)
        local r, g, b = GetSkinColors()
        SetPixelBackdropColors(self, { r, g, b, 0.5 })
    end)

    skinnedEntries[btn] = true
end

-- Main function to skin Equipment Manager popup
local function SkinEquipmentManager()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_EquipMgrPopup
    if not popup then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    local fontPath = GetFontPath()

    -- Skin popup backdrop
    if not skinnedEntries[popup] then
        ApplyPixelBackdrop(popup, 1, true, false, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        skinnedEntries[popup] = true
    end
    SetPixelBackdropColors(popup, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })

    -- Skin title
    if popup.title then
        CJKFont(popup.title, fontPath, 12, "")
        popup.title:SetTextColor(sr, sg, sb, 1)
    end

    -- Skin equipment set entries — fires once per acquisition.
    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if pane and pane.ScrollBox then
        SkinBase.HookScrollBoxAcquired(pane.ScrollBox, function(row)
            if IsSkinningEnabled() then SkinEquipmentSetEntry(row) end
        end)
    end

    -- HookScrollBoxAcquired fires once per pool acquisition, but Blizzard's global
    -- PaperDollEquipmentManagerPane_InitButton re-asserts GREEN/RED/NORMAL text color
    -- + re-SetTexture's the icon (resetting texcoord) on EVERY data Update without
    -- re-acquiring. Re-apply our font/color + icon crop after it, once-guarded.
    if type(_G.PaperDollEquipmentManagerPane_InitButton) == "function"
        and not SkinBase.GetFrameData(pane, "qEquipInitHooked") then
        hooksecurefunc("PaperDollEquipmentManagerPane_InitButton", function(button)
            if not IsSkinningEnabled() or not button then return end
            RestyleEquipmentSetEntryText(button)
            if button.icon then button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end)
        SkinBase.SetFrameData(pane, "qEquipInitHooked", true)
    end

    if pane then
        StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar), sr, sg, sb)
    end

    -- Skin buttons
    StyleEquipMgrButton(PaperDollFrameEquipSet)
    StyleEquipMgrButton(PaperDollFrameSaveSet)
end

---------------------------------------------------------------------------
-- Refresh Equipment Manager colors (merged into character frame refresh)
---------------------------------------------------------------------------
RefreshEquipmentManagerColors = function()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_EquipMgrPopup
    if not popup or not skinnedEntries[popup] then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    -- Update popup
    SetPixelBackdropColors(popup, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    if popup.title then
        popup.title:SetTextColor(sr, sg, sb, 1)
    end

    -- Update entries
    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if pane and pane.ScrollBox then
        pane.ScrollBox:ForEachFrame(function(entry)
            if not skinnedEntries[entry] then return end
            RestyleEquipmentSetEntryText(entry)
            if entry.icon and iconBorders[entry.icon] then
                SetPixelBackdropColors(iconBorders[entry.icon], { sr, sg, sb, 1 })
            end
            if entry.SelectedBar then
                entry.SelectedBar:SetColorTexture(sr, sg, sb, 0.3)
            end
            if entry.HighlightBar then
                entry.HighlightBar:SetColorTexture(sr, sg, sb, 0.15)
            end
        end)
    end
    if pane then
        StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar), sr, sg, sb)
    end

    -- Update buttons
    if PaperDollFrameEquipSet and skinnedEntries[PaperDollFrameEquipSet] then
        SetPixelBackdropColors(PaperDollFrameEquipSet, { sr, sg, sb, 0.5 })
    end
    if PaperDollFrameSaveSet and skinnedEntries[PaperDollFrameSaveSet] then
        SetPixelBackdropColors(PaperDollFrameSaveSet, { sr, sg, sb, 0.5 })
    end
end

---------------------------------------------------------------------------
-- TITLE PANE SKINNING
-- Skins the player titles list (PaperDollFrame.TitleManagerPane)
---------------------------------------------------------------------------

-- Skin individual title entry button
local function SkinTitleEntry(button)
    if skinnedEntries[button] then return end

    local sr, sg, sb, sa = GetSkinColors()
    local fontPath = GetFontPath()

    -- Style title text
    if button.text then
        CJKFont(button.text, fontPath, 12, "")
        button.text:SetTextColor(0.9, 0.9, 0.9, 1)
    end

    -- Style check mark with skin color
    if button.Check then
        button.Check:SetVertexColor(sr, sg, sb, 1)
    end

    -- Style selection bar with skin color
    if button.SelectedBar then
        button.SelectedBar:SetColorTexture(sr, sg, sb, 0.3)
    end

    -- Hide Blizzard background textures
    if button.BgTop then button.BgTop:Hide() end
    if button.BgMiddle then button.BgMiddle:Hide() end
    if button.BgBottom then button.BgBottom:Hide() end

    -- Add subtle hover highlight
    if button.Highlight then
        button.Highlight:SetColorTexture(sr, sg, sb, 0.15)
    elseif not titleHighlights[button] then
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(sr, sg, sb, 0.15)
        titleHighlights[button] = highlight
    end

    skinnedEntries[button] = true
end

-- Main function to skin Title Manager popup and pane
local function SkinTitleManagerPane()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_TitlesPopup
    local pane = PaperDollFrame and PaperDollFrame.TitleManagerPane
    if not pane then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    local fontPath = GetFontPath()

    -- Skin popup backdrop (if popup exists)
    if popup and not skinnedEntries[popup] then
        ApplyPixelBackdrop(popup, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        SetPixelBackdropColors(popup, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })

        -- Style title text
        if popup.title then
            CJKFont(popup.title, fontPath, 14, "")
            popup.title:SetTextColor(sr, sg, sb, 1)
        end

        skinnedEntries[popup] = true
    end

    -- Skip pane if already skinned
    if skinnedEntries[pane] then return end

    -- Hide pane background (uses popup's custom bg)
    if pane.Bg then pane.Bg:Hide() end

    -- Style ScrollBox entries — fires once per acquisition. Pair with the guarded
    -- once-per-row font lock (matching the rep/currency rows) so the QUI face survives
    -- any future font-object rebind on the row.
    if pane.ScrollBox then
        SkinBase.HookScrollBoxAcquired(pane.ScrollBox, function(row)
            SkinTitleEntry(row)
            SkinBase.LockPooledRowText(row, 3)
        end)
    end

    -- Blizzard's PaperDollTitlesPane_InitButton re-Shows BgTop/BgMiddle/BgBottom for
    -- first/last rows on every bind (the acquire-guarded SkinTitleEntry won't re-hide).
    if type(_G.PaperDollTitlesPane_InitButton) == "function"
        and not SkinBase.GetFrameData(pane, "qTitleInitHooked") then
        hooksecurefunc("PaperDollTitlesPane_InitButton", function(button)
            if not IsSkinningEnabled() or not button then return end
            if button.BgTop then button.BgTop:Hide() end
            if button.BgMiddle then button.BgMiddle:Hide() end
            if button.BgBottom then button.BgBottom:Hide() end
        end)
        SkinBase.SetFrameData(pane, "qTitleInitHooked", true)
    end

    -- Style scrollbar
    StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar), sr, sg, sb)

    skinnedEntries[pane] = true
end

-- Refresh Title Pane colors
RefreshTitlePaneColors = function()
    if not IsSkinningEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    -- Update popup
    local popup = _G.QUI_TitlesPopup
    if popup and skinnedEntries[popup] then
        SetPixelBackdropColors(popup, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        if popup.title then
            popup.title:SetTextColor(sr, sg, sb, 1)
        end
    end

    -- Update pane entries
    local pane = PaperDollFrame and PaperDollFrame.TitleManagerPane
    if not pane or not skinnedEntries[pane] then return end

    if pane.ScrollBox then
        pane.ScrollBox:ForEachFrame(function(button)
            if not skinnedEntries[button] then return end
            if button.Check then
                button.Check:SetVertexColor(sr, sg, sb, 1)
            end
            if button.SelectedBar then
                button.SelectedBar:SetColorTexture(sr, sg, sb, 0.3)
            end
            if titleHighlights[button] then
                titleHighlights[button]:SetColorTexture(sr, sg, sb, 0.15)
            end
        end)
    end
    StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar), sr, sg, sb)
end

-- Hook setup function (called from initialization after CharacterFrame loads)
local function SetupTitlePaneHook()
    if PaperDollFrame and PaperDollFrame.TitleManagerPane then
        PaperDollFrame.TitleManagerPane:HookScript("OnShow", function()
            SkinTitleManagerPane()
        end)
    end
end

---------------------------------------------------------------------------
-- CONSOLIDATED API TABLE
-- All public functions exposed via single global for clean namespace
---------------------------------------------------------------------------
local api = _G.QUI_CharacterFrameSkinning or {}
api.CONFIG = CONFIG
api.IsEnabled = IsSkinningEnabled
api.SetExtended = SetCharacterFrameBgExtended
api.Refresh = RefreshCharacterFrameColors
api.SkinEquipmentManager = SkinEquipmentManager
api.SkinTitleManager = SkinTitleManagerPane
_G.QUI_CharacterFrameSkinning = api

-- Legacy compatibility alias (deprecated - use QUI_CharacterFrameSkinning table)
_G.QUI_RefreshCharacterFrameColors = RefreshCharacterFrameColors

if ns.Registry then
    ns.Registry:Register("skinCharacter", {
        refresh = _G.QUI_RefreshCharacterFrameColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
local characterFrameSkinningInitialized = false

local function InitializeCharacterFrameSkinning()
    if characterFrameSkinningInitialized or not CharacterFrame then return end
    characterFrameSkinningInitialized = true

    SetupCharacterFrameSkinning()
    SetupTitlePaneHook()
end

SkinBase.OnAddOnLoaded("Blizzard_CharacterFrame", InitializeCharacterFrameSkinning, 0)
SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", InitializeCharacterFrameSkinning, 0)
