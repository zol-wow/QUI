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
        if scrollParent then
            GUI:AttachSidebarSectionScrollSpy(scrollParent)
        end

        GUI:RegisterSectionNavigateHandler(tabIndex, subTabIndex, title, function()
            if section.SetExpanded then
                section:SetExpanded(true)
            end
            return false
        end)
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

    local bulkActions = CreateFrame("Frame", nil, parent)
    bulkActions:SetHeight(controlsHeight)
    bulkActions:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, startY)
    bulkActions:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)

    local closeAllBtn
    local expandAllBtn = GUI:CreateButton(bulkActions, "Expand All", 110, 24, function()
        for _, section in ipairs(sections) do
            if section.SetExpanded then
                section:SetExpanded(true, true)
            end
        end
        relayout()
    end)
    expandAllBtn:SetPoint("TOPRIGHT", bulkActions, "TOPRIGHT", -96, -2)

    closeAllBtn = GUI:CreateButton(bulkActions, "Close All", 90, 24, function()
        for _, section in ipairs(sections) do
            if section.SetExpanded then
                section:SetExpanded(false, true)
            end
        end
        relayout()
    end)
    closeAllBtn:SetPoint("TOPRIGHT", bulkActions, "TOPRIGHT", 0, -2)

    local function CreateCollapsible(title, contentHeight, buildFunc)
        local suppressedAtCreation = GUI._suppressSearchRegistration
        local searchContext = {
            tabIndex = GUI._searchContext.tabIndex,
            tabName = GUI._searchContext.tabName,
            subTabIndex = GUI._searchContext.subTabIndex,
            subTabName = GUI._searchContext.subTabName,
        }
        local stateKey
        if searchContext.tabIndex and title and title ~= "" then
            stateKey = table.concat({
                tostring(searchContext.tabIndex or 0),
                tostring(searchContext.subTabIndex or 0),
                title,
            }, ":")
        end
        if title and not suppressedAtCreation then
            GUI:SetSearchSection(title)
        end

        local section = CreateFrame("Frame", nil, parent)
        section:SetHeight(COLLAPSIBLE_HEADER_HEIGHT)
        section._sectionTitle = title
        section._searchContext = searchContext
        section._stateKey = stateKey
        section._hasStoredState = stateKey and GUI._optionsCollapsibleStates[stateKey] ~= nil or false

        local btn = CreateFrame("Button", nil, section)
        btn:SetPoint("TOPLEFT", 0, 0)
        btn:SetPoint("TOPRIGHT", 0, 0)
        btn:SetHeight(COLLAPSIBLE_HEADER_HEIGHT)

        local ar, ag, ab = GetCollapsibleAccent()
        local chevron = UIKit and UIKit.CreateChevronCaret and UIKit.CreateChevronCaret(btn, {
            point = "LEFT",
            relativeTo = btn,
            relativePoint = "LEFT",
            xPixels = 2,
            yPixels = 0,
            sizePixels = 10,
            lineWidthPixels = 6,
            lineHeightPixels = 1,
            expanded = false,
            collapsedDirection = "right",
            r = ar,
            g = ag,
            b = ab,
            a = 1,
        }) or btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if not (UIKit and UIKit.CreateChevronCaret) then
            chevron:SetPoint("LEFT", 2, 0)
            chevron:SetTextColor(ar, ag, ab, 1)
            chevron:SetText(">")
        end

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
        label:SetTextColor(ar, ag, ab, 1)
        label:SetText(title)

        local underline = btn:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(1)
        underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        underline:SetColorTexture(ar, ag, ab, 0.3)

        local bodyClip = CreateFrame("ScrollFrame", nil, section)
        bodyClip:SetPoint("TOPLEFT", 0, -COLLAPSIBLE_HEADER_HEIGHT)
        bodyClip:SetPoint("RIGHT", section, "RIGHT", 0, 0)
        bodyClip:SetHeight(0)
        bodyClip:Hide()

        local body = CreateFrame("Frame", nil, bodyClip)
        body:SetHeight(contentHeight)
        body:SetWidth(1)
        bodyClip:SetScrollChild(body)
        bodyClip:SetScript("OnSizeChanged", function(self, width)
            body:SetWidth(math.max(width or 1, 1))
        end)
        body:SetAlpha(0)
        body._logicalSection = section
        bodyClip._logicalSection = section

        section._expanded = false
        section._contentHeight = contentHeight
        section._body = body
        section._bodyClip = bodyClip

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

            local childCount = body.GetNumChildren and body:GetNumChildren() or 0
            for i = 1, childCount do
                Accumulate(select(i, body:GetChildren()))
            end

            local regionCount = body.GetNumRegions and body:GetNumRegions() or 0
            for i = 1, regionCount do
                Accumulate(select(i, body:GetRegions()))
            end

            if maxOffset <= 0 then
                return nil
            end
            return math.ceil(maxOffset + 8)
        end

        local function RefreshContentHeight()
            if type(body._contentHeight) == "number" and body._contentHeight > 0 then
                section._contentHeight = math.max(section._contentHeight or 0, body._contentHeight)
                body._contentHeight = nil
            end
            if type(bodyClip._contentHeight) == "number" and bodyClip._contentHeight > 0 then
                section._contentHeight = math.max(section._contentHeight or 0, bodyClip._contentHeight)
                bodyClip._contentHeight = nil
            end

            local measuredHeight = MeasureBodyContentHeight()
            if measuredHeight and measuredHeight > 0 then
                section._contentHeight = math.max(section._contentHeight or 0, measuredHeight)
            end

            body:SetHeight(section._contentHeight or contentHeight)
        end

        local function ApplyExpandedState(currentHeight)
            local height = math.max(0, math.min(section._contentHeight, currentHeight or 0))
            bodyClip:SetHeight(height)
            section:SetHeight(COLLAPSIBLE_HEADER_HEIGHT + height)
        end

        section.SetExpanded = function(self, expanded, skipRelayout)
            section._expanded = expanded and true or false
            if stateKey then
                GUI._optionsCollapsibleStates[stateKey] = section._expanded
            end
            if UIKit and UIKit.SetChevronCaretExpanded then
                UIKit.SetChevronCaretExpanded(chevron, section._expanded)
            else
                chevron:SetText(section._expanded and "v" or ">")
            end

            RefreshContentHeight()
            local targetHeight = section._expanded and section._contentHeight or 0
            local currentHeight = bodyClip:GetHeight() or 0

            if section._expanded then
                bodyClip:Show()
                body:SetAlpha(skipRelayout and 1 or body:GetAlpha())
            end

            if skipRelayout or not (UIKit and UIKit.AnimateValue and UIKit.CancelValueAnimation) then
                if UIKit and UIKit.CancelValueAnimation then
                    UIKit.CancelValueAnimation(section, "optionsCollapsible")
                end
                ApplyExpandedState(targetHeight)
                body:SetAlpha(section._expanded and 1 or 0)
                if not section._expanded then
                    bodyClip:Hide()
                end
                if not skipRelayout then
                    relayout()
                end
                return
            end

            UIKit.CancelValueAnimation(section, "optionsCollapsible")
            UIKit.AnimateValue(section, "optionsCollapsible", {
                fromValue = currentHeight,
                toValue = targetHeight,
                duration = (GUI and GUI._sidebarAnimDuration) or 0.16,
                onUpdate = function(_, progressHeight)
                    local totalRange = math.max(section._contentHeight, 1)
                    local ratio = math.max(0, math.min(1, progressHeight / totalRange))
                    ApplyExpandedState(progressHeight)
                    body:SetAlpha(ratio)
                    relayout()
                end,
                onFinish = function(_, finalHeight)
                    ApplyExpandedState(finalHeight)
                    body:SetAlpha(section._expanded and 1 or 0)
                    if not section._expanded then
                        bodyClip:Hide()
                    end
                    relayout()
                end,
            })
        end

        btn:SetScript("OnClick", function()
            section:SetExpanded(not section._expanded)
        end)

        btn:SetScript("OnEnter", function()
            label:SetTextColor(1, 1, 1, 1)
            if UIKit and UIKit.SetChevronCaretColor then
                UIKit.SetChevronCaretColor(chevron, 1, 1, 1, 1)
            else
                chevron:SetTextColor(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function()
            local lr, lg, lb = GetCollapsibleAccent()
            label:SetTextColor(lr, lg, lb, 1)
            if UIKit and UIKit.SetChevronCaretColor then
                UIKit.SetChevronCaretColor(chevron, lr, lg, lb, 1)
            else
                chevron:SetTextColor(lr, lg, lb, 1)
            end
        end)

        buildFunc(body)
        RefreshContentHeight()
        if stateKey and GUI._optionsCollapsibleStates[stateKey] then
            section:SetExpanded(true, true)
        end
        C_Timer.After(0, function()
            if not section or not body then return end
            RefreshContentHeight()
            if section._expanded then
                ApplyExpandedState(section._contentHeight)
                relayout()
            end
        end)
        table.insert(sections, section)
        return section
    end

    return sections, relayout, CreateCollapsible
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
