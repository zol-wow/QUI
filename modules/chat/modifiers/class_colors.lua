---------------------------------------------------------------------------
-- QUI Chat Modifier — Class Colors
-- Applies class-color rendering to a message's SENDER name, entirely
-- post-render: the modifier runs from chat.lua's rendered-line transform
-- (after Blizzard's chat-history bookkeeping), finds the sender's
-- |Hplayer:..|h[Name]|h hyperlink in the already-rendered line, and wraps it
-- with the class color resolved from the event's sender GUID. Same visual as
-- Blizzard's native colorNameByClass, with zero global mutation.
--
-- IMPORTANT: do NOT toggle ChatTypeInfo[event].colorNameByClass to achieve
-- this. Writing that Blizzard-owned global table taints chat: every secure
-- ChatFrame_MessageEventHandler read of ChatTypeInfo then runs tainted, the
-- persistent accessIDs table inside ChatHistory_GetAccessID stays poisoned for
-- the session, and the first secret chat payload (monster combat speech)
-- throws "string conversion on a secret string value" in GetToken. Post-render
-- coloring keeps the feature out of the secure dispatch path entirely.
--
-- Sub-toggle "recolorBodyText" (default off) enables a regex pass that
-- wraps player-name tokens in the message body with class color codes.
-- More expensive; opt-in. Only fires for events the pipeline transforms.
--
-- Cache: name → { class = <classFile>, realm = <realm or nil> } populated
-- from prior GUID-bearing chat events and from GROUP_ROSTER_UPDATE walking
-- the roster. Cleared on PLAYER_LEAVING_WORLD. Realm is captured so the
-- Phase D player-link payload can address cross-realm players.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: class_colors.lua loaded before chat.lua. Check chat.xml — chat.lua must precede class_colors.lua.")

local Pipeline = assert(ns.QUI.Chat.Pipeline,
    "QUI Chat: class_colors.lua loaded before pipeline.lua. Check chat.xml — pipeline.lua must precede modifiers/.")

local Helpers = ns.Helpers

-- Forward declaration so frame:SetScript closures can capture this as an
-- upvalue. The function body is assigned later in the file.
local ApplyEnabled

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function IsChatMessagingLockedDown()
    return I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()
end

-- Cache: name (no realm in key) → { class, realm }. Plain table — entries
-- are explicitly cleared on PLAYER_LEAVING_WORLD; weak values would let GC
-- drop the entry tables between pipeline invocations.
local nameToClass = {}

-- ---------------------------------------------------------------------------
-- Cache population
-- ---------------------------------------------------------------------------

local function splitNameRealm(author)
    if IsSecret(author) then return nil, nil end
    if type(author) ~= "string" or author == "" then return nil, nil end
    local hyphen = author:find("-", 1, true)
    if hyphen then return author:sub(1, hyphen - 1), author:sub(hyphen + 1) end
    return author, nil
end

local function cacheFromGUID(name, realm, guid)
    if not guid or not name then return nil end
    if Helpers.IsSecretValue and Helpers.IsSecretValue(guid) then return nil end
    local _, classFile, _, _, _, _, guidRealm = GetPlayerInfoByGUID(guid)
    if classFile then
        local resolvedRealm = realm
        if (not resolvedRealm or resolvedRealm == "") and guidRealm and guidRealm ~= "" then
            resolvedRealm = guidRealm
        end
        nameToClass[name] = { class = classFile, realm = resolvedRealm }
        return classFile
    end
    return nil
end

local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("PLAYER_LOGIN")
rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
rosterFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Re-evaluate after AceDB has finished initializing in OnInitialize.
        ApplyEnabled()
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then
        for k in pairs(nameToClass) do nameToClass[k] = nil end
        return
    end
    -- GROUP_ROSTER_UPDATE
    local count = GetNumGroupMembers() or 0
    if count == 0 then return end
    if IsInRaid() then
        for i = 1, count do
            local rawName, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if rawName and classFile then
                local name, realm = splitNameRealm(rawName)
                nameToClass[name] = { class = classFile, realm = realm }
            end
        end
    else
        -- Party
        for i = 1, count do
            local unit = (i == count) and "player" or ("party" .. i)
            local _, classFile = UnitClass(unit)
            local name, realm = UnitFullName(unit)
            if name and classFile then
                nameToClass[name] = { class = classFile, realm = realm }
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Body-text recolor (optional)
-- ---------------------------------------------------------------------------

local function colorize(name, class, realm)
    if not name or not class then return nil end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color or not color.colorStr then return nil end
    local colored = string.format("|c%s%s|r", color.colorStr, name)

    -- Phase D: when interactive names are enabled, additionally wrap with
    -- the addon-protocol player link. Click handler lives in hyperlinks.lua
    -- (dispatched via SetItemRef hook). Defensive: settings table may not
    -- yet be ready during early init; if hyperlinks subtable is missing,
    -- fall through to plain coloring.
    local settings = I.GetSettings and I.GetSettings()
    local hl = settings and settings.hyperlinks
    if hl and hl.interactiveNames then
        return "|Haddon:quaziiuichat:player:" .. name .. ":" .. (realm or "") .. "|h" .. colored .. "|h"
    end
    return colored
end

-- Recolor cached player names within a plain-text span. The caller guarantees
-- the span contains no |H..|h hyperlinks, so a name match can never land inside
-- a link payload (e.g. |Hplayer:Name-Realm:..|h) and corrupt it.
local function recolorPlainText(text)
    for cachedName, info in pairs(nameToClass) do
        if cachedName and info and info.class then
            local colored = colorize(cachedName, info.class, info.realm)
            if colored then
                -- Word-boundary substitution. Lua patterns don't have \b but
                -- %f[set] frontier pattern works for transitions across char classes.
                local escapedName = cachedName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                local escapedColored = colored:gsub("%%", "%%%%")
                text = text:gsub("(%f[%w_])(" .. escapedName .. ")(%f[^%w_])",
                                 "%1" .. escapedColored .. "%3")
            end
        end
    end
    return text
end

local function recolorBody(msg)
    if IsSecret(msg) or IsChatMessagingLockedDown() then return msg end
    if type(msg) ~= "string" or msg == "" then return msg end
    if next(nameToClass) == nil then return msg end

    -- Recolor only OUTSIDE hyperlink spans. A cached name can also appear inside
    -- a |Hplayer:Name-Realm:..|h payload; rewriting it there corrupts the link
    -- (and the sender link is class-colored separately by recolorSenderName).
    -- Walk the line, copy each |H..|h..|h span verbatim, and recolor only the
    -- plain-text gaps between them.
    local out, i, n = {}, 1, #msg
    while i <= n do
        local hs, he = msg:find("|H.-|h.-|h", i)
        if not hs then
            out[#out + 1] = recolorPlainText(msg:sub(i))
            break
        end
        if hs > i then
            out[#out + 1] = recolorPlainText(msg:sub(i, hs - 1))
        end
        out[#out + 1] = msg:sub(hs, he)
        i = he + 1
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Sender-name recolor (main toggle)
-- ---------------------------------------------------------------------------

-- Resolve the sender's class file, name AND realm (name+realm are needed to
-- target the sender's own link rather than a same-name link from another realm):
-- prefer the event GUID, fall back to the name→class cache keyed on author name.
-- GetPlayerInfoByGUID returns localizedClass, englishClass, localizedRace,
-- englishRace, sex, name, realmName (PlayerScriptDocumentation.lua:675).
local function resolveSender(info)
    if not info then return nil end
    local authorName, authorRealm = splitNameRealm(info.author)
    local guid = info.guid
    if guid and not IsSecret(guid) then
        local _, classFile, _, _, _, guidName, guidRealm = GetPlayerInfoByGUID(guid)
        if classFile then
            local name = (guidName and guidName ~= "") and guidName or authorName
            local realm = (guidRealm and guidRealm ~= "") and guidRealm or authorRealm
            return classFile, name, realm
        end
    end
    local cached = authorName and nameToClass[authorName]
    if cached and cached.class then
        local realm = (cached.realm and cached.realm ~= "") and cached.realm or authorRealm
        return cached.class, authorName, realm
    end
    return nil, authorName, authorRealm
end

-- Events whose sender name Blizzard does NOT auto-color by class. Only these
-- get our post-render recolor; the rest (PARTY/RAID/GUILD/OFFICER/INSTANCE/...)
-- are already class-colored natively, so re-wrapping would double-color them.
local SENDER_RECOLOR_EVENTS = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_CHANNEL = true,
}

-- Wrap the SENDER's own player hyperlink in the rendered line with the class
-- color. The sender link is identified by matching its payload Name-Realm (not
-- "the first |Hplayer: link", which may be a different player — possibly a
-- same-name player from another realm — quoted in the line). The whole link is
-- wrapped rather than nested into, and a link already immediately preceded by a
-- |c color escape is left untouched (idempotent — no double-wrap). No-op when
-- class/name can't be resolved or the sender's link is absent (system / monster
-- lines, sender prefix stripped).
local function recolorSenderName(msg, info)
    if IsSecret(msg) or IsChatMessagingLockedDown() then return msg end
    if type(msg) ~= "string" or msg == "" then return msg end
    local class, senderName, senderRealm = resolveSender(info)
    if not class or not senderName or senderName == "" then return msg end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color or not color.colorStr then return msg end

    local nameLower = senderName:lower()
    local realmLower = (senderRealm and senderRealm ~= "") and senderRealm:lower() or nil

    -- Player names cannot contain '-', so the link payload up to the first ':'
    -- splits cleanly into Name[-Realm]. Pass 1 requires an exact Name-Realm
    -- match (so a same-name cross-realm link is never mistaken for the sender);
    -- pass 2 falls back to a base-name match, used only when the realm is
    -- unknown or no realm-qualified link matched — and still skips a link whose
    -- realm is known to differ from the sender's.
    local function locate(requireRealm)
        local s = 1
        while true do
            local ls, le = msg:find("|Hplayer:.-|h.-|h", s)
            if not ls then return nil end
            local payload = msg:sub(ls, le):match("^|Hplayer:([^:]+)")
            if payload then
                local lname, lrealm = payload:match("^([^%-]+)%-?(.*)$")
                lname = lname and lname:lower()
                lrealm = (lrealm and lrealm ~= "") and lrealm:lower() or nil
                if lname == nameLower then
                    if requireRealm then
                        if realmLower and lrealm == realmLower then return ls, le end
                    elseif not (realmLower and lrealm and lrealm ~= realmLower) then
                        return ls, le
                    end
                end
            end
            s = le + 1
        end
    end

    local ls, le
    if realmLower then ls, le = locate(true) end
    if not ls then ls, le = locate(false) end
    if not ls then return msg end

    local link = msg:sub(ls, le)
    -- Already class-colored? Skip, to avoid nesting |c codes — either a color
    -- escape immediately before the link (a whole-link wrap), or one inside the
    -- link's display text. Blizzard colors the name in the display when
    -- ChatFrameUtil.ShouldColorChatByClass is true (e.g. the chatClassColorOverride
    -- CVar): |Hplayer:..|h[|cff..Name|r]|h. The |Hplayer payload never contains
    -- |c, so any color escape within the link span is in the display text.
    if msg:sub(1, ls - 1):match("|c%x%x%x%x%x%x%x%x$")
        or link:match("|c%x%x%x%x%x%x%x%x") then
        return msg
    end
    return msg:sub(1, ls - 1)
        .. string.format("|c%s%s|r", color.colorStr, link)
        .. msg:sub(le + 1)
end

-- ---------------------------------------------------------------------------
-- Modifier function
-- ---------------------------------------------------------------------------

local function modifier(msg, info, event)
    if not info then return msg, info end

    -- Always opportunistically populate cache from this event's GUID.
    local name, realm = nil, nil
    if not IsChatMessagingLockedDown() then
        name, realm = splitNameRealm(info.author)
    end
    if name and info.guid then
        cacheFromGUID(name, realm, info.guid)
    end

    -- Respect setting toggle (live re-check — cheap, settings is a table read).
    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.modifiers and settings.modifiers.classColors
    if not s or not s.enabled then return msg, info end

    -- Main toggle: color the sender's name by class (post-render, taint-free).
    -- Only for events Blizzard leaves uncolored; it already class-colors the
    -- rest natively (matches the old ChatTypeInfo opt-in set: SAY/YELL/CHANNEL).
    local senderEvent = event or (info and info.event)
    if senderEvent and SENDER_RECOLOR_EVENTS[senderEvent] then
        msg = recolorSenderName(msg, info)
    end

    -- Body-text recolor (sub-toggle).
    if s.recolorBodyText then
        msg = recolorBody(msg)
    end

    return msg, info
end

-- ---------------------------------------------------------------------------
-- Registration / live-toggle
-- ---------------------------------------------------------------------------

local REGISTERED = false

function ApplyEnabled()
    local settings = I.GetSettings and I.GetSettings()
    local enabled = (I.IsChatEnabled and I.IsChatEnabled(settings))
        and settings.modifiers and settings.modifiers.classColors
        and settings.modifiers.classColors.enabled

    if enabled then
        if not REGISTERED then
            Pipeline.Register("class_colors", 100, modifier)
            REGISTERED = true
        end
    else
        if REGISTERED then
            Pipeline.Unregister("class_colors")
            REGISTERED = false
        end
    end
end

-- Initial application. Defensive no-op if QUI.db isn't ready at file-load
-- time (returns early because settings is nil); PLAYER_LOGIN guarantees the
-- actual activation once AceDB has been constructed in OnInitialize.
ApplyEnabled()

-- Register ApplyEnabled with the chat module's centralized after-refresh
-- hook list so it runs after every chat refresh (settings change, profile
-- switch, profile import, etc.).
table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
