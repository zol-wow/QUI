-- tests/unit/chat_copy_frame_font_test.lua
-- Run: lua tests/unit/chat_copy_frame_font_test.lua
-- The copy surfaces (history copy frame + URL popup) must render with the
-- SAME font object the chat message frame publishes (I.chatFontObject,
-- resolved once in display_layer.ApplyTheme), falling back to
-- QUI_CustomChatFontObject then stock ChatFontNormal — the chain the input
-- editbox already uses. Re-resolved on EVERY open: the frames are created
-- once and reused, and the user can change the chat font between opens.
-- luacheck: globals CreateFrame hooksecurefunc UIParent ChatFontNormal UISpecialFrames tContains QUI_CustomChatFontObject

-------------------------------------------------------------------------------
-- Frame stub: records SetFontObject; every other method is a generated noop.
-------------------------------------------------------------------------------

-- Keys copy.lua reads as PROPERTIES (not methods); the auto-noop __index must
-- hand back nil for these, not a generated function.
local NIL_PROPS = {
    ScrollBar = true, Track = true, Background = true, BG = true,
    ThumbTexture = true,
    -- font-state keys the editbox stub records; unset must read back nil, not a
    -- generated noop, so "did NOT SetFont" / seed-once assertions hold.
    font = true, fontObject = true, _quiFontSeeded = true,
    -- popup members RefreshPopupAccent probes; only SOME are assigned per
    -- popup kind (the URL popup has no hint/scrollFrame/selectAllButton/...).
    -- Real assignments land in the table and shadow these nils.
    title = true, hint = true, editBg = true, editBox = true,
    scrollFrame = true, scrollingEditBox = true, scrollBar = true,
    selectAllButton = true, closeButton = true,
    cornerCloseButton = true, resizeButton = true, text = true,
}

local function recFrame(name)
    local f = { name = name, scripts = {} }
    f.SetFontObject = function(s, fo) s.fontObject = fo end
    f.SetFont = function(s, path, size, flags) s.font = { path = path, size = size, flags = flags } end
    f.SetScript = function(s, k, v) s.scripts[k] = v end
    f.CreateTexture = function() return recFrame() end
    f.CreateFontString = function() return recFrame() end
    f.GetWidth = function() return 400 end
    f.GetName = function(s) return s.name end
    setmetatable(f, { __index = function(t, k)
        if NIL_PROPS[k] then return nil end
        local fn = function() end
        rawset(t, k, fn)
        return fn
    end })
    return f
end

-- Mock of Blizzard's ScrollingEditBoxTemplate: a control wrapping an inner
-- EditBox + ScrollBox. SetFontObject routes to the inner editbox (font lands on
-- frame.editBox), matching the real mixin.
local function scrollingEditBoxMock(name)
    local control = recFrame(name)
    local inner = recFrame((name or "SEB") .. ".EditBox")
    local scrollBox = recFrame((name or "SEB") .. ".ScrollBox")
    scrollBox.scrolledToEnd = false
    scrollBox.ScrollToEnd = function(s) s.scrolledToEnd = true end
    control.GetEditBox = function() return inner end
    control.GetScrollBox = function() return scrollBox end
    control.SetFontObject = function(_, fo) inner.fontObject = fo end
    control.SetText = function(_, t) inner.text = t end
    control.UpdateScrollBox = function() end
    return control
end

function _G.CreateFrame(_, name, parent, template)
    local f = (template == "ScrollingEditBoxTemplate") and scrollingEditBoxMock(name)
        or recFrame(name)
    if name then _G[name] = f end
    if parent and parent ~= _G.UIParent and rawget(parent, "children") then
        parent.children[#parent.children + 1] = f
    end
    return f
end
function _G.hooksecurefunc() end
function _G.tContains(t, v)
    for _, x in ipairs(t) do if x == v then return true end end
    return false
end
_G.UIParent = recFrame("UIParent")
_G.ChatFontNormal = { stock = true }
_G.UISpecialFrames = {}

-------------------------------------------------------------------------------
-- ns scaffolding
-------------------------------------------------------------------------------

-- Plain table like the real ns.QUI.Chat._internals — NO catch-all __index, so
-- I.chatFontObject reads back exactly what display_layer would have published
-- (nil when unset), which is what the fallback-chain assertions exercise.
local settings = { enabled = true }
local internals = {
    GetSettings = function() return settings end,
    IsChatEnabled = function(s) return s and s.enabled ~= false end,
    GetThemeColors = function()
        return { bg = {0,0,0,1}, bgDark = {0,0,0,1}, text = {1,1,1,1},
                 textDim = {.7,.7,.7,1}, textMuted = {.7,.7,.7,1},
                 accent = {.2,.8,.6,1}, accentHover = {.2,.8,.6,1},
                 border = {1,1,1,.1} }
    end,
    GetAccent = function() return { .2, .8, .6, 1 } end,
    ApplySurfaceStyle = function() end,
}

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    -- CreateThemedButton now delegates to the central factory, so UIKit.CreateButton
    -- must return a real mock frame; other UIKit.* stay generated no-ops.
    UIKit = setmetatable({
        CreateButton = function() return recFrame() end,
    }, { __index = function() return function() end end }),
    QUI = { Chat = {
        _internals = internals,
        DisplayLayer = {
            GetWindowCount = function() return 1 end,
            GetContainer = function() return nil end,
            ForEachVisible = function(_, fn)
                fn({ m = "hello line", e = "CHAT_MSG_SAY" })
            end,
        },
    } },
}

(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("QUI_Chat/chat/copy.lua"))("QUI", ns)
local Copy = ns.QUI.Chat.Copy
local I = ns.QUI.Chat._internals

-------------------------------------------------------------------------------
-- (a) History copy frame adopts the published chat font object on open
-------------------------------------------------------------------------------

local quiFont = { qui = true }
rawset(I, "chatFontObject", quiFont)

Copy.ShowCustomCopyFrame(1)
local frame = _G.QUI_ChatCopyFrame
assert(frame and frame.editBox, "(a) copy frame + editBox created")
assert(frame.editBox.fontObject == quiFont,
    "(a) copy editBox must adopt I.chatFontObject, got "
    .. tostring(frame.editBox.fontObject and frame.editBox.fontObject.stock and "ChatFontNormal" or frame.editBox.fontObject))
-- The ScrollingEditBox re-applies fontName on relayout; it MUST be set too or the
-- font reverts to the template default after SetText.
assert(frame.editBox.fontName == quiFont,
    "(a) ScrollingEditBox editbox must also set .fontName so the font survives relayout")
print("  ok  (a) history copy frame adopts I.chatFontObject (+ fontName)")

-------------------------------------------------------------------------------
-- (b) Font changed between opens -> reused frame re-resolves on next open
-------------------------------------------------------------------------------

local newFont = { qui = "v2" }
rawset(I, "chatFontObject", newFont)
Copy.ShowCustomCopyFrame(1)
assert(frame.editBox.fontObject == newFont,
    "(b) reused copy frame must re-resolve the font on every open")
print("  ok  (b) reused frame re-resolves font on next open")

-------------------------------------------------------------------------------
-- (c) Fallback chain: QUI_CustomChatFontObject, then stock ChatFontNormal
-------------------------------------------------------------------------------

rawset(I, "chatFontObject", nil)
_G.QUI_CustomChatFontObject = { degrade = true }
Copy.ShowCustomCopyFrame(1)
assert(frame.editBox.fontObject == _G.QUI_CustomChatFontObject,
    "(c) falls back to QUI_CustomChatFontObject when no published object")

_G.QUI_CustomChatFontObject = nil
Copy.ShowCustomCopyFrame(1)
assert(frame.editBox.fontObject == _G.ChatFontNormal,
    "(c) falls back to stock ChatFontNormal when nothing is configured")
print("  ok  (c) fallback chain QUI_CustomChatFontObject -> ChatFontNormal")

-------------------------------------------------------------------------------
-- (d) URL copy popup gets the same treatment
-------------------------------------------------------------------------------

-- The history frame uses the font-bearing ScrollingEditBoxTemplate, so the font
-- is set via the control's SetFontObject (the family attaches) — it must NEVER
-- fall back to a raw physical SetFont on that editbox.
assert(frame.editBox.font == nil,
    "(history) ScrollingEditBox editbox must take the font object, never raw SetFont")
assert(frame.scrollingEditBox, "(history) must use the ScrollingEditBox control")

rawset(I, "chatFontObject", quiFont)
Copy.ShowURLPopup("https://example.com")
local popup = _G.QUI_ChatCopyPopup
assert(popup and popup.editBox, "(d) URL popup + editBox created")
assert(popup.editBox.fontObject == quiFont,
    "(d) URL popup editBox must adopt I.chatFontObject")
print("  ok  (d) URL popup adopts I.chatFontObject")

-------------------------------------------------------------------------------
-- The URL popup is a single-line bare EditBox (not the scrolling template), so
-- it keeps the seed-once-physical + layer-family path:
-- (e) physical triple published -> seed it once (QUI font + baked symbols) and
--     layer the family for CJK.
-------------------------------------------------------------------------------

rawset(I, "chatFontObject", quiFont)
rawset(I, "chatFontPath", "Interface\\AddOns\\QUI\\Media\\Quazii.ttf")
rawset(I, "chatFontSize", 14)
rawset(I, "chatFontFlags", "OUTLINE")
popup.editBox.font = nil
popup.editBox.fontObject = nil
popup.editBox._quiFontSeeded = nil
Copy.ShowURLPopup("https://example.com/a")
assert(popup.editBox.font and popup.editBox.font.path == I.chatFontPath,
    "(e) URL editBox must seed the published physical chat font path")
assert(popup.editBox.font.size == 14 and popup.editBox.font.flags == "OUTLINE",
    "(e) URL editBox must seed the published size + flags")
assert(popup.editBox._quiFontSeeded == true, "(e) seed must be flagged")
assert(popup.editBox.fontObject == quiFont,
    "(e) URL editBox must layer the per-script family (I.chatFontObject) for CJK")
print("  ok  (e) URL editBox seeds physical base once + layers CJK family")

-------------------------------------------------------------------------------
-- (g) Reopen stability: the reused URL editbox must NOT re-SetFont (repeating it
--     drops the font), but must re-assert the family object each open.
-------------------------------------------------------------------------------

popup.editBox.font = nil  -- if SetFont runs again this becomes non-nil
popup.editBox.fontObject = nil
Copy.ShowURLPopup("https://example.com/b")
assert(popup.editBox.font == nil,
    "(g) reopen must NOT re-SetFont the seeded editbox (reopen-stable)")
assert(popup.editBox.fontObject == quiFont,
    "(g) reopen must re-assert the per-script family object")
print("  ok  (g) reopen re-asserts family, never re-seeds (reopen-stable)")

-------------------------------------------------------------------------------
-- (f) No physical path published yet (pre-build / stock chat font): nothing to
--     seed, so fall straight back to the published font-object chain.
-------------------------------------------------------------------------------

rawset(I, "chatFontPath", nil)
rawset(I, "chatFontSize", nil)
rawset(I, "chatFontFlags", nil)
rawset(I, "chatFontObject", newFont)
frame.editBox.font = nil
Copy.ShowCustomCopyFrame(1)
assert(frame.editBox.fontObject == newFont,
    "(f) with no physical path, copy editBox falls back to the font object")
assert(frame.editBox.font == nil,
    "(f) with no physical path, copy editBox does not SetFont")
print("  ok  (f) no physical path -> font-object fallback chain")

print("OK: chat_copy_frame_font_test")
