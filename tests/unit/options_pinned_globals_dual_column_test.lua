-- tests/unit/options_pinned_globals_dual_column_test.lua
-- Structure regression: the Pinned Globals list renders pinned items two-up
-- per 44px row with a card-group-style center divider; stale styling is per
-- cell; odd counts leave the last row with a solo left cell.
-- Run: lua tests/unit/options_pinned_globals_dual_column_test.lua

local unpack = table.unpack or unpack

-- Headless WoW-ish stubs --------------------------------------------------
local function NewFontString()
    local fs = {}
    function fs:SetPoint() end
    function fs:SetText(text) self._text = text end
    function fs:SetTextColor() end
    function fs:SetJustifyH() end
    function fs:SetJustifyV() end
    function fs:SetFont() end
    function fs:GetFont() return "font", 11, "" end
    function fs:SetWordWrap() end
    function fs:SetShown() end
    function fs:Hide() end
    function fs:Show() end
    return fs
end

local function NewTexture()
    local t = {}
    function t:SetPoint() end
    function t:SetAllPoints() end
    function t:SetColorTexture() end
    function t:SetVertexColor() end
    function t:SetTexture() end
    function t:SetWidth() end
    function t:SetHeight() end
    function t:Hide() end
    function t:Show() end
    function t:ClearAllPoints() end
    function t:SetParent() end
    return t
end

local function NewFrame(parent)
    local f = { _children = {}, _parent = parent }
    if parent and parent._children then
        parent._children[#parent._children + 1] = f
    end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetSize(w, h) self._width = w; self._height = h end
    function f:SetHeight(h) self._height = h end
    function f:GetHeight() return self._height or 0 end
    function f:SetWidth(w) self._width = w end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:SetShown(shown) self._shown = shown end
    function f:SetScript(name, fn) self["_" .. name] = fn end
    function f:SetParent(p) self._parent = p end
    function f:GetParent() return self._parent end
    function f:GetChildren() return unpack(self._children) end
    function f:GetRegions() return end
    function f:EnableMouse() end
    function f:SetAutoFocus() end
    function f:SetTextInsets() end
    function f:SetText() end
    function f:GetText() return "" end
    function f:SetFont() end
    function f:GetFont() return "font", 11, "" end
    function f:SetTextColor() end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetBackdropBorderColor() end
    function f:CreateFontString() return NewFontString() end
    function f:CreateTexture() return NewTexture() end
    return f
end

_G.CreateFrame = function(_, _, parent) return NewFrame(parent) end
_G.C_Timer = { After = function() end }
_G.UIParent = NewFrame()
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local buttons = {}
local gui = {
    Colors = {
        text = { 1, 1, 1, 1 },
        textMuted = { 0.6, 0.6, 0.6, 1 },
        accent = { 0.2, 0.8, 0.6, 1 },
        bgContent = { 0.08, 0.09, 0.11, 1 },
        border = { 1, 1, 1, 0.2 },
    },
}
function gui:CreateButton(_parent, text)
    local b = NewFrame(_parent)
    b._buttonText = text
    buttons[#buttons + 1] = b
    return b
end
function gui:CreateFormDropdown()
    local d = NewFrame()
    function d:SetValue() end
    return d
end
function gui:ShowConfirmation() end

_G.QUI = { GUI = gui }

-- Pins store stub: 3 items, newest-first under the default "recent" sort,
-- with the OLDEST one stale so it lands as the solo cell on row 2.
local items = {
    { path = "a", label = "Alpha Setting", value = true,  pinnedAt = 30, tabName = "Unit Frames", subTabName = "Player" },
    { path = "b", label = "Beta Setting",  value = 1.25,  pinnedAt = 20, tabName = "Minimap" },
    { path = "c", label = "Gamma Setting", value = "off", pinnedAt = 10, tabName = "QoL", disabled = true },
}

local pins = {}
function pins:List()
    local out = {}
    for i, item in ipairs(items) do out[i] = item end
    return out
end
function pins:Subscribe() return "token" end
function pins:FormatValue(value) return tostring(value) end
function pins:NavigateToPinned() end
function pins:Unpin() end
function pins:DropPath() end
function pins:UnpinAll() end

local ns = {
    Settings = { Pins = pins },
    Helpers = { AssetPath = "assets/", DeepCopy = function(v) return v end },
}

assert(loadfile("core/settings/pins_ui.lua"))("QUI", ns)
local PinUI = ns.QUI_PinnedSettingsOptions
assert(PinUI and type(PinUI.BuildPinnedGlobalsContent) == "function",
    "pins_ui must expose BuildPinnedGlobalsContent")

local content = NewFrame()
PinUI.BuildPinnedGlobalsContent(content, content)

local state = content._quiPinnedGlobalsState
assert(state and state.rowsHost, "build must store list state on the host")

-- 3 items -> 2 rows (two-up). ----------------------------------------------
local rows = state.rowsHost._children
assert(#rows == 2, "expected 2 paired rows for 3 items, got " .. #rows)

-- Row 1: two pin cells + center divider.
local row1Cells = {}
for _, child in ipairs(rows[1]._children) do
    if child._quiPinCell then row1Cells[#row1Cells + 1] = child end
end
assert(#row1Cells == 2, "row 1 must hold two pin cells, got " .. #row1Cells)
assert(rows[1]._centerDivider, "paired row must draw a center divider")

-- Row 2: solo left cell, no divider.
local row2Cells = {}
for _, child in ipairs(rows[2]._children) do
    if child._quiPinCell then row2Cells[#row2Cells + 1] = child end
end
assert(#row2Cells == 1, "row 2 must hold one solo cell, got " .. #row2Cells)
assert(rows[2]._centerDivider == nil, "solo row must not draw a divider")

-- Stale styling is per cell: only the disabled item's cell is stale.
assert(row2Cells[1]._quiPinStale, "disabled pin's cell must be marked stale")
assert(not row1Cells[1]._quiPinStale and not row1Cells[2]._quiPinStale,
    "fresh pins must not be marked stale")

-- Stale banner shows when any pin is disabled.
assert(state.staleBanner._shown == true, "stale banner must show for a stale pin")

-- Per-cell buttons: 3x Jump; Unpin for fresh pins, Remove for the stale one.
local counts = {}
for _, b in ipairs(buttons) do
    counts[b._buttonText] = (counts[b._buttonText] or 0) + 1
end
assert(counts["Jump"] == 3, "expected 3 Jump buttons, got " .. tostring(counts["Jump"]))
assert(counts["Unpin"] == 2, "expected 2 Unpin buttons, got " .. tostring(counts["Unpin"]))
assert(counts["Remove"] == 1, "expected 1 Remove button, got " .. tostring(counts["Remove"]))

-- Row geometry: 2 rows x 46px step; content floor formula unchanged.
assert(state.rowsHost._height == 92,
    "rowsHost must be 92 tall for two rows, got " .. tostring(state.rowsHost._height))
assert(content._height == 224,
    "content must be 224 tall (132 + 92), got " .. tostring(content._height))

print("OK options_pinned_globals_dual_column_test")
