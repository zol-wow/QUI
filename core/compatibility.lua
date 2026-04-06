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

-- Migrate legacy cooldownSwipe (hideEssential/hideUtility) to new 3-toggle system
local function MigrateCooldownSwipeV2(profile)
    if not profile then return end
    if not profile.cooldownSwipe then profile.cooldownSwipe = {} end

    local cs = profile.cooldownSwipe
    if cs.migratedToV2 then return end  -- Already migrated

    -- Check old settings
    local hadHideEssential = cs.hideEssential == true
    local hadHideUtility = cs.hideUtility == true
    local hadHideBuffSwipe = profile.cooldownManager and profile.cooldownManager.hideSwipe == true

    -- Migration: If user had swipes hidden, they likely wanted to hide GCD clutter
    -- Give them spell cooldowns back while keeping GCD hidden
    if hadHideEssential or hadHideUtility or hadHideBuffSwipe then
        cs.showBuffSwipe = true
        cs.showGCDSwipe = false       -- Hide GCD (what most users wanted)
        cs.showCooldownSwipe = true   -- Show actual cooldowns
    else
        -- Fresh or never-hidden: show all
        cs.showBuffSwipe = true
        cs.showGCDSwipe = true
        cs.showCooldownSwipe = true
    end

    -- Clean up legacy keys
    cs.hideEssential = nil
    cs.hideUtility = nil
    if profile.cooldownManager then
        profile.cooldownManager.hideSwipe = nil
    end

    cs.migratedToV2 = true
end

-- Migrate legacy top-level castBar/targetCastBar/focusCastBar to quiUnitFrames.*.castbar
local CASTBAR_MIGRATION_MAP = {
    castBar       = { "quiUnitFrames", "player",  "castbar" },
    targetCastBar = { "quiUnitFrames", "target",  "castbar" },
    focusCastBar  = { "quiUnitFrames", "focus",   "castbar" },
}

-- Keys that map 1:1 between old castBar and new quiUnitFrames.*.castbar
local CASTBAR_DIRECT_KEYS = {
    "enabled", "bgColor", "color", "height",
    "showIcon", "width",
}

-- Keys with renamed equivalents: old → new
local CASTBAR_RENAMED_KEYS = {
    textSize = "fontSize",
}

-- Position keys always migrate (legacy values represent actual screen positions
-- and should take priority even when the target castbar section already exists
-- from a transitional-era profile that had both old and new keys).
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

-- Migrate legacy General settings (PascalCase → camelCase)
local function MigrateUnitFramesGeneral(oldGeneral, newGeneral)
    if type(oldGeneral) ~= "table" then return end

    SetIfNil(newGeneral, "font", oldGeneral.Font)
    SetIfNil(newGeneral, "fontOutline", oldGeneral.FontFlag)

    -- DarkMode sub-table
    if type(oldGeneral.DarkMode) == "table" then
        local dm = oldGeneral.DarkMode
        SetIfNil(newGeneral, "darkMode", dm.Enabled)
        SetIfNil(newGeneral, "darkModeBgColor", dm.BackgroundColor)
        SetIfNil(newGeneral, "darkModeHealthColor", dm.ForegroundColor)
        if dm.UseSolidTexture ~= nil and newGeneral.darkModeOpacity == nil then
            newGeneral.darkModeOpacity = 1
        end
    end

    -- FontShadows
    if type(oldGeneral.FontShadows) == "table" then
        local fs = oldGeneral.FontShadows
        SetIfNil(newGeneral, "fontShadowColor", fs.Color)
        SetIfNil(newGeneral, "fontShadowOffsetX", fs.OffsetX)
        SetIfNil(newGeneral, "fontShadowOffsetY", fs.OffsetY)
    end

    -- CustomColors.Power → powerColors (top-level, handled separately)
    -- CustomColors.Reaction → hostility colors
    if type(oldGeneral.CustomColors) == "table" then
        local cc = oldGeneral.CustomColors
        if type(cc.Reaction) == "table" then
            -- Reaction colors: 1-2 = hostile, 3 = neutral, 4 = friendly, 5-8 = friendly
            SetIfNil(newGeneral, "hostilityColorHostile", cc.Reaction[1])
            SetIfNil(newGeneral, "hostilityColorNeutral", cc.Reaction[4])
            SetIfNil(newGeneral, "hostilityColorFriendly", cc.Reaction[5])
        end
    end
end

-- Migrate a single unit's PascalCase data to camelCase
local function MigrateUnitFrameUnit(oldUnit, newUnit)
    if type(oldUnit) ~= "table" then return end

    -- Top-level Enabled
    SetIfNil(newUnit, "enabled", oldUnit.Enabled)

    -- Frame sub-table → flat keys
    if type(oldUnit.Frame) == "table" then
        local f = oldUnit.Frame
        SetIfNil(newUnit, "width", f.Width)
        SetIfNil(newUnit, "height", f.Height)
        SetIfNil(newUnit, "texture", f.Texture)
        SetIfNil(newUnit, "useClassColor", f.ClassColor)
        SetIfNil(newUnit, "useHostilityColor", f.ReactionColor)
        -- Frame position (boss frames used XPosition/YPosition for anchored offset)
        SetIfNil(newUnit, "offsetX", f.XPosition)
        SetIfNil(newUnit, "offsetY", f.YPosition)
    end

    -- Tags.Health → health text keys
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

        -- Tags.Name → name text keys
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

        -- Tags.Power → power text keys
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

    -- PowerBar → flat power bar keys
    if type(oldUnit.PowerBar) == "table" then
        local pb = oldUnit.PowerBar
        SetIfNil(newUnit, "showPowerBar", pb.Enabled)
        SetIfNil(newUnit, "powerBarHeight", pb.Height)
        SetIfNil(newUnit, "powerBarUsePowerColor", pb.ColorByType)
        SetIfNil(newUnit, "powerBarColor", pb.FGColor)
    end

    -- Absorb → absorbs sub-table
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

    -- Migrate enabled flag
    SetIfNil(new, "enabled", old.enabled)

    -- Migrate General → general (PascalCase → camelCase with key mapping)
    if type(old.General) == "table" then
        local general = EnsureSubTable(new, "general")
        MigrateUnitFramesGeneral(old.General, general)
    end

    -- Migrate per-unit sub-tables with PascalCase → camelCase key mapping
    for _, unit in ipairs(UNIT_FRAME_UNITS) do
        if type(old[unit]) == "table" then
            local newUnit = EnsureSubTable(new, unit)
            MigrateUnitFrameUnit(old[unit], newUnit)
        end
    end

    -- Migrate power custom colors to top-level powerColors if available
    if type(old.General) == "table" and type(old.General.CustomColors) == "table" then
        local customPower = old.General.CustomColors.Power
        if type(customPower) == "table" and profile.powerColors == nil then
            profile.powerColors = customPower
        end
    end

    -- Remove the legacy key
    profile.unitFrames = nil
end

-- Default frameAnchoring parent chain and structure for profiles that predate
-- the layout mode anchoring overhaul. These entries define the standard HUD
-- stacking order (bar layout, unit frame relationships, power bar chain).
-- Only entries with non-trivial parent relationships are included; entries
-- that default to parent="screen" at CENTER/0,0 are omitted since they match
-- the uninitialized pattern already present in old profiles.
local DEFAULT_FRAME_ANCHORING = {
    bagBar          = { parent = "microMenu",       point = "TOPLEFT",      relative = "BOTTOMLEFT" },
    bar1            = { parent = "bar3",            point = "BOTTOM",       relative = "TOP" },
    bar2            = { parent = "bar1",            point = "BOTTOM",       relative = "TOP" },
    bar3            = { parent = "screen",          point = "BOTTOMRIGHT",  relative = "BOTTOM" },
    bar4            = { parent = "bar5",            point = "BOTTOMLEFT",   relative = "TOPLEFT" },
    bar5            = { parent = "bar6",            point = "BOTTOMLEFT",   relative = "TOPLEFT" },
    bar6            = { parent = "bar3",            point = "BOTTOMLEFT",   relative = "BOTTOMRIGHT" },
    bossFrames      = { parent = "datatextPanel",   point = "TOPLEFT",      relative = "BOTTOMLEFT" },
    brezCounter     = { parent = "combatTimer",     point = "BOTTOM",       relative = "TOP" },
    atonementCounter = { parent = "brezCounter",    point = "BOTTOM",       relative = "TOP" },
    buffFrame       = { parent = "minimap",         point = "TOPRIGHT",     relative = "TOPLEFT" },
    buffIcon        = { parent = "cdmEssential",    point = "BOTTOM",       relative = "TOP" },
    cdmUtility      = { parent = "secondaryPower",  point = "TOP",          relative = "BOTTOM" },
    combatTimer     = { parent = "bar3",            point = "BOTTOMRIGHT",  relative = "BOTTOMLEFT" },
    consumables     = { parent = "readyCheck",      point = "BOTTOM",       relative = "TOP" },
    datatextPanel   = { parent = "minimap",         point = "TOP",          relative = "BOTTOM" },
    debuffFrame     = { parent = "buffFrame",       point = "TOPRIGHT",     relative = "BOTTOMRIGHT" },
    focusCastbar    = { parent = "focusFrame",      point = "TOP",          relative = "BOTTOM",  autoWidth = true },
    focusFrame      = { parent = "playerFrame",     point = "BOTTOMLEFT",   relative = "TOPLEFT", offsetY = 200 },
    microMenu       = { parent = "screen",          point = "TOPLEFT",      relative = "TOPLEFT" },
    minimap         = { parent = "screen",          point = "TOPRIGHT",     relative = "TOPRIGHT", offsetY = -25 },
    objectiveTracker = { parent = "datatextPanel",  point = "TOPRIGHT",     relative = "BOTTOMRIGHT" },
    partyFrames     = { parent = "cdmUtility",      point = "TOP",          relative = "BOTTOM",  offsetY = -25, keepInPlace = true },
    petBar          = { parent = "bar6",            point = "BOTTOMLEFT",   relative = "BOTTOMRIGHT" },
    petCastbar      = { parent = "petFrame",        point = "TOP",          relative = "BOTTOM" },
    petFrame        = { parent = "playerFrame",     point = "BOTTOMRIGHT",  relative = "BOTTOMLEFT" },
    playerCastbar   = { parent = "playerFrame",     point = "TOP",          relative = "BOTTOM",  autoWidth = true },
    playerFrame     = { parent = "cdmEssential",    point = "BOTTOMRIGHT",  relative = "BOTTOMLEFT" },
    primaryPower    = { parent = "cdmEssential",    point = "TOP",          relative = "BOTTOM",  autoWidth = true },
    raidFrames      = { parent = "cdmUtility",      point = "TOP",          relative = "BOTTOM",  offsetY = -25, keepInPlace = true },
    secondaryPower  = { parent = "primaryPower",    point = "TOP",          relative = "BOTTOM",  autoWidth = true },
    stanceBar       = { parent = "petBar",          point = "BOTTOMLEFT",   relative = "TOPLEFT" },
    targetCastbar   = { parent = "targetFrame",     point = "TOP",          relative = "BOTTOM",  autoWidth = true },
    targetFrame     = { parent = "cdmEssential",    point = "BOTTOMLEFT",   relative = "BOTTOMRIGHT" },
    totCastbar      = { parent = "totFrame",        point = "TOP",          relative = "BOTTOM" },
    totFrame        = { parent = "targetFrame",     point = "BOTTOMLEFT",   relative = "BOTTOMRIGHT" },
    zoneAbility     = { parent = "extraActionButton", point = "CENTER",     relative = "CENTER" },
    cdmEssential    = { parent = "screen",          point = "CENTER",       relative = "CENTER",  offsetY = -180 },
    lootRollAnchor  = { parent = "readyCheck",      point = "TOP",          relative = "BOTTOM",  keepInPlace = true },
    skyriding       = { parent = "screen",          point = "CENTER",       relative = "TOP",     offsetY = -30 },
    powerBarAlt     = { parent = "screen",          point = "CENTER",       relative = "TOP",     offsetY = -75 },
    bnetToastAnchor = { parent = "screen",          point = "CENTER",       relative = "TOP",     offsetY = -125 },
}

-- Detect if a frameAnchoring table looks like uninitialized defaults from a
-- pre-layout-mode profile: every entry has parent="screen", offset 0,0.
local function IsUninitializedAnchoring(fa)
    if type(fa) ~= "table" then return true end
    local count = 0
    for key, entry in pairs(fa) do
        if type(entry) == "table" then
            count = count + 1
            -- Check for the telltale uninitialized pattern
            local parent = entry.parent
            if parent and parent ~= "screen" and parent ~= "disabled" then
                return false  -- Has a real parent chain
            end
            if (entry.offsetX or 0) ~= 0 or (entry.offsetY or 0) ~= 0 then
                -- Has real position offsets (not all zeroed)
                if parent ~= "screen" then
                    return false
                end
            end
        end
    end
    -- If all entries look like screen/0,0 defaults, it's uninitialized
    return count > 0
end

local ANCHORING_SEED_VERSION = 1

local function SeedDefaultFrameAnchoring(profile)
    if not profile then return end

    -- Only run once — stamp a version flag so we never re-seed on future loads
    if profile._anchoringSeedVersion and profile._anchoringSeedVersion >= ANCHORING_SEED_VERSION then
        return
    end

    if type(profile.frameAnchoring) ~= "table" then
        profile.frameAnchoring = {}
    end
    local fa = profile.frameAnchoring

    -- Only seed if the existing data looks uninitialized
    if not IsUninitializedAnchoring(fa) then
        profile._anchoringSeedVersion = ANCHORING_SEED_VERSION
        return
    end

    for key, defaults in pairs(DEFAULT_FRAME_ANCHORING) do
        if type(fa[key]) ~= "table" then
            fa[key] = {}
        end
        local entry = fa[key]

        -- Seed parent chain and anchor points (overwrite uninitialized
        -- "screen"/CENTER data with the proper default parent chain)
        entry.parent   = defaults.parent
        entry.point    = defaults.point
        entry.relative = defaults.relative

        -- Seed offsets from defaults (only if currently zeroed)
        if defaults.offsetX and (entry.offsetX or 0) == 0 then
            entry.offsetX = defaults.offsetX
        end
        if defaults.offsetY and (entry.offsetY or 0) == 0 then
            entry.offsetY = defaults.offsetY
        end

        -- Seed newer fields that old profiles don't have at all
        if entry.hideWithParent == nil then
            entry.hideWithParent = false
        end
        if defaults.keepInPlace and entry.keepInPlace == nil then
            entry.keepInPlace = defaults.keepInPlace
        elseif entry.keepInPlace == nil then
            entry.keepInPlace = false
        end
        if defaults.autoWidth and entry.autoWidth == nil then
            entry.autoWidth = defaults.autoWidth
        end

        -- Ensure standard fields exist
        if entry.sizeStable == nil then entry.sizeStable = true end
        if entry.autoHeight == nil then entry.autoHeight = false end
        if entry.autoWidth == nil then entry.autoWidth = false end
        if entry.heightAdjust == nil then entry.heightAdjust = 0 end
        if entry.widthAdjust == nil then entry.widthAdjust = 0 end
    end

    profile._anchoringSeedVersion = ANCHORING_SEED_VERSION
end

-- Remove orphaned keys that cannot be meaningfully migrated
---------------------------------------------------------------------------
-- Defaults v1 migration (v3.1.0 defaults overhaul)
-- Stamps OLD default values into existing profiles so that changing
-- defaults.lua doesn't silently flip settings for returning users.
-- Only writes a value when rawget returns nil (user never touched it).
---------------------------------------------------------------------------
local function StampOldDefaults(db)
    local profileName = db:GetCurrentProfile()
    local rawProfile = db.sv and db.sv.profiles and db.sv.profiles[profileName]
    if not rawProfile then return end  -- brand-new profile, use new defaults

    -- Already migrated this profile?
    -- v1 had a bug that created intermediate tables via rawset, polluting the SV.
    -- v2 is the fixed version; re-run is harmless (stamp only writes nil keys).
    if rawProfile._defaultsVersion and rawProfile._defaultsVersion >= 2 then return end

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
        db.profile._defaultsVersion = 2
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
    -- row2 had iconCount=8 (→10), already covered above

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
    -- buttonSpacing: old default was nil (use Blizzard Edit Mode padding), new default is 0.
    -- Can't stamp nil (it's indistinguishable from "never set"), so we skip it.
    -- Existing users who never set it will get 0 instead of nil — acceptable since
    -- 0 spacing is visually similar to Blizzard default spacing.
    stamp({"actionBars", "style", "rangeIndicator"}, false)
    stamp({"actionBars", "style", "usabilityIndicator"}, false)
    stamp({"actionBars", "style", "usabilityDesaturate"}, false)

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
    stamp({"quiGroupFrames", "party", "partyTracker", "ccIcons", "enabled"}, false)
    stamp({"quiGroupFrames", "party", "partyTracker", "kickTimer", "enabled"}, false)
    stamp({"quiGroupFrames", "party", "partyTracker", "partyCooldowns", "enabled"}, false)

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

    ---------------------------------------------------------------------------
    -- Done — stamp version
    ---------------------------------------------------------------------------
    db.profile._defaultsVersion = 2
end

local ORPHAN_KEYS = { "cooldownManager", "trackerSystem", "nudgeAmount" }

local function CleanOrphanKeys(profile)
    if not profile then return end
    for _, key in ipairs(ORPHAN_KEYS) do
        if profile[key] ~= nil then
            profile[key] = nil
        end
    end
end

function QUI:BackwardsCompat()
    -- Stamp old defaults for existing users upgrading past the v3.1.0 defaults overhaul.
    -- Must run FIRST, before other migrations that might create subtables.
    if self.db then
        StampOldDefaults(self.db)
    end

    -- Migrate datatext settings to slot-based architecture
    if self.db and self.db.profile and self.db.profile.datatext then
        MigrateDatatextSlots(self.db.profile.datatext)
        MigratePerSlotSettings(self.db.profile.datatext)
    end

    -- Migrate master text color toggles (legacy classColorText → new system)
    if self.db and self.db.profile and self.db.profile.quiUnitFrames and self.db.profile.quiUnitFrames.general then
        MigrateMasterTextColors(self.db.profile.quiUnitFrames.general)
    end

    -- Migrate chat styleEditBox boolean to editBox table
    if self.db and self.db.profile and self.db.profile.chat then
        MigrateChatEditBox(self.db.profile.chat)
    end

    -- Migrate cooldownSwipe to v2 (3-toggle system)
    if self.db and self.db.profile then
        MigrateCooldownSwipeV2(self.db.profile)
    end

    -- Migrate legacy top-level castBar keys to quiUnitFrames.*.castbar
    if self.db and self.db.profile then
        MigrateCastBars(self.db.profile)
    end

    -- Migrate legacy unitFrames to quiUnitFrames
    if self.db and self.db.profile then
        MigrateUnitFrames(self.db.profile)
    end

    if self.db and self.db.profile and self.db.profile.quiGroupFrames then
        local gf = self.db.profile.quiGroupFrames
        if gf.selfFirst ~= nil then
            if gf.partySelfFirst == nil then
                gf.partySelfFirst = gf.selfFirst
            end
            if gf.raidSelfFirst == nil then
                gf.raidSelfFirst = gf.selfFirst
            end
            gf.selfFirst = nil
        end
    end

    -- Remove orphaned keys that no longer have runtime consumers
    if self.db and self.db.profile then
        CleanOrphanKeys(self.db.profile)
    end

    -- Seed default frameAnchoring parent chain for profiles that predate
    -- the layout mode anchoring overhaul (all entries parent="screen", offset 0,0)
    if self.db and self.db.profile then
        SeedDefaultFrameAnchoring(self.db.profile)
    end

    -- Ensure db.global exists and has required fields
    if not self.db.global then
        self:DebugPrint("DB Global not found")
        self.db.global = {
            isDone = false,
            lastVersion = 0,
            imports = {}
        }
    end
    
    -- Ensure db.global has all required fields
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
