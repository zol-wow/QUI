-- luacheck: read globals ATTACHMENTS_MAX_RECEIVE GetInboxNumItems GetInboxHeaderInfo GetInboxItem
-- luacheck: read globals GetInboxItemLink
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanMail = {}
Storage.ScanMail = ScanMail

local MAX_ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16

local atMailbox = false
local hasDirty = false

function ScanMail.OnMailShow()
    atMailbox = true
    hasDirty = true
end

function ScanMail.OnMailClosed()
    atMailbox = false
end

function ScanMail.MarkDirty()
    hasDirty = true
end

function ScanMail.Drain()
    if not hasDirty then return false end
    if not atMailbox then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    hasDirty = false
    local list = {}
    local numItems = GetInboxNumItems()
    for i = 1, numItems do
        local _, _, _, _, _, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
        if itemCount and itemCount > 0 then
            for attach = 1, MAX_ATTACHMENTS do
                local _, itemID, texture, count, quality, _, isCurrency = GetInboxItem(i, attach)
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
    rec.mail = { size = #list, slots = list }
    Storage.Bus.Publish("MailChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
