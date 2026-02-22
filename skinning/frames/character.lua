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
QUICore.CharacterSkinning = CharacterSkinning

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
local iconBorders = setmetatable({}, { __mode = "k" })  -- CurrencyIcon/entry.icon → border frame
local skinnedEntries = setmetatable({}, { __mode = "k" })  -- entry → true
local hookedScrollBoxes = setmetatable({}, { __mode = "k" })  -- ScrollBox → true (hooked for Update)
local titleHighlights = setmetatable({}, { __mode = "k" })  -- button → highlight texture

---------------------------------------------------------------------------
-- Helper: Get skin colors from QUI system
---------------------------------------------------------------------------
local function GetSkinColors()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor(settings, "characterFrame")
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColor()
    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

---------------------------------------------------------------------------
-- Helper: Get font path from settings
---------------------------------------------------------------------------
local function GetFontPath()
    return Helpers.GetGeneralFont()
end

---------------------------------------------------------------------------
-- Helper: Check if skinning is enabled
---------------------------------------------------------------------------
local function IsSkinningEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinCharacterFrame
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

    customBg:SetBackdropColor(bgr, bgg, bgb, bga)
    customBg:SetBackdropBorderColor(sr, sg, sb, sa)

    return customBg
end

---------------------------------------------------------------------------
-- Hide Blizzard decorative elements on CharacterFrame
---------------------------------------------------------------------------
local function HideBlizzardDecorations()
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    if CharacterFrame.Background then CharacterFrame.Background:Hide() end
    if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Hide() end
    if CharacterFrameBg then CharacterFrameBg:Hide() end
    if CharacterStatsPane then CharacterStatsPane:Hide() end
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

    -- Hook ScrollBox updates for reputation
    if ReputationFrame and ReputationFrame.ScrollBox then
        -- TAINT SAFETY: Defer to break taint chain from secure Update context.
        hooksecurefunc(ReputationFrame.ScrollBox, "Update", function(frame)
            C_Timer.After(0, function()
                if IsSkinningEnabled() then
                    frame:ForEachFrame(SkinReputationEntry)
                end
            end)
        end)
    end

    -- Hook ScrollBox updates for currency
    if TokenFrame and TokenFrame.ScrollBox then
        -- TAINT SAFETY: Defer to break taint chain from secure Update context.
        hooksecurefunc(TokenFrame.ScrollBox, "Update", function(frame)
            C_Timer.After(0, function()
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
            if IsSkinningEnabled() and not (PaperDollFrame and PaperDollFrame:IsShown()) then
                SetCharacterFrameBgExtended(false)
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
    if pane.ScrollBar then
        local scrollBar = pane.ScrollBar
        if scrollBar.Track then
            scrollBar.Track:SetAlpha(0.3)
        end
        if scrollBar.Thumb then
            scrollBar.Thumb:SetAlpha(0.5)
        end
    end

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

-- Legacy compatibility aliases (deprecated - use QUI_CharacterFrameSkinning table)
_G.QUI_RefreshCharacterFrameColors = RefreshCharacterFrameColors

-- Legacy global function aliases for qui_character.lua
_G.QUI_SkinEquipmentManager = SkinEquipmentManager
_G.QUI_SkinTitleManager = SkinTitleManagerPane
_G.QUI_SetCharacterFrameBgExtended = SetCharacterFrameBgExtended

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == "Blizzard_CharacterFrame" then
        C_Timer.After(0.1, function()
            SetupCharacterFrameSkinning()
            SetupTitlePaneHook()
        end)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
