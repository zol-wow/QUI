-- tests/unit/chat_copy_button_hover_test.lua
-- Run: lua tests/unit/chat_copy_button_hover_test.lua
-- Verifies copyButtonMode="hover": button hidden until container OnEnter,
-- hidden again on true OnLeave (not when entering a child), and that
-- "always"/"hidden" modes behave as before with hover scripts cleared.

local function recFrame(name)
    local f = { name = name, shown = true, scripts = {}, mouseOver = false, frameLevel = 10, children = {}, textLabels = {} }
    local function noop() end
    f.SetSize = noop; f.SetPoint = noop; f.EnableMouse = function(s, v) s.mouse = v end
    f.SetFrameLevel = function(s, v) s.frameLevel = v end
    f.GetFrameLevel = function(s) return s.frameLevel end
    f.GetAlpha = function(s) return s.alpha or 1 end
    f.SetAlpha = function(s, v) s.alpha = v end
    f.ClearAllPoints = noop
    f.SetHeight = function(s, v) s.height = v end
    f.SetWidth = function(s, v) s.width = v end
    f.SetAllPoints = noop
    f.SetColorTexture = function(s, ...) s.color = { ... } end
    f.SetTexture = function(s, v) s.texture = v end
    f.Show = function(s) s.shown = true end
    f.Hide = function(s) s.shown = false end
    f.SetShown = function(s, v) s.shown = v and true or false end
    f.IsShown = function(s) return s.shown end
    f.IsMouseOver = function(s) return s.mouseOver end
    f.SetScript = function(s, k, v) s.scripts[k] = v end
    f.CreateTexture = function(s)
        local t = recFrame("texture")
        s.children[#s.children + 1] = t
        return t
    end
    f.CreateFontString = function()
        local fs = { SetFontObject = noop, SetPoint = noop }
        function fs:SetText(text) self.text = text end
        f.textLabels[#f.textLabels + 1] = fs
        return fs
    end
    return f
end

local container = recFrame("container")
container.frameLevel = 20
local button
function _G.CreateFrame(_, name, parent)
    local f = recFrame(name)
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    if name == "QUI_CustomChatCopyButton" then button = f end
    return f
end
function _G.hooksecurefunc() end
_G.UIParent = recFrame("UIParent")
_G.ChatFontNormal = {}
_G.StaticPopupDialogs = {}
_G.NUM_CHAT_WINDOWS = 10

local settings = { enabled = true, copyButtonMode = "hover" }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    UIKit = setmetatable({}, { __index = function() return function() end end }),
    QUI = { Chat = {
        _internals = setmetatable({
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            IsChatMessagingLockedDown = function() return false end,
        }, { __index = function() return function() end end }),
        DisplayLayer = { GetContainer = function() return container end },
        MessageStore = { ForEach = function() end },
    } },
}

assert(loadfile("modules/chat/message_store.lua"))("QUI", ns) -- harmless; copy reads it lazily
assert(loadfile("modules/chat/copy.lua"))("QUI", ns)
local Copy = ns.QUI.Chat.Copy

-- Hover mode: created hidden, container hover scripts installed
Copy.EnsureCustomCopyButton()
assert(button, "button created")
assert(button.shown == false, "hover mode starts hidden")
assert(button.frameLevel > container.frameLevel, "copy button must sit above display drag/resize overlays")
assert(button._quiGlyphParts, "copy button should render the paper-copy glyph, not a text-only label")
assert(not (button.textLabels[1] and button.textLabels[1].text == "c"), "copy button must not render as a lone c glyph")
local clicked = false
Copy.ShowCustomCopyFrame = function() clicked = true end
button.scripts.OnClick(button)
assert(clicked == true, "copy button click should open the custom copy frame")
assert(type(container.scripts.OnEnter) == "function", "OnEnter installed")
assert(type(container.scripts.OnLeave) == "function", "OnLeave installed")
assert(container.mouse == true, "container mouse enabled for hover")

-- Enter shows; leave-with-cursor-still-over (child) keeps it
container.scripts.OnEnter(container)
assert(button.shown == true, "shown on hover")
container.mouseOver = true
container.scripts.OnLeave(container)
assert(button.shown == true, "stays while cursor over a child")

-- True leave hides
container.mouseOver = false
container.scripts.OnLeave(container)
assert(button.shown == false, "hidden on true leave")

-- Switch to always: shown, hover scripts cleared, mouse released
settings.copyButtonMode = "always"
Copy.EnsureCustomCopyButton()
assert(button.shown == true, "always shows")
assert(container.scripts.OnEnter == nil and container.scripts.OnLeave == nil, "hover scripts cleared")
assert(container.mouse == false, "container mouse released")

-- Hidden mode hides
settings.copyButtonMode = "hidden"
Copy.EnsureCustomCopyButton()
assert(button.shown == false, "hidden mode hides")

print("OK: chat_copy_button_hover_test")
