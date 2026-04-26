---------------------------------------------------------------------------
-- QUI Backwards Compatibility
-- Tier 0: StampOldDefaults (raw SV access, must run before AceDB defaults)
-- Tier 1: Delegates to ns.Migrations.Run() for all profile-level migrations
-- Also handles global/char structure housekeeping.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Shadow-defaults mechanism (full-coverage / track-everything mode)
--
-- On every successful load, after migrations settle, we deep-copy the
-- currently-shipping defaults table into rawProfile._shippedDefaults.
-- On the *next* load, StampOldDefaultsOnRawProfile recursively walks the
-- shadow and the new shipping defaults in lockstep. For every leaf where
--   (a) the previous shipping value differs from the new shipping value,
--   (b) the user has no explicit override at that path in raw SV, and
--   (c) the parent path already exists in raw SV (we don't create
--       intermediate tables — a missing parent means the user has never
--       customized that subtree, so AceDB defaults should apply normally),
-- we pin the previous value into raw SV so the default flip doesn't
-- silently change the user's behavior.
--
-- The shadow only takes effect starting from the *first* load after the
-- mechanism ships. Users who lost a value to a default flip *before* the
-- shadow existed need a one-shot stamp (like the v3 rescue below).
--
-- Important behavior consequence: tracking everything means every default
-- flip becomes opt-in for *new installs only*. Existing users who never
-- toggled a setting will be permanently pinned to whatever default they
-- first installed under, until they manually change it. If you want a
-- default change to propagate to existing users, you must either bump
-- the schema and explicitly migrate, or accept that only new installs
-- will see it.
---------------------------------------------------------------------------

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

local function DeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Recursive lockstep walk over shadow + current + raw.
--
-- shadowNode  — previous shipping value (always a table at this level)
-- currentNode — current shipping value at the same position (may be nil
--               or non-table if the defaults shape changed)
-- rawNode     — raw SV table at the same position (always a table at
--               this level — caller guarantees this)
local function PinDefaultsRecursive(shadowNode, currentNode, rawNode)
    for key, shadowVal in pairs(shadowNode) do
        local currentVal = (type(currentNode) == "table") and currentNode[key] or nil
        local rawVal = rawget(rawNode, key)

        if currentVal == nil then
            -- Default was removed entirely. Don't resurrect it — that's a
            -- migration concern, not a defaults-pin concern.
        elseif type(shadowVal) == "table" and type(currentVal) == "table" then
            -- Both shapes are tables. Recurse only if the user has touched
            -- this subtree in raw SV — otherwise AceDB serves the entire
            -- subtree from defaults and we have no parent to write into.
            if type(rawVal) == "table" then
                PinDefaultsRecursive(shadowVal, currentVal, rawVal)
            end
        else
            -- Leaf (or shape-mismatch). Pin if the value flipped and the
            -- user has no explicit override at this exact key.
            if rawVal == nil and not DeepEqual(shadowVal, currentVal) then
                rawset(rawNode, key, DeepCopy(shadowVal))
            end
        end
    end
end

local function PinTrackedDefaults(rawProfile)
    local shadow = rawget(rawProfile, "_shippedDefaults")
    if type(shadow) ~= "table" then return end
    if not (ns.defaults and ns.defaults.profile) then return end
    PinDefaultsRecursive(shadow, ns.defaults.profile, rawProfile)
end

-- Snapshot the entire current shipping defaults table into
-- rawProfile._shippedDefaults via deep copy. Called after migrations
-- have settled, on every load, for every stored profile.
local function WriteShippedDefaultsSnapshot(rawProfile)
    if type(rawProfile) ~= "table" then return end
    if not (ns.defaults and ns.defaults.profile) then return end
    rawset(rawProfile, "_shippedDefaults", DeepCopy(ns.defaults.profile))
end

local function WriteShippedDefaultsSnapshotAll(db)
    if not (db and db.sv and db.sv.profiles) then return end
    for _, rawProfile in pairs(db.sv.profiles) do
        WriteShippedDefaultsSnapshot(rawProfile)
    end
end

---------------------------------------------------------------------------
-- Defaults v1 migration (v3.1.0 defaults overhaul)
-- Stamps OLD default values into existing profiles so that changing
-- defaults.lua doesn't silently flip settings for returning users.
-- Only writes a value when rawget returns nil (user never touched it).
--
-- This MUST operate on the raw SV table (not the AceDB proxy) because
-- it needs to distinguish "user never set this" (rawget == nil) from
-- "AceDB filled in the default" (proxy returns default value).
---------------------------------------------------------------------------
-- Stamp old defaults into a single raw profile table. Operates entirely on
-- raw data via rawget/rawset — no AceDB proxy access — so it can be called
-- against any profile, not just the active one.
local function StampOldDefaultsOnRawProfile(rawProfile)
    if not rawProfile then return end  -- brand-new profile, use new defaults

    -- Already migrated this profile?
    -- v1 had a bug that created intermediate tables via rawset, polluting the SV.
    -- v2 is the fixed version of the original stamp block.
    -- v3 adds a quiGroupFrames.enabled rescue stamp for users who lived
    -- through the default=true window (see end of this function).
    local currentVersion = rawProfile._defaultsVersion or 0
    if currentVersion >= 3 then return end

    -- Check if this is an existing profile (has any real data).
    -- Brand-new profiles have no keys in the raw SV table.
    local hasData = false
    for k in pairs(rawProfile) do
        if k ~= "_defaultsVersion" then
            hasData = true
            break
        end
    end
    if not hasData then
        -- New profile — just stamp version, let new defaults apply
        rawset(rawProfile, "_defaultsVersion", 3)
        return
    end

    -- Helper: stamp old value at path only if user never set it.
    -- path is an array of keys, e.g. {"general", "skinGameMenu"}.
    -- IMPORTANT: If the parent table doesn't exist in raw SV, skip the stamp.
    -- Creating intermediate tables with rawset pollutes the SV and can shadow
    -- AceDB defaults or confuse later migrations (e.g. containers schema).
    -- A missing parent means the user never configured that subtree at all,
    -- so new defaults are appropriate for them.
    local function stamp(path, oldValue)
        -- Walk raw profile to the parent table
        local raw = rawProfile
        for i = 1, #path - 1 do
            raw = raw and rawget(raw, path[i])
        end
        -- Parent doesn't exist in raw data — user never touched this subtree, skip
        if raw == nil then return end
        -- Parent exists; only stamp if user never set this specific key
        local key = path[#path]
        if rawget(raw, key) == nil then
            rawset(raw, key, oldValue)
        end
        -- If rawget(raw, key) ~= nil, user explicitly set it — leave it alone
    end

    -- v2 stamp block: only for profiles that haven't been through it yet.
    -- Re-running on v2+ profiles would be a no-op for already-stamped keys
    -- but would be actively wrong for `quiGroupFrames.enabled`, since users
    -- in the default=true window have a nil raw value that we now want to
    -- preserve as `true`, not overwrite with `false`. See v3 block below.
    if currentVersion < 2 then
    ---------------------------------------------------------------------------
    -- General Settings (false → true flips)
    ---------------------------------------------------------------------------
    stamp({"general", "skinGameMenu"}, false)
    stamp({"general", "addQUIButton"}, false)
    stamp({"general", "skinOverrideActionBar"}, false)
    stamp({"general", "skinObjectiveTracker"}, false)
    stamp({"general", "hideObjectiveTrackerBorder"}, false)
    stamp({"general", "skinAuctionHouse"}, false)
    stamp({"general", "skinCraftingOrders"}, false)
    stamp({"general", "skinProfessions"}, false)

    ---------------------------------------------------------------------------
    -- QoL Settings
    ---------------------------------------------------------------------------
    stamp({"general", "autoAcceptQuest"}, false)
    stamp({"general", "autoTurnInQuest"}, false)
    stamp({"general", "autoSelectGossip"}, false)
    stamp({"general", "autoCombatLog"}, false)
    stamp({"general", "autoCombatLogRaid"}, false)

    ---------------------------------------------------------------------------
    -- Focus Cast Alert
    ---------------------------------------------------------------------------
    stamp({"general", "focusCastAlert", "enabled"}, false)

    ---------------------------------------------------------------------------
    -- Consumable Check
    ---------------------------------------------------------------------------
    stamp({"general", "consumableCheckEnabled"}, false)
    stamp({"general", "consumableExpirationWarning"}, false)

    ---------------------------------------------------------------------------
    -- CDM Essential Cooldown Viewer — row layout changes
    ---------------------------------------------------------------------------
    local essRows = {"row1", "row2", "row3"}
    local essOldIconCount = {8, 8, 8}
    local essOldPadding = {2, 2, 2}
    local essOldStackOffsetY = {2, 2, 2}
    local essOldYOffset = {0, 3, 0}
    for i, row in ipairs(essRows) do
        stamp({"ncdm", "EssentialCooldownViewer", row, "iconCount"}, essOldIconCount[i])
        stamp({"ncdm", "EssentialCooldownViewer", row, "padding"}, essOldPadding[i])
        stamp({"ncdm", "EssentialCooldownViewer", row, "stackOffsetY"}, essOldStackOffsetY[i])
        stamp({"ncdm", "EssentialCooldownViewer", row, "yOffset"}, essOldYOffset[i])
    end

    ---------------------------------------------------------------------------
    -- CDM Utility Cooldown Viewer — row layout changes
    ---------------------------------------------------------------------------
    local utilOldIconCount = {6, 0, 0}
    local utilOldPadding = {2, 2, 2}
    local utilOldStackOffsetY = {0, 0, 0}
    local utilOldYOffset = {0, 8, 4}
    for i, row in ipairs(essRows) do
        stamp({"ncdm", "UtilityCooldownViewer", row, "iconCount"}, utilOldIconCount[i])
        stamp({"ncdm", "UtilityCooldownViewer", row, "padding"}, utilOldPadding[i])
        stamp({"ncdm", "UtilityCooldownViewer", row, "stackOffsetY"}, utilOldStackOffsetY[i])
        stamp({"ncdm", "UtilityCooldownViewer", row, "yOffset"}, utilOldYOffset[i])
    end

    ---------------------------------------------------------------------------
    -- CDM Buff container
    ---------------------------------------------------------------------------
    stamp({"ncdm", "buff", "iconSize"}, 32)
    stamp({"ncdm", "buff", "borderSize"}, 1)
    stamp({"ncdm", "buff", "padding"}, 4)
    stamp({"ncdm", "buff", "durationSize"}, 14)
    stamp({"ncdm", "buff", "durationOffsetY"}, 8)
    stamp({"ncdm", "buff", "durationAnchor"}, "TOP")
    stamp({"ncdm", "buff", "stackSize"}, 14)
    stamp({"ncdm", "buff", "stackOffsetY"}, -8)

    ---------------------------------------------------------------------------
    -- CDM containers (target debuff) — mirrors buff changes
    ---------------------------------------------------------------------------
    -- containers[1].essential rows
    for i, row in ipairs(essRows) do
        stamp({"ncdm", "containers", 1, "essential", row, "iconCount"}, essOldIconCount[i])
        stamp({"ncdm", "containers", 1, "essential", row, "padding"}, essOldPadding[i])
        stamp({"ncdm", "containers", 1, "essential", row, "stackOffsetY"}, essOldStackOffsetY[i])
        stamp({"ncdm", "containers", 1, "essential", row, "yOffset"}, essOldYOffset[i])
    end
    -- containers[1].utility rows
    for i, row in ipairs(essRows) do
        stamp({"ncdm", "containers", 1, "utility", row, "iconCount"}, utilOldIconCount[i])
        stamp({"ncdm", "containers", 1, "utility", row, "padding"}, utilOldPadding[i])
        stamp({"ncdm", "containers", 1, "utility", row, "stackOffsetY"}, utilOldStackOffsetY[i])
        stamp({"ncdm", "containers", 1, "utility", row, "yOffset"}, utilOldYOffset[i])
    end
    -- containers[1].buff (aura)
    stamp({"ncdm", "containers", 1, "buff", "iconSize"}, 32)
    stamp({"ncdm", "containers", 1, "buff", "borderSize"}, 1)
    stamp({"ncdm", "containers", 1, "buff", "padding"}, 4)
    stamp({"ncdm", "containers", 1, "buff", "durationSize"}, 14)
    stamp({"ncdm", "containers", 1, "buff", "durationOffsetY"}, 8)
    stamp({"ncdm", "containers", 1, "buff", "durationAnchor"}, "TOP")
    stamp({"ncdm", "containers", 1, "buff", "stackSize"}, 14)
    stamp({"ncdm", "containers", 1, "buff", "stackOffsetY"}, -8)

    ---------------------------------------------------------------------------
    -- CDM Visibility
    ---------------------------------------------------------------------------
    stamp({"ncdm", "cdmVisibility", "showWhenTargetExists"}, true)
    stamp({"ncdm", "cdmVisibility", "hideWhenMounted"}, false)
    stamp({"ncdm", "cdmVisibility", "hideWhenFlying"}, false)
    stamp({"ncdm", "cdmVisibility", "hideWhenSkyriding"}, false)
    stamp({"ncdm", "cdmVisibility", "dontHideInDungeonsRaids"}, false)

    ---------------------------------------------------------------------------
    -- Unitframes Visibility
    ---------------------------------------------------------------------------
    stamp({"ncdm", "unitframesVisibility", "showWhenHealthBelow100"}, false)
    stamp({"ncdm", "unitframesVisibility", "alwaysShowCastbars"}, false)
    stamp({"ncdm", "unitframesVisibility", "hideWhenMounted"}, false)
    stamp({"ncdm", "unitframesVisibility", "hideWhenFlying"}, false)
    stamp({"ncdm", "unitframesVisibility", "hideWhenSkyriding"}, false)
    stamp({"ncdm", "unitframesVisibility", "dontHideInDungeonsRaids"}, false)

    ---------------------------------------------------------------------------
    -- Custom Trackers Visibility
    ---------------------------------------------------------------------------
    stamp({"ncdm", "customTrackersVisibility", "hideWhenMounted"}, false)
    stamp({"ncdm", "customTrackersVisibility", "hideWhenFlying"}, false)
    stamp({"ncdm", "customTrackersVisibility", "hideWhenSkyriding"}, false)
    stamp({"ncdm", "customTrackersVisibility", "dontHideInDungeonsRaids"}, false)

    ---------------------------------------------------------------------------
    -- Action Bars Visibility
    ---------------------------------------------------------------------------
    stamp({"ncdm", "actionBarsVisibility", "hideWhenMounted"}, false)
    stamp({"ncdm", "actionBarsVisibility", "hideWhenInVehicle"}, false)
    stamp({"ncdm", "actionBarsVisibility", "hideWhenFlying"}, false)
    stamp({"ncdm", "actionBarsVisibility", "hideWhenSkyriding"}, false)
    stamp({"ncdm", "actionBarsVisibility", "dontHideInDungeonsRaids"}, false)

    ---------------------------------------------------------------------------
    -- CDM Keybinds + Rotation Helper (Essential & Utility viewers)
    ---------------------------------------------------------------------------
    stamp({"ncdm", "EssentialCooldownViewer", "showKeybinds"}, false)
    stamp({"ncdm", "EssentialCooldownViewer", "showRotationHelper"}, false)
    stamp({"ncdm", "EssentialCooldownViewer", "rotationHelperThickness"}, 2)
    stamp({"ncdm", "UtilityCooldownViewer", "showKeybinds"}, false)
    stamp({"ncdm", "UtilityCooldownViewer", "showRotationHelper"}, false)
    stamp({"ncdm", "UtilityCooldownViewer", "rotationHelperThickness"}, 2)

    ---------------------------------------------------------------------------
    -- Power Bars (Primary)
    ---------------------------------------------------------------------------
    stamp({"ncdm", "powerBar", "borderSize"}, 1)
    stamp({"ncdm", "powerBar", "width"}, 326)
    stamp({"ncdm", "powerBar", "textSize"}, 16)
    stamp({"ncdm", "powerBar", "textX"}, 1)
    stamp({"ncdm", "powerBar", "textY"}, 3)
    stamp({"ncdm", "powerBar", "tickThickness"}, 2)
    stamp({"ncdm", "powerBar", "lockedToEssential"}, false)

    ---------------------------------------------------------------------------
    -- Power Bars (Secondary)
    ---------------------------------------------------------------------------
    stamp({"ncdm", "secondaryPowerBar", "width"}, 326)
    stamp({"ncdm", "secondaryPowerBar", "textSize"}, 14)
    stamp({"ncdm", "secondaryPowerBar", "tickThickness"}, 2)
    stamp({"ncdm", "secondaryPowerBar", "lockedToEssential"}, false)
    stamp({"ncdm", "secondaryPowerBar", "lockedToPrimary"}, true)

    ---------------------------------------------------------------------------
    -- Reticle (GCD tracker)
    ---------------------------------------------------------------------------
    stamp({"ncdm", "reticle", "enabled"}, false)
    stamp({"ncdm", "reticle", "ringStyle"}, "standard")
    stamp({"ncdm", "reticle", "hideOutOfCombat"}, false)

    ---------------------------------------------------------------------------
    -- Tooltips
    ---------------------------------------------------------------------------
    stamp({"general", "tooltips", "cursorAnchor"}, "TOPLEFT")
    stamp({"general", "tooltips", "cursorOffsetX"}, 16)
    stamp({"general", "tooltips", "cursorOffsetY"}, -16)
    stamp({"general", "tooltips", "hideInCombat"}, true)
    stamp({"general", "tooltips", "classColorName"}, false)
    stamp({"general", "tooltips", "bgOpacity"}, 0.95)
    stamp({"general", "tooltips", "borderUseClassColor"}, false)
    stamp({"general", "tooltips", "showSpellIDs"}, false)
    stamp({"general", "tooltips", "showPlayerItemLevel"}, false)
    stamp({"general", "tooltips", "combatKey"}, "SHIFT")

    ---------------------------------------------------------------------------
    -- Action Bars (style)
    ---------------------------------------------------------------------------
    stamp({"actionBars", "style", "backdropAlpha"}, 0.8)
    stamp({"actionBars", "style", "glossAlpha"}, 0.6)
    stamp({"actionBars", "style", "showMacroNames"}, false)
    stamp({"actionBars", "style", "keybindAnchor"}, "TOPLEFT")
    stamp({"actionBars", "style", "keybindOffsetX"}, 4)
    stamp({"actionBars", "style", "keybindOffsetY"}, -4)
    stamp({"actionBars", "style", "macroNameOffsetY"}, 4)
    stamp({"actionBars", "style", "countOffsetX"}, -4)
    stamp({"actionBars", "style", "countOffsetY"}, 4)
    stamp({"actionBars", "style", "rangeIndicator"}, false)
    stamp({"actionBars", "style", "usabilityIndicator"}, false)

    ---------------------------------------------------------------------------
    -- Action Bars (fade)
    ---------------------------------------------------------------------------
    stamp({"actionBars", "fade", "enabled"}, true)
    stamp({"actionBars", "fade", "linkBars1to8"}, false)

    ---------------------------------------------------------------------------
    -- Unit Frames — absorbs opacity
    ---------------------------------------------------------------------------
    stamp({"quiUnitFrames", "player", "absorbs", "opacity"}, 0.3)
    stamp({"quiUnitFrames", "target", "absorbs", "opacity"}, 0.3)

    ---------------------------------------------------------------------------
    -- Group Frames
    ---------------------------------------------------------------------------
    stamp({"quiGroupFrames", "enabled"}, false)
    stamp({"quiGroupFrames", "party", "layout", "spacing"}, 2)
    stamp({"quiGroupFrames", "party", "absorbs", "opacity"}, 0.3)
    stamp({"quiGroupFrames", "party", "dimensions", "partyWidth"}, 200)
    stamp({"quiGroupFrames", "party", "dimensions", "partyHeight"}, 40)

    -- Raid absorbs
    stamp({"quiGroupFrames", "raid", "absorbs", "opacity"}, 0.3)

    ---------------------------------------------------------------------------
    -- Cleanup: remove bogus numeric key created by v1 stamp bug.
    -- v1 created containers[1] (numeric) which conflicts with the string-keyed
    -- container schema used by the _containersMigrated migration.
    ---------------------------------------------------------------------------
    local rawNcdm = rawget(rawProfile, "ncdm")
    if rawNcdm then
        local rawContainers = rawget(rawNcdm, "containers")
        if rawContainers and rawget(rawContainers, 1) then
            rawset(rawContainers, 1, nil)
        end
    end
    end  -- end v2 stamp block

    ---------------------------------------------------------------------------
    -- v3: rescue quiGroupFrames.enabled for users from the default=true window
    --
    -- Between commits 78b420b ("Overhaul defaults for better OOTB experience")
    -- and 6e50421 ("Migration overhaul"), the default for
    -- quiGroupFrames.enabled was `true`. Users who installed during that window
    -- and never explicitly toggled the setting had no `enabled` key written to
    -- their SavedVariables (AceDB strips keys whose value matches the default).
    --
    -- After 6e50421 reverted the default back to `false`, AceDB started
    -- serving `false` for those same users — silently turning off their group
    -- frames. The v2 stamp block above can't help: those users were already
    -- stamped at v2, so the early return prevented it from running.
    --
    -- This v3 stamp targets that exact population: profiles that already
    -- reached v2 AND still have `quiGroupFrames` in raw SV but no `enabled`
    -- key. For them we can be confident their lived experience was `true`
    -- (otherwise the key would be present with an explicit value), so we
    -- pin it back to `true`. Profiles freshly upgrading from < v2 are
    -- unaffected — the v2 block above already handled them with the
    -- pre-flip `false` default.
    if currentVersion >= 2 then
        local rawGF = rawget(rawProfile, "quiGroupFrames")
        if type(rawGF) == "table" and rawget(rawGF, "enabled") == nil then
            rawset(rawGF, "enabled", true)
        end
    end

    ---------------------------------------------------------------------------
    -- Shadow-defaults pin: handles all future default flips for paths in
    -- TRACKED_DEFAULTS. No-op on the very first load that introduces a path
    -- (no previous shadow to compare against) — that's why one-shot rescues
    -- like the v3 block above are still needed for the existing broken
    -- population at the moment a path is added.
    ---------------------------------------------------------------------------
    PinTrackedDefaults(rawProfile)

    ---------------------------------------------------------------------------
    -- Done — stamp version directly on the raw profile
    ---------------------------------------------------------------------------
    rawset(rawProfile, "_defaultsVersion", 3)
end

-- Iterate every stored profile and stamp old defaults on each. Previously
-- this only operated on db:GetCurrentProfile(), so unused profiles never
-- got their defaults stamped and silently inherited new default values on
-- upgrade. Now every profile in db.sv.profiles is processed independently.
local function StampOldDefaults(db)
    if not (db and db.sv and db.sv.profiles) then return end
    for _, rawProfile in pairs(db.sv.profiles) do
        StampOldDefaultsOnRawProfile(rawProfile)
    end
end

---------------------------------------------------------------------------
-- BackwardsCompat: facade that orchestrates both tiers
---------------------------------------------------------------------------

function QUI:BackwardsCompat()
    -- Tier 0: Raw SV defaults stamp (must run before AceDB fills defaults)
    if self.db then
        StampOldDefaults(self.db)
    end

    -- Tier 1: All profile-level migrations (consolidated in migrations.lua)
    if ns.Migrations and ns.Migrations.Run then
        ns.Migrations.Run(self.db)
    end

    -- Tier 2: Shadow-defaults snapshot. After migrations have settled,
    -- record the currently-shipping defaults for tracked fragile paths
    -- on every stored profile, so the *next* load can detect default
    -- flips and pin previous values via PinTrackedDefaults.
    if self.db then
        WriteShippedDefaultsSnapshotAll(self.db)
    end

    -- Global/char structure housekeeping (not profile-specific)
    if not self.db.global then
        self:DebugPrint("DB Global not found")
        self.db.global = {
            isDone = false,
            lastVersion = 0,
            imports = {}
        }
    end

    if not self.db.global.isDone then
        self.db.global.isDone = false
    end
    if not self.db.global.lastVersion then
        self.db.global.lastVersion = 0
    end
    if not self.db.global.imports then
        self.db.global.imports = {}
    end

    -- Initialize spec-specific tracker spell storage
    if not self.db.global.specTrackerSpells then
        self.db.global.specTrackerSpells = {}
    end

    -- Ensure db.char exists and has debug table
    if self.db.char then
        if not self.db.char.debug then
            self.db.char.debug = { reload = false }
        end

        -- If lastVersion is specified in self.db.char, and not in db.global - move it to db.global and remove lastVersion from char
        if self.db.char.lastVersion and not self.db.global.lastVersion then
            self:DebugPrint("Last version found in char profile, but not global.")
            self.db.global.lastVersion = self.db.char.lastVersion
            self.db.char.lastVersion = nil
        end
    end

    -----------------------------------------------------------------------
    -- Scrub removed char-level keys
    -- Mirrors the StampOldDefaults/Migrations.Run pattern of iterating
    -- every stored character table, not just db:GetCurrentProfile()'s
    -- char. That way alt characters get cleaned up on first load of any
    -- character, without requiring us to log in on each alt.
    --
    -- devOptionsV2 (removed in Options V2 Phase 5): was a char-level
    -- scaffolding flag that toggled between V1 and V2 options panels.
    -- V2 is now the only panel, so nil the key from raw SV on every
    -- stored character.
    -----------------------------------------------------------------------
    if self.db and self.db.sv and type(self.db.sv.chars) == "table" then
        for _, rawChar in pairs(self.db.sv.chars) do
            if type(rawChar) == "table" then
                rawset(rawChar, "devOptionsV2", nil)
            end
        end
    elseif self.db and self.db.char then
        -- Stub/fallback path: no sv.chars table available, scrub the
        -- active char proxy directly.
        self.db.char.devOptionsV2 = nil
    end

    -- Check if old profile-based imports exist
    if QUI_DB and QUI_DB.profiles and QUI_DB.profiles.Default then
        self:DebugPrint("Profiles.Default.imports Exists: " .. tostring(not (not QUI_DB.profiles.Default.imports)))
        self:DebugPrint("global.imports Exists: " .. tostring(not (not self.db.global.imports)))
        self:DebugPrint("global.imports is {}: " .. tostring(self.db.global.imports == {}))

        -- if imports are in default profile db, and not in global, move them over
        if QUI_DB.profiles.Default.imports and (not self.db.global.imports or next(self.db.global.imports) == nil) then
            self:DebugPrint("Import Data found in profile imports but not global imports.")
            self.db.global.imports = QUI_DB.profiles.Default.imports
        end
    end
end
