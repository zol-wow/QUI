-- tests/unit/cdm_resolvers_void_volley_override_test.lua
-- Run: lua tests/unit/cdm_resolvers_void_volley_override_test.lua
-- luacheck: globals InCombatLockdown geterrorhandler CreateFrame issecretvalue
--
-- Shadow Priest Void Volley replaces Voidform on the essential icon while
-- Voidform is active. Blizzard's CooldownViewer queries the override spell's
-- cooldown lane (CooldownViewerItemDataMixin:GetSpellID). The base Voidform
-- major cooldown must not paint over a ready or recharging Void Volley.

local function noop() end

function InCombatLockdown() return false end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return { RegisterEvent = noop, RegisterUnitEvent = noop, SetScript = noop }
end

local VF_BASE, VF_OVERRIDE, VF_CDID = 228260, 1242173, 8801
local vfVolleyCooldownDuration = { token = "void-volley-cooldown-duration" }
local vfMajorCooldownDuration = { token = "voidform-major-cooldown-duration" }

local cooldownActive = {
    [VF_BASE] = true,
    [VF_OVERRIDE] = false,
}

local ns = {
    Helpers = {},
    CDMSources = {
        QuerySpellCooldown = function(spellID)
            return { isActive = cooldownActive[spellID] == true, isOnGCD = false }
        end,
        QuerySpellCooldownDuration = function(spellID, ignoreGCD)
            if ignoreGCD == true and spellID == VF_OVERRIDE then
                return vfVolleyCooldownDuration
            end
            if ignoreGCD == true and spellID == VF_BASE then
                return vfMajorCooldownDuration
            end
            return nil
        end,
        QueryOverrideSpell = function(spellID)
            if spellID == VF_BASE then return VF_OVERRIDE end
            return nil
        end,
        QueryIsSpellKnownOrPlayerSpell = function() return true end,
        QuerySpellInfo = function() return nil end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, viewerCategory)
            if cooldownID == VF_CDID and viewerCategory == "essential" then
                return {
                    cooldownID = VF_CDID,
                    mirrorEpoch = 4,
                    spellID = VF_BASE,
                    overrideSpellID = VF_OVERRIDE,
                    viewerCategory = "essential",
                    childIsActive = true,
                }
            end
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local function ResolveMode()
    local entry = {
        id = VF_BASE,
        spellID = VF_BASE,
        overrideSpellID = VF_OVERRIDE,
        viewerType = "essential",
        type = "spell",
    }
    local icon = { _spellEntry = entry, _runtimeSpellID = VF_OVERRIDE }
    local context = ns.CDMResolvers.BuildCooldownStateContext(icon, entry, VF_OVERRIDE, {
        containerKey = "essential",
        useBuffSwipe = false,
        skipAuraPhase = false,
        showGCDSwipe = true,
    })
    context.mirrorCooldownID = VF_CDID
    context.mirrorCategory = "essential"
    return ns.CDMResolvers.ResolveCooldownState(context)
end

-- Void Volley ready while Voidform major cooldown is still rolling.
local ready = ResolveMode()
assert(ready.mode == "inactive",
    "active override child must surface ready when override cooldown is idle, got "
        .. tostring(ready.mode))

-- Void Volley recharging: show the short override swipe, not Voidform's major cd.
cooldownActive[VF_OVERRIDE] = true
local recharging = ResolveMode()
assert(recharging.mode == "cooldown",
    "active override child must surface override cooldown lane, got "
        .. tostring(recharging.mode))
assert(recharging.durObj == vfVolleyCooldownDuration,
    "override cooldown lane must bind the override DurationObject")

-- After Voidform ends the child drops; the major cooldown should surface again.
cooldownActive[VF_OVERRIDE] = false
ns.CDMBlizzMirror.GetStateByCooldownID = function(cooldownID, viewerCategory)
    if cooldownID == VF_CDID and viewerCategory == "essential" then
        return {
            cooldownID = VF_CDID,
            mirrorEpoch = 5,
            spellID = VF_BASE,
            overrideSpellID = VF_BASE,
            viewerCategory = "essential",
            childIsActive = false,
        }
    end
end
local majorCd = ResolveMode()
assert(majorCd.mode == "cooldown",
    "without an active override child the base major cooldown must show, got "
        .. tostring(majorCd.mode))
assert(majorCd.durObj == vfMajorCooldownDuration,
    "base major cooldown must bind the base DurationObject")

print("cdm_resolvers_void_volley_override_test: PASS")
