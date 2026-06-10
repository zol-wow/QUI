-- tests/unit/chat_tab_drag_reorder_test.lua
-- Run: lua tests/unit/chat_tab_drag_reorder_test.lua
-- Verifies: ComputeDropIndex pure math, ReorderDisplayTab stored-array
-- mutation, unread badge identity-remap, active-tab follow, OnDragStart/Stop
-- handlers end-to-end (saved AND conversation tabs in one display-order
-- space), single-tab guard.
-- Ported to per-window instance model: TU._instances[1].buttons replaces
-- the old TU._buttons singleton; TU._instances[1].dragIndicator replaces
-- TU._dragIndicator; TabManager stubs use window API signatures.

local function makeFrame(ftype)
    local f = { ftype = ftype, shown = true, children = {} }
    local function noop() end
    f.SetPoint = noop; f.ClearAllPoints = noop; f.SetSize = noop; f.SetHeight = noop
    f.SetWidth = function(s, w) s.width = w end
    f.Show = function(s) s.shown = true end
    f.Hide = function(s) s.shown = false end
    f.IsShown = function(s) return s.shown end
    f.EnableMouse = noop
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 5 end
    f.GetParent = function(s) return s._parent end
    f.SetParent = function(s, p) s._parent = p end
    f.RegisterEvent = function(s, e) s.events = s.events or {}; s.events[e] = true end
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    f.SetAlpha = function(s, a) s._alpha = a end
    f.GetAlpha = function(s) return s._alpha or 1 end
    f.RegisterForDrag = noop
    f.RegisterForClicks = noop
    f.GetLeft = function(s) return s._left or 0 end
    f.GetWidth = function(s) return s.width or 50 end
    f.GetEffectiveScale = function() return 1 end
    f.CreateFontString = function(s)
        local fs = { SetPoint = noop, SetText = function(o, t) o.text = t end,
            GetStringWidth = function() return 30 end, SetFontObject = noop,
            SetTextColor = function(o, r, g, b) o.color = { r, g, b } end }
        return fs
    end
    f.CreateTexture = function(s)
        local tx = {
            points = {},
            SetPoint = function(o, ...) o.points[#o.points + 1] = { ... } end,
            ClearAllPoints = function(o) o.points = {} end,
            SetTexture = function(o, texture) o.texture = texture end,
            SetColorTexture = function(o, r, g, b, a) o.color = { r, g, b, a } end,
            SetHeight = function(o, h) o.height = h end,
            SetWidth = function(o, w) o.width = w end,
            SetShown = function(o, v) o.visible = v; o.shown = v end,
            Show = function(o) o.shown = true; o.visible = true end,
            Hide = function(o) o.shown = false; o.visible = false end,
        }
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
_G.NUM_CHAT_WINDOWS = 3
local windows = {
    [1] = { "General", 14, 1, 1, 1, 1, true, false, true },
    [2] = { "Trade",   14, 1, 1, 1, 1, true, false, true },
}
function _G.GetChatWindowInfo(i)
    local w = windows[i]
    if w then return unpack(w) end
    return ""
end
_G.ChatFontNormal = {}

local container = makeFrame("Frame")
local setActiveCalls = {}
local storeCb

-- Three custom tabs for reorder tests
local tabA = { name = "Alpha", groups = { SAY = true } }
local tabB = { name = "Beta",  groups = { YELL = true } }
local tabC = { name = "Gamma", groups = { LOOT = true } }
local stubCustomTabs = { tabA, tabB, tabC }

-- Per-tab BuildTabFilter: each tab matches messages whose k equals the tab name.
-- This makes badge counts distinguishable: Alpha-keyed msgs only badge the
-- Alpha tab; Beta-keyed msgs only badge the Beta tab.
local function makePerTabFilter(td)
    -- Custom tab: match entries whose k equals the tab's name.
    return function(entry) return entry.k == (td and td.name) end
end

-- Conversation (whisper) tabs share the display-order space with saved tabs.
-- The mixed-order engine is the REAL tab_manager (its semantics are covered
-- in depth by chat_tab_display_order_test.lua); it is loaded into its own ns
-- and drives the same stubCustomTabs array, so the stubbed TabManager below
-- delegates GetDisplayEntries/MoveDisplayEntry to it.
local stubConvs = {}
_G.ChatTypeGroupInverted = _G.ChatTypeGroupInverted or {}
function _G.GetChatWindowMessages() end
function _G.GetChatWindowChannels() end
local tmSettings = { enabled = true, customDisplay = { combatLogTab = false,
    windows = { { tabs = stubCustomTabs } } } }
local nsTM = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return tmSettings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}
nsTM.QUI.Chat.ConversationManager = {
    EachForWindow = function(windowID, fn)
        for i = 1, #stubConvs do
            if stubConvs[i].windowID == windowID then fn(stubConvs[i]) end
        end
    end,
}
assert(loadfile("QUI_Chat/chat/tab_manager.lua"))("QUI", nsTM)
local realTM = nsTM.QUI.Chat.TabManager

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return { enabled = true } end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetAccent = function() return { 0.2, 0.8, 0.6, 1 } end,
            GetThemeColors = function() return { text = { 1, 1, 1, 1 }, textDim = { 0.7, 0.7, 0.7, 1 } } end,
        },
        DisplayLayer = { GetContainer = function() return container end },
        MessageStore = { OnAppend = function(fn) storeCb = fn end },
        TabManager = {
            SetActiveTab = function(wid, td) setActiveCalls[#setActiveCalls + 1] = { td = td } end,
            GetWindowTabs = function(wid) return stubCustomTabs end,
            GetWindowTab = function(wid, i) return stubCustomTabs[i] end,
            BuildTabFilter = makePerTabFilter,
            BuildConversationFilter = function(key)
                return function(entry) return entry.cv == key end
            end,
            GetDisplayEntries = function(wid) return realTM.GetDisplayEntries(wid) end,
            MoveDisplayEntry = function(wid, from, to) return realTM.MoveDisplayEntry(wid, from, to) end,
        },
    } },
}

assert(loadfile("QUI_Chat/chat/tab_ui.lua"))("QUI", ns)
local TU = ns.QUI.Chat.TabUI

-- Per-window instance accessor helpers (window 1)
local function inst1() return TU._instances[1] end
local function buttons1() return TU._instances[1].buttons end

-- ─── (a) Pure drop-math ────────────────────────────────────────────────────

local pos = { { mid = 110 }, { mid = 160 }, { mid = 220 } }
assert(TU._ComputeDropIndex(pos, 90)  == 1, "(a) before first mid -> slot 1")
assert(TU._ComputeDropIndex(pos, 140) == 2, "(a) between 1-2 mids -> slot 2")
assert(TU._ComputeDropIndex(pos, 195) == 3, "(a) between 2-3 mids -> slot 3")
assert(TU._ComputeDropIndex(pos, 500) == 4, "(a) past last mid -> slot n+1")

-- ─── (b) ReorderCustomTab mutates the LIVE stored array ───────────────────

-- stubCustomTabs is the exact table returned by GetWindowTabs — mutation persists.
assert(TU._ReorderDisplayTab(1, 3) == true, "(b) move A(1) -> slot 3 returns true")
assert(stubCustomTabs[1] == tabB, "(b) slot 1 is now B, got " .. tostring(stubCustomTabs[1] and stubCustomTabs[1].name))
assert(stubCustomTabs[2] == tabC, "(b) slot 2 is now C, got " .. tostring(stubCustomTabs[2] and stubCustomTabs[2].name))
assert(stubCustomTabs[3] == tabA, "(b) slot 3 is now A, got " .. tostring(stubCustomTabs[3] and stubCustomTabs[3].name))

-- ─── Restore to A,B,C for subsequent tests ────────────────────────────────
stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC

-- ─── (c) Unread badges follow their identity after reorder ────────────────
-- Per-tab filter: 5 "Alpha" msgs -> badge 5 on tabA; 2 "Beta" msgs -> badge 2 on tabB.
-- After moving Alpha from slot 1 to slot 3 the badge "5" must ride to the -3
-- button and "2" must land on the -1 button. Deleting the vals-snapshot/restore
-- block in ReorderCustomTab loses the identity remap, so these asserts will fail
-- against that mutation.

TU.EnsureAttached()

local function feedMsg(k)
    if storeCb then storeCb({ k = k }) end
end

local function getCustomBtnAt(idx)
    for _, b in ipairs(buttons1()) do
        if b.frameID == -idx then return b end
    end
    return nil
end

local function getBar()
    for _, f in ipairs(created) do
        if f.name == "QUI_CustomChatTabBar" then return f end
    end
    return nil
end

-- Activate Gamma so Alpha and Beta are inactive and accumulate badges.
local bC0 = getCustomBtnAt(3)
assert(bC0, "(c) tabC button exists at -3")
bC0._OnClick(bC0)

-- Feed 5 messages matching Alpha's filter and 2 matching Beta's filter.
for _ = 1, 5 do feedMsg("Alpha") end
for _ = 1, 2 do feedMsg("Beta")  end

-- tabA is at slot 1 (-1), tabB at slot 2 (-2), tabC at slot 3 (-3).
local bA = getCustomBtnAt(1)
local bB = getCustomBtnAt(2)
assert(bA and bA.badge.text == "5",
    "(c) Alpha starts with badge 5, got " .. tostring(bA and bA.badge.text))
assert(bB and bB.badge.text == "2",
    "(c) Beta starts with badge 2, got " .. tostring(bB and bB.badge.text))

-- Move Alpha (slot 1) -> slot 3: array becomes [Beta, Gamma, Alpha].
-- Expected remap: unread[-3]=5 (Alpha's 5 follows it), unread[-1]=2 (Beta's 2 follows it).
TU._ReorderDisplayTab(1, 3)
TU.Rebuild()

-- After Rebuild: frameID -3 = Alpha (slot 3), frameID -1 = Beta (slot 1).
local newbA = getCustomBtnAt(3)  -- Alpha is now at slot 3 -> frameID -3
local newbB = getCustomBtnAt(1)  -- Beta is now at slot 1 -> frameID -1
assert(newbA, "(c) Alpha moved to slot 3")
assert(newbB, "(c) Beta moved to slot 1")
assert(newbA.badge.text == "5",
    "(c) Alpha's badge 5 followed it to -3, got " .. tostring(newbA.badge.text))
assert(newbB.badge.text == "2",
    "(c) Beta's badge 2 followed it to -1, got " .. tostring(newbB.badge.text))

-- Restore stubCustomTabs to [A,B,C] for next tests.
stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC
TU.Rebuild()

-- ─── (d) Active custom tab follows after reorder ──────────────────────────

-- Activate tab A (slot 1 -> frameID -1).
local bA2 = getCustomBtnAt(1)
assert(bA2, "(d) tabA button exists at -1")
bA2._OnClick(bA2)
local setActiveCountBefore = #setActiveCalls

-- Move A from slot 1 to slot 3; activeID should update to -3.
TU._ReorderDisplayTab(1, 3)
TU.Rebuild()
-- stubCustomTabs is now [B,C,A]; A is at slot 3.

-- The button for A is now at frameID -3 and should be styled active.
local movedA = getCustomBtnAt(3)
assert(movedA, "(d) A moved to slot 3")
assert(movedA._active == true, "(d) moved tab A is still styled active, got " .. tostring(movedA._active))

-- SetActiveTab should NOT have been called again (no definition change).
assert(#setActiveCalls == setActiveCountBefore,
    "(d) no extra SetActiveTab calls after reorder, expected " .. setActiveCountBefore ..
    " got " .. #setActiveCalls)

-- Restore.
stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC
TU.Rebuild()
-- Activate Gamma to reset active state.
local bCReset = getCustomBtnAt(3)
assert(bCReset, "(d) tabC button exists for active reset")
bCReset._OnClick(bCReset)

-- ─── (e) Handlers end-to-end ──────────────────────────────────────────────

-- Helper: assign sequential _left values to all buttons in the current bar.
local function assignGeometry()
    local xOff = 0
    for _, b in ipairs(buttons1()) do
        b._left = xOff
        xOff = xOff + (b.width or 50) + 6
    end
end

-- Helper: collect the midpoints of custom buttons in bar order.
local function collectCustomMids()
    local mids = {}
    for _, b in ipairs(buttons1()) do
        if b.frameID and b.frameID < 0 then
            mids[#mids + 1] = (b._left or 0) + (b.width or 50) / 2
        end
    end
    return mids
end

-- (e1) OnDragStart on custom dims button to 0.5.
stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC
TU.Rebuild()
local customBtnE = getCustomBtnAt(1)
assert(customBtnE, "(e1) custom button found for drag test")
assert(customBtnE._OnDragStart, "(e1) OnDragStart registered on custom button")
assignGeometry()
local midsStart = collectCustomMids()
local betweenStart2And3 = midsStart[2] + (midsStart[3] - midsStart[2]) / 2
_G.GetCursorPosition = function() return betweenStart2And3 end
customBtnE._OnDragStart(customBtnE)
assert(customBtnE:GetAlpha() == 0.5,
    "(e1) OnDragStart dims custom button, got " .. tostring(customBtnE:GetAlpha()))
local dragBar = assert(getBar(), "(e1) tab bar exists")
assert(type(dragBar._OnUpdate) == "function", "(e1) drag installs an OnUpdate indicator refresher")
local indicator = assert(inst1().dragIndicator, "(e1) drag indicator created on instance")
assert(indicator.shown == true, "(e1) drag indicator shown")
assert(indicator.width == 2, "(e1) drag indicator is a narrow insert line")
assert(indicator.points[1] and indicator.points[1][2] == getCustomBtnAt(3)
    and indicator.points[1][3] == "LEFT",
    "(e1) interior cursor anchors indicator before slot 3")

-- (e2) OnDragStop past last mid reorders and Rebuild ran (rendered state asserted).
-- from=1 (A), insertPos=4 (past all 3 mids), to = 4-1 = 3 -> [B,C,A].
assignGeometry()
local mids3 = collectCustomMids()
local pastLast = (mids3[#mids3] or 0) + 100
_G.GetCursorPosition = function() return pastLast end
dragBar._OnUpdate(dragBar, 0)
assert(indicator.shown == true, "(e2) drag indicator remains visible while cursor moves")
assert(indicator.points[1] and indicator.points[1][2] == getCustomBtnAt(3)
    and indicator.points[1][3] == "RIGHT",
    "(e2) past-last cursor anchors indicator after the last tab")
customBtnE._OnDragStop(customBtnE)
assert(customBtnE:GetAlpha() == 1, "(e2) button alpha restored after DragStop")
assert(indicator.shown == false, "(e2) drag indicator hidden after DragStop")
assert(dragBar._OnUpdate == nil, "(e2) drag indicator OnUpdate cleared after DragStop")
assert(stubCustomTabs[3] == tabA,
    "(e2) A ended at slot 3 after drop past last mid, got " ..
    tostring(stubCustomTabs[3] and stubCustomTabs[3].name))
-- Rebuild ran: the rendered button at slot 3 (frameID -3) should display "Alpha".
local renderedSlot3 = getCustomBtnAt(3)
assert(renderedSlot3 and renderedSlot3.label.text == "Alpha",
    "(e2) Rebuild ran: slot-3 button label is Alpha, got " ..
    tostring(renderedSlot3 and renderedSlot3.label.text))
-- And buttons1() reflects the new order: last custom button is Alpha.
local lastCustom
for _, b in ipairs(buttons1()) do
    if b.frameID and b.frameID < 0 then lastCustom = b end
end
assert(lastCustom and lastCustom.label.text == "Alpha",
    "(e2) last custom in buttons is Alpha after Rebuild, got " ..
    tostring(lastCustom and lastCustom.label.text))

-- (e3) Interior rightward drop: drag tab 1, cursor between mid2 and mid3.
-- insertPos = ComputeDropIndex gives 3 (cursor < mid[3]), from = 1,
-- to = (insertPos > from) -> (3-1) = 2 -> [B,A,C].
-- Without the insertPos-1 adjustment to=3 is used, giving [B,C,A] instead.
stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC
TU.Rebuild()
assignGeometry()
local midsE3b = collectCustomMids()
-- Place cursor between mid[2] and mid[3] (strictly after mid2, before mid3).
local betweenMid2And3 = midsE3b[2] + (midsE3b[3] - midsE3b[2]) / 2
_G.GetCursorPosition = function() return betweenMid2And3 end
local customBtnE3b = getCustomBtnAt(1)  -- Alpha at slot 1
customBtnE3b._OnDragStart(customBtnE3b)
customBtnE3b._OnDragStop(customBtnE3b)
assert(stubCustomTabs[1] == tabB and stubCustomTabs[2] == tabA and stubCustomTabs[3] == tabC,
    "(e3) interior rightward drop [A,B,C]->[B,A,C], got " ..
    (stubCustomTabs[1] and stubCustomTabs[1].name or "?") .. "," ..
    (stubCustomTabs[2] and stubCustomTabs[2].name or "?") .. "," ..
    (stubCustomTabs[3] and stubCustomTabs[3].name or "?"))

-- (e4) Own-slot right-gap no-op: drag tab 2 (Beta), cursor between mid2 and mid3.
-- from=2, insertPos=3 -> to = (3>2) -> 3-1 = 2 -> from==to -> no move.
-- Without the adjustment to=3 != from=2 so the tab would shift.
stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC
TU.Rebuild()
assignGeometry()
local midsE3c = collectCustomMids()
betweenMid2And3 = midsE3c[2] + (midsE3c[3] - midsE3c[2]) / 2
_G.GetCursorPosition = function() return betweenMid2And3 end
local customBtnE3c = getCustomBtnAt(2)  -- Beta at slot 2
customBtnE3c._OnDragStart(customBtnE3c)
customBtnE3c._OnDragStop(customBtnE3c)
assert(stubCustomTabs[1] == tabA and stubCustomTabs[2] == tabB and stubCustomTabs[3] == tabC,
    "(e4) own-slot right-gap drop is a no-op, got " ..
    (stubCustomTabs[1] and stubCustomTabs[1].name or "?") .. "," ..
    (stubCustomTabs[2] and stubCustomTabs[2].name or "?") .. "," ..
    (stubCustomTabs[3] and stubCustomTabs[3].name or "?"))

-- (e5) Drop onto own slot does not mutate.
-- Restore [A,B,C] and drop A onto slot 1 (before first mid -> insertPos=1, to=1, from=1).
stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC
TU.Rebuild()
assignGeometry()
local mids4 = collectCustomMids()
-- Cursor before the first custom tab's mid -> insertPos=1, to=1, from=1 -> no move.
_G.GetCursorPosition = function() return (mids4[1] or 0) - 5 end
local customBtnE4 = getCustomBtnAt(1)
customBtnE4._OnDragStart(customBtnE4)
customBtnE4._OnDragStop(customBtnE4)
assert(stubCustomTabs[1] == tabA and stubCustomTabs[2] == tabB and stubCustomTabs[3] == tabC,
    "(e5) drop on own slot does not mutate, got " ..
    (stubCustomTabs[1] and stubCustomTabs[1].name or "?") .. "," ..
    (stubCustomTabs[2] and stubCustomTabs[2].name or "?") .. "," ..
    (stubCustomTabs[3] and stubCustomTabs[3].name or "?"))

-- ─── (g) Conversation (whisper) tabs drag-reorder among saved tabs ────────

stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC
stubConvs[1] = { key = "W:ann", name = "Ann", windowID = 1 }
TU.Rebuild()
local function getConvBtn(key)
    for _, b in ipairs(buttons1()) do
        if b.frameID == "conv:" .. key then return b end
    end
    return nil
end
local function barFrameIDs()
    local out = {}
    for _, b in ipairs(buttons1()) do out[#out + 1] = tostring(b.frameID) end
    return table.concat(out, ",")
end
local convBtn = assert(getConvBtn("W:ann"), "(g) conversation button rendered")
assert(barFrameIDs() == "-1,-2,-3,conv:W:ann", "(g) default order, got " .. barFrameIDs())

-- Drag Ann (display slot 4) between Alpha and Beta -> display slot 2.
assignGeometry()
local midsAll = {}
for _, b in ipairs(buttons1()) do
    midsAll[#midsAll + 1] = (b._left or 0) + (b.width or 50) / 2
end
_G.GetCursorPosition = function() return midsAll[1] + (midsAll[2] - midsAll[1]) / 2 end
convBtn._OnDragStart(convBtn)
assert(convBtn:GetAlpha() == 0.5, "(g) conversation tab drag is permitted (dims)")
convBtn._OnDragStop(convBtn)
assert(barFrameIDs() == "-1,conv:W:ann,-2,-3",
    "(g) conv interleaved between saved tabs, got " .. barFrameIDs())
assert(stubCustomTabs[1] == tabA and stubCustomTabs[2] == tabB and stubCustomTabs[3] == tabC,
    "(g) conv-only move leaves the stored array untouched")

-- (g2) Saved tab dragged across the conversation persists the saved order:
-- drag Alpha (display 1) past everything -> display [Ann,B,C,A], stored {B,C,A}.
assignGeometry()
local midsG2 = {}
for _, b in ipairs(buttons1()) do
    midsG2[#midsG2 + 1] = (b._left or 0) + (b.width or 50) / 2
end
_G.GetCursorPosition = function() return midsG2[#midsG2] + 100 end
local alphaBtn = assert(getCustomBtnAt(1), "(g2) Alpha button at stored slot 1")
alphaBtn._OnDragStart(alphaBtn)
alphaBtn._OnDragStop(alphaBtn)
assert(stubCustomTabs[1] == tabB and stubCustomTabs[2] == tabC and stubCustomTabs[3] == tabA,
    "(g2) stored array rewritten to B,C,A, got " ..
    (stubCustomTabs[1] and stubCustomTabs[1].name or "?") .. "," ..
    (stubCustomTabs[2] and stubCustomTabs[2].name or "?") .. "," ..
    (stubCustomTabs[3] and stubCustomTabs[3].name or "?"))
assert(barFrameIDs() == "conv:W:ann,-1,-2,-3",
    "(g2) bar order conv,B,C,A, got " .. barFrameIDs())
local lastBtn = buttons1()[#buttons1()]
assert(lastBtn and lastBtn.label.text == "Alpha",
    "(g2) last bar button is Alpha, got " .. tostring(lastBtn and lastBtn.label.text))

-- (g3) Conversation close prunes its slot; saved order stays.
stubConvs[1] = nil
TU.Rebuild()
assert(barFrameIDs() == "-1,-2,-3", "(g3) conv pruned, got " .. barFrameIDs())

-- Restore baseline for the sections below.
stubCustomTabs[1] = tabA; stubCustomTabs[2] = tabB; stubCustomTabs[3] = tabC
TU.Rebuild()

-- ─── (f) Single custom tab guard ──────────────────────────────────────────

local singleStub = { { name = "Only", groups = { SAY = true } } }
local nsf = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return { enabled = true } end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetAccent = function() return { 0.2, 0.8, 0.6, 1 } end,
            GetThemeColors = function() return { text = { 1, 1, 1, 1 }, textDim = { 0.7, 0.7, 0.7, 1 } } end,
        },
        DisplayLayer = { GetContainer = function() return makeFrame("Frame") end },
        MessageStore = { OnAppend = function() end },
        TabManager = {
            SetActiveTab = function(wid, td) end,
            GetWindowTabs = function(wid) return singleStub end,
            GetWindowTab = function(wid, i) return singleStub[i] end,
            BuildTabFilter = function() return function() return true end end,
        },
    } },
}
assert(loadfile("QUI_Chat/chat/tab_ui.lua"))("QUI", nsf)
local TUsingle = nsf.QUI.Chat.TabUI
assert(TUsingle._ReorderDisplayTab(1, 2) == false,
    "(f) single custom tab -> _ReorderDisplayTab returns false")
assert(TUsingle._ReorderDisplayTab(1, 1) == false,
    "(f) single tab same-slot -> false")

print("OK: chat_tab_drag_reorder_test")
