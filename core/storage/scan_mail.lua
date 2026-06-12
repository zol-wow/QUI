---------------------------------------------------------------------------
-- Core storage: mailbox (inbox) scanner.
-- Inbox data is server-resident and only readable while a mailbox is open,
-- through the legacy global API: GetInboxNumItems / GetInboxHeaderInfo /
-- GetInboxItem / GetInboxItemLink (verified against vendored
-- Blizzard_MailFrame/MailFrame.lua). The session is keyed by
-- MAIL_SHOW/MAIL_CLOSED; MAIL_INBOX_UPDATE is payload-free, so the rescan
-- unit is the whole inbox — at most 50 visible mails × 16 attachment reads,
-- all synchronous (no async item loads, so no snapshot-swap; cf. scan_guild).
-- Store shape: rec.mail = { size = n, slots = <dense entry list> } —
-- list-as-slots so summaries' IndexInto walks it unchanged.
-- Mail entries carry daysLeft instead of isBound (expiry matters at the
-- mailbox; bind state is unknowable from header data).
-- Sent-mail tracking stays out per spec §12. GetInboxNumItems' second
-- return (totalItems) can exceed the visible count; only the visible page
-- is readable — accepted v1 limitation.
---------------------------------------------------------------------------
-- luacheck: read globals ATTACHMENTS_MAX_RECEIVE GetInboxNumItems GetInboxHeaderInfo GetInboxItem
-- luacheck: read globals GetInboxItemLink
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanMail = {}
Storage.ScanMail = ScanMail

-- 16 — vendored Blizzard_MailFrame/MailFrame.lua:7 (fallback for harnesses).
local MAX_ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16

local atMailbox = false -- session: true while a mailbox is open
local hasDirty = false

--- MAIL_SHOW: opens the session and marks the inbox for a full scan.
function ScanMail.OnMailShow()
    atMailbox = true
    hasDirty = true
end

--- MAIL_CLOSED: ends the session; later drains no-op. The collector always
--- clears the flag (collection is a core service) — a stale at-mailbox flag
--- would let a drain away from a mailbox read an empty inbox and wipe the
--- cache.
function ScanMail.OnMailClosed()
    atMailbox = false
end

--- MAIL_INBOX_UPDATE carries no payload → whole-inbox rescan is the unit.
function ScanMail.MarkDirty()
    hasDirty = true
end

--- Re-read the visible inbox into the store; publishes MailChanged(charKey)
--- (whole-record event — no changed array; see bus.lua). Returns true when
--- written. No-op unless dirty AND a mailbox session is open AND the
--- character record exists.
function ScanMail.Drain()
    if not hasDirty then return false end
    if not atMailbox then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end -- transient: dirty mark preserved
    hasDirty = false
    local list = {}
    local numItems = GetInboxNumItems()
    for i = 1, numItems do
        -- header returns (MailFrame.lua:203): packageIcon, stationeryIcon,
        -- sender, subject, money, CODAmount, daysLeft, itemCount, ...
        local _, _, _, _, _, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
        if itemCount and itemCount > 0 then
            for attach = 1, MAX_ATTACHMENTS do
                -- (MailFrame.lua:470): name, itemID, texture, count, quality,
                -- canUse, isCurrency
                local _, itemID, texture, count, quality, _, isCurrency = GetInboxItem(i, attach)
                -- isCurrency: id is a currencyID, NOT an itemID (different ID
                -- space) — never persisted as an item entry.
                if itemID and not isCurrency then
                    list[#list + 1] = {
                        itemID = itemID,
                        count = count,
                        link = GetInboxItemLink(i, attach),
                        quality = quality,
                        icon = texture,
                        daysLeft = daysLeft,
                    }
                end
            end
        end
    end
    -- A genuinely empty inbox must overwrite (the user collected everything)
    -- and still publish so consumers drop stale counts.
    rec.mail = { size = #list, slots = list }
    Storage.Bus.Publish("MailChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
