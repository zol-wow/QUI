---------------------------------------------------------------------------
-- QUI Backwards Compatibility
-- Tier 0: StampOldDefaults (raw SV access, must run before AceDB defaults)
-- Tier 1: Delegates to ns.Migrations.Run() for all profile-level migrations
-- Also handles global/char structure housekeeping.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

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
        rawset(rawProfile, "_defaultsVersion", 2)
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
    -- Done — stamp version directly on the raw profile
    ---------------------------------------------------------------------------
    rawset(rawProfile, "_defaultsVersion", 2)
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
