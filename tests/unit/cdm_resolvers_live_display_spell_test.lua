-- tests/unit/cdm_resolvers_live_display_spell_test.lua
-- Run: lua tests/unit/cdm_resolvers_live_display_spell_test.lua
-- luacheck: globals InCombatLockdown geterrorhandler CreateFrame issecretvalue
--
-- ResolveLiveDisplaySpellID must follow C_Spell.GetOverrideSpell when it flips,
-- and fall back to the mirror override child when GetOverrideSpell stays on the
-- registered base (Brewmaster Empty Barrel on Keg Smash is the reference case).

local function noop() end

function InCombatLockdown() return false end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return { RegisterEvent = noop, RegisterUnitEvent = noop, SetScript = noop }
end

local KS_BASE = 121253
local EB_OVERRIDE = 1240001
local EB_TOOLTIP = 1240002
local HOL_BASE, HOL_OVERRIDE = 255937, 427453

local overrideOf = {
    [HOL_BASE] = HOL_OVERRIDE,
}

local ns = {
    Helpers = {},
    CDMSources = {
        QueryOverrideSpell = function(spellID) return overrideOf[spellID] end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local ResolveLiveDisplaySpellID = ns.CDMResolvers.ResolveLiveDisplaySpellID

-- Empty Barrel: mirror child active, API override absent.
local ebMirror = {
    spellID = KS_BASE,
    overrideSpellID = EB_OVERRIDE,
    childIsActive = true,
}
assert(ResolveLiveDisplaySpellID(KS_BASE, ebMirror) == EB_OVERRIDE,
    "active mirror override child must supply proc display spell")

-- Tooltip id wins when both are present on the active child.
local ebTooltipMirror = {
    spellID = KS_BASE,
    overrideSpellID = EB_OVERRIDE,
    overrideTooltipSpellID = EB_TOOLTIP,
    childIsActive = true,
}
assert(ResolveLiveDisplaySpellID(KS_BASE, ebTooltipMirror) == EB_TOOLTIP,
    "overrideTooltipSpellID must win on an active mirror child")

-- Hammer of Light: live GetOverrideSpell wins over a stale mirror base field.
local holMirror = {
    spellID = HOL_BASE,
    overrideSpellID = HOL_BASE,
    childIsActive = true,
}
assert(ResolveLiveDisplaySpellID(HOL_BASE, holMirror) == HOL_OVERRIDE,
    "GetOverrideSpell must stay authoritative when it flips away from base")

-- Inactive child: no mirror fallback.
overrideOf[KS_BASE] = nil
local ebInactiveMirror = {
    spellID = KS_BASE,
    overrideSpellID = EB_OVERRIDE,
    childIsActive = false,
}
assert(ResolveLiveDisplaySpellID(KS_BASE, ebInactiveMirror) == KS_BASE,
    "mirror override must not apply when childIsActive is false")

-- childIsActive with no mirror override ids: fall back to API/base.
assert(ResolveLiveDisplaySpellID(HOL_BASE, holMirror) == HOL_OVERRIDE,
    "GetOverrideSpell must still apply when mirror ids match the base")

-- ResolveCooldownState threads the mirror child into spellID identity.
overrideOf[KS_BASE] = nil
local ebState = {
    spellID = KS_BASE,
    overrideSpellID = EB_OVERRIDE,
    childIsActive = true,
    cooldownID = 9001,
    mirrorEpoch = 2,
    viewerCategory = "essential",
    charges = true,
}
ns.CDMSources.QuerySpellCooldown = function(spellID)
    return { isActive = false, isOnGCD = false }
end
ns.CDMSources.QueryIsSpellKnownOrPlayerSpell = function() return true end
ns.CDMSources.QuerySpellInfo = function() return nil end
ns.CDMBlizzMirror = {
    GetStateByCooldownID = function(cooldownID, viewerCategory)
        if cooldownID == 9001 and viewerCategory == "essential" then
            return ebState
        end
    end,
}

local entry = {
    id = KS_BASE,
    spellID = KS_BASE,
    viewerType = "essential",
    type = "spell",
    hasCharges = true,
}
local context = ns.CDMResolvers.BuildCooldownStateContext(
    { _spellEntry = entry, _runtimeSpellID = KS_BASE },
    entry,
    KS_BASE,
    {
        containerKey = "essential",
        useBuffSwipe = false,
        skipAuraPhase = false,
        showGCDSwipe = true,
        cachedMirrorState = ebState,
    })
context.mirrorCooldownID = 9001
context.mirrorCategory = "essential"
local resolved = ns.CDMResolvers.ResolveCooldownState(context)
assert(resolved.spellID == EB_OVERRIDE,
    "ResolveCooldownState must expose mirror-child proc art spellID, got "
        .. tostring(resolved.spellID))

print("cdm_resolvers_live_display_spell_test: PASS")
