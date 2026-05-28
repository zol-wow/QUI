-- tests/unit/cdm_resolvers_buffbar_crosscat_render_test.lua
-- Run: lua tests/unit/cdm_resolvers_buffbar_crosscat_render_test.lua
-- luacheck: globals InCombatLockdown GetTime geterrorhandler issecretvalue CreateFrame
--
-- Replicates the OWNED BAR render path (cdm_bar_renderer.UpdateOwnedBarAura):
--   BuildCooldownStateContext(bar, entry, spellID, {
--       mirrorIdentityPolicy = "entry-or-fallback",
--       fallbackContainerKey = "trackedBar",
--       containerKey = entry.viewerType,   -- "trackedBar"
--       useBuffSwipe = true,
--   })
--   -> ResolveCooldownState(context)
--
-- A built-in Buff Bars (trackedBar) container entry the user added for Blur's
-- buff (212800) must activate from the sibling buff (icon) viewer's cdID
-- (168618), since Blizzard registers Blur's buff in the buff viewer ONLY.
-- The buff ICON for the same spell already resolves active in-game; the bar
-- must reach the same active aura state through the same cross-category mirror.

local function noop() end

local inCombat = false
function InCombatLockdown() return inCombat end
function GetTime() return 120 end
function geterrorhandler() return function(err) error(err) end end
function issecretvalue() return false end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local auraDur = { token = "blur-aura-dur" }

-- The ONLY active mirror for Blur's buff lives in the buff (icon) viewer.
local buffMirrorState = {
    cooldownID = 168618,
    viewerCategory = "buff",
    spellID = 212800,
    overrideSpellID = 212800,
    mirrorEpoch = 7,
    auraInstanceID = 9250,
    auraUnit = "player",
    selfAura = true,
    auraDurObj = auraDur,
    auraDurObjSource = "aura-duration",
}

local bySpell = {
    buff = { [212800] = 168618 },
    trackedBar = {}, -- Blizzard does NOT register Blur in the bar viewer
}

local ns = {
    Helpers = {},
    CDMShared = {
        IsSafeNumeric = function(value)
            return type(value) == "number" or issecretvalue(value)
        end,
    },
    CDMSources = {
        QueryOverrideSpell = function() return nil end,
        QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
            if unit == "player" and auraInstanceID == 9250 then
                return { auraInstanceID = 9250, isFromPlayerOrPlayerPet = true }
            end
            return nil
        end,
    },
    CDMBlizzMirror = {
        GetDirectCooldownIDForViewer = function(spellID, viewerCategory)
            local cat = bySpell[viewerCategory]
            return cat and cat[spellID] or nil
        end,
        GetCooldownIDForViewer = function(spellID, viewerCategory)
            local cat = bySpell[viewerCategory]
            return cat and cat[spellID] or nil
        end,
        GetStateByCooldownID = function(cooldownID, viewerCategory)
            if cooldownID == 168618 and viewerCategory == "buff" then
                return buffMirrorState
            end
            return nil
        end,
        HasChildForCooldownID = function(cooldownID, viewerCategory)
            return cooldownID == 168618 and viewerCategory == "buff"
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("modules/cdm/cdm_runtime.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("modules/cdm/cdm_runtime.lua", "cdm_resolvers.lua")("QUI", ns)

local resolvers = assert(ns.CDMResolvers, "CDMResolvers should be exported")
local buildContext = assert(resolvers.BuildCooldownStateContext, "BuildCooldownStateContext should be exported")
local resolve = assert(resolvers.ResolveCooldownState, "ResolveCooldownState should be exported")

-- Entry the user added to the built-in Buff Bars container.
local entry = {
    type = "spell",
    kind = "aura",
    id = 212800,
    spellID = 212800,
    overrideSpellID = 212800,
    viewerType = "trackedBar",
}

local bar = {}
local context = buildContext(bar, entry, 212800, {
    mirrorIdentityPolicy = "entry-or-fallback",
    fallbackContainerKey = "trackedBar",
    containerKey = "trackedBar",
    useBuffSwipe = true,
})

assert(context, "bar context should build")
assert(context.mirrorCooldownID == 168618,
    "bar context should cross-bind to the buff cdID, got " .. tostring(context.mirrorCooldownID))
assert(context.mirrorCategory == "buff",
    "bar context should resolve the buff mirror category, got " .. tostring(context.mirrorCategory))

local state = resolve(context)

assert(state.mode == "aura",
    "Buff Bars Blur entry should resolve aura mode from the buff mirror, got " .. tostring(state.mode))
assert(state.isActive == true,
    "Buff Bars Blur entry should resolve active, got " .. tostring(state.isActive))
assert(state.durObj == auraDur,
    "Buff Bars Blur entry should carry the buff aura DurationObject")
assert(state.auraUnit == "player",
    "Buff Bars Blur entry should resolve to the player unit")

-- Stale-cache trap (the actual /reload bug): the resolver's cached-state fast
-- path deliberately trusts the cached state and skips re-querying the live
-- mirror. A state cached while the buff was DOWN (no auraInstanceID/auraDurObj)
-- therefore freezes the bar at mode=inactive even though the live mirror
-- (168618) now carries the aura -- this is why the owned bar "won't activate
-- until a rebuild" and "breaks again on /reload". The bar context builder must
-- NOT feed cachedMirrorState; resolving fresh (as above) reads the live aura.
local staleCache = {
    cooldownID = 168618,
    viewerCategory = "buff",
    spellID = 212800,
    overrideSpellID = 212800,
    mirrorEpoch = 1,
    -- captured while the buff was down: deliberately no auraInstanceID/auraDurObj
}

local staleActive = resolve(buildContext(bar, entry, 212800, {
    mirrorIdentityPolicy = "entry-or-fallback",
    fallbackContainerKey = "trackedBar",
    containerKey = "trackedBar",
    useBuffSwipe = true,
    cachedMirrorState = staleCache,
})).isActive
assert(staleActive ~= true,
    "feeding a stale (buff-down) cached mirror state freezes the bar inactive -- "
    .. "the bar context builder must never pass cachedMirrorState")

local freshActive = resolve(buildContext(bar, entry, 212800, {
    mirrorIdentityPolicy = "entry-or-fallback",
    fallbackContainerKey = "trackedBar",
    containerKey = "trackedBar",
    useBuffSwipe = true,
})).isActive
assert(freshActive == true,
    "resolving fresh (no cached state) reads the live mirror and activates the bar")

print("OK: cdm_resolvers_buffbar_crosscat_render_test")
