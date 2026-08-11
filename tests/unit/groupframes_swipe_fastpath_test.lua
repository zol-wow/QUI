-- tests/unit/groupframes_swipe_fastpath_test.lua
-- Run: lua tests/unit/groupframes_swipe_fastpath_test.lua
-- Extracts R.RefreshUpdatedIcons from groupframes_aura_render.lua (between the
-- QUI_TEST_EXTRACT sentinels) and verifies the UNIT_AURA fast path (a pure
-- stack/duration refresh, no element rebuild) reseats the linear swipe bar
-- (StatusBar:SetTimerDuration) on a duration delta, not just the radial
-- cooldown. SetTimerDuration is a snapshot: if it isn't reseated here, the
-- linear fill drains toward the OLD expiration while the countdown number is
-- correct. Also verifies a hidden (radial-mode) swipe bar is left untouched.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("QUI_GroupFrames/groupframes/groupframes_aura_render.lua")
local s = assert(source:find("-- >>> QUI_TEST_EXTRACT RefreshUpdatedIcons", 1, true), "begin sentinel")
local fnStart = assert(source:find("\n", s)) + 1
local nl = assert(source:find("\n%-%- <<< QUI_TEST_EXTRACT RefreshUpdatedIcons", fnStart), "end sentinel")
local fnSource = source:sub(fnStart, nl - 1)

-- factory injects R (table), STATE_KEY (string constant), a unit accessor,
-- a stubbed C_UnitAuras, and ns (core/safecall.lua stub: silent pcall
-- passthrough — Task 45a routed the reseat loop's SetCooldownFromDurationObject
-- / SetTimerDuration calls through ns.SafeCall("sink-forward", ...)) as upvalues
local factory = assert(loadstring(
    "return function(_R, _STATE_KEY, _GetFrameUnit, _CUA, _ns)\nlocal R = _R\nlocal STATE_KEY = _STATE_KEY\nlocal GetFrameUnit = _GetFrameUnit\nlocal C_UnitAuras = _CUA\nlocal ns = _ns\n"
        .. fnSource .. "\nreturn R.RefreshUpdatedIcons\nend",
    "refreshUpdatedIcons"))()

local STATE_KEY = "_quiAuraRender" -- must match groupframes_aura_render.lua's `local STATE_KEY = "_quiAuraRender"`
local durSentinel = { __dur = true }
local CUA = { GetAuraDuration = function() return durSentinel end }
local R = {}
local GetFrameUnit = function(frame) return frame.previewUnit end
local function safeCallStub(_policy, fn, ...) return pcall(fn, ...) end
local function safeCallMethodStub(_policy, obj, name, ...)
    return pcall(function(...) return obj[name](obj, ...) end, ...)
end
local safeCallMethodIfPresentStub = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local ns = { SafeCall = safeCallStub, SafeCallMethod = safeCallMethodStub, SafeCallMethodIfPresent = safeCallMethodIfPresentStub }
local RefreshUpdatedIcons = factory(R, STATE_KEY, GetFrameUnit, CUA, ns)

local function newIcon(instID, swipeShown)
    local icon = {
        _auraInstanceID = instID,
        _shown = true,
        cooldown = { SetCooldownFromDurationObject = function() end },
        _cfgElement = { reverseSwipe = false },
        _swipeBar = {
            _shown = swipeShown,
            IsShown = function(sb) return sb._shown end,
            SetTimerDuration = function(sb, ...) sb.timer = { ... } end,
        },
    }
    function icon:IsShown() return self._shown end
    return icon
end

-- linear icon: swipe bar shown -> must be reseated alongside the radial cd
local icon = newIcon(7, true)
-- radial icon: swipe bar not shown -> must NOT be reseated
local icon2 = newIcon(7, false)

local frame = { previewUnit = "raid1", _shown = true }
function frame:IsShown() return self._shown end
frame[STATE_KEY] = { some = { icons = { icon, icon2 } } }

local frames = { frame }

local ok = RefreshUpdatedIcons(R, frames, 1, "raid1", { 7 })
assert(ok == true, "fast path returns true")

assert(icon._swipeBar.timer ~= nil, "linear swipe bar reseated")
assert(icon._swipeBar.timer[1] == durSentinel, "reseated with duration object")
assert(icon._swipeBar.timer[2] == 0, "immediate = 0")
assert(icon._swipeBar.timer[3] == 1, "direction RemainingTime(1) for non-reverse")

assert(icon2._swipeBar.timer == nil, "non-shown (radial) swipe bar left untouched")

print("PASS: groupframes_swipe_fastpath")
