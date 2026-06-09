-- modules/chat/tab_ui.lua
-- Visual tab bar for the custom chat display. Each window gets its own bar
-- frame and independent state (active tab, unread counts, drag state). Saved
-- QUI tabs (customDisplay.windows[w].tabs) are the primary runtime tab source.
-- Conversation tabs ("conv:<key>" frameIDs) are session-only; the
-- ConversationManager module that supplies them lands in a later task — all
-- ns.QUI.Chat.ConversationManager references are nil-safe runtime lookups.
-- Clicking a tab swaps the display filter via TabManager (lossless store
-- rebuild). Inactive tabs show an unread badge (accent-colored count of
-- messages matching that tab's filter since it was last active).
-- Custom tabs use negative frameIDs (-i for tabs[i]).
-- Custom tabs drag to reorder; conversation tabs use middle-click to close.
--
-- Layout note: the bar sits just above its container. The bar frame itself is
-- NOT mouse-enabled — only the buttons are — so the row does not create a
-- large invisible hit area around the chat frame.
local ADDON_NAME, ns = ... -- luacheck: ignore ADDON_NAME
local Helpers = ns.Helpers

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: tab_ui.lua loaded before chat.lua. Check chat.xml — chat.lua must precede tab_ui.lua.")

local IsSecret = ns.Helpers and ns.Helpers.IsSecretValue or function() return false end

ns.QUI.Chat.TabUI = ns.QUI.Chat.TabUI or {}
local TabUI = ns.QUI.Chat.TabUI

-- Per-window instances. Keyed by windowID; each inst owns its bar frame,
-- live buttons, recycle pool, active id, unread counts, drag state.
local instances = {}
TabUI._instances = instances -- for unit tests

local function GetInstance(windowID)
    windowID = tonumber(windowID) or 1
    local inst = instances[windowID]
    if not inst then
        inst = {
            windowID = windowID,
            buttons = {},
            pool = {},
            unread = {},      -- frameID -> count while inactive
            activeID = nil,
            pendingActivationID = nil,
            activeCustomSig = nil,
            draggingBtn = nil,
            dragIndicator = nil,
            bar = nil,
        }
        instances[windowID] = inst
    end
    return inst
end

local storeSubscribed = false

local function CustomTabSignature(t)
    if type(t) ~= "table" then return "" end
    local parts = { tostring(t.name or ""), t.invert and "1" or "0" }
    if type(t.groups) == "table" then
        local keys = {}
        for k in pairs(t.groups) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        parts[#parts + 1] = "g:" .. table.concat(keys, ",")
    end
    if type(t.channels) == "table" then
        local keys = {}
        for k in pairs(t.channels) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        parts[#parts + 1] = "c:" .. table.concat(keys, ",")
    end
    return table.concat(parts, "|")
end

-- Drag-reorder (custom tabs only).
-- Drop slot for a release at cursorX, given the ordered custom buttons'
-- horizontal midpoints (same coordinate space as cursorX). Returns 1..n+1.
local function ComputeDropIndex(positions, cursorX)
    for i = 1, #positions do
        if cursorX < positions[i].mid then return i end
    end
    return #positions + 1
end
TabUI._ComputeDropIndex = ComputeDropIndex -- for unit tests

local BAR_HEIGHT = 18
local PAD_X = 0
local TAB_EDGE_SIZE = 1
local TAB_LABEL_PAD_X = 6
local TAB_BADGE_RESERVED_WIDTH = 30
local TAB_BADGE_RIGHT_PAD = 6
local DRAG_INDICATOR_WIDTH = 2

-- Move tabs[from] to final position `to`, remapping the unread badges (keyed
-- -index) and the active id so both FOLLOW their tab (identity-keyed snapshot;
-- index math stays mechanical). Mutates the live stored array — persistence is
-- the mutation. Returns true on a real move.
local function ReorderCustomTab(inst, from, to)
    local TM = ns.QUI.Chat.TabManager
    local tabs = TM and TM.GetWindowTabs and TM.GetWindowTabs(inst.windowID)
    if type(tabs) ~= "table" then return false end
    local n = #tabs
    if n < 2 or type(from) ~= "number" or from < 1 or from > n then return false end
    if type(to) ~= "number" then return false end
    if to < 1 then to = 1 elseif to > n then to = n end
    if to == from then return false end

    local activeTab = (type(inst.activeID) == "number" and inst.activeID < 0)
        and tabs[-inst.activeID] or nil
    local vals = {}
    for i = 1, n do
        vals[tabs[i]] = inst.unread[-i]
        inst.unread[-i] = nil
    end

    local moved = table.remove(tabs, from)
    table.insert(tabs, to, moved)

    for i = 1, n do
        if vals[tabs[i]] ~= nil then inst.unread[-i] = vals[tabs[i]] end
    end
    if activeTab then
        for i = 1, n do
            if tabs[i] == activeTab then
                -- Signature is definition-based, so following the moved tab
                -- never triggers Rebuild's re-derive (no scroll reset).
                inst.activeID = -i
                break
            end
        end
    end
    return true
end
-- Test export: the test calls _ReorderCustomTab(from, to) on the module-level
-- TabUI; we shim it to use window 1's instance.
TabUI._ReorderCustomTab = function(from, to)
    return ReorderCustomTab(GetInstance(1), from, to)
end

local ApplyTextureColor
local CreateSolidTexture

local function CustomButtonMidpoints(inst)
    local positions = {}
    for i = 1, #inst.buttons do
        local b = inst.buttons[i]
        if type(b.frameID) == "number" and b.frameID < 0 then
            -- GetLeft: MayReturnNothing + SecretWhenAnchoringSecret.
            -- GetWidth: SecretWhenAnchoringSecret + ConstSecretAccessor.
            -- Both: guard type=="number" before arithmetic.
            local left = b.GetLeft and b:GetLeft()
            local w    = b.GetWidth and b:GetWidth()
            if type(left) == "number" and not IsSecret(left)
               and type(w) == "number" and not IsSecret(w) then
                positions[#positions + 1] = { mid = left + w / 2, button = b }
            else
                -- Any unmeasurable button would compress slot indices relative
                -- to tab indices, producing a misaligned reorder. Abort entirely.
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
    -- GetEffectiveScale: SecretReturnsForAspect=Scale — guard secrets.
    local scale = btn and btn.GetEffectiveScale and btn:GetEffectiveScale()
    if type(cx) ~= "number" or IsSecret(cx) then return nil end
    if type(scale) ~= "number" or IsSecret(scale) or scale <= 0 then return nil end
    return cx / scale -- same space as GetLeft (scrollbar uses this pattern)
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
    local positions = CustomButtonMidpoints(inst)
    if #positions < 2 then
        HideDragIndicator(inst)
        return
    end
    PositionDragIndicator(inst, ComputeDropIndex(positions, cx), positions)
end

local function OnTabDragStart(self)
    local inst = self._inst
    if not inst then return end
    if not (type(self.frameID) == "number" and self.frameID < 0) then return end
    -- The combat-log tab is pinned to window 1 — not drag-reorderable.
    local TMcl = ns.QUI.Chat.TabManager
    if TMcl and TMcl.GetWindowTab and TMcl.IsCombatLogTab
        and TMcl.IsCombatLogTab(TMcl.GetWindowTab(inst.windowID, -self.frameID)) then
        return
    end
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
    local positions = CustomButtonMidpoints(inst)
    if #positions < 2 then return end
    local insertPos = ComputeDropIndex(positions, cx)
    local from = -self.frameID
    local to = (insertPos > from) and (insertPos - 1) or insertPos
    if ReorderCustomTab(inst, from, to) then
        TabUI.Rebuild()
        -- Saved tab order changed in-game: a cached options panel must rebuild.
        if I.NotifyChatSettingsChanged then I.NotifyChatSettingsChanged() end
    end
end

-- Rebuild/pool-recycle mid-drag hides the button: abort cleanly.
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
    fontString:SetFont(fontPath, size or 11, outline)
end

local function ThemeText()
    local theme = I.GetThemeColors and I.GetThemeColors()
    local accent = I.GetAccent and I.GetAccent() or (theme and theme.accent) or { 1, 1, 1, 1 }
    local dim = (theme and theme.textDim) or { 0.7, 0.7, 0.7, 1 }
    return accent, dim
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

-- Forward declaration so TabUI.ActivateConversation can reference it.
local RebuildInstance

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

    -- Combat-log tab routing: deactivate a previously-active embed when
    -- switching away. (Re)activation happens in the saved-tab branch below.
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

    -- Editbox follow is USER intent only: rebuild/fallback activations must
    -- never steal the active window (EnsureAttached fans out over all
    -- windows; the last one iterated would otherwise win).
    if userInitiated then
        local Display = ns.QUI.Chat.DisplayLayer
        if Display and Display.SetActiveWindow then
            Display.SetActiveWindow(inst.windowID)
        end
    end

    local TabManager = ns.QUI.Chat.TabManager
    if type(frameID) == "string" then
        -- Conversation tab ("conv:<key>").
        local key = frameID:sub(6)
        if TabManager and TabManager.SetActiveConversation then
            TabManager.SetActiveConversation(inst.windowID, key)
        end
        local Conv = ns.QUI.Chat.ConversationManager
        if Conv and Conv.PreTargetEditBox then
            Conv.PreTargetEditBox(key)
        end
    elseif TabManager and TabManager.SetActiveTab then
        -- Saved tab: negative ID -i addresses windows[w].tabs[i]. Record the
        -- signature BEFORE SetActiveTab so the first Rebuild after activation
        -- does not treat it as a definition change and re-derive.
        local t = TabManager.GetWindowTab and TabManager.GetWindowTab(inst.windowID, -frameID) or nil
        inst.activeCustomSig = CustomTabSignature(t)
        TabManager.SetActiveTab(inst.windowID, t)
        -- Combat-log tab: embed the real ChatFrame2 into this window.
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
    return true
end

function TabUI.ActivateFrameID(windowID, frameID)
    local Display = ns.QUI.Chat.DisplayLayer
    local count = Display and Display.GetWindowCount and Display.GetWindowCount() or 0
    windowID = tonumber(windowID) or 1
    if windowID < 1 or (count > 0 and windowID > count) then windowID = 1 end
    local inst = GetInstance(windowID)
    frameID = NormalizeFrameID(frameID)
    if not frameID then return false end
    if not inst.bar then
        inst.pendingActivationID = frameID
        return false
    end
    return ActivateFrameID(inst, frameID, true)
end

-- Select a conversation tab (rebuilds the bar first so a just-created
-- conversation's button exists, then activates it).
function TabUI.ActivateConversation(windowID, key)
    local Display = ns.QUI.Chat.DisplayLayer
    local count = Display and Display.GetWindowCount and Display.GetWindowCount() or 0
    windowID = tonumber(windowID) or 1
    if windowID < 1 or (count > 0 and windowID > count) then windowID = 1 end
    local inst = GetInstance(windowID)
    if not inst.bar then
        inst.pendingActivationID = "conv:" .. key
        return false
    end
    RebuildInstance(inst)
    return ActivateFrameID(inst, "conv:" .. key, true)
end

-- A window's tab-bar frame (layoutmode's per-window mover overlay needs its
-- height for the top inset; bars 2+ are unnamed so a global lookup can't work).
function TabUI.GetBar(windowID)
    local inst = instances[tonumber(windowID) or 1]
    return inst and inst.bar
end

-- Brief attention pulse on a conversation tab created without focus-steal.
-- Uses C_Timer.NewTicker's iterations argument (6 ticks = 3 dim/bright
-- cycles at 0.35 s each). Tick count is tracked in the callback so the
-- final tick can nil the handle and restore full alpha without a separate
-- After (which would fire after pool-recycle and corrupt the recycled button).
-- :Cancel() is only needed in the pool-recycle path to abort early.
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
                    -- Final tick: restore and clear handle before ticker
                    -- self-stops so recycle sees a clean button immediately.
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

-- Move a saved tab's config table to another window. The source window must
-- keep at least one tab (delete the window via settings if you want it gone).
-- When the target was just created by "Move to new window", its placeholder
-- seed tab is replaced instead of appended-after.
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
    -- Saved tab config changed in-game: bump the settings provider revision
    -- so a cached options panel rebuilds its window/tab lists.
    if I.NotifyChatSettingsChanged then I.NotifyChatSettingsChanged() end
end
TabUI._MoveTabToWindow = MoveTabToWindow -- for unit tests

local function ShowTabContextMenu(inst, btn)
    if not (_G.MenuUtil and _G.MenuUtil.CreateContextMenu) then return end
    -- MenuUtil.CreateContextMenu(owner, generator) —
    -- tests/framexml/Interface/AddOns/Blizzard_Menu/MenuUtil.lua:153.
    _G.MenuUtil.CreateContextMenu(btn, function(owner, rootDescription)
        -- Combat-log tab: delegate filtering to Blizzard's combat-log config;
        -- omit move/close (pinned to window 1).
        if type(btn.frameID) == "number" and btn.frameID < 0 then
            local TMcl = ns.QUI.Chat.TabManager
            local clTab = TMcl and TMcl.GetWindowTab and TMcl.GetWindowTab(inst.windowID, -btn.frameID)
            if TMcl and TMcl.IsCombatLogTab and TMcl.IsCombatLogTab(clTab) then
                rootDescription:CreateButton("Combat Log Settings", function()
                    if _G.ShowUIPanel and _G.ChatConfigFrame then
                        _G.ShowUIPanel(_G.ChatConfigFrame)
                    end
                end)
                return
            end
        end
        if type(btn.frameID) == "string" then
            rootDescription:CreateButton("Close conversation", function()
                -- Click-time re-read: the button may have been pool-recycled
                -- while the menu was open. Only act if it's still a
                -- conversation tab.
                local fid = btn.frameID
                if type(fid) ~= "string" then return end
                local Conv = ns.QUI.Chat.ConversationManager
                if Conv and Conv.Close then Conv.Close(fid:sub(6)) end
            end)
            return
        end
        -- Saved-tab branch: re-derive the tab index at click time so a
        -- Rebuild that reorders tabs while the menu is open doesn't act on
        -- a stale snapshot.
        local Display = ns.QUI.Chat.DisplayLayer
        if not Display then return end
        local nWindows = (Display.GetWindowCount and Display.GetWindowCount()) or 1
        for w = 1, nWindows do
            if w ~= inst.windowID then
                rootDescription:CreateButton("Move to window " .. w, function()
                    local fid = btn.frameID
                    if type(fid) ~= "number" or fid >= 0 then return end
                    MoveTabToWindow(inst, -fid, w)
                end)
            end
        end
        rootDescription:CreateButton("Move to new window", function()
            local fid = btn.frameID
            if type(fid) ~= "number" or fid >= 0 then return end
            local newID = Display.CreateNewWindow and Display.CreateNewWindow()
            if newID then MoveTabToWindow(inst, -fid, newID, true) end
        end)
        -- Spec: a non-primary window can be closed from its tab bar once
        -- it's down to its last tab (full deletion lives in settings).
        if inst.windowID > 1 then
            local TM = ns.QUI.Chat.TabManager
            local tabs = TM and TM.GetWindowTabs and TM.GetWindowTabs(inst.windowID)
            if tabs and #tabs <= 1 then
                rootDescription:CreateButton("Close window", function()
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
        if type(self.frameID) == "string" then
            local Conv = ns.QUI.Chat.ConversationManager
            if Conv and Conv.Close then
                Conv.Close(self.frameID:sub(6))
            end
        end
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
    btn:SetScript("OnClick", OnTabClick)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
    btn:SetScript("OnDragStart", OnTabDragStart)
    btn:SetScript("OnDragStop", OnTabDragStop)
    btn:SetScript("OnHide", OnTabDragAbort)
    return btn
end

RebuildInstance = function(inst)
    if not inst.bar then return end

    for i = #inst.buttons, 1, -1 do
        inst.buttons[i]:Hide()
        inst.pool[#inst.pool + 1] = table.remove(inst.buttons)
    end

    local x = 0
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
        btn.labelColor = labelColor -- conversation tabs tint by whisper color
        btn._inst = inst -- re-bind on pool reuse (buttons never migrate between instances)
        btn.label:SetText(label)
        local sw = btn.label.GetStringWidth and btn.label:GetStringWidth()
        local w = (sw and not IsSecret(sw) and sw or 30)
            + (TAB_LABEL_PAD_X * 2)
            + TAB_BADGE_RESERVED_WIDTH
        btn:SetWidth(w)
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", inst.bar, "BOTTOMLEFT", x, 0)
        x = x + w + PAD_X
        btn:Show()
        btn:SetAlpha(1) -- pool-reuse safety: clear any drag-dim or flash-dim on recycle
        if btn._quiFlashTicker then btn._quiFlashTicker:Cancel(); btn._quiFlashTicker = nil end
        StyleButton(btn, frameID == inst.activeID)
        UpdateBadge(inst, btn)
        inst.buttons[#inst.buttons + 1] = btn
    end

    local TM = ns.QUI.Chat.TabManager
    if TM and TM.GetWindowTabs then
        local saved = TM.GetWindowTabs(inst.windowID)
        for i = 1, #saved do
            local t = saved[i]
            local label = (type(t) == "table" and type(t.name) == "string" and t.name ~= "")
                and t.name or ("Tab " .. i)
            place(-i, label, TM.BuildTabFilter and TM.BuildTabFilter(t) or nil)
        end
    end

    -- Conversation tabs render after the saved tabs (session-only).
    local Conv = ns.QUI.Chat.ConversationManager
    if Conv and Conv.EachForWindow and TM and TM.BuildConversationFilter then
        -- Whisper chat color, read-only from ChatTypeInfo (never written).
        local c = _G.ChatTypeInfo and _G.ChatTypeInfo.WHISPER
        local tint = c and { c.r or 1, c.g or 0.5, c.b or 1, 1 } or nil
        Conv.EachForWindow(inst.windowID, function(conv)
            place("conv:" .. conv.key, conv.name, TM.BuildConversationFilter(conv.key), tint)
        end)
    end

    -- Prune unread for tabs that no longer exist.
    local live = {}
    for i = 1, #inst.buttons do
        if inst.buttons[i].frameID then live[inst.buttons[i].frameID] = true end
    end
    for fid in pairs(inst.unread) do
        if not live[fid] then inst.unread[fid] = nil end
    end

    -- Active tab no longer exists -> fall back to the first tab; if a live
    -- saved tab is active, re-derive its filter only on definition change
    -- (cosmetic refreshes must not scroll-reset).
    local activeLive = false
    for i = 1, #inst.buttons do
        if inst.buttons[i].frameID == inst.activeID then
            activeLive = true
            break
        end
    end
    local TabManager = ns.QUI.Chat.TabManager
    if not activeLive then
        local first = inst.buttons[1]
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
end

function TabUI.Rebuild()
    for _, inst in pairs(instances) do
        RebuildInstance(inst)
    end
end

function TabUI.OnWindowDeleted(windowID)
    -- Window IDs shifted down in Display; rebuild the instance map. Bars are
    -- parented to their (pooled/hidden or live) containers, so dropping the
    -- stale instances and re-attaching is safe and cheap.
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

-- Create or re-parent inst.bar onto container, then anchor and level it.
-- Returns immediately if the bar already has the right parent (idempotent).
local function AttachBar(inst, container, name)
    if not inst.bar then
        inst.bar = CreateFrame("Frame", name, container)
        inst.bar:SetHeight(BAR_HEIGHT)
    elseif inst.bar:GetParent() ~= container then
        -- Recycled instance slot pointing at a new container (window
        -- deletion shuffle): re-parent before re-anchoring.
        inst.bar:SetParent(container)
    else
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
        -- Single-window fallback: if Display only exposes GetContainer (old API
        -- or test stub), attach window 1 directly.
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
                if entry.s then return end -- never classify secrets
                if entry.e == "HISTORY" or entry.e == "BACKFILL" then return end
                for _, inst in pairs(instances) do
                    local n = #inst.buttons
                    if n > 0 then
                        for i = 1, n do
                            local btn = inst.buttons[i]
                            local fid = btn.frameID
                            if fid and fid ~= inst.activeID
                                and (not btn.filter or btn.filter(entry)) then
                                inst.unread[fid] = (inst.unread[fid] or 0) + 1
                                UpdateBadge(inst, btn)
                            end
                        end
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
