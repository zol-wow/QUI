---------------------------------------------------------------------------
-- QUI Backwards Compatibility
-- Tier 0: StampOldDefaults (raw SV access, must run before AceDB defaults)
-- Tier 1: Delegates to ns.Migrations.Run() for all profile-level migrations
-- Also handles global/char structure housekeeping.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Shadow-defaults mechanism
--
-- Older builds deep-copied the complete defaults table into every profile as
-- rawProfile._shippedDefaults. That made future default flips detectable, but
-- it also duplicated thousands of default values per profile in SavedVariables
-- and forced a large recursive copy on every reload.
--
-- Keep the same default-flip protection, but store the last-shipped profile
-- defaults once in global storage. Existing per-profile snapshots are consumed
-- first, then pruned after the account-level snapshot is refreshed.
---------------------------------------------------------------------------

local DeepCopy = ns.Helpers.DeepCopy
local GLOBAL_SHIPPED_DEFAULTS_KEY = "_shippedProfileDefaults"
ns.Compatibility = ns.Compatibility or {}

local StampOldDefaults

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

local function PinTrackedDefaults(rawProfile, fallbackShadow)
    local profileShadow = rawget(rawProfile, "_shippedDefaults")
    local shadow = type(profileShadow) == "table" and profileShadow or fallbackShadow
    if type(shadow) ~= "table" then return end
    if not (ns.defaults and ns.defaults.profile) then return end
    PinDefaultsRecursive(shadow, ns.defaults.profile, rawProfile)
end

local function GetGlobalShippedDefaultsSnapshot(db)
    local global = db and db.global
    local shadow = global and global[GLOBAL_SHIPPED_DEFAULTS_KEY]
    return type(shadow) == "table" and shadow or nil
end

local function WriteGlobalShippedDefaultsSnapshot(db)
    if not db then return end
    if not (ns.defaults and ns.defaults.profile) then return end

    if not db.global then
        db.global = {}
    end

    local existing = db.global[GLOBAL_SHIPPED_DEFAULTS_KEY]
    if type(existing) == "table" and DeepEqual(existing, ns.defaults.profile) then
        return
    end

    db.global[GLOBAL_SHIPPED_DEFAULTS_KEY] = DeepCopy(ns.defaults.profile)
end

-- Remove legacy per-profile snapshots after migrations have consumed them.
-- The refreshed account-level snapshot above preserves the default-flip guard.
local function PruneShippedDefaultsSnapshot(rawProfile)
    if type(rawProfile) ~= "table" then return end
    rawset(rawProfile, "_shippedDefaults", nil)
end

local function PruneShippedDefaultsSnapshotAll(db)
    if not db then return end

    local profiles = db.sv and db.sv.profiles
    if type(profiles) == "table" then
        for _, rawProfile in pairs(profiles) do
            PruneShippedDefaultsSnapshot(rawProfile)
        end
        return
    end

    PruneShippedDefaultsSnapshot(db.profile)
end

local function RunShippedDefaultsMaintenance(db)
    StampOldDefaults(db)
    PruneShippedDefaultsSnapshotAll(db)
    WriteGlobalShippedDefaultsSnapshot(db)
end

ns.Compatibility.RunShippedDefaultsMaintenance = RunShippedDefaultsMaintenance

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
local function StampOldDefaultsOnRawProfile(rawProfile, fallbackShadow)
    if not rawProfile then return end  -- brand-new profile, use new defaults

    -- Already migrated through the one-shot defaults stamps. Still consume
    -- the shipped-default shadow so future default flips remain protected.
    -- v1 had a bug that created intermediate tables via rawset, polluting the SV.
    -- v2 is the fixed version of the original stamp block.
    -- v3 adds a quiGroupFrames.enabled rescue stamp for users who lived
    -- through the default=true window (see end of this function).
    local currentVersion = rawProfile._defaultsVersion or 0
    if currentVersion >= 3 then
        PinTrackedDefaults(rawProfile, fallbackShadow)
        return
    end

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

    -- Legacy default-stamp blocks (defaults v1/v2) were removed in 4.0: every
    -- profile new enough to keep (schema >= 31, the 3.5.11 floor) is already at
    -- _defaultsVersion 3 and returns early above; older profiles are floored
    -- (wiped + reseeded) by Migrations. The v3 rescue below is retained as a
    -- harmless no-op safety net for any lingering _defaultsVersion==2 profile.

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
    PinTrackedDefaults(rawProfile, fallbackShadow)

    ---------------------------------------------------------------------------
    -- Done — stamp version directly on the raw profile
    ---------------------------------------------------------------------------
    rawset(rawProfile, "_defaultsVersion", 3)
end

-- Iterate every stored profile and stamp old defaults on each. Previously
-- this only operated on db:GetCurrentProfile(), so unused profiles never
-- got their defaults stamped and silently inherited new default values on
-- upgrade. Now every profile in db.sv.profiles is processed independently.
function StampOldDefaults(db)
    if not db then return end

    local fallbackShadow = GetGlobalShippedDefaultsSnapshot(db)
    local profiles = db.sv and db.sv.profiles
    if type(profiles) == "table" then
        for _, rawProfile in pairs(profiles) do
            StampOldDefaultsOnRawProfile(rawProfile, fallbackShadow)
        end
        return
    end

    StampOldDefaultsOnRawProfile(db.profile, fallbackShadow)
end

---------------------------------------------------------------------------
-- BackwardsCompat: facade that orchestrates both tiers
---------------------------------------------------------------------------

-- Pre-3.5.11 floor reseed. Migrations backs up + wipes any profile older than
-- the schema floor and flags it `_needsStarterReseed`. Seed the shipped
-- new-profile defaults onto each flagged raw profile and clear the flag.
--
-- Runs here in BackwardsCompat (OnEnable, BEFORE modules build at
-- PLAYER_LOGIN), so a floored ACTIVE profile is reseeded before its modules
-- initialize -- no UI reload, and no Starter Profile import (ns.ApplyNewProfileSeed lives
-- in core). AceDB fills the remaining legacy defaults when each profile is next
-- activated; the floor's `_migrationBackup` rollback snapshot is left intact.
local function ReseedStarterFlaggedProfiles(db)
    if not db or not db.sv or type(db.sv.profiles) ~= "table" then return end
    if not ns.ApplyNewProfileSeed then return end
    for _, rawProfile in pairs(db.sv.profiles) do
        if type(rawProfile) == "table" and rawget(rawProfile, "_needsStarterReseed") then
            ns.ApplyNewProfileSeed(rawProfile)
            rawset(rawProfile, "_needsStarterReseed", nil)
        end
    end
end

function QUI:BackwardsCompat()
    -- Tier 0: Raw SV defaults stamp (must run before AceDB fills defaults)
    if self.db then
        RunShippedDefaultsMaintenance(self.db)
    end

    -- Tier 1: All profile-level migrations (consolidated in migrations.lua)
    if ns.Migrations and ns.Migrations.Run then
        ns.Migrations.Run(self.db)
    end

    -- Tier 2: reseed any profile the migration floor wiped (pre-3.5.11) with
    -- the shipped new-profile defaults, before modules build.
    ReseedStarterFlaggedProfiles(self.db)

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
        self:DebugPrint("global.imports is {}: " .. tostring(next(self.db.global.imports) == nil))

        -- if imports are in default profile db, and not in global, move them over
        if QUI_DB.profiles.Default.imports and (not self.db.global.imports or next(self.db.global.imports) == nil) then
            self:DebugPrint("Import Data found in profile imports but not global imports.")
            self.db.global.imports = QUI_DB.profiles.Default.imports
        end
    end
end
