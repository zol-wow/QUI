local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local QUICore = ns.Addon
local UIKit = ns.UIKit
local Helpers = ns.Helpers

local ROW_GAP = 28
local SECTION_GAP = 38
local SECTION_HEADER_GAP = 46
local PADDING = 15
local SLIDER_HEIGHT = 65

local SCROLL_STEP = 60
ns.SCROLL_STEP = SCROLL_STEP

local function GetSafeVerticalScrollRange(scrollFrame)
    local ok, maxScroll = pcall(scrollFrame.GetVerticalScrollRange, scrollFrame)
    if not ok then return 0 end
    return math.max(0, maxScroll or 0)
end
ns.GetSafeVerticalScrollRange = GetSafeVerticalScrollRange

local function GetSafeVerticalScroll(scrollFrame)
    local ok, currentScroll = pcall(scrollFrame.GetVerticalScroll, scrollFrame)
    if not ok then return 0 end
    currentScroll = currentScroll or 0
    return currentScroll + 0
end
ns.GetSafeVerticalScroll = GetSafeVerticalScroll

-- Wheel input eases through the shared UIKit controller (target accumulation,
-- pixel-snapped landing, drag cancellation). Returns the controller so callers
-- can ScrollTo()/Cancel() against the same target the wheel uses. `opts`
-- overrides the default 60-unit step (see UIKit.AttachSmoothScroll).
function ns.ApplyScrollWheel(scrollFrame, opts)
    local kit = UIKit or ns.UIKit
    if kit and kit.AttachSmoothScroll then
        return kit.AttachSmoothScroll(scrollFrame, opts or { step = SCROLL_STEP })
    end
    -- No UIKit (never in-game; keeps headless harnesses that stub it out alive).
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = GetSafeVerticalScroll(self)
        local maxScroll = GetSafeVerticalScrollRange(self)
        local newScroll = math.max(0, math.min(currentScroll - (delta * SCROLL_STEP), maxScroll))
        self:SetVerticalScroll(newScroll)
    end)
    return nil
end

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

local NINE_POINT_ANCHOR_OPTIONS = ns.QUI_SettingsLayoutShared.BuildNinePointAnchorOptions()

local QUAZII_FPS_CVARS = {
    ["vsync"] = "0",
    ["LowLatencyMode"] = "3",
    ["MSAAQuality"] = "0",
    ["ffxAntiAliasingMode"] = "0",
    ["alphaTestMSAA"] = "1",
    ["cameraFov"] = "90",

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

    ["cameraDistanceMaxZoomFactor"] = "2.6",
    ["CameraReduceUnexpectedMovement"] = "1",
}

local LSM = ns.LSM

local function GetTextureList()
    local textures = {}
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            table.insert(textures, {value = name, text = name})
        end
    else
        textures = {{value = "Solid", text = ns.L["Solid"]}}
    end
    return textures
end

local fontPrewarmFrame = nil
local _fontListCache = nil

local function GetFontList()
    if _fontListCache then return _fontListCache end

    local fonts = {}
    if LSM then
        if not fontPrewarmFrame then
            fontPrewarmFrame = CreateFrame("Frame", nil, UIParent)
            fontPrewarmFrame:SetSize(1, 1)
            fontPrewarmFrame:SetPoint("TOPLEFT", -9999, 9999)
            fontPrewarmFrame.text = fontPrewarmFrame:CreateFontString(nil, "OVERLAY")
            fontPrewarmFrame.text:SetPoint("CENTER")
            fontPrewarmFrame.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
            fontPrewarmFrame.text:SetText("A")
        end

        for _, name in ipairs(LSM:List("font")) do
            local path = LSM:Fetch("font", name) or ""
            if path ~= "" then
                local success = ns.SafeCall("best-effort-style", function()
                    fontPrewarmFrame.text:SetFont(path, 12, "")
                end)
                if success then
                    table.insert(fonts, {value = name, text = name})
                end
            end
        end
    else
        fonts = {{value = "Friz Quadrata TT", text = ns.L["Friz Quadrata TT"]}}
    end

    if fontPrewarmFrame then
        fontPrewarmFrame.text:SetText("")
        fontPrewarmFrame:Hide()
        fontPrewarmFrame = nil
    end

    _fontListCache = fonts
    return fonts
end

local function GetSoundList()
    local sounds = {{value = "None", text = ns.L["None"]}}
    if LSM then
        for _, name in ipairs(LSM:List("sound") or {}) do
            if name ~= "None" then
                table.insert(sounds, {value = name, text = name})
            end
        end
    end
    return sounds
end

local function CreateScrollableContent(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 5)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    content._hasContent = false

    scrollFrame:SetScript("OnSizeChanged", function(self, width, height)
        content:SetWidth(width)
    end)

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)

        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            local st = (GUI and GUI.Colors and GUI.Colors.scrollThumb) or { 1, 1, 1, 0.27 }
            thumb:SetColorTexture(st[1], st[2], st[3], st[4])
        end

        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end

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

local function GetDB()
    if QUICore and QUICore.db and QUICore.db.profile then
        return QUICore.db.profile
    end
    return nil
end

local function BackupCurrentFPSSettings()
    local db = GetDB()
    if not db then return false end
    local backup = {}
    for cvar, _ in pairs(QUAZII_FPS_CVARS) do
        local success, current = ns.SafeCall("best-effort-style", C_CVar.GetCVar, cvar)
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
        local ok = ns.SafeCall("best-effort-style", C_CVar.SetCVar, cvar, tostring(value))
        if ok then
            successCount = successCount + 1
        else
            failCount = failCount + 1
        end
    end

    db.fpsBackup = nil

    print("|cff60A5FAQUI:|r Restored " .. successCount .. " previous settings.")
    if failCount > 0 then
        print("|cffFF6B6BQUI:|r " .. failCount .. " settings could not be restored.")
    end
    return true
end

local function ApplyQuaziiFPSSettings()
    BackupCurrentFPSSettings()

    local successCount = 0
    local failCount = 0

    for cvar, value in pairs(QUAZII_FPS_CVARS) do
        local success = ns.SafeCall("best-effort-style", function()
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

local function RefreshMinimap()
    if QUICore and QUICore.Minimap and QUICore.Minimap.Refresh then QUICore.Minimap:Refresh() end
end

local function RefreshUIHider()
    if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end
end

local function RefreshUnitFrames(unit)
    if QUICore and QUICore.UnitFrames then
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

local function SafeGetPixelSize(frame)
    local core = ns.Addon
    return (core and core.GetPixelSize and core:GetPixelSize(frame)) or 1
end

local function CreateWrappedLabel(parent, text, size, color, maxWidth)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontPath = GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF"
    Helpers.ApplyFontWithFallback(label, fontPath, size or 12, "")
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
    Helpers.ApplyFontWithFallback(text, fontPath, 11, "")
    text:SetTextColor(C.text[1], C.text[2], C.text[3])
    text:SetText(label .. "  |cff999999" .. url .. "|r")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)

    local btn = CreateFrame("Button", nil, item, "BackdropTemplate")
    btn:SetSize(56, 18)
    btn:SetPoint("LEFT", text, "RIGHT", 8, 0)

    UIKit.ApplyPixelBackdrop(btn, 1, true, false, { C.border[1], C.border[2], C.border[3], 1 }, { 0.15, 0.15, 0.15, 1 })

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Helpers.ApplyFontWithFallback(btnText, fontPath, 9, "")
    btnText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    btnText:SetText(COPY_ICON .. ns.L["COPY"])
    btnText:SetPoint("CENTER")

    btn:SetScript("OnClick", function()
        if GUI and GUI.ShowExportPopup then
            GUI:ShowExportPopup(popupTitle or ns.L["Copy Link"], url)
        end
        btnText:SetText(ns.L["OPENED"])
        C_Timer.After(2, function()
            if btnText then btnText:SetText(COPY_ICON .. ns.L["COPY"]) end
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

local function GetCollapsibleAccent()
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        return GUI.Colors.accent[1], GUI.Colors.accent[2], GUI.Colors.accent[3]
    end
    return 0.376, 0.647, 0.980
end
local COLLAPSIBLE_HEADER_HEIGHT = 24
local COLLAPSIBLE_FORM_ROW = 32

local function RegisterCollapsibleSection(parent, section)
    local title = section and section._sectionTitle
    local context = section and section._searchContext
    if not title or not context or not context.tabIndex then return end
    GUI.RegisterSectionEntry(context.tabIndex, context.subTabIndex, title, section, parent)
end

local function MeasureBodyContentHeight(body)
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

local COLLAPSIBLE_CARD_GAP = 6
local COLLAPSIBLE_CARD_PAD = 8

local function BuildCollapsibleChrome(parent, title, contentHeight, buildCard)
    local section = CreateFrame("Frame", nil, parent)

    local ar, ag, ab = GetCollapsibleAccent()

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

    buildCard(section)

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(COLLAPSIBLE_HEADER_HEIGHT + COLLAPSIBLE_CARD_GAP + COLLAPSIBLE_CARD_PAD))
    body:SetPoint("RIGHT", section, "RIGHT", 0, 0)
    body:SetHeight(contentHeight)

    section._expanded = true
    section._contentHeight = contentHeight
    section._body = body

    return section, body
end

local function CreateCollapsiblePage(parent, pad, topOffset)
    local PAD = pad or PADDING
    local startY = topOffset or -10
    local sections = {}

    local function relayout()
        local cy = startY
        for _, s in ipairs(sections) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, cy)
            s:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
            RegisterCollapsibleSection(parent, s)
            cy = cy - s:GetHeight() - 4
        end
        parent:SetHeight(math.abs(cy) + 20)
    end

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

        local section, body = BuildCollapsibleChrome(parent, title, contentHeight, function(host)
            local cardBg = CreateFrame("Frame", nil, host)
            cardBg:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(COLLAPSIBLE_HEADER_HEIGHT + COLLAPSIBLE_CARD_GAP))
            cardBg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
            local fill = cardBg:CreateTexture(nil, "BACKGROUND")
            fill:SetAllPoints(cardBg)
            fill:SetColorTexture(1, 1, 1, 0.02)
            if ns.UIKit and ns.UIKit.CreateBorderLines then
                ns.UIKit.CreateBorderLines(cardBg)
                ns.UIKit.UpdateBorderLines(cardBg, 1, 1, 1, 1, 0.12, false)
            end
        end)
        section._sectionTitle = title
        section._searchContext = searchContext
        body._logicalSection = section

        local function RefreshContentHeight()
            if type(body._contentHeight) == "number" and body._contentHeight > 0 then
                section._contentHeight = math.max(section._contentHeight or 0, body._contentHeight)
                body._contentHeight = nil
            end
            local measured = MeasureBodyContentHeight(body)
            if measured and measured > 0 then
                section._contentHeight = math.max(section._contentHeight or 0, measured)
            end
            local bh = section._contentHeight or contentHeight
            body:SetHeight(bh)
            section:SetHeight(COLLAPSIBLE_HEADER_HEIGHT + COLLAPSIBLE_CARD_GAP + (COLLAPSIBLE_CARD_PAD * 2) + bh)
        end
        section.RefreshContentHeight = RefreshContentHeight

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

local function CreateTilePage(parent, pad, topOffset)
    local PAD = pad or PADDING
    local startY = topOffset or -10
    local sections = {}

    local function relayout()
        local cy = startY
        for _, s in ipairs(sections) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, cy)
            s:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
            RegisterCollapsibleSection(parent, s)
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

local function CreateInlineCollapsible(parent, title, contentHeight, onResize)
    local section, body = BuildCollapsibleChrome(parent, title, contentHeight, function(host)
        local cardBg = host:CreateTexture(nil, "BACKGROUND")
        cardBg:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(COLLAPSIBLE_HEADER_HEIGHT + COLLAPSIBLE_CARD_GAP))
        cardBg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        cardBg:SetColorTexture(1, 1, 1, 0.02)

        local function Hairline()
            local t = host:CreateTexture(nil, "BORDER")
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
    end)

    local function RefreshContentHeight()
        if type(body._contentHeight) == "number" and body._contentHeight > 0 then
            section._contentHeight = body._contentHeight
            body._contentHeight = nil
        end
        local measured = MeasureBodyContentHeight(body)
        if measured and measured > 0 then
            section._contentHeight = measured
        end
        local bh = section._contentHeight or contentHeight
        body:SetHeight(bh)
        section:SetHeight(COLLAPSIBLE_HEADER_HEIGHT + COLLAPSIBLE_CARD_GAP + (COLLAPSIBLE_CARD_PAD * 2) + bh)
        if onResize then onResize() end
    end
    section.RefreshContentHeight = RefreshContentHeight

    section.SetExpanded = function(self, _expanded)
        RefreshContentHeight()
    end

    return section, body
end

local Options = ns.QUI_Options or {}
ns.QUI_Options = Options

Options.PADDING = PADDING
Options.NINE_POINT_ANCHOR_OPTIONS = NINE_POINT_ANCHOR_OPTIONS
Options.QUAZII_FPS_CVARS = QUAZII_FPS_CVARS

Options.GetDB = GetDB
Options.CreateScrollableContent = CreateScrollableContent
Options.CreateCollapsiblePage = CreateCollapsiblePage
Options.CreateTilePage = CreateTilePage
Options.CreateInlineCollapsible = CreateInlineCollapsible
Options.GetTextureList = GetTextureList
Options.GetFontList = GetFontList
Options.GetSoundList = GetSoundList
Options.PrintImportFeedback = ns.PrintImportFeedback
Options.SafeGetPixelSize = SafeGetPixelSize
Options.CreateWrappedLabel = CreateWrappedLabel
Options.CreateLinkItem = CreateLinkItem

Options.BackupCurrentFPSSettings = BackupCurrentFPSSettings
Options.RestorePreviousFPSSettings = RestorePreviousFPSSettings
Options.ApplyQuaziiFPSSettings = ApplyQuaziiFPSSettings
Options.CheckCVarsMatch = CheckCVarsMatch

Options.RefreshMinimap = RefreshMinimap
Options.RefreshUIHider = RefreshUIHider
Options.RefreshUnitFrames = RefreshUnitFrames
Options.RefreshBuffBorders = RefreshBuffBorders
Options.RefreshCrosshair = RefreshCrosshair
Options.RefreshReticle = RefreshReticle
Options.RefreshRangeCheck = RefreshRangeCheck

local function CreateAccentDotLabel(parent, text, yOffset, skipSectionNav)
    local ar, ag, ab = GetCollapsibleAccent()

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
    Helpers.ApplyFontWithFallback(label, fpath or select(1, label:GetFont()), 12, "")
    label:SetPoint("LEFT", dot, "RIGHT", 7, 0)
    label:SetTextColor(ar, ag, ab, 1)
    label:SetText(text or "")

    local sep = container:CreateTexture(nil, "BORDER")
    sep:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(ar, ag, ab, 0.3)

    container._dot = dot
    container._label = label
    container._separator = sep

    if type(text) == "string" and text ~= "" and not skipSectionNav then
        local target = parent
        while target do
            if type(target.RegisterSection) == "function" then
                if not target._sectionsAuthoritative then
                    target:RegisterSection(text, text, container)
                end
                break
            end
            if not target.GetParent then break end
            target = target:GetParent()
        end
    end

    return container
end

ns.QUI_Options = ns.QUI_Options or {}
ns.QUI_Options.CreateAccentDotLabel = CreateAccentDotLabel

local function CreateSettingsCardGroup(parent, yOffset)
    local C = QUI.GUI and QUI.GUI.Colors or {}

    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset or 0)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset or 0)
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

    local accent = C.accent or {0.204, 0.827, 0.6, 1}
    local lbl = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local fpath = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(QUI.GUI:GetFontPath())
    Helpers.ApplyFontWithFallback(lbl, fpath or select(1, lbl:GetFont()), 8, "")
    lbl:SetTextColor(accent[1], accent[2], accent[3], 0.7)
    lbl:SetPoint("TOPLEFT", preview, "TOPLEFT", 8, -6)
    local spaced = ("PREVIEW"):gsub(".", "%0 "):sub(1, -2)
    lbl:SetText(spaced)
    preview._label = lbl

    return preview
end
ns.QUI_Options.CreatePreviewArea = CreatePreviewArea

local function ResolveTooltipInfo(frame, depth)
    if not frame or (depth or 0) > 6 then
        return nil, nil
    end

    local description = frame._quiTooltipDescription
    if type(description) == "string" and description ~= "" then
        local label = frame._quiTooltipLabel
        if type(label) == "string" and label ~= "" then
            return description, label
        end
        return description, nil
    end

    if type(frame.GetChildren) ~= "function" then
        return nil, nil
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        local childDescription, childLabel = ResolveTooltipInfo(child, (depth or 0) + 1)
        if childDescription then
            return childDescription, childLabel
        end
    end

    return nil, nil
end

local function SetSettingControlEnabled(control, enabled)
    if not control then
        return
    end

    if type(control.SetEnabled) == "function" then
        control:SetEnabled(enabled and true or false)
        return
    end

    if type(control.EnableMouse) == "function" then
        control:EnableMouse(enabled and true or false)
    end
    if type(control.SetAlpha) == "function" then
        control:SetAlpha(enabled and 1 or 0.4)
    end
end

local function SetSettingRowEnabled(row, enabled)
    if not row then
        return
    end

    enabled = enabled and true or false

    local label = row._label
    if label and row._labelColor then
        local c = row._labelColor
        label:SetTextColor(c[1], c[2], c[3], enabled and c[4] or 0.45)
    end

    local desc = row._desc
    if desc and row._descColor then
        local c = row._descColor
        desc:SetTextColor(c[1], c[2], c[3], enabled and c[4] or 0.35)
    end

    SetSettingControlEnabled(row._widget, enabled)
    row._enabled = enabled
end
ns.QUI_Options.SetSettingRowEnabled = SetSettingRowEnabled

local function BuildSettingRow(parent, labelText, widget, desc)
    local C = QUI.GUI and QUI.GUI.Colors or {}
    local textCol = C.text or {1, 1, 1, 1}
    local mutedCol = C.textMuted or {1, 1, 1, 0.45}

    local cell = CreateFrame("Frame", nil, parent)
    cell:SetHeight(28)

    local fpath = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(QUI.GUI:GetFontPath())

    local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Helpers.ApplyFontWithFallback(label, fpath or select(1, label:GetFont()), 11, "")
    label:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
    label:SetPoint("LEFT", cell, "LEFT", 0, desc and 5 or 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetNonSpaceWrap(false)
    label:SetText(labelText or "")
    cell._label = label
    cell._labelColor = { textCol[1], textCol[2], textCol[3], 1 }

    if desc then
        local d = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        Helpers.ApplyFontWithFallback(d, fpath or select(1, d:GetFont()), 9, "")
        d:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
        d:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        d:SetText(desc)
        cell._desc = d
        cell._descColor = { mutedCol[1], mutedCol[2], mutedCol[3], 1 }
    end

    if widget then
        widget:SetParent(cell)
        widget:ClearAllPoints()
        widget:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
        cell._widget = widget
        label:SetPoint("RIGHT", widget, "LEFT", -6, 0)
    end

    local pins = ns.Settings and ns.Settings.Pins
    if pins and widget and type(pins.AttachSettingRow) == "function" then
        pins:AttachSettingRow(cell, widget, labelText)
    end

    local tooltipDesc, tooltipLabel = ResolveTooltipInfo(widget)
    if not tooltipDesc and type(desc) == "string" and desc ~= "" then
        tooltipDesc = desc
    end
    if tooltipDesc and QUI.GUI and type(QUI.GUI.AttachTooltip) == "function" then
        cell:EnableMouse(true)
        QUI.GUI:AttachTooltip(cell, tooltipDesc, tooltipLabel or labelText)
    end

    cell._widgetLabel = labelText
    cell.SetEnabled = SetSettingRowEnabled
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

    if frame._sections then
        wipe(frame._sections)
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

    if type(featureId) == "string" and featureId ~= "" then
        merged.featureId = featureId
        local registry = Settings and Settings.Registry
        local feature = registry and type(registry.GetFeature) == "function"
            and registry:GetFeature(featureId) or nil
        if type(feature) == "table" then
            if type(feature.providerKey) == "string" and feature.providerKey ~= "" then
                merged.providerKey = feature.providerKey
            end
            if type(feature.category) == "string" and feature.category ~= "" then
                merged.category = feature.category
            end
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
    local text = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
        moduleFeatureId = spec.moduleFeatureId,
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

                tileConfig.subPages[index] = {
                    id = page.id,
                    name = page.name,
                    featureId = page.featureId,
                    featureIds = page.featureIds,
                    preview = subPage.preview,
                    noScroll = subPage.noScroll,
                    sectionNav = subPage.sectionNav,
                    buildFunc = function(body)
                        BuildFeaturePageBody(body, page, BuildFeatureTabPage)
                    end,
                }
            end
        end
    else
        tileConfig.featureId = spec.featureId
        tileConfig.noScroll = spec.noScroll ~= false
        tileConfig.sectionNav = spec.sectionNav
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

    tabContent._sectionsAuthoritative = true

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
            titleRow._quiSearchSectionFeatureId = featureId

            local dot = titleRow:CreateTexture(nil, "OVERLAY")
            dot:SetSize(6, 6)
            dot:SetPoint("LEFT", titleRow, "LEFT", 0, 1)
            dot:SetColorTexture(accent[1], accent[2], accent[3], 1)

            local text = titleRow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            text:SetPoint("LEFT", dot, "RIGHT", 10, 0)
            local textCol = C.text or { 1, 1, 1, 1 }
            text:SetTextColor(textCol[1], textCol[2], textCol[3], textCol[4] or 1)
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
