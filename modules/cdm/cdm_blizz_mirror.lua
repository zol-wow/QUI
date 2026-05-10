local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- CDM Blizzard Mirror
--
-- Thin, kind-agnostic mirror of Blizzard's Cooldown Viewer children. Captures
-- DurationObjects from `Cooldown:SetCooldownFromDurationObject` calls on each
-- bound child and tracks visibility via Show/Hide hooks. Two consumers
-- ratified by spec 2026-05-07-cdm-blizzard-aura-mirror-design.md:
--
--   * aura resolver Phase 3.0   (cdm_spelldata.lua, ResolveAuraState)
--   * cooldown resolver Phase 3.0 (cdm_resolvers.lua)
--
-- Plus ResolveEntryKind reads `viewerCategory` for custom-bar entry kind
-- classification when no explicit kind is supplied.
--
-- Discovery is OOC-only. Hooks fire any time, including combat. The
-- `LuaDurationObject` is secret-safe — it flows through C-side sinks
-- (`SetCooldownFromDurationObject`) without taint. We never read its fields
-- in Lua.
---------------------------------------------------------------------------

local CDMBlizzMirror = {}
ns.CDMBlizzMirror = CDMBlizzMirror

local Helpers = ns.Helpers
local Sources = ns.CDMSources

---------------------------------------------------------------------------
-- File-local state — never read outside this module.
---------------------------------------------------------------------------
-- The cooldownID is the unambiguous primary key per Blizzard's CooldownViewer
-- documentation. A single spellID can resolve to multiple cooldownIDs across
-- categories (e.g., the cast lives in essential, the buff in TrackedBuff),
-- so callers must look up by (spellID, category) — never just by spellID
-- alone, since last-write-wins on a global map is silently wrong.
local _childByCooldownID   = {}    -- [cooldownID] = child frame (current as of last Walk)
local _viewerCategoryByID  = {}    -- [cooldownID] = "essential"|"utility"|"buff"|"trackedBar"
local _mirrorState         = {}    -- [cooldownID] = { durObj, isActive, mirrorEpoch, lastTouch }
local _categoryByFrame     = {}    -- [child frame] = catNum (lazy-init category fallback)
local _childByCooldownFrame = setmetatable({}, { __mode = "k" }) -- [child.Cooldown] = child frame
local _forceShowingChild    = setmetatable({}, { __mode = "k" }) -- [child] = true for QUI's feed-preserving Show()
local _hostByCooldownID
local SetHostPandemicState
-- CooldownViewerCooldown info captured from C_CooldownViewer.GetCooldownViewerCooldownInfo:
--   cooldownID, spellID, overrideSpellID, overrideTooltipSpellID,
--   linkedSpellIDs (numberArray), selfAura (bool), hasAura (bool),
--   charges (bool), isKnown (bool), flags, category.
local _cooldownInfoByID    = {}    -- [cooldownID] = info table
-- Per-category spellID -> cooldownID maps. Indexed by category name.
-- `_cdIDByCatSpell[catName][spellID]` resolves an entry's catalog spellID
-- to the cooldownID for that exact viewer category — no cross-category
-- contamination. Aura aliases are only recorded in the aura categories
-- (buff/trackedBar); cooldown categories do not own aura spellIDs.
local _cdIDByCatSpell      = {
    essential  = {},
    utility    = {},
    buff       = {},
    trackedBar = {},
}
-- Strict spellID -> cooldownID maps used when choosing the Blizzard child to
-- reparent. Unlike `_cdIDByCatSpell`, these do not include broad linked
-- aliases when a direct aura identity is available; this prevents a buff icon
-- from binding to a related parent/ability cooldownID and showing the wrong
-- duration or application count.
local _directCDIDByCatSpell = {
    essential  = {},
    utility    = {},
    buff       = {},
    trackedBar = {},
}
-- Totem-backed CDM children (e.g. Anti-Magic Zone) get their swipe / active
-- state from PLAYER_TOTEM_UPDATE, NOT from any Cooldown:Set* on the child.
-- Blizzard's mixin watches totem events and drives the visual through a path
-- that bypasses our 5 Cooldown setter hooks. We mirror that by listening for
-- PLAYER_TOTEM_UPDATE here and authoritatively flipping s.isActive / s.durObj
-- for cdIDs whose CooldownInfo spell name matches an active totem's name.
-- Slot → cdID resolution is by spell name; the index is rebuilt on every
-- Walk and incrementally extended on BindNewChildren.
local _spellNameToCDID = {}        -- [spellName lowercase] = cdID (aura categories only)
local _totemActiveCDID = {}        -- [cdID] = totem slot, set by PLAYER_TOTEM_UPDATE

-- Forward decls: Walk / BindNewChildren reference these by upvalue, but the
-- definitions live further down (alongside the rest of the totem helpers,
-- where the surrounding context — _eventFrame, EnsureState, TaintLog —
-- exists). The `function NAME(...)` form below ASSIGNS to these existing
-- locals; do not re-add `local` to those definitions.
local _IndexSpellNameForCDID
local HandlePlayerTotemUpdate

do
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_blizzMirror_state",         tbl = _mirrorState }
    mp[#mp + 1] = { name = "CDM_blizzMirror_essentialMap",  tbl = _cdIDByCatSpell.essential }
    mp[#mp + 1] = { name = "CDM_blizzMirror_utilityMap",    tbl = _cdIDByCatSpell.utility }
    mp[#mp + 1] = { name = "CDM_blizzMirror_buffMap",       tbl = _cdIDByCatSpell.buff }
    mp[#mp + 1] = { name = "CDM_blizzMirror_trackedBarMap", tbl = _cdIDByCatSpell.trackedBar }
    mp[#mp + 1] = { name = "CDM_blizzMirror_buffDirectMap", tbl = _directCDIDByCatSpell.buff }
    mp[#mp + 1] = { name = "CDM_blizzMirror_trackedBarDirectMap", tbl = _directCDIDByCatSpell.trackedBar }
    mp[#mp + 1] = { name = "CDM_blizzMirror_spellNameIndex", tbl = _spellNameToCDID }
    mp[#mp + 1] = { name = "CDM_blizzMirror_totemActive",   tbl = _totemActiveCDID }
end

---------------------------------------------------------------------------
-- Category mapping. WoW exposes Enum.CooldownViewerCategory at runtime;
-- numeric fallbacks here match the documented values:
--   Essential = 0  | Utility = 1  | TrackedBuff = 2  | TrackedBar = 3
---------------------------------------------------------------------------
local CATEGORY_NAMES = {
    [0] = "essential",
    [1] = "utility",
    [2] = "buff",
    [3] = "trackedBar",
}

local CATEGORY_GLOBALS = {
    [0] = "EssentialCooldownViewer",
    [1] = "UtilityCooldownViewer",
    [2] = "BuffIconCooldownViewer",
    [3] = "BuffBarCooldownViewer",
}

---------------------------------------------------------------------------
-- Aura-event freshness tracking.
--
-- The SetCooldownFromDurationObject hook (line ~538) only sets s.isActive
-- to true; it never clears it. Blizzard's mixin force-shows the parent
-- child for inactive auras (see HookChildPreventHide and the comment at
-- line ~919) so the Hide hook clearing path rarely fires for expired
-- auras. Without an external freshness check, mirror states accumulate
-- stale-true entries that drive icons into "stuck shown" visibility.
--
-- Strategy: stamp each mirror state with the auraInstanceID Blizzard
-- delivers via UNIT_AURA addedAuras / a bootstrap rescan. On every
-- consumer-facing PackState read, call C_UnitAuras.GetAuraDuration on
-- the stored instID — it returns nil when the aura is no longer present
-- on the unit. nil → clear the mirror's isActive/durObj.
--
-- auraInstanceID is secret in combat (re-randomized on encounter/M+/PvP
-- start). It is only ever stored as a Lua table value and forwarded to
-- the C-side GetAuraDuration sink — never used as a Lua key, never
-- compared with == against another instID.
---------------------------------------------------------------------------
-- Stamp the auraInstanceID for a known cdID. Caller has already resolved
-- which cdID this aura belongs to (from the non-secret catalog spellID it
-- queried for) so we never need to reach into ad's potentially-secret
-- fields for identity. We only read ad.auraInstanceID — stored as a Lua
-- value, never used as a key, never compared with == — and forwarded to
-- C-side sinks (C_UnitAuras.GetAuraDuration / GetAuraDataByAuraInstanceID)
-- where secrets are accepted natively.
local function StampAuraInstanceForCooldown(unit, cdID, ad)
    if not (ad and cdID) then return end
    local s = _mirrorState[cdID]
    if not s then return end
    local instID = ad.auraInstanceID
    if not instID then return end
    s.auraInstanceID = instID
    s.auraUnit = unit
    if CDMBlizzMirror.TaintLog then
        CDMBlizzMirror.TaintLog("Stamp", "unit", unit, "cdID", cdID)
    end
end

local function ClearMirrorAuraState(cdID, s, reason)
    if not s then return end
    if not (s.isActive == true or s.durObj or s.auraInstanceID
        or s.pandemicActive or s.pandemicStateKnown) then
        return
    end

    s.isActive = false
    s.durObj = nil
    s.auraInstanceID = nil
    s.auraUnit = nil
    s.pandemicActive = false
    s.pandemicStateKnown = nil
    s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
    s.lastTouch = GetTime()
    if SetHostPandemicState then
        SetHostPandemicState(cdID, nil, false)
    end
    if CDMBlizzMirror.TaintLog then
        CDMBlizzMirror.TaintLog("ClearAuraState",
            "cdID", cdID, "reason", reason or "unknown")
    end
end

-- Iterate our (non-secret) catalog and ask Blizzard whether each registered
-- aura spellID is on the unit. Same approach for player / pet / target —
-- never reads aura fields to identify the aura, since the caller already
-- knows which spellID it queried for. Sidesteps every secret-value index
-- problem.
local function CaptureAurasFromUnit(unit)
    if type(unit) ~= "string" or unit == "" then return end
    if not Sources then return end
    -- Target stamps must be source-filtered. The CDM trackedBar/buff
    -- categories only ever expose the player's own auras — Blizzard's
    -- mixin filters by source internally for the trackedBar (DK DoTs,
    -- Hunter stings, etc). Without this guard, another player's debuff
    -- on the same target stamps our mirror with their auraInstanceID,
    -- VerifyStateFreshness then confirms the aura exists on the target,
    -- and the icon flips active even though the player never cast it.
    -- The HARMFUL/HELPFUL split bounds buff-vs-debuff cross-pollution but
    -- does NOT bound mine-vs-theirs; the source check below is the gate.
    local needsSourceFilter = (unit == "target")
    for cat, directMap in pairs(_directCDIDByCatSpell) do
        if cat == "buff" or cat == "trackedBar" then
            for sid, cdID in pairs(directMap) do
                local ad
                if unit == "player" and Sources.QueryPlayerAuraBySpellID then
                    ad = Sources.QueryPlayerAuraBySpellID(sid)
                elseif Sources.QueryUnitAuraBySpellID then
                    ad = Sources.QueryUnitAuraBySpellID(unit, sid)
                end
                if ad and (not needsSourceFilter or Helpers.IsAuraOwnedByPlayerOrPet(ad)) then
                    StampAuraInstanceForCooldown(unit, cdID, ad)
                end
            end
        end
    end
end

local function VerifyStateFreshness(cdID, s, clearOnMissing)
    -- Bidirectional verification of the stamped auraInstanceID:
    --   * GetAuraDuration returns nil → aura is no longer on the unit,
    --     clear stale isActive/durObj.
    --   * GetAuraDuration returns a DurationObject → aura IS on the unit,
    --     promote isActive=true even if SetCooldownFromDurationObject
    --     never fired. Durationless auras (stances, forms, perma buffs/
    --     debuffs) never push a durObj through that hook, so the
    --     promote-on-verify path is the only way isActive can become
    --     true for them. The hook still owns s.durObj for duration-
    --     bearing auras; we only fill it in here when the hook hasn't.
    -- All `== nil` / `~= nil` checks below were rewritten to truthy
    -- (`not v` / `v`) form because the values being checked
    -- (auraInstanceID, durObj) can be secret in combat, and `==` against
    -- a secret errors. Truthy checks are C-level type-tag tests and are
    -- safe for secrets. Without this fix the resolver silently dies inside
    -- the icon visibility loop's pcall — UpdateIconCooldown becomes a
    -- no-op and `icon._auraActive` never flips true → icons stay hidden
    -- in combat even when the aura is on the unit.
    if not s then return end
    if not s.auraInstanceID then return end
    if not (Sources and Sources.QueryAuraDuration) then return end
    local durObj = Sources.QueryAuraDuration(s.auraUnit or "player", s.auraInstanceID)
    if CDMBlizzMirror.TaintLog then
        CDMBlizzMirror.TaintLog("Verify",
            "auraUnit", s.auraUnit,
            "instID", s.auraInstanceID,
            "durObj", durObj,
            "priorIsActive", s.isActive,
            "priorDurObj", s.durObj)
    end
    if not durObj then
        -- GetAuraDuration returning nil has two meanings:
        --   (a) aura expired or was removed from the unit
        --   (b) aura is on the unit but durationless (permanent buffs
        --       like Lesser Ghoul's pet-presence indicator, stances,
        --       forms — no expiration time)
        -- Disambiguate via GetAuraDataByAuraInstanceID, which returns
        -- AuraData when the aura still exists on the unit (regardless
        -- of duration) and nil when it's gone. Without this check we
        -- invalidate permanent auras every tick and the icon oscillates
        -- false/true, never visually settling into "shown."
        local ad = Sources.QueryAuraDataByAuraInstanceID
            and Sources.QueryAuraDataByAuraInstanceID(s.auraUnit or "player", s.auraInstanceID)
        local auraStillOnUnit = ad and true or false
        if auraStillOnUnit then
            -- Permanent aura: keep isActive=true, drop the (nil) durObj
            -- so consumers don't try to render a swipe. Icon factory
            -- treats active+durObj=nil as "show without countdown."
            if s.isActive ~= true then
                s.isActive = true
                s.lastTouch = GetTime()
            end
            if s.durObj then
                s.durObj = nil
                s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
                s.lastTouch = GetTime()
            end
        elseif clearOnMissing or not InCombatLockdown() then
            -- Both probes returned nil. Out of combat, that is enough to
            -- prove the aura is gone. In combat, only an explicit UNIT_AURA
            -- removal path passes clearOnMissing=true; plain consumer reads
            -- still preserve ambiguous nils until combat ends.
            ClearMirrorAuraState(cdID, s, clearOnMissing and "unit-aura-removed" or "freshness")
        end
    else
        if s.isActive ~= true then
            s.isActive = true
            s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
            s.lastTouch = GetTime()
        end
        if not s.durObj then
            s.durObj = durObj
            s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
        end
    end
end

local function EvictRemovedMirrorStatesForUnit(unit)
    if type(unit) ~= "string" or unit == "" then return end
    for cdID, s in pairs(_mirrorState) do
        local cat = _viewerCategoryByID[cdID]
        if (cat == "buff" or cat == "trackedBar")
            and s
            and s.auraUnit == unit
            and s.auraInstanceID then
            VerifyStateFreshness(cdID, s, true)
        end
    end
end

---------------------------------------------------------------------------
-- Public API surface (read-only).
---------------------------------------------------------------------------
-- Pack the live mirror state + captured info struct into the read-only
-- shape consumers see. Always keyed by cooldownID, since cooldownID is
-- the unambiguous primary key per the CooldownViewer documentation.
local function PackState(cooldownID)
    if not cooldownID then return nil end
    local s = _mirrorState[cooldownID]
    if not s then return nil end
    VerifyStateFreshness(cooldownID, s, false)
    local info = _cooldownInfoByID[cooldownID]
    -- selfAura / hasAura must NOT be coerced to false on nil. CleanBool
    -- returns nil when the source bool was secret AND the curve-decode
    -- fallback failed — i.e. "we don't know". `or false` would force
    -- those into target-side classification (selfAura=false), which is
    -- the wrong default for buff icons (most are player-side). Pass nil
    -- through and let consumers default safely with `m.selfAura == false`
    -- / `== true` checks (nil compares equal to neither, so consumers
    -- that branch on the explicit value default to the safer side).
    return {
        durObj                 = s.durObj,
        isActive               = s.isActive,
        mirrorEpoch            = s.mirrorEpoch,
        viewerCategory         = _viewerCategoryByID[cooldownID],
        spellID                = info and info.spellID or nil,
        overrideSpellID        = info and info.overrideSpellID or nil,
        hasAura                = info and info.hasAura,
        selfAura               = info and info.selfAura,
        linkedSpellIDs         = info and info.linkedSpellIDs or nil,
        overrideTooltipSpellID = info and info.overrideTooltipSpellID or nil,
        pandemicActive         = s.pandemicActive,
        pandemicStateKnown     = s.pandemicStateKnown,
        cooldownID             = cooldownID,
    }
end

-- Resolve (spellID, viewerCategory) -> cooldownID. The viewer category
-- IS the disambiguator — a single spellID can be in multiple viewers
-- (e.g., a cast in essential and its buff in TrackedBuff). Callers that
-- know which viewer the entry belongs to (essential/utility/buff/trackedBar)
-- must pass it; the resolver disambiguates aura vs cooldown contexts that
-- way. Returns the cooldownID or nil.
function CDMBlizzMirror.GetCooldownIDForViewer(spellID, viewerCategory)
    if not (spellID and viewerCategory) then return nil end
    local catMap = _cdIDByCatSpell[viewerCategory]
    if not catMap then return nil end
    return catMap[spellID]
end

function CDMBlizzMirror.GetDirectCooldownIDForViewer(spellID, viewerCategory)
    if not (spellID and viewerCategory) then return nil end
    local catMap = _directCDIDByCatSpell[viewerCategory]
    if not catMap then return nil end
    return catMap[spellID]
end

-- Returns the live mirror state for the (spellID, viewerCategory) pair.
-- This is the primary entry point for resolvers — it's the
-- "get-the-child-by-cooldownID-for-aura" path: spellID maps to cooldownID
-- in the explicit viewer the entry belongs to, and the child for that
-- cooldownID owns the live durObj / isActive snapshot.
function CDMBlizzMirror.GetMirroredStateForViewer(spellID, viewerCategory)
    local cdID = CDMBlizzMirror.GetDirectCooldownIDForViewer(spellID, viewerCategory)
        or CDMBlizzMirror.GetCooldownIDForViewer(spellID, viewerCategory)
    return PackState(cdID)
end

function CDMBlizzMirror.GetDirectMirroredStateForViewer(spellID, viewerCategory)
    local cdID = CDMBlizzMirror.GetDirectCooldownIDForViewer(spellID, viewerCategory)
    return PackState(cdID)
end

-- Lookup-only sibling that returns the live state of a specific cooldownID
-- without going through any spellID map.
function CDMBlizzMirror.GetStateByCooldownID(cooldownID)
    return PackState(cooldownID)
end

---------------------------------------------------------------------------
-- Custom-bar / unknown-viewer helpers.
--
-- A custom QUI bar can hold any mix of cooldowns and auras whose Blizzard
-- CDM children live in any category (essential / utility / buff /
-- trackedBar). The bar's own viewerType is a QUI identifier, not a
-- CooldownViewer category, so the resolver can't gate on viewerType to
-- find the right child. FindCooldownState/FindCooldownInfo probe the
-- cooldown viewers in priority order (essential -> utility); the first
-- category whose map contains the spellID wins. Built-in containers should
-- still pass their explicit viewerType to GetMirroredStateForViewer;
-- these helpers exist for the custom-bar and `unknown viewerType` cases.
---------------------------------------------------------------------------
function CDMBlizzMirror.FindCooldownState(spellID)
    if not spellID then return nil end
    local cdID = _cdIDByCatSpell.essential[spellID]
        or _cdIDByCatSpell.utility[spellID]
    return PackState(cdID)
end

function CDMBlizzMirror.FindCooldownInfo(spellID)
    if not spellID then return nil end
    local cdID = _cdIDByCatSpell.essential[spellID]
        or _cdIDByCatSpell.utility[spellID]
    return cdID and _cooldownInfoByID[cdID] or nil
end

-- Returns the viewer category name a spellID lives in, probed in cooldown-
-- first then aura-first order. Used by the composer to stamp custom-bar
-- entries with their canonical Blizzard-side category.
function CDMBlizzMirror.FindCategoryForSpellID(spellID)
    if not spellID then return nil end
    if _cdIDByCatSpell.essential[spellID]  then return "essential"  end
    if _cdIDByCatSpell.utility[spellID]    then return "utility"    end
    if _cdIDByCatSpell.buff[spellID]       then return "buff"       end
    if _cdIDByCatSpell.trackedBar[spellID] then return "trackedBar" end
    return nil
end

-- Returns the CooldownViewer info struct (hasAura, selfAura, linkedSpellIDs,
-- overrideTooltipSpellID, etc.) captured at Walk time. Per-category lookup
-- to avoid the ambiguous "any cdID matching this spellID" behavior.
function CDMBlizzMirror.GetCooldownInfoForViewer(spellID, viewerCategory)
    local cdID = CDMBlizzMirror.GetCooldownIDForViewer(spellID, viewerCategory)
    if not cdID then return nil end
    return _cooldownInfoByID[cdID]
end

function CDMBlizzMirror.GetCooldownInfoByCooldownID(cooldownID)
    return cooldownID and _cooldownInfoByID[cooldownID] or nil
end

---------------------------------------------------------------------------
-- Backward-compat shim. Old callers used GetMirroredState(spellID) which
-- returned whichever cdID won the last-write race in a single global map.
-- That behavior is wrong (cross-category contamination), so this shim now
-- searches in viewer-priority order: aura viewers first (buff -> trackedBar)
-- because aura resolvers were the dominant caller, then cooldown viewers
-- (essential -> utility). New code should use GetMirroredStateForViewer
-- with the entry's explicit viewerType.
---------------------------------------------------------------------------
function CDMBlizzMirror.GetMirroredState(spellID)
    if not spellID then return nil end
    local cdID = _cdIDByCatSpell.buff[spellID]
        or _cdIDByCatSpell.trackedBar[spellID]
        or _cdIDByCatSpell.essential[spellID]
        or _cdIDByCatSpell.utility[spellID]
    return PackState(cdID)
end

function CDMBlizzMirror.GetCooldownInfo(spellID)
    if not spellID then return nil end
    local cdID = _cdIDByCatSpell.buff[spellID]
        or _cdIDByCatSpell.trackedBar[spellID]
        or _cdIDByCatSpell.essential[spellID]
        or _cdIDByCatSpell.utility[spellID]
    if not cdID then return nil end
    return _cooldownInfoByID[cdID]
end

---------------------------------------------------------------------------
-- Diagnostic dump.
--
-- Pretty-prints C_CooldownViewer.GetCooldownViewerCooldownInfo plus the
-- mirror's tracked fields for every walked cooldownID, optionally filtered
-- by spell name substring (case-insensitive) or numeric spellID. Use to
-- inspect what selfAura / hasAura / linkedSpellIDs / etc. actually
-- contain for a given spell — Blizzard's field semantics are not always
-- intuitive from the documentation.
--
-- Wired to /qui cdm_info [filter] in init.lua.
---------------------------------------------------------------------------
local function FormatLinkedIDs(ids)
    if type(ids) ~= "table" then return tostring(ids) end
    local parts = {}
    for _, lid in ipairs(ids) do parts[#parts + 1] = tostring(lid) end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function ResolveSpellName(spellID)
    if not spellID then return nil end
    if Sources and Sources.QuerySpellName then
        local name = Sources.QuerySpellName(spellID)
        if type(name) == "string" then return name end
    end
    return nil
end

function CDMBlizzMirror.DumpInfoForSpell(filter)
    local numericFilter = tonumber(filter)
    local stringFilter
    if not numericFilter and type(filter) == "string" and filter ~= "" then
        stringFilter = filter:lower()
    end

    local function entryMatches(cdID, info)
        if not numericFilter and not stringFilter then return true end
        if numericFilter then
            if info.spellID == numericFilter
                or info.overrideSpellID == numericFilter
                or info.overrideTooltipSpellID == numericFilter
                or cdID == numericFilter then
                return true
            end
            if type(info.linkedSpellIDs) == "table" then
                for _, lid in ipairs(info.linkedSpellIDs) do
                    if lid == numericFilter then return true end
                end
            end
            return false
        end
        local sid = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
        local name = ResolveSpellName(sid)
        if name and name:lower():find(stringFilter, 1, true) then return true end
        return false
    end

    local prefix = "|cff60A5FA[CDM info]|r"
    local count = 0
    for cdID, info in pairs(_cooldownInfoByID) do
        if entryMatches(cdID, info) then
            count = count + 1
            local cat = _viewerCategoryByID[cdID] or "?"
            local sid = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
            local name = ResolveSpellName(sid) or "?"

            -- Re-query the live API so we can see whether stored info has
            -- drifted from current Blizzard state.
            local liveInfo
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local li = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if li then liveInfo = li end
            end

            local s = _mirrorState[cdID]

            print(("%s cdID=%d cat=%s spell='%s' (id=%s)"):format(
                prefix, cdID, cat, name, tostring(sid)))
            print(("  stored: spellID=%s overrideSpellID=%s overrideTooltipSpellID=%s"):format(
                tostring(info.spellID),
                tostring(info.overrideSpellID),
                tostring(info.overrideTooltipSpellID)))
            print(("          selfAura=%s  hasAura=%s  charges=%s  isKnown=%s"):format(
                tostring(info.selfAura),
                tostring(info.hasAura),
                tostring(info.charges),
                tostring(info.isKnown)))
            print(("          linkedSpellIDs=%s"):format(
                FormatLinkedIDs(info.linkedSpellIDs)))

            if liveInfo then
                local diverged =
                       liveInfo.selfAura ~= info.selfAura
                    or liveInfo.hasAura ~= info.hasAura
                    or liveInfo.charges ~= info.charges
                    or liveInfo.isKnown ~= info.isKnown
                if diverged then
                    print(("  live  : selfAura=%s  hasAura=%s  charges=%s  isKnown=%s  (differs from stored)"):format(
                        tostring(liveInfo.selfAura),
                        tostring(liveInfo.hasAura),
                        tostring(liveInfo.charges),
                        tostring(liveInfo.isKnown)))
                end
            else
                print("  live  : <API returned nil>")
            end

            if s then
                print(("  mirror: isActive=%s  durObj=%s  auraInstanceID=%s  auraUnit=%s  epoch=%s"):format(
                    tostring(s.isActive),
                    tostring(s.durObj),
                    tostring(s.auraInstanceID),
                    tostring(s.auraUnit),
                    tostring(s.mirrorEpoch)))
            else
                print("  mirror: <no state>")
            end
        end
    end
    if count == 0 then
        print(("%s no entries match filter %s"):format(prefix, tostring(filter)))
    else
        print(("%s dumped %d entrie(s)."):format(prefix, count))
    end
end

---------------------------------------------------------------------------
-- Hook installation (one-shot per child frame).
--
-- Blizzard's CDM viewer pools/reuses child frames across rebuilds — a frame
-- that displayed cooldownID X at bind time may later display cooldownID Y
-- (talent change, spec change, viewer rebuild). `_quiMirrorBound` is set on
-- the frame to avoid re-installing the hook closure, but the closure itself
-- must read `cooldownID` from the live frame each fire — never close over
-- the bind-time cooldownID. State is lazy-initialized so reassigned
-- cooldownIDs that haven't been formally walked still get a state slot.
---------------------------------------------------------------------------
local function EnsureState(cdID, frame)
    if not cdID then return nil end
    local s = _mirrorState[cdID]
    if not s then
        s = {
            durObj      = nil,
            isActive    = false,
            mirrorEpoch = 0,
            lastTouch   = 0,
            pandemicActive = false,
            pandemicStateKnown = nil,
        }
        _mirrorState[cdID] = s
    end
    if not _viewerCategoryByID[cdID] and frame and _categoryByFrame[frame] ~= nil then
        _viewerCategoryByID[cdID] = CATEGORY_NAMES[_categoryByFrame[frame]]
    end
    return s
end

local function SafeFrameField(frame, key)
    if not frame then return nil end
    local value = frame[key]
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function DecodePotentialSecretBoolean(value)
    if issecretvalue and issecretvalue(value) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local scalar = C_CurveUtil.EvaluateColorValueFromBoolean(value, 1, 0)
            if not (issecretvalue and issecretvalue(scalar)) and type(scalar) == "number" then
                return scalar >= 0.5
            end
        end
        return nil
    end

    if type(value) == "boolean" then
        return value
    end
    return nil
end

local function SafeFrameBooleanField(frame, key)
    if not frame then return nil end
    local value = frame[key]
    return DecodePotentialSecretBoolean(value)
end

local function IsAuraViewerCategory(cdID)
    local cat = cdID and _viewerCategoryByID[cdID]
    return cat == "buff" or cat == "trackedBar"
end

local function ReadChildSemanticActive(child, cdID)
    if not child then return nil end

    if IsAuraViewerCategory(cdID) then
        -- Aura children's frame fields (isActive, wasSetFromAura, etc.) are
        -- not authoritative active-aura signals: BuffIconItemMixin.Refresh
        -- CooldownInfo drives the swipe via CooldownFrame_Set rather than
        -- the SetWasSetFromAura path, and Blizzard's mixin force-shows the
        -- parent for inactive auras so visibility-based reads also lie.
        -- Authoritative aura activity comes from
        -- C_UnitAuras.GetAuraDuration on the captured auraInstanceID
        -- (see VerifyStateFreshness above) — return nil here so the
        -- caller's fallbackActive drives the bind-time write while the
        -- per-PackState freshness check owns the steady-state truth.
        return nil
    end

    if child.IsShown then
        return child:IsShown() and true or false
    end
    return nil
end

local function RefreshChildSemanticState(child, cdID, fallbackActive)
    local s = EnsureState(cdID, child)
    if not s then return nil end

    -- Totem-driven mirror states are owned by HandlePlayerTotemUpdate.
    -- Show/Hide cycles on the Blizzard child don't reflect totem expiry, so
    -- letting them clobber s.isActive here would race the totem handler and
    -- leave the icon stuck inactive between PLAYER_TOTEM_UPDATE events.
    if _totemActiveCDID[cdID] then return s.isActive end

    local active = ReadChildSemanticActive(child, cdID)
    if active == nil then
        active = fallbackActive == true
    end
    s.isActive = active
    if not active then
        s.durObj = nil
        s.pandemicActive = false
        s.pandemicStateKnown = nil
        if SetHostPandemicState then
            SetHostPandemicState(cdID, nil, false)
        end
    end
    s.lastTouch = GetTime()
    return active
end

SetHostPandemicState = function(cdID, active, known)
    local host = _hostByCooldownID and _hostByCooldownID[cdID]
    if not (host and host._isBlizzBacked == cdID) then return end

    if known == true then
        host._blizzPandemicActive = active == true
        host._blizzPandemicStateKnown = true
    else
        host._blizzPandemicActive = nil
        host._blizzPandemicStateKnown = nil
    end

    local glows = ns._OwnedGlows
    if glows and glows.UpdatePandemicGlow then
        glows.UpdatePandemicGlow(host)
    end
end

local function SetChildPandemicState(child, active)
    local cdID = child and child.cooldownID
    if not cdID then return end

    local s = EnsureState(cdID, child)
    if not s then return end
    if active ~= true and s.pandemicStateKnown ~= true then
        return
    end
    s.pandemicActive = active == true
    s.pandemicStateKnown = true
    s.lastTouch = GetTime()

    SetHostPandemicState(cdID, s.pandemicActive, true)
end

---------------------------------------------------------------------------
-- Taint diagnostic logger.
--
-- Toggle: /run QUI_CDM_TAINT_DEBUG = true; /rl
--
-- Implementation lives in cdm_debug.lua. The placeholder below is rebound
-- by cdm_debug.lua's BindAll() at the end of its load; cdm_debug.lua
-- also re-attaches the public CDMBlizzMirror.TaintLog method.
---------------------------------------------------------------------------
local TaintLog = function() end
function CDMBlizzMirror.TaintLog(...)
    return TaintLog(...)
end

---------------------------------------------------------------------------
-- CooldownInfo sanitization.
--
-- C_CooldownViewer.GetCooldownViewerCooldownInfo is annotated
-- `SecretArguments = "AllowedWhenUntainted"`. From a tainted call site,
-- its returned struct fields can be SECRET values (numbers/booleans/etc).
-- Storing those raw and later running `info.spellID <= 0` or
-- `info.selfAura == true` errors silently inside the icon visibility
-- loop's pcall — no user-facing error, no icon update.
--
-- Strip secrets at capture time so every consumer (MapCooldownInfoIDs,
-- StampAuraInstanceForCooldown, the resolver, SyncBlizzBackedIconState)
-- can treat the stored info as a plain Lua table with comparable values.
---------------------------------------------------------------------------
-- Order of operations matters: check IsSecretValue FIRST. Doing
-- `if v == nil then return nil end` before the secret strip would
-- itself error when v is secret, defeating the whole point. IsSecretValue
-- on nil is safe (returns false), so checking it first costs nothing.
-- The post-strip `==` and `>` operations only run on values we've
-- proven non-secret.
local function CleanScalar(v)
    if issecretvalue and issecretvalue(v) then return nil end
    -- v is non-secret here. nil passes through, non-secret values pass
    -- through. No `==` against v needed.
    return v
end

-- Decoding a secret boolean: C_CurveUtil.EvaluateColorValueFromBoolean
-- is annotated AllowedWhenTainted (it's how Blizzard's own UI extracts
-- self.isActive into a numeric to drive SetAlpha, etc.). Calling it on a
-- secret boolean with the args (1, 0) yields 1 if the bool was true, 0
-- if false. The scalar is sometimes also secret, so we re-check; when
-- it's clean we get a real true/false back. When the decode fails
-- entirely we return nil to signal "couldn't determine" rather than
-- forcing a default that destroys real data.
local function CleanBool(v)
    if issecretvalue and issecretvalue(v) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local scalar = C_CurveUtil.EvaluateColorValueFromBoolean(v, 1, 0)
            if not (issecretvalue and issecretvalue(scalar))
                and type(scalar) == "number" then
                return scalar >= 0.5
            end
        end
        return nil
    end
    if v == nil then return nil end
    if v then return true end
    return false
end

local function CleanLinkedIDs(ids)
    if type(ids) ~= "table" then return nil end
    local out
    for _, id in ipairs(ids) do
        local clean = CleanScalar(id)
        -- type() returns "number" for both clean numbers and secret
        -- numbers, but CleanScalar already returned nil for secrets, so
        -- by here clean is either nil or a normal Lua number that's
        -- safe to compare with `>`.
        if type(clean) == "number" and clean > 0 then
            out = out or {}
            out[#out + 1] = clean
        end
    end
    return out
end

local function SanitizeCooldownInfo(cdID, info)
    if not info then return nil end
    -- Log the RAW field types/secret-status before sanitization so we can
    -- see whether the API returned secrets in the user's environment.
    TaintLog("Sanitize",
        "cdID", cdID,
        "raw.spellID",                info.spellID,
        "raw.overrideSpellID",        info.overrideSpellID,
        "raw.overrideTooltipSpellID", info.overrideTooltipSpellID,
        "raw.selfAura",               info.selfAura,
        "raw.hasAura",                info.hasAura,
        "raw.charges",                info.charges,
        "raw.isKnown",                info.isKnown)
    return {
        cooldownID             = cdID,
        spellID                = CleanScalar(info.spellID),
        overrideSpellID        = CleanScalar(info.overrideSpellID),
        overrideTooltipSpellID = CleanScalar(info.overrideTooltipSpellID),
        linkedSpellIDs         = CleanLinkedIDs(info.linkedSpellIDs),
        selfAura               = CleanBool(info.selfAura),
        hasAura                = CleanBool(info.hasAura),
        charges                = CleanBool(info.charges),
        isKnown                = CleanBool(info.isKnown),
    }
end

local function MapCooldownInfoIDs(catMap, info, cdID)
    if not (catMap and info and cdID) then return end

    local function add(id, overwrite)
        if type(id) ~= "number" or id <= 0 then return end
        if overwrite or not catMap[id] then
            catMap[id] = cdID
        end
    end

    local catName
    for name, map in pairs(_cdIDByCatSpell) do
        if map == catMap then
            catName = name
            break
        end
    end
    local directMap = catName and _directCDIDByCatSpell[catName] or nil
    local function addDirect(id, overwrite)
        if not directMap or type(id) ~= "number" or id <= 0 then return end
        if overwrite or not directMap[id] then
            directMap[id] = cdID
        end
    end

    local isAuraCat = catName == "buff" or catName == "trackedBar"

    add(info.overrideSpellID or info.spellID, true)
    add(info.spellID, false)
    add(info.overrideSpellID, false)
    if isAuraCat then
        add(info.overrideTooltipSpellID, true)

        if type(info.linkedSpellIDs) == "table" then
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                add(linkedID, false)
            end
        end
    end

    if isAuraCat then
        -- The documented CooldownViewerCooldown struct exposes every
        -- identity Blizzard associates with this aura child. Treat all of
        -- them as direct identities for binding, with tooltip/linked aura
        -- IDs winning over source ability IDs on collisions.
        addDirect(info.overrideTooltipSpellID, true)
        if type(info.linkedSpellIDs) == "table" then
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                addDirect(linkedID, true)
            end
        end
        addDirect(info.overrideSpellID or info.spellID, false)
        addDirect(info.spellID, false)
        addDirect(info.overrideSpellID, false)
        return
    end

    addDirect(info.overrideSpellID or info.spellID, true)
    addDirect(info.spellID, false)
    addDirect(info.overrideSpellID, false)
end

local function ClearCatalogMaps()
    for _, catMap in pairs(_cdIDByCatSpell) do
        wipe(catMap)
    end
    for _, directMap in pairs(_directCDIDByCatSpell) do
        wipe(directMap)
    end
    wipe(_cooldownInfoByID)
    wipe(_childByCooldownID)
    wipe(_viewerCategoryByID)
    wipe(_spellNameToCDID)
end

local function RemoveCooldownIDFromMaps(cdID)
    if not cdID then return end
    for _, catMap in pairs(_cdIDByCatSpell) do
        for spellID, mappedCDID in pairs(catMap) do
            if mappedCDID == cdID then
                catMap[spellID] = nil
            end
        end
    end
    for _, directMap in pairs(_directCDIDByCatSpell) do
        for spellID, mappedCDID in pairs(directMap) do
            if mappedCDID == cdID then
                directMap[spellID] = nil
            end
        end
    end
end

local function FindMappedCooldownID(...)
    for i = 1, select("#", ...) do
        local spellID = select(i, ...)
        if spellID then
            for catName, catMap in pairs(_cdIDByCatSpell) do
                local cdID = catMap[spellID]
                if cdID then return cdID, catName end
            end
            for catName, directMap in pairs(_directCDIDByCatSpell) do
                local cdID = directMap[spellID]
                if cdID then return cdID, catName end
            end
        end
    end
    return nil, nil
end

local function BindChildHooks(child, cooldownID, viewerCategoryNum)
    -- Always refresh the bind-time category map and seed state for the
    -- current cooldownID, even if the frame was already bound.
    _categoryByFrame[child] = viewerCategoryNum
    _childByCooldownID[cooldownID]  = child
    _viewerCategoryByID[cooldownID] = CATEGORY_NAMES[viewerCategoryNum]
    EnsureState(cooldownID, child)
    RefreshChildSemanticState(child, cooldownID, false)

    local cooldownFrame = child.Cooldown
    if cooldownFrame then
        _childByCooldownFrame[cooldownFrame] = child
    end

    if child._quiMirrorBound then
        return
    end
    child._quiMirrorBound = true

    -- Cooldown widget hooks — capture active-state transitions on every
    -- Blizzard push, regardless of which Cooldown method the mixin uses.
    --
    -- Different CooldownViewer item mixins drive their swipe through
    -- different APIs:
    --   * EssentialItemMixin / UtilityItemMixin → SetCooldownFromDurationObject
    --   * BuffIconItemMixin / BuffBarItemMixin  → CooldownFrame_Set →
    --     Cooldown:SetCooldown(start, duration, ...)
    -- Hooking only the DurationObject path means buff items never flip
    -- s.isActive=true via the hook path. We hook SetCooldown too — args
    -- can be secret (start/duration are secret in combat post-12.0.5),
    -- but we DON'T read them; the call's existence is the signal.
    --
    -- Cooldown:Clear is the de-active edge for both mixins; capture it.
    --
    -- Reads the original owner child's cooldownID dynamically. The Cooldown
    -- subframe can be reparented onto a QUI host for rendering, so
    -- self:GetParent() is not reliable after ApplyChildToHost().
    local function _ownerCooldownID(self)
        local owner = _childByCooldownFrame[self]
        local cdID = owner and owner.cooldownID
        if not cdID then
            owner = self.GetParent and self:GetParent()
            cdID = owner and owner.cooldownID
        end
        return cdID, owner
    end

    if cooldownFrame and cooldownFrame.SetCooldownFromDurationObject then
        hooksecurefunc(cooldownFrame, "SetCooldownFromDurationObject", function(self, durObj)
            local cdID, owner = _ownerCooldownID(self)
            if not cdID then return end
            local s = EnsureState(cdID, owner)
            s.durObj      = durObj
            s.isActive    = true
            s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
            s.lastTouch   = GetTime()
            if CDMBlizzMirror.TaintLog then
                CDMBlizzMirror.TaintLog("hook.SCFDO", "cdID", cdID)
            end
        end)
    end

    -- Active-edge: hook EVERY Cooldown setter Blizzard might use. Different
    -- mixins / different code paths use different methods; missing any of
    -- them leaves m.isActive stuck at false. We don't read the args (some
    -- are secret in combat post-12.0.5); the call's existence is the signal.
    local function _activateMirror(self, methodName)
        local cdID, owner = _ownerCooldownID(self)
        if not cdID then return end
        local s = EnsureState(cdID, owner)
        s.isActive    = true
        s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
        s.lastTouch   = GetTime()
        if CDMBlizzMirror.TaintLog then
            CDMBlizzMirror.TaintLog("hook." .. methodName, "cdID", cdID)
        end
    end
    if cooldownFrame and cooldownFrame.SetCooldown then
        hooksecurefunc(cooldownFrame, "SetCooldown", function(self)
            _activateMirror(self, "SetCooldown")
        end)
    end
    if cooldownFrame and cooldownFrame.SetCooldownFromExpirationTime then
        hooksecurefunc(cooldownFrame, "SetCooldownFromExpirationTime", function(self)
            _activateMirror(self, "SetCooldownFromExpirationTime")
        end)
    end
    if cooldownFrame and cooldownFrame.SetCooldownDuration then
        hooksecurefunc(cooldownFrame, "SetCooldownDuration", function(self)
            _activateMirror(self, "SetCooldownDuration")
        end)
    end
    if cooldownFrame and cooldownFrame.SetCooldownUNIX then
        hooksecurefunc(cooldownFrame, "SetCooldownUNIX", function(self)
            _activateMirror(self, "SetCooldownUNIX")
        end)
    end

    if cooldownFrame and cooldownFrame.Clear then
        hooksecurefunc(cooldownFrame, "Clear", function(self)
            local cdID = _ownerCooldownID(self)
            if not cdID then return end
            local s = _mirrorState[cdID]
            if not s then return end

            -- Aura-category cdIDs: VerifyStateFreshness in PackState is
            -- the authoritative path for s.isActive (it polls
            -- C_UnitAuras with a stamped auraInstanceID and handles all
            -- the corner cases: duration-bearing auras, durationless
            -- presence indicators, combat API restrictions). The Clear
            -- hook fires from Blizzard's mixin and can spuriously wipe
            -- state for hasAura=false entries (Lesser Ghoul / Unholy
            -- Aura / Reaping) where the mixin doesn't track the aura at
            -- all, and in combat where C_UnitAuras returns nil due to
            -- restrictions even though the aura is still on the unit.
            -- Refresh durObj opportunistically when the API gives us a
            -- live one, but never clobber isActive from this path.
            local cat = _viewerCategoryByID[cdID]
            if cat == "buff" or cat == "trackedBar" then
                if s.auraInstanceID and Sources and Sources.QueryAuraDuration then
                    local durObj = Sources.QueryAuraDuration(s.auraUnit or "player", s.auraInstanceID)
                    if durObj then
                        s.durObj    = durObj
                        s.lastTouch = GetTime()
                    end
                end
                if CDMBlizzMirror.TaintLog then
                    CDMBlizzMirror.TaintLog("hook.Clear.skip-aura-cat",
                        "cdID", cdID)
                end
                return
            end

            -- Non-aura cdID (essential / utility / cooldown-only):
            -- Clear is the de-active edge.
            s.isActive = false
            s.durObj   = nil
            s.pandemicActive = false
            s.pandemicStateKnown = nil
            if SetHostPandemicState then
                SetHostPandemicState(cdID, nil, false)
            end
            s.lastTouch = GetTime()
            if CDMBlizzMirror.TaintLog then
                CDMBlizzMirror.TaintLog("hook.Clear", "cdID", cdID)
            end
        end)
    end

    if child.ShowPandemicStateFrame then
        hooksecurefunc(child, "ShowPandemicStateFrame", function(self)
            SetChildPandemicState(self, true)
        end)
    end
    if child.HidePandemicStateFrame then
        hooksecurefunc(child, "HidePandemicStateFrame", function(self)
            SetChildPandemicState(self, false)
        end)
    end

    -- Visibility hooks — drive isActive without polling.
    hooksecurefunc(child, "Show", function(self)
        local cdID = self.cooldownID
        if not cdID then return end
        local forced = _forceShowingChild[self] == true
        _forceShowingChild[self] = nil
        RefreshChildSemanticState(self, cdID, not forced)
    end)

    hooksecurefunc(child, "Hide", function(self)
        local cdID = self.cooldownID
        if not cdID then return end
        RefreshChildSemanticState(self, cdID, false)
    end)
end

---------------------------------------------------------------------------
-- Discovery walk. OOC-only. Idempotent — re-runs on viewer rebuilds and
-- only binds new children (existing bindings short-circuit via the
-- `_quiMirrorBound` flag).
---------------------------------------------------------------------------
local _walkPendingOnRegen = false

local function Walk()
    -- Allow execution during the ADDON_LOADED / PLAYER_ENTERING_WORLD
    -- safe window even though InCombatLockdown() returns true on a combat
    -- /reload. Walk's body is hook-installation + read-only C_CooldownViewer
    -- calls + Lua table writes — none are protected. Without this bypass,
    -- combat /reload leaves the catalog empty and every Blizz-backed icon
    -- (essential/utility/buff/trackedBar) fails to bind until combat ends.
    if InCombatLockdown() and not (ns and ns._inInitSafeWindow) then
        _walkPendingOnRegen = true
        return
    end
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return
    end

    ClearCatalogMaps()

    for catNum = 0, 3 do
        local viewerName = CATEGORY_GLOBALS[catNum]
        local viewer     = _G[viewerName]
        if viewer and viewer.GetChildren then
            local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(catNum, false)
            if type(cooldownIDs) == "table" then
                local validIDs = {}
                for _, cid in ipairs(cooldownIDs) do
                    validIDs[cid] = true
                end

                local children = { viewer:GetChildren() }
                for i = 1, #children do
                    local child = children[i]
                    local cdID  = child and child.cooldownID
                    if cdID and validIDs[cdID] then
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                        if info then
                            -- Sanitize before any field comparison. The API
                            -- can return secret values when called from a
                            -- tainted context; raw `info.spellID <= 0` etc.
                            -- below would error silently inside our pcall'd
                            -- callers and leave icons unupdated.
                            local clean = SanitizeCooldownInfo(cdID, info)
                            _cooldownInfoByID[cdID] = clean
                            local catName = CATEGORY_NAMES[catNum]
                            local catMap  = _cdIDByCatSpell[catName]
                            -- Map every stable spell identity Blizzard exposes
                            -- for this child into the SAME category bucket.
                            -- TrackedBuff entries often use
                            -- overrideTooltipSpellID as the real aura spell ID,
                            -- while spellID/overrideSpellID can point at the
                            -- cast ability; binding only the latter leaves
                            -- active buff icons with no viewer child.
                            MapCooldownInfoIDs(catMap, clean, cdID)
                            -- Index by spell name for PLAYER_TOTEM_UPDATE
                            -- lookups. _viewerCategoryByID was populated
                            -- inside BindChildHooks during the prior pass,
                            -- but for first-time entries we need to seed
                            -- it before the index call. EnsureState will
                            -- read _categoryByFrame[child] if available.
                            _viewerCategoryByID[cdID] = CATEGORY_NAMES[catNum]
                            _IndexSpellNameForCDID(cdID, clean)
                            BindChildHooks(child, cdID, catNum)
                        end
                    end
                end
            end
        end
    end
end

function CDMBlizzMirror.ForceRescan()
    Walk()
end

---------------------------------------------------------------------------
-- Lazy bind of newly-created CooldownViewer children.
--
-- Walk runs OOC only and rebuilds the catalog. But Blizzard's pool can
-- create new child frames AT ANY TIME — pet summoned in combat, talent
-- proc registers a new cdID, etc. Those children never get our hooks,
-- so their SetCooldown/SetCooldownFromDurationObject calls don't update
-- the mirror. The icon mirror's `m.isActive` stays false forever.
--
-- BindNewChildren is the additive sibling of Walk: it iterates viewer
-- children and binds any not yet seen, WITHOUT clearing catalog maps
-- or existing state. Lua-table writes and `hooksecurefunc` are both
-- safe in combat. Called from UNIT_AURA dispatch so combat-created
-- children get hooked the first time an aura event fires after their
-- creation.
---------------------------------------------------------------------------
-- Listeners notified when a previously-unknown cdID is freshly indexed
-- by BindNewChildren. Used by cdm_icon_factory to retry TryBindIconToBlizz
-- on icons that failed their initial bind because the Blizzard child
-- didn't exist yet (e.g. DT buff cdID 27925 is created lazily by
-- BuffIconCooldownViewer only when the buff applies — well after icon
-- creation at addon load).
--
-- Listener signature: function(cooldownID, viewerCategoryName)
-- Listeners run in UNIT_AURA dispatch context (potentially in combat),
-- so they must do Lua-table reads + safe frame ops only.
local _onChildBoundListeners = {}

function CDMBlizzMirror.AddOnChildBoundListener(callback)
    if type(callback) ~= "function" then return end
    _onChildBoundListeners[#_onChildBoundListeners + 1] = callback
end

local function FireOnChildBound(cdID, catName)
    if not (cdID and catName) then return end
    for i = 1, #_onChildBoundListeners do
        _onChildBoundListeners[i](cdID, catName)
    end
end

local function BindNewChildren()
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return
    end
    for catNum = 0, 3 do
        local viewerName = CATEGORY_GLOBALS[catNum]
        local viewer     = _G[viewerName]
        if viewer and viewer.GetChildren then
            local children = { viewer:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                local cdID  = child and child.cooldownID
                if cdID and not child._quiMirrorBound then
                    -- New child: capture info if we haven't already, install
                    -- hooks. Don't trample _cooldownInfoByID if Walk already
                    -- captured this cdID — that would erase our sanitized
                    -- info. Only fill it in when missing.
                    if not _cooldownInfoByID[cdID] then
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                        if info then
                            local clean = SanitizeCooldownInfo(cdID, info)
                            _cooldownInfoByID[cdID] = clean
                            local catName = CATEGORY_NAMES[catNum]
                            local catMap  = _cdIDByCatSpell[catName]
                            MapCooldownInfoIDs(catMap, clean, cdID)
                            _viewerCategoryByID[cdID] = catName
                            _IndexSpellNameForCDID(cdID, clean)
                        end
                    end
                    BindChildHooks(child, cdID, catNum)
                    if CDMBlizzMirror.TaintLog then
                        CDMBlizzMirror.TaintLog("LazyBind", "cdID", cdID,
                            "cat", CATEGORY_NAMES[catNum])
                    end
                    -- Fire the new-child signal whenever BindChildHooks
                    -- newly attaches to a child. The outer
                    -- `not child._quiMirrorBound` gate guarantees this is
                    -- a fresh attach, regardless of whether the cdID's
                    -- info struct was already cached by an earlier Walk.
                    -- The QUI icon factory needs the *child-bound* signal,
                    -- not the info-cached signal — a child being bound is
                    -- what flips HasChildForCooldownID from false to true,
                    -- which is the gate that previously rejected its bind.
                    FireOnChildBound(cdID, CATEGORY_NAMES[catNum])
                end
            end
        end
    end
end

CDMBlizzMirror.BindNewChildren = BindNewChildren

---------------------------------------------------------------------------
-- BLIZZARD VIEWER SUPPRESSION
--
-- The mirror requires Blizzard's CDM to be running (children populate, durObj
-- feed fires) — but when QUI's CDM is the active engine the user shouldn't
-- see Blizzard's UI competing with QUI's. We suppress visuals via alpha=0
-- + mouse off + a SetAlpha hook + a periodic alpha enforcer that catches
-- Blizzard's internal restoration paths during cooldown activations.
--
-- Suppression is gated on QUI_IsCDMMasterEnabled. When the user disables
-- QUI's CDM, Unsuppress is called and Blizzard's UI returns.
--
-- All operations are taint-safe: SetAlpha is C-side, EnableMouse is
-- C-side, hooksecurefunc is the recommended observation primitive.
---------------------------------------------------------------------------
local function IsCDMMasterEnabled()
    local checker = _G.QUI_IsCDMMasterEnabled
    return type(checker) ~= "function" or checker()
end

local _viewersSuppressed = false
local _viewerAlphaHooked   = {}    -- [viewerName] = true
local _selectionAlphaHooked = {}   -- [viewerName] = true (.Selection overlay)
local _alphaEnforcer = CreateFrame("Frame")
local _alphaEnforcerElapsed = 0

local UnsuppressViewers  -- forward decl

local function HookViewerAlpha(viewer, viewerName)
    if _viewerAlphaHooked[viewerName] then return end
    _viewerAlphaHooked[viewerName] = true
    hooksecurefunc(viewer, "SetAlpha", function(self, alpha)
        if _viewersSuppressed and alpha and alpha > 0 then
            -- Defer to next frame so we don't fight inside Blizzard's
            -- own protected execution chain (cutscene exit, etc.).
            C_Timer.After(0, function()
                if _viewersSuppressed and IsCDMMasterEnabled() and self:GetAlpha() > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end)
end

-- viewer.Selection is the Edit Mode selection overlay. It uses
-- IgnoreParentAlpha so the parent viewer's alpha=0 doesn't hide it.
-- During Blizzard Edit Mode it becomes visible (teal border + handles)
-- to let users move/resize the viewer — defeating our suppression for
-- the duration of the edit session. Hook Show/SetAlpha to fight it.
local function HookSelectionAlpha(viewer, viewerName)
    if _selectionAlphaHooked[viewerName] then return end
    if not viewer.Selection then return end
    _selectionAlphaHooked[viewerName] = true
    local sel = viewer.Selection
    hooksecurefunc(sel, "Show", function(self)
        if _viewersSuppressed and IsCDMMasterEnabled() then
            C_Timer.After(0, function()
                if _viewersSuppressed and IsCDMMasterEnabled() then
                    self:SetAlpha(0)
                end
            end)
        end
    end)
    hooksecurefunc(sel, "SetAlpha", function(self, alpha)
        if _viewersSuppressed and alpha and alpha > 0 then
            C_Timer.After(0, function()
                if _viewersSuppressed and IsCDMMasterEnabled() and self:GetAlpha() > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end)
end

local function DisableViewerChildrenMouse(viewer)
    if not viewer or not viewer.GetChildren then return end
    local n = select('#', viewer:GetChildren())
    if not n then return end
    for i = 1, n do
        local child = select(i, viewer:GetChildren())
        if child then
            if child.EnableMouse then child.EnableMouse(child, false) end
            if child.SetMouseClickEnabled then child.SetMouseClickEnabled(child, false) end
            if child.SetMouseMotionEnabled then child.SetMouseMotionEnabled(child, false) end
        end
    end
end

local function AlphaEnforcerOnUpdate(self, dt)
    if not IsCDMMasterEnabled() then
        self:SetScript("OnUpdate", nil)
        if UnsuppressViewers then UnsuppressViewers() end
        return
    end

    _alphaEnforcerElapsed = _alphaEnforcerElapsed + dt
    if _alphaEnforcerElapsed < 0.1 then return end
    _alphaEnforcerElapsed = 0

    for catNum = 0, 3 do
        local viewer = _G[CATEGORY_GLOBALS[catNum]]
        if viewer then
            if viewer.GetAlpha and viewer:GetAlpha() > 0 then
                viewer.SetAlpha(viewer, 0)
            end
            if viewer.Selection and viewer.Selection.GetAlpha
               and viewer.Selection:GetAlpha() > 0 then
                viewer.Selection.SetAlpha(viewer.Selection, 0)
            end
            -- Blizzard creates children dynamically when cooldowns fire;
            -- catch any new ones that escaped our initial pass.
            DisableViewerChildrenMouse(viewer)
        end
    end
end
_alphaEnforcer:SetScript("OnUpdate", nil)

local function SuppressViewers()
    if _viewersSuppressed then return end
    if not IsCDMMasterEnabled() then return end

    for catNum = 0, 3 do
        local viewerName = CATEGORY_GLOBALS[catNum]
        local viewer = _G[viewerName]
        if viewer then
            viewer.SetAlpha(viewer, 0)
            if viewer.EnableMouse then viewer.EnableMouse(viewer, false) end
            if viewer.SetMouseClickEnabled then viewer.SetMouseClickEnabled(viewer, false) end
            if viewer.SetMouseMotionEnabled then viewer.SetMouseMotionEnabled(viewer, false) end
            DisableViewerChildrenMouse(viewer)
            HookViewerAlpha(viewer, viewerName)
            -- .Selection is the Edit Mode overlay (IgnoreParentAlpha-flagged,
            -- so parent alpha=0 doesn't hide it). Hide + hook independently.
            if viewer.Selection then
                viewer.Selection.SetAlpha(viewer.Selection, 0)
                HookSelectionAlpha(viewer, viewerName)
            end
        end
    end
    _viewersSuppressed = true
    _alphaEnforcerElapsed = 0
    _alphaEnforcer:SetScript("OnUpdate", AlphaEnforcerOnUpdate)
end

UnsuppressViewers = function()
    if not _viewersSuppressed then return end
    _viewersSuppressed = false
    _alphaEnforcer:SetScript("OnUpdate", nil)

    for catNum = 0, 3 do
        local viewer = _G[CATEGORY_GLOBALS[catNum]]
        if viewer then
            viewer.SetAlpha(viewer, 1)
            if viewer.EnableMouse then viewer.EnableMouse(viewer, true) end
            if viewer.SetMouseClickEnabled then viewer.SetMouseClickEnabled(viewer, true) end
            if viewer.SetMouseMotionEnabled then viewer.SetMouseMotionEnabled(viewer, true) end
            -- Selection alpha is normally 0 outside Edit Mode; restoring to 1
            -- here lets Blizzard's Edit Mode show it again. Blizzard sets it
            -- back to 0 when leaving Edit Mode through their own paths.
            if viewer.Selection then
                viewer.Selection.SetAlpha(viewer.Selection, 1)
            end

            -- Restore mouse on existing children too so tooltips work.
            local n = select('#', viewer:GetChildren())
            if n then
                for i = 1, n do
                    local child = select(i, viewer:GetChildren())
                    if child then
                        if child.EnableMouse then child.EnableMouse(child, true) end
                        if child.SetMouseClickEnabled then child.SetMouseClickEnabled(child, true) end
                        if child.SetMouseMotionEnabled then child.SetMouseMotionEnabled(child, true) end
                    end
                end
            end
        end
    end
end

function CDMBlizzMirror.Suppress() SuppressViewers() end
function CDMBlizzMirror.Unsuppress() UnsuppressViewers() end

function CDMBlizzMirror.SyncSuppressionToMaster()
    if IsCDMMasterEnabled() then
        SuppressViewers()
    else
        UnsuppressViewers()
    end
end

---------------------------------------------------------------------------
-- BLIZZARD CHILD REPARENT (host-slot binding)
--
-- Each QUI icon for a Blizzard-CDM-backed entry registers itself as a
-- "host" for a specific cooldownID. The mirror reparents the matching
-- Blizzard child frame into the host so the user sees Blizzard's native
-- cooldown swipe / charge text / overlay (driven by Blizzard's own
-- secret-safe code path) rendered inside QUI's container layout. The
-- viewer's pool keeps the child in its active set, so OnUpdate keeps
-- ticking the swipe even after SetParent.
--
-- Re-host strategy: Blizzard's RefreshData reassigns cooldownIDs to
-- pool-acquired item frames after every layout / data event. We hook
-- RefreshData (post) and walk the active pool, reparenting each item
-- frame to the host registered for its current cooldownID. This handles:
--   * RefreshLayout (Edit Mode change / hotfix / spec change)
--   * Data refresh (talent change / spell override)
--   * Pool re-acquire (frame may carry a different cooldownID after
--     Blizzard's pool releases-and-reacquires)
--
-- The child stays in the viewer's pool (the active set is unchanged),
-- so Blizzard's update / event passes continue to drive it.
---------------------------------------------------------------------------
_hostByCooldownID          = {}    -- [cooldownID] = QUI host frame
local _cooldownIDByHost    = {}    -- [host frame] = cooldownID
local _refreshDataHooked   = false
-- Hosts whose SetFrameLevel has been hooked. The hook re-applies the
-- (host_level + 5) offset to the bound child so any later normalization
-- pass (e.g. NormalizeIconFrameLevels) that bumps the host's level
-- doesn't strand the child at a lower level — which would let the host's
-- Border draw on top of the child's Icon.
local _hostLevelHooked = setmetatable({}, { __mode = "k" })
-- Children whose Hide we've hooked so a Blizzard mixin attempt to hide
-- them gets reverted on the next frame. Essential/Utility icons must
-- remain visible — when Blizzard's mixin hides them in combat the QUI
-- host slot ends up rendering as a black border square with no spell
-- texture (because the reparented child's Icon goes invisible).
local _childPreventHideHooked = setmetatable({}, { __mode = "k" })
-- Cooldown subframes whose SetSwipeColor / SetDrawSwipe / SetDrawEdge /
-- SetSwipeTexture have been hooked to defend QUI's swipe styling against
-- Blizzard's mixin re-applying its template defaults. The hook reads
-- `cd._quiIntendedSwipeColor` (set by cdm_effects.lua when QUI applies styling)
-- and reverts a non-matching write on the next frame.
local _swipeStyleHooked = setmetatable({}, { __mode = "k" })

local function HookSwipeStyleDefense(cd)
    if not cd or _swipeStyleHooked[cd] then return end
    _swipeStyleHooked[cd] = true
    -- Synchronous revert: when Blizzard's mixin writes a different value,
    -- immediately re-apply QUI's intended state inside the same frame.
    -- The recursive call back into the setter fires our hook again, but
    -- the args match `_quiIntended*` and we no-op out — no infinite loop.
    -- Synchronous (vs deferred) prevents the 1-frame flicker window where
    -- Blizzard's value is visible.
    if cd.SetSwipeColor then
        hooksecurefunc(cd, "SetSwipeColor", function(self, r, g, b, a)
            local want = self._quiIntendedSwipeColor
            if not want then return end
            local wa = want[4] or 1
            local ca = a or 1
            if r == want[1] and g == want[2] and b == want[3] and ca == wa then
                return  -- QUI's own call, no-op
            end
            self.SetSwipeColor(self, want[1], want[2], want[3], wa)
        end)
    end
    if cd.SetDrawSwipe then
        hooksecurefunc(cd, "SetDrawSwipe", function(self, draw)
            local want = self._quiIntendedDrawSwipe
            if want == nil then return end
            if draw == want then return end
            self.SetDrawSwipe(self, want)
        end)
    end
    if cd.SetDrawEdge then
        hooksecurefunc(cd, "SetDrawEdge", function(self, draw)
            local want = self._quiIntendedDrawEdge
            if want == nil then return end
            if draw == want then return end
            self.SetDrawEdge(self, want)
        end)
    end
    if cd.SetSwipeTexture then
        hooksecurefunc(cd, "SetSwipeTexture", function(self, texture)
            local want = self._quiIntendedSwipeTexture
            if not want then return end
            if texture == want then return end
            self.SetSwipeTexture(self, want)
        end)
    end
end

ns._CDMHookSwipeStyleDefense = HookSwipeStyleDefense

-- Always force the parent item frame to stay shown for ALL Blizzard-backed
-- categories. Why for buff/trackedBar too:
--   * Blizzard's mixin Hides the parent when the aura isn't currently
--     active. With subframes reparented onto our host, hiding the parent
--     alone doesn't hide our reparented widgets — but it does stop the
--     mixin's data feed (the mixin only writes to subframes when the
--     parent is showing in its UpdateShownState pass).
--   * Forcing parent stays shown means the mixin keeps polling/updating,
--     so when the aura activates the subframes get fresh data immediately.
--   * For inactive auras the reparented Icon/Cooldown still hold the last
--     spell's data — that's a known cosmetic limitation we can address
--     later by also tracking aura-applied/aura-removed events.
local function HookChildPreventHide(child)
    if _childPreventHideHooked[child] then return end
    if not (child and child.Show) then return end
    _childPreventHideHooked[child] = true
    hooksecurefunc(child, "Hide", function(self)
        local cdID = self.cooldownID
        if not cdID then return end
        local h = _hostByCooldownID[cdID]
        if not (h and h._isBlizzBacked == cdID) then return end
        -- Defer to next frame to avoid fighting inside Blizzard's
        -- protected execution chain (mirrors the SuppressViewers pattern
        -- for Edit Mode .Selection overlay).
        C_Timer.After(0, function()
            if h._isBlizzBacked == cdID and self.IsShown and not self:IsShown() then
                _forceShowingChild[self] = true
                self.Show(self)
            end
        end)
    end)
end

local CHILD_LEVEL_OFFSET = 5

local function HookHostFrameLevel(host)
    if _hostLevelHooked[host] then return end
    if not (host and host.SetFrameLevel) then return end
    _hostLevelHooked[host] = true
    hooksecurefunc(host, "SetFrameLevel", function(self)
        local cdID = _cooldownIDByHost[self]
        if not cdID then return end
        local child = _childByCooldownID[cdID]
        if not (child and child.SetFrameLevel and child.GetFrameLevel) then return end
        local target = (self:GetFrameLevel() or 1) + CHILD_LEVEL_OFFSET
        if child:GetFrameLevel() ~= target then
            child.SetFrameLevel(child, target)
        end
    end)
end

-- Reparent a single Blizzard subframe onto the QUI host, anchored
-- SetAllPoints, with mouse off (host owns mouse routing). Idempotent.
local function ReparentSubframe(sub, host, levelOffset)
    if not (sub and host) then return end
    if sub.SetParent and sub:GetParent() ~= host then
        sub.SetParent(sub, host)
    end
    if host.GetFrameStrata and sub.SetFrameStrata then
        sub.SetFrameStrata(sub, host:GetFrameStrata() or "MEDIUM")
    end
    if sub.ClearAllPoints then sub.ClearAllPoints(sub) end
    if sub.SetAllPoints  then sub.SetAllPoints(sub, host) end
    if levelOffset and host.GetFrameLevel and sub.SetFrameLevel then
        sub.SetFrameLevel(sub, (host:GetFrameLevel() or 1) + levelOffset)
    end
    if sub.EnableMouse           then sub.EnableMouse(sub, false) end
    if sub.SetMouseClickEnabled  then sub.SetMouseClickEnabled(sub, false) end
    if sub.SetMouseMotionEnabled then sub.SetMouseMotionEnabled(sub, false) end
end

local function FindFirstFontString(owner)
    if not owner then return nil end
    if owner.GetObjectType then
        local kind = owner.GetObjectType(owner)
        if kind == "FontString" then
            return owner
        end
    end

    if owner.GetRegions then
        local regions = { owner:GetRegions() }
        if regions then
            for i = 1, #regions do
                local region = regions[i]
                if region and region.GetObjectType then
                    local kind = region.GetObjectType(region)
                    if kind == "FontString" then
                        return region
                    end
                end
            end
        end
    end

    if owner.GetChildren then
        local children = { owner:GetChildren() }
        if children then
            for i = 1, #children do
                local found = FindFirstFontString(children[i])
                if found then return found end
            end
        end
    end

    return nil
end

local BLIZZ_ICON_CHROME_ATLASES = {
    ["UI-HUD-CoolDownManager-IconOverlay"] = true,
    ["UI-CooldownManager-OORshadow"] = true,
}

local function HideVisualRegion(region)
    if not region then return end
    if region.Hide then region.Hide(region) end
    if region.SetAlpha then region.SetAlpha(region, 0) end
end

local function HideDecorativeRegion(region)
    if not (region and region.GetObjectType) then return false end

    local kind = region.GetObjectType(region)
    if kind == "MaskTexture" then
        HideVisualRegion(region)
        return true
    end

    if kind ~= "Texture" then return false end
    local atlas
    if region.GetAtlas then
        local value = region.GetAtlas(region)
        if value then atlas = value end
    end
    -- atlas can be a secret string in combat — indexing a Lua table with a
    -- secret key errors. Guard before the lookup; secret atlases never match
    -- our hardcoded chrome list anyway, so skipping is safe.
    if atlas and not (issecretvalue and issecretvalue(atlas))
        and BLIZZ_ICON_CHROME_ATLASES[atlas] then
        HideVisualRegion(region)
        return true
    end

    return false
end

local function IsCooldownFrame(frame)
    if not frame then return false end
    if frame.SetCooldownFromDurationObject and frame.SetDrawSwipe then
        return true
    end
    if not frame.GetObjectType then return false end
    local kind = frame.GetObjectType(frame)
    return kind == "Cooldown"
end

local function StripIconChrome(owner, visited, depth)
    if not owner then return end
    depth = depth or 0
    if depth > 3 then return end
    visited = visited or {}
    if visited[owner] then return end
    visited[owner] = true

    if IsCooldownFrame(owner) then
        return
    end

    if HideDecorativeRegion(owner) then
        return
    end

    local function hideField(key)
        local region = owner[key]
        if region then HideVisualRegion(region) end
    end

    hideField("IconOverlay")
    hideField("OutOfRangeOverlay")
    hideField("OutOfRangeShadow")
    hideField("DebuffBorder")

    if owner.GetNumMaskTextures and owner.GetMaskTexture and owner.RemoveMaskTexture then
        local count = owner.GetNumMaskTextures(owner)
        if count and count > 0 then
            for i = count, 1, -1 do
                local mask = owner.GetMaskTexture(owner, i)
                if mask then
                    owner.RemoveMaskTexture(owner, mask)
                    HideVisualRegion(mask)
                end
            end
        end
    end

    if owner.GetRegions then
        local regions = { owner:GetRegions() }
        if regions then
            for i = 1, #regions do
                StripIconChrome(regions[i], visited, depth + 1)
            end
        end
    end

    if owner.Icon and owner.Icon ~= owner then
        StripIconChrome(owner.Icon, visited, depth + 1)
    end
    if owner.IconTexture and owner.IconTexture ~= owner then
        StripIconChrome(owner.IconTexture, visited, depth + 1)
    end

    if owner.GetChildren then
        local children = { owner:GetChildren() }
        if children then
            for i = 1, #children do
                StripIconChrome(children[i], visited, depth + 1)
            end
        end
    end
end

local function ApplyChildToHost(child, host)
    if not (child and host) then return end
    -- Strategy: leave Blizzard's child item frame parented to its source
    -- viewer (untainted, owned by Blizzard's mixin). Reparent only the
    -- VISUAL subframes onto our QUI host. Blizzard's mixin keeps writing
    -- to subframes via `child.Cooldown:Set...`, `child.Icon:SetTexture`,
    -- `child.ChargeCount:Show()` — those operate on the subframe regardless
    -- of where the subframe is now parented.
    --
    -- This avoids tainting the parent item frame entirely, sidesteps
    -- Blizzard's Hide/Show cascade onto its (now-empty) parent, and lets
    -- QUI's container/Border/keybind chrome stay in lockstep with the
    -- visible Blizzard widgets.
    host._blizzIcon = nil
    host._blizzCooldownFrame = nil
    host._blizzDurationText = nil
    host._blizzChargeCount = nil
    host._blizzChargeCountText = nil
    host._blizzApplications = nil
    host._blizzApplicationsText = nil

    -- The visual subframes are hosted by QUI, but the parent item frame must
    -- remain shown in Blizzard's pool so its mixin keeps feeding Icon,
    -- Cooldown, DurationText, Applications, and ChargeCount. We ignore this
    -- forced Show for semantic active-state tracking; aura activity still
    -- comes from Blizzard's fields/duration feed, not parent visibility.
    HookChildPreventHide(child)
    if child.IsShown and child.Show and not child:IsShown() then
        _forceShowingChild[child] = true
        child.Show(child)
        RefreshChildSemanticState(child, child.cooldownID, false)
    end

    -- Spell Icon texture (ARTWORK layer)
    if child.Icon then
        ReparentSubframe(child.Icon, host)
        host._blizzIcon = child.Icon
    end

    -- Cooldown swipe frame — needs a frame level above the host so the
    -- swipe paints over the icon. SetCooldownFromDurationObject from
    -- Blizzard's mixin continues to feed durObj into this frame.
    if child.Cooldown then
        _childByCooldownFrame[child.Cooldown] = child
        ReparentSubframe(child.Cooldown, host, 2)
        if child.Cooldown.Show then
            child.Cooldown.Show(child.Cooldown)
        end
        if child.Cooldown.SetHideCountdownNumbers
           and not (host._rowConfig and host._rowConfig.hideDurationText) then
            child.Cooldown.SetHideCountdownNumbers(child.Cooldown, false)
        end
        -- Expose the reparented Cooldown frame on the host so QUI's
        -- styling pass (cdm_icons.lua ConfigureIcon, cdm_effects.lua
        -- ApplySwipeToIcon) can also write font/color/position/swipe
        -- settings to it. Without this, Blizzard's default white swipe +
        -- default font show through.
        host._blizzCooldownFrame = child.Cooldown
        host._blizzDurationText = FindFirstFontString(child.Cooldown)
        -- Defend QUI's swipe styling against Blizzard's mixin re-applying
        -- template defaults on every cooldown update — without this hook,
        -- the swipe color flickers between QUI and Blizzard values.
        HookSwipeStyleDefense(child.Cooldown)
    end

    -- ChargeCount (Essential/Utility) and Applications (BuffIcon) text
    -- containers. Reparent above the cooldown swipe. Expose refs on the
    -- host so QUI's ConfigureIcon stack-styling pass can find them.
    if child.ChargeCount then
        ReparentSubframe(child.ChargeCount, host, 4)
        host._blizzChargeCount = child.ChargeCount
        host._blizzChargeCountText = child.ChargeCount.Current
            or FindFirstFontString(child.ChargeCount)
    end
    if child.Applications then
        ReparentSubframe(child.Applications, host, 4)
        host._blizzApplications = child.Applications
        host._blizzApplicationsText = child.Applications.Applications
            or FindFirstFontString(child.Applications)
    end

    -- CooldownFlash (GCD pulse flipbook) — keep above the swipe
    if child.CooldownFlash then ReparentSubframe(child.CooldownFlash, host, 3) end

    -- BuffBar template — Icon is a Frame here (not a texture), and Bar is
    -- the status bar that drives duration display.
    if child.Bar then ReparentSubframe(child.Bar, host, 2) end

    -- Strip masks and decorative CDM chrome from both parent-level and
    -- nested icon frames so only QUI's own Border remains visible.
    StripIconChrome(child)
    if child.Icon then StripIconChrome(child.Icon) end

    -- DebuffBorder (BuffIcon/BuffBar templates) — Blizzard's red border
    -- for debuffs. QUI's own Border serves the same purpose; hide.
    if child.DebuffBorder and child.DebuffBorder.Hide then
        child.DebuffBorder.Hide(child.DebuffBorder)
    end

    -- Apply QUI's swipe styling to the reparented Blizzard cooldown so
    -- its swipe color/texture/draw flags match the user's QUI settings
    -- instead of Blizzard's template defaults (white at full alpha).
    -- The swipe module's ApplyToIcon writes to both `icon.Cooldown`
    -- (QUI native, hidden) and `icon._blizzCooldownFrame` (the reparent
    -- target we just bound). Called here because UpdateIconCooldown's
    -- per-tick path short-circuits for Blizzard-backed icons and never
    -- reaches its swipe-restyle call.
    local swipe = ns._OwnedSwipe
    if swipe and swipe.ApplyToIcon then
        swipe.ApplyToIcon(host)
    end

    local icons = ns.CDMIcons
    if icons and icons.ConfigureIcon and host._rowConfig then
        icons.ConfigureIcon(host, host._rowConfig)
    elseif icons and icons.ApplyBlizzIconTexCoord then
        icons.ApplyBlizzIconTexCoord(host)
    end
end

-- Blizzard's CooldownViewerMixin:RefreshData iterates the active pool
-- and reassigns cooldownIDs onto item frames. By the time RefreshData
-- returns, every active item frame's `.cooldownID` reflects the latest
-- Blizzard catalog. Walk the pool and re-host any frame whose cooldownID
-- has a registered QUI host.
local function ReHostActivePool(viewer)
    if not (viewer and viewer.itemFramePool and viewer.itemFramePool.EnumerateActive) then
        return
    end
    for itemFrame in viewer.itemFramePool:EnumerateActive() do
        local cdID = itemFrame and itemFrame.cooldownID
        if cdID then
            local host = _hostByCooldownID[cdID]
            if host then
                -- Update child-by-cooldownID cache as well — the active
                -- frame for this cdID may have changed after a pool
                -- release/reacquire.
                _childByCooldownID[cdID] = itemFrame
                ApplyChildToHost(itemFrame, host)
            end
        end
    end
end

local function HookRefreshData()
    if _refreshDataHooked then return end
    if not (CooldownViewerMixin and CooldownViewerMixin.RefreshData) then return end
    hooksecurefunc(CooldownViewerMixin, "RefreshData", ReHostActivePool)
    _refreshDataHooked = true
end

-- RegisterHostSlot(host, cooldownID): bind a QUI host frame to a Blizzard
-- cooldownID. Idempotent on repeated calls with the same pair. If the host
-- previously held a different cooldownID, that prior binding is cleared.
function CDMBlizzMirror.RegisterHostSlot(host, cooldownID)
    if not (host and cooldownID) then return end
    HookRefreshData()

    local prior = _cooldownIDByHost[host]
    if prior and prior ~= cooldownID then
        if _hostByCooldownID[prior] == host then
            _hostByCooldownID[prior] = nil
        end
    end
    _hostByCooldownID[cooldownID] = host
    _cooldownIDByHost[host]       = cooldownID

    -- Reparent immediately if the child is already known.
    local child = _childByCooldownID[cooldownID]
    if child then
        ApplyChildToHost(child, host)
    end
end

function CDMBlizzMirror.UnregisterHostSlot(host)
    if not host then return end
    local cdID = _cooldownIDByHost[host]
    if not cdID then return end
    _cooldownIDByHost[host] = nil
    if _hostByCooldownID[cdID] == host then
        _hostByCooldownID[cdID] = nil
    end
    host._blizzIcon = nil
    host._blizzCooldownFrame = nil
    host._blizzDurationText = nil
    host._blizzChargeCount = nil
    host._blizzChargeCountText = nil
    host._blizzApplications = nil
    host._blizzApplicationsText = nil
    -- We don't actively SetParent the child back to the viewer. Blizzard's
    -- pool reset callback will hide+clear-anchors on next RefreshLayout,
    -- and the next Acquire reparents the child back to the viewer's
    -- itemContainerFrame. Leaving it alone is harmless.
end

-- Lookup helper used by the icon factory to decide whether an entry can
-- be Blizzard-backed (yes if a child currently exists for the cooldownID).
function CDMBlizzMirror.HasChildForCooldownID(cooldownID)
    return cooldownID and _childByCooldownID[cooldownID] ~= nil or false
end

-- Returns the host frame currently bound to `cooldownID`, or nil if no
-- frame has registered a host slot for it. Used by the sibling absorber
-- in cdm_icon_factory.lua to decide whether to claim an unclaimed
-- sibling cdID with a hidden frame, or skip claiming if a real QUI icon
-- already owns the binding.
function CDMBlizzMirror.GetHostForCooldownID(cooldownID)
    return cooldownID and _hostByCooldownID[cooldownID] or nil
end

local function SafeCall(owner, method, ...)
    local fn = owner and owner[method]
    if not fn then return nil end
    return fn(owner, ...)
end

local function SafeFieldText(owner)
    local text = SafeCall(owner, "GetText")
    if text == nil then return "nil" end
    return tostring(text)
end

local function SafeShown(owner)
    if not owner then return "nil" end
    local shown = SafeCall(owner, "IsShown")
    return tostring(shown == true)
end

local function SafeTexture(owner)
    if not owner then return "nil" end
    local tex = SafeCall(owner, "GetTexture")
    if tex ~= nil then return tostring(tex) end
    local atlas = SafeCall(owner, "GetAtlas")
    if atlas ~= nil then return "atlas:" .. tostring(atlas) end
    return "nil"
end

local function SafeName(owner)
    if not owner then return "nil" end
    local name = SafeCall(owner, "GetName")
    return tostring(name or owner)
end

local function FormatDebugIDList(ids)
    if type(ids) ~= "table" or #ids == 0 then return "nil" end
    local out = {}
    for i, id in ipairs(ids) do
        out[i] = tostring(id)
    end
    return table.concat(out, ",")
end

local function AddDebugLine(lines, ...)
    local out = {}
    for i = 1, select("#", ...) do
        out[#out + 1] = tostring(select(i, ...))
    end
    lines[#lines + 1] = table.concat(out, " ")
end

function CDMBlizzMirror.GetChildDebugLines(cooldownID)
    local lines = {}
    local child = cooldownID and _childByCooldownID[cooldownID]
    local state = PackState(cooldownID)
    AddDebugLine(lines,
        "state cdID=", cooldownID,
        "cat=", state and state.viewerCategory,
        "active=", state and tostring(state.isActive == true),
        "hasDurObj=", state and tostring(state.durObj ~= nil),
        "epoch=", state and state.mirrorEpoch,
        "spell=", state and state.spellID,
        "ov=", state and state.overrideSpellID,
        "tooltip=", state and state.overrideTooltipSpellID,
        "links=", state and FormatDebugIDList(state.linkedSpellIDs))

    if not child then
        AddDebugLine(lines, "child=nil")
        return lines
    end

    AddDebugLine(lines,
        "child name=", SafeName(child),
        "shown=", SafeShown(child),
        "alpha=", SafeCall(child, "GetAlpha"),
        "cooldownID=", child.cooldownID,
        "wasSetFromAura=", tostring(SafeFrameBooleanField(child, "wasSetFromAura")),
        "parent=", SafeName(SafeCall(child, "GetParent")))
    AddDebugLine(lines,
        "child fields isActive=", tostring(SafeFrameBooleanField(child, "isActive")),
        "cooldownIsActive=", tostring(SafeFrameBooleanField(child, "cooldownIsActive")),
        "wasSetFromCooldown=", tostring(SafeFrameBooleanField(child, "wasSetFromCooldown")),
        "wasSetFromCharges=", tostring(SafeFrameBooleanField(child, "wasSetFromCharges")),
        "cooldownStart=", tostring(SafeFrameField(child, "cooldownStartTime")),
        "cooldownDuration=", tostring(SafeFrameField(child, "cooldownDuration")),
        "cooldownShowSwipe=", tostring(SafeFrameBooleanField(child, "cooldownShowSwipe")))

    local icon = child.Icon
    AddDebugLine(lines,
        "Icon shown=", SafeShown(icon),
        "alpha=", SafeCall(icon, "GetAlpha"),
        "tex=", SafeTexture(icon),
        "parent=", SafeName(SafeCall(icon, "GetParent")))

    local cd = child.Cooldown
    local startMS, durationMS = SafeCall(cd, "GetCooldownTimes")
    AddDebugLine(lines,
        "Cooldown shown=", SafeShown(cd),
        "alpha=", SafeCall(cd, "GetAlpha"),
        "times=", tostring(startMS), "/", tostring(durationMS),
        "duration=", tostring(SafeCall(cd, "GetCooldownDuration")),
        "drawSwipe=", tostring(SafeCall(cd, "GetDrawSwipe")),
        "drawEdge=", tostring(SafeCall(cd, "GetDrawEdge")),
        "parent=", SafeName(SafeCall(cd, "GetParent")))

    AddDebugLine(lines,
        "DurationText shown=", SafeShown(FindFirstFontString(cd)),
        "text=", SafeFieldText(FindFirstFontString(cd)))

    local apps = child.Applications
    AddDebugLine(lines,
        "Applications shown=", SafeShown(apps),
        "text=", SafeFieldText(apps and (apps.Applications or FindFirstFontString(apps))),
        "parent=", SafeName(SafeCall(apps, "GetParent")))

    local charges = child.ChargeCount
    AddDebugLine(lines,
        "ChargeCount shown=", SafeShown(charges),
        "text=", SafeFieldText(charges and (charges.Current or FindFirstFontString(charges))),
        "parent=", SafeName(SafeCall(charges, "GetParent")))

    local bar = child.Bar
    AddDebugLine(lines,
        "Bar shown=", SafeShown(bar),
        "value=", tostring(SafeCall(bar, "GetValue")),
        "parent=", SafeName(SafeCall(bar, "GetParent")))

    return lines
end

---------------------------------------------------------------------------
-- Totem-backed mirror state.
--
-- Some Blizzard CDM children (e.g. Anti-Magic Zone) are activated by a
-- totem on the player, not by an aura. Their visual is driven via a
-- PLAYER_TOTEM_UPDATE-bound mixin path that bypasses the 5 Cooldown setter
-- hooks above; without a separate handler m.isActive stays false forever
-- and the icon never pops in.
--
-- Resolution: rebuild a spell-name → cdID index over aura-category cdIDs
-- whenever Walk runs (and incrementally on BindNewChildren). On each
-- PLAYER_TOTEM_UPDATE, look up each active totem's name in that index and
-- stamp the matching cdID active with GetTotemDuration's DurationObject.
-- The DurationObject is secret-safe — it flows through SetCooldownFromDurationObject
-- without ever being read from Lua.
---------------------------------------------------------------------------
local function _CleanSpellNameForCDID(info)
    if not info then return nil end
    local sid = info.spellID or info.overrideSpellID or info.overrideTooltipSpellID
    if type(sid) ~= "number" then return nil end
    if not (Sources and Sources.QuerySpellName) then return nil end
    local name = Sources.QuerySpellName(sid)
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    return name:lower()
end

function _IndexSpellNameForCDID(cdID, info)
    if not (cdID and info) then return end
    local cat = _viewerCategoryByID[cdID]
    if cat ~= "buff" and cat ~= "trackedBar" then return end
    local key = _CleanSpellNameForCDID(info)
    if not key then return end
    _spellNameToCDID[key] = cdID
end

local function _RebuildSpellNameIndex()
    wipe(_spellNameToCDID)
    for cdID, info in pairs(_cooldownInfoByID) do
        _IndexSpellNameForCDID(cdID, info)
    end
end

function HandlePlayerTotemUpdate()
    if type(GetTotemInfo) ~= "function" then
        if CDMBlizzMirror.TaintLog then
            CDMBlizzMirror.TaintLog("totem.update.no-api")
        end
        return
    end

    -- Lazy-rebuild if Walk hasn't populated the index yet (e.g. PLAYER_LOGIN
    -- arrives before any catalog walk has completed).
    if next(_spellNameToCDID) == nil and next(_cooldownInfoByID) ~= nil then
        _RebuildSpellNameIndex()
    end

    local indexCount = 0
    for _ in pairs(_spellNameToCDID) do indexCount = indexCount + 1 end
    if CDMBlizzMirror.TaintLog then
        CDMBlizzMirror.TaintLog("totem.update.enter",
            "indexEntries", indexCount,
            "MAX_TOTEMS", MAX_TOTEMS)
    end

    local seen = {}
    local maxSlots = (type(MAX_TOTEMS) == "number" and MAX_TOTEMS) or 4
    -- Probe one extra slot in case MAX_TOTEMS is locally underreported.
    for slot = 1, maxSlots + 1 do
        local tok = true; local hasTotem, totemName, _, _, totemIcon = GetTotemInfo(slot)
        local nameSecret = issecretvalue and issecretvalue(totemName) or false
        local hasTotemSecret = issecretvalue and issecretvalue(hasTotem) or false
        local nameRender = nameSecret and "<SECRET>" or tostring(totemName)
        if CDMBlizzMirror.TaintLog then
            CDMBlizzMirror.TaintLog("totem.scan",
                "slot", slot,
                "ok", tok,
                "hasTotem", hasTotemSecret and "<SECRET>" or hasTotem,
                "nameSecret", nameSecret,
                "name", nameRender,
                "icon", totemIcon)
        end
        -- A non-empty totemName already implies an active totem, so we don't
        -- strictly need to test hasTotem when it's secret. Short-circuit via
        -- hasTotemSecret so Lua never evaluates the bool of a secret value.
        if tok and (hasTotemSecret or hasTotem) and not nameSecret
            and type(totemName) == "string" and totemName ~= "" then
            local key = totemName:lower()
            local cdID = _spellNameToCDID[key]
            if CDMBlizzMirror.TaintLog then
                CDMBlizzMirror.TaintLog("totem.match",
                    "slot", slot, "key", key, "cdID", cdID)
            end
            if cdID then
                seen[cdID] = true
                _totemActiveCDID[cdID] = slot
                local s = EnsureState(cdID, _childByCooldownID[cdID])
                if s then
                    s.isActive    = true
                    s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
                    s.lastTouch   = GetTime()
                    if type(GetTotemDuration) == "function" then
                        local durObj = GetTotemDuration(slot)
                        -- GetTotemDuration returns a DurationObject in
                        -- modern API; numeric returns mean the slot is
                        -- inactive or the API hasn't been adopted for that
                        -- totem. Only stamp when we actually got an object.
                        if durObj and type(durObj) ~= "number" then
                            s.durObj = durObj
                        end
                    end
                end
                if CDMBlizzMirror.TaintLog then
                    CDMBlizzMirror.TaintLog("totem.activate",
                        "slot", slot, "cdID", cdID)
                end
            end
        end
    end

    -- Deactivation: any cdID we previously stamped that no longer matches an
    -- active totem this pass. Walk removes stale catalog entries; their
    -- mirror state lingers but a no-op clear is harmless.
    for cdID in pairs(_totemActiveCDID) do
        if not seen[cdID] then
            _totemActiveCDID[cdID] = nil
            local s = _mirrorState[cdID]
            if s then
                s.isActive    = false
                s.durObj      = nil
                s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
                s.lastTouch   = GetTime()
            end
            if CDMBlizzMirror.TaintLog then
                CDMBlizzMirror.TaintLog("totem.deactivate", "cdID", cdID)
            end
        end
    end
end

CDMBlizzMirror.HandlePlayerTotemUpdate = HandlePlayerTotemUpdate

---------------------------------------------------------------------------
-- Event lifecycle.
---------------------------------------------------------------------------
local _eventFrame = CreateFrame("Frame")
_eventFrame:RegisterEvent("PLAYER_LOGIN")
_eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
_eventFrame:RegisterEvent("TRAIT_TREE_CHANGED")
-- COOLDOWN_VIEWER_DATA_LOADED / SPELL_OVERRIDE_UPDATED / TABLE_HOTFIXED
-- now flow through the ns.CDMIndex broker; subscription installed at the
-- bottom of this file at priority 10 (rebuilds before consumers read).
_eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- UNIT_AURA stamps each mirror state with the current auraInstanceID so
-- VerifyStateFreshness can poll C_UnitAuras.GetAuraDuration to detect
-- expired auras (Blizzard's mixin force-shows inactive aura children, so
-- the Hide/clearing path doesn't fire on aura expiry).
-- Target included for trackedBar(selfAura=false) — target debuff entries.
_eventFrame:RegisterUnitEvent("UNIT_AURA", "player", "pet", "target")
-- Target swap — stored target instIDs reference the previous target and
-- become stale immediately. Re-capture so the new target's existing
-- debuffs get fresh instIDs without waiting for a UNIT_AURA tick.
_eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Totem-backed CDM entries (Anti-Magic Zone, etc.) — only signal we get
-- when the Blizzard mixin's totem-driven path activates the child.
_eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")

-- Targeted refresh after a base→override swap. Searches every per-category
-- map for an existing cooldownID for either spellID, refreshes that cdID's
-- info struct, and rewires the per-category bucket accordingly. Falls back
-- to full Walk if no existing cdID is found (the override may have introduced
-- a new spell that wasn't yet known to any viewer).
local function RefreshSpellOverridePair(baseSpellID, overrideSpellID)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
        Walk()
        return
    end
    local cdID, hostCatName = FindMappedCooldownID(baseSpellID, overrideSpellID)
    if not cdID or not hostCatName then
        Walk()
        return
    end
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    if not info then
        Walk()
        return
    end
    -- Sanitize: API returns may be secret in tainted execution.
    local clean = SanitizeCooldownInfo(cdID, info)
    _cooldownInfoByID[cdID] = clean
    local catMap = _cdIDByCatSpell[hostCatName]
    RemoveCooldownIDFromMaps(cdID)
    MapCooldownInfoIDs(catMap, clean, cdID)
    -- The spell name for this cdID may have changed (override swap rewires
    -- the underlying spell). Rebuild the name index so PLAYER_TOTEM_UPDATE
    -- looks up the new name. Cheap O(n) over _cooldownInfoByID.
    _RebuildSpellNameIndex()
end

_eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "UNIT_AURA" then
        -- Stamp the auraInstanceID for any cdID this aura's spellID maps
        -- to. For full updates and explicit removals, also verify stamped
        -- states for this unit immediately so stale active flags do not
        -- keep buff icons visible until a later lazy read.
        --
        -- Also catch CooldownViewer children created post-Walk: pet
        -- summon, talent activation, dynamic class spec swaps, etc. all
        -- can introduce cdIDs Blizzard hadn't surfaced when our last Walk
        -- ran. Without lazy-binding their hooks, their SetCooldown calls
        -- bypass us and m.isActive stays false → icon never shows.
        BindNewChildren()
        local unit, updateInfo = arg1, arg2
        if unit ~= "player" and unit ~= "pet" and unit ~= "target" then return end
        -- Whatever the updateInfo shape (isFullUpdate, addedAuras only, or
        -- removed-only), re-run CaptureAurasFromUnit. For player that walks
        -- every catalog spellID via C_UnitAuras.GetPlayerAuraBySpellID, so
        -- a fresh aura application for one spell catches sibling cdIDs that
        -- share aliases too. Idempotent on already-stamped cdIDs.
        CaptureAurasFromUnit(unit)
        if not updateInfo
            or updateInfo.isFullUpdate
            or (updateInfo.removedAuraInstanceIDs
                and #updateInfo.removedAuraInstanceIDs > 0) then
            EvictRemovedMirrorStatesForUnit(unit)
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        -- Proactively invalidate every mirror state stamped from the
        -- prior target. Without this, target-side stamps (e.g. VP / DP
        -- debuffs) linger after the user drops their target until
        -- VerifyStateFreshness eventually polls — visible lag.
        --
        -- Keying off s.auraUnit (not info.selfAura) is correct: it
        -- records the unit that actually held the aura at stamp time,
        -- regardless of how Blizzard's misleading selfAura flag
        -- classifies the cdID.
        for cdID, s in pairs(_mirrorState) do
            if s.auraUnit == "target" then
                s.auraUnit = nil
                ClearMirrorAuraState(cdID, s, "target-changed")
            end
        end
        -- Re-capture for the new target. If there's no target, this is
        -- a no-op (AuraUtil.ForEachAura on an invalid unit yields nothing)
        -- and the prior invalidation pass leaves all target-side states
        -- correctly cleared.
        CaptureAurasFromUnit("target")
        return
    end

    if event == "PLAYER_TOTEM_UPDATE" then
        HandlePlayerTotemUpdate()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if _walkPendingOnRegen then
            _walkPendingOnRegen = false
            Walk()
        end
        -- Re-stamp on combat exit: auraInstanceIDs re-randomize on combat
        -- enter for some scenarios (encounter/M+/PvP), so the values stamped
        -- pre-combat may be stale post-combat.
        CaptureAurasFromUnit("player")
        CaptureAurasFromUnit("pet")
        CaptureAurasFromUnit("target")
        CDMBlizzMirror.SyncSuppressionToMaster()
        return
    end

    -- PLAYER_LOGIN / PLAYER_ENTERING_WORLD / PLAYER_SPECIALIZATION_CHANGED /
    -- TRAIT_TREE_CHANGED reshape the catalog (spec change moves spells
    -- in/out of viewers; talent change rewires linkedSpellIDs). The
    -- CDM-table events (DATA_LOADED / SPELL_OVERRIDE_UPDATED /
    -- TABLE_HOTFIXED) are handled via the ns.CDMIndex broker subscription
    -- at the bottom of this file.
    if InCombatLockdown() then
        _walkPendingOnRegen = true
        return
    end

    Walk()
    -- Bootstrap aura instance IDs after the catalog walk so any auras
    -- already on the player/pet/target at /reload or zone-in get tracked
    -- without waiting for them to re-apply.
    CaptureAurasFromUnit("player")
    CaptureAurasFromUnit("pet")
    CaptureAurasFromUnit("target")
    -- Bootstrap totem-backed mirror state too: a /reload mid-AMZ would
    -- otherwise wait for the next totem state change before flipping
    -- isActive=true on the matching cdID.
    HandlePlayerTotemUpdate()
    CDMBlizzMirror.SyncSuppressionToMaster()
end)

---------------------------------------------------------------------------
-- DEBUG IMPORT BINDING (rebound by cdm_debug.lua's BindAll())
---------------------------------------------------------------------------
function CDMBlizzMirror._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        TaintLog = d.Taint or TaintLog
    end
end

---------------------------------------------------------------------------
-- CDMIndex broker subscription (priority 10 — runs before any consumer
-- that depends on the mirror's catalog being current).
---------------------------------------------------------------------------
if ns.CDMIndex and ns.CDMIndex.Subscribe then
    ns.CDMIndex.Subscribe("blizz_mirror", function(reason, baseSpellID, overrideSpellID)
        if InCombatLockdown() then
            _walkPendingOnRegen = true
            return
        end
        if reason == "override" then
            -- Targeted: only the (baseSpellID, overrideSpellID) pair changed.
            RefreshSpellOverridePair(baseSpellID, overrideSpellID)
        else
            -- data_loaded / hotfix / refresh_layout: full catalog rebuild
            -- and bootstrap of aura/totem state, matching the previous
            -- COOLDOWN_VIEWER_DATA_LOADED / TABLE_HOTFIXED handler exactly.
            Walk()
            CaptureAurasFromUnit("player")
            CaptureAurasFromUnit("pet")
            CaptureAurasFromUnit("target")
            HandlePlayerTotemUpdate()
            CDMBlizzMirror.SyncSuppressionToMaster()
        end
    end, 10)
end
