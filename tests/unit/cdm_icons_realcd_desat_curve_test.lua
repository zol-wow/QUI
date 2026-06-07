-- tests/unit/cdm_icons_realcd_desat_curve_test.lua
-- Run: lua tests/unit/cdm_icons_realcd_desat_curve_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame C_Timer C_CurveUtil
--
-- The essential-icon saturation must be driven by the real-CD-only
-- (ignoreGCD) DurationObject through a step curve into Texture:SetDesaturation,
-- NOT by the Lua-decoded resolved mode via SetDesaturated(true). The mode is
-- only re-decided on the next SPELL_UPDATE_COOLDOWN, so a mode-gated
-- SetDesaturated lagged the real-CD->GCD transition by up to a GCD (icon stayed
-- dark seconds after the real cooldown ended). The curve binding is re-sampled
-- C-side every frame: dark while the real CD rolls, bright the instant it hits
-- zero, with the secret value never read in Lua.
--
-- The charge carve-out (wasSetFromCharges) and the desaturateOnCooldown gate
-- must still suppress the curve drive and keep the icon saturated.

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

-- Guardian Druid Thrash: a short real CD that, under Incarnation, is held
-- "active" by constant GCD from other abilities. The reference case for the
-- saturation lag this curve drive fixes.
local THRASH = 77758
local ITEM_ID = 241288
local ITEM_USE_SPELL = 91001

local fullDuration = { token = "full-duration" }

-- The real-CD-only (ignoreGCD) DurationObject. Its curve evaluation is the
-- secret-safe value that must flow into SetDesaturation.
local DESAT_FROM_CURVE = { token = "desat-from-real-cd-curve" }
local ITEM_DESAT_FROM_CURVE = { token = "item-desat-from-item-cd-curve" }
local realCdDurObj = {
    EvaluateRemainingPercent = function(_, curve)
        assert(curve ~= nil, "EvaluateRemainingPercent must receive the desat step curve")
        return DESAT_FROM_CURVE
    end,
}
local itemCdDurObj = {
    EvaluateRemainingPercent = function(_, curve)
        assert(curve ~= nil, "item cooldown desaturation must receive the desat step curve")
        return ITEM_DESAT_FROM_CURVE
    end,
}

local curveAddPoints = {}
C_CurveUtil = {
    CreateCurve = function()
        return {
            AddPoint = function(_, x, y)
                curveAddPoints[#curveAddPoints + 1] = { x = x, y = y }
            end,
        }
    end,
}

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
            if spellID == THRASH then
                return {
                    startTime = GetTime(),
                    duration = 6,
                    isActive = true,
                    isOnGCD = false,
                }
            end
            return nil
        end,
        -- Real-CD-only duration object query. ignoreGCD must be true so the
        -- returned remaining excludes the incidental GCD.
        QuerySpellCooldownDuration = function(spellID, ignoreGCD)
            assert(ignoreGCD == true,
                "real-CD desaturation must query GetSpellCooldownDuration with ignoreGCD=true")
            if spellID == THRASH then
                return realCdDurObj
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
        ResolveCooldownState = function(context)
            local entry = context and context.entry
            if entry and entry.id == ITEM_ID then
                return {
                    mode = "item-cooldown",
                    active = true,
                    isActive = true,
                    durObj = itemCdDurObj,
                    sourceID = "item-duration:" .. ITEM_ID,
                    spellID = ITEM_USE_SPELL,
                    isOnCooldown = true,
                    gcdOnly = false,
                }
            end
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
                durObj = fullDuration,
                sourceID = "mirror:8203:" .. THRASH,
                spellID = THRASH,
                mirrorBacked = true,
                isOnCooldown = true,
                gcdOnly = false,
                cooldownInfo = {
                    startTime = GetTime(),
                    duration = 6,
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
    local desatAmount, desatBool
    local icon = {
        Cooldown = {
            SetCooldownFromDurationObject = noop,
            SetReverse = noop,
            SetSwipeTexture = noop,
            Clear = noop,
        },
        Icon = {
            SetDesaturated = function(_, value) desatBool = value end,
            SetDesaturation = function(_, value) desatAmount = value end,
            SetVertexColor = noop,
        },
        PandemicGlow = { SetAlpha = noop },
        _blizzMirrorCooldownID = 8203,
        _blizzMirrorCategory = "essential",
        _blizzMirrorStateCooldownID = 8203,
        _blizzMirrorStateCategory = "essential",
        _spellEntry = {
            id = THRASH,
            spellID = THRASH,
            kind = "cooldown",
            type = "spell",
            viewerType = "essential",
            name = "Thrash",
        },
    }
    return icon,
        function() return desatAmount end,
        function() return desatBool end
end

local function makeItemIcon()
    local desatAmount, desatBool
    local icon = {
        Cooldown = {
            SetCooldownFromDurationObject = noop,
            SetReverse = noop,
            SetSwipeTexture = noop,
            Clear = noop,
        },
        Icon = {
            SetDesaturated = function(_, value) desatBool = value end,
            SetDesaturation = function(_, value) desatAmount = value end,
            SetVertexColor = noop,
        },
        PandemicGlow = { SetAlpha = noop },
        _spellEntry = {
            id = ITEM_ID,
            itemID = ITEM_ID,
            kind = "cooldown",
            type = "item",
            viewerType = "essential",
            name = "Test Item",
        },
    }
    return icon,
        function() return desatAmount end,
        function() return desatBool end
end

-- Case 1: real CD rolling -> saturation is curve-driven off the real-CD-only
-- DurationObject (SetDesaturation gets the curve value), NOT a mode-gated
-- SetDesaturated(true).
do
    local icon, getAmount = makeIcon()
    icon._blizzMirrorState = {}
    local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)
    assert(applied == true, "case1: real-CD spell should report an applied cooldown")
    assert(getAmount() == DESAT_FROM_CURVE,
        "case1: essential saturation must be driven by the real-CD-only DurationObject curve via SetDesaturation")
    assert(#curveAddPoints > 0, "case1: a desaturation step curve must be built")
end

-- Case 2: charge carve-out (wasSetFromCharges=true) must suppress the curve
-- drive and keep the icon saturated via SetDesaturated(false).
do
    curveAddPoints = {}
    local realCdQueried = false
    ns.CDMSources.QuerySpellCooldownDuration = function(spellID, ignoreGCD)
        realCdQueried = true
        assert(ignoreGCD == true, "ignoreGCD must be true")
        if spellID == THRASH then return realCdDurObj end
        return nil
    end

    local icon, getAmount, getBool = makeIcon()
    icon._blizzMirrorState = { wasSetFromCharges = true }
    local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)
    assert(applied == true, "case2: charge mirror should report an applied cooldown")
    assert(getAmount() ~= DESAT_FROM_CURVE,
        "case2: charge carve-out (wasSetFromCharges) must NOT route saturation through the real-CD curve")
    assert(getBool() == false,
        "case2: charge spell with banked charges must stay saturated via SetDesaturated(false)")
    assert(realCdQueried == false,
        "case2: the real-CD duration must not even be queried when the charge carve-out keeps the icon saturated")
end

-- Case 3: item-cooldown phase must drive saturation from the item cooldown
-- DurationObject returned by the resolver. Querying the use spell's spell-CD
-- duration can report no real cooldown for item-backed trinkets.
do
    ns.CDMSources.QuerySpellCooldownDuration = function(spellID)
        if spellID == ITEM_USE_SPELL then
            error("item cooldown desaturation must use the resolved item DurationObject")
        end
        return nil
    end

    local icon, getAmount = makeItemIcon()
    local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)
    assert(applied == true, "case3: item cooldown should report an applied cooldown")
    assert(getAmount() == ITEM_DESAT_FROM_CURVE,
        "case3: item cooldown saturation must be driven by the item DurationObject curve")
end

print("OK cdm_icons_realcd_desat_curve_test")
