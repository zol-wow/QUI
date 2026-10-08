local _, ns = ...
local GUI = QUI.GUI
local UIKit = ns.UIKit

local groups = {
    { ns.L["Setup"], { "welcome", "global", "help" } },
    { ns.L["Frames & Bars"], { "unit_frames", "group_frames", "nameplates", "action_bars" } },
    { ns.L["Abilities & Auras"], { "cooldown_manager", "resource_bars", "auras" } },
    { ns.L["Interface"], { "appearance", "minimap", "infobar", "chat_tooltips", "bags", "alts" } },
    { ns.L["Gameplay & Utilities"], { "gameplay", "qol" } },
}

local function Owner(body)
    local pageIndex
    while body do
        pageIndex = pageIndex or body._quiOptionsSubPageIndex
        if body._quiOptionsTile then return body._quiOptionsTile, pageIndex or 1 end
        body = body.GetParent and body:GetParent()
    end
end

local function Font(label, size)
    local path = GUI:GetFontPath()
    ns.Helpers.ApplyFontWithFallback(label, path, size, "")
    label:SetTextColor(unpack(GUI.Colors.text))
end

function GUI:IsOptionsMotionEnabled()
    local profile = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile
        or QUI.db and QUI.db.profile
    return not (profile and profile.general and profile.general.optionsMotion == false)
end

function GUI:StopOptionsPageAnimation(page)
    if not page then return end
    if UIKit.CancelValueAnimation then UIKit.CancelValueAnimation(page, "options-page") end
    page:SetAlpha(1)
    local anchor = page._optionsEntranceAnchor
    if anchor then page:SetPoint("TOPLEFT", anchor.relativeTo, "TOPRIGHT", anchor.x, anchor.y) end
end

function GUI:AnimateOptionsPage(page)
    if not page then return end
    self:StopOptionsPageAnimation(page)
    if not self:IsOptionsMotionEnabled() or not UIKit.AnimateValue then return end
    local anchor = page._optionsEntranceAnchor
    UIKit.AnimateValue(page, "options-page", {
        fromValue = 0, toValue = 1, duration = anchor and 0.13 or 0.15,
        onUpdate = function(owner, _, progress)
            local eased = 1 - (1 - progress) ^ 3
            owner:SetAlpha(0.25 + 0.75 * eased)
            if anchor then owner:SetPoint("TOPLEFT", anchor.relativeTo, "TOPRIGHT", anchor.x, anchor.y - 3 * (1 - eased)) end
        end,
    })
end

function GUI:RefreshOptionsMotion()
    local frame = self.MainFrame
    if not frame or self:IsOptionsMotionEnabled() then return end
    for _, tile in ipairs(frame._tiles or {}) do
        if tile._pageFrame then
            self:StopOptionsPageAnimation(tile._pageFrame)
        end
    end
    if frame._pageFlyout then
        self:StopOptionsPageAnimation(frame._pageFlyout)
    end
    local function RefreshToggles(parent)
        if parent.GetToggleProgress and parent.Refresh then parent.Refresh() end
        for _, child in ipairs({ parent:GetChildren() }) do RefreshToggles(child) end
    end
    RefreshToggles(frame)
end

function GUI:PushNavigationHistory(frame)
    local tile = frame._tiles and frame._tiles[frame._lastTileIndex or 0]
    if not tile then return end
    local pageIndex = tile._activeSubPageIndex or 1
    local descriptor = tile._surfacePagesByPage and tile._surfacePagesByPage[pageIndex]
    local box = frame._searchBox and frame._searchBox.editBox
    local entry = {
        tileIndex = tile.index, pageIndex = pageIndex,
        key = descriptor and descriptor.getActiveTab and descriptor.getActiveTab(),
        query = box and box:GetText() or "",
    }
    frame._navigationHistory = frame._navigationHistory or {}
    local history = frame._navigationHistory
    local previous = history[#history]
    if not previous or previous.tileIndex ~= entry.tileIndex or previous.pageIndex ~= entry.pageIndex
        or previous.key ~= entry.key or previous.query ~= entry.query then
        history[#history + 1] = entry
        if #history > 40 then table.remove(history, 1) end
    end
    if frame._navigationBack then frame._navigationBack:Enable() end
end

function GUI:NavigateOptionsBack(frame)
    local history = frame._navigationHistory or {}
    local entry = table.remove(history)
    if not entry then return end
    self:SelectFeatureTile(frame, entry.tileIndex, { subPageIndex = entry.pageIndex, noHistory = true })
    local tile = frame._tiles[entry.tileIndex]
    local descriptor = tile._surfacePagesByPage and tile._surfacePagesByPage[entry.pageIndex]
    if entry.key and descriptor and descriptor.selectTab then descriptor.selectTab(entry.key) end
    if entry.query ~= "" and frame._searchBox and frame._searchBox.editBox then
        frame._searchBox.editBox:SetText(entry.query)
        frame._searchBox.onSearch(entry.query)
    end
    if frame._navigationBack then frame._navigationBack:SetEnabled(#history > 0) end
end

function GUI:CreateNavigationBackButton(frame, searchContainer)
    local button = self:CreateButton(frame, "<", 28, 28, function() GUI:NavigateOptionsBack(frame) end, "ghost", ns.L["Back"])
    button:SetPoint("RIGHT", searchContainer, "LEFT", -8, 0)
    button:Disable()
    frame._navigationBack = button
end

function GUI:RegisterTileSurfacePages(body, descriptor)
    local tile, pageIndex = Owner(body)
    if not tile then return false end
    tile._surfacePagesByPage = tile._surfacePagesByPage or {}
    tile._surfacePagesByPage[pageIndex] = descriptor
    descriptor.owner = body
    self:RefreshTileSurfacePages(body)
    return true
end

function GUI:GetTileNavigationPages(tile)
    local result = {}
    local activePage = tile._activeSubPageIndex or 1
    local function SurfacePages(index, prefix)
        local descriptor = tile._surfacePagesByPage and tile._surfacePagesByPage[index]
        if not descriptor or type(descriptor.getTabs) ~= "function" then return false end
        local activeKey = descriptor.getActiveTab and descriptor.getActiveTab()
        local tabs = descriptor.getTabs() or {}
        for _, tab in ipairs(tabs) do
            result[#result + 1] = {
                label = tab.label or tab.key, group = prefix or nil, key = tab.key, pageIndex = index,
                descriptor = descriptor,
                active = tile._isActive and index == activePage and tab.key == activeKey,
                disabled = tab.disabled == true or tab.enabled == false,
            }
        end
        return #tabs > 0
    end
    local function Sections(index, group)
        local first = #result
        local page = tile._subPageBodies and tile._subPageBodies[index]
        local body = page and page._contentBody
        local selected
        local scroll = page and page._scrollFrame
        local viewportTop = scroll and scroll:GetTop()
        local scrollRange = scroll and scroll:GetVerticalScrollRange() or 0
        local progress = scrollRange > 0 and math.min(1, math.max(0, scroll:GetVerticalScroll() / scrollRange)) or 0
        local position = viewportTop and viewportTop - (scroll and scroll:GetHeight() or 0) * progress
        if scroll and not scroll._quiNavigationSectionHook then
            scroll._quiNavigationSectionHook = true
            scroll:HookScript("OnVerticalScroll", function() GUI:RefreshNavigationSectionHighlight(tile) end)
        end
        for _, section in ipairs(body and body._sections or {}) do
            if section.frame and section.frame:IsShown() then
                result[#result + 1] = {
                    label = section.label or section.id, group = group, pageIndex = index,
                    section = section.frame, sectionId = section.id,
                }
                local top = section.frame:GetTop()
                if not selected or (position and top and top >= position - 8) then selected = #result end
            end
        end
        if selected then result[selected].active = tile._isActive and index == activePage end
        return #result > first
    end
    local subPages = tile.config.subPages
    if subPages and #subPages > 0 then
        if #subPages == 1 then
            if not SurfacePages(1, false) and subPages[1].sectionNav then Sections(1) end
            if #result > 0 then return result end
        end
        for index, subPage in ipairs(subPages) do
            if not (subPage.sectionNav and Sections(index, subPage.name)) then
                result[#result + 1] = {
                    label = subPage.name, pageIndex = index,
                    active = tile._isActive and index == activePage,
                }
                if index == activePage then SurfacePages(index, subPage.name) end
            end
        end
    else
        SurfacePages(1, false)
    end
    return result
end

function GUI:RefreshTileSurfacePages(body)
    local tile = Owner(body)
    if tile then self:UpdateTileNavigationTitle(tile) end
end

function GUI:UpdateTileNavigationTitle(tile)
    if not tile or not tile._title then return end
    local pageIndex = tile._activeSubPageIndex or 1
    local page = tile.config.subPages and tile.config.subPages[pageIndex]
    local title = page and page.name or tile.config.name
    local descriptor = tile._surfacePagesByPage and tile._surfacePagesByPage[pageIndex]
    if descriptor and descriptor.getTabs then
        local active = descriptor.getActiveTab and descriptor.getActiveTab()
        for _, tab in ipairs(descriptor.getTabs() or {}) do
            if tab.key == active then
                title = tab.label or tab.key
                break
            end
        end
    end
    tile._title:SetText(title)
    if tile._navArrow then tile._navArrow:SetShown(#self:GetTileNavigationPages(tile) > 1) end
    if tile._isActive then
        self:RefreshNavigationDock(self.MainFrame)
        self:RememberNavigationDestination(self.MainFrame, tile, descriptor)
    end
end

function GUI:CloseNavigationFlyout(frame)
    frame._navHoverToken = (frame._navHoverToken or 0) + 1
    frame._navHoverTile = nil
    local flyout = frame._pageFlyout
    if not flyout then return end
    flyout:Hide()
    flyout._tile = nil
    flyout._pinned = false
    flyout._keyboard = false
end

local function Highlight(flyout, index)
    flyout._keyboardIndex = index
    for i, button in ipairs(flyout._buttons) do
        if button:IsShown() then
            button._wash:SetShown((flyout._keyboard and i == index) or button._hovered or button._page.active)
            button._label:SetTextColor(unpack(GUI.Colors.text))
        end
    end
    local button = flyout._buttons[index]
    if button and flyout._keyboard then
        local top = button._navTop or (index - 1) * 30
        local scroll = flyout._scroll:GetVerticalScroll()
        local view = flyout._scroll:GetHeight()
        if top < scroll then flyout._scroll:SetVerticalScroll(top)
        elseif top + 30 > scroll + view then flyout._scroll:SetVerticalScroll(top + 30 - view) end
    end
end

function GUI:RefreshNavigationSectionHighlight(tile)
    local frame = self.MainFrame
    if not frame then return end
    local current = self:GetTileNavigationPages(tile)
    for _, panel in pairs({ frame._pageDock, frame._pageFlyout }) do
        if panel._tile == tile and panel:IsShown() then
            for i, button in ipairs(panel._buttons) do
                if button:IsShown() and current[i] then button._page.active = current[i].active end
            end
            Highlight(panel, panel._keyboardIndex or 1)
        end
    end
end

local function SelectPage(frame, tile, page)
    if page.disabled then return end
    GUI:CloseNavigationFlyout(frame)
    GUI:SelectFeatureTile(frame, tile.index, { subPageIndex = page.pageIndex })
    if page.descriptor and page.descriptor.selectTab then page.descriptor.selectTab(page.key) end
    if page.section then
        C_Timer.After(0, function()
            local owner = tile._subPageBodies and tile._subPageBodies[page.pageIndex]
            local scroll = owner and owner._scrollFrame
            local sections = owner and owner._contentBody and owner._contentBody._sections or {}
            local visible = {}
            local selected
            for _, section in ipairs(sections) do
                if section.frame and section.frame:IsShown() then
                    visible[#visible + 1] = section.frame
                    if section.frame == page.section or (page.sectionId and section.id == page.sectionId) then selected = #visible end
                end
            end
            local body = scroll and scroll:GetScrollChild()
            local top = body and body:GetTop()
            local sectionTop = selected and visible[selected]:GetTop()
            if top and sectionTop then
                local range = scroll:GetVerticalScrollRange()
                local extent = range + scroll:GetHeight()
                local nextTop = visible[selected + 1] and visible[selected + 1]:GetTop()
                local position = math.max(0, top - sectionTop)
                local offset = math.min(range, position)
                if nextTop and extent > 0 then
                    local endOffset = math.max(0, top - nextTop - 9) * range / extent
                    offset = math.min(offset, endOffset)
                end
                if selected == 1 then offset = 0 end
                offset = math.min(range, math.max(0, offset))
                local controller = UIKit.GetSmoothScroll and UIKit.GetSmoothScroll(scroll)
                if controller then controller:ScrollTo(offset, true) else scroll:SetVerticalScroll(offset) end
                GUI:RefreshNavigationSectionHighlight(tile)
            end
        end)
    end
    GUI:UpdateTileNavigationTitle(tile)
    GUI:AnimateOptionsPage(tile._pageFrame)
end

local function CreateFlyout(frame, docked)
    local C = GUI.Colors
    local flyout = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    flyout:SetFrameLevel(frame:GetFrameLevel() + 70)
    flyout:SetWidth(270)
    flyout:EnableMouse(true)
    if UIKit.CreateRoundedSurface then
        UIKit.CreateRoundedSurface(flyout, {
            radius = 8, bgColor = C.bgElevated or C.bgLight,
            borderColor = { 0.40, 0.52, 0.50, 0.45 },
        })
    else
        UIKit.CreateBackground(flyout, C.bgLight[1], C.bgLight[2], C.bgLight[3], 1)
        UIKit.CreateBorderLines(flyout)
        UIKit.UpdateBorderLines(flyout, 1, C.borderStrong[1], C.borderStrong[2], C.borderStrong[3], 1)
    end
    flyout._title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Font(flyout._title, 15)
    flyout._title:SetPoint("TOPLEFT", 13, -12)
    flyout._title:SetPoint("RIGHT", -30, 0)
    flyout._title:SetJustifyH("LEFT")
    flyout._hint = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Font(flyout._hint, 10)
    flyout._hint:SetTextColor(unpack(C.textDim))
    flyout._hint:SetPoint("TOPLEFT", 13, -33)
    flyout._hint:SetPoint("RIGHT", -10, 0)
    flyout._hint:SetJustifyH("LEFT")
    UIKit.CreateCloseButton(flyout, {
        size = 18, point = "TOPRIGHT", relativeTo = flyout, x = -6, y = -6,
        onClick = function()
            if docked then GUI:SetNavigationDocked(frame, false) else GUI:CloseNavigationFlyout(frame) end
        end,
    })
    local scroll = CreateFrame("ScrollFrame", nil, flyout)
    scroll:SetPoint("TOPLEFT", 6, -56)
    scroll:SetPoint("TOPRIGHT", -12, -56)
    scroll:SetHeight(1)
    local inner = CreateFrame("Frame", nil, scroll)
    inner:SetWidth(250)
    inner:SetHeight(1)
    scroll:SetScrollChild(inner)
    flyout._scroll, flyout._inner = scroll, inner
    flyout._buttons = {}
    local function Range()
        local overflow = inner:GetHeight() - scroll:GetHeight()
        return overflow > 0.5 and overflow or 0
    end
    scroll:SetScript("OnSizeChanged", function(_, width) inner:SetWidth(math.max(1, width)) end)
    flyout._scrollbar = UIKit.CreateScrollBar(scroll, { parent = flyout, anchor = scroll, offsetX = -1, width = 4, getRange = Range })
    UIKit.AttachSmoothScroll(scroll, { step = 60, getRange = Range })
    if not docked then
    flyout:SetScript("OnUpdate", function(self, elapsed)
        local over = self:IsMouseOver() or (self._tile and self._tile:IsMouseOver())
            or (frame._navHoverTile and frame._navHoverTile:IsMouseOver())
        local dragging = self._scrollbar and self._scrollbar:IsDragging()
        if self._pinned or self._keyboard or over or dragging then self._away = 0; return end
        self._away = (self._away or 0) + elapsed
        if self._away >= 0.3 then GUI:CloseNavigationFlyout(frame) end
    end)
    flyout:RegisterEvent("GLOBAL_MOUSE_DOWN")
    flyout:SetScript("OnHide", function(self) GUI:StopOptionsPageAnimation(self) end)
    flyout:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not (self._tile and self._tile:IsMouseOver()) then
            GUI:CloseNavigationFlyout(frame)
        end
    end)
    end
    flyout:Hide()
    if docked then frame._pageDock = flyout else frame._pageFlyout = flyout end
    return flyout
end

local function RenderPages(frame, flyout, tile, pages)
    for _, button in ipairs(flyout._buttons) do button:Hide() end
    flyout._headings = flyout._headings or {}
    for _, heading in ipairs(flyout._headings) do heading:Hide(); heading._divider:Hide() end
    local activeIndex = 1
    local offset, group, headingIndex = 0, nil, 0
    for index, page in ipairs(pages) do
        if page.group and page.group ~= group then
            if offset > 0 then offset = offset + 12 end
            headingIndex = headingIndex + 1
            local heading = flyout._headings[headingIndex]
            if not heading then
                heading = flyout._inner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                Font(heading, 12)
                ns.Helpers.ApplyFontWithFallback(heading, ns.Helpers.AssetPath .. "Poppins-Bold.ttf", 11, "")
                heading._divider = flyout._inner:CreateTexture(nil, "ARTWORK")
                heading._divider:SetColorTexture(GUI.Colors.text[1], GUI.Colors.text[2], GUI.Colors.text[3], 0.22)
                heading._divider:SetHeight(1)
                heading._divider:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
                heading:SetJustifyH("LEFT")
                flyout._headings[headingIndex] = heading
            end
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", 10, -offset - 5)
            heading:SetPoint("RIGHT", -8, 0)
            heading:SetText(page.group)
            heading._divider:SetWidth(math.min(heading:GetStringWidth(), heading:GetWidth()))
            heading:Show()
            heading._divider:Show()
            offset = offset + 30
        end
        group = page.group
        local button = flyout._buttons[index]
        if not button then
            button = CreateFrame("Button", nil, flyout._inner)
            button:SetHeight(30)
            button:SetPoint("TOPLEFT", 0, -(index - 1) * 30)
            button:SetPoint("RIGHT", 0, 0)
            button._wash = button:CreateTexture(nil, "BACKGROUND")
            button._wash:SetAllPoints()
            button._wash:SetColorTexture(GUI.Colors.accent[1], GUI.Colors.accent[2], GUI.Colors.accent[3], 0.13)
            button._label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            Font(button._label, 12)
            button._label:SetPoint("LEFT", 10, 0)
            button._label:SetPoint("RIGHT", -8, 0)
            button._label:SetJustifyH("LEFT")
            button._label:SetWordWrap(false)
            button:SetScript("OnEnter", function(self) self._hovered = true; Highlight(flyout, self._index) end)
            button:SetScript("OnLeave", function(self) self._hovered = nil; Highlight(flyout, flyout._keyboardIndex or 1) end)
            button:SetScript("OnClick", function(self) SelectPage(frame, flyout._tile, self._page) end)
            flyout._buttons[index] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, -offset)
        button:SetPoint("RIGHT", 0, 0)
        button._navTop = offset
        offset = offset + 30
        button._index, button._page = index, page
        button._label:ClearAllPoints()
        button._label:SetPoint("LEFT", page.group and 18 or 10, 0)
        button._label:SetPoint("RIGHT", -8, 0)
        button._label:SetText(page.label)
        button:SetEnabled(not page.disabled)
        button:Show()
        if page.active then activeIndex = index end
    end
    flyout._contentHeight = offset
    flyout._inner:SetHeight(math.max(1, offset))
    Highlight(flyout, activeIndex)
    return activeIndex
end

function GUI:OpenNavigationFlyout(frame, tile, pinned, keyboard)
    if not frame:IsShown() then return false end
    local existing = frame._pageFlyout
    local keepOpen = pinned == true or (existing and existing:IsShown() and existing._pinned) or false
    if existing and existing:IsShown() and existing._tile == tile and not pinned then return true end
    if pinned or keyboard then
        local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focused and focused.ClearFocus then focused:ClearFocus() end
    end
    self:BuildTilePage(frame, tile)
    local pages = self:GetTileNavigationPages(tile)
    if #pages <= 1 then self:CloseNavigationFlyout(frame); return false end
    frame._navHoverToken = (frame._navHoverToken or 0) + 1
    frame._navHoverTile = nil
    local flyout = existing or CreateFlyout(frame)
    flyout._tile, flyout._pinned, flyout._keyboard = tile, keepOpen, keyboard == true
    flyout._away = 0
    flyout._pages = pages
    flyout._title:SetText(tile.config.name)
    flyout._hint:SetText(ns.L["Choose a page · Click module to close"])
    local activeIndex = RenderPages(frame, flyout, tile, pages)
    local width = math.min(280, math.max(180, frame:GetWidth() - frame.sidebar:GetWidth() - 40))
    flyout:SetWidth(width)
    flyout._inner:SetWidth(width - 18)
    flyout._inner:SetHeight(math.max(1, flyout._contentHeight))
    local height = math.min(63 + flyout._contentHeight, math.max(100, frame:GetHeight() - 65))
    flyout:SetHeight(height)
    flyout._scroll:SetHeight(math.max(1, height - 63))
    local top = math.max(42, math.min((frame:GetTop() or 0) - (tile:GetTop() or 0), frame:GetHeight() - height - 10))
    flyout:ClearAllPoints()
    local y = (frame:GetTop() or 0) - (frame.sidebar:GetTop() or 0) - top
    flyout._optionsEntranceAnchor = { relativeTo = frame.sidebar, x = 0, y = y }
    flyout:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 0, y)
    flyout._scroll:SetVerticalScroll(0)
    flyout:Show()
    if flyout._scrollbar and flyout._scrollbar.Update then flyout._scrollbar:Update() end
    Highlight(flyout, activeIndex)
    self:AnimateOptionsPage(flyout)
    return true
end

local function NavigationProfile()
    local profile = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile or QUI.db and QUI.db.profile
    return profile and profile.general
end

function GUI:SetNavigationDocked(frame, enabled)
    local general = NavigationProfile()
    if general then general.optionsNavigationDocked = enabled end
    self:CloseNavigationFlyout(frame)
    self:RefreshNavigationDock(frame)
end

function GUI:RefreshNavigationDock(frame)
    if not frame or not frame.contentArea or not frame.sidebar or frame._refreshingNavigationDock then return end
    frame._refreshingNavigationDock = true
    local general = NavigationProfile()
    local available = frame:GetWidth() - frame.sidebar:GetWidth() - 25
    local scale = frame.GetScale and frame:GetScale() or 1
    local fits = available >= 840 and (available - 196) * scale >= 720
    local enabled = fits and not (general and general.optionsNavigationDocked == false)
    local tile = frame._tiles and frame._tiles[frame._lastTileIndex or 0]
    local pages = tile and self:GetTileNavigationPages(tile) or {}
    local docked = enabled and #pages > 1
    frame._navigationDocked = enabled
    if not frame._navigationModeButton and frame._searchBox then
        frame._navigationModeButton = self:CreateButton(frame, ns.L["Dock pages"], 132, 28, function()
            GUI:SetNavigationDocked(frame, not frame._navigationDocked)
        end, "ghost")
        local searchContainer = frame._searchBox:GetParent()
        searchContainer:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 188, -7)
        frame._navigationModeButton:SetPoint("RIGHT", searchContainer, "LEFT", -8, 0)
        if frame._navigationBack then
            frame._navigationBack:ClearAllPoints()
            frame._navigationBack:SetPoint("RIGHT", frame._navigationModeButton, "LEFT", -8, 0)
        end
    end
    local button = frame._navigationModeButton
    if button then
        button:SetText(enabled and ns.L["Compact navigation"] or ns.L["Dock pages"])
        button:SetEnabled(fits)
    end
    if docked then
        local dock = frame._pageDock or CreateFlyout(frame, true)
        dock._tile, dock._pages, dock._pinned = tile, pages, true
        dock._title:SetText(tile.config.name)
        dock._hint:SetText(ns.L["Pages"])
        dock:ClearAllPoints()
        dock:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 5, -44)
        dock:SetPoint("BOTTOMLEFT", frame.contentArea, "BOTTOMLEFT", -196, 0)
        dock:SetWidth(184)
        dock._scroll:SetHeight(math.max(1, frame.contentArea:GetHeight() - 63))
        RenderPages(frame, dock, tile, pages)
        dock:Show()
        if dock._scrollbar and dock._scrollbar.Update then dock._scrollbar:Update() end
    elseif frame._pageDock then frame._pageDock:Hide() end
    frame.contentArea:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", docked and 201 or 5, -44)
    frame._refreshingNavigationDock = nil
end

function GUI:AttachTileNavigation(frame, tile)
    local arrow = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Font(arrow, 14)
    arrow:SetText(">")
    arrow:SetPoint("RIGHT", tile, "RIGHT", -9, 0)
    arrow:SetTextColor(unpack(self.Colors.textDim))
    tile._navArrow = arrow
    if tile.moduleToggle then
        tile.moduleToggle:ClearAllPoints()
        tile.moduleToggle:SetPoint("RIGHT", arrow, "LEFT", -8, 1)
    end
    if tile.id == "welcome" then arrow:Hide() end
    tile.text:SetPoint("RIGHT", tile, "RIGHT", tile.moduleToggle and -55 or -23, 0)
    tile:HookScript("OnEnter", function()
        if frame._navigationDocked then return end
        frame._navHoverToken = (frame._navHoverToken or 0) + 1
        frame._navHoverTile = tile
        local token = frame._navHoverToken
        C_Timer.After(0.25, function()
            if token == frame._navHoverToken and frame._navHoverTile == tile then
                frame._navHoverTile = nil
                if tile:IsMouseOver() and frame:IsShown() then GUI:OpenNavigationFlyout(frame, tile) end
            end
        end)
    end)
    tile:HookScript("OnLeave", function()
        if frame._navHoverTile == tile then
            frame._navHoverToken = (frame._navHoverToken or 0) + 1
            frame._navHoverTile = nil
        end
    end)
    tile:SetScript("OnClick", function()
        if frame._navigationDocked then GUI:SelectFeatureTile(frame, tile.index); return end
        local flyout = frame._pageFlyout
        if flyout and flyout:IsShown() and flyout._tile == tile then
            GUI:CloseNavigationFlyout(frame)
        elseif not GUI:OpenNavigationFlyout(frame, tile, true) then
            GUI:SelectFeatureTile(frame, tile.index)
        end
    end)
end

function GUI:LayoutSidebarGroups(frame)
    local parent = frame._sidebarScrollChild
    if not parent then return end
    frame._sidebarGroups = frame._sidebarGroups or {}
    local byId = {}
    for _, tile in ipairs(frame._tiles) do byId[tile.id] = tile end
    local y = 5
    local assigned = {}
    for index, definition in ipairs(groups) do
        local label = frame._sidebarGroups[index]
        if not label then
            label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            Font(label, 9)
            label:SetTextColor(unpack(self.Colors.sectionLabel))
            label:SetJustifyH("LEFT")
            frame._sidebarGroups[index] = label
        end
        label:SetText(definition[1])
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y)
        label:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
        y = y + 24
        for _, id in ipairs(definition[2]) do
            local tile = byId[id]
            if tile then
                tile:SetParent(parent)
                tile._sidebarBucket = "top"
                tile._sidebarTop = y
                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -y)
                tile:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -y)
                y = y + tile:GetHeight() + 2
                assigned[tile] = true
            end
        end
        y = y + 5
    end
    for _, tile in ipairs(frame._tiles) do
        if not assigned[tile] then
            tile:SetParent(parent)
            tile._sidebarBucket, tile._sidebarTop = "top", y
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -y)
            tile:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -y)
            y = y + tile:GetHeight() + 2
        end
    end
    parent:SetHeight(y)
    frame._bottomTiles = {}
    frame._sidebarScroll:SetPoint("TOPLEFT", frame.sidebar, "TOPLEFT", 0, -4)
    frame._sidebarScroll:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", 0, frame._toolsStrip and 102 or 8)
    if frame._sidebarClampScroll then frame._sidebarClampScroll() end
    if UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(frame, "optionsNavigationDock", function() GUI:RefreshNavigationDock(frame) end)
    end
    frame:HookScript("OnHide", function() GUI:CloseNavigationFlyout(frame) end)
    frame:HookScript("OnSizeChanged", function() GUI:CloseNavigationFlyout(frame); GUI:RefreshNavigationDock(frame) end)
    frame._sidebarScroll:HookScript("OnVerticalScroll", function() GUI:CloseNavigationFlyout(frame) end)
end

function GUI:HandleNavigationKey(frame, key)
    local dock = frame._pageDock
    if dock and dock:IsShown() and key == "RIGHT" then
        dock._keyboard = true
        Highlight(dock, dock._keyboardIndex or 1)
        return true
    end
    local flyout = dock and dock:IsShown() and dock._keyboard and dock or frame._pageFlyout
    if not flyout or not flyout:IsShown() then
        if key == "RIGHT" then
            local tile = frame._tiles and frame._tiles[frame._lastTileIndex or 1]
            return tile and self:OpenNavigationFlyout(frame, tile, true, true) or false
        end
        return false
    end
    if key == "ESCAPE" or key == "LEFT" then
        if flyout == dock then dock._keyboard = false else self:CloseNavigationFlyout(frame) end
        return true
    end
    if key == "UP" or key == "DOWN" or key == "TAB" or key == "HOME" or key == "END" then
        flyout._keyboard = true
        local index = flyout._keyboardIndex or 1
        if key == "HOME" then index = 1
        elseif key == "END" then index = #flyout._pages
        else index = (index - 1 + (key == "UP" and -1 or 1)) % #flyout._pages + 1 end
        Highlight(flyout, index)
        return true
    end
    if key == "ENTER" or key == "SPACE" then
        flyout._keyboard = false
        SelectPage(frame, flyout._tile, flyout._pages[flyout._keyboardIndex or 1])
        return true
    end
    self:CloseNavigationFlyout(frame)
    return false
end

function GUI:RememberNavigationDestination(frame, tile, descriptor)
    if not frame or not tile then return end
    local entry = {
        tileIndex = tile.index, pageIndex = tile._activeSubPageIndex or 1,
        key = descriptor and descriptor.getActiveTab and descriptor.getActiveTab(),
        label = tile.config.name .. " / " .. tile._title:GetText(),
    }
    local recent = frame._recentDestinations or {}
    frame._recentDestinations = recent
    for index = #recent, 1, -1 do
        local previous = recent[index]
        if previous.tileIndex == entry.tileIndex and previous.pageIndex == entry.pageIndex and previous.key == entry.key then
            table.remove(recent, index)
        end
    end
    table.insert(recent, 1, entry)
    if #recent > 6 then table.remove(recent) end
end

function GUI:ShowNavigationSuggestions(frame)
    local wrapper = frame._navigationSuggestions or self:_CreateV2SearchResultsArea(frame)
    frame._navigationSuggestions = wrapper
    wrapper._rows = wrapper._rows or {}
    for _, row in ipairs(wrapper._rows) do row:Hide() end
    local y, index = 18, 0
    local function Row(label, callback)
        index = index + 1
        local row = wrapper._rows[index]
        if not row then
            row = GUI:CreateButton(wrapper.inner, "", 1, 30, function(self)
                if self._navigate then self._navigate() end
            end, "ghost")
            wrapper._rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", wrapper.inner, "TOPLEFT", 18, -y)
        row:SetPoint("TOPRIGHT", wrapper.inner, "TOPRIGHT", -18, -y)
        row:SetText(label)
        if row.text then row.text:SetJustifyH("LEFT"); row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 10, 0); row.text:SetPoint("RIGHT", -10, 0) end
        row._navigate = callback
        row:SetEnabled(callback ~= nil)
        row:Show()
        y = y + 34
    end
    local pins = ns.Settings and ns.Settings.Pins
    Row(ns.L["Favorites"])
    local favorites = pins and pins.List and pins:List() or {}
    for i = 1, math.min(6, #favorites) do
        local favorite = favorites[i]
        Row(favorite.label, function() wrapper:Hide(); pins:NavigateToPinned(favorite.path) end)
    end
    if #favorites == 0 then Row(ns.L["Pin settings to keep them here."]) end
    y = y + 12
    Row(ns.L["Recent pages"])
    for _, destination in ipairs(frame._recentDestinations or {}) do
        local entry = destination
        Row(entry.label, function()
            wrapper:Hide()
            GUI:SelectFeatureTile(frame, entry.tileIndex, { subPageIndex = entry.pageIndex })
            local tile = frame._tiles[entry.tileIndex]
            local descriptor = tile._surfacePagesByPage and tile._surfacePagesByPage[entry.pageIndex]
            if entry.key and descriptor and descriptor.selectTab then descriptor.selectTab(entry.key) end
        end)
    end
    wrapper.inner:SetHeight(y + 18)
    if frame._tileContent then frame._tileContent:Hide() end
    if frame._searchResultsArea then frame._searchResultsArea:Hide() end
    wrapper:Show()
end
