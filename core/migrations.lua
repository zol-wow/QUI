---------------------------------------------------------------------------
-- QUI Profile Migrations
-- Shared normalization pipeline for legacy SavedVariables and profile imports.
--
-- This is the single entry point for ALL profile-level migrations.
-- Call Migrations.Run(db) from any context that activates a profile:
--   - Addon startup (init.lua OnEnable via BackwardsCompat)
--   - Module startup (main.lua QUICore:OnInitialize)
--   - Profile switch (main.lua QUICore:OnProfileChanged)
--   - Profile import (profile_io.lua via BackwardsCompat)
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Migrations = ns.Migrations or {}
ns.Migrations = Migrations
-- Also expose on the QUI global so init.lua (which has no `ns` scope) can
-- reach the snapshot/restore helpers for the `/qui migration` slash command.
if _G.QUI then _G.QUI.Migrations = Migrations end

-- Module-level upvalues set by Migrations.Run before iterating profiles and
-- cleared on exit. Declared here (file scope) so migration functions defined
-- anywhere in the file can reference them without forward-declaration issues.
local _currentGlobalDB     = nil  -- db.global; for cross-profile reads (v32+)
local _currentActiveProfile = nil  -- raw sv profile table for the active profile (v43+)

---------------------------------------------------------------------------
-- Schema version history
---------------------------------------------------------------------------
-- v0–v31 = pre-4.0 history (3.x and 2.55 data model). These step-by-step
--       migrations were REMOVED in 4.0. v31 is the migration floor
--       (MIN_SUPPORTED_SCHEMA): profiles stored below it are backed up, wiped,
--       and reseeded rather than upgraded incrementally. The migration chain
--       in RunOnProfile therefore starts at v32; nothing below runs here.
--
-- v32 = OptionsV2BranchConsolidated (the V2 settings branch's data work)
--       Nine discrete transforms collapsed into one schema bump because the
--       V2 branch never shipped past v31 — there's no point preserving the
--       intermediate step granularity. Helper functions stay separate for
--       readability; they're called sequentially behind a single
--       `if stored < 32` gate. Order matters: container/spec finalization
--       (a-d) must precede shape stamping (e), and the field-level repair
--       passes (f-i) run after to reach the already-shaped containers and
--       resource-bar tables.
--         (a) MigrateCustomTrackersToContainers — mirror legacy
--             db.customTrackers.bars[] into db.ncdm.containers[customBar_*]
--             so the unified V2 renderer can serve them. Non-destructive.
--         (b) RemovePartyTrackerData — strip orphan partyTracker subtree
--             (feature removed before 12.0.5).
--         (c) FinalizeCustomBarContainers — synthesize row1 config from
--             flat iconSize/spacing/etc., port per-spec entries from the
--             legacy db.global.specTrackerSpells[legacyID] location into
--             db.global.ncdm.specTrackerSpells[containerKey] when present.
--         (d) FinalizeLegacyTrackerSpecState — promote legacy
--             specSpecificSpells -> V2 specSpecific, stamp
--             container._sourceSpecID from ncdm._lastSpecID, then promote
--             container.entries into per-spec storage at
--             db.global.ncdm.specTrackerSpells[key][canonicalSpec] and
--             clear. Each promoted entry is stamped with _sourceSpecID,
--             _legacySourceSpecKey, and _legacySpellbookSlot so the
--             composer can attribute it ("Source: <Spec>", "Legacy data —
--             may need review") and unresolvable IDs render as the
--             standard ? fallback. Real spell IDs and pre-V2 drag-handler
--             garbage both promote unconditionally — the user gets full
--             visibility into what was imported instead of a silently
--             empty bar.
--         (e) MigrateContainerShapeAndEntryKind — collapses the 4-value
--             containerType taxonomy {aura, auraBar, cooldown, customBar}
--             into two orthogonal axes: container.shape ∈ {icon, bar} for
--             layout/render, and entry.kind ∈ {aura, cooldown} for
--             behavior. trackedBar/auraBar → shape=bar; everything else →
--             shape=icon. Spell entries on previously-aura containers get
--             kind=aura stamped; non-spell entries (item/trinket/slot/
--             macro) get kind=cooldown stamped; ambiguous spell entries
--             are left for the runtime classifier. Must run after
--             (a)/(c)/(d) so the customBar-style containers and per-spec
--             entry storage already exist in their final shape.
--         (f) RepairCustomTrackerCDMBarFidelity — re-sync legacy custom
--             tracker bars into their migrated Custom CDM Bars to recover
--             row/text fields and frameAnchoring customTracker:<id> →
--             cdmCustom_customBar_<id> resolver keys that the (a) pass
--             missed.
--         (g) Migrations.RepairCustomTrackerSpecStorage — canonicalize
--             spec-specific custom tracker buckets from numeric spec keys
--             ("250") to CLASS-specID keys ("DEATHKNIGHT-250") read by the
--             unified CDM runtime, preserve source-key metadata, and
--             promote any container.entries that leaked back onto a
--             spec-specific bar through the same per-spec storage path
--             as (d) before clearing them.
--         (h) RepairResourceBarSettings — copy primary/secondary power-bar
--             values from legacy ncdm storage into the active top-level
--             powerBar / secondaryPowerBar tables when the runtime keys
--             are still defaults.
--         (i) NormalizeCustomCDMBarCompatibility — stamp legacy tooltip/
--             keybind contexts, restore old custom-tracker default
--             behavior for dynamic layout, normalize mutually-exclusive
--             visibility flags, and backfill active-glow/text fields that
--             the initial customBar mirror left implicit.
-- v33 = RemapThirdPartyAnchorAliases
--       (3.6 alpha: third-party integrations (BigWigs, DandersFrames,
--        AbilityTimeline) now route their "Anchor To" dropdown through the
--        same registry-driven categorized + searchable widget the rest of
--        QUI's movers use. The integrations historically stored four legacy
--        alias values that aren't in the canonical anchor-target registry:
--        essential, utility, primary, secondary. Rewrite them to the
--        canonical registry keys (cdmEssential, cdmUtility, primaryPower,
--        secondaryPower) so the new dropdown can render and round-trip the
--        saved value. The legacy alias arms in each integration's
--        GetAnchorFrame still resolve unmigrated values as a safety net.)
-- v34 = MigrateUnitFrameAuraFilters
--       (3.6.0+: replaces per-unit auras.onlyMyDebuffs checkbox with the
--        structured debuffFilter.modifiers.PLAYER flag. Translates true →
--        modifier set, false/absent → modifier unset, then strips the old
--        key. Buff/debuff filter table shells themselves are stamped
--        lazily by EnsureAuraSettings; this migration only handles the
--        old toggle's behavior preservation.)
-- v35 = Phase C edit-box history schema initialization
--       (3.6.0+: marks the introduction of persistent per-character
--        Up/Down arrow recall at db.char.chat.editboxHistory. The prior
--        session-only history was in-memory and not persisted, so there
--        is nothing on the profile to migrate from — this entry is a
--        no-op stamp on the profile. Per-character storage is reached
--        through QUI.db.char (not the profile), and gets initialized
--        lazily by editbox_history.lua's getStore().)
-- v36 = SplitPandemicByAuraType
--       (3.6.0+: split each customGlow.<viewer>PandemicEnabled toggle into
--        two aura-type-aware toggles: <viewer>PandemicDebuffEnabled (DoTs
--        / harmful auras) and <viewer>PandemicBuffEnabled (HoTs / helpful
--        auras). Existing single-toggle profiles get the value copied into
--        both new keys to preserve current "show pandemic glow on every
--        active aura" behavior; the old key is then nilled. Covers built-in
--        viewers (essential / utility / buff) and custom containers via
--        any *PandemicEnabled key under customGlow.)
-- v37 = RetireSkinDamageMeter
--       (3.7: skinner module deleted in favor of native QUI damage meter.
--        This migration deletes the skinner's saved keys so they can't
--        actively fight the native module's CVar suppression on future
--        loads. Native module keys at damageMeter.native.* are preserved.)
-- v38 = DropDamageMeterMaxVisibleRows
--       (3.7+: the damage meter row-cap setting was removed in favor of
--        scrollable rows. The window height alone decides what renders
--        without scrolling; everything below the fold is reachable via
--        mouse-wheel scroll. This migration drops the dead key from every
--        saved window entry so it doesn't sit in savedvars forever.)
-- v39 = MigrateBorderColorSource
--       (3.6.0+: replaces skinBorderUseClassColor + frozen skinBorderColor and the
--        tooltip borderUseClassColor/borderUseAccentColor toggles with an explicit
--        skinBorderColorSource / borderColorSource enum: "theme" | "class" |
--        "custom". Auto-heals accent-snapshot freeze-bug colors back to "theme"
--        via a preset-RGB fingerprint; preserves genuine custom colors.)
-- v40 = MigrateBorderColoring
--       (options-v2: registry-driven roll-out of the per-module border color
--        SOURCE enum to the remaining in-scope modules. Iterates
--        Helpers.BorderRegistry; for each module's DB table (or each instance
--        of a `multi` module) it renames the legacy color key, folds crosshair
--        borderR/G/B/A scalars into a color table, and derives the new
--        {prefix}BorderColorSource from the module's old useClass / accent
--        booleans — preserving the current look (class/theme), defaulting to
--        "custom" otherwise. Existing profiles migrate ONCE to "custom"/"class"/
--        "theme"; fresh installs are stamped at the current version on first
--        save and never run this gate, so they keep the new "inherit" default.
--        Per-table idempotent: a table that already carries the source key is
--        skipped. The registry is empty until later tasks register modules, so
--        on a current build this gate is a no-op stamp — its behavior is
--        exercised by the unit test with synthetic registry entries.)
--
-- v41 = PurgeOrphanedChatKeys
--       (chat takeover: the QUI display replaced the skinned-Blizzard-frame
--        path outright — chat.enabled IS the takeover. TRANSLATES the old
--        opt-in first: only displayMode == "custom" keeps the module
--        enabled; "blizzard"/absent (the released default) sets
--        chat.enabled = false so nobody is silently switched into the
--        takeover. Then purges the profile
--        keys nothing reads anymore: displayMode (the old blizzard/custom
--        switch), hideButtons, the chatTab border-color pair, the
--        ChatFrame1 frameSize/framePosition persistence that belonged to
--        the deleted sizing helper, copyHistorySource + scrollbackLines
--        (the copy window reads the QUI display's store now), and
--        hyperlinks.interactiveNames (its producer was the deleted
--        player-link wrapper). Pure deletion; no value translation.)
--
-- v42 = MigrateCustomDisplayWindows
--       (multi-window chat: flat single-window keys width/height/position/
--        tabs on customDisplay wrap into customDisplay.windows[1]. Geometry
--        keys may be absent (AceDB strips defaults); only wraps when
--        something flat is actually stored — a fully-default profile stays
--        empty and the runtime seeder builds windows[1] from defaults.
--        Idempotent: a profile already carrying windows[] only sheds any
--        leftover flat keys.)
--
-- v43 = RetireModuleMasterFlags (suite-split follow-up)
--       The Module Addons rows (addon enable state, account-wide via
--       C_AddOns.EnableAddOn/DisableAddOn) are now the only module-level
--       switch. Five legacy per-profile master flags are forced true so a
--       stale false can never silently disable a module whose addon row
--       says on. When the ACTIVE profile carried an explicit false, that
--       intent is first reflected account-wide into the addon disable state
--       before the flag is forced. chat.enabled and quiGroupFrames.enabled
--       are deliberately NOT touched (dormant guards: stock-chat users and
--       group-frames opt-in default).
--
-- v44 = MigrateChatRealmNames
--       Sender realm display (Anya vs Anya-Stormrage) used to be a side effect
--       of chat.modifiers.channelShorten. It now has its own setting,
--       chat.modifiers.showRealmNames (default false). Realm was shown iff
--       channel-shortening was EXPLICITLY off, so the migration only sets
--       showRealmNames = true for those profiles; the false default reproduces
--       the stripped look everywhere else. Idempotent.
--
-- v45 = MigrateChatWindowPositionsToFrameAnchoring
--       Chat window position becomes frameAnchoring-only (damage-meter
--       pattern). The legacy chat.customDisplay.windows[i].position
--       sub-table is folded into frameAnchoring.chatFrame1/chatWindow<i>
--       (it wins over free/stale FA entries — it's what the display layer
--       re-asserted on every refresh, i.e. what the user saw; real frame
--       anchors are kept) and then deleted. Ends the dual-store drift that
--       made the chat frame snap between two saved positions.
--
-- v46 = MigrateUnifiedAuras  (collapse auras strips + pinnedAuras + auraIndicators → auras.elements)
--       Per group-frame context (party/raid), fold the three legacy aura DB
--       tables (flat buff/debuff filter strips in `auras`, the `pinnedAuras`
--       spec-slot model, and the `auraIndicators` per-spell indicator model)
--       into the single `auras.elements` element list keyed by "*" (all specs)
--       plus per-spec IDs. The old `auras`/`pinnedAuras`/`auraIndicators` are
--       stashed under `auras._migratedFrom` for one release (rollback) and the
--       legacy `pinnedAuras`/`auraIndicators` keys are removed. Idempotent: a
--       second pass finds `auras.elements` already present and no-ops.
--
-- When adding a new migration: bump CURRENT_SCHEMA_VERSION, add it to the
-- linear gate chain in RunOnProfile, and document the version above.
---------------------------------------------------------------------------
local CURRENT_SCHEMA_VERSION = 47

-- The oldest schema we still migrate incrementally. 3.5.11 (the last major
-- release before 4.0) shipped schema v31, and migrations v2–v31 were removed
-- in 4.0. A profile stored below this floor is too old to upgrade step-by-step;
-- RunOnProfile backs it up, wipes it, and flags it for a starter-profile
-- reseed at login (see profile._needsStarterReseed). Fresh profiles (stored==0)
-- are NOT floored — they take the normal fresh-init path.
local MIN_SUPPORTED_SCHEMA = 31

-- Exposed so the profile-import path can reject pre-3.5.11 exports before they
-- reach RunOnProfile (where they would otherwise trip the floor and wipe the
-- active profile they import into).
Migrations.MIN_SUPPORTED_SCHEMA = MIN_SUPPORTED_SCHEMA

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------

local function CloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nestedValue in pairs(value) do
        copy[key] = CloneValue(nestedValue)
    end
    return copy
end

local function ValuesEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not ValuesEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local SPEC_ID_CLASS_TOKEN = {
    [62] = "MAGE", [63] = "MAGE", [64] = "MAGE",
    [65] = "PALADIN", [66] = "PALADIN", [70] = "PALADIN",
    [71] = "WARRIOR", [72] = "WARRIOR", [73] = "WARRIOR",
    [102] = "DRUID", [103] = "DRUID", [104] = "DRUID", [105] = "DRUID",
    [250] = "DEATHKNIGHT", [251] = "DEATHKNIGHT", [252] = "DEATHKNIGHT",
    [253] = "HUNTER", [254] = "HUNTER", [255] = "HUNTER",
    [256] = "PRIEST", [257] = "PRIEST", [258] = "PRIEST",
    [259] = "ROGUE", [260] = "ROGUE", [261] = "ROGUE",
    [262] = "SHAMAN", [263] = "SHAMAN", [264] = "SHAMAN",
    [265] = "WARLOCK", [266] = "WARLOCK", [267] = "WARLOCK",
    [268] = "MONK", [269] = "MONK", [270] = "MONK",
    [577] = "DEMONHUNTER", [581] = "DEMONHUNTER",
    [1467] = "EVOKER", [1468] = "EVOKER", [1473] = "EVOKER",
}

local function ParseSpecKey(value)
    if type(value) == "number" then
        return value, nil
    end
    if type(value) ~= "string" then
        return nil, nil
    end

    local classToken, specText = value:match("^([A-Z]+)%-(%d+)$")
    if specText then
        return tonumber(specText), classToken
    end
    local numeric = tonumber(value)
    if numeric then
        return numeric, nil
    end
    return nil, nil
end

local function GetClassTokenForSpecID(specID)
    if type(specID) ~= "number" then return nil end
    if GetSpecializationInfoByID then
        local result = { pcall(GetSpecializationInfoByID, specID) }
        local classToken = result[7]
        if result[1] and type(classToken) == "string" and classToken ~= "" then
            return classToken
        end
    end
    return SPEC_ID_CLASS_TOKEN[specID]
end

local function GetCanonicalSpecKey(value)
    local specID, classToken = ParseSpecKey(value)
    if not specID then
        return value, nil
    end
    classToken = classToken or GetClassTokenForSpecID(specID)
    if classToken then
        return classToken .. "-" .. tostring(specID), specID
    end
    return tostring(specID), specID
end

local function GetLiveSpecID()
    if not GetSpecialization or not GetSpecializationInfo then return nil end
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return type(specID) == "number" and specID or nil
end

local function GetProfileSourceSpecID(profile)
    local fromProfile = profile and profile.ncdm and profile.ncdm._lastSpecID
    if type(fromProfile) == "number" and fromProfile > 0 then
        return fromProfile
    end
    return GetLiveSpecID()
end

local function RecordSpecKeyAlias(container, fromKey, toKey)
    if type(container) ~= "table" or fromKey == nil or toKey == nil or fromKey == toKey then return end
    if type(container._legacySpecKeyAliases) ~= "table" then
        container._legacySpecKeyAliases = {}
    end
    container._legacySpecKeyAliases[tostring(fromKey)] = tostring(toKey)
end

local function StampLegacySpecEntry(entry, sourceSpecID, sourceSpecKey, opts)
    if type(entry) ~= "table" then return entry end
    if type(sourceSpecID) == "number" and sourceSpecID > 0 and entry._sourceSpecID == nil then
        entry._sourceSpecID = sourceSpecID
    end
    if sourceSpecKey ~= nil and entry._legacySourceSpecKey == nil then
        entry._legacySourceSpecKey = tostring(sourceSpecKey)
    end
    if opts and opts.legacySpellbookSlot
       and entry.type == "spell"
       and type(entry.id) == "number"
       and entry._legacySpellbookSlot == nil
    then
        entry._legacySpellbookSlot = entry.id
    end
    return entry
end

local function EntriesEquivalent(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.type == b.type
       and a.id == b.id
       and a.macroName == b.macroName
       and a.customName == b.customName
end

local function DeduplicateEntryList(entries)
    if type(entries) ~= "table" then return false end
    local seen = {}
    local kept = {}
    local changed = false
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local key = tostring(entry.type or "") .. "\031"
                .. tostring(entry.id or "") .. "\031"
                .. tostring(entry.macroName or "") .. "\031"
                .. tostring(entry.customName or "")
            if not seen[key] then
                seen[key] = true
                kept[#kept + 1] = entry
            else
                changed = true
            end
        else
            kept[#kept + 1] = entry
        end
    end
    if changed then
        for i = 1, math.max(#entries, #kept) do
            entries[i] = kept[i]
        end
    end
    return changed
end

local function MergeSpecEntryLists(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    local changed = false
    for _, entry in ipairs(src) do
        local exists = false
        for _, existing in ipairs(dst) do
            if EntriesEquivalent(existing, entry) then
                exists = true
                break
            end
        end
        if not exists then
            dst[#dst + 1] = entry
            changed = true
        end
    end
    if DeduplicateEntryList(dst) then
        changed = true
    end
    return changed
end

-- Forward declaration: defined further down (depends on _currentGlobalDB
-- and other v32-era helpers), but called from Migrations.RepairCustomTrackerSpecStorage
-- which is defined earlier in source order.
local PromoteLegacyContainerEntriesToPerSpec



---------------------------------------------------------------------------
-- 1. Data format migrations (restructure raw data first)
---------------------------------------------------------------------------















---------------------------------------------------------------------------
-- v34: MigrateUnitFrameAuraFilters
--   Replaces the per-unit auras.onlyMyDebuffs checkbox with the new
--   structured debuffFilter.modifiers.PLAYER flag. Idempotent — safe to
--   re-run because once onlyMyDebuffs is gone there's nothing to migrate.
---------------------------------------------------------------------------
local function MigrateUnitFrameAuraFilters(profile)
    local ufdb = profile and profile.quiUnitFrames
    if type(ufdb) ~= "table" then return end

    for _, unitTbl in pairs(ufdb) do
        local auraDB = type(unitTbl) == "table" and unitTbl.auras
        if type(auraDB) == "table" then
            if auraDB.onlyMyDebuffs == true then
                if type(auraDB.debuffFilter) ~= "table" then
                    auraDB.debuffFilter = {}
                end
                if type(auraDB.debuffFilter.modifiers) ~= "table" then
                    auraDB.debuffFilter.modifiers = {}
                end
                auraDB.debuffFilter.modifiers.PLAYER = true
            end
            auraDB.onlyMyDebuffs = nil
        end
    end
end

-- v47: the "IMPORTANT" AuraFilters flag was removed by Blizzard in 12.0.7.
-- Scrub it from stored unit-frame filter state. The exclusive picker stores the
-- raw flag string and the render path appends it straight into the filter passed
-- to C_UnitAuras.GetAuraDataByIndex (unguarded), so a stale "IMPORTANT" would
-- feed a now-invalid token to a live API call. The per-classification booleans
-- are no longer read (the code-side map dropped the key), so they are only
-- deleted here for cleanliness.
local function ScrubRemovedImportantAuraFilter(profile)
    local ufdb = profile and profile.quiUnitFrames
    if type(ufdb) ~= "table" then return end

    for _, unitTbl in pairs(ufdb) do
        local auraDB = type(unitTbl) == "table" and unitTbl.auras
        if type(auraDB) == "table" then
            for _, key in ipairs({ "buffFilter", "debuffFilter" }) do
                local filterDB = auraDB[key]
                if type(filterDB) == "table" and filterDB.exclusive == "IMPORTANT" then
                    filterDB.exclusive = nil
                end
            end
            if type(auraDB.buffClassifications) == "table" then
                auraDB.buffClassifications.important = nil
            end
            if type(auraDB.debuffClassifications) == "table" then
                auraDB.debuffClassifications.important = nil
            end
        end
    end
end

-- v36: Split each customGlow.<viewer>PandemicEnabled toggle into two
-- aura-type-aware toggles: <viewer>PandemicDebuffEnabled (DoTs / harmful)
-- and <viewer>PandemicBuffEnabled (HoTs / helpful). Existing single-toggle
-- profiles get the value copied into both new keys to preserve current
-- "show pandemic glow on every active aura" behavior.
local function SplitPandemicByAuraType(profile)
    local glowDB = profile and profile.customGlow
    if type(glowDB) ~= "table" then return end

    -- Snapshot keys before mutating so we don't touch keys mid-iteration.
    local oldKeys = {}
    for k, v in pairs(glowDB) do
        if type(k) == "string" and type(v) == "boolean" then
            local prefix = k:match("^(.+)PandemicEnabled$")
            if prefix and prefix ~= "" then
                oldKeys[#oldKeys + 1] = { key = k, prefix = prefix, value = v }
            end
        end
    end

    for _, entry in ipairs(oldKeys) do
        local debuffKey = entry.prefix .. "PandemicDebuffEnabled"
        local buffKey   = entry.prefix .. "PandemicBuffEnabled"
        if glowDB[debuffKey] == nil then glowDB[debuffKey] = entry.value end
        if glowDB[buffKey]   == nil then glowDB[buffKey]   = entry.value end
        glowDB[entry.key] = nil
    end
end

---------------------------------------------------------------------------
-- RetireSkinDamageMeter
-- v37: The damage meter skinner (modules/skinning/gameplay/damage_meter.lua)
-- was deleted in commit a4ec6f24 in favor of the native QUI damage meter at
-- modules/damage_meter/. The skinner's saved keys are defunct AND actively
-- harmful: the skinner's `enabled` key was being pushed back to the
-- damageMeterEnabled CVar on every login, re-showing Blizzard's stock meter
-- despite the native module's CVar suppression. This migration deletes the
-- skinner's saved keys so they can't fight the native module on future loads.
--
-- The native module's keys live under `damageMeter.native.*` and are
-- preserved unchanged. Future cleanup may flatten `native.*` back to the
-- top-level damageMeter table; this migration intentionally does NOT do
-- that yet.
---------------------------------------------------------------------------
local function RetireSkinDamageMeter(profile)
    if not profile then return end

    -- Master toggle under general.
    if type(profile.general) == "table" then
        profile.general.skinDamageMeter = nil
    end

    -- Skinner-owned keys at top level of damageMeter. The native module's
    -- damageMeter.native.* subtree must be preserved.
    local dm = profile.damageMeter
    if type(dm) == "table" then
        dm.enabled         = nil
        dm.visibility      = nil
        dm.style           = nil
        dm.numberDisplay   = nil
        dm.useClassColor   = nil
        dm.showBarIcons    = nil
        dm.barHeight       = nil
        dm.barSpacing      = nil
        dm.textSize        = nil
        dm.windowAlpha     = nil
        dm.backgroundAlpha = nil
        dm._initialized    = nil
        dm.appearance      = nil   -- top-level skinner appearance; native uses dm.native.appearance
    end
end

---------------------------------------------------------------------------
-- DropDamageMeterMaxVisibleRows
-- v38: maxVisibleRows is no longer consulted by the damage meter (rows are
-- now scrollable, and the window's height alone decides what's visible
-- without scrolling). Drop the dead key from every saved window entry to
-- keep savedvars tidy.
---------------------------------------------------------------------------
local function DropDamageMeterMaxVisibleRows(profile)
    if type(profile) ~= "table" then return end
    local native = profile.damageMeter and profile.damageMeter.native
    if type(native) ~= "table" then return end
    if type(native.windows) ~= "table" then return end
    for _, windowState in pairs(native.windows) do
        if type(windowState) == "table" then
            windowState.maxVisibleRows = nil
        end
    end
end




---------------------------------------------------------------------------
-- 2. Legacy profile detection & normalization
---------------------------------------------------------------------------


local function IsPlaceholderAnchorEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    local parent = entry.parent
    local point = entry.point
    local relative = entry.relative
    local offsetX = tonumber(entry.offsetX) or 0
    local offsetY = tonumber(entry.offsetY) or 0
    local widthAdjust = tonumber(entry.widthAdjust) or 0
    local heightAdjust = tonumber(entry.heightAdjust) or 0

    if parent ~= nil and parent ~= "screen" then
        return false
    end
    if point ~= nil and point ~= "CENTER" then
        return false
    end
    if relative ~= nil and relative ~= "CENTER" then
        return false
    end
    if offsetX ~= 0 or offsetY ~= 0 or widthAdjust ~= 0 or heightAdjust ~= 0 then
        return false
    end
    if entry.hideWithParent or entry.keepInPlace or entry.autoWidth or entry.autoHeight then
        return false
    end

    -- Ignore housekeeping-only entries such as hudMinWidth.
    --
    -- `enabled` is whitelisted because 3.0 era profiles still carry the
    -- legacy enabled flag on ghost entries — without this, an `enabled=false`
    -- ghost survives pruning, falls through the cleanup loop, and ends up
    -- masking the AceDB default with a useless zero-offset CENTER anchor.
    -- The flag itself is meaningless once the migration normalizes things.
    for key, value in pairs(entry) do
        if key ~= "parent"
            and key ~= "point"
            and key ~= "relative"
            and key ~= "offsetX"
            and key ~= "offsetY"
            and key ~= "sizeStable"
            and key ~= "sizeStableAnchoring"
            and key ~= "hideWithParent"
            and key ~= "keepInPlace"
            and key ~= "autoWidth"
            and key ~= "autoHeight"
            and key ~= "widthAdjust"
            and key ~= "heightAdjust"
            and key ~= "enabled"
            and value ~= nil
        then
            return false
        end
    end

    return true
end

-- Buffered debug log: chat isn't available during OnInitialize/OnEnable when
-- migrations run, so we collect lines into a global table that can be dumped
-- via /qui miglog after login. The buffer is created lazily on first write.
--
-- Logging is unconditional during the v3.1.5 anchor-migration debug push.
-- Strip the MigLog calls and this helper after the bug is fixed.
local function MigLog(fmt, ...)
    if not _G.QUI_MIGRATION_LOG then _G.QUI_MIGRATION_LOG = {} end
    local line
    if select("#", ...) > 0 then
        local ok, msg = pcall(string.format, fmt, ...)
        line = ok and msg or fmt
    else
        line = fmt
    end
    _G.QUI_MIGRATION_LOG[#_G.QUI_MIGRATION_LOG + 1] = line
end






---------------------------------------------------------------------------
-- 3. Feature migrations
---------------------------------------------------------------------------

local function ResetCastbarPreviewModes(profile)
    if not profile or not profile.quiUnitFrames then
        return
    end

    for _, unitKey in ipairs({ "player", "target", "focus", "pet", "targettarget" }) do
        local unitDB = profile.quiUnitFrames[unitKey]
        if unitDB and unitDB.castbar then
            unitDB.castbar.previewMode = false
        end
    end

    for i = 1, 8 do
        local bossDB = profile.quiUnitFrames["boss" .. i]
        if bossDB and bossDB.castbar then
            bossDB.castbar.previewMode = false
        end
    end
end

local function ColorsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    for i = 1, 4 do
        if (a[i] or 0) ~= (b[i] or 0) then
            return false
        end
    end

    return true
end

-- v39: Border color SOURCE enum. Replaces the implicit two-toggle model
-- (skinBorderUseClassColor + frozen skinBorderColor; tooltip's
-- borderUseClassColor/borderUseAccentColor) with an explicit
-- "theme" | "class" | "custom" source. The old Skinning options page froze
-- skinBorderColor to a snapshot of the accent the first time it was opened,
-- which permanently shadowed the theme. This migration auto-heals those
-- snapshots back to "theme" via a preset-RGB fingerprint.
--
-- BORDER_PRESET_RGBS is a FROZEN copy of GUI.ThemePresets as of v39. Migrations
-- must be self-contained and version-stable; they cannot read GUI.ThemePresets
-- (which may change in future releases).
local BORDER_PRESET_RGBS = {
    { 0.376, 0.647, 0.980, 1 }, { 0.204, 0.827, 0.600, 1 }, { 0.780, 0.192, 0.192, 1 },
    { 0.267, 0.467, 0.800, 1 }, { 0.580, 0.490, 0.890, 1 }, { 0.961, 0.620, 0.043, 1 },
    { 0.914, 0.349, 0.518, 1 }, { 0.196, 0.804, 0.494, 1 },
}

-- A stored border color is a freeze snapshot (-> "theme") if it is nil, equals the
-- profile's current accent, or exactly equals any built-in theme-preset RGB. Only
-- a color matching none of those is treated as a genuine custom pick.
local function IsBorderFreezeSnapshot(color, accent)
    if type(color) ~= "table" then return true end
    if type(accent) == "table" and ColorsEqual(color, accent) then return true end
    for _, preset in ipairs(BORDER_PRESET_RGBS) do
        if ColorsEqual(color, preset) then return true end
    end
    return false
end

local function MigrateBorderColorSource(profile)
    if type(profile) ~= "table" then return end
    local general = profile.general
    if type(general) == "table" and general.skinBorderColorSource == nil then
        local accent = general.addonAccentColor
        local source
        if general.skinBorderUseClassColor == true then
            source = "class"
        elseif type(general.skinBorderColor) == "table"
            and not IsBorderFreezeSnapshot(general.skinBorderColor, accent) then
            source = "custom"
        else
            source = "theme"
        end
        general.skinBorderColorSource = source
        general.skinBorderUseClassColor = nil
    end

    local tooltip = profile.tooltip
    if type(tooltip) == "table" and tooltip.borderColorSource == nil then
        local accent = general and general.addonAccentColor
        local hasLegacyClassKey = rawget(tooltip, "borderUseClassColor") ~= nil
        local hasLegacyAccentKey = rawget(tooltip, "borderUseAccentColor") ~= nil
        local source
        if tooltip.borderUseClassColor == true then
            source = "class"
        elseif tooltip.borderUseAccentColor == true then
            source = "theme"
        elseif hasLegacyClassKey and tooltip.borderUseClassColor == false then
            source = "custom"
        elseif type(tooltip.borderColor) == "table"
            and not IsBorderFreezeSnapshot(tooltip.borderColor, accent) then
            source = "custom"
        elseif not hasLegacyClassKey and not hasLegacyAccentKey then
            source = "class"
        else
            source = "theme"
        end
        tooltip.borderColorSource = source
        tooltip.borderUseClassColor = nil
        tooltip.borderUseAccentColor = nil
    end
end

---------------------------------------------------------------------------
-- v40: MigrateBorderColoring (registry-driven)
--
-- Rolls the per-module border color SOURCE enum out to the remaining
-- in-scope modules. Each module is described by a Helpers.BorderRegistry
-- entry carrying a `prefix`, a `db(profile)` accessor (or, for `multi`
-- modules, an `instances(profile)` list), and a `legacy` descriptor:
--   legacy = { table=<oldColorKey>, useClass=<oldBool>, accent=<oldBool>,
--              scalars=<bool>, override=<oldBool> }
--
-- For each module DB table we (in order):
--   1. Skip entirely if it already carries the source key (idempotent).
--   2. Rename the legacy color key onto the canonical {prefix}BorderColor.
--   3. Fold crosshair-style borderR/G/B/A scalars into {prefix}BorderColor.
--   4. Derive {prefix}BorderColorSource preserving the current look:
--        override declared AND off/absent -> "inherit" (NO pinned color);
--        else useClass truthy -> "class"; else accent truthy -> "theme";
--        else "custom" (keeping whatever literal color is present).
--      The `override` arm is for modules whose OFF state historically meant
--      "inherit the global skin border" (preyTracker/mplusTimer/readyCheck);
--      those users must NOT be pinned to the frozen custom color.
--   5. Delete the now-dead legacy boolean keys (including override).
--
-- Exposed as Helpers.MigrateBorderColoringTable (one table) and
-- Helpers.MigrateBorderColoring (whole registry) so the gate and the unit
-- test invoke the exact same conversion. Key derivation is shared with the
-- options page and the resolver via Helpers.GetBorderKeys.
---------------------------------------------------------------------------
local function MigrateBorderColoringTable(db, entry)
    if type(db) ~= "table" or type(entry) ~= "table" then return end

    local Helpers = ns.Helpers
    local prefix = entry.prefix or ""
    local keys = (Helpers and Helpers.GetBorderKeys and Helpers.GetBorderKeys(prefix)) or {
        source = (prefix == "" and "borderColorSource") or (prefix .. "BorderColorSource"),
        color  = (prefix == "" and "borderColor") or (prefix .. "BorderColor"),
    }
    local sourceKey = keys.source
    local colorKey = keys.color
    local legacy = entry.legacy or {}

    -- 1. Idempotent guard: a table that already has the source key is done.
    if db[sourceKey] ~= nil then return end

    -- 2. Rename legacy color key -> canonical color key (don't clobber).
    if legacy.table and db[legacy.table] ~= nil and db[colorKey] == nil then
        db[colorKey] = db[legacy.table]
        db[legacy.table] = nil
    end

    -- 3. Crosshair scalar fold: borderR/G/B/A -> {prefix}BorderColor table.
    if legacy.scalars and db[colorKey] == nil and db.borderR ~= nil then
        db[colorKey] = { db.borderR, db.borderG, db.borderB, db.borderA }
    end

    -- 4. Derive source, preserving the current look.
    --
    -- Override-flag modules (preyTracker, mplusTimer, readyCheck) historically
    -- had an OFF state meaning "inherit the global skin border" — their apply
    -- called the no-arg global resolver when the override was off. When such an
    -- entry declares `legacy.override`, a FALSY (false/nil/absent) override must
    -- migrate to "inherit" — NOT a pinned custom color — or those users would
    -- suddenly get the frozen (usually black) borderColor instead of the global
    -- accent they actually see today. The useClass/accent/custom derivation only
    -- applies when the override was explicitly ON.
    if legacy.override and not db[legacy.override] then
        db[sourceKey] = "inherit"
    elseif legacy.useClass and db[legacy.useClass] then
        db[sourceKey] = "class"
    elseif legacy.accent and db[legacy.accent] then
        db[sourceKey] = "theme"
    else
        -- Containers that never carried a per-instance border color (the flat
        -- CDM aura/auraBar buff containers) declare legacy.defaultSource so the
        -- fall-through lands on "inherit" instead of pinning a colorless
        -- "custom". Icon-row containers omit it and keep the "custom" default,
        -- preserving the legacy per-row color renamed in step 2.
        db[sourceKey] = legacy.defaultSource or "custom"
    end

    -- 5. Delete dead legacy booleans.
    if legacy.override then db[legacy.override] = nil end
    if legacy.useClass then db[legacy.useClass] = nil end
    if legacy.accent then db[legacy.accent] = nil end
end

local function MigrateBorderColoring(profile)
    if type(profile) ~= "table" then return end
    local Helpers = ns.Helpers
    local registry = Helpers and Helpers.BorderRegistry
    if not registry or type(registry.Each) ~= "function" then return end

    registry.Each(function(entry)
        if type(entry) ~= "table" then return end
        if entry.multi then
            local instances = type(entry.instances) == "function" and entry.instances(profile)
            if type(instances) == "table" then
                for _, db in ipairs(instances) do
                    MigrateBorderColoringTable(db, entry)
                end
            end
        else
            local db = type(entry.db) == "function" and entry.db(profile)
            if db ~= nil then
                MigrateBorderColoringTable(db, entry)
            end
        end
    end)
end

-- Expose the conversion so the gate, the options page, and the unit test all
-- share one implementation. Guarded so a partially-loaded ns can't error.
if ns.Helpers then
    ns.Helpers.MigrateBorderColoringTable = MigrateBorderColoringTable
    ns.Helpers.MigrateBorderColoring = MigrateBorderColoring
end

-- v41: Purge chat keys orphaned by the chat takeover. The QUI display
-- replaced the skinned-Blizzard-frame path outright (chat.enabled IS the
-- takeover), so nothing reads these profile keys anymore. Pure deletion.
local function PurgeOrphanedChatKeys(profile)
    if type(profile) ~= "table" then return end
    local chat = type(profile.chat) == "table" and profile.chat or nil

    -- TRANSLATE the old opt-in switch before purging it (adversarial-review
    -- High). chat.enabled alone now drives the takeover, but on released
    -- builds it defaulted true while displayMode (default "blizzard") was
    -- the real opt-in. Only an explicit displayMode == "custom" — a
    -- non-default value, so it survived AceDB's defaults-strip — marks a
    -- takeover opt-in. An explicit "blizzard", an absent key (stripped
    -- default), or a profile with no chat table at all means the user was
    -- on (skinned) Blizzard chat: hand them STOCK chat, opt-in via the
    -- master toggle. Without this, every migrated default profile would be
    -- silently flipped into the takeover.
    if not (chat and chat.displayMode == "custom") then
        if not chat then
            profile.chat = {}
            chat = profile.chat
        end
        chat.enabled = false
    end

    chat.displayMode = nil               -- the old blizzard/custom switch
    chat.hideButtons = nil               -- Blizzard-frame button hiding
    chat.chatTabBorderColor = nil        -- Blizzard tab border colors
    chat.chatTabBorderColorSource = nil
    chat.frameSize = nil                 -- ChatFrame1 size persistence
    chat.framePosition = nil             -- ChatFrame1 position persistence
    chat.copyHistorySource = nil         -- copy window reads the store now
    chat.scrollbackLines = nil           -- Blizzard-frame scrollback cap
    if type(chat.hyperlinks) == "table" then
        chat.hyperlinks.interactiveNames = nil -- producer (player-link wrap) deleted
    end
end

-- v42: customDisplay multi-window — wrap the flat single-window keys
-- (width/height/position/tabs) into customDisplay.windows[1]. Geometry keys
-- may be absent (AceDB strips defaults); only wrap when something flat is
-- actually stored — a fully-default profile stays empty and the runtime
-- seeder (tab_manager.GetWindowsConfig) builds windows[1] from defaults.
-- Idempotent: a profile already carrying windows[] only sheds leftover
-- flat keys.
local function MigrateCustomDisplayWindows(profile)
    if type(profile) ~= "table" then return end
    local chat = type(profile.chat) == "table" and profile.chat or nil
    local cd = chat and type(chat.customDisplay) == "table" and chat.customDisplay or nil
    if not cd then return end
    if type(cd.windows) == "table" and next(cd.windows) ~= nil then
        cd.width, cd.height, cd.position, cd.tabs = nil, nil, nil, nil
        return
    end
    local hasFlat = cd.width ~= nil or cd.height ~= nil or cd.position ~= nil
        or (type(cd.tabs) == "table" and #cd.tabs > 0)
    if not hasFlat then return end
    cd.windows = { {
        width = cd.width,
        height = cd.height,
        position = cd.position and CloneValue(cd.position) or nil,
        tabs = (type(cd.tabs) == "table") and CloneValue(cd.tabs) or nil,
    } }
    cd.width, cd.height, cd.position, cd.tabs = nil, nil, nil, nil
end

---------------------------------------------------------------------------
-- v43: RetireModuleMasterFlags — suite-split follow-up.
--
-- The Module Addons rows (C_AddOns enable state, account-wide) are now the
-- only module-level switch. Five legacy per-profile master flags are forced
-- true so a stale false can never silently disable a module whose addon row
-- says on.
--
-- When the ACTIVE profile carried an explicit false, that intent is first
-- reflected account-wide into the addon disable state before the flag is
-- forced, so users who turned a module off don't silently lose their choice.
--
-- chat.enabled and quiGroupFrames.enabled are deliberately NOT touched:
-- chat.enabled is the dormant guard for stock-chat users; quiGroupFrames.enabled
-- is the group-frames opt-in default.
--
-- Headless safety: every C_AddOns / QUI reference is guarded so the step
-- degrades to pure force-true when running outside the WoW client.
---------------------------------------------------------------------------
local RETIRED_MASTER_FLAGS = {
    { path = { "quiUnitFrames", "enabled" },         folder = "QUI_UnitFrames"  },
    { path = { "actionBars",    "enabled" },         folder = "QUI_ActionBars"  },
    { path = { "ncdm",          "enabled" },         folder = "QUI_CDM"         },
    { path = { "minimap",       "enabled" },         folder = "QUI_Minimap"     },
    { path = { "damageMeter",   "native", "enabled" }, folder = "QUI_DamageMeter" },
}

local function RetireModuleMasterFlags(profile)
    if type(profile) ~= "table" then return end

    -- Detect whether this is the currently active profile by table identity
    -- against the raw sv entry that Migrations.Run pinned in _currentActiveProfile.
    -- Outside Migrations.Run (e.g. profile import / profile switch), the
    -- variable is nil and the addon-disable branch is skipped gracefully.
    local isActiveProfile = (_currentActiveProfile ~= nil)
        and (profile == _currentActiveProfile)

    for _, entry in ipairs(RETIRED_MASTER_FLAGS) do
        -- Walk the path into the profile, stopping at any non-table step.
        local tbl = profile
        local ok = true
        for i = 1, #entry.path - 1 do
            local segment = entry.path[i]
            if type(tbl[segment]) ~= "table" then
                ok = false
                break
            end
            tbl = tbl[segment]
        end
        if not ok then
            -- Intermediate table absent — no stored flag, nothing to retire.
        else
            local leaf = entry.path[#entry.path]
            if tbl[leaf] == false then
                -- This profile explicitly disabled the module.
                -- If it's the active profile, carry the intent to the addon layer.
                if isActiveProfile
                    and C_AddOns
                    and type(C_AddOns.DisableAddOn) == "function"
                then
                    C_AddOns.DisableAddOn(entry.folder)
                    if type(C_AddOns.SaveAddOns) == "function" then
                        C_AddOns.SaveAddOns()
                    end
                end
                -- Force the flag true in ALL profiles so it can never suppress
                -- a module whose addon row is on.
                tbl[leaf] = true
            end
        end
    end
end

---------------------------------------------------------------------------
-- v44: MigrateChatRealmNames — decouple sender realm display from
-- channelShorten.
--
-- Sender realm display used to be a side effect of chat.modifiers.channelShorten
-- ("shorten channel labels"): on ⇒ realm stripped, off ⇒ realm shown. It now
-- has its own setting, chat.modifiers.showRealmNames (default false).
--
-- Realm names were shown iff channel-shortening was EXPLICITLY disabled, so only
-- that case needs a write — the false default already reproduces the stripped
-- look for default / shorten-on profiles. Idempotent.
---------------------------------------------------------------------------
local function MigrateChatRealmNames(profile)
    if type(profile) ~= "table" then return end
    local chat = type(profile.chat) == "table" and profile.chat or nil
    local mods = chat and type(chat.modifiers) == "table" and chat.modifiers or nil
    if not mods then return end
    local cs = type(mods.channelShorten) == "table" and mods.channelShorten or nil
    if cs and cs.enabled == false then
        -- This profile opted out of shortening, so it was showing realms; keep it.
        mods.showRealmNames = true
    end
    -- else: leave the false default — default/shorten-on profiles stripped the realm.
end

---------------------------------------------------------------------------
-- v45: MigrateChatWindowPositionsToFrameAnchoring — single position store
-- for chat windows (damage-meter pattern).
--
-- Chat window position used to live in TWO places at once:
--   * chat.customDisplay.windows[i].position — re-asserted by the display
--     layer on every Refresh, and
--   * frameAnchoring.chatFrame1/chatWindow<i> — written by every layout-mode
--     drag and re-applied by the anchoring system at login, on spec change,
--     and on layout-mode Save/Discard.
-- The two drifted apart (grip resizes, size sliders, and settings writes
-- only updated windows[i]), so the chat frame snapped between the stores
-- depending on which system applied last.
--
-- frameAnchoring is now the only position store. windows[i].position wins
-- the fold for free/screen entries because the display layer re-asserted it
-- on every refresh — it is the position the user actually saw. An entry
-- anchored to a REAL frame is an explicit user choice and is kept as-is.
-- The legacy position sub-table is deleted either way. Idempotent: a second
-- pass finds no windows[i].position and does nothing.
---------------------------------------------------------------------------
local function MigrateChatWindowPositionsToFrameAnchoring(profile)
    if type(profile) ~= "table" then return end
    local chat = type(profile.chat) == "table" and profile.chat or nil
    local cd = chat and type(chat.customDisplay) == "table" and chat.customDisplay or nil
    local windows = cd and type(cd.windows) == "table" and cd.windows or nil
    if not windows then return end
    for i = 1, #windows do
        local wc = windows[i]
        if type(wc) == "table" then
            local pos = type(wc.position) == "table" and wc.position or nil
            if pos and pos.point then
                if type(profile.frameAnchoring) ~= "table" then
                    profile.frameAnchoring = {}
                end
                local key = (i == 1) and "chatFrame1" or ("chatWindow" .. i)
                local existing = profile.frameAnchoring[key]
                local hasRealParent = type(existing) == "table" and existing.parent
                    and existing.parent ~= "disabled" and existing.parent ~= "screen"
                if not hasRealParent then
                    profile.frameAnchoring[key] = {
                        parent     = "disabled",
                        point      = pos.point,
                        relative   = pos.relPoint or pos.point,
                        offsetX    = pos.x or 0,
                        offsetY    = pos.y or 0,
                        sizeStable = true,
                    }
                end
            end
            wc.position = nil
        end
    end
end

---------------------------------------------------------------------------
-- v46: MigrateUnifiedAuras — collapse the three legacy group-frame aura
-- tables (flat `auras` filter strips, `pinnedAuras` spec slots, and
-- `auraIndicators` per-spell indicators) into one `auras.elements` element
-- list. `elements["*"]` holds all-spec elements; `elements[specID]` holds
-- per-spec (pinned) ones. Pure and idempotent.
---------------------------------------------------------------------------

-- edgeInset → (offsetX, offsetY) by anchor sign
local PINNED_INSET_SIGN = {
    TOPLEFT = { 1, -1 }, TOP = { 0, -1 }, TOPRIGHT = { -1, -1 },
    LEFT = { 1, 0 }, CENTER = { 0, 0 }, RIGHT = { -1, 0 },
    BOTTOMLEFT = { 1, 1 }, BOTTOM = { 0, 1 }, BOTTOMRIGHT = { -1, 1 },
}

local function migrateStrips(auras, elements)
    local function carryCommon(e, a, p)  -- p = "buff" | "debuff"
        local Cap = (p == "buff") and "Buff" or "Debuff"
        e.iconSize = a[p .. "IconSize"]; e.anchor = a[p .. "Anchor"]
        e.growDirection = a[p .. "GrowDirection"]; e.spacing = a[p .. "Spacing"]
        e.offsetX = a[p .. "OffsetX"]; e.offsetY = a[p .. "OffsetY"]
        e.hideSwipe = a[p .. "HideSwipe"]; e.reverseSwipe = a[p .. "ReverseSwipe"]
        e.showDurationText = a["show" .. Cap .. "DurationText"]
        e.durationFont = a[p .. "DurationFont"]; e.durationFontSize = a[p .. "DurationFontSize"]
        e.durationAnchor = a[p .. "DurationAnchor"]
        e.durationOffsetX = a[p .. "DurationOffsetX"]; e.durationOffsetY = a[p .. "DurationOffsetY"]
        e.durationColor = a[p .. "DurationColor"]; e.durationUseTimeColor = a[p .. "DurationUseTimeColor"]
        e.showDurationColor = a.showDurationColor; e.showExpiringPulse = a.showExpiringPulse
        e.filterMode = a.filterMode
    end
    local debuff = { id = "debuffs", enabled = auras.showDebuffs == true, mode = "filterStrip",
        auraType = "HARMFUL", maxIcons = auras.maxDebuffs or 0,
        classifications = auras.debuffClassifications or {}, whitelist = auras.debuffWhitelist or {},
        blacklist = auras.debuffBlacklist or {} }
    carryCommon(debuff, auras, "debuff")
    local buff = { id = "buffs", enabled = auras.showBuffs == true, mode = "filterStrip",
        auraType = "HELPFUL", maxIcons = auras.maxBuffs or 0,
        onlyMine = auras.buffFilterOnlyMine == true, hidePermanent = auras.buffHidePermanent == true,
        dedupeDefensives = auras.buffDeduplicateDefensives ~= false,
        classifications = auras.buffClassifications or {}, whitelist = auras.buffWhitelist or {},
        blacklist = auras.buffBlacklist or {} }
    carryCommon(buff, auras, "buff")
    elements["*"][#elements["*"] + 1] = debuff
    elements["*"][#elements["*"] + 1] = buff
end

local function migratePinned(pinned, elements)
    if type(pinned) ~= "table" or type(pinned.specSlots) ~= "table" then return end
    local inset = pinned.edgeInset or 0
    for specID, slots in pairs(pinned.specSlots) do
        elements[specID] = elements[specID] or {}
        for _, slot in ipairs(slots) do
            local sign = PINNED_INSET_SIGN[slot.anchor] or { 0, 0 }
            elements[specID][#elements[specID] + 1] = {
                mode = "tracked", spells = { slot.spellID }, onlyMine = false, onlyMineSpells = {},
                displayType = slot.displayType or "icon",
                anchor = slot.anchor, offsetX = sign[1] * inset, offsetY = sign[2] * inset,
                iconSize = pinned.slotSize or 8, color = slot.color or { 1, 1, 1 },
                hideSwipe = pinned.showSwipe ~= true, reverseSwipe = pinned.reverseSwipe == true,
                enabled = pinned.enabled == true,
            }
        end
    end
end

local function migrateIndicators(ai, elements)
    if type(ai) ~= "table" or type(ai.entries) ~= "table" then return end
    local enabled = ai.enabled == true
    local iconStrip = nil
    for _, entry in ipairs(ai.entries) do
        for _, ind in ipairs(entry.indicators or {}) do
            if ind.enabled ~= false then
                local on = enabled and entry.enabled ~= false
                if ind.type == "icon" then
                    -- Only enabled entries contribute their spell (a disabled tracked
                    -- aura was never shown). The shared strip's own enabled flag is the
                    -- container-level toggle, set once and order-independent -- deriving
                    -- it from the first entry processed would wrongly disable a live
                    -- strip when a disabled entry happens to come first.
                    if entry.enabled ~= false then
                        if not iconStrip then
                            iconStrip = { mode = "tracked", displayType = "icon", spells = {}, onlyMine = false,
                                onlyMineSpells = {}, enabled = enabled, anchor = ai.anchor, growDirection = ai.growDirection,
                                spacing = ai.spacing, iconSize = ai.iconSize, maxIcons = ai.maxIndicators,
                                offsetX = ai.anchorOffsetX or 0, offsetY = ai.anchorOffsetY or 0,
                                hideSwipe = ai.hideSwipe == true, reverseSwipe = ai.reverseSwipe == true,
                                color = { 1, 1, 1 } }
                            elements["*"][#elements["*"] + 1] = iconStrip
                        end
                        iconStrip.spells[#iconStrip.spells + 1] = entry.spellID
                        iconStrip.onlyMineSpells[entry.spellID] = entry.onlyMine == true
                    end
                elseif ind.type == "bar" then
                    elements["*"][#elements["*"] + 1] = {
                        mode = "tracked", displayType = "bar", spells = { entry.spellID }, enabled = on,
                        onlyMine = entry.onlyMine == true, onlyMineSpells = {},
                        anchor = ind.anchor, offsetX = ind.offsetX or 0, offsetY = ind.offsetY or 0,
                        color = ind.color or { 1, 1, 1 },
                        bar = { orientation = ind.orientation, thickness = ind.thickness, length = ind.length,
                            matchFrameSize = ind.matchFrameSize, backgroundColor = ind.backgroundColor,
                            hideBorder = ind.hideBorder, borderSize = ind.borderSize, borderColor = ind.borderColor,
                            lowTimeThreshold = ind.lowTimeThreshold, lowTimeColor = ind.lowTimeColor },
                    }
                elseif ind.type == "healthBarColor" then
                    elements["*"][#elements["*"] + 1] = {
                        mode = "tracked", displayType = "healthTint", spells = { entry.spellID }, enabled = on,
                        onlyMine = entry.onlyMine == true, onlyMineSpells = {},
                        color = ind.color or { 1, 1, 1 }, healthTint = { animation = ind.animation or "fill" },
                    }
                end
            end
        end
    end
end

-- Pure, idempotent per-context migration. Exposed for tests.
function Migrations.MigrateUnifiedAuras_Context(ctx)
    if type(ctx) ~= "table" then return end
    if ctx.auras and ctx.auras.elements then return end  -- already migrated → no-op
    ctx.auras = ctx.auras or {}
    local elements = { ["*"] = {} }
    migrateStrips(ctx.auras, elements)
    migratePinned(ctx.pinnedAuras, elements)
    migrateIndicators(ctx.auraIndicators, elements)
    -- ADDITIVE: add the unified model alongside the legacy keys. The old
    -- auras.buff*/debuff* fields, ctx.pinnedAuras and ctx.auraIndicators are KEPT
    -- so the legacy runtime keeps rendering until the consumer flip (and they
    -- double as the rollback source). The flip release removes them from defaults;
    -- existing-profile copies then sit as harmless, ignored cruft.
    ctx.auras.elements = elements
    ctx.auras.enabled = true
end

-- v46 is wired directly into RunOnProfile's gate chain (inlined party/raid
-- loop over Migrations.MigrateUnifiedAuras_Context) rather than via a
-- dedicated file-scope wrapper: RunOnProfile already references every
-- migration as an upvalue and sits at the Lua 5.1 60-upvalue ceiling, so a
-- new wrapper upvalue would break compilation. Group-frame settings live
-- under profile.quiGroupFrames.{party,raid} — confirmed against v15
-- MigrateGroupFrameContainers / v16 NormalizeAuraIndicators.

---------------------------------------------------------------------------
-- v32: MigrateCustomTrackersToContainers
--
-- Mirror each legacy custom tracker (db.customTrackers.bars[i]) into the
-- unified ncdm container table (db.ncdm.containers["customBar_<id>"]) as
-- a new container of type "customBar". The legacy data is left in place
-- so the existing customtrackers.lua renderer keeps working — Phase B.3
-- will wire the new renderer that consumes the migrated containers.
--
-- Safety properties:
--   * Idempotent: re-running refreshes only the legacy-derived customBar
--     mirror for the same legacy id instead of creating duplicates.
--   * Non-destructive: source `customTrackers.bars` is never read for
--     deletion, only for cloning.
--   * Trace-back: each migrated entry is stamped with
--     `_migratedFromCustomTrackers = true` and `_legacyId = <originalId>`
--     so a future cleanup pass can locate and verify them.
--
-- Position semantics:
--   Legacy bars store offsetX/offsetY relative to screen center. CDM
--   containers use `pos = { ox, oy }` for free positioning when
--   `anchorTo = "disabled"`. The migration translates by copying the
--   offsets verbatim and forcing anchorTo="disabled".
---------------------------------------------------------------------------
local CUSTOM_TRACKER_ANCHOR_PREFIX = "customTracker:"
local CDM_CUSTOM_ANCHOR_PREFIX = "cdmCustom_"

local function GetCustomBarContainerKey(legacyId)
    return "customBar_" .. tostring(legacyId)
end

local function GetCustomBarAnchorKey(containerKey)
    return CDM_CUSTOM_ANCHOR_PREFIX .. tostring(containerKey)
end

local function FindCustomBarContainerByLegacyId(containers, legacyId)
    if type(containers) ~= "table" then return nil, nil end
    local destKey = GetCustomBarContainerKey(legacyId)
    if type(containers[destKey]) == "table" then
        return destKey, containers[destKey]
    end
    for key, container in pairs(containers) do
        if type(container) == "table" and container._legacyId == legacyId then
            return key, container
        end
    end
    return nil, nil
end

local function BuildCustomBarRowFromLegacy(bar)
    return {
        iconCount        = bar.maxIcons or 8,
        iconSize         = bar.iconSize or 28,
        borderSize       = bar.borderSize or 2,
        borderColorTable = CloneValue(bar.borderColor or bar.borderColorTable or {0, 0, 0, 1}),
        aspectRatioCrop  = bar.aspectRatioCrop or 1.0,
        zoom             = bar.zoom or 0,
        padding          = bar.spacing or 4,
        xOffset          = 0,
        yOffset          = 0,
        hideDurationText = bar.hideDurationText == true,
        durationFont     = bar.durationFont,
        durationSize     = bar.durationSize or bar.durationTextSize or 13,
        durationOffsetX  = bar.durationOffsetX or 0,
        durationOffsetY  = bar.durationOffsetY or 0,
        durationTextColor = CloneValue(bar.durationColor or bar.durationTextColor or {1, 1, 1, 1}),
        durationAnchor   = bar.durationAnchor or "CENTER",
        stackFont        = bar.stackFont,
        stackSize        = bar.stackSize or bar.stackTextSize or 9,
        stackOffsetX     = bar.stackOffsetX or 3,
        stackOffsetY     = bar.stackOffsetY or -1,
        stackTextColor   = CloneValue(bar.stackColor or bar.stackTextColor or {1, 1, 1, 1}),
        stackAnchor      = bar.stackAnchor or "BOTTOMRIGHT",
        hideStackText    = bar.hideStackText == true,
        opacity          = 1.0,
    }
end

local LEGACY_CUSTOM_TRACKER_COMPAT_FIELDS = {
    "enabled",
    "locked",
    "hideGCD",
    "hideNonUsable",
    "showOnlyOnCooldown",
    "showOnlyWhenActive",
    "showOnlyWhenOffCooldown",
    "showOnlyInCombat",
    "dynamicLayout",
    "clickableIcons",
    "showItemCharges",
    "showRechargeSwipe",
    "noDesaturateWithCharges",
    "showProfessionQuality",
    "showActiveState",
    "activeGlowEnabled",
    "activeGlowType",
    "activeGlowColor",
    "activeGlowLines",
    "activeGlowFrequency",
    "activeGlowThickness",
    "activeGlowScale",
}

local function NormalizeCustomBarVisibilityFlags(container)
    if type(container) ~= "table" then return end

    local mode = "always"
    if container.showOnlyOnCooldown then
        mode = "onCooldown"
        container.showOnlyWhenActive = false
        container.showOnlyWhenOffCooldown = false
    elseif container.showOnlyWhenActive then
        mode = "active"
        container.showOnlyWhenOffCooldown = false
    elseif container.showOnlyWhenOffCooldown then
        mode = "offCooldown"
    end

    container.visibilityMode = mode

    if mode ~= "onCooldown" then
        container.noDesaturateWithCharges = false
    end
end

local function StampCustomBarCompatibilityDefaults(container)
    if type(container) ~= "table" then return end

    container.tooltipContext = container.tooltipContext or "customTrackers"
    container.keybindContext = container.keybindContext or "customTrackers"

    if container.hideGCD == nil then container.hideGCD = true end
    if container.showItemCharges == nil then container.showItemCharges = true end
    if container.showProfessionQuality == nil then container.showProfessionQuality = true end
    if container.showActiveState == nil then container.showActiveState = true end
    if container.activeGlowEnabled == nil then container.activeGlowEnabled = true end
    if container.activeGlowType == nil then container.activeGlowType = "Pixel Glow" end
    if container.activeGlowColor == nil then container.activeGlowColor = {1, 0.85, 0.3, 1} end
    if container.activeGlowLines == nil then container.activeGlowLines = 8 end
    if container.activeGlowFrequency == nil then container.activeGlowFrequency = 0.25 end
    if container.activeGlowThickness == nil then container.activeGlowThickness = 2 end
    if container.activeGlowScale == nil then container.activeGlowScale = 1.0 end

    -- Legacy custom trackers defaulted to fixed slots. A nil value in old
    -- profiles means "static", while generic CDM containers treat nil as
    -- "dynamic"; stamp the legacy default explicitly for migrated bars.
    if container.dynamicLayout == nil then
        container.dynamicLayout = false
    end
    if container.dynamicLayout and container.clickableIcons then
        container.clickableIcons = false
    end

    if type(container.row1) == "table" then
        local row = container.row1
        if row.hideStackText == nil then row.hideStackText = container.hideStackText == true end
        if row.durationFont == nil then row.durationFont = container.durationFont end
        if row.stackFont == nil then row.stackFont = container.stackFont end
    end

    NormalizeCustomBarVisibilityFlags(container)
end

local function CopyLegacyCustomTrackerAnchor(profile, legacyId, containerKey)
    local fa = profile and profile.frameAnchoring
    if type(fa) ~= "table" then return end

    local oldKey = CUSTOM_TRACKER_ANCHOR_PREFIX .. tostring(legacyId)
    local newKey = GetCustomBarAnchorKey(containerKey)

    if type(fa[oldKey]) == "table" and type(fa[newKey]) ~= "table" then
        fa[newKey] = CloneValue(fa[oldKey])
    end

    -- Anything anchored to the old dynamic target should now point at the
    -- unified CDM container resolver.
    for _, entry in pairs(fa) do
        if type(entry) == "table" and entry.parent == oldKey then
            entry.parent = newKey
        end
    end
end

local function PortLegacySpecTrackerEntries(globalDB, legacyId, containerKey, container)
    if type(globalDB) ~= "table" then return end
    if type(globalDB.specTrackerSpells) ~= "table" then return end
    local src = globalDB.specTrackerSpells[legacyId]
    if type(src) ~= "table" then return end

    if type(globalDB.ncdm) ~= "table" then globalDB.ncdm = {} end
    if type(globalDB.ncdm.specTrackerSpells) ~= "table" then
        globalDB.ncdm.specTrackerSpells = {}
    end

    local dstRoot = globalDB.ncdm.specTrackerSpells
    if type(dstRoot[containerKey]) ~= "table" then
        dstRoot[containerKey] = {}
    end

    local dst = dstRoot[containerKey]
    local anyPorted = false
    for specKey, specList in pairs(src) do
        local canonicalKey, specID = GetCanonicalSpecKey(specKey)
        canonicalKey = canonicalKey or specKey
        if type(specList) == "table" then
            local copy = {}
            for i, entry in ipairs(specList) do
                copy[i] = StampLegacySpecEntry(CloneValue(entry), specID, specKey)
            end
            if type(dst[canonicalKey]) == "table" then
                if MergeSpecEntryLists(dst[canonicalKey], copy) then
                    anyPorted = true
                end
            else
                dst[canonicalKey] = copy
                anyPorted = true
            end
            RecordSpecKeyAlias(container, specKey, canonicalKey)
        end
    end

    if anyPorted and type(container) == "table" then
        container.specSpecific = true
    end
end

local IsUncustomizedDefaultTrackerBar

function Migrations.EnsureCustomTrackerBarContainer(profile, bar, globalDB)
    if type(profile) ~= "table" or type(bar) ~= "table" then return nil end
    if type(profile.ncdm) ~= "table" then profile.ncdm = {} end
    if type(profile.ncdm.containers) ~= "table" then profile.ncdm.containers = {} end

    local legacyId = bar.id
    if legacyId == nil or legacyId == "" then return nil end
    local sourceLegacyId = bar._importedLegacyId or legacyId

    local containers = profile.ncdm.containers
    local containerKey, container = FindCustomBarContainerByLegacyId(containers, legacyId)
    if not containerKey then
        containerKey = GetCustomBarContainerKey(legacyId)
    end

    if type(container) ~= "table" then
        container = CloneValue(bar)
        containers[containerKey] = container
    end

    container.builtIn = false
    container.containerType = "customBar"
    container.shape = "icon"
    container.name = bar.name or container.name or "Custom Bar"
    container.id = bar.id
    container._migratedFromCustomTrackers = true
    container._legacyId = legacyId
    container._importedLegacyId = nil

    for _, field in ipairs(LEGACY_CUSTOM_TRACKER_COMPAT_FIELDS) do
        if bar[field] ~= nil then
            container[field] = CloneValue(bar[field])
        end
    end

    container.pos = {
        ox = bar.offsetX or 0,
        oy = bar.offsetY or 0,
    }
    container.anchorTo = "disabled"

    container.row1 = BuildCustomBarRowFromLegacy(bar)
    container.row2 = { iconCount = 0 }
    container.row3 = { iconCount = 0 }

    local gd = bar.growDirection or container.growDirection
    container.growDirection = gd or "RIGHT"
    container.layoutDirection = (gd == "UP" or gd == "DOWN") and "VERTICAL" or "HORIZONTAL"

    if type(container.entries) ~= "table" and type(bar.entries) == "table" then
        container.entries = CloneValue(bar.entries)
    end
    if bar.specSpecificSpells == true then
        container.specSpecific = true
    end

    CopyLegacyCustomTrackerAnchor(profile, legacyId, containerKey)
    PortLegacySpecTrackerEntries(globalDB or _currentGlobalDB, sourceLegacyId, containerKey, container)
    StampCustomBarCompatibilityDefaults(container)

    return containerKey, container
end

function Migrations.SyncCustomTrackerBarsToCDM(profile, globalDB)
    local bars = profile and profile.customTrackers and profile.customTrackers.bars
    if type(bars) ~= "table" then return false end

    local any = false
    for _, bar in ipairs(bars) do
        if type(bar) == "table" and not IsUncustomizedDefaultTrackerBar(bar) then
            local key = Migrations.EnsureCustomTrackerBarContainer(profile, bar, globalDB)
            if key then any = true end
        end
    end
    if any and type(Migrations.RepairCustomTrackerSpecStorage) == "function" then
        Migrations.RepairCustomTrackerSpecStorage(profile, globalDB)
    end
    return any
end

function Migrations.RemoveLegacyCustomBarContainers(profile, globalDB)
    local containers = profile and profile.ncdm and profile.ncdm.containers
    if type(containers) ~= "table" then return end

    for key, container in pairs(containers) do
        if type(key) == "string" and type(container) == "table"
           and container.containerType == "customBar"
           and container._migratedFromCustomTrackers
        then
            containers[key] = nil
            if type(globalDB) == "table"
               and type(globalDB.ncdm) == "table"
               and type(globalDB.ncdm.specTrackerSpells) == "table"
            then
                globalDB.ncdm.specTrackerSpells[key] = nil
            end
            local fa = profile.frameAnchoring
            if type(fa) == "table" then
                fa[GetCustomBarAnchorKey(key)] = nil
            end
        end
    end
end

function IsUncustomizedDefaultTrackerBar(bar)
    if type(bar) ~= "table" then return false end
    if bar.id ~= "default_tracker_1" then return false end
    if bar.enabled ~= nil and bar.enabled ~= false then return false end
    if bar.name ~= nil and bar.name ~= "Trinket & Pot" then return false end
    if bar.offsetX ~= nil and bar.offsetX ~= -406 then return false end
    if bar.offsetY ~= nil and bar.offsetY ~= -152 then return false end
    if bar.iconSize ~= nil and bar.iconSize ~= 28 then return false end
    if bar.spacing ~= nil and bar.spacing ~= 4 then return false end

    local entries = bar.entries
    if type(entries) == "table" then
        if #entries ~= 1 then return false end
        local entry = entries[1]
        if type(entry) ~= "table" or entry.type ~= "item" or entry.id ~= 224022 then
            return false
        end
    end

    return true
end

local function MigrateCustomTrackersToContainers(profile)
    if not profile then return end
    if not profile.customTrackers or type(profile.customTrackers.bars) ~= "table" then
        return
    end

    for i, bar in ipairs(profile.customTrackers.bars) do
        if type(bar) == "table" then
            if bar.id == nil or bar.id == "" then
                bar.id = "anon_" .. tostring(i)
            end
        end
    end
    Migrations.SyncCustomTrackerBarsToCDM(profile, _currentGlobalDB)
end

---------------------------------------------------------------------------
-- v33: RemovePartyTrackerData
--
-- The party tracker feature (CC icons, kick timer, party cooldowns) was
-- removed before the 12.0.5 release. Strip its orphan subtree from existing
-- profiles so the dead keys don't linger.
---------------------------------------------------------------------------
local function RemovePartyTrackerData(profile)
    if not profile then return end
    local gf = profile.quiGroupFrames
    if type(gf) ~= "table" then return end
    if type(gf.party) == "table" then gf.party.partyTracker = nil end
    if type(gf.raid) == "table" then gf.raid.partyTracker = nil end
end

---------------------------------------------------------------------------
-- v34: FinalizeCustomBarContainers
--
-- Phase B.3: legacy customTrackers bars were mirrored into ncdm.containers
-- as customBar_* entries in v32, but they lacked two things the unified
-- renderer needs:
--
--   1. row1 config — the CDM layout pipeline reads iconSize/spacing/etc.
--      from tracker.row1/row2/row3, not from flat top-level fields. Legacy
--      bars stored these flat (tracker.iconSize, tracker.spacing, ...), so
--      LayoutContainer would see #rows == 0 and bail. We synthesize row1
--      from the flat fields and leave row2/row3 as zero-count defaults.
--
--   2. per-spec entry port — legacy bars with specSpecificSpells=true
--      stored their entries under db.global.specTrackerSpells[legacyID]
--      [specKey]. The CDM engine expects per-spec lists under
--      db.global.ncdm.specTrackerSpells[containerKey][specKey]. We copy
--      them across and flag container.specSpecific = true.
--
-- Idempotent: the row1 synthesis only runs when tracker.row1 is absent;
-- the spec port only runs when the destination is empty. Source data is
-- not modified (legacy db.customTrackers / db.global.specTrackerSpells
-- stays intact for B.4 cleanup).
---------------------------------------------------------------------------
local function FinalizeCustomBarContainers(profile)
    if not profile then return end
    local ncdm = profile.ncdm
    if type(ncdm) ~= "table" or type(ncdm.containers) ~= "table" then return end

    for containerKey, container in pairs(ncdm.containers) do
        if type(container) == "table" and container.containerType == "customBar" then
            -- 1. Row1 synthesis
            if type(container.row1) ~= "table" then
                container.row1 = BuildCustomBarRowFromLegacy(container)
                -- Zero-count rows so the 1..3 row loop sees a single row.
                container.row2 = container.row2 or { iconCount = 0 }
                container.row3 = container.row3 or { iconCount = 0 }
            end

            -- Layout direction: legacy bars used growDirection RIGHT/LEFT/UP/DOWN.
            -- Collapse to CDM's HORIZONTAL/VERTICAL if the unified direction
            -- isn't already set.
            if not container.layoutDirection then
                local gd = container.growDirection
                if gd == "UP" or gd == "DOWN" then
                    container.layoutDirection = "VERTICAL"
                else
                    container.layoutDirection = "HORIZONTAL"
                end
            end

            -- 2. Per-spec entry port (only if legacy bar had specSpecific)
            local legacyID = container._legacyId
            local global = _currentGlobalDB
            if legacyID and global
               and type(global.specTrackerSpells) == "table"
               and type(global.specTrackerSpells[legacyID]) == "table"
               and not container._specEntriesPortedB3 then

                if type(global.ncdm) ~= "table" then global.ncdm = {} end
                if type(global.ncdm.specTrackerSpells) ~= "table" then
                    global.ncdm.specTrackerSpells = {}
                end

                local before = global.ncdm.specTrackerSpells[containerKey]
                PortLegacySpecTrackerEntries(global, legacyID, containerKey, container)
                local after = global.ncdm.specTrackerSpells[containerKey]
                if type(after) == "table" and (before ~= nil or next(after) ~= nil) then
                    container.specSpecific = true
                end
                container._specEntriesPortedB3 = true
            end
        end
    end
end

local function RepairCustomTrackerCDMBarFidelity(profile)
    local containers = profile and profile.ncdm and profile.ncdm.containers
    if type(containers) ~= "table" then return end

    local hasMigratedCustomBar = false
    for key, container in pairs(containers) do
        if type(key) == "string"
           and type(container) == "table"
           and container.containerType == "customBar"
           and container._legacyId
        then
            hasMigratedCustomBar = true
            break
        end
    end

    if hasMigratedCustomBar then
        Migrations.SyncCustomTrackerBarsToCDM(profile, _currentGlobalDB)
    end
end

function Migrations.RepairCustomTrackerSpecStorage(profile, globalDB)
    if type(profile) ~= "table" then return false end
    local containers = profile.ncdm and profile.ncdm.containers
    if type(containers) ~= "table" then return false end
    globalDB = globalDB or _currentGlobalDB
    if type(globalDB) ~= "table" then return false end
    if type(globalDB.ncdm) ~= "table" then globalDB.ncdm = {} end
    if type(globalDB.ncdm.specTrackerSpells) ~= "table" then
        globalDB.ncdm.specTrackerSpells = {}
    end

    local root = globalDB.ncdm.specTrackerSpells
    local changed = false

    for containerKey, container in pairs(containers) do
        if type(containerKey) == "string"
           and containerKey:find("^customBar_")
           and type(container) == "table"
        then
            local byContainer = root[containerKey]
            if type(byContainer) == "table" then
                local keys = {}
                for specKey in pairs(byContainer) do
                    keys[#keys + 1] = specKey
                end

                for _, specKey in ipairs(keys) do
                    local list = byContainer[specKey]
                    if type(list) == "table" then
                        local canonicalKey, specID = GetCanonicalSpecKey(specKey)
                        canonicalKey = canonicalKey or specKey
                        if not specID and type(container._sourceSpecID) == "number" then
                            specID = container._sourceSpecID
                        end

                        for _, entry in ipairs(list) do
                            StampLegacySpecEntry(entry, specID, specKey)
                        end
                        if DeduplicateEntryList(list) then
                            changed = true
                        end

                        if canonicalKey ~= specKey then
                            if type(byContainer[canonicalKey]) == "table" then
                                if MergeSpecEntryLists(byContainer[canonicalKey], list) then
                                    changed = true
                                end
                            else
                                byContainer[canonicalKey] = list
                                changed = true
                            end
                            byContainer[specKey] = nil
                            RecordSpecKeyAlias(container, specKey, canonicalKey)
                            changed = true
                        end
                    end
                end
            end

            -- Defensive late pass: if any container.entries leaked back
            -- into a spec-specific bar between v32(d) and here, promote
            -- it through the same path. PromoteLegacyContainerEntriesToPerSpec
            -- handles _sourceSpecID stamping internally; the wipe stays
            -- unconditional for the no-source-spec corner case.
            if container.specSpecific == true
               and type(container.entries) == "table"
               and #container.entries > 0
            then
                PromoteLegacyContainerEntriesToPerSpec(profile, containerKey, container, globalDB)
                container.entries = {}
                changed = true
            end
        end
    end

    return changed
end

local function CopyLegacyResourceBarSettings(profile, legacyKey, targetKey)
    if type(profile) ~= "table" or type(profile.ncdm) ~= "table" then return false end
    local legacy = profile.ncdm[legacyKey]
    if type(legacy) ~= "table" then return false end

    local target = profile[targetKey]
    if type(target) ~= "table" then
        target = {}
        profile[targetKey] = target
    end

    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile[targetKey]
    local changed = false
    for key, legacyValue in pairs(legacy) do
        local currentValue = target[key]
        local defaultValue = type(defaults) == "table" and defaults[key] or nil
        if currentValue == nil or (defaultValue ~= nil and ValuesEqual(currentValue, defaultValue)) then
            target[key] = CloneValue(legacyValue)
            changed = true
        end
    end
    return changed
end

local function RepairResourceBarSettings(profile)
    local changed = false
    if CopyLegacyResourceBarSettings(profile, "powerBar", "powerBar") then
        changed = true
    end
    if CopyLegacyResourceBarSettings(profile, "secondaryPowerBar", "secondaryPowerBar") then
        changed = true
    end
    return changed
end

local function NormalizeCustomCDMBarCompatibility(profile)
    local containers = profile and profile.ncdm and profile.ncdm.containers
    if type(containers) ~= "table" then return end

    local legacyBarsByID = nil
    local legacyBars = profile.customTrackers and profile.customTrackers.bars
    if type(legacyBars) == "table" then
        legacyBarsByID = {}
        for _, bar in ipairs(legacyBars) do
            if type(bar) == "table" and bar.id ~= nil then
                legacyBarsByID[tostring(bar.id)] = bar
            end
        end
    end

    for key, container in pairs(containers) do
        if type(container) == "table" and container.containerType == "customBar" then
            if legacyBarsByID then
                local legacyId = container._legacyId or container.id
                if legacyId == nil and type(key) == "string" then
                    legacyId = key:match("^customBar_(.+)$")
                end
                local bar = legacyId ~= nil and legacyBarsByID[tostring(legacyId)] or nil
                if type(bar) == "table" then
                    for _, field in ipairs(LEGACY_CUSTOM_TRACKER_COMPAT_FIELDS) do
                        if container[field] == nil and bar[field] ~= nil then
                            container[field] = CloneValue(bar[field])
                        end
                    end
                end
            end
            StampCustomBarCompatibilityDefaults(container)
        end
    end
end

----------------------------------------------------------------------------
-- Promote legacy container.entries on a spec-specific customBar into the
-- canonical per-spec storage location at
-- db.global.ncdm.specTrackerSpells[containerKey][canonicalSpec].
--
-- Used by both v32(d) FinalizeLegacyTrackerSpecState and v32(g)
-- RepairCustomTrackerSpecStorage just before they clear container.entries.
-- Each promoted entry is cloned and stamped with _sourceSpecID,
-- _legacySourceSpecKey, and _legacySpellbookSlot so the composer's
-- "Source: <Spec>" tooltip and "Legacy data" hint can attach to it. Real
-- spell IDs and pre-V2 drag-handler garbage both go through unconditionally
-- — the runtime icon factory renders the standard ? fallback for IDs that
-- C_Spell.GetSpellInfo can't resolve, IsPlayerSpell drives the "Not usable
-- on your current class" hint for known-but-cross-class entries, and the
-- _legacySpellbookSlot stamp drives the "Legacy data — may need review"
-- hint. The user gets visibility into what was imported instead of a
-- silently empty bar.
--
-- Returns true if anything was promoted, false otherwise. Caller still
-- wipes container.entries unconditionally so a no-source-spec-hint bar
-- ends up empty (matches prior wipe semantics in that corner case).
----------------------------------------------------------------------------
PromoteLegacyContainerEntriesToPerSpec = function(profile, containerKey, container, globalDB)
    if type(container) ~= "table" then return false end
    if container.specSpecific ~= true then return false end
    if type(container.entries) ~= "table" or #container.entries == 0 then return false end

    local sourceSpecID = container._sourceSpecID
    if type(sourceSpecID) ~= "number" or sourceSpecID <= 0 then
        sourceSpecID = GetProfileSourceSpecID(profile)
    end
    if type(sourceSpecID) ~= "number" or sourceSpecID <= 0 then
        return false
    end
    if container._sourceSpecID == nil then
        container._sourceSpecID = sourceSpecID
    end

    globalDB = globalDB or _currentGlobalDB
    if type(globalDB) ~= "table" then return false end
    if type(globalDB.ncdm) ~= "table" then globalDB.ncdm = {} end
    if type(globalDB.ncdm.specTrackerSpells) ~= "table" then
        globalDB.ncdm.specTrackerSpells = {}
    end
    local root = globalDB.ncdm.specTrackerSpells
    if type(root[containerKey]) ~= "table" then
        root[containerKey] = {}
    end
    local byContainer = root[containerKey]

    local canonicalKey = GetCanonicalSpecKey(sourceSpecID) or tostring(sourceSpecID)
    if type(byContainer[canonicalKey]) ~= "table" then
        byContainer[canonicalKey] = {}
    end

    local promoted = {}
    for _, entry in ipairs(container.entries) do
        if type(entry) == "table" then
            local clone = CloneValue(entry)
            StampLegacySpecEntry(clone, sourceSpecID, tostring(sourceSpecID),
                { legacySpellbookSlot = true })
            promoted[#promoted + 1] = clone
        end
    end
    MergeSpecEntryLists(byContainer[canonicalKey], promoted)
    DeduplicateEntryList(byContainer[canonicalKey])
    return true
end

----------------------------------------------------------------------------
-- LegacyTrackerSpecState repair (folded into the v32 consolidation gate)
--
-- Three repairs in one pass for customBar containers migrated from the
-- legacy customTrackers system:
--
--   1. Field rename promotion: legacy bars stored the toggle as
--      specSpecificSpells; V2 reads specSpecific. v34 only set specSpecific
--      after porting entries from db.global.specTrackerSpells — but the
--      pre-V2 drag-drop handler bypassed that storage, so for the very
--      profiles we need to repair, no entries existed there to port and
--      v34 silently skipped the rename. v35 unconditionally promotes when
--      the legacy field is true.
--
--   2. Spec stamp: tag the container with ncdm._lastSpecID as
--      _sourceSpecID for traceability and as a hint to the runtime
--      LegacyResolver about which spec to attempt entry recovery on.
--
--   3. Promote container.entries into per-spec storage and clear. The
--      pre-V2 drag-drop handler bypassed db.global.specTrackerSpells and
--      stored entries directly under bar.entries (a mix of real spellIDs
--      and slot-index garbage). Promoting them into
--      db.global.ncdm.specTrackerSpells[key][canonicalSpec] (via the
--      shared PromoteLegacyContainerEntriesToPerSpec helper) makes them
--      visible in the composer with full attribution: "Source: <Spec>",
--      "Not usable on your current class" for cross-class IDs, "Legacy
--      data" for slot-index garbage, and the standard ? icon fallback
--      for IDs C_Spell can't resolve. container.entries is then cleared
--      so the live renderer reads exclusively from per-spec storage.
--
-- Source spec hint is a single value (ncdm._lastSpecID), so all
-- spec-specific containers in the profile receive the same stamp. Profiles
-- where bars were configured under different specs will mis-stamp some
-- bars; the user can dismiss / delete those via the Custom CDM Bars UI.
--
-- Idempotent: only writes fields that are absent and only promotes when
-- container.entries is non-empty. After promotion+clear, re-runs see the
-- empty entries list and skip.
----------------------------------------------------------------------------
local function FinalizeLegacyTrackerSpecState(profile)
    if not profile then return end
    local ncdm = profile.ncdm
    if type(ncdm) ~= "table" then return end
    if type(ncdm.containers) ~= "table" then return end

    local sourceSpecID = ncdm._lastSpecID

    for key, container in pairs(ncdm.containers) do
        if type(key) == "string" and key:find("^customBar_")
           and type(container) == "table"
        then
            -- (1) Promote legacy specSpecificSpells -> V2 specSpecific.
            if container.specSpecificSpells == true and container.specSpecific == nil then
                container.specSpecific = true
            end

            -- (2) Stamp the source spec hint when this is a spec-specific bar
            -- and we have a usable hint to apply.
            if container.specSpecific == true
               and container._sourceSpecID == nil
               and type(sourceSpecID) == "number" and sourceSpecID > 0
            then
                container._sourceSpecID = sourceSpecID
            end

            -- (3) Reconcile container.entries with per-spec storage.
            --
            -- For spec-specific containers, the canonical live read path is
            -- db.global.ncdm.specTrackerSpells[key][canonicalSpec]. The
            -- container.entries field is a stale pre-toggle snapshot — and on
            -- profiles damaged by the pre-V2 drag handler bug it holds
            -- spellbook slot indexes / cooldownIDs rather than real spellIDs.
            -- Promoting that data into live storage produced fallback icons
            -- on import.
            --
            -- Promote container.entries into per-spec storage, then clear.
            -- See PromoteLegacyContainerEntriesToPerSpec for the rationale:
            -- the live renderer reads exclusively from per-spec storage,
            -- and the user gets full per-entry attribution in the composer
            -- ("Source: <Spec>", "Legacy data", ? for unresolvable) instead
            -- of a silently empty bar. Caller-side wipe stays unconditional
            -- so profiles missing _sourceSpecID still end up empty.
            if container.specSpecific == true
               and type(container.entries) == "table" and #container.entries > 0
            then
                PromoteLegacyContainerEntriesToPerSpec(profile, key, container, _currentGlobalDB)
                container.entries = {}
            end
        end
    end
end

---------------------------------------------------------------------------
-- v32 step (e): MigrateContainerShapeAndEntryKind
--
-- Collapses the legacy 4-value containerType taxonomy
-- {aura, auraBar, cooldown, customBar} into two orthogonal axes:
--   * container.shape ∈ {icon, bar} — layout/render concern.
--   * entry.kind ∈ {aura, cooldown} — drives aura tracking, ID correction,
--     "show only when active", grey-out, etc.
--
-- Mapping for shape:
--   auraBar  → bar   (the only true StatusBar container)
--   aura     → icon
--   cooldown → icon
--   customBar → icon (already renders via the icon factory; row1 was
--                     synthesized by v32's FinalizeCustomBarContainers)
--
-- Mapping for entry.kind on custom containers (built-ins inject kind at
-- scan time, so they aren't walked here):
--   * Non-spell entries (type=item/trinket/slot/macro): kind=cooldown.
--   * Spell entries on a previously-aura container (containerType in
--     {aura, auraBar}): kind=aura.
--   * Spell entries on cooldown/customBar containers: kind left nil
--     (runtime classifier resolves via _abilityToAuraSpellID + viewer).
--
-- The legacy containerType field is retained as redundant data — readers
-- migrate site-by-site to consult shape/kind. A future cleanup pass can
-- delete it once all consumers are switched.
--
-- Idempotent: writes shape only when nil; writes entry.kind only when nil.
---------------------------------------------------------------------------
local function MigrateContainerShapeAndEntryKind(profile)
    if not profile then return end
    local ncdm = profile.ncdm
    if type(ncdm) ~= "table" or type(ncdm.containers) ~= "table" then return end

    for _, container in pairs(ncdm.containers) do
        if type(container) == "table" then
            -- Stamp shape from legacy containerType.
            if container.shape == nil then
                local ct = container.containerType
                if ct == "auraBar" then
                    container.shape = "bar"
                else
                    -- aura, cooldown, customBar, or unknown → icon
                    container.shape = "icon"
                end
            end

            -- Stamp entry.kind on user-curated entries. Built-in containers
            -- (essential/utility/buff/trackedBar) have entries injected at
            -- scan time with kind already set; custom containers are the
            -- ones we walk here.
            local wasAuraContainer = (container.containerType == "aura"
                                       or container.containerType == "auraBar")

            local function StampList(list)
                if type(list) ~= "table" then return end
                for _, entry in ipairs(list) do
                    if type(entry) == "table" and entry.kind == nil then
                        if entry.type and entry.type ~= "spell" then
                            entry.kind = "cooldown"
                        elseif wasAuraContainer then
                            entry.kind = "aura"
                        end
                        -- Spell entries on cd/customBar containers fall
                        -- through to runtime classification — leave nil.
                    end
                end
            end

            StampList(container.ownedSpells)
            StampList(container.entries)
        end
    end

    -- Per-spec entry storage lives outside ncdm.containers. Walk it too so
    -- spec-specific custom containers (specSpecific=true) get their entries
    -- stamped consistently with their non-spec siblings.
    local globalDB = _currentGlobalDB
    if type(globalDB) == "table"
       and type(globalDB.ncdm) == "table"
       and type(globalDB.ncdm.specTrackerSpells) == "table"
    then
        for containerKey, byContainer in pairs(globalDB.ncdm.specTrackerSpells) do
            local sourceContainer = ncdm.containers[containerKey]
            local wasAuraContainer = sourceContainer
                and (sourceContainer.containerType == "aura"
                     or sourceContainer.containerType == "auraBar")
            if type(byContainer) == "table" then
                for _, specList in pairs(byContainer) do
                    if type(specList) == "table" then
                        for _, entry in ipairs(specList) do
                            if type(entry) == "table" and entry.kind == nil then
                                if entry.type and entry.type ~= "spell" then
                                    entry.kind = "cooldown"
                                elseif wasAuraContainer then
                                    entry.kind = "aura"
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Late migration: import action bar / micro menu / bag bar positions from
-- Blizzard Edit Mode for users whose QUI profile predates frame anchoring
-- for these bars. Runs at PLAYER_LOGIN (not at addon-init time) because it
-- depends on EditModeManagerFrame being populated and the live bar frames
-- being laid out, neither of which is guaranteed during ADDON_LOADED.
--
-- Per-bar gating:
--   1. Bar already has a real (non-placeholder) frameAnchoring entry → PROTECTED.
--      Users who positioned the bar in QUI's Layout Mode keep their position.
--   2. Live frame readable → IMPORTED. Read absolute screen coords from
--      the live frame (lets WoW resolve any anchor chain like
--      MainActionBar → MultiBar5 → ...) and write a UIParent-relative
--      anchor into profile.frameAnchoring[<key>].
--   3. Live frame missing/nil-coords → SKIPPED. Bar gets no entry from
--      this migration; sentinel still stamps so we don't retry forever.
--      Affects e.g. stance bar on a stanceless character — harmless
--      because that bar is never visible for them anyway.
--
-- Note: we deliberately do NOT skip `isInDefaultPosition` entries. Even
-- bars at Blizzard's default need to be captured as explicit QUI data,
-- otherwise the migration leaves a gap exactly where legacy users with
-- no QUI overrides need it filled — they currently get the EditMode
-- position via actionbars.lua's RestoreContainerPosition fallback, but
-- that fallback depends on the live Blizzard frame being readable at
-- apply time. Importing makes the position permanent and editable.
--
-- Sentinel: profile._abPositionsImportedFromEditMode. Stamped after the
-- first successful EditMode read regardless of how many bars actually
-- imported — this is a one-shot best-effort migration, not a "keep
-- trying until everything succeeds" loop.
--
-- Only operates on the active profile (db.profile), not all stored
-- profiles, because EditMode layouts are per-character and other profiles
-- belong to alts with potentially different EditMode setups.
---------------------------------------------------------------------------

-- (system, systemIndex) → { fa = frameAnchoring key, frame = global frame name }
-- Indexed by [system][systemIndex] for ActionBar (which has multiple
-- instances), and [system]["*"] for MicroMenu/Bags (single instance, no
-- systemIndex). Built lazily so the Enum reference doesn't blow up if
-- this file is loaded in a context without Blizzard's enums.
local EM_TO_QUI = nil
local function GetEditModeLookup()
    if EM_TO_QUI then return EM_TO_QUI end
    if type(Enum) ~= "table" or type(Enum.EditModeSystem) ~= "table" then
        return nil
    end
    local AB    = Enum.EditModeSystem.ActionBar
    local MICRO = Enum.EditModeSystem.MicroMenu
    local BAGS  = Enum.EditModeSystem.Bags
    if AB == nil or MICRO == nil or BAGS == nil then
        return nil
    end
    EM_TO_QUI = {
        [AB] = {
            [1]  = { fa = "bar1",      frame = "MainActionBar" },
            [2]  = { fa = "bar2",      frame = "MultiBarBottomLeft" },
            [3]  = { fa = "bar3",      frame = "MultiBarBottomRight" },
            [4]  = { fa = "bar4",      frame = "MultiBarRight" },
            [5]  = { fa = "bar5",      frame = "MultiBarLeft" },
            [6]  = { fa = "bar6",      frame = "MultiBar5" },
            [7]  = { fa = "bar7",      frame = "MultiBar6" },
            [8]  = { fa = "bar8",      frame = "MultiBar7" },
            [11] = { fa = "stanceBar", frame = "StanceBar" },
            [12] = { fa = "petBar",    frame = "PetActionBar" },
            -- 13 = PossessActionBar — intentionally omitted, QUI doesn't manage it
        },
        [MICRO] = { ["*"] = { fa = "microMenu", frame = "MicroMenuContainer" } },
        [BAGS]  = { ["*"] = { fa = "bagBar",    frame = "BagsBar" } },
    }
    return EM_TO_QUI
end

local function LookupEditModeSystem(sys)
    local lookup = GetEditModeLookup()
    if not lookup then return nil end
    local typeTable = lookup[sys.system]
    if not typeTable then return nil end
    return typeTable[sys.systemIndex] or typeTable["*"]
end

local function MigrateActionBarPositionsFromEditMode(profile)
    if type(profile) ~= "table" then return end
    if profile._abPositionsImportedFromEditMode then
        MigLog("EditMode AB import: sentinel set, skipping")
        return
    end

    -- Scope gate: this migration is intended for fresh installs and
    -- pre-3.0 legacy upgraders. RunOnProfile flags eligible profiles
    -- (those whose pre-migration `_schemaVersion` was < 19, i.e. before
    -- MigrateAnchoringV1) by setting `_needsLateAbImport`. Profiles
    -- without that flag have already been through the modern anchoring
    -- pipeline and have explicit QUI positions for any bars they care
    -- about, so we just stamp the sentinel and return.
    if not profile._needsLateAbImport then
        MigLog("EditMode AB import: profile not flagged for late import, stamping sentinel and skipping")
        profile._abPositionsImportedFromEditMode = true
        return
    end

    if not (EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo) then
        MigLog("EditMode AB import: EditModeManagerFrame not ready, will retry")
        return
    end

    local layout = EditModeManagerFrame:GetActiveLayoutInfo()
    if type(layout) ~= "table" or type(layout.systems) ~= "table" then
        MigLog("EditMode AB import: no active layout, will retry")
        return
    end

    profile.frameAnchoring = profile.frameAnchoring or {}
    local fa = profile.frameAnchoring

    local imported, protected, skipped = 0, 0, 0

    for _, sys in ipairs(layout.systems) do
        local mapping = LookupEditModeSystem(sys)
        if mapping then
            local key = mapping.fa
            local existing = fa[key]
            local userHasPosition = (existing ~= nil) and (not IsPlaceholderAnchorEntry(existing))

            if userHasPosition then
                protected = protected + 1
                MigLog("  %s: PROTECTED (user has QUI position)", key)
            else
                local frame = _G[mapping.frame]
                local L = frame and frame.GetLeft and frame:GetLeft()
                local B = frame and frame.GetBottom and frame:GetBottom()
                if type(L) == "number" and type(B) == "number" then
                    fa[key] = {
                        parent   = "screen",
                        point    = "BOTTOMLEFT",
                        relative = "BOTTOMLEFT",
                        offsetX  = L,
                        offsetY  = B,
                    }
                    imported = imported + 1
                    MigLog("  %s: IMPORTED at %.1f, %.1f (from %s, %s)",
                        key, L, B, mapping.frame,
                        sys.isInDefaultPosition and "default" or "moved")
                else
                    skipped = skipped + 1
                    MigLog("  %s: SKIPPED (frame %s not laid out)", key, mapping.frame)
                end
            end
        end
    end

    -- One-shot best-effort: stamp the sentinel after a successful
    -- EditMode read regardless of how many bars actually imported.
    -- Bars that couldn't be read (e.g. stance bar on a stanceless
    -- character) won't get retried — they're invisible for that
    -- character anyway and don't need a frameAnchoring entry.
    profile._abPositionsImportedFromEditMode = true
    profile._needsLateAbImport = nil

    MigLog("EditMode AB import done: imported=%d protected=%d skipped=%d",
        imported, protected, skipped)
end

---------------------------------------------------------------------------
-- Late entry point: migrations that depend on Blizzard runtime state
---------------------------------------------------------------------------
-- Called from QUICore PLAYER_LOGIN (after EditModeManagerFrame is loaded
-- and live frames are laid out, but before the action bar module applies
-- frameAnchoring on PLAYER_ENTERING_WORLD).
--
-- Unlike Migrations.Run, this only operates on the active profile —
-- the data sources (live frames, EditMode layout) are per-character and
-- don't apply to alts' stored profiles.
function Migrations.RunLate(db)
    if not db then return false end
    local profile = db.profile
    if type(profile) ~= "table" then return false end
    MigrateActionBarPositionsFromEditMode(profile)
    return true
end

---------------------------------------------------------------------------
-- Entry point: Run all profile migrations
---------------------------------------------------------------------------
--
-- Note: SeedDefaultFrameAnchoring and DEFAULT_FRAME_ANCHORING used to live
-- here. They wrote a parallel copy of default frameAnchoring entries into
-- every profile on login, bloating SVs with data AceDB already provides
-- via its defaults metatable. Removed. All frameAnchoring defaults now
-- live in core/defaults.lua as the single source of truth. AceDB serves
-- them on read, strips them on save, and no migration write is needed.
--
-- For legacy 2.55 absolute-offset profiles, MigrateAnchoring v1's
-- LEGACY255_DISCARD_ABSOLUTE handling still nils the broken entries;
-- AceDB defaults then fill in the replacements via metatable.

---------------------------------------------------------------------------
-- Snapshot / restore
---------------------------------------------------------------------------
-- Before the migration pipeline mutates a profile, we save a deep copy of
-- the profile under `_migrationBackup`. If a migration corrupts data, the
-- user can run `/qui migration restore [N]` to roll back to the latest
-- pre-migration state. Only the newest snapshot is retained; older builds
-- kept several full profile copies, which made SavedVariables expensive to
-- parse during login/reload.
--
-- The backup excludes `_migrationBackup` itself to prevent recursive growth,
-- and excludes legacy per-profile shipped-default snapshots because those are
-- now represented once in global storage.

local BACKUP_KEY = "_migrationBackup"
local MAX_BACKUP_SLOTS = 1
local BACKUP_EXCLUDED_KEYS = {
    [BACKUP_KEY] = true,
    _shippedDefaults = true,
}

local function DeepCloneExcluding(value, excludedKeys)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        if not excludedKeys[k] then
            copy[k] = DeepCloneExcluding(v, excludedKeys)
        end
    end
    return copy
end

-- Returns the backup container in slotted form, lazily upgrading the
-- legacy single-slot shape ({fromVersion, toVersion, savedAt, snapshot})
-- to the new {slots = {...}} shape. Returns nil if no backup exists.
local function GetBackupContainer(profile)
    local b = profile[BACKUP_KEY]
    if type(b) ~= "table" then return nil end
    if type(b.slots) == "table" then
        return b
    end
    -- Legacy single-slot shape — migrate in place.
    if type(b.snapshot) == "table" then
        local upgraded = { slots = { {
            fromVersion = b.fromVersion,
            toVersion   = b.toVersion,
            savedAt     = b.savedAt,
            snapshot    = b.snapshot,
        } } }
        profile[BACKUP_KEY] = upgraded
        return upgraded
    end
    return nil
end

local function CreateBackup(profile, fromVersion)
    local container = GetBackupContainer(profile) or { slots = {} }
    local newEntry = {
        fromVersion = fromVersion or 0,
        toVersion   = CURRENT_SCHEMA_VERSION,
        savedAt     = (time and time()) or 0,
        snapshot    = DeepCloneExcluding(profile, BACKUP_EXCLUDED_KEYS),
    }
    -- Push to front, trim tail to MAX_BACKUP_SLOTS.
    table.insert(container.slots, 1, newEntry)
    while #container.slots > MAX_BACKUP_SLOTS do
        table.remove(container.slots)
    end
    profile[BACKUP_KEY] = container
end

-- Restore the active profile from a migration backup slot. `slotIndex`
-- is 1-based and defaults to 1 (most recent). Wipes all current profile
-- keys (except the backup container itself) and copies the snapshot in.
-- Returns (ok, messageOrBackupInfo).
function Migrations.Restore(profile, slotIndex)
    if type(profile) ~= "table" then
        return false, "no profile"
    end
    local container = GetBackupContainer(profile)
    if not container or #container.slots == 0 then
        return false, "no migration backup available for this profile"
    end
    slotIndex = tonumber(slotIndex) or 1
    if slotIndex < 1 or slotIndex > #container.slots then
        return false, ("invalid slot %d (have %d backup(s))"):format(slotIndex, #container.slots)
    end
    local entry = container.slots[slotIndex]
    if type(entry) ~= "table" or type(entry.snapshot) ~= "table" then
        return false, ("backup slot %d is empty or corrupt"):format(slotIndex)
    end

    for k in pairs(profile) do
        if k ~= BACKUP_KEY then
            profile[k] = nil
        end
    end
    for k, v in pairs(entry.snapshot) do
        profile[k] = DeepCloneExcluding(v, BACKUP_EXCLUDED_KEYS)
    end
    -- After restore, the profile is back at its pre-migration version. The
    -- backup container is preserved so the user can restore other slots.
    return true, entry
end

local function PruneBackupContainer(profile)
    local existing = profile[BACKUP_KEY]
    local container = GetBackupContainer(profile)
    if not container or type(container.slots) ~= "table" then
        if existing ~= nil then
            profile[BACKUP_KEY] = nil
            return true
        end
        return false
    end

    local changed = existing ~= profile[BACKUP_KEY]
    local prunedSlots = {}
    for _, entry in ipairs(container.slots) do
        local snapshot = entry and entry.snapshot
        if type(snapshot) == "table" then
            for excludedKey in pairs(BACKUP_EXCLUDED_KEYS) do
                if snapshot[excludedKey] ~= nil then
                    snapshot[excludedKey] = nil
                    changed = true
                end
            end
            if #prunedSlots < MAX_BACKUP_SLOTS then
                prunedSlots[#prunedSlots + 1] = entry
            else
                changed = true
            end
        else
            changed = true
        end
    end

    if #prunedSlots == 0 then
        changed = changed or profile[BACKUP_KEY] ~= nil
        profile[BACKUP_KEY] = nil
    else
        changed = changed or #container.slots ~= #prunedSlots
        container.slots = prunedSlots
        profile[BACKUP_KEY] = container
    end

    return changed
end

-- Returns the full backup container ({slots = {...}}) for inspection.
-- Lazily upgrades legacy single-slot shape on read.
function Migrations.GetBackupInfo(profile)
    if type(profile) ~= "table" then return nil end
    PruneBackupContainer(profile)
    return GetBackupContainer(profile)
end

Migrations.MAX_BACKUP_SLOTS = MAX_BACKUP_SLOTS

---------------------------------------------------------------------------
-- v33: third-party "Anchor To" alias remap.
--
-- BigWigs / DandersFrames / AbilityTimeline historically built their
-- "Anchor To" dropdown from a per-integration flat list with four legacy
-- alias values that aren't in the canonical anchor-target registry:
--   essential  -> cdmEssential
--   utility    -> cdmUtility
--   primary    -> primaryPower
--   secondary  -> secondaryPower
-- The integrations now route through the same registry-driven categorized
-- + searchable widget the rest of QUI uses, which only knows the canonical
-- keys. Rewrite saved values so they round-trip through the new dropdown.
-- The legacy alias arms in each integration's GetAnchorFrame still resolve
-- unmigrated values as a safety net.
---------------------------------------------------------------------------
local THIRD_PARTY_ANCHOR_ALIAS_MAP = {
    essential = "cdmEssential",
    utility = "cdmUtility",
    primary = "primaryPower",
    secondary = "secondaryPower",
}

local THIRD_PARTY_ANCHOR_DB_KEYS = { "bigWigs", "dandersFrames", "abilityTimeline" }

local function RemapThirdPartyAnchorAliases(profile)
    if type(profile) ~= "table" then return end
    for _, dbKey in ipairs(THIRD_PARTY_ANCHOR_DB_KEYS) do
        local section = profile[dbKey]
        if type(section) == "table" then
            for entryKey, cfg in pairs(section) do
                if type(cfg) == "table" and type(cfg.anchorTo) == "string" then
                    local mapped = THIRD_PARTY_ANCHOR_ALIAS_MAP[cfg.anchorTo]
                    if mapped then
                        MigLog("v33 RemapThirdPartyAnchorAliases: %s.%s.anchorTo %s -> %s",
                            dbKey, tostring(entryKey), cfg.anchorTo, mapped)
                        cfg.anchorTo = mapped
                    end
                end
            end
        end
    end
end

-- Clear every key on a profile table in place, preserving only the migration
-- backup container so a floored profile can still be rolled back. Used by the
-- pre-3.5.11 floor in RunOnProfile before flagging a starter-profile reseed.
local function WipeProfileData(profile)
    for k in pairs(profile) do
        if k ~= BACKUP_KEY then
            profile[k] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Entry point: Run all profile migrations
---------------------------------------------------------------------------
--
-- Run the full migration pipeline against a single raw profile table.
-- Accepts either db.profile (AceDB proxy) or a raw db.sv.profiles[name]
-- entry. Operates only on explicit user data — never relies on AceDB
-- default-merging, so it's safe to call against raw tables that have
-- never been touched by AceDB.
--
-- Each migration is gated by a linear schema version. A profile's
-- `_schemaVersion` records the last version it was migrated through;
-- on upgrade, gates v(stored+1)..v(CURRENT) run in order. Each migration
-- function retains an internal data-shape guard so that running it twice
-- (e.g. on a profile already at CURRENT that re-enters the pipeline from
-- a profile import) is a no-op.
--
-- Historical note: prior to the rewrite, CURRENT_SCHEMA_VERSION was a
-- constant `1` that never matched the actual number of migrations added
-- over time. Profiles from the 3.0 – 3.1.4 era all have `_schemaVersion=1`
-- stamped regardless of which migrations had actually run; they are
-- treated as v1 here and all post-v1 gates re-run against them, relying
-- on each migration's internal shape guards to no-op on already-migrated
-- data.
function Migrations.RunOnProfile(profile)
    if type(profile) ~= "table" then return false end

    local cleanupChanged = PruneBackupContainer(profile)

    local stored = tonumber(profile._schemaVersion) or 0

    -- === Pre-3.5.11 floor ===
    -- A profile stored below MIN_SUPPORTED_SCHEMA predates 3.5.11 and the
    -- incremental migrations that would upgrade it (v2–v31) were removed in
    -- 4.0. Rather than leave it half-migrated, snapshot it, wipe it, and flag
    -- it for a Starter Profile reseed at login — the reseed lives in
    -- QUI_Options (where the preset string + import engine load) and prompts a
    -- reload. Fresh profiles (stored==0) are explicitly NOT floored: they take
    -- the normal fresh-init path through the gates below.
    if stored > 0 and stored < MIN_SUPPORTED_SCHEMA then
        MigLog("RunOnProfile: stored=%d below floor %d — backup + reseed",
            stored, MIN_SUPPORTED_SCHEMA)
        CreateBackup(profile, stored)
        WipeProfileData(profile)
        profile._needsStarterReseed = true
        profile._schemaVersion = CURRENT_SCHEMA_VERSION
        return true
    end

    -- Flag fresh profiles for the late EditMode action bar import. v19
    -- (the removed MigrateAnchoringV1) was the first migration to write
    -- frameAnchoring data; a fresh profile (stored==0) has none yet, so the
    -- late EditMode import should run for it. The flag is read at PLAYER_LOGIN
    -- by Migrations.RunLate after EditModeManagerFrame loads. Profiles at v31+
    -- already carry anchoring data and never get the flag, so RunLate stamps
    -- their sentinel and skips the import loop.
    if stored == 0 and not profile._abPositionsImportedFromEditMode then
        profile._needsLateAbImport = true
    end

    do
        local faCount = 0
        if type(profile.frameAnchoring) == "table" then
            for _ in pairs(profile.frameAnchoring) do faCount = faCount + 1 end
        end
        MigLog("=== RunOnProfile: stored=%d current=%d faEntries=%d ===",
            stored, CURRENT_SCHEMA_VERSION, faCount)
        if type(profile.frameAnchoring) == "table" and profile.frameAnchoring.debuffFrame then
            local d = profile.frameAnchoring.debuffFrame
            MigLog("  pre-mig debuffFrame: parent=%s point=%s ofs=%s/%s enabled=%s",
                tostring(d.parent), tostring(d.point), tostring(d.offsetX), tostring(d.offsetY), tostring(d.enabled))
        else
            MigLog("  pre-mig debuffFrame: NIL (no raw entry)")
        end
    end

    -- ResetCastbarPreviewModes is a runtime sanity reset, NOT a migration —
    -- it clears the transient previewMode flag on every load so a preview
    -- left enabled in a prior session never persists. Always runs.
    ResetCastbarPreviewModes(profile)

    if stored >= CURRENT_SCHEMA_VERSION then
        MigLog("RunOnProfile: stored >= current, NOTHING TO DO")
        return cleanupChanged
    end

    -- Skip the backup for empty/fresh profiles — there's nothing worth
    -- rolling back to. A profile is "fresh" if it has no keys other than
    -- internal version stamps.
    local hasUserData = false
    for k in pairs(profile) do
        if k ~= "_schemaVersion" and k ~= "_defaultsVersion" and k ~= BACKUP_KEY then
            hasUserData = true
            break
        end
    end

    -- Snapshot BEFORE any gate runs, so a failed/corrupt migration can
    -- always be rolled back to the pre-pipeline state.
    if hasUserData then
        CreateBackup(profile, stored)
    end

    -- === Pre-3.5.11 migrations (v2–v31) removed in 4.0 ===
    -- These incremental steps were deleted; profiles older than
    -- MIN_SUPPORTED_SCHEMA are floored at the top of this function (backed up,
    -- wiped, and flagged for a starter-profile reseed), so they never reach
    -- the chain below. Any profile that does reach here is at v31 or newer and
    -- only needs the 4.0-beta-era migrations starting at v32.

    -- v32: V2 settings branch consolidated migration. Nine discrete
    -- transforms run sequentially behind one gate (V2 branch never
    -- shipped past v31, so intermediate version steps were collapsed).
    -- Order matters — see version log for what each function does.
    -- (a-d) finalize containers and per-spec storage; (e) stamps shape
    -- and entry.kind on the finalized containers; (f-i) apply field-
    -- level repairs against the already-shaped data.
    if stored < 32 then
        MigrateCustomTrackersToContainers(profile)
        RemovePartyTrackerData(profile)
        FinalizeCustomBarContainers(profile)
        FinalizeLegacyTrackerSpecState(profile)
        MigrateContainerShapeAndEntryKind(profile)
        RepairCustomTrackerCDMBarFidelity(profile)
        Migrations.RepairCustomTrackerSpecStorage(profile, _currentGlobalDB)
        RepairResourceBarSettings(profile)
        NormalizeCustomCDMBarCompatibility(profile)
    end

    -- v33: rewrite legacy "Anchor To" alias values stored on third-party
    -- integrations to canonical registry keys so the unified categorized
    -- + searchable dropdown can render and round-trip them.
    if stored < 33 then RemapThirdPartyAnchorAliases(profile) end

    -- v34: replace per-unit onlyMyDebuffs checkbox with debuffFilter.modifiers.PLAYER
    if stored < 34 then MigrateUnitFrameAuraFilters(profile) end

    -- v35: Phase C edit-box history schema initialization. The prior
    -- session-only arrow-key history was in-memory and not persisted, so
    -- there is nothing on the profile to migrate from. This entry exists
    -- to document the schema bump and reserve the version for any future
    -- post-version logic that needs to run. Per-character storage is
    -- reached via QUI.db.char.chat.editboxHistory (not the profile);
    -- editbox_history.lua's getStore() lazily initializes it on first
    -- capture or recall.
    if stored < 35 then
        -- intentionally empty
    end

    -- v36: split single PandemicEnabled toggle per viewer into separate
    -- Debuff/Buff toggles, copying old value to both to preserve behavior.
    if stored < 36 then SplitPandemicByAuraType(profile) end

    -- v37: Retire the damage meter skinner module's saved keys. The skinner
    -- was deleted in favor of the native QUI damage meter (modules/damage_meter/).
    -- Defunct keys must be removed because the skinner's `enabled` key was
    -- being pushed to the damageMeterEnabled CVar, re-showing Blizzard's
    -- meter despite the native module's suppression.
    if stored < 37 then RetireSkinDamageMeter(profile) end

    -- v38: Damage meter rows are now scrollable; the hard cap setting was
    -- removed. Drop the legacy key from saved window entries.
    if stored < 38 then DropDamageMeterMaxVisibleRows(profile) end

    -- v39: Replace the two-toggle border color model with an explicit enum.
    if stored < 39 then MigrateBorderColorSource(profile) end

    -- v40: Roll the per-module border color SOURCE enum out to the remaining
    -- in-scope modules via Helpers.BorderRegistry, preserving the current look
    -- (class/theme) and defaulting to "custom" so existing profiles never flip
    -- to the new "inherit" default. Fresh installs are stamped at the current
    -- version and skip this gate. No-op until later tasks populate the registry.
    if stored < 40 then MigrateBorderColoring(profile) end

    -- v41: Purge chat keys orphaned by the chat takeover (pure deletion).
    if stored < 41 then PurgeOrphanedChatKeys(profile) end

    -- v42: wrap flat customDisplay into the multi-window array.
    if stored < 42 then MigrateCustomDisplayWindows(profile) end

    -- v43: force the five legacy per-profile module master-flags to true so a
    -- stale false can't silently disable a module whose addon row is on. For the
    -- active profile, an explicit false is first reflected to the addon layer.
    if stored < 43 then RetireModuleMasterFlags(profile) end

    -- v44: decouple chat sender realm display from channelShorten — preserve the
    -- shown-realm look for profiles that had channel-shortening explicitly off.
    if stored < 44 then MigrateChatRealmNames(profile) end

    -- v45: chat window position becomes frameAnchoring-only (single store);
    -- fold legacy windows[i].position in and delete it.
    if stored < 45 then MigrateChatWindowPositionsToFrameAnchoring(profile) end

    -- v46: collapse the three legacy group-frame aura tables (flat auras
    -- filter strips, pinnedAuras, auraIndicators) into auras.elements per
    -- party/raid context. Inlined (rather than a dedicated file-scope helper)
    -- so it adds no new upvalue to this closure, which already sits at the
    -- Lua 5.1 60-upvalue ceiling. `Migrations` is already an upvalue here.
    if stored < 46 and type(profile.quiGroupFrames) == "table" then
        local gf = profile.quiGroupFrames
        if type(gf.party) == "table" then Migrations.MigrateUnifiedAuras_Context(gf.party) end
        if type(gf.raid)  == "table" then Migrations.MigrateUnifiedAuras_Context(gf.raid) end
    end

    if type(profile.frameAnchoring) == "table" and profile.frameAnchoring.debuffFrame then
        local d = profile.frameAnchoring.debuffFrame
        MigLog("post-mig debuffFrame: parent=%s point=%s ofs=%s/%s enabled=%s",
            tostring(d.parent), tostring(d.point), tostring(d.offsetX), tostring(d.offsetY), tostring(d.enabled))
    else
        MigLog("post-mig debuffFrame: NIL (entry removed)")
    end
    if type(profile.frameAnchoring) == "table" and profile.frameAnchoring.bar1 then
        local b = profile.frameAnchoring.bar1
        MigLog("post-mig bar1: parent=%s point=%s ofs=%s/%s enabled=%s",
            tostring(b.parent), tostring(b.point), tostring(b.offsetX), tostring(b.offsetY), tostring(b.enabled))
    else
        MigLog("post-mig bar1: NIL (entry removed)")
    end

    -- v47: drop the Blizzard-removed "IMPORTANT" AuraFilters flag from stored
    -- unit-frame filter state (12.0.7 removed it from Enum AuraFilters).
    if stored < 47 then ScrubRemovedImportantAuraFilter(profile) end

    profile._schemaVersion = CURRENT_SCHEMA_VERSION
    return true
end

-- Run migrations across every stored profile in the database. Previously
-- this function only touched db.profile (the active profile of the logged-
-- in character), leaving all other profiles frozen in their pre-migration
-- state until the user happened to log in on the matching character. Now
-- it iterates db.sv.profiles and migrates each one.
--
-- For stub db objects (e.g. profile import path) without db.sv.profiles,
-- falls back to migrating db.profile alone.
function Migrations.Run(db)
    if not db then return false end

    -- Expose db.global to migrations that need cross-profile / global
    -- reads (e.g. v32's legacy spec-tracker port). Cleared on exit so
    -- individual RunOnProfile calls from other entry points (profile
    -- import, profile switch) get nil and handle its absence gracefully.
    _currentGlobalDB = db.global

    -- Pin the active profile's raw sv table so RetireModuleMasterFlags (v43)
    -- can detect which profile is active and carry an explicit false to the
    -- addon layer. db.keys.profile is the profile name key; db.sv.profiles
    -- maps that name to the raw table iterated below. Cleared on exit so
    -- standalone RunOnProfile calls (profile import/switch) get nil and
    -- degrade to force-true only.
    local activeProfileName = db.keys and db.keys.profile
    local sv = db.sv
    _currentActiveProfile = (activeProfileName and sv and sv.profiles)
        and sv.profiles[activeProfileName] or nil

    local profiles = sv and sv.profiles
    if type(profiles) == "table" then
        local any = false
        for _, profile in pairs(profiles) do
            if Migrations.RunOnProfile(profile) then
                any = true
            end
        end

        local pins = ns.Settings and ns.Settings.Pins
        if pins and type(pins.IsAutoApplySuppressed) == "function"
            and not pins:IsAutoApplySuppressed() then
            if type(pins.PrepareActiveProfileForApply) == "function" then
                pins:PrepareActiveProfileForApply(db)
            end
            if type(pins.ApplyAllForDB) == "function" then
                pins:ApplyAllForDB(db)
            end
        end

        _currentGlobalDB     = nil
        _currentActiveProfile = nil
        return any
    end

    local result = Migrations.RunOnProfile(db.profile)

    local pins = ns.Settings and ns.Settings.Pins
    if pins and type(pins.IsAutoApplySuppressed) == "function"
        and not pins:IsAutoApplySuppressed() then
        if type(pins.PrepareActiveProfileForApply) == "function" then
            pins:PrepareActiveProfileForApply(db)
        end
        if type(pins.ApplyAllForDB) == "function" then
            pins:ApplyAllForDB(db)
        end
    end

    _currentGlobalDB     = nil
    _currentActiveProfile = nil
    return result
end
