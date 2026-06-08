-- tests/unit/chat_editbox_font_test.lua
-- Run: lua tests/unit/chat_editbox_font_test.lua
-- The chat input editbox must follow the QUI font: StyleEditBox applies the
-- shared chat-message font object (_G.QUI_CustomChatFontObject) so typed text
-- matches the rendered messages exactly. RemoveEditBoxStyle hands back the
-- stock font object on a live disable flip.

local function noop() end

function _G.InCombatLockdown() return false end
function _G.GetChatWindowInfo() return "General" end
_G.C_Timer = { After = function(_, callback) callback() end }

-- Sentinel font objects.
_G.ChatFontNormal = { _id = "ChatFontNormal" }
_G.QUI_CustomChatFontObject = { _id = "QUI_CustomChatFontObject" }

local function createFrame()
    local frame = { shown = true, hooks = {}, frameLevel = 20, width = 420 }
    function frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function frame:SetScript(script, cb) self.scripts = self.scripts or {}; self.scripts[script] = cb end
    function frame:HookScript(script, cb)
        self.hooks[script] = self.hooks[script] or {}
        table.insert(self.hooks[script], cb)
    end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points = self.points or {}; table.insert(self.points, {...}) end
    function frame:SetHeight(h) self.height = h end
    function frame:SetWidth(w) self.width = w end
    function frame:GetWidth() return self.width end
    function frame:GetName() return self.name end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameLevel(l) self.frameLevel = l end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:EnableMouse(e) self.mouseEnabled = e end
    function frame:SetAlpha(a) self.alpha = a end
    function frame:GetRegions() end
    function frame:SetTextInsets(...) self.insets = { ... } end
    function frame:GetParent() return self.parent end
    function frame:SetParent(p) self.parent = p end
    return frame
end

local createdFrames = {}
function _G.CreateFrame(_, name, parent)
    local f = createFrame()
    f.parent = parent
    createdFrames[#createdFrames + 1] = f
    return f
end

local settings = {
    enabled = true,
    glass = { enabled = true },
    editBox = { enabled = true, positionTop = false },
}

-- A header-style fontstring (the channel prefix shown left of the input).
-- Inherits ChatFontNormal from the template, like the real editbox children.
local function createFontString()
    local fs = { fontObject = _G.ChatFontNormal }
    function fs:SetFontObject(fo) self.fontObject = fo end
    function fs:GetFontObject() return self.fontObject end
    return fs
end

-- Editbox mock that records font-object assignments. Starts on the stock font
-- (mirrors the ChatFrameEditBoxTemplate's `<FontString inherits="ChatFontNormal"/>`).
local editBox = createFrame()
editBox.fontObject = _G.ChatFontNormal
function editBox:SetFontObject(fo) self.fontObject = fo end
function editBox:GetFontObject() return self.fontObject end
-- Channel prefix + suffix children (parentKeys per ChatFrameEditBox.xml).
editBox.header = createFontString()
editBox.headerSuffix = createFontString()

local chatFrame = createFrame()
chatFrame.name = "ChatFrame1"
chatFrame.editBox = editBox

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetCurrentSpecID = function() return nil end,
    },
    QUI = {
        Chat = {
            _internals = {
                editBoxState = setmetatable({}, { __mode = "k" }),
                editBoxBackdrops = setmetatable({}, { __mode = "k" }),
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                ApplySurfaceStyle = noop,
            },
        },
    },
}

assert(loadfile("QUI_Chat/chat/editbox_basics.lua"))("QUI", ns)
local EditBoxBasics = ns.QUI.Chat.EditBoxBasics

-- 1) Styling applies the shared chat-message font object — to the input AND the
--    channel-prefix header fontstrings (which inherit ChatFontNormal otherwise).
EditBoxBasics.StyleEditBox(chatFrame)
assert(editBox.fontObject == _G.QUI_CustomChatFontObject,
    "editbox must adopt the QUI chat message font object")
assert(editBox.header.fontObject == _G.QUI_CustomChatFontObject,
    "channel prefix header must adopt the QUI chat font")
assert(editBox.headerSuffix.fontObject == _G.QUI_CustomChatFontObject,
    "channel prefix suffix must adopt the QUI chat font")

-- 2) Live disable flip restores the stock font object on input AND header.
EditBoxBasics.RemoveEditBoxStyle(chatFrame)
assert(editBox.fontObject == _G.ChatFontNormal,
    "RemoveEditBoxStyle must restore the stock font object")
assert(editBox.header.fontObject == _G.ChatFontNormal,
    "RemoveEditBoxStyle must restore the stock header font")

-- 3) Re-enable re-applies the QUI font.
EditBoxBasics.StyleEditBox(chatFrame)
assert(editBox.fontObject == _G.QUI_CustomChatFontObject,
    "re-enabling re-applies the QUI chat font")

-- 4) No custom font object yet (e.g. no font path) -> fall back to stock font.
_G.QUI_CustomChatFontObject = nil
editBox.fontObject = nil
EditBoxBasics.StyleEditBox(chatFrame)
assert(editBox.fontObject == _G.ChatFontNormal,
    "missing custom font object falls back to ChatFontNormal")

print("OK: chat_editbox_font_test")
