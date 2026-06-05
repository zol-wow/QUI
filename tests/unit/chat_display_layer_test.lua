-- tests/unit/chat_display_layer_test.lua
-- Run: lua tests/unit/chat_display_layer_test.lua
-- Verifies: lazy creation, live render on append (with render-time channel
-- color override via _lineColorResolver), Rebuild() (clear + re-append with
-- filter, secrets ALWAYS pass), Show/Hide, and that secret entries reach
-- AddMessage by identity with zero Lua ops.

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

-- Recording frame factory --------------------------------------------------
local function makeFrame()
    local f = { points = {}, scripts = {}, shown = true, added = {} }
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetHeight(h) self.h = h end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:GetPoint() return "BOTTOMLEFT", nil, "BOTTOMLEFT", 35, 40 end
    function f:GetWidth() return self.w or 430 end
    function f:GetHeight() return self.h or 190 end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetScript(k, v) self.scripts[k] = v end
    function f:SetMovable() end
    function f:SetResizable() end
    function f:SetResizeBounds() end
    function f:SetClampedToScreen() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:StartMoving() end
    function f:StartSizing() end
    function f:StopMovingOrSizing() end
    function f:SetFrameStrata() end
    function f:SetFontObject() end
    function f:SetJustifyH() end
    function f:SetFading() end
    function f:SetMaxLines(n) self.maxLines = n end
    function f:SetHyperlinksEnabled() end
    function f:AddMessage(m, r, g, b) self.added[#self.added + 1] = { m = m, r = r, g = g, b = b } end
    function f:Clear() self.added = {} end
    function f:ScrollUp() end
    function f:ScrollDown() end
    function f:ScrollToBottom() self.scrolledToBottom = true end
    return f
end

local frames = {}
function _G.CreateFrame(ftype, name)
    local f = makeFrame()
    f.ftype, f.name = ftype, name
    frames[#frames + 1] = f
    return f
end
_G.UIParent = makeFrame()
_G.ChatFontNormal = {}

local settings = { enabled = true, displayMode = "custom",
    customDisplay = { width = 430, height = 190,
        position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 35, y = 40 },
        maxLines = 500, bgAlpha = 0.25 } }

local resolverCalls = {}
local ns = {
    Helpers = {
        IsSecretValue = function(v) return v == secret end,
        SetFrameBackdropColor = function() end,
        SetFrameBackdropBorderColor = function() end,
    },
    UIKit = { ApplyPixelBackdrop = function() end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
        },
        _lineColorResolver = function(event, eventArgs)
            resolverCalls[#resolverCalls + 1] = { event = event, eventArgs = eventArgs }
            if eventArgs and eventArgs[9] == "Trade" then return 0.9, 0.1, 0.1 end
            return nil
        end,
    } },
}

assert(loadfile("modules/chat/message_store.lua"))("QUI", ns)
assert(loadfile("modules/chat/display_layer.lua"))("QUI", ns)
local Store = ns.QUI.Chat.MessageStore
local Display = ns.QUI.Chat.DisplayLayer

-- Lazy: nothing created yet
assert(#frames == 0, "no frames before EnsureCreated")

Display.EnsureCreated()
assert(#frames >= 2, "container + SMF created")
local container, smf
for _, f in ipairs(frames) do
    if f.name == "QUI_CustomChatFrame" then container = f end
    if f.name == "QUI_CustomChatMessages" then smf = f end
end
assert(container, "container frame named QUI_CustomChatFrame")
assert(smf and smf.ftype == "ScrollingMessageFrame", "SMF child created as intrinsic type")
assert(smf.maxLines == 500, "maxLines from settings")
assert(container.w == 430 and container.h == 190, "saved geometry applied")

-- EnsureCreated is idempotent
local n = #frames
Display.EnsureCreated()
assert(#frames == n, "no duplicate frames")

-- Live render on append, base color
Store.Append({ m = "plain", r = 0.2, g = 0.3, b = 0.4, e = "CHAT_MSG_SAY", k = "SAY" })
assert(#smf.added == 1 and smf.added[1].m == "plain", "append renders live")
assert(smf.added[1].r == 0.2, "entry color used")

-- Render-time channel color override (HARD CONSTRAINT 2: render-time only)
Store.Append({ m = "wts", r = 1, g = 1, b = 1, e = "CHAT_MSG_CHANNEL", k = "CHANNEL", ch = "Trade" })
assert(smf.added[2].r == 0.9 and smf.added[2].g == 0.1, "resolver override applied at render")
assert(resolverCalls[#resolverCalls].eventArgs[9] == "Trade", "resolver got channel args")

-- Secret entry: identity pass-through to AddMessage, resolver skipped
Store.Append({ m = secret, r = 1, g = 0.28, b = 0, e = "CHAT_MSG_RAID_WARNING", k = "RAID_WARNING", s = true })
assert(rawequal(smf.added[3].m, secret), "secret reaches AddMessage by identity")

-- Rebuild with filter: only CHANNEL passes, but the SECRET always passes
Display.Rebuild(function(entry) return entry.k == "CHANNEL" end)
assert(#smf.added == 2, "rebuild: 1 filtered match + 1 secret, got " .. #smf.added)
assert(smf.added[1].m == "wts", "filtered entry rendered")
assert(rawequal(smf.added[2].m, secret), "secret bypasses filter on rebuild")
assert(smf.scrolledToBottom, "rebuild scrolls to bottom")

-- Hide/Show
Display.Hide()
assert(container.shown == false, "Hide hides container")
Display.Show()
assert(container.shown == true, "Show shows container")

-- Appends while hidden are skipped (caller must Rebuild after Show)
Display.Hide()
local hiddenCount = #smf.added
Store.Append({ m = "while hidden", r = 1, g = 1, b = 1, e = "CHAT_MSG_SAY", k = "SAY" })
assert(#smf.added == hiddenCount, "no render while hidden")
Display.Show()

-- Refresh() pushes maxLines + cap + bgAlpha live
settings.customDisplay.maxLines = 750
Display.Refresh()
assert(smf.maxLines == 750, "Refresh applies maxLines")

print("OK: chat_display_layer_test")
