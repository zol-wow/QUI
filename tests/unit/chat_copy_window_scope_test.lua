-- tests/unit/chat_copy_window_scope_test.lua
-- Run: lua tests/unit/chat_copy_window_scope_test.lua
-- Verifies the copy frame is scoped to the window/tab it was opened from:
-- GetCustomDisplayLines(windowID) sources from Display.ForEachVisible(windowID)
-- (that window's active-tab filtered view, NOT the whole store), each per-window
-- copy button passes its OWN windowID through to ShowCustomCopyFrame, and the
-- no-window path still falls back to the whole store (back-compat).

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

-- Recording frame stub (minimal; extend only if loadfile/copy.lua errors).
local function recFrame(name)
    local f = { name = name, shown = true, scripts = {}, children = {}, textLabels = {}, frameLevel = 10 }
    local function noop() end
    f.SetSize = noop; f.SetPoint = noop
    f.EnableMouse = function(s, v) s.mouse = v end
    f.SetFrameLevel = function(s, v) s.frameLevel = v end
    f.GetFrameLevel = function(s) return s.frameLevel end
    f.SetAlpha = function(s, v) s.alpha = v end
    f.GetAlpha = function(s) return s.alpha or 1 end
    f.ClearAllPoints = noop
    f.SetHeight = function(s, v) s.height = v end
    f.SetWidth = function(s, v) s.width = v end
    f.SetAllPoints = noop
    f.SetColorTexture = function(s, ...) s.color = { ... } end
    f.SetTexture = noop
    f.Show = function(s) s.shown = true end
    f.Hide = function(s) s.shown = false end
    f.SetShown = function(s, v) s.shown = v and true or false end
    f.IsShown = function(s) return s.shown end
    f.IsMouseOver = function(s) return s.mouseOver end
    f.SetScript = function(s, k, v) s.scripts[k] = v end
    f.CreateTexture = function(s) local t = recFrame("tex"); s.children[#s.children + 1] = t; return t end
    f.CreateFontString = function()
        return { SetFontObject = noop, SetPoint = noop, SetText = function(s, t) s.text = t end }
    end
    return f
end

-- Two window containers (window 1 keeps the legacy global name).
local containers = { recFrame("QUI_CustomChatFrame"), recFrame("QUI_CustomChatFrame2") }
function _G.CreateFrame(_, name, parent)
    local f = recFrame(name)
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    return f
end
function _G.hooksecurefunc() end
_G.UIParent = recFrame("UIParent")
_G.ChatFontNormal = {}
_G.StaticPopupDialogs = {}
_G.NUM_CHAT_WINDOWS = 10

-- Each window's visible (filtered) set, surfaced via the Display.ForEachVisible
-- stub the copy module is expected to consult instead of the raw store.
local windowVisible = {
    [1] = { { m = "win1 hello", e = "CHAT_MSG_SAY" }, { m = secret, s = true } },
    [2] = { { m = "win2 guild", e = "CHAT_MSG_GUILD" } },
}

local settings = { enabled = true, copyButtonMode = "always" }
local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    UIKit = setmetatable({}, { __index = function() return function() end end }),
    QUI = { Chat = {
        _internals = setmetatable({
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetThemeColors = function() return { bg = {0,0,0,1}, text = {1,1,1,1}, textDim = {.7,.7,.7,1}, accent = {.2,.8,.6,1}, border = {1,1,1,.1} } end,
            GetAccent = function() return { .2, .8, .6, 1 } end,
        }, { __index = function() return function() end end }),
        DisplayLayer = {
            GetWindowCount = function() return 2 end,
            GetContainer = function(id) return containers[tonumber(id) or 1] end,
            ForEachVisible = function(id, fn)
                local set = windowVisible[tonumber(id) or 1] or {}
                for i = 1, #set do fn(set[i]) end
            end,
        },
    } },
}

assert(loadfile("QUI_Chat/chat/message_store.lua"))("QUI", ns) -- copy reads it lazily for the fallback path
assert(loadfile("QUI_Chat/chat/copy.lua"))("QUI", ns)
local Copy = ns.QUI.Chat.Copy

-- Scoping: each window's copy lines come only from its own filtered view.
local l1 = Copy.GetCustomDisplayLines(1)
assert(#l1 == 2, "window 1: 2 lines from its own view, got " .. #l1)
assert(l1[1] == "win1 hello", "window 1 line 1, got " .. tostring(l1[1]))
assert(l1[2] == "??? (protected message)", "window 1 secret placeholder, got " .. tostring(l1[2]))

local l2 = Copy.GetCustomDisplayLines(2)
assert(#l2 == 1 and l2[1] == "win2 guild",
    "window 2 scoped to its own line only, got " .. tostring(l2[1]) .. " (count " .. #l2 .. ")")

-- Per-window buttons: one per window, each routes its OWN windowID.
Copy.EnsureCustomCopyButton()
local clickedWith
Copy.ShowCustomCopyFrame = function(id) clickedWith = id end

local b1 = containers[1]._quiCopyButton
local b2 = containers[2]._quiCopyButton
assert(b1, "window 1 gets its own copy button")
assert(b2, "window 2 gets its own copy button")
assert(b1 ~= b2, "per-window copy buttons are distinct")

b1.scripts.OnClick(b1)
assert(clickedWith == 1, "window 1 button opens copy scoped to window 1, got " .. tostring(clickedWith))
b2.scripts.OnClick(b2)
assert(clickedWith == 2, "window 2 button opens copy scoped to window 2, got " .. tostring(clickedWith))

-- No-window / no-Display path falls back to the whole store (back-compat with
-- the existing no-arg callers and the lines-only test).
ns.QUI.Chat.DisplayLayer = nil
local Store = ns.QUI.Chat.MessageStore
Store.Append({ m = "store-line", e = "CHAT_MSG_SAY" })
local lAll = Copy.GetCustomDisplayLines()
assert(#lAll == 1 and lAll[1] == "store-line", "no windowID falls back to whole store, got " .. tostring(lAll[1]))

print("OK: chat_copy_window_scope_test")
