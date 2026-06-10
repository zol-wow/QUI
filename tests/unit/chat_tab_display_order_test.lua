-- tests/unit/chat_tab_display_order_test.lua
-- Run: lua tests/unit/chat_tab_display_order_test.lua
-- Mixed tab display order: conversation (whisper) tabs are orderable anywhere
-- among saved tabs (TabManager.GetDisplayEntries / MoveDisplayEntry). Saved
-- tabs persist their RELATIVE order in the stored windows[].tabs array;
-- conversation positions are session-only and reconciled on every read
-- (closed conversations pruned, new ones appended, external saved-array
-- reorders re-seat the saved tokens without disturbing conversation slots).

_G.ChatTypeGroupInverted = {}
_G.NUM_CHAT_WINDOWS = 1
function _G.GetChatWindowInfo() return "" end
function _G.GetChatWindowMessages() end
function _G.GetChatWindowChannels() end

local tabA = { name = "Alpha", groups = { SAY = true } }
local tabB = { name = "Beta",  groups = { YELL = true } }
local tabC = { name = "Gamma", groups = { LOOT = true } }
local savedTabs = { tabA, tabB, tabC }
local settings = { enabled = true, customDisplay = { combatLogTab = false,
    windows = { { tabs = savedTabs } } } }

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

-- Conversation registry stub (creation order, per-window).
local convs = {}
ns.QUI.Chat.ConversationManager = {
    EachForWindow = function(windowID, fn)
        for i = 1, #convs do
            if convs[i].windowID == windowID then fn(convs[i]) end
        end
    end,
}

assert(loadfile("QUI_Chat/chat/tab_manager.lua"))("QUI", ns)
local TM = ns.QUI.Chat.TabManager

local function ids(windowID)
    local out = {}
    for _, e in ipairs(TM.GetDisplayEntries(windowID or 1)) do
        out[#out + 1] = (e.kind == "conv") and ("conv:" .. e.key) or e.tab.name
    end
    return table.concat(out, ",")
end

-- (a) Default order: saved array order, then conversations in creation order.
convs = { { key = "W:ann", name = "Ann", windowID = 1 },
          { key = "BN:bob", name = "Bob", windowID = 1 } }
assert(ids() == "Alpha,Beta,Gamma,conv:W:ann,conv:BN:bob",
    "(a) default order, got " .. ids())
local e2 = TM.GetDisplayEntries(1)[2]
assert(e2.kind == "saved" and e2.index == 2 and e2.tab == tabB,
    "(a) saved entry carries its saved-array index")
local e4 = TM.GetDisplayEntries(1)[4]
assert(e4.kind == "conv" and e4.key == "W:ann" and e4.conv == convs[1],
    "(a) conv entry carries key + registry object")

-- (b) Move a conversation between saved tabs: display moves, stored array
--     untouched (conversation positions are session-only).
local ok, savedChanged = TM.MoveDisplayEntry(1, 4, 2) -- Ann -> slot 2
assert(ok == true, "(b) move returns true")
assert(savedChanged == false, "(b) conv-only move reports saved order unchanged")
assert(ids() == "Alpha,conv:W:ann,Beta,Gamma,conv:BN:bob",
    "(b) conv interleaved, got " .. ids())
assert(savedTabs[1] == tabA and savedTabs[2] == tabB and savedTabs[3] == tabC,
    "(b) stored array unchanged")

-- (c) Session order is sticky across reads.
assert(ids() == "Alpha,conv:W:ann,Beta,Gamma,conv:BN:bob",
    "(c) sticky, got " .. ids())

-- (d) Move a saved tab across a conversation: stored array relative order
--     rewritten IN PLACE (persistence is the mutation).
ok, savedChanged = TM.MoveDisplayEntry(1, 1, 3) -- Alpha -> after Beta
assert(ok and savedChanged == true, "(d) saved move reports a persisted change")
assert(ids() == "conv:W:ann,Beta,Alpha,Gamma,conv:BN:bob",
    "(d) display order, got " .. ids())
assert(savedTabs[1] == tabB and savedTabs[2] == tabA and savedTabs[3] == tabC,
    "(d) stored relative order rewritten")

-- (e) Closing a conversation prunes its slot; the rest keep their order.
table.remove(convs, 1) -- Ann closed
assert(ids() == "Beta,Alpha,Gamma,conv:BN:bob", "(e) pruned, got " .. ids())

-- (f) A new conversation appends at the end.
convs[#convs + 1] = { key = "W:cyn", name = "Cyn", windowID = 1 }
assert(ids() == "Beta,Alpha,Gamma,conv:BN:bob,conv:W:cyn",
    "(f) new conv appends, got " .. ids())

-- (g) External saved-array reorder (options panel) re-seats saved tokens in
--     array order while conversation slots stay put.
ok = TM.MoveDisplayEntry(1, 4, 1) -- Bob -> front
assert(ok and ids() == "conv:BN:bob,Beta,Alpha,Gamma,conv:W:cyn",
    "(g) setup, got " .. ids())
savedTabs[1], savedTabs[2], savedTabs[3] = tabC, tabB, tabA -- panel rewrote the array
assert(ids() == "conv:BN:bob,Gamma,Beta,Alpha,conv:W:cyn",
    "(g) saved tokens re-seated to array order, conv slots kept, got " .. ids())

-- (h) Guards: same-slot no-op, out-of-range, bad types, clamp-to-end.
assert(TM.MoveDisplayEntry(1, 3, 3) == false, "(h) same-slot no-op")
assert(TM.MoveDisplayEntry(1, 99, 1) == false, "(h) out-of-range from")
assert(TM.MoveDisplayEntry(1, "x", 1) == false, "(h) non-number from")
ok, savedChanged = TM.MoveDisplayEntry(1, 1, 99) -- clamp to end
assert(ok and savedChanged == false and
    ids() == "Gamma,Beta,Alpha,conv:W:cyn,conv:BN:bob",
    "(h) to clamps to end, got " .. ids())

-- (i) Per-window isolation + window-deletion shift.
convs[#convs + 1] = { key = "W:dee", name = "Dee", windowID = 2 }
settings.customDisplay.windows[2] = { tabs = { { name = "Win2", groups = { SAY = true } } } }
assert(ids(2) == "Win2,conv:W:dee", "(i) window 2 isolated, got " .. ids(2))
TM.MoveDisplayEntry(2, 2, 1)
assert(ids(2) == "conv:W:dee,Win2", "(i) window 2 move, got " .. ids(2))
-- Window 1 deleted: window 2's session order must follow the shifted ID.
-- (Simulate the rest of the deletion flow too: the dead window's
-- conversations close/re-home, and surviving windows shift down.)
TM.OnWindowDeleted(1)
table.remove(settings.customDisplay.windows, 1)
for i = #convs, 1, -1 do
    if convs[i].windowID == 1 then
        table.remove(convs, i)
    elseif convs[i].windowID == 2 then
        convs[i].windowID = 1
    end
end
assert(ids(1) == "conv:W:dee,Win2",
    "(i) shifted window keeps its session order, got " .. ids(1))

print("OK: chat_tab_display_order_test")
