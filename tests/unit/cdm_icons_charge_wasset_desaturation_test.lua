-- tests/unit/cdm_icons_charge_wasset_desaturation_test.lua
-- Run: lua tests/unit/cdm_icons_charge_wasset_desaturation_test.lua
--
-- Regression: a multi-charge spell (e.g. Putrefy) whose recharge reports
-- C_Spell.GetSpellCooldown().isActive == true while charges are still banked
-- must NOT desaturate. The cdInfo.isActive == false heuristic is wrong for
-- this class of charge spell; the authoritative, secret-safe signal is the
-- Blizzard mirror child's NeverSecret wasSetFromCharges flag (set iff
-- currentCharges > 0). currentCharges itself is secret in combat.

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local chargeDuration = { token = "charge-duration" }

-- Putrefy-style: GetSpellCooldown reports the recharge AS an active cooldown
-- (isActive == true) even with charges banked. The cdInfo.isActive == false
-- fallback therefore CANNOT keep it saturated — only wasSetFromCharges can.
local PUTREFY = 1247378

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {
                    essential = {
                        desaturateOnCooldown = true,
                    },
                }
            end
        end,
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        SafeToNumber = function(value) return value end,
        CanAccessTable = function(tbl) return type(tbl) == "table" end,
    },
    Addon = {
        db = {
            profile = { ncdm = {} },
            char = { ncdm = {} },
        },
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        IsSafeNumeric = function(value) return type(value) == "number" end,
    },
    CDMSources = {
        QuerySpellUsable = function() return true, false end,
        QuerySpellCharges = function()
            error("desaturation path must not query spell charges (currentCharges is secret)")
        end,
        QuerySpellCooldown = function(spellID)
            if spellID == PUTREFY then
                -- Recharge reported as an active cooldown.
                return {
                    startTime = GetTime(),
                    duration = 10,
                    isActive = true,
                    isOnGCD = false,
                }
            end
            return nil
        end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        GetSpellTexture = function() return nil end,
        ResolveMacro = function() return nil end,
        GetEntryTexture = function() return nil end,
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function() return nil end,
        ResolveCooldownState = function()
            local state = {
                cooldownID = 8203,
                viewerCategory = "essential",
                isActive = true,
                resolvedMode = "cooldown",
            }
            return {
                mode = "cooldown",
                active = true,
                isActive = true,
                durObj = chargeDuration,
                sourceID = "mirror:8203:" .. PUTREFY,
                spellID = PUTREFY,
                mirrorBacked = true,
                -- Recharge IS rolling and reported as on cooldown.
                isOnCooldown = true,
                gcdOnly = false,
                cooldownInfo = {
                    startTime = GetTime(),
                    duration = 10,
                    isActive = true,
                    isOnGCD = false,
                },
                cooldownInfoActive = true,
                cooldownInfoOnGCD = false,
                mirrorCooldownID = 8203,
                mirrorCategory = "essential",
                cooldownID = 8203,
                category = "essential",
                state = state,
                mirrorState = state,
            }
        end,
    },
    CDMIconFactory = {
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
    },
    CDMRuntimeStore = {
        SetIconState = noop,
    },
    _OwnedGlows = {
        ClearPandemicState = function(icon)
            if icon and icon.PandemicGlow then
                icon.PandemicGlow:SetAlpha(0)
            end
        end,
    },
}

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local function makeIcon()
    local desaturated
    local icon = {
        Cooldown = {
            SetCooldownFromDurationObject = noop,
            SetReverse = noop,
            SetSwipeTexture = noop,
            Clear = noop,
        },
        Icon = {
            SetDesaturated = function(_, value) desaturated = value end,
            SetDesaturation = function(_, value) desaturated = value end,
            SetVertexColor = noop,
        },
        PandemicGlow = { SetAlpha = noop },
        -- Mirror binding so GetIconMirrorState resolves to our injected state.
        _blizzMirrorCooldownID = 8203,
        _blizzMirrorCategory = "essential",
        _blizzMirrorStateCooldownID = 8203,
        _blizzMirrorStateCategory = "essential",
        _spellEntry = {
            id = PUTREFY,
            spellID = PUTREFY,
            kind = "cooldown",
            type = "spell",
            viewerType = "essential",
            name = "Putrefy",
            -- Deliberately NOT setting hasCharges: wasSetFromCharges must keep
            -- the icon saturated independent of the static entry flag.
        },
    }
    return icon, function() return desaturated end
end

-- Case 1: charge cooldown rolling with a charge banked (wasSetFromCharges=true)
-- even though GetSpellCooldown().isActive == true -> stay saturated.
do
    local icon, getDesat = makeIcon()
    icon._blizzMirrorState = { wasSetFromCharges = true }
    local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)
    assert(applied == true, "case1: charge mirror should report an applied cooldown")
    assert(icon._hasCooldownActive == true,
        "case1: recharge should be classified as an active (real) cooldown")
    assert(getDesat() == false,
        "case1: charge spell with banked charges (wasSetFromCharges) must stay saturated even when GetSpellCooldown().isActive == true")
end

-- Case 2: all charges spent (wasSetFromCharges=false) with the spell cooldown
-- active -> the icon must grey out.
do
    local icon, getDesat = makeIcon()
    icon._blizzMirrorState = { wasSetFromCharges = false }
    icon._spellEntry.hasCharges = true
    local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)
    assert(applied == true, "case2: depleted charge mirror should still report an applied cooldown")
    assert(getDesat() == true,
        "case2: a charge spell with no charges banked (wasSetFromCharges=false) and an active cooldown must desaturate")
end

print("OK cdm_icons_charge_wasset_desaturation_test")
