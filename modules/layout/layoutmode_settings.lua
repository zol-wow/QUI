local ADDON_NAME, ns = ...

local function EnsureCJKFont(fs)
    if not fs or not fs.GetFont then return fs end
    local fp, sz, fl = fs:GetFont()
    if fp and ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, fp, sz, fl)
    end
    return fs
end

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local QUI_LayoutMode_Settings = {}
ns.QUI_LayoutMode_Settings = QUI_LayoutMode_Settings

local ACCENT_R, ACCENT_G, ACCENT_B = 0.376, 0.647, 0.980

function QUI_LayoutMode_Settings:RefreshAccentColor()
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        ACCENT_R = GUI.Colors.accent[1]
        ACCENT_G = GUI.Colors.accent[2]
        ACCENT_B = GUI.Colors.accent[3]
    end
    local panel = self._panel
    local glow = panel and panel._accentGlow
    if glow then
        local accentGlow = (GUI and GUI.Colors and GUI.Colors.accentGlow)
            or {ACCENT_R, ACCENT_G, ACCENT_B, 0.06}
        if glow.SetGradient then
            local ok = pcall(function()
                glow:SetGradient("HORIZONTAL",
                    CreateColor(accentGlow[1], accentGlow[2], accentGlow[3], accentGlow[4] or 0.06),
                    CreateColor(accentGlow[1], accentGlow[2], accentGlow[3], 0))
            end)
            if not ok then
                glow:SetColorTexture(accentGlow[1], accentGlow[2], accentGlow[3], accentGlow[4] or 0.06)
            end
        else
            glow:SetColorTexture(accentGlow[1], accentGlow[2], accentGlow[3], accentGlow[4] or 0.06)
        end
    end
end

local PANEL_WIDTH = 420
local PANEL_HEIGHT = 650
local PANEL_STRATA = "FULLSCREEN_DIALOG"
local PANEL_LEVEL = 200
local TITLE_HEIGHT = 32
local CONTENT_PADDING = 12
local BORDER_SIZE = 1

local SCROLL_STEP = 60

local GetPixelSize = UIKit.GetPixelSize

local function GetPixelLineSize(frame, pixels)
    return (pixels or 1) * GetPixelSize(frame)
end

QUI_LayoutMode_Settings._currentKey = nil
QUI_LayoutMode_Settings._panel = nil
QUI_LayoutMode_Settings._built = false

local function GetSharedProviderRegistry()
    local Settings = ns.Settings
    if not Settings then
        return nil
    end

    return Settings.Providers or Settings.ProviderRegistry
end

function QUI_LayoutMode_Settings:RegisterSharedProvider(key, provider)
    local sharedProviders = GetSharedProviderRegistry()
    if sharedProviders and type(sharedProviders.Register) == "function" then
        sharedProviders:Register(key, provider)
    end
end

local function CreateBorderLine(parent, p1, r1, p2, r2, isHoriz, r, g, b, a)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetColorTexture(r or ACCENT_R, g or ACCENT_G, b or ACCENT_B, a or 0.6)
    line._layoutModeSettingsIsHoriz = isHoriz and true or false
    line:ClearAllPoints()
    line:SetPoint(p1, parent, r1, 0, 0)
    line:SetPoint(p2, parent, r2, 0, 0)
    if isHoriz then
        line:SetHeight(GetPixelLineSize(parent, BORDER_SIZE))
    else
        line:SetWidth(GetPixelLineSize(parent, BORDER_SIZE))
    end
    return line
end

local function RefreshPanelPixelLayout(panel)
    if not panel then return end
    local borderSize = GetPixelLineSize(panel, BORDER_SIZE)
    for _, line in ipairs(panel._pixelBorderLines or {}) do
        if line._layoutModeSettingsIsHoriz then
            line:SetHeight(borderSize)
        else
            line:SetWidth(borderSize)
        end
    end

    local titleBg = panel._titleBg
    if titleBg then
        titleBg:ClearAllPoints()
        titleBg:SetPoint("TOPLEFT", borderSize, -borderSize)
        titleBg:SetPoint("TOPRIGHT", -borderSize, -borderSize)
    end

    local contentSurface = panel._contentSurface
    if contentSurface and titleBg then
        contentSurface:ClearAllPoints()
        contentSurface:SetPoint("TOPLEFT", titleBg, "BOTTOMLEFT", 0, 0)
        contentSurface:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -borderSize, borderSize)
    end

    local glow = panel._accentGlow
    if glow and titleBg then
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", titleBg, "BOTTOMLEFT", 0, 0)
        glow:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -borderSize, borderSize)
    end

    local titleLine = panel._titleLine
    if titleLine then
        titleLine:SetHeight(borderSize)
    end
end

local function SafeGetVerticalScrollRange(scrollFrame)
    local ok, maxScroll = pcall(scrollFrame.GetVerticalScrollRange, scrollFrame)
    if not ok then return 0 end
    local ok2, safeMax = pcall(function() return math.max(0, maxScroll or 0) end)
    return ok2 and safeMax or 0
end

local function SafeGetVerticalScroll(scrollFrame)
    local ok, currentScroll = pcall(scrollFrame.GetVerticalScroll, scrollFrame)
    if not ok then return 0 end
    local ok2, safeCurrent = pcall(function() return currentScroll + 0 end)
    return ok2 and safeCurrent or 0
end

local function CreateQUIStyleCloseButton(parent, relativeTo, relativePoint, xOffset, yOffset, onClick)
    return UIKit.CreateCloseButton(parent, {
        point = "RIGHT",
        relativeTo = relativeTo,
        relativePoint = "RIGHT",
        x = xOffset or 0,
        y = yOffset or 0,
        onClick = onClick,
    })
end

local function CreatePanel()
    local panel = CreateFrame("Frame", "QUI_LayoutMode_SettingsPanel", UIParent)
    panel:SetFrameStrata(PANEL_STRATA)
    panel:SetFrameLevel(PANEL_LEVEL)
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:Hide()

    local GUI = _G.QUI and _G.QUI.GUI
    local C = GUI and GUI.Colors or {}
    local bgColor = C.bg or {0.051, 0.067, 0.09, 0.97}
    local bgContent = C.bgContent or {1, 1, 1, 0.02}
    local accentGlow = C.accentGlow or {ACCENT_R, ACCENT_G, ACCENT_B, 0.06}

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.97)

    panel._pixelBorderLines = {
        CreateBorderLine(panel, "TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", true),
        CreateBorderLine(panel, "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", true),
        CreateBorderLine(panel, "TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", false),
        CreateBorderLine(panel, "TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", false),
    }

    local borderSize = GetPixelLineSize(panel, BORDER_SIZE)
    local titleBg = panel:CreateTexture(nil, "ARTWORK")
    titleBg:SetPoint("TOPLEFT", borderSize, -borderSize)
    titleBg:SetPoint("TOPRIGHT", -borderSize, -borderSize)
    titleBg:SetHeight(TITLE_HEIGHT)
    titleBg:SetColorTexture(0.04, 0.06, 0.1, 1)
    panel._titleBg = titleBg

    local contentSurface = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    contentSurface:SetPoint("TOPLEFT", titleBg, "BOTTOMLEFT", 0, 0)
    contentSurface:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -borderSize, borderSize)
    contentSurface:SetColorTexture(bgContent[1], bgContent[2], bgContent[3], bgContent[4] or 0.02)
    panel._contentSurface = contentSurface

    local glow = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    glow:SetPoint("TOPLEFT", titleBg, "BOTTOMLEFT", 0, 0)
    glow:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -borderSize, borderSize)
    glow:SetTexture("Interface\\BUTTONS\\WHITE8x8")
    if glow.SetGradient then
        local ok = pcall(function()
            glow:SetGradient("HORIZONTAL",
                CreateColor(accentGlow[1], accentGlow[2], accentGlow[3], accentGlow[4] or 0.06),
                CreateColor(accentGlow[1], accentGlow[2], accentGlow[3], 0))
        end)
        if not ok then
            glow:SetColorTexture(accentGlow[1], accentGlow[2], accentGlow[3], accentGlow[4] or 0.06)
        end
    else
        glow:SetColorTexture(accentGlow[1], accentGlow[2], accentGlow[3], accentGlow[4] or 0.06)
    end
    panel._accentGlow = glow

    local titleLine = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    titleLine:SetPoint("TOPLEFT", titleBg, "BOTTOMLEFT")
    titleLine:SetPoint("TOPRIGHT", titleBg, "BOTTOMRIGHT")
    titleLine:SetHeight(borderSize)
    titleLine:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.4)
    panel._titleLine = titleLine

    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(panel, "layoutModeSettingsPixelLayout", RefreshPanelPixelLayout)
    end

    local titleText = EnsureCJKFont(panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    titleText:SetPoint("LEFT", titleBg, "LEFT", 12, 0)
    titleText:SetPoint("RIGHT", titleBg, "RIGHT", -32, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetTextColor(1, 1, 1, 1)
    titleText:SetText(ns.L["Settings"])
    panel._titleText = titleText

    local closeBtn = CreateQUIStyleCloseButton(panel, titleBg, "TOPRIGHT", -6, 0, function()
        QUI_LayoutMode_Settings:Hide()
    end)

    local dragHandle = CreateFrame("Frame", nil, panel)
    dragHandle:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -4, 0)
    dragHandle:SetHeight(TITLE_HEIGHT)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        panel:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        panel._userDragged = true
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PADDING, -(TITLE_HEIGHT + CONTENT_PADDING))
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(CONTENT_PADDING + 22), CONTENT_PADDING)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(PANEL_WIDTH - (CONTENT_PADDING * 2) - 22)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8)
        end
        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end

        scrollBar:HookScript("OnShow", function(self)
            C_Timer.After(0.066, function()
                local maxScroll = SafeGetVerticalScrollRange(scrollFrame)
                if maxScroll <= 1 then
                    self:Hide()
                end
            end)
        end)
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = SafeGetVerticalScroll(self)
        local maxScroll = SafeGetVerticalScrollRange(self)
        local newScroll = math.max(0, math.min(currentScroll - (delta * SCROLL_STEP), maxScroll))
        self:SetVerticalScroll(newScroll)
    end)

    panel._scrollFrame = scrollFrame
    panel._content = content

    local placeholder = EnsureCJKFont(content:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    placeholder:SetPoint("TOP", content, "TOP", 0, -40)
    placeholder:SetTextColor(0.6, 0.65, 0.7, 1)
    placeholder:SetText(ns.L["No settings available for this frame."])
    placeholder:SetJustifyH("CENTER")
    placeholder:Hide()
    panel._placeholder = placeholder

    return panel
end

local function PositionAdjacentToDrawer(panel)
    local ui = ns.QUI_LayoutMode_UI
    local anchor = ui and ((ui._drawer and ui._drawer:IsShown() and ui._drawer) or ui._toolbarPanel)
    if not anchor then return end

    local side = ui._tabDocked and ui._tabDocked() or "RIGHT"
    local panelScale = panel:GetScale() or 1
    local screenW = UIParent:GetWidth()
    local screenH = UIParent:GetHeight()
    local panelW = PANEL_WIDTH * panelScale
    local panelH = PANEL_HEIGHT * panelScale
    local gap = 4

    local x, y

    if side == "LEFT" then
        local anchorRight = anchor:GetRight()
        if anchorRight then
            x = anchorRight + gap
            if x + panelW > screenW then
                local tabLeft = ui._toolbar and ui._toolbar:GetLeft()
                x = tabLeft and (tabLeft - panelW - gap) or (screenW - panelW - gap)
            end
        else
            x = gap
        end
    else
        local anchorLeft = anchor:GetLeft()
        if anchorLeft then
            x = anchorLeft - panelW - gap
            if x < 0 then
                local tabRight = ui._toolbar and ui._toolbar:GetRight()
                x = tabRight and (tabRight + gap) or gap
            end
        else
            x = screenW - panelW - gap
        end
    end

    local anchorTop = anchor:GetTop()
    y = math.min(anchorTop or (screenH - gap), screenH - gap)
    y = math.max(y, panelH + gap)

    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function ClearContent(panel)
    local content = panel._content
    local GUI = _G.QUI and _G.QUI.GUI

    local expandedStates = {}
    for _, child in pairs({content:GetChildren()}) do
        if child._expanded ~= nil and child._sectionTitle then
            expandedStates[child._sectionTitle] = child._expanded
        end
    end
    QUI_LayoutMode_Settings._expandedStates = expandedStates

    if content._origSetHeight then
        content.SetHeight = content._origSetHeight
    end

    if GUI and GUI.CleanupWidgetTree then
        GUI:CleanupWidgetTree(content)
    end

    for _, child in pairs({content:GetChildren()}) do
        if child == panel._infoSection then
            if UIKit and UIKit.CancelValueAnimation then
                UIKit.CancelValueAnimation(child, "anchoringInfo")
            end
            child:Hide()
        else
            child:Hide()
            child:SetParent(nil)
        end
    end
    for _, region in pairs({content:GetRegions()}) do
        if region ~= panel._placeholder then
            region:Hide()
        end
    end
    panel._placeholder:Hide()
    content._quiProviderSync = nil
    content:SetHeight(1)
    pcall(panel._scrollFrame.SetVerticalScroll, panel._scrollFrame, 0)
end

local function BuildAnchorChainText(key)
    local fa
    local core = ns.Helpers.GetCore()
    if core and core.db and core.db.profile then
        fa = core.db.profile.frameAnchoring
    end
    if not fa then return "No anchor data" end

    local lines = {}
    local visited = {}
    local current = key

    while current and not visited[current] do
        visited[current] = true

        local entry = fa[current]
        if type(entry) ~= "table" then
            local info = ns.FRAME_ANCHOR_INFO and ns.FRAME_ANCHOR_INFO[current]
            local name = info and info.displayName or current
            table.insert(lines, name .. "  (" .. ns.L["layout mode"] .. ")")
            break
        end

        local parent = entry.parent
        local pt = entry.point or "CENTER"
        local rel = entry.relative or "CENTER"

        local info = ns.FRAME_ANCHOR_INFO and ns.FRAME_ANCHOR_INFO[current]
        local name = info and info.displayName or current

        if not parent or parent == "disabled" then
            table.insert(lines, name .. "  (" .. ns.L["disabled"] .. ")")
            break
        elseif parent == "screen" then
            table.insert(lines, string.format("%s  [%s]", name, pt))
            table.insert(lines, string.format("  -> " .. ns.L["Screen"] .. "  [%s]", rel))
            break
        else
            local parentInfo = ns.FRAME_ANCHOR_INFO and ns.FRAME_ANCHOR_INFO[parent]
            local parentName = parentInfo and parentInfo.displayName or parent
            table.insert(lines, string.format("%s  [%s]", name, pt))
            table.insert(lines, string.format("  -> %s  [%s]", parentName, rel))
            current = parent
        end
    end

    if #lines == 0 then
        return ns.L["No anchor chain"]
    end

    return table.concat(lines, "\n")
end

local function ResolveSharedFeature(key)
    local Settings = ns.Settings
    local Registry = Settings and Settings.Registry
    if not Registry then
        return nil
    end

    if type(Registry.GetFeatureByLookupKey) == "function" then
        local byLookup = Registry:GetFeatureByLookupKey(key)
        if byLookup then
            return byLookup
        end
    end

    if type(Registry.GetFeatureByMoverKey) == "function" then
        return Registry:GetFeatureByMoverKey(key)
    end

    return nil
end

local function BuildContent(panel, key)
    ClearContent(panel)

    local content = panel._content
    local contentWidth = content:GetWidth()
    local feature = ResolveSharedFeature(key)
    content._quiProviderSync = {
        providerKey = key,
        featureId = feature and feature.id or nil,
        surfaceId = "layoutmode-settings",
    }

    local providerHeight = 0
    local Settings = ns.Settings
    local Renderer = Settings and Settings.Renderer
    local U = ns.QUI_LayoutMode_Utils

    if feature and Renderer and type(Renderer.RenderFeature) == "function" then
        if type(feature.onNavigate) == "function" then
            ns.SafeCall("bulkhead", feature.onNavigate, key, nil, {
                source = "layoutmode-drawer",
            })
        end

        local usePositionOnly = feature.layoutPositionOnly ~= false
        local ok, totalHeight

        local function renderSharedFeature()
            local previousMinimalDrawerChrome = U and U._useMinimalDrawerChrome
            local previousPositionOnly = U and U._layoutModePositionOnly
            if U then
                U._useMinimalDrawerChrome = true
                U._layoutModePositionOnly = usePositionOnly
            end
            local ok2, h = ns.SafeCallMethod("bulkhead", Renderer, "RenderFeature", feature, content, {
                surface = "layout",
                width = contentWidth,
                includePosition = true,
                positionOnly = usePositionOnly,
                layoutModePositionOnly = usePositionOnly,
                useMinimalDrawerChrome = true,
                providerKey = key,
            })
            if U then
                U._useMinimalDrawerChrome = previousMinimalDrawerChrome
                U._layoutModePositionOnly = previousPositionOnly
            end
            ok = ok2
            return h
        end

        totalHeight = renderSharedFeature()

        if ok then
            if totalHeight and totalHeight > 0 then
                providerHeight = totalHeight
            else
                local maxBottom = 0
                for _, child in pairs({content:GetChildren()}) do
                    if child:IsShown() then
                        local bottom = -(child:GetBottom() and (content:GetTop() - child:GetBottom()) or 0)
                        if bottom > maxBottom then maxBottom = bottom end
                    end
                end
                providerHeight = math.max(maxBottom + 20, 80)
            end
        else
            ClearContent(panel)
            content = panel._content
            contentWidth = content:GetWidth()
            content._quiProviderSync = {
                providerKey = key,
                featureId = feature and feature.id or nil,
                surfaceId = "layoutmode-settings",
            }
        end
    end

    if U and U.CreateCollapsible then
        local statusText
        local customStatus
        if feature and type(feature.getAnchorStatus) == "function" then
            local ok, result = ns.SafeCall("bulkhead", feature.getAnchorStatus, key)
            if ok and type(result) == "table" then
                customStatus = result
            end
        end

        if customStatus then
            if customStatus.enabled then
                statusText = "|cff888888" .. ns.L["Anchoring:"] .. "|r  |cff34D399" .. ns.L["Enabled"] .. "|r"
            else
                statusText = "|cff888888" .. ns.L["Anchoring:"] .. "|r  |cffFF6666" .. ns.L["Disabled"] .. "|r"
            end
        else
            local fa
            local core = ns.Helpers.GetCore()
            if core and core.db and core.db.profile then
                fa = core.db.profile.frameAnchoring
            end
            local anchorEntry = fa and fa[key]
            local isAnchored = type(anchorEntry) == "table"

            if not isAnchored then
                statusText = "|cff888888" .. ns.L["Anchoring:"] .. "|r  |cffFF6666" .. ns.L["Disabled"] .. "|r"
            else
                local parent = anchorEntry.parent
                if not parent or parent == "disabled" then
                    statusText = "|cff888888" .. ns.L["Anchoring:"] .. "|r  |cffFF6666" .. ns.L["Disabled"] .. "|r"
                else
                    statusText = "|cff888888" .. ns.L["Anchoring:"] .. "|r  |cff34D399" .. ns.L["Enabled"] .. "|r"
                end
            end
        end

        local chainText
        if customStatus then
            if customStatus.enabled and customStatus.parent then
                local info = ns.FRAME_ANCHOR_INFO and ns.FRAME_ANCHOR_INFO[customStatus.parent]
                local parentName = info and info.displayName or customStatus.parent
                chainText = ns.L["Anchored to: "] .. parentName
            else
                chainText = ns.L["No anchor chain"]
            end
        else
            chainText = BuildAnchorChainText(key)
        end

        local HEADER_HEIGHT = U.HEADER_HEIGHT or 24
        local infoSection = panel._infoSection

        if not infoSection then
            infoSection = CreateFrame("Frame", nil, content)
            panel._infoSection = infoSection
            infoSection._sectionTitle = "Anchoring Details"

            local btn = CreateFrame("Button", nil, infoSection)
            btn:SetPoint("TOPLEFT", 0, 0)
            btn:SetPoint("TOPRIGHT", 0, 0)
            btn:SetHeight(HEADER_HEIGHT)
            infoSection._btn = btn

            local chevron = UIKit and UIKit.CreateChevronCaret and UIKit.CreateChevronCaret(btn, {
                point = "LEFT",
                relativeTo = btn,
                relativePoint = "LEFT",
                xPixels = 2,
                yPixels = 0,
                sizePixels = 10,
                lineWidthPixels = 6,
                lineHeightPixels = 1,
                expanded = true,
                collapsedDirection = "right",
                r = ACCENT_R,
                g = ACCENT_G,
                b = ACCENT_B,
                a = 1,
            }) or EnsureCJKFont(btn:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
            if not (UIKit and UIKit.CreateChevronCaret) then
                chevron:SetPoint("LEFT", 2, 0)
                chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            end
            infoSection._chevron = chevron

            local titleLabel = EnsureCJKFont(btn:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
            titleLabel:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
            titleLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            titleLabel:SetText(ns.L["Anchoring Details"])
            infoSection._titleLabel = titleLabel

            local underline = btn:CreateTexture(nil, "ARTWORK")
            underline:SetHeight(1)
            underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            underline:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.3)

            local bodyClip = CreateFrame("ScrollFrame", nil, infoSection)
            bodyClip:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
            bodyClip:SetPoint("RIGHT", infoSection, "RIGHT", 0, 0)
            bodyClip:SetHeight(0)
            bodyClip:Hide()
            infoSection._bodyClip = bodyClip

            local body = CreateFrame("Frame", nil, bodyClip)
            body:SetWidth(1)
            bodyClip:SetScrollChild(body)
            bodyClip:SetScript("OnSizeChanged", function(self, width)
                body:SetWidth(math.max(width or 1, 1))
            end)
            body:SetAlpha(0)
            infoSection._body = body

            local statusLabel = EnsureCJKFont(body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
            statusLabel:SetPoint("TOPLEFT", 8, -6)
            statusLabel:SetPoint("RIGHT", body, "RIGHT", -8, 0)
            statusLabel:SetJustifyH("LEFT")
            infoSection._statusLabel = statusLabel

            local chainLabel = EnsureCJKFont(body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
            chainLabel:SetPoint("TOPLEFT", 8, -(6 + statusLabel:GetStringHeight() + 6))
            chainLabel:SetPoint("RIGHT", body, "RIGHT", -8, 0)
            chainLabel:SetTextColor(0.85, 0.85, 0.85, 1)
            chainLabel:SetJustifyH("LEFT")
            chainLabel:SetJustifyV("TOP")
            chainLabel:SetWordWrap(true)
            chainLabel:SetSpacing(3)
            infoSection._chainLabel = chainLabel
        end

        local btn = infoSection._btn
        local chevron = infoSection._chevron
        local label = infoSection._titleLabel
        local bodyClip = infoSection._bodyClip
        local body = infoSection._body
        local statusLabel = infoSection._statusLabel
        local chainLabel = infoSection._chainLabel

        infoSection:Show()
        statusLabel:SetText(statusText)
        chainLabel:SetPoint("TOPLEFT", 8, -(6 + statusLabel:GetStringHeight() + 6))
        chainLabel:SetText(chainText)

        local bodyHeight = 6 + statusLabel:GetStringHeight() + 6 + chainLabel:GetStringHeight() + 10
        body:SetHeight(bodyHeight)

        infoSection._expanded = true
        if UIKit and UIKit.SetChevronCaretExpanded then
            UIKit.SetChevronCaretExpanded(chevron, true)
        elseif chevron.SetText then
            chevron:SetText("v")
        end
        bodyClip:Show()
        bodyClip:SetHeight(bodyHeight)
        body:SetAlpha(1)
        infoSection:SetHeight(HEADER_HEIGHT + bodyHeight)

        if not content._origSetHeight then
            content._origSetHeight = content.SetHeight
        end
        local origSetHeight = content._origSetHeight
        local function repositionInfo()
            infoSection:ClearAllPoints()
            infoSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(providerHeight + 4))
            infoSection:SetPoint("RIGHT", content, "RIGHT", 0, 0)

            local totalH = providerHeight + 8 + infoSection:GetHeight()
            origSetHeight(content, totalH)
        end

        local savedStates = QUI_LayoutMode_Settings._expandedStates
        if savedStates and savedStates["Anchoring Details"] == false then
            infoSection._expanded = false
            if UIKit and UIKit.SetChevronCaretExpanded then
                UIKit.SetChevronCaretExpanded(chevron, false)
            else
                chevron:SetText(">")
            end
            bodyClip:SetHeight(0)
            bodyClip:Hide()
            body:SetAlpha(0)
            infoSection:SetHeight(HEADER_HEIGHT)
        end

        local function ApplyInfoState(currentHeight)
            local height = math.max(0, math.min(bodyHeight, currentHeight or 0))
            bodyClip:SetHeight(height)
            infoSection:SetHeight(HEADER_HEIGHT + height)
            repositionInfo()
        end

        btn:SetScript("OnClick", function()
            infoSection._expanded = not infoSection._expanded
            local targetHeight = infoSection._expanded and bodyHeight or 0
            local currentHeight = bodyClip:GetHeight() or 0
            if infoSection._expanded then
                if UIKit and UIKit.SetChevronCaretExpanded then
                    UIKit.SetChevronCaretExpanded(chevron, true)
                else
                    chevron:SetText("v")
                end
                bodyClip:Show()
            else
                if UIKit and UIKit.SetChevronCaretExpanded then
                    UIKit.SetChevronCaretExpanded(chevron, false)
                else
                    chevron:SetText(">")
                end
            end
            if UIKit and UIKit.AnimateValue and UIKit.CancelValueAnimation then
                UIKit.CancelValueAnimation(infoSection, "anchoringInfo")
                UIKit.AnimateValue(infoSection, "anchoringInfo", {
                    fromValue = currentHeight,
                    toValue = targetHeight,
                    duration = ((_G.QUI and _G.QUI.GUI and _G.QUI.GUI._sidebarAnimDuration) or 0.16),
                    onUpdate = function(_, progressHeight)
                        local ratio = math.max(0, math.min(1, progressHeight / math.max(bodyHeight, 1)))
                        ApplyInfoState(progressHeight)
                        body:SetAlpha(ratio)
                    end,
                    onFinish = function(_, finalHeight)
                        ApplyInfoState(finalHeight)
                        body:SetAlpha(infoSection._expanded and 1 or 0)
                        if not infoSection._expanded then
                            bodyClip:Hide()
                        end
                    end,
                })
            else
                ApplyInfoState(targetHeight)
                body:SetAlpha(infoSection._expanded and 1 or 0)
                if not infoSection._expanded then
                    bodyClip:Hide()
                end
            end
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
            label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            if UIKit and UIKit.SetChevronCaretColor then
                UIKit.SetChevronCaretColor(chevron, ACCENT_R, ACCENT_G, ACCENT_B, 1)
            else
                chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            end
        end)

        content.SetHeight = function(self, h)
            if h and h > 0 then
                providerHeight = h
            end
            repositionInfo()
        end

        repositionInfo()
    else
        content:SetHeight(math.max(providerHeight, 80))
    end
end

function QUI_LayoutMode_Settings:Show(key)
    if not key then
        self:Hide()
        return
    end

    if not self._panel then
        self._panel = CreatePanel()
    end

    local panel = self._panel
    local layoutUI = ns.QUI_LayoutMode_UI
    if layoutUI and layoutUI.ApplyConfigPanelScale then
        layoutUI:ApplyConfigPanelScale(panel)
    end
    local um = ns.QUI_LayoutMode
    local def = um and um._elements and um._elements[key]
    local label = def and def.label or key

    panel._titleText:SetText("|cff60A5FA" .. label .. "|r " .. ns.L["Settings"])

    if self._currentKey ~= key then
        local wasShown = panel:IsShown()
        self._currentKey = key
        BuildContent(panel, key)

        if not wasShown and not panel._userDragged then
            PositionAdjacentToDrawer(panel)
        end
    end

    local compat = ns.Settings and ns.Settings.RenderAdapters
    if compat and compat.RegisterProviderSurface then
        compat.RegisterProviderSurface(key, "layoutmode-settings", function(meta)
            self:Refresh(meta)
        end, function()
            return panel:IsShown()
        end)
    end

    panel:Show()
end

function QUI_LayoutMode_Settings:Hide()
    if not self._hiding then
        self._hiding = true
        local um = ns.QUI_LayoutMode
        if um and um.SelectMover then
            um:SelectMover(nil)
        end
        self._hiding = nil
    end
    if self._panel then
        self._panel:Hide()
    end
    local compat = ns.Settings and ns.Settings.RenderAdapters
    if compat and compat.UnregisterProviderSurface then
        compat.UnregisterProviderSurface("layoutmode-settings")
    end
end

function QUI_LayoutMode_Settings:IsShown()
    return self._panel and self._panel:IsShown()
end

function QUI_LayoutMode_Settings:Refresh(meta)
    if not self._currentKey or not self._panel or not self._panel:IsShown() then return end
    local panel = self._panel
    local key = (meta and meta.providerKey) or self._currentKey
    local currentScroll = SafeGetVerticalScroll(panel._scrollFrame)

    BuildContent(panel, key)
    self._currentKey = key
    local maxScroll = SafeGetVerticalScrollRange(panel._scrollFrame)
    pcall(panel._scrollFrame.SetVerticalScroll, panel._scrollFrame, math.max(0, math.min(currentScroll, maxScroll)))
end

function QUI_LayoutMode_Settings:Reset()
    self:Hide()
    self._currentKey = nil
    if self._panel then
        self._panel._userDragged = nil
    end
end
