-- tests/unit/chat_custom_copy_lines_test.lua
-- Run: lua tests/unit/chat_custom_copy_lines_test.lua
-- Verifies Copy.GetCustomDisplayLines: store-sourced, CleanMessage-stripped,
-- secrets replaced with the protected placeholder, empty lines dropped.

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

-- copy.lua module-scope needs (stub minimally; extend ONLY if loadfile errors)
local function noopFrame()
    local f = {}
    local function noop() end
    return setmetatable(f, { __index = function() return noop end })
end
function _G.CreateFrame() return noopFrame() end
_G.UIParent = noopFrame()
function _G.hooksecurefunc() end
_G.StaticPopupDialogs = {}
_G.NUM_CHAT_WINDOWS = 10

local settings = { enabled = true, copyHistorySource = "live" }
local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    UIKit = setmetatable({}, { __index = function() return function() end end }),
    QUI = { Chat = {
        -- Live line-color resolver (channel_colors.ColorFor in production):
        -- copy must apply the SAME render-time override RenderEntry does, or
        -- channel lines fall back to their baked (often white) capture color.
        _lineColorResolver = function(event, eventArgs)
            if eventArgs and eventArgs[9] == "Trade" then return 0.9, 0.1, 0.1 end
            return nil
        end,
        _internals = setmetatable({
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
        IsChatMessagingLockedDown = function() return false end,
        GetThemeColors = function() return { bg = {0,0,0,1}, text = {1,1,1,1}, textDim = {.7,.7,.7,1}, accent = {.2,.8,.6,1}, border = {1,1,1,.1} } end,
        GetAccent = function() return { .2, .8, .6, 1 } end,
    }, { __index = function() return function() end end }) } },
}

-- Real store feeds the copy source
assert(loadfile("QUI_Chat/chat/message_store.lua"))("QUI", ns)
assert(loadfile("QUI_Chat/chat/copy.lua"))("QUI", ns)
local Copy = ns.QUI.Chat.Copy
local Store = ns.QUI.Chat.MessageStore

Store.Append({ m = "|cff00ff00|Hplayer:Ann|h[Ann]|h|r: hello |TInterface\\icon:0|t", e = "CHAT_MSG_SAY" })
Store.Append({ m = secret, s = true, e = "CHAT_MSG_RAID_WARNING" })
Store.Append({ m = "plain", e = "CHAT_MSG_SAY" })
-- Baked base color (GMOTD green) wraps the line so the copy window renders it
-- like the chat display; inner |r terminators are substituted with the base
-- color (a bare |r would reset to the editbox color, not the line color).
Store.Append({ m = "Guild MOTD: Raid tonight", r = 0.25, g = 1, b = 0.25, e = "GUILD_MOTD", k = "GUILD" })
Store.Append({ m = "|cffff0000Bob|r says hi", r = 0.25, g = 1, b = 0.25, e = "CHAT_MSG_GUILD" })
Store.Append({ m = "kill |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t now", e = "CHAT_MSG_SAY" })
Store.Append({ m = "white", r = 1, g = 1, b = 1, e = "CHAT_MSG_SAY" })
-- Class-colored player link: the color escape lives INSIDE the bracket text
-- (|H...|h[|cff..Name|r]|h — the live capture shape). The wrapper must still
-- strip; leaking raw |H..|h into the copy editbox breaks its rendering.
Store.Append({ m = "[R] |Hplayer:Castles-Illidan:26802:RAID:|h[|cfffff468Castles|r]|h: hi", e = "CHAT_MSG_RAID" })
Store.Append({ m = "[R] |Hplayer:Yukel-Illidan:26821:RAID:|h[|cfff48cbaYukel|r]|h: ok", r = 1, g = 0.5, b = 0, e = "CHAT_MSG_RAID" })
-- Battle.net kstrings (|Kq1|k) and name-wrap escapes (|Wname|w) cannot render
-- in an EditBox the way they do in a message frame: ONE leaked |K anywhere in
-- the concatenated text blanks the whole copy editbox. Must be substituted.
Store.Append({ m = "|Kq1|k has come online.", e = "BN_INLINE_TOAST_ALERT", k = "BN_INLINE_TOAST_ALERT" })
Store.Append({ m = "|HBNplayer:|Kq2|k:1:2:|h[|Kq2|k]|h whispers: yo", e = "CHAT_MSG_BN_WHISPER", k = "BN_WHISPER" })
-- Channel line baked white at capture (channel colors resolve at RENDER time):
-- the copy wrap must use the live resolver's color, like RenderEntry, so the
-- copied line keeps the channel color across inner |r resets.
Store.Append({ m = "|Hchannel:channel:5|h[5. Trade]|h |Hplayer:Ann|h[|cffc41e3aAnn|r]|h: WTS |cffa335ee|Hitem:1|h[Sword]|h|r cheap",
    r = 1, g = 1, b = 1, e = "CHAT_MSG_CHANNEL", k = "CHANNEL", ch = "Trade" })

local lines = Copy.GetCustomDisplayLines()
assert(#lines == 12, "twelve lines, got " .. #lines)
assert(lines[1] == "|cff00ff00[Ann]|r: hello ",
    "link wrapper stripped, bracket text + color escapes kept, got " .. tostring(lines[1]))
assert(lines[2] == "??? (protected message)", "secret placeholder")
assert(lines[3] == "plain", "plain passthrough (no baked color -> no wrap)")
assert(lines[4] == "|cff40ff40Guild MOTD: Raid tonight|r",
    "baked base color wraps the line, got " .. tostring(lines[4]))
assert(lines[5] == "|cff40ff40|cffff0000Bob|r says hi|r",
    "plain wrap: inner |r untouched, NO color re-assert (re-asserts corrupt editbox rendering at scale), got " .. tostring(lines[5]))
assert(lines[6] == "kill {rt8} now", "raid icon converted before texture strip, got " .. tostring(lines[6]))
assert(lines[7] == "white", "white base color skips the wrap")
assert(lines[8] == "[R] [|cfffff468Castles|r]: hi",
    "class-colored player link stripped, brackets + inner color kept, got " .. tostring(lines[8]))
assert(lines[9] == "|cffff8000[R] [|cfff48cbaYukel|r]: ok|r",
    "class-colored link inside a plain base-color wrap, got " .. tostring(lines[9]))
assert(lines[10] == "??? has come online.",
    "BN kstring substituted, got " .. tostring(lines[10]))
assert(lines[11] == "[???] whispers: yo",
    "kstring inside BNplayer link data scrubbed before link strip, got " .. tostring(lines[11]))
assert(lines[12] == "|cffe61a1a[5. Trade] [|cffc41e3aAnn|r]: WTS |cffa335ee[Sword]|r cheap|r",
    "channel line plain-wrapped in the LIVE resolver color, window-parity brackets, got " .. tostring(lines[12]))

-- No cap: every line the window's filter passes is offered (store-bounded).
for i = 1, 250 do
    Store.Append({ m = "bulk " .. i, e = "CHAT_MSG_SAY" })
end
local all = Copy.GetCustomDisplayLines()
assert(#all == 262, "no line cap — full filtered store offered, got " .. #all)
assert(all[262] == "bulk 250", "newest line last, got " .. tostring(all[262]))

print("OK: chat_custom_copy_lines_test")
