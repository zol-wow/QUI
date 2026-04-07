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

local CURRENT_SCHEMA_VERSION = 1

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

local function LooksLikeLegacyMainlineProfile(profile)
    if type(profile) ~= "table" then
        return false
    end

    local general = profile.general
    local hasNextVersionMarkers = false
    if type(general) == "table" then
        if general.addEditModeButton ~= nil
            or general.objectiveTrackerClickThrough ~= nil
            or general.skinAuctionHouse ~= nil
            or general.skinCraftingOrders ~= nil
            or general.skinProfessions ~= nil
            or general.overrideSCTFont ~= nil
            or general.craftingOrderExpansionFilter ~= nil
            or general.themePreset ~= nil
        then
            hasNextVersionMarkers = true
        end
    end
    if profile.actionBarsVisibility ~= nil
        or profile.chatVisibility ~= nil
        or profile.cooldownHighlighter ~= nil
        or profile.preyTracker ~= nil
        or profile.themePreset ~= nil
    then
        hasNextVersionMarkers = true
    end

    if hasNextVersionMarkers then
        return false
    end

    if type(general) == "table" then
        if general.skinLootWindow ~= nil
            or general.skinLootUnderMouse ~= nil
            or general.skinLootHistory ~= nil
            or general.skinRollFrames ~= nil
            or general.skinRollSpacing ~= nil
        then
            return true
        end
    end

    if profile.unitFrames ~= nil
        or profile.castBar ~= nil
        or profile.targetCastBar ~= nil
        or profile.focusCastBar ~= nil
    then
        return true
    end

    local gf = profile.quiGroupFrames
    if type(gf) == "table" and (gf.unifiedPosition ~= nil or gf.partyLayout ~= nil or gf.raidLayout ~= nil) then
        return true
    end

    local mm = profile.minimap
    if type(mm) == "table" and (mm.hideMicroMenu ~= nil or mm.hideBagBar ~= nil) then
        return true
    end

    local cdmVis = profile.cdmVisibility
    local ufVis = profile.unitframesVisibility
    for _, vis in ipairs({ cdmVis, ufVis }) do
        if type(vis) == "table" and (
            vis.hideOutOfCombat ~= nil
            or vis.hideWhenNotInGroup ~= nil
            or vis.hideWhenNotInInstance ~= nil
        ) then
            return true
        end
    end

    if type(profile.ncdm) == "table" and profile.ncdm.engine ~= nil then
        return true
    end
    if type(profile.actionBars) == "table" and profile.actionBars.engine == "classic" then
        return true
    end

    if type(profile.frameAnchoring) == "table" or profile._anchoringMigrationVersion ~= nil then
        return true
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
            and value ~= nil
        then
            return false
        end
    end

    return true
end

local function PruneLegacyPlaceholderAnchors(profile)
    if type(profile) ~= "table" or type(profile.frameAnchoring) ~= "table" then
        return
    end

    for key, entry in pairs(profile.frameAnchoring) do
        if key ~= "hudMinWidth" and IsPlaceholderAnchorEntry(entry) then
            profile.frameAnchoring[key] = nil
        end
    end
end

local function ResetLegacyAnchorsForRebuild(profile)
    if type(profile) ~= "table" or profile._legacyMainlineAnchorsRebuilt then
        return
    end
    if type(profile.frameAnchoring) ~= "table" then
        profile.frameAnchoring = {}
    end

    local fa = profile.frameAnchoring
    local function ClearAnchor(key)
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
        for dbKey, barData in pairs(barsDB) do
            if type(barData) == "table" and type(barData.ownedPosition) == "table" then
                ClearAnchor(barKeyMap[dbKey] or dbKey)
            end
        end
        if HasOffsets(barsDB.extraActionButton) then ClearAnchor("extraActionButton") end
        if HasOffsets(barsDB.zoneAbility) then ClearAnchor("zoneAbility") end
    end

    profile._anchoringMigrationVersion = nil
    profile._legacyMainlineAnchorsRebuilt = true
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

local function EnsureCraftingOrderIndicator(profile)
    if not profile then
        return
    end
    if not profile.minimap then
        profile.minimap = {}
    end
    if profile.minimap._showCraftingOrderMigrated ~= true then
        profile.minimap.showCraftingOrder = true
        profile.minimap._showCraftingOrderMigrated = true
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

local function MigrateAnchoring(profile)
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

    if not profile._anchoringMigrationVersion then
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
        if existingFa then
            for key, settings in pairs(existingFa) do
                if type(settings) == "table" and settings.enabled ~= nil then
                    if settings.enabled == false then
                        -- enabled=false = never explicitly positioned via layout mode.
                        -- For CDM containers and chain frames: discard (absolute 2.55
                        -- coords don't translate). For other frames with real position
                        -- data: preserve. Seed defaults are a last resort.
                        if CDM_OWNED_KEYS[key] or LEGACY255_DISCARD_ABSOLUTE[key] then
                            existingFa[key] = nil
                        else
                            local hasPositionData = (tonumber(settings.offsetX) or 0) ~= 0
                                or (tonumber(settings.offsetY) or 0) ~= 0
                                or (tonumber(settings.widthAdjust) or 0) ~= 0
                                or (tonumber(settings.heightAdjust) or 0) ~= 0
                            if hasPositionData then
                                settings.enabled = nil  -- strip flag, keep data
                            else
                                existingFa[key] = nil
                            end
                        end
                    else
                        -- enabled=true = user explicitly positioned this via layout
                        -- mode. The entry already has valid parent-chain data (e.g.
                        -- playerCastbar with parent=cdmUtility). Always preserve,
                        -- except for CDM containers which the CDM module owns.
                        if CDM_OWNED_KEYS[key] then
                            existingFa[key] = nil
                        else
                            settings.enabled = nil  -- strip flag, keep data
                        end
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

        profile._anchoringMigrationVersion = 1
    end

    if (profile._anchoringMigrationVersion or 0) < 2 then
        local mpt = profile.mplusTimer and profile.mplusTimer.position
        if mpt then
            local currentFa = ReadFa()
            if not (currentFa and currentFa.mplusTimer) then
                EnsureFa().mplusTimer = {
                    parent = "screen",
                    point = mpt.point or "TOPRIGHT",
                    relative = mpt.relPoint or "TOPRIGHT",
                    offsetX = mpt.x or -100,
                    offsetY = mpt.y or -200,
                    sizeStable = true,
                }
            end
        end

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

        MigrateOffsets(profile.brzCounter, "brezCounter")
        MigrateOffsets(profile.combatTimer, "combatTimer")
        MigrateOffsets(profile.rangeCheck, "rangeCheck")
        MigrateOffsets(profile.actionTracker, "actionTracker")
        MigrateOffsets(profile.focusCastAlert, "focusCastAlert")
        MigrateOffsets(profile.petCombatWarning, "petWarning")
        MigrateOffsets(profile.raidBuffs, "missingRaidBuffs")

        profile._anchoringMigrationVersion = 2
    end

    if (profile._anchoringMigrationVersion or 0) < 3 then
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
                    -- Prefer ownedPosition (new), fall back to position (old 2.55 format)
                    local posSource = barData.ownedPosition or barData.position
                    if posSource then
                        MigratePos(posSource, faKey,
                            { point = "CENTER", relative = "CENTER", offsetX = 0, offsetY = 0 })
                    end
                end
            end
        end

        profile._anchoringMigrationVersion = 3
    end
end

local function MigrateNCDMContainers(profile)
    if not profile.ncdm or profile.ncdm._containersMigrated then
        return
    end

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

    for _, key in ipairs({ "essential", "utility", "buff", "trackedBar" }) do
        if profile.ncdm[key] then
            profile.ncdm.containers[key] = CloneValue(profile.ncdm[key])
            profile.ncdm.containers[key].builtIn = true
            profile.ncdm.containers[key].containerType = containerTypes[key]
            profile.ncdm.containers[key].name = containerNames[key]
        end
    end

    profile.ncdm._containersMigrated = true
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

-- Run the full migration pipeline against a single raw profile table.
-- Accepts either db.profile (AceDB proxy) or a raw db.sv.profiles[name]
-- entry. Operates only on explicit user data — never relies on AceDB
-- default-merging, so it's safe to call against raw tables that have
-- never been touched by AceDB.
function Migrations.RunOnProfile(profile)
    if type(profile) ~= "table" then return false end

    -- Cleanup: delete CDM container FA entries from existing profiles.
    -- The CDM module owns positioning via ncdm.pos; FA entries for CDM
    -- containers are ignored at the apply layer (ApplyFrameAnchor early-
    -- returns for them), but we still want to remove them from the SV to
    -- keep it clean.
    --
    -- BEFORE nilling, backfill ncdm.<key>.pos from any screen-rooted FA
    -- entry. This rescues 3.0 upgraders whose CDM container position
    -- lived only in frameAnchoring (they never opened layout mode, so
    -- SaveContainerPosition never wrote ncdm.pos). Chain-rooted entries
    -- (parent = "primaryPower" etc.) can't be resolved at migration time;
    -- those are skipped and the user will need to re-drag in layout mode.
    --
    -- v1 (initial cleanup) ran once per profile. v2 re-runs to purge any
    -- ghost entries created by the pre-fix GetFrameDB write-on-read bug,
    -- and to add the ncdm.pos backfill that v1 was missing.
    if (profile._cdmFaCleanupVersion or 0) < 2 then
        local fa = profile.frameAnchoring
        if type(fa) == "table" then
            local FA_TO_NCDM = {
                cdmEssential = "essential",
                cdmUtility   = "utility",
                buffIcon     = "buff",
                buffBar      = "trackedBar",
            }
            for faKey, ncdmKey in pairs(FA_TO_NCDM) do
                local entry = fa[faKey]
                if type(entry) == "table" then
                    local parent = entry.parent or "screen"
                    if parent == "screen" or parent == "disabled" then
                        -- Screen-rooted: copy offsets to ncdm.<key>.pos
                        -- (only if ncdm.pos doesn't already have a value).
                        if type(profile.ncdm) ~= "table" then
                            profile.ncdm = {}
                        end
                        if type(profile.ncdm[ncdmKey]) ~= "table" then
                            profile.ncdm[ncdmKey] = {}
                        end
                        local tracker = profile.ncdm[ncdmKey]
                        if type(tracker.pos) ~= "table"
                            or tracker.pos.ox == nil
                            or tracker.pos.oy == nil then
                            tracker.pos = {
                                ox = entry.offsetX or 0,
                                oy = entry.offsetY or 0,
                            }
                        end
                    end
                    -- Nil the FA entry regardless of parent type.
                    fa[faKey] = nil
                end
            end
        end
        profile._cdmFaCleanupVersion = 2
    end

    -- 1. Data format migrations (restructure raw data first)
    MigrateDatatextSlots(profile.datatext)
    MigratePerSlotSettings(profile.datatext)
    MigrateMasterTextColors(profile.quiUnitFrames and profile.quiUnitFrames.general)
    MigrateChatEditBox(profile.chat)
    MigrateCooldownSwipeV2(profile)
    MigrateCastBars(profile)
    MigrateUnitFrames(profile)
    MigrateSelfFirst(profile)
    CleanOrphanKeys(profile)

    -- 2. Legacy profile detection & normalization
    local isLegacy = LooksLikeLegacyMainlineProfile(profile)
    if isLegacy then
        PruneLegacyPlaceholderAnchors(profile)
        ResetLegacyAnchorsForRebuild(profile)
        NormalizeLegacyActionBarLayouts(profile)
    end

    -- 3. Feature migrations
    ResetCastbarPreviewModes(profile)
    EnsureThemeStorage(profile)
    MigrateLegacyLootSettings(profile)
    EnsureCraftingOrderIndicator(profile)
    MigrateToShowLogic(profile.cdmVisibility)
    MigrateToShowLogic(profile.unitframesVisibility)
    MigrateGroupFrameContainers(profile)
    NormalizeAuraIndicators(profile)
    NormalizeEngines(profile)
    NormalizeMinimapSettings(profile)

    -- 4. Anchoring (depends on data being in final locations)
    MigrateAnchoring(profile)
    MigrateNCDMContainers(profile)

    -- 5. Stamp schema version
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

    local profiles = db.sv and db.sv.profiles
    if type(profiles) == "table" then
        local any = false
        for _, profile in pairs(profiles) do
            if Migrations.RunOnProfile(profile) then
                any = true
            end
        end
        return any
    end

    return Migrations.RunOnProfile(db.profile)
end
