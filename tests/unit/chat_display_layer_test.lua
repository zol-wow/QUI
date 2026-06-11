-- tests/unit/chat_display_layer_test.lua
-- Run: lua tests/unit/chat_display_layer_test.lua
-- Verifies: multi-window factory (two windows from config), legacy global names
-- on window 1, per-window filter routing, active-window tracking, window
-- lifecycle (CreateNewWindow / DeleteWindow), live render on append, Rebuild
-- (clear + re-append with per-window filter), Show/Hide, secret entries reach
-- AddMessage by identity with zero Lua ops, PersistGeometry writes into
-- the correct config entry, and Refresh applies maxLines + theming.

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

-- Recording frame factory --------------------------------------------------
local function makeFrame()
    local f = { points = {}, scripts = {}, shown = true, added = {} }
    function f:GetName() return self.name end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetHeight(h) self.h = h end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:GetPoint() return "BOTTOMLEFT", nil, "BOTTOMLEFT", 35, 40 end
    function f:GetNumPoints() return #self.points end
    function f:GetCenter() return self.cx or 200, self.cy or 100 end
    function f:GetWidth() return self.w or 430 end
    function f:GetHeight() return self.h or 190 end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetScript(k, v) self.scripts[k] = v end
    function f:HookScript(k, v) self.scripts["hook_" .. k] = v end
    function f:SetMovable() end
    function f:SetResizable() end
    function f:SetResizeBounds() end
    function f:SetClampedToScreen() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:StartMoving() self.moveStarts = (self.moveStarts or 0) + 1 end
    function f:StartSizing(corner) self.sizeStarts = (self.sizeStarts or 0) + 1; self.sizeCorner = corner end
    function f:StopMovingOrSizing() self.moveStops = (self.moveStops or 0) + 1 end
    function f:SetFrameStrata() end
    function f:SetFontObject(o)
        self.fontObject = o
        -- Model the live SMF behavior this regression exposed: refreshing the
        -- font object can reset justification unless the display reapplies it.
        self.justifyH = "CENTER"
    end
    function f:SetJustifyH(value) self.justifyH = value end
    function f:SetFading(v) self.fading = v end
    function f:SetTimeVisible(v) self.timeVisible = v end
    function f:SetMaxLines(n) self.maxLines = n end
    function f:EnableMouseWheel(v) self.wheelEnabled = v end
    function f:SetHyperlinksEnabled() end
    function f:AddMessage(m, r, g, b) self.added[#self.added + 1] = m end
    function f:Clear() self.added = {} end
    function f:ScrollUp() end
    function f:ScrollDown() end
    function f:ScrollToBottom() self.scrolledToBottom = true end
    function f:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
    function f:UnregisterEvent(e) if self.events then self.events[e] = nil end end
    return f
end

local frames = {}
local createdFrameCount = 0
function _G.CreateFrame(ftype, name)
    local f = makeFrame()
    f.ftype, f.name = ftype, name
    frames[#frames + 1] = f
    createdFrameCount = createdFrameCount + 1
    if name then _G[name] = f end
    return f
end
_G.UIParent = makeFrame()
_G.ChatFontNormal = {}
local layoutModeActive = false
function _G.QUI_IsLayoutModeActive() return layoutModeActive end
_G.ChatFrame1 = {}

function _G.CreateFont(name)
    local fo = { name = name }
    fo.SetFont = function(s, path, size, flags) s.path, s.size, s.flags = path, size, flags end
    _G[name] = fo
    return fo
end
function _G.GetChatWindowInfo() return "General", 13 end

local settings = { enabled = true, customDisplay = {
    maxLines = 1000,
    windows = {
        { width = 430, height = 190,
          position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 35, y = 40 }, tabs = {} },
        { width = 300, height = 150,
          position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }, tabs = {} },
    },
} }

local resolverCalls = {}
-- Live frameAnchoring store: chat window POSITION persists here (single
-- store, damage-meter pattern); windows[i] keeps only width/height.
local faStore = {}
local registeredResolvers = {}
function _G.QUI_RegisterFrameResolver(key, info)
    registeredResolvers[key] = info
end
function _G.QUI_UnregisterFrameResolver(key)
    registeredResolvers[key] = nil
end
local ns = {
    Helpers = {
        IsSecretValue = function(v) return v == secret end,
        SetFrameBackdropColor = function(f, r, g, b, a) f._bg = { r, g, b, a } end,
        SetFrameBackdropBorderColor = function(f, r, g, b, a) f._border = { r, g, b, a } end,
        GetGeneralFont = function() return "Interface\\Addons\\QUI\\media\\font.ttf" end,
        GetCore = function() return { db = { profile = { frameAnchoring = faStore } } } end,
    },
    UIKit = { ApplyPixelBackdrop = function() end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetChatSurfaceColors = function() return { 0.05, 0.07, 0.1, 0.9 }, { 0.2, 0.8, 0.6, 1 } end,
        },
        _lineColorResolver = function(event, eventArgs)
            resolverCalls[#resolverCalls + 1] = { event = event, eventArgs = eventArgs }
            if eventArgs and eventArgs[9] == "Trade" then return 0.9, 0.1, 0.1 end
            return nil
        end,
    } },
}

-- TabManager stub: returns windows config from settings.
ns.QUI.Chat.TabManager = {
    GetWindowsConfig = function() return settings.customDisplay.windows end,
}

assert(loadfile("QUI_Chat/chat/message_store.lua"))("QUI", ns)
assert(loadfile("QUI_Chat/chat/display_layer.lua"))("QUI", ns)
local Store = ns.QUI.Chat.MessageStore
local Display = ns.QUI.Chat.DisplayLayer

-- Lazy: nothing created yet
assert(#frames == 0, "no frames before EnsureCreated")

Display.EnsureCreated()

-- Core multi-window contract -----------------------------------------------
assert(Display.IsCreated(), "created")
assert(Display.GetWindowCount() == 2, "two windows from config, got " .. tostring(Display.GetWindowCount()))
assert(Display.GetContainer() == Display.GetContainer(1), "no-arg GetContainer = window 1")
assert(Display.GetContainer(1) ~= Display.GetContainer(2), "windows distinct")
assert(Display.GetContainer(1):GetName() == "QUI_CustomChatFrame",
    "window 1 keeps legacy global name, got " .. tostring(Display.GetContainer(1):GetName()))
assert(Display.GetMessageFrame(1):GetName() == "QUI_CustomChatMessages",
    "window 1 SMF keeps legacy name, got " .. tostring(Display.GetMessageFrame(1):GetName()))

-- Window 2 has its own container + SMF frames
assert(Display.GetContainer(2) ~= nil, "window 2 has container")
assert(Display.GetMessageFrame(2) ~= nil, "window 2 has SMF")

-- Geometry: each window seeded from its config entry
local c1, c2 = Display.GetContainer(1), Display.GetContainer(2)
assert(c1.w == 430 and c1.h == 190, "window 1 geometry from config")
assert(c2.w == 300 and c2.h == 150, "window 2 geometry from config")

-- Single position store: legacy windows[i].position is folded into
-- frameAnchoring (free entry, parent="disabled") and deleted.
assert(settings.customDisplay.windows[1].position == nil, "legacy position consumed (window 1)")
assert(settings.customDisplay.windows[2].position == nil, "legacy position consumed (window 2)")
assert(faStore.chatFrame1 and faStore.chatFrame1.parent == "disabled"
    and faStore.chatFrame1.point == "BOTTOMLEFT"
    and faStore.chatFrame1.offsetX == 35 and faStore.chatFrame1.offsetY == 40,
    "window 1 legacy position folded into frameAnchoring.chatFrame1")
assert(faStore.chatWindow2 and faStore.chatWindow2.point == "CENTER"
    and faStore.chatWindow2.parent == "disabled",
    "window 2 legacy position folded into frameAnchoring.chatWindow2")
-- Windows 2+ register a dynamic frame resolver so QUI_ApplyFrameAnchor can
-- position them at create time (window 1 is statically resolved).
assert(registeredResolvers.chatWindow2 and registeredResolvers.chatWindow2.resolver() == c2,
    "window 2 registers a frameAnchoring resolver")
assert(registeredResolvers.chatFrame1 == nil, "window 1 uses the static anchoring resolver")

-- maxLines from settings.customDisplay.maxLines
local smf1, smf2 = Display.GetMessageFrame(1), Display.GetMessageFrame(2)
assert(smf1.maxLines == 1000, "window 1 SMF maxLines from settings")
assert(smf2.maxLines == 1000, "window 2 SMF maxLines from settings")

-- SMF wheel + justify
assert(smf1.wheelEnabled == true, "mouse wheel input enabled on window 1 SMF")
assert(smf1.justifyH == "LEFT", "window 1 messages must stay left aligned after font setup")

-- Drag handles: 2 per window (drag strip + resize grip), 4 total
local dragHandles = {}
for _, f in ipairs(frames) do
    if f.scripts.OnMouseDown then
        dragHandles[#dragHandles + 1] = f
    end
end
assert(#dragHandles == 4, "two windows x two handles each = 4 drag-capable frames, got " .. #dragHandles)

-- Interaction state: moves/sizes only in layout mode
dragHandles[1].scripts.OnMouseDown(dragHandles[1], "LeftButton")
dragHandles[2].scripts.OnMouseDown(dragHandles[2], "LeftButton")
-- Neither container should have started moving (layout mode is off)
local anyMove = false
for _, f in ipairs(frames) do
    if (f.moveStarts or 0) > 0 or (f.sizeStarts or 0) > 0 then anyMove = true end
end
assert(not anyMove, "custom display must not move or resize outside Layout Mode")

layoutModeActive = true
dragHandles[1].scripts.OnMouseDown(dragHandles[1], "LeftButton")
dragHandles[2].scripts.OnMouseDown(dragHandles[2], "LeftButton")
local totalMoves, totalSizes = 0, 0
for _, f in ipairs(frames) do
    totalMoves = totalMoves + (f.moveStarts or 0)
    totalSizes = totalSizes + (f.sizeStarts or 0)
end
assert(totalMoves >= 1 and totalSizes >= 1,
    "custom display drag/resize should work while Layout Mode is active")
layoutModeActive = false

-- EnsureCreated is idempotent
local n = #frames
Display.EnsureCreated()
assert(#frames == n, "no duplicate frames")

-- Per-window filter routing ------------------------------------------------
Display.Rebuild(1, function(e) return e.k == "SAY" end)
Display.Rebuild(2, function(e) return e.k == "GUILD" end)
smf1.added, smf2.added = {}, {}
Store.Append({ m = "hello-say", r = 1, g = 1, b = 1, e = "CHAT_MSG_SAY", k = "SAY", t = 0 })
Store.Append({ m = "hello-guild", r = 1, g = 1, b = 1, e = "CHAT_MSG_GUILD", k = "GUILD", t = 0 })
assert(#smf1.added == 1 and smf1.added[1] == "hello-say",
    "window 1 got only SAY, got " .. #smf1.added)
assert(#smf2.added == 1 and smf2.added[1] == "hello-guild",
    "window 2 got only GUILD, got " .. #smf2.added)

-- ForEachVisible: the copy source must mirror a window's filtered view exactly
-- (store filtered by that window's active tab), not the whole store.
do
    local seen1, seen2 = {}, {}
    Display.ForEachVisible(1, function(e) seen1[#seen1 + 1] = e.m end)
    Display.ForEachVisible(2, function(e) seen2[#seen2 + 1] = e.m end)
    assert(#seen1 == 1 and seen1[1] == "hello-say",
        "ForEachVisible(1) yields only window 1's filtered set, got " .. #seen1)
    assert(#seen2 == 1 and seen2[1] == "hello-guild",
        "ForEachVisible(2) yields only window 2's filtered set, got " .. #seen2)
    -- Unknown window id is a no-op, not an error.
    local count = 0
    Display.ForEachVisible(99, function() count = count + 1 end)
    assert(count == 0, "ForEachVisible on an unknown window is a no-op")
end

-- Clear store and reset filters for subsequent tests
Store.Clear()
smf1.added, smf2.added = {}, {}
Display.Rebuild(1, nil)
Display.Rebuild(2, nil)

-- Live render on append, base color (both windows, no filter)
Store.Append({ m = "plain", r = 0.2, g = 0.3, b = 0.4, e = "CHAT_MSG_SAY", k = "SAY" })
assert(#smf1.added == 1 and smf1.added[1] == "plain", "window 1 append renders live")
assert(#smf2.added == 1 and smf2.added[1] == "plain", "window 2 append renders live")

-- Render-time channel color override (HARD CONSTRAINT 2: render-time only)
Store.Append({ m = "wts", r = 1, g = 1, b = 1, e = "CHAT_MSG_CHANNEL", k = "CHANNEL", ch = "Trade" })
-- Resolver is called; verify the call was made (color check via smf AddMessage internals
-- not tracked here since AddMessage just stores the string now — verify via resolverCalls)
assert(#resolverCalls >= 1, "resolver called for non-secret entry")

-- A malformed/stale SMF must not poison Store.Append delivery to other windows.
do
    local reported
    local oldHandler = _G.geterrorhandler
    _G.geterrorhandler = function()
        return function(err) reported = err end
    end
    local add1 = smf1.AddMessage
    smf1.AddMessage = nil
    local before2 = #smf2.added
    Store.Append({ m = "sink unavailable", r = 1, g = 1, b = 1, e = "CHAT_MSG_SYSTEM", k = "SYSTEM" })
    assert(reported == nil, "missing AddMessage sink should not report subscriber error: " .. tostring(reported))
    assert(#smf2.added == before2 + 1 and smf2.added[#smf2.added] == "sink unavailable",
        "window 2 should still render when window 1 message sink is unavailable")
    smf1.AddMessage = add1
    _G.geterrorhandler = oldHandler
end

-- Secret entry: identity pass-through to AddMessage, resolver skipped
local secretEntry = { m = secret, r = 1, g = 0.28, b = 0, e = "CHAT_MSG_RAID_WARNING", k = "RAID_WARNING", s = true }
Store.Append(secretEntry)
assert(rawequal(smf1.added[#smf1.added], secret), "secret reaches window 1 AddMessage by identity")
assert(rawequal(smf2.added[#smf2.added], secret), "secret reaches window 2 AddMessage by identity")

-- Rebuild window 1 with filter: only CHANNEL passes
Store.Clear()
Store.Append({ m = "plain", r = 0.2, g = 0.3, b = 0.4, e = "CHAT_MSG_SAY", k = "SAY" })
Store.Append({ m = "wts", r = 1, g = 1, b = 1, e = "CHAT_MSG_CHANNEL", k = "CHANNEL", ch = "Trade" })
Store.Append({ m = secret, r = 1, g = 0.28, b = 0, e = "CHAT_MSG_RAID_WARNING", k = "RAID_WARNING", s = true })
smf1.added = {}
Display.Rebuild(1, function(entry) return entry.k == "CHANNEL" end)
assert(#smf1.added == 1, "rebuild: 1 filtered match, got " .. #smf1.added)
assert(smf1.added[1] == "wts", "filtered entry rendered")
assert(smf1.scrolledToBottom, "rebuild scrolls to bottom")

-- Secret metadata match
smf1.added = {}
Display.Rebuild(1, function(entry) return entry.k == "RAID_WARNING" end)
assert(#smf1.added == 1, "rebuild: secret metadata match rendered")
assert(rawequal(smf1.added[1], secret), "secret metadata match reaches AddMessage by identity")

-- Restore no filter
Display.Rebuild(1, nil)
Display.Rebuild(2, nil)

-- Hide/Show
Display.Hide()
assert(c1.shown == false, "Hide hides window 1 container")
assert(c2.shown == false, "Hide hides window 2 container")
Display.Show()
assert(c1.shown == true, "Show shows window 1 container")
assert(c2.shown == true, "Show shows window 2 container")

-- Appends while hidden are skipped (caller must Rebuild after Show)
Display.Hide()
local hiddenCount1 = #smf1.added
Store.Append({ m = "while hidden", r = 1, g = 1, b = 1, e = "CHAT_MSG_SAY", k = "SAY" })
assert(#smf1.added == hiddenCount1, "no render to window 1 while hidden")
Display.Show()

-- Refresh() pushes maxLines + cap + surface theme live
settings.customDisplay.maxLines = 750
Display.Refresh()
assert(smf1.maxLines == 750, "Refresh applies maxLines to window 1")
assert(smf2.maxLines == 750, "Refresh applies maxLines to window 2")

-- Theming: surface colors and alpha come from the chat background helper.
assert(c1._bg and c1._bg[1] == 0.05 and c1._bg[4] == 0.9,
    "window 1 surface bg color/alpha should come from GetChatSurfaceColors, got "
        .. tostring(c1._bg and c1._bg[1]) .. "/"
        .. tostring(c1._bg and c1._bg[4]))
assert(c1._border and c1._border[2] == 0.8, "window 1 border color from skin helper")
assert(smf1.justifyH == "LEFT", "refresh must preserve left alignment after font changes")

settings.glass = { enabled = false }
Display.Refresh()
assert(c1._bg and c1._bg[4] == 0,
    "disabled chat background must make window 1 fill transparent")
settings.glass = nil

-- QUI font object applied to the SMF with the Blizzard window-1 size
assert(smf1.fontObject and smf1.fontObject.path == "Interface\\Addons\\QUI\\media\\font.ttf",
    "QUI font applied to window 1")
assert(smf1.fontObject.size == 13, "font size from GetChatWindowInfo(1)")

-- PersistGeometry: SIZE only into the window's config entry; position is
-- frameAnchoring-owned and must never come back as windows[i].position.
do
    local wc = settings.customDisplay.windows[1]
    c1.w = 550
    c1.h = 240
    Display.PersistGeometry(1)
    assert(wc.width  == 550, "PersistGeometry writes width to windows[1]")
    assert(wc.height == 240, "PersistGeometry writes height to windows[1]")
    assert(wc.position == nil, "PersistGeometry must NOT write a position sub-table")
end

-- No-arg PersistGeometry = window 1 (back-compat)
do
    c1.w = 561
    Display.PersistGeometry()
    assert(settings.customDisplay.windows[1].width == 561,
        "no-arg PersistGeometry persists window 1")
end

-- Grip/drag stop refreshes the FREE position store: the internal resize
-- grip's OnMouseUp writes the live center as CENTER-based screen offsets
-- (StopMovingOrSizing rewrites the frame anchor, so the store must follow).
do
    layoutModeActive = true
    faStore.chatFrame1 = { parent = "disabled", point = "BOTTOMLEFT",
        relative = "BOTTOMLEFT", offsetX = 35, offsetY = 40 }
    _G.UIParent.w, _G.UIParent.h = 1000, 600
    c1.cx, c1.cy = 300, 120
    -- dragHandles[2] is window 1's resize grip (creation order).
    dragHandles[2].scripts.OnMouseUp(dragHandles[2])
    local e = faStore.chatFrame1
    assert(e.point == "CENTER" and e.relative == "CENTER",
        "free-position write normalizes to CENTER offsets")
    assert(e.offsetX == 300 - 500 and e.offsetY == 120 - 300,
        "free-position offsets from live center, got "
            .. tostring(e.offsetX) .. "/" .. tostring(e.offsetY))
    -- Anchored to a real frame: the anchoring system owns position — the
    -- grip stop must NOT clobber the entry.
    faStore.chatFrame1 = { parent = "minimap", point = "TOPLEFT",
        relative = "BOTTOMLEFT", offsetX = 1, offsetY = 2 }
    c1.cx, c1.cy = 50, 50
    dragHandles[2].scripts.OnMouseUp(dragHandles[2])
    assert(faStore.chatFrame1.parent == "minimap" and faStore.chatFrame1.offsetX == 1,
        "anchored entry untouched by grip stop")
    faStore.chatFrame1 = { parent = "disabled", point = "BOTTOMLEFT",
        relative = "BOTTOMLEFT", offsetX = 35, offsetY = 40 }
    _G.UIParent.w, _G.UIParent.h = nil, nil
    layoutModeActive = false
end

-- Fade wiring: disabled by default (settings.fade absent)
settings.fade = { enabled = false, delay = 15 }
Display.Refresh()
assert(smf1.fading == false, "fade disabled: SetFading(false) called, got " .. tostring(smf1.fading))

-- Fade enabled
settings.fade.enabled = true
settings.fade.delay   = 20
Display.Refresh()
assert(smf1.fading == true,  "fade enabled: SetFading(true) called")
assert(smf1.timeVisible == 20, "fade enabled: SetTimeVisible(delay) called, got " .. tostring(smf1.timeVisible))

-- Fade disabled again
settings.fade.enabled = false
Display.Refresh()
assert(smf1.fading == false, "fade re-disabled: SetFading(false) called")

-- Hyperlink click context frame --------------------------------------------
-- A player/channel name click hands its frame to Blizzard's SetItemRef, which
-- routes it through ChatFrameUtil.SendTell / OpenChat -> ChooseBoxForSend(frame)
-- -> frame.editBox. The custom ScrollingMessageFrame has NO editBox (the QUI
-- input is ChatFrame1's editbox restyled in place), so passing the SMF crashed
-- the instant someone left-clicked a player or channel name. The handler must
-- substitute the canonical chat frame (DEFAULT_CHAT_FRAME / ChatFrame1), which
-- owns the QUI-styled editbox and stays IsShown()-true under the takeover.
do
    local captured
    local realChatFrame = { editBox = {} }
    _G.DEFAULT_CHAT_FRAME = realChatFrame
    local origSetItemRef = _G.SetItemRef
    _G.SetItemRef = function(link, text, button, frame)
        captured = { link = link, text = text, button = button, frame = frame }
    end

    local hyperlinkClick = smf1.scripts.OnHyperlinkClick
    assert(type(hyperlinkClick) == "function", "SMF wires OnHyperlinkClick")

    hyperlinkClick(smf1, "player:Tenszangetsu-Sylvanas:1:WHISPER", "[Tenszangetsu]", "LeftButton")
    assert(captured, "OnHyperlinkClick forwards to SetItemRef")
    assert(captured.frame ~= smf1,
        "must NOT pass the editbox-less custom SMF as the link context frame")
    assert(captured.frame == realChatFrame and captured.frame.editBox ~= nil,
        "must pass the canonical chat frame that owns the editbox (ChooseBoxForSend reads .editBox)")
    assert(captured.link == "player:Tenszangetsu-Sylvanas:1:WHISPER" and captured.button == "LeftButton",
        "link + button forwarded to SetItemRef unchanged")

    _G.SetItemRef = origSetItemRef
    _G.DEFAULT_CHAT_FRAME = nil
end

-- Active-window tracking ---------------------------------------------------
assert(Display.GetActiveWindow() == 1, "primary active by default")
Display.SetActiveWindow(2)
assert(Display.GetActiveWindow() == 2, "active window follows")
Display.SetActiveWindow(99)
assert(Display.GetActiveWindow() == 1, "unknown id falls back to 1")

-- Window lifecycle ---------------------------------------------------------
local newID = Display.CreateNewWindow()
assert(newID == 3 and Display.GetWindowCount() == 3,
    "CreateNewWindow appends, got id=" .. tostring(newID) .. " count=" .. tostring(Display.GetWindowCount()))
assert(#settings.customDisplay.windows == 3, "config entry appended, got " .. #settings.customDisplay.windows)
assert(settings.customDisplay.windows[3].position == nil,
    "new window config carries no position (frameAnchoring owns it)")
assert(faStore.chatWindow3 and faStore.chatWindow3.parent == "disabled"
    and faStore.chatWindow3.offsetX == 80 and faStore.chatWindow3.offsetY == -60,
    "CreateNewWindow seeds a cascade-offset FA entry")
assert(Display.DeleteWindow(1) == false, "window 1 not deletable")
Display.SetActiveWindow(3)
assert(Display.DeleteWindow(3) == true, "delete works")
assert(Display.GetWindowCount() == 2 and #settings.customDisplay.windows == 2,
    "both sides compacted, got count=" .. tostring(Display.GetWindowCount())
    .. " cfg=" .. tostring(#settings.customDisplay.windows))
assert(Display.GetActiveWindow() == 1, "active falls back after deleting active window")

-- Pooled-shell reuse: deleting then re-creating must reuse the released
-- shell (no new frame allocation), re-show it, and not leak the old filter.
-- State: windows 1..2 exist after the previous lifecycle block.
-- First need a third window to delete and pool, then re-create.
local w3id = Display.CreateNewWindow()
assert(w3id == 3, "created window 3 for pool test, got " .. tostring(w3id))
assert(Display.DeleteWindow(3) == true, "window 3 deleted into pool")
-- Now re-create: should pull from pool, no new frames allocated.
local framesBefore = createdFrameCount
local poolWinID = Display.CreateNewWindow()
assert(poolWinID == 3, "recreate after delete appends as window 3, got " .. tostring(poolWinID))
assert(createdFrameCount == framesBefore, "pooled shell reused — no new frames allocated")
local smf3 = Display.GetMessageFrame(3)
assert(Display.GetContainer(3):IsShown(), "pooled shell re-shown")
Display.Rebuild(3, nil)
smf3.added = {}
Store.Append({ m = "pool-check", r = 1, g = 1, b = 1, e = "CHAT_MSG_SAY", k = "SAY", t = 0 })
assert(#smf3.added == 1 and smf3.added[1] == "pool-check",
    "reused window renders unfiltered (stale filter cleared)")

-- Mid-list deletion: delete window 2 of 3; survivor re-indexes and
-- geometry persists into the right config slot.
-- State: windows 1..3 exist.
Display.Rebuild(2, function(e) return e.k == "NEVER" end) -- marker filter on the doomed window
local survivorContainer = Display.GetContainer(3)
-- Distinguishable FA entries: the index-keyed position store must shift
-- down with the re-indexed windows on a mid-list delete.
faStore.chatWindow2 = { parent = "disabled", point = "CENTER", relative = "CENTER", offsetX = 11, offsetY = 22 }
faStore.chatWindow3 = { parent = "disabled", point = "CENTER", relative = "CENTER", offsetX = 33, offsetY = 44 }
assert(Display.DeleteWindow(2) == true, "mid-list delete works")
assert(Display.GetWindowCount() == 2, "registry compacted after mid-list delete, got " .. tostring(Display.GetWindowCount()))
assert(Display.GetContainer(2) == survivorContainer, "old window 3 shifted into slot 2")
assert(faStore.chatWindow2 and faStore.chatWindow2.offsetX == 33 and faStore.chatWindow2.offsetY == 44,
    "FA entry shifted down with the re-indexed window")
assert(faStore.chatWindow3 == nil, "top FA key dropped after delete")
Display.PersistGeometry(2)
assert(settings.customDisplay.windows[2] ~= nil, "geometry written to compacted slot 2")

-- Layout-mode mover sync: every window lifecycle change must ping
-- QUI_LayoutMode:SyncChatWindowElements so windows 2+ get movers.
-- (The element defs themselves live in layoutmode.lua; display_layer only
-- notifies.) Stubbed late on purpose — the sync call resolves at call time.
local moverSyncs = 0
ns.QUI_LayoutMode = {
    SyncChatWindowElements = function() moverSyncs = moverSyncs + 1 end,
}
-- In-game window add/delete must bump the chat settings provider revision
-- (I.NotifyChatSettingsChanged) so an open/cached options panel rebuilds
-- instead of listing stale windows.
local settingsNotifies = 0
ns.QUI.Chat._internals.NotifyChatSettingsChanged = function()
    settingsNotifies = settingsNotifies + 1
end
local preSync = moverSyncs
Display.EnsureCreated()
assert(moverSyncs == preSync + 1, "EnsureCreated syncs layout movers")
local syncWinID = Display.CreateNewWindow()
assert(moverSyncs == preSync + 2, "CreateNewWindow syncs layout movers")
assert(settingsNotifies == 1, "CreateNewWindow bumps the settings provider revision")
assert(Display.DeleteWindow(syncWinID) == true, "sync-test window deleted")
assert(moverSyncs >= preSync + 3, "DeleteWindow syncs layout movers")
assert(settingsNotifies == 2, "DeleteWindow bumps the settings provider revision")
local refreshSyncBase = moverSyncs
Display.Refresh()
assert(moverSyncs > refreshSyncBase, "Refresh syncs layout movers")
ns.QUI_LayoutMode = nil

-- Combat anchor-restriction --------------------------------------------------
-- A protected DEPENDENT (the button bar anchors to the container's corners
-- and hosts SecureActionButton custom macro buttons) anchor-restricts the
-- container in combat: insecure SetSize/SetPoint on it is then
-- ADDON_ACTION_BLOCKED ("QUI_CustomChatFrame:SetSize()" from a mid-combat
-- options-open RefreshAll). Refresh must defer geometry while restricted and
-- re-apply once on PLAYER_REGEN_ENABLED.
do
    local inCombat = false
    _G.InCombatLockdown = function() return inCombat end

    -- Model the live-game block: geometry writes on a restricted frame in
    -- combat throw, so a regression fails loudly instead of recording.
    local function armRestricted(cont)
        cont.IsAnchoringRestricted = function() return inCombat end
        for _, m in ipairs({ "SetSize", "SetPoint", "ClearAllPoints" }) do
            local real = cont[m]
            cont[m] = function(self, ...)
                if inCombat then
                    error("ADDON_ACTION_BLOCKED: " .. m .. " on anchor-restricted frame in combat", 2)
                end
                return real(self, ...)
            end
        end
    end
    armRestricted(Display.GetContainer(1))
    armRestricted(Display.GetContainer(2))

    local cw = Display.GetContainer(1)
    local before = cw.w
    settings.customDisplay.windows[1].width = 555

    inCombat = true
    local ok, err = pcall(Display.Refresh)
    assert(ok, "Refresh in combat with a restricted container must not write geometry: " .. tostring(err))
    assert(cw.w == before, "geometry deferred while restricted, got " .. tostring(cw.w))

    -- The deferral registers a PLAYER_REGEN_ENABLED watcher.
    local watcher
    for _, f in ipairs(frames) do
        if f.events and f.events.PLAYER_REGEN_ENABLED then watcher = f end
    end
    assert(watcher, "combat-deferred geometry needs a PLAYER_REGEN_ENABLED watcher")

    inCombat = false
    watcher.scripts.OnEvent(watcher, "PLAYER_REGEN_ENABLED")
    assert(c1.w == 555, "deferred geometry applied at combat end, got " .. tostring(c1.w))

    -- Drained: a second regen fire must not re-apply (no thrash).
    c1.w = 111
    watcher.scripts.OnEvent(watcher, "PLAYER_REGEN_ENABLED")
    assert(c1.w == 111, "pending flag drained after the regen re-apply")
end

print("OK: chat_display_layer_test")
