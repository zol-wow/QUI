-- tests/unit/chat_font_justify_preserved_test.lua
-- Run: lua tests/unit/chat_font_justify_preserved_test.lua
--
-- Regression: applying the global Blizzard font to chat frames must NOT
-- re-center their text.
--
-- SetFontObject re-bases a ScrollingMessageFrame's inherited layout props, and
-- a freshly built FontFamily (Helpers.GetFontFamilyObject) carries no
-- justification — so the frame falls back to the default (CENTER) and renders
-- every line centered. This is invisible while the QUI chat takeover is on
-- (ChatFrame1 is suppressed/hidden), but once chat is handed back to Blizzard
-- the default frame shows centered text. Blizzard's own ChatFrameMixin:OnLoad
-- sets the font object THEN re-asserts SetJustifyH("LEFT") for exactly this
-- reason; QUICore:ApplyGlobalFontToChatFrames must mirror that on both the
-- apply and the restore (flip-back) paths.

-- ---------------------------------------------------------------------------
-- A chat ScrollingMessageFrame whose SetFontObject re-bases justify to the
-- WoW default (CENTER/MIDDLE), matching live behaviour.
-- ---------------------------------------------------------------------------
local function NewChatFrame()
    local cf = {
        _font = "Fonts\\ARIALN.TTF", _size = 14, _flags = "",
        _jh = "LEFT", _jv = "BOTTOM",
        _obj = { __name = "ChatFontNormal" },
    }
    function cf:GetFont() return self._font, self._size, self._flags end
    function cf:SetFont(f, s, fl) self._font, self._size, self._flags = f, s, fl end
    function cf:GetFontObject() return self._obj end
    function cf:SetFontObject(obj)
        self._obj = obj
        -- WoW re-bases inherited layout props on SetFontObject; a fresh
        -- FontFamily has no justify set, so the frame falls back to CENTER.
        self._jh, self._jv = "CENTER", "MIDDLE"
        if type(obj) == "table" and obj.__font then self._font = obj.__font end
    end
    function cf:GetJustifyH() return self._jh end
    function cf:GetJustifyV() return self._jv end
    function cf:SetJustifyH(v) self._jh = v end
    function cf:SetJustifyV(v) self._jv = v end
    return cf
end

local QUII = [[Interface\AddOns\QUI\assets\Quazii.ttf]]

local chatFrame = NewChatFrame()
_G.ChatFrame1 = chatFrame
_G.NUM_CHAT_WINDOWS = 1

local QUICore = {}
QUICore.db = { profile = { general = { applyGlobalFontToBlizzard = true, font = "Quazii" } } }

local ns = {
    Addon = QUICore,
    LSM = { Fetch = function() return QUII end },
    Helpers = {
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        GetFontFamilyObject = function(path) return { __family = "fam", __font = path } end,
    },
}

assert(loadfile("core/font_system.lua"))("QUI", ns)
assert(type(QUICore.ApplyGlobalFontToChatFrames) == "function",
    "ApplyGlobalFontToChatFrames must be a public method so the chat-font path is testable")

-- ---------------------------------------------------------------------------
-- 1) APPLY: the QUI font is set as a font OBJECT, but justify stays LEFT.
-- ---------------------------------------------------------------------------
QUICore:ApplyGlobalFontToChatFrames(QUII, true)
assert(chatFrame._obj and chatFrame._obj.__family == "fam",
    "apply must SetFontObject the per-script family on the chat frame")
assert(chatFrame._jh == "LEFT",
    "chat text justification must remain LEFT after SetFontObject (got " .. tostring(chatFrame._jh) .. ")")
assert(chatFrame._jv == "BOTTOM",
    "chat vertical justification must be preserved after SetFontObject (got " .. tostring(chatFrame._jv) .. ")")

-- ---------------------------------------------------------------------------
-- 2) RESTORE (flip back to Blizzard): original object back, still LEFT.
-- ---------------------------------------------------------------------------
QUICore:ApplyGlobalFontToChatFrames(QUII, false)
assert(chatFrame._obj and chatFrame._obj.__name == "ChatFontNormal",
    "restore must put the original font object back on the chat frame")
assert(chatFrame._jh == "LEFT",
    "chat text justification must remain LEFT after restore (got " .. tostring(chatFrame._jh) .. ")")
assert(chatFrame._jv == "BOTTOM",
    "chat vertical justification must be preserved after restore (got " .. tostring(chatFrame._jv) .. ")")

print("OK: chat_font_justify_preserved_test")
