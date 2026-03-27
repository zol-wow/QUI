---------------------------------------------------------------------------
-- QUI Profile Migrations
-- Shared normalization pipeline for legacy SavedVariables and profile imports.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Migrations = ns.Migrations or {}
ns.Migrations = Migrations

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

    if type(profile.ncdm) == "table" and profile.ncdm.engine == "classic" then
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

local function NormalizeEngines(profile)
    if profile.tooltip and profile.tooltip.engine and profile.tooltip.engine ~= "default" then
        profile.tooltip.engine = "default"
    end

    if profile.ncdm and profile.ncdm.engine and profile.ncdm.engine ~= "owned" then
        profile.ncdm.engine = "owned"
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

local function MigrateAnchoring(profile)
    if not profile._anchoringMigrationVersion then
        if not profile.frameAnchoring then
            profile.frameAnchoring = {}
        end
        local fa = profile.frameAnchoring

        for key, settings in pairs(fa) do
            if type(settings) == "table" and settings.enabled ~= nil then
                if settings.enabled == false then
                    fa[key] = nil
                else
                    settings.enabled = nil
                end
            end
        end

        local function MigrateInlineOffsets(sourceTable, targetKey)
            if not sourceTable then return end
            local ox = sourceTable.offsetX
            local oy = sourceTable.offsetY
            if ox == nil and oy == nil then return end
            if fa[targetKey] then return end
            fa[targetKey] = {
                parent = "screen",
                point = "CENTER",
                relative = "CENTER",
                offsetX = ox or 0,
                offsetY = oy or 0,
                sizeStable = true,
            }
        end

        local uf = profile.quiUnitFrames
        if uf then
            MigrateInlineOffsets(uf.player, "playerFrame")
            MigrateInlineOffsets(uf.target, "targetFrame")
            MigrateInlineOffsets(uf.targettarget, "totFrame")
            MigrateInlineOffsets(uf.focus, "focusFrame")
            MigrateInlineOffsets(uf.pet, "petFrame")
            MigrateInlineOffsets(uf.boss, "bossFrames")
        end

        local bars = profile.actionBars and profile.actionBars.bars
        if bars then
            MigrateInlineOffsets(bars.extraActionButton, "extraActionButton")
            MigrateInlineOffsets(bars.zoneAbility, "zoneAbility")
        end

        MigrateInlineOffsets(profile.totemBar, "totemBar")
        MigrateInlineOffsets(profile.xpTracker, "xpTracker")
        MigrateInlineOffsets(profile.skyriding, "skyriding")
        MigrateInlineOffsets(profile.crosshair, "crosshair")

        local gf = profile.quiGroupFrames
        if gf then
            local pos = gf.position
            if pos and (pos.offsetX or pos.offsetY) and not fa.partyFrames then
                fa.partyFrames = {
                    parent = "screen",
                    point = "CENTER",
                    relative = "CENTER",
                    offsetX = pos.offsetX or 0,
                    offsetY = pos.offsetY or 0,
                    sizeStable = true,
                }
            end

            local raidPos = gf.raidPosition
            if raidPos and (raidPos.offsetX or raidPos.offsetY) and not fa.raidFrames then
                fa.raidFrames = {
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
            local castbarMigrations = {
                { unitKey = "player", targetKey = "playerCastbar", parentFrameKey = "playerFrame" },
                { unitKey = "target", targetKey = "targetCastbar", parentFrameKey = "targetFrame" },
                { unitKey = "focus",  targetKey = "focusCastbar",  parentFrameKey = "focusFrame" },
            }

            for _, cm in ipairs(castbarMigrations) do
                local unitSettings = uf[cm.unitKey]
                local castDB = unitSettings and unitSettings.castbar
                if castDB and not fa[cm.targetKey] then
                    local anchor = castDB.anchor or "none"
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
                    fa[cm.targetKey] = entry
                end
            end
        end

        profile._anchoringMigrationVersion = 1
    end

    if (profile._anchoringMigrationVersion or 0) < 2 then
        if not profile.frameAnchoring then profile.frameAnchoring = {} end
        local fa = profile.frameAnchoring

        local mpt = profile.mplusTimer and profile.mplusTimer.position
        if mpt and not fa.mplusTimer then
            fa.mplusTimer = {
                point = mpt.point or "TOPRIGHT",
                relative = mpt.relPoint or "TOPRIGHT",
                offsetX = mpt.x or -100,
                offsetY = mpt.y or -200,
                sizeStable = true,
            }
        end

        local tp = profile.tooltip and profile.tooltip.anchorPosition
        if tp and not fa.tooltipAnchor then
            fa.tooltipAnchor = {
                point = tp.point or "BOTTOMRIGHT",
                relative = tp.relPoint or "BOTTOMRIGHT",
                offsetX = tp.x or -200,
                offsetY = tp.y or 100,
                sizeStable = true,
            }
        end

        local function MigrateOffsets(sourceTable, targetKey)
            if not sourceTable then return end
            local ox = sourceTable.offsetX or sourceTable.xOffset
            local oy = sourceTable.offsetY or sourceTable.yOffset
            if ox == nil and oy == nil then return end
            if fa[targetKey] then return end
            fa[targetKey] = {
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
        if not profile.frameAnchoring then profile.frameAnchoring = {} end
        local fa = profile.frameAnchoring

        local function MigratePos(source, faKey, defaults)
            if not source then return end
            if fa[faKey] then return end
            fa[faKey] = {
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
            if cfp and not fa.consumables then
                fa.consumables = {
                    point = cfp.point or "CENTER",
                    relative = cfp.relativePoint or cfp.relPoint or "CENTER",
                    offsetX = cfp.x or 0,
                    offsetY = cfp.y or 100,
                    sizeStable = true,
                }
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

        local barsDB = profile.actionBars and profile.actionBars.bars
        if barsDB then
            local barKeyMap = {
                pet = "petBar",
                stance = "stanceBar",
                microbar = "microMenu",
                bags = "bagBar",
            }
            for dbKey, barData in pairs(barsDB) do
                if type(barData) == "table" and barData.ownedPosition then
                    local faKey = barKeyMap[dbKey] or dbKey
                    MigratePos(barData.ownedPosition, faKey,
                        { point = "CENTER", relative = "CENTER", offsetX = 0, offsetY = 0 })
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

function Migrations.NormalizeProfile(core, opts)
    local profile = core and core.db and core.db.profile
    if type(profile) ~= "table" then
        return false
    end

    local isLegacyMainlineProfile = LooksLikeLegacyMainlineProfile(profile)

    local addon = _G.QUI
    if addon and addon.BackwardsCompat then
        addon:BackwardsCompat()
    end

    if isLegacyMainlineProfile then
        PruneLegacyPlaceholderAnchors(profile)
        ResetLegacyAnchorsForRebuild(profile)
        NormalizeLegacyActionBarLayouts(profile)
    end

    ResetCastbarPreviewModes(profile)
    EnsureThemeStorage(profile)
    MigrateLegacyLootSettings(profile)
    EnsureCraftingOrderIndicator(profile)
    MigrateToShowLogic(profile.cdmVisibility)
    MigrateToShowLogic(profile.unitframesVisibility)
    MigrateGroupFrameContainers(profile)
    NormalizeEngines(profile)
    NormalizeMinimapSettings(profile)
    MigrateAnchoring(profile)
    MigrateNCDMContainers(profile)

    return true
end

