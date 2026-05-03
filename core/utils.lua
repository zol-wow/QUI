---------------------------------------------------------------------------
-- QUI Shared Helpers
-- Common utility functions used across multiple modules
-- This file should be loaded early (before other utils) via utils.xml
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Ensure namespace tables exist
ns.Helpers = ns.Helpers or {}
local Helpers = ns.Helpers
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local select = select
local table_remove = table.remove

-- Cache LibSharedMedia reference
local LSM = LibStub("LibSharedMedia-3.0", true)
ns.LSM = LSM

-- Resolve asset paths against the actual addon folder name (e.g. "QUI", "QUI5",
-- "QUI-main"), so hardcoding a single folder name doesn't break renamed installs.
Helpers.AssetPath = "Interface\\AddOns\\" .. ADDON_NAME .. "\\assets\\"

-- Cache global secret-value API functions at file scope (avoids repeated _G lookups)
local issecretvalue = _G.issecretvalue
local canaccesstable = _G.canaccesstable

local function GetCore()
    return (_G.QUI and _G.QUI.QUICore) or ns.Addon
end

---------------------------------------------------------------------------
-- SECRET VALUE UTILITIES (Patch 12.0+)
-- Combat-related APIs can return "secret values" in restricted contexts.
-- These helpers provide safe operations that won't error on secrets.
---------------------------------------------------------------------------

--- Check if a value is a secret value (12.x combat restriction)
--- @param value any The value to check
--- @return boolean True if value is a secret value
function Helpers.IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

--- Check whether any value in a vararg list is secret.
--- @return boolean True if at least one value is a secret value
function Helpers.HasSecretValue(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue(select(i, ...)) then
            return true
        end
    end
    return false
end

--- Check if a table can be accessed (not tainted/restricted)
--- @param tbl table The table to check
--- @return boolean True if table can be accessed safely
function Helpers.CanAccessTable(tbl)
    return not canaccesstable or canaccesstable(tbl)
end

--- Safely get a value, returning fallback if it's a secret
--- @param value any The potentially secret value
--- @param fallback any Value to return if secret (default: nil)
--- @return any The value or fallback
function Helpers.SafeValue(value, fallback)
    if issecretvalue and issecretvalue(value) then
        return fallback
    end
    return value
end

--- Safely compare two values (returns false if either is secret)
--- @param a any First value
--- @param b any Second value
--- @return boolean|nil Result of comparison, or nil if can't compare
function Helpers.SafeCompare(a, b)
    if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then
        return nil
    end
    return a == b
end

--- Safely convert to number
--- @param value any The potentially secret value
--- @param fallback number Value to return if secret or not a number
--- @return number The number or fallback
function Helpers.SafeToNumber(value, fallback)
    if issecretvalue and issecretvalue(value) then
        return fallback or 0
    end
    -- No pcall needed: tonumber never errors on non-secret values
    local num = tonumber(value)
    if num then
        return num
    end
    return fallback or 0
end

--- Safely convert to string
--- @param value any The potentially secret value
--- @param fallback string Value to return if secret or conversion fails (default: "")
--- @return string The string or fallback
function Helpers.SafeToString(value, fallback)
    fallback = fallback or ""
    if issecretvalue and issecretvalue(value) then
        return fallback
    end
    -- No pcall needed: tostring never errors on non-secret values
    local str = tostring(value)
    if str then
        return str
    end
    return fallback
end

--- Is an aura sourced from the player / pet / vehicle?
--- Taint-safe: reads sourceUnit / sourceGUID / isFromPlayerOrPlayerPet via
--- SafeValue so secret values become nil instead of returning into Lua.
--- @param auraData table AuraData struct from C_UnitAuras.*
--- @param strictSource boolean? When true, require explicit sourceUnit/sourceGUID
---        to match; do not trust isFromPlayerOrPlayerPet alone. Use for defenses
---        against Blizzard viewer children that report "player" while carrying
---        a foreign aura instance.
--- @return boolean
function Helpers.IsAuraOwnedByPlayerOrPet(auraData, strictSource)
    if not auraData then return false end

    local ownedFlag = Helpers.SafeValue(auraData.isFromPlayerOrPlayerPet, nil)
    if ownedFlag ~= nil and not strictSource then
        return ownedFlag == true
    end

    local sourceUnit = Helpers.SafeValue(auraData.sourceUnit, nil)
    if sourceUnit then
        if sourceUnit == "player" or sourceUnit == "pet" or sourceUnit == "vehicle" then
            return true
        end
        if UnitIsUnit then
            if UnitExists("player") and UnitIsUnit(sourceUnit, "player") then return true end
            if UnitExists("pet") and UnitIsUnit(sourceUnit, "pet") then return true end
            if UnitExists("vehicle") and UnitIsUnit(sourceUnit, "vehicle") then return true end
        end
    end

    local sourceGUID = Helpers.SafeValue(auraData.sourceGUID, nil)
    if sourceGUID then
        local playerGUID = UnitGUID and UnitGUID("player") or nil
        local petGUID = UnitGUID and UnitGUID("pet") or nil
        local vehicleGUID = UnitGUID and UnitGUID("vehicle") or nil
        return sourceGUID == playerGUID or sourceGUID == petGUID or sourceGUID == vehicleGUID
    end

    if ownedFlag ~= nil then
        return strictSource and false or ownedFlag == true
    end

    return false
end

---------------------------------------------------------------------------
-- DATABASE ACCESS HELPERS
-- Standardized pattern for accessing QUICore database profiles
---------------------------------------------------------------------------

--- Get QUICore reference (with _G.QUI fallback)
--- Drop-in replacement for the local GetCore() pattern used across 30+ files.
--- @return table|nil QUICore addon object
function Helpers.GetCore()
    return (_G.QUI and _G.QUI.QUICore) or ns.Addon
end


--- Get the full profile database
--- @return table|nil The profile table or nil
function Helpers.GetProfile()
    local core = Helpers.GetCore()
    if core and core.db and core.db.profile then
        return core.db.profile
    end
    return nil
end

--- Create a DB getter function for a specific module
--- @param moduleName string The module key in the profile (e.g., "ncdm", "castbar")
--- @return function A function that returns the module's DB table or nil
function Helpers.CreateDBGetter(moduleName)
    return function()
        local profile = Helpers.GetProfile()
        if profile then
            return profile[moduleName]
        end
        return nil
    end
end

--- Get a specific module's database directly
--- @param moduleName string The module key in the profile
--- @return table|nil The module's DB table or nil
function Helpers.GetModuleDB(moduleName)
    local profile = Helpers.GetProfile()
    if profile then
        return profile[moduleName]
    end
    return nil
end

--- Returns the active consumable-macros settings table.
--- Picks db.char.consumableMacros when its characterSpecific flag is true,
--- otherwise db.profile.general.consumableMacros. Used by the macro module
--- and the settings UI so both agree on which scope is currently active.
--- @return table|nil The active settings table or nil if QUI core/db is not ready
function Helpers.GetConsumableMacrosDB()
    local core = Helpers.GetCore()
    if not core or not core.db then return nil end
    local charT = core.db.char and core.db.char.consumableMacros
    if charT and charT.characterSpecific then
        return charT
    end
    local profile = core.db.profile
    return profile and profile.general and profile.general.consumableMacros
end

--- Returns the per-character consumable-macros table (where characterSpecific
--- itself lives). Always returns the char-scope table regardless of which
--- scope is currently active.
--- @return table|nil
function Helpers.GetCharConsumableMacrosDB()
    local core = Helpers.GetCore()
    return core and core.db and core.db.char and core.db.char.consumableMacros
end

--- Deep-copy a defaults table (shallow values, recursive sub-tables).
--- Used by GetModuleSettings to repair corrupted entries.
local function DeepCopyDefaults(src)
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = type(v) == "table" and DeepCopyDefaults(v) or v
    end
    return copy
end

-- Merge missing defaults into an existing settings table without
-- overwriting user-saved values. Returns true if the existing data had a
-- structural mismatch (table default replaced by a scalar), which callers
-- can treat as corruption and rebuild from defaults.
local function MergeMissingDefaults(target, defaults)
    local hadStructuralMismatch = false
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return hadStructuralMismatch
    end

    for k, v in pairs(defaults) do
        local cur = target[k]
        if cur == nil then
            target[k] = type(v) == "table" and DeepCopyDefaults(v) or v
        elseif type(v) == "table" then
            if type(cur) ~= "table" then
                hadStructuralMismatch = true
            else
                if MergeMissingDefaults(cur, v) then
                    hadStructuralMismatch = true
                end
            end
        end
    end

    return hadStructuralMismatch
end

local function CreateDefaultAuraIndicatorRecord(indicatorType, index)
    indicatorType = indicatorType or "icon"
    local record = {
        id = indicatorType .. "_" .. tostring(index or 1),
        type = indicatorType,
        enabled = true,
    }

    if indicatorType == "bar" then
        record.orientation = "HORIZONTAL"
        record.thickness = 4
        record.length = 40
        record.matchFrameSize = false
        record.anchor = "BOTTOM"
        record.offsetX = 0
        record.offsetY = 0
        record.color = { 0.2, 0.8, 0.2, 1 }
        record.backgroundColor = { 0.2, 0.8, 0.2, 0.18 }
        record.borderSize = 1
        record.borderColor = { 0, 0, 0, 1 }
        record.hideBorder = false
        record.lowTimeThreshold = 0
        record.lowTimeColor = { 1, 0.2, 0.2, 1 }
    elseif indicatorType == "healthBarColor" then
        record.color = { 0.2, 0.8, 0.2, 1 }
        record.animation = "fill"
    end

    return record
end

local function NormalizeAuraIndicatorRecord(record, entryIndex, indicatorIndex)
    if type(record) ~= "table" then
        record = {}
    end

    local indicatorType = record.type
    if indicatorType ~= "icon" and indicatorType ~= "bar" and indicatorType ~= "healthBarColor" then
        indicatorType = "icon"
    end

    local defaults = CreateDefaultAuraIndicatorRecord(indicatorType, indicatorIndex)
    for key, value in pairs(defaults) do
        if record[key] == nil then
            record[key] = type(value) == "table" and DeepCopyDefaults(value) or value
        end
    end

    record.type = indicatorType
    record.id = record.id or (indicatorType .. "_" .. tostring(entryIndex or 1) .. "_" .. tostring(indicatorIndex or 1))
    if record.enabled == nil then
        record.enabled = true
    end

    if indicatorType == "bar" then
        if record.orientation ~= "VERTICAL" then
            record.orientation = "HORIZONTAL"
        end
        record.thickness = tonumber(record.thickness) or defaults.thickness
        record.length = tonumber(record.length) or defaults.length
        record.matchFrameSize = record.matchFrameSize == true
        record.anchor = record.anchor or defaults.anchor
        record.offsetX = tonumber(record.offsetX) or 0
        record.offsetY = tonumber(record.offsetY) or 0
        if type(record.color) ~= "table" then
            record.color = DeepCopyDefaults(defaults.color)
        end
        if type(record.backgroundColor) ~= "table" then
            record.backgroundColor = DeepCopyDefaults(defaults.backgroundColor)
        end
        if type(record.borderColor) ~= "table" then
            record.borderColor = DeepCopyDefaults(defaults.borderColor)
        end
        record.borderSize = tonumber(record.borderSize) or defaults.borderSize
        record.hideBorder = record.hideBorder == true
        record.lowTimeThreshold = tonumber(record.lowTimeThreshold) or 0
        if type(record.lowTimeColor) ~= "table" then
            record.lowTimeColor = DeepCopyDefaults(defaults.lowTimeColor)
        end
    elseif indicatorType == "healthBarColor" then
        if type(record.color) ~= "table" then
            record.color = DeepCopyDefaults(defaults.color)
        end
        if record.animation ~= "instant"
            and record.animation ~= "fill"
            and record.animation ~= "fade"
            and record.animation ~= "fillFade"
            and record.animation ~= "pulse" then
            record.animation = defaults.animation
        end
    end

    return record
end

function Helpers.NormalizeAuraIndicatorConfig(ai)
    if type(ai) ~= "table" then
        return nil
    end

    if type(ai.trackedSpells) ~= "table" then
        ai.trackedSpells = {}
    end
    if type(ai.entries) ~= "table" then
        ai.entries = {}
    end

    if #ai.entries == 0 then
        for spellID, enabled in pairs(ai.trackedSpells) do
            if enabled then
                local normalizedSpellID = tonumber(spellID) or spellID
                ai.entries[#ai.entries + 1] = {
                    id = "aura_" .. tostring(normalizedSpellID),
                    spellID = normalizedSpellID,
                    enabled = true,
                    indicators = {
                        CreateDefaultAuraIndicatorRecord("icon", 1),
                    },
                }
            end
        end
    end

    for idx = #ai.entries, 1, -1 do
        local entry = ai.entries[idx]
        if type(entry) ~= "table" or entry.spellID == nil then
            table_remove(ai.entries, idx)
        else
            entry.spellID = tonumber(entry.spellID) or entry.spellID
            entry.id = entry.id or ("aura_" .. tostring(entry.spellID) .. "_" .. tostring(idx))
            if entry.enabled == nil then
                entry.enabled = true
            end
            entry.onlyMine = entry.onlyMine == true
            if type(entry.indicators) ~= "table" then
                entry.indicators = {}
            end

            for indIdx = #entry.indicators, 1, -1 do
                if type(entry.indicators[indIdx]) ~= "table" then
                    table_remove(entry.indicators, indIdx)
                else
                    entry.indicators[indIdx] = NormalizeAuraIndicatorRecord(entry.indicators[indIdx], idx, indIdx)
                end
            end

            if #entry.indicators == 0 then
                entry.indicators[1] = CreateDefaultAuraIndicatorRecord("icon", 1)
            end
        end
    end

    return ai
end

--- Get module settings with defaults fallback
--- This is the standard pattern for modules to access their settings.
--- Creates the profile entry if it doesn't exist.
--- Detects structural corruption (e.g. a table default overwritten by a scalar)
--- and resets the module entry from defaults when found.
--- @param moduleName string The module key in the profile (e.g., "cooldownEffects", "castbar")
--- @param defaults table Default values to return/initialize if settings don't exist
--- @return table The module's settings table (never nil)
function Helpers.GetModuleSettings(moduleName, defaults)
    defaults = defaults or {}
    local profile = Helpers.GetProfile()
    if profile then
        if not profile[moduleName] then
            profile[moduleName] = DeepCopyDefaults(defaults)
        else
            local settings = profile[moduleName]
            -- Backfill newly-added keys into existing module tables so runtime
            -- code and the options UI read the same effective values.
            -- If a table-shaped default was overwritten by a scalar, treat the
            -- module settings as corrupted and rebuild from defaults.
            if MergeMissingDefaults(settings, defaults) then
                wipe(settings)
                MergeMissingDefaults(settings, defaults)
            end
        end
        return profile[moduleName]
    end
    return defaults
end

---------------------------------------------------------------------------
-- NCDM CUSTOM ENTRIES HELPERS
-- Character-scope data partitioned by profile and optionally by spec.
---------------------------------------------------------------------------

local function NormalizeNCDMCustomEntries(data)
    if type(data) ~= "table" then
        data = {}
    end

    if data.enabled == nil then
        data.enabled = true
    end
    if data.placement ~= "before" and data.placement ~= "after" then
        data.placement = "after"
    end
    if type(data.entries) ~= "table" then
        data.entries = {}
    end

    for i = #data.entries, 1, -1 do
        local entry = data.entries[i]
        if type(entry) ~= "table" then
            table.remove(data.entries, i)
        else
            if entry.enabled == nil then
                entry.enabled = true
            end
            if entry.position ~= nil then
                local pos = tonumber(entry.position)
                if pos and pos >= 1 then
                    entry.position = math.max(1, math.floor(pos))
                else
                    entry.position = nil
                end
            end
        end
    end

    return data
end

local function CloneNCDMCustomEntries(source)
    local cloned = {
        enabled = true,
        placement = "after",
        entries = {},
    }

    if type(source) ~= "table" then
        return cloned
    end

    if source.enabled ~= nil then
        cloned.enabled = source.enabled
    end
    if source.placement then
        cloned.placement = source.placement
    end

    if type(source.entries) == "table" then
        for _, entry in ipairs(source.entries) do
            if type(entry) == "table" then
                local copiedEntry = {}
                for k, v in pairs(entry) do
                    if type(v) == "table" then
                        local sub = {}
                        for sk, sv in pairs(v) do
                            sub[sk] = sv
                        end
                        copiedEntry[k] = sub
                    else
                        copiedEntry[k] = v
                    end
                end
                table.insert(cloned.entries, copiedEntry)
            end
        end
    end

    return NormalizeNCDMCustomEntries(cloned)
end

local function CreateNCDMSpecTemplate(sharedData)
    return NormalizeNCDMCustomEntries({
        enabled = (type(sharedData) == "table" and sharedData.enabled ~= nil) and sharedData.enabled or true,
        placement = (type(sharedData) == "table" and sharedData.placement) or "after",
        entries = {},
    })
end

--- Get the current specialization ID.
--- @return number|nil specID
function Helpers.GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if type(specID) ~= "number" then
        return nil
    end
    return specID
end

--- Resolve NCDM custom entries for the active profile/spec context.
--- Data is stored in db.char to survive profile switches, but partitioned by
--- profile name and (optionally) by spec when enabled per-profile.
--- @param trackerKey string "essential" or "utility"
--- @return table|nil
function Helpers.GetNCDMCustomEntries(trackerKey)
    if type(trackerKey) ~= "string" or trackerKey == "" then
        return nil
    end

    local core = Helpers.GetCore()
    if not (core and core.db and core.db.char and core.db.profile) then
        return nil
    end

    local charDB = core.db.char
    local profileDB = core.db.profile

    if type(charDB.ncdm) ~= "table" then
        charDB.ncdm = {}
    end
    if type(charDB.ncdm[trackerKey]) ~= "table" then
        charDB.ncdm[trackerKey] = {}
    end
    local trackerCharDB = charDB.ncdm[trackerKey]

    -- Legacy shared storage (kept for backward compatibility and as fallback seed).
    trackerCharDB.customEntries = NormalizeNCDMCustomEntries(trackerCharDB.customEntries)

    if type(trackerCharDB.customEntriesByProfile) ~= "table" then
        trackerCharDB.customEntriesByProfile = {}
    end

    local profileName = (core.db.GetCurrentProfile and core.db:GetCurrentProfile()) or "Default"
    local profileBucket = trackerCharDB.customEntriesByProfile[profileName]
    if type(profileBucket) ~= "table" then
        profileBucket = {}
        trackerCharDB.customEntriesByProfile[profileName] = profileBucket
    end

    if type(profileBucket.shared) ~= "table" then
        local legacyProfileData = profileDB and profileDB.ncdm and profileDB.ncdm[trackerKey] and profileDB.ncdm[trackerKey].customEntries
        local hasLegacyProfileData = type(legacyProfileData) == "table"
            and (
                (type(legacyProfileData.entries) == "table" and #legacyProfileData.entries > 0)
                or legacyProfileData.enabled ~= nil
                or legacyProfileData.placement ~= nil
            )
        if hasLegacyProfileData then
            profileBucket.shared = CloneNCDMCustomEntries(legacyProfileData)
        else
            profileBucket.shared = CloneNCDMCustomEntries(trackerCharDB.customEntries)
        end
    end
    profileBucket.shared = NormalizeNCDMCustomEntries(profileBucket.shared)

    local useSpecSpecific = profileDB and profileDB.ncdm and profileDB.ncdm.customEntriesSpecSpecific == true
    if not useSpecSpecific then
        return profileBucket.shared
    end

    if type(profileBucket.bySpec) ~= "table" then
        profileBucket.bySpec = {}
    end

    local specID = Helpers.GetCurrentSpecID()
    if not specID then
        return profileBucket.shared
    end

    local specKey = tostring(specID)
    if type(profileBucket.bySpec[specKey]) ~= "table" then
        profileBucket.bySpec[specKey] = CreateNCDMSpecTemplate(profileBucket.shared)
    end
    profileBucket.bySpec[specKey] = NormalizeNCDMCustomEntries(profileBucket.bySpec[specKey])
    return profileBucket.bySpec[specKey]
end

--- Seed the current spec's custom-entry bucket from shared data.
--- Intended for one-time use when spec-specific mode is first enabled.
--- @param trackerKey string "essential" or "utility"
--- @return boolean seeded True when a seed copy was applied
function Helpers.SeedNCDMCustomEntriesForCurrentSpec(trackerKey)
    if type(trackerKey) ~= "string" or trackerKey == "" then
        return false
    end

    local core = Helpers.GetCore()
    if not (core and core.db and core.db.char and core.db.profile) then
        return false
    end

    local profileDB = core.db.profile
    if not (profileDB and profileDB.ncdm and profileDB.ncdm.customEntriesSpecSpecific == true) then
        return false
    end

    local specID = Helpers.GetCurrentSpecID()
    if not specID then
        return false
    end

    -- Ensure base structures exist and are normalized.
    Helpers.GetNCDMCustomEntries(trackerKey)

    local charDB = core.db.char
    local trackerCharDB = charDB and charDB.ncdm and charDB.ncdm[trackerKey]
    if type(trackerCharDB) ~= "table" then
        return false
    end

    local profileName = (core.db.GetCurrentProfile and core.db:GetCurrentProfile()) or "Default"
    local profileBucket = trackerCharDB.customEntriesByProfile and trackerCharDB.customEntriesByProfile[profileName]
    if type(profileBucket) ~= "table" or type(profileBucket.shared) ~= "table" then
        return false
    end

    if type(profileBucket.bySpec) ~= "table" then
        profileBucket.bySpec = {}
    end

    local specKey = tostring(specID)
    local currentSpecData = profileBucket.bySpec[specKey]
    local hasEntries = type(currentSpecData) == "table"
        and type(currentSpecData.entries) == "table"
        and #currentSpecData.entries > 0
    if hasEntries then
        return false
    end

    profileBucket.bySpec[specKey] = CloneNCDMCustomEntries(profileBucket.shared)
    return true
end

---------------------------------------------------------------------------
-- CDM HUD MIN-WIDTH HELPERS
-- Shared constants/parsing/migration for frameAnchoring.hudMinWidth
---------------------------------------------------------------------------

Helpers.HUD_MIN_WIDTH_DEFAULT = 200
Helpers.HUD_MIN_WIDTH_MIN = 100
Helpers.HUD_MIN_WIDTH_MAX = 500

--- Clamp and round HUD min width into allowed bounds.
--- @param width any
--- @return number
function Helpers.ClampHUDMinWidth(width)
    local rounded = math.floor(Helpers.SafeToNumber(width, Helpers.HUD_MIN_WIDTH_DEFAULT) + 0.5)
    if rounded < Helpers.HUD_MIN_WIDTH_MIN then
        return Helpers.HUD_MIN_WIDTH_MIN
    end
    if rounded > Helpers.HUD_MIN_WIDTH_MAX then
        return Helpers.HUD_MIN_WIDTH_MAX
    end
    return rounded
end

--- Parse HUD min-width settings from a frameAnchoring table.
--- Supports both current object format and legacy scalar format.
--- @param frameAnchoring table|nil
--- @return boolean, number enabled, width
function Helpers.ParseHUDMinWidth(frameAnchoring)
    if type(frameAnchoring) ~= "table" then
        return false, Helpers.HUD_MIN_WIDTH_DEFAULT
    end

    local cfg = frameAnchoring.hudMinWidth
    local enabled, width

    if type(cfg) == "table" then
        enabled = cfg.enabled == true
        width = cfg.width
    else
        local legacyEnabled = frameAnchoring.hudMinWidthEnabled
        if legacyEnabled == nil then
            enabled = tonumber(cfg) ~= nil
        else
            enabled = legacyEnabled == true
        end
        width = cfg
    end

    return enabled == true, Helpers.ClampHUDMinWidth(width)
end

--- Parse HUD min-width settings from a profile table.
--- @param profile table|nil
--- @return boolean, number enabled, width
function Helpers.GetHUDMinWidthSettingsFromProfile(profile)
    local frameAnchoring = profile and profile.frameAnchoring
    return Helpers.ParseHUDMinWidth(frameAnchoring)
end

--- Normalize/migrate HUD min-width settings to object format in-place.
--- @param frameAnchoring table|nil
--- @return table|nil hudMinWidth object ({ enabled, width })
function Helpers.MigrateHUDMinWidthSettings(frameAnchoring)
    if type(frameAnchoring) ~= "table" then
        return nil
    end

    local cfg = frameAnchoring.hudMinWidth
    if type(cfg) == "table" then
        -- Normalize in place so existing widget/db references stay valid.
        cfg.enabled = (cfg.enabled == true)
        cfg.width = Helpers.ClampHUDMinWidth(cfg.width)
        frameAnchoring.hudMinWidthEnabled = nil
        return cfg
    end

    local enabled, width = Helpers.ParseHUDMinWidth(frameAnchoring)
    frameAnchoring.hudMinWidth = { enabled = enabled, width = width }
    frameAnchoring.hudMinWidthEnabled = nil
    return frameAnchoring.hudMinWidth
end

--- Check whether player/target HUD frames are anchored to CDM.
--- Covers both legacy unitframes anchor settings and frameAnchoring overrides.
--- @param profile table|nil
--- @return boolean
function Helpers.IsHUDAnchoredToCDM(profile)
    if type(profile) ~= "table" then
        return false
    end

    local unitframes = profile.unitframes
    if unitframes then
        local playerAnchor = unitframes.player and unitframes.player.anchorTo
        local targetAnchor = unitframes.target and unitframes.target.anchorTo
        if playerAnchor == "essential" or playerAnchor == "utility" then
            return true
        end
        if targetAnchor == "essential" or targetAnchor == "utility" then
            return true
        end
    end

    local frameAnchoring = profile.frameAnchoring
    if frameAnchoring then
        for _, key in ipairs({"playerFrame", "targetFrame"}) do
            local entry = frameAnchoring[key]
            if type(entry) == "table" then
                local p = entry.parent
                if p == "cdmEssential" or p == "cdmUtility" or p == "essential" or p == "utility" then
                    return true
                end
            end
        end
    end

    return false
end

---------------------------------------------------------------------------
-- EDIT / UNLOCK MODE STATE HELPERS
---------------------------------------------------------------------------

--- Check if QUI Layout Mode is currently active
--- @return boolean
function Helpers.IsLayoutModeActive()
    return ns.QUI_LayoutMode and ns.QUI_LayoutMode.isActive or false
end

--- Check if Blizzard Edit Mode is currently active
--- @return boolean
function Helpers.IsEditModeActive()
    if EditModeManagerFrame then
        if type(EditModeManagerFrame.IsEditModeActive) == "function" then
            return EditModeManagerFrame:IsEditModeActive()
        end
        return not not EditModeManagerFrame.editModeActive
    end
    return false
end

---------------------------------------------------------------------------
-- FONT HELPERS
-- Centralized font fetching from general settings
---------------------------------------------------------------------------

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local DEFAULT_FONT_NAME = "Friz Quadrata TT"
local DEFAULT_OUTLINE = "OUTLINE"

--- Get the user's configured general font path
--- @return string Font file path
function Helpers.GetGeneralFont()
    local profile = Helpers.GetProfile()
    if profile and profile.general then
        local fontName = profile.general.font or DEFAULT_FONT_NAME
        if LSM then
            return LSM:Fetch("font", fontName) or DEFAULT_FONT
        end
    end
    return DEFAULT_FONT
end

--- Get the user's configured font outline style
--- @return string Font outline flag (e.g., "OUTLINE", "THICKOUTLINE", "")
function Helpers.GetGeneralFontOutline()
    local profile = Helpers.GetProfile()
    if profile and profile.general then
        return profile.general.fontOutline or DEFAULT_OUTLINE
    end
    return DEFAULT_OUTLINE
end

--- Get both font path and outline in one call
--- @return string, string Font path and outline flag
function Helpers.GetGeneralFontSettings()
    return Helpers.GetGeneralFont(), Helpers.GetGeneralFontOutline()
end

---------------------------------------------------------------------------
-- COLOR/THEME HELPERS
-- Centralized color utilities for skin system and class colors
---------------------------------------------------------------------------

--- Get skin colors from the QUI theme system
--- Returns both accent color and background color with fallbacks
--- @return number, number, number, number, number, number, number, number sr, sg, sb, sa, bgr, bgg, bgb, bga
function Helpers.GetSkinColors()
    local QUI = _G.QUI
    -- Fallback sky blue accent (#60A5FA)
    local sr, sg, sb, sa = 0.376, 0.647, 0.980, 1
    -- Fallback dark background
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

--- Get just the skin accent color
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinAccentColor()
    local sr, sg, sb, sa = Helpers.GetSkinColors()
    return sr, sg, sb, sa
end

local function GetBorderKeys(prefix)
    if not prefix or prefix == "" then
        return {
            override  = "borderOverride",
            hide      = "hideBorder",
            useClass  = "borderUseClassColor",
            color     = "borderColor",
        }
    end
    return {
        override  = prefix .. "BorderOverride",
        hide      = prefix .. "HideBorder",
        useClass  = prefix .. "BorderUseClassColor",
        color     = prefix .. "BorderColor",
    }
end

--- Get skin border color from dedicated border settings.
--- Falls back to skin accent color so existing profiles keep current visuals.
--- Supports optional per-module override settings tables.
--- @param moduleSettings table|nil Optional module settings table
--- @param prefix string|nil Optional key prefix for module settings in camelCase
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local profile = Helpers.GetProfile()
    local general = profile and profile.general

    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinAccentColor()
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if general then
        if general.skinBorderUseClassColor then
            r, g, b = Helpers.GetPlayerClassColor()
            a = 1
        elseif type(general.skinBorderColor) == "table" then
            r = general.skinBorderColor[1] or r
            g = general.skinBorderColor[2] or g
            b = general.skinBorderColor[3] or b
            a = general.skinBorderColor[4] or a
        end

        if general.hideSkinBorders then
            a = 0
        end
    end

    if type(moduleSettings) == "table" then
        local keys = GetBorderKeys(type(prefix) == "string" and prefix or "")

        if moduleSettings[keys.override] then
            if moduleSettings[keys.useClass] then
                r, g, b = Helpers.GetPlayerClassColor()
                a = 1
            elseif type(moduleSettings[keys.color]) == "table" then
                local moduleColor = moduleSettings[keys.color]
                r = moduleColor[1] or r
                g = moduleColor[2] or g
                b = moduleColor[3] or b
                a = moduleColor[4] or a
            end

            if moduleSettings[keys.hide] then
                a = 0
            end
        end
    end

    return r, g, b, a
end

--- Get skin bar color from dedicated bar settings.
--- Falls back to border color so existing profiles keep current visuals.
--- Supports optional per-module override settings tables.
--- @param moduleSettings table|nil Optional module settings table
--- @param prefix string|nil Optional key prefix for module settings in camelCase
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBarColor(moduleSettings, prefix)
    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if type(moduleSettings) == "table" then
        local keyPrefix = type(prefix) == "string" and prefix or ""
        local useClassKey = keyPrefix ~= "" and (keyPrefix .. "BarUseClassColor") or "barUseClassColor"
        local colorKey = keyPrefix ~= "" and (keyPrefix .. "BarColor") or "barColor"

        if moduleSettings[useClassKey] then
            r, g, b = Helpers.GetPlayerClassColor()
            a = 1
        elseif type(moduleSettings[colorKey]) == "table" then
            local moduleColor = moduleSettings[colorKey]
            r = moduleColor[1] or r
            g = moduleColor[2] or g
            b = moduleColor[3] or b
            a = moduleColor[4] or a
        end
    end

    return r, g, b, a
end

--- Get just the skin background color
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBgColor()
    local _, _, _, _, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    return bgr, bgg, bgb, bga
end

--- Get skin background color with optional module-level override
--- Supports optional per-module override settings tables for background color
--- @param moduleSettings table|nil Optional module settings table
--- @param prefix string|nil Optional key prefix for module settings in camelCase
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBgColorWithOverride(moduleSettings, prefix)
    local profile = Helpers.GetProfile()
    local general = profile and profile.general

    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinBgColor()
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if type(moduleSettings) == "table" then
        local keyPrefix = type(prefix) == "string" and prefix or ""
        local overrideKey = keyPrefix ~= "" and (keyPrefix .. "BgOverride") or "bgOverride"
        local hideKey = keyPrefix ~= "" and (keyPrefix .. "HideBackground") or "hideBackground"
        local colorKey = keyPrefix ~= "" and (keyPrefix .. "BackgroundColor") or "backgroundColor"

        if moduleSettings[overrideKey] then
            if type(moduleSettings[colorKey]) == "table" then
                local moduleColor = moduleSettings[colorKey]
                r = moduleColor[1] or r
                g = moduleColor[2] or g
                b = moduleColor[3] or b
                a = moduleColor[4] or a
            end

            if moduleSettings[hideKey] then
                a = 0
            end
        end
    end

    return r, g, b, a
end

--- Get class color for a class token (e.g., "WARRIOR", "MAGE")
--- @param classToken string The uppercase class token from UnitClass
--- @return number, number, number r, g, b values (0-1)
function Helpers.GetClassColor(classToken)
    if not classToken then return 1, 1, 1 end
    local classColor = RAID_CLASS_COLORS[classToken]
    if classColor then
        return classColor.r, classColor.g, classColor.b
    end
    return 1, 1, 1  -- White fallback
end

--- Get class color for the player
--- @return number, number, number r, g, b values (0-1)
function Helpers.GetPlayerClassColor()
    local _, classToken = UnitClass("player")
    return Helpers.GetClassColor(classToken)
end

--- Get item quality color
--- @param quality number Item quality (0-8)
--- @return number, number, number r, g, b values (0-1)
function Helpers.GetItemQualityColor(quality)
    if not quality or quality < 0 then return 1, 1, 1 end
    local r, g, b = C_Item.GetItemQualityColor(quality)
    if r then
        return r, g, b
    end
    return 1, 1, 1  -- White fallback
end

---------------------------------------------------------------------------
-- UTILITY HELPERS
-- Common utility functions for frame creation and event handling
---------------------------------------------------------------------------

--- Create an OnUpdate callback throttler.
--- Returns a function(self, elapsed, ...) that only calls callback at the
--- requested interval and passes the accumulated elapsed as second argument.
--- @param interval number Seconds between callback executions
--- @param callback function Callback(self, accumulatedElapsed, ...)
--- @return function Throttled OnUpdate handler
function Helpers.CreateOnUpdateThrottle(interval, callback)
    interval = tonumber(interval) or 0
    local elapsedSinceLast = 0
    return function(self, elapsed, ...)
        elapsedSinceLast = elapsedSinceLast + (elapsed or 0)
        if elapsedSinceLast < interval then
            return
        end
        local accumulated = elapsedSinceLast
        elapsedSinceLast = 0
        callback(self, accumulated, ...)
    end
end

--- Create a time-based throttle wrapper for event-heavy callbacks.
--- @param interval number Seconds between callback executions
--- @param callback function Callback(...)
--- @return function Throttled function
function Helpers.CreateTimeThrottle(interval, callback)
    interval = tonumber(interval) or 0
    local lastRun = 0
    return function(...)
        local now = GetTime()
        if (now - lastRun) < interval then
            return
        end
        lastRun = now
        return callback(...)
    end
end

-- if QUI Player or Target Frames don't exist, find a 3rd party UF
-- eg Elv, Unhalted, or Blizzard UF for anchoring purposes
-- @param type string eg player or target
-- @return frame
function Helpers.FindAnchorFrame(type)
    local frameHighestWidth, highestWidth = nil, 0
    local f = EnumerateFrames()
    while f do
        -- Fast field access first; only fall back to GetAttribute if nil
        local unit = f.unit
        if unit == nil and f.GetAttribute then
            unit = f:GetAttribute("unit")
        end
        -- Cheapest checks first: unit match > IsVisible > IsObjectType > GetName
        if unit == type and f:IsVisible() and f:IsObjectType("Button") and f:GetName() then
            local w = f:GetWidth()
            if w > 20 and w > highestWidth then
                frameHighestWidth, highestWidth = f, w
            end
        end
        f = EnumerateFrames(f)
    end
    return frameHighestWidth
end

--- Clamp a value between min and max bounds
--- @param value number The value to clamp
--- @param minVal number Minimum bound
--- @param maxVal number Maximum bound
--- @return number Clamped value
function Helpers.Clamp(value, minVal, maxVal)
    if value < minVal then return minVal end
    if value > maxVal then return maxVal end
    return value
end

--- Clamp a value to [0, 1] range with optional fallback for nil/secret values
--- @param value any The value to clamp
--- @param fallback number|nil Fallback if value is nil or secret (default: 0)
--- @return number Clamped value in [0, 1]
function Helpers.Clamp01(value, fallback)
    local v = tonumber(value)
    if not v then return fallback or 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

---------------------------------------------------------------------------
-- HUD VISIBILITY HELPERS
-- Shared checks for CDM, Unitframes, and Custom Trackers visibility
---------------------------------------------------------------------------

--- Spell ID for Dracthyr Evoker Soar (racial flight form)
local SOAR_SPELL_ID = 381322

--- Check if player is a passenger on someone else's mount/vehicle.
--- Returns false when state cannot be determined to avoid false positives.
--- @return boolean True when in a passenger seat (not controlling)
function Helpers.IsPlayerPassenger()
    if not (UnitInVehicle and UnitInVehicle("player")) then
        return false
    end

    if UnitControllingVehicle then
        local ok, controlling = pcall(UnitControllingVehicle, "player")
        if ok then
            return not controlling
        end
    end

    if UnitHasVehicleUI then
        local ok, hasVehicleUI = pcall(UnitHasVehicleUI, "player")
        if ok then
            return not hasVehicleUI
        end
    end

    return false
end

--- Check if player is mounted (includes Druid flight form, Dracthyr Soar)
--- Druid: GetShapeshiftFormID() == 27 (Swift Flight Form)
--- Evoker: Soar buff (369536) when using racial flight form
--- @return boolean True if mounted or in Druid/Evoker flight form
function Helpers.IsPlayerMounted()
    if Helpers.IsPlayerPassenger() then return false end
    if IsMounted and IsMounted() then return true end
    if GetShapeshiftFormID and GetShapeshiftFormID() == 27 then return true end
    -- Dracthyr Evoker Soar (racial flight form; not detected by IsMounted)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SOAR_SPELL_ID)
        if ok and aura then return true end
    end
    return false
end

--- Check if player is flying (airborne)
--- @return boolean True if flying
function Helpers.IsPlayerFlying()
    if Helpers.IsPlayerPassenger() then return false end
    if IsFlying then return IsFlying() end
    return false
end

--- Check if player is skyriding
--- Uses C_PlayerInfo.GetGlidingInfo() for accurate
--- grounded detection (PLAYER_IS_GLIDING_CHANGED fires on takeoff/landing).
--- @return boolean True if flying in a dynamic flight zone
function Helpers.IsPlayerSkyriding()
    if Helpers.IsPlayerPassenger() then return false end
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return false end
    local ok, gliding = pcall(C_PlayerInfo.GetGlidingInfo)
    return ok and gliding
end

--- Check if player is in a vehicle or override-bar state.
--- Covers UnitInVehicle, vehicle-UI, and override action bar (quest vehicles).
--- @return boolean True when player is controlling or riding a vehicle
function Helpers.IsPlayerInVehicle()
    if UnitInVehicle and UnitInVehicle("player") then return true end
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return true end
    if HasOverrideActionBar and HasOverrideActionBar() then return true end
    return false
end

--- Check if player is inside a dungeon or raid instance.
--- Used by HUD visibility hide-rule overrides.
--- @return boolean True when instance type is party or raid
function Helpers.IsPlayerInDungeonOrRaid()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "party" or instanceType == "raid"
end

--- Create a GetSkinColors function for a specific module/frame prefix.
--- Returns a function that gets skin border + background colors.
--- @param prefix string|nil The border settings prefix (e.g., "characterFrame", "inspectFrame")
--- @param settingsPath string|nil The profile sub-key to look up (default: "general")
--- @return function Returns (sr, sg, sb, sa, bgr, bgg, bgb, bga)
function Helpers.CreateSkinColorGetter(prefix, settingsPath)
    settingsPath = settingsPath or "general"
    return function()
        local profile = Helpers.GetProfile()
        local settings = profile and profile[settingsPath]
        local sr, sg, sb, sa = Helpers.GetSkinBorderColor(settings, prefix)
        local bgr, bgg, bgb, bga = Helpers.GetSkinBgColor()
        return sr, sg, sb, sa, bgr, bgg, bgb, bga
    end
end

-- Shared utility namespace (used by consumablecheck, raidbuffs, etc.)
ns.Utils = ns.Utils or {}

--- Check if player is inside a dungeon or raid instance.
--- @return boolean
function ns.Utils.IsInInstancedContent()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

 ---------------------------------------------------------------------------
-- TEXT TRUNCATION HELPERS
-- UTF-8 safe text truncation for names and labels
 ---------------------------------------------------------------------------

 --- Truncate text to max character length (UTF-8 safe)
 --- Handles secret values from combat-restricted APIs in Patch 12.0+
 --- @param text string|any The text to truncate
 --- @param maxLength number Maximum character count (0 or nil = no limit)
 --- @return string The truncated text, or original if no truncation needed
 function Helpers.TruncateUTF8(text, maxLength)
     if text == nil then return "" end
     if type(text) ~= "string" then
         return Helpers.SafeToString(text, "")
     end
     if not maxLength or maxLength <= 0 then return text end

     if Helpers.IsSecretValue(text) then
         return string.format("%." .. maxLength .. "s", text)
     end

     local lenOk, textLen = pcall(function() return #text end)
     if not lenOk then
         return string.format("%." .. maxLength .. "s", text)
     end

     if textLen <= maxLength then
         return text
     end

     local byte = string.byte
     local i = 1
     local c = 0
     while i <= textLen and c < maxLength do
         c = c + 1
         local b = byte(text, i)
         if b < 0x80 then
             i = i + 1
         elseif b < 0xE0 then
             i = i + 2
         elseif b < 0xF0 then
             i = i + 3
         else
             i = i + 4
         end
     end

     local subOk, truncated = pcall(string.sub, text, 1, i - 1)
     if subOk and truncated then
         return truncated
     end

     return string.format("%." .. maxLength .. "s", text)
 end

 ---------------------------------------------------------------------------
-- TAINT-SAFETY UTILITIES
-- Shared patterns for WoW 12.0 taint-safe frame property management.
---------------------------------------------------------------------------

--- Create a weak-keyed state table (and optional lazy-init getter).
-- @return table  The weak-keyed table.
-- @return function  getter(key) — returns tbl[key], auto-creating {} if missing.
function Helpers.CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

-- IsEditModeActive is defined earlier in the EDIT / UNLOCK MODE STATE HELPERS section.

--- Hook a frame's Show method to defer-hide it on the next frame.
-- @param frame  The frame to hook.
-- @param opts   Optional table: { clearAlpha = bool, combatCheck = bool }
--               clearAlpha (default false): also call SetAlpha(0) after Hide.
--               combatCheck (default true): skip hide if InCombatLockdown().
local _deferredHideHooked = setmetatable({}, { __mode = "k" })

-- Queue for frames that need Hide() deferred until combat ends.
-- When combatCheck=false and we're in combat, we alpha-hide immediately
-- and queue the real Hide() for PLAYER_REGEN_ENABLED.
local _combatHideQueue = {}  -- [frame] = clearAlpha (bool)
local _combatHideFrame
local function FlushCombatHideQueue()
    -- Guard against rapid combat re-entry (PLAYER_REGEN_ENABLED can fire
    -- while InCombatLockdown() is already true again from a new combat).
    if InCombatLockdown() then return end
    for frame, shouldClearAlpha in pairs(_combatHideQueue) do
        if not (frame.IsForbidden and frame:IsForbidden()) then
            pcall(frame.Hide, frame)
            if shouldClearAlpha and frame.SetAlpha then frame:SetAlpha(0) end
        end
    end
    wipe(_combatHideQueue)
    _combatHideFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end
local function QueueCombatHide(frame, clearAlpha)
    _combatHideQueue[frame] = clearAlpha or false
    if not _combatHideFrame then
        _combatHideFrame = CreateFrame("Frame")
        _combatHideFrame:SetScript("OnEvent", FlushCombatHideQueue)
    end
    _combatHideFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Helpers.DeferredHideOnShow(frame, opts)
    if not frame or not frame.Show then return end
    if _deferredHideHooked[frame] then return end
    _deferredHideHooked[frame] = true
    local clearAlpha = opts and opts.clearAlpha or false
    local combatCheck = not opts or opts.combatCheck ~= false
    hooksecurefunc(frame, "Show", function(self)
        C_Timer.After(0, function()
            if self.IsForbidden and self:IsForbidden() then return end
            if InCombatLockdown() then
                if combatCheck then return end
                -- Visually hide via alpha now; defer real Hide() to combat end.
                -- Calling Hide() during combat fires ADDON_ACTION_BLOCKED even
                -- inside pcall — IsProtected() doesn't catch all restricted frames.
                if self.SetAlpha then self:SetAlpha(0) end
                QueueCombatHide(self, clearAlpha)
                return
            end
            pcall(self.Hide, self)
            if clearAlpha and self.SetAlpha then self:SetAlpha(0) end
        end)
    end)
end

--- Hook a texture's SetAtlas method to defer-clear it on the next frame.
-- @param texture     The texture to hook.
-- @param combatCheck Optional boolean (default true): skip clear if InCombatLockdown().
local _deferredAtlasHooked = setmetatable({}, { __mode = "k" })
function Helpers.DeferredSetAtlasBlock(texture, combatCheck)
    if not texture or not texture.SetAtlas then return end
    if _deferredAtlasHooked[texture] then return end
    _deferredAtlasHooked[texture] = true
    if combatCheck == nil then combatCheck = true end
    hooksecurefunc(texture, "SetAtlas", function(self)
        C_Timer.After(0, function()
            if combatCheck and InCombatLockdown() then return end
            if not self then return end
            if self.SetTexture then self:SetTexture(nil) end
            if self.SetAlpha then self:SetAlpha(0) end
        end)
    end)
end

--- Check whether Blizzard's Edit Mode panel is currently shown.
-- Uses IsShown() (not IsEditModeActive()) — checks panel visibility,
-- used for UI fade/hide suppression during edit mode.
-- @return boolean
function Helpers.IsEditModeShown()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown() or false
end

--- Combat-safe Show: skips if already shown or if protected + in combat.
-- @param frame  The frame to show.
-- @return boolean  true if shown (or already was), false if skipped/failed.
function Helpers.SafeShow(frame)
    if not frame then return false end
    if frame:IsShown() then return true end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        return false
    end
    return pcall(frame.Show, frame)
end

--- Combat-safe Hide: skips if already hidden or if protected + in combat.
-- @param frame  The frame to hide.
-- @return boolean  true if hidden (or already was), false if skipped/failed.
function Helpers.SafeHide(frame)
    if not frame then return false end
    if not frame:IsShown() then return true end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        return false
    end
    return pcall(frame.Hide, frame)
end

--- Normalize spell cooldown returns across 11.x tuple and 12.x table APIs.
--- @param spellID any
--- @return any start
--- @return any duration
--- @return any modRate
--- @return boolean|nil isActive
--- @return table|nil cooldownInfo Raw cooldown info table when available
function Helpers.ReadSpellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local a, b, c, d = C_Spell.GetSpellCooldown(spellID)
        if type(a) == "table" then
            local info = a
            return info.startTime or info.start, info.duration, info.modRate, info.isActive, info
        end
        return a, b, d, nil, nil
    end

    if GetSpellCooldown then
        local start, duration = GetSpellCooldown(spellID)
        return start, duration, nil, nil, nil
    end

    return nil, nil, nil, nil, nil
end

--- Treat secret values as active cooldowns unless a non-secret boolean says otherwise.
--- @param start any
--- @param duration any
--- @param isActive boolean|nil
--- @return boolean
function Helpers.IsCooldownActive(start, duration, isActive)
    if type(isActive) == "boolean" then
        return isActive
    end
    if not start or not duration then return false end

    local ok, result = pcall(function()
        return duration > 0 and start > 0
    end)
    if not ok then
        return true
    end
    return result
end

--- Apply a cooldown from a DurationObject when available, falling back to
--- numeric start/duration only when values are confirmed non-secret.
--- @param cooldownFrame table
--- @param durationObj any
--- @param startTime any
--- @param duration any
--- @param modRate any
--- @param reverse boolean|nil
--- @return boolean applied True when a cooldown was applied
function Helpers.ApplyCooldownFromStart(cooldownFrame, durationObj, startTime, duration, modRate, reverse)
    if not cooldownFrame then
        return false
    end

    if durationObj and cooldownFrame.SetCooldownFromDurationObject then
        local applied = pcall(cooldownFrame.SetCooldownFromDurationObject, cooldownFrame, durationObj, reverse)
        if applied then
            return true
        end
    end

    if Helpers.IsSecretValue(startTime) or Helpers.IsSecretValue(duration) or Helpers.IsSecretValue(modRate) then
        return false
    end
    if type(startTime) ~= "number" or type(duration) ~= "number" then
        return false
    end
    if duration <= 0 or not cooldownFrame.SetCooldown then
        return false
    end

    if modRate ~= nil then
        if type(modRate) ~= "number" then
            return false
        end
        return pcall(cooldownFrame.SetCooldown, cooldownFrame, startTime, duration, modRate)
    end
    return pcall(cooldownFrame.SetCooldown, cooldownFrame, startTime, duration)
end

--- Apply a spell cooldown using a DurationObject when possible, falling back to
--- numeric APIs only when the values are confirmed non-secret.
--- @param cooldownFrame table
--- @param spellID any
--- @param reverse boolean|nil
--- @return boolean applied True when a cooldown was applied
function Helpers.ApplyCooldownFromSpell(cooldownFrame, spellID, reverse)
    if not cooldownFrame or not spellID then
        return false
    end

    local start, duration, modRate, isActive = Helpers.ReadSpellCooldown(spellID)
    if not Helpers.IsCooldownActive(start, duration, isActive) then
        return false
    end

    local durationObj = nil
    if cooldownFrame.SetCooldownFromDurationObject
        and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, fetchedDurationObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok and fetchedDurationObj then
            durationObj = fetchedDurationObj
        end
    end

    return Helpers.ApplyCooldownFromStart(cooldownFrame, durationObj, start, duration, modRate, reverse)
end

--- Apply a cooldown using a DurationObject when possible, falling back to
--- numeric APIs only when the numeric values are confirmed non-secret.
--- This keeps combat-time aura cooldown rendering on the C-side path and
--- avoids doing Lua math on secret values.
--- @param cooldownFrame table
--- @param unit string|nil
--- @param auraInstanceID any
--- @param expirationTime any
--- @param duration any
--- @param reverse boolean|nil
--- @return boolean applied True when a cooldown was applied
function Helpers.ApplyCooldownFromAura(cooldownFrame, unit, auraInstanceID, expirationTime, duration, reverse)
    if not cooldownFrame then
        return false
    end

    if cooldownFrame.SetCooldownFromDurationObject
        and unit and auraInstanceID
        and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
        if ok and durationObj then
            local applied = pcall(cooldownFrame.SetCooldownFromDurationObject, cooldownFrame, durationObj, reverse)
            if applied then
                return true
            end
        end
    end

    if expirationTime ~= nil and duration ~= nil then
        if Helpers.IsSecretValue(expirationTime) or Helpers.IsSecretValue(duration) then
            if cooldownFrame.Clear then
                cooldownFrame:Clear()
            end
            return false
        end

        if cooldownFrame.SetCooldownFromExpirationTime then
            return pcall(cooldownFrame.SetCooldownFromExpirationTime, cooldownFrame, expirationTime, duration)
        end

        return pcall(cooldownFrame.SetCooldown, cooldownFrame, expirationTime - duration, duration)
    end

    if cooldownFrame.Clear then
        cooldownFrame:Clear()
    end
    return false
end

---------------------------------------------------------------------------
-- FORM LAYOUT HELPERS
---------------------------------------------------------------------------

--- Place a form widget in a standard row layout (TOPLEFT + RIGHT anchors)
--- and advance the Y cursor by FORM_ROW (default 32).
--- @param widget table The widget frame to position
--- @param body table The parent body frame
--- @param sy number Current Y offset
--- @param rowHeight number|nil Optional row height (default 32)
--- @return number New Y offset after this row
function Helpers.PlaceRow(widget, body, sy, rowHeight)
    widget:SetPoint("TOPLEFT", 0, sy)
    widget:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    return sy - (rowHeight or 32)
end

--- Apply default values to a table for any keys that are nil.
--- @param tbl table The target table
--- @param defaults table Key-value pairs of defaults to apply
--- Sets backdrop color AND stores backup fields for orphaned overlay recovery.
--- Use instead of frame:SetBackdropColor() on QUI-owned frames.
function Helpers.SetFrameBackdropColor(frame, r, g, b, a)
    frame:SetBackdropColor(r, g, b, a)
    frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA = r, g, b, a
end

--- Sets backdrop border color AND stores backup fields for recovery.
function Helpers.SetFrameBackdropBorderColor(frame, r, g, b, a)
    frame:SetBackdropBorderColor(r, g, b, a)
    frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA = r, g, b, a
end

function Helpers.EnsureDefaults(tbl, defaults)
    for k, v in pairs(defaults) do
        if tbl[k] == nil then
            if type(v) == "table" then
                -- Shallow-copy table defaults so instances don't share a reference
                local copy = {}
                for tk, tv in pairs(v) do copy[tk] = tv end
                tbl[k] = copy
            else
                tbl[k] = v
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- ResolveDragToSpellID
--
-- GetCursorInfo() returns different shapes depending on drag source:
--   spellbook:                cursorType="spell", id1=slot,       id4=spellID
--   action bar / spell menu:  cursorType="spell", id1=spellID,    id4=spellID
--   Blizzard CooldownManager: cursorType="spell", id1=cooldownID, id4 unreliable
--
-- Trusting any single return as a spellID without validation lets cooldownIDs,
-- spellbook slot indexes, and stale values slip into storage as if they were
-- spellIDs. Live runtime then renders dead icons because C_Spell.GetSpellInfo
-- on those values returns nothing usable.
--
-- This helper probes every plausible interpretation, validates against the
-- player's actual castable spells, applies talent override resolution, and
-- returns nil for anything that doesn't survive. Drop handlers should call
-- this with id4 first, then id1 as a fallback.
-- ----------------------------------------------------------------------------
function Helpers.ResolveDragToSpellID(rawID)
    if type(rawID) ~= "number" or rawID <= 0 then return nil end

    local function accept(id)
        if type(id) ~= "number" or id <= 0 then return nil end
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        if not info or info.isPassive then return nil end
        if not IsPlayerSpell or not IsPlayerSpell(id) then return nil end
        if C_Spell and C_Spell.GetOverrideSpell then
            local override = C_Spell.GetOverrideSpell(id)
            if override and override ~= 0 and override ~= id then
                return override
            end
        end
        return id
    end

    -- Probe 1: as-is. Action-bar drags pass the spellID directly.
    local resolved = accept(rawID)
    if resolved then return resolved end

    -- Probe 2: spellbook slot index. Spellbook drags pre-DF API.
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo
       and Enum and Enum.SpellBookSpellBank then
        local ok, book = pcall(C_SpellBook.GetSpellBookItemInfo, rawID, Enum.SpellBookSpellBank.Player)
        if ok and book and book.spellID then
            resolved = accept(book.spellID)
            if resolved then return resolved end
        end
    end

    -- Probe 3: CooldownViewer cooldownID. Blizzard CooldownManager drags.
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, rawID)
        if ok and info and info.spellID then
            resolved = accept(info.spellID)
            if resolved then return resolved end
        end
    end

    return nil
end

function Helpers.NotifyDragResolutionFailed()
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(
            "QUI: Couldn't resolve that spell. Try dragging from your spellbook.",
            1, 0.3, 0.3, 1
        )
    end
end

