-- tests/unit/chat_tab_ui_multiwindow_test.lua
-- Run: lua tests/unit/chat_tab_ui_multiwindow_test.lua
-- Covers multi-window behaviour introduced alongside the tab-bar review fixes:
--   1. EnsureAttached creates one bar per window; window 1 named, window 2 unnamed.
--   2. Fan-out activation does NOT call Display.SetActiveWindow (regression for
--      the rebuild-steals-active bug).
--   3. Public TabUI.ActivateFrameID(2, 1) DOES call SetActiveWindow(2).
--   4. Independent unread: entry matching w1-inactive / w2-active → unread only
--      increments in instance 1.
--   5. TabUI.OnWindowDeleted(1) compacts: old instance 2 becomes instance 1 with
--      windowID == 1 and keeps its unread state.
--   6. Phantom guard: TabUI.ActivateFrameID(7, 1) with 2 windows routes to
--      window 1 (no instances[7] created).

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
    f.SetParent = function(s, p)
        s._parent = p
        -- Update the container lookup used by the Display stub.
        if s._onSetParent then s._onSetParent(p) end
    end
    f.RegisterEvent = function(s, e) s.events = s.events or {}; s.events[e] = true end
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    f.CreateFontString = function()
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
    f.CreateTexture = function()
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
_G.ChatFontNormal = {}
function _G.GetChatWindowInfo() return "" end

-- Two containers for two windows.
local containers = { makeFrame("Frame"), makeFrame("Frame") }

-- Track SetActiveWindow calls.
local setActiveCalls = {}
local activeFilter

-- Store subscriber callback captured by EnsureAttached.
local storeCb

-- Custom tabs: two distinct sets per window, but backed by the same global
-- store array (TabManager.GetWindowTabs returns per-wid slices).
local tabsW1 = {
    { name = "Loot",  groups = { LOOT = true } },
    { name = "Trade", channels = { Trade = true } },
}
local tabsW2 = {
    { name = "All W2", groups = { SAY = true } },
}

local function makeFilter(td)
    return function(entry)
        if td.groups and td.groups[entry.k] then return true end
        if td.channels and td.channels[entry.ch] then return true end
        return false
    end
end

-- Build a 2-window DisplayLayer stub with GetWindowCount / GetContainer /
-- SetActiveWindow.
local displayWindowCount = 2
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
        DisplayLayer = {
            GetWindowCount = function() return displayWindowCount end,
            GetContainer = function(wid) return containers[wid] end,
            SetActiveWindow = function(wid)
                setActiveCalls[#setActiveCalls + 1] = wid
            end,
        },
        MessageStore = { OnAppend = function(fn) storeCb = fn end },
        TabManager = {
            SetActiveTab = function(wid, td)
                activeFilter = td and makeFilter(td) or nil
            end,
            GetActiveFilter = function() return activeFilter end,
            GetWindowTabs = function(wid)
                if wid == 1 then return tabsW1 end
                if wid == 2 then return tabsW2 end
                return {}
            end,
            GetWindowTab = function(wid, i)
                if wid == 1 then return tabsW1[i] end
                if wid == 2 then return tabsW2[i] end
            end,
            BuildTabFilter = makeFilter,
        },
    } },
}

assert(loadfile("modules/chat/tab_ui.lua"))("QUI", ns)
local TabUI = ns.QUI.Chat.TabUI
local instances = TabUI._instances

-- ── Test 1: EnsureAttached creates one bar per window; w1 named, w2 unnamed ──

TabUI.EnsureAttached()

-- Window 1: bar named QUI_CustomChatTabBar
local bar1, bar2
for _, f in ipairs(created) do
    if f.name == "QUI_CustomChatTabBar" then bar1 = f end
end
assert(bar1, "test1: window 1 bar named QUI_CustomChatTabBar")
assert(instances[1] and instances[1].bar == bar1,
    "test1: instance 1 holds window-1 bar")
assert(instances[1].bar:GetParent() == containers[1],
    "test1: window-1 bar parented to container[1]")

-- Window 2: bar exists but has no name (nil passed to CreateFrame).
assert(instances[2] and instances[2].bar,
    "test1: instance 2 has a bar")
assert(instances[2].bar.name == nil,
    "test1: window-2 bar has no global name, got " .. tostring(instances[2].bar.name))
assert(instances[2].bar:GetParent() == containers[2],
    "test1: window-2 bar parented to container[2]")
bar2 = instances[2].bar

-- Both bars correctly anchored (BOTTOMLEFT/BOTTOMRIGHT points).
assert(instances[1].bar.points[1][1] == "BOTTOMLEFT",
    "test1: window-1 bar anchored BOTTOMLEFT")
assert(instances[2].bar.points[1][1] == "BOTTOMLEFT",
    "test1: window-2 bar anchored BOTTOMLEFT")

-- ── Test 2: Fan-out activation does NOT call SetActiveWindow ──
-- After EnsureAttached (which triggers Rebuild + possibly stale-active
-- fallback ActivateFrameID calls internally), no SetActiveWindow should have
-- fired because those are all rebuild/fallback paths (userInitiated=false).

local callsAfterAttach = #setActiveCalls
assert(callsAfterAttach == 0,
    "test2: EnsureAttached must not call SetActiveWindow, got " .. callsAfterAttach .. " calls")

-- ── Test 3: Public ActivateFrameID(2, 1) DOES call SetActiveWindow(2) ──

local before3 = #setActiveCalls
local ok3 = TabUI.ActivateFrameID(2, 1)
assert(ok3 == true, "test3: ActivateFrameID(2,1) returns true")
assert(#setActiveCalls == before3 + 1,
    "test3: SetActiveWindow called once, got " .. (#setActiveCalls - before3))
assert(setActiveCalls[#setActiveCalls] == 2,
    "test3: SetActiveWindow called with windowID=2, got " .. tostring(setActiveCalls[#setActiveCalls]))

-- Also verify tab 1 of window 2 is now active in instance 2.
assert(instances[2].activeID == -1,
    "test3: instance 2 activeID == -1 (first tab), got " .. tostring(instances[2].activeID))

-- ── Test 4: Independent unread — entry matching w1-inactive tab only
--           increments instance 1 ──
-- Setup: make window-1's tab-1 (Loot, groups.LOOT) the inactive one by
-- activating tab-2 in window 1, while window-2's tab-1 (SAY) remains active.

TabUI.ActivateFrameID(1, 2)  -- window 1: make "Trade" (tab-2) active
setActiveCalls = {}           -- reset call log

-- Instance 1 active = -2 (Trade), inactive = -1 (Loot, matches LOOT).
-- Instance 2 active = -1 (All W2 / SAY), no other tabs.
-- Send a LOOT entry — should badge only instance 1's Loot tab.
assert(type(storeCb) == "function", "test4: store subscriber registered")
storeCb({ k = "LOOT" })

-- Window-1 Loot tab unread should be 1.
local lootBtn
for _, b in ipairs(instances[1].buttons) do
    if b.frameID == -1 then lootBtn = b end
end
assert(lootBtn, "test4: window-1 Loot button present")
assert(instances[1].unread[-1] == 1,
    "test4: w1 Loot unread=1, got " .. tostring(instances[1].unread[-1]))

-- Window-2 should have no unread (its only tab is active and doesn't match).
local w2Unread = 0
for _, v in pairs(instances[2].unread) do w2Unread = w2Unread + (v or 0) end
assert(w2Unread == 0,
    "test4: w2 has no unread, got " .. w2Unread)

-- ── Test 5: OnWindowDeleted(1) compacts; old w2 instance becomes w1 ──
-- Give instance 2 some unread to verify it survives compaction.
instances[2].unread[-1] = 3

-- In production, Display.GetWindowCount() already returns the post-deletion
-- count when OnWindowDeleted fires (Display removes the window first, then
-- notifies TabUI). Reflect that in the stub before calling.
displayWindowCount = 1

-- Provide only one container now (the old w2 container becomes w1's).
containers[1] = containers[2]
containers[2] = nil

TabUI.OnWindowDeleted(1)

-- After deletion with 2→1 windows, we should only have instance 1.
assert(instances[1] ~= nil, "test5: instance 1 exists after compaction")
assert(instances[2] == nil, "test5: instance 2 gone after compaction")
assert(instances[1].windowID == 1,
    "test5: compacted instance has windowID=1, got " .. tostring(instances[1].windowID))
-- The old w2 unread (3 on tab -1) should be preserved.
assert(instances[1].unread[-1] == 3,
    "test5: compacted instance retains unread, got " .. tostring(instances[1].unread[-1]))

-- ── Test 6: Phantom guard — ActivateFrameID(7, 1) routes to w1, no phantom inst ──
-- State: 1 window (displayWindowCount=1 from test 5). Requesting windowID=7
-- must clamp to 1; no instances[7] should be created.
local before6 = #setActiveCalls
local ok6 = TabUI.ActivateFrameID(7, 1)
assert(instances[7] == nil,
    "test6: no instance created for windowID=7")
assert(ok6 == true or ok6 == false,
    "test6: ActivateFrameID(7,1) returns a boolean")
-- If the activation succeeded, SetActiveWindow must have been called with 1.
if ok6 then
    assert(setActiveCalls[#setActiveCalls] == 1,
        "test6: SetActiveWindow called with 1 (clamped), got " .. tostring(setActiveCalls[#setActiveCalls]))
end

-- ── Tests 7-10: MoveTabToWindow ──
-- Reset to a clean 2-window state. Tests 5-6 collapsed to 1 window;
-- restore containers, displayWindowCount, and the tab arrays so
-- TabUI._MoveTabToWindow can be driven directly without UI side-effects.

-- Fresh tab arrays so tests have known identity references.
local mTabsW1 = {
    { name = "Loot",  groups = { LOOT = true } },
    { name = "Trade", channels = { Trade = true } },
}
local mTabsW2 = {
    { name = "All W2", groups = { SAY = true } },
}

-- Swap the stub's GetWindowTabs to use these fresh arrays.
local savedGetWindowTabs = ns.QUI.Chat.TabManager.GetWindowTabs
ns.QUI.Chat.TabManager.GetWindowTabs = function(wid)
    if wid == 1 then return mTabsW1 end
    if wid == 2 then return mTabsW2 end
    return {}
end

-- Restore 2-window display so EnsureAttached creates both instances.
displayWindowCount = 2
containers[1] = makeFrame("Frame")
containers[2] = makeFrame("Frame")

-- Silence Rebuild's RebuildInstance calls (bar frames already exist from
-- earlier; EnsureAttached will wire new bars for the fresh containers).
-- Reset instances so EnsureAttached re-attaches cleanly.
for k in pairs(instances) do instances[k] = nil end
TabUI.EnsureAttached()

local inst1 = instances[1]
local inst2 = instances[2]
assert(inst1, "move-setup: instance 1 exists")
assert(inst2, "move-setup: instance 2 exists")

-- In-game tab moves mutate saved tab config: they must bump the chat
-- settings provider revision so a cached options panel rebuilds.
local moveNotifies = 0
ns.QUI.Chat._internals.NotifyChatSettingsChanged = function()
    moveNotifies = moveNotifies + 1
end

-- ── Test 7: Move tab 2 of window 1 to window 2 ──
-- mTabsW1 has 2 tabs; moving tab 2 (Trade) appends it to mTabsW2.
local tradeRef = mTabsW1[2]
TabUI._MoveTabToWindow(inst1, 2, 2, false)
assert(moveNotifies == 1, "test7: tab move bumps the settings provider revision")

assert(#mTabsW1 == 1,
    "test7: mTabsW1 now has 1 tab, got " .. #mTabsW1)
assert(mTabsW1[1].name == "Loot",
    "test7: remaining tab is Loot, got " .. tostring(mTabsW1[1].name))
assert(#mTabsW2 == 2,
    "test7: mTabsW2 now has 2 tabs, got " .. #mTabsW2)
local moved7 = mTabsW2[2]
assert(moved7 == tradeRef,
    "test7: same table identity — moved tab is the original Trade ref")

-- ── Test 8: Single-tab window refuses the move ──
-- mTabsW1 now has only 1 tab; a move from it must be a no-op.
local lootRef = mTabsW1[1]
TabUI._MoveTabToWindow(inst1, 1, 2, false)
assert(moveNotifies == 1, "test8: refused move does NOT bump the provider revision")

assert(#mTabsW1 == 1,
    "test8: single-tab window unchanged — still 1 tab")
assert(mTabsW1[1] == lootRef,
    "test8: single-tab window unchanged — same tab identity")
assert(#mTabsW2 == 2,
    "test8: target window unchanged — still 2 tabs")

-- ── Test 9: replaceSeed=true onto a window with placeholder "Tab 1" replaces it ──
-- Set up a fresh target window with only the seed placeholder.
local seedTabs = { { name = "Tab 1", groups = {}, channels = {}, invert = false } }
ns.QUI.Chat.TabManager.GetWindowTabs = function(wid)
    if wid == 1 then return mTabsW1 end  -- 1 tab (Loot)
    if wid == 3 then return seedTabs end
    return {}
end
-- Give window 1 a second tab so the move is allowed.
local extraTab = { name = "Extra", groups = { SAY = true } }
mTabsW1[2] = extraTab

local extraRef = mTabsW1[2]
-- inst1.windowID == 1; target windowID == 3 (seed window).
-- We need a minimal inst3 for the call (MoveTabToWindow uses inst.windowID).
local inst3 = { windowID = 3 }
-- Make the call directly — MoveTabToWindow uses inst.windowID, not inst keys.
TabUI._MoveTabToWindow(inst1, 2, 3, true)

assert(#mTabsW1 == 1,
    "test9: extra tab removed from window 1, got " .. #mTabsW1)
assert(#seedTabs == 1,
    "test9: seed window length stays 1 (replace, not append), got " .. #seedTabs)
assert(seedTabs[1] == extraRef,
    "test9: seed placeholder replaced by the moved tab (same identity)")

-- ── Test 10: replaceSeed=true onto a window whose single tab is NOT "Tab 1" appends ──
local namedTabs = { { name = "General", groups = { SAY = true } } }
ns.QUI.Chat.TabManager.GetWindowTabs = function(wid)
    if wid == 1 then return mTabsW1 end  -- 1 tab again after test 9
    if wid == 4 then return namedTabs end
    return {}
end
-- Give window 1 another tab so the move is allowed.
local tab10 = { name = "Combat", groups = { COMBAT = true } }
mTabsW1[2] = tab10
local tab10Ref = mTabsW1[2]

TabUI._MoveTabToWindow(inst1, 2, 4, true)

assert(#mTabsW1 == 1,
    "test10: tab removed from window 1, got " .. #mTabsW1)
assert(#namedTabs == 2,
    "test10: named single-tab window appended (length 2), got " .. #namedTabs)
assert(namedTabs[2] == tab10Ref,
    "test10: appended tab has correct identity")

-- Restore GetWindowTabs for any subsequent use.
ns.QUI.Chat.TabManager.GetWindowTabs = savedGetWindowTabs

print("OK: chat_tab_ui_multiwindow_test")
