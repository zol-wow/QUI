-- tests/unit/chat_editbox_restore_safe_font_test.lua
-- Run: lua tests/unit/chat_editbox_restore_safe_font_test.lua
--
-- Regression (ERROR #132 STACK_OVERFLOW when disabling the chat module):
-- RemoveEditBoxStyle must NEVER restore the chat font by re-applying a captured
-- font OBJECT via SetFontObject. In-game, ChatFrame1EditBox:GetFontObject()
-- returns a runtime font object — reported "Font <UnknownFile:0>" — that RESOLVES
-- to a real file (ARIALN) yet whose derivation chain is self-referential.
-- Re-applying it via editBox:SetFontObject(snapshot) makes the engine walk that
-- cycle until the C stack overflows (uncatchable by pcall, and indistinguishable
-- by any property test since GetFont returns a valid path). The restore must use
-- SetFont(file,height,flags) — explicit physical values with no derivation link —
-- so a cycle is structurally impossible. This test asserts SetFontObject is never
-- called during restore and that SetFont applies the stock ChatFontNormal values.

local function noop() end
function _G.InCombatLockdown() return false end
function _G.GetChatWindowInfo() return "General" end
_G.C_Timer = { After = function(_, callback) callback() end }

-- Stock named font: resolves to a real file (GetFont returns a path + size).
_G.ChatFontNormal = { _id = "ChatFontNormal" }
function _G.ChatFontNormal:GetFont() return "Fonts\\ARIALN.TTF", 14, "" end
_G.QUI_CustomChatFontObject = { _id = "QUI_CustomChatFontObject" }
function _G.QUI_CustomChatFontObject:GetFont() return "Fonts\\Quazii.ttf", 13, "" end

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
function _G.CreateFrame(_, _name, parent)
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

-- Font-tracking mix-in: records SetFont calls and counts SetFontObject calls so
-- the test can assert the restore path uses SetFont (safe) and never
-- SetFontObject (the crash call). The intrinsic font object is the FontInstance
-- itself — mirrors GetFontObject() returning a self-referential "<UnknownFile:0>"
-- object that still resolves to a real file.
local function makeFontTracking(obj)
    obj.fontObject = obj
    obj.setFontObjectCalls = 0
    obj.font = nil
    function obj:SetFontObject(fo) self.setFontObjectCalls = self.setFontObjectCalls + 1; self.fontObject = fo end
    function obj:GetFontObject() return self.fontObject end
    function obj:GetFont() return "Fonts\\ARIALN.TTF", 14, "" end -- resolves to a real file
    function obj:SetFont(file, h, fl) self.font = { file, h, fl } end
    return obj
end

local editBox = makeFontTracking(createFrame())
editBox.header = makeFontTracking({})
editBox.headerSuffix = makeFontTracking({})

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

-- 1) Styling adopts the QUI font (apply path legitimately uses SetFontObject).
EditBoxBasics.StyleEditBox(chatFrame)
assert(editBox.fontObject == _G.QUI_CustomChatFontObject,
    "editbox must adopt the QUI chat message font object on style")

-- Reset the SetFontObject counters so we measure ONLY the restore path.
editBox.setFontObjectCalls = 0
editBox.header.setFontObjectCalls = 0
editBox.headerSuffix.setFontObjectCalls = 0

-- 2) THE REGRESSION: the live disable flip must NOT call SetFontObject (which
--    self-cycles on the captured "<UnknownFile:0>" object -> stack overflow).
EditBoxBasics.RemoveEditBoxStyle(chatFrame)
assert(editBox.setFontObjectCalls == 0,
    "RemoveEditBoxStyle must NOT use SetFontObject on the input (self-cycle -> stack overflow)")
assert(editBox.header.setFontObjectCalls == 0,
    "RemoveEditBoxStyle must NOT use SetFontObject on a header child")
assert(editBox.headerSuffix.setFontObjectCalls == 0,
    "RemoveEditBoxStyle must NOT use SetFontObject on a header suffix child")

-- 3) The stock chat font is restored via SetFont with ChatFontNormal's values.
assert(type(editBox.font) == "table" and editBox.font[1] == "Fonts\\ARIALN.TTF" and editBox.font[2] == 14,
    "RemoveEditBoxStyle must SetFont the input to the stock ChatFontNormal values")
assert(type(editBox.header.font) == "table" and editBox.header.font[1] == "Fonts\\ARIALN.TTF",
    "RemoveEditBoxStyle must SetFont the header child to the stock font")
assert(type(editBox.headerSuffix.font) == "table" and editBox.headerSuffix.font[1] == "Fonts\\ARIALN.TTF",
    "RemoveEditBoxStyle must SetFont the header suffix child to the stock font")

-- 4) Fallback: with no ChatFontNormal, restore still uses a safe stock file via
--    SetFont (never SetFontObject) and never errors.
_G.ChatFontNormal = nil
EditBoxBasics.StyleEditBox(chatFrame)
editBox.setFontObjectCalls = 0
editBox.font = nil
EditBoxBasics.RemoveEditBoxStyle(chatFrame)
assert(editBox.setFontObjectCalls == 0,
    "restore must not use SetFontObject even without ChatFontNormal")
assert(type(editBox.font) == "table" and editBox.font[1] == "Fonts\\ARIALN.TTF" and editBox.font[2] == 14,
    "restore falls back to a hardcoded stock font file/size when ChatFontNormal is absent")

print("OK: chat_editbox_restore_safe_font_test")
