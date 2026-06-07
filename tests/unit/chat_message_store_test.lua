-- tests/unit/chat_message_store_test.lua
-- Run: lua tests/unit/chat_message_store_test.lua
-- Verifies the custom-display message store: append/iterate order, cap
-- trimming, subscriber dispatch, and that secret payloads pass through with
-- ZERO Lua operators applied (op-trapped sentinel).

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, {
    __tostring = explode, __concat = explode, __len = explode,
    __eq = explode, __lt = explode, __le = explode, __index = explode,
    __newindex = explode,
})

local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    QUI = { Chat = { _internals = {} } },
}

assert(loadfile("QUI_Chat/chat/message_store.lua"))("QUI", ns)
local Store = ns.QUI.Chat.MessageStore

-- Append + ForEach order (oldest -> newest)
Store.SetCap(100)
Store.Append({ m = "one" })
Store.Append({ m = "two" })
local seen = {}
Store.ForEach(function(e) seen[#seen + 1] = e.m end)
assert(#seen == 2 and seen[1] == "one" and seen[2] == "two", "order oldest->newest")
assert(Store.Size() == 2, "Size after 2 appends")

-- Subscriber fires with the appended entry
local got
Store.OnAppend(function(e) got = e end)
local entry3 = { m = "three" }
Store.Append(entry3)
assert(got == entry3, "subscriber receives identical entry table")

-- Cap trimming: overflow drops oldest, keeps newest
Store.Clear()
Store.SetCap(50)
for i = 1, 130 do Store.Append({ m = i }) end
assert(Store.Size() <= 75, "compaction keeps size near cap, got " .. Store.Size())
local first
Store.ForEach(function(e) if not first then first = e.m end end)
assert(first > 130 - 75, "oldest entries were dropped, first=" .. tostring(first))
local last
Store.ForEach(function(e) last = e.m end)
assert(last == 130, "newest entry retained")

-- SetCap shrink: reducing cap on a populated store evicts oldest immediately
Store.Clear()
Store.SetCap(200)
for i = 1, 200 do Store.Append({ m = i }) end
Store.SetCap(50)
assert(Store.Size() <= 75, "SetCap shrink compacts immediately, got " .. Store.Size())
local firstAfterShrink
Store.ForEach(function(e) if not firstAfterShrink then firstAfterShrink = e.m end end)
assert(firstAfterShrink > 200 - 75, "SetCap shrink drops oldest, first=" .. tostring(firstAfterShrink))

-- Secret pass-through: storing + iterating a secret entry applies no operator
Store.Clear()
local sEntry = { m = secret, s = true }
Store.Append(sEntry)
local out
Store.ForEach(function(e) out = e end)
assert(out == sEntry and rawequal(out.m, secret),
    "secret entry stored and returned untouched")

-- Clear empties
Store.Clear()
assert(Store.Size() == 0, "Clear empties store")

-- A subscriber that errors must not break Append (pcall isolation)
Store.OnAppend(function() error("boom") end)
Store.Append({ m = "after-bad-subscriber" })
assert(Store.Size() == 1, "append survives erroring subscriber")

print("OK: chat_message_store_test")
