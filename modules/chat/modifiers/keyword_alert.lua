---------------------------------------------------------------------------
-- QUI Chat Modifier — Keyword Alert
-- Highlights chat messages matching user-configured keywords, with an
-- optional sound alert via LSM. Runs on the custom display's capture path.
--
-- Triggers (each individually toggleable):
--   * User-supplied keywords list
--   * Own character name (default on)
--   * Own first name (default off; only fires when the name has a space)
--   * Own guild name (default off; only fires when in a guild)
--
-- Match: case-insensitive substring (string.find with plain=true on
-- lowercased copies of msg and trigger).
--
-- Highlight: the matched substring is wrapped with |c<colorhex>...|r.
-- Sound: PlaySoundFile with LSM:Fetch result if available, else literal path.
-- No tab flash: the custom tabs' unread badges serve that role.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: keyword_alert.lua loaded before chat.lua. Check chat.xml — chat.lua must precede keyword_alert.lua.")

local Helpers = ns.Helpers

-- Optional dependency. The "true" silent flag suppresses the LibStub error
-- if LibSharedMedia-3.0 is not loaded; we fall back to the literal sound
-- path on PlaySoundFile, which accepts both LSM names and FilePath strings.
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function IsChatMessagingLockedDown()
    return I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()
end

local function IsCombatLockedDown()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

-- Strip "-Realm" suffix.
local function bareName(author)
    if IsSecret(author) then return nil end
    if type(author) ~= "string" or author == "" then return nil end
    local hyphen = author:find("-", 1, true)
    if hyphen then return author:sub(1, hyphen - 1) end
    return author
end

-- Convert {r,g,b,a} floats (0..1) to "aarrggbb" hex used by |c color codes.
local function colorHex(c)
    if type(c) ~= "table" then return "ff34d399" end  -- mint fallback
    local r = math.floor(((c[1] or 0)) * 255 + 0.5)
    local g = math.floor(((c[2] or 0)) * 255 + 0.5)
    local b = math.floor(((c[3] or 0)) * 255 + 0.5)
    local a = math.floor(((c[4] or 1)) * 255 + 0.5)
    return string.format("%02x%02x%02x%02x", a, r, g, b)
end

-- Escape Lua-pattern magic characters so we can use plain string.find with
-- plain=true on the lowercased haystack/needle. (We use plain=true below;
-- this helper is reserved in case we ever switch to non-plain matching.)

-- ---------------------------------------------------------------------------
-- Player identity (lazy — cached after first PLAYER_LOGIN run)
-- ---------------------------------------------------------------------------

local playerName       -- "Foo Bar"
local playerFirstName  -- "Foo" if name has a space, else nil
local playerGuildName  -- guild name if in a guild, else nil

local function refreshIdentity()
    playerName = UnitName("player")
    playerFirstName = nil
    if type(playerName) == "string" then
        local sp = playerName:find(" ", 1, true)
        if sp then
            playerFirstName = playerName:sub(1, sp - 1)
        end
    end
    playerGuildName = GetGuildInfo and GetGuildInfo("player") or nil
end

-- ---------------------------------------------------------------------------
-- Modifier
-- ---------------------------------------------------------------------------

-- Build the trigger list from settings + identity. Returns array of strings.
-- Empty/nil triggers are filtered out.
local function buildTriggers(s)
    local list = {}
    if s.keywords then
        for i = 1, #s.keywords do
            local kw = s.keywords[i]
            if type(kw) == "string" and kw ~= "" then
                list[#list + 1] = kw
            end
        end
    end
    if s.includeOwnName and type(playerName) == "string" and playerName ~= "" then
        list[#list + 1] = playerName
    end
    if s.includeFirstName and type(playerFirstName) == "string" and playerFirstName ~= "" then
        list[#list + 1] = playerFirstName
    end
    if s.includeGuildName and type(playerGuildName) == "string" and playerGuildName ~= "" then
        list[#list + 1] = playerGuildName
    end
    return list
end

-- Highlight every (case-insensitive) occurrence of `trigger` in `msg` by
-- wrapping the matched substrings with |c<hex>...|r. Preserves the original
-- casing of the matched substring (we only lowercase for the search).
-- Returns newMsg, matched (boolean).
local function highlightTrigger(msg, trigger, hex)
    if IsSecret(msg) or IsSecret(trigger) then
        return msg, false
    end
    if type(msg) ~= "string" or msg == "" or type(trigger) ~= "string" or trigger == "" then
        return msg, false
    end
    local lowerMsg     = msg:lower()
    local lowerTrigger = trigger:lower()
    local triggerLen   = #trigger
    local pos = 1
    local out = {}
    local matched = false
    while true do
        local s, e = lowerMsg:find(lowerTrigger, pos, true)
        if not s then
            out[#out + 1] = msg:sub(pos)
            break
        end
        matched = true
        if s > pos then
            out[#out + 1] = msg:sub(pos, s - 1)
        end
        out[#out + 1] = "|c" .. hex .. msg:sub(s, e) .. "|r"
        pos = e + 1
        if pos > #msg then break end
        -- Safety: triggerLen 0 would loop forever; guard above ensures >=1.
        if triggerLen == 0 then break end
    end
    if matched then
        return table.concat(out), true
    end
    return msg, false
end

-- Gates + highlight only. Sole caller is ProcessForCapture (the capture
-- path), which adds the sound side effect; no tab flash (the custom tabs'
-- unread badges serve that role).
-- Split into link spans (|H...|h...|h, kept verbatim) and plain text. A
-- trigger matching inside link DATA corrupts the hyperlink (e.g. a numeric
-- keyword inside a waypoint payload), so highlighting only runs on the
-- plain segments. Link LABELS are skipped too — an intact link beats a
-- highlighted-but-broken one.
local function highlightOutsideLinks(msg, trigger, hex)
    if type(msg) ~= "string" or not msg:find("|H", 1, true) then
        return highlightTrigger(msg, trigger, hex)
    end
    local out = {}
    local pos = 1
    local matched = false
    while true do
        local s, e = msg:find("|H.-|h.-|h", pos)
        if not s then
            local seg, hit = highlightTrigger(msg:sub(pos), trigger, hex)
            out[#out + 1] = seg
            matched = matched or hit
            break
        end
        if s > pos then
            local seg, hit = highlightTrigger(msg:sub(pos, s - 1), trigger, hex)
            out[#out + 1] = seg
            matched = matched or hit
        end
        out[#out + 1] = msg:sub(s, e) -- link span verbatim
        pos = e + 1
        if pos > #msg then break end
    end
    return table.concat(out), matched
end

local function GateAndHighlight(msg, author)
    if IsSecret(msg) or IsChatMessagingLockedDown() then return msg, false end
    if not msg or type(msg) ~= "string" or msg == "" then return msg, false end
    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.modifiers and settings.modifiers.keywordAlert
    if not s or not s.enabled then return msg, false end
    if s.skipSelf and author and playerName then
        if not IsSecret(author) and not IsSecret(playerName) and bareName(author) == playerName then
            return msg, false
        end
    end
    local triggers = buildTriggers(s)
    if #triggers == 0 then return msg, false end
    local hex = colorHex(s.highlightColor)
    local triggered = false
    for i = 1, #triggers do
        local newMsg, hit = highlightOutsideLinks(msg, triggers[i], hex)
        if hit then
            msg = newMsg
            triggered = true
        end
    end
    return msg, triggered
end

-- Sound-only side effect. Extracted so the store-path (ProcessForCapture)
-- can fire it while suppressed without duplicating the LSM resolution logic.
local function PlayAlertSound(s)
    local soundFile = s and s.soundFile
    local resolved = (LSM and soundFile) and LSM:Fetch("sound", soundFile) or soundFile
    if resolved and PlaySoundFile then
        pcall(PlaySoundFile, resolved, "Master")
    end
end

-- ---------------------------------------------------------------------------
-- Capture-path export
-- ---------------------------------------------------------------------------

ns.QUI.Chat.KeywordAlert = ns.QUI.Chat.KeywordAlert or {}
-- Capture-path entry. Highlights matches and owns the keyword sound — the
-- capture path runs whenever the chat module is enabled (pre-PEW login
-- window included), and it is the only message path. Tab flash is
-- intentionally omitted: the custom tabs' unread badges serve that role.
function ns.QUI.Chat.KeywordAlert.ProcessForCapture(msg, author)
    local newMsg, triggered = GateAndHighlight(msg, author)
    if triggered then
        -- NOTE: wider scope than the old rendered-frame pipeline (which
        -- covered only the 12 conversational events): ANY captured line can
        -- keyword-ding, including whispers. Deliberate — keyword alerts are
        -- most valuable on whispers.
        local s = (I.GetSettings and I.GetSettings() or {}).modifiers
        s = s and s.keywordAlert
        if s then PlayAlertSound(s) end
    end
    return newMsg
end

-- ---------------------------------------------------------------------------
-- Registration / live-toggle
-- ---------------------------------------------------------------------------

local function ApplyEnabled()
    -- Refresh identity each apply so guild changes / character name on first
    -- login propagate without requiring a /reload. (Enablement itself is
    -- checked per-message inside GateAndHighlight — nothing to register.)
    refreshIdentity()
end

-- Initial application. Defensive no-op if QUI.db isn't ready at file-load
-- time (returns early because settings is nil); PLAYER_LOGIN guarantees the
-- actual activation once AceDB has been constructed in OnInitialize.
ApplyEnabled()

-- ---------------------------------------------------------------------------
-- PLAYER_LOGIN re-evaluation (after AceDB initializes)
-- ---------------------------------------------------------------------------

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
loginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ApplyEnabled()
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- Guild membership changed; refresh identity so includeGuildName
        -- picks up the new (or absent) guild name on next message.
        refreshIdentity()
    end
end)

-- Register ApplyEnabled with the chat module's centralized after-refresh
-- hook list so it runs after every chat refresh (settings change, profile
-- switch, profile import, etc.).
table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
