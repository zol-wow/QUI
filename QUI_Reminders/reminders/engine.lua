-- QUI_Reminders/reminders/engine.lua -- turns a boss-mod countdown into "press
-- this defensive now".
--
-- Flow, per boss-mod timer:
--   1. Is the ability one the player opted into for some boss?  (Blizzard's own
--      timeline cannot name its abilities, so with that source every encounter
--      event counts when the option says so.)
--   2. Arm a fire at `duration - leadTime`; a stopped bar disarms it.
--   3. On fire: tank specs only when the boss is on them, skip when a listed
--      defensive is already up, then the first ready entry in this spec's
--      priority list wins.
--   4. Hand the pick to the callout, sound/TTS, chat and the Cooldown Manager
--      glow. Each output is its own switch.
--
-- Ability identity is the spell id the boss mod broadcasts, matched against the
-- union of every opted-in ability. That sidesteps the two encounter-id spaces
-- (journal vs. ENCOUNTER_START) entirely: a spell id belongs to one boss.
local _, ns = ...

local Helpers = ns.Helpers

local R = {}
ns.Reminders = R

local SUBSCRIBER_KEY = "QUI_Reminders"
local GLOW_KEY = "_QUIReminders"
local SEEN_CAP = 400

local GetDB = Helpers.CreateDBGetter("reminders")

local pending = {}      -- barID -> { handle, evt }
local lastFired = {}    -- ability key -> GetTime()
local optedCache, optedDirty = nil, true
local activeEncounter
local subscribed = false
local eventFrame
local glowedIcon, glowTimer

local function IsSecret(value)
    if Helpers and Helpers.IsSecretValue then return Helpers.IsSecretValue(value) end
    local probe = _G.issecretvalue
    return probe ~= nil and probe(value) == true
end

local function Readable(value)
    if IsSecret(value) then return nil end
    return value
end

local function Now()
    if type(GetTime) == "function" then return GetTime() end
    return os.time()
end

local function Defensives() return ns.RemindersDefensives end
local function Callout() return ns.RemindersCallout end

-------------------------------------------------------------------------------
-- Settings views
-------------------------------------------------------------------------------
function R.IsEnabled()
    local db = GetDB()
    return db ~= nil and db.enabled == true
end

local function ContextAllowed()
    local db = GetDB()
    if not db then return false end
    local instanceType
    if type(GetInstanceInfo) == "function" then
        local ok, _, kind = ns.SafeCall("secret-probe", GetInstanceInfo)
        if ok then instanceType = Readable(kind) end
    end
    if instanceType == "party" then return db.inDungeons ~= false end
    if instanceType == "raid" then return db.inRaids ~= false end
    return db.elsewhere == true
end
R.ContextAllowed = ContextAllowed

function R.MarkAbilitiesDirty()
    optedDirty = true
end

-- Union of every opted-in ability across every boss.
local function OptedSpells()
    if optedCache and not optedDirty then return optedCache end
    local set = {}
    local db = GetDB()
    local abilities = db and db.abilities
    if type(abilities) == "table" then
        for _, spells in pairs(abilities) do
            if type(spells) == "table" then
                for spellID, on in pairs(spells) do
                    if on == true then
                        local id = tonumber(spellID)
                        if id then set[id] = true end
                    end
                end
            end
        end
    end
    optedCache = set
    optedDirty = false
    return set
end
R.OptedSpells = OptedSpells

function R.CurrentList()
    local db = GetDB()
    local D = Defensives()
    local specID = D and D.PlayerSpecID and D.PlayerSpecID()
    local priorities = db and db.priorities
    local list = priorities and specID and priorities[specID]
    if type(list) ~= "table" then list = {} end
    return list, specID
end

-------------------------------------------------------------------------------
-- Seen catalogue (account-wide): what boss mods actually broadcast, so the
-- settings page can offer abilities the journal does not list.
-------------------------------------------------------------------------------
local function SeenStore()
    local core = _G.QUI
    local global = core and core.db and core.db.global
    local bucket = global and global.reminders
    if type(bucket) ~= "table" then return nil end
    if type(bucket.seen) ~= "table" then bucket.seen = {} end
    return bucket.seen
end

local function PruneSeen(seen)
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    while count > SEEN_CAP do
        local oldestKey, oldest
        for key, rec in pairs(seen) do
            local at = type(rec) == "table" and tonumber(rec.last) or 0
            if not oldest or at < oldest then oldest, oldestKey = at, key end
        end
        if oldestKey == nil then break end
        seen[oldestKey] = nil
        count = count - 1
    end
end

local function RecordSeen(evt)
    local spellID = evt.spellID
    if type(spellID) ~= "number" then return end
    local seen = SeenStore()
    if not seen then return end
    local rec = seen[spellID]
    if type(rec) ~= "table" then
        rec = { count = 0 }
        seen[spellID] = rec
        PruneSeen(seen)
    end
    rec.count = (tonumber(rec.count) or 0) + 1
    if type(evt.text) == "string" then rec.text = evt.text end
    if type(evt.icon) == "number" or type(evt.icon) == "string" then rec.icon = evt.icon end
    if activeEncounter then rec.encounter = activeEncounter end
    rec.source = evt.source
    rec.last = type(time) == "function" and time() or 0
end
R.RecordSeen = RecordSeen

-------------------------------------------------------------------------------
-- Outputs
-------------------------------------------------------------------------------
local function StopCDMGlow()
    if glowTimer and glowTimer.Cancel then glowTimer:Cancel() end
    glowTimer = nil
    local OG = ns._OwnedGlows
    if glowedIcon and OG and OG.StopGlowWithKey then
        ns.SafeCall("best-effort-style", OG.StopGlowWithKey, glowedIcon, GLOW_KEY)
    end
    glowedIcon = nil
end

local function GlowCDM(pick, duration)
    local OG = ns._OwnedGlows
    if not (OG and OG.FindIconBySpellID and OG.ApplyGlowWithKey) then return false end
    StopCDMGlow()
    local icon = OG.FindIconBySpellID(pick.spellID)
    if not icon then return false end
    local viewerType = OG.GetViewerType and OG.GetViewerType(icon)
    local settings = viewerType and OG.GetViewerSettings and OG.GetViewerSettings(viewerType)
    if type(settings) ~= "table" then
        settings = { glowType = "Pixel Glow", color = { 1, 0.85, 0.2, 1 }, lines = 8, frequency = 0.25, thickness = 2 }
    end
    local ok = ns.SafeCall("best-effort-style", OG.ApplyGlowWithKey, icon, settings, GLOW_KEY)
    if not ok then return false end
    glowedIcon = icon
    if C_Timer and C_Timer.NewTimer then
        glowTimer = C_Timer.NewTimer(duration, StopCDMGlow)
    end
    return true
end

local function AbilityName(evt)
    if type(evt.spellID) == "number" and _G.C_Spell and _G.C_Spell.GetSpellName then
        local ok, name = ns.SafeCall("secret-probe", _G.C_Spell.GetSpellName, evt.spellID)
        name = ok and Readable(name) or nil
        if type(name) == "string" and name ~= "" then return name end
    end
    if type(evt.text) == "string" and evt.text ~= "" then return evt.text end
    return ns.L["Boss ability"]
end

-- What text-to-speech says: the defensive's name, or one phrase the user
-- chose ("defensive") when they would rather not hear a spell name every time.
function R.SpokenText(pick, sound)
    if type(sound) == "table" and sound.ttsMode == "custom" then
        local phrase = sound.ttsText
        if type(phrase) == "string" and phrase:match("%S") then return phrase end
    end
    return pick and pick.name or ""
end

local function Dispatch(pick, evt)
    local db = GetDB()
    local linger = tonumber(db.linger) or 4
    local out = { callout = false, sound = false, chat = false, glow = false }

    local C = Callout()
    if C and C.Show then
        out.callout = C.Show(pick, { duration = linger }) == true
    end

    local A = ns.Announce
    local sound = db.sound
    if A and type(sound) == "table" then
        if sound.mode == "tts" and A.Speak then
            out.sound = A.Speak(R.SpokenText(pick, sound)) == true
        elseif sound.mode == "sound" and A.PlaySound then
            out.sound = A.PlaySound(sound.sound) == true
        end
    end

    local chat = db.chat
    if A and A.Chat and type(chat) == "table" and chat.enabled == true then
        local line = ns.L["%s incoming - using %s"]:format(AbilityName(evt), pick.name or "")
        out.chat = A.Chat(line, chat.channel) == true
    end

    if db.cdmGlow ~= false and pick.spellID then
        out.glow = GlowCDM(pick, linger)
    end
    return out
end
R.Dispatch = Dispatch

-------------------------------------------------------------------------------
-- Gate and fire
-------------------------------------------------------------------------------
-- Returns the chosen entry, or nil with a reason string for diagnostics.
function R.Decide()
    local db = GetDB()
    local D = Defensives()
    if not (db and D) then return nil, "unavailable" end

    if db.onlyWhenTanking ~= false and D.PlayerRole() == "TANK" then
        if D.IsTankingBoss() == false then return nil, "not-tanking" end
    end

    local list = R.CurrentList()
    if #list == 0 then return nil, "empty-list" end

    if db.skipWhenCovered ~= false and D.IsCovered(list) == true then
        return nil, "covered"
    end

    local pick = D.Pick(list)
    if not pick then return nil, "nothing-ready" end
    return pick
end

local function Fire(evt)
    local db = GetDB()
    if not db then return end
    local key = evt.spellID or evt.barID
    local now = Now()
    local window = math.max(tonumber(db.linger) or 4, 2)
    if key and lastFired[key] and (now - lastFired[key]) < window then return end

    local pick = R.Decide()
    if not pick then return end
    if key then lastFired[key] = now end
    Dispatch(pick, evt)
end
R.Fire = Fire

local function Cancel(barID)
    local entry = pending[barID]
    if not entry then return end
    if entry.handle and entry.handle.Cancel then entry.handle:Cancel() end
    pending[barID] = nil
end

local function CancelAll()
    for barID in pairs(pending) do Cancel(barID) end
end

local function ShouldHandle(evt)
    if not R.IsEnabled() or not ContextAllowed() then return false end
    local db = GetDB()
    if evt.source == "timeline" and evt.secretIdentity then
        return db.timelineAllEvents ~= false
    end
    if type(evt.spellID) ~= "number" then return false end
    return OptedSpells()[evt.spellID] == true
end
R.ShouldHandle = ShouldHandle

local function OnTimer(evt)
    RecordSeen(evt)
    if not ShouldHandle(evt) then return end
    Cancel(evt.barID)
    local lead = tonumber(GetDB().leadTime) or 3
    local delay = (tonumber(evt.duration) or 0) - lead
    if delay <= 0 then
        Fire(evt)
        return
    end
    local handle
    if C_Timer and C_Timer.NewTimer then
        handle = C_Timer.NewTimer(delay, function()
            pending[evt.barID] = nil
            Fire(evt)
        end)
    end
    pending[evt.barID] = { handle = handle, evt = evt, fireAt = Now() + delay }
end

local function OnTimerStop(evt)
    Cancel(evt.barID)
end

local function OnMessage(evt)
    RecordSeen(evt)
    if not ShouldHandle(evt) then return end
    if GetDB().fireOnMessages == false then return end
    Fire(evt)
end

local function OnReset()
    CancelAll()
end

local HANDLERS = {
    onTimer = OnTimer,
    onTimerStop = OnTimerStop,
    onMessage = OnMessage,
    onReset = OnReset,
}
R.Handlers = HANDLERS

function R.PendingCount()
    local n = 0
    for _ in pairs(pending) do n = n + 1 end
    return n
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
local function OnGameEvent(_, event, arg1)
    if event == "ENCOUNTER_START" then
        activeEncounter = tonumber(Readable(arg1))
    elseif event == "ENCOUNTER_END" then
        activeEncounter = nil
        CancelAll()
        StopCDMGlow()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        lastFired = {}
    end
end

local function EnsureEventFrame()
    if eventFrame or type(CreateFrame) ~= "function" then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:SetScript("OnEvent", OnGameEvent)
end

function R.Refresh()
    local db = GetDB()
    local bus = ns.BossMods
    optedDirty = true
    if bus and bus.SetPreferredSource then
        bus.SetPreferredSource(db and db.source or "auto")
    end
    if db and db.enabled == true then
        EnsureEventFrame()
        if bus and not subscribed then
            subscribed = bus.Subscribe(SUBSCRIBER_KEY, HANDLERS) == true
        end
    else
        if bus and subscribed then
            bus.Unsubscribe(SUBSCRIBER_KEY)
            subscribed = false
        end
        CancelAll()
        StopCDMGlow()
        local C = Callout()
        if C and C.Hide and not (C.IsPreviewActive and C.IsPreviewActive()) then C.Hide() end
    end
    local C = Callout()
    if C and C.Refresh then C.Refresh() end
end

function R.IsSubscribed()
    return subscribed
end

function R.ActiveEncounter()
    return activeEncounter
end

-- `/qui reminders test`: run the decision against the live priority list and
-- show the result, ignoring context and boss gates.
function R.Test()
    local D = Defensives()
    if not D then return nil, "unavailable" end
    local list = R.CurrentList()
    if #list == 0 then return nil, "empty-list" end
    local pick = D.Pick(list)
    if not pick then return nil, "nothing-ready" end
    Dispatch(pick, { source = "test", text = ns.L["Test"] })
    return pick
end

-- Layout Mode, the settings page and other suite files reach these through
-- ns.Reminders; nothing is exported on _G.
function R.TogglePreview(on)
    local C = Callout()
    if not C then return nil end
    if on == nil then return C.TogglePreview() end
    C.SetPreview(on)
    return on
end

-- Profile switches and selective imports re-run every registered refresh.
if ns.Registry and type(ns.Registry.Register) == "function" then
    ns.Registry:Register("reminders", {
        refresh = R.Refresh,
        priority = 60,
        group = "qol",
        importCategories = { "reminders" },
    })
end
if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        local C = Callout()
        if C and C.GetFrame then C.GetFrame() end
        R.Refresh()
    end)
end
