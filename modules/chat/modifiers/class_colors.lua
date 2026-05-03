---------------------------------------------------------------------------
-- QUI Chat Modifier — Class Colors
-- Applies class-color rendering to sender names for events where Blizzard
-- does not auto-color (CHANNEL, SAY, YELL). The mechanism is toggling
-- ChatTypeInfo[event].colorNameByClass — Blizzard's own chat-frame rendering
-- then applies the class color via its built-in pathway. Zero taint surface.
--
-- For events where Blizzard already auto-colors (PARTY, RAID, GUILD, OFFICER,
-- INSTANCE, WHISPER), this modifier is a no-op — the toggle just doesn't
-- change anything since those events already have colorNameByClass = true
-- by default.
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

-- Events where Blizzard does NOT auto-color names; these are the ones we toggle.
local OPT_IN_TYPES = { "CHANNEL", "SAY", "YELL" }

-- Saved original colorNameByClass values per type, used for clean restore.
local SAVED = {}

-- Cache: name (no realm in key) → { class, realm }. Plain table — entries
-- are explicitly cleared on PLAYER_LEAVING_WORLD; weak values would let GC
-- drop the entry tables between pipeline invocations.
local nameToClass = {}

-- ---------------------------------------------------------------------------
-- Cache population
-- ---------------------------------------------------------------------------

local function splitNameRealm(author)
    if not author then return nil, nil end
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

local function recolorBody(msg)
    if not msg or msg == "" then return msg end
    -- Skip if msg already has any |c..|r block (paranoia — don't double-wrap).
    -- We allow some |c blocks (e.g., from URL detection) but skip if any
    -- |c block contains a known cached name.
    for cachedName, info in pairs(nameToClass) do
        if cachedName and info and info.class then
            local colored = colorize(cachedName, info.class, info.realm)
            if colored then
                -- Word-boundary substitution. Lua patterns don't have \b but
                -- %f[set] frontier pattern works for transitions across char classes.
                -- Pattern: a non-word char (or string start), the name, a non-word char (or end).
                local escapedName = cachedName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                local escapedColored = colored:gsub("%%", "%%%%")
                msg = msg:gsub("(%f[%w_])(" .. escapedName .. ")(%f[^%w_])",
                               "%1" .. escapedColored .. "%3")
            end
        end
    end
    return msg
end

-- ---------------------------------------------------------------------------
-- Modifier function
-- ---------------------------------------------------------------------------

local function modifier(msg, info, event)
    if not info then return msg, info end

    -- Always opportunistically populate cache from this event's GUID.
    local name, realm = splitNameRealm(info.author)
    if name and info.guid then
        cacheFromGUID(name, realm, info.guid)
    end

    -- Respect setting toggle (live re-check — cheap, settings is a table read).
    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.modifiers and settings.modifiers.classColors
    if not s or not s.enabled then return msg, info end

    -- Body-text recolor (sub-toggle).
    if s.recolorBodyText then
        msg = recolorBody(msg)
    end

    return msg, info
end

-- ---------------------------------------------------------------------------
-- Apply / restore ChatTypeInfo overrides
-- ---------------------------------------------------------------------------

local OVERRIDES_APPLIED = false

local function captureSaved()
    if next(SAVED) ~= nil then return end
    for i = 1, #OPT_IN_TYPES do
        local t = OPT_IN_TYPES[i]
        if ChatTypeInfo and ChatTypeInfo[t] then
            SAVED[t] = ChatTypeInfo[t].colorNameByClass
        end
    end
end

local function applyOverrides()
    captureSaved()
    for i = 1, #OPT_IN_TYPES do
        local t = OPT_IN_TYPES[i]
        if SetChatColorNameByClass then
            SetChatColorNameByClass(t, true)
        elseif ChatTypeInfo and ChatTypeInfo[t] then
            ChatTypeInfo[t].colorNameByClass = true
        end
    end
    OVERRIDES_APPLIED = true
end

local function restoreOverrides()
    for t, original in pairs(SAVED) do
        if SetChatColorNameByClass then
            SetChatColorNameByClass(t, original and true or false)
        elseif ChatTypeInfo and ChatTypeInfo[t] then
            ChatTypeInfo[t].colorNameByClass = original
        end
    end
    OVERRIDES_APPLIED = false
end

-- ---------------------------------------------------------------------------
-- Registration / live-toggle
-- ---------------------------------------------------------------------------

local REGISTERED = false

function ApplyEnabled()
    local settings = I.GetSettings and I.GetSettings()
    local enabled = settings and settings.modifiers and settings.modifiers.classColors
        and settings.modifiers.classColors.enabled

    if enabled then
        if not REGISTERED then
            Pipeline.Register("class_colors", 100, modifier)
            REGISTERED = true
        end
        if not OVERRIDES_APPLIED then
            applyOverrides()
        end
    else
        if REGISTERED then
            Pipeline.Unregister("class_colors")
            REGISTERED = false
        end
        if OVERRIDES_APPLIED then
            restoreOverrides()
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
