-- tests/unit/cdm_resolvers_proc_override_overlay_test.lua
-- Run: lua tests/unit/cdm_resolvers_proc_override_overlay_test.lua
-- luacheck: globals InCombatLockdown geterrorhandler CreateFrame issecretvalue
--
-- DeriveMirrorPayloadMode treats a live spell-override over a still-known base
-- on a real (non-GCD) cooldown as a transient PROC override and shows it READY
-- (mode=inactive) -- correct for Hammer of Light (427453) over Wake of Ashes
-- (255937) on a Light's Guidance proc, where the override carries an active
-- spell-activation overlay and is castable while the base recharges.
--
-- A FORM/SPEC override that merely SHARES the base cooldown (Druid Stampeding
-- Roar 77761 overriding 106898) matches the same spell-API shape -- both report
-- the shared recharge slot active -- but has NO proc overlay and is genuinely on
-- cooldown. It must resolve mode=cooldown so the swipe shows.
--
-- The discriminator is the proc-overlay probe cdm_effects registers via
-- CDMResolvers.SetProcOverlayProbe.

local function noop() end

function InCombatLockdown() return false end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return { RegisterEvent = noop, RegisterUnitEvent = noop, SetScript = noop }
end

local SR_BASE, SR_OVERRIDE, SR_CDID = 106898, 77761, 2282     -- Stampeding Roar (form override, shared cd)
local HOL_BASE, HOL_OVERRIDE, HOL_CDID = 255937, 427453, 7000 -- Wake of Ashes -> Hammer of Light (proc)
local srCooldownDuration = { token = "sr-cooldown-duration" }

-- Live overrides + per-spell cooldown state. Both bases are on a real (non-GCD)
-- cooldown; both overrides report the shared slot active.
local overrideOf = { [SR_BASE] = SR_OVERRIDE, [HOL_BASE] = HOL_OVERRIDE }
local cooldownActive = {
    [SR_BASE] = true, [SR_OVERRIDE] = true,
    [HOL_BASE] = true, [HOL_OVERRIDE] = true,
}

-- Proc overlays: only the Hammer of Light proc is overlay-active.
local overlayed = { [HOL_OVERRIDE] = true }

local ns = {
    Helpers = {},
    CDMSources = {
        QuerySpellCooldown = function(spellID)
            return { isActive = cooldownActive[spellID] == true, isOnGCD = false }
        end,
        QuerySpellCooldownDuration = function(spellID, ignoreGCD)
            -- Shared recharge slot: the base and its override report the same
            -- live cooldown duration.
            if ignoreGCD == true and (spellID == SR_OVERRIDE or spellID == SR_BASE) then
                return srCooldownDuration
            end
            return nil
        end,
        QueryOverrideSpell = function(spellID) return overrideOf[spellID] end,
        QueryIsSpellKnownOrPlayerSpell = function() return true end,
        QuerySpellInfo = function() return nil end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, viewerCategory)
            if cooldownID == SR_CDID and viewerCategory == "utility" then
                return {
                    cooldownID = SR_CDID, mirrorEpoch = 3,
                    spellID = SR_BASE, overrideSpellID = SR_OVERRIDE,
                    viewerCategory = "utility",
                }
            end
            if cooldownID == HOL_CDID and viewerCategory == "essential" then
                return {
                    cooldownID = HOL_CDID, mirrorEpoch = 3,
                    spellID = HOL_BASE, overrideSpellID = HOL_OVERRIDE,
                    viewerCategory = "essential",
                }
            end
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

-- Stand in for cdm_effects' registration of the authoritative proc-overlay probe.
ns.CDMResolvers.SetProcOverlayProbe(function(spellID) return overlayed[spellID] == true end)

local function ResolveMode(cdID, category, baseSpellID, overrideSpellID)
    local entry = {
        id = baseSpellID, spellID = baseSpellID, overrideSpellID = overrideSpellID,
        viewerType = category, type = "spell",
    }
    local icon = { _spellEntry = entry, _runtimeSpellID = overrideSpellID }
    local context = ns.CDMResolvers.BuildCooldownStateContext(icon, entry, overrideSpellID, {
        containerKey = category,
        useBuffSwipe = false,
        skipAuraPhase = false,
        showGCDSwipe = true,
    })
    context.mirrorCooldownID = cdID
    context.mirrorCategory = category
    return ns.CDMResolvers.ResolveCooldownState(context)
end

-- Stampeding Roar: no proc overlay on the override -> genuine cooldown.
local sr = ResolveMode(SR_CDID, "utility", SR_BASE, SR_OVERRIDE)
assert(sr.mode == "cooldown",
    "form override sharing the base cooldown (no proc overlay) must resolve cooldown, got " .. tostring(sr.mode))
assert(sr.durObj == srCooldownDuration,
    "cooldown payload should bind the override's live cooldown duration")

-- Hammer of Light: proc overlay active on the override -> shown ready.
local hol = ResolveMode(HOL_CDID, "essential", HOL_BASE, HOL_OVERRIDE)
assert(hol.mode == "inactive",
    "transient proc override with an active overlay must resolve ready/inactive, got " .. tostring(hol.mode))

-- Without any registered probe the override can never be classed a ready proc;
-- it must fall through to the real cooldown (the safe default).
ns.CDMResolvers.SetProcOverlayProbe(nil)
local holNoProbe = ResolveMode(HOL_CDID, "essential", HOL_BASE, HOL_OVERRIDE)
assert(holNoProbe.mode == "cooldown",
    "with no overlay probe, a shared-slot override must default to cooldown, got " .. tostring(holNoProbe.mode))

print("cdm_resolvers_proc_override_overlay_test: PASS")
