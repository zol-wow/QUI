-- Behavioral regression for the keystone completion reminder (Lua 5.1).
local frames, timers = {}, {}
local completion, ownedLevel
local ownedReads = 0
local now = 0
UIParent = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
C_AddOns = { IsAddOnLoaded = function() return false end }
C_ChallengeMode = { GetChallengeCompletionInfo = function() return completion end }
C_MythicPlus = { GetOwnedKeystoneLevel = function()
    ownedReads = ownedReads + 1
    return ownedLevel
end }
C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { at = now + delay, callback = callback }
end }

function CreateFrame()
    local frame = { events = {}, scripts = {}, shown = true }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:CreateFontString()
        local text = {}
        function text:SetAllPoints() end
        function text:SetFont(font, size) self.font, self.size = font, size end
        function text:SetTextColor(...) self.color = { ... } end
        function text:SetText(value) self.value = value end
        self.text = text
        return text
    end
    frames[#frames + 1] = frame
    return frame
end

local ns = { Helpers = { CreateDBGetter = function() return function() return {} end end } }
assert(loadfile("modules/dungeon/keystone.lua"))("QUI", ns)

local function dispatch(event)
    local count = #frames
    for index = 1, count do
        local frame = frames[index]
        if frame.events[event] then frame.scripts.OnEvent(frame, event) end
    end
end

local function advance(seconds)
    local target = now + seconds
    while true do
        local nextIndex
        for index, timer in ipairs(timers) do
            if timer.at <= target and (not nextIndex or timer.at < timers[nextIndex].at) then
                nextIndex = index
            end
        end
        if not nextIndex then break end
        local timer = table.remove(timers, nextIndex)
        now = timer.at
        timer.callback()
    end
    now = target
end

local function flushTimers()
    advance(1)
end

local function visibleReminder()
    for _, frame in ipairs(frames) do
        if frame.shown and frame.text and frame.text.value == "Re-roll key?" then
            return frame
        end
    end
end

local function finish(level, owned, practice, onTime)
    completion = level and { level = level, practiceRun = practice, onTime = onTime } or nil
    ownedLevel = owned
    dispatch("CHALLENGE_MODE_COMPLETED")
    flushTimers()
    return visibleReminder()
end

local reminder = assert(finish(10, 10, false, true),
    "equal completed and owned key levels must show Re-roll key?")
assert(reminder.text.size >= 30, "reminder must use large lettering")
assert(finish(12, 10, false, true), "higher completed key must show the reminder")
assert(finish(10, 10, false, false), "overtime completion still meets the requested comparison")
assert(not finish(9, 10), "lower completed key must not show the reminder")
assert(not finish(10, nil), "no owned key must not show the reminder")
assert(not finish(10, 0), "invalid owned level must not show the reminder")
assert(not finish(nil, 10), "missing completion data must not show the reminder")
assert(not finish(0, 10), "invalid completion level must not show the reminder")
assert(not finish(10, 10, true), "practice runs must not show the reminder")

-- Compare the updated bag key, not its pre-completion level.
completion, ownedLevel = { level = 10 }, 10
dispatch("CHALLENGE_MODE_COMPLETED")
ownedLevel = 11
flushTimers()
assert(not visibleReminder(), "an upgraded owned key must suppress the reminder")

reminder = assert(finish(10, 10))
reminder.scripts.OnUpdate(reminder, 14)
assert(visibleReminder(), "reminder must remain visible long enough to read")
reminder.scripts.OnUpdate(reminder, 1)
assert(not visibleReminder(), "reminder must expire")

for _, event in ipairs({ "CHALLENGE_MODE_START", "CHALLENGE_MODE_RESET", "PLAYER_ENTERING_WORLD" }) do
    assert(finish(10, 10))
    dispatch(event)
    assert(not visibleReminder(), event .. " must clear an old reminder")
    dispatch("CHALLENGE_MODE_COMPLETED")
    dispatch(event)
    flushTimers()
    assert(not visibleReminder(), event .. " must cancel a pending reminder")
end

-- Model an allowed unavailable API result followed by eligible owned-key data.
-- This proves recovery logic; it does not establish native refresh timing.
assert(not finish(17, nil))
ownedLevel = 17
advance(1)
assert(visibleReminder(), "temporarily unavailable owned key must be checked again")

assert(not finish(17, 0))
ownedLevel = 16
advance(1)
assert(visibleReminder(), "zero owned level must recover when an eligible key becomes available")

local reads = ownedReads
assert(not finish(17, nil))
advance(20)
assert(not visibleReminder(), "absent key must never show a reminder")
assert(ownedReads - reads == 5 and #timers == 0, "unavailable key polling must stop after five checks")

reads = ownedReads
assert(not finish(17, 18))
advance(20)
assert(not visibleReminder() and ownedReads - reads == 1,
    "available ineligible key must not be polled or produce a reminder")

assert(not finish(17, nil))
ownedLevel = 18
advance(1)
assert(not visibleReminder(), "a late higher owned key must still suppress the reminder")
advance(20)
assert(#timers == 0, "higher owned key must end polling")

for _, event in ipairs({ "CHALLENGE_MODE_START", "CHALLENGE_MODE_RESET", "PLAYER_ENTERING_WORLD" }) do
    assert(not finish(17, nil))
    reads = ownedReads
    dispatch(event)
    ownedLevel = 17
    advance(10)
    assert(not visibleReminder() and ownedReads == reads,
        event .. " must cancel late-key polling before another API read")
end

-- A newer completion owns the reminder even if an older retry is pending.
assert(not finish(17, nil))
completion, ownedLevel = { level = 16 }, 17
dispatch("CHALLENGE_MODE_COMPLETED")
advance(10)
assert(not visibleReminder(), "an older eligible completion must not override a newer ineligible one")

print("keystone completion reminder regression: ok")
