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
-- Blizzard can reuse a cooldownID in more than one viewer category. Store
-- child-backed state by (category, cooldownID), and keep the cooldownID-only
-- tables as legacy/default lookups for older call sites and broad debug tools.
local _childByCooldownID   = {}    -- [cooldownID] = default child frame
local _viewerCategoryByID  = {}    -- [cooldownID] = default category
local _childByInstanceKey  = {}    -- ["category:cooldownID"] = child frame
local _viewerCategoryByKey = {}    -- ["category:cooldownID"] = category
local _instanceKeyByCatID  = {
    essential  = {},
    utility    = {},
    buff       = {},
    trackedBar = {},
}
local _defaultInstanceKeyByID = {} -- [cooldownID] = first-seen instance key
local _mirrorState         = {}    -- [instanceKey] = { durObj, isActive, mirrorEpoch, lastTouch }
local _packedStateByInstanceKey = {} -- [instanceKey] = read-only public state table
local _categoryByFrame     = {}    -- [child frame] = catNum (lazy-init category fallback)
local _childByCooldownFrame = setmetatable({}, { __mode = "k" }) -- [child.Cooldown] = child frame
local _forceShowingChild    = setmetatable({}, { __mode = "k" }) -- [child] = true for mirror-internal Show()
local _textOwnerHooked      = setmetatable({}, { __mode = "k" }) -- [Applications/ChargeCount owner] = true
local SetHostPandemicState
local GCD_MAX_DURATION = 1.75
-- CooldownViewerCooldown info captured from C_CooldownViewer.GetCooldownViewerCooldownInfo:
--   cooldownID, spellID, overrideSpellID, overrideTooltipSpellID,
--   linkedSpellIDs (numberArray), selfAura (bool), hasAura (bool),
--   charges (bool), isKnown (bool), flags, category.
local _cooldownInfoByID    = {}    -- [cooldownID] = default info table
local _cooldownInfoByKey   = {}    -- ["category:cooldownID"] = info table
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
-- mirror. Unlike `_cdIDByCatSpell`, these do not include broad linked
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
-- for cdIDs whose CooldownInfo identity set matches an active totem's name or
-- spellID. The index is rebuilt on every Walk and incrementally extended on
-- BindNewChildren.
local _spellNameToCDID = {}        -- [spellName lowercase] = { [cdID] = true }
local _totemSpellIDToCDID = {}     -- [spellID] = { [cdID] = true }
local _totemActiveCDID = {}        -- [cdID] = totem slot, set by PLAYER_TOTEM_UPDATE

-- Forward decls: Walk / BindNewChildren reference these by upvalue, but the
-- definitions live further down (alongside the rest of the totem helpers,
-- where the surrounding context — _eventFrame, EnsureState, TaintLog —
-- exists). The `function NAME(...)` form below ASSIGNS to these existing
-- locals; do not re-add `local` to those definitions.
local _IndexSpellNameForCDID
local EnsureState
local BindChildHooks
local HandlePlayerTotemUpdate
local SafeFrameBooleanField
local SafeFrameShownField
local RawFrameField
local RequestMirrorTextRefresh
local RequestMirrorTextRefreshForState
local RequestMirrorTextRefreshForChild
local RequestMirrorTextRefreshForMappedSpells
local ClearMirrorStackState
local AuraInstanceMatchesExpectedOwner
local CleanScalar
local CleanBool

do
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_blizzMirror_state",         tbl = _mirrorState }
    mp[#mp + 1] = { name = "CDM_blizzMirror_packedState",   tbl = _packedStateByInstanceKey }
    mp[#mp + 1] = { name = "CDM_blizzMirror_essentialMap",  tbl = _cdIDByCatSpell.essential }
    mp[#mp + 1] = { name = "CDM_blizzMirror_utilityMap",    tbl = _cdIDByCatSpell.utility }
    mp[#mp + 1] = { name = "CDM_blizzMirror_buffMap",       tbl = _cdIDByCatSpell.buff }
    mp[#mp + 1] = { name = "CDM_blizzMirror_trackedBarMap", tbl = _cdIDByCatSpell.trackedBar }
    mp[#mp + 1] = { name = "CDM_blizzMirror_buffDirectMap", tbl = _directCDIDByCatSpell.buff }
    mp[#mp + 1] = { name = "CDM_blizzMirror_trackedBarDirectMap", tbl = _directCDIDByCatSpell.trackedBar }
    mp[#mp + 1] = { name = "CDM_blizzMirror_spellNameIndex", tbl = _spellNameToCDID }
    mp[#mp + 1] = { name = "CDM_blizzMirror_totemSpellIDIndex", tbl = _totemSpellIDToCDID }
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

local CATEGORY_NUM_BY_NAME = {
    essential  = 0,
    utility    = 1,
    buff       = 2,
    trackedBar = 3,
}

local COOLDOWN_RELATED_CATEGORIES = { "essential", "utility" }
local AURA_RELATED_CATEGORIES = { "buff", "trackedBar" }
local SELF_AURA_UNITS = { "player", "pet" }
local TARGET_AURA_UNITS = { "target" }
local ALL_AURA_UNITS = { "player", "pet", "target" }
local EMPTY_LIST = {}

local _auraDurationCandidatesByInfo = setmetatable({}, { __mode = "k" })
local _spellDurationCandidatesByInfo = setmetatable({}, { __mode = "k" })

local AURA_CHILD_DURATION_SOURCE = "aura-child"

local function DebugAuraStamp(label, ...)
    local log = CDMBlizzMirror and CDMBlizzMirror.TaintLog
    if log then
        log(label, ...)
    end
end

local function IsAuraViewerCategoryName(cat)
    return cat == "buff" or cat == "trackedBar"
end

local function MakeInstanceKey(cdID, catName)
    if not (cdID and catName) then return nil end
    return tostring(catName) .. ":" .. tostring(cdID)
end

local function GetFrameCategoryName(frame)
    local catNum = frame and _categoryByFrame[frame]
    return catNum ~= nil and CATEGORY_NAMES[catNum] or nil
end

local function ResolveInstanceKey(cdID, catName)
    if not cdID then return nil end
    if catName then
        local byCat = _instanceKeyByCatID[catName]
        if byCat and byCat[cdID] then
            return byCat[cdID]
        end
        return MakeInstanceKey(cdID, catName)
    end
    return _defaultInstanceKeyByID[cdID]
end

local function RegisterCooldownInstance(cdID, catName, child, info)
    local key = MakeInstanceKey(cdID, catName)
    if not key then return nil end

    local byCat = _instanceKeyByCatID[catName]
    if byCat then
        byCat[cdID] = key
    end
    _defaultInstanceKeyByID[cdID] = _defaultInstanceKeyByID[cdID] or key
    _viewerCategoryByKey[key] = catName
    _viewerCategoryByID[cdID] = _viewerCategoryByID[cdID] or catName

    if child then
        _childByInstanceKey[key] = child
        _childByCooldownID[cdID] = _childByCooldownID[cdID] or child
    end
    if info then
        _cooldownInfoByKey[key] = info
        _cooldownInfoByID[cdID] = _cooldownInfoByID[cdID] or info
    end

    return key
end

local function GetInstanceCategoryName(cdID, catName)
    if catName then return catName end
    local key = ResolveInstanceKey(cdID)
    return (key and _viewerCategoryByKey[key]) or _viewerCategoryByID[cdID]
end

local function GetInstanceInfo(cdID, catName)
    local key = ResolveInstanceKey(cdID, catName)
    return (key and _cooldownInfoByKey[key]) or _cooldownInfoByID[cdID]
end

local function GetInstanceChild(cdID, catName)
    local key = ResolveInstanceKey(cdID, catName)
    return (key and _childByInstanceKey[key]) or _childByCooldownID[cdID]
end

local function ResolveChildCatalogCategories(cdID, viewerCatName)
    local categories = {}
    local viewerCatKnown = false
    for catNum = 0, 3 do
        local catName = CATEGORY_NAMES[catNum]
        local byCat = catName and _instanceKeyByCatID[catName]
        if byCat and byCat[cdID] then
            if catName == viewerCatName then
                viewerCatKnown = true
            end
            categories[#categories + 1] = catName
        end
    end

    if viewerCatKnown then
        return { viewerCatName }
    end
    if #categories > 0 then
        return categories
    end
    if viewerCatName then
        return { viewerCatName }
    end
    return categories
end

local function DurationModeForSource(source, viewerCategory)
    if source == "aura-duration"
        or source == "aura-child"
        or source == "aura-child-frame"
        or source == "aura-related-child" then
        return "aura"
    end
    -- Totem lane surfaced through an aura viewer (buff / trackedBar) is the
    -- duration of the buff itself — guardian-summoning self-buffs land here
    -- (e.g. Raise Abomination), where hasAura=false on the parent cdID and
    -- the only duration source is the totem timer slot.
    if source == "totem-duration" and IsAuraViewerCategoryName(viewerCategory) then
        return "aura"
    end
    if source == "spell-charge" or source == "resource-duration" then
        return "charge"
    end
    if source == "gcd-duration" then
        return "gcd-only"
    end
    if source then
        return "cooldown"
    end
    return nil
end

local function SelectDurationForState(cdID, s)
    if not s then return nil, nil, nil end

    local cat = s.viewerCategory or GetInstanceCategoryName(cdID)
    if IsAuraViewerCategoryName(cat) then
        if s.totemDurObj and _totemActiveCDID[cdID] then
            return s.totemDurObj, s.totemDurObjSource or "totem-duration", nil
        end
        if s.auraDurObj then
            return s.auraDurObj, s.auraDurObjSource or "aura-duration", nil
        end
        -- Guardian-summoning self-buffs (Raise Abomination, Army of the
        -- Dead, etc.) carry hasAura=false on the parent cdID; their only
        -- duration source is the totem timer slot captured via
        -- PLAYER_TOTEM_UPDATE. Surface that lane so the buff viewer can
        -- render a swipe instead of dead-ending at durObj=nil.
        if s.totemDurObj then
            return s.totemDurObj, s.totemDurObjSource or "totem-duration", nil
        end
        return nil, nil, s.auraDurationStateUnknown
    end

    if s.auraDurObj then
        return s.auraDurObj, s.auraDurObjSource or "aura-duration", nil
    end
    if s.totemDurObj then
        return s.totemDurObj, s.totemDurObjSource or "totem-duration", nil
    end
    if s.resourceDurObj then
        return s.resourceDurObj, s.resourceDurObjSource or "resource-duration", nil
    end
    if s.cooldownDurObj then
        return s.cooldownDurObj, s.cooldownDurObjSource or "cooldown-frame", nil
    end
    if s.gcdDurObj then
        return s.gcdDurObj, s.gcdDurObjSource or "gcd-duration", nil
    end

    return nil, nil,
        s.auraDurationStateUnknown
        or s.cooldownDurationStateUnknown
        or s.resourceDurationStateUnknown
        or s.gcdDurationStateUnknown
end

local function RefreshSelectedDurationState(cdID, s)
    local durObj, source, unknown = SelectDurationForState(cdID, s)
    s.durObj = durObj
    s.durObjSource = source
    local cat = s and (s.viewerCategory or GetInstanceCategoryName(cdID))
    s.resolvedMode = DurationModeForSource(source, cat)
    s.durationStateUnknown = unknown or nil
    return durObj, source, unknown
end

local function ClearAuraDurationLane(cdID, s)
    if not s then return end
    s.auraDurObj = nil
    s.auraDurObjSource = nil
    s.auraDurationStateUnknown = nil
    RefreshSelectedDurationState(cdID, s)
end

local function ClearAllDurationLanes(cdID, s)
    if not s then return end
    s.auraDurObj = nil
    s.auraDurObjSource = nil
    s.auraDurationStateUnknown = nil
    s.cooldownDurObj = nil
    s.cooldownDurObjSource = nil
    s.cooldownDurationStateUnknown = nil
    s.resourceDurObj = nil
    s.resourceDurObjSource = nil
    s.resourceDurationStateUnknown = nil
    s.gcdDurObj = nil
    s.gcdDurObjSource = nil
    s.gcdDurationStateUnknown = nil
    s.totemDurObj = nil
    s.totemDurObjSource = nil
    RefreshSelectedDurationState(cdID, s)
end

-- Lane writes are ASYMMETRIC by design: cooldown writes wipe the gcd lane,
-- but gcd writes do NOT wipe the cooldown lane. Rationale: a real cooldown
-- supersedes a transient GCD write (which is a side-effect of the GCD pulse
-- on a spell that already had a real CD scheduled), but a GCD pulse must not
-- erase the real CD that was scheduled earlier. SelectDurationForState picks
-- cooldown ahead of gcd so co-existing lanes resolve correctly.
local function SetDurationLane(cdID, s, lane, durObj, source)
    if not s then return end
    if lane == "aura" then
        s.auraDurObj = durObj
        s.auraDurObjSource = source or "aura-duration"
        s.auraDurationStateUnknown = nil
    elseif lane == "cooldown" then
        s.gcdDurObj = nil
        s.gcdDurObjSource = nil
        s.gcdDurationStateUnknown = nil
        s.cooldownDurObj = durObj
        s.cooldownDurObjSource = source or "cooldown-frame"
        s.cooldownDurationStateUnknown = nil
    elseif lane == "resource" then
        s.resourceDurObj = durObj
        s.resourceDurObjSource = source or "resource-duration"
        s.resourceDurationStateUnknown = nil
    elseif lane == "gcd" then
        s.gcdDurObj = durObj
        s.gcdDurObjSource = source or "gcd-duration"
        s.gcdDurationStateUnknown = nil
    elseif lane == "totem" then
        s.totemDurObj = durObj
        s.totemDurObjSource = source or "totem-duration"
    end
    RefreshSelectedDurationState(cdID, s)
end

local function MarkDurationLaneUnknown(cdID, s, lane)
    if not s then return end
    if lane == "aura" then
        s.auraDurationStateUnknown = true
    elseif lane == "cooldown" then
        s.cooldownDurationStateUnknown = true
    elseif lane == "resource" then
        s.resourceDurationStateUnknown = true
    elseif lane == "gcd" then
        s.gcdDurationStateUnknown = true
    else
        s.cooldownDurationStateUnknown = true
    end
    RefreshSelectedDurationState(cdID, s)
end

local function StoreCooldownSetterArgs(s, methodName, a, b, c)
    if not s then return end
    s.lastCooldownSetter = methodName
    if methodName == "SetCooldownFromDurationObject" then
        s.lastDurationObjectArg = a
        s.lastDurationObjectClearIfZero = b
    elseif methodName == "SetCooldown" then
        s.lastSetCooldownStart = a
        s.lastSetCooldownDuration = b
        s.lastSetCooldownModRate = c
    elseif methodName == "SetCooldownDuration" then
        s.lastSetCooldownDurationOnly = a
        s.lastSetCooldownDurationModRate = b
    elseif methodName == "SetCooldownFromExpirationTime" then
        s.lastSetCooldownExpirationTime = a
        s.lastSetCooldownExpirationDuration = b
        s.lastSetCooldownExpirationModRate = c
    elseif methodName == "SetCooldownUNIX" then
        s.lastSetCooldownUnixStart = a
        s.lastSetCooldownUnixDuration = b
        s.lastSetCooldownUnixModRate = c
    end
end

---------------------------------------------------------------------------
-- Aura-event freshness tracking.
--
-- The SetCooldownFromDurationObject hook (line ~538) only sets s.isActive
-- to true; it never clears it. Blizzard's mixin force-shows the parent
-- child for inactive auras, so child:IsShown() is not an active-aura signal.
-- The exact child field `isActive` is the event-driven visibility signal
-- for aura-viewer cIDs, including hasAura=false entries like Lesser Ghoul.
--
-- Strategy: on UNIT_AURA, refresh every aura-viewer child from its decoded
-- `isActive` field and separately stamp auraInstanceID values when Blizzard
-- exposes a normal aura path. Removed-aura events verify stamped instances
-- immediately; PackState stays read-only and does not poll.
--
-- auraInstanceID is NeverSecret. It is stable inside an active encounter/
-- combat context, but re-randomized on encounter/M+/PvP start.
---------------------------------------------------------------------------
-- Stamp the auraInstanceID for a known cdID. Caller has already resolved
-- which cdID this aura belongs to (from the non-secret catalog spellID it
-- queried for) so we never need to reach into ad's potentially-secret
-- fields for identity. We read ad.auraInstanceID and forward it to C-side
-- sinks (C_UnitAuras.GetAuraDuration / GetAuraDataByAuraInstanceID).
local function StampAuraInstanceForCooldown(unit, cdID, ad, viewerCategory)
    if not (ad and cdID) then return end
    local s = EnsureState(cdID, nil, viewerCategory)
    if not s then return end
    local instID = ad.auraInstanceID
    if not instID then return end
    s.auraInstanceID = instID
    s.auraInstanceIDSource = "aura-data"
    s.auraUnit = unit

    local childOwnsAuraDuration = s.auraDurObj
        and s.auraDurObjSource == AURA_CHILD_DURATION_SOURCE

    if Sources and Sources.QueryAuraDuration then
        local durObj = Sources.QueryAuraDuration(unit, instID)
        if durObj then
            if not childOwnsAuraDuration then
                SetDurationLane(cdID, s, "aura", durObj, "aura-duration")
            else
                RefreshSelectedDurationState(cdID, s)
            end
        elseif s.auraDurObj and not childOwnsAuraDuration then
            ClearAuraDurationLane(cdID, s)
            s.auraDurationStateUnknown = true
            RefreshSelectedDurationState(cdID, s)
        elseif not childOwnsAuraDuration then
            MarkDurationLaneUnknown(cdID, s, "aura")
        end
    end
    s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
    s.lastTouch = GetTime()
    if _G.QUI_CDM_TAINT_DEBUG then
        local info = GetInstanceInfo(cdID, viewerCategory)
        DebugAuraStamp("AuraStamp.data",
            "targetCDID", cdID,
            "targetCat", viewerCategory,
            "unit", unit,
            "instID", instID,
            "stateSpell", info and info.spellID,
            "stateOverride", info and info.overrideSpellID,
            "stateTooltip", info and info.overrideTooltipSpellID,
            "durObj", s.auraDurObj ~= nil)
    end
end

local function ClearMirrorAuraState(cdID, s, reason)
    if not s then return end
    -- Guard only on aura-side state. A live cooldown / gcd / totem / resource
    -- lane is not aura state and must not trigger this clear path. Callers
    -- (aura-owner-mismatch, unit-aura-removed, freshness, target-changed)
    -- only care about aura invalidation.
    if not (s.auraDurObj or s.auraInstanceID
        or s.auraData
        or s.pandemicActive or s.pandemicStateKnown
        or s.stackText or s.stackTextSource or s.stackTextShown == true) then
        return
    end

    ClearAuraDurationLane(cdID, s)
    s.auraInstanceID = nil
    s.auraInstanceIDSource = nil
    s.auraUnit = nil
    s.auraData = nil
    s.pandemicActive = false
    s.pandemicStateKnown = nil
    local clearedStack = ClearMirrorStackState(s)
    -- Only flip the overall isActive flag if no other lane is still
    -- holding state. Preserves real cooldowns that outlive their aura
    -- (e.g., target debuff faded mid-CD; spell is still on cooldown so
    -- the swipe must keep rendering).
    if not (s.cooldownDurObj or s.gcdDurObj or s.totemDurObj or s.resourceDurObj) then
        s.isActive = false
    end
    s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
    s.lastTouch = GetTime()
    if SetHostPandemicState then
        SetHostPandemicState(cdID, nil, false)
    end
    if clearedStack then
        RequestMirrorTextRefreshForState(cdID, s, "aura-clear")
    end
    if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
        CDMBlizzMirror.TaintLog("ClearAuraState",
            "cdID", cdID, "reason", reason or "unknown")
    end
end

local function QueryAuraForMirrorUnit(unit, spellID)
    if not (Sources and unit and spellID) then return nil end
    local ad
    if unit == "player" and Sources.QueryPlayerAuraBySpellID then
        ad = Sources.QueryPlayerAuraBySpellID(spellID)
    end
    if ad then return ad end

    if Sources.QueryUnitAuraBySpellID then
        ad = Sources.QueryUnitAuraBySpellID(unit, spellID)
            or Sources.QueryUnitAuraBySpellID(unit, spellID, "HELPFUL")
            or Sources.QueryUnitAuraBySpellID(unit, spellID, "HARMFUL")
    end
    if ad then return ad end

    if Sources.QueryAuraDataBySpellID then
        ad = Sources.QueryAuraDataBySpellID(unit, spellID)
            or Sources.QueryAuraDataBySpellID(unit, spellID, "HELPFUL")
            or Sources.QueryAuraDataBySpellID(unit, spellID, "HARMFUL")
    end
    return ad
end

local function CooldownInfoMatchesAuraUnit(cdID, unit, viewerCategory)
    local info = cdID and GetInstanceInfo(cdID, viewerCategory)
    if unit == "target" then
        return info and info.selfAura == false
    end
    if unit == "player" or unit == "pet" then
        return not (info and info.selfAura == false)
    end
    return false
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
                if CooldownInfoMatchesAuraUnit(cdID, unit, cat) then
                    local ad = QueryAuraForMirrorUnit(unit, sid)
                    if ad and (not needsSourceFilter or Helpers.IsAuraOwnedByPlayerOrPet(ad)) then
                        StampAuraInstanceForCooldown(unit, cdID, ad, cat)
                    end
                end
            end
        end
    end
end

local function GetPayloadAuraSpellID(ad)
    if not ad then return nil end
    local sid = ad.spellId
    if not sid then sid = ad.spellID end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(sid) then
        return nil
    end
    if type(sid) == "number" and sid > 0 then
        return sid
    end
    return nil
end

local function StampAuraPayloadForUnit(unit, ad)
    if type(unit) ~= "string" or unit == "" or not ad then return false end
    local sid = GetPayloadAuraSpellID(ad)
    if not sid then return false end

    local needsSourceFilter = unit == "target"
    if needsSourceFilter and not Helpers.IsAuraOwnedByPlayerOrPet(ad) then
        return false
    end

    local stamped = false
    for cat, directMap in pairs(_directCDIDByCatSpell) do
        if cat == "buff" or cat == "trackedBar" then
            local cdID = directMap[sid]
            if cdID and CooldownInfoMatchesAuraUnit(cdID, unit, cat) then
                StampAuraInstanceForCooldown(unit, cdID, ad, cat)
                stamped = true
            end
        end
    end
    return stamped
end

local function CaptureAurasFromUnitAuraPayload(unit, updateInfo)
    if type(unit) ~= "string" or unit == "" or type(updateInfo) ~= "table" then
        return false
    end

    local stamped = false
    if type(updateInfo.addedAuras) == "table" then
        for _, ad in ipairs(updateInfo.addedAuras) do
            stamped = StampAuraPayloadForUnit(unit, ad) or stamped
        end
    end

    if type(updateInfo.updatedAuraInstanceIDs) == "table"
        and Sources and Sources.QueryAuraDataByAuraInstanceID then
        for _, instID in ipairs(updateInfo.updatedAuraInstanceIDs) do
            local ad = Sources.QueryAuraDataByAuraInstanceID(unit, instID)
            stamped = StampAuraPayloadForUnit(unit, ad) or stamped
        end
    end

    return stamped
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
    -- Use truthy checks for duration objects here; auraInstanceID is
    -- NeverSecret, but DurationObjects may still be restricted in combat.
    -- Without this defensive shape the resolver can die inside the icon
    -- visibility loop's pcall, leaving `icon._auraActive` stale.
    if not s then return end
    if not s.auraInstanceID then return end
    if not (Sources and Sources.QueryAuraDuration) then return end
    local auraUnit = s.auraUnit or "player"
    if AuraInstanceMatchesExpectedOwner
        and not AuraInstanceMatchesExpectedOwner(auraUnit, s.auraInstanceID) then
        ClearMirrorAuraState(cdID, s, "aura-owner-mismatch")
        return
    end
    local durObj = Sources.QueryAuraDuration(auraUnit, s.auraInstanceID)
    if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
        CDMBlizzMirror.TaintLog("Verify",
            "auraUnit", s.auraUnit,
            "instID", s.auraInstanceID,
            "durObj", durObj,
            "priorIsActive", s.isActive,
            "priorDurObj", s.durObj,
            "priorAuraDurObj", s.auraDurObj)
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
            if s.auraDurObj then
                ClearAuraDurationLane(cdID, s)
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
        if not s.auraDurObj then
            SetDurationLane(cdID, s, "aura", durObj, "aura-duration")
            s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
        end
    end
end

local function EvictRemovedMirrorStatesForUnit(unit)
    if type(unit) ~= "string" or unit == "" then return end
    for _, s in pairs(_mirrorState) do
        local cdID = s and s.cooldownID
        local cat = s and s.viewerCategory
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
local function PackState(cooldownID, viewerCategory)
    if not cooldownID then return nil end
    local key = ResolveInstanceKey(cooldownID, viewerCategory)
    local s = key and _mirrorState[key]
    if not s then return nil end
    RefreshSelectedDurationState(cooldownID, s)
    local catName = s.viewerCategory or GetInstanceCategoryName(cooldownID, viewerCategory)
    local info = GetInstanceInfo(cooldownID, catName)
    local child = GetInstanceChild(cooldownID, catName)
    -- selfAura / hasAura must NOT be coerced to false on nil. CleanBool
    -- returns nil when the source bool was secret AND the curve-decode
    -- fallback failed — i.e. "we don't know". `or false` would force
    -- those into target-side classification (selfAura=false), which is
    -- the wrong default for buff icons (most are player-side). Pass nil
    -- through and let consumers default safely with `m.selfAura == false`
    -- / `== true` checks (nil compares equal to neither, so consumers
    -- that branch on the explicit value default to the safer side).
    local packed = _packedStateByInstanceKey[key]
    if not packed then
        packed = {}
        _packedStateByInstanceKey[key] = packed
    end

    packed.durObj                 = s.durObj
    packed.durObjSource           = s.durObjSource
    packed.resolvedMode           = s.resolvedMode
    packed.durationStateUnknown   = s.durationStateUnknown
    packed.auraDurObj             = s.auraDurObj
    packed.auraDurObjSource       = s.auraDurObjSource
    packed.auraDurationStateUnknown = s.auraDurationStateUnknown
    packed.cooldownDurObj         = s.cooldownDurObj
    packed.cooldownDurObjSource   = s.cooldownDurObjSource
    packed.cooldownDurationStateUnknown = s.cooldownDurationStateUnknown
    packed.resourceDurObj         = s.resourceDurObj
    packed.resourceDurObjSource   = s.resourceDurObjSource
    packed.resourceDurationStateUnknown = s.resourceDurationStateUnknown
    packed.gcdDurObj              = s.gcdDurObj
    packed.gcdDurObjSource        = s.gcdDurObjSource
    packed.gcdDurationStateUnknown = s.gcdDurationStateUnknown
    packed.totemDurObj            = s.totemDurObj
    packed.totemDurObjSource      = s.totemDurObjSource
    packed.isActive               = s.isActive
    packed.mirrorEpoch            = s.mirrorEpoch
    packed.auraInstanceID         = s.auraInstanceID
    packed.hasAuraInstanceID      = s.auraInstanceID and true or false
    packed.auraUnit               = s.auraUnit
    packed.auraData               = s.auraData
    packed.viewerCategory         = catName
    packed.spellID                = info and info.spellID or nil
    packed.overrideSpellID        = info and info.overrideSpellID or nil
    packed.hasAura                = info and info.hasAura
    packed.selfAura               = info and info.selfAura
    packed.linkedSpellIDs         = info and info.linkedSpellIDs or nil
    packed.overrideTooltipSpellID = info and info.overrideTooltipSpellID or nil
    packed.pandemicActive         = s.pandemicActive
    packed.pandemicStateKnown     = s.pandemicStateKnown
    packed.stackText              = s.stackText
    packed.stackTextSource        = s.stackTextSource
    packed.stackTextShown         = s.stackTextShown
    packed.stackTextEpoch         = s.stackTextEpoch
    packed.cooldownChargesCount   = RawFrameField(child, "cooldownChargesCount")
    packed.cooldownChargesShown   = SafeFrameBooleanField(child, "cooldownChargesShown")
    packed.chargeCountFrameShown  = SafeFrameShownField(child and child.ChargeCount)
    packed.totemSlot              = s.totemSlot
    packed.totemName              = s.totemName
    packed.totemIcon              = s.totemIcon
    packed.totemSpellID           = s.totemSpellID
    packed.cooldownID             = cooldownID
    packed.childIsActive          = SafeFrameBooleanField(child, "isActive")
    packed.cooldownIsActive       = SafeFrameBooleanField(child, "cooldownIsActive")
    packed.wasSetFromAura         = SafeFrameBooleanField(child, "wasSetFromAura")
    packed.wasSetFromCooldown     = SafeFrameBooleanField(child, "wasSetFromCooldown")
    packed.wasSetFromCharges      = SafeFrameBooleanField(child, "wasSetFromCharges")

    return packed
end

local function CountMapEntries(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do
            count = count + 1
        end
    end
    return count
end

local function CountNestedMapEntries(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _, childMap in pairs(tbl) do
            count = count + CountMapEntries(childMap)
        end
    end
    return count
end

function CDMBlizzMirror.GetCacheStats()
    return {
        mirrorStates = CountMapEntries(_mirrorState),
        packedStates = CountMapEntries(_packedStateByInstanceKey),
        childFrames = CountMapEntries(_childByInstanceKey),
        cooldownInfo = CountMapEntries(_cooldownInfoByKey),
        defaultCooldownInfo = CountMapEntries(_cooldownInfoByID),
        auraCandidateCaches = CountMapEntries(_auraDurationCandidatesByInfo),
        spellCandidateCaches = CountMapEntries(_spellDurationCandidatesByInfo),
        spellMapEntries = CountNestedMapEntries(_cdIDByCatSpell),
        directSpellMapEntries = CountNestedMapEntries(_directCDIDByCatSpell),
        spellNameEntries = CountMapEntries(_spellNameToCDID),
        totemSpellIDEntries = CountMapEntries(_totemSpellIDToCDID),
        activeTotems = CountMapEntries(_totemActiveCDID),
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
    return PackState(cdID, viewerCategory)
end

function CDMBlizzMirror.GetDirectMirroredStateForViewer(spellID, viewerCategory)
    local cdID = CDMBlizzMirror.GetDirectCooldownIDForViewer(spellID, viewerCategory)
    return PackState(cdID, viewerCategory)
end

-- Lookup-only sibling that returns the live state of a specific cooldownID
-- without going through any spellID map.
function CDMBlizzMirror.GetStateByCooldownID(cooldownID, viewerCategory)
    return PackState(cooldownID, viewerCategory)
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
    if cdID then return PackState(cdID, "essential") end
    cdID = _cdIDByCatSpell.utility[spellID]
    return PackState(cdID, "utility")
end

function CDMBlizzMirror.FindCooldownInfo(spellID)
    if not spellID then return nil end
    local cdID = _cdIDByCatSpell.essential[spellID]
    if cdID then return GetInstanceInfo(cdID, "essential") end
    cdID = _cdIDByCatSpell.utility[spellID]
    return cdID and GetInstanceInfo(cdID, "utility") or nil
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
    return GetInstanceInfo(cdID, viewerCategory)
end

function CDMBlizzMirror.GetCooldownInfoByCooldownID(cooldownID, viewerCategory)
    return cooldownID and GetInstanceInfo(cooldownID, viewerCategory) or nil
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
    if cdID then return PackState(cdID, "buff") end
    cdID = _cdIDByCatSpell.trackedBar[spellID]
    if cdID then return PackState(cdID, "trackedBar") end
    cdID = _cdIDByCatSpell.essential[spellID]
    if cdID then return PackState(cdID, "essential") end
    cdID = _cdIDByCatSpell.utility[spellID]
    return PackState(cdID, "utility")
end

function CDMBlizzMirror.GetCooldownInfo(spellID)
    if not spellID then return nil end
    local cdID = _cdIDByCatSpell.buff[spellID]
    if cdID then return GetInstanceInfo(cdID, "buff") end
    cdID = _cdIDByCatSpell.trackedBar[spellID]
    if cdID then return GetInstanceInfo(cdID, "trackedBar") end
    cdID = _cdIDByCatSpell.essential[spellID]
    if cdID then return GetInstanceInfo(cdID, "essential") end
    cdID = _cdIDByCatSpell.utility[spellID]
    return cdID and GetInstanceInfo(cdID, "utility") or nil
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

local function FormatRawValue(v)
    if issecretvalue and issecretvalue(v) then
        return "<SECRET:" .. type(v) .. ">"
    end
    if v == nil then return "nil" end
    local t = type(v)
    if t == "boolean" then return (v and "true" or "false") .. ":bool" end
    if t == "number" then return tostring(v) .. ":num" end
    if t == "string" then return "\"" .. v .. "\":str" end
    return "<" .. t .. ">"
end

local function FormatRawLinkedIDs(ids)
    if issecretvalue and issecretvalue(ids) then
        return "<SECRET:" .. type(ids) .. ">"
    end
    if type(ids) ~= "table" then return FormatRawValue(ids) end
    local parts = {}
    for i, id in ipairs(ids) do
        parts[i] = FormatRawValue(id)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function AppendRawInfoFields(parts, info)
    parts[#parts + 1] = "spellID=" .. FormatRawValue(info and info.spellID)
    parts[#parts + 1] = "overrideSpellID=" .. FormatRawValue(info and info.overrideSpellID)
    parts[#parts + 1] = "overrideTooltipSpellID=" .. FormatRawValue(info and info.overrideTooltipSpellID)
    parts[#parts + 1] = "linkedSpellIDs=" .. FormatRawLinkedIDs(info and info.linkedSpellIDs)
    parts[#parts + 1] = "selfAura=" .. FormatRawValue(info and info.selfAura)
    parts[#parts + 1] = "hasAura=" .. FormatRawValue(info and info.hasAura)
    parts[#parts + 1] = "charges=" .. FormatRawValue(info and info.charges)
    parts[#parts + 1] = "isKnown=" .. FormatRawValue(info and info.isKnown)
end

local function SafeObjectName(obj)
    if not obj then return "nil" end
    local fn = obj.GetName
    if type(fn) == "function" then
        local ok, name = pcall(fn, obj)
        if ok and name then return tostring(name) end
    end
    return tostring(obj)
end

function CDMBlizzMirror.GetRawCooldownViewerDebugLines()
    local lines = {}
    local totalSetEntries = 0
    local totalChildren = 0

    lines[#lines + 1] = "[CDM raw] C_CooldownViewer + live viewer children"
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
        lines[#lines + 1] = "[CDM raw] C_CooldownViewer.GetCooldownViewerCategorySet unavailable"
        return lines
    end

    for catNum = 0, 3 do
        local catName = CATEGORY_NAMES[catNum] or tostring(catNum)
        local viewerName = CATEGORY_GLOBALS[catNum]
        local viewer = _G[viewerName]
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(catNum, false)
        local setCount = 0
        if type(cooldownIDs) == "table" then
            for _ in ipairs(cooldownIDs) do
                setCount = setCount + 1
            end
        end

        local children = {}
        if viewer and viewer.GetChildren then
            children = { viewer:GetChildren() }
        end
        local childCount = #children
        totalSetEntries = totalSetEntries + setCount
        totalChildren = totalChildren + childCount

        lines[#lines + 1] = ("[CDM raw] cat=%s(%d) apiSet=%d viewerChildren=%d viewer=%s"):format(
            catName, catNum, setCount, childCount, tostring(viewerName))

        if type(cooldownIDs) == "table" then
            for i, cdID in ipairs(cooldownIDs) do
                local info
                local ok, result = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                if ok then info = result end
                local parts = {
                    "[CDM raw] api",
                    "cat=" .. catName,
                    "index=" .. tostring(i),
                    "cdID=" .. FormatRawValue(cdID),
                }
                if ok then
                    AppendRawInfoFields(parts, info)
                else
                    parts[#parts + 1] = "infoError=" .. tostring(result)
                end
                lines[#lines + 1] = table.concat(parts, " | ")
            end
        else
            lines[#lines + 1] = "[CDM raw] api cat=" .. catName .. " categorySet=" .. FormatRawValue(cooldownIDs)
        end

        for i, child in ipairs(children) do
            local parts = {
                "[CDM raw] child",
                "cat=" .. catName,
                "index=" .. tostring(i),
                "name=" .. SafeObjectName(child),
                "cdID=" .. FormatRawValue(child and child.cooldownID),
                "isActive=" .. FormatRawValue(child and child.isActive),
                "cooldownIsActive=" .. FormatRawValue(child and child.cooldownIsActive),
                "wasSetFromAura=" .. FormatRawValue(child and child.wasSetFromAura),
                "wasSetFromCooldown=" .. FormatRawValue(child and child.wasSetFromCooldown),
                "wasSetFromCharges=" .. FormatRawValue(child and child.wasSetFromCharges),
                "bound=" .. FormatRawValue(child and child._quiMirrorBound),
            }
            lines[#lines + 1] = table.concat(parts, " | ")
        end
    end

    lines[#lines + 1] = ("[CDM raw] summary categorySetEntries=%d viewerChildren=%d mirrorInfoEntries=%d"):format(
        totalSetEntries,
        totalChildren,
        (function()
            local n = 0
            for _ in pairs(_cooldownInfoByKey) do n = n + 1 end
            return n
        end)())
    return lines
end

function CDMBlizzMirror.DumpInfoForSpell(filter)
    if CDMBlizzMirror.BindNewChildren then
        CDMBlizzMirror.BindNewChildren()
    end

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
    for key, info in pairs(_cooldownInfoByKey) do
        local cdID = info and info.cooldownID
        if entryMatches(cdID, info) then
            count = count + 1
            local cat = _viewerCategoryByKey[key] or GetInstanceCategoryName(cdID) or "?"
            local sid = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
            local name = ResolveSpellName(sid) or "?"

            -- Re-query the live API so we can see whether stored info has
            -- drifted from current Blizzard state.
            local liveInfo
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local li = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if li then liveInfo = li end
            end

            local s = _mirrorState[key]

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
                RefreshSelectedDurationState(cdID, s)
                print(("  mirror: isActive=%s  durObj=%s  source=%s  auraDur=%s  cdDur=%s  resourceDur=%s  totemDur=%s  auraInstanceID=%s  auraUnit=%s  epoch=%s"):format(
                    tostring(s.isActive),
                    tostring(s.durObj),
                    tostring(s.durObjSource),
                    tostring(s.auraDurObj),
                    tostring(s.cooldownDurObj),
                    tostring(s.resourceDurObj),
                    tostring(s.totemDurObj),
                    tostring(s.auraInstanceID),
                    tostring(s.auraUnit),
                    tostring(s.mirrorEpoch)))
            else
                print("  mirror: <no state>")
            end
            local child = _childByInstanceKey[key]
            if child then
                print(("  child : isActive=%s  cooldownIsActive=%s  fromAura=%s  fromCooldown=%s  fromCharges=%s"):format(
                    tostring(SafeFrameBooleanField(child, "isActive")),
                    tostring(SafeFrameBooleanField(child, "cooldownIsActive")),
                    tostring(SafeFrameBooleanField(child, "wasSetFromAura")),
                    tostring(SafeFrameBooleanField(child, "wasSetFromCooldown")),
                    tostring(SafeFrameBooleanField(child, "wasSetFromCharges"))))
            else
                print("  child : <no frame>")
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
EnsureState = function(cdID, frame, viewerCategory)
    if not cdID then return nil end
    local catName = viewerCategory or GetFrameCategoryName(frame) or GetInstanceCategoryName(cdID)
    local key = ResolveInstanceKey(cdID, catName) or MakeInstanceKey(cdID, catName) or cdID
    local s = _mirrorState[key]
    if not s then
        s = {
            cooldownID  = cdID,
            stateKey    = key,
            viewerCategory = catName,
            durObj      = nil,
            isActive    = false,
            mirrorEpoch = 0,
            lastTouch   = 0,
            pandemicActive = false,
            pandemicStateKnown = nil,
        }
        _mirrorState[key] = s
    end
    s.cooldownID = cdID
    if catName and not s.viewerCategory then
        s.viewerCategory = catName
    end
    if catName then
        RegisterCooldownInstance(cdID, catName, frame, nil)
    end
    return s
end

local function SafeFrameField(frame, key)
    if not frame then return nil end
    local value = frame[key]
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

RawFrameField = function(frame, key)
    if not frame then return nil end
    return frame[key]
end

local function ReadChildAuraData(child)
    local auraData = SafeFrameField(child, "auraData")
    if type(auraData) ~= "table" then return nil end
    if Helpers and Helpers.CanAccessTable
        and not Helpers.CanAccessTable(auraData) then
        return nil
    end
    return auraData
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

SafeFrameBooleanField = function(frame, key)
    if not frame then return nil end
    local value = frame[key]
    return DecodePotentialSecretBoolean(value)
end

SafeFrameShownField = function(frame)
    if not (frame and frame.IsShown) then return nil end
    return DecodePotentialSecretBoolean(frame:IsShown())
end

local function IsAuraViewerCategory(cdID, stateOrCategory)
    local cat = type(stateOrCategory) == "table"
        and stateOrCategory.viewerCategory
        or stateOrCategory
    return IsAuraViewerCategoryName(cat or (cdID and GetInstanceCategoryName(cdID)))
end

local function IsTargetAuraViewerCategory(cdID, stateOrCategory)
    local cat = type(stateOrCategory) == "table"
        and stateOrCategory.viewerCategory
        or stateOrCategory
    if not IsAuraViewerCategory(cdID, cat) then return false end
    local info = GetInstanceInfo(cdID, cat)
    return info and info.selfAura == false
end

local function AddDurationSpellCandidate(candidates, seen, spellID)
    if not spellID then return end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(spellID) then return end
    if type(spellID) ~= "number" or spellID <= 0 then return end
    if seen[spellID] then return end
    seen[spellID] = true
    candidates[#candidates + 1] = spellID
end

local function AddLinkedDurationSpellCandidates(candidates, seen, linkedSpellIDs)
    if type(linkedSpellIDs) ~= "table" then return end
    for _, spellID in ipairs(linkedSpellIDs) do
        AddDurationSpellCandidate(candidates, seen, spellID)
    end
end

local function AddCooldownAuraMappedCandidate(candidates, seen, spellID)
    AddDurationSpellCandidate(candidates, seen, spellID)
    if not (spellID and Sources and Sources.QueryCooldownAuraBySpellID) then return end
    AddDurationSpellCandidate(candidates, seen, Sources.QueryCooldownAuraBySpellID(spellID))
end

local function AddLinkedCooldownAuraMappedCandidates(candidates, seen, linkedSpellIDs)
    if type(linkedSpellIDs) ~= "table" then return end
    for _, spellID in ipairs(linkedSpellIDs) do
        AddCooldownAuraMappedCandidate(candidates, seen, spellID)
    end
end

local function BuildAuraDurationSpellCandidates(info)
    if not info then return EMPTY_LIST end
    local queryCooldownAura = Sources and Sources.QueryCooldownAuraBySpellID
    local cached = _auraDurationCandidatesByInfo[info]
    if cached and cached.queryCooldownAura == queryCooldownAura then
        return cached.candidates
    end

    local candidates, seen = {}, {}

    AddCooldownAuraMappedCandidate(candidates, seen, info.overrideTooltipSpellID)
    AddLinkedCooldownAuraMappedCandidates(candidates, seen, info.linkedSpellIDs)
    AddCooldownAuraMappedCandidate(candidates, seen, info.overrideSpellID)
    AddCooldownAuraMappedCandidate(candidates, seen, info.spellID)

    _auraDurationCandidatesByInfo[info] = {
        queryCooldownAura = queryCooldownAura,
        candidates = candidates,
    }
    return candidates
end

local function BuildSpellDurationCandidates(info)
    if not info then return EMPTY_LIST end
    local cached = _spellDurationCandidatesByInfo[info]
    if cached then return cached end

    local candidates, seen = {}, {}
    AddDurationSpellCandidate(candidates, seen, info.overrideTooltipSpellID)
    AddDurationSpellCandidate(candidates, seen, info.overrideSpellID)
    AddDurationSpellCandidate(candidates, seen, info.spellID)
    AddLinkedDurationSpellCandidates(candidates, seen, info.linkedSpellIDs)

    _spellDurationCandidatesByInfo[info] = candidates
    return candidates
end

local function CooldownInfoRealState(info, spellID)
    if not info then return nil end

    local active = CleanBool(info.isActive)
    if active == false then
        return false
    end

    local enabled = CleanBool(info.isEnabled)
    if enabled == false then
        return false
    end

    local duration = CleanScalar(info.duration)
    local start = CleanScalar(info.startTime)
    if not start then
        start = CleanScalar(info.start)
    end
    if type(duration) == "number" then
        if duration <= GCD_MAX_DURATION then
            return false
        end
        if type(start) == "number" and start <= 0 then
            return false
        end
        if active == true then
            return true
        end
    end

    local activeCategory = CleanScalar(info.activeCategory)
    if activeCategory ~= nil then
        return true
    end

    local startRecovery = CleanScalar(info.timeUntilEndOfStartRecovery)
    if type(startRecovery) == "number" and startRecovery > 0 then
        return false
    end

    return nil
end

local function ShouldUseSpellGCDDuration(spellID)
    if not (spellID and Sources and Sources.QuerySpellCooldown) then
        return false
    end
    local info = Sources.QuerySpellCooldown(spellID)
    if CleanBool(info and info.isOnGCD) ~= true then
        return false
    end
    return CooldownInfoRealState(info, spellID) ~= true
end

function CDMBlizzMirror.ResolveChargeDurationObjectForCooldownID(cdID, child, state)
    if IsAuraViewerCategory(cdID, state or GetFrameCategoryName(child)) then
        return nil, nil
    end
    if SafeFrameBooleanField(child, "cooldownChargesShown") == true then
        return nil, nil
    end
    if not (Sources and Sources.QuerySpellCharges and Sources.QuerySpellChargeDuration) then
        return nil, nil
    end

    local info = cdID and GetInstanceInfo(cdID, state and state.viewerCategory or GetFrameCategoryName(child))
    if CleanBool(info and info.charges) ~= true then
        return nil, nil
    end

    local candidates = BuildSpellDurationCandidates(info)
    for _, spellID in ipairs(candidates) do
        local chargeInfo = Sources.QuerySpellCharges(spellID)
        if chargeInfo
            and (not Helpers or not Helpers.CanAccessTable or Helpers.CanAccessTable(chargeInfo))
            and CleanBool(chargeInfo.isActive) == true then
            local maxCharges = CleanScalar(chargeInfo.maxCharges)
            if type(maxCharges) == "number" and maxCharges > 1 then
                local durObj = Sources.QuerySpellChargeDuration(spellID)
                if durObj then
                    return durObj, "spell-charge"
                end
            end
        end
    end

    return nil, nil
end

function CDMBlizzMirror.ShouldSuppressChargeDurationForCooldownID(cdID, child, state)
    if CDMBlizzMirror.ResolveChargeDurationObjectForCooldownID(cdID, child, state) then
        return false
    end

    local chargesShown = SafeFrameBooleanField(child, "cooldownChargesShown")
    if chargesShown == true then
        return false
    end
    if chargesShown == false then
        return true
    end

    local chargeFrameShown = SafeFrameShownField(child and child.ChargeCount)
    if chargeFrameShown == true then
        return false
    end
    if chargeFrameShown == false then
        return true
    end

    if state and state.stackTextSource == "ChargeCount" and state.stackText ~= nil then
        return false
    end

    return true
end

local function ShouldUseGCDDurationForCooldownID(cdID, child, state)
    local info = cdID and GetInstanceInfo(cdID, state and state.viewerCategory or GetFrameCategoryName(child))
    local candidates = BuildSpellDurationCandidates(info)
    for _, spellID in ipairs(candidates) do
        if ShouldUseSpellGCDDuration(spellID) then
            return true
        end
    end
    return false
end

local function ResolveSpellDurationObjectForCooldownID(cdID, child, state)
    -- Aura viewer entries must get swipe duration from aura-instance APIs
    -- only. Numeric Cooldown:SetCooldown hooks on those children can reflect
    -- Blizzard's internal refresh path, but deriving spell cooldown
    -- DurationObjects here would make aura icons render cooldown durations.
    if IsAuraViewerCategory(cdID, state or GetFrameCategoryName(child)) then
        return nil, "aura-viewer"
    end

    if not (Sources and Sources.QuerySpellCooldownDuration) then
        return nil, nil
    end

    local info = cdID and GetInstanceInfo(cdID, state and state.viewerCategory or GetFrameCategoryName(child))
    local candidates = BuildSpellDurationCandidates(info)

    local chargeDurObj, chargeSource = CDMBlizzMirror.ResolveChargeDurationObjectForCooldownID(cdID, child, state)
    if chargeDurObj then
        return chargeDurObj, chargeSource
    end

    for _, spellID in ipairs(candidates) do
        local useGCDDuration = ShouldUseSpellGCDDuration(spellID)
        if useGCDDuration and Sources.QuerySpellCooldownDuration then
            local durObj = Sources.QuerySpellCooldownDuration(spellID, false)
            if durObj then
                return durObj, "gcd-duration"
            end
        end
        if Sources.QuerySpellCooldownDuration then
            local durObj = Sources.QuerySpellCooldownDuration(spellID, true)
            if durObj then
                if useGCDDuration then
                    return durObj, "gcd-duration"
                end
                return durObj, "spell-cooldown"
            end
        end
    end

    return nil, nil
end

local function CleanAuraUnitValue(unit)
    if not unit then return nil end
    if issecretvalue and issecretvalue(unit) then return nil end
    if type(unit) == "string" and unit ~= "" then return unit end
    return nil
end

local function GetChildAuraUnit(child)
    if not child then return nil end
    return CleanAuraUnitValue(child.auraDataUnit or child.auraUnit)
end

local function AuraViewerNeedsTargetOwnershipProof(cdID, stateOrCategory, child)
    if not IsAuraViewerCategory(cdID, stateOrCategory) then return false end
    if IsTargetAuraViewerCategory(cdID, stateOrCategory) then return true end
    return GetChildAuraUnit(child) == "target"
end

local function BuildExpectedAuraUnitsForCooldownID(cdID, viewerCategory)
    local info = GetInstanceInfo(cdID, viewerCategory)
    if info and info.selfAura == false then
        return TARGET_AURA_UNITS
    end
    return SELF_AURA_UNITS
end

AuraInstanceMatchesExpectedOwner = function(unit, auraInstanceID)
    if unit ~= "target" then return true end
    if not (Sources and Sources.QueryAuraDataByAuraInstanceID
        and Helpers and Helpers.IsAuraOwnedByPlayerOrPet) then
        return false
    end
    local ad = Sources.QueryAuraDataByAuraInstanceID(unit, auraInstanceID)
    return ad and Helpers.IsAuraOwnedByPlayerOrPet(ad) == true
end

local function StampAuraInstanceIDForCooldown(unit, cdID, auraInstanceID, viewerCategory, source, auraData)
    if not (cdID and auraInstanceID) then return false end
    local s = EnsureState(cdID, nil, viewerCategory)
    if not s then return false end

    local cleanUnit = CleanAuraUnitValue(unit)

    local acceptedUnit
    local stampedUnit
    local stampedDurObj
    if Sources and Sources.QueryAuraDuration then
        if cleanUnit then
            if not AuraInstanceMatchesExpectedOwner(cleanUnit, auraInstanceID) then
                if _G.QUI_CDM_TAINT_DEBUG then
                    DebugAuraStamp("AuraStamp.instance.reject",
                        "reason", "owner",
                        "source", source or "aura-duration",
                        "targetCDID", cdID,
                        "targetCat", viewerCategory,
                        "unit", cleanUnit,
                        "instID", auraInstanceID)
                end
                return false
            end
            acceptedUnit = cleanUnit
            local durObj = Sources.QueryAuraDuration(cleanUnit, auraInstanceID)
            if durObj then
                stampedUnit = cleanUnit
                stampedDurObj = durObj
            end
        else
            local units = BuildExpectedAuraUnitsForCooldownID(cdID, viewerCategory)
            for i = 1, #units do
                local tryUnit = units[i]
                if AuraInstanceMatchesExpectedOwner(tryUnit, auraInstanceID) then
                    acceptedUnit = acceptedUnit or tryUnit
                    local durObj = Sources.QueryAuraDuration(tryUnit, auraInstanceID)
                    if durObj then
                        stampedUnit = tryUnit
                        stampedDurObj = durObj
                        break
                    end
                end
            end
        end
    else
        if cleanUnit then
            if not AuraInstanceMatchesExpectedOwner(cleanUnit, auraInstanceID) then
                if _G.QUI_CDM_TAINT_DEBUG then
                    DebugAuraStamp("AuraStamp.instance.reject",
                        "reason", "owner",
                        "source", source or "aura-duration",
                        "targetCDID", cdID,
                        "targetCat", viewerCategory,
                        "unit", cleanUnit,
                        "instID", auraInstanceID)
                end
                return false
            end
            acceptedUnit = cleanUnit
        else
            local units = BuildExpectedAuraUnitsForCooldownID(cdID, viewerCategory)
            for i = 1, #units do
                local tryUnit = units[i]
                if AuraInstanceMatchesExpectedOwner(tryUnit, auraInstanceID) then
                    acceptedUnit = tryUnit
                    break
                end
            end
        end
    end

    stampedUnit = stampedUnit or acceptedUnit
    if not stampedUnit then
        if _G.QUI_CDM_TAINT_DEBUG then
            DebugAuraStamp("AuraStamp.instance.reject",
                "reason", "no-unit",
                "source", source or "aura-duration",
                "targetCDID", cdID,
                "targetCat", viewerCategory,
                "instID", auraInstanceID)
        end
        return false
    end

    s.auraInstanceID = auraInstanceID
    s.auraInstanceIDSource = source or "aura-duration"
    s.auraUnit = stampedUnit
    s.auraData = auraData
    if stampedDurObj then
        SetDurationLane(cdID, s, "aura", stampedDurObj, source or "aura-duration")
    else
        MarkDurationLaneUnknown(cdID, s, "aura")
    end
    s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
    s.lastTouch = GetTime()
    if _G.QUI_CDM_TAINT_DEBUG then
        DebugAuraStamp("AuraStamp.instance.ok",
            "source", source or "aura-duration",
            "targetCDID", cdID,
            "targetCat", viewerCategory,
            "unit", stampedUnit,
            "instID", auraInstanceID,
            "auraDataInst", auraData and auraData.auraInstanceID,
            "auraDataSpell", auraData and auraData.spellId,
            "auraDataName", auraData and auraData.name,
            "durObj", stampedDurObj ~= nil)
    end
    return true
end

local function CaptureAuraInstanceFromChildFrame(cdID, viewerCategory, child, source)
    if not (cdID and child) then return false end
    local auraData = ReadChildAuraData(child)
    local auraInstanceID = child.auraInstanceID
    if not auraInstanceID and auraData then
        auraInstanceID = auraData.auraInstanceID
    end
    if not auraInstanceID then return false end
    if _G.QUI_CDM_TAINT_DEBUG then
        DebugAuraStamp("AuraStamp.child.try",
            "source", source or "aura-child-frame",
            "targetCDID", cdID,
            "targetCat", viewerCategory,
            "childCDID", child.cooldownID,
            "childCat", GetFrameCategoryName(child),
            "childInst", child.auraInstanceID,
            "auraDataInst", auraData and auraData.auraInstanceID,
            "auraDataSpell", auraData and auraData.spellId,
            "auraDataName", auraData and auraData.name)
    end
    local stamped = StampAuraInstanceIDForCooldown(
        child.auraDataUnit or child.auraUnit,
        cdID,
        auraInstanceID,
        viewerCategory,
        source or "aura-child-frame",
        auraData)
    if _G.QUI_CDM_TAINT_DEBUG then
        DebugAuraStamp(stamped and "AuraStamp.child.ok" or "AuraStamp.child.reject",
            "source", source or "aura-child-frame",
            "targetCDID", cdID,
            "targetCat", viewerCategory,
            "childCDID", child.cooldownID,
            "childCat", GetFrameCategoryName(child),
            "instID", auraInstanceID)
    end
    return stamped
end

-- Per-category seen-set pools. These functions fire per UNIT_AURA × every
-- cooldown viewer child (~500-1000 calls/sec in combat). The per-call
-- `seen = {}` plus the `cat .. ":" .. tostring(relatedID)` key strings were
-- producing ~300-600 KB/s of transient garbage. Cats are known up front
-- (COOLDOWN_RELATED_CATEGORIES / AURA_RELATED_CATEGORIES), so we pre-allocate
-- one set per cat and wipe at function top.
local _captureRelatedSeenCD = {}
for _, cat in ipairs(COOLDOWN_RELATED_CATEGORIES) do
    _captureRelatedSeenCD[cat] = {}
end
local _captureRelatedSeenAura = {}
for _, cat in ipairs(AURA_RELATED_CATEGORIES) do
    _captureRelatedSeenAura[cat] = {}
end

local function CaptureAuraInstanceFromRelatedCooldownChildren(cdID, viewerCategory)
    local info = GetInstanceInfo(cdID, viewerCategory)
    if not info then return false end

    local candidates = BuildAuraDurationSpellCandidates(info)
    for _, cat in ipairs(COOLDOWN_RELATED_CATEGORIES) do
        wipe(_captureRelatedSeenCD[cat])
    end
    for _, cat in ipairs(COOLDOWN_RELATED_CATEGORIES) do
        local catMap = _cdIDByCatSpell[cat]
        local directMap = _directCDIDByCatSpell[cat]
        local seenCat = _captureRelatedSeenCD[cat]
        for _, spellID in ipairs(candidates) do
            local relatedID = (catMap and catMap[spellID]) or (directMap and directMap[spellID])
            if relatedID and not seenCat[relatedID] then
                seenCat[relatedID] = true
                if _G.QUI_CDM_TAINT_DEBUG then
                    local relatedInfo = GetInstanceInfo(relatedID, cat)
                    DebugAuraStamp("AuraStamp.relatedCooldown.try",
                        "targetCDID", cdID,
                        "targetCat", viewerCategory,
                        "candidate", spellID,
                        "sourceCDID", relatedID,
                        "sourceCat", cat,
                        "sourceSpell", relatedInfo and relatedInfo.spellID,
                        "sourceOverride", relatedInfo and relatedInfo.overrideSpellID,
                        "sourceTooltip", relatedInfo and relatedInfo.overrideTooltipSpellID)
                end
                local child = GetInstanceChild(relatedID, cat)
                if CaptureAuraInstanceFromChildFrame(cdID, viewerCategory, child, "aura-related-child") then
                    if _G.QUI_CDM_TAINT_DEBUG then
                        DebugAuraStamp("AuraStamp.relatedCooldown.ok",
                            "targetCDID", cdID,
                            "targetCat", viewerCategory,
                            "candidate", spellID,
                            "sourceCDID", relatedID,
                            "sourceCat", cat)
                    end
                    return true
                end
            end
        end
    end

    return false
end

local function CaptureAuraInstanceFromRelatedAuraChildren(cdID, viewerCategory)
    local info = GetInstanceInfo(cdID, viewerCategory)
    if not info then return false end

    local candidates = BuildAuraDurationSpellCandidates(info)
    for _, cat in ipairs(AURA_RELATED_CATEGORIES) do
        wipe(_captureRelatedSeenAura[cat])
    end
    for _, cat in ipairs(AURA_RELATED_CATEGORIES) do
        local catMap = _cdIDByCatSpell[cat]
        local directMap = _directCDIDByCatSpell[cat]
        local seenCat = _captureRelatedSeenAura[cat]
        local isSelfCat = cat == viewerCategory
        for _, spellID in ipairs(candidates) do
            local relatedID = (directMap and directMap[spellID]) or (catMap and catMap[spellID])
            -- Skip the (cdID, viewerCategory) instance itself, then dedupe
            -- across category iterations. Replaces the per-call string key
            -- `cat .. ":" .. tostring(relatedID)`.
            if relatedID and not (isSelfCat and relatedID == cdID) and not seenCat[relatedID] then
                seenCat[relatedID] = true
                if _G.QUI_CDM_TAINT_DEBUG then
                    local relatedInfo = GetInstanceInfo(relatedID, cat)
                    DebugAuraStamp("AuraStamp.relatedAura.try",
                        "targetCDID", cdID,
                        "targetCat", viewerCategory,
                        "candidate", spellID,
                        "sourceCDID", relatedID,
                        "sourceCat", cat,
                        "sourceSpell", relatedInfo and relatedInfo.spellID,
                        "sourceOverride", relatedInfo and relatedInfo.overrideSpellID,
                        "sourceTooltip", relatedInfo and relatedInfo.overrideTooltipSpellID)
                end
                local child = GetInstanceChild(relatedID, cat)
                if CaptureAuraInstanceFromChildFrame(cdID, viewerCategory, child, "aura-related-child") then
                    if _G.QUI_CDM_TAINT_DEBUG then
                        DebugAuraStamp("AuraStamp.relatedAura.child.ok",
                            "targetCDID", cdID,
                            "targetCat", viewerCategory,
                            "candidate", spellID,
                            "sourceCDID", relatedID,
                            "sourceCat", cat)
                    end
                    return true
                end

                local relatedState = _mirrorState[ResolveInstanceKey(relatedID, cat)]
                if relatedState and relatedState.auraInstanceID
                    and StampAuraInstanceIDForCooldown(
                        relatedState.auraUnit,
                        cdID,
                        relatedState.auraInstanceID,
                        viewerCategory,
                        "aura-related-child") then
                    if _G.QUI_CDM_TAINT_DEBUG then
                        DebugAuraStamp("AuraStamp.relatedAura.state.ok",
                            "targetCDID", cdID,
                            "targetCat", viewerCategory,
                            "candidate", spellID,
                            "sourceCDID", relatedID,
                            "sourceCat", cat,
                            "sourceInst", relatedState.auraInstanceID,
                            "sourceUnit", relatedState.auraUnit)
                    end
                    return true
                end
            end
        end
    end

    return false
end

local function CaptureAuraForCooldownID(unit, cdID, viewerCategory)
    if not (unit and cdID and Sources) then return false end
    local cat = viewerCategory or GetInstanceCategoryName(cdID)
    if not IsAuraViewerCategoryName(cat) then return false end
    if not CooldownInfoMatchesAuraUnit(cdID, unit, cat) then return false end

    local info = GetInstanceInfo(cdID, cat)
    if not info then return false end

    local candidates = BuildAuraDurationSpellCandidates(info)

    local needsSourceFilter = unit == "target"
    for _, spellID in ipairs(candidates) do
        local ad = QueryAuraForMirrorUnit(unit, spellID)
        if ad and (not needsSourceFilter or Helpers.IsAuraOwnedByPlayerOrPet(ad)) then
            StampAuraInstanceForCooldown(unit, cdID, ad, cat)
            return true
        end
    end

    return false
end

local function CaptureAuraForCooldownIDFromExpectedUnits(cdID, viewerCategory)
    local cat = viewerCategory or GetInstanceCategoryName(cdID)
    if not IsAuraViewerCategoryName(cat) then return false end

    local info = GetInstanceInfo(cdID, cat)
    if not info then return false end

    if info.selfAura == false then
        return CaptureAuraForCooldownID("target", cdID, cat)
    end

    return CaptureAuraForCooldownID("player", cdID, cat)
        or CaptureAuraForCooldownID("pet", cdID, cat)
end

local function FormatCandidateIDList(candidates)
    if type(candidates) ~= "table" or #candidates == 0 then return "nil" end
    local out = {}
    for i, id in ipairs(candidates) do
        out[i] = tostring(id)
    end
    return table.concat(out, ",")
end

local PROBE_FIELD_NAMES = {
    "cooldownID",
    "cooldownInfo",
    "spellID",
    "overrideSpellID",
    "overrideTooltipSpellID",
    "linkedSpellID",
    "linkedSpellIDs",
    "auraInstanceID",
    "auraSpellID",
    "auraDataUnit",
    "auraUnit",
    "auraData",
    "isActive",
    "cooldownIsActive",
    "wasSetFromAura",
    "wasSetFromCooldown",
    "wasSetFromCharges",
    "cooldownStartTime",
    "cooldownDuration",
    "cooldownModRate",
    "cooldownUseAuraDisplayTime",
    "cooldownShowSwipe",
    "cooldownEnabled",
    "isOnActualCooldown",
    "duration",
    "modRate",
}

local PROBE_KEY_PATTERNS = {
    "aura",
    "spell",
    "cooldown",
    "duration",
    "linked",
}

local function ProbeCall(owner, method, ...)
    local fn = owner and owner[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, owner, ...)
    if ok then return a, b, c end
    return nil
end

local function FormatProbeValue(value, depth)
    if issecretvalue and issecretvalue(value) then
        return "<SECRET:" .. type(value) .. ">"
    end
    if value == nil then return "nil" end
    local valueType = type(value)
    if valueType ~= "table" or (depth or 0) >= 1 then
        return FormatRawValue(value)
    end

    local parts = {}
    local count = 0
    for k, v in pairs(value) do
        count = count + 1
        if count <= 10 then
            parts[#parts + 1] = FormatProbeValue(k, (depth or 0) + 1)
                .. "=" .. FormatProbeValue(v, (depth or 0) + 1)
        end
    end
    if count > 10 then
        parts[#parts + 1] = "..."
    end
    return "{" .. table.concat(parts, ",") .. "}:table"
end

local function ProbeKeyMatches(key)
    if issecretvalue and issecretvalue(key) then return false end
    if type(key) ~= "string" then return false end
    local lower = key:lower()
    for _, pattern in ipairs(PROBE_KEY_PATTERNS) do
        if lower:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

local function AppendFrameFieldProbeLines(lines, label, frame)
    if type(lines) ~= "table" then return end
    lines[#lines + 1] = ("frameProbe label=%s object=%s"):format(
        tostring(label),
        FormatProbeValue(frame))
    if not frame then return end

    local seen = {}
    for _, key in ipairs(PROBE_FIELD_NAMES) do
        seen[key] = true
        lines[#lines + 1] = ("frameField label=%s key=%s value=%s"):format(
            tostring(label),
            tostring(key),
            FormatProbeValue(frame[key]))
    end

    local emitted = 0
    for key, value in pairs(frame) do
        if ProbeKeyMatches(key) and not seen[key] then
            emitted = emitted + 1
            if emitted > 30 then
                lines[#lines + 1] = ("frameField label=%s more=true"):format(tostring(label))
                break
            end
            lines[#lines + 1] = ("frameField label=%s key=%s value=%s"):format(
                tostring(label),
                tostring(key),
                FormatProbeValue(value))
        end
    end
end

local function AppendFrameAuraDurationProbeLines(lines, label, frame)
    if not (type(lines) == "table" and frame and Sources and Sources.QueryAuraDuration) then
        return
    end

    local instID = frame.auraInstanceID
    if not instID then return end

    local unit = frame.auraDataUnit or frame.auraUnit
    local units
    if not (issecretvalue and issecretvalue(unit)) and type(unit) == "string" and unit ~= "" then
        units = { unit }
    else
        units = ALL_AURA_UNITS
    end

    for _, tryUnit in ipairs(units) do
        local durObj = Sources.QueryAuraDuration(tryUnit, instID)
        lines[#lines + 1] = ("frameAuraDuration label=%s unit=%s inst=%s dur=%s"):format(
            tostring(label),
            tostring(tryUnit),
            FormatProbeValue(instID),
            tostring(durObj and true or false))
    end
end

local function AppendCooldownObjectProbeLines(lines, label, child)
    if type(lines) ~= "table" then return end
    AppendFrameFieldProbeLines(lines, label .. ".child", child)
    AppendFrameAuraDurationProbeLines(lines, label .. ".child", child)

    local cd = child and child.Cooldown
    AppendFrameFieldProbeLines(lines, label .. ".cooldown", cd)
    AppendFrameAuraDurationProbeLines(lines, label .. ".cooldown", cd)

    local startMS, durationMS = ProbeCall(cd, "GetCooldownTimes")
    lines[#lines + 1] = ("frameCooldown label=%s shown=%s times=%s/%s duration=%s"):format(
        tostring(label),
        FormatProbeValue(ProbeCall(cd, "IsShown")),
        FormatProbeValue(startMS),
        FormatProbeValue(durationMS),
        FormatProbeValue(ProbeCall(cd, "GetCooldownDuration")))
end

local function AppendRelatedCooldownProbeLines(lines, sourceCDID, sourceCat, candidates)
    if type(lines) ~= "table" then return end

    local seen = {}
    for _, cat in ipairs({ "essential", "utility" }) do
        local catMap = _cdIDByCatSpell[cat]
        local directMap = _directCDIDByCatSpell[cat]
        for _, spellID in ipairs(candidates or {}) do
            local relatedID = (catMap and catMap[spellID]) or (directMap and directMap[spellID])
            local key = relatedID and (cat .. ":" .. tostring(relatedID)) or nil
            if key and not seen[key] and not (relatedID == sourceCDID and cat == sourceCat) then
                seen[key] = true
                local state = PackState(relatedID, cat)
                lines[#lines + 1] = ("related cat=%s sid=%s cdID=%s active=%s dur=%s source=%s hasInst=%s"):format(
                    tostring(cat),
                    tostring(spellID),
                    tostring(relatedID),
                    tostring(state and state.isActive == true),
                    FormatProbeValue(state and state.durObj),
                    tostring(state and state.durObjSource),
                    tostring(state and state.hasAuraInstanceID == true))
                AppendCooldownObjectProbeLines(lines, "related." .. cat .. "." .. tostring(relatedID), GetInstanceChild(relatedID, cat))
            end
        end
    end
end

local function GetAuraDataSpellID(ad)
    if not ad then return nil end
    local sid = ad.spellId
    if not sid then sid = ad.spellID end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(sid) then
        return nil
    end
    if type(sid) == "number" and sid > 0 then
        return sid
    end
    return nil
end

local function GetAuraDataName(ad)
    if not ad then return nil end
    local name = ad.name
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(name) then
        return nil
    end
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function BuildAuraCandidateNameSet(candidates)
    local names = {}
    if not (type(candidates) == "table" and Sources and Sources.QuerySpellName) then
        return names
    end
    for _, spellID in ipairs(candidates) do
        local name = Sources.QuerySpellName(spellID)
        if not (Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(name))
            and type(name) == "string"
            and name ~= "" then
            names[name] = true
        end
    end
    return names
end

local function AppendAuraScanProbeLines(lines, units, candidates)
    if not (type(lines) == "table" and Sources and Sources.QueryUnitAuras) then
        return
    end

    local candidateIDs = {}
    for _, spellID in ipairs(candidates or {}) do
        candidateIDs[spellID] = true
    end
    local candidateNames = BuildAuraCandidateNameSet(candidates)
    local filters = { "HELPFUL", "HARMFUL" }

    for _, unit in ipairs(units or {}) do
        for _, filter in ipairs(filters) do
            local auras = Sources.QueryUnitAuras(unit, filter, 80)
            if type(auras) ~= "table" then
                lines[#lines + 1] = ("scan unit=%s filter=%s auras=nil"):format(
                    tostring(unit), tostring(filter))
            else
                local ids = {}
                local total = #auras
                local limit = total < 24 and total or 24
                for i = 1, total do
                    local ad = auras[i]
                    local sid = GetAuraDataSpellID(ad)
                    local name = GetAuraDataName(ad)
                    local isCandidateID = sid and candidateIDs[sid]
                    local isCandidateName = name and candidateNames[name]
                    if i <= limit then
                        ids[#ids + 1] = sid and tostring(sid) or "nil"
                    end
                    if isCandidateID or isCandidateName then
                        local instID = ad and ad.auraInstanceID
                        local durObj = instID and Sources.QueryAuraDuration
                            and Sources.QueryAuraDuration(unit, instID)
                        lines[#lines + 1] = ("scanHit unit=%s filter=%s index=%s sid=%s name=%s inst=%s dur=%s by=%s"):format(
                            tostring(unit),
                            tostring(filter),
                            tostring(i),
                            tostring(sid),
                            tostring(name),
                            tostring(instID and true or false),
                            tostring(durObj and true or false),
                            isCandidateID and "id" or "name")
                    end
                end
                if total > limit then
                    ids[#ids + 1] = "..."
                end
                lines[#lines + 1] = ("scan unit=%s filter=%s count=%s ids=%s"):format(
                    tostring(unit),
                    tostring(filter),
                    tostring(total),
                    table.concat(ids, ","))
            end
        end
    end
end

local function BuildAuraProbeLines(cdID, viewerCategory)
    local cat = viewerCategory or GetInstanceCategoryName(cdID)
    if not IsAuraViewerCategoryName(cat) then return nil end

    local info = GetInstanceInfo(cdID, cat)
    if not info then return nil end

    local candidates = BuildAuraDurationSpellCandidates(info)
    local lines = {
        "probe candidates=" .. FormatCandidateIDList(candidates),
    }

    local units
    if info.selfAura == false then
        units = TARGET_AURA_UNITS
    else
        units = SELF_AURA_UNITS
    end

    for _, unit in ipairs(units) do
        for _, spellID in ipairs(candidates) do
            local ad = QueryAuraForMirrorUnit(unit, spellID)
            local instID = ad and ad.auraInstanceID
            local durObj = instID and Sources and Sources.QueryAuraDuration
                and Sources.QueryAuraDuration(unit, instID)
            local owner = "n/a"
            if unit == "target" and ad then
                owner = tostring(Helpers.IsAuraOwnedByPlayerOrPet(ad) == true)
            end
            lines[#lines + 1] = ("probe unit=%s sid=%s ad=%s inst=%s dur=%s owner=%s"):format(
                tostring(unit),
                tostring(spellID),
                tostring(ad and true or false),
                tostring(instID and true or false),
                tostring(durObj and true or false),
                owner)
        end
    end

    AppendCooldownObjectProbeLines(lines, "current." .. tostring(cat) .. "." .. tostring(cdID), GetInstanceChild(cdID, cat))
    AppendRelatedCooldownProbeLines(lines, cdID, cat, candidates)
    AppendAuraScanProbeLines(lines, units, candidates)

    return lines
end

RequestMirrorTextRefresh = function(cooldownID, viewerCategory, reason)
    local icons = ns.CDMIcons
    if icons and icons.RequestMirrorTextRefresh then
        icons:RequestMirrorTextRefresh(cooldownID, viewerCategory, reason)
    end
end

RequestMirrorTextRefreshForState = function(cooldownID, state, reason)
    if not cooldownID then return end
    RequestMirrorTextRefresh(cooldownID,
        state and state.viewerCategory or GetInstanceCategoryName(cooldownID),
        reason)
end

RequestMirrorTextRefreshForChild = function(child, cooldownID, state, reason)
    if not cooldownID then return end
    RequestMirrorTextRefresh(cooldownID,
        state and state.viewerCategory
            or GetFrameCategoryName(child)
            or GetInstanceCategoryName(cooldownID),
        reason)
end

RequestMirrorTextRefreshForMappedSpells = function(reason, ...)
    local requested = false
    for i = 1, select("#", ...) do
        local spellID = select(i, ...)
        if spellID then
            for catName, catMap in pairs(_cdIDByCatSpell) do
                local cdID = catMap[spellID]
                if cdID then
                    RequestMirrorTextRefresh(cdID, catName, reason)
                    requested = true
                end
            end
            for catName, directMap in pairs(_directCDIDByCatSpell) do
                local cdID = directMap[spellID]
                if cdID then
                    RequestMirrorTextRefresh(cdID, catName, reason)
                    requested = true
                end
            end
        end
    end
    return requested
end

local function FindMirrorFontString(owner)
    if not owner then return nil end
    if owner.GetObjectType and owner:GetObjectType() == "FontString" then
        return owner
    end
    if owner.GetNumRegions and owner.GetRegions then
        for i = 1, owner:GetNumRegions() do
            local region = select(i, owner:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                return region
            end
        end
    end
    if owner.GetChildren then
        local children = { owner:GetChildren() }
        for i = 1, #children do
            local found = FindMirrorFontString(children[i])
            if found then return found end
        end
    end
    return nil
end

local function FindDirectMirrorFontString(owner)
    if not owner then return nil end
    if owner.GetObjectType and owner:GetObjectType() == "FontString" then
        return owner
    end
    if owner.GetNumRegions and owner.GetRegions then
        for i = 1, owner:GetNumRegions() do
            local region = select(i, owner:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                return region
            end
        end
    end
    return nil
end

local function FindNamedMirrorTextOwner(owner, ...)
    if not owner then return nil end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local candidate = owner[key]
        if candidate and (candidate.GetText or candidate.SetText or candidate.SetFormattedText) then
            return candidate
        end
    end
    return nil
end

local function FindMirrorTextOwner(owner, ...)
    return FindNamedMirrorTextOwner(owner, ...) or FindMirrorFontString(owner)
end

local function FindDirectMirrorTextOwner(owner, ...)
    return FindNamedMirrorTextOwner(owner, ...) or FindDirectMirrorFontString(owner)
end

ClearMirrorStackState = function(s)
    if not s then return false end
    if not (s.stackText or s.stackTextSource or s.stackTextShown == true) then
        return false
    end
    s.stackText = nil
    s.stackTextSource = nil
    s.stackTextShown = false
    s.stackTextEpoch = (s.stackTextEpoch or 0) + 1
    return true
end

local STACK_TEXT_SOURCE_PRIORITY = {
    FrameText = 1,
    ChargeCount = 2,
    Applications = 3,
}

local function StackTextSourcePriority(source)
    return STACK_TEXT_SOURCE_PRIORITY[source] or 0
end

local function CanReplaceStackTextSource(currentSource, source)
    if not currentSource then return true end
    return StackTextSourcePriority(source) >= StackTextSourcePriority(currentSource)
end

local function MirrorStackTextHasDisplay(source, text)
    if text == nil then return false end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(text) then
        return true
    end
    if issecretvalue and issecretvalue(text) then
        return true
    end

    local textType = type(text)
    if source == "Applications" then
        if textType == "string" then
            return not (text == "" or text == "0" or text == "1")
        end
        if textType == "number" then
            return text > 1
        end
        return true
    end

    if textType == "string" then
        return text ~= ""
    end
    return true
end

local function ChildHasAuthoritativeCountText(child)
    local cdID = child and child.cooldownID
    if not cdID then return false end

    local chargesShown = SafeFrameBooleanField(child, "cooldownChargesShown")
    if chargesShown == true then
        return true
    end
    if chargesShown == false then
        return false
    end

    local chargeFrameShown = SafeFrameShownField(child.ChargeCount)
    if chargeFrameShown == true then
        return true
    end
    if chargeFrameShown == false then
        return false
    end

    return false
end

local function CaptureChildStackText(child, source, text, fromTextWrite)
    local cdID = child and child.cooldownID
    if not (cdID and source) then return end
    local s = EnsureState(cdID, child)
    if not s then return end

    if source == "ChargeCount" and not ChildHasAuthoritativeCountText(child) then
        if (not s.stackTextSource or s.stackTextSource == source) and ClearMirrorStackState(s) then
            s.lastTouch = GetTime()
            RequestMirrorTextRefreshForChild(child, cdID, s, "stack-clear")
        end
        return
    end

    if MirrorStackTextHasDisplay(source, text) then
        if not CanReplaceStackTextSource(s.stackTextSource, source) then
            return
        end
        s.stackText = text
        s.stackTextSource = source
        s.stackTextShown = true
        s.stackTextEpoch = (s.stackTextEpoch or 0) + 1
        s.lastTouch = GetTime()
        RequestMirrorTextRefreshForChild(child, cdID, s, "stack-text")
        return
    end

    if (not s.stackTextSource or s.stackTextSource == source) and ClearMirrorStackState(s) then
        s.lastTouch = GetTime()
        RequestMirrorTextRefreshForChild(child, cdID, s, "stack-empty")
    end
end

local function ClearChildStackText(child, source)
    local cdID = child and child.cooldownID
    if not cdID then return end
    local s = EnsureState(cdID, child)
    if not s then return end
    if s.stackTextSource and source and s.stackTextSource ~= source then return end
    if ClearMirrorStackState(s) then
        s.lastTouch = GetTime()
        RequestMirrorTextRefreshForChild(child, cdID, s, "stack-clear")
    end
end

local function CaptureTextFromOwner(child, source, owner, fromTextWrite)
    if not (owner and owner.GetText) then return end
    CaptureChildStackText(child, source, owner:GetText(), fromTextWrite)
end

local function CaptureTextFromPreferredOwner(child, source, owner, readOwner, fallbackText, fromTextWrite)
    if readOwner and readOwner ~= owner and readOwner.GetText then
        local text = readOwner:GetText()
        if MirrorStackTextHasDisplay(source, text) then
            CaptureChildStackText(child, source, text, fromTextWrite)
            return
        end
        if fallbackText ~= nil and MirrorStackTextHasDisplay(source, fallbackText) then
            CaptureChildStackText(child, source, fallbackText, fromTextWrite)
            return
        end
        CaptureChildStackText(child, source, text, fromTextWrite)
        return
    end
    if fallbackText ~= nil then
        CaptureChildStackText(child, source, fallbackText, fromTextWrite)
        return
    end
    CaptureTextFromOwner(child, source, owner, fromTextWrite)
end

local function HookTextOwner(child, source, owner, readOwner)
    if not owner or _textOwnerHooked[owner] then return end
    _textOwnerHooked[owner] = true
    readOwner = readOwner or owner

    if owner.SetText then
        hooksecurefunc(owner, "SetText", function(_, text)
            CaptureTextFromPreferredOwner(child, source, owner, readOwner, text, true)
        end)
    end
    if owner.SetFormattedText then
        hooksecurefunc(owner, "SetFormattedText", function(self)
            CaptureTextFromPreferredOwner(child, source, self, readOwner, nil, true)
        end)
    end
    if owner.Show then
        hooksecurefunc(owner, "Show", function()
            CaptureTextFromPreferredOwner(child, source, owner, readOwner)
        end)
    end
    if owner.Hide then
        hooksecurefunc(owner, "Hide", function()
            ClearChildStackText(child, source)
        end)
    end
    if owner.SetShown then
        hooksecurefunc(owner, "SetShown", function(_, shown)
            local decoded = DecodePotentialSecretBoolean(shown)
            if decoded == false then
                ClearChildStackText(child, source)
            else
                CaptureTextFromPreferredOwner(child, source, owner, readOwner)
            end
        end)
    end

    CaptureTextFromPreferredOwner(child, source, owner, readOwner)
end

local function BindChildTextHooks(child)
    if not child then return end

    local applications = child.Applications
    if applications then
        local textOwner = FindMirrorTextOwner(applications, "DisplayText", "Applications")
        HookTextOwner(child, "Applications", applications, textOwner)
        if textOwner and textOwner ~= applications then
            HookTextOwner(child, "Applications", textOwner)
        end
    end

    local chargeCount = child.ChargeCount
    if chargeCount then
        local textOwner = FindMirrorTextOwner(chargeCount, "Current", "DisplayText")
        HookTextOwner(child, "ChargeCount", chargeCount, textOwner)
        if textOwner and textOwner ~= chargeCount then
            HookTextOwner(child, "ChargeCount", textOwner)
        end
    end

    local frameText = FindDirectMirrorTextOwner(child, "DisplayText", "Text", "Count", "StackText", "Stacks")
    HookTextOwner(child, "FrameText", frameText)
end

local function ReadChildSemanticActive(child, cdID)
    if not child then return nil end

    if IsAuraViewerCategory(cdID, GetFrameCategoryName(child)) then
        -- Aura viewer children stay shown even when inactive, so frame
        -- visibility is not meaningful. The per-cooldownID child field is
        -- Blizzard's exact active-state signal for entries that do not expose
        -- a normal aura instance path (hasAura=false). Decode via the same
        -- CurveUtil helper Blizzard uses for secret booleans; if decoding is
        -- unavailable, return nil so callers preserve the prior state.
        local active = SafeFrameBooleanField(child, "isActive")
        if active ~= nil then return active end
        return SafeFrameBooleanField(child, "cooldownIsActive")
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
        if IsAuraViewerCategory(cdID) then
            active = s.isActive == true
        else
            active = fallbackActive == true
        end
    end

    -- Target-side aura viewer children can report active for a matching
    -- target debuff regardless of caster. Only trust them after the
    -- source-filtered auraInstance path has stamped this state.
    if active and AuraViewerNeedsTargetOwnershipProof(cdID, s, child) and not s.auraInstanceID then
        local captured = CaptureAuraInstanceFromChildFrame(cdID, s.viewerCategory, child)
            or CaptureAuraInstanceFromRelatedCooldownChildren(cdID, s.viewerCategory)
        if not captured and not s.auraInstanceID then
            active = false
        end
    end

    local priorActive = s.isActive == true
    local changed = priorActive ~= active
    if not active and (s.durObj or s.auraDurObj or s.cooldownDurObj
        or s.resourceDurObj or s.gcdDurObj or s.totemDurObj
        or s.pandemicActive or s.pandemicStateKnown) then
        changed = true
    end
    if changed then
        s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
        RequestMirrorTextRefreshForChild(child, cdID, s, "active-state")
    end
    s.isActive = active
    if active then
        local info = GetInstanceInfo(cdID, s.viewerCategory)
        if not s.auraUnit then
            s.auraUnit = GetChildAuraUnit(child)
                or ((info and info.selfAura == false) and "target" or "player")
        end
        if IsAuraViewerCategory(cdID, s) and not s.auraDurObj then
            local captured = CaptureAuraInstanceFromChildFrame(cdID, s.viewerCategory, child)
            if not captured then
                CaptureAuraInstanceFromRelatedCooldownChildren(cdID, s.viewerCategory)
            end
        elseif not IsAuraViewerCategory(cdID, s) then
            CaptureAuraInstanceFromRelatedAuraChildren(cdID, s.viewerCategory)
        end
    else
        ClearAllDurationLanes(cdID, s)
        s.auraInstanceID = nil
        s.auraInstanceIDSource = nil
        s.auraUnit = nil
        s.auraData = nil
        s.pandemicActive = false
        s.pandemicStateKnown = nil
        if ClearMirrorStackState(s) then
            RequestMirrorTextRefreshForChild(child, cdID, s, "inactive-stack-clear")
        end
        if SetHostPandemicState then
            SetHostPandemicState(cdID, nil, false)
        end
    end
    s.lastTouch = GetTime()
    return active
end

local function ShouldPreserveTransientNonAuraCooldownClear(cdID, child, s)
    if not s or IsAuraViewerCategory(cdID, s) then return false end
    if not (s.cooldownDurObj or s.resourceDurObj or s.gcdDurObj) then
        return false
    end
    if SafeFrameBooleanField(child, "cooldownIsActive") == false then
        return false
    end
    if SafeFrameBooleanField(child, "isActive") ~= true then
        return false
    end
    return SafeFrameBooleanField(child, "wasSetFromCooldown") == true
        or SafeFrameBooleanField(child, "wasSetFromCharges") == true
end

local function RefreshAuraViewerChildActiveStates()
    for _, child in pairs(_childByInstanceKey) do
        local cdID = child and child.cooldownID
        if IsAuraViewerCategory(cdID, GetFrameCategoryName(child)) and child then
            RefreshChildSemanticState(child, cdID, false)
        end
    end
end

local function RefreshCooldownViewerRelatedAuraStates()
    local changed = false
    for _, child in pairs(_childByInstanceKey) do
        local cdID = child and child.cooldownID
        local cat = child and GetFrameCategoryName(child)
        if cdID and cat and not IsAuraViewerCategoryName(cat) then
            local s = EnsureState(cdID, child, cat)
            if s and s.isActive == true then
                local hadRelatedAura = s.auraDurObjSource == "aura-related-child"
                    or s.auraInstanceIDSource == "aura-related-child"
                if CaptureAuraInstanceFromRelatedAuraChildren(cdID, cat) then
                    RequestMirrorTextRefreshForState(cdID, s, "related-aura")
                    changed = true
                elseif hadRelatedAura then
                    ClearAuraDurationLane(cdID, s)
                    s.auraInstanceID = nil
                    s.auraInstanceIDSource = nil
                    s.auraUnit = nil
                    s.auraData = nil
                    s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
                    s.lastTouch = GetTime()
                    RequestMirrorTextRefreshForState(cdID, s, "related-aura-clear")
                    changed = true
                end
            end
        end
    end

    return changed
end

SetHostPandemicState = function(cdID, active, known)
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
-- Implementation lives in the load-on-demand debug addon. The placeholder
-- below is rebound by cdm_debug.lua's BindAll() when loaded; cdm_debug.lua
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
-- StampAuraInstanceForCooldown, the resolver, SyncBlizzMirrorIconState)
-- can treat the stored info as a plain Lua table with comparable values.
---------------------------------------------------------------------------
-- Order of operations matters: check IsSecretValue FIRST. Doing
-- `if v == nil then return nil end` before the secret strip would
-- itself error when v is secret, defeating the whole point. IsSecretValue
-- on nil is safe (returns false), so checking it first costs nothing.
-- The post-strip `==` and `>` operations only run on values we've
-- proven non-secret.
CleanScalar = function(v)
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
CleanBool = function(v)
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
    if _G.QUI_CDM_TAINT_DEBUG then
        TaintLog(
            "Sanitize",
            "cdID", cdID,
            "raw.spellID",                info.spellID,
            "raw.overrideSpellID",        info.overrideSpellID,
            "raw.overrideTooltipSpellID", info.overrideTooltipSpellID,
            "raw.selfAura",               info.selfAura,
            "raw.hasAura",                info.hasAura,
            "raw.charges",                info.charges,
            "raw.isKnown",                info.isKnown)
    end
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

local function CaptureCooldownInfoForCategory(cdID, catName, child)
    if not (cdID and catName) then return nil end
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    if not info then return nil end

    local clean = SanitizeCooldownInfo(cdID, info)
    RegisterCooldownInstance(cdID, catName, child, clean)
    local catMap = _cdIDByCatSpell[catName]
    MapCooldownInfoIDs(catMap, clean, cdID)
    _IndexSpellNameForCDID(cdID, clean)
    return clean
end

local function BindChildToCatalogCategories(child, cdID, viewerCategoryNum)
    if not (child and cdID) then return false end
    local viewerCatName = CATEGORY_NAMES[viewerCategoryNum]
    local categories = ResolveChildCatalogCategories(cdID, viewerCatName)
    local bound = false

    for _, catName in ipairs(categories) do
        local catNum = CATEGORY_NUM_BY_NAME[catName] or viewerCategoryNum
        local info = GetInstanceInfo(cdID, catName)
        if not info then
            info = CaptureCooldownInfoForCategory(cdID, catName, child)
        else
            RegisterCooldownInstance(cdID, catName, child, nil)
        end
        if info then
            BindChildHooks(child, cdID, catNum)
            bound = true
        end
    end

    return bound
end

local function ClearCatalogMaps()
    for _, catMap in pairs(_cdIDByCatSpell) do
        wipe(catMap)
    end
    for _, directMap in pairs(_directCDIDByCatSpell) do
        wipe(directMap)
    end
    wipe(_cooldownInfoByID)
    wipe(_cooldownInfoByKey)
    wipe(_auraDurationCandidatesByInfo)
    wipe(_spellDurationCandidatesByInfo)
    wipe(_packedStateByInstanceKey)
    wipe(_childByCooldownID)
    wipe(_childByInstanceKey)
    wipe(_viewerCategoryByID)
    wipe(_viewerCategoryByKey)
    for _, byCat in pairs(_instanceKeyByCatID) do
        wipe(byCat)
    end
    wipe(_defaultInstanceKeyByID)
    wipe(_spellNameToCDID)
    wipe(_totemSpellIDToCDID)
end

local function RemoveCooldownIDFromMaps(cdID, onlyCatName)
    if not cdID then return end
    for catName, catMap in pairs(_cdIDByCatSpell) do
        if onlyCatName and catName ~= onlyCatName then
            -- continue
        else
        for spellID, mappedCDID in pairs(catMap) do
            if mappedCDID == cdID then
                catMap[spellID] = nil
            end
        end
        end
    end
    for catName, directMap in pairs(_directCDIDByCatSpell) do
        if onlyCatName and catName ~= onlyCatName then
            -- continue
        else
        for spellID, mappedCDID in pairs(directMap) do
            if mappedCDID == cdID then
                directMap[spellID] = nil
            end
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

function BindChildHooks(child, cooldownID, viewerCategoryNum)
    -- Always refresh the bind-time category map and seed state for the
    -- current cooldownID, even if the frame was already bound.
    local catName = CATEGORY_NAMES[viewerCategoryNum]
    _categoryByFrame[child] = viewerCategoryNum
    RegisterCooldownInstance(cooldownID, catName, child, nil)
    EnsureState(cooldownID, child, catName)
    RefreshChildSemanticState(child, cooldownID, false)

    local cooldownFrame = child.Cooldown
    if cooldownFrame then
        _childByCooldownFrame[cooldownFrame] = child
    end

    BindChildTextHooks(child)

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
    -- Reads the original owner child's cooldownID dynamically. The explicit
    -- cooldown-frame map avoids depending on current parentage.
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
        hooksecurefunc(cooldownFrame, "SetCooldownFromDurationObject", function(self, durObj, clearIfZero)
            local cdID, owner = _ownerCooldownID(self)
            if not cdID then return end
            local s = EnsureState(cdID, owner)
            StoreCooldownSetterArgs(s, "SetCooldownFromDurationObject", durObj, clearIfZero)
            if IsAuraViewerCategory(cdID, s) then
                local capturedAura = CaptureAuraInstanceFromChildFrame(cdID, s.viewerCategory, owner)
                    or CaptureAuraInstanceFromRelatedCooldownChildren(cdID, s.viewerCategory)
                local needsTargetOwnershipProof = AuraViewerNeedsTargetOwnershipProof(cdID, s, owner)
                local trusted = capturedAura
                    or (not needsTargetOwnershipProof)
                    or (s.auraInstanceID and true or false)
                if not trusted then
                    capturedAura = CaptureAuraForCooldownIDFromExpectedUnits(cdID, s.viewerCategory)
                    trusted = capturedAura
                end
                if trusted then
                    if durObj then
                        SetDurationLane(cdID, s, "aura", durObj, AURA_CHILD_DURATION_SOURCE)
                    elseif not s.auraDurObj then
                        capturedAura = capturedAura
                            or CaptureAuraInstanceFromChildFrame(cdID, s.viewerCategory, owner)
                            or CaptureAuraInstanceFromRelatedCooldownChildren(cdID, s.viewerCategory)
                            or CaptureAuraForCooldownIDFromExpectedUnits(cdID, s.viewerCategory)
                        if not s.auraInstanceID and not s.auraDurObj then
                            MarkDurationLaneUnknown(cdID, s, "aura")
                        end
                    end
                    s.isActive = true
                else
                    s.isActive = false
                    ClearAuraDurationLane(cdID, s)
                end
                s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
                s.lastTouch   = GetTime()
                if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                    CDMBlizzMirror.TaintLog("hook.SCFDO.aura-cat",
                        "cdID", cdID,
                        "trusted", trusted,
                        "durObjSource", s.durObjSource,
                        "hasDurObj", s.durObj and true or false)
                end
                return
            end

            local fromAura = SafeFrameBooleanField(owner, "wasSetFromAura") == true
            local fromCharges = SafeFrameBooleanField(owner, "wasSetFromCharges") == true
            local chargeDurObj, chargeSource
            if not fromAura then
                chargeDurObj, chargeSource = CDMBlizzMirror.ResolveChargeDurationObjectForCooldownID(cdID, owner, s)
            end
            local suppressChargeDuration = not chargeDurObj
                and fromCharges
                and CDMBlizzMirror.ShouldSuppressChargeDurationForCooldownID(cdID, owner, s)
            local lane = fromAura and "aura"
                or (chargeDurObj and "resource")
                or (fromCharges and not suppressChargeDuration and "resource" or "cooldown")
            local source = fromAura and "aura-duration"
                or chargeSource
                or (fromCharges and not suppressChargeDuration and "spell-charge" or "cooldown-frame")
            durObj = chargeDurObj or durObj
            if suppressChargeDuration then
                s.resourceDurObj = nil
                s.resourceDurObjSource = nil
                s.resourceDurationStateUnknown = nil
            end
            if not fromAura and not fromCharges
                and ShouldUseGCDDurationForCooldownID(cdID, owner, s) then
                lane = "gcd"
                source = "gcd-duration"
            end
            -- Capture for side effect: writes the aura lane via the related-
            -- aura-child path. SetDurationLane below runs RefreshSelectedDurationState
            -- on tail, which picks the freshly-captured aura ahead of this lane.
            CaptureAuraInstanceFromRelatedAuraChildren(cdID, s.viewerCategory)
            SetDurationLane(cdID, s, lane, durObj, source)
            s.isActive    = true
            s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
            s.lastTouch   = GetTime()
            if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                CDMBlizzMirror.TaintLog("hook.SCFDO", "cdID", cdID,
                    "durObjSource", s.durObjSource)
            end
        end)
    end

    -- Active-edge: hook EVERY Cooldown setter Blizzard might use. Different
    -- mixins / different code paths use different methods; missing any of
    -- them leaves m.isActive stuck at false. We don't read the args (some
    -- are secret in combat post-12.0.5); the call's existence is the signal.
    local function _activateMirror(self, methodName, a, b, c)
        local cdID, owner = _ownerCooldownID(self)
        if not cdID then return end
        local s = EnsureState(cdID, owner)
        StoreCooldownSetterArgs(s, methodName, a, b, c)
        if IsAuraViewerCategory(cdID, s) then
            local capturedAura = CaptureAuraInstanceFromChildFrame(cdID, s.viewerCategory, owner)
                or CaptureAuraInstanceFromRelatedCooldownChildren(cdID, s.viewerCategory)
            local needsTargetOwnershipProof = AuraViewerNeedsTargetOwnershipProof(cdID, s, owner)
            local trusted = capturedAura
                or (not needsTargetOwnershipProof)
                or (s.auraInstanceID and true or false)
            if not trusted then
                capturedAura = CaptureAuraForCooldownIDFromExpectedUnits(cdID, s.viewerCategory)
                trusted = capturedAura
            end
            if trusted then
                if not s.auraDurObj then
                    capturedAura = capturedAura
                        or CaptureAuraInstanceFromChildFrame(cdID, s.viewerCategory, owner)
                        or CaptureAuraInstanceFromRelatedCooldownChildren(cdID, s.viewerCategory)
                        or CaptureAuraForCooldownIDFromExpectedUnits(cdID, s.viewerCategory)
                end
                if not s.auraInstanceID and not s.auraDurObj then
                    MarkDurationLaneUnknown(cdID, s, "aura")
                end
                s.isActive = true
            else
                s.isActive = false
                ClearAuraDurationLane(cdID, s)
            end
            s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
            s.lastTouch   = GetTime()
            if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                CDMBlizzMirror.TaintLog("hook." .. methodName, "cdID", cdID,
                    "durObjSource", s.durObjSource,
                    "hasDurObj", s.durObj and true or false,
                    "durationStateUnknown", s.durationStateUnknown)
            end
            return
        end
        s.isActive    = true
        s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
        s.lastTouch   = GetTime()
        local durObj, source = ResolveSpellDurationObjectForCooldownID(cdID, owner, s)
        -- Capture for side effect: writes the aura lane via the related-aura-
        -- child path. SetDurationLane below refreshes the selection on tail,
        -- which picks the freshly-captured aura ahead of this lane.
        CaptureAuraInstanceFromRelatedAuraChildren(cdID, s.viewerCategory)
        if durObj then
            local lane = source == "spell-charge" and "resource"
                or (source == "gcd-duration" and "gcd" or "cooldown")
            SetDurationLane(cdID, s, lane, durObj, source)
        elseif not s.auraInstanceID then
            local fromAura = SafeFrameBooleanField(owner, "wasSetFromAura") == true
            if fromAura then
                MarkDurationLaneUnknown(cdID, s, "aura")
            else
                MarkDurationLaneUnknown(cdID, s, "cooldown")
            end
        end
        if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
            CDMBlizzMirror.TaintLog("hook." .. methodName, "cdID", cdID,
                "durObjSource", s.durObjSource,
                "hasDurObj", s.durObj and true or false,
                "durationStateUnknown", s.durationStateUnknown)
        end
    end
    if cooldownFrame and cooldownFrame.SetCooldown then
        hooksecurefunc(cooldownFrame, "SetCooldown", function(self, startTime, duration, modRate)
            _activateMirror(self, "SetCooldown", startTime, duration, modRate)
        end)
    end
    if cooldownFrame and cooldownFrame.SetCooldownFromExpirationTime then
        hooksecurefunc(cooldownFrame, "SetCooldownFromExpirationTime", function(self, expirationTime, duration, modRate)
            _activateMirror(self, "SetCooldownFromExpirationTime", expirationTime, duration, modRate)
        end)
    end
    if cooldownFrame and cooldownFrame.SetCooldownDuration then
        hooksecurefunc(cooldownFrame, "SetCooldownDuration", function(self, duration, modRate)
            _activateMirror(self, "SetCooldownDuration", duration, modRate)
        end)
    end
    if cooldownFrame and cooldownFrame.SetCooldownUNIX then
        hooksecurefunc(cooldownFrame, "SetCooldownUNIX", function(self, startTime, duration, modRate)
            _activateMirror(self, "SetCooldownUNIX", startTime, duration, modRate)
        end)
    end

    if cooldownFrame and cooldownFrame.Clear then
        hooksecurefunc(cooldownFrame, "Clear", function(self)
            local cdID, owner = _ownerCooldownID(self)
            if not cdID then return end
            local s = EnsureState(cdID, owner)
            if not s then return end

            -- Aura-category cdIDs: the exact child field `isActive`, refreshed
            -- from UNIT_AURA and child Show/Hide hooks, owns visibility. Clear
            -- can fire while the child still represents an active durationless
            -- aura, so only refresh a duration object here and never clobber
            -- isActive from this path.
            local cat = s.viewerCategory or GetFrameCategoryName(owner)
            if cat == "buff" or cat == "trackedBar" then
                local childOwnsAuraDuration = s.auraDurObj
                    and s.auraDurObjSource == AURA_CHILD_DURATION_SOURCE
                if not childOwnsAuraDuration
                    and s.auraInstanceID
                    and Sources
                    and Sources.QueryAuraDuration then
                    local durObj = Sources.QueryAuraDuration(s.auraUnit or "player", s.auraInstanceID)
                    if durObj then
                        SetDurationLane(cdID, s, "aura", durObj, "aura-duration")
                        s.lastTouch = GetTime()
                    end
                end
                if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                    CDMBlizzMirror.TaintLog("hook.Clear.skip-aura-cat",
                        "cdID", cdID)
                end
                return
            end

            -- Non-aura cdID (essential / utility / cooldown-only):
            -- Clear is the de-active edge.
            if ShouldPreserveTransientNonAuraCooldownClear(cdID, owner, s) then
                s.isActive = true
                s.lastTouch = GetTime()
                if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                    CDMBlizzMirror.TaintLog("hook.Clear.preserve-active", "cdID", cdID)
                end
                return
            end

            s.isActive = false
            ClearAllDurationLanes(cdID, s)
            s.pandemicActive = false
            s.pandemicStateKnown = nil
            if SetHostPandemicState then
                SetHostPandemicState(cdID, nil, false)
            end
            s.lastTouch = GetTime()
            if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
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
        if IsAuraViewerCategory(cdID, GetFrameCategoryName(self)) then
            RefreshCooldownViewerRelatedAuraStates()
        end
    end)

    hooksecurefunc(child, "Hide", function(self)
        local cdID = self.cooldownID
        if not cdID then return end
        RefreshChildSemanticState(self, cdID, false)
        if IsAuraViewerCategory(cdID, GetFrameCategoryName(self)) then
            RefreshCooldownViewerRelatedAuraStates()
        end
    end)

    if child.SetShown then
        hooksecurefunc(child, "SetShown", function(self, shown)
            local cdID = self.cooldownID
            if not cdID then return end
            local fallbackActive = DecodePotentialSecretBoolean(shown) == true
            RefreshChildSemanticState(self, cdID, fallbackActive)
            if IsAuraViewerCategory(cdID, GetFrameCategoryName(self)) then
                RefreshCooldownViewerRelatedAuraStates()
            end
        end)
    end
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
    -- combat /reload leaves the catalog empty and every Blizzard-mirrored icon
    -- (essential/utility/buff/trackedBar) fails to bind until combat ends.
    if InCombatLockdown() and not (ns and ns._inInitSafeWindow) then
        _walkPendingOnRegen = true
        return
    end
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return
    end

    ClearCatalogMaps()

    -- First trust Blizzard's category-set API as the category authority.
    -- Live children can be parented under a different viewer container than
    -- their category-set owner, so indexing only same-viewer children drops
    -- entries that still have valid CooldownViewer info.
    for catNum = 0, 3 do
        local catName = CATEGORY_NAMES[catNum]
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(catNum, false)
        if type(cooldownIDs) == "table" then
            for _, cdID in ipairs(cooldownIDs) do
                CaptureCooldownInfoForCategory(cdID, catName, nil)
            end
        end
    end

    -- Then bind whatever live children Blizzard actually parented under the
    -- viewer frames. If a child's cdID is known to exactly one API category,
    -- bind it to that category even when it lives under another viewer.
    for catNum = 0, 3 do
        local viewerName = CATEGORY_GLOBALS[catNum]
        local viewer = _G[viewerName]
        if viewer and viewer.GetChildren then
            local children = { viewer:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                local cdID = child and child.cooldownID
                if cdID then
                    BindChildToCatalogCategories(child, cdID, catNum)
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
                if cdID then
                    local wasBound = child._quiMirrorBound == true
                    local bound = BindChildToCatalogCategories(child, cdID, catNum)
                    if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                        CDMBlizzMirror.TaintLog("LazyBind", "cdID", cdID,
                            "viewerCat", CATEGORY_NAMES[catNum],
                            "bound", bound)
                    end
                    -- Fire the new-child signal when hooks were attached for
                    -- the first time. Later passes still refresh category
                    -- mappings for reassigned pool children without forcing
                    -- every bound icon through another retry.
                    if bound and not wasBound then
                        local categories = ResolveChildCatalogCategories(cdID, CATEGORY_NAMES[catNum])
                        for _, catName in ipairs(categories) do
                            FireOnChildBound(cdID, catName)
                        end
                    end
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
-- BLIZZARD CHILD DEBUG HELPERS
--
-- Blizzard child frames now stay in Blizzard's viewers. QUI icons consume
-- mirrored state by cooldownID, while debug tooling can still inspect the
-- original child frame and its native regions.
---------------------------------------------------------------------------
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

-- Lookup helper used by the icon factory to decide whether a mirror entry
-- has a live child for the cooldownID.
function CDMBlizzMirror.HasChildForCooldownID(cooldownID, viewerCategory)
    return cooldownID and GetInstanceChild(cooldownID, viewerCategory) ~= nil or false
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

local function SafeDebugScalar(value)
    if issecretvalue and issecretvalue(value) then
        return "<SECRET:" .. type(value) .. ">"
    end
    return value
end

function CDMBlizzMirror.GetChildDebugLines(cooldownID, viewerCategory)
    local lines = {}
    local child = cooldownID and GetInstanceChild(cooldownID, viewerCategory)
    local state = PackState(cooldownID, viewerCategory)
    AddDebugLine(lines,
        "state cdID=", cooldownID,
        "cat=", state and state.viewerCategory,
        "active=", state and tostring(state.isActive == true),
        "hasDurObj=", state and tostring(state.durObj ~= nil),
        "hasInst=", state and tostring(state.hasAuraInstanceID == true),
        "auraUnit=", state and state.auraUnit,
        "epoch=", state and state.mirrorEpoch,
        "spell=", state and state.spellID,
        "ov=", state and state.overrideSpellID,
        "tooltip=", state and state.overrideTooltipSpellID,
        "links=", state and FormatDebugIDList(state.linkedSpellIDs),
        "totemSlot=", state and state.totemSlot,
        "totemSpellID=", state and state.totemSpellID)

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

    local childAuraData = ReadChildAuraData(child)
    AddDebugLine(lines,
        "child auraInstanceID=", SafeDebugScalar(SafeFrameField(child, "auraInstanceID")),
        "auraDataUnit=", SafeDebugScalar(SafeFrameField(child, "auraDataUnit")),
        "auraUnit=", SafeDebugScalar(SafeFrameField(child, "auraUnit")),
        "auraData.inst=", SafeDebugScalar(childAuraData and childAuraData.auraInstanceID),
        "auraData.spellId=", SafeDebugScalar(childAuraData and childAuraData.spellId),
        "auraData.spellID=", SafeDebugScalar(childAuraData and childAuraData.spellID),
        "auraData.name=", SafeDebugScalar(childAuraData and childAuraData.name))

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

function CDMBlizzMirror.GetCooldownMethodTestPayload(cooldownID, viewerCategory)
    local child = cooldownID and GetInstanceChild(cooldownID, viewerCategory)
    local key = cooldownID and ResolveInstanceKey(cooldownID, viewerCategory)
    local s = key and _mirrorState[key]
    if not child or not s then return nil end

    local state = PackState(cooldownID, viewerCategory)
    local icon = child.Icon
    local cd = child.Cooldown
    local childStartMS, childDurationMS = SafeCall(cd, "GetCooldownTimes")
    return {
        cooldownID = cooldownID,
        child = child,
        childCooldown = cd,
        state = state,
        iconTexture = SafeCall(icon, "GetTexture"),
        auraProbeLines = BuildAuraProbeLines(cooldownID, state and state.viewerCategory),
        childCooldownShown = SafeCall(cd, "IsShown"),
        childCooldownStartMS = childStartMS,
        childCooldownDurationMS = childDurationMS,
        childCooldownDurationValue = SafeCall(cd, "GetCooldownDuration"),

        durObj = s.durObj,
        durObjSource = s.durObjSource,
        lastCooldownSetter = s.lastCooldownSetter,

        setDurationObjectArg = s.lastDurationObjectArg or s.durObj,
        setDurationObjectClearIfZero = s.lastDurationObjectClearIfZero,

        setCooldownStart = s.lastSetCooldownStart or child.cooldownStartTime,
        setCooldownDuration = s.lastSetCooldownDuration or child.cooldownDuration,
        setCooldownModRate = s.lastSetCooldownModRate,

        setCooldownDurationOnly = s.lastSetCooldownDurationOnly
            or s.lastSetCooldownDuration
            or child.cooldownDuration,
        setCooldownDurationModRate = s.lastSetCooldownDurationModRate
            or s.lastSetCooldownModRate,

        setCooldownExpirationTime = s.lastSetCooldownExpirationTime,
        setCooldownExpirationDuration = s.lastSetCooldownExpirationDuration
            or s.lastSetCooldownDuration
            or child.cooldownDuration,
        setCooldownExpirationModRate = s.lastSetCooldownExpirationModRate
            or s.lastSetCooldownModRate,
    }
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
-- Resolution: rebuild spell-name/spellID → cdID indexes over every
-- CooldownViewer identity Blizzard exposes. On each PLAYER_TOTEM_UPDATE,
-- look up each active totem by GetTotemInfo's spellID and name, then stamp
-- every matching cdID active with GetTotemDuration's DurationObject.
-- The DurationObject is secret-safe — it flows through SetCooldownFromDurationObject
-- without ever being read from Lua.
---------------------------------------------------------------------------
local function _AddCooldownIDToIndexBucket(map, key, cdID)
    if key == nil or not cdID then return false end
    local bucket = map[key]
    if not bucket then
        bucket = {}
        map[key] = bucket
    end
    bucket[cdID] = true
    return true
end

local function _IndexTotemSpellIDForCDID(cdID, sid)
    if type(sid) ~= "number" or sid <= 0 then return false end
    return _AddCooldownIDToIndexBucket(_totemSpellIDToCDID, sid, cdID)
end

local function _IndexTotemSpellNameForCDID(cdID, sid)
    if type(sid) ~= "number" then return nil end
    if not (Sources and Sources.QuerySpellName) then return nil end
    local name = Sources.QuerySpellName(sid)
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    return _AddCooldownIDToIndexBucket(_spellNameToCDID, name:lower(), cdID)
end

local function _IndexTotemIdentityForCDID(cdID, sid)
    local indexed = _IndexTotemSpellIDForCDID(cdID, sid)
    if _IndexTotemSpellNameForCDID(cdID, sid) then
        indexed = true
    end
    return indexed
end

function _IndexSpellNameForCDID(cdID, info)
    if not (cdID and info) then return end
    _IndexTotemIdentityForCDID(cdID, info.overrideTooltipSpellID)
    _IndexTotemIdentityForCDID(cdID, info.overrideSpellID)
    _IndexTotemIdentityForCDID(cdID, info.spellID)
    if type(info.linkedSpellIDs) == "table" then
        for _, linkedID in ipairs(info.linkedSpellIDs) do
            _IndexTotemIdentityForCDID(cdID, linkedID)
        end
    end
end

local function _RebuildSpellNameIndex()
    wipe(_spellNameToCDID)
    wipe(_totemSpellIDToCDID)
    for cdID, info in pairs(_cooldownInfoByID) do
        _IndexSpellNameForCDID(cdID, info)
    end
end

local function _AddCooldownIDsFromIndexBucket(out, bucket)
    if type(bucket) ~= "table" then return 0 end
    local added = 0
    for cdID in pairs(bucket) do
        if not out[cdID] then
            out[cdID] = true
            added = added + 1
        end
    end
    return added
end

local function CleanTotemSlotNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value < 1 then return nil end
    return math.floor(value)
end

local function GetTotemSlotScanLimit(updatedSlot)
    local maxSlots
    if type(GetNumTotemSlots) == "function" then
        local ok, slotCount = pcall(GetNumTotemSlots)
        if ok then
            maxSlots = CleanTotemSlotNumber(slotCount)
        end
    end

    if not maxSlots then
        -- Preserve the legacy extra-slot probe only when the dynamic
        -- slot-count API is unavailable.
        maxSlots = (CleanTotemSlotNumber(MAX_TOTEMS) or 4) + 1
    end

    local cleanUpdatedSlot = CleanTotemSlotNumber(updatedSlot)
    if cleanUpdatedSlot and cleanUpdatedSlot > maxSlots then
        maxSlots = cleanUpdatedSlot
    end
    return maxSlots
end

local function _ActivateTotemCooldownID(cdID, slot, durObj, totemName, totemIcon, totemSpellID)
    if not cdID then return false end
    local cleanSlot = CleanTotemSlotNumber(slot)
    _totemActiveCDID[cdID] = cleanSlot or true
    local s = EnsureState(cdID, _childByCooldownID[cdID])
    if not s then return false end
    s.isActive     = true
    s.mirrorEpoch  = (s.mirrorEpoch or 0) + 1
    s.lastTouch    = GetTime()
    s.totemSlot    = cleanSlot
    s.totemName    = totemName
    s.totemIcon    = totemIcon
    s.totemSpellID = totemSpellID
    if durObj then
        SetDurationLane(cdID, s, "totem", durObj, "totem-duration")
    end
    RequestMirrorTextRefreshForState(cdID, s, "totem-active")
    return true
end

function HandlePlayerTotemUpdate(updatedSlot)
    if type(GetTotemInfo) ~= "function" then
        if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
            CDMBlizzMirror.TaintLog("totem.update.no-api")
        end
        return
    end

    -- Lazy-rebuild if Walk hasn't populated the index yet (e.g. PLAYER_LOGIN
    -- arrives before any catalog walk has completed).
    if next(_spellNameToCDID) == nil
        and next(_totemSpellIDToCDID) == nil
        and next(_cooldownInfoByID) ~= nil then
        _RebuildSpellNameIndex()
    end

    local maxSlots = GetTotemSlotScanLimit(updatedSlot)

    if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
        local nameIndexCount = 0
        for _ in pairs(_spellNameToCDID) do nameIndexCount = nameIndexCount + 1 end
        local spellIDIndexCount = 0
        for _ in pairs(_totemSpellIDToCDID) do spellIDIndexCount = spellIDIndexCount + 1 end
        CDMBlizzMirror.TaintLog("totem.update.enter",
            "nameIndexEntries", nameIndexCount,
            "spellIDIndexEntries", spellIDIndexCount,
            "slotCount", maxSlots)
    end

    local seen = {}
    for slot = 1, maxSlots do
        local tok = true; local hasTotem, totemName, _, _, totemIcon, _, totemSpellID = GetTotemInfo(slot)
        local nameSecret = issecretvalue and issecretvalue(totemName) or false
        local hasTotemSecret = issecretvalue and issecretvalue(hasTotem) or false
        local iconSecret = issecretvalue and issecretvalue(totemIcon) or false
        local spellIDSecret = issecretvalue and issecretvalue(totemSpellID) or false
        if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
            local nameRender = nameSecret and "<SECRET>" or tostring(totemName)
            local iconRender = iconSecret and "<SECRET>" or totemIcon
            local spellIDRender = spellIDSecret and "<SECRET>" or totemSpellID
            CDMBlizzMirror.TaintLog("totem.scan",
                "slot", slot,
                "ok", tok,
                "hasTotem", hasTotemSecret and "<SECRET>" or hasTotem,
                "nameSecret", nameSecret,
                "name", nameRender,
                "icon", iconRender,
                "spellID", spellIDRender)
        end
        -- A non-empty totemName already implies an active totem, so we don't
        -- strictly need to test hasTotem when it's secret. Short-circuit via
        -- hasTotemSecret so Lua never evaluates the bool of a secret value.
        if tok and (hasTotemSecret or hasTotem) then
            local key
            local cleanTotemName
            if not nameSecret and type(totemName) == "string" and totemName ~= "" then
                key = totemName:lower()
                cleanTotemName = totemName
            end
            local cleanTotemSpellID
            if not spellIDSecret and type(totemSpellID) == "number" and totemSpellID > 0 then
                cleanTotemSpellID = totemSpellID
            end
            local cleanTotemIcon = nil
            if not iconSecret then
                cleanTotemIcon = totemIcon
            end

            local matches = {}
            local matchCount = 0
            if cleanTotemSpellID then
                matchCount = matchCount + _AddCooldownIDsFromIndexBucket(matches, _totemSpellIDToCDID[cleanTotemSpellID])
            end
            if key then
                matchCount = matchCount + _AddCooldownIDsFromIndexBucket(matches, _spellNameToCDID[key])
            end
            if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                CDMBlizzMirror.TaintLog("totem.match",
                    "slot", slot,
                    "key", key,
                    "spellID", cleanTotemSpellID,
                    "matches", matchCount)
            end

            local durObj
            if matchCount > 0 and type(GetTotemDuration) == "function" then
                local rawDurObj = GetTotemDuration(slot)
                -- GetTotemDuration returns a DurationObject in modern API;
                -- numeric returns mean the slot is inactive or the API hasn't
                -- been adopted for that totem. Only stamp objects.
                if rawDurObj and type(rawDurObj) ~= "number" then
                    durObj = rawDurObj
                end
            end

            for cdID in pairs(matches) do
                seen[cdID] = true
                _ActivateTotemCooldownID(cdID, slot, durObj, cleanTotemName, cleanTotemIcon, cleanTotemSpellID)
                if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                    CDMBlizzMirror.TaintLog("totem.activate",
                        "slot", slot,
                        "cdID", cdID,
                        "durObj", durObj)
                end
            end
        end
    end

    for _, child in pairs(_childByInstanceKey) do
        local cdID = child and child.cooldownID
        if cdID and not seen[cdID] and type(GetTotemDuration) == "function" then
            local slot = RawFrameField(child, "preferredTotemUpdateSlot")
            if type(slot) == "nil" then
                local totemData = RawFrameField(child, "totemData")
                local totemDataSecret = Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(totemData)
                local totemDataReadable = not totemDataSecret
                    and type(totemData) == "table"
                    and (not (Helpers and Helpers.CanAccessTable) or Helpers.CanAccessTable(totemData))
                if totemDataReadable then
                    slot = totemData.slot
                end
            end

            if type(slot) ~= "nil" then
                local rawDurObj = GetTotemDuration(slot)
                if rawDurObj and type(rawDurObj) ~= "number" then
                    seen[cdID] = true
                    _ActivateTotemCooldownID(cdID, nil, rawDurObj)
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
            local key = ResolveInstanceKey(cdID)
            local s = key and _mirrorState[key]
            if s then
                s.isActive    = false
                ClearAllDurationLanes(cdID, s)
                s.totemSlot   = nil
                s.totemName   = nil
                s.totemIcon   = nil
                s.totemSpellID = nil
                s.mirrorEpoch = (s.mirrorEpoch or 0) + 1
                s.lastTouch   = GetTime()
                RequestMirrorTextRefreshForState(cdID, s, "totem-inactive")
            end
            if _G.QUI_CDM_TAINT_DEBUG and CDMBlizzMirror.TaintLog then
                CDMBlizzMirror.TaintLog("totem.deactivate", "cdID", cdID)
            end
        end
    end

end

CDMBlizzMirror.HandlePlayerTotemUpdate = HandlePlayerTotemUpdate

function CDMBlizzMirror.HandlePlayerTargetChanged()
    -- Proactively invalidate every mirror state stamped from the prior
    -- target. Without this, target-side stamps (e.g. VP / DP debuffs)
    -- linger after the user drops their target.
    --
    -- Keying off s.auraUnit (not info.selfAura) is correct: it records
    -- the unit that actually held the aura at stamp time, regardless
    -- of how Blizzard's misleading selfAura flag classifies the cdID.
    --
    -- ClearMirrorAuraState wipes ONLY the aura lane; the cooldown / gcd
    -- / totem / resource lanes survive a target swap (target change
    -- doesn't end a cooldown the player is still on).
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
    RefreshAuraViewerChildActiveStates()
    RefreshCooldownViewerRelatedAuraStates()
end

function CDMBlizzMirror.HandleUnitAuraChanged(unit, updateInfo)
    -- Catch CooldownViewer children created post-Walk: pet summon, talent
    -- activation, dynamic class spec swaps, etc. all can introduce cdIDs
    -- Blizzard had not surfaced when our last Walk ran.
    BindNewChildren()

    -- Event-driven visibility: Blizzard updates the exact child field for
    -- aura-viewer cIDs, even for hasAura=false entries that never expose a
    -- normal auraInstanceID path. Read every aura child on UNIT_AURA instead
    -- of polling from PackState.
    RefreshAuraViewerChildActiveStates()
    RefreshCooldownViewerRelatedAuraStates()

    if not unit then
        CaptureAurasFromUnit("player")
        CaptureAurasFromUnit("pet")
        CaptureAurasFromUnit("target")
        return
    end
    if unit ~= "player" and unit ~= "pet" and unit ~= "target" then return end

    -- UNIT_AURA's payload is the combat-safe identity handoff. Capture it
    -- first, then fall back to a live scan only for full/empty updates or
    -- when the payload did not include an aura we can map to a cdID.
    local stampedFromPayload = CaptureAurasFromUnitAuraPayload(unit, updateInfo)
    if not stampedFromPayload or not updateInfo or updateInfo.isFullUpdate then
        CaptureAurasFromUnit(unit)
    end
    if not updateInfo
        or updateInfo.isFullUpdate
        or (updateInfo.removedAuraInstanceIDs
            and #updateInfo.removedAuraInstanceIDs > 0) then
        EvictRemovedMirrorStatesForUnit(unit)
    end
end

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
-- Proc-style buff icons can update through the spell activation overlay path
-- without a normal UNIT_AURA payload or cooldown setter. Re-read child
-- isActive for those durationless aura-viewer entries.
_eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
_eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
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
    RegisterCooldownInstance(cdID, hostCatName, GetInstanceChild(cdID, hostCatName), clean)
    local catMap = _cdIDByCatSpell[hostCatName]
    RemoveCooldownIDFromMaps(cdID, hostCatName)
    MapCooldownInfoIDs(catMap, clean, cdID)
    -- The spell name for this cdID may have changed (override swap rewires
    -- the underlying spell). Rebuild the name index so PLAYER_TOTEM_UPDATE
    -- looks up the new name. Cheap O(n) over _cooldownInfoByID.
    _RebuildSpellNameIndex()
end

_eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
        or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        BindNewChildren()
        RefreshAuraViewerChildActiveStates()
        RefreshCooldownViewerRelatedAuraStates()
        if not RequestMirrorTextRefreshForMappedSpells("overlay", arg1) then
            RequestMirrorTextRefresh(nil, nil, "overlay")
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        CDMBlizzMirror.HandlePlayerTargetChanged()
        return
    end

    if event == "PLAYER_TOTEM_UPDATE" then
        HandlePlayerTotemUpdate(arg1)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if _walkPendingOnRegen then
            _walkPendingOnRegen = false
            Walk()
        end
        CDMBlizzMirror.SyncSuppressionToMaster()
        return
    end

    -- PLAYER_LOGIN / PLAYER_ENTERING_WORLD / PLAYER_SPECIALIZATION_CHANGED /
    -- TRAIT_TREE_CHANGED reshape the catalog (spec change moves spells
    -- in/out of viewers; talent change rewires linkedSpellIDs). The
    -- CDM-table events (DATA_LOADED / SPELL_OVERRIDE_UPDATED /
    -- TABLE_HOTFIXED) are handled via the ns.CDMIndex broker subscription
    -- at the bottom of this file.
    if InCombatLockdown() and not (ns and ns._inInitSafeWindow) then
        _walkPendingOnRegen = true
        return
    end

    Walk()
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
        if InCombatLockdown() and not (ns and ns._inInitSafeWindow) then
            _walkPendingOnRegen = true
            return
        end
        if reason == "override" then
            -- Targeted: only the (baseSpellID, overrideSpellID) pair changed.
            RefreshSpellOverridePair(baseSpellID, overrideSpellID)
        else
            -- data_loaded / hotfix / refresh_layout: full catalog rebuild
            -- and bootstrap of totem state, matching the previous
            -- COOLDOWN_VIEWER_DATA_LOADED / TABLE_HOTFIXED handler exactly.
            Walk()
            HandlePlayerTotemUpdate()
            CDMBlizzMirror.SyncSuppressionToMaster()
        end
    end, 10)
end
