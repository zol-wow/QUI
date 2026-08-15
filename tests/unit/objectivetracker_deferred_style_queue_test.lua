local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/skinning/gameplay/objectivetracker.lua")

local function extract(name)
    local S = "-- <<< QUI_TEST_EXTRACT " .. name
    local a1 = assert(source:find(S, 1, true), "start sentinel must exist: " .. name)
    local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist: " .. name)
    return source:sub(a1 + #S, a2 - 1)
end

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

local queueChunk = table.concat({
    "local C_Timer, ns = ...",
    extract("deferred_style_queue"),
    "return CreateDeferredStyleQueue",
}, "\n")

local timers
local safeCallPolicies

local function buildQueue(handler)
    timers = {}
    safeCallPolicies = {}
    local fakeTimer = {
        After = function(delay, cb) timers[#timers + 1] = { delay = delay, cb = cb } end,
    }
    local fakeNs = {
        SafeCall = function(policy, fn, ...)
            safeCallPolicies[#safeCallPolicies + 1] = policy
            return pcall(fn, ...)
        end,
    }
    local factory = assert(loadstring(queueChunk, "deferred_style_queue"))(fakeTimer, fakeNs)
    return factory(handler)
end

local function fire()
    local batch = timers
    timers = {}
    for _, t in ipairs(batch) do t.cb() end
end

do
    local calls = {}
    local q = buildQueue(function(f) calls[#calls + 1] = f end)
    local f1, f2 = { name = "f1" }, { name = "f2" }

    q(nil)
    check("nil target schedules nothing", #timers == 0)

    q(f1)
    check("queueing never runs the handler synchronously", #calls == 0)
    check("first target schedules exactly one 0-delay timer",
        #timers == 1 and timers[1].delay == 0)

    q(f2)
    q(f1)
    check("same batch reuses the pending timer", #timers == 1)
    check("handler still deferred before the timer fires", #calls == 0)

    fire()
    check("batch handles each target exactly once",
        #calls == 2 and ((calls[1] == f1 and calls[2] == f2) or (calls[1] == f2 and calls[2] == f1)))

    q(f1)
    check("post-flush queueing schedules a fresh timer", #timers == 1)
    fire()
    check("post-flush batch runs the handler again", #calls == 3 and calls[3] == f1)
end

do
    local count = 0
    local q
    q = buildQueue(function(f)
        count = count + 1
        if count == 1 then q(f) end
    end)
    q({})
    fire()
    check("re-queue during a flush lands in a new batch", count == 1 and #timers == 1)
    fire()
    check("re-queued target is handled once on the next flush", count == 2 and #timers == 0)
end

do
    local handled = {}
    local bad = { name = "bad" }
    local q = buildQueue(function(f)
        if f == bad then error("boom") end
        handled[#handled + 1] = f
    end)
    local g1, g2 = { name = "g1" }, { name = "g2" }
    q(g1)
    q(bad)
    q(g2)
    fire()
    check("a throwing target does not drop its batch-mates", #handled == 2)
    check("flush isolates each target through the best-effort SafeCall policy",
        #safeCallPolicies == 3 and safeCallPolicies[1] == "best-effort-style"
            and safeCallPolicies[2] == "best-effort-style" and safeCallPolicies[3] == "best-effort-style")
end

check("SetState hook routes through the deferred queue",
    source:find('hooksecurefunc(mixin, "SetState", QueueLineIconStyle)', 1, true) ~= nil)
check("UpdateHighlight hook routes through the deferred queue",
    source:find('hooksecurefunc(block, "UpdateHighlight", QueueBlockHighlightRestyle)', 1, true) ~= nil)
check("progress bar hooks route through the deferred queue",
    source:find("hooksecurefunc(pm.mixin, pm.method, QueueProgressBarStyle)", 1, true) ~= nil)

local iconChunk = table.concat({
    "local GetSettings, IsWidgetPoolBlock, Helpers, _G = ...",
    extract("line_icon_style"),
    "return StyleLineIcon",
}, "\n")

local CHECK_COLOR = { 0.2, 0.8, 0.2, 1 }
local BULLET_COLOR = { 0.9, 0.8, 0.1, 1 }

local function newIcon(atlas)
    local icon = {}
    function icon:GetAtlas() return atlas end
    function icon:IsShown() return true end
    function icon:GetVertexColor() return 1, 1, 1, 1 end
    function icon:SetDesaturated(v) self.desaturated = v end
    function icon:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
    return icon
end

local function styleIcon(atlas, secretValues)
    local settings = {
        skinObjectiveTracker = true,
        objectiveTrackerCustomIcons = true,
        objectiveTrackerCheckColor = CHECK_COLOR,
        objectiveTrackerBulletColor = BULLET_COLOR,
    }
    local probed = {}
    local helpers = {
        IsSecretValue = function(v)
            probed[#probed + 1] = v
            return (secretValues and secretValues[v]) == true
        end,
        SafeNumberOrNil = function(v) return type(v) == "number" and v or nil end,
    }
    local style = assert(loadstring(iconChunk, "line_icon_style"))(
        function() return settings end,
        function() return false end,
        helpers,
        {})
    local icon = newIcon(atlas)
    style({ Icon = icon })
    return icon, probed
end

do
    local icon, probed = styleIcon("UI-QuestTracker-Objective-Check")
    check("check atlas is probed for secrecy before styling",
        probed[1] == "UI-QuestTracker-Objective-Check")
    check("plain check atlas recolors to the check color",
        icon.vertex ~= nil and icon.vertex[1] == CHECK_COLOR[1] and icon.vertex[2] == CHECK_COLOR[2]
            and icon.vertex[3] == CHECK_COLOR[3] and icon.vertex[4] == CHECK_COLOR[4])
    check("plain check atlas desaturates the icon", icon.desaturated == true)
end

do
    local icon = styleIcon("ui-questtracker-objective-nub")
    check("plain nub atlas recolors to the bullet color",
        icon.vertex ~= nil and icon.vertex[1] == BULLET_COLOR[1] and icon.vertex[2] == BULLET_COLOR[2]
            and icon.vertex[3] == BULLET_COLOR[3])
end

do
    local icon = styleIcon("ui-questtracker-objective-fail")
    check("unmatched atlas keeps its native look",
        icon.vertex == nil and icon.desaturated == nil)
end

do
    local secretAtlas = "secret-check-atlas"
    local icon, probed = styleIcon(secretAtlas, { [secretAtlas] = true })
    check("secret atlas is probed", probed[1] == secretAtlas)
    check("secret atlas is never styled even when it names a check",
        icon.vertex == nil and icon.desaturated == nil)
end

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("OK: objectivetracker_deferred_style_queue_test")
