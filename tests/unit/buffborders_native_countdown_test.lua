-- tests/unit/buffborders_native_countdown_test.lua
-- Run: lua tests/unit/buffborders_native_countdown_test.lua
--
-- Regression guard for inconsistent buff/debuff duration (esp. flasks).
--
-- 12.0 aura timing is secret in combat: C_UnitAuras.GetUnitAuras fields
-- (expirationTime/duration) are ConditionalSecretContents and a LuaDurationObject
-- returns a secret number in combat. A Lua-side duration renderer therefore
-- cannot read/format the remaining time during combat -- it freezes stale or
-- blanks. Long auras like flasks expose it across many combat transitions.
--
-- After the E4 unification the live buff/debuff duration is rendered entirely by
-- the SHARED secure CustomAuraContainer + QUI.AuraSkin: the container drives the
-- aura DATA C-side and AuraSkin wires a duration FontString via SetDurationText
-- with NO Lua formatter (Blizzard falls back to its C-side
-- DefaultAuraDurationFormatter, which formats secret numbers natively). So
-- buffborders.lua must carry NO Lua-side aura-duration renderer of its own.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_ActionBars/actionbars/buffborders.lua")

-- No secret-fragile custom Lua duration renderer for live auras.
for _, dead in ipairs({
    "FormatDuration",        -- custom Lua formatter (can't format secret values)
    "sharedDurationTimer",   -- a Lua timer that froze/blanked
    "EnsureDurationText",    -- a custom aura duration FontString
    "_quiUseNativeDuration", -- structural-time readability flag (stale across combat)
    "GetRemainingDuration",  -- reading the secret remaining time in Lua
    "ApplyCooldownFromAura", -- the old per-button Lua aura-cooldown driver (now the container's job)
}) do
    assert(not source:find(dead, 1, true),
        "buffborders must not keep a Lua-side aura-duration renderer (" .. dead
        .. "): live aura duration is owned C-side by the CustomAuraContainer + AuraSkin "
        .. "(SetDurationText, no Lua formatter). Secret combat durations format C-side only.")
end

-- buffborders does not read any secret aura field for the live display: it never
-- calls C_UnitAuras.GetUnitAuras itself (the container does, C-side).
assert(not source:find("C_UnitAuras.GetUnitAuras", 1, true),
    "buffborders.lua must NOT read auras in Lua (GetUnitAuras): the secure container reads them C-side")

-- Temp weapon enchants (NOT auras -- GetWeaponEnchantInfo) also render fully
-- engine-side now: they fold into the buff container via PTR4
-- AddItemEnchantment (AuraSkin.ConfigureEnchantments), so buffborders.lua must
-- carry NO Lua-side SetCooldown call for them either (the old separate
-- insecure strip drove its own Cooldown widget; that machinery is gone).
assert(not source:find("SetCooldown", 1, true),
    "buffborders.lua must not drive any Cooldown widget in Lua: live aura AND "
    .. "temp-enchant countdowns are both engine-owned now (CustomAuraContainer / AddItemEnchantment)")

print("OK: buffborders_native_countdown_test")
