-- tests/unit/chat_conversation_manager_test.lua
-- Conversation registry: key derivation (both whisper directions, BN),
-- idempotent Open, Close-returns-to-general, window re-homing, popout
-- translation gating, auto-create store subscriber, editbox pre-target.
-- Run: lua tests/unit/chat_conversation_manager_test.lua

local secretSentinel = setmetatable({}, { __tostring = function() return "SECRET" end })
local whisperSettings = { translatePopout = true, autoIncoming = false, autoOutgoing = false, targetWindow = 1 }
local settings = { enabled = true, customDisplay = { whisperTabs = whisperSettings, windows = { {}, {} } } }

local ns = {
    Helpers = { IsSecretValue = function(v) return v == secretSentinel end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}
_G.Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
_G.GetNormalizedRealmName = function() return "Realm" end

-- Store stub with subscriber support
local subscribers = {}
ns.QUI.Chat.MessageStore = {
    OnAppend = function(fn) subscribers[#subscribers + 1] = fn end,
    Append = function(e) for i = 1, #subscribers do subscribers[i](e) end end,
}
-- Display / TabUI / TabManager stubs
local activated, reapplied, rebuilt, flashed = nil, 0, 0, nil
ns.QUI.Chat.DisplayLayer = {
    GetWindowCount = function() return #settings.customDisplay.windows end,
    GetActiveWindow = function() return 2 end,
}
ns.QUI.Chat.TabUI = {
    Rebuild = function() rebuilt = rebuilt + 1 end,
    ActivateConversation = function(windowID, key) activated = { windowID = windowID, key = key } end,
    FlashConversation = function(windowID, key) flashed = { windowID = windowID, key = key } end,
}
ns.QUI.Chat.TabManager = { ReapplyAll = function() reapplied = reapplied + 1 end }

-- EditBox stub
local eb = { attrs = {}, focused = false, text = "" }
function eb:SetAttribute(k, v) self.attrs[k] = v end
function eb:GetAttribute(k) return self.attrs[k] end
function eb:SetChatType(t) self.attrs.chatType = t end
function eb:SetTellTarget(t) self.attrs.tellTarget = t end
function eb:UpdateHeader() self.headerUpdated = (self.headerUpdated or 0) + 1 end
function eb:HasFocus() return self.focused end
function eb:HasText() return self.text ~= "" end
function eb:GetText() return self.text end
_G.ChatFrame1EditBox = eb

assert(loadfile("QUI_Chat/chat/conversation_manager.lua"))("QUI", ns)
local Conv = ns.QUI.Chat.ConversationManager

-- Key derivation
-- Already realm-qualified name: no qualification added (has a dash).
assert(Conv.DeriveKey("WHISPER", "Somebody-Realm") == "W:somebody-realm", "whisper key lowers name")
assert(Conv.DeriveKey("BN_WHISPER", "FriendName") == "BN:friendname", "bn key prefixed")
assert(Conv.DeriveKey("WHISPER", secretSentinel) == nil, "secret identity -> nil key")
assert(Conv.DeriveKey("WHISPER", "") == nil, "empty -> nil")
-- Fix 6: realm-less WHISPER name gets qualified with GetNormalizedRealmName().
assert(Conv.DeriveKey("WHISPER", "Somebody") == "W:somebody-realm",
    "realm-less whisper name qualified with own realm")
-- BN_WHISPER names are never realm-qualified (BN identity is global).
assert(Conv.DeriveKey("BN_WHISPER", "Friend") == "BN:friend",
    "BN_WHISPER name not realm-qualified")

-- Open: idempotent, clamped window, ordered per window
local key = Conv.Open("WHISPER", "Somebody-Realm", 2, false)
assert(key == "W:somebody-realm" and Conv.IsOpen(key), "open registers")
assert(Conv.Get(key).windowID == 2 and Conv.Get(key).name == "Somebody", "window + short name")
-- Additive model: opening a conversation only rebuilds the tab BAR (adds the
-- button); it must NOT trigger a content ReapplyAll (that would double-render the
-- just-appended whisper, since this subscriber runs before display_layer's).
assert(rebuilt == 1 and reapplied == 0, "open rebuilds the tab bar only, no content reapply")
assert(flashed and flashed.key == key, "background open flashes the tab")
flashed = nil
assert(Conv.Open("WHISPER", "SOMEBODY-Realm", 1, false) == key, "case-insensitive idempotent")
assert(Conv.Get(key).windowID == 2, "existing conversation keeps its window")
assert(flashed == nil, "duplicate open does not re-flash")
assert(Conv.Open("WHISPER", "Other-Realm", 99, false) and Conv.Get("W:other-realm").windowID == 1,
    "out-of-range window clamps to 1")

-- EachForWindow
local seen = {}
Conv.EachForWindow(2, function(c) seen[#seen + 1] = c.key end)
assert(#seen == 1 and seen[1] == key, "EachForWindow scoped")

-- Activate path on duplicate open
Conv.Open("WHISPER", "Somebody-Realm", 1, true)
assert(activated and activated.windowID == 2 and activated.key == key, "re-open activates existing tab")

-- Pre-target + clear (clear while NOT composing: attribute IS reset)
Conv.PreTargetEditBox(key)
assert(eb.attrs.chatType == "WHISPER" and eb.attrs.tellTarget == "Somebody-Realm", "pre-target set")
assert((eb.headerUpdated or 0) >= 1, "header updated")
Conv.ClearPreTarget()
assert(eb.attrs.chatType == "SAY", "clear restores default chat type")
Conv.ClearPreTarget()
assert(eb.attrs.chatType == "SAY", "double clear harmless")

-- Mid-compose guard on PreTargetEditBox (unchanged).
eb.focused, eb.text = true, "half a message"
eb.attrs.chatType = "GUILD"
Conv.PreTargetEditBox(key)
assert(eb.attrs.chatType == "GUILD", "mid-compose editbox not clobbered by PreTargetEditBox")
eb.focused, eb.text = false, ""

-- Fix 2b: ClearPreTarget mid-compose leaves chatType untouched.
-- Sequence: pre-target → focus+text → clear → chatType stays WHISPER.
Conv.PreTargetEditBox(key)
assert(eb.attrs.chatType == "WHISPER", "pre-target set before compose guard test")
eb.focused, eb.text = true, "half a draft"
Conv.ClearPreTarget()
assert(eb.attrs.chatType == "WHISPER",
    "ClearPreTarget mid-compose: chatType left alone (draft in progress)")
-- preTargetedKey is now nil (tracking cleared). A second ClearPreTarget is a no-op.
Conv.ClearPreTarget()
assert(eb.attrs.chatType == "WHISPER",
    "second ClearPreTarget (key already nil): no-op, chatType unchanged")
-- The residue (editbox stays in WHISPER after the close) is intentional —
-- mirrors Blizzard's sticky-whisper behaviour. The user can clear it themselves.
-- Restore clean state.
eb.focused, eb.text = false, ""
eb.attrs.chatType = "SAY"

-- User-typed whisper is never fought: pre-target, then user switches type.
Conv.PreTargetEditBox(key)
eb.attrs.chatType = "WHISPER"
eb.attrs.tellTarget = "ManualTarget-Realm" -- user re-targeted manually
Conv.ClearPreTarget()
assert(eb.attrs.chatType == "SAY", "clear still applies when whisper mode is ours (no draft)")

-- Fix 2a: closing an UNRELATED conversation must not reset the editbox.
-- Pre-target key, open a second conversation, close the second.
Conv.PreTargetEditBox(key)
assert(eb.attrs.chatType == "WHISPER", "pre-target active before unrelated-close test")
local otherKey = Conv.Open("WHISPER", "Other-Realm", 1, false)
assert(otherKey and otherKey ~= key, "opened a second conversation")
eb.attrs.chatType = "WHISPER" -- simulate editbox still in whisper mode for key
Conv.Close(otherKey)          -- close the OTHER conversation
assert(eb.attrs.chatType == "WHISPER",
    "closing unrelated conversation must not clobber editbox chatType")
-- Now close the pre-targeted conversation itself — that one SHOULD clear.
Conv.ClearPreTarget() -- reset pre-target so Close can be the one to do it
Conv.PreTargetEditBox(key)
assert(eb.attrs.chatType == "WHISPER", "re-pre-targeted before self-close test")
eb.focused, eb.text = false, "" -- not composing, so Close IS allowed to clear
Conv.Close(key)
assert(not Conv.IsOpen(key), "closed")
assert(eb.attrs.chatType == "SAY", "closing the pre-targeted conversation resets chatType")
Conv.Close(key) -- harmless double-close

-- Window re-homing on delete
Conv.Open("WHISPER", "A-Realm", 1, false)
Conv.Open("WHISPER", "B-Realm", 2, false)
Conv.OnWindowDeleted(1)
assert(Conv.Get("W:a-realm").windowID == 1, "deleted window's conversations re-home to 1")
assert(Conv.Get("W:b-realm").windowID == 1, "higher windows shift down")
Conv.Close("W:a-realm"); Conv.Close("W:b-realm")

-- Popout translation gating
activated = nil
Conv.OnBlizzardPopout("WHISPER", "Popout-Realm")
assert(Conv.IsOpen("W:popout-realm"), "popout opens conversation")
assert(Conv.Get("W:popout-realm").windowID == 2, "popout lands in last-active window")
assert(activated and activated.key == "W:popout-realm", "popout activates the tab")
Conv.OnBlizzardPopout("PARTY", "X") -- non-whisper ignored
assert(not Conv.IsOpen("W:x"), "non-whisper popout ignored")
Conv.OnBlizzardPopout("WHISPER", secretSentinel)
assert(true, "secret popout target ignored without error")
whisperSettings.translatePopout = false
Conv.OnBlizzardPopout("WHISPER", "Gated-Realm")
assert(not Conv.IsOpen("W:gated-realm"), "translatePopout=false gates")
whisperSettings.translatePopout = true
Conv.Close("W:popout-realm")

-- Auto-create subscriber (installed at load): incoming gated by autoIncoming
ns.QUI.Chat.MessageStore.Append({ e = "CHAT_MSG_WHISPER", k = "WHISPER",
    w = "W:auto-realm", wn = "Auto-Realm", m = "x", t = 0 })
assert(not Conv.IsOpen("W:auto-realm"), "autoIncoming off -> no tab")
whisperSettings.autoIncoming = true
ns.QUI.Chat.MessageStore.Append({ e = "CHAT_MSG_WHISPER", k = "WHISPER",
    w = "W:auto-realm", wn = "Auto-Realm", m = "x", t = 0 })
assert(Conv.IsOpen("W:auto-realm"), "autoIncoming on -> tab created")
assert(Conv.Get("W:auto-realm").windowID == 1, "auto tab lands in targetWindow")
-- replayed history never auto-opens
ns.QUI.Chat.MessageStore.Append({ e = "HISTORY", k = "WHISPER",
    w = "W:replay-realm", wn = "Replay-Realm", m = "x", t = 0 })
assert(not Conv.IsOpen("W:replay-realm"), "history replay never auto-opens")
-- outgoing gated by autoOutgoing
ns.QUI.Chat.MessageStore.Append({ e = "CHAT_MSG_WHISPER_INFORM", k = "WHISPER_INFORM",
    w = "W:out-realm", wn = "Out-Realm", m = "x", t = 0 })
assert(not Conv.IsOpen("W:out-realm"), "autoOutgoing off -> no tab")
whisperSettings.autoOutgoing = true
ns.QUI.Chat.MessageStore.Append({ e = "CHAT_MSG_BN_WHISPER_INFORM", k = "BN_WHISPER_INFORM",
    w = "BN:bnfriend", wn = "BnFriend", m = "x", t = 0 })
assert(Conv.IsOpen("BN:bnfriend"), "outgoing BN auto-creates")
assert(Conv.Get("BN:bnfriend").chatType == "BN_WHISPER", "BN chat type recorded")

print("chat_conversation_manager_test: all passed")
