local addonName, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

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
local hookedScrollBoxes = Helpers.CreateStateTable() -- ScrollBox → true (hooked for Update)
local titleHighlights = Helpers.CreateStateTable()   -- button → highlight texture
local characterTabsHooked = false

---------------------------------------------------------------------------
-- Helper: Get skin colors from QUI system
---------------------------------------------------------------------------
local GetSkinColors = Helpers.CreateSkinColorGetter("characterFrame")

local GetFontPath = Helpers.GetGeneralFont

---------------------------------------------------------------------------
-- Helper: Style a thin QUI scrollbar
---------------------------------------------------------------------------
local function StyleThinScrollBar(scrollBar, r, g, b)
    if not scrollBar then return end

    if scrollBar.Track then scrollBar.Track:SetAlpha(0) end
    if scrollBar.Background then scrollBar.Background:SetAlpha(0) end

    local thumb = scrollBar.ThumbTexture or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture()) or scrollBar.Thumb
    if thumb then
        thumb:SetColorTexture(r, g, b, 0.78)
        thumb:SetWidth(8 * QUICore:GetPixelSize(scrollBar))
    end

    local upBtn = scrollBar.ScrollUpButton or scrollBar.Back
    local downBtn = scrollBar.ScrollDownButton or scrollBar.Forward
    if upBtn then upBtn:SetAlpha(0) upBtn:SetSize(1, 1) end
    if downBtn then downBtn:SetAlpha(0) downBtn:SetSize(1, 1) end
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
        local px = QUICore:GetPixelSize(customBg)
        customBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
            insets = { left = px, right = px, top = px, bottom = px }
        })
        customBg:SetFrameStrata("BACKGROUND")
        customBg:SetFrameLevel(0)
        customBg:EnableMouse(false)  -- Don't steal clicks
    end

    Helpers.SetFrameBackdropColor(customBg, bgr, bgg, bgb, bga)
    Helpers.SetFrameBackdropBorderColor(customBg, sr, sg, sb, sa)

    return customBg
end

---------------------------------------------------------------------------
-- Hide Blizzard decorative elements on CharacterFrame
-- NineSlice borders are hooked once so Blizzard cannot re-show them.
---------------------------------------------------------------------------
local nineSliceHooked = {}

local function HideNineSlice(ns)
    if not ns then return end
    ns:Hide()
    ns:SetAlpha(0)
    if not nineSliceHooked[ns] then
        hooksecurefunc(ns, "Show", function(self) self:Hide(); self:SetAlpha(0) end)
        nineSliceHooked[ns] = true
    end
end

local function HideBlizzardDecorations()
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    if CharacterFrame.Background then CharacterFrame.Background:Hide() end
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
local function StyleCharacterFrameTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not tab then return end

    if not SkinBase.IsStyled(tab) then
        SkinBase.StripTextures(tab)

        if tab.Left then tab.Left:SetAlpha(0) end
        if tab.Middle then tab.Middle:SetAlpha(0) end
        if tab.Right then tab.Right:SetAlpha(0) end
        if tab.LeftDisabled then tab.LeftDisabled:SetAlpha(0) end
        if tab.MiddleDisabled then tab.MiddleDisabled:SetAlpha(0) end
        if tab.RightDisabled then tab.RightDisabled:SetAlpha(0) end
        if tab.LeftActive then tab.LeftActive:SetAlpha(0) end
        if tab.MiddleActive then tab.MiddleActive:SetAlpha(0) end
        if tab.RightActive then tab.RightActive:SetAlpha(0) end
        if tab.LeftHighlight then tab.LeftHighlight:SetAlpha(0) end
        if tab.MiddleHighlight then tab.MiddleHighlight:SetAlpha(0) end
        if tab.RightHighlight then tab.RightHighlight:SetAlpha(0) end

        local highlight = tab.GetHighlightTexture and tab:GetHighlightTexture()
        if highlight then highlight:SetAlpha(0) end

        SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
        local tabBackdrop = SkinBase.GetBackdrop(tab)
        if tabBackdrop then
            tabBackdrop:ClearAllPoints()
            tabBackdrop:SetPoint("TOPLEFT", 3, -3)
            tabBackdrop:SetPoint("BOTTOMRIGHT", -3, 0)
        end

        SkinBase.MarkStyled(tab)
    end

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })
end

local function GetCharacterFrameSelectedTab()
    if not CharacterFrame then return nil end
    if PanelTemplates_GetSelectedTab then
        local selected = PanelTemplates_GetSelectedTab(CharacterFrame)
        if selected then return selected end
    end
    return CharacterFrame.selectedTab
end

local function UpdateCharacterFrameTabSelectedState()
    local selectedTab = GetCharacterFrameSelectedTab()

    for i = 1, 3 do
        local tab = _G["CharacterFrameTab" .. i]
        local bd = tab and SkinBase.GetBackdrop(tab)
        local sc = tab and SkinBase.GetFrameData(tab, "skinColor")
        local bg = tab and SkinBase.GetFrameData(tab, "bgColor")
        if bd and sc and bg then
            local tabID = tab.GetID and tab:GetID()
            local isSelected = selectedTab == i or selectedTab == tabID
            if isSelected then
                bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
                bd:SetBackdropColor(math.min(bg[1] + 0.10, 1), math.min(bg[2] + 0.10, 1), math.min(bg[3] + 0.10, 1), 1)
            else
                bd:SetBackdropBorderColor(sc[1] * 0.5, sc[2] * 0.5, sc[3] * 0.5, sc[4] * 0.6)
                bd:SetBackdropColor(bg[1], bg[2], bg[3], 0.7)
            end
        end
    end
end

local function SkinCharacterFrameTabs()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    for i = 1, 3 do
        local tab = _G["CharacterFrameTab" .. i]
        if tab then
            StyleCharacterFrameTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    if not characterTabsHooked and PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", function(frame)
            if frame == CharacterFrame then
                C_Timer.After(0, SkinCharacterFrameTabs)
            end
        end)
        characterTabsHooked = true
    end

    UpdateCharacterFrameTabSelectedState()
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
        if child.Name then
            child.Name:SetFont(fontPath, 13, "")
            child.Name:SetTextColor(sr, sg, sb, 1)
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

    -- Skin reputation bar
    local ReputationBar = child.Content and child.Content.ReputationBar
    if ReputationBar then
        ReputationBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")

        if ReputationBar.BarText then
            ReputationBar.BarText:SetFont(fontPath, 10, "")
            ReputationBar.BarText:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3], 1)
        end

        -- Create backdrop for rep bar
        if not SkinBase.GetFrameData(ReputationBar, "backdrop") then
            local backdrop = CreateFrame("Frame", nil, ReputationBar:GetParent(), "BackdropTemplate")
            backdrop:SetFrameLevel(ReputationBar:GetFrameLevel())
            backdrop:SetPoint("TOPLEFT", ReputationBar, "TOPLEFT", -2, 2)
            backdrop:SetPoint("BOTTOMRIGHT", ReputationBar, "BOTTOMRIGHT", 2, -2)
            local repPx = QUICore:GetPixelSize(backdrop)
            local repEdge2 = 2 * repPx
            backdrop:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = repEdge2,
            })
            backdrop:SetBackdropColor(0, 0, 0, 0.9)
            backdrop:SetBackdropBorderColor(sr, sg, sb, 1)
            backdrop:Show()
            SkinBase.SetFrameData(ReputationBar, "backdrop", backdrop)
        end

        if child.Content.Name then
            child.Content.Name:SetFont(fontPath, 11, "")
        end
    end

    -- Skin collapse button
    local ToggleCollapseButton = child.ToggleCollapseButton
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
        if child.Name then
            child.Name:SetFont(fontPath, 13, "")
            child.Name:SetTextColor(sr, sg, sb, 1)
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

    -- Style currency icon
    local CurrencyIcon = child.Content and child.Content.CurrencyIcon
    if CurrencyIcon then
        CurrencyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        if not iconBorders[CurrencyIcon] then
            local border = CreateFrame("Frame", nil, CurrencyIcon:GetParent(), "BackdropTemplate")
            local drawLayer = CurrencyIcon.GetDrawLayer and CurrencyIcon:GetDrawLayer()
            border:SetFrameLevel((drawLayer == "OVERLAY") and child:GetFrameLevel() + 2 or child:GetFrameLevel() + 1)
            border:SetPoint("TOPLEFT", CurrencyIcon, "TOPLEFT", -1, 1)
            border:SetPoint("BOTTOMRIGHT", CurrencyIcon, "BOTTOMRIGHT", 1, -1)
            local curPx = QUICore:GetPixelSize(border)
            border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = curPx,
            })
            border:SetBackdropBorderColor(sr, sg, sb, 1)
            iconBorders[CurrencyIcon] = border
        end
    end

    -- Style name and count
    if child.Content then
        if child.Content.Name then
            child.Content.Name:SetFont(fontPath, 11, "")
        end
        if child.Content.Count then
            child.Content.Count:SetFont(fontPath, 11, "")
        end
    end

    -- Skin collapse button
    local ToggleCollapseButton = child.ToggleCollapseButton
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

    -- Hook ScrollBox updates for reputation (debounced to avoid timer spam during rapid scrolling)
    local _repUpdatePending = false
    if ReputationFrame and ReputationFrame.ScrollBox then
        -- TAINT SAFETY: Defer to break taint chain from secure Update context.
        hooksecurefunc(ReputationFrame.ScrollBox, "Update", function(frame)
            if _repUpdatePending then return end
            _repUpdatePending = true
            C_Timer.After(0, function()
                _repUpdatePending = false
                if IsSkinningEnabled() then
                    frame:ForEachFrame(SkinReputationEntry)
                end
            end)
        end)
    end

    -- Hook ScrollBox updates for currency (debounced to avoid timer spam during rapid scrolling)
    local _tokenUpdatePending = false
    if TokenFrame and TokenFrame.ScrollBox then
        -- TAINT SAFETY: Defer to break taint chain from secure Update context.
        hooksecurefunc(TokenFrame.ScrollBox, "Update", function(frame)
            if _tokenUpdatePending then return end
            _tokenUpdatePending = true
            C_Timer.After(0, function()
                _tokenUpdatePending = false
                if IsSkinningEnabled() then
                    frame:ForEachFrame(SkinCurrencyEntry)
                end
            end)
        end)
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
        customBg:SetBackdropColor(bgr, bgg, bgb, bga)
        customBg:SetBackdropBorderColor(sr, sg, sb, sa)
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
                repBd:SetBackdropBorderColor(sr, sg, sb, 1)
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
                iconBorders[CurrencyIcon]:SetBackdropBorderColor(sr, sg, sb, 1)
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

-- Skin individual equipment set entry
local function SkinEquipmentSetEntry(entry)
    if skinnedEntries[entry] then return end

    local sr, sg, sb, sa = GetSkinColors()
    local fontPath = GetFontPath()

    -- Style the entry text
    if entry.text then
        entry.text:SetFont(fontPath, 11, "")
        entry.text:SetTextColor(0.9, 0.9, 0.9, 1)
    end

    -- Style the icon with a border
    if entry.icon and not iconBorders[entry.icon] then
        entry.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = CreateFrame("Frame", nil, entry, "BackdropTemplate")
        border:SetPoint("TOPLEFT", entry.icon, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", entry.icon, "BOTTOMRIGHT", 1, -1)
        local eqPx = QUICore:GetPixelSize(border)
        border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = eqPx,
        })
        border:SetBackdropBorderColor(sr, sg, sb, 1)
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
    local fontPath = GetFontPath()

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
    local btnPx = QUICore:GetPixelSize(btn)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = btnPx,
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    btn:SetBackdropBorderColor(sr, sg, sb, 0.5)

    -- Style text
    local text = btn:GetFontString()
    if text then
        text:SetFont(fontPath, 11, "")
        text:SetTextColor(0.9, 0.9, 0.9, 1)
    end

    -- Restore width
    btn:SetWidth(origWidth)

    -- Hover effects (capture colors at hook time for consistency)
    btn:HookScript("OnEnter", function(self)
        local r, g, b = GetSkinColors()
        self:SetBackdropBorderColor(r, g, b, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        local r, g, b = GetSkinColors()
        self:SetBackdropBorderColor(r, g, b, 0.5)
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
        local popPx = QUICore:GetPixelSize(popup)
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = popPx,
        })
        skinnedEntries[popup] = true
    end
    popup:SetBackdropColor(bgr, bgg, bgb, bga)
    popup:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Skin title
    if popup.title then
        popup.title:SetFont(fontPath, 12, "")
        popup.title:SetTextColor(sr, sg, sb, 1)
    end

    -- Skin equipment set entries
    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if pane and pane.ScrollBox then
        -- Hook ScrollBox to skin entries as they're created/recycled
        if not hookedScrollBoxes[pane.ScrollBox] then
            -- TAINT SAFETY: Defer to break taint chain from secure Update context.
            hooksecurefunc(pane.ScrollBox, "Update", function(scrollBox)
                C_Timer.After(0, function()
                    if IsSkinningEnabled() then
                        scrollBox:ForEachFrame(SkinEquipmentSetEntry)
                    end
                end)
            end)
            hookedScrollBoxes[pane.ScrollBox] = true
        end
        -- Initial skin
        pane.ScrollBox:ForEachFrame(SkinEquipmentSetEntry)
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
    popup:SetBackdropColor(bgr, bgg, bgb, bga)
    popup:SetBackdropBorderColor(sr, sg, sb, sa)
    if popup.title then
        popup.title:SetTextColor(sr, sg, sb, 1)
    end

    -- Update entries
    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if pane and pane.ScrollBox then
        pane.ScrollBox:ForEachFrame(function(entry)
            if not skinnedEntries[entry] then return end
            if entry.icon and iconBorders[entry.icon] then
                iconBorders[entry.icon]:SetBackdropBorderColor(sr, sg, sb, 1)
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
        PaperDollFrameEquipSet:SetBackdropBorderColor(sr, sg, sb, 0.5)
    end
    if PaperDollFrameSaveSet and skinnedEntries[PaperDollFrameSaveSet] then
        PaperDollFrameSaveSet:SetBackdropBorderColor(sr, sg, sb, 0.5)
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
        button.text:SetFont(fontPath, 12, "")
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
        local pop2Px = QUICore:GetPixelSize(popup)
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pop2Px,
            insets = { left = pop2Px, right = pop2Px, top = pop2Px, bottom = pop2Px }
        })
        popup:SetBackdropColor(bgr, bgg, bgb, bga)
        popup:SetBackdropBorderColor(sr, sg, sb, sa)

        -- Style title text
        if popup.title then
            popup.title:SetFont(fontPath, 14, "")
            popup.title:SetTextColor(sr, sg, sb, 1)
        end

        skinnedEntries[popup] = true
    end

    -- Skip pane if already skinned
    if skinnedEntries[pane] then return end

    -- Hide pane background (uses popup's custom bg)
    if pane.Bg then pane.Bg:Hide() end

    -- Style ScrollBox entries
    if pane.ScrollBox then
        -- Hook to skin entries as they're created
        -- TAINT SAFETY: Defer to break taint chain from secure Update context.
        hooksecurefunc(pane.ScrollBox, "Update", function(scrollBox)
            C_Timer.After(0, function()
                scrollBox:ForEachFrame(function(button)
                    SkinTitleEntry(button)
                end)
            end)
        end)

        -- Skin any existing entries
        pane.ScrollBox:ForEachFrame(function(button)
            SkinTitleEntry(button)
        end)
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
        popup:SetBackdropColor(bgr, bgg, bgb, bga)
        popup:SetBackdropBorderColor(sr, sg, sb, sa)
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
_G.QUI_CharacterFrameSkinning = {
    -- Configuration
    CONFIG = CONFIG,

    -- Core functions
    IsEnabled = IsSkinningEnabled,
    SetExtended = SetCharacterFrameBgExtended,
    Refresh = RefreshCharacterFrameColors,

    -- Skinning functions (called by qui_character.lua)
    SkinEquipmentManager = SkinEquipmentManager,
    SkinTitleManager = SkinTitleManagerPane,
}

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
local function InitializeCharacterFrameSkinning(self)
    C_Timer.After(0.1, function()
        SetupCharacterFrameSkinning()
        SetupTitlePaneHook()
    end)
    if self then
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, addon)
    if (event == "ADDON_LOADED" and (addon == "Blizzard_CharacterFrame" or addon == "Blizzard_UIPanels_Game"))
        or (event == "PLAYER_LOGIN" and CharacterFrame and CharacterFrameTab1)
    then
        InitializeCharacterFrameSkinning(self)
    end
end)

if CharacterFrame and CharacterFrameTab1 then
    InitializeCharacterFrameSkinning(frame)
end
