-- tests/unit/chat_button_bar_item_order_test.lua
-- Run: lua tests/unit/chat_button_bar_item_order_test.lua
--
-- Covers the merged button-bar item model.
--
-- The bar used to store built-ins and custom slash commands in two separate
-- arrays (`buttons` / `customButtons`) and render them in two passes, so a
-- custom button could never sit before a built-in. They are now one ordered
-- `items` array whose array order IS render order.
--
-- There is deliberately NO schema migration for the fold: seed-derived and
-- imported profiles are stamped at the current schema and never enter the
-- migration pipeline, so button_bar.lua's normalizeEntry is the only path that
-- covers every profile. This test pins that fold, the single-pass renderer,
-- and MoveItem's clamping.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc InCombatLockdown GameTooltip
-- luacheck: globals UIParent NUM_CHAT_WINDOWS ChatFrame1 STANDARD_TEXT_FONT

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
function M:SetBackdropColor() end
function M:SetBackdropBorderColor() end
function M:SetScript(ev, fn) self._scripts[ev] = fn end
function M:HookScript(ev, fn) self._hooks[ev] = self._hooks[ev] or {}; self._hooks[ev][#self._hooks[ev] + 1] = fn end
-- The two fields the assertions read back off a built button.
function M:SetText(t) self._text = t end
function M:SetAttribute(k, v) self._attributes[k] = v end
function M:RegisterForClicks(...) self._clicks = { ... } end
function M:SetFontString(fs) self._fontString = fs end
-- Reparenting has to be real here: buildBar tears a bar down by reparenting
-- every child to nil before rebuilding, so a no-op SetParent would leave the
-- old buttons in _children and make a rebuilt bar look like it appended.
function M:GetParent() return self._parent end
function M:SetParent(parent)
    local old = self._parent
    if old and old._children then
        for i = #old._children, 1, -1 do
            if old._children[i] == self then table.remove(old._children, i) end
        end
    end
    self._parent = parent
    if parent and parent._children then
        parent._children[#parent._children + 1] = self
    end
end
for _, name in ipairs({
    "SetFrameLevel", "SetFrameStrata", "SetWidth", "SetHeight", "SetSize", "Show", "Hide",
    "SetPoint", "SetAllPoints", "ClearAllPoints", "EnableMouse",
    "GetScript", "RegisterEvent", "UnregisterEvent", "GetFontString", "SetAlpha",
    "SetBlendMode", "SetTexture", "SetTexCoord", "SetColorTexture", "SetVertexColor",
    "SetDrawLayer", "SetFont", "SetTextColor", "GetName",
}) do
    M[name] = NOOP
end
local frameMeta = { __index = M }
NewFrame = function()
    return setmetatable({ _children = {}, _scripts = {}, _hooks = {}, _attributes = {}, frameLevel = 1 }, frameMeta)
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

-- Legacy split shape, deliberately: built-ins in one array, customs in the
-- other. This is what every profile written before the merge looks like.
local settings = {
    buttonBars = {
        [1] = {
            enabled = true,
            position = "outside_left",
            buttons = {
                -- Pre-rebrand id, exactly as the shipped starter seed stores
                -- it. BUILTINS only knows qui_options, so without the
                -- rename map this row renders nothing despite visible = true.
                { id = "qui_options",    visible = true },
                { id = "social",         visible = false },
                { id = "reload",         visible = true },
                -- Transient options-binding key that leaked into stored
                -- config in the shipped seed. Names no built-in; must be
                -- purged, not surfaced as a settings row.
                { id = "_quiTransientOptionsProxy", visible = false },
            },
            customButtons = {
                { label = "Ready", slashCommand = "/readycheck", icon = "" },
                { label = "Pull",  slashCommand = "/pull 10",    icon = "" },
            },
        },
    },
}

local ns = {
    Addon = { GetPixelSize = function() return 0.5 end },
    Registry = { Register = NOOP, RefreshAll = NOOP },
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = CreateStateTable,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        IsSecretValue = function() return false end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        GetSkinColors = function() return 0.1, 0.2, 0.3, 1, 0.4, 0.5, 0.6, 0.9 end,
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
    f._parent = parent
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

;(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("core/uikit.lua"))("QUI", ns)
assert(loadfile("QUI_Chat/chat/button_bar.lua"))("QUI", ns)

local BB = ns.QUI.Chat.ButtonBar
local entry = settings.buttonBars[1]

----------------------------------------------------------------------------
-- 1. The legacy arrays fold into one ordered list and are then gone.
----------------------------------------------------------------------------
assert(entry.buttons == nil, "fold must drop the legacy buttons array")
assert(entry.customButtons == nil, "fold must drop the legacy customButtons array")
assert(#entry.items == 5, "fold must carry all 5 rows across, got " .. tostring(#entry.items))

local function describe(items)
    local out = {}
    for i = 1, #items do
        out[i] = items[i].id or items[i].slashCommand
    end
    return table.concat(out, ",")
end

-- Order is preserved exactly: every built-in in its stored order, then every
-- custom in its stored order -- what the old two-pass renderer produced.
assert(describe(entry.items) == "qui_options,social,reload,/readycheck,/pull 10",
    "fold must preserve legacy render order, got " .. describe(entry.items))
assert(entry.items[1].kind == "builtin" and entry.items[4].kind == "custom",
    "fold must stamp kind on both sorts of row")
assert(entry.items[2].visible == false, "fold must carry the visible flag through")

-- The rebrand rename must be applied, and the leaked proxy row purged.
assert(entry.items[1].id == "qui_options",
    "pre-rebrand qui_options must be renamed, got " .. tostring(entry.items[1].id))
for i = 1, #entry.items do
    assert(entry.items[i].id ~= "_quiTransientOptionsProxy",
        "the leaked transient options-binding row must be purged")
end

----------------------------------------------------------------------------
-- 2. Rendering is a single pass in array order, and hidden built-ins are
--    skipped without consuming a slot.
----------------------------------------------------------------------------
local function renderedLabels()
    local bar = _G.QUIChatButtonBar1
    local out = {}
    for i = 1, #bar._children do
        local child = bar._children[i]
        -- Custom buttons carry a macrotext attribute; built-ins carry a label.
        out[i] = child._attributes.macrotext or child._fontString._text
    end
    return table.concat(out, ",")
end

assert(renderedLabels() == "QUI,Reload,/readycheck,/pull 10",
    "baseline render must skip the hidden built-in, got " .. renderedLabels())

----------------------------------------------------------------------------
-- 3. A custom button can be moved AHEAD of the built-ins -- the whole point
--    of merging the two arrays.
----------------------------------------------------------------------------
assert(BB.MoveItem(1, 4, -1) == 3, "MoveItem must return the new index")
assert(BB.MoveItem(1, 3, -1) == 2)
assert(BB.MoveItem(1, 2, -1) == 1)
assert(describe(entry.items) == "/readycheck,qui_options,social,reload,/pull 10",
    "custom row must be movable to the head of the list, got " .. describe(entry.items))

BB.ReconcileAll()
assert(renderedLabels() == "/readycheck,QUI,Reload,/pull 10",
    "renderer must follow the new order, got " .. renderedLabels())

----------------------------------------------------------------------------
-- 4. MoveItem clamps at both ends and rejects out-of-range indices rather
--    than wrapping or shuffling.
----------------------------------------------------------------------------
local before = describe(entry.items)
assert(BB.MoveItem(1, 1, -1) == nil, "moving the first row up must be a no-op")
assert(BB.MoveItem(1, #entry.items, 1) == nil, "moving the last row down must be a no-op")
assert(BB.MoveItem(1, 0, 1) == nil, "index 0 must be rejected")
assert(BB.MoveItem(1, 99, -1) == nil, "out-of-range index must be rejected")
assert(BB.MoveItem(99, 1, 1) == nil, "unknown frame must be rejected")
assert(describe(entry.items) == before, "a rejected move must not touch the array")

----------------------------------------------------------------------------
-- 5. InitFrameDefaults appends built-ins the user has never seen instead of
--    splicing them in at BUILTIN_ORDER position (which would reshuffle an
--    order the user arranged by hand), and they arrive hidden.
----------------------------------------------------------------------------
settings.buttonBars[2] = {
    enabled = false,
    items = {
        { kind = "custom", label = "First", slashCommand = "/qui", icon = "" },
        { kind = "builtin", id = "reload", visible = true },
    },
}
local seeded = BB.InitFrameDefaults(2)
assert(seeded.items[1].slashCommand == "/qui" and seeded.items[2].id == "reload",
    "existing rows must keep their position")
for i = 3, #seeded.items do
    assert(seeded.items[i].visible == false,
        "a built-in appended to an existing bar must arrive hidden")
end
local order = BB.GetBuiltinOrder()
assert(#seeded.items == #order + 1, "every missing built-in must be appended exactly once")
assert(BB.InitFrameDefaults(2) and #settings.buttonBars[2].items == #order + 1,
    "InitFrameDefaults must be idempotent")

-- A genuinely fresh entry still gets the documented default: all built-ins on,
-- in BUILTIN_ORDER.
settings.buttonBars[3] = nil
local fresh = BB.InitFrameDefaults(3)
assert(#fresh.items == #order, "fresh entry seeds exactly the built-in set")
for i = 1, #order do
    assert(fresh.items[i].id == order[i], "fresh seed must follow BUILTIN_ORDER")
    assert(fresh.items[i].visible == true, "fresh seed must enable every built-in")
end

----------------------------------------------------------------------------
-- 6. A custom row carries the same on/off flag a built-in does -- the
--    settings list now shows that toggle on the collapsed row for BOTH sorts.
--    The fold stamps it (absent has always meant shown), and a row switched
--    off is skipped by the renderer without consuming a slot.
----------------------------------------------------------------------------
for i = 1, #entry.items do
    local item = entry.items[i]
    if BB.IsCustomItem(item) then
        assert(item.visible == true, "the fold must stamp visible on every custom row")
    end
end

local readycheck
for i = 1, #entry.items do
    if entry.items[i].slashCommand == "/readycheck" then readycheck = entry.items[i] end
end
assert(readycheck, "the custom /readycheck row must still be in the list")

readycheck.visible = false
BB.ReconcileAll()
assert(renderedLabels() == "QUI,Reload,/pull 10",
    "a custom row switched off must not render, got " .. renderedLabels())

-- Absent still means shown: a hand-edited SavedVariables row that never
-- passed through the fold must keep rendering.
readycheck.visible = nil
BB.ReconcileAll()
assert(renderedLabels() == "/readycheck,QUI,Reload,/pull 10",
    "a custom row with no visible flag must render, got " .. renderedLabels())

print("OK: chat_button_bar_item_order_test")
