-- tests/unit/chat_tab_ui_test.lua
-- Run: lua tests/unit/chat_tab_ui_test.lua
-- Verifies: lazy attach, buttons built only from saved QUI tabs, default
-- activation by QUI tab index, idempotent attach, active styling flag, unread
-- badge counting and clearing, stale-active fallback, and rebuild re-derive.
-- Ported to per-window instance model: TabUI._instances[1].buttons replaces
-- the old TabUI._buttons singleton export; ActivateFrameID takes (windowID, tabIndex).

local function makeFrame(ftype)
    local f = { ftype = ftype, shown = true, children = {}, points = {} }
    local function noop() end
    f.SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end
    f.ClearAllPoints = function(s) s.points = {} end
    f.SetSize = noop; f.SetHeight = noop
    f.SetWidth = function(s, w) s.width = w end
    f.Show = function(s) s.shown = true end
    f.Hide = function(s) s.shown = false end
    f.IsShown = function(s) return s.shown end
    f.EnableMouse = noop
    f.RegisterForDrag = noop
    f.RegisterForClicks = noop
    f.SetAlpha = noop
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 5 end
    f.GetParent = function(s) return s._parent end
    f.SetParent = function(s, p) s._parent = p end
    f.RegisterEvent = function(s, e) s.events = s.events or {}; s.events[e] = true end
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    f.CreateFontString = function(s)
        local fs = { points = {},
            SetPoint = function(o, ...) o.points[#o.points + 1] = { ... } end,
            ClearAllPoints = function(o) o.points = {} end,
            SetText = function(o, t) o.text = t end,
            GetStringWidth = function() return 30 end,
            GetFont = function() return "Fonts\\FRIZQT__.TTF", 11, "" end,
            SetFont = function(o, path, size, outline) o.font = { path, size, outline } end,
            SetFontObject = function(o, object) o.fontObject = object end,
            SetTextColor = function(o, r, g, b) o.color = { r, g, b } end,
            SetJustifyH = function(o, justify) o.justifyH = justify end }
        return fs
    end
    f.CreateTexture = function(s)
        local tx = { SetPoint = noop,
            SetAllPoints = function(o, target) o.allPoints = target or true end,
            SetTexture = function(o, texture) o.texture = texture end,
            SetColorTexture = function(o, r, g, b, a) o.color = { r, g, b, a } end,
            SetHeight = function(o, h) o.height = h end,
            SetWidth = function(o, w) o.width = w end,
            SetShown = function(o, v) o.visible = v end, Hide = function(o) o.visible = false end }
        return tx
    end
    return f
end

local created = {}
function _G.CreateFrame(ftype, name, parent)
    local f = makeFrame(ftype)
    f.name = name
    f._parent = parent
    created[#created + 1] = f
    return f
end
_G.NUM_CHAT_WINDOWS = 10
local windows = {
    [1] = { "General", 14, 1, 1, 1, 1, true, false, true },
    [2] = { "Log", 14, 1, 1, 1, 1, false, false, false },  -- not shown, not docked
    [3] = { "Trade", 14, 1, 1, 1, 1, true, false, true },
}
function _G.GetChatWindowInfo(i)
    local w = windows[i]
    if w then return unpack(w) end
    return ""
end
_G.ChatFontNormal = {}

local container = makeFrame("Frame")
local setActiveCalls = {}
local activeFilter
local storeCb  -- captured when EnsureAttached calls Store.OnAppend

local stubCustomTabs = {
    { name = "Loot Watch", groups = { LOOT = true } },
    { name = "Trade Only", channels = { Trade = true } },
}

local function makeFilter(td)
    return function(entry)
        if td.groups and td.groups[entry.k] then return true end
        if td.channels and td.channels[entry.ch] then return true end
        return false
    end
end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetGeneralFont = function() return "Interface\\AddOns\\QUI\\media\\custom-font.ttf" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
    },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return { enabled = true } end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetAccent = function() return { 0.2, 0.8, 0.6, 1 } end,
            GetThemeColors = function() return {
                bg = { 0.05, 0.06, 0.07, 1 },
                bgDark = { 0.01, 0.02, 0.03, 1 },
                border = { 0.3, 0.3, 0.3, 0.4 },
                text = { 1, 1, 1, 1 },
                textDim = { 0.7, 0.7, 0.7, 1 },
            } end,
        },
        DisplayLayer = { GetContainer = function() return container end },
        MessageStore = { OnAppend = function(fn) storeCb = fn end },
        TabManager = {
            SetActiveTab = function(wid, td)
                activeFilter = td and makeFilter(td) or nil
                setActiveCalls[#setActiveCalls + 1] = { td = td }
            end,
            GetActiveFilter = function(wid) return activeFilter end,
            GetWindowTabs = function(wid) return stubCustomTabs end,
            GetWindowTab = function(wid, i) return stubCustomTabs[i] end,
            BuildTabFilter = makeFilter,
        },
    } },
}

assert(loadfile("modules/chat/tab_ui.lua"))("QUI", ns)
local TabUI = ns.QUI.Chat.TabUI

TabUI.EnsureAttached()
local bar
for _, f in ipairs(created) do
    if f.name == "QUI_CustomChatTabBar" then bar = f end
end
assert(bar, "tab bar created")
assert(bar.points[1] and bar.points[1][1] == "BOTTOMLEFT" and bar.points[1][2] == container
    and bar.points[1][3] == "TOPLEFT" and bar.points[1][5] >= 0,
    "tab bar must anchor outside above the chat frame, got "
        .. tostring(bar.points[1] and bar.points[1][1]) .. "/"
        .. tostring(bar.points[1] and bar.points[1][3]) .. "/"
        .. tostring(bar.points[1] and bar.points[1][5]))

-- Per-window instance accessor helper
local function inst1() return TabUI._instances[1] end
local function buttons1() return TabUI._instances[1].buttons end

-- Buttons: only saved QUI tabs. Stock windows are seed-only and never mirrored
-- into the runtime tab bar.
local labels = {}
for _, b in ipairs(buttons1()) do
    if b._active ~= nil or true then labels[#labels + 1] = b.label and b.label.text end
end
assert(labels[1] == "Loot Watch" and labels[2] == "Trade Only",
    "buttons should be saved QUI tabs only, got " .. table.concat(labels, ","))
assert(#buttons1() == 2, "runtime tab bar must not include All or stock-window mirror tabs")
assert(buttons1()[2].points[1][4] == buttons1()[1].width,
    "tab buttons should touch without spacing, got second x " .. tostring(buttons1()[2].points[1][4])
        .. " after first width " .. tostring(buttons1()[1].width))
assert(buttons1()[2].label.font and buttons1()[2].label.font[1] == "Interface\\AddOns\\QUI\\media\\custom-font.ttf",
    "tab title should use QUI configured font, got " .. tostring(buttons1()[2].label.font and buttons1()[2].label.font[1]))
assert(buttons1()[2].label.font[3] == "OUTLINE",
    "tab title should use QUI configured outline, got " .. tostring(buttons1()[2].label.font[3]))
assert(buttons1()[2].label.fontObject == nil, "tab title must not stay on ChatFontNormal")
assert(buttons1()[2].badge.font and buttons1()[2].badge.font[1] == "Interface\\AddOns\\QUI\\media\\custom-font.ttf",
    "tab badge should use QUI configured font")
assert(buttons1()[2].width >= 72,
    "tab width should reserve space for an inline unread badge, got " .. tostring(buttons1()[2].width))
assert(buttons1()[2].label.points[1][1] == "LEFT"
    and buttons1()[2].label.points[2][1] == "RIGHT"
    and buttons1()[2].label.points[2][2] == buttons1()[2]
    and buttons1()[2].label.points[2][4] < 0,
    "tab label should be constrained before the reserved badge space")
assert(buttons1()[2].badge.points[1][1] == "RIGHT"
    and buttons1()[2].badge.points[1][2] == buttons1()[2]
    and buttons1()[2].badge.points[1][3] == "RIGHT"
    and buttons1()[2].badge.points[1][4] < 0,
    "tab badge should be anchored inside the tab button")
assert(buttons1()[2].badge.justifyH == "RIGHT", "tab badge should right-align inside its reserved space")
assert(buttons1()[1]._quiTabChrome and buttons1()[1]._quiTabChrome.bg,
    "active tab should have a painted background")
assert(buttons1()[1]._quiTabChrome.edges and #buttons1()[1]._quiTabChrome.edges == 4,
    "active tab should have four outline edges")
assert(buttons1()[1]._quiTabChrome.bg.color and buttons1()[1]._quiTabChrome.bg.color[4] > 0,
    "active tab background should be visible")
assert(buttons1()[2]._quiTabChrome and buttons1()[2]._quiTabChrome.bg.color,
    "inactive tab should also have a painted background")
assert(buttons1()[1]._quiTabChrome.bg.color[4] > buttons1()[2]._quiTabChrome.bg.color[4],
    "active tab background should be stronger than inactive")
assert(buttons1()[1]._active == true, "initial active tab is the first QUI tab")
assert(setActiveCalls[#setActiveCalls].td == stubCustomTabs[1],
    "initial rebuild activates the first QUI tab")
assert(type(TabUI.ActivateFrameID) == "function", "TabUI exposes default-tab activation")
assert(TabUI.ActivateFrameID(1, 2) == true, "default tab index activates the second QUI tab")
assert(buttons1()[2]._active == true, "second QUI tab is active after default activation")
assert(setActiveCalls[#setActiveCalls].td == stubCustomTabs[2], "default activation applies QUI tab data")
assert(buttons1()[2]._quiTabChrome.bg.color[4] > buttons1()[1]._quiTabChrome.bg.color[4],
    "active background should become stronger after activation")
assert(buttons1()[2]._quiTabChrome.edges[1].color[1] == 0.2
    and buttons1()[2]._quiTabChrome.edges[1].color[2] == 0.8,
    "active tab outline should use accent color")
local customBtn
for _, b in ipairs(buttons1()) do if b.frameID == -1 then customBtn = b end end
assert(customBtn, "custom tab carries negative frameID")

-- Custom click routes its tabData
customBtn._OnClick(customBtn)
assert(setActiveCalls[#setActiveCalls].td == stubCustomTabs[1], "custom click passes its tabData")

-- Idempotent attach
local n = #created
TabUI.EnsureAttached()
assert(#created == n, "no duplicate frames on re-attach")

-- Stock chat-window changes do not rebuild or append mirror tabs.
windows[4] = { "New", 14, 1, 1, 1, 1, true, false, true }
local ev
for _, f in ipairs(created) do
    if f.events and f.events.UPDATE_CHAT_WINDOWS then ev = f end
end
assert(ev == nil, "tab UI must not subscribe to stock chat-window updates")
TabUI.Rebuild()
assert(#buttons1() == 2, "stock-window changes must not add runtime tabs")

-- Badges: inactive matching QUI tabs accumulate.
assert(type(storeCb) == "function", "store subscriber registered")
customBtn._OnClick(customBtn) -- Loot active
local tradeBtn
for _, b in ipairs(buttons1()) do if b.frameID == -2 then tradeBtn = b end end
storeCb({ k = "CHANNEL", ch = "Trade" })
storeCb({ k = "CHANNEL", ch = "Trade" })
storeCb({ k = "LOOT" })
assert(tradeBtn.badge.text == "2", "inactive QUI tab badge counts matching messages, got " .. tostring(tradeBtn.badge.text))
assert(customBtn.badge.text == "" or customBtn.badge.text == nil, "active QUI tab does not badge")

-- Secrets never badge
storeCb({ s = true })
assert(tradeBtn.badge.text == "2", "secret did not badge")

-- Activating clears; active never accumulates
tradeBtn._OnClick(tradeBtn)
assert(tradeBtn.badge.text == "", "badge cleared on activation")
storeCb({ k = "CHANNEL", ch = "Trade" })
assert(tradeBtn.badge.text == "", "active tab never badges")

-- Stale active custom tab: delete it, rebuild -> falls back to first remaining QUI tab.
tradeBtn._OnClick(tradeBtn)
assert(setActiveCalls[#setActiveCalls].td == stubCustomTabs[2], "second custom active")
table.remove(stubCustomTabs, 2)
TabUI.Rebuild()
assert(setActiveCalls[#setActiveCalls].td == stubCustomTabs[1],
    "deleted active custom tab falls back to first remaining QUI tab")
assert(#buttons1() == 1, "deleted custom button gone after rebuild")

-- Gated re-derive: editing the ACTIVE custom tab's definition re-applies it
-- on Rebuild exactly once; cosmetic Rebuilds don't re-derive
stubCustomTabs[1] = { name = "Loot Watch", groups = { LOOT = true } }
TabUI.Rebuild()
for _, b in ipairs(buttons1()) do if b.frameID == -1 then customBtn = b end end
customBtn._OnClick(customBtn)
local derivesAfterClick = #setActiveCalls
TabUI.Rebuild()  -- cosmetic: no definition change
assert(#setActiveCalls == derivesAfterClick, "cosmetic rebuild does not re-derive")
activeFilter = nil
TabUI.Rebuild()
assert(#setActiveCalls == derivesAfterClick + 1, "missing active filter re-derives active tab")
assert(setActiveCalls[#setActiveCalls].td == stubCustomTabs[1], "missing-filter recovery uses active tabData")
local derivesAfterRecovery = #setActiveCalls
TabUI.Rebuild()
assert(#setActiveCalls == derivesAfterRecovery, "recovered active filter suppresses cosmetic re-derive")
stubCustomTabs[1].groups.CURRENCY = true  -- edit the definition
TabUI.Rebuild()
assert(#setActiveCalls == derivesAfterRecovery + 1, "definition change re-derives once")
assert(setActiveCalls[#setActiveCalls].td == stubCustomTabs[1], "re-derived with the edited tabData")

-- Tab bar renders custom tabs in array order; reorder follows
stubCustomTabs[2] = { name = "Second", groups = { SAY = true } }
TabUI.Rebuild()
local names = {}
for _, b in ipairs(buttons1()) do names[#names + 1] = b.label and b.label.text end
assert(names[#names - 1] == "Loot Watch" and names[#names] == "Second",
    "custom tabs in array order, got " .. table.concat(names, ","))
stubCustomTabs[1], stubCustomTabs[2] = stubCustomTabs[2], stubCustomTabs[1]
TabUI.Rebuild()
names = {}
for _, b in ipairs(buttons1()) do names[#names + 1] = b.label and b.label.text end
assert(names[#names - 1] == "Second" and names[#names] == "Loot Watch",
    "reorder reflected after rebuild, got " .. table.concat(names, ","))

print("OK: chat_tab_ui_test")
