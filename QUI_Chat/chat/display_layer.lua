-- modules/chat/display_layer.lua
-- The custom chat display: N QUI-owned windows (movable/resizable, glass
-- backdrop), each containing a ScrollingMessageFrame VIEW of the single
-- shared MessageStore filtered by that window's active tab.
-- ScrollingMessageFrame is an intrinsic widget (Blizzard_SharedXML/
-- ScrollingMessageFrame.xml:3); its render path re-initializes fontstrings
-- "to clear secret aspects" before SetText (ScrollingMessageFrame.lua:632-635)
-- so secret message bodies pass straight through AddMessage untouched.
-- Tab filters only inspect stored event/channel metadata, not the body.
--
-- All geometry here is OUR OWN insecure frames — no protected-frame writes,
-- no combat deferral needed.
--
-- Window 1 is the PRIMARY: it keeps the QUI_CustomChatFrame /
-- QUI_CustomChatMessages global names (layoutmode.lua + anchoring.lua bind
-- to them), it owns the editbox fallback, and it is never deletable.
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: display_layer.lua loaded before chat.lua. Check chat.xml — chat.lua must precede display_layer.lua.")

ns.QUI.Chat.DisplayLayer = ns.QUI.Chat.DisplayLayer or {}
local Display = ns.QUI.Chat.DisplayLayer

local Store = assert(ns.QUI.Chat.MessageStore, "message_store.lua must load before display_layer.lua")

local windows = {}        -- dense array: windowID -> win { id, container, smf, dragHandle, resizeGrip, filter }
local framePool = {}      -- released window shells (windows 2+) for reuse
local activeWindowID = 1  -- last-active window (editbox follow); 1 = primary
local storeSubscribed = false
local nameCounter = 1     -- monotonic global-name suffix for windows 2+

local DRAG_STRIP_HEIGHT = 14
local MIN_W, MIN_H = 220, 100

local function IsLayoutModeActive()
    return _G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive() and true or false
end

local function GetCustomDisplaySettings()
    local settings = I.GetSettings and I.GetSettings()
    return settings and settings.customDisplay, settings
end

local function GetWindowsConfig()
    local TM = ns.QUI.Chat.TabManager
    local cfg = TM and TM.GetWindowsConfig and TM.GetWindowsConfig()
    return type(cfg) == "table" and cfg or {}
end

-- Position persists in the codebase-standard sub-table shape:
-- windows[id].position = { point, relPoint, x, y }.
local function SaveGeometry(win)
    local wc = GetWindowsConfig()[win.id]
    if not wc or not win.container then return end
    local point, _, relPoint, x, y = win.container:GetPoint(1)
    if point then
        wc.position = wc.position or {}
        wc.position.point, wc.position.relPoint = point, relPoint or point
        wc.position.x, wc.position.y = x, y
    end
    wc.width  = math.floor((win.container:GetWidth()  or wc.width  or 430) + 0.5)
    wc.height = math.floor((win.container:GetHeight() or wc.height or 190) + 0.5)
end

local function ApplySavedGeometry(win)
    local wc = GetWindowsConfig()[win.id]
    if not wc or not win.container then return end
    win.container:SetSize(wc.width or 430, wc.height or 190)
    win.container:ClearAllPoints()
    local pos = wc.position or {}
    win.container:SetPoint(pos.point or "BOTTOMLEFT", _G.UIParent,
        pos.relPoint or pos.point or "BOTTOMLEFT", pos.x or 35, pos.y or 40)
end

-- Theme the container + SMF font from the chat module's skin helpers.
local function ApplyTheme(win)
    if not win.container then return end
    local cd, settings = GetCustomDisplaySettings()
    local bgColor, borderColor
    if I.GetChatSurfaceColors then
        bgColor, borderColor = I.GetChatSurfaceColors(settings)
    end
    if not bgColor then
        local theme = I.GetThemeColors and I.GetThemeColors()
        bgColor    = (theme and theme.bg)     or { 0, 0, 0, 0.25 }
        borderColor = (theme and theme.border) or { 0, 0, 0, 1 }
    end
    if Helpers and Helpers.SetFrameBackdropColor then
        local bgAlpha = bgColor[4] or 0.25
        local glass = settings and settings.glass
        if glass and glass.enabled == false then
            bgAlpha = 0
        end
        Helpers.SetFrameBackdropColor(win.container,
            bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgAlpha)
        Helpers.SetFrameBackdropBorderColor(win.container,
            borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1)
    end
    local smf = win.smf
    if smf then
        -- Fade: settings.fade.{enabled,delay} -> SMF native fade API.
        -- SetFading(bool) / SetTimeVisible(seconds) — both non-secret.
        local fade = settings and settings.fade
        if fade and fade.enabled then
            smf:SetFading(true)
            smf:SetTimeVisible(type(fade.delay) == "number" and fade.delay > 0 and fade.delay or 15)
        else
            smf:SetFading(false)
        end
        local fontPath = Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont()
        if fontPath then
            local size = 13
            if _G.GetChatWindowInfo then
                local _, winSize = _G.GetChatWindowInfo(1)
                -- Guard: GetChatWindowInfo can hand back garbage sizes.
                if type(winSize) == "number" and winSize > 0 and winSize < 64 then
                    size = winSize
                end
            end
            local flags = ""
            if settings and settings.font and settings.font.forceOutline then
                flags = "OUTLINE"
            end
            -- Prefer a per-script font family so CJK chat (Korean/Chinese
            -- names and messages) falls back to Blizzard fonts instead of
            -- rendering blank; degrade to the single-file path if unavailable.
            local family = Helpers and Helpers.GetFontFamilyObject and Helpers.GetFontFamilyObject(fontPath, size, flags)
            if family then
                smf:SetFontObject(family)
            elseif _G.CreateFont then
                local fo = _G.QUI_CustomChatFontObject or _G.CreateFont("QUI_CustomChatFontObject")
                fo:SetFont(fontPath, size, flags)
                smf:SetFontObject(fo)
            else
                smf:SetFontObject(_G.ChatFontNormal)
            end
        else
            smf:SetFontObject(_G.ChatFontNormal)
        end
        smf:SetJustifyH("LEFT")
        if cd then smf:SetMaxLines(cd.maxLines or 1000) end
    end
end

-- The container's SetMovable/SetResizable flags are set ONCE at creation and
-- NEVER toggled here — the damage-meter pattern (damage_meter.lua:2264-2265).
-- Toggling SetResizable with layout-mode state raced the resize grips: the
-- flag could read false at the instant a grip fired, so the protected
-- StartSizing threw "Frame is not resizable" + tainted QUI. The window stays
-- move/resize-only-in-Layout-Mode because the AFFORDANCES are gated, not the
-- flags: the dragHandle/resizeGrip are mouse-disabled outside Layout Mode
-- (below) AND every handler returns early unless IsLayoutModeActive(), and the
-- four-corner overlay grips live on a handle that is hidden outside Layout Mode.
local function RefreshInteractionState()
    local layoutActive = IsLayoutModeActive()
    for i = 1, #windows do
        local win = windows[i]
        if win.dragHandle  then win.dragHandle:EnableMouse(layoutActive)  end
        if win.resizeGrip  then win.resizeGrip:EnableMouse(layoutActive)  end
    end
end

local layoutCallbacksRegistered = false
local function RegisterLayoutCallbacks()
    if layoutCallbacksRegistered then return end
    local core = _G.QUI
    if not core then return end
    local registered = false
    if type(core.RegisterLayoutModeEnter) == "function" then
        core:RegisterLayoutModeEnter(RefreshInteractionState)
        registered = true
    end
    if type(core.RegisterLayoutModeExit) == "function" then
        core:RegisterLayoutModeExit(RefreshInteractionState)
        registered = true
    end
    layoutCallbacksRegistered = registered
end

-- Render one entry into a window's SMF. Color override is resolved at RENDER
-- time via channel_colors' registered resolver (never ChatTypeInfo writes).
-- Secrets: no resolver call, no operators — straight to AddMessage.
local function RenderEntry(win, entry)
    if not win.smf then return end
    local addMessage = win.smf.AddMessage
    if type(addMessage) ~= "function" then return end
    local r, g, b = entry.r or 1, entry.g or 1, entry.b or 1
    if not entry.s then
        local resolver = ns.QUI.Chat._lineColorResolver
        if resolver and entry.e then
            local orR, orG, orB = resolver(entry.e, entry.ch and { [9] = entry.ch } or nil)
            if orR then r, g, b = orR, orG, orB end
        end
    end
    addMessage(win.smf, entry.m, r, g, b)
end

local function PassesFilter(win, entry)
    if not win.filter then return true end
    return win.filter(entry) and true or false
end

local function OnStoreAppend(entry)
    for i = 1, #windows do
        local win = windows[i]
        if win.container and win.container:IsShown() and PassesFilter(win, entry) then
            RenderEntry(win, entry)
        end
    end
end

function Display.SetActiveWindow(id)
    id = tonumber(id) or 1
    if not windows[id] then id = 1 end
    if activeWindowID == id then return end
    activeWindowID = id
    -- Editbox follows the active window: re-anchor via editbox_basics
    -- (self-gates on settings.editBox; idempotent).
    local EditBox = ns.QUI.Chat.EditBoxBasics
    if EditBox and EditBox.StyleEditBox and _G.ChatFrame1 then
        EditBox.StyleEditBox(_G.ChatFrame1)
    end
end

function Display.GetActiveWindow()
    if not windows[activeWindowID] then return 1 end
    return activeWindowID
end

local function CreateWindow(id)
    -- Check the pool first (reuse released window-2+ shells).
    local win = table.remove(framePool)
    if win then
        win.id = id
        win.filter = nil
        win.smf:Clear()
        windows[id] = win
        ApplySavedGeometry(win)
        ApplyTheme(win)
        win.container:Show()
        RefreshInteractionState()
        return win
    end

    win = { id = id }
    local containerName, smfName
    if id == 1 then
        containerName = "QUI_CustomChatFrame"
        smfName       = "QUI_CustomChatMessages"
    else
        -- Global names for windows 2+ are decoupled from the (mutable)
        -- window id: pooled shells keep their birth name forever.
        nameCounter = nameCounter + 1
        containerName = "QUI_CustomChatFrame"  .. nameCounter
        smfName       = "QUI_CustomChatMessages" .. nameCounter
    end

    local container = CreateFrame("Frame", containerName, _G.UIParent, "BackdropTemplate")
    win.container = container
    container:SetFrameStrata("LOW")
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:SetResizable(true)
    container:SetResizeBounds(MIN_W, MIN_H)
    if UIKit and UIKit.ApplyPixelBackdrop then
        UIKit.ApplyPixelBackdrop(container, 1, true)
    end

    -- Top drag strip (keeps the message area free for hyperlink clicks).
    -- Mouse-only during layout mode; in normal play, window activation
    -- happens via the SMF OnMouseDown hook below and tab clicks.
    local dragHandle = CreateFrame("Frame", nil, container)
    win.dragHandle = dragHandle
    dragHandle:SetPoint("TOPLEFT",  container, "TOPLEFT",  0, 0)
    dragHandle:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    dragHandle:SetHeight(DRAG_STRIP_HEIGHT)
    dragHandle:EnableMouse(true)
    dragHandle:SetScript("OnMouseDown", function()
        Display.SetActiveWindow(win.id)
        if not IsLayoutModeActive() then return end
        container:StartMoving()
    end)
    dragHandle:SetScript("OnMouseUp", function()
        if not IsLayoutModeActive() then return end
        container:StopMovingOrSizing()
        SaveGeometry(win)
    end)
    -- SetPropagateMouseMotion is a protected function — safe here because
    -- window creation runs at login/options time, never from a secure handler.
    if dragHandle.SetPropagateMouseMotion then
        dragHandle:SetPropagateMouseMotion(true)
    end

    -- Bottom-right resize grip.
    local resizeGrip = CreateFrame("Frame", nil, container)
    win.resizeGrip = resizeGrip
    resizeGrip:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    resizeGrip:SetSize(14, 14)
    resizeGrip:EnableMouse(true)
    resizeGrip:SetScript("OnMouseDown", function()
        Display.SetActiveWindow(win.id)
        if not IsLayoutModeActive() then return end
        -- Guarantee the resizable flag at the point of use: StartSizing is
        -- protected and throws "Frame is not resizable" if RefreshInteractionState
        -- hasn't (re)enabled it for this container. SetResizable is not protected.
        if container.SetResizable and container.IsResizable and not container:IsResizable() then
            container:SetResizable(true)
        end
        container:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        if not IsLayoutModeActive() then return end
        container:StopMovingOrSizing()
        SaveGeometry(win)
    end)
    if resizeGrip.SetPropagateMouseMotion then
        resizeGrip:SetPropagateMouseMotion(true)
    end

    local cd = GetCustomDisplaySettings()
    local smf = CreateFrame("ScrollingMessageFrame", smfName, container)
    win.smf = smf
    smf:SetPoint("TOPLEFT",     container, "TOPLEFT",     6,  -(DRAG_STRIP_HEIGHT + 2))
    -- Right inset clears the scrollbar's lane instead of overlapping it. The
    -- custom scrollbar occupies the rightmost ~11px (scrollbar_custom.lua's
    -- TRACK_INSET 3 + TRACK_WIDTH 8); the SMF and that track are both mouse-
    -- enabled at the same frame level, so any overlap lets the SMF win the
    -- contested zone and swallow clicks on the bar's left half. -13 ends the
    -- text ~2px before the bar's left edge so the whole bar stays grabbable.
    smf:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -13, 6)
    smf:SetJustifyH("LEFT")
    smf:SetMaxLines((cd and cd.maxLines) or 1000)
    smf:SetHyperlinksEnabled(true)
    smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if not _G.SetItemRef then return end
        -- The 4th SetItemRef arg becomes Blizzard's contextData.frame. For
        -- player/BN/channel links it flows into ChatFrameUtil.SendTell /
        -- OpenChat -> ChooseBoxForSend(frame), which dereferences frame.editBox.
        -- This custom ScrollingMessageFrame has no editBox (the QUI input is
        -- ChatFrame1's editbox, restyled in place by editbox_basics), so handing
        -- Blizzard `self` crashes the instant someone left-clicks a player or
        -- channel name. Hand it the canonical chat frame instead: ChatFrame1 is
        -- only reparented (never Hide()'d) under the takeover, so it stays
        -- IsShown()-true and owns the QUI-styled editbox -- whispers/joins open
        -- there. contextData.frame is read ONLY by chat link handlers (whisper
        -- editbox + context-menu anchor); every other link type anchors its
        -- tooltip to UIParent, so this substitution is inert for them.
        local refFrame = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1 or self
        _G.SetItemRef(link, text, button, refFrame)
    end)
    -- Clicking the message area marks the window active (editbox follow).
    if smf.HookScript then
        smf:HookScript("OnMouseDown", function()
            Display.SetActiveWindow(win.id)
        end)
    end
    -- WoW only delivers OnMouseWheel after EnableMouseWheel(true); a bare
    -- ScrollingMessageFrame doesn't enable it.
    if smf.EnableMouseWheel then
        smf:EnableMouseWheel(true)
    end
    -- Wheel scrolls 3 lines; Ctrl+wheel-down jumps to the newest line.
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp(); self:ScrollUp(); self:ScrollUp()
        elseif _G.IsControlKeyDown and _G.IsControlKeyDown() then
            self:ScrollToBottom()
        else
            self:ScrollDown(); self:ScrollDown(); self:ScrollDown()
        end
    end)

    windows[id] = win
    ApplySavedGeometry(win)
    ApplyTheme(win)
    RegisterLayoutCallbacks()
    RefreshInteractionState()
    return win
end

-- Layout-mode movers for windows 2+ are owned by layoutmode.lua (it has the
-- overlay/resize-grip machinery); it re-derives the element set from the
-- live window count, so every lifecycle change just pings it. Nil-safe both
-- ways: layoutmode installs SyncChatWindowElements ~2s after login and runs
-- one sync itself then, covering windows created before the method exists.
local function SyncChatWindowMovers()
    local um = ns.QUI_LayoutMode
    if um and um.SyncChatWindowElements then
        um:SyncChatWindowElements()
    end
end

function Display.EnsureCreated()
    local cfg = GetWindowsConfig()
    for id = 1, #cfg do
        if not windows[id] then CreateWindow(id) end
    end
    if not storeSubscribed then
        storeSubscribed = true
        Store.OnAppend(OnStoreAppend)
    end
    SyncChatWindowMovers()
end

-- Append a new window to the config and create it. Returns the new id.
function Display.CreateNewWindow()
    if not windows[1] then return nil end -- display not active; nothing to add to
    local cfg = GetWindowsConfig()
    local TM = ns.QUI.Chat.TabManager
    local n = #cfg
    cfg[n + 1] = {
        width  = 430,
        height = 190,
        -- Cascade so stacked new windows don't perfectly overlap.
        position = { point = "CENTER", relPoint = "CENTER", x = 40 * n, y = -30 * n },
        tabs = { TM and TM.NewDefaultTab and TM.NewDefaultTab() or { name = "Tab 1", groups = {}, channels = {}, invert = false } },
    }
    local id = n + 1
    CreateWindow(id)
    local TabUI = ns.QUI.Chat.TabUI
    if TabUI and TabUI.EnsureAttached then TabUI.EnsureAttached() end
    local Scrollbar = ns.QUI.Chat.Scrollbar
    if Scrollbar and Scrollbar.EnsureAttached then Scrollbar.EnsureAttached() end
    local Copy = ns.QUI.Chat.Copy
    if Copy and Copy.EnsureCustomCopyButton then Copy.EnsureCustomCopyButton() end
    SyncChatWindowMovers()
    -- A cached options panel must rebuild — its window lists changed.
    if I.NotifyChatSettingsChanged then I.NotifyChatSettingsChanged() end
    return id
end

-- Delete a window (id >= 2). Its tabs are removed with it; open conversation
-- tabs re-home to window 1. Returns true on success.
function Display.DeleteWindow(id)
    id = tonumber(id)
    if not id or id <= 1 or not windows[id] then return false end
    local cfg = GetWindowsConfig()
    if cfg[id] then table.remove(cfg, id) end
    local win = table.remove(windows, id)
    -- A delete can race a live layout-mode drag: leave no frame in moving state.
    if win.container.StopMovingOrSizing then win.container:StopMovingOrSizing() end
    win.container:Hide()
    win.smf:Clear()
    win.filter = nil
    framePool[#framePool + 1] = win
    -- Re-index surviving windows' id fields.
    for i = id, #windows do windows[i].id = i end
    if activeWindowID == id then
        activeWindowID = 1
        local EditBox = ns.QUI.Chat.EditBoxBasics
        if EditBox and EditBox.StyleEditBox and _G.ChatFrame1 then
            EditBox.StyleEditBox(_G.ChatFrame1)
        end
    elseif activeWindowID > id then
        activeWindowID = activeWindowID - 1
    end
    local TM = ns.QUI.Chat.TabManager
    if TM and TM.OnWindowDeleted then TM.OnWindowDeleted(id) end
    local Conv = ns.QUI.Chat.ConversationManager
    if Conv and Conv.OnWindowDeleted then Conv.OnWindowDeleted(id) end
    local TabUI = ns.QUI.Chat.TabUI
    if TabUI and TabUI.OnWindowDeleted then TabUI.OnWindowDeleted(id) end
    local Scrollbar = ns.QUI.Chat.Scrollbar
    if Scrollbar and Scrollbar.OnWindowDeleted then Scrollbar.OnWindowDeleted() end
    local Copy = ns.QUI.Chat.Copy
    if Copy and Copy.OnWindowDeleted then Copy.OnWindowDeleted() end
    SyncChatWindowMovers()
    -- A cached options panel must rebuild — its window lists changed (the
    -- context-menu "Close window" path never goes through the settings UI).
    if I.NotifyChatSettingsChanged then I.NotifyChatSettingsChanged() end
    return true
end

-- Clear + re-append the full store through `filterFn` (nil = everything)
-- for ONE window. This is how tab switching works losslessly.
function Display.Rebuild(windowID, filterFn)
    local win = windows[tonumber(windowID) or 1]
    if not win then return end
    win.filter = filterFn
    if not win.smf then return end
    win.smf:Clear()
    Store.ForEach(function(entry)
        if PassesFilter(win, entry) then
            RenderEntry(win, entry)
        end
    end)
    win.smf:ScrollToBottom()
end

-- Live-apply settings that can change without recreate.
function Display.Refresh()
    -- Never CREATES: Apply()'s enabled path calls EnsureCreated explicitly.
    -- Refresh reached while the takeover is off (or pre-create) must not
    -- seed config or materialize shown frames.
    if not windows[1] then return end
    local cd = GetCustomDisplaySettings()
    if cd then Store.SetCap(cd.maxLines or 1000) end
    -- Config may have gained/lost windows (profile import).
    Display.EnsureCreated()
    local cfg = GetWindowsConfig()
    for i = #windows, #cfg + 1, -1 do
        Display.DeleteWindow(i)
    end
    for i = 1, #windows do
        ApplySavedGeometry(windows[i])
        ApplyTheme(windows[i])
    end
    SyncChatWindowMovers()
end

-- CONTRACT: appends are skipped while hidden (OnStoreAppend gates on
-- IsShown), so callers showing previously-hidden displays must follow up
-- with TabManager.ReapplyAll() — display_fallback.Apply() does exactly that.
function Display.Show()
    for i = 1, #windows do
        if windows[i].container then windows[i].container:Show() end
    end
end

function Display.Hide()
    for i = 1, #windows do
        if windows[i].container then windows[i].container:Hide() end
    end
end

-- Write a window's current rect into its config entry. No-arg = window 1
-- (layoutmode.lua's grip OnMouseUp contract).
function Display.PersistGeometry(windowID)
    local win = windows[tonumber(windowID) or 1]
    if win then SaveGeometry(win) end
end

-- Accessors for sibling chrome files (tab bar, scrollbar, copy button).
-- No-arg = window 1 (back-compat for window-1-only chrome).
function Display.GetContainer(windowID)
    local win = windows[tonumber(windowID) or 1]
    return win and win.container
end

function Display.GetMessageFrame(windowID)
    local win = windows[tonumber(windowID) or 1]
    return win and win.smf
end

-- Iterate the store through ONE window's active-tab filter, in store order —
-- exactly the lines that window's SMF currently renders. The copy frame uses
-- this so the copied text matches the visible window (not the whole store).
-- Entries pass through untouched (may carry secret bodies); callers must honor
-- entry.s and never apply a Lua operator to entry.m.
function Display.ForEachVisible(windowID, fn)
    if type(fn) ~= "function" then return end
    local win = windows[tonumber(windowID) or 1]
    if not win then return end
    Store.ForEach(function(entry)
        if PassesFilter(win, entry) then
            fn(entry)
        end
    end)
end

function Display.GetWindowCount()
    return #windows
end

function Display.IsCreated()
    return windows[1] ~= nil
end
