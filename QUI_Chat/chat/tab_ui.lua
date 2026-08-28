local ADDON_NAME, ns = ... -- luacheck: ignore ADDON_NAME
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: tab_ui.lua loaded before chat.lua. Check chat.xml — chat.lua must precede tab_ui.lua.")

---@type fun(...) -- the `or` fallback is narrower than Helpers.IsSecretValue(value)
local IsSecret = ns.Helpers and ns.Helpers.IsSecretValue or function() return false end

ns.QUI.Chat.TabUI = ns.QUI.Chat.TabUI or {}
local TabUI = ns.QUI.Chat.TabUI

local instances = {}
TabUI._instances = instances

local function GetInstance(windowID)
    windowID = tonumber(windowID) or 1
    local inst = instances[windowID]
    if not inst then
        inst = {
            windowID = windowID,
            buttons = {},
            pool = {},
            unread = {},
            activeID = nil,
            pendingActivationID = nil,
            activeCustomSig = nil,
            draggingBtn = nil,
            dragIndicator = nil,
            scrollOffset = 0,
            visibleFirst = nil,
            visibleLast = nil,
            hasOverflow = false,
            overflowBtn = nil,
            bar = nil,
        }
        instances[windowID] = inst
    end
    return inst
end

local function ResolveInstance(windowID)
    local Display = ns.QUI.Chat.DisplayLayer
    local count = Display and Display.GetWindowCount and Display.GetWindowCount() or 0
    windowID = tonumber(windowID) or 1
    if windowID < 1 or (count > 0 and windowID > count) then windowID = 1 end
    return GetInstance(windowID)
end

local storeSubscribed = false

local function CustomTabSignature(t)
    if type(t) ~= "table" then return "" end
    local parts = { tostring(t.name or ""), t.invert and "1" or "0" }
    if type(t.groups) == "table" then
        local keys = {}
        for k, v in pairs(t.groups) do
            keys[#keys + 1] = tostring(k) .. (v and "=1" or "=0")
        end
        table.sort(keys)
        parts[#parts + 1] = "g:" .. table.concat(keys, ",")
    end
    if type(t.channels) == "table" then
        local keys = {}
        for k, v in pairs(t.channels) do
            keys[#keys + 1] = tostring(k) .. (v and "=1" or "=0")
        end
        table.sort(keys)
        parts[#parts + 1] = "c:" .. table.concat(keys, ",")
    end
    return table.concat(parts, "|")
end
TabUI._CustomTabSignature = CustomTabSignature

local function ComputeDropIndex(positions, cursorX)
    for i = 1, #positions do
        if cursorX < positions[i].mid then return i end
    end
    return #positions + 1
end
TabUI._ComputeDropIndex = ComputeDropIndex

local BAR_HEIGHT = 18
local PAD_X = 0
local TAB_EDGE_SIZE = 1
local TAB_LABEL_PAD_X = 6
local TAB_BADGE_RESERVED_WIDTH = 30
local TAB_BADGE_RIGHT_PAD = 6
local DRAG_INDICATOR_WIDTH = 2

local function ReorderDisplayTab(inst, from, to)
    local TM = ns.QUI.Chat.TabManager
    if not (TM and TM.MoveDisplayEntry and TM.GetWindowTabs) then return false end
    local tabs = TM.GetWindowTabs(inst.windowID)
    local n = #tabs
    local vals = {}
    for i = 1, n do
        vals[tabs[i]] = inst.unread[-i]
        inst.unread[-i] = nil
    end
    local activeTab = (type(inst.activeID) == "number" and inst.activeID < 0)
        and tabs[-inst.activeID] or nil

    local moved, savedChanged = TM.MoveDisplayEntry(inst.windowID, from, to)

    for i = 1, n do
        if vals[tabs[i]] ~= nil then inst.unread[-i] = vals[tabs[i]] end
    end
    if activeTab then
        for i = 1, n do
            if tabs[i] == activeTab then
                inst.activeID = -i
                break
            end
        end
    end
    return moved, savedChanged
end
TabUI._ReorderDisplayTab = function(from, to)
    return ReorderDisplayTab(GetInstance(1), from, to)
end

local ApplyTextureColor
local CreateSolidTexture

local function IsReorderableID(frameID)
    return (type(frameID) == "number" and frameID < 0)
        or (type(frameID) == "string" and frameID:sub(1, 5) == "conv:")
end

local function ReorderableButtonMidpoints(inst)
    local positions = {}
    for i = 1, #inst.buttons do
        local b = inst.buttons[i]
        if IsReorderableID(b.frameID) and (not b.IsShown or b:IsShown()) then
            local left = b.GetLeft and b:GetLeft()
            local w    = b.GetWidth and b:GetWidth()
            if type(left) == "number" and not IsSecret(left)
               and type(w) == "number" and not IsSecret(w) then
                positions[#positions + 1] = { mid = left + w / 2, button = b, displayIndex = i }
            else
                return {}
            end
        end
    end
    return positions
end

local function HideDragIndicator(inst)
    if inst.dragIndicator and inst.dragIndicator.Hide then
        inst.dragIndicator:Hide()
    end
    if inst.bar and inst.bar.SetScript then
        inst.bar:SetScript("OnUpdate", nil)
    end
end

local function EnsureDragIndicator(inst)
    if inst.dragIndicator or not inst.bar then return inst.dragIndicator end

    inst.dragIndicator = CreateSolidTexture(inst.bar, "OVERLAY")
    if inst.dragIndicator.SetWidth then inst.dragIndicator:SetWidth(DRAG_INDICATOR_WIDTH) end
    if inst.dragIndicator.SetHeight then inst.dragIndicator:SetHeight(BAR_HEIGHT + 4) end
    if inst.dragIndicator.Hide then inst.dragIndicator:Hide() end
    return inst.dragIndicator
end

local function CursorXForButton(btn)
    local cx = _G.GetCursorPosition and _G.GetCursorPosition()
    local scale = btn and btn.GetEffectiveScale and btn:GetEffectiveScale()
    if type(cx) ~= "number" or IsSecret(cx) then return nil end
    if type(scale) ~= "number" or IsSecret(scale) or scale <= 0 then return nil end
    return cx / scale
end

local function PositionDragIndicator(inst, insertPos, positions)
    local indicator = EnsureDragIndicator(inst)
    if not indicator or #positions < 2 then
        HideDragIndicator(inst)
        return false
    end

    local attachPos = positions[insertPos]
    local attachPoint = "LEFT"
    if not attachPos then
        attachPos = positions[#positions]
        attachPoint = "RIGHT"
    end
    local target = attachPos and attachPos.button
    if not target then
        HideDragIndicator(inst)
        return false
    end

    local accent = I.GetAccent and I.GetAccent() or { 0.2, 0.8, 0.6, 1 }
    ApplyTextureColor(indicator, { accent[1] or 1, accent[2] or 1, accent[3] or 1, 1 })
    if indicator.ClearAllPoints then indicator:ClearAllPoints() end
    indicator:SetPoint("CENTER", target, attachPoint, 0, 0)
    if indicator.Show then indicator:Show() end
    return true
end

local function UpdateDragIndicator(inst)
    if not inst.draggingBtn then
        HideDragIndicator(inst)
        return
    end
    local cx = CursorXForButton(inst.draggingBtn)
    if not cx then
        HideDragIndicator(inst)
        return
    end
    local positions = ReorderableButtonMidpoints(inst)
    if #positions < 2 then
        HideDragIndicator(inst)
        return
    end
    PositionDragIndicator(inst, ComputeDropIndex(positions, cx), positions)
end

local function OnTabDragStart(self)
    local inst = self._inst
    if not inst then return end
    if not IsReorderableID(self.frameID) then return end
    inst.draggingBtn = self
    self:SetAlpha(0.5)
    if inst.bar and inst.bar.SetScript then
        inst.bar:SetScript("OnUpdate", function() UpdateDragIndicator(inst) end)
    end
    UpdateDragIndicator(inst)
end

local function OnTabDragStop(self)
    local inst = self._inst
    if not inst then return end
    if inst.draggingBtn ~= self then return end
    inst.draggingBtn = nil
    HideDragIndicator(inst)
    self:SetAlpha(1)
    local cx = CursorXForButton(self)
    if not cx then return end
    local positions = ReorderableButtonMidpoints(inst)
    if #positions < 2 then return end
    local from
    for i = 1, #positions do
        if positions[i].button == self then from = positions[i].displayIndex; break end
    end
    if not from then return end
    local insertPos = ComputeDropIndex(positions, cx)
    local insertDisplay = positions[insertPos] and positions[insertPos].displayIndex
        or (positions[#positions].displayIndex + 1)
    local to = (insertDisplay > from) and (insertDisplay - 1) or insertDisplay
    local moved, savedChanged = ReorderDisplayTab(inst, from, to)
    if moved then
        TabUI.Rebuild()
        if savedChanged and I.NotifyChatSettingsChanged then I.NotifyChatSettingsChanged() end
    end
end

local function OnTabDragAbort(self)
    local inst = self._inst
    if not inst then return end
    if inst.draggingBtn == self then
        inst.draggingBtn = nil
        HideDragIndicator(inst)
        self:SetAlpha(1)
    end
end

ApplyTextureColor = function(texture, color)
    if texture and texture.SetColorTexture and color then
        texture:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    end
end

CreateSolidTexture = function(parent, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    if texture.SetTexture then
        texture:SetTexture("Interface\\Buttons\\WHITE8x8")
    end
    return texture
end

local function EnsureTabChrome(btn)
    if not btn or btn._quiTabChrome then return end

    local chrome = {
        bg = CreateSolidTexture(btn, "BACKGROUND"),
        edges = {},
    }
    if chrome.bg.SetAllPoints then
        chrome.bg:SetAllPoints(btn)
    else
        chrome.bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        chrome.bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    end

    local top = CreateSolidTexture(btn, "OVERLAY")
    top:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    if top.SetHeight then top:SetHeight(TAB_EDGE_SIZE) end
    chrome.edges[1] = top

    local bottom = CreateSolidTexture(btn, "OVERLAY")
    bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    if bottom.SetHeight then bottom:SetHeight(TAB_EDGE_SIZE) end
    chrome.edges[2] = bottom

    local left = CreateSolidTexture(btn, "OVERLAY")
    left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    if left.SetWidth then left:SetWidth(TAB_EDGE_SIZE) end
    chrome.edges[3] = left

    local right = CreateSolidTexture(btn, "OVERLAY")
    right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    if right.SetWidth then right:SetWidth(TAB_EDGE_SIZE) end
    chrome.edges[4] = right

    btn._quiTabChrome = chrome
end

local function ResolveTabChromeColors(active)
    local settings = I.GetSettings and I.GetSettings()
    local theme = I.GetThemeColors and I.GetThemeColors() or {}
    local accent = I.GetAccent and I.GetAccent() or theme.accent or { 0.2, 0.8, 0.6, 1 }
    local glass = settings and settings.glass
    local alpha = glass and type(glass.bgAlpha) == "number" and glass.bgAlpha or 0.4
    local inactiveAlpha = math.max(0.12, math.min(0.75, alpha))
    local activeAlpha = math.max(inactiveAlpha + 0.12, math.min(1, alpha + 0.2))

    local activeBg = theme.bg or { 0.067, 0.094, 0.153, 1 }
    local inactiveBg = theme.bgDark or theme.bg or { 0.03, 0.04, 0.06, 1 }
    local inactiveBorder = theme.border or { 0, 0, 0, 0.35 }

    if active then
        return { activeBg[1] or 0, activeBg[2] or 0, activeBg[3] or 0, activeAlpha },
            { accent[1] or 1, accent[2] or 1, accent[3] or 1, 0.9 },
            accent
    end

    return { inactiveBg[1] or 0, inactiveBg[2] or 0, inactiveBg[3] or 0, inactiveAlpha },
        { inactiveBorder[1] or 0, inactiveBorder[2] or 0, inactiveBorder[3] or 0,
            math.max(0.25, inactiveBorder[4] or inactiveAlpha) },
        theme.textDim or { 0.72, 0.72, 0.76, 1 }
end

local function PaintTabChrome(btn, active)
    EnsureTabChrome(btn)
    local chrome = btn and btn._quiTabChrome
    if not chrome then return end

    local bg, border = ResolveTabChromeColors(active)
    ApplyTextureColor(chrome.bg, bg)
    for i = 1, #chrome.edges do
        ApplyTextureColor(chrome.edges[i], border)
    end
end

local function ApplyTabFont(fontString, fallbackSize)
    if not fontString then return end

    local fontPath = Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont()
    if not (fontPath and fontString.SetFont) then
        if fontString.SetFontObject then
            fontString:SetFontObject(_G.ChatFontNormal)
        end
        return
    end

    local size = fallbackSize
    if not size and fontString.GetFont then
        local _, currentSize = fontString:GetFont()
        if type(currentSize) == "number" and not IsSecret(currentSize) and currentSize > 0 and currentSize < 64 then
            size = currentSize
        end
    end
    local outline = (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or ""
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fontString, fontPath, size or 11, outline)
    else
        fontString:SetFont(fontPath, size or 11, outline)
    end
end

local function ThemeText()
    local theme = I.GetThemeColors and I.GetThemeColors()
    local accent = I.GetAccent and I.GetAccent() or (theme and theme.accent) or { 1, 1, 1, 1 }
    local dim = (theme and theme.textDim) or { 0.7, 0.7, 0.7, 1 }
    return accent, dim
end

local function UpdateCloseButton(btn)
    local show = btn.close and type(btn.frameID) == "string"
        and btn.frameID:sub(1, 5) == "conv:"
        and (btn._active or btn._quiHovered)
    if btn.close and btn.close.SetShown then btn.close:SetShown(show and true or false) end
    if btn.badge and btn.badge.SetShown then btn.badge:SetShown(not show) end
end

local function StyleButton(btn, active)
    btn._active = active
    PaintTabChrome(btn, active)
    local text, dim = ThemeText()
    local c = active and text or dim
    if not active and btn.labelColor then c = btn.labelColor end
    if btn.label and btn.label.SetTextColor then
        btn.label:SetTextColor(c[1], c[2], c[3])
    end
    if btn.underline then
        btn.underline:SetShown(active and true or false)
    end
    UpdateCloseButton(btn)
end

local function UpdateBadge(inst, btn)
    if not btn.badge then return end
    local n = btn.frameID and inst.unread[btn.frameID]
    if n and n > 0 then
        local accent = I.GetAccent and I.GetAccent() or { 0.2, 0.8, 0.6, 1 }
        if btn.badge.SetTextColor then
            btn.badge:SetTextColor(accent[1], accent[2], accent[3])
        end
        btn.badge:SetText(n > 99 and "99+" or tostring(n))
    else
        btn.badge:SetText("")
    end
end

local function NormalizeFrameID(frameID)
    if type(frameID) == "string" then
        if frameID:sub(1, 5) == "conv:" then return frameID end
        frameID = tonumber(frameID)
    end
    if type(frameID) ~= "number" or frameID == 0 then return nil end
    if frameID > 0 then return -frameID end
    return frameID
end

local LayoutInstance
local ShowOverflowMenu

local OVERFLOW_CONTROL_WIDTH = 24

local function EnsureOverflowButton(inst)
    local btn = inst.overflowBtn
    if btn then return btn end

    btn = CreateFrame("Button", nil, inst.bar)
    btn:SetHeight(BAR_HEIGHT)
    btn:SetWidth(OVERFLOW_CONTROL_WIDTH)
    btn:EnableMouse(true)
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    ApplyTabFont(btn.label, 11)
    btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.underline = btn:CreateTexture(nil, "OVERLAY")
    btn.underline:SetHeight(1)
    btn.underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 0)
    btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 0)
    btn.label:SetText("»")
    btn._quiTabW = OVERFLOW_CONTROL_WIDTH
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function() ShowOverflowMenu(inst) end)
    inst.overflowBtn = btn
    return btn
end

local function RestyleOverflowButton(inst)
    local btn = inst.overflowBtn
    if not (btn and inst.hasOverflow and btn:IsShown()) then return end
    local activeHidden, unreadHidden = false, false
    for i = 1, #inst.buttons do
        if i < inst.visibleFirst or i > inst.visibleLast then
            local fid = inst.buttons[i].frameID
            if fid then
                if fid == inst.activeID then activeHidden = true end
                local u = inst.unread[fid]
                if u and u > 0 then unreadHidden = true end
            end
        end
    end
    PaintTabChrome(btn, activeHidden)
    local accent, dim = ThemeText()
    local c = (activeHidden or unreadHidden) and accent or dim
    if btn.label and btn.label.SetTextColor then
        btn.label:SetTextColor(c[1], c[2], c[3])
    end
    if btn.underline then
        if btn.underline.SetColorTexture then
            btn.underline:SetColorTexture(accent[1], accent[2], accent[3], 1)
        end
        btn.underline:SetShown(activeHidden and true or false)
    end
end

local function ClampScrollOffset(inst, maxOffset)
    maxOffset = math.max(0, maxOffset or 0)
    inst.scrollOffset = math.max(0, math.min(inst.scrollOffset or 0, maxOffset))
end

local function FitVisibleRange(buttons, startIndex, availableWidth)
    local last, used = startIndex - 1, 0
    for i = startIndex, #buttons do
        local w = (buttons[i]._quiTabW or 0) + PAD_X
        if last >= startIndex and used + w > availableWidth then break end
        if w > availableWidth and last >= startIndex then break end
        used = used + w
        last = i
        if used >= availableWidth then break end
    end
    return math.max(startIndex, last)
end

local function ComputeMaxOffset(buttons, availableWidth)
    if #buttons <= 1 then return 0 end
    local maxOffset = 0
    for offset = 0, #buttons - 1 do
        local first = offset + 1
        local last = FitVisibleRange(buttons, first, availableWidth)
        maxOffset = offset
        if last >= #buttons then break end
    end
    return maxOffset
end

LayoutInstance = function(inst)
    if not inst.bar then return end
    local buttons = inst.buttons
    local n = #buttons

    local avail = inst.bar.GetWidth and inst.bar:GetWidth()
    if type(avail) ~= "number" or IsSecret(avail) or avail <= 0 then avail = nil end

    local total = 0
    for i = 1, n do total = total + (buttons[i]._quiTabW or 0) + PAD_X end

    local overflow = avail and total > avail and n > 1
    local more = EnsureOverflowButton(inst)

    if not overflow then
        inst.scrollOffset = 0
        inst.visibleFirst = n > 0 and 1 or nil
        inst.visibleLast = n > 0 and n or nil
        inst.hasOverflow = false
        inst.firstHidden = nil
        local x = 0
        for i = 1, n do
            local btn = buttons[i]
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", inst.bar, "BOTTOMLEFT", x, 0)
            x = x + (btn._quiTabW or 0) + PAD_X
            btn:Show()
        end
        more:Hide()
        return
    end

    local middleWidth = math.max(1, avail - OVERFLOW_CONTROL_WIDTH - PAD_X)
    ClampScrollOffset(inst, ComputeMaxOffset(buttons, middleWidth))
    local first = inst.scrollOffset + 1
    local last = FitVisibleRange(buttons, first, middleWidth)
    inst.visibleFirst = first
    inst.visibleLast = last
    inst.hasOverflow = true
    inst.firstHidden = (first > 1) and 1 or ((last < n) and (last + 1) or nil)

    local x = 0
    for i = 1, n do
        local btn = buttons[i]
        btn:ClearAllPoints()
        if i >= first and i <= last then
            btn:SetPoint("BOTTOMLEFT", inst.bar, "BOTTOMLEFT", x, 0)
            x = x + (btn._quiTabW or 0) + PAD_X
            btn:Show()
        else
            btn:Hide()
        end
    end

    more:ClearAllPoints()
    more:SetPoint("BOTTOMLEFT", inst.bar, "BOTTOMLEFT",
        math.min(x, math.max(0, avail - OVERFLOW_CONTROL_WIDTH)), 0)
    more:Show()
    RestyleOverflowButton(inst)
end

local RebuildInstance

local function EnsureFrameIDVisible(inst, frameID)
    if not (inst.hasOverflow and frameID) then return end
    local targetIndex
    for i = 1, #inst.buttons do
        if inst.buttons[i].frameID == frameID then
            targetIndex = i
            break
        end
    end
    if not targetIndex then return end
    if inst.visibleFirst and inst.visibleLast
        and targetIndex >= inst.visibleFirst and targetIndex <= inst.visibleLast then
        return
    end
    if inst.visibleFirst and targetIndex < inst.visibleFirst then
        inst.scrollOffset = targetIndex - 1
    elseif inst.visibleLast and targetIndex > inst.visibleLast then
        inst.scrollOffset = targetIndex - 1
    end
    LayoutInstance(inst)
end

local function ActivateFrameID(inst, frameID, userInitiated)
    frameID = NormalizeFrameID(frameID)
    if not frameID then return false end

    local target
    for i = 1, #inst.buttons do
        if inst.buttons[i].frameID == frameID then
            target = inst.buttons[i]
            break
        end
    end
    if not target then return false end

    local TM_cl = ns.QUI.Chat.TabManager
    local CL_tab = ns.QUI.Chat.CombatLogTab
    local newIsCombatLog = false
    if type(frameID) == "number" and frameID < 0 and TM_cl and TM_cl.GetWindowTab and TM_cl.IsCombatLogTab then
        newIsCombatLog = TM_cl.IsCombatLogTab(TM_cl.GetWindowTab(inst.windowID, -frameID))
    end
    if inst.combatLogActive and not newIsCombatLog and CL_tab and CL_tab.Deactivate then
        CL_tab.Deactivate(inst.windowID)
        inst.combatLogActive = false
    end

    inst.activeID = frameID
    inst.unread[frameID] = nil
    UpdateBadge(inst, target)

    if userInitiated then
        local Display = ns.QUI.Chat.DisplayLayer
        if Display and Display.SetActiveWindow then
            Display.SetActiveWindow(inst.windowID)
        end
    end

    local TabManager = ns.QUI.Chat.TabManager
    if type(frameID) == "string" then
        local key = frameID:sub(6)
        if TabManager and TabManager.SetActiveConversation then
            TabManager.SetActiveConversation(inst.windowID, key)
        end
        local Conv = ns.QUI.Chat.ConversationManager
        if Conv and Conv.PreTargetEditBox then
            Conv.PreTargetEditBox(key)
        end
    elseif TabManager and TabManager.SetActiveTab then
        local t = TabManager.GetWindowTab and TabManager.GetWindowTab(inst.windowID, -frameID) or nil
        inst.activeCustomSig = CustomTabSignature(t)
        TabManager.SetActiveTab(inst.windowID, t)
        if newIsCombatLog and CL_tab and CL_tab.Activate then
            CL_tab.Activate(inst.windowID)
            inst.combatLogActive = true
        end
        local Conv = ns.QUI.Chat.ConversationManager
        if Conv and Conv.ClearPreTarget then
            Conv.ClearPreTarget()
        end
    end
    for i = 1, #inst.buttons do
        StyleButton(inst.buttons[i], inst.buttons[i].frameID == inst.activeID)
    end
    EnsureFrameIDVisible(inst, frameID)
    RestyleOverflowButton(inst)
    return true
end

function TabUI.ActivateFrameID(windowID, frameID)
    local inst = ResolveInstance(windowID)
    frameID = NormalizeFrameID(frameID)
    if not frameID then return false end
    if not inst.bar then
        inst.pendingActivationID = frameID
        return false
    end
    return ActivateFrameID(inst, frameID, true)
end

function TabUI.ActivateConversation(windowID, key)
    local inst = ResolveInstance(windowID)
    if not inst.bar then
        inst.pendingActivationID = "conv:" .. key
        return false
    end
    RebuildInstance(inst)
    return ActivateFrameID(inst, "conv:" .. key, true)
end

function TabUI.GetBar(windowID)
    local inst = instances[tonumber(windowID) or 1]
    return inst and inst.bar
end

function TabUI.FlashConversation(windowID, key)
    local inst = instances[tonumber(windowID) or 1]
    if not inst then return end
    local frameID = "conv:" .. key
    for i = 1, #inst.buttons do
        local btn = inst.buttons[i]
        if btn.frameID == frameID then
            if btn._quiFlashTicker then return end
            if not (_G.C_Timer and _G.C_Timer.NewTicker) then return end
            local shown, ticks = false, 0
            btn._quiFlashTicker = _G.C_Timer.NewTicker(0.35, function()
                ticks = ticks + 1
                shown = not shown
                if ticks >= 6 then
                    btn._quiFlashTicker = nil
                    btn:SetAlpha(1)
                else
                    btn:SetAlpha(shown and 0.4 or 1)
                end
            end, 6)
            return
        end
    end
end

local function MoveTabToWindow(inst, tabIndex, targetWindowID, replaceSeed)
    local TM = ns.QUI.Chat.TabManager
    if not (TM and TM.GetWindowTabs) then return end
    local fromTabs = TM.GetWindowTabs(inst.windowID)
    local tab = fromTabs[tabIndex]
    if not tab then return end
    if #fromTabs <= 1 then return end
    table.remove(fromTabs, tabIndex)
    local toTabs = TM.GetWindowTabs(targetWindowID)
    if replaceSeed and #toTabs == 1 and toTabs[1].name == "Tab 1" then
        toTabs[1] = tab
    else
        toTabs[#toTabs + 1] = tab
    end
    TabUI.Rebuild()
    if I.NotifyChatSettingsChanged then I.NotifyChatSettingsChanged() end
end
TabUI._MoveTabToWindow = MoveTabToWindow

local function OpenChatSettings(subPageIndex)
    local QUI = _G.QUI
    if not (QUI and type(QUI.OpenOptions) == "function") then return end
    QUI:OpenOptions()
    C_Timer.After(0, function()
        local gui = _G.QUI and _G.QUI.GUI
        local frame = gui and gui.MainFrame
        if not (frame and gui.FindV2TileByID and gui.SelectFeatureTile) then return end
        local _, idx = gui:FindV2TileByID(frame, "chat_tooltips")
        if idx then
            gui:SelectFeatureTile(frame, idx, { subPageIndex = subPageIndex })
        end
    end)
end

local function CloseConversation(inst, frameID)
    if type(frameID) ~= "string" or frameID:sub(1, 5) ~= "conv:" then return false end
    local Conv = ns.QUI.Chat.ConversationManager
    if not (Conv and Conv.Close) then return false end

    local fallbackID
    if inst.activeID == frameID then
        for i = 1, #inst.buttons do
            if inst.buttons[i].frameID == frameID then
                local fallback = inst.buttons[i + 1] or inst.buttons[i - 1]
                fallbackID = fallback and fallback.frameID
                break
            end
        end
    end

    for _, current in pairs(instances) do
        current.preserveViewportOnce = true
        current.viewportAnchors = {}
        for i = current.visibleFirst or 1, current.visibleLast or 0 do
            local button = current.buttons[i]
            current.viewportAnchors[#current.viewportAnchors + 1] = button and button.frameID
        end
    end
    inst.closeFallbackID = fallbackID
    Conv.Close(frameID:sub(6))
    for _, current in pairs(instances) do
        current.preserveViewportOnce = nil
        current.viewportAnchors = nil
    end
    inst.closeFallbackID = nil
    return true
end

ShowOverflowMenu = function(inst)
    if not (_G.MenuUtil and _G.MenuUtil.CreateContextMenu) then return end
    if not (inst.hasOverflow and inst.overflowBtn) then return end
    _G.MenuUtil.CreateContextMenu(inst.overflowBtn, function(_, rootDescription)
        for i = 1, #inst.buttons do
            local btn = inst.buttons[i]
            local fid = btn.frameID
            if fid then
                local text = type(btn._quiTabLabel) == "string" and btn._quiTabLabel or "?"
                local tint = btn.labelColor
                if tint and type(tint[1]) == "number" and not IsSecret(tint[1])
                    and type(tint[2]) == "number" and not IsSecret(tint[2])
                    and type(tint[3]) == "number" and not IsSecret(tint[3]) then
                    text = string.format("|cff%02x%02x%02x%s|r",
                        math.floor(tint[1] * 255 + 0.5),
                        math.floor(tint[2] * 255 + 0.5),
                        math.floor(tint[3] * 255 + 0.5), text)
                end
                local unread = inst.unread[fid]
                if unread and unread > 0 then
                    text = text .. " (" .. (unread > 99 and "99+" or tostring(unread)) .. ")"
                end
                rootDescription:CreateRadio(text,
                    function() return inst.activeID == fid end,
                    function() ActivateFrameID(inst, fid, true) end)
            end
        end
        if rootDescription.SetScrollMode then
            rootDescription:SetScrollMode(BAR_HEIGHT * 18)
        end
    end)
end

local function ShowTabContextMenu(inst, btn)
    if not (_G.MenuUtil and _G.MenuUtil.CreateContextMenu) then return end
    _G.MenuUtil.CreateContextMenu(btn, function(owner, rootDescription)
        if type(btn.frameID) == "number" and btn.frameID < 0 then
            local TMcl = ns.QUI.Chat.TabManager
            local clTab = TMcl and TMcl.GetWindowTab and TMcl.GetWindowTab(inst.windowID, -btn.frameID)
            if TMcl and TMcl.IsCombatLogTab and TMcl.IsCombatLogTab(clTab) then
                rootDescription:CreateButton(ns.L["Combat Log Settings"], function()
                    if _G.ShowUIPanel and _G.ChatConfigFrame then
                        _G.ShowUIPanel(_G.ChatConfigFrame)
                    end
                end)
                return
            end
        end
        if type(btn.frameID) == "string" then
            local fid = btn.frameID
            rootDescription:CreateButton(ns.L["Close conversation"], function()
                CloseConversation(inst, fid)
            end)
            return
        end
        rootDescription:CreateButton(ns.L["Filter Settings"], function()
            OpenChatSettings(2)
        end)
        rootDescription:CreateButton(ns.L["Tab Settings"], function()
            OpenChatSettings(1)
        end)
        local Display = ns.QUI.Chat.DisplayLayer
        if not Display then return end
        local nWindows = (Display.GetWindowCount and Display.GetWindowCount()) or 1
        for w = 1, nWindows do
            if w ~= inst.windowID then
                rootDescription:CreateButton(ns.L["Move to window "] .. w, function()
                    local fid = btn.frameID
                    if type(fid) ~= "number" or fid >= 0 then return end
                    MoveTabToWindow(inst, -fid, w)
                end)
            end
        end
        rootDescription:CreateButton(ns.L["Move to new window"], function()
            local fid = btn.frameID
            if type(fid) ~= "number" or fid >= 0 then return end
            local newID = Display.CreateNewWindow and Display.CreateNewWindow()
            if newID then MoveTabToWindow(inst, -fid, newID, true) end
        end)
        if inst.windowID > 1 then
            local TM = ns.QUI.Chat.TabManager
            local tabs = TM and TM.GetWindowTabs and TM.GetWindowTabs(inst.windowID)
            if tabs and #tabs <= 1 then
                rootDescription:CreateButton(ns.L["Close window"], function()
                    if Display.DeleteWindow then Display.DeleteWindow(inst.windowID) end
                end)
            end
        end
    end)
end

local function OnTabClick(self, mouseButton)
    local inst = self._inst
    if not inst then return end
    if mouseButton == "RightButton" then
        ShowTabContextMenu(inst, self)
        return
    end
    if mouseButton == "MiddleButton" then
        CloseConversation(inst, self.frameID)
        return
    end
    ActivateFrameID(inst, self.frameID, true)
end

local function CreateButton(inst)
    local btn = CreateFrame("Button", nil, inst.bar)
    btn:SetHeight(BAR_HEIGHT)
    btn:EnableMouse(true)
    btn._inst = inst
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    ApplyTabFont(btn.label, 11)
    btn.label:SetPoint("LEFT", btn, "LEFT", TAB_LABEL_PAD_X, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -TAB_BADGE_RESERVED_WIDTH, 0)
    if btn.label.SetJustifyH then
        btn.label:SetJustifyH("CENTER")
    end
    btn.underline = btn:CreateTexture(nil, "OVERLAY")
    btn.underline:SetHeight(1)
    btn.underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 0)
    btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 0)
    btn.badge = btn:CreateFontString(nil, "OVERLAY")
    ApplyTabFont(btn.badge, 10)
    btn.badge:SetPoint("RIGHT", btn, "RIGHT", -TAB_BADGE_RIGHT_PAD, 1)
    if btn.badge.SetJustifyH then
        btn.badge:SetJustifyH("RIGHT")
    end
    if UIKit and UIKit.CreateCloseButton then
        btn.close = UIKit.CreateCloseButton(btn, {
            size = 14,
            lineLen = 6,
            lineWidth = 1,
            point = "RIGHT",
            x = -3,
            onClick = function() CloseConversation(inst, btn.frameID) end,
        })
        btn.close:RegisterForClicks("LeftButtonUp")
        btn.close:HookScript("OnEnter", function(self)
            btn._quiHovered = true
            UpdateCloseButton(btn)
            if _G.GameTooltip then
                _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                _G.GameTooltip:SetText(ns.L["Close conversation"])
                _G.GameTooltip:Show()
            end
        end)
        btn.close:HookScript("OnLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
            if not (btn.IsMouseOver and btn:IsMouseOver()) then
                btn._quiHovered = false
                UpdateCloseButton(btn)
            end
        end)
    end
    btn:SetScript("OnClick", OnTabClick)
    btn:SetScript("OnEnter", function(self)
        self._quiHovered = true
        UpdateCloseButton(self)
    end)
    btn:SetScript("OnLeave", function(self)
        if self.close and self.close.IsMouseOver and self.close:IsMouseOver() then return end
        self._quiHovered = false
        UpdateCloseButton(self)
    end)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
    btn:SetScript("OnDragStart", OnTabDragStart)
    btn:SetScript("OnDragStop", OnTabDragStop)
    btn:SetScript("OnHide", function(self)
        OnTabDragAbort(self)
        self._quiHovered = false
        UpdateCloseButton(self)
    end)
    return btn
end

RebuildInstance = function(inst)
    if not inst.bar then return end
    local preserveViewport = inst.preserveViewportOnce
    local viewportAnchors = inst.viewportAnchors
    local closeFallbackID = inst.closeFallbackID
    inst.preserveViewportOnce = nil
    inst.viewportAnchors = nil
    inst.closeFallbackID = nil

    for i = #inst.buttons, 1, -1 do
        inst.buttons[i]:Hide()
        inst.pool[#inst.pool + 1] = table.remove(inst.buttons)
    end

    local function place(frameID, label, filter, labelColor)
        local btn = table.remove(inst.pool) or CreateButton(inst)
        local accent = I.GetAccent and I.GetAccent() or { 0.2, 0.8, 0.6, 1 }
        ApplyTabFont(btn.label, 11)
        ApplyTabFont(btn.badge, 10)
        if btn.underline and btn.underline.SetColorTexture then
            btn.underline:SetColorTexture(accent[1], accent[2], accent[3], 1)
        end
        btn.frameID = frameID
        btn.filter = filter
        btn.labelColor = labelColor
        btn._inst = inst
        btn._quiHovered = false
        btn.label:SetText(label)
        btn._quiTabLabel = type(label) == "string" and label or nil
        local sw = btn.label.GetStringWidth and btn.label:GetStringWidth()
        local w = (sw and not IsSecret(sw) and sw or 30)
            + (TAB_LABEL_PAD_X * 2)
            + TAB_BADGE_RESERVED_WIDTH
        btn:SetWidth(w)
        btn._quiTabW = w
        btn:Show()
        btn:SetAlpha(1)
        if btn._quiFlashTicker then btn._quiFlashTicker:Cancel(); btn._quiFlashTicker = nil end
        StyleButton(btn, frameID == inst.activeID)
        UpdateBadge(inst, btn)
        inst.buttons[#inst.buttons + 1] = btn
    end

    local TM = ns.QUI.Chat.TabManager
    local Conv = ns.QUI.Chat.ConversationManager
    local entries
    if TM and TM.GetDisplayEntries then
        entries = TM.GetDisplayEntries(inst.windowID)
    else
        entries = {}
        if TM and TM.GetWindowTabs then
            local saved = TM.GetWindowTabs(inst.windowID)
            for i = 1, #saved do
                entries[#entries + 1] = { kind = "saved", index = i, tab = saved[i] }
            end
        end
        if Conv and Conv.EachForWindow then
            Conv.EachForWindow(inst.windowID, function(c)
                entries[#entries + 1] = { kind = "conv", key = c.key, conv = c }
            end)
        end
    end
    local wc = _G.ChatTypeInfo and _G.ChatTypeInfo.WHISPER
    local tint = wc and { wc.r or 1, wc.g or 0.5, wc.b or 1, 1 } or nil
    for i = 1, #entries do
        local e = entries[i]
        if e.kind == "saved" and type(e.tab) == "table" then
            local label = (type(e.tab.name) == "string" and e.tab.name ~= "")
                and e.tab.name or ("Tab " .. e.index)
            place(-e.index, label,
                TM and TM.BuildTabFilter and TM.BuildTabFilter(e.tab) or nil)
        elseif e.kind == "conv" and e.conv and TM and TM.BuildConversationFilter then
            place("conv:" .. e.key, e.conv.name, TM.BuildConversationFilter(e.key), tint)
        end
    end

    if preserveViewport and viewportAnchors then
        local anchored
        for a = 1, #viewportAnchors do
            for i = 1, #inst.buttons do
                if inst.buttons[i].frameID == viewportAnchors[a] then
                    inst.scrollOffset = i - 1
                    anchored = true
                    break
                end
            end
            if anchored then break end
        end
    end

    LayoutInstance(inst)

    local live = {}
    for i = 1, #inst.buttons do
        if inst.buttons[i].frameID then live[inst.buttons[i].frameID] = true end
    end
    for fid in pairs(inst.unread) do
        if not live[fid] then inst.unread[fid] = nil end
    end

    local activeLive = false
    for i = 1, #inst.buttons do
        if inst.buttons[i].frameID == inst.activeID then
            activeLive = true
            break
        end
    end
    local TabManager = ns.QUI.Chat.TabManager
    if not activeLive then
        local first
        if closeFallbackID then
            for i = 1, #inst.buttons do
                if inst.buttons[i].frameID == closeFallbackID then
                    first = inst.buttons[i]
                    break
                end
            end
        end
        first = first or inst.buttons[1]
        inst.activeCustomSig = nil
        if first then
            ActivateFrameID(inst, first.frameID, false)
            return
        elseif TabManager and TabManager.SetActiveTab then
            inst.activeID = nil
            TabManager.SetActiveTab(inst.windowID, nil)
        end
    elseif type(inst.activeID) == "number" and inst.activeID < 0
        and TabManager and TabManager.SetActiveTab and TabManager.GetWindowTab then
        local t = TabManager.GetWindowTab(inst.windowID, -inst.activeID)
        local sig = CustomTabSignature(t)
        local missingActiveFilter = false
        if TabManager.GetActiveFilter and not TabManager.GetActiveFilter(inst.windowID) then
            missingActiveFilter = true
        end
        if sig ~= inst.activeCustomSig or missingActiveFilter then
            inst.activeCustomSig = sig
            TabManager.SetActiveTab(inst.windowID, t)
        end
    end
    if inst.activeID and not preserveViewport then
        EnsureFrameIDVisible(inst, inst.activeID)
    end
    RestyleOverflowButton(inst)
end

function TabUI.Rebuild()
    for _, inst in pairs(instances) do
        RebuildInstance(inst)
    end
end

function TabUI.OnWindowDeleted(windowID)
    local stale = instances[windowID]
    if stale and stale.bar then stale.bar:Hide() end
    local maxID = 0
    for id in pairs(instances) do if id > maxID then maxID = id end end
    for id = windowID, maxID - 1 do
        instances[id] = instances[id + 1]
        if instances[id] then instances[id].windowID = id end
    end
    instances[maxID] = nil
    TabUI.EnsureAttached()
end

local function ConfigureBarScripts(inst)
    if not inst.bar then return end
    inst.bar:SetScript("OnSizeChanged", function() LayoutInstance(inst) end)
    inst.ScrollTabs = function(delta)
        if not inst.hasOverflow then return false end
        local old = inst.scrollOffset or 0
        inst.scrollOffset = old + (delta or 0)
        LayoutInstance(inst)
        return inst.scrollOffset ~= old
    end
    if inst.bar.EnableMouseWheel then inst.bar:EnableMouseWheel(true) end
    inst.bar:SetScript("OnMouseWheel", function(_, delta)
        if type(delta) ~= "number" or delta == 0 then return end
        inst.ScrollTabs(delta > 0 and -1 or 1)
    end)
end

local function AttachBar(inst, container, name)
    if not inst.bar then
        inst.bar = CreateFrame("Frame", name, container)
        inst.bar:SetHeight(BAR_HEIGHT)
        ConfigureBarScripts(inst)
    elseif inst.bar:GetParent() ~= container then
        inst.bar:SetParent(container)
        ConfigureBarScripts(inst)
    else
        ConfigureBarScripts(inst)
        return
    end
    inst.bar:ClearAllPoints()
    inst.bar:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 4, 0)
    inst.bar:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", -22, 0)
    local rawLevel = container.GetFrameLevel and container:GetFrameLevel()
    local safeLevel = (rawLevel and not IsSecret(rawLevel) and rawLevel or 1) + 5
    inst.bar:SetFrameLevel(safeLevel)
    inst.bar:Show()
end

function TabUI.EnsureAttached()
    local Display = ns.QUI.Chat.DisplayLayer
    if not (Display and Display.GetWindowCount) then
        local container = Display and Display.GetContainer and Display.GetContainer()
        if not container then return end
        AttachBar(GetInstance(1), container, "QUI_CustomChatTabBar")
    else
        for windowID = 1, Display.GetWindowCount() do
            local container = Display.GetContainer(windowID)
            if container then
                local barName = (windowID == 1) and "QUI_CustomChatTabBar" or nil
                AttachBar(GetInstance(windowID), container, barName)
            end
        end
    end
    if not storeSubscribed then
        local Store = ns.QUI.Chat.MessageStore
        if Store and Store.OnAppend then
            storeSubscribed = true
            Store.OnAppend(function(entry)
                if entry.s then return end
                if entry.e == "HISTORY" or entry.e == "BACKFILL" then return end
                for _, inst in pairs(instances) do
                    local n = #inst.buttons
                    if n > 0 then
                        local changed = false
                        for i = 1, n do
                            local btn = inst.buttons[i]
                            local fid = btn.frameID
                            if fid and fid ~= inst.activeID
                                and (not btn.filter or btn.filter(entry)) then
                                inst.unread[fid] = (inst.unread[fid] or 0) + 1
                                UpdateBadge(inst, btn)
                                changed = true
                            end
                        end
                        if changed then RestyleOverflowButton(inst) end
                    end
                end
            end)
        end
    end
    TabUI.Rebuild()
    for _, inst in pairs(instances) do
        if inst.pendingActivationID and inst.bar then
            local frameID = inst.pendingActivationID
            inst.pendingActivationID = nil
            ActivateFrameID(inst, frameID, true)
        end
    end
end
