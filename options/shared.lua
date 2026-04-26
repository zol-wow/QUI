--[[
    QUI Options - Shared Infrastructure
    Contains constants, helper functions, and refresh callbacks used across all option pages.
    Must load after qui_gui.lua and before individual option page files.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local QUICore = ns.Addon
local UIKit = ns.UIKit
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- CONSTANTS - Match panel width (750px panel)
---------------------------------------------------------------------------
local ROW_GAP = 28
local SECTION_GAP = 38
local SECTION_HEADER_GAP = 46  -- Section header height + spacing below underline
local PADDING = 15  -- Standard left/right padding for all content
local SLIDER_HEIGHT = 65  -- Standard height for slider widgets

-- Mouse wheel scroll speed (pixels per tick)
local SCROLL_STEP = 60
ns.SCROLL_STEP = SCROLL_STEP

-- Midnight-safe scroll value helpers
local function GetSafeVerticalScrollRange(scrollFrame)
    local ok, maxScroll = pcall(scrollFrame.GetVerticalScrollRange, scrollFrame)
    if not ok then return 0 end
    local ok2, safeMax = pcall(function() return math.max(0, maxScroll or 0) end)
    return ok2 and safeMax or 0
end
ns.GetSafeVerticalScrollRange = GetSafeVerticalScrollRange

local function GetSafeVerticalScroll(scrollFrame)
    local ok, currentScroll = pcall(scrollFrame.GetVerticalScroll, scrollFrame)
    if not ok then return 0 end
    local ok2, safeCurrent = pcall(function() return currentScroll + 0 end)
    return ok2 and safeCurrent or 0
end

function ns.ApplyScrollWheel(scrollFrame)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = GetSafeVerticalScroll(self)
        local maxScroll = GetSafeVerticalScrollRange(self)
        local okNewScroll, newScroll = pcall(function()
            return math.max(0, math.min(currentScroll - (delta * SCROLL_STEP), maxScroll))
        end)
        if okNewScroll then
            pcall(self.SetVerticalScroll, self, newScroll)
        end
    end)
end

-- Shared chat formatter for import success/failure feedback.
-- showReloadHint is optional and only used by profile imports.
function ns.PrintImportFeedback(ok, message, showReloadHint)
    if ok then
        print("|cff60A5FAQUI:|r " .. (message or "Import successful"))
        if showReloadHint then
            print("|cff60A5FAQUI:|r Please type |cFFFFD700/reload|r to apply changes.")
        end
        return
    end

    local err = tostring(message or "Import failed")
    print("|cffff4d4dQUI:|r Import failed.")

    -- Make dense validator output readable in chat.
    err = err:gsub("^Import failed:%s*", "")
    err = err:gsub("%s*;%s*", "\n")
    err = err:gsub("%s+%-%s+", "\n")

    local lineCount = 0
    for line in err:gmatch("[^\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            lineCount = lineCount + 1
            if lineCount <= 6 then
                print("|cffff7a7aQUI:|r - " .. line)
            elseif lineCount == 7 then
                print("|cffff7a7aQUI:|r - (additional details omitted)")
                break
            end
        end
    end
end

-- Nine-point anchor options (used for UI element positioning)
local NINE_POINT_ANCHOR_OPTIONS = {
    {value = "TOPLEFT", text = "Top Left"},
    {value = "TOP", text = "Top"},
    {value = "TOPRIGHT", text = "Top Right"},
    {value = "LEFT", text = "Left"},
    {value = "CENTER", text = "Center"},
    {value = "RIGHT", text = "Right"},
    {value = "BOTTOMLEFT", text = "Bottom Left"},
    {value = "BOTTOM", text = "Bottom"},
    {value = "BOTTOMRIGHT", text = "Bottom Right"},
}

---------------------------------------------------------------------------
-- QUAZII RECOMMENDED FPS SETTINGS (58 CVars)
---------------------------------------------------------------------------
local QUAZII_FPS_CVARS = {
    -- Graphics Tab
    ["vsync"] = "0",
    ["LowLatencyMode"] = "3",
    ["MSAAQuality"] = "0",
    ["ffxAntiAliasingMode"] = "0",
    ["alphaTestMSAA"] = "1",
    ["cameraFov"] = "90",

    -- Graphics Quality (Base)
    ["graphicsQuality"] = "9",
    ["graphicsShadowQuality"] = "0",
    ["graphicsLiquidDetail"] = "1",
    ["graphicsParticleDensity"] = "5",
    ["graphicsSSAO"] = "0",
    ["graphicsDepthEffects"] = "0",
    ["graphicsComputeEffects"] = "0",
    ["graphicsOutlineMode"] = "1",
    ["OutlineEngineMode"] = "1",
    ["graphicsTextureResolution"] = "2",
    ["graphicsSpellDensity"] = "0",
    ["spellClutter"] = "1",
    ["spellVisualDensityFilterSetting"] = "1",
    ["graphicsProjectedTextures"] = "1",
    ["projectedTextures"] = "1",
    ["graphicsViewDistance"] = "3",
    ["graphicsEnvironmentDetail"] = "0",
    ["graphicsGroundClutter"] = "0",

    -- Advanced Tab
    ["gxTripleBuffer"] = "0",
    ["textureFilteringMode"] = "5",
    ["graphicsRayTracedShadows"] = "0",
    ["rtShadowQuality"] = "0",
    ["ResampleQuality"] = "4",
    ["ffxSuperResolution"] = "1",
    ["VRSMode"] = "0",
    ["GxApi"] = "D3D12",
    ["physicsLevel"] = "0",
    ["maxFPS"] = "144",
    ["maxFPSBk"] = "60",
    ["targetFPS"] = "61",
    ["useTargetFPS"] = "0",
    ["ResampleSharpness"] = "0.2",
    ["Contrast"] = "75",
    ["Brightness"] = "50",
    ["Gamma"] = "1",

    -- Additional Optimizations
    ["particulatesEnabled"] = "0",
    ["clusteredShading"] = "0",
    ["volumeFogLevel"] = "0",
    ["reflectionMode"] = "0",
    ["ffxGlow"] = "0",
    ["farclip"] = "5000",
    ["horizonStart"] = "1000",
    ["horizonClip"] = "5000",
    ["lodObjectCullSize"] = "35",
    ["lodObjectFadeScale"] = "50",
    ["lodObjectMinSize"] = "0",
    ["doodadLodScale"] = "50",
    ["entityLodDist"] = "7",
    ["terrainLodDist"] = "350",
    ["TerrainLodDiv"] = "512",
    ["waterDetail"] = "1",
    ["rippleDetail"] = "0",
    ["weatherDensity"] = "3",
    ["entityShadowFadeScale"] = "15",
    ["groundEffectDist"] = "40",
    ["ResampleAlwaysSharpen"] = "1",

    -- Special Hacks
    ["cameraDistanceMaxZoomFactor"] = "2.6",
    ["CameraReduceUnexpectedMovement"] = "1",
}

---------------------------------------------------------------------------
-- HELPER: Get texture list from LSM
---------------------------------------------------------------------------
local LSM = ns.LSM

local function GetTextureList()
    local textures = {}
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            table.insert(textures, {value = name, text = name})
        end
    else
        textures = {{value = "Solid", text = "Solid"}}
    end
    return textures
end

-- Hidden frame for pre-warming fonts (forces WoW to load font files).
-- Created on demand and cleaned up after the font list is built to avoid
-- holding an off-screen frame + FontString in memory for the entire session.
local fontPrewarmFrame = nil
local _fontListCache = nil  -- cache the result so prewarm only happens once

local function GetFontList()
    -- Return cached list if already built (font list doesn't change mid-session)
    if _fontListCache then return _fontListCache end

    local fonts = {}
    if LSM then
        -- Create a hidden frame for pre-warming fonts if needed
        if not fontPrewarmFrame then
            fontPrewarmFrame = CreateFrame("Frame", nil, UIParent)
            fontPrewarmFrame:SetSize(1, 1)
            fontPrewarmFrame:SetPoint("TOPLEFT", -9999, 9999)  -- Off-screen
            fontPrewarmFrame.text = fontPrewarmFrame:CreateFontString(nil, "OVERLAY")
            fontPrewarmFrame.text:SetPoint("CENTER")
            fontPrewarmFrame.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")  -- Set default font first
            fontPrewarmFrame.text:SetText("A")  -- Need some text for font to load
        end

        for _, name in ipairs(LSM:List("font")) do
            local path = LSM:Fetch("font", name) or ""
            local pathLower = path:lower()

            -- Only allow fonts from WoW defaults, QUI, or SharedMedia
            local isWoWFont = pathLower:find("^fonts\\") ~= nil or pathLower:find("^fonts/") ~= nil
            local isQuaziiFont = pathLower:find("quaziiui") ~= nil
            local isSharedMediaFont = pathLower:find("sharedmedia") ~= nil

            if (isWoWFont or isQuaziiFont or isSharedMediaFont) and path ~= "" then
                -- Pre-warm the font by actually applying it (forces WoW to load the font file)
                local success = pcall(function()
                    fontPrewarmFrame.text:SetFont(path, 12, "")
                end)
                if success then
                    table.insert(fonts, {value = name, text = name})
                end
            end
        end
    else
        fonts = {{value = "Friz Quadrata TT", text = "Friz Quadrata TT"}}
    end

    -- Clean up prewarm frame after building the list (no longer needed)
    if fontPrewarmFrame then
        fontPrewarmFrame.text:SetText("")
        fontPrewarmFrame:Hide()
        fontPrewarmFrame = nil  -- allow GC
    end

    _fontListCache = fonts
    return fonts
end

local function GetSoundList()
    local sounds = {{value = "None", text = "None"}}
    if LSM then
        for _, name in ipairs(LSM:List("sound") or {}) do
            if name ~= "None" then
                table.insert(sounds, {value = name, text = name})
            end
        end
    end
    return sounds
end

---------------------------------------------------------------------------
-- HELPER: Create scrollable content frame
---------------------------------------------------------------------------
local function CreateScrollableContent(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 5)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())  -- Dynamic width based on scroll frame
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    content._hasContent = false  -- Track if any content added (for auto-spacing)

    -- Update content width when scroll frame resizes (for panel resize support)
    scrollFrame:SetScript("OnSizeChanged", function(self, width, height)
        content:SetWidth(width)
    end)

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)

        -- Style the thumb (safe operation)
        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8)  -- Subtle grey-blue
        end

        -- Hide arrow buttons (modern best practice)
        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end

        -- Auto-hide scrollbar when not needed
        scrollBar:HookScript("OnShow", function(self)
            C_Timer.After(0.066, function()
                local maxScroll = GetSafeVerticalScrollRange(scrollFrame)
                if maxScroll <= 1 then
                    self:Hide()
                end
            end)
        end)
    end
    
    ns.ApplyScrollWheel(scrollFrame)

    return scrollFrame, content
end

---------------------------------------------------------------------------
-- HELPER: Get database safely
---------------------------------------------------------------------------
local function GetDB()
    if QUICore and QUICore.db and QUICore.db.profile then
        return QUICore.db.profile
    end
    return nil
end

---------------------------------------------------------------------------
-- FPS SETTINGS FUNCTIONS
---------------------------------------------------------------------------
local function BackupCurrentFPSSettings()
    local db = GetDB()
    if not db then return false end
    local backup = {}
    for cvar, _ in pairs(QUAZII_FPS_CVARS) do
        local success, current = pcall(C_CVar.GetCVar, cvar)
        if success and current then
            backup[cvar] = current
        end
    end
    db.fpsBackup = backup
    return true
end

local function RestorePreviousFPSSettings()
    local db = GetDB()
    if not db then return false end
    if not db.fpsBackup then
        print("|cffFF6B6BQUI:|r No backup found. Apply FPS settings first to create a backup.")
        return false
    end

    local successCount = 0
    local failCount = 0
    for cvar, value in pairs(db.fpsBackup) do
        local ok = pcall(C_CVar.SetCVar, cvar, tostring(value))
        if ok then
            successCount = successCount + 1
        else
            failCount = failCount + 1
        end
    end

    -- Clear backup after successful restore
    db.fpsBackup = nil

    print("|cff60A5FAQUI:|r Restored " .. successCount .. " previous settings.")
    if failCount > 0 then
        print("|cffFF6B6BQUI:|r " .. failCount .. " settings could not be restored.")
    end
    return true
end

local function ApplyQuaziiFPSSettings()
    -- Backup current settings first
    BackupCurrentFPSSettings()

    local successCount = 0
    local failCount = 0

    for cvar, value in pairs(QUAZII_FPS_CVARS) do
        local success = pcall(function()
            C_CVar.SetCVar(cvar, value)
        end)

        if success then
            successCount = successCount + 1
        else
            failCount = failCount + 1
        end
    end

    print("|cff60A5FAQUI:|r Your previous settings have been backed up.")
    print("|cff60A5FAQUI:|r Applied " .. successCount .. " FPS settings. Use 'Restore Previous Settings' to undo.")
    if failCount > 0 then
        print("|cffFF6B6BQUI:|r " .. failCount .. " settings could not be applied (may require restart).")
    end
end

local function CheckCVarsMatch()
    local matchCount, totalCount = 0, 0
    for cvar, expectedVal in pairs(QUAZII_FPS_CVARS) do
        totalCount = totalCount + 1
        local currentVal = C_CVar.GetCVar(cvar)
        if currentVal == expectedVal then
            matchCount = matchCount + 1
        end
    end
    return matchCount == totalCount, matchCount, totalCount
end

---------------------------------------------------------------------------
-- HELPER: Refresh callbacks
---------------------------------------------------------------------------
local function RefreshMinimap()
    if QUICore and QUICore.Minimap and QUICore.Minimap.Refresh then QUICore.Minimap:Refresh() end
end

local function RefreshUIHider()
    if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end
end

local function RefreshUnitFrames(unit)
    if QUICore and QUICore.UnitFrames then
        -- If unit is a string (valid unit name), update that specific frame
        -- Otherwise (nil, boolean from checkbox, etc.), refresh all frames
        if type(unit) == "string" then
            QUICore.UnitFrames:UpdateUnitFrame(unit)
        else
            QUICore.UnitFrames:RefreshFrames()
        end
    end
end

local function RefreshBuffBorders()
    if _G.QUI_RefreshBuffBorders then
        _G.QUI_RefreshBuffBorders()
    end
end

local function RefreshCrosshair()
    if _G.QUI_RefreshCrosshair then
        _G.QUI_RefreshCrosshair()
    end
end

local function RefreshReticle()
    if _G.QUI_RefreshReticle then
        _G.QUI_RefreshReticle()
    end
end

local function RefreshRangeCheck()
    if _G.QUI_RefreshRangeCheck then
        _G.QUI_RefreshRangeCheck()
    end
end

---------------------------------------------------------------------------
-- HELPER: Pixel size (safe fallback)
---------------------------------------------------------------------------
local function SafeGetPixelSize(frame)
    local core = ns.Addon
    return (core and core.GetPixelSize and core:GetPixelSize(frame)) or 1
end

---------------------------------------------------------------------------
-- HELPER: Create a wrapped paragraph label (auto word-wrap)
---------------------------------------------------------------------------
local function CreateWrappedLabel(parent, text, size, color, maxWidth)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontPath = GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF"
    label:SetFont(fontPath, size or 12, "")
    label:SetTextColor(unpack(color or GUI.Colors.text))
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    label:SetNonSpaceWrap(true)
    if maxWidth then
        label:SetWidth(maxWidth)
    end
    return label
end

---------------------------------------------------------------------------
-- HELPER: Create a compact link item (icon + label + copy button)
---------------------------------------------------------------------------
local COPY_ICON = "|TInterface\\Buttons\\UI-GuildButton-PublicNote-Up:11|t "
local function CreateLinkItem(parent, label, url, iconR, iconG, iconB, iconTexture, popupTitle)
    local C = GUI.Colors
    local item = CreateFrame("Frame", nil, parent)
    item:SetHeight(22)

    local icon = item:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 0, 0)
    if iconTexture then
        icon:SetTexture(iconTexture)
        icon:SetVertexColor(iconR or 1, iconG or 1, iconB or 1)
    else
        icon:SetColorTexture(iconR or 1, iconG or 1, iconB or 1, 1)
    end

    local fontPath = GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF"
    local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(fontPath, 11, "")
    text:SetTextColor(C.text[1], C.text[2], C.text[3])
    text:SetText(label .. "  |cff999999" .. url .. "|r")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)

    local btn = CreateFrame("Button", nil, item, "BackdropTemplate")
    btn:SetSize(56, 18)
    btn:SetPoint("LEFT", text, "RIGHT", 8, 0)

    local px = SafeGetPixelSize(btn)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetFont(fontPath, 9, "")
    btnText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    btnText:SetText(COPY_ICON .. "COPY")
    btnText:SetPoint("CENTER")

    btn:SetScript("OnClick", function()
        if GUI and GUI.ShowExportPopup then
            GUI:ShowExportPopup(popupTitle or "Copy Link", url)
        end
        btnText:SetText("OPENED")
        C_Timer.After(2, function()
            if btnText then btnText:SetText(COPY_ICON .. "COPY") end
        end)
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)

    item.totalWidth = 14 + 6 + (text:GetStringWidth() or 200) + 8 + 56
    return item
end

---------------------------------------------------------------------------
-- EXPORT TO NAMESPACE
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- COLLAPSIBLE PAGE HELPER
-- Creates the boilerplate for a page with collapsible sections.
-- Returns: sections table, relayout function, CreateCollapsible builder
---------------------------------------------------------------------------
-- Accent color: read from GUI.Colors.accent so collapsible headers
-- update when the user changes the accent color via the theme picker.
local function GetCollapsibleAccent()
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        return GUI.Colors.accent[1], GUI.Colors.accent[2], GUI.Colors.accent[3]
    end
    return 0.376, 0.647, 0.980 -- fallback: Sky Blue
end
local COLLAPSIBLE_HEADER_HEIGHT = 24
local COLLAPSIBLE_FORM_ROW = 32

local function CreateCollapsiblePage(parent, pad, topOffset)
    local PAD = pad or PADDING
    local startY = topOffset or -10
    local sections = {}
    local controlsHeight = 28
    local controlsGap = 8
    local db = GetDB()
    if db then
        db.optionsPanelCollapsibleStates = db.optionsPanelCollapsibleStates or {}
        GUI._optionsCollapsibleStates = db.optionsPanelCollapsibleStates
    else
        GUI._optionsCollapsibleStates = GUI._optionsCollapsibleStates or {}
    end

    local function GetSectionRegistryKey(tabIndex, subTabIndex)
        return (tabIndex or 0) * 10000 + (subTabIndex or 0)
    end

    local function FindScrollParent(frame)
        local current = frame
        while current do
            if current.GetVerticalScroll and current.SetVerticalScroll then
                return current
            end
            current = current:GetParent()
        end
        return nil
    end

    local function RegisterCollapsibleSection(section)
        local title = section and section._sectionTitle
        local context = section and section._searchContext
        if not title or not context or not context.tabIndex then return end

        local tabIndex = context.tabIndex
        local subTabIndex = context.subTabIndex or 0
        local numKey = GetSectionRegistryKey(tabIndex, subTabIndex)
        local scrollParent = FindScrollParent(parent)

        GUI.SectionRegistry[numKey] = GUI.SectionRegistry[numKey] or {}
        GUI.SectionRegistryOrder[numKey] = GUI.SectionRegistryOrder[numKey] or {}
        if not GUI.SectionRegistry[numKey][title] then
            table.insert(GUI.SectionRegistryOrder[numKey], title)
        end
        GUI.SectionRegistry[numKey][title] = {
            frame = section,
            scrollParent = scrollParent,
            contentParent = parent,
        }
    end

    local function relayout()
        local cy = startY - controlsHeight - controlsGap
        for _, s in ipairs(sections) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, cy)
            s:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
            RegisterCollapsibleSection(s)
            cy = cy - s:GetHeight() - 4
        end
        parent:SetHeight(math.abs(cy) + 20)
    end

    -- V3: no Expand/Close All buttons — sections are always open.
    -- The bulk-action strip is dropped entirely; controlsHeight stays at 0 so
    -- relayout() starts at startY with no offset.
    controlsHeight = 0
    controlsGap = 0

    -- V3 card group: always-visible accent-dot header + subtle card body.
    -- Signature preserved for every tab-builder caller. Legacy fields kept
    -- for backwards compat (_expanded pinned true, _body, _sectionTitle).
    local function CreateCollapsible(title, contentHeight, buildFunc)
        local suppressedAtCreation = GUI._suppressSearchRegistration
        local searchContext = {
            tabIndex = GUI._searchContext.tabIndex,
            tabName = GUI._searchContext.tabName,
            subTabIndex = GUI._searchContext.subTabIndex,
            subTabName = GUI._searchContext.subTabName,
        }
        if title and not suppressedAtCreation then
            GUI:SetSearchSection(title)
        end

        local CARD_GAP = 6
        local CARD_PAD = 8

        local section = CreateFrame("Frame", nil, parent)
        section._sectionTitle = title
        section._searchContext = searchContext

        local ar, ag, ab = GetCollapsibleAccent()

        -- Header: accent dot + title + 1px accent underline
        local dot = section:CreateTexture(nil, "OVERLAY")
        dot:SetSize(4, 4)
        dot:SetPoint("TOPLEFT", section, "TOPLEFT", 2, -((COLLAPSIBLE_HEADER_HEIGHT - 4) / 2))
        dot:SetColorTexture(ar, ag, ab, 1)

        local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", dot, "RIGHT", 8, 0)
        label:SetTextColor(ar, ag, ab, 1)
        label:SetText(title)

        local underline = section:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(1)
        underline:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -COLLAPSIBLE_HEADER_HEIGHT)
        underline:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -COLLAPSIBLE_HEADER_HEIGHT)
        underline:SetColorTexture(ar, ag, ab, 0.3)

        -- Card surface: subtle bg fill + 1px pixel-perfect hairline border.
        -- UIKit.CreateBorderLines draws 4 OVERLAY textures each exactly 1
        -- physical pixel wide (PP.perfect / effectiveScale), so the border
        -- stays razor-crisp at any UI scale — no blurry edge files, no
        -- thick Blizzard tooltip border.
        local cardBg = CreateFrame("Frame", nil, section)
        cardBg:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(COLLAPSIBLE_HEADER_HEIGHT + CARD_GAP))
        cardBg:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", 0, 0)
        local fill = cardBg:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(cardBg)
        fill:SetColorTexture(1, 1, 1, 0.02)
        if ns.UIKit and ns.UIKit.CreateBorderLines then
            ns.UIKit.CreateBorderLines(cardBg)
            ns.UIKit.UpdateBorderLines(cardBg, 1, 1, 1, 1, 0.12, false)
        end

        -- Body: full section width so widget positioning math survives
        local body = CreateFrame("Frame", nil, section)
        body:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(COLLAPSIBLE_HEADER_HEIGHT + CARD_GAP + CARD_PAD))
        body:SetPoint("RIGHT", section, "RIGHT", 0, 0)
        body:SetHeight(contentHeight)
        body._logicalSection = section

        section._expanded = true
        section._contentHeight = contentHeight
        section._body = body

        local function MeasureBodyContentHeight()
            local bodyTop = body.GetTop and body:GetTop()
            if not bodyTop then return nil end
            local maxOffset = 0
            local function Accumulate(region)
                if not region or not region.GetBottom then return end
                if region.IsShown and not region:IsShown() then return end
                local bottom = region:GetBottom()
                if bottom then
                    maxOffset = math.max(maxOffset, bodyTop - bottom)
                end
            end
            for i = 1, (body.GetNumChildren and body:GetNumChildren() or 0) do
                Accumulate(select(i, body:GetChildren()))
            end
            for i = 1, (body.GetNumRegions and body:GetNumRegions() or 0) do
                Accumulate(select(i, body:GetRegions()))
            end
            if maxOffset <= 0 then return nil end
            return math.ceil(maxOffset + 4)
        end

        local function RefreshContentHeight()
            if type(body._contentHeight) == "number" and body._contentHeight > 0 then
                section._contentHeight = math.max(section._contentHeight or 0, body._contentHeight)
                body._contentHeight = nil
            end
            local measured = MeasureBodyContentHeight()
            if measured and measured > 0 then
                section._contentHeight = math.max(section._contentHeight or 0, measured)
            end
            local bh = section._contentHeight or contentHeight
            body:SetHeight(bh)
            section:SetHeight(COLLAPSIBLE_HEADER_HEIGHT + CARD_GAP + (CARD_PAD * 2) + bh)
        end
        section.RefreshContentHeight = RefreshContentHeight

        -- Legacy no-op shim: V3 sections are always expanded.
        section.SetExpanded = function(self, _expanded, skipRelayout)
            RefreshContentHeight()
            if not skipRelayout then relayout() end
        end

        buildFunc(body)
        RefreshContentHeight()
        C_Timer.After(0, function()
            if not section or not body then return end
            RefreshContentHeight()
            relayout()
        end)
        table.insert(sections, section)
        return section
    end

    return sections, relayout, CreateCollapsible
end

---------------------------------------------------------------------------
-- TILE PAGE (dual-column ready)
-- Drop-in replacement for CreateCollapsiblePage that delegates to
-- Utils.CreateCollapsible so the renderer's tile chrome adapter can apply
-- dual-column chrome. SectionRegistry wiring + GUI:SetSearchSection are
-- preserved so jump-to-section search keeps working.
---------------------------------------------------------------------------
local function CreateTilePage(parent, pad, topOffset)
    local PAD = pad or PADDING
    local startY = topOffset or -10
    local sections = {}
    local db = GetDB()
    if db then
        db.optionsPanelCollapsibleStates = db.optionsPanelCollapsibleStates or {}
        GUI._optionsCollapsibleStates = db.optionsPanelCollapsibleStates
    else
        GUI._optionsCollapsibleStates = GUI._optionsCollapsibleStates or {}
    end

    local function GetSectionRegistryKey(tabIndex, subTabIndex)
        return (tabIndex or 0) * 10000 + (subTabIndex or 0)
    end

    local function FindScrollParent(frame)
        local current = frame
        while current do
            if current.GetVerticalScroll and current.SetVerticalScroll then
                return current
            end
            current = current:GetParent()
        end
        return nil
    end

    local function RegisterCollapsibleSection(section)
        local title = section and section._sectionTitle
        local context = section and section._searchContext
        if not title or not context or not context.tabIndex then return end

        local tabIndex = context.tabIndex
        local subTabIndex = context.subTabIndex or 0
        local numKey = GetSectionRegistryKey(tabIndex, subTabIndex)
        local scrollParent = FindScrollParent(parent)

        GUI.SectionRegistry[numKey] = GUI.SectionRegistry[numKey] or {}
        GUI.SectionRegistryOrder[numKey] = GUI.SectionRegistryOrder[numKey] or {}
        if not GUI.SectionRegistry[numKey][title] then
            table.insert(GUI.SectionRegistryOrder[numKey], title)
        end
        GUI.SectionRegistry[numKey][title] = {
            frame = section,
            scrollParent = scrollParent,
            contentParent = parent,
        }
    end

    local function relayout()
        local cy = startY
        for _, s in ipairs(sections) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, cy)
            s:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
            RegisterCollapsibleSection(s)
            cy = cy - s:GetHeight() - 4
        end
        parent:SetHeight(math.abs(cy) + 20)
    end

    local function CreateCollapsible(title, contentHeight, buildFunc)
        local U = ns.QUI_LayoutMode_Utils
        if not U or not U.CreateCollapsible then return end

        local suppressedAtCreation = GUI._suppressSearchRegistration
        local searchContext = {
            tabIndex = GUI._searchContext.tabIndex,
            tabName = GUI._searchContext.tabName,
            subTabIndex = GUI._searchContext.subTabIndex,
            subTabName = GUI._searchContext.subTabName,
        }
        if title and not suppressedAtCreation then
            GUI:SetSearchSection(title)
        end

        local section = U.CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
        if section then
            section._sectionTitle = title
            section._searchContext = searchContext
        end
        return section
    end

    return sections, relayout, CreateCollapsible
end

---------------------------------------------------------------------------
-- INLINE COLLAPSIBLE HELPER
-- A lightweight, self-contained collapsible section that can be embedded
-- anywhere in a manually-positioned layout.  Stripped-down version of the
-- CreateCollapsible inner function without page-level features (sections
-- array, DB persistence, search registration, deferred re-measure).
--
-- Returns: section (outer frame), body (inner frame to build content into)
---------------------------------------------------------------------------
-- V3 card group variant of the inline collapsible. Always visible; the
-- onResize callback is fired after content remeasures so callers (import.lua)
-- can reflow their outer layout when the body grows or shrinks.
local function CreateInlineCollapsible(parent, title, contentHeight, onResize)
    local CARD_GAP = 6
    local CARD_PAD = 8

    local section = CreateFrame("Frame", nil, parent)

    local ar, ag, ab = GetCollapsibleAccent()

    -- Header: accent dot + title + 1px accent underline
    local dot = section:CreateTexture(nil, "OVERLAY")
    dot:SetSize(4, 4)
    dot:SetPoint("TOPLEFT", section, "TOPLEFT", 2, -((COLLAPSIBLE_HEADER_HEIGHT - 4) / 2))
    dot:SetColorTexture(ar, ag, ab, 1)

    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    label:SetTextColor(ar, ag, ab, 1)
    label:SetText(title)

    local underline = section:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -COLLAPSIBLE_HEADER_HEIGHT)
    underline:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -COLLAPSIBLE_HEADER_HEIGHT)
    underline:SetColorTexture(ar, ag, ab, 0.3)

    -- Card surface
    local cardBg = section:CreateTexture(nil, "BACKGROUND")
    cardBg:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(COLLAPSIBLE_HEADER_HEIGHT + CARD_GAP))
    cardBg:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", 0, 0)
    cardBg:SetColorTexture(1, 1, 1, 0.02)

    local function Hairline()
        local t = section:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 1, 1, 0.06)
        return t
    end
    local cardTop = Hairline(); cardTop:SetHeight(1)
    cardTop:SetPoint("TOPLEFT", cardBg, "TOPLEFT", 0, 0)
    cardTop:SetPoint("TOPRIGHT", cardBg, "TOPRIGHT", 0, 0)
    local cardBot = Hairline(); cardBot:SetHeight(1)
    cardBot:SetPoint("BOTTOMLEFT", cardBg, "BOTTOMLEFT", 0, 0)
    cardBot:SetPoint("BOTTOMRIGHT", cardBg, "BOTTOMRIGHT", 0, 0)
    local cardLeft = Hairline(); cardLeft:SetWidth(1)
    cardLeft:SetPoint("TOPLEFT", cardBg, "TOPLEFT", 0, 0)
    cardLeft:SetPoint("BOTTOMLEFT", cardBg, "BOTTOMLEFT", 0, 0)
    local cardRight = Hairline(); cardRight:SetWidth(1)
    cardRight:SetPoint("TOPRIGHT", cardBg, "TOPRIGHT", 0, 0)
    cardRight:SetPoint("BOTTOMRIGHT", cardBg, "BOTTOMRIGHT", 0, 0)

    -- Body
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(COLLAPSIBLE_HEADER_HEIGHT + CARD_GAP + CARD_PAD))
    body:SetPoint("RIGHT", section, "RIGHT", 0, 0)
    body:SetHeight(contentHeight)

    section._expanded = true
    section._contentHeight = contentHeight
    section._body = body

    local function MeasureBodyContentHeight()
        local bodyTop = body.GetTop and body:GetTop()
        if not bodyTop then return nil end
        local maxOffset = 0
        local function Accumulate(region)
            if not region or not region.GetBottom then return end
            if region.IsShown and not region:IsShown() then return end
            local bottom = region:GetBottom()
            if bottom then
                maxOffset = math.max(maxOffset, bodyTop - bottom)
            end
        end
        for i = 1, (body.GetNumChildren and body:GetNumChildren() or 0) do
            Accumulate(select(i, body:GetChildren()))
        end
        for i = 1, (body.GetNumRegions and body:GetNumRegions() or 0) do
            Accumulate(select(i, body:GetRegions()))
        end
        if maxOffset <= 0 then return nil end
        return math.ceil(maxOffset + 4)
    end

    local function RefreshContentHeight()
        -- Inline variant allows the content height to shrink (import preview
        -- rebuilds with fewer rows on each analysis).
        if type(body._contentHeight) == "number" and body._contentHeight > 0 then
            section._contentHeight = body._contentHeight
            body._contentHeight = nil
        end
        local measured = MeasureBodyContentHeight()
        if measured and measured > 0 then
            section._contentHeight = measured
        end
        local bh = section._contentHeight or contentHeight
        body:SetHeight(bh)
        section:SetHeight(COLLAPSIBLE_HEADER_HEIGHT + CARD_GAP + (CARD_PAD * 2) + bh)
        if onResize then onResize() end
    end
    section.RefreshContentHeight = RefreshContentHeight

    -- Legacy no-op shim: V3 sections are always expanded.
    section.SetExpanded = function(self, _expanded)
        RefreshContentHeight()
    end

    return section, body
end

ns.QUI_Options = {
    -- Constants
    PADDING = PADDING,
    NINE_POINT_ANCHOR_OPTIONS = NINE_POINT_ANCHOR_OPTIONS,
    QUAZII_FPS_CVARS = QUAZII_FPS_CVARS,

    -- Helper functions
    GetDB = GetDB,
    CreateScrollableContent = CreateScrollableContent,
    CreateCollapsiblePage = CreateCollapsiblePage,
    CreateTilePage = CreateTilePage,
    CreateInlineCollapsible = CreateInlineCollapsible,
    GetTextureList = GetTextureList,
    GetFontList = GetFontList,
    GetSoundList = GetSoundList,
    PrintImportFeedback = ns.PrintImportFeedback,
    SafeGetPixelSize = SafeGetPixelSize,
    CreateWrappedLabel = CreateWrappedLabel,
    CreateLinkItem = CreateLinkItem,
    -- FPS functions
    BackupCurrentFPSSettings = BackupCurrentFPSSettings,
    RestorePreviousFPSSettings = RestorePreviousFPSSettings,
    ApplyQuaziiFPSSettings = ApplyQuaziiFPSSettings,
    CheckCVarsMatch = CheckCVarsMatch,

    -- Refresh callbacks
    RefreshMinimap = RefreshMinimap,
    RefreshUIHider = RefreshUIHider,
    RefreshUnitFrames = RefreshUnitFrames,
    RefreshBuffBorders = RefreshBuffBorders,
    RefreshCrosshair = RefreshCrosshair,
    RefreshReticle = RefreshReticle,
    RefreshRangeCheck = RefreshRangeCheck,
}

--[[
    ns.QUI_Options.CreateAccentDotLabel(parent, text, yOffset)

    Creates an accent-dot section label. Used OUTSIDE of card groups to
    introduce a grouped set of settings below.

    parent: Frame to anchor to (uses TOPLEFT/TOPRIGHT).
    text: label text, rendered as provided.
    yOffset (number, optional): y offset from parent's top-left, default 0.

    Returns: container Frame with ._dot (Texture) and ._label (FontString).
]]
local function CreateAccentDotLabel(parent, text, yOffset)
    local ar, ag, ab = GetCollapsibleAccent()

    -- Grow the container to include the 1px separator line that
    -- delimits the section from its rows below.
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(22)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset or 0)
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset or 0)

    local dot = container:CreateTexture(nil, "OVERLAY")
    dot:SetSize(5, 5)
    dot:SetColorTexture(ar, ag, ab, 1)
    dot:SetPoint("LEFT", container, "LEFT", 0, 4)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local fpath = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(QUI.GUI:GetFontPath())
    label:SetFont(fpath or select(1, label:GetFont()), 12, "")
    label:SetPoint("LEFT", dot, "RIGHT", 7, 0)
    label:SetTextColor(ar, ag, ab, 1)
    label:SetText(text or "")

    -- 1px separator line under the label, spanning full container width.
    local sep = container:CreateTexture(nil, "BORDER")
    sep:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(ar, ag, ab, 0.3)

    container._dot = dot
    container._label = label
    container._separator = sep
    return container
end

ns.QUI_Options = ns.QUI_Options or {}
ns.QUI_Options.CreateAccentDotLabel = CreateAccentDotLabel

--[[
    ns.QUI_Options.CreateSettingsCardGroup(parent, yOffset)

    Creates a subtle-surface card group for settings rows. Populate with
    .AddRow(leftCell, rightCell) or .AddRow(fullWidthCell). Call .Finalize()
    after all rows are added to size the card and hide the trailing divider.

    parent: Frame to anchor to.
    yOffset (optional): y offset from parent TOPLEFT, default 0.

    Returns: table { frame, AddRow, Finalize, GetRowCount }
]]
local function CreateSettingsCardGroup(parent, yOffset)
    local C = QUI.GUI and QUI.GUI.Colors or {}

    -- "Section" pattern: NO card border, NO card fill. Rows stack directly,
    -- alternating row backgrounds give the rhythm. Much lighter visual weight
    -- than a boxed card. Center divider between the two columns.
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset or 0)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset or 0)
    -- Marker so settings_builders.lua's ApplyDualColumnLayout can detect
    -- a pre-rendered card group and skip its own row-pairing pass (which
    -- would scramble the already-paired rows + vertical-center the card
    -- inside a 32px row frame, causing content overlap).
    card._quiCardGroup = true

    local rows = {}
    local rowHeight = 32
    local padX = 2
    local cumulativeY = 0

    local function AddRow(leftChild, rightChild)
        local row = CreateFrame("Frame", nil, card)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", padX, cumulativeY)
        row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -padX, cumulativeY)
        row:SetHeight(rowHeight)

        -- Alternating row background tint — subtle (~3% white) on even rows,
        -- nothing on odd rows. Gives rhythm without the heavy card border.
        if (#rows % 2) == 1 then
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints(row)
            rowBg:SetColorTexture(1, 1, 1, 0.02)
            row._rowBg = rowBg
        end

        if rightChild then
            leftChild:SetParent(row)
            leftChild:ClearAllPoints()
            leftChild:SetPoint("LEFT", row, "LEFT", 12, 0)
            leftChild:SetPoint("RIGHT", row, "CENTER", -12, 0)
            rightChild:SetParent(row)
            rightChild:ClearAllPoints()
            rightChild:SetPoint("LEFT", row, "CENTER", 12, 0)
            rightChild:SetPoint("RIGHT", row, "RIGHT", -12, 0)

            -- 1px center divider between the two columns (matches reference)
            local cdiv = row:CreateTexture(nil, "ARTWORK")
            cdiv:SetPoint("TOP", row, "TOP", 0, -6)
            cdiv:SetPoint("BOTTOM", row, "BOTTOM", 0, 6)
            cdiv:SetWidth(1)
            cdiv:SetColorTexture(1, 1, 1, 0.05)
            row._centerDivider = cdiv
        else
            leftChild:SetParent(row)
            leftChild:ClearAllPoints()
            leftChild:SetPoint("LEFT", row, "LEFT", 12, 0)
            leftChild:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        end

        rows[#rows + 1] = row
        cumulativeY = cumulativeY - rowHeight
        return row
    end

    local function Finalize()
        card:SetHeight(math.abs(cumulativeY))
    end

    local function GetRowCount() return #rows end

    return {
        frame = card,
        AddRow = AddRow,
        Finalize = Finalize,
        GetRowCount = GetRowCount,
    }
end

ns.QUI_Options.CreateSettingsCardGroup = CreateSettingsCardGroup

--[[
    ns.QUI_Options.CreatePreviewArea(parent, yOffset, height)

    Creates a framed preview area — a bounded region at the top of a tile
    page where tile builders can populate a live preview of the feature
    being configured (e.g. action buttons for the Action Bars tile, a unit
    frame for the Unit Frames tile, a nameplate for Nameplates).

    Returns a Frame scoped to (yOffset, yOffset - height) with a subtle
    1px hairline border and slight bg fill so the preview area visually
    stands apart from the settings content below it.
]]
local function CreatePreviewArea(parent, yOffset, height)
    local C = QUI.GUI and QUI.GUI.Colors or {}
    local border = C.border or {1, 1, 1, 0.06}

    local preview = CreateFrame("Frame", nil, parent)
    preview:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset or 0)
    preview:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset or 0)
    preview:SetHeight(height or 90)

    local fill = preview:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(preview)
    fill:SetColorTexture(0, 0, 0, 0.2)

    if ns.UIKit and ns.UIKit.CreateBorderLines then
        ns.UIKit.CreateBorderLines(preview)
        ns.UIKit.UpdateBorderLines(preview, 1, border[1], border[2], border[3], 0.15, false)
    end

    -- Small "PREVIEW" label in the top-left
    local accent = C.accent or {0.204, 0.827, 0.6, 1}
    local lbl = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local fpath = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(QUI.GUI:GetFontPath())
    lbl:SetFont(fpath or select(1, lbl:GetFont()), 8, "")
    lbl:SetTextColor(accent[1], accent[2], accent[3], 0.7)
    lbl:SetPoint("TOPLEFT", preview, "TOPLEFT", 8, -6)
    local spaced = ("PREVIEW"):gsub(".", "%0 "):sub(1, -2)
    lbl:SetText(spaced)
    preview._label = lbl

    return preview
end
ns.QUI_Options.CreatePreviewArea = CreatePreviewArea

--[[
    ns.QUI_Options.BuildSettingRow(parent, labelText, widget, desc)

    Creates a single setting cell: label (left) + widget (right). Pass the
    returned Frame to CreateSettingsCardGroup.AddRow() as a left or right cell.

    parent: parent Frame (usually the card's frame).
    labelText: displayed label.
    widget: the control (toggle, slider, dropdown, etc.) to place on the right.
    desc (optional): secondary description text under the label.

    Returns: the cell Frame (with ._label, ._desc, ._widget, ._widgetLabel).
]]
local function BuildSettingRow(parent, labelText, widget, desc)
    local C = QUI.GUI and QUI.GUI.Colors or {}
    local textCol = C.text or {1, 1, 1, 1}
    local mutedCol = C.textMuted or {1, 1, 1, 0.45}

    local cell = CreateFrame("Frame", nil, parent)
    cell:SetHeight(28)

    local fpath = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(QUI.GUI:GetFontPath())

    local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetFont(fpath or select(1, label:GetFont()), 11, "")
    label:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
    label:SetPoint("LEFT", cell, "LEFT", 0, desc and 5 or 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetNonSpaceWrap(false)
    label:SetText(labelText or "")
    cell._label = label

    if desc then
        local d = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        d:SetFont(fpath or select(1, d:GetFont()), 9, "")
        d:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
        d:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        d:SetText(desc)
        cell._desc = d
    end

    if widget then
        widget:SetParent(cell)
        widget:ClearAllPoints()
        widget:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
        cell._widget = widget
        -- Constrain the label so it can't overlap the widget. Clip with "..."
        -- if the label is too long for the space left after the widget.
        label:SetPoint("RIGHT", widget, "LEFT", -6, 0)
    end

    local pins = ns.Settings and ns.Settings.Pins
    if pins and widget and type(pins.AttachSettingRow) == "function" then
        pins:AttachSettingRow(cell, widget, labelText)
    end

    cell._widgetLabel = labelText  -- For search jump-to-setting
    return cell
end

ns.QUI_Options.BuildSettingRow = BuildSettingRow

local function MergeOptions(base, extra)
    local merged = {}
    if type(base) == "table" then
        for key, value in pairs(base) do
            merged[key] = value
        end
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            merged[key] = value
        end
    end
    return merged
end

local function ClearDynamicContent(frame)
    if not frame then
        return
    end

    local gui = QUI and QUI.GUI
    if gui and type(gui.TeardownFrameTree) == "function" then
        gui:TeardownFrameTree(frame)
        return
    elseif gui and type(gui.CleanupWidgetTree) == "function" then
        gui:CleanupWidgetTree(frame)
    end

    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.Hide then child:Hide() end
            if child.ClearAllPoints then child:ClearAllPoints() end
            if child.SetParent then child:SetParent(nil) end
        end
    end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.Hide then region:Hide() end
            if region.SetParent then region:SetParent(nil) end
        end
    end
end

local function ResolveFeatureSearchContext(featureId, searchContext)
    local merged = MergeOptions(searchContext, nil)

    local Settings = ns.Settings
    local Nav = Settings and Settings.Nav
    local route = Nav and type(Nav.GetRoute) == "function" and Nav:GetRoute(featureId) or nil
    if type(route) == "table" then
        if type(route.tileId) == "string" and route.tileId ~= "" then
            merged.tileId = route.tileId
        end
        if route.subPageIndex ~= nil then
            merged.subPageIndex = route.subPageIndex
        end
    end

    return merged
end

local function BuildFeatureTabPage(tabContent, featureId, searchContext, renderOptions)
    local GUI = QUI and QUI.GUI
    if not GUI then return end
    local featureSearchContext = ResolveFeatureSearchContext(featureId, searchContext)
    if featureSearchContext then GUI:SetSearchContext(featureSearchContext) end
    ClearDynamicContent(tabContent)

    local PAD = ns.QUI_Options.PADDING
    local host = CreateFrame("Frame", nil, tabContent)
    host:SetPoint("TOPLEFT", PAD, -10)
    host:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    host:SetHeight(1)

    local Settings = ns.Settings
    local Renderer = Settings and Settings.Renderer
    if not Renderer or type(Renderer.RenderFeature) ~= "function" then return end

    local width = math.max(300, (tabContent:GetWidth() or 760) - (PAD * 2))
    local height = Renderer:RenderFeature(featureId, host, MergeOptions({
        surface = "tile",
        includePosition = false,
        tileLayout = true,
        width = width,
    }, renderOptions))

    tabContent:SetHeight((height or 80) + 20)
end

local function BuildFeatureDirectPage(tabContent, featureId, searchContext, renderOptions)
    local GUI = QUI and QUI.GUI
    if not GUI then return end
    local featureSearchContext = ResolveFeatureSearchContext(featureId, searchContext)
    if featureSearchContext then GUI:SetSearchContext(featureSearchContext) end
    ClearDynamicContent(tabContent)

    local Settings = ns.Settings
    local Renderer = Settings and Settings.Renderer
    if not Renderer or type(Renderer.RenderFeature) ~= "function" then return end

    local PAD = ns.QUI_Options.PADDING
    local width = math.max(300, (tabContent:GetWidth() or 760) - (PAD * 2))
    return Renderer:RenderFeature(featureId, tabContent, MergeOptions({
        surface = "tile",
        includePosition = false,
        tileLayout = true,
        width = width,
    }, renderOptions))
end

local BuildFeatureStackPage

local function GetRegisteredFeature(featureId)
    local Settings = ns.Settings
    local Registry = Settings and Settings.Registry
    if not Registry or type(Registry.GetFeature) ~= "function" then
        return nil
    end
    return Registry:GetFeature(featureId)
end

local function HasRegisteredFeature(featureId)
    return GetRegisteredFeature(featureId) ~= nil
end

ns.QUI_Options.HasFeature = HasRegisteredFeature

local function ShowUnavailableFeaturePage(body, label)
    local text = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 20, -20)
    text:SetText((label or "Settings") .. " unavailable.")
end

local function ReportFeatureTileIssue(message)
    if type(message) ~= "string" or message == "" then
        return
    end

    local isDev = (_G and _G.QUI_DEV) or (QUI and QUI.dev)
    if isDev then
        error(message, 3)
    end

    local handler = geterrorhandler and geterrorhandler()
    if type(handler) == "function" then
        handler(message)
    end
end

local function HasBuildFunc(value)
    if type(value) ~= "table" then
        return false
    end
    if value.buildFunc ~= nil then
        return true
    end
    for _, item in ipairs(value.subPages or {}) do
        if type(item) == "table" and item.buildFunc ~= nil then
            return true
        end
    end
    return false
end

local function ValidateFeatureReference(ownerLabel, featureId)
    if type(featureId) ~= "string" or featureId == "" then
        return false
    end
    if HasRegisteredFeature(featureId) then
        return true
    end
    ReportFeatureTileIssue(ownerLabel .. ": feature '" .. featureId .. "' is not registered")
    return false
end

local function ValidateFeatureReferences(ownerLabel, featureIds)
    if type(featureIds) ~= "table" then
        return false
    end
    local ok = #featureIds > 0
    for _, item in ipairs(featureIds) do
        local featureId = item
        if type(item) == "table" then
            featureId = item.key
        end
        ok = ValidateFeatureReference(ownerLabel, featureId) and ok
    end
    return ok
end

local function TryBuildFeaturePage(body, render, featureId, searchContext, fallback, renderOptions)
    if featureId and HasRegisteredFeature(featureId) and type(render) == "function" then
        render(body, featureId, searchContext, renderOptions)
        return true
    end

    if type(fallback) == "function" then
        fallback(body)
        return true
    end

    return false
end

local function RegisterNavRoutes(GUI, tileId, routes, defaultSubPageIndex)
    if not GUI or type(GUI.RegisterV2NavRoute) ~= "function" or type(routes) ~= "table" then
        return
    end

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            GUI:RegisterV2NavRoute(
                route.tabIndex,
                route.subTabIndex,
                route.tileId or tileId,
                route.subPageIndex ~= nil and route.subPageIndex or defaultSubPageIndex
            )
        end
    end
end

local function ResolvePageFeatureId(page)
    if type(page) ~= "table" then
        return nil
    end
    if type(page.featureId) == "string" and page.featureId ~= "" then
        return page.featureId
    end
    if type(page.id) == "string" and page.id ~= "" and HasRegisteredFeature(page.id) then
        return page.id
    end
    return nil
end

local function BuildFeaturePageBody(body, page, render)
    if type(page) ~= "table" then
        ShowUnavailableFeaturePage(body, "Settings")
        return
    end

    if type(page.featureIds) == "table" then
        if type(BuildFeatureStackPage) == "function" then
            BuildFeatureStackPage(body, page.featureIds, page.searchContext, page.renderOptions)
            return
        end
        ShowUnavailableFeaturePage(body, page.unavailableLabel or page.name or "Feature stack")
        return
    end

    local featureId = ResolvePageFeatureId(page)
    if featureId and TryBuildFeaturePage(
        body,
        render or BuildFeatureDirectPage,
        featureId,
        page.searchContext,
        nil,
        page.renderOptions
    ) then
        return
    end

    ShowUnavailableFeaturePage(body, page.unavailableLabel or page.name or featureId or "Settings")
end

local function RegisterFeatureTile(frame, spec)
    local GUI = QUI and QUI.GUI
    if not GUI or type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
        return
    end

    if HasBuildFunc(spec) then
        ReportFeatureTileIssue("RegisterFeatureTile(" .. spec.id .. "): buildFunc is not accepted")
        return
    end

    local hasSingle = type(spec.featureId) == "string" and spec.featureId ~= ""
    local hasSubPages = type(spec.subPages) == "table" and #spec.subPages > 0
    if hasSingle == hasSubPages then
        ReportFeatureTileIssue("RegisterFeatureTile(" .. spec.id .. "): provide exactly one of featureId or subPages")
        return
    end
    if hasSingle and not ValidateFeatureReference("RegisterFeatureTile(" .. spec.id .. ")", spec.featureId) then
        return
    end

    RegisterNavRoutes(GUI, spec.id, spec.navRoutes, hasSingle and 1 or nil)

    local feature = hasSingle and GetRegisteredFeature(spec.featureId) or nil
    local preview = feature and feature.preview
    local previewHeight = (preview and preview.height) or spec.previewHeight
    local previewBuild = (preview and preview.build) or spec.previewBuild or function() end
    if type(spec.preview) == "table" then
        previewHeight = spec.preview.height or previewHeight
        previewBuild = spec.preview.build or previewBuild
    end

    local tileConfig = {
        id = spec.id,
        icon = spec.icon,
        iconTexture = spec.iconTexture,
        name = spec.name,
        subtitle = spec.subtitle,
        isBottomItem = spec.isBottomItem,
        primaryCTA = spec.primaryCTA,
        relatedSettings = spec.relatedSettings,
        preview = previewHeight and {
            height = previewHeight,
            build = previewBuild,
        } or nil,
    }

    if hasSubPages then
        tileConfig.subPages = {}
        for index, subPage in ipairs(spec.subPages) do
            if type(subPage) == "table" then
                if subPage.buildFunc ~= nil then
                    ReportFeatureTileIssue("RegisterFeatureTile(" .. spec.id .. "): subpage buildFunc is not accepted")
                    return
                end

                local page = {
                    id = subPage.id,
                    name = subPage.name,
                    featureId = subPage.featureId,
                    featureIds = subPage.featureIds,
                    searchContext = subPage.searchContext,
                    renderOptions = subPage.renderOptions,
                    unavailableLabel = subPage.unavailableLabel,
                }
                if not page.featureId and not page.featureIds then
                    page.featureId = ResolvePageFeatureId(subPage)
                end
                if not page.featureId and not page.featureIds then
                    ReportFeatureTileIssue("RegisterFeatureTile(" .. spec.id .. "): subpage " .. tostring(index) .. " has no featureId/featureIds")
                    return
                end
                if page.featureId then
                    if not ValidateFeatureReference(
                        "RegisterFeatureTile(" .. spec.id .. ") subpage " .. tostring(index),
                        page.featureId
                    ) then
                        return
                    end
                elseif page.featureIds and not ValidateFeatureReferences(
                    "RegisterFeatureTile(" .. spec.id .. ") subpage " .. tostring(index),
                    page.featureIds
                ) then
                    return
                end

                RegisterNavRoutes(GUI, spec.id, subPage.navRoutes, index)

                local pageConfig = page
                tileConfig.subPages[index] = {
                    id = page.id,
                    name = page.name,
                    featureId = page.featureId,
                    featureIds = page.featureIds,
                    noScroll = subPage.noScroll,
                    buildFunc = function(body)
                        BuildFeaturePageBody(body, pageConfig, BuildFeatureTabPage)
                    end,
                }
            end
        end
    else
        tileConfig.featureId = spec.featureId
        tileConfig.noScroll = spec.noScroll ~= false
        tileConfig.buildFunc = function(body)
            BuildFeaturePageBody(body, spec, BuildFeatureDirectPage)
        end
    end

    GUI:AddFeatureTile(frame, tileConfig)
end

ns.QUI_Options.RegisterFeatureTile = RegisterFeatureTile

local function ResolveFeatureStackLabel(featureId, explicitLabel)
    if type(explicitLabel) == "string" and explicitLabel ~= "" then
        return explicitLabel
    end

    local feature = GetRegisteredFeature(featureId)
    local providerKey = feature and feature.providerKey
    if type(providerKey) ~= "string" or providerKey == "" then
        providerKey = featureId
    end

    local Settings = ns.Settings
    local RenderAdapters = Settings and Settings.RenderAdapters
    if RenderAdapters and type(RenderAdapters.GetProviderLabel) == "function" then
        local label = RenderAdapters.GetProviderLabel(providerKey)
        if type(label) == "string" and label ~= "" then
            return label
        end
    end

    return providerKey
end

BuildFeatureStackPage = function(tabContent, featureIds, searchContext, options)
    local GUI = QUI and QUI.GUI
    if not GUI then return end
    if searchContext then GUI:SetSearchContext(searchContext) end
    ClearDynamicContent(tabContent)

    local Settings = ns.Settings
    local Renderer = Settings and Settings.Renderer
    if not Renderer or type(Renderer.RenderFeature) ~= "function" then return end

    local PAD = 10
    local GAP = 20
    local HEADER_HEIGHT = 26
    local HEADER_TO_CARD_GAP = 6
    local C = (QUI and QUI.GUI and QUI.GUI.Colors) or {}
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
    local yOffset = -10
    local width = math.max(300, ((tabContent.GetWidth and tabContent:GetWidth()) or 760) - (PAD * 2))

    if type(featureIds) ~= "table" or #featureIds == 0 then
        tabContent:SetHeight(80)
        return
    end

    for _, item in ipairs(featureIds) do
        local featureId, explicitLabel
        if type(item) == "string" then
            featureId = item
        elseif type(item) == "table" and type(item.key) == "string" then
            featureId = item.key
            explicitLabel = item.label
        end

        if featureId and HasRegisteredFeature(featureId) then
            local featureSearchContext = ResolveFeatureSearchContext(featureId, searchContext)
            if featureSearchContext then
                GUI:SetSearchContext(featureSearchContext)
            end
            local label = ResolveFeatureStackLabel(featureId, explicitLabel)

            local titleRow = CreateFrame("Frame", nil, tabContent)
            titleRow:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, yOffset)
            titleRow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            titleRow:SetHeight(HEADER_HEIGHT)

            local dot = titleRow:CreateTexture(nil, "OVERLAY")
            dot:SetSize(6, 6)
            dot:SetPoint("LEFT", titleRow, "LEFT", 0, 1)
            dot:SetColorTexture(accent[1], accent[2], accent[3], 1)

            local text = titleRow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            text:SetPoint("LEFT", dot, "RIGHT", 10, 0)
            text:SetTextColor(1, 1, 1, 0.95)
            text:SetText(label)

            local underline = titleRow:CreateTexture(nil, "ARTWORK")
            underline:SetPoint("BOTTOMLEFT", titleRow, "BOTTOMLEFT", 0, 0)
            underline:SetPoint("BOTTOMRIGHT", titleRow, "BOTTOMRIGHT", 0, 0)
            underline:SetHeight(1)
            underline:SetColorTexture(accent[1], accent[2], accent[3], 0.5)

            if type(tabContent.RegisterSection) == "function" then
                tabContent:RegisterSection(featureId, label, titleRow)
            end

            yOffset = yOffset - HEADER_HEIGHT - HEADER_TO_CARD_GAP

            local host = CreateFrame("Frame", nil, tabContent)
            host:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, yOffset)
            host:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            host:SetHeight(1)

            local height = Renderer:RenderFeature(featureId, host, MergeOptions({
                surface = "tile",
                includePosition = false,
                tileLayout = true,
                width = width,
            }, options))
            if type(height) ~= "number" or height <= 0 then
                height = host.GetHeight and host:GetHeight() or 80
            end
            height = math.max(80, height)
            host:SetHeight(height)
            yOffset = yOffset - height - GAP
        end
    end

    tabContent:SetHeight(math.max(80, math.abs(yOffset) + 10))
end
