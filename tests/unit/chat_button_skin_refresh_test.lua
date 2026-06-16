-- tests/unit/chat_button_skin_refresh_test.lua
-- Run: lua tests/unit/chat_button_skin_refresh_test.lua
--
-- Regression guard for "custom chat buttons don't follow a live skin/accent
-- color change until /reload".
--
-- Root cause: button_bar.lua only re-skins via the chat module's _afterRefresh
-- chain (chat settings changes) and never registered with the Registry
-- "skinning" group. The skin/accent/border color controls fire
-- Registry:RefreshAll("skinning"), which only refreshes group == "skinning"
-- modules -- so the chat buttons (group "chat") were skipped and kept their old
-- colors.
--
-- The fix registers a lightweight re-skin (reskinAll) with the "skinning" group
-- so a skin-color change re-applies the current colors to the live buttons. This
-- test drives the real BB.ReconcileAll build, then the real Registry-driven
-- "skinning" refresh, and asserts the button picks up the new colors.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc InCombatLockdown GameTooltip
-- luacheck: globals UIParent NUM_CHAT_WINDOWS ChatFrame1 STANDARD_TEXT_FONT

local function approx(a, b) return a and math.abs(a - b) < 1e-4 end

local NOOP = function() end
local NewFrame
local M = {}
function M:GetFrameLevel() return self.frameLevel end
function M:GetEffectiveScale() return 1 end
function M:GetWidth() return 60 end
function M:GetHeight() return 18 end
function M:IsShown() return true end
function M:IsVisible() return true end
function M:IsForbidden() return false end
function M:IsMouseOver() return false end
function M:GetBackdrop() return self._backdrop end
function M:GetChildren() return (table.unpack or unpack)(self._children) end
function M:CreateTexture() return NewFrame() end
function M:CreateFontString() return NewFrame() end
function M:SetBackdrop(info) self._backdrop = info end
function M:SetBackdropColor(r, g, b, a) self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA = r, g, b, a end
function M:SetBackdropBorderColor(r, g, b, a) self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA = r, g, b, a end
function M:SetColorTexture(r, g, b, a) self._texColor = { r, g, b, a } end
function M:SetVertexColor(r, g, b, a) self._texColor = { r, g, b, a } end
function M:SetScript(ev, fn) self._scripts[ev] = fn end
function M:HookScript(ev, fn) self._hooks[ev] = self._hooks[ev] or {}; self._hooks[ev][#self._hooks[ev] + 1] = fn end
for _, name in ipairs({
    "SetFrameLevel", "SetFrameStrata", "SetWidth", "SetHeight", "SetSize", "Show", "Hide",
    "SetPoint", "SetAllPoints", "ClearAllPoints", "EnableMouse", "GetParent", "SetParent",
    "GetScript", "RegisterForClicks", "SetAttribute", "RegisterEvent", "UnregisterEvent",
    "SetFontString", "GetFontString", "SetAlpha", "SetBlendMode", "SetTexture", "SetTexCoord",
    "SetDrawLayer", "SetFont", "SetText", "SetTextColor", "GetName",
}) do
    M[name] = NOOP
end
local frameMeta = { __index = M }
NewFrame = function()
    return setmetatable({ _children = {}, _scripts = {}, _hooks = {}, frameLevel = 1 }, frameMeta)
end

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

-- Mutable skin colors so the test can simulate a live theme change.
local SKIN = { 0.10, 0.20, 0.30, 1, 0.40, 0.50, 0.60, 0.9 }

-- Registry stub mirroring core/registry.lua's group-filtered RefreshAll.
local registrations = {}
local Registry = {
    Register = function(_, name, def) registrations[name] = def end,
    RefreshAll = function(_, group)
        for _, def in pairs(registrations) do
            if def.refresh and (not group or def.group == group) then def.refresh() end
        end
    end,
}

local settings = {
    buttonBars = {
        [1] = { enabled = true, position = "outside_left", buttons = { { id = "reload", visible = true } } },
    },
}

local ns = {
    Addon = { GetPixelSize = function() return 0.5 end },
    Registry = Registry,
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = CreateStateTable,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        IsSecretValue = function() return false end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        GetSkinColors = function()
            return SKIN[1], SKIN[2], SKIN[3], SKIN[4], SKIN[5], SKIN[6], SKIN[7], SKIN[8]
        end,
    },
    QUI = { Chat = {
        _afterRefresh = {},
        _internals = {
            GetSettings = function() return settings end,
            IsChatEnabled = function() return true end,
        },
    } },
}

CreateFrame = function(_, name, parent, _)
    local f = NewFrame()
    if name then _G[name] = f end
    if parent and parent._children then parent._children[#parent._children + 1] = f end
    return f
end
C_Timer = { After = function(_, fn) if fn then fn() end end }
hooksecurefunc = NOOP
function InCombatLockdown() return false end
GameTooltip = setmetatable({}, { __index = function() return NOOP end })
UIParent = NewFrame()
NUM_CHAT_WINDOWS = 1
ChatFrame1 = NewFrame()
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("core/uikit.lua"))("QUI", ns)
assert(loadfile("QUI_Chat/chat/button_bar.lua"))("QUI", ns)

local bar = _G.QUIChatButtonBar1
assert(bar, "button bar frame must be built at load")
local button = bar._children[1]
assert(button, "bar must have one button child")
assert(approx(button._quiBgR, SKIN[5]) and approx(button._quiBorderR, SKIN[1]),
    "precondition: button starts at the original skin colors")

-- Simulate the user changing the skin/accent color, then the skinning options'
-- Registry:RefreshAll("skinning") that those controls fire.
SKIN = { 0.70, 0.65, 0.20, 1, 0.12, 0.13, 0.14, 0.95 }
ns.Registry:RefreshAll("skinning")

assert(approx(button._quiBgR, SKIN[5]) and approx(button._quiBgG, SKIN[6]) and approx(button._quiBgB, SKIN[7]),
    "FIX: a skinning refresh must re-skin the chat button bg to the new color")
assert(approx(button._quiBorderR, SKIN[1]) and approx(button._quiBorderG, SKIN[2]),
    "FIX: a skinning refresh must re-skin the chat button border to the new color")
-- The hover base must track the new colors too (so the hover isn't stale).
assert(approx(button._quiBaseBgR, SKIN[5]) and approx(button._quiBaseBorderR, SKIN[1]),
    "FIX: re-skin must refresh the cached hover base colors")

print("OK: chat_button_skin_refresh_test")
