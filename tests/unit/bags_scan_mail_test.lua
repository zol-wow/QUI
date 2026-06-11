-- tests/unit/bags_scan_mail_test.lua
-- Run: lua tests/unit/bags_scan_mail_test.lua
-- Mail scanner: legacy inbox globals, whole-inbox rescan unit, session keyed
-- by MAIL_SHOW/MAIL_CLOSED (inbox data is server-resident and only readable
-- at a mailbox). Store shape: rec.mail = { size = n, slots = list } so
-- summaries' IndexInto walks it unchanged (list-as-slots).
-- luacheck: globals QUI_StorageDB GetInboxNumItems GetInboxHeaderInfo GetInboxItem GetInboxItemLink
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- Legacy inbox API stubs ----------------------------------------------------
-- Shapes per vendored Blizzard_MailFrame/MailFrame.lua:
--   GetInboxNumItems() → numItems, totalItems                       (line 180)
--   GetInboxHeaderInfo(i) → packageIcon, stationeryIcon, sender, subject,
--     money, CODAmount, daysLeft, itemCount, wasRead, wasReturned,
--     textCreated, canReply, isGM, firstItemQuantity, firstItemLink (line 203)
--   GetInboxItem(i, j) → name, itemID, texture, count, quality, canUse,
--     isCurrency                                                    (line 470)
--   GetInboxItemLink(i, j) → link                            (MailFrame.xml:254)
local inbox = {} -- [i] = { money, daysLeft, attachments = { [j] = {...} } }
_G.GetInboxNumItems = function() return #inbox, #inbox end
_G.GetInboxHeaderInfo = function(i)
    local m = inbox[i]
    if not m then return nil end
    local itemCount = 0
    for _ in pairs(m.attachments or {}) do itemCount = itemCount + 1 end
    return 134327, 134328, "Sender", "Subject", m.money or 0, 0, m.daysLeft,
           itemCount > 0 and itemCount or nil, true, false, false, true, false, nil, nil
end
_G.GetInboxItem = function(i, j)
    local a = inbox[i] and inbox[i].attachments and inbox[i].attachments[j]
    if not a then return nil end
    return a.name, a.id, a.texture, a.count, a.quality, true, a.isCurrency or false
end
_G.GetInboxItemLink = function(i, j)
    local a = inbox[i] and inbox[i].attachments and inbox[i].attachments[j]
    return a and a.link or nil
end

local ns = loader.LoadAll(nil, "scan_mail.lua")
ns.Bags.RequestDrain = function() end
local Store, ScanMail, Bus = ns.Bags.Store, ns.Bags.ScanMail, ns.Bags.Bus

_G.QUI_StorageDB = nil
Store.Initialize()
Store.EnsureCurrentCharacter()
local KEY = "Testchar-TestRealm"

local events = {}
Bus.Subscribe("MailChanged", function(_, charKey) events[#events + 1] = charKey end)

-- Test 1: dirty drain without a mail session must no-op (inbox unreadable
-- away from a mailbox — a wipe here would clobber the cache with emptiness)
ScanMail.MarkDirty()
assert(ScanMail.Drain() == false, "drain away from a mailbox must no-op")
assert(#events == 0, "no-session drain must not publish")

-- Test 2: OnMailShow opens the session + marks; drain writes the flat list
inbox[1] = {
    money = 500, daysLeft = 29.5,
    attachments = {
        [1] = { name = "Widget", id = 6948, texture = 134414, count = 5, quality = 2,
                link = "|Hitem:6948::::::::70:::::|h[Widget]|h" },
        -- sparse attachment index (slot 2 empty, slot 3 occupied)
        [3] = { name = "Gizmo", id = 12345, texture = 132599, count = 1, quality = 3,
                link = "|Hitem:12345::::::::70:::::|h[Gizmo]|h" },
    },
}
inbox[2] = { money = 1000, daysLeft = 12 } -- money-only mail: no item entries
ScanMail.OnMailShow()
assert(ScanMail.Drain() == true, "session drain must write")
local rec = Store.GetCurrentCharacter()
assert(rec.mail.size == 2, "two attachment entries expected, got " .. tostring(rec.mail.size))
assert(#rec.mail.slots == 2, "slots must be a dense list")
local e1, e2 = rec.mail.slots[1], rec.mail.slots[2]
assert(e1.itemID == 6948 and e1.count == 5 and e1.quality == 2 and e1.icon == 134414
       and e1.link == "|Hitem:6948::::::::70:::::|h[Widget]|h" and e1.daysLeft == 29.5,
       "first entry wrong")
assert(e2.itemID == 12345 and e2.count == 1 and e2.daysLeft == 29.5, "sparse attachment index missed")
assert(#events == 1 and events[1] == KEY, "exactly one MailChanged(charKey) per drain")
assert(ScanMail.Drain() == false, "clean drain must no-op")

-- Test 3: entry-shape minimalism guard — ONLY the six mail entry keys
-- (itemID, count, link, quality, icon, daysLeft; mail carries no isBound)
local allowed = { itemID = true, count = true, link = true, quality = true,
                  icon = true, daysLeft = true }
for i, e in ipairs(rec.mail.slots) do
    for k in pairs(e) do
        assert(allowed[k], "unexpected persisted key in mail entry " .. i .. ": " .. tostring(k))
    end
end

-- Test 4: currency attachments are skipped — GetInboxItem's id is a
-- currencyID there, a different ID space than itemIDs
inbox[2].attachments = {
    [1] = { name = "Shiny Token", id = 3008, texture = 463446, count = 250,
            quality = 1, isCurrency = true },
}
ScanMail.MarkDirty()
assert(ScanMail.Drain() == true, "dirty session drain must write")
assert(rec.mail == Store.GetCurrentCharacter().mail, "rec still current")
rec = Store.GetCurrentCharacter()
for _, e in ipairs(rec.mail.slots) do
    assert(e.itemID ~= 3008, "currency attachment must not persist as an item entry")
end
assert(rec.mail.size == 2, "currency attachment must not change the entry count")

-- Test 5: genuine empty inbox at an open mailbox must overwrite (the user
-- collected everything) and still publish
inbox = {}
ScanMail.MarkDirty()
assert(ScanMail.Drain() == true, "empty-inbox session drain must write")
rec = Store.GetCurrentCharacter()
assert(rec.mail.size == 0 and next(rec.mail.slots) == nil, "empty inbox must wipe the cache")
assert(#events == 3, "empty-inbox drain must publish (consumers must drop stale counts)")

-- Test 6: OnMailClosed ends the session; dirty drains no-op again
inbox[1] = { daysLeft = 5, attachments = { [1] = { name = "Late", id = 777, texture = 1,
                                                   count = 1, quality = 1 } } }
ScanMail.OnMailClosed()
ScanMail.MarkDirty()
assert(ScanMail.Drain() == false, "drain after close must no-op even when dirty")
assert(#events == 3, "closed-session drain must not publish")

-- Test 7: drain with no character record preserves the dirty mark
ScanMail.OnMailShow()
Store.DeleteCharacter(KEY)
assert(ScanMail.Drain() == false, "drain without a record must not write")
Store.EnsureCurrentCharacter()
assert(ScanMail.Drain() == true, "mark must survive a record-less drain")

print("OK: bags_scan_mail_test")
