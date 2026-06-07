-- tests/unit/chat_scrollbar_custom_test.lua
-- Run: lua tests/unit/chat_scrollbar_custom_test.lua
-- Verifies: lazy attach (per-window instances), scroll-changed callback
-- registration, thumb/track visibility vs scroll range, jump-to-bottom button
-- shown only when scrolled up and clicking it scrolls to bottom, idempotent
-- attach, OnWindowDeleted teardown + rebuild, multi-window independence.

local createdTextures = {}
local createdFontStrings = {}

local function makeFrame(ftype)
    local f = { ftype = ftype, shown = true }
    local function noop() end
    f.SetPoint = noop; f.ClearAllPoints = noop; f.SetSize = noop
    f.SetHeight = function(s, h) s.h = h end
    f.SetWidth = function(s, w) s.width = w end
    f.GetHeight = function(s) return s.h or 100 end
    f.GetBottom = function() return 100 end
    f.GetEffectiveScale = function() return 1 end
    f.SetHitRectInsets = noop
    f.EnableMouse = noop
    f.Show = function(s) s.shown = true end
    f.Hide = function(s) s.shown = false end
    f.SetShown = function(s, v) s.shown = v and true or false end
    f.IsShown = function(s) return s.shown end
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 5 end
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    f.CreateTexture = function(self)
        local tx = { SetPoint = noop, ClearAllPoints = noop,
            SetTexture = function(o, texture) o.texture = texture end,
            SetColorTexture = function(o, r, g, b, a) o.color = { r, g, b, a } end,
            SetSize = function(o, w, h) o.w, o.h = w, h end,
            SetHeight = function(o, h) o.h = h end,
            SetWidth = function(o, w) o.w = w end,
            SetRotation = function(o, r) o.rotation = r end,
            SetShown = function(o, v) o.shown = v and true or false end,
            Show = function(o) o.shown = true end, Hide = function(o) o.shown = false end }
        createdTextures[#createdTextures + 1] = tx
        -- track ownership so we can identify this frame's textures
        self._textures = self._textures or {}
        self._textures[#self._textures + 1] = tx
        return tx
    end
    f.CreateFontString = function()
        local fs = { SetPoint = noop, SetFontObject = noop }
        function fs:SetText(text) self.text = text end
        createdFontStrings[#createdFontStrings + 1] = fs
        return fs
    end
    return f
end

function _G.GetCursorPosition() return 0, _G.__cursorY or 0 end

local created = {}
function _G.CreateFrame(ftype, name, parent)
    local f = makeFrame(ftype); f.name = name; f.parent = parent
    created[#created + 1] = f
    return f
end

-- Build two containers and two SMFs (window 1 and window 2).
local containers = { makeFrame("Frame"), makeFrame("Frame") }
local scrollCbs = {}
local function makeSMF(idx)
    local smf = {
        range = 0, offset = 0,
        GetMaxScrollRange = function(s) return s.range end,
        GetScrollOffset   = function(s) return s.offset end,
        SetScrollOffset   = function(s, o)
            s.offset = o
            if scrollCbs[idx] then scrollCbs[idx]() end
        end,
        ScrollToBottom    = function(s)
            s.offset = 0
            if scrollCbs[idx] then scrollCbs[idx]() end
        end,
        SetOnScrollChangedCallback = function(s, cb)
            scrollCbs[idx] = function() cb(s) end
        end,
    }
    return smf
end
local smfs = { makeSMF(1), makeSMF(2) }

-- windowCount controls how many windows EnsureAttached iterates.
local windowCount = 1

local accent = { 0.2, 0.8, 0.6, 1 }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return { enabled = true } end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetAccent = function() return accent end,
        },
        DisplayLayer = {
            GetWindowCount = function() return windowCount end,
            GetContainer   = function(id) return containers[id or 1] end,
            GetMessageFrame = function(id) return smfs[id or 1] end,
        },
    } },
}

assert(loadfile("QUI_Chat/chat/scrollbar_custom.lua"))("QUI", ns)
local SB = ns.QUI.Chat.Scrollbar

-- ── Window 1: initial attach ─────────────────────────────────────────────────
SB.EnsureAttached()
assert(scrollCbs[1], "window 1: scroll-changed callback registered")
local track1, bottomBtn1
for _, f in ipairs(created) do
    if f.name == "QUI_CustomChatScrollbar" then track1 = f end
    if f.name == "QUI_CustomChatJumpBottom" then bottomBtn1 = f end
end
assert(track1 and bottomBtn1, "window 1: track + jump button created")
assert(track1.width == 8, "window 1: track width should be 8, got " .. tostring(track1.width))
assert(bottomBtn1._quiGlyphParts and #bottomBtn1._quiGlyphParts == 3,
    "window 1: jump button should render the drawn three-line glyph")
for _, fs in ipairs(createdFontStrings) do
    assert(fs.text ~= "v", "jump button must not render as a lone v glyph")
end

-- No scroll range: both hidden
smfs[1].range, smfs[1].offset = 0, 0
SB.Update()
assert(track1.shown == false and bottomBtn1.shown == false, "window 1: hidden with no range")

-- Range but at bottom: track shown, button hidden
smfs[1].range, smfs[1].offset = 40, 0
SB.Update()
assert(track1.shown == true, "window 1: track shown with range")
assert(bottomBtn1.shown == false, "window 1: button hidden at bottom")

-- Scrolled up: button shown; callback path drives Update too
smfs[1].offset = 10
scrollCbs[1]()
assert(bottomBtn1.shown == true, "window 1: button shown when scrolled up")

-- Click jumps to bottom
bottomBtn1._OnClick(bottomBtn1)
assert(smfs[1].offset == 0, "window 1: click scrolls to bottom")
assert(bottomBtn1.shown == false, "window 1: button hides after jump")

-- Idempotent attach
local n = #created
SB.EnsureAttached()
assert(#created == n, "no duplicate frames on re-attach")

-- Click-to-jump: cursor at 75% of the 100px track (bottom=100) -> 75% of range
smfs[1].range, smfs[1].offset = 40, 0
SB.Update()
assert(type(track1._OnMouseDown) == "function", "window 1: track is clickable")
_G.__cursorY = 175   -- (175/1 - 100) / 100 = 0.75
track1._OnMouseDown(track1)
assert(smfs[1].offset == 30, "window 1: jumped to 75% of range, got " .. tostring(smfs[1].offset))

-- Clamp above the track
_G.__cursorY = 500
track1._OnMouseDown(track1)
assert(smfs[1].offset == 40, "window 1: clamped to full range")
track1._OnMouseUp(track1)

-- Clamp below
_G.__cursorY = 50
track1._OnMouseDown(track1)
assert(smfs[1].offset == 0, "window 1: clamped to bottom")
track1._OnMouseUp(track1)

-- Restyle re-applies the accent to the thumb (skin-refresh path).
-- Track textures: [1]=bg, [2]=thumb (both created inside CreateInstance on the track frame).
local thumbTx = track1._textures and track1._textures[2]
assert(thumbTx, "thumb texture captured on track1._textures")
assert(thumbTx.color and thumbTx.color[1] == 0.2,
    "window 1: initial accent applied, got " .. tostring(thumbTx.color and thumbTx.color[1]))
accent = { 0.9, 0.1, 0.1, 1 }
SB.Restyle()
assert(thumbTx.color and thumbTx.color[1] == 0.9,
    "Restyle re-applied accent, got " .. tostring(thumbTx.color and thumbTx.color[1]))
local glyph = bottomBtn1._quiGlyphParts
assert(glyph[1].color and glyph[1].color[1] == 0.9,
    "Restyle re-applied accent to jump glyph, got " .. tostring(glyph[1].color and glyph[1].color[1]))
accent = { 0.2, 0.8, 0.6, 1 } -- restore

-- ── Window 2: multi-window attach ────────────────────────────────────────────
windowCount = 2
local nBefore = #created
SB.EnsureAttached()
assert(#created > nBefore, "window 2: new frames created for second window")
assert(scrollCbs[2], "window 2: scroll-changed callback registered")

local track2, bottomBtn2
for i = nBefore + 1, #created do
    local f = created[i]
    -- window 2+ tracks get no global name; identify by parent
    if f.ftype == "Frame" and f.parent == containers[2] and not track2 then
        track2 = f
    end
    if f.ftype == "Button" and f.parent == containers[2] then
        bottomBtn2 = f
    end
end
assert(track2 and bottomBtn2, "window 2: track + jump button created")

-- Window 2 has independent scroll state
smfs[2].range, smfs[2].offset = 20, 5
SB.Update()
assert(track2.shown == true,    "window 2: track shown with range")
assert(bottomBtn2.shown == true, "window 2: button shown when scrolled up")
-- Window 1 unaffected (offset=0 from the clamp test above)
smfs[1].range, smfs[1].offset = 40, 0
SB.Update()
assert(bottomBtn1.shown == false, "window 1: still at bottom, button hidden")

-- ── OnWindowDeleted: teardown + rebuild ─────────────────────────────────────
-- Simulate deletion of window 2: windowCount drops back to 1, old instances
-- hidden, new instance for window 1 recreated.
windowCount = 1
-- Reset the w1 SMF scroll callback slot so we can detect re-registration.
scrollCbs[1] = nil
SB.OnWindowDeleted()
-- Old track/btn for window 2 must be hidden.
assert(track2.shown == false,    "OnWindowDeleted: old window-2 track hidden")
assert(bottomBtn2.shown == false, "OnWindowDeleted: old window-2 button hidden")
-- A new instance for window 1 must have been created and its callback registered.
assert(scrollCbs[1], "OnWindowDeleted: window-1 scroll callback re-registered")
-- Idempotency after rebuild: another EnsureAttached creates nothing new.
local nAfter = #created
SB.EnsureAttached()
assert(#created == nAfter, "no duplicate frames after OnWindowDeleted rebuild")

print("OK: chat_scrollbar_custom_test")
