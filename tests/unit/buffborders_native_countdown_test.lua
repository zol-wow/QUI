-- tests/unit/buffborders_native_countdown_test.lua
-- Run: lua tests/unit/buffborders_native_countdown_test.lua
--
-- Regression guard for inconsistent buff/debuff duration (esp. flasks).
--
-- 12.0 aura timing is secret in combat: C_UnitAuras.GetUnitAuras fields
-- (expirationTime/duration) are ConditionalSecretContents, and
-- LuaDurationObject:GetRemainingDuration() returns a secret number in combat
-- (see cdm_bar_renderer reference). A Lua-side duration renderer therefore
-- cannot read or format the remaining time during combat -- it freezes at a
-- stale value ("duration plainly wrong") or blanks ("no duration"). Long auras
-- like flasks expose it because they span many combat transitions with no
-- per-aura structural refresh to heal the stale state.
--
-- Correct approach (matches CDM icons, cdm_icon_factory.lua): render duration
-- ENTIRELY via Blizzard's C-side cooldown countdown -- SetHideCountdownNumbers
-- (false) fed by SetCooldownFromDurationObject. The C-side renderer formats
-- secret numbers natively. No QUI Lua timer / FormatDuration / readability flag.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function sliceFunction(source, signature)
    local startPos = source:find(signature, 1, true)
    assert(startPos, signature .. " must exist in buffborders.lua")
    local nextFn = source:find("\nlocal function ", startPos + 1, true)
    return source:sub(startPos, nextFn or #source)
end

local source = readFile("QUI_ActionBars/actionbars/buffborders.lua")

-- The secret-fragile custom Lua duration renderer must be gone.
for _, dead in ipairs({
    "local function FormatDuration",  -- custom Lua formatter (can't format secret values)
    "sharedDurationTimer",            -- the 0.2s Lua timer that froze/blanked
    "EnsureDurationText",             -- the custom duration FontString
    "_quiUseNativeDuration",          -- structural-time readability flag (stale across combat)
}) do
    assert(not source:find(dead, 1, true),
        "buffborders must not keep the Lua-side duration renderer (" .. dead
        .. "): it cannot format secret combat durations and freezes/blanks for "
        .. "long auras like flasks. Use Blizzard's C-side countdown instead.")
end

-- Native C-side countdown must stay enabled (never hidden).
local cfgBody = sliceFunction(source, "local function ConfigureAuraCooldownFrame")
assert(cfgBody:find("SetHideCountdownNumbers", 1, true) and cfgBody:find("false", 1, true),
    "ConfigureAuraCooldownFrame must enable Blizzard's native countdown (SetHideCountdownNumbers(false))")

-- The cooldown must still be driven from the aura (so the native countdown has
-- data to render).
local styleBody = sliceFunction(source, "local function StyleHeaderChildren")
assert(styleBody:find("ApplyCooldownFromAura", 1, true),
    "StyleHeaderChildren must apply the aura cooldown so the native countdown renders")
assert(not styleBody:find("child.Cooldown.SetHideCountdownNumbers", 1, true),
    "StyleHeaderChildren must not re-toggle the native countdown on the child (that "
    .. "override, keyed on a structural-time readability flag, is what broke flask "
    .. "durations); SetHideCountdownNumbers(false) lives only in ConfigureAuraCooldownFrame")

print("OK: buffborders_native_countdown_test")
