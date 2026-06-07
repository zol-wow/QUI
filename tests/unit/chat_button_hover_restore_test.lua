-- tests/unit/chat_button_hover_restore_test.lua
-- Run: lua tests/unit/chat_button_hover_restore_test.lua
--
-- Regression guard for the "custom chat button hover highlight never clears"
-- bug (it stayed lit until a rebuild, and compounded brighter on each hover).
--
-- Root cause: button_bar.lua applySkin() skins the button with
-- SkinBase.ApplyFullBackdrop, whose manual backdrop installs
-- ManualSetBackdropColor as frame:SetBackdropColor -- and that setter WRITES the
-- frame's _quiBgR/_quiBorderR backup fields (uikit.lua). The OnEnter hover
-- brighten called self:SetBackdropColor(self._quiBgR + 0.30, ...), which
-- overwrote _quiBgR with the brightened value; OnLeave then "restored" from the
-- now-corrupted _quiBgR, so the highlight stuck (and each hover read the
-- already-brightened value and brightened again).
--
-- The fix caches the canonical base colors in dedicated _quiBase* fields that the
-- manual setter never touches, and has the hover hooks read/restore from those.
-- This test drives the real BB.ReconcileAll -> createButton -> applySkin path
-- through the real SkinBase manual backdrop, then fires OnEnter/OnLeave.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc InCombatLockdown GameTooltip
-- luacheck: globals UIParent NUM_CHAT_WINDOWS ChatFrame1 STANDARD_TEXT_FONT

local function approx(a, b) return a and math.abs(a - b) < 1e-4 end

-- Frame/texture factory: records applied backdrop colors, tracks children, and
-- captures OnEnter/OnLeave handlers (SetScript + HookScript) so the test can
-- fire them. Permissive for the long tail of void setters via __index.
local NOOP = function() end
local NewFrame
-- Methods table used as __index. Using a TABLE (not a function) is deliberate:
-- unknown DATA-field reads (e.g. button._quiHoverHooked) must return nil, not a
-- truthy no-op function -- otherwise applySkin's `if button._quiHoverHooked then
-- return end` guard would short-circuit and never attach the hover hooks.
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
-- Real SkinBase installs ManualSetBackdropColor over these after the first
-- ApplyFullBackdrop; before that, record directly so preconditions hold.
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

-- Fire a frame's handlers for an event (SetScript first, then HookScript hooks),
-- mirroring WoW's dispatch order.
local function fire(frame, event)
    if frame._scripts[event] then frame._scripts[event](frame) end
    local hooks = frame._hooks[event]
    if hooks then for i = 1, #hooks do hooks[i](frame) end end
end

-- Mutable skin colors: sr,sg,sb,sa, bgr,bgg,bgb,bga.
local SKIN = { 0.10, 0.20, 0.30, 1, 0.40, 0.50, 0.60, 0.9 }

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

local settings = {
    buttonBars = {
        [1] = { enabled = true, position = "outside_left", buttons = { { id = "reload", visible = true } } },
    },
}

local ns = {
    Addon = { GetPixelSize = function() return 0.5 end },
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

-- Load the real SkinBase, then the real button-bar module. button_bar runs
-- ApplyEnabled() at load -> builds the bar + button with our settings.
assert(loadfile("core/uikit.lua"))("QUI", ns)
assert(loadfile("QUI_Chat/chat/button_bar.lua"))("QUI", ns)

local bar = _G.QUIChatButtonBar1
assert(bar, "button bar frame must be built at load")
local button = bar._children[1]
assert(button, "bar must have one button child")

-- Precondition: the skinned button starts at the base bg/border color.
assert(approx(button._quiBgR, SKIN[5]) and approx(button._quiBorderR, SKIN[1]),
    "precondition: button starts at base skin colors")

-- Hover on: bg brightens by +0.30, border by *1.6.
fire(button, "OnEnter")
assert(approx(button._quiBgR, math.min(SKIN[5] + 0.30, 1)),
    "precondition: OnEnter brightens the bg")

-- Hover off: the button must RETURN to the base color, not stay brightened.
fire(button, "OnLeave")
assert(approx(button._quiBgR, SKIN[5]) and approx(button._quiBgG, SKIN[6]) and approx(button._quiBgB, SKIN[7]),
    "FIX: OnLeave must restore the base bg, not stay on the brightened hover color")
assert(approx(button._quiBorderR, SKIN[1]) and approx(button._quiBorderG, SKIN[2]),
    "FIX: OnLeave must restore the base border, not stay on the brightened hover color")

-- A second hover cycle must NOT drift brighter (the bug compounded each time).
fire(button, "OnEnter")
fire(button, "OnLeave")
assert(approx(button._quiBgR, SKIN[5]) and approx(button._quiBorderR, SKIN[1]),
    "FIX: repeated hover must not march the colors toward white")

print("OK: chat_button_hover_restore_test")
