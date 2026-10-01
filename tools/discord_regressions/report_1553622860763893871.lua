-- Behavioral regression for the keystone completion reminder (Lua 5.1).
local frames, timers = {}, {}
local completion, ownedLevel
UIParent = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
C_AddOns = { IsAddOnLoaded = function() return false end }
C_ChallengeMode = { GetChallengeCompletionInfo = function() return completion end }
C_MythicPlus = { GetOwnedKeystoneLevel = function() return ownedLevel end }
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }

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

local function flushTimers()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
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

print("keystone completion reminder regression: ok")
