-- tests/unit/chat_copy_button_hover_hide_test.lua
-- Run: lua tests/unit/chat_copy_button_hover_hide_test.lua
--
-- Regression guard for the copy button (copyButtonMode == "hover") failing to
-- auto-show/-hide when the cursor enters or leaves the chat window THROUGH a
-- mouse-enabled child (the scrollbar track).
--
-- Root cause: hover relied on the container's OWN OnEnter/OnLeave. The container
-- has mouse-enabled children (scrollbar track, jump-to-bottom + copy buttons,
-- drag strip, resize grip). When the cursor enters by landing directly on a
-- child, the container's OnEnter never fires (button never shows); when it
-- leaves through a child, the container's OnLeave never re-fires (button never
-- hides). Both directions break.
--
-- The fix drives show AND hide from a single IsMouseOver() poll (true across the
-- whole container rect, children included), toggling on transitions only.
--
-- luacheck: globals CreateFrame

-------------------------------------------------------------------------------
-- Minimal frame factory: records scripts, supports the copy-glyph build path.
-------------------------------------------------------------------------------
local NOOP = function() end
local M = {}
function M:IsMouseOver() return self._mouseOver and true or false end
function M:Show() self._shown = true end
function M:Hide() self._shown = false end
function M:IsShown() return self._shown and true or false end
function M:SetShown(v) self._shown = v and true or false end
function M:SetScript(ev, fn) self._scripts[ev] = fn end
function M:GetScript(ev) return self._scripts[ev] end
function M:HookScript(ev, fn) self._scripts[ev] = fn end
function M:CreateTexture() return CreateFrame("Texture") end
function M:CreateFontString() return CreateFrame("FontString") end
function M:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
for _, name in ipairs({
    "SetSize", "SetPoint", "SetAllPoints", "ClearAllPoints", "SetWidth", "SetHeight",
    "EnableMouse", "SetFrameLevel", "GetFrameLevel", "SetTexture", "SetAlpha",
    "SetVertexColor", "SetTexCoord", "SetDrawLayer", "SetRotation", "SetBlendMode",
    "SetText", "SetFontObject", "SetFont", "SetTextColor", "GetName",
}) do
    M[name] = NOOP
end
local frameMeta = { __index = M }

function _G.CreateFrame(_, name, parent)
    local f = setmetatable({ _scripts = {}, _shown = true, _children = {} }, frameMeta)
    if name then _G[name] = f end
    if parent and parent._children then parent._children[#parent._children + 1] = f end
    return f
end

local function fire(frame, event)
    local fn = frame._scripts[event]
    if fn then fn(frame) end
end

-------------------------------------------------------------------------------
-- ns / settings
-------------------------------------------------------------------------------
local container = setmetatable({ _scripts = {}, _shown = true, _children = {} }, frameMeta)

local settings = { enabled = true, copyButtonMode = "hover" }

local accent = { 0.2, 0.8, 0.6, 1 }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    UIKit = {},
    QUI = { Chat = {
        _internals = {
            GetSettings   = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetAccent     = function() return accent end,
            ApplySurfaceStyle = NOOP,
        },
        DisplayLayer = {
            GetWindowCount = function() return 1 end,
            GetContainer   = function() return container end,
        },
    } },
}

assert(loadfile("QUI_Chat/chat/copy.lua"))("QUI", ns)
local Copy = ns.QUI.Chat.Copy
assert(Copy and type(Copy.EnsureCustomCopyButton) == "function", "Copy.EnsureCustomCopyButton exported")

-------------------------------------------------------------------------------
-- Build the per-window copy button in hover mode.
-------------------------------------------------------------------------------
Copy.EnsureCustomCopyButton()
local button = container._quiCopyButton
assert(button, "copy button created on the container")
assert(button:IsShown() == false, "hover mode: button starts hidden")
-- Poll-only design: show/hide are driven by an IsMouseOver() poll, NOT by
-- container OnEnter/OnLeave (which a child intercepts in both directions).
assert(type(container._scripts.OnUpdate) == "function", "hover mode: IsMouseOver poll installed")
assert(container._scripts.OnEnter == nil and container._scripts.OnLeave == nil,
    "hover mode: must NOT rely on container OnEnter/OnLeave")

-------------------------------------------------------------------------------
-- INVERSE BUG (this report): the cursor enters the chat by landing DIRECTLY on
-- a mouse-enabled child (the scrollbar track) — the container's OnEnter never
-- fires. The poll sees IsMouseOver() == true and must SHOW the button anyway.
-------------------------------------------------------------------------------
container._mouseOver = true                 -- cursor is over the scrollbar child
fire(container, "OnUpdate")
assert(button:IsShown() == true,
    "FIX: entering chat directly over the scrollbar must auto-show the copy "
    .. "button (container OnEnter never fired)")
print("  ok  hover: enter via the scrollbar still auto-shows the copy button")

-- Idle frames while still over the window are a no-op (transition-only toggle).
fire(container, "OnUpdate")
assert(button:IsShown() == true, "button stays shown while cursor remains over the window")

-------------------------------------------------------------------------------
-- ORIGINAL BUG: the cursor leaves the frame entirely THROUGH the scrollbar
-- child — the container's OnLeave never re-fires. The poll sees IsMouseOver()
-- go false and must HIDE the button.
-------------------------------------------------------------------------------
container._mouseOver = false
fire(container, "OnUpdate")
assert(button:IsShown() == false,
    "FIX: leaving chat through the scrollbar must auto-hide the copy button")
fire(container, "OnUpdate")
assert(button:IsShown() == false, "stays hidden while cursor is away (no thrash)")
print("  ok  hover: exit via the scrollbar still auto-hides the copy button")

-------------------------------------------------------------------------------
-- Switching to "always" must clear the poll and show the button.
-------------------------------------------------------------------------------
container._mouseOver = true
fire(container, "OnUpdate")                 -- re-show via the poll
settings.copyButtonMode = "always"
Copy.EnsureCustomCopyButton()
assert(button:IsShown() == true, "always mode: button shown")
assert(container._scripts.OnUpdate == nil, "always mode: stale poll cleared")
print("  ok  mode switch to always clears the hover poll")

-------------------------------------------------------------------------------
-- "hidden" mode also clears the poll and hides the button.
-------------------------------------------------------------------------------
settings.copyButtonMode = "hover"
Copy.EnsureCustomCopyButton()
container._mouseOver = true
fire(container, "OnUpdate")
settings.copyButtonMode = "hidden"
Copy.EnsureCustomCopyButton()
assert(button:IsShown() == false, "hidden mode: button hidden")
assert(container._scripts.OnUpdate == nil, "hidden mode: stale poll cleared")
print("  ok  mode switch to hidden clears the hover poll")

print("OK: chat_copy_button_hover_hide_test")
