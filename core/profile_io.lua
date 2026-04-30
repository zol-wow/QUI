---------------------------------------------------------------------------
-- QUI Profile Import/Export
-- Handles serialization of profiles, tracker bars, and spell scanner data.
-- Extracted from core/main.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub("LibDeflate", true)

local MAX_IMPORT_DEPTH = 20
local MAX_IMPORT_NODES = 50000
local MAX_SCHEMA_ERRORS = 8
local MAX_DISPLAY_SCHEMA_ERRORS = 3
local MAX_DETAIL_TYPE_MISMATCHES = 64
local MAX_SANITIZE_STEPS = 128

local function CloneValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[CloneValue(k, seen)] = CloneValue(v, seen)
    end
    return copy
end

local function GetDisplayPath(path, rootLabel)
    if type(path) ~= "string" or path == "" then
        return "root"
    end
    local prefix = (rootLabel or "profile") .. "."
    if path:sub(1, #prefix) == prefix then
        path = path:sub(#prefix + 1)
    elseif path == (rootLabel or "profile") then
        return "root"
    end
    return path ~= "" and path or "root"
end

local function FormatTreeValidationError(issue, rootLabel)
    if type(issue) ~= "table" then
        return "Import failed validation. The string appears to be malformed."
    end

    if issue.kind == "unsupported_value_type" then
        local where = GetDisplayPath(issue.path, rootLabel)
        return ("Import rejected: unsupported value type '%s' at '%s'."):format(tostring(issue.valueType), where)
    end
    if issue.kind == "unsupported_key_type" then
        local where = GetDisplayPath(issue.path, rootLabel)
        return ("Import rejected: unsupported key type '%s' at '%s'."):format(tostring(issue.keyType), where)
    end
    if issue.kind == "depth_limit" then
        local where = GetDisplayPath(issue.path, rootLabel)
        return ("Import rejected: data is nested too deeply at '%s' (limit: %d)."):format(where, issue.limit or MAX_IMPORT_DEPTH)
    end
    if issue.kind == "node_limit" then
        return ("Import rejected: data payload is too large (limit: %d nodes)."):format(issue.limit or MAX_IMPORT_NODES)
    end

    return "Import failed validation. The string appears to be malformed."
end

local function FormatTypeMismatchErrors(errors, rootLabel)
    if type(errors) ~= "table" or #errors == 0 then
        return nil
    end

    local samples = {}
    local shown = math.min(#errors, MAX_DISPLAY_SCHEMA_ERRORS)
    for i = 1, shown do
        local err = errors[i]
        local where = GetDisplayPath(err.path, rootLabel)
        samples[#samples + 1] = ("%s (expected %s, got %s)"):format(where, err.expected, err.actual)
    end

    local summary = table.concat(samples, "; ")
    local remaining = #errors - shown
    if remaining > 0 then
        summary = summary .. ("; and %d more"):format(remaining)
    end

    return "Import rejected: incompatible setting types - " .. summary .. "."
end

-- Defensive import validation:
-- 1) Reject unsupported Lua value types in payload trees.
-- 2) Soft-check imported profile keys against AceDB defaults when available.
local function ValidateImportTree(value, label, state, depth)
    state = state or { visited = {}, nodes = 0 }
    depth = depth or 0

    local valueType = type(value)
    if valueType ~= "table" then
        if valueType == "function" or valueType == "thread" or valueType == "userdata" then
            return false, { kind = "unsupported_value_type", valueType = valueType, path = label or "root" }
        end
        return true
    end

    if state.visited[value] then
        return true
    end
    state.visited[value] = true

    if depth >= MAX_IMPORT_DEPTH then
        return false, { kind = "depth_limit", limit = MAX_IMPORT_DEPTH, path = label or "root" }
    end

    state.nodes = state.nodes + 1
    if state.nodes > MAX_IMPORT_NODES then
        return false, { kind = "node_limit", limit = MAX_IMPORT_NODES }
    end

    for k, v in pairs(value) do
        local keyType = type(k)
        if keyType ~= "string" and keyType ~= "number" and keyType ~= "boolean" then
            return false, {
                kind = "unsupported_key_type",
                keyType = keyType,
                path = label or "root",
                badKey = k,
            }
        end
        local childLabel = ("%s.%s"):format(label or "root", tostring(k))
        local ok, issue = ValidateImportTree(v, childLabel, state, depth + 1)
        if not ok then
            return false, issue
        end
    end

    return true
end

local function ValidateTableTypeShape(candidate, schema, path, errors, depth)
    if #errors >= MAX_SCHEMA_ERRORS then return end
    depth = depth or 0
    if depth > MAX_IMPORT_DEPTH then return end
    if type(candidate) ~= "table" or type(schema) ~= "table" then return end

    for key, schemaValue in pairs(schema) do
        if #errors >= MAX_SCHEMA_ERRORS then break end

        local candidateValue = candidate[key]
        if candidateValue ~= nil then
            local schemaType = type(schemaValue)
            local candidateType = type(candidateValue)
            local keyPath = ("%s.%s"):format(path or "profile", tostring(key))

            if schemaType ~= candidateType then
                table.insert(errors, { path = keyPath, expected = schemaType, actual = candidateType })
            elseif schemaType == "table" then
                ValidateTableTypeShape(candidateValue, schemaValue, keyPath, errors, depth + 1)
            end
        end
    end
end

local function ValidateTableTypeShapeDetailed(candidate, schema, path, errors, depth)
    if #errors >= MAX_DETAIL_TYPE_MISMATCHES then return end
    depth = depth or 0
    if depth > MAX_IMPORT_DEPTH then return end
    if type(candidate) ~= "table" or type(schema) ~= "table" then return end

    for key, schemaValue in pairs(schema) do
        if #errors >= MAX_DETAIL_TYPE_MISMATCHES then break end

        local candidateValue = candidate[key]
        if candidateValue ~= nil then
            local schemaType = type(schemaValue)
            local candidateType = type(candidateValue)
            local keyPath = ("%s.%s"):format(path or "profile", tostring(key))

            if schemaType ~= candidateType then
                table.insert(errors, {
                    kind = "type_mismatch",
                    path = keyPath,
                    expected = schemaType,
                    actual = candidateType,
                })
            elseif schemaType == "table" then
                ValidateTableTypeShapeDetailed(candidateValue, schemaValue, keyPath, errors, depth + 1)
            end
        end
    end
end

local function NormalizeTreeIssue(issue)
    if type(issue) ~= "table" then
        return { kind = "unknown", path = "profile", detail = "invalid issue" }
    end
    local normalized = {
        kind = issue.kind or "unknown",
        path = issue.path,
        limit = issue.limit,
        expected = issue.expected,
        actual = issue.actual,
        valueType = issue.valueType,
        keyType = issue.keyType,
        badKey = issue.badKey,
    }
    return normalized
end

local function FormatDetailedLine(err)
    if type(err) ~= "table" then
        return tostring(err)
    end
    if err.kind == "type_mismatch" and err.path then
        local where = GetDisplayPath(err.path, "profile")
        return ("%s — expected %s, got %s"):format(where, tostring(err.expected), tostring(err.actual))
    end
    if err.kind == "unsupported_value_type" then
        local where = GetDisplayPath(err.path or "profile", "profile")
        return ("%s — unsupported value type %s"):format(where, tostring(err.valueType))
    end
    if err.kind == "unsupported_key_type" then
        local where = GetDisplayPath(err.path or "profile", "profile")
        return ("%s — table has invalid key type %s"):format(where, tostring(err.keyType))
    end
    if err.kind == "depth_limit" then
        local where = GetDisplayPath(err.path or "profile", "profile")
        return ("%s — nesting deeper than %s levels"):format(where, tostring(err.limit or MAX_IMPORT_DEPTH))
    end
    if err.kind == "node_limit" then
        return ("Table too large (over %s nodes)"):format(tostring(err.limit or MAX_IMPORT_NODES))
    end
    return tostring(err.kind or "validation issue")
end

local function ValidateProfilePayloadDetailed(core, profileData)
    local ok, issue = ValidateImportTree(profileData, "profile")
    if not ok then
        local n = NormalizeTreeIssue(issue)
        return false, {
            summary = FormatTreeValidationError(issue, "profile"),
            errors = { n },
        }
    end

    local defaults = core and core.db and core.db.defaults and core.db.defaults.profile
    if type(defaults) ~= "table" then
        return true, nil
    end

    local typeErrors = {}
    ValidateTableTypeShapeDetailed(profileData, defaults, "profile", typeErrors, 0)
    if #typeErrors > 0 then
        local legacyErrors = {}
        for _, e in ipairs(typeErrors) do
            legacyErrors[#legacyErrors + 1] = { path = e.path, expected = e.expected, actual = e.actual }
        end
        return false, {
            summary = FormatTypeMismatchErrors(legacyErrors, "profile"),
            errors = typeErrors,
        }
    end

    return true, nil
end

local function ValidateProfilePayload(core, profileData)
    local ok, detail = ValidateProfilePayloadDetailed(core, profileData)
    if not ok then
        return false, detail and detail.summary or "Import failed profile validation."
    end
    return true
end

local function DeleteKeyByDottedPath(root, fullPath)
    if type(root) ~= "table" or type(fullPath) ~= "string" or fullPath == "" then
        return false
    end
    local segments = {}
    for segment in fullPath:gmatch("[^.]+") do
        segments[#segments + 1] = segment
    end
    if #segments == 0 then
        return false
    end
    if segments[1] == "profile" then
        table.remove(segments, 1)
    end
    if #segments == 0 then
        return false
    end
    local parent = root
    for i = 1, #segments - 1 do
        local seg = segments[i]
        if type(parent[seg]) ~= "table" then
            return false
        end
        parent = parent[seg]
    end
    local lastKey = segments[#segments]
    parent[lastKey] = nil
    return true
end

local function RemoveRawKeyAtPath(root, parentPath, badKey)
    if type(root) ~= "table" or badKey == nil then
        return false
    end
    local parent = root
    if type(parentPath) == "string" and parentPath ~= "" and parentPath ~= "root" then
        local segments = {}
        for segment in parentPath:gmatch("[^.]+") do
            segments[#segments + 1] = segment
        end
        if segments[1] == "profile" then
            table.remove(segments, 1)
        end
        for i = 1, #segments do
            local seg = segments[i]
            if type(parent[seg]) ~= "table" then
                return false
            end
            parent = parent[seg]
        end
    end
    parent[badKey] = nil
    return true
end

local function SanitizeProfilePayloadStep(core, working, stripped)
    local ok, detail = ValidateProfilePayloadDetailed(core, working)
    if ok then
        return true, true
    end
    if type(detail) ~= "table" or type(detail.errors) ~= "table" or #detail.errors == 0 then
        return false, false, detail and detail.summary or "Validation failed."
    end

    local err = detail.errors[1]
    local removed = false

    if err.kind == "type_mismatch" and err.path then
        if DeleteKeyByDottedPath(working, err.path) then
            removed = true
            stripped[#stripped + 1] = FormatDetailedLine(err) .. " (removed)"
        end
    elseif err.kind == "unsupported_value_type" and err.path then
        if DeleteKeyByDottedPath(working, err.path) then
            removed = true
            stripped[#stripped + 1] = FormatDetailedLine(err) .. " (removed)"
        end
    elseif err.kind == "unsupported_key_type" then
        if RemoveRawKeyAtPath(working, err.path or "profile", err.badKey) then
            removed = true
            stripped[#stripped + 1] = FormatDetailedLine(err) .. " (removed)"
        end
    elseif err.kind == "depth_limit" and err.path then
        if DeleteKeyByDottedPath(working, err.path) then
            removed = true
            stripped[#stripped + 1] = FormatDetailedLine(err) .. " (removed; subtree too deep)"
        end
    elseif err.kind == "node_limit" then
        return false, false, detail.summary or "This profile is too large to import."
    else
        return false, false, detail.summary or "Could not automatically remove incompatible settings."
    end

    if not removed then
        return false, false, detail.summary or "Could not remove incompatible settings."
    end
    return true, false
end

local function SanitizeProfilePayload(core, profileData)
    if type(profileData) ~= "table" then
        return false, nil, {}, "Invalid profile data."
    end
    local working = CloneValue(profileData)
    local stripped = {}

    for _ = 1, MAX_SANITIZE_STEPS do
        local proceed, done, errMsg = SanitizeProfilePayloadStep(core, working, stripped)
        if not proceed then
            return false, working, stripped, errMsg
        end
        if done then
            return true, working, stripped, nil
        end
    end

    return false, working, stripped, "Too many incompatible settings; try a fresh export from QUI."
end

local function ValidateTrackerBarPayload(data, multi)
    local ok, issue = ValidateImportTree(data, "trackers")
    if not ok then
        return false, FormatTreeValidationError(issue, "trackers")
    end

    if multi then
        if type(data.bars) ~= "table" then
            return false, "Import rejected: tracker bars payload is missing a valid bars table."
        end
        for i, bar in ipairs(data.bars) do
            if type(bar) ~= "table" then
                return false, ("Import rejected: tracker bar #%d is invalid."):format(i)
            end
        end
    else
        if type(data.bar) ~= "table" then
            return false, "Import rejected: tracker bar payload is missing a valid bar table."
        end
    end

    if data.specEntries ~= nil and type(data.specEntries) ~= "table" then
        return false, "Import rejected: tracker spec entries must be a table."
    end

    return true
end

local function ValidateSpellScannerPayload(data)
    local ok, issue = ValidateImportTree(data, "spellScanner")
    if not ok then
        return false, FormatTreeValidationError(issue, "spellScanner")
    end

    if type(data) ~= "table" then
        return false, "Import rejected: spell scanner payload is not a table."
    end
    if data.spells ~= nil and type(data.spells) ~= "table" then
        return false, "Import rejected: spell scanner spells must be a table."
    end
    if data.items ~= nil and type(data.items) ~= "table" then
        return false, "Import rejected: spell scanner items must be a table."
    end
    return true
end

local SUPPORTED_PROFILE_IMPORT_PREFIXES = {
    QUI1 = true,
    CDM1 = true,
}

local PROFILE_THEME_GENERAL_KEYS = {
    "font",
    "fontOutline",
    "texture",
    "darkMode",
    "darkModeHealthColor",
    "darkModeBgColor",
    "darkModeOpacity",
    "darkModeHealthOpacity",
    "darkModeBgOpacity",
    "masterColorNameText",
    "masterColorToTText",
    "masterColorPowerText",
    "masterColorHealthText",
    "masterColorCastbarText",
    "defaultUseClassColor",
    "defaultHealthColor",
    "hostilityColorHostile",
    "hostilityColorNeutral",
    "hostilityColorFriendly",
    "defaultBgColor",
    "defaultOpacity",
    "defaultHealthOpacity",
    "defaultBgOpacity",
    "applyGlobalFontToBlizzard",
    "overrideSCTFont",
}

local PROFILE_QOL_GENERAL_KEYS = {
    "uiScale",
    "allowReloadInCombat",
    "autoInsertKey",
    "consumableMacros",
    "consumablePersistent",
    "craftingOrderExpansionFilter",
    "sellJunk",
    "autoRepair",
    "autoRoleAccept",
    "autoAcceptInvites",
    "autoAcceptQuest",
    "autoTurnInQuest",
    "questHoldShift",
    "fastAutoLoot",
    "autoSelectGossip",
    "autoCombatLog",
    "autoCombatLogRaid",
    "autoDeleteConfirm",
    "auctionHouseExpansionFilter",
    "popupBlocker",
    "petCombatWarning",
    "petWarningOffsetX",
    "petWarningOffsetY",
    "focusCastAlert",
    "consumableCheckEnabled",
    "consumableOnReadyCheck",
    "consumableOnDungeon",
    "consumableOnRaid",
    "consumableOnResurrect",
    "consumableFood",
    "consumableFlask",
    "consumableOilMH",
    "consumableOilOH",
    "consumableRune",
    "consumableHealthstone",
    "consumablePreferredFood",
    "consumablePreferredFlask",
    "consumablePreferredRune",
    "consumablePreferredOilMH",
    "consumablePreferredOilOH",
    "consumableExpirationWarning",
    "consumableExpirationThreshold",
    "consumableAnchorMode",
    "consumableIconOffset",
    "consumableIconSize",
    "consumableScale",
    "quickSalvage",
    "mplusTeleportEnabled",
    "keyTrackerEnabled",
    "keyTrackerFontSize",
    "keyTrackerFont",
    "keyTrackerTextColor",
    "keyTrackerPoint",
    "keyTrackerRelPoint",
    "keyTrackerOffsetX",
    "keyTrackerOffsetY",
    "keyTrackerWidth",
}

local PROFILE_SKINNING_GENERAL_KEYS = {
    "skinKeystoneFrame",
    "skinGameMenu",
    "addQUIButton",
    "addEditModeButton",
    "objectiveTrackerClickThrough",
    "gameMenuFontSize",
    "gameMenuDim",
    "skinPowerBarAlt",
    "skinStatusTrackingBars",
    "statusTrackingBarsBarColorMode",
    "statusTrackingBarsBarColor",
    "statusTrackingBarsBarHeight",
    "statusTrackingBarsBarWidthPercent",
    "statusTrackingBarsShowBorder",
    "statusTrackingBarsBorderThickness",
    "statusTrackingBarsShowBarText",
    "statusTrackingBarsBarTextAlways",
    "statusTrackingBarsBarTextAnchor",
    "statusTrackingBarsBarTextColor",
    "statusTrackingBarsBarTextFont",
    "statusTrackingBarsBarTextFontSize",
    "statusTrackingBarsBarTextOutline",
    "statusTrackingBarsBarTextOffsetX",
    "statusTrackingBarsBarTextOffsetY",
    "skinOverrideActionBar",
    "skinObjectiveTracker",
    "objectiveTrackerHeight",
    "objectiveTrackerModuleFontSize",
    "objectiveTrackerTitleFontSize",
    "objectiveTrackerTextFontSize",
    "hideObjectiveTrackerBorder",
    "objectiveTrackerModuleColor",
    "objectiveTrackerTitleColor",
    "objectiveTrackerTextColor",
    "skinInstanceFrames",
    "skinAuctionHouse",
    "skinCraftingOrders",
    "skinProfessions",
    "skinBgColor",
    "skinAlerts",
    "skinCharacterFrame",
    "skinInspectFrame",
    "skinLootWindow",
    "skinLootUnderMouse",
    "skinLootHistory",
    "skinRollFrames",
    "skinRollSpacing",
    "skinUseClassColor",
}

local PROFILE_LAYOUT_PATHS = {
    "alerts.alertPosition",
    "alerts.toastPosition",
    "alerts.bnetToastPosition",
    "raidBuffs.position",
    "mplusTimer.position",
    "loot.position",
    "lootRoll.position",
    "ncdm.essential.pos",
    "ncdm.utility.pos",
    "ncdm.buff.pos",
    "powerBar.offsetX",
    "powerBar.offsetY",
    "castBar.offsetX",
    "castBar.offsetY",
    "targetCastBar.offsetX",
    "targetCastBar.offsetY",
    "focusCastBar.offsetX",
    "focusCastBar.offsetY",
    "secondaryPowerBar.offsetX",
    "secondaryPowerBar.offsetY",
    "reticle.offsetX",
    "reticle.offsetY",
    "crosshair.offsetX",
    "crosshair.offsetY",
    "rangeCheck.offsetX",
    "rangeCheck.offsetY",
    "skyriding.offsetX",
    "skyriding.offsetY",
    "actionBars.bars.extraActionButton.position",
    "actionBars.bars.extraActionButton.offsetX",
    "actionBars.bars.extraActionButton.offsetY",
    "actionBars.bars.zoneAbility.position",
    "actionBars.bars.zoneAbility.offsetX",
    "actionBars.bars.zoneAbility.offsetY",
    "quiUnitFrames.player.offsetX",
    "quiUnitFrames.player.offsetY",
    "quiUnitFrames.target.offsetX",
    "quiUnitFrames.target.offsetY",
    "quiUnitFrames.targettarget.offsetX",
    "quiUnitFrames.targettarget.offsetY",
    "quiUnitFrames.pet.offsetX",
    "quiUnitFrames.pet.offsetY",
    "quiUnitFrames.focus.offsetX",
    "quiUnitFrames.focus.offsetY",
    "quiUnitFrames.boss.offsetX",
    "quiUnitFrames.boss.offsetY",
    "quiUnitFrames.player.castbar.offsetX",
    "quiUnitFrames.player.castbar.offsetY",
    "quiUnitFrames.target.castbar.offsetX",
    "quiUnitFrames.target.castbar.offsetY",
    "quiUnitFrames.focus.castbar.offsetX",
    "quiUnitFrames.focus.castbar.offsetY",
    "quiGroupFrames.position",
    "quiGroupFrames.raidPosition",
    "quiGroupFrames.raid.spotlight.position",
    "combatText.xOffset",
    "combatText.yOffset",
    "brzCounter.xOffset",
    "brzCounter.yOffset",
    "combatTimer.xOffset",
    "combatTimer.yOffset",
    "xpTracker.offsetX",
    "xpTracker.offsetY",
    "xpTracker.locked",
    "minimap.lock",
    "minimap.position",
    "totemBar.offsetX",
    "totemBar.offsetY",
    "totemBar.locked",
}

local PROFILE_THEME_PRESERVE_PATHS = {
    "addonAccentColor",
    "powerColors",
}

for _, key in ipairs(PROFILE_THEME_GENERAL_KEYS) do
    PROFILE_THEME_PRESERVE_PATHS[#PROFILE_THEME_PRESERVE_PATHS + 1] = "general." .. key
end

local CUSTOM_TRACKER_BAR_ID_PREFIX = "customTrackerBar:"
local GenerateUniqueTrackerID

local function SyncCustomTrackerBarsToCDM(core, profile)
    local migrations = ns.Migrations
    if not migrations or type(migrations.SyncCustomTrackerBarsToCDM) ~= "function" then
        return false
    end
    local globalDB = core and core.db and core.db.global
    return migrations.SyncCustomTrackerBarsToCDM(profile, globalDB)
end

-- Cross-character profile imports lose the source-spec association on
-- spec-specific custom-tracker bars: ncdm._lastSpecID is the only spec
-- hint a v31 export carries, and the importing client's session
-- overwrites it on the next save with the importer's current spec. By
-- the time migrations next run, the original spec is gone.
--
-- Stamp bar._sourceSpecID directly from the imported _lastSpecID before
-- migrations run. v32(c) EnsureCustomTrackerBarContainer clones the bar
-- into the V2 container via CloneValue, propagating the stamp to
-- container._sourceSpecID. v32(d)/v32(g) skip stamping when it's
-- already set, so a priest export imported on a warrior preserves
-- _sourceSpecID = priestSpec instead of being overwritten with the
-- warrior's current spec.
local function StampSourceSpecOnImportedSpecBars(targetProfile, importedProfile)
    if type(targetProfile) ~= "table" or type(importedProfile) ~= "table" then return end
    local bars = targetProfile.customTrackers and targetProfile.customTrackers.bars
    if type(bars) ~= "table" then return end
    local sourceSpecID = importedProfile.ncdm and importedProfile.ncdm._lastSpecID
    if type(sourceSpecID) ~= "number" or sourceSpecID <= 0 then return end
    for _, bar in ipairs(bars) do
        if type(bar) == "table"
           and bar.specSpecificSpells == true
           and bar._sourceSpecID == nil
        then
            bar._sourceSpecID = sourceSpecID
        end
    end
end

local function RemoveImportedCustomBarContainers(core, profile)
    local migrations = ns.Migrations
    if migrations and type(migrations.RemoveLegacyCustomBarContainers) == "function" then
        migrations.RemoveLegacyCustomBarContainers(profile, core and core.db and core.db.global)
    end
end

local function IsCustomBarContainer(container)
    return type(container) == "table" and container.containerType == "customBar"
end

local function GetCustomBarLegacyID(containerKey, container)
    if type(container) ~= "table" then return nil end
    if container._legacyId ~= nil then return tostring(container._legacyId) end
    if container.id ~= nil then return tostring(container.id) end
    if type(containerKey) == "string" then
        return containerKey:match("^customBar_(.+)$")
    end
    return nil
end

local function BuildLegacyCustomTrackerBarFromContainer(containerKey, container)
    if not IsCustomBarContainer(container) then return nil end

    local legacyID = GetCustomBarLegacyID(containerKey, container)
    if not legacyID or legacyID == "" then return nil end

    local row = type(container.row1) == "table" and container.row1 or {}
    return {
        id = legacyID,
        name = container.name or "Custom Bar",
        enabled = container.enabled ~= false,
        locked = container.locked == true,
        offsetX = (type(container.pos) == "table" and container.pos.ox) or container.offsetX or 0,
        offsetY = (type(container.pos) == "table" and container.pos.oy) or container.offsetY or 0,
        growDirection = container.growDirection or "RIGHT",
        maxIcons = row.iconCount or container.maxIcons or 8,
        iconSize = row.iconSize or container.iconSize or 28,
        spacing = row.padding or container.spacing or 4,
        borderSize = row.borderSize or container.borderSize or 2,
        borderColor = CloneValue(row.borderColorTable or container.borderColor or container.borderColorTable or {0, 0, 0, 1}),
        aspectRatioCrop = row.aspectRatioCrop or container.aspectRatioCrop or 1.0,
        zoom = row.zoom or container.zoom or 0,
        durationFont = row.durationFont or container.durationFont,
        durationSize = row.durationSize or container.durationSize or 13,
        durationColor = CloneValue(row.durationTextColor or container.durationColor or container.durationTextColor or {1, 1, 1, 1}),
        durationAnchor = row.durationAnchor or container.durationAnchor or "CENTER",
        durationOffsetX = row.durationOffsetX or container.durationOffsetX or 0,
        durationOffsetY = row.durationOffsetY or container.durationOffsetY or 0,
        hideDurationText = row.hideDurationText == true or container.hideDurationText == true,
        stackFont = row.stackFont or container.stackFont,
        stackSize = row.stackSize or container.stackSize or 9,
        stackColor = CloneValue(row.stackTextColor or container.stackColor or container.stackTextColor or {1, 1, 1, 1}),
        stackAnchor = row.stackAnchor or container.stackAnchor or "BOTTOMRIGHT",
        stackOffsetX = row.stackOffsetX or container.stackOffsetX or 3,
        stackOffsetY = row.stackOffsetY or container.stackOffsetY or -1,
        hideStackText = row.hideStackText == true or container.hideStackText == true,
        showItemCharges = container.showItemCharges ~= false,
        showProfessionQuality = container.showProfessionQuality ~= false,
        showRechargeSwipe = container.showRechargeSwipe == true,
        noDesaturateWithCharges = container.noDesaturateWithCharges == true,
        bgOpacity = container.bgOpacity or 0,
        bgColor = CloneValue(container.bgColor or {0, 0, 0, 1}),
        hideGCD = container.hideGCD ~= false,
        hideNonUsable = container.hideNonUsable == true,
        showOnlyOnCooldown = container.showOnlyOnCooldown == true,
        showOnlyWhenActive = container.showOnlyWhenActive == true,
        showOnlyWhenOffCooldown = container.showOnlyWhenOffCooldown == true,
        showOnlyInCombat = container.showOnlyInCombat == true,
        dynamicLayout = container.dynamicLayout == true,
        clickableIcons = container.clickableIcons == true,
        showActiveState = container.showActiveState ~= false,
        activeGlowEnabled = container.activeGlowEnabled ~= false,
        activeGlowType = container.activeGlowType or "Pixel Glow",
        activeGlowColor = CloneValue(container.activeGlowColor or {1, 0.85, 0.3, 1}),
        activeGlowLines = container.activeGlowLines or 8,
        activeGlowFrequency = container.activeGlowFrequency or 0.25,
        activeGlowThickness = container.activeGlowThickness or 2,
        activeGlowScale = container.activeGlowScale or 1.0,
        specSpecificSpells = container.specSpecificSpells == true or container.specSpecific == true,
        entries = CloneValue(container.entries or {}),
    }
end

local function CollectCustomTrackerExportRecords(profile)
    if type(profile) ~= "table" then return {} end

    local containers = profile.ncdm and profile.ncdm.containers
    local byLegacyID = {}
    local customKeys = {}
    if type(containers) == "table" then
        for key, container in pairs(containers) do
            if IsCustomBarContainer(container) then
                local legacyID = GetCustomBarLegacyID(key, container)
                if legacyID then
                    byLegacyID[legacyID] = { key = key, container = container, legacyID = legacyID }
                    customKeys[#customKeys + 1] = key
                end
            end
        end
    end
    table.sort(customKeys)

    local records = {}
    local seen = {}
    local bars = profile.customTrackers and profile.customTrackers.bars
    if type(bars) == "table" then
        for _, bar in ipairs(bars) do
            if type(bar) == "table" then
                local legacyID = bar.id ~= nil and tostring(bar.id) or nil
                local mapped = legacyID and byLegacyID[legacyID] or nil
                if mapped then
                    local exportedBar = BuildLegacyCustomTrackerBarFromContainer(mapped.key, mapped.container)
                    if exportedBar then
                        records[#records + 1] = {
                            bar = exportedBar,
                            legacyID = mapped.legacyID,
                            containerKey = mapped.key,
                        }
                    end
                    seen[legacyID] = true
                else
                    records[#records + 1] = {
                        bar = CloneValue(bar),
                        legacyID = legacyID,
                        containerKey = legacyID and ("customBar_" .. legacyID) or nil,
                    }
                    if legacyID then seen[legacyID] = true end
                end
            end
        end
    end

    for _, key in ipairs(customKeys) do
        local mapped = byLegacyID[GetCustomBarLegacyID(key, containers[key])]
        if mapped and not seen[mapped.legacyID] then
            local exportedBar = BuildLegacyCustomTrackerBarFromContainer(mapped.key, mapped.container)
            if exportedBar then
                records[#records + 1] = {
                    bar = exportedBar,
                    legacyID = mapped.legacyID,
                    containerKey = mapped.key,
                }
                seen[mapped.legacyID] = true
            end
        end
    end

    return records
end

local function ExtractBarsFromExportRecords(records)
    local bars = {}
    for _, record in ipairs(records or {}) do
        if type(record) == "table" and type(record.bar) == "table" then
            bars[#bars + 1] = CloneValue(record.bar)
        end
    end
    return bars
end

local function CollectSpecEntriesForExportRecord(record, globals)
    if type(record) ~= "table" or type(globals) ~= "table" then return nil end
    if not (record.bar and record.bar.specSpecificSpells) then return nil end

    local legacyID = record.legacyID or (record.bar and record.bar.id)
    if legacyID ~= nil and type(globals.specTrackerSpells) == "table" then
        local legacyEntries = globals.specTrackerSpells[legacyID]
        if type(legacyEntries) == "table" then
            return CloneValue(legacyEntries)
        end
    end

    local containerKey = record.containerKey
    if (not containerKey or containerKey == "") and legacyID ~= nil then
        containerKey = "customBar_" .. tostring(legacyID)
    end
    local ncdmEntries = globals.ncdm
        and globals.ncdm.specTrackerSpells
        and globals.ncdm.specTrackerSpells[containerKey]
    if type(ncdmEntries) == "table" then
        return CloneValue(ncdmEntries)
    end

    return nil
end

local function CollectLegacySpecEntriesForExportRecords(records, globals)
    if type(records) ~= "table" or type(globals) ~= "table" then return nil end
    local result = nil
    for _, record in ipairs(records) do
        local entries = CollectSpecEntriesForExportRecord(record, globals)
        local legacyID = record.legacyID or (record.bar and record.bar.id)
        if entries and legacyID ~= nil then
            result = result or {}
            result[legacyID] = entries
        end
    end
    return result
end

local function StampCustomTrackerBarsForExport(targetProfile, sourceProfile)
    local records = CollectCustomTrackerExportRecords(sourceProfile)
    if #records == 0 then return records end

    if type(targetProfile.customTrackers) == "table" then
        targetProfile.customTrackers = CloneValue(targetProfile.customTrackers)
    else
        targetProfile.customTrackers = {}
    end
    targetProfile.customTrackers.bars = ExtractBarsFromExportRecords(records)

    return records
end

local function GetTrackerEntryResolvedName(entry)
    if type(entry) ~= "table" then
        return nil
    end

    if type(entry.name) == "string" and entry.name ~= "" then
        return entry.name
    end

    local entryID = entry.id or entry.itemID or entry.spellID
    if not entryID then
        return nil
    end

    if entry.type == "item" then
        if C_Item and C_Item.GetItemNameByID then
            local ok, itemName = pcall(C_Item.GetItemNameByID, entryID)
            if ok and type(itemName) == "string" and itemName ~= "" then
                return itemName
            end
        end

        if GetItemInfo then
            local ok, itemName = pcall(GetItemInfo, entryID)
            if ok and type(itemName) == "string" and itemName ~= "" then
                return itemName
            end
        end

        return ("Item %s"):format(tostring(entryID))
    end

    if entry.type == "spell" then
        if C_Spell and C_Spell.GetSpellName then
            local ok, spellName = pcall(C_Spell.GetSpellName, entryID)
            if ok and type(spellName) == "string" and spellName ~= "" then
                return spellName
            end
        end

        if GetSpellInfo then
            local ok, spellName = pcall(GetSpellInfo, entryID)
            if ok and type(spellName) == "string" and spellName ~= "" then
                return spellName
            end
        end

        return ("Spell %s"):format(tostring(entryID))
    end

    return ("%s %s"):format(tostring(entry.type or "Entry"), tostring(entryID))
end

local function BuildCustomTrackerBarDescription(bar)
    if type(bar) ~= "table" then
        return "Import this custom tracker bar only."
    end

    local entries = type(bar.entries) == "table" and bar.entries or {}
    local entryCount = 0
    local sampleNames = {}

    for _, entry in ipairs(entries) do
        entryCount = entryCount + 1
        if #sampleNames < 3 then
            sampleNames[#sampleNames + 1] = GetTrackerEntryResolvedName(entry) or "Unknown entry"
        end
    end

    local parts = {}
    parts[#parts + 1] = ("%d entr%s"):format(entryCount, entryCount == 1 and "y" or "ies")

    if bar.specSpecificSpells then
        parts[#parts + 1] = "spec-specific"
    end
    if bar.showOnlyOnCooldown then
        parts[#parts + 1] = "cooldown-only"
    end
    if bar.showOnlyWhenActive then
        parts[#parts + 1] = "active-only"
    end
    if bar.enabled == false then
        parts[#parts + 1] = "disabled"
    end
    if type(bar.growDirection) == "string" and bar.growDirection ~= "" then
        parts[#parts + 1] = "grows " .. bar.growDirection
    end

    local summary = table.concat(parts, "; ")
    if #sampleNames > 0 then
        summary = summary .. ". " .. table.concat(sampleNames, ", ")
        if entryCount > #sampleNames then
            summary = summary .. ", ..."
        end
    end

    return summary
end

local function BuildCustomTrackerBarPreviewChildren(profileData)
    local records = CollectCustomTrackerExportRecords(profileData)
    if #records == 0 then
        return nil
    end

    local children = {}
    for index, record in ipairs(records) do
        local bar = record.bar
        local barName = type(bar) == "table" and bar.name or nil
        children[#children + 1] = {
            id = CUSTOM_TRACKER_BAR_ID_PREFIX .. index,
            label = barName and tostring(barName) or ("Bar " .. index),
            description = BuildCustomTrackerBarDescription(bar),
            available = type(bar) == "table",
            dynamic = true,
        }
    end

    return #children > 0 and children or nil
end

local PROFILE_IMPORT_CATEGORIES = {
    {
        id = "theme",
        label = "Theme / Fonts / Colors",
        description = "Shared fonts, textures, dark mode, and addon-wide color settings.",
        recommended = false,
        topLevelKeys = { "addonAccentColor", "powerColors", "themePreset" },
        generalKeys = PROFILE_THEME_GENERAL_KEYS,
    },
    {
        id = "layout",
        label = "Layout / Positions",
                description = "Mover positions, frame placement, and tracked element offsets.",
        recommended = false,
        topLevelKeys = { "frameAnchoring", "dandersFrames", "abilityTimeline", "blizzardMover" },
        paths = PROFILE_LAYOUT_PATHS,
    },
    {
        id = "unitFrames",
        label = "Unit Frames",
        description = "Player, target, focus, pet, and boss frame settings.",
        recommended = true,
        topLevelKeys = { "quiUnitFrames", "unitframesVisibility", "unitFrames" },
        children = {
            {
                id = "unitFramesGeneral",
                label = "General",
                description = "Master unit frame settings, shared visibility rules, and legacy unit frame compatibility.",
                paths = { "quiUnitFrames.enabled", "quiUnitFrames.general" },
                topLevelKeys = { "unitframesVisibility", "unitFrames" },
            },
            { id = "unitFramePlayer", label = "Player", description = "Player frame settings.", paths = { "quiUnitFrames.player" } },
            { id = "unitFrameTarget", label = "Target", description = "Target frame settings.", paths = { "quiUnitFrames.target" } },
            { id = "unitFrameToT", label = "ToT", description = "Target-of-target frame settings.", paths = { "quiUnitFrames.targettarget" } },
            { id = "unitFramePet", label = "Pet", description = "Pet frame settings.", paths = { "quiUnitFrames.pet" } },
            { id = "unitFrameFocus", label = "Focus", description = "Focus frame settings.", paths = { "quiUnitFrames.focus" } },
            { id = "unitFrameBoss", label = "Boss", description = "Boss frame settings.", paths = { "quiUnitFrames.boss" } },
        },
    },
    {
        id = "groupFrames",
        label = "Group / Raid Frames",
        description = "Party, raid, click-cast, and raid buff settings.",
        recommended = true,
        topLevelKeys = { "quiGroupFrames", "raidBuffs" },
        children = {
            {
                id = "groupFramesGeneral",
                label = "General",
                description = "Shared group frame options and global toggles.",
                topLevelKeys = { "raidBuffs" },
                paths = {
                    "quiGroupFrames.enabled",
                    "quiGroupFrames.unifiedPosition",
                    "quiGroupFrames.partySelfFirst",
                    "quiGroupFrames.raidSelfFirst",
                    -- quiGroupFrames.clickCast intentionally omitted: click-cast
                    -- bindings live on db.char (per-character) so they cannot
                    -- meaningfully travel through profile import/export.
                },
            },
            { id = "groupFramesParty", label = "Party", description = "Party frame designer settings.", paths = { "quiGroupFrames.party" } },
            { id = "groupFramesRaid", label = "Raid", description = "Raid frame designer settings.", paths = { "quiGroupFrames.raid" } },
        },
    },
    {
        id = "castBars",
        label = "Cast Bars / Power HUD",
        description = "Cast bars, power bars, crosshair, reticle, and HUD layering.",
        recommended = true,
        topLevelKeys = {
            "castBar",
            "targetCastBar",
            "focusCastBar",
            "reticle",
            "crosshair",
            "rangeCheck",
            "skyriding",
            "hudLayering",
            "powerBar",
            "secondaryPowerBar",
            "powerColors",
        },
    },
    {
        id = "cdm",
        label = "CDM / Cooldowns",
        description = "Cooldown viewers, glows, swipe behavior, and rotation-assist settings.",
        recommended = true,
        topLevelKeys = {
            "ncdm",
            "cdmVisibility",
            "viewers",
            "rotationAssistIcon",
            "cooldownSwipe",
            "cooldownEffects",
            "cooldownManager",
            "customGlow",
            "buffBorders",
            "keybindOverridesEnabledCDM",
            "powerBar",
            "secondaryPowerBar",
            "powerColors",
            "cooldownHighlighter",
        },
        children = {
            { id = "cdmEssential", label = "Essential", description = "Essential cooldown rows and essential viewer settings.", paths = { "ncdm.essential" } },
            { id = "cdmUtility", label = "Utility", description = "Utility cooldown rows and utility viewer settings.", paths = { "ncdm.utility" } },
            { id = "cdmBuff", label = "Buff", description = "Buff icon styling and tracked buff bar settings.", paths = { "ncdm.buff" } },
            {
                id = "cdmClassResourceBar",
                label = "Class Resource Bar",
                description = "Primary and secondary class resource bars, including their colors.",
                topLevelKeys = { "powerBar", "secondaryPowerBar", "powerColors" },
            },
            {
                id = "cdmEffectsSubtab",
                label = "Effects",
                description = "Swipes, glow effects, and buff border visuals.",
                topLevelKeys = { "cooldownSwipe", "cooldownEffects", "cooldownManager", "customGlow", "buffBorders" },
            },
            {
                id = "cdmRotationAssist",
                label = "Rotation Assist",
                description = "Rotation assist icon settings.",
                topLevelKeys = { "rotationAssistIcon" },
            },
            {
                id = "cdmKeybinds",
                label = "Keybinds",
                description = "CDM keybind display toggles stored in the profile.",
                topLevelKeys = { "keybindOverridesEnabledCDM" },
            },
        },
    },
    {
        id = "actionBars",
        label = "Action Bars",
        description = "Action bar styling, fade rules, and per-bar behavior.",
        recommended = true,
        topLevelKeys = { "actionBars", "actionBarsVisibility" },
        children = {
            {
                id = "actionBarsMaster",
                label = "Master Settings",
                description = "Global action bar settings shared across bars.",
                paths = { "actionBars.enabled", "actionBars.global" },
            },
            {
                id = "actionBarsMouseover",
                label = "Mouseover Hide",
                description = "Mouseover fade and visibility rules.",
                paths = { "actionBars.fade" },
            },
            {
                id = "actionBarsPerBar",
                label = "Per-Bar Overrides",
                description = "Per-bar overrides for action bars 1-8 and Blizzard support bars.",
                paths = {
                    "actionBars.bars.bar1",
                    "actionBars.bars.bar2",
                    "actionBars.bars.bar3",
                    "actionBars.bars.bar4",
                    "actionBars.bars.bar5",
                    "actionBars.bars.bar6",
                    "actionBars.bars.bar7",
                    "actionBars.bars.bar8",
                    "actionBars.bars.pet",
                    "actionBars.bars.stance",
                    "actionBars.bars.microbar",
                    "actionBars.bars.bags",
                },
            },
            {
                id = "actionBarsExtraButtons",
                label = "Extra Buttons",
                description = "Extra Action Button and Zone Ability Button settings.",
                paths = {
                    "actionBars.bars.extraActionButton",
                    "actionBars.bars.zoneAbility",
                },
            },
            {
                id = "actionBarsTotemBar",
                label = "Totem Bar",
                description = "Blizzard TotemFrame bar settings (totems, guardians, etc., per class).",
                topLevelKeys = { "totemBar" },
            },
        },
    },
    {
        id = "minimapDatatexts",
        label = "Minimap / Datatexts",
        description = "Minimap, datatext panel, and extra datatext settings.",
        recommended = true,
        topLevelKeys = { "minimap", "minimapButton", "datatext", "quiDatatexts" },
        children = {
            {
                id = "minimapSubtab",
                label = "Minimap",
                description = "Minimap frame and minimap utility settings.",
                topLevelKeys = { "minimap", "minimapButton" },
            },
            {
                id = "datatextSubtab",
                label = "Datatext",
                description = "Minimap datatexts and custom movable datatext panels.",
                topLevelKeys = { "datatext", "quiDatatexts" },
            },
        },
    },
    {
        id = "customTrackers",
        label = "Custom CDM Bars",
        description = "Custom CDM bar settings and individual imported bars.",
        recommended = true,
        topLevelKeys = { "customTrackers", "customTrackersVisibility", "keybindOverridesEnabledTrackers" },
        children = {
            {
                id = "customTrackersShared",
                label = "Shared Settings",
                description = "CDM bar keybind display and shared visibility settings.",
                topLevelKeys = { "customTrackersVisibility", "keybindOverridesEnabledTrackers" },
                paths = {
                    "customTrackers.keybinds",
                },
            },
        },
    },
    {
        id = "trackersTimers",
        label = "Timers / Widgets",
        description = "M+ timer, combat timers, XP tracker, and other utility widgets.",
        recommended = true,
        topLevelKeys = {
            "mplusTimer",
            "mplusProgress",
            "combatText",
            "brzCounter",
            "atonementCounter",
            "combatTimer",
            "xpTracker",
            "totemBar",
            "preyTracker",
        },
    },
    {
        id = "chat",
        label = "Chat",
        description = "Chat frame skinning, formatting, and utility options.",
        recommended = true,
        topLevelKeys = { "chat", "chatVisibility" },
    },
    {
        id = "qol",
        label = "QoL / Automation",
        description = "Automation helpers, popup blocker, consumables, and utility toggles.",
        recommended = true,
        topLevelKeys = { "uiHider", "configPanelWidth", "configPanelAlpha", "configPanelScale" },
        generalKeys = PROFILE_QOL_GENERAL_KEYS,
    },
    {
        id = "skinning",
        label = "Skinning / Blizzard UI",
        description = "Tooltip, alerts, character pane, and Blizzard skinning options.",
        recommended = true,
        topLevelKeys = { "alerts", "tooltip", "character", "loot", "lootRoll", "lootResults" },
        generalKeys = PROFILE_SKINNING_GENERAL_KEYS,
    },
}

local PROFILE_IMPORT_CATEGORY_BY_ID = {}
local PROFILE_IMPORT_CHILDREN_BY_PARENT = {}

local function RegisterImportCategory(category, parentID)
    PROFILE_IMPORT_CATEGORY_BY_ID[category.id] = category
    if parentID then
        PROFILE_IMPORT_CHILDREN_BY_PARENT[parentID] = PROFILE_IMPORT_CHILDREN_BY_PARENT[parentID] or {}
        PROFILE_IMPORT_CHILDREN_BY_PARENT[parentID][#PROFILE_IMPORT_CHILDREN_BY_PARENT[parentID] + 1] = category
    end

    if type(category.children) == "table" then
        for _, child in ipairs(category.children) do
            RegisterImportCategory(child, category.id)
        end
    end
end

for _, category in ipairs(PROFILE_IMPORT_CATEGORIES) do
    RegisterImportCategory(category)
end

local function ParseCustomTrackerBarSelectionID(categoryID)
    if type(categoryID) ~= "string" then
        return nil
    end

    local indexText = categoryID:match("^" .. CUSTOM_TRACKER_BAR_ID_PREFIX:gsub("%-", "%%-") .. "(%d+)$")
    local index = indexText and tonumber(indexText)
    if index and index > 0 then
        return index
    end
    return nil
end

local function GetValueAtPath(root, path)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return nil, false
    end

    local node = root
    for segment in path:gmatch("[^.]+") do
        if type(node) ~= "table" then
            return nil, false
        end
        node = node[segment]
        if node == nil then
            return nil, false
        end
    end

    return node, true
end

local function SetValueAtPath(root, path, value)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return
    end

    local parent = root
    local segments = {}
    for segment in path:gmatch("[^.]+") do
        segments[#segments + 1] = segment
    end

    if #segments == 0 then
        return
    end

    for i = 1, #segments - 1 do
        local segment = segments[i]
        local nextNode = parent[segment]
        if type(nextNode) ~= "table" then
            if value == nil then
                return
            end
            nextNode = {}
            parent[segment] = nextNode
        end
        parent = nextNode
    end

    parent[segments[#segments]] = CloneValue(value)
end

local function CopyTopLevelKeys(targetProfile, importedProfile, keys)
    if type(targetProfile) ~= "table" or type(importedProfile) ~= "table" or type(keys) ~= "table" then
        return
    end

    for _, key in ipairs(keys) do
        if importedProfile[key] ~= nil then
            targetProfile[key] = CloneValue(importedProfile[key])
        end
    end
end

local function CopyGeneralKeys(targetProfile, importedProfile, keys)
    if type(targetProfile) ~= "table" or type(importedProfile) ~= "table" or type(keys) ~= "table" then
        return
    end

    local importedGeneral = importedProfile.general
    if type(importedGeneral) ~= "table" then
        return
    end

    if type(targetProfile.general) ~= "table" then
        targetProfile.general = {}
    end

    for _, key in ipairs(keys) do
        if importedGeneral[key] ~= nil then
            targetProfile.general[key] = CloneValue(importedGeneral[key])
        end
    end
end

local function CopyPathList(targetProfile, importedProfile, paths)
    if type(targetProfile) ~= "table" or type(importedProfile) ~= "table" or type(paths) ~= "table" then
        return
    end

    for _, path in ipairs(paths) do
        local value, exists = GetValueAtPath(importedProfile, path)
        if exists then
            SetValueAtPath(targetProfile, path, value)
        end
    end
end

local function RestorePathList(targetProfile, previousProfile, paths)
    if type(targetProfile) ~= "table" or type(previousProfile) ~= "table" or type(paths) ~= "table" then
        return
    end

    for _, path in ipairs(paths) do
        local value, exists = GetValueAtPath(previousProfile, path)
        if exists then
            SetValueAtPath(targetProfile, path, value)
        else
            SetValueAtPath(targetProfile, path, nil)
        end
    end
end

local function RestoreCustomTrackerLayout(targetProfile, previousProfile)
    local targetBars = targetProfile
        and targetProfile.customTrackers
        and targetProfile.customTrackers.bars
    local previousBars = previousProfile
        and previousProfile.customTrackers
        and previousProfile.customTrackers.bars

    if type(targetBars) ~= "table" or type(previousBars) ~= "table" then
        return
    end

    for index, previousBar in ipairs(previousBars) do
        local targetBar = targetBars[index]
        if type(previousBar) == "table" and type(targetBar) == "table" then
            if previousBar.offsetX ~= nil then targetBar.offsetX = CloneValue(previousBar.offsetX) end
            if previousBar.offsetY ~= nil then targetBar.offsetY = CloneValue(previousBar.offsetY) end
            if previousBar.locked ~= nil then targetBar.locked = CloneValue(previousBar.locked) end
        end
    end
end

local function RestoreDatatextPanelLayout(targetProfile, previousProfile)
    local targetPanels = targetProfile
        and targetProfile.quiDatatexts
        and targetProfile.quiDatatexts.panels
    local previousPanels = previousProfile
        and previousProfile.quiDatatexts
        and previousProfile.quiDatatexts.panels

    if type(targetPanels) ~= "table" or type(previousPanels) ~= "table" then
        return
    end

    for index, previousPanel in ipairs(previousPanels) do
        local targetPanel = targetPanels[index]
        if type(previousPanel) == "table" and type(targetPanel) == "table" then
            if previousPanel.position ~= nil then
                targetPanel.position = CloneValue(previousPanel.position)
            else
                targetPanel.position = nil
            end
        end
    end
end

local function ImportSelectedCustomTrackerBars(core, targetProfile, importedProfile, barIndexes)
    if type(targetProfile) ~= "table" or type(importedProfile) ~= "table" or type(barIndexes) ~= "table" then
        return false
    end

    local importedBars = importedProfile.customTrackers and importedProfile.customTrackers.bars
    if type(importedBars) ~= "table" then
        return false
    end

    if type(targetProfile.customTrackers) ~= "table" then
        targetProfile.customTrackers = {}
    end
    if type(targetProfile.customTrackers.bars) ~= "table" then
        targetProfile.customTrackers.bars = {}
    end

    local importedAny = false
    local mappings = {}
    for _, barIndex in ipairs(barIndexes) do
        local sourceBar = importedBars[barIndex]
        if type(sourceBar) == "table" then
            local clonedBar = CloneValue(sourceBar)
            local sourceID = clonedBar.id
            clonedBar.id = GenerateUniqueTrackerID()
            clonedBar._importedLegacyId = sourceID
            table.insert(targetProfile.customTrackers.bars, clonedBar)
            mappings[#mappings + 1] = {
                sourceID = sourceID,
                targetID = clonedBar.id,
            }
            importedAny = true
        end
    end

    return importedAny, mappings
end

local function DetectProfileImportPrefix(str)
    if type(str) ~= "string" then
        return nil
    end
    return str:match("^([A-Z][A-Z0-9]*%d):")
end

local function DeserializeProfileImportPayload(str)
    if not AceSerializer or not LibDeflate then
        return false, nil, nil, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, nil, nil, "No data provided."
    end

    str = str:gsub("%s+", "")
    if str == "" then
        return false, nil, nil, "No data provided."
    end

    local prefix = DetectProfileImportPrefix(str)
    if prefix then
        if not SUPPORTED_PROFILE_IMPORT_PREFIXES[prefix] then
            return false, nil, nil, ("This doesn't appear to be a QUI profile string (%s)."):format(prefix)
        end
        str = str:sub(#prefix + 2)
    else
        prefix = "QUI1"
    end

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, nil, prefix, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, nil, prefix, "Could not decompress data."
    end

    local ok, payload = AceSerializer:Deserialize(serialized)
    if not ok or type(payload) ~= "table" then
        return false, nil, prefix, "Could not deserialize profile."
    end

    return true, payload, prefix, nil
end

local function ParseProfileImportString(core, str)
    if not core or not core.db or not core.db.profile then
        return false, "No profile loaded."
    end

    local ok, payload, prefix, decodeErr = DeserializeProfileImportPayload(str)
    if not ok then
        return false, decodeErr or "Could not read import string."
    end

    local payloadValid, payloadErr = ValidateProfilePayload(core, payload)
    if not payloadValid then
        return false, payloadErr or "Import failed profile validation."
    end

    return true, payload, prefix
end

local function CategoryHasData(category, profileData)
    if type(category) ~= "table" or type(profileData) ~= "table" then
        return false
    end

    if type(category.topLevelKeys) == "table" then
        for _, key in ipairs(category.topLevelKeys) do
            if profileData[key] ~= nil then
                return true
            end
        end
    end

    if type(category.generalKeys) == "table" and type(profileData.general) == "table" then
        for _, key in ipairs(category.generalKeys) do
            if profileData.general[key] ~= nil then
                return true
            end
        end
    end

    if type(category.paths) == "table" then
        for _, path in ipairs(category.paths) do
            local _, exists = GetValueAtPath(profileData, path)
            if exists then
                return true
            end
        end
    end

    return false
end

local function BuildProfileImportPreview(profileData, prefix, importType)
    local function BuildCategoryPreview(category)
        local children = nil
        local hasAvailableChild = false

        if type(category.children) == "table" then
            children = {}
            for _, child in ipairs(category.children) do
                local childPreview = BuildCategoryPreview(child)
                children[#children + 1] = childPreview
                if childPreview.available then
                    hasAvailableChild = true
                end
            end
        end

        if category.id == "customTrackers" then
            local dynamicChildren = BuildCustomTrackerBarPreviewChildren(profileData)
            if dynamicChildren then
                children = children or {}
                for _, childPreview in ipairs(dynamicChildren) do
                    children[#children + 1] = childPreview
                    if childPreview.available then
                        hasAvailableChild = true
                    end
                end
            end
        end

        local available = CategoryHasData(category, profileData)
        if hasAvailableChild then
            available = true
        end

        return {
            id = category.id,
            label = category.label,
            description = category.description,
            recommended = category.recommended and true or false,
            available = available,
            children = children,
        }
    end

    local categories = {}
    for _, category in ipairs(PROFILE_IMPORT_CATEGORIES) do
        categories[#categories + 1] = BuildCategoryPreview(category)
    end

    return {
        importType = importType or "QUI Profile",
        prefix = prefix or "QUI1",
        categories = categories,
    }
end

local function BuildSelectedCategoryLabel(category)
    if not category then
        return nil
    end

    for parentID, children in pairs(PROFILE_IMPORT_CHILDREN_BY_PARENT) do
        for _, child in ipairs(children) do
            if child == category then
                local parent = PROFILE_IMPORT_CATEGORY_BY_ID[parentID]
                if parent then
                    return ("%s > %s"):format(parent.label, category.label)
                end
            end
        end
    end

    return category.label
end

local function CollectSelectedProfileCategories(selectedCategoryIDs, profileData)
    if type(selectedCategoryIDs) ~= "table" then
        return false, "Select at least one category."
    end

    local selectedLookup = {}
    local selectedLabels = {}
    local selectedSpecs = {}
    local selectedCustomTrackerBarIndexes = {}

    for _, categoryID in ipairs(selectedCategoryIDs) do
        local category = PROFILE_IMPORT_CATEGORY_BY_ID[categoryID]
        if category and not selectedLookup[categoryID] then
            selectedLookup[categoryID] = true
            selectedLabels[#selectedLabels + 1] = BuildSelectedCategoryLabel(category)
            selectedSpecs[#selectedSpecs + 1] = category
        else
            local barIndex = ParseCustomTrackerBarSelectionID(categoryID)
            if barIndex and not selectedLookup[categoryID] then
                selectedLookup[categoryID] = true
                selectedCustomTrackerBarIndexes[#selectedCustomTrackerBarIndexes + 1] = barIndex

                local trackerRecords = CollectCustomTrackerExportRecords(profileData)
                local selectedBar = trackerRecords[barIndex] and trackerRecords[barIndex].bar or nil
                local barName = type(selectedBar) == "table" and selectedBar.name or ("Bar " .. barIndex)
                selectedLabels[#selectedLabels + 1] = ("Custom CDM Bars > %s"):format(tostring(barName))
            end
        end
    end

    if #selectedLabels == 0 then
        return false, "Select at least one category."
    end

    return true, {
        lookup = selectedLookup,
        labels = selectedLabels,
        specs = selectedSpecs,
        customTrackerBarIndexes = selectedCustomTrackerBarIndexes,
    }
end

local function ApplyProfileImportCategory(targetProfile, importedProfile, category)
    if type(targetProfile) ~= "table" or type(importedProfile) ~= "table" or type(category) ~= "table" then
        return
    end

    CopyTopLevelKeys(targetProfile, importedProfile, category.topLevelKeys)
    CopyGeneralKeys(targetProfile, importedProfile, category.generalKeys)
    CopyPathList(targetProfile, importedProfile, category.paths)

    if category.id == "layout" and type(importedProfile.bigWigs) == "table" then
        if type(targetProfile.bigWigs) ~= "table" then
            targetProfile.bigWigs = {}
        end
        if importedProfile.bigWigs.normal ~= nil then
            targetProfile.bigWigs.normal = CloneValue(importedProfile.bigWigs.normal)
        end
        if importedProfile.bigWigs.emphasized ~= nil then
            targetProfile.bigWigs.emphasized = CloneValue(importedProfile.bigWigs.emphasized)
        end
    end
end

local function ExportSelectedCustomTrackerBars(targetProfile, sourceProfile, barIndexes)
    if type(targetProfile) ~= "table" or type(sourceProfile) ~= "table" or type(barIndexes) ~= "table" then
        return false
    end

    local sourceRecords = CollectCustomTrackerExportRecords(sourceProfile)
    if #sourceRecords == 0 then
        return false
    end

    if type(targetProfile.customTrackers) ~= "table" then
        targetProfile.customTrackers = {}
    end
    if type(targetProfile.customTrackers.bars) ~= "table" then
        targetProfile.customTrackers.bars = {}
    end

    local exportedAny = false
    for _, barIndex in ipairs(barIndexes) do
        local record = sourceRecords[barIndex]
        local sourceBar = record and record.bar
        if type(sourceBar) == "table" then
            table.insert(targetProfile.customTrackers.bars, CloneValue(sourceBar))
            exportedAny = true
        end
    end

    return exportedAny
end

-- Tracker bar entries with specSpecificSpells live in db.global, not
-- db.profile, so a profile-scoped export drops them. We bundle the
-- relevant subtrees under a top-level key on the payload, then unpack
-- them into db.global on import. Self-contained — no schema knowledge
-- needed beyond "these specific tables hold tracker spell entries".
local PROFILE_EXPORT_GLOBALS_KEY = "_quiBundledGlobals"

local function CollectExportGlobals(globals, profile)
    if type(globals) ~= "table" then return nil end
    local bundle = nil
    if type(globals.specTrackerSpells) == "table" and next(globals.specTrackerSpells) then
        bundle = bundle or {}
        bundle.specTrackerSpells = globals.specTrackerSpells
    end
    if type(globals.ncdm) == "table"
       and type(globals.ncdm.specTrackerSpells) == "table"
       and next(globals.ncdm.specTrackerSpells)
    then
        bundle = bundle or {}
        bundle.ncdm_specTrackerSpells = globals.ncdm.specTrackerSpells
    end
    local records = CollectCustomTrackerExportRecords(profile)
    local legacySpecEntries = CollectLegacySpecEntriesForExportRecords(records, globals)
    if legacySpecEntries then
        bundle = bundle or {}
        local merged = CloneValue(bundle.specTrackerSpells or {})
        for key, value in pairs(legacySpecEntries) do
            merged[key] = value
        end
        bundle.specTrackerSpells = merged
    end
    return bundle
end

local function ApplyImportedGlobals(core, bundle)
    if type(bundle) ~= "table" then return end
    local globals = core and core.db and core.db.global
    if type(globals) ~= "table" then return end

    if type(bundle.specTrackerSpells) == "table" then
        globals.specTrackerSpells = CloneValue(bundle.specTrackerSpells)
    end
    if type(bundle.ncdm_specTrackerSpells) == "table" then
        if type(globals.ncdm) ~= "table" then globals.ncdm = {} end
        globals.ncdm.specTrackerSpells = CloneValue(bundle.ncdm_specTrackerSpells)
    end
end

local function EnsureGlobalSpecTrackerRoots(core)
    local globals = core and core.db and core.db.global
    if type(globals) ~= "table" then return nil end
    if type(globals.specTrackerSpells) ~= "table" then
        globals.specTrackerSpells = {}
    end
    if type(globals.ncdm) ~= "table" then
        globals.ncdm = {}
    end
    if type(globals.ncdm.specTrackerSpells) ~= "table" then
        globals.ncdm.specTrackerSpells = {}
    end
    return globals
end

local function MergeImportedCustomTrackerGlobals(core, bundle, mappings)
    if type(bundle) ~= "table" then return end
    local globals = EnsureGlobalSpecTrackerRoots(core)
    if not globals then return end

    if type(mappings) == "table" and #mappings > 0 then
        for _, mapping in ipairs(mappings) do
            local sourceID = mapping.sourceID
            local targetID = mapping.targetID
            if sourceID ~= nil then
                local sourceLegacy = type(bundle.specTrackerSpells) == "table"
                    and bundle.specTrackerSpells[sourceID]
                if type(sourceLegacy) == "table" then
                    globals.specTrackerSpells[sourceID] = CloneValue(sourceLegacy)
                end

                local sourceContainerKey = "customBar_" .. tostring(sourceID)
                local targetContainerKey = "customBar_" .. tostring(targetID)
                local sourceNCDM = type(bundle.ncdm_specTrackerSpells) == "table"
                    and bundle.ncdm_specTrackerSpells[sourceContainerKey]
                if type(sourceNCDM) == "table" then
                    globals.ncdm.specTrackerSpells[targetContainerKey] = CloneValue(sourceNCDM)
                end
            end
        end
        return
    end

    if type(bundle.specTrackerSpells) == "table" then
        for key, value in pairs(bundle.specTrackerSpells) do
            globals.specTrackerSpells[key] = CloneValue(value)
        end
    end
    if type(bundle.ncdm_specTrackerSpells) == "table" then
        for key, value in pairs(bundle.ncdm_specTrackerSpells) do
            globals.ncdm.specTrackerSpells[key] = CloneValue(value)
        end
    end
end

local function ApplyFullProfilePayload(core, importedProfile)
    local profile = core and core.db and core.db.profile
    if type(profile) ~= "table" or type(importedProfile) ~= "table" then
        return false, "No profile loaded."
    end

    local bundledGlobals = importedProfile[PROFILE_EXPORT_GLOBALS_KEY]

    for key in pairs(profile) do
        profile[key] = nil
    end
    for key, value in pairs(importedProfile) do
        -- Strip any stale migration backup that rode along in the export.
        -- It refers to the source user's profile state and is meaningless
        -- here. A fresh backup will be created by the migration pipeline
        -- below if the imported data actually needs migrating.
        if key ~= "_migrationBackup" and key ~= PROFILE_EXPORT_GLOBALS_KEY then
            profile[key] = CloneValue(value)
        end
    end

    ApplyImportedGlobals(core, bundledGlobals)

    -- Capture the imported _lastSpecID onto each spec-specific bar before
    -- migrations or the live session can overwrite the field. Otherwise
    -- a priest profile imported on a warrior loses its priest origin the
    -- moment the warrior's session saves.
    StampSourceSpecOnImportedSpecBars(profile, importedProfile)

    local pins = ns.Settings and ns.Settings.Pins
    if pins and type(pins.HandleFullImportSnapshot) == "function" then
        local migratedImport = CloneValue(importedProfile)
        if ns.Migrations and type(ns.Migrations.RunOnProfile) == "function" then
            ns.Migrations.RunOnProfile(migratedImport)
        end
        pins:HandleFullImportSnapshot(core.db, migratedImport)
    end

    -- Run backward-compatibility migrations on the freshly imported data
    -- so that legacy keys (castBar, unitFrames, etc.) are moved to their
    -- current locations before any module tries to read them.
    local addon = _G.QUI
    if addon and addon.BackwardsCompat then
        addon:BackwardsCompat()
    end

    -- If the import payload already carries the current schema but only has
    -- legacy tracker bars, the schema gate will no-op. Normalize explicitly.
    SyncCustomTrackerBarsToCDM(core, profile)

    -- Refresh all modules via the Registry (includes frame anchoring).
    -- Falls back to core:RefreshAll() if the Registry is not available.
    if ns.Registry then
        ns.Registry:RefreshAll()
    elseif core.RefreshAll then
        core:RefreshAll()
    end

    -- Imported profiles may contain CDM spells from a different class/spec.
    -- Clear the imported ownedSpells and re-snapshot from Blizzard's CDM
    -- viewers so the current spec's abilities display immediately.
    if ns.CDMContainers and ns.CDMContainers.ResnapshotForCurrentSpec then
        ns.CDMContainers.ResnapshotForCurrentSpec()
    end

    return true, "Profile imported successfully."
end

local function NormalizeOptionalProfileName(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return nil
    end
    return name
end

local function PrepareImportTargetProfile(core, requestedProfileName)
    local db = core and core.db
    if not db or not db.profile then
        return false, "No profile loaded."
    end

    local explicitName = NormalizeOptionalProfileName(requestedProfileName)
    local currentName = db.GetCurrentProfile and db:GetCurrentProfile() or "Default"
    if not explicitName then
        return true, currentName, false
    end

    if explicitName ~= currentName then
        local ok, err = pcall(db.SetProfile, db, explicitName)
        if not ok then
            return false, ("Could not switch to profile '%s': %s"):format(explicitName, tostring(err))
        end
    end

    return true, (db.GetCurrentProfile and db:GetCurrentProfile()) or explicitName, true
end

local function RunImportFullProfile(core, importedProfile, targetProfileName)
    local targetOK, activeProfileName, usingExplicitTarget = PrepareImportTargetProfile(core, targetProfileName)
    if not targetOK then
        return false, activeProfileName
    end

    local importOK, message = ApplyFullProfilePayload(core, importedProfile)
    if importOK and usingExplicitTarget then
        return true, ("Profile imported successfully into profile '%s'."):format(activeProfileName)
    end
    return importOK, message
end

local function RunImportProfileSelection(core, payloadOrErr, selectedCategoryIDs, targetProfileName)
    local selectionOK, selectionData = CollectSelectedProfileCategories(selectedCategoryIDs, payloadOrErr)
    if not selectionOK then
        return false, "Select at least one category to import."
    end

    local selectedLookup = selectionData.lookup
    local selectedLabels = selectionData.labels
    local selectedSpecs = selectionData.specs
    local selectedCustomTrackerBarIndexes = selectionData.customTrackerBarIndexes

    local targetOK, activeProfileName, usingExplicitTarget = PrepareImportTargetProfile(core, targetProfileName)
    if not targetOK then
        return false, activeProfileName
    end

    local profile = core.db and core.db.profile
    if type(profile) ~= "table" then
        return false, "No profile loaded."
    end

    local previousProfile = CloneValue(profile)

    for _, category in ipairs(selectedSpecs) do
        ApplyProfileImportCategory(profile, payloadOrErr, category)
    end

    local importedCustomTrackerMappings
    if not selectedLookup.customTrackers and #selectedCustomTrackerBarIndexes > 0 then
        local importedBars
        importedBars, importedCustomTrackerMappings = ImportSelectedCustomTrackerBars(core, profile, payloadOrErr, selectedCustomTrackerBarIndexes)
        if not importedBars then
            importedCustomTrackerMappings = nil
        end
    end

    if selectedLookup.customTrackers or #selectedCustomTrackerBarIndexes > 0 then
        MergeImportedCustomTrackerGlobals(
            core,
            payloadOrErr[PROFILE_EXPORT_GLOBALS_KEY],
            selectedLookup.customTrackers and nil or importedCustomTrackerMappings
        )
        -- Same import-time stamping as the full-profile path: capture the
        -- imported _lastSpecID onto spec-specific bars before SyncCustomTrackerBarsToCDM
        -- builds the V2 containers (which clone bar fields verbatim).
        StampSourceSpecOnImportedSpecBars(profile, payloadOrErr)
        SyncCustomTrackerBarsToCDM(core, profile)
        if type(profile.customTrackers) == "table" and type(profile.customTrackers.bars) == "table" then
            for _, bar in ipairs(profile.customTrackers.bars) do
                if type(bar) == "table" then
                    bar._importedLegacyId = nil
                end
            end
        end
    end

    local function CategoryCanImportThemePath(category, path)
        if type(category) ~= "table" or type(path) ~= "string" or path == "" then
            return false
        end

        if type(category.paths) == "table" then
            for _, itemPath in ipairs(category.paths) do
                if itemPath == path then
                    return true
                end
            end
        end

        local generalKey = path:match("^general%.(.+)$")
        if generalKey and type(category.generalKeys) == "table" then
            for _, key in ipairs(category.generalKeys) do
                if key == generalKey then
                    return true
                end
            end
        end

        if type(category.topLevelKeys) == "table" then
            for _, key in ipairs(category.topLevelKeys) do
                if key == path then
                    return true
                end
            end
        end

        return false
    end

    local function SelectedSpecsCoverThemePath(path)
        for _, category in ipairs(selectedSpecs) do
            if CategoryCanImportThemePath(category, path) then
                return true
            end
        end
        return false
    end

    if not selectedLookup.theme then
        for _, path in ipairs(PROFILE_THEME_PRESERVE_PATHS) do
            if not SelectedSpecsCoverThemePath(path) then
                RestorePathList(profile, previousProfile, { path })
            end
        end
    end

    if not selectedLookup.layout then
        RestorePathList(profile, previousProfile, PROFILE_LAYOUT_PATHS)
        RestoreCustomTrackerLayout(profile, previousProfile)
        RestoreDatatextPanelLayout(profile, previousProfile)
    end

    local pins = ns.Settings and ns.Settings.Pins
    if pins and type(pins.HandleSelectiveImport) == "function" then
        pins:HandleSelectiveImport(core.db, selectedSpecs)
    end

    if ns.Registry then
        ns.Registry:RefreshByCategories(selectedCategoryIDs)
    elseif core.RefreshAll then
        core:RefreshAll()
    end

    -- Imported profiles may contain CDM spells from a different class/spec.
    -- Clear the imported ownedSpells and re-snapshot from Blizzard's CDM
    -- viewers so the current spec's abilities display immediately.
    if ns.CDMContainers and ns.CDMContainers.ResnapshotForCurrentSpec then
        ns.CDMContainers.ResnapshotForCurrentSpec()
    end

    if usingExplicitTarget then
        return true, ("Imported %s into profile '%s'."):format(table.concat(selectedLabels, ", "), activeProfileName)
    end
    return true, ("Imported %s."):format(table.concat(selectedLabels, ", "))
end

local function SerializeProfileExportPayload(payload)
    if type(payload) ~= "table" then
        return nil, "Failed to serialize profile."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local serialized = AceSerializer:Serialize(payload)
    if not serialized or type(serialized) ~= "string" then
        return nil, "Failed to serialize profile."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Failed to compress profile."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Failed to encode profile."
    end

    return "QUI1:" .. encoded
end

local function RunExportProfileSelection(core, selectedCategoryIDs)
    local profile = core and core.db and core.db.profile
    if type(profile) ~= "table" then
        return nil, "No profile loaded."
    end

    local selectionOK, selectionData = CollectSelectedProfileCategories(selectedCategoryIDs, profile)
    if not selectionOK then
        return nil, "Select at least one category to export."
    end

    local exportPayload = {}
    for _, category in ipairs(selectionData.specs) do
        ApplyProfileImportCategory(exportPayload, profile, category)
    end
    if selectionData.lookup.customTrackers then
        StampCustomTrackerBarsForExport(exportPayload, profile)
    end

    if not selectionData.lookup.customTrackers and #selectionData.customTrackerBarIndexes > 0 then
        ExportSelectedCustomTrackerBars(exportPayload, profile, selectionData.customTrackerBarIndexes)
    end

    if selectionData.lookup.customTrackers or #selectionData.customTrackerBarIndexes > 0 then
        local bundle = CollectExportGlobals(core and core.db and core.db.global, profile)
        if bundle then
            exportPayload[PROFILE_EXPORT_GLOBALS_KEY] = bundle
        end
    end

    return SerializeProfileExportPayload(exportPayload)
end

---=================================================================================
--- PROFILE IMPORT/EXPORT
---=================================================================================

function QUICore:ExportProfileToString()
    if not self.db or not self.db.profile then
        return "No profile loaded."
    end

    -- Shallow-copy so we can strip `_migrationBackup` (per-profile rollback
    -- buffer, not user data) without mutating the live profile.
    local payload = {}
    for k, v in pairs(self.db.profile) do
        if k ~= "_migrationBackup" then
            payload[k] = v
        end
    end
    StampCustomTrackerBarsForExport(payload, self.db.profile)

    local bundle = CollectExportGlobals(self.db.global, self.db.profile)
    if bundle then
        payload[PROFILE_EXPORT_GLOBALS_KEY] = bundle
    end

    local exportString, exportErr = SerializeProfileExportPayload(payload)
    return exportString or exportErr or "Failed to export profile."
end

function QUICore:GetProfileImportCategories()
    return BuildProfileImportPreview({}, "QUI1").categories or {}
end

function QUICore:GetProfileExportCategories()
    local profile = self and self.db and self.db.profile
    return BuildProfileImportPreview(profile or {}, "QUI1", "Current Profile").categories or {}
end

function QUICore:BuildProfileImportPreviewFromPayload(payload, prefix)
    if type(payload) ~= "table" then
        return nil
    end
    return BuildProfileImportPreview(payload, prefix or "QUI1")
end

function QUICore:BuildProfileExportPreview()
    local profile = self and self.db and self.db.profile
    if type(profile) ~= "table" then
        return nil
    end
    return BuildProfileImportPreview(profile, "QUI1", "Current Profile")
end

function QUICore:DescribeProfileImportValidationErrors(detail)
    if type(detail) ~= "table" then
        return tostring(detail or "Unknown error")
    end
    local lines = { detail.summary or "Validation failed.", "" }
    for _, err in ipairs(detail.errors or {}) do
        lines[#lines + 1] = "• " .. FormatDetailedLine(err)
    end
    return table.concat(lines, "\n")
end


function QUICore:AnalyzeProfileImportString(str)
    if not self.db or not self.db.profile then
        return false, "No profile loaded."
    end

    local ok, payload, prefix, decodeErr = DeserializeProfileImportPayload(str)
    if not ok then
        return false, decodeErr or "Could not read import string."
    end

    local vok, detail = ValidateProfilePayloadDetailed(self, payload)
    if not vok then
        return false, detail
    end

    return true, BuildProfileImportPreview(payload, prefix)
end

function QUICore:SanitizeProfileImportString(str)
    if not self.db or not self.db.profile then
        return false, nil, nil, nil, "No profile loaded."
    end

    local ok, payload, prefix, decodeErr = DeserializeProfileImportPayload(str)
    if not ok then
        return false, nil, nil, nil, decodeErr or "Could not read import string."
    end

    local sok, sanitized, stripped, serr = SanitizeProfilePayload(self, payload)
    stripped = stripped or {}
    if not sok then
        return false, nil, prefix, stripped, serr or "Could not remove incompatible settings."
    end

    return true, sanitized, prefix, stripped, nil
end

function QUICore:ImportProfileFromString(str, targetProfileName)
    local ok, payloadOrErr = ParseProfileImportString(self, str)
    if not ok then
        -- Strict validation failed — attempt auto-sanitize (strip incompatible types and retry)
        local sok, sanitized, prefix, stripped, serr = self:SanitizeProfileImportString(str)
        if not sok then
            return false, payloadOrErr  -- Return original error if sanitize also fails
        end
        if stripped and #stripped > 0 then
            local count = #stripped
            print(("|cff60A5FAQUI:|r Auto-fixed %d incompatible setting%s during import."):format(count, count == 1 and "" or "s"))
        end
        payloadOrErr = sanitized
    end

    return RunImportFullProfile(self, payloadOrErr, targetProfileName)
end

function QUICore:ImportProfileFromValidatedPayload(payload, targetProfileName)
    if type(payload) ~= "table" then
        return false, "Invalid import data."
    end

    local payloadValid, payloadErr = ValidateProfilePayload(self, payload)
    if not payloadValid then
        return false, payloadErr
    end

    return RunImportFullProfile(self, payload, targetProfileName)
end

function QUICore:ImportProfileSelectionFromString(str, selectedCategoryIDs, targetProfileName)
    local ok, payloadOrErr = ParseProfileImportString(self, str)
    if not ok then
        return false, payloadOrErr
    end

    return RunImportProfileSelection(self, payloadOrErr, selectedCategoryIDs, targetProfileName)
end

function QUICore:ImportProfileSelectionFromValidatedPayload(payload, selectedCategoryIDs, targetProfileName)
    if type(payload) ~= "table" then
        return false, "Invalid import data."
    end

    local payloadValid, payloadErr = ValidateProfilePayload(self, payload)
    if not payloadValid then
        return false, payloadErr
    end

    return RunImportProfileSelection(self, payload, selectedCategoryIDs, targetProfileName)
end

function QUICore:ExportProfileSelectionToString(selectedCategoryIDs)
    return RunExportProfileSelection(self, selectedCategoryIDs)
end

---=================================================================================
--- CUSTOM TRACKER BAR IMPORT/EXPORT
---=================================================================================

-- Generate a collision-safe unique tracker ID
function QUICore:GenerateUniqueTrackerID()
    local db = self and self.db or QUICore.db
    local used = {}
    local bars = db and db.profile and db.profile.customTrackers and db.profile.customTrackers.bars or {}
    for _, b in ipairs(bars) do
        if b.id then used[b.id] = true end
    end
    if db and db.global and db.global.specTrackerSpells then
        for id in pairs(db.global.specTrackerSpells) do
            used[id] = true
        end
    end
    local containers = db and db.profile and db.profile.ncdm and db.profile.ncdm.containers
    if type(containers) == "table" then
        for key, container in pairs(containers) do
            if type(container) == "table" then
                if container._legacyId then used[container._legacyId] = true end
                local suffix = type(key) == "string" and key:match("^customBar_(.+)$")
                if suffix then used[suffix] = true end
            end
        end
    end
    local id
    repeat
        id = "tracker" .. time() .. math.random(1000, 9999)
    until not used[id]
    return id
end

GenerateUniqueTrackerID = function()
    return QUICore:GenerateUniqueTrackerID()
end

-- Export a single tracker bar (with its spec-specific entries if enabled)
function QUICore:ExportSingleTrackerBar(barIndex)
    if not self.db or not self.db.profile then
        return nil, "No tracker data loaded."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local records = CollectCustomTrackerExportRecords(self.db.profile)
    local record = records[barIndex]
    local bar = record and record.bar
    if not bar then
        return nil, "Bar not found."
    end

    -- Build export data including spec-specific entries if enabled
    local exportData = {
        bar = bar,
        specEntries = nil,
    }

    -- Include spec-specific entries if the bar uses them
    if bar.specSpecificSpells and self.db.global then
        exportData.specEntries = CollectSpecEntriesForExportRecord(record, self.db.global)
    end

    local serialized = AceSerializer:Serialize(exportData)
    if not serialized or type(serialized) ~= "string" then
        return nil, "Failed to serialize bar."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Failed to compress bar data."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Failed to encode bar data."
    end

    return "QCB1:" .. encoded
end

-- Export all tracker bars
function QUICore:ExportAllTrackerBars()
    if not self.db or not self.db.profile then
        return nil, "No tracker data loaded."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local records = CollectCustomTrackerExportRecords(self.db.profile)
    local bars = ExtractBarsFromExportRecords(records)
    if not bars or #bars == 0 then
        return nil, "No tracker bars to export."
    end

    local exportData = {
        bars = bars,
        specEntries = self.db.global and CollectLegacySpecEntriesForExportRecords(records, self.db.global) or nil,
    }

    local serialized = AceSerializer:Serialize(exportData)
    if not serialized or type(serialized) ~= "string" then
        return nil, "Failed to serialize bars."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Failed to compress bar data."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Failed to encode bar data."
    end

    return "QCT1:" .. encoded
end

-- Import a single tracker bar (appends to existing bars)
function QUICore:ImportSingleTrackerBar(str)
    if not self.db or not self.db.profile then
        return false, "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")

    -- Check for correct prefix
    if not str:match("^QCB1:") then
        return false, "This doesn't appear to be a tracker bar export."
    end
    str = str:gsub("^QCB1:", "")

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, data = AceSerializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" or not data.bar then
        return false, "Could not deserialize bar data."
    end

    local payloadValid, payloadErr = ValidateTrackerBarPayload(data, false)
    if not payloadValid then
        return false, payloadErr or "Import failed bar validation."
    end

    -- Ensure customTrackers structure exists
    if not self.db.profile.customTrackers then
        self.db.profile.customTrackers = { bars = {} }
    end
    if not self.db.profile.customTrackers.bars then
        self.db.profile.customTrackers.bars = {}
    end

    -- Generate collision-safe unique ID for the imported bar
    local oldID = data.bar.id
    local newID = GenerateUniqueTrackerID()
    local importedBar = CloneValue(data.bar)
    importedBar.id = newID

    -- Append bar to existing bars
    table.insert(self.db.profile.customTrackers.bars, importedBar)

    -- Copy spec-specific entries if present (with new ID)
    if data.specEntries then
        if not self.db.global then self.db.global = {} end
        if not self.db.global.specTrackerSpells then self.db.global.specTrackerSpells = {} end
        self.db.global.specTrackerSpells[newID] = data.specEntries
    end

    SyncCustomTrackerBarsToCDM(self, self.db.profile)

    return true, "Bar imported successfully."
end

-- Import all tracker bars (replaceExisting: true = replace all, false = merge/append)
function QUICore:ImportAllTrackerBars(str, replaceExisting)
    if not self.db or not self.db.profile then
        return false, "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")

    -- Check for correct prefix
    if not str:match("^QCT1:") then
        return false, "This doesn't appear to be a tracker bars export."
    end
    str = str:gsub("^QCT1:", "")

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, data = AceSerializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" or not data.bars then
        return false, "Could not deserialize bars data."
    end

    local payloadValid, payloadErr = ValidateTrackerBarPayload(data, true)
    if not payloadValid then
        return false, payloadErr or "Import failed bars validation."
    end

    -- Ensure customTrackers structure exists
    if not self.db.profile.customTrackers then
        self.db.profile.customTrackers = { bars = {} }
    end

    if replaceExisting then
        RemoveImportedCustomBarContainers(self, self.db.profile)

        -- Replace all bars
        self.db.profile.customTrackers.bars = CloneValue(data.bars)

        -- Replace spec entries (or clear if none provided)
        if not self.db.global then self.db.global = {} end
        self.db.global.specTrackerSpells = CloneValue(data.specEntries or {})
    else
        -- Merge: append bars with new IDs
        if not self.db.profile.customTrackers.bars then
            self.db.profile.customTrackers.bars = {}
        end

        local idMapping = {}  -- old ID -> new ID

        for _, bar in ipairs(data.bars) do
            local oldID = bar.id
            local newID = GenerateUniqueTrackerID()
            local clonedBar = CloneValue(bar)
            clonedBar.id = newID
            if oldID ~= nil then
                idMapping[oldID] = newID
            end
            table.insert(self.db.profile.customTrackers.bars, clonedBar)
        end

        -- Copy spec entries with new IDs
        if data.specEntries then
            if not self.db.global then self.db.global = {} end
            if not self.db.global.specTrackerSpells then self.db.global.specTrackerSpells = {} end

            for oldID, specData in pairs(data.specEntries) do
                local newID = idMapping[oldID]
                if newID then
                    self.db.global.specTrackerSpells[newID] = specData
                end
            end
        end
    end

    SyncCustomTrackerBarsToCDM(self, self.db.profile)

    return true, "CDM bars imported successfully."
end

---=================================================================================
--- SPELL SCANNER IMPORT/EXPORT
---=================================================================================

-- Export spell scanner learned data
function QUICore:ExportSpellScanner()
    if not self.db or not self.db.global or not self.db.global.spellScanner then
        return nil, "No spell scanner data to export."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local scannerData = self.db.global.spellScanner
    local spellCount = 0
    local itemCount = 0

    if scannerData.spells then
        for _ in pairs(scannerData.spells) do spellCount = spellCount + 1 end
    end
    if scannerData.items then
        for _ in pairs(scannerData.items) do itemCount = itemCount + 1 end
    end

    if spellCount == 0 and itemCount == 0 then
        return nil, "No learned spells or items to export."
    end

    local exportData = {
        spells = scannerData.spells,
        items = scannerData.items,
    }

    local serialized = AceSerializer:Serialize(exportData)
    if not serialized or type(serialized) ~= "string" then
        return nil, "Failed to serialize spell scanner data."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Failed to compress spell scanner data."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Failed to encode spell scanner data."
    end

    return "QSS1:" .. encoded
end

-- Import spell scanner data (replaceExisting: true = replace all, false = merge)
function QUICore:ImportSpellScanner(str, replaceExisting)
    if not self.db then
        return false, "No database loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")

    -- Check for correct prefix
    if not str:match("^QSS1:") then
        return false, "This doesn't appear to be spell scanner data."
    end
    str = str:gsub("^QSS1:", "")

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, data = AceSerializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" then
        return false, "Could not deserialize spell scanner data."
    end

    local payloadValid, payloadErr = ValidateSpellScannerPayload(data)
    if not payloadValid then
        return false, payloadErr or "Import failed spell scanner validation."
    end

    -- Ensure global structure exists
    if not self.db.global then self.db.global = {} end
    if not self.db.global.spellScanner then
        self.db.global.spellScanner = { spells = {}, items = {}, autoScan = false }
    end

    if replaceExisting then
        -- Replace all learned data
        self.db.global.spellScanner.spells = data.spells or {}
        self.db.global.spellScanner.items = data.items or {}
    else
        -- Merge: add new entries without overwriting existing
        if data.spells then
            for spellID, spellData in pairs(data.spells) do
                if not self.db.global.spellScanner.spells[spellID] then
                    self.db.global.spellScanner.spells[spellID] = spellData
                end
            end
        end
        if data.items then
            for itemID, itemData in pairs(data.items) do
                if not self.db.global.spellScanner.items[itemID] then
                    self.db.global.spellScanner.items[itemID] = itemData
                end
            end
        end
    end

    return true, "Spell scanner data imported successfully."
end
