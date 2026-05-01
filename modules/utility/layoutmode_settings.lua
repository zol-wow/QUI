---------------------------------------------------------------------------
-- QUI Layout Mode — Settings Panel
-- Context-aware settings panel that appears when a mover is selected
-- in Layout Mode. Modules register providers for their frame keys.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local QUI_LayoutMode_Settings = {}
ns.QUI_LayoutMode_Settings = QUI_LayoutMode_Settings

-- Accent color: cached from GUI.Colors.accent, refreshed when layout mode opens.
local ACCENT_R, ACCENT_G, ACCENT_B = 0.376, 0.647, 0.980

function QUI_LayoutMode_Settings:RefreshAccentColor()
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        ACCENT_R = GUI.Colors.accent[1]
        ACCENT_G = GUI.Colors.accent[2]
        ACCENT_B = GUI.Colors.accent[3]
    end
end

-- Panel constants
local PANEL_WIDTH = 420
local PANEL_HEIGHT = 650
local PANEL_STRATA = "FULLSCREEN_DIALOG"
local PANEL_LEVEL = 200
local TITLE_HEIGHT = 32
local CONTENT_PADDING = 12
local BORDER_SIZE = 1

-- Scroll speed
local SCROLL_STEP = 60

-- State
QUI_LayoutMode_Settings._currentKey = nil
QUI_LayoutMode_Settings._panel = nil
QUI_LayoutMode_Settings._built = false

---------------------------------------------------------------------------
-- PROVIDER REGISTRY
---------------------------------------------------------------------------

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


---------------------------------------------------------------------------
-- PANEL CREATION
---------------------------------------------------------------------------

local function CreateBorderLine(parent, p1, r1, p2, r2, isHoriz, r, g, b, a)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetColorTexture(r or ACCENT_R, g or ACCENT_G, b or ACCENT_B, a or 0.6)
    line:ClearAllPoints()
    line:SetPoint(p1, parent, r1, 0, 0)
    line:SetPoint(p2, parent, r2, 0, 0)
    if isHoriz then
        line:SetHeight(BORDER_SIZE)
    else
        line:SetWidth(BORDER_SIZE)
    end
    return line
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
    local GUI = _G.QUI and _G.QUI.GUI
    local C = GUI and GUI.Colors or {}
    local border = C.border or {0.24, 0.28, 0.34, 1}
    local text = C.text or {0.85, 0.88, 0.92, 1}

    local close = CreateFrame("Button", nil, parent, "BackdropTemplate")
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", relativeTo, "RIGHT", xOffset or 0, yOffset or 0)
    close:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    close:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
    close:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)

    local lineLen, lineWidth = 10, 1.5
    local xLine1 = close:CreateTexture(nil, "OVERLAY")
    xLine1:SetSize(lineLen, lineWidth)
    xLine1:SetPoint("CENTER")
    xLine1:SetColorTexture(text[1], text[2], text[3], 0.8)
    xLine1:SetRotation(math.rad(45))

    local xLine2 = close:CreateTexture(nil, "OVERLAY")
    xLine2:SetSize(lineLen, lineWidth)
    xLine2:SetPoint("CENTER")
    xLine2:SetColorTexture(text[1], text[2], text[3], 0.8)
    xLine2:SetRotation(math.rad(-45))

    close:SetScript("OnClick", onClick)
    close:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        self:SetBackdropColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.15)
        xLine1:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        xLine2:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    close:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, border[1], border[2], border[3], border[4] or 1)
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
        xLine1:SetColorTexture(text[1], text[2], text[3], 0.8)
        xLine2:SetColorTexture(text[1], text[2], text[3], 0.8)
    end)

    return close
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

    -- Background
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.067, 0.094, 0.153, 0.97)

    -- Border
    CreateBorderLine(panel, "TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", true)
    CreateBorderLine(panel, "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", true)
    CreateBorderLine(panel, "TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", false)
    CreateBorderLine(panel, "TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", false)

    -- Title bar background
    local titleBg = panel:CreateTexture(nil, "ARTWORK")
    titleBg:SetPoint("TOPLEFT", BORDER_SIZE, -BORDER_SIZE)
    titleBg:SetPoint("TOPRIGHT", -BORDER_SIZE, -BORDER_SIZE)
    titleBg:SetHeight(TITLE_HEIGHT)
    titleBg:SetColorTexture(0.04, 0.06, 0.1, 1)

    -- Title bar bottom line
    local titleLine = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    titleLine:SetPoint("TOPLEFT", titleBg, "BOTTOMLEFT")
    titleLine:SetPoint("TOPRIGHT", titleBg, "BOTTOMRIGHT")
    titleLine:SetHeight(BORDER_SIZE)
    titleLine:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.4)

    -- Title text
    local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBg, "LEFT", 12, 0)
    titleText:SetPoint("RIGHT", titleBg, "RIGHT", -32, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetTextColor(1, 1, 1, 1)
    titleText:SetText("Settings")
    panel._titleText = titleText

    -- Close button
    local closeBtn = CreateQUIStyleCloseButton(panel, titleBg, "TOPRIGHT", -6, 0, function()
        QUI_LayoutMode_Settings:Hide()
    end)

    -- Drag handle (title bar)
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

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PADDING, -(TITLE_HEIGHT + CONTENT_PADDING))
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(CONTENT_PADDING + 22), CONTENT_PADDING)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(PANEL_WIDTH - (CONTENT_PADDING * 2) - 22)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    -- Style scrollbar
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

        -- Auto-hide scrollbar when not needed
        scrollBar:HookScript("OnShow", function(self)
            C_Timer.After(0.066, function()
                local maxScroll = SafeGetVerticalScrollRange(scrollFrame)
                if maxScroll <= 1 then
                    self:Hide()
                end
            end)
        end)
    end

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = SafeGetVerticalScroll(self)
        local maxScroll = SafeGetVerticalScrollRange(self)
        local okNew, newScroll = pcall(function()
            return math.max(0, math.min(currentScroll - (delta * SCROLL_STEP), maxScroll))
        end)
        if okNew then
            pcall(self.SetVerticalScroll, self, newScroll)
        end
    end)

    panel._scrollFrame = scrollFrame
    panel._content = content

    -- Placeholder message (shown when no provider exists)
    local placeholder = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("TOP", content, "TOP", 0, -40)
    placeholder:SetTextColor(0.6, 0.65, 0.7, 1)
    placeholder:SetText("No settings available for this frame.")
    placeholder:SetJustifyH("CENTER")
    placeholder:Hide()
    panel._placeholder = placeholder

    return panel
end

---------------------------------------------------------------------------
-- POSITIONING (adjacent to the slide-out drawer)
---------------------------------------------------------------------------

local function PositionAdjacentToDrawer(panel)
    local ui = ns.QUI_LayoutMode_UI
    -- Prefer anchoring to drawer if visible, fall back to toolbar panel
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
        -- Drawer is to the right of toolbar; settings goes right of drawer
        local anchorRight = anchor:GetRight()
        if anchorRight then
            x = anchorRight + gap
            if x + panelW > screenW then
                -- Not enough space right, try left of toolbar
                local tabLeft = ui._toolbar and ui._toolbar:GetLeft()
                x = tabLeft and (tabLeft - panelW - gap) or (screenW - panelW - gap)
            end
        else
            x = gap
        end
    else
        -- Drawer is to the left of toolbar; settings goes left of drawer
        local anchorLeft = anchor:GetLeft()
        if anchorLeft then
            x = anchorLeft - panelW - gap
            if x < 0 then
                -- Not enough space left, try right of toolbar
                local tabRight = ui._toolbar and ui._toolbar:GetRight()
                x = tabRight and (tabRight + gap) or gap
            end
        else
            x = screenW - panelW - gap
        end
    end

    -- Vertical: align top with anchor, clamp to screen
    local anchorTop = anchor:GetTop()
    y = math.min(anchorTop or (screenH - gap), screenH - gap)
    y = math.max(y, panelH + gap)

    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

---------------------------------------------------------------------------
-- CONTENT MANAGEMENT
---------------------------------------------------------------------------

local function ClearContent(panel)
    local content = panel._content
    local GUI = _G.QUI and _G.QUI.GUI

    -- Save collapsible expanded states before clearing
    local expandedStates = {}
    for _, child in pairs({content:GetChildren()}) do
        if child._expanded ~= nil and child._sectionTitle then
            expandedStates[child._sectionTitle] = child._expanded
        end
    end
    QUI_LayoutMode_Settings._expandedStates = expandedStates

    -- Restore the true original SetHeight before clearing, so stacked hooks
    -- from previous BuildContent calls don't accumulate and corrupt heights.
    if content._origSetHeight then
        content.SetHeight = content._origSetHeight
    end

    if GUI and GUI.CleanupWidgetTree then
        GUI:CleanupWidgetTree(content)
    end

    -- Hide and release children
    for _, child in pairs({content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    -- Hide font strings (except placeholder)
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

--- Build the anchor chain text for a given frame key.
--- Returns a string like "Frame > Parent > Grandparent > Screen Center"
local function BuildAnchorChainText(key)
    local um = ns.QUI_LayoutMode
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
            -- Frame has no anchoring entry — it's positioned by layout mode
            local info = ns.FRAME_ANCHOR_INFO and ns.FRAME_ANCHOR_INFO[current]
            local name = info and info.displayName or current
            table.insert(lines, name .. "  (layout mode)")
            break
        end

        local parent = entry.parent
        local pt = entry.point or "CENTER"
        local rel = entry.relative or "CENTER"

        local info = ns.FRAME_ANCHOR_INFO and ns.FRAME_ANCHOR_INFO[current]
        local name = info and info.displayName or current

        if not parent or parent == "disabled" then
            table.insert(lines, name .. "  (disabled)")
            break
        elseif parent == "screen" then
            table.insert(lines, string.format("%s  [%s]", name, pt))
            table.insert(lines, string.format("  -> Screen  [%s]", rel))
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
        return "No anchor chain"
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
            pcall(feature.onNavigate, key, nil, {
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
            local ok2, h = pcall(Renderer.RenderFeature, Renderer, feature, content, {
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

    -- Anchoring Details section — appended after provider content
    if U and U.CreateCollapsible then
        -- Determine anchor status. Features whose anchor lives outside the
        -- shared frameAnchoring table (e.g. DandersFrames stores anchor in
        -- db.dandersFrames.<container>) can override this via feature.getAnchorStatus.
        local statusText
        local customStatus
        if feature and type(feature.getAnchorStatus) == "function" then
            local ok, result = pcall(feature.getAnchorStatus, key)
            if ok and type(result) == "table" then
                customStatus = result
            end
        end

        if customStatus then
            if customStatus.enabled then
                statusText = "|cff888888Anchoring:|r  |cff34D399Enabled|r"
            else
                statusText = "|cff888888Anchoring:|r  |cffFF6666Disabled|r"
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
                statusText = "|cff888888Anchoring:|r  |cffFF6666Disabled|r"
            else
                local parent = anchorEntry.parent
                if not parent or parent == "disabled" then
                    statusText = "|cff888888Anchoring:|r  |cffFF6666Disabled|r"
                else
                    statusText = "|cff888888Anchoring:|r  |cff34D399Enabled|r"
                end
            end
        end

        local chainText
        if customStatus then
            if customStatus.enabled and customStatus.parent then
                local info = ns.FRAME_ANCHOR_INFO and ns.FRAME_ANCHOR_INFO[customStatus.parent]
                local parentName = info and info.displayName or customStatus.parent
                chainText = "Anchored to: " .. parentName
            else
                chainText = "No anchor chain"
            end
        else
            chainText = BuildAnchorChainText(key)
        end

        local infoSection = CreateFrame("Frame", nil, content)
        local HEADER_HEIGHT = U.HEADER_HEIGHT or 24

        -- Build collapsible manually here to avoid needing sections/relayout
        local btn = CreateFrame("Button", nil, infoSection)
        btn:SetPoint("TOPLEFT", 0, 0)
        btn:SetPoint("TOPRIGHT", 0, 0)
        btn:SetHeight(HEADER_HEIGHT)

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
        }) or btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if not (UIKit and UIKit.CreateChevronCaret) then
            chevron:SetPoint("LEFT", 2, 0)
            chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
        label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        label:SetText("Anchoring Details")

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

        local body = CreateFrame("Frame", nil, bodyClip)
        body:SetWidth(1)
        bodyClip:SetScrollChild(body)
        bodyClip:SetScript("OnSizeChanged", function(self, width)
            body:SetWidth(math.max(width or 1, 1))
        end)
        body:SetAlpha(0)

        -- Anchor status line
        local statusLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusLabel:SetPoint("TOPLEFT", 8, -6)
        statusLabel:SetPoint("RIGHT", body, "RIGHT", -8, 0)
        statusLabel:SetJustifyH("LEFT")
        statusLabel:SetText(statusText)

        -- Chain text
        local chainLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        chainLabel:SetPoint("TOPLEFT", 8, -(6 + statusLabel:GetStringHeight() + 6))
        chainLabel:SetPoint("RIGHT", body, "RIGHT", -8, 0)
        chainLabel:SetTextColor(0.85, 0.85, 0.85, 1)
        chainLabel:SetJustifyH("LEFT")
        chainLabel:SetJustifyV("TOP")
        chainLabel:SetWordWrap(true)
        chainLabel:SetSpacing(3)
        chainLabel:SetText(chainText)

        local bodyHeight = 6 + statusLabel:GetStringHeight() + 6 + chainLabel:GetStringHeight() + 10
        body:SetHeight(bodyHeight)

        -- Default to expanded
        infoSection._expanded = true
        infoSection._sectionTitle = "Anchoring Details"
        if not (UIKit and UIKit.CreateChevronCaret) then
            chevron:SetText("v")
        end
        bodyClip:Show()
        bodyClip:SetHeight(bodyHeight)
        body:SetAlpha(1)
        infoSection:SetHeight(HEADER_HEIGHT + bodyHeight)

        -- Position Info section dynamically below provider content.
        -- Hook content's SetHeight so Info repositions when provider sections expand/collapse.
        -- Store the true original once so ClearContent can restore it (prevents hook stacking).
        if not content._origSetHeight then
            content._origSetHeight = content.SetHeight
        end
        local origSetHeight = content._origSetHeight
        local function repositionInfo()
            -- Use providerHeight (set by StandardRelayout via SetHeight override)
            -- instead of spatial queries, which are unreliable during build when
            -- frames haven't been rendered yet (causes overlay on expanded sections).
            infoSection:ClearAllPoints()
            infoSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(providerHeight + 4))
            infoSection:SetPoint("RIGHT", content, "RIGHT", 0, 0)

            local totalH = providerHeight + 8 + infoSection:GetHeight()
            origSetHeight(content, totalH)
        end

        -- Restore collapsed state if user previously collapsed it
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
            -- Update providerHeight from the value StandardRelayout computed,
            -- then reposition the Info section below all provider sections.
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

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

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

    panel._titleText:SetText("|cff60A5FA" .. label .. "|r Settings")

    -- New key: rebuild content, only reposition if panel isn't already open
    if self._currentKey ~= key then
        local wasShown = panel:IsShown()
        self._currentKey = key
        BuildContent(panel, key)

        -- Position adjacent to drawer on first open (not when switching between movers)
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
    -- Deselect mover (stops pixel glow) — guard against re-entry
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

function QUI_LayoutMode_Settings:Reset()
    self:Hide()
    self._currentKey = nil
end

function QUI_LayoutMode_Settings:IsShown()
    return self._panel and self._panel:IsShown()
end


--- Force rebuild of current content (e.g., after DB change).
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

--- Reset state when Layout Mode closes.
function QUI_LayoutMode_Settings:Reset()
    self:Hide()
    self._currentKey = nil
    if self._panel then
        self._panel._userDragged = nil
    end
end
