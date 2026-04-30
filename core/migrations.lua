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

---------------------------------------------------------------------------
-- Schema version history
---------------------------------------------------------------------------
-- v0  = unknown / fresh install / 2.55 and earlier (pre-modern data model)
-- v1  = legacy "always 1" stamp (3.0 – 3.1.4) — treated as v0 by the rewrite
-- v2  = MigrateDatatextSlots                       (3.0)
-- v3  = MigratePerSlotSettings                     (3.0)
-- v4  = MigrateMasterTextColors                    (3.0)
-- v5  = MigrateChatEditBox                         (3.0)
-- v6  = MigrateCooldownSwipeV2                     (3.0)
-- v7  = MigrateCastBars                            (3.0)
-- v8  = MigrateUnitFrames                          (3.0)
-- v9  = MigrateSelfFirst + CleanOrphanKeys         (3.0)
-- v10 = Legacy 2.55 mainline anchor rebuild        (2.55 only)
-- v11 = EnsureThemeStorage                         (3.0/3.1)
-- v12 = MigrateLegacyLootSettings                  (3.0)
-- v13 = EnsureCraftingOrderIndicator               (minimap indicator default flip)
-- v14 = MigrateToShowLogic (cdm + unitframes)      (3.0 hide → show)
-- v15 = MigrateGroupFrameContainers                (3.0 party/raid split)
-- v16 = NormalizeAuraIndicators                    (3.0 shape normalize)
-- v17 = NormalizeEngines                           (3.0 drop legacy engine keys)
-- v18 = NormalizeMinimapSettings                   (2.55 position array → FA)
-- v19 = MigrateAnchoringV1                         (2.55 anchoring + castbar anchor)
-- v20 = MigrateAnchoringV2                         (3.0 mplusTimer/tooltip/brez legacy offsets)
-- v21 = MigrateAnchoringV3                         (3.1 readyCheck/loot/alerts/bars position)
-- v22 = MigrateNCDMContainers                      (3.0 ncdm.containers schema)
-- v23 = Re-run PruneLegacyPlaceholderAnchors with `enabled` whitelisted
--       (3.1.5: ghost FA entries with enabled=false survived earlier prune
--        passes because the enabled flag prevented placeholder detection;
--        re-running cleans them up so AceDB defaults take over)
-- v24 = RepairDisabledAnchorsWithStaleCornerPoints
--       (3.1.5: SavePendingPosition's free-position branch failed to reset
--        point/relative when existingParent == "disabled". Frames that had
--        been corner-converted (TOPRIGHT/TOPRIGHT) before being unanchored
--        ended up with CENTER-based offsets stored against TOPRIGHT anchor
--        points, teleporting them off-screen. Repair: detect entries where
--        parent="disabled" and point/relative are non-CENTER, normalize
--        them back to CENTER/CENTER preserving the offsets.)
-- v25 = Re-run RepairDisabledStaleCornerEntries
--       (3.1.5: a separate bug in buffborders.lua LayoutIcons was writing
--        the runtime corner-conversion BACK to the DB on every layout pass,
--        re-corrupting any entry that v24 repaired. The buffborders bug is
--        fixed in this same release; this gate re-runs the repair against
--        profiles that already migrated past v24 with re-corrupted data.
--        v25 also handles the AceDB-default-stripped variant: entries
--        where point=nil but relative is a corner string. AceDB strips
--        point="TOPRIGHT" on save because it matches the default for
--        debuffFrame, leaving only `relative="TOPRIGHT"` as the buggy
--        fingerprint in raw SV.)
-- v26 = Add growAnchor field to buff/debuff/auraBar FA entries
--       (3.1.5 Phase 2: split icon-grow direction from container anchor.
--        Existing corner-anchored entries get growAnchor = entry.point so
--        the new ApplyFrameAnchor growAnchor branch interprets them as
--        already-corner-anchored. Entries that v24/v25 normalized to
--        CENTER/CENTER get growAnchor derived from buffBorders config.)
-- v27 = RestoreChainedDefaultAnchors
--       (3.1.5: MigrateAnchoringV2's MigrateOffsets unconditionally pinned
--        legacy 2.55 inline-offset frames to parent="screen", which
--        clobbered the chained-default parents for brezCounter (→
--        combatTimer), combatTimer (→ bar3), and petWarning (→ playerFrame).
--        Detect FA entries that exactly match the legacy MigrateOffsets
--        shape and delete them so AceDB defaults restore the chain. Also
--        patches MigrateOffsets going forward to skip these keys.)
-- v28 = RestoreMplusTimerChainedDefault
--       (3.1.5: same root cause as v27, but for MigrateAnchoringV2's
--        mplusTimer branch — it pinned the timer to parent="screen" from
--        legacy `profile.mplusTimer.position`, clobbering the chained
--        partyFrames default. v27's RestoreChainedDefaultAnchors couldn't
--        catch it because IsLegacyMigrateOffsetsEntry requires point=CENTER
--        and the V2 mplusTimer entry inherits the user's saved point. v28
--        uses a relaxed shape check (parent=screen, sizeStable=true, only
--        the 6 V2 fields) and also patches MigrateAnchoringV2 to skip the
--        mplusTimer write going forward.)
-- v29 = RestorePowerBarModulePositioning
--       (3.1.6: older 3.x profiles can carry raw frameAnchoring entries for
--        primaryPower / secondaryPower that still match the seeded defaults.
--        Those entries make the resource bars look explicitly anchored, which
--        bypasses resourcebars.lua's swap / quick-position logic. Delete only
--        entries that still match the seeded defaults so the power-bar module
--        regains ownership; real user customizations stay intact.)
-- v30 = SplitGroupAuraDurationText
--       (3.1.6: replace the shared group-frame aura duration text toggle with
--        separate buff/debuff toggles. Existing profiles inherit the old
--        shared value into both new keys when it was explicitly saved.)
-- v31 = EnsureGroupAuraDurationTextStyle
--       (3.1.6: add per-kind group-frame aura duration text font, color,
--        anchor, and offset settings. Existing profiles inherit the old shared
--        duration font size and time-based color toggle.)
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
--
-- When adding a new migration: bump CURRENT_SCHEMA_VERSION, add it to the
-- linear gate chain in RunOnProfile, and document the version above.
---------------------------------------------------------------------------
local CURRENT_SCHEMA_VERSION = 32

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

-- Helper: set key in target only if target[k] is nil (conservative merge)
local function SetIfNil(target, key, value)
    if value ~= nil and target[key] == nil then
        target[key] = value
    end
end

-- Helper: ensure a sub-table exists and merge into it conservatively
local function EnsureSubTable(target, key)
    if type(target[key]) ~= "table" then
        target[key] = {}
    end
    return target[key]
end

---------------------------------------------------------------------------
-- 1. Data format migrations (restructure raw data first)
---------------------------------------------------------------------------

-- Migrate legacy datatext toggles to slot-based config
local function MigrateDatatextSlots(dt)
    if not dt then return end
    if dt.slots then return end  -- Already migrated

    -- Build slots from legacy flags
    dt.slots = {}

    -- Priority order: time, friends, guild (matching old composite order)
    if dt.showTime then table.insert(dt.slots, "time") end
    if dt.showFriends then table.insert(dt.slots, "friends") end
    if dt.showGuild then table.insert(dt.slots, "guild") end

    -- Pad to 3 slots with empty strings
    while #dt.slots < 3 do
        table.insert(dt.slots, "")
    end
end

-- Migrate global shortLabels to per-slot configuration
local function MigratePerSlotSettings(dt)
    if not dt then return end
    if dt.slot1 then return end  -- Already migrated

    -- Get global shortLabels value (from previous implementation)
    local globalShortLabels = dt.shortLabels or false

    -- Create per-slot configs with inherited global setting
    dt.slot1 = { shortLabel = globalShortLabels, xOffset = 0, yOffset = 0 }
    dt.slot2 = { shortLabel = globalShortLabels, xOffset = 0, yOffset = 0 }
    dt.slot3 = { shortLabel = globalShortLabels, xOffset = 0, yOffset = 0 }
end

-- Migrate legacy classColorText to new master text color toggles
local function MigrateMasterTextColors(general)
    if not general then return end

    -- If legacy classColorText was enabled, migrate to new master toggles
    if general.classColorText == true and general.masterColorNameText == nil then
        general.masterColorNameText = true
        general.masterColorHealthText = true
        -- Leave power/castbar/ToT as false (new features not covered by legacy toggle)
    end

    -- Initialize any nil values to false (for fresh profiles or profiles without legacy toggle)
    if general.masterColorNameText == nil then general.masterColorNameText = false end
    if general.masterColorHealthText == nil then general.masterColorHealthText = false end
    if general.masterColorPowerText == nil then general.masterColorPowerText = false end
    if general.masterColorCastbarText == nil then general.masterColorCastbarText = false end
    if general.masterColorToTText == nil then general.masterColorToTText = false end
end

-- Migrate chat.styleEditBox boolean to chat.editBox table
local function MigrateChatEditBox(chat)
    if not chat then return end
    if chat.editBox then return end  -- Already migrated

    -- Create editBox table from legacy styleEditBox boolean
    chat.editBox = {
        enabled = chat.styleEditBox ~= false,  -- Default true if nil or true
        bgAlpha = 0.25,
        bgColor = {0, 0, 0},
    }

    -- Remove legacy key
    chat.styleEditBox = nil
end

-- Migrate legacy cooldownSwipe (hideEssential/hideUtility) to new 3-toggle system.
-- Idempotency: gated externally by schema version v6; internally by the absence
-- of the legacy hide* keys. Safe to call on already-migrated data.
local function MigrateCooldownSwipeV2(profile)
    if not profile then return end
    if not profile.cooldownSwipe then profile.cooldownSwipe = {} end

    local cs = profile.cooldownSwipe
    -- Strip legacy sentinel from any 3.1.x profile that still carries it.
    cs.migratedToV2 = nil

    local hadHideEssential = cs.hideEssential == true
    local hadHideUtility = cs.hideUtility == true
    local hadHideBuffSwipe = profile.cooldownManager and profile.cooldownManager.hideSwipe == true

    -- Data-shape guard: if none of the legacy keys exist and the new-style
    -- show* keys already exist, there's nothing to migrate.
    if not (hadHideEssential or hadHideUtility or hadHideBuffSwipe)
        and cs.hideEssential == nil and cs.hideUtility == nil
        and cs.showBuffSwipe ~= nil then
        return
    end

    if hadHideEssential or hadHideUtility or hadHideBuffSwipe then
        cs.showBuffSwipe = true
        cs.showGCDSwipe = false       -- Hide GCD (what most users wanted)
        cs.showCooldownSwipe = true   -- Show actual cooldowns
    elseif cs.showBuffSwipe == nil then
        cs.showBuffSwipe = true
        cs.showGCDSwipe = true
        cs.showCooldownSwipe = true
    end

    cs.hideEssential = nil
    cs.hideUtility = nil
    if profile.cooldownManager then
        profile.cooldownManager.hideSwipe = nil
    end
end

-- Migrate legacy top-level castBar/targetCastBar/focusCastBar to quiUnitFrames.*.castbar
local CASTBAR_MIGRATION_MAP = {
    castBar       = { "quiUnitFrames", "player",  "castbar" },
    targetCastBar = { "quiUnitFrames", "target",  "castbar" },
    focusCastBar  = { "quiUnitFrames", "focus",   "castbar" },
}

local CASTBAR_DIRECT_KEYS = {
    "enabled", "bgColor", "color", "height",
    "showIcon", "width",
}

local CASTBAR_RENAMED_KEYS = {
    textSize = "fontSize",
}

local CASTBAR_POSITION_KEYS = { "offsetX", "offsetY" }

local function MigrateCastBars(profile)
    if not profile then return end

    for oldKey, path in pairs(CASTBAR_MIGRATION_MAP) do
        local old = profile[oldKey]
        if type(old) ~= "table" then
            -- Nothing to migrate for this cast bar
        else
            -- Ensure target table path exists
            local container = profile
            for i = 1, #path - 1 do
                if type(container[path[i]]) ~= "table" then
                    container[path[i]] = {}
                end
                container = container[path[i]]
            end
            local target = container[path[#path]]
            if type(target) ~= "table" then
                target = {}
                container[path[#path]] = target
            end

            -- Only migrate into keys that are still nil (don't overwrite new-style data)
            for _, k in ipairs(CASTBAR_DIRECT_KEYS) do
                if old[k] ~= nil and target[k] == nil then
                    target[k] = old[k]
                end
            end
            for oldName, newName in pairs(CASTBAR_RENAMED_KEYS) do
                if old[oldName] ~= nil and target[newName] == nil then
                    target[newName] = old[oldName]
                end
            end

            -- Position offsets always migrate from legacy (user's actual screen placement)
            for _, k in ipairs(CASTBAR_POSITION_KEYS) do
                if old[k] ~= nil then
                    target[k] = old[k]
                end
            end

            -- Remove the legacy key
            profile[oldKey] = nil
        end
    end
end

-- Migrate legacy unitFrames table to quiUnitFrames
-- The old format used PascalCase (General, Frame.Width, Tags.Health.FontSize)
-- while the new format uses flat camelCase (width, healthFontSize, showName).
local UNIT_FRAME_UNITS = { "player", "target", "targettarget", "pet", "focus", "boss" }

local function MigrateUnitFramesGeneral(oldGeneral, newGeneral)
    if type(oldGeneral) ~= "table" then return end

    SetIfNil(newGeneral, "font", oldGeneral.Font)
    SetIfNil(newGeneral, "fontOutline", oldGeneral.FontFlag)

    if type(oldGeneral.DarkMode) == "table" then
        local dm = oldGeneral.DarkMode
        SetIfNil(newGeneral, "darkMode", dm.Enabled)
        SetIfNil(newGeneral, "darkModeBgColor", dm.BackgroundColor)
        SetIfNil(newGeneral, "darkModeHealthColor", dm.ForegroundColor)
        if dm.UseSolidTexture ~= nil and newGeneral.darkModeOpacity == nil then
            newGeneral.darkModeOpacity = 1
        end
    end

    if type(oldGeneral.FontShadows) == "table" then
        local fs = oldGeneral.FontShadows
        SetIfNil(newGeneral, "fontShadowColor", fs.Color)
        SetIfNil(newGeneral, "fontShadowOffsetX", fs.OffsetX)
        SetIfNil(newGeneral, "fontShadowOffsetY", fs.OffsetY)
    end

    if type(oldGeneral.CustomColors) == "table" then
        local cc = oldGeneral.CustomColors
        if type(cc.Reaction) == "table" then
            SetIfNil(newGeneral, "hostilityColorHostile", cc.Reaction[1])
            SetIfNil(newGeneral, "hostilityColorNeutral", cc.Reaction[4])
            SetIfNil(newGeneral, "hostilityColorFriendly", cc.Reaction[5])
        end
    end
end

local function MigrateUnitFrameUnit(oldUnit, newUnit)
    if type(oldUnit) ~= "table" then return end

    SetIfNil(newUnit, "enabled", oldUnit.Enabled)

    if type(oldUnit.Frame) == "table" then
        local f = oldUnit.Frame
        SetIfNil(newUnit, "width", f.Width)
        SetIfNil(newUnit, "height", f.Height)
        SetIfNil(newUnit, "texture", f.Texture)
        SetIfNil(newUnit, "useClassColor", f.ClassColor)
        SetIfNil(newUnit, "useHostilityColor", f.ReactionColor)
        SetIfNil(newUnit, "offsetX", f.XPosition)
        SetIfNil(newUnit, "offsetY", f.YPosition)
    end

    if type(oldUnit.Tags) == "table" then
        if type(oldUnit.Tags.Health) == "table" then
            local h = oldUnit.Tags.Health
            SetIfNil(newUnit, "showHealth", h.Enabled)
            SetIfNil(newUnit, "healthFontSize", h.FontSize)
            SetIfNil(newUnit, "healthAnchor", h.AnchorFrom)
            SetIfNil(newUnit, "healthOffsetX", h.OffsetX)
            SetIfNil(newUnit, "healthOffsetY", h.OffsetY)
            SetIfNil(newUnit, "healthTextColor", h.Color)
            if h.DisplayPercent ~= nil and newUnit.showHealthPercent == nil then
                newUnit.showHealthPercent = h.DisplayPercent
            end
        end

        if type(oldUnit.Tags.Name) == "table" then
            local n = oldUnit.Tags.Name
            SetIfNil(newUnit, "showName", n.Enabled)
            SetIfNil(newUnit, "nameFontSize", n.FontSize)
            SetIfNil(newUnit, "nameAnchor", n.AnchorFrom)
            SetIfNil(newUnit, "nameOffsetX", n.OffsetX)
            SetIfNil(newUnit, "nameOffsetY", n.OffsetY)
            SetIfNil(newUnit, "nameTextColor", n.Color)
            SetIfNil(newUnit, "nameTextUseClassColor", n.ColorByClass)
        end

        if type(oldUnit.Tags.Power) == "table" then
            local p = oldUnit.Tags.Power
            SetIfNil(newUnit, "showPowerText", p.Enabled)
            SetIfNil(newUnit, "powerTextFontSize", p.FontSize)
            SetIfNil(newUnit, "powerTextAnchor", p.AnchorFrom)
            SetIfNil(newUnit, "powerTextOffsetX", p.OffsetX)
            SetIfNil(newUnit, "powerTextOffsetY", p.OffsetY)
            SetIfNil(newUnit, "powerTextColor", p.Color)
        end
    end

    if type(oldUnit.PowerBar) == "table" then
        local pb = oldUnit.PowerBar
        SetIfNil(newUnit, "showPowerBar", pb.Enabled)
        SetIfNil(newUnit, "powerBarHeight", pb.Height)
        SetIfNil(newUnit, "powerBarUsePowerColor", pb.ColorByType)
        SetIfNil(newUnit, "powerBarColor", pb.FGColor)
    end

    if type(oldUnit.Absorb) == "table" then
        local absorbs = EnsureSubTable(newUnit, "absorbs")
        SetIfNil(absorbs, "enabled", oldUnit.Absorb.Enabled)
        SetIfNil(absorbs, "color", oldUnit.Absorb.Color)
    end
end

local function MigrateUnitFrames(profile)
    if not profile then return end

    local old = profile.unitFrames
    if type(old) ~= "table" then return end

    if type(profile.quiUnitFrames) ~= "table" then
        profile.quiUnitFrames = {}
    end
    local new = profile.quiUnitFrames

    SetIfNil(new, "enabled", old.enabled)

    if type(old.General) == "table" then
        local general = EnsureSubTable(new, "general")
        MigrateUnitFramesGeneral(old.General, general)
    end

    for _, unit in ipairs(UNIT_FRAME_UNITS) do
        if type(old[unit]) == "table" then
            local newUnit = EnsureSubTable(new, unit)
            MigrateUnitFrameUnit(old[unit], newUnit)
        end
    end

    if type(old.General) == "table" and type(old.General.CustomColors) == "table" then
        local customPower = old.General.CustomColors.Power
        if type(customPower) == "table" and profile.powerColors == nil then
            profile.powerColors = customPower
        end
    end

    -- Remove the legacy key
    profile.unitFrames = nil
end

-- Migrate selfFirst → partySelfFirst / raidSelfFirst
local function MigrateSelfFirst(profile)
    if not profile then return end
    local gf = profile.quiGroupFrames
    if not gf or gf.selfFirst == nil then return end

    if gf.partySelfFirst == nil then
        gf.partySelfFirst = gf.selfFirst
    end
    if gf.raidSelfFirst == nil then
        gf.raidSelfFirst = gf.selfFirst
    end
    gf.selfFirst = nil
end

-- Remove orphaned keys that no longer have runtime consumers
local ORPHAN_KEYS = { "cooldownManager", "trackerSystem", "nudgeAmount" }

local function CleanOrphanKeys(profile)
    if not profile then return end
    for _, key in ipairs(ORPHAN_KEYS) do
        if profile[key] ~= nil then
            profile[key] = nil
        end
    end
end

---------------------------------------------------------------------------
-- 2. Legacy profile detection & normalization
---------------------------------------------------------------------------

-- Explicit legacy-2.55 detection.
--
-- We no longer shape-sniff a dozen heuristics. The 2.55-era anchoring system
-- stored positions with an `enabled` flag on each `frameAnchoring` entry;
-- 3.0+ dropped that flag in favor of parent-chain entries. Presence of any
-- `frameAnchoring.<key>.enabled` value is a reliable 2.55 marker.
--
-- Called exactly once, from the v10 schema gate in RunOnProfile, for profiles
-- whose schema version is below v10. Fresh installs and 3.0+ upgraders return
-- false here and skip the legacy anchor rebuild entirely.
local function IsLegacy255Profile(profile)
    if type(profile) ~= "table" then return false end
    local fa = profile.frameAnchoring
    if type(fa) ~= "table" then return false end
    for _, entry in pairs(fa) do
        if type(entry) == "table" and entry.enabled ~= nil then
            return true
        end
    end
    return false
end

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

local function PruneLegacyPlaceholderAnchors(profile)
    if type(profile) ~= "table" or type(profile.frameAnchoring) ~= "table" then
        MigLog("PruneLegacyPlaceholderAnchors: skip — profile=%s frameAnchoring=%s",
            type(profile), type(profile and profile.frameAnchoring))
        return
    end

    local pruned, kept = 0, 0
    MigLog("PruneLegacyPlaceholderAnchors: scanning frameAnchoring")
    for key, entry in pairs(profile.frameAnchoring) do
        if key == "hudMinWidth" then
            -- skip
        elseif IsPlaceholderAnchorEntry(entry) then
            MigLog("  PRUNE %s (parent=%s, point=%s, ofs=%s/%s, enabled=%s)",
                tostring(key),
                tostring(entry.parent),
                tostring(entry.point),
                tostring(entry.offsetX),
                tostring(entry.offsetY),
                tostring(entry.enabled))
            profile.frameAnchoring[key] = nil
            pruned = pruned + 1
        else
            MigLog("  keep  %s (parent=%s, point=%s, ofs=%s/%s, enabled=%s)",
                tostring(key),
                tostring(entry.parent),
                tostring(entry.point),
                tostring(entry.offsetX),
                tostring(entry.offsetY),
                tostring(entry.enabled))
            kept = kept + 1
        end
    end
    MigLog("PruneLegacyPlaceholderAnchors done: pruned=%d kept=%d", pruned, kept)
end

-- Gated externally by schema version v10 (only runs once, only for legacy
-- 2.55 mainline profiles). Any stale `_legacyMainlineAnchorsRebuilt` sentinel
-- on 3.1.x profiles is scrubbed at the bottom of this function.
local function ResetLegacyAnchorsForRebuild(profile)
    if type(profile) ~= "table" then
        return
    end
    if type(profile.frameAnchoring) ~= "table" then
        profile.frameAnchoring = {}
    end

    local fa = profile.frameAnchoring
    -- Only clear entries that look like legacy 2.55 placeholders. A 3.0+
    -- shaped entry (one with a `parent` field set) was authored by the user
    -- via the modern layout system — preserve it even on profiles that
    -- IsLegacy255Profile flagged due to a stray `enabled` flag elsewhere.
    -- This mirrors the discriminator MigrateAnchoringV1 uses at the
    -- `hasParentField` branch.
    local function ClearAnchor(key)
        local entry = fa[key]
        if type(entry) == "table" and entry.parent ~= nil then
            return
        end
        fa[key] = nil
    end
    local function HasOffsets(sourceTable)
        if type(sourceTable) ~= "table" then
            return false
        end
        return sourceTable.offsetX ~= nil
            or sourceTable.offsetY ~= nil
            or sourceTable.xOffset ~= nil
            or sourceTable.yOffset ~= nil
    end

    local uf = profile.quiUnitFrames
    if type(uf) == "table" then
        if HasOffsets(uf.player) then ClearAnchor("playerFrame") end
        if HasOffsets(uf.target) then ClearAnchor("targetFrame") end
        if HasOffsets(uf.targettarget) then ClearAnchor("totFrame") end
        if HasOffsets(uf.focus) then ClearAnchor("focusFrame") end
        if HasOffsets(uf.pet) then ClearAnchor("petFrame") end
        if HasOffsets(uf.boss) then ClearAnchor("bossFrames") end

        if type(uf.player) == "table" and type(uf.player.castbar) == "table" then ClearAnchor("playerCastbar") end
        if type(uf.target) == "table" and type(uf.target.castbar) == "table" then ClearAnchor("targetCastbar") end
        if type(uf.focus) == "table" and type(uf.focus.castbar) == "table" then ClearAnchor("focusCastbar") end
    end

    local gf = profile.quiGroupFrames
    if type(gf) == "table" then
        if type(gf.position) == "table" then ClearAnchor("partyFrames") end
        if type(gf.raidPosition) == "table" then ClearAnchor("raidFrames") end
    end

    if type(profile.mplusTimer) == "table" and type(profile.mplusTimer.position) == "table" then ClearAnchor("mplusTimer") end
    if type(profile.tooltip) == "table" and type(profile.tooltip.anchorPosition) == "table" then ClearAnchor("tooltipAnchor") end
    if HasOffsets(profile.brzCounter) then ClearAnchor("brezCounter") end
    if HasOffsets(profile.combatTimer) then ClearAnchor("combatTimer") end
    if HasOffsets(profile.rangeCheck) then ClearAnchor("rangeCheck") end
    if HasOffsets(profile.actionTracker) then ClearAnchor("actionTracker") end
    if HasOffsets(profile.focusCastAlert) then ClearAnchor("focusCastAlert") end
    if HasOffsets(profile.petCombatWarning) then ClearAnchor("petWarning") end
    if HasOffsets(profile.raidBuffs) then ClearAnchor("missingRaidBuffs") end
    if HasOffsets(profile.totemBar) then ClearAnchor("totemBar") end
    if HasOffsets(profile.xpTracker) then ClearAnchor("xpTracker") end
    if HasOffsets(profile.skyriding) then ClearAnchor("skyriding") end
    if HasOffsets(profile.crosshair) then ClearAnchor("crosshair") end

    local gen = profile.general
    if type(gen) == "table" then
        if type(gen.readyCheckPosition) == "table" then ClearAnchor("readyCheck") end
        if type(gen.consumableFreePosition) == "table" then ClearAnchor("consumables") end
    end

    if type(profile.powerBarAltPosition) == "table" then ClearAnchor("powerBarAlt") end
    if type(profile.loot) == "table" and type(profile.loot.position) == "table" then ClearAnchor("lootFrame") end
    if type(profile.lootRoll) == "table" and type(profile.lootRoll.position) == "table" then ClearAnchor("lootRollAnchor") end

    local alerts = profile.alerts
    if type(alerts) == "table" then
        if type(alerts.alertPosition) == "table" then ClearAnchor("alertAnchor") end
        if type(alerts.toastPosition) == "table" then ClearAnchor("toastAnchor") end
        if type(alerts.bnetToastPosition) == "table" then ClearAnchor("bnetToastAnchor") end
    end

    local barsDB = profile.actionBars and profile.actionBars.bars
    if type(barsDB) == "table" then
        local barKeyMap = {
            pet = "petBar",
            stance = "stanceBar",
            microbar = "microMenu",
            bags = "bagBar",
        }
        -- Only the legacy 2.55 `position` field counts as a position source.
        -- See the matching comment in MigrateAnchoringV3 — `ownedPosition` is
        -- dead orphaned data on 3.x profiles and must not trigger ClearAnchor,
        -- which would yank a chained-default bar onto the screen-center seed.
        for dbKey, barData in pairs(barsDB) do
            if type(barData) == "table" and type(barData.position) == "table" then
                ClearAnchor(barKeyMap[dbKey] or dbKey)
            end
        end
        if HasOffsets(barsDB.extraActionButton) then ClearAnchor("extraActionButton") end
        if HasOffsets(barsDB.zoneAbility) then ClearAnchor("zoneAbility") end
    end

    profile._anchoringMigrationVersion = nil
    profile._legacyMainlineAnchorsRebuilt = nil
end

local LEGACY_MAINLINE_EDIT_MODE_BARS = {
    bar1 = 12,
    bar2 = 12,
    bar3 = 12,
    bar4 = 6,
    bar5 = 6,
    bar6 = 12,
    bar7 = 12,
    bar8 = 12,
}

local function LooksLikeSyntheticOwnedLayout(layout, expectedColumns)
    if type(layout) ~= "table" then
        return false
    end

    return (layout.orientation or "horizontal") == "horizontal"
        and (layout.columns or 12) == expectedColumns
        and (layout.iconCount or 12) == 12
        and layout.buttonSize == nil
        and layout.buttonSpacing == nil
        and (layout.growUp or false) == false
        and (layout.growLeft or false) == false
end

local function NormalizeLegacyActionBarLayouts(profile)
    local bars = profile and profile.actionBars and profile.actionBars.bars
    if type(bars) ~= "table" then
        return
    end

    local useEditModeFallback = false

    for barKey, expectedColumns in pairs(LEGACY_MAINLINE_EDIT_MODE_BARS) do
        local barData = bars[barKey]
        if type(barData) == "table" then
            local ownedLayout = rawget(barData, "ownedLayout")
            if ownedLayout == nil then
                useEditModeFallback = true
            elseif LooksLikeSyntheticOwnedLayout(ownedLayout, expectedColumns) then
                barData.ownedLayout = nil
                useEditModeFallback = true
            end
        end
    end

    if useEditModeFallback then
        profile._legacyMainlineUsesEditModeActionBars = true
    end
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

local DEFAULT_SKY_BLUE_ACCENT = { 0.376, 0.647, 0.980, 1 }

local function EnsureThemeStorage(profile)
    if type(profile) ~= "table" then
        return
    end
    if type(profile.general) ~= "table" then
        profile.general = {}
    end

    local general = profile.general
    local generalAccent = type(general.addonAccentColor) == "table" and general.addonAccentColor or nil
    local rootAccent = type(profile.addonAccentColor) == "table" and profile.addonAccentColor or nil

    if generalAccent then
        profile.addonAccentColor = CloneValue(generalAccent)
    elseif rootAccent then
        general.addonAccentColor = CloneValue(rootAccent)
    end

    local generalPreset = type(general.themePreset) == "string" and general.themePreset ~= "" and general.themePreset or nil
    local rootPreset = type(profile.themePreset) == "string" and profile.themePreset ~= "" and profile.themePreset or nil

    -- Older mainline profiles never had themePreset. If AceDB filled the new
    -- default preset into the root only, ignore that placeholder and prefer the
    -- legacy accent/class-color intent instead of forcing Sky Blue.
    if not generalPreset and rootPreset == "Sky Blue" then
        local accent = generalAccent or rootAccent
        if general.skinUseClassColor == true or (accent and not ColorsEqual(accent, DEFAULT_SKY_BLUE_ACCENT)) then
            rootPreset = nil
        end
    end

    if general.skinUseClassColor == true then
        generalPreset = "Class Colored"
        rootPreset = "Class Colored"
    elseif generalPreset then
        rootPreset = generalPreset
    elseif rootPreset then
        generalPreset = rootPreset
    end

    if generalPreset then
        general.themePreset = generalPreset
    end
    if rootPreset then
        profile.themePreset = rootPreset
    elseif profile.themePreset ~= nil and general.themePreset == nil then
        profile.themePreset = nil
    end
end

local function MigrateLegacyLootSettings(profile)
    if type(profile) ~= "table" or type(profile.general) ~= "table" then
        return
    end

    local general = profile.general
    local hadLegacyLootSettings = false
    if profile.loot == nil then profile.loot = {} end
    if profile.lootRoll == nil then profile.lootRoll = {} end
    if profile.lootResults == nil then profile.lootResults = {} end

    if general.skinLootWindow ~= nil then
        profile.loot.enabled = general.skinLootWindow
        general.skinLootWindow = nil
        hadLegacyLootSettings = true
    end

    if general.skinLootUnderMouse ~= nil then
        profile.loot.lootUnderMouse = general.skinLootUnderMouse
        general.skinLootUnderMouse = nil
        hadLegacyLootSettings = true
    end

    if general.skinLootHistory ~= nil then
        profile.lootResults.enabled = general.skinLootHistory
        general.skinLootHistory = nil
        hadLegacyLootSettings = true
    end

    if general.skinRollFrames ~= nil then
        profile.lootRoll.enabled = general.skinRollFrames
        general.skinRollFrames = nil
        hadLegacyLootSettings = true
    end

    if general.skinRollSpacing ~= nil then
        profile.lootRoll.spacing = general.skinRollSpacing
        general.skinRollSpacing = nil
        hadLegacyLootSettings = true
    end

    if hadLegacyLootSettings and profile.lootRoll.enabled == nil then
        profile.lootRoll.enabled = true
    end
end

-- Gated externally by schema version v13. This is a one-time default flip:
-- users who never touched `showCraftingOrder` get it set to true. Users who
-- explicitly set it to false must NOT have their choice overwritten. We
-- detect "untouched" as `== nil` (AceDB proxy returns nil for keys the user
-- never set, because there's no default for this key). Scrubs any stale
-- sentinel from 3.1.x profiles.
local function EnsureCraftingOrderIndicator(profile)
    if not profile then
        return
    end
    if not profile.minimap then
        profile.minimap = {}
    end
    profile.minimap._showCraftingOrderMigrated = nil
    if profile.minimap.showCraftingOrder == nil then
        profile.minimap.showCraftingOrder = true
    end
end

local function MigrateToShowLogic(visTable)
    if not visTable then return end

    if visTable.hideOutOfCombat then
        visTable.showInCombat = true
    end
    if visTable.hideWhenNotInGroup then
        visTable.showInGroup = true
    end
    if visTable.hideWhenNotInInstance then
        visTable.showInInstance = true
    end

    visTable.hideOutOfCombat = nil
    visTable.hideWhenNotInGroup = nil
    visTable.hideWhenNotInInstance = nil
end

local function MigrateGroupFrameContainers(profile)
    local gf = profile and profile.quiGroupFrames
    if not gf then
        return
    end

    local VISUAL_KEYS = {
        "general", "layout", "health", "power", "name", "absorbs", "healPrediction",
        "indicators", "healer", "classPower", "range", "auras",
        "privateAuras", "auraIndicators", "castbar", "portrait", "pets",
    }

    local needsMigration = false
    for _, key in ipairs(VISUAL_KEYS) do
        if gf[key] then
            needsMigration = true
            break
        end
    end
    if gf.partyLayout or gf.raidLayout then
        needsMigration = true
    end

    if needsMigration then
        if not gf.party then gf.party = {} end
        if not gf.raid then gf.raid = {} end

        for _, key in ipairs(VISUAL_KEYS) do
            if gf[key] then
                if not gf.party[key] then gf.party[key] = CloneValue(gf[key]) end
                if not gf.raid[key] then gf.raid[key] = CloneValue(gf[key]) end
                gf[key] = nil
            end
        end

        if gf.partyLayout then
            if not gf.party.layout then
                gf.party.layout = gf.partyLayout
            else
                for key, value in pairs(gf.partyLayout) do
                    if gf.party.layout[key] == nil then
                        gf.party.layout[key] = value
                    end
                end
            end
            gf.partyLayout = nil
        end

        if gf.raidLayout then
            if not gf.raid.layout then
                gf.raid.layout = gf.raidLayout
            else
                for key, value in pairs(gf.raidLayout) do
                    if gf.raid.layout[key] == nil then
                        gf.raid.layout[key] = value
                    end
                end
            end
            gf.raidLayout = nil
        end
    end

    if gf.dimensions then
        if not gf.party then gf.party = {} end
        if not gf.raid then gf.raid = {} end
        if not gf.party.dimensions then gf.party.dimensions = CloneValue(gf.dimensions) end
        if not gf.raid.dimensions then gf.raid.dimensions = CloneValue(gf.dimensions) end
        gf.dimensions = nil
    end

    if gf.spotlight then
        if not gf.raid then gf.raid = {} end
        if not gf.raid.spotlight then gf.raid.spotlight = gf.spotlight end
        gf.spotlight = nil
    end

    if gf.unifiedPosition ~= nil then
        if gf.unifiedPosition and gf.position and not gf.raidPosition then
            gf.raidPosition = {
                offsetX = gf.position.offsetX,
                offsetY = gf.position.offsetY,
            }
        end
        gf.unifiedPosition = nil
    end
end

local function NormalizeAuraIndicators(profile)
    if not profile or not profile.quiGroupFrames then return end
    local normalizeAuraIndicators = ns.Helpers and ns.Helpers.NormalizeAuraIndicatorConfig
    if not normalizeAuraIndicators then return end

    local gf = profile.quiGroupFrames
    if gf.party and gf.party.auraIndicators then
        normalizeAuraIndicators(gf.party.auraIndicators)
    end
    if gf.raid and gf.raid.auraIndicators then
        normalizeAuraIndicators(gf.raid.auraIndicators)
    end
end

local function NormalizeEngines(profile)
    if profile.tooltip and profile.tooltip.engine and profile.tooltip.engine ~= "default" then
        profile.tooltip.engine = "default"
    end

    if profile.ncdm and profile.ncdm.engine ~= nil then
        profile.ncdm.engine = nil
    end

    if profile.actionBars and profile.actionBars.engine == "classic" then
        profile.actionBars.engine = "owned"
    end
end

local function NormalizeMinimapSettings(profile)
    if not profile or not profile.minimap then
        return
    end

    if profile.minimap.scale ~= nil and profile.minimap.scale ~= 1.0 then
        profile.minimap.scale = 1.0
    end

    local mm = profile.minimap
    if mm.hideMicroMenu ~= nil then
        if not profile.actionBars then profile.actionBars = {} end
        if not profile.actionBars.bars then profile.actionBars.bars = {} end
        if not profile.actionBars.bars.microbar then profile.actionBars.bars.microbar = {} end
        if mm.hideMicroMenu then
            profile.actionBars.bars.microbar.enabled = false
        end
        mm.hideMicroMenu = nil
    end

    if mm.hideBagBar ~= nil then
        if not profile.actionBars then profile.actionBars = {} end
        if not profile.actionBars.bars then profile.actionBars.bars = {} end
        if not profile.actionBars.bars.bags then profile.actionBars.bars.bags = {} end
        if mm.hideBagBar then
            profile.actionBars.bars.bags.enabled = false
        end
        mm.hideBagBar = nil
    end

    -- Legacy 2.55 profiles stored minimap position as an array
    -- { [1]=point, [2]=relPoint, [3]=x, [4]=y }. Convert to a frameAnchoring
    -- entry so the user's custom minimap position survives the upgrade.
    if type(mm.position) == "table" and mm.position[1] and mm.position[3] then
        if not profile.frameAnchoring then profile.frameAnchoring = {} end
        if not profile.frameAnchoring.minimap then
            profile.frameAnchoring.minimap = {
                parent = "screen",
                point = tostring(mm.position[1]) or "CENTER",
                relative = tostring(mm.position[2]) or "CENTER",
                offsetX = tonumber(mm.position[3]) or 0,
                offsetY = tonumber(mm.position[4]) or 0,
                sizeStable = true,
            }
        end
        mm.position = nil
    end
end

---------------------------------------------------------------------------
-- 4. Anchoring migrations (depend on data being in final locations)
---------------------------------------------------------------------------
--
-- Split into three separate functions, one per schema version (v19/v20/v21).
-- Each function is gated externally by the linear schema version in
-- RunOnProfile; the old `profile._anchoringMigrationVersion` sentinel is
-- scrubbed at the top of MigrateAnchoringV1 on first upgrade.
--
-- The Ensure/Read helpers are shared via closure-capture factories.

local function MakeAnchoringHelpers(profile)
    -- Lazy accessor: only materializes profile.frameAnchoring on first write.
    -- Fresh profiles with no legacy source data never trigger the creation,
    -- so they don't get an empty shadow table that would mask AceDB defaults.
    local function EnsureFa()
        if not profile.frameAnchoring then
            profile.frameAnchoring = {}
        end
        return profile.frameAnchoring
    end
    -- Snapshot the existing table (may be nil) for read paths. Iterators and
    -- membership checks should treat nil as "no entries" without creating the
    -- table. Writes go through EnsureFa().
    local function ReadFa()
        return profile.frameAnchoring
    end
    return EnsureFa, ReadFa
end

local function MigrateAnchoringV1(profile)
    -- Scrub legacy sentinel on first upgrade.
    profile._anchoringMigrationVersion = nil

    local EnsureFa, ReadFa = MakeAnchoringHelpers(profile)

    do
        -- Detect 2.55-style profile: has frameAnchoring entries with the
        -- legacy `enabled` flag. In 2.55, positions were stored as absolute
        -- screen offsets (parent=screen, CENTER) regardless of the frame's
        -- logical parent. These offsets are meaningless in the new parent-
        -- chain system — they must be discarded so the seed can apply
        -- proper default parent chains.
        local isLegacy255 = false
        local existingFa = ReadFa()
        if existingFa then
            for _, settings in pairs(existingFa) do
                if type(settings) == "table" and settings.enabled ~= nil then
                    isLegacy255 = true
                    break
                end
            end
        end

        -- CDM containers are positioned by the CDM module (ncdm.pos,
        -- anchorBelowEssential). Creating FA entries for them makes
        -- QUI_HasFrameAnchor return true, which causes CDM to skip its
        -- own positioning logic. Always delete old CDM FA entries.
        local CDM_OWNED_KEYS = {
            cdmEssential = true,
            cdmUtility   = true,
            buffIcon     = true,
            buffBar      = true,
        }

        -- Frames whose absolute 2.55 offsets should be discarded because
        -- their new default parent is a CDM container or another moving
        -- frame. Preserving absolute offsets would orphan them from the
        -- parent chain and leave them at the wrong visual location.
        local LEGACY255_DISCARD_ABSOLUTE = {
            playerFrame    = true,
            targetFrame    = true,
            totFrame       = true,
            focusFrame     = true,
            petFrame       = true,
            bossFrames     = true,
            playerCastbar  = true,
            targetCastbar  = true,
            focusCastbar   = true,
            petCastbar     = true,
            totCastbar     = true,
            primaryPower   = true,
            secondaryPower = true,
            partyFrames    = true,
            raidFrames     = true,
        }

        -- Legacy cleanup only runs if the profile actually has entries.
        -- Fresh profiles skip this block entirely (existingFa is nil).
        --
        -- Discriminator: a TRUE 2.55 entry has no `parent` field at all
        -- (2.55 stored only point/relative/offsets/enabled, no parent
        -- chain). A 3.0+ entry that happens to still carry an `enabled`
        -- flag will have `parent` set, and its position data must be
        -- preserved exactly — even when the key is in
        -- LEGACY255_DISCARD_ABSOLUTE, because that list only describes
        -- frames whose 2.55 absolute coords don't translate. A 3.0+
        -- entry with `parent="screen"` and real offsets is a free
        -- screen position the user explicitly chose, not a stale 2.55
        -- artifact. Discarding it falls back to the AceDB default
        -- (e.g. playerFrame → cdmEssential), which silently re-parents
        -- the user's frames to a CDM container they may have hidden.
        if existingFa then
            for key, settings in pairs(existingFa) do
                if type(settings) == "table" and settings.enabled ~= nil then
                    local hasParentField = settings.parent ~= nil
                    local hasPositionData = (tonumber(settings.offsetX) or 0) ~= 0
                        or (tonumber(settings.offsetY) or 0) ~= 0
                        or (tonumber(settings.widthAdjust) or 0) ~= 0
                        or (tonumber(settings.heightAdjust) or 0) ~= 0

                    if CDM_OWNED_KEYS[key] then
                        -- CDM containers are positioned by the CDM module via
                        -- ncdm.<key>.pos. The cooperation contract is that
                        -- frameAnchoring entries for these keys yield to CDM,
                        -- so always strip them.
                        existingFa[key] = nil
                    elseif hasParentField then
                        -- 3.0+ shape: full {parent, point, relative, offsets}.
                        -- User data — preserve, just remove the legacy flag.
                        settings.enabled = nil
                    elseif settings.enabled == false then
                        -- True 2.55 shape (no parent field), enabled=false:
                        -- this was never explicitly positioned via layout
                        -- mode. For frames whose new default chains them
                        -- to a CDM container or other moving frame, the
                        -- legacy absolute coords don't translate — discard
                        -- so the seed default applies. For other frames,
                        -- preserve real position data via the seed pin.
                        if LEGACY255_DISCARD_ABSOLUTE[key] then
                            existingFa[key] = nil
                        elseif hasPositionData then
                            settings.enabled = nil  -- keep, will be pinned to screen later
                        else
                            existingFa[key] = nil
                        end
                    else
                        -- True 2.55 shape, enabled=true: user moved it via
                        -- 2.55 layout mode. Strip the flag, keep the data.
                        -- The seed at the end of MigrateAnchoringV1 won't
                        -- overwrite it because the entry still exists.
                        settings.enabled = nil
                    end
                end
            end
        end

        local function MigrateInlineOffsets(sourceTable, targetKey)
            if not sourceTable then return end
            local ox = sourceTable.offsetX
            local oy = sourceTable.offsetY
            if ox == nil and oy == nil then return end
            -- Skip if the target entry already exists (read without creating).
            local currentFa = ReadFa()
            if currentFa and currentFa[targetKey] then return end
            EnsureFa()[targetKey] = {
                parent = "screen",
                point = "CENTER",
                relative = "CENTER",
                offsetX = ox or 0,
                offsetY = oy or 0,
                sizeStable = true,
            }
        end

        local uf = profile.quiUnitFrames
        if uf and not isLegacy255 then
            -- Only migrate inline offsets for non-legacy profiles. On legacy
            -- 2.55 profiles these offsets are absolute screen positions that
            -- don't fit the new parent-chain system — let the seed handle them.
            MigrateInlineOffsets(uf.player, "playerFrame")
            MigrateInlineOffsets(uf.target, "targetFrame")
            MigrateInlineOffsets(uf.targettarget, "totFrame")
            MigrateInlineOffsets(uf.focus, "focusFrame")
            MigrateInlineOffsets(uf.pet, "petFrame")
            MigrateInlineOffsets(uf.boss, "bossFrames")
        elseif uf and isLegacy255 then
            -- Strip absolute offsets from quiUnitFrames so they don't bleed
            -- through via other code paths. The seed will apply proper
            -- default parent chains (playerFrame → cdmEssential, etc.)
            for _, unitKey in ipairs({"player","target","targettarget","focus","pet","boss"}) do
                local unitDB = uf[unitKey]
                if type(unitDB) == "table" then
                    unitDB.offsetX = nil
                    unitDB.offsetY = nil
                end
            end
        end

        local bars = profile.actionBars and profile.actionBars.bars
        if bars then
            -- Skip inline offsets for bars that have a position table — those
            -- small offsets are icon/layout adjustments, not screen positions.
            -- The actual screen position in bars.*.position is migrated by v3.
            if type(bars.extraActionButton) == "table" and not bars.extraActionButton.position then
                MigrateInlineOffsets(bars.extraActionButton, "extraActionButton")
            end
            if type(bars.zoneAbility) == "table" and not bars.zoneAbility.position then
                MigrateInlineOffsets(bars.zoneAbility, "zoneAbility")
            end
        end

        MigrateInlineOffsets(profile.totemBar, "totemBar")
        MigrateInlineOffsets(profile.xpTracker, "xpTracker")
        MigrateInlineOffsets(profile.skyriding, "skyriding")
        MigrateInlineOffsets(profile.crosshair, "crosshair")

        local gf = profile.quiGroupFrames
        if gf and not isLegacy255 then
            local currentFa = ReadFa()
            local pos = gf.position
            if pos and (pos.offsetX or pos.offsetY) and not (currentFa and currentFa.partyFrames) then
                EnsureFa().partyFrames = {
                    parent = "screen",
                    point = "CENTER",
                    relative = "CENTER",
                    offsetX = pos.offsetX or 0,
                    offsetY = pos.offsetY or 0,
                    sizeStable = true,
                }
            end

            local raidPos = gf.raidPosition
            currentFa = ReadFa()
            if raidPos and (raidPos.offsetX or raidPos.offsetY) and not (currentFa and currentFa.raidFrames) then
                EnsureFa().raidFrames = {
                    parent = "screen",
                    point = "CENTER",
                    relative = "CENTER",
                    offsetX = raidPos.offsetX or 0,
                    offsetY = raidPos.offsetY or 0,
                    sizeStable = true,
                }
            end
        end

        if uf then
            -- Castbar migration: if the user had an explicit playerCastbar
            -- entry (enabled=true) it was already preserved above. For implicit
            -- cases, translate the castbar.anchor field to an FA entry. The
            -- anchor field is semantic ("unitframe"/"essential"/"utility"/"none")
            -- so it works across profile versions.
            local castbarMigrations = {
                { unitKey = "player", targetKey = "playerCastbar", parentFrameKey = "playerFrame" },
                { unitKey = "target", targetKey = "targetCastbar", parentFrameKey = "targetFrame" },
                { unitKey = "focus",  targetKey = "focusCastbar",  parentFrameKey = "focusFrame" },
            }

            for _, cm in ipairs(castbarMigrations) do
                local unitSettings = uf[cm.unitKey]
                local castDB = unitSettings and unitSettings.castbar
                local anchor = castDB and (castDB.anchor or "none")
                -- On legacy 2.55 profiles, skip "none" anchor entirely:
                -- freeOffsetX/Y are absolute screen coords that don't translate.
                -- Let the seed apply the default parent chain (castbar → unit
                -- frame TOP→BOTTOM).
                local skipLegacyNone = isLegacy255 and anchor == "none"
                local currentFa = ReadFa()
                if castDB and not (currentFa and currentFa[cm.targetKey]) and not skipLegacyNone then
                    local parent, ox, oy, point, relative
                    if anchor == "none" then
                        parent = "screen"
                        ox = castDB.freeOffsetX or castDB.offsetX or 0
                        oy = castDB.freeOffsetY or castDB.offsetY or 0
                        point = "CENTER"
                        relative = "CENTER"
                    elseif anchor == "unitframe" then
                        parent = cm.parentFrameKey
                        ox = castDB.offsetX or castDB.lockedOffsetX or 0
                        oy = castDB.offsetY or castDB.lockedOffsetY or 0
                        point = "TOP"
                        relative = "BOTTOM"
                    elseif anchor == "essential" then
                        parent = "cdmEssential"
                        ox = castDB.offsetX or castDB.lockedOffsetX or 0
                        oy = castDB.offsetY or castDB.lockedOffsetY or 0
                        point = "TOP"
                        relative = "BOTTOM"
                    elseif anchor == "utility" then
                        parent = "cdmUtility"
                        ox = castDB.offsetX or castDB.lockedOffsetX or 0
                        oy = castDB.offsetY or castDB.lockedOffsetY or 0
                        point = "TOP"
                        relative = "BOTTOM"
                    else
                        parent = "screen"
                        ox = castDB.offsetX or 0
                        oy = castDB.offsetY or 0
                        point = "CENTER"
                        relative = "CENTER"
                    end

                    local entry = {
                        parent = parent,
                        point = point,
                        relative = relative,
                        offsetX = ox,
                        offsetY = oy,
                        sizeStable = true,
                    }
                    if castDB.widthAdjustment and castDB.widthAdjustment ~= 0 then
                        entry.widthAdjust = castDB.widthAdjustment
                    end
                    if anchor ~= "none" then
                        entry.autoWidth = true
                    end
                    EnsureFa()[cm.targetKey] = entry
                end
            end
        end

    end
end

local function MigrateAnchoringV2(profile)
    local EnsureFa, ReadFa = MakeAnchoringHelpers(profile)

    do
        -- mplusTimer's AceDB default is chained to partyFrames
        -- (point=BOTTOMLEFT, parent=partyFrames, relative=BOTTOMRIGHT). The
        -- legacy `profile.mplusTimer.position` table is just resolved screen
        -- coords written by the module's GetPosition(), so migrating it into
        -- frameAnchoring as parent="screen" clobbers the chained default.
        -- Skip the write entirely; the chained default will take over. v28
        -- (RestoreMplusTimerChainedDefault) cleans up profiles that already
        -- ran the buggy version of this migration.

        local tp = profile.tooltip and profile.tooltip.anchorPosition
        if tp then
            local currentFa = ReadFa()
            if not (currentFa and currentFa.tooltipAnchor) then
                EnsureFa().tooltipAnchor = {
                    parent = "screen",
                    point = tp.point or "BOTTOMRIGHT",
                    relative = tp.relPoint or "BOTTOMRIGHT",
                    offsetX = tp.x or -200,
                    offsetY = tp.y or 100,
                    sizeStable = true,
                }
            end
        end

        -- Legacy inline offsets are UIParent-center-based absolute coords.
        -- Pin parent="screen" explicitly so copyDefaults can't later fill
        -- in a chain-rooted default parent and misinterpret the offsets.
        --
        -- Excludes keys whose AceDB default has a chained (non-screen)
        -- parent — pinning those to screen would clobber the chain. See
        -- v27 (RestoreChainedDefaultAnchors) for the cleanup of profiles
        -- that ran the original buggy version of this migration.
        local function MigrateOffsets(sourceTable, targetKey)
            if not sourceTable then return end
            local ox = sourceTable.offsetX or sourceTable.xOffset
            local oy = sourceTable.offsetY or sourceTable.yOffset
            if ox == nil and oy == nil then return end
            local currentFa = ReadFa()
            if currentFa and currentFa[targetKey] then return end
            EnsureFa()[targetKey] = {
                parent = "screen",
                point = "CENTER",
                relative = "CENTER",
                offsetX = ox or 0,
                offsetY = oy or 0,
                sizeStable = true,
            }
        end

        -- brezCounter, combatTimer, petWarning omitted intentionally — their
        -- AceDB defaults chain to other frames (combatTimer / bar3 /
        -- playerFrame respectively) and screen-pinning loses the chain.
        MigrateOffsets(profile.rangeCheck, "rangeCheck")
        MigrateOffsets(profile.actionTracker, "actionTracker")
        MigrateOffsets(profile.focusCastAlert, "focusCastAlert")
        MigrateOffsets(profile.raidBuffs, "missingRaidBuffs")
    end
end

local function MigrateAnchoringV3(profile)
    local EnsureFa, ReadFa = MakeAnchoringHelpers(profile)

    do
        -- Legacy position tables are UIParent-center-based absolute coords.
        -- Pin parent="screen" explicitly so copyDefaults can't later fill
        -- in a chain-rooted default parent and misinterpret the offsets.
        local function MigratePos(source, faKey, defaults)
            if not source then return end
            local currentFa = ReadFa()
            if currentFa and currentFa[faKey] then return end
            EnsureFa()[faKey] = {
                parent = "screen",
                point = source.point or defaults.point,
                relative = source.relPoint or source.relativePoint or defaults.relative,
                offsetX = source.x or defaults.offsetX,
                offsetY = source.y or defaults.offsetY,
                sizeStable = true,
            }
        end

        local gen = profile.general
        if gen then
            MigratePos(gen.readyCheckPosition, "readyCheck",
                { point = "CENTER", relative = "CENTER", offsetX = 0, offsetY = -10 })
        end

        MigratePos(profile.powerBarAltPosition, "powerBarAlt",
            { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -100 })

        local lootDB = profile.loot
        if lootDB then
            MigratePos(lootDB.position, "lootFrame",
                { point = "CENTER", relative = "CENTER", offsetX = 0, offsetY = 100 })
        end

        local rollDB = profile.lootRoll
        if rollDB then
            MigratePos(rollDB.position, "lootRollAnchor",
                { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -200 })
        end

        if gen then
            local cfp = gen.consumableFreePosition
            if cfp then
                local currentFa = ReadFa()
                if not (currentFa and currentFa.consumables) then
                    EnsureFa().consumables = {
                        parent = "screen",
                        point = cfp.point or "CENTER",
                        relative = cfp.relativePoint or cfp.relPoint or "CENTER",
                        offsetX = cfp.x or 0,
                        offsetY = cfp.y or 100,
                        sizeStable = true,
                    }
                end
            end
        end

        local alertDB = profile.alerts
        if alertDB then
            MigratePos(alertDB.alertPosition, "alertAnchor",
                { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -20 })
            MigratePos(alertDB.toastPosition, "toastAnchor",
                { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -150 })
            MigratePos(alertDB.bnetToastPosition, "bnetToastAnchor",
                { point = "TOPRIGHT", relative = "TOPRIGHT", offsetX = -200, offsetY = -80 })
        end

        -- Legacy 2.55 raidBuffs position table (format: { point, relPoint, x, y })
        -- The v2 MigrateOffsets only checks offsetX/Y so this was missed.
        local rbDB = profile.raidBuffs
        if rbDB and type(rbDB.position) == "table" then
            MigratePos(rbDB.position, "missingRaidBuffs",
                { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -100 })
        end

        local barsDB = profile.actionBars and profile.actionBars.bars
        if barsDB then
            local barKeyMap = {
                pet = "petBar",
                stance = "stanceBar",
                microbar = "microMenu",
                bags = "bagBar",
            }
            for dbKey, barData in pairs(barsDB) do
                if type(barData) == "table" then
                    local faKey = barKeyMap[dbKey] or dbKey
                    -- ONLY the legacy 2.55 `position` field is migrated here.
                    -- `ownedPosition` is a dead 3.x-era field that no runtime
                    -- code reads or writes anymore — it lingers in some 3.0
                    -- profiles as orphaned data. Treating it as a position
                    -- source would clobber the user's chained-default bars
                    -- with a screen-center FA entry on every login (bar1 →
                    -- bar3 chain replaced with parent="screen", offset 0/0).
                    local posSource = barData.position
                    if type(posSource) == "table" then
                        MigratePos(posSource, faKey,
                            { point = "CENTER", relative = "CENTER", offsetX = 0, offsetY = 0 })
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- v24: Repair entries with parent="disabled" + stale corner point/relative
---------------------------------------------------------------------------
-- The SavePendingPosition free-position branch had a bug: when the user
-- middle-clicked a frame to unanchor it (parent → "disabled") and the
-- entry already had non-CENTER point/relative from a prior corner-
-- conversion, subsequent drags wrote fresh CENTER-based offsets without
-- normalizing point/relative. The runtime then interpreted CENTER offsets
-- as TOPRIGHT-anchored offsets and the frame teleported off-screen.
--
-- Detection: parent == "disabled" AND point == relative AND that value
-- is one of the four corners. Layout mode's drag handler measures offsets
-- against UIParent CENTER, so the stored offsetX/offsetY are already in
-- CENTER coordinate space — they just need the entry's point/relative
-- normalized to CENTER/CENTER to be interpreted correctly. Repair preserves
-- the user's drag position; it does NOT discard the offsets.
local CORNER_POINTS = {
    TOPLEFT     = true,
    TOPRIGHT    = true,
    BOTTOMLEFT  = true,
    BOTTOMRIGHT = true,
}

local function RepairDisabledStaleCornerEntries(profile)
    if type(profile) ~= "table" or type(profile.frameAnchoring) ~= "table" then
        return
    end
    local repaired = 0
    for key, entry in pairs(profile.frameAnchoring) do
        if type(entry) == "table" and entry.parent == "disabled" then
            -- Two fingerprints to detect:
            --
            -- (a) point == relative AND both are corner names. The straight-
            --     forward case after the SavePendingPosition bug.
            -- (b) point == nil AND relative is a corner name. This occurs
            --     after AceDB save/load: AceDB strips fields whose value
            --     matches the default. For buff/debuff frames the default
            --     point happens to be "TOPRIGHT" — when the corner conv
            --     wrote point="TOPRIGHT", AceDB stripped it on save,
            --     leaving relative="TOPRIGHT" as the only on-disk witness
            --     to the corruption. The proxy view fills point back in
            --     from defaults so consumers see (TOPRIGHT, TOPRIGHT)
            --     again. From a repair standpoint, the raw entry shape
            --     {parent=disabled, point=nil, relative=<corner>} is the
            --     same bug as case (a) just with one field stripped.
            local isCornerPair = entry.point == entry.relative
                and CORNER_POINTS[entry.point or ""]
            local isStrippedCorner = entry.point == nil
                and CORNER_POINTS[entry.relative or ""]

            if isCornerPair or isStrippedCorner then
                MigLog("v25 RepairDisabledStaleCorner: %s (parent=disabled, point=%s, rel=%s, ofs=%s/%s) → CENTER/CENTER",
                    tostring(key),
                    tostring(entry.point),
                    tostring(entry.relative),
                    tostring(entry.offsetX),
                    tostring(entry.offsetY))
                -- Repair: keep parent/offsets exactly as the user dragged
                -- them, normalize point/relative to CENTER/CENTER so the
                -- runtime interprets the offsets in the same coordinate
                -- space they were measured in.
                entry.point = "CENTER"
                entry.relative = "CENTER"
                repaired = repaired + 1
            end
        end
    end
    MigLog("RepairDisabledStaleCorner done: repaired=%d", repaired)
end

---------------------------------------------------------------------------
-- v26: Backfill growAnchor field on buff/debuff/auraBar FA entries
---------------------------------------------------------------------------
-- Phase 2 of the buff/debuff anchor split: separate "where the container
-- lives" (FA entry point/relative/offsets) from "which corner stays fixed
-- as the container resizes" (FA entry growAnchor field). The apply path
-- reads growAnchor and converts CENTER offsets to corner offsets at apply
-- time using the container's current natural size.
--
-- For existing profiles, we need to populate growAnchor so the new apply
-- path knows the corner. Two cases:
--
-- (a) Entry was already corner-anchored from a prior corner-conversion
--     run: point == relative AND both are corner names. Set
--     growAnchor = entry.point so the new apply path treats the existing
--     offsets as already-corner-anchored and applies them directly. We
--     leave point/relative/offsets alone — they're already in the right
--     shape for the apply-time path to consume verbatim.
--
-- (b) Entry was normalized to CENTER/CENTER by v24/v25 repair, OR is a
--     fresh CENTER-anchored entry from a Phase 2 layout-mode drag.
--     growAnchor is derived from buffBorders.{buff,debuff}GrowLeft/GrowUp.
--     The apply path will compute the corner conversion using the live
--     container size on next apply.
--
-- For v26 we only backfill case (a) — case (b) is handled at runtime by
-- buffborders.lua's UpdateGrowAnchor watcher, which fires on every refresh
-- including the post-migration FullRefresh that runs at module init.
local function BackfillGrowAnchor(profile)
    if type(profile) ~= "table" or type(profile.frameAnchoring) ~= "table" then
        return
    end
    -- Only buff-borders containers. CDM containers (buffIcon, buffBar,
    -- cdmEssential, cdmUtility) are positioned by the CDM module via
    -- ncdm.<key>.pos — their FA entries are stripped by CDM_OWNED_KEYS
    -- and they use a different growth model (CENTERED_HORIZONTAL etc.)
    -- that doesn't fit the four-corner growAnchor scheme.
    local KEYS = { "buffFrame", "debuffFrame" }
    local backfilled = 0
    for _, key in ipairs(KEYS) do
        local entry = profile.frameAnchoring[key]
        if type(entry) == "table" and entry.growAnchor == nil then
            -- Case (a): existing corner-anchored entry. Both point and
            -- relative are the same corner string. Capture it as growAnchor.
            if entry.point == entry.relative
                and CORNER_POINTS[entry.point or ""]
            then
                entry.growAnchor = entry.point
                backfilled = backfilled + 1
                MigLog("v26 BackfillGrowAnchor: %s growAnchor=%s (from existing corner anchor)",
                    tostring(key), tostring(entry.growAnchor))
            end
            -- Case (b) is left for the runtime watcher (UpdateGrowAnchor in
            -- buffborders.lua), which fires on FullRefresh after the module
            -- initializes and reads buffBorders.{buff,debuff}GrowLeft/GrowUp
            -- to derive the corner. Doing it here would require a copy of
            -- that logic and would race with anything that mutates the
            -- buffBorders DB before module init.
        end
    end
    MigLog("BackfillGrowAnchor done: backfilled=%d", backfilled)
end

---------------------------------------------------------------------------
-- v27: Restore chained-default parents clobbered by MigrateOffsets
---------------------------------------------------------------------------
-- The original v20 MigrateOffsets pinned all legacy 2.55 inline-offset
-- frames to parent="screen", which broke the chained defaults for
-- frames whose AceDB default points at another frame:
--
--   brezCounter → combatTimer  (default)
--   combatTimer → bar3         (default)
--   petWarning  → playerFrame  (default)
--
-- Detect FA entries that exactly match the legacy MigrateOffsets shape
-- and delete them so AceDB's default chain takes over. The shape is
-- distinctive: parent="screen", point/relative=CENTER (or stripped to
-- nil by AceDB), sizeStable=true, with no other customization fields.
-- Any user-edited entry (different point/relative, enabled flag,
-- keepInPlace, scale, etc.) is left untouched.
local RESTORE_CHAINED_KEYS = {
    brezCounter = true,
    combatTimer = true,
    petWarning  = true,
}

-- Fields permitted in a "pristine MigrateOffsets" entry. Anything outside
-- this set means the user (or another migration) edited the entry, so
-- we leave it alone.
local MIGRATE_OFFSETS_FIELDS = {
    parent     = true,
    point      = true,
    relative   = true,
    offsetX    = true,
    offsetY    = true,
    sizeStable = true,
}

local function IsLegacyMigrateOffsetsEntry(entry)
    if type(entry) ~= "table" then return false end
    if entry.parent ~= "screen" then return false end
    if entry.point ~= nil and entry.point ~= "CENTER" then return false end
    if entry.relative ~= nil and entry.relative ~= "CENTER" then return false end
    for k in pairs(entry) do
        if not MIGRATE_OFFSETS_FIELDS[k] then
            return false
        end
    end
    return true
end

local function RestoreChainedDefaultAnchors(profile)
    if type(profile) ~= "table" or type(profile.frameAnchoring) ~= "table" then
        return
    end
    local fa = profile.frameAnchoring
    local restored = 0
    for key in pairs(RESTORE_CHAINED_KEYS) do
        local entry = fa[key]
        if IsLegacyMigrateOffsetsEntry(entry) then
            MigLog("v27 RestoreChainedDefault: %s (parent=screen, point=%s, ofs=%s/%s) → default chain",
                tostring(key),
                tostring(entry.point),
                tostring(entry.offsetX),
                tostring(entry.offsetY))
            fa[key] = nil
            restored = restored + 1
        end
    end
    MigLog("RestoreChainedDefaultAnchors done: restored=%d", restored)
end

-- v28: clean up frameAnchoring.mplusTimer entries that the buggy
-- MigrateAnchoringV2 wrote with parent="screen". The mplusTimer AceDB
-- default is chained to partyFrames, so deleting the entry restores the
-- chain. RestoreChainedDefaultAnchors couldn't handle this key because
-- IsLegacyMigrateOffsetsEntry requires point=CENTER, while V2's mplusTimer
-- entry inherited the user's saved point (TOPRIGHT/BOTTOMRIGHT/etc.).
-- The shape check here is relaxed: parent="screen", sizeStable=true, only
-- the 6 fields V2 ever wrote, and no extra keys. A user who positioned
-- the timer via layout mode after the buggy V2 ran will lose that
-- customization, but v27 only just landed so the blast radius is small.
local function IsLegacyMigrateAnchoringV2MplusEntry(entry)
    if type(entry) ~= "table" then return false end
    if entry.parent ~= "screen" then return false end
    if entry.sizeStable ~= true then return false end
    for k in pairs(entry) do
        if not MIGRATE_OFFSETS_FIELDS[k] then
            return false
        end
    end
    return true
end

local function RestoreMplusTimerChainedDefault(profile)
    if type(profile) ~= "table" or type(profile.frameAnchoring) ~= "table" then
        return
    end
    local fa = profile.frameAnchoring
    local entry = fa.mplusTimer
    if IsLegacyMigrateAnchoringV2MplusEntry(entry) then
        MigLog("v28 RestoreMplusTimerChainedDefault: mplusTimer (parent=screen, point=%s, ofs=%s/%s) → default chain",
            tostring(entry.point),
            tostring(entry.offsetX),
            tostring(entry.offsetY))
        fa.mplusTimer = nil
        MigLog("RestoreMplusTimerChainedDefault done: restored=1")
    else
        MigLog("RestoreMplusTimerChainedDefault done: restored=0")
    end
end

-- v29: remove raw primary/secondary power-bar frameAnchoring entries when
-- they still resolve to the 3.x seeded defaults. Those entries make the
-- power bars appear explicitly anchored and block resourcebars.lua from
-- applying spec-aware swap / lock positioning. Matching against the current
-- effective values lets this catch raw tables that AceDB partially or fully
-- stripped back to defaults, while the raw-key check preserves customized
-- entries with extra fields.
local SEEDED_POWER_BAR_ANCHOR_DEFAULTS = {
    primaryPower = {
        point = "TOP", parent = "cdmEssential", relative = "BOTTOM",
        offsetX = 0, offsetY = 0,
        sizeStable = true, autoWidth = true, autoHeight = false,
        hideWithParent = false, keepInPlace = true,
        widthAdjust = 0, heightAdjust = 0,
    },
    secondaryPower = {
        point = "TOP", parent = "primaryPower", relative = "BOTTOM",
        offsetX = 0, offsetY = 0,
        sizeStable = true, autoWidth = true, autoHeight = false,
        hideWithParent = false, keepInPlace = true,
        widthAdjust = 0, heightAdjust = 0,
    },
}

local function IsSeededDefaultPowerBarAnchor(key, entry)
    local defaults = SEEDED_POWER_BAR_ANCHOR_DEFAULTS[key]
    if not defaults or type(entry) ~= "table" then
        return false
    end
    for field, defaultValue in pairs(defaults) do
        if entry[field] ~= defaultValue then
            return false
        end
    end
    for field in pairs(entry) do
        if defaults[field] == nil then
            return false
        end
    end
    return true
end

local function RestorePowerBarModulePositioning(profile)
    if type(profile) ~= "table" or type(profile.frameAnchoring) ~= "table" then
        return
    end
    local fa = profile.frameAnchoring
    local removed = 0
    for key in pairs(SEEDED_POWER_BAR_ANCHOR_DEFAULTS) do
        local entry = rawget(fa, key)
        if IsSeededDefaultPowerBarAnchor(key, entry) then
            MigLog("v29 RestorePowerBarModulePositioning: %s → remove seeded/default FA entry",
                tostring(key))
            fa[key] = nil
            removed = removed + 1
        end
    end
    MigLog("RestorePowerBarModulePositioning done: removed=%d", removed)
end

local function SplitGroupAuraDurationText(profile)
    if type(profile) ~= "table" or type(profile.quiGroupFrames) ~= "table" then
        return
    end

    local function MigrateContext(contextKey)
        local context = profile.quiGroupFrames[contextKey]
        local auras = type(context) == "table" and context.auras or nil
        if type(auras) ~= "table" then
            return
        end

        local legacy = auras.showDurationText
        if legacy == nil then
            return
        end

        SetIfNil(auras, "showBuffDurationText", legacy)
        SetIfNil(auras, "showDebuffDurationText", legacy)
        MigLog("v30 SplitGroupAuraDurationText: %s shared=%s", tostring(contextKey), tostring(legacy))
    end

    MigrateContext("party")
    MigrateContext("raid")
end

local function EnsureGroupAuraDurationTextStyle(profile)
    if type(profile) ~= "table" or type(profile.quiGroupFrames) ~= "table" then
        return
    end

    local function MigrateContext(contextKey)
        local context = profile.quiGroupFrames[contextKey]
        local auras = type(context) == "table" and context.auras or nil
        if type(auras) ~= "table" then
            return
        end

        local legacyShow = auras.showDurationText
        if legacyShow ~= nil then
            SetIfNil(auras, "showBuffDurationText", legacyShow)
            SetIfNil(auras, "showDebuffDurationText", legacyShow)
        end

        local legacyFontSize = auras.durationFontSize or 9
        local legacyUseTimeColor = auras.showDurationColor
        if legacyUseTimeColor == nil then
            legacyUseTimeColor = true
        end

        for _, prefix in ipairs({ "buff", "debuff" }) do
            SetIfNil(auras, prefix .. "DurationFont", "")
            SetIfNil(auras, prefix .. "DurationFontSize", legacyFontSize)
            SetIfNil(auras, prefix .. "DurationAnchor", "BOTTOM")
            SetIfNil(auras, prefix .. "DurationOffsetX", 0)
            SetIfNil(auras, prefix .. "DurationOffsetY", -6)
            SetIfNil(auras, prefix .. "DurationColor", { 1, 1, 1, 1 })
            SetIfNil(auras, prefix .. "DurationUseTimeColor", legacyUseTimeColor)
        end

        MigLog("v31 EnsureGroupAuraDurationTextStyle: %s fontSize=%s timeColor=%s",
            tostring(contextKey), tostring(legacyFontSize), tostring(legacyUseTimeColor))
    end

    MigrateContext("party")
    MigrateContext("raid")
end

-- CORNER_POINTS used by both RepairDisabledStaleCornerEntries and
-- BackfillGrowAnchor. Defined locally so the migration module is
-- self-contained (anchoring.lua has its own copy).
-- (Already declared earlier in this file.)

-- Gated externally by schema version v22. The data-shape guard is "does
-- ncdm.<legacy key> still exist?" — if not, the loop below is a no-op.
local function MigrateNCDMContainers(profile)
    if not profile or not profile.ncdm then
        return
    end

    -- Scrub stale sentinel from 3.1.x profiles.
    profile.ncdm._containersMigrated = nil

    if not profile.ncdm.containers then
        profile.ncdm.containers = {}
    end

    local containerNames = {
        essential  = "Essential",
        utility    = "Utility",
        buff       = "Buff Icons",
        trackedBar = "Buff Bars",
    }
    local containerTypes = {
        essential  = "cooldown",
        utility    = "cooldown",
        buff       = "aura",
        trackedBar = "auraBar",
    }

    -- Only migrate each key when the destination container is absent.
    -- Profiles that have already been through this migration once (3.0 / 3.1.x
    -- users) already have `containers[key]` populated and may have modified
    -- it since; clobbering it from the stale `ncdm[key]` would lose user
    -- changes. The source `ncdm[key]` is intentionally left in place to
    -- stay compatible with any module still reading from the old location.
    for _, key in ipairs({ "essential", "utility", "buff", "trackedBar" }) do
        if profile.ncdm[key] and profile.ncdm.containers[key] == nil then
            profile.ncdm.containers[key] = CloneValue(profile.ncdm[key])
            profile.ncdm.containers[key].builtIn = true
            profile.ncdm.containers[key].containerType = containerTypes[key]
            profile.ncdm.containers[key].name = containerNames[key]
        end
    end
end

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
local _currentGlobalDB = nil  -- set by Migrations.Run for cross-profile access
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
-- user can run `/qui migration restore [N]` to roll back to a previous
-- pre-migration state. We keep up to MAX_BACKUP_SLOTS snapshots in a
-- circular buffer (slot 1 = newest, slot N = oldest); each successful
-- migration run pushes a new snapshot to the front and trims the tail.
--
-- The backup excludes `_migrationBackup` itself to prevent recursive growth.

local BACKUP_KEY = "_migrationBackup"
local MAX_BACKUP_SLOTS = 5

local function DeepCloneExcluding(value, excludeKey)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        if k ~= excludeKey then
            copy[k] = DeepCloneExcluding(v, excludeKey)
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
        snapshot    = DeepCloneExcluding(profile, BACKUP_KEY),
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
        profile[k] = DeepCloneExcluding(v, BACKUP_KEY)
    end
    -- After restore, the profile is back at its pre-migration version. The
    -- backup container is preserved so the user can restore other slots.
    return true, entry
end

-- Returns the full backup container ({slots = {...}}) for inspection.
-- Lazily upgrades legacy single-slot shape on read.
function Migrations.GetBackupInfo(profile)
    if type(profile) ~= "table" then return nil end
    return GetBackupContainer(profile)
end

Migrations.MAX_BACKUP_SLOTS = MAX_BACKUP_SLOTS

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

    local stored = tonumber(profile._schemaVersion) or 0

    -- Flag legacy/fresh profiles for the late EditMode action bar import.
    -- v19 (MigrateAnchoringV1) is the first migration that wrote any
    -- frameAnchoring data; profiles stored at < 19 either predate the
    -- modern anchoring pipeline or are fresh installs. Either way, the
    -- late migration should run for them. The flag is read at PLAYER_LOGIN
    -- by Migrations.RunLate after EditModeManagerFrame is loaded.
    -- Profiles already at v19+ never get the flag, so RunLate stamps
    -- their sentinel and skips the import loop.
    if stored < 19 and not profile._abPositionsImportedFromEditMode then
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
        return false  -- Nothing to do. Backup (if any) remains untouched.
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

    -- === Data format migrations (restructure raw data first) ===
    if stored < 2  then MigrateDatatextSlots(profile.datatext) end
    if stored < 3  then MigratePerSlotSettings(profile.datatext) end
    if stored < 4  then MigrateMasterTextColors(profile.quiUnitFrames and profile.quiUnitFrames.general) end
    if stored < 5  then MigrateChatEditBox(profile.chat) end
    if stored < 6  then MigrateCooldownSwipeV2(profile) end
    if stored < 7  then MigrateCastBars(profile) end
    if stored < 8  then MigrateUnitFrames(profile) end
    if stored < 9  then
        MigrateSelfFirst(profile)
        CleanOrphanKeys(profile)
    end

    -- === Legacy 2.55 mainline normalization (explicit marker check) ===
    if stored < 10 and IsLegacy255Profile(profile) then
        PruneLegacyPlaceholderAnchors(profile)
        ResetLegacyAnchorsForRebuild(profile)
        NormalizeLegacyActionBarLayouts(profile)
    end

    -- === Feature migrations ===
    if stored < 11 then EnsureThemeStorage(profile) end
    if stored < 12 then MigrateLegacyLootSettings(profile) end
    if stored < 13 then EnsureCraftingOrderIndicator(profile) end
    if stored < 14 then
        MigrateToShowLogic(profile.cdmVisibility)
        MigrateToShowLogic(profile.unitframesVisibility)
    end
    if stored < 15 then MigrateGroupFrameContainers(profile) end
    if stored < 16 then NormalizeAuraIndicators(profile) end
    if stored < 17 then NormalizeEngines(profile) end
    if stored < 18 then NormalizeMinimapSettings(profile) end

    -- === Anchoring (depends on data being in final locations) ===
    if stored < 19 then MigrateAnchoringV1(profile) end
    if stored < 20 then MigrateAnchoringV2(profile) end
    if stored < 21 then MigrateAnchoringV3(profile) end
    if stored < 22 then MigrateNCDMContainers(profile) end

    -- v23: re-prune ghost FA entries that the original v10 prune missed
    -- because they carried a stray `enabled = false` flag (3.0-era write
    -- artifacts). The whitelist update to IsPlaceholderAnchorEntry needs
    -- to actually run against existing v22 profiles to clean up the
    -- ghosts that the v19 cleanup loop preserved with `enabled` stripped
    -- but parent="screen", point=CENTER, all zeros — those ghost entries
    -- mask the AceDB default chain (e.g. debuffFrame → buffFrame →
    -- minimap), so chained children fall back to screen center instead
    -- of following their default parent.
    if stored < 23 then PruneLegacyPlaceholderAnchors(profile) end

    -- v24: repair `parent="disabled"` entries that carry stale corner
    -- point/relative from a SavePendingPosition bug. See the function
    -- docstring above for details. Heals frames that were unanchored
    -- via middle-click and then dragged, ending up off-screen.
    if stored < 24 then RepairDisabledStaleCornerEntries(profile) end

    -- v25: re-run the repair against profiles that already migrated past
    -- v24 with re-corrupted data. Two reasons:
    --   1. The buffborders.lua LayoutIcons bug was writing the runtime
    --      corner conversion BACK to the DB on every layout pass, undoing
    --      v24's work for any profile that had buffs/debuffs visible at
    --      reload time. The buffborders bug is fixed in this same release.
    --   2. The original v24 discriminator only matched entries with
    --      explicit point AND relative both set to a corner name. AceDB's
    --      default-stripping on save left some entries with point=nil and
    --      only relative set to a corner — same bug, different shape.
    --      v25 catches both shapes.
    if stored < 25 then RepairDisabledStaleCornerEntries(profile) end

    -- v26: backfill growAnchor on buff/debuff/auraBar FA entries that have
    -- existing corner anchoring. The new apply-path growAnchor branch reads
    -- this field to perform CENTER → corner conversion at apply time. See
    -- the function docstring for case-handling details.
    if stored < 26 then BackfillGrowAnchor(profile) end

    -- v27: undo MigrateOffsets's screen-pinning of frames whose AceDB
    -- default has a chained parent (brezCounter → combatTimer, combatTimer
    -- → bar3, petWarning → playerFrame). See function docstring.
    if stored < 27 then RestoreChainedDefaultAnchors(profile) end

    -- v28: undo MigrateAnchoringV2's mplusTimer screen-pinning. Same root
    -- cause as v27 but for a key v27's discriminator couldn't catch (V2's
    -- mplusTimer entry uses non-CENTER points). See function docstring.
    if stored < 28 then RestoreMplusTimerChainedDefault(profile) end

    -- v29: remove seeded/default raw FA entries for primary/secondary power
    -- bars so resourcebars.lua regains control of swap/quick positioning.
    if stored < 29 then RestorePowerBarModulePositioning(profile) end

    -- v30: split the shared group-frame aura duration text toggle into
    -- separate buff/debuff settings while preserving old saved values.
    if stored < 30 then SplitGroupAuraDurationText(profile) end

    -- v31: add font, color, anchor, and offset controls for duration text.
    if stored < 31 then EnsureGroupAuraDurationTextStyle(profile) end

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

    local profiles = db.sv and db.sv.profiles
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

        _currentGlobalDB = nil
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

    _currentGlobalDB = nil
    return result
end
