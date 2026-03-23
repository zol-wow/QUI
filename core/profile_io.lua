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
            return false, { kind = "unsupported_key_type", keyType = keyType, path = label or "root" }
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

local function ValidateProfilePayload(core, profileData)
    local ok, issue = ValidateImportTree(profileData, "profile")
    if not ok then
        return false, FormatTreeValidationError(issue, "profile")
    end

    local defaults = core and core.db and core.db.defaults and core.db.defaults.profile
    if type(defaults) ~= "table" then
        return true
    end

    local typeErrors = {}
    ValidateTableTypeShape(profileData, defaults, "profile", typeErrors, 0)
    if #typeErrors > 0 then
        return false, FormatTypeMismatchErrors(typeErrors, "profile")
    end

    return true
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
}

local PROFILE_QOL_GENERAL_KEYS = {
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
    "gameMenuFontSize",
    "gameMenuDim",
    "skinPowerBarAlt",
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
    local bars = profileData
        and profileData.customTrackers
        and profileData.customTrackers.bars

    if type(bars) ~= "table" then
        return nil
    end

    local children = {}
    for index, bar in ipairs(bars) do
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
        topLevelKeys = { "addonAccentColor", "powerColors" },
        generalKeys = PROFILE_THEME_GENERAL_KEYS,
    },
    {
        id = "layout",
        label = "Layout / Positions",
        description = "Mover positions, HUD anchors, frame placement, and tracked element offsets.",
        recommended = false,
        topLevelKeys = { "frameAnchoring", "dandersFrames", "abilityTimeline" },
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
                description = "Shared group frame options, click-cast, and global toggles.",
                topLevelKeys = { "raidBuffs" },
                paths = {
                    "quiGroupFrames.enabled",
                    "quiGroupFrames.unifiedPosition",
                    "quiGroupFrames.selfFirst",
                    "quiGroupFrames.clickCast",
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
        topLevelKeys = { "actionBars" },
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
        topLevelKeys = { "minimap", "datatext", "quiDatatexts" },
        children = {
            {
                id = "minimapSubtab",
                label = "Minimap",
                description = "Minimap frame and minimap utility settings.",
                topLevelKeys = { "minimap" },
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
        label = "Custom Trackers",
        description = "Custom tracker bar settings and individual imported tracker bars.",
        recommended = true,
        topLevelKeys = { "customTrackersVisibility", "keybindOverridesEnabledTrackers" },
        paths = {
            "customTrackers.bars",
            "customTrackers.keybinds",
        },
        children = {
            {
                id = "customTrackersShared",
                label = "Shared Settings",
                description = "Tracker keybind display and shared visibility settings.",
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
            "combatText",
            "brzCounter",
            "combatTimer",
            "xpTracker",
            "totemBar",
        },
    },
    {
        id = "chat",
        label = "Chat",
        description = "Chat frame skinning, formatting, and utility options.",
        recommended = true,
        topLevelKeys = { "chat" },
    },
    {
        id = "qol",
        label = "QoL / Automation",
        description = "Automation helpers, popup blocker, consumables, and utility toggles.",
        recommended = true,
        topLevelKeys = { "uiHider" },
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

local function ImportSelectedCustomTrackerBars(targetProfile, importedProfile, barIndexes)
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
    for _, barIndex in ipairs(barIndexes) do
        local sourceBar = importedBars[barIndex]
        if type(sourceBar) == "table" then
            local clonedBar = CloneValue(sourceBar)
            if clonedBar.id then
                clonedBar.id = GenerateUniqueTrackerID()
            end
            table.insert(targetProfile.customTrackers.bars, clonedBar)
            importedAny = true
        end
    end

    return importedAny
end

local function DetectProfileImportPrefix(str)
    if type(str) ~= "string" then
        return nil
    end
    return str:match("^([A-Z][A-Z0-9]*%d):")
end

local function ParseProfileImportString(core, str)
    if not core or not core.db or not core.db.profile then
        return false, "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")
    if str == "" then
        return false, "No data provided."
    end

    local prefix = DetectProfileImportPrefix(str)
    if prefix then
        if not SUPPORTED_PROFILE_IMPORT_PREFIXES[prefix] then
            return false, ("This doesn't appear to be a QUI profile string (%s)."):format(prefix)
        end
        str = str:sub(#prefix + 2)
    else
        prefix = "QUI1"
    end

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, payload = AceSerializer:Deserialize(serialized)
    if not ok or type(payload) ~= "table" then
        return false, "Could not deserialize profile."
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

local function BuildProfileImportPreview(profileData, prefix)
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
        importType = "QUI Profile",
        prefix = prefix or "QUI1",
        categories = categories,
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

local function ApplyFullProfilePayload(core, importedProfile)
    local profile = core and core.db and core.db.profile
    if type(profile) ~= "table" or type(importedProfile) ~= "table" then
        return false, "No profile loaded."
    end

    for key in pairs(profile) do
        profile[key] = nil
    end
    for key, value in pairs(importedProfile) do
        profile[key] = CloneValue(value)
    end

    if core.RefreshAll then
        core:RefreshAll()
    end

    return true, "Profile imported successfully."
end

---=================================================================================
--- PROFILE IMPORT/EXPORT
---=================================================================================

function QUICore:ExportProfileToString()
    if not self.db or not self.db.profile then
        return "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local serialized = AceSerializer:Serialize(self.db.profile)
    if not serialized or type(serialized) ~= "string" then
        return "Failed to serialize profile."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return "Failed to compress profile."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return "Failed to encode profile."
    end

    return "QUI1:" .. encoded
end

function QUICore:GetProfileImportCategories()
    return BuildProfileImportPreview({}, "QUI1").categories or {}
end

function QUICore:AnalyzeProfileImportString(str)
    local ok, payloadOrErr, prefix = ParseProfileImportString(self, str)
    if not ok then
        return false, payloadOrErr
    end

    return true, BuildProfileImportPreview(payloadOrErr, prefix)
end

function QUICore:ImportProfileFromString(str)
    local ok, payloadOrErr = ParseProfileImportString(self, str)
    if not ok then
        return false, payloadOrErr
    end

    return ApplyFullProfilePayload(self, payloadOrErr)
end

function QUICore:ImportProfileSelectionFromString(str, selectedCategoryIDs)
    local ok, payloadOrErr = ParseProfileImportString(self, str)
    if not ok then
        return false, payloadOrErr
    end

    if type(selectedCategoryIDs) ~= "table" then
        return false, "Select at least one category to import."
    end

    local selectedLookup = {}
    local selectedLabels = {}
    local selectedSpecs = {}
    local selectedCustomTrackerBarIndexes = {}

    local function BuildSelectedLabel(category)
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

    for _, categoryID in ipairs(selectedCategoryIDs) do
        local category = PROFILE_IMPORT_CATEGORY_BY_ID[categoryID]
        if category and not selectedLookup[categoryID] then
            selectedLookup[categoryID] = true
            selectedLabels[#selectedLabels + 1] = BuildSelectedLabel(category)
            selectedSpecs[#selectedSpecs + 1] = category
        else
            local barIndex = ParseCustomTrackerBarSelectionID(categoryID)
            if barIndex and not selectedLookup[categoryID] then
                selectedLookup[categoryID] = true
                selectedCustomTrackerBarIndexes[#selectedCustomTrackerBarIndexes + 1] = barIndex

                local importedBars = payloadOrErr.customTrackers and payloadOrErr.customTrackers.bars
                local importedBar = type(importedBars) == "table" and importedBars[barIndex] or nil
                local barName = type(importedBar) == "table" and importedBar.name or ("Bar " .. barIndex)
                selectedLabels[#selectedLabels + 1] = ("Custom Trackers > %s"):format(tostring(barName))
            end
        end
    end

    if #selectedLabels == 0 then
        return false, "Select at least one category to import."
    end

    local profile = self.db and self.db.profile
    if type(profile) ~= "table" then
        return false, "No profile loaded."
    end

    local previousProfile = CloneValue(profile)

    for _, category in ipairs(selectedSpecs) do
        ApplyProfileImportCategory(profile, payloadOrErr, category)
    end

    if not selectedLookup.customTrackers and #selectedCustomTrackerBarIndexes > 0 then
        ImportSelectedCustomTrackerBars(profile, payloadOrErr, selectedCustomTrackerBarIndexes)
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

    if self.RefreshAll then
        self:RefreshAll()
    end

    return true, ("Imported %s."):format(table.concat(selectedLabels, ", "))
end

---=================================================================================
--- CUSTOM TRACKER BAR IMPORT/EXPORT
---=================================================================================

-- Generate a collision-safe unique tracker ID
GenerateUniqueTrackerID = function()
    local used = {}
    local bars = QUICore.db.profile.customTrackers and QUICore.db.profile.customTrackers.bars or {}
    for _, b in ipairs(bars) do
        if b.id then used[b.id] = true end
    end
    if QUICore.db.global and QUICore.db.global.specTrackerSpells then
        for id in pairs(QUICore.db.global.specTrackerSpells) do
            used[id] = true
        end
    end
    local id
    repeat
        id = "tracker" .. time() .. math.random(1000, 9999)
    until not used[id]
    return id
end

-- Export a single tracker bar (with its spec-specific entries if enabled)
function QUICore:ExportSingleTrackerBar(barIndex)
    if not self.db or not self.db.profile or not self.db.profile.customTrackers
        or not self.db.profile.customTrackers.bars then
        return nil, "No tracker data loaded."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local bar = self.db.profile.customTrackers.bars[barIndex]
    if not bar then
        return nil, "Bar not found."
    end

    -- Build export data including spec-specific entries if enabled
    local exportData = {
        bar = bar,
        specEntries = nil,
    }

    -- Include spec-specific entries if the bar uses them
    if bar.specSpecificSpells and bar.id and self.db.global and self.db.global.specTrackerSpells then
        exportData.specEntries = self.db.global.specTrackerSpells[bar.id]
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
    if not self.db or not self.db.profile or not self.db.profile.customTrackers then
        return nil, "No tracker data loaded."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local bars = self.db.profile.customTrackers.bars
    if not bars or #bars == 0 then
        return nil, "No tracker bars to export."
    end

    local exportData = {
        bars = bars,
        specEntries = self.db.global and self.db.global.specTrackerSpells or nil,
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
    data.bar.id = newID

    -- Append bar to existing bars
    table.insert(self.db.profile.customTrackers.bars, data.bar)

    -- Copy spec-specific entries if present (with new ID)
    if data.specEntries then
        if not self.db.global then self.db.global = {} end
        if not self.db.global.specTrackerSpells then self.db.global.specTrackerSpells = {} end
        self.db.global.specTrackerSpells[newID] = data.specEntries
    end

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
        -- Replace all bars
        self.db.profile.customTrackers.bars = data.bars

        -- Replace spec entries (or clear if none provided)
        if not self.db.global then self.db.global = {} end
        self.db.global.specTrackerSpells = data.specEntries or {}
    else
        -- Merge: append bars with new IDs
        if not self.db.profile.customTrackers.bars then
            self.db.profile.customTrackers.bars = {}
        end

        local idMapping = {}  -- old ID -> new ID

        for _, bar in ipairs(data.bars) do
            local oldID = bar.id
            local newID = GenerateUniqueTrackerID()
            bar.id = newID
            idMapping[oldID] = newID
            table.insert(self.db.profile.customTrackers.bars, bar)
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

    return true, "Tracker bars imported successfully."
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
