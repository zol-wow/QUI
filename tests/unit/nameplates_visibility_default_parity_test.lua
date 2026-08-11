local function fail(msg)
    print("FAIL: nameplates_visibility_default_parity_test - " .. msg)
    os.exit(1)
end

local function noop() end

local core = dofile("tools/_addon_env.lua").LoadCore()
local shipped = core.defaults
    and core.defaults.profile
    and core.defaults.profile.nameplates
    and core.defaults.profile.nameplates.cvars
if type(shipped) ~= "table" then
    fail("core/defaults.lua does not expose profile.nameplates.cvars")
end

InCombatLockdown = function() return false end
SetCVar = noop
C_CVar = { SetCVar = noop, SetCVarBitfield = noop }
C_Timer = { After = function(_, fn) fn() end }
CreateFrame = function()
    return { RegisterEvent = noop, UnregisterEvent = noop, SetScript = noop, Hide = noop, Show = noop }
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return { enabled = true } end,
    },
}
assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/cvars.lua"))("QUI_Nameplates", ns)

local NPCVars = ns.QUI_NameplatesCVars
local fromShipped = NPCVars.ResolveUnitVisibility(shipped)
local fromFallback = NPCVars.ResolveUnitVisibility({})

for cvar, fallbackValue in pairs(fromFallback) do
    local shippedValue = fromShipped[cvar]
    if shippedValue ~= fallbackValue then
        fail(("%s: core/defaults.lua resolves to %s but the UNIT_VISIBILITY_CVARS fallback in "
            .. "cvars.lua resolves to %s -- the two default tables have drifted, so a profile "
            .. "missing the key behaves differently from a fresh one")
            :format(cvar, tostring(shippedValue), tostring(fallbackValue)))
    end
end

local count = 0
for _ in pairs(fromFallback) do count = count + 1 end
if count ~= 10 then
    fail("expected 10 visibility CVars, got " .. count)
end

print(("OK: nameplates_visibility_default_parity_test (%d CVars agree across both default tables)")
    :format(count))
