--- QUI Core
--- All branding changed to QUI

local ADDON_NAME, ns = ...
local QUI = QUI
local ADDON_NAME = "QUI"

-- Upvalue frequently-used globals (core/main.lua is ~3000 lines)
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local select = select
local wipe = wipe
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc

-- Create QUICore as an Ace3 module within QUI
local QUICore = QUI:NewModule("QUICore", "AceConsole-3.0", "AceEvent-3.0")
QUI.QUICore = QUICore

-- Expose QUICore to namespace for other files
ns.Addon = QUICore

-- Shared utility functions and secrets are in utils.lua (ns.Helpers, ns.Utils)

-- Global pending reload system
QUICore.__pendingReload = false
QUICore.__reloadEventFrame = nil

local function EnsureReloadEventFrame(self)
    if self.__reloadEventFrame then
        return self.__reloadEventFrame
    end

    self.__reloadEventFrame = CreateFrame("Frame")
    self.__reloadEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.__reloadEventFrame:SetScript("OnEvent", function(frame, event)
        if event == "PLAYER_REGEN_ENABLED" and QUICore.__pendingReload then
            QUICore.__pendingReload = false
            -- Show popup with reload button (user click = allowed)
            QUICore:ShowReloadPopup()
        end
    end)

    return self.__reloadEventFrame
end

function QUICore:RequestReload()
    if InCombatLockdown() and not (QUI.db and QUI.db.profile and QUI.db.profile.general and QUI.db.profile.general.allowReloadInCombat) then
        if not self.__pendingReload then
            self.__pendingReload = true
            print("|cFF30D1FFQUI:|r Reload queued - will execute when combat ends.")
            EnsureReloadEventFrame(self)
        end
        return
    end

    self:ShowReloadPopup()
end

-- Safe reload function - queues if in combat, reloads immediately if not
function QUICore:SafeReload()
    if InCombatLockdown() and not (QUI.db and QUI.db.profile and QUI.db.profile.general and QUI.db.profile.general.allowReloadInCombat) then
        if not self.__pendingReload then
            self.__pendingReload = true
            print("|cFF30D1FFQUI:|r Reload queued - will execute when combat ends.")
            EnsureReloadEventFrame(self)
        end
    else
        ReloadUI()
    end
end

-- Show reload popup after combat ends (user must click to reload)
function QUICore:ShowReloadPopup()
    -- Use QUI's existing confirmation dialog
    if QUI and QUI.GUI and QUI.GUI.ShowConfirmation then
        QUI.GUI:ShowConfirmation({
            title = "Reload Ready",
            message = "Combat ended. Click to reload the UI.",
            acceptText = "Reload Now",
            cancelText = "Later",
            onAccept = function() ReloadUI() end,
        })
    else
        -- Fallback: print message if GUI not available
        print("|cFF30D1FFQUI:|r Combat ended. Type /reload to reload.")
    end
end

-- Global safe reload function on QUI object
function QUI:SafeReload()
    if self.QUICore then
        self.QUICore:SafeReload()
    else
        -- Fallback if QUICore not loaded
        if InCombatLockdown() and not (self.db and self.db.profile and self.db.profile.general and self.db.profile.general.allowReloadInCombat) then
            print("|cFF30D1FFQUI:|r Cannot reload during combat.")
        else
            ReloadUI()
        end
    end
end

local LSM = ns.LSM
local LCG = LibStub("LibCustomGlow-1.0", true)

local LibDualSpec   = LibStub("LibDualSpec-1.0", true)

-- Texture registration handled in media.lua
-- Profile import/export functions are in core/profile_io.lua

---=================================================================================
--- HUD LAYERING UTILITY
---=================================================================================

-- Convert layer priority (0-10) to frame level
-- Base 100, step 20 = range 100-300
-- Higher priority = rendered on top of lower priority elements
function QUICore:GetHUDFrameLevel(priority)
    return 100 + (priority or 5) * 20
end

---=================================================================================
--- VIEWER LIST
---=================================================================================

local defaults = ns.defaults


function QUICore:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("QUIDB", defaults, true)
    QUI.db = self.db  -- Make database accessible to other QUI modules

    -- Migrate visibility settings to SHOW logic
    -- Old hideWhenX → new showX (semantic conversion)
    -- hideOutOfCombat=true → showInCombat=true (user wants combat-only)
    -- hideWhenNotInGroup=true → showInGroup=true (user wants group-only)
    -- hideWhenNotInInstance=true → showInInstance=true (user wants instance-only)
    -- hideWhenMounted has no equivalent (can't express "hide when mounted" in SHOW logic)
    local profile = self.db.profile

    -- Castbar preview is a transient options-state and should never persist
    -- across reload/login. Clear it early before frame modules initialize.
    if profile and profile.quiUnitFrames then
        for _, unitKey in ipairs({"player", "target", "focus", "pet", "targettarget"}) do
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

    -- Migrate skinUseClassColor → themePreset
    if profile.general and profile.general.skinUseClassColor and not profile.general.themePreset then
        profile.general.themePreset = "Class Colored"
    end

    -- One-time migration: enable work order (crafting order) minimap indicator
    -- for existing profiles. After this runs once, user preference is preserved.
    if profile then
        if not profile.minimap then
            profile.minimap = {}
        end
        if profile.minimap._showCraftingOrderMigrated ~= true then
            profile.minimap.showCraftingOrder = true
            profile.minimap._showCraftingOrderMigrated = true
        end
    end

    -- Helper to migrate a visibility table from HIDE to SHOW logic
    local function migrateToShowLogic(visTable)
        if not visTable then return end
        -- Convert hideOutOfCombat → showInCombat
        if visTable.hideOutOfCombat then
            visTable.showInCombat = true
        end
        -- Convert hideWhenNotInGroup → showInGroup
        if visTable.hideWhenNotInGroup then
            visTable.showInGroup = true
        end
        -- Convert hideWhenNotInInstance → showInInstance
        if visTable.hideWhenNotInInstance then
            visTable.showInInstance = true
        end
        -- Clean up old keys (hideWhenMounted is a new feature, not migrated)
        visTable.hideOutOfCombat = nil
        visTable.hideWhenNotInGroup = nil
        visTable.hideWhenNotInInstance = nil
    end

    -- Migrate recently-added hideWhenX keys to showX (if user reloaded after first implementation)
    migrateToShowLogic(profile.cdmVisibility)
    migrateToShowLogic(profile.unitframesVisibility)

    -- Migrate flat group frame visual settings → party/raid containers
    local gf = profile.quiGroupFrames
    if gf then
        if gf.selfFirst ~= nil then
            if gf.partySelfFirst == nil then
                gf.partySelfFirst = gf.selfFirst
            end
            if gf.raidSelfFirst == nil then
                gf.raidSelfFirst = gf.selfFirst
            end
            gf.selfFirst = nil
        end

        -- Keys that should live under party/raid containers
        local VISUAL_KEYS = {
            "general", "layout", "health", "power", "name", "absorbs", "healPrediction",
            "indicators", "healer", "classPower", "range", "auras",
            "privateAuras", "auraIndicators", "castbar", "portrait", "pets",
        }
        -- Also handle the previous partyLayout/raidLayout migration
        local needsMigration = false
        for _, key in ipairs(VISUAL_KEYS) do
            if gf[key] then needsMigration = true break end
        end
        if gf.partyLayout or gf.raidLayout then needsMigration = true end

        if needsMigration then
            if not gf.party then gf.party = {} end
            if not gf.raid then gf.raid = {} end

            -- Deep-copy helper for migration
            local function deepCopy(src)
                if type(src) ~= "table" then return src end
                local copy = {}
                for k, v in pairs(src) do copy[k] = deepCopy(v) end
                return copy
            end

            -- Copy each flat visual key into both party and raid
            for _, key in ipairs(VISUAL_KEYS) do
                if gf[key] then
                    if not gf.party[key] then gf.party[key] = deepCopy(gf[key]) end
                    if not gf.raid[key] then gf.raid[key] = deepCopy(gf[key]) end
                    gf[key] = nil
                end
            end

            -- Handle partyLayout/raidLayout from the intermediate migration
            if gf.partyLayout then
                if not gf.party.layout then gf.party.layout = gf.partyLayout
                else
                    for k, v in pairs(gf.partyLayout) do
                        if gf.party.layout[k] == nil then gf.party.layout[k] = v end
                    end
                end
                gf.partyLayout = nil
            end
            if gf.raidLayout then
                if not gf.raid.layout then gf.raid.layout = gf.raidLayout
                else
                    for k, v in pairs(gf.raidLayout) do
                        if gf.raid.layout[k] == nil then gf.raid.layout[k] = v end
                    end
                end
                gf.raidLayout = nil
            end
        end

        -- Migrate shared dimensions → party/raid containers
        if gf.dimensions then
            local function deepCopyDims(src)
                if type(src) ~= "table" then return src end
                local copy = {}
                for k, v in pairs(src) do copy[k] = deepCopyDims(v) end
                return copy
            end
            if not gf.party.dimensions then gf.party.dimensions = deepCopyDims(gf.dimensions) end
            if not gf.raid.dimensions then gf.raid.dimensions = deepCopyDims(gf.dimensions) end
            gf.dimensions = nil
        end

        -- Migrate shared spotlight → raid-only
        if gf.spotlight then
            if not gf.raid.spotlight then gf.raid.spotlight = gf.spotlight end
            gf.spotlight = nil
        end
    end

    -- Migrate unifiedPosition → always separate party/raid positions
    if gf and gf.unifiedPosition ~= nil then
        if gf.unifiedPosition and gf.position then
            -- User had unified mode: copy shared position to raidPosition
            if not gf.raidPosition then
                gf.raidPosition = { offsetX = gf.position.offsetX, offsetY = gf.position.offsetY }
            end
        end
        gf.unifiedPosition = nil
    end

    -- Migrate legacy group-frame aura indicator spell toggles into the new
    -- per-aura entries model while keeping the old table for backwards compat.
    if gf then
        local Helpers = ns.Helpers
        local normalizeAuraIndicators = Helpers and Helpers.NormalizeAuraIndicatorConfig
        if normalizeAuraIndicators then
            if gf.party and gf.party.auraIndicators then
                normalizeAuraIndicators(gf.party.auraIndicators)
            end
            if gf.raid and gf.raid.auraIndicators then
                normalizeAuraIndicators(gf.raid.auraIndicators)
            end
        end
    end

    -- Migrate tooltip engine: normalize legacy engine names to "default"
    if profile.tooltip and profile.tooltip.engine and profile.tooltip.engine ~= "default" then
        profile.tooltip.engine = "default"
    end

    -- Remove deprecated CDM engine setting (owned is always used now)
    if profile.ncdm and profile.ncdm.engine ~= nil then
        profile.ncdm.engine = nil
    end

    -- Migrate action bar engine: classic engine removed, force to "owned"
    if profile.actionBars and profile.actionBars.engine == "classic" then
        profile.actionBars.engine = "owned"
    end

    -- Force minimap scale to 1.0 (UI option removed; stale values may linger in saved profiles)
    if profile.minimap and profile.minimap.scale ~= nil and profile.minimap.scale ~= 1.0 then
        profile.minimap.scale = 1.0
    end

    -- Migrate minimap hideMicroMenu/hideBagBar → actionBars.bars.microbar/bags.enabled
    if profile.minimap then
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

    ---------------------------------------------------------------------------
    -- Anchoring unification migration: remove enabled field, migrate inline
    -- offsets to frameAnchoring as the single source of truth.
    ---------------------------------------------------------------------------
    if not profile._anchoringMigrationVersion then
        if not profile.frameAnchoring then
            profile.frameAnchoring = {}
        end
        local fa = profile.frameAnchoring

        -- 2a: Remove enabled field from existing entries
        for key, settings in pairs(fa) do
            if type(settings) == "table" and settings.enabled ~= nil then
                if settings.enabled == false then
                    -- User never configured this — delete the entry
                    fa[key] = nil
                else
                    -- Was enabled — remove the field (now implicit)
                    settings.enabled = nil
                end
            end
        end

        -- 2b: Migrate inline offsets → frameAnchoring (only if not already set)
        local function MigrateInlineOffsets(sourceTable, targetKey)
            if not sourceTable then return end
            local ox = sourceTable.offsetX
            local oy = sourceTable.offsetY
            if ox == nil and oy == nil then return end
            if fa[targetKey] then return end  -- Already has anchoring config
            fa[targetKey] = {
                parent = "screen",
                point = "CENTER",
                relative = "CENTER",
                offsetX = ox or 0,
                offsetY = oy or 0,
                sizeStable = true,
            }
        end

        -- Unit frames
        local uf = profile.quiUnitFrames
        if uf then
            MigrateInlineOffsets(uf.player, "playerFrame")
            MigrateInlineOffsets(uf.target, "targetFrame")
            MigrateInlineOffsets(uf.targettarget, "totFrame")
            MigrateInlineOffsets(uf.focus, "focusFrame")
            MigrateInlineOffsets(uf.pet, "petFrame")
            MigrateInlineOffsets(uf.boss, "bossFrames")
        end

        -- Action bar special buttons
        local bars = profile.actionBars and profile.actionBars.bars
        if bars then
            MigrateInlineOffsets(bars.extraActionButton, "extraActionButton")
            MigrateInlineOffsets(bars.zoneAbility, "zoneAbility")
        end

        -- Other modules
        MigrateInlineOffsets(profile.totemBar, "totemBar")
        MigrateInlineOffsets(profile.xpTracker, "xpTracker")
        MigrateInlineOffsets(profile.skyriding, "skyriding")
        MigrateInlineOffsets(profile.crosshair, "crosshair")

        -- Group frames
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

        -- 2c: Migrate castbar anchor modes → frameAnchoring
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
                    local parent, ox, oy
                    if anchor == "none" then
                        parent = "screen"
                        ox = castDB.freeOffsetX or castDB.offsetX or 0
                        oy = castDB.freeOffsetY or castDB.offsetY or 0
                    elseif anchor == "unitframe" then
                        parent = cm.parentFrameKey
                        ox = castDB.lockedOffsetX or castDB.offsetX or 0
                        oy = castDB.lockedOffsetY or castDB.offsetY or 0
                    elseif anchor == "essential" then
                        parent = "cdmEssential"
                        ox = castDB.lockedOffsetX or castDB.offsetX or 0
                        oy = castDB.lockedOffsetY or castDB.offsetY or 0
                    elseif anchor == "utility" then
                        parent = "cdmUtility"
                        ox = castDB.lockedOffsetX or castDB.offsetX or 0
                        oy = castDB.lockedOffsetY or castDB.offsetY or 0
                    else
                        parent = "screen"
                        ox = castDB.offsetX or 0
                        oy = castDB.offsetY or 0
                    end

                    local entry = {
                        parent = parent,
                        point = "CENTER",
                        relative = "CENTER",
                        offsetX = ox,
                        offsetY = oy,
                        sizeStable = true,
                    }
                    -- Migrate width adjustment
                    if castDB.widthAdjustment and castDB.widthAdjustment ~= 0 then
                        entry.widthAdjust = castDB.widthAdjustment
                    end
                    -- Auto-width when locked to a parent
                    if anchor ~= "none" then
                        entry.autoWidth = true
                    end
                    fa[cm.targetKey] = entry
                end
            end
        end

        -- 2d: Leave inline fields intact for backup (don't delete)

        profile._anchoringMigrationVersion = 1
    end

    -- Migration v2: module-specific position formats → frameAnchoring
    if (profile._anchoringMigrationVersion or 0) < 2 then
        if not profile.frameAnchoring then profile.frameAnchoring = {} end
        local fa = profile.frameAnchoring

        -- M+ Timer: position = { point, relPoint, x, y }
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

        -- Tooltip: anchorPosition = { point, relPoint, x, y }
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

        -- Modules using offsetX/offsetY not covered in v1
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

    -- Migration v3: remaining module position formats → frameAnchoring
    if (profile._anchoringMigrationVersion or 0) < 3 then
        if not profile.frameAnchoring then profile.frameAnchoring = {} end
        local fa = profile.frameAnchoring

        -- Helper: migrate { point, relPoint/relativePoint, x, y } → frameAnchoring entry
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

        -- ReadyCheck: general.readyCheckPosition
        local gen = profile.general
        if gen then
            MigratePos(gen.readyCheckPosition, "readyCheck",
                { point = "CENTER", relative = "CENTER", offsetX = 0, offsetY = -10 })
        end

        -- Power Bar Alt: profile.powerBarAltPosition (top-level in profile)
        MigratePos(profile.powerBarAltPosition, "powerBarAlt",
            { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -100 })

        -- Loot frame: profile.loot.position
        local lootDB = profile.loot
        if lootDB then
            MigratePos(lootDB.position, "lootFrame",
                { point = "CENTER", relative = "CENTER", offsetX = 0, offsetY = 100 })
        end

        -- Loot roll anchor: profile.lootRoll.position
        local rollDB = profile.lootRoll
        if rollDB then
            MigratePos(rollDB.position, "lootRollAnchor",
                { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -200 })
        end

        -- Consumable Check: general.consumableFreePosition
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

        -- Alert holders: profile.alerts.*Position
        local alertDB = profile.alerts
        if alertDB then
            MigratePos(alertDB.alertPosition, "alertAnchor",
                { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -20 })
            MigratePos(alertDB.toastPosition, "toastAnchor",
                { point = "TOP", relative = "TOP", offsetX = 0, offsetY = -150 })
            MigratePos(alertDB.bnetToastPosition, "bnetToastAnchor",
                { point = "TOPRIGHT", relative = "TOPRIGHT", offsetX = -200, offsetY = -80 })
        end

        -- Action bars: actionBars.bars[barKey].ownedPosition
        local barsDB = profile.actionBars and profile.actionBars.bars
        if barsDB then
            -- Layout mode keys differ from DB keys for some bars
            local barKeyMap = {
                pet = "petBar", stance = "stanceBar",
                microbar = "microMenu", bags = "bagBar",
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

    -- Phase G CDM Overhaul: Migrate top-level ncdm container keys into
    -- unified ncdm.containers table.  Existing data is copied (not moved)
    -- so the old paths stay for backward compatibility during the transition.
    if profile.ncdm and not profile.ncdm._containersMigrated then
        if not profile.ncdm.containers then
            profile.ncdm.containers = {}
        end
        local CONTAINER_NAMES = {
            essential  = "Essential",
            utility    = "Utility",
            buff       = "Buff Icons",
            trackedBar = "Buff Bars",
        }
        local CONTAINER_TYPES = {
            essential  = "cooldown",
            utility    = "cooldown",
            buff       = "aura",
            trackedBar = "auraBar",
        }
        for _, key in ipairs({"essential", "utility", "buff", "trackedBar"}) do
            if profile.ncdm[key] then
                -- Force-overwrite the AceDB-populated defaults with real user data
                profile.ncdm.containers[key] = CopyTable(profile.ncdm[key])
                profile.ncdm.containers[key].builtIn = true
                profile.ncdm.containers[key].containerType = CONTAINER_TYPES[key]
                profile.ncdm.containers[key].name = CONTAINER_NAMES[key]
            end
        end
        profile.ncdm._containersMigrated = true
    end

    -- Initialize preserved scale - will be properly set in OnEnable after UI scale is applied
    self._preservedUIScale = nil

    -- Track spec for detecting false PLAYER_SPECIALIZATION_CHANGED events during M+ entry
    self._lastKnownSpec = GetSpecialization() or 0

    -- Track current profile to detect same-profile "switches" during M+ entry
    self._lastKnownProfile = self.db:GetCurrentProfile()

    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")

    -- Enhance database with LibDualSpec if available
    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(self.db, ADDON_NAME)
    end


    -- Note: Main /qui command is handled by init.lua
    -- (quicorerefresh slash command removed — classic viewer skinning deleted)

    -- Defer minimap button creation to reduce load-time CPU
    C_Timer.After(0.1, function()
        self:CreateMinimapButton()
    end)

    -- Apply theme accent color to GUI.Colors early so modules outside the
    -- options panel (layout mode, skinning, etc.) see the correct color.
    local GUI = QUI.GUI
    if GUI and GUI.ApplyAccentColor and GUI.ResolveThemePreset then
        local general = profile and profile.general
        local preset = general and general.themePreset
        if preset then
            local r, g, b = GUI:ResolveThemePreset(preset)
            GUI:ApplyAccentColor(r, g, b)
        elseif general and general.addonAccentColor then
            local ac = general.addonAccentColor
            if ac[1] and ac[2] and ac[3] then
                GUI:ApplyAccentColor(ac[1], ac[2], ac[3])
            end
        end
    end

	self._didInitialize = true
	for _, callback in ipairs(self._postInitializeCallbacks or {}) do
		local ok, err = pcall(callback, self)
		if not ok and geterrorhandler then
			geterrorhandler()(err)
		end
	end

end

function QUICore:OnProfileChanged(event, db, profileKey)

    -- AGGRESSIVE M+ PROTECTION: If we're in a challenge mode dungeon, defer EVERYTHING
    -- WoW's protected state during M+ transitions can't be reliably detected by InCombatLockdown()
    -- and pcall doesn't suppress ADDON_ACTION_BLOCKED (fires before Lua error propagates)
    -- Check multiple conditions: active M+ OR in an M+ dungeon (covers keystone activation phase)
    local inChallengeMode = false
    if C_ChallengeMode then
        -- IsChallengeModeActive = timer is running
        -- GetActiveChallengeMapID returns non-nil if in an M+ dungeon (even before timer starts)
        inChallengeMode = (C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive())
            or (C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID() ~= nil)
    end
    if inChallengeMode then return end

    -- Skip if "switching" to the same profile (happens during M+ entry false events)
    -- LibDualSpec triggers profile switch even when already on correct profile
    local currentProfile = self.db:GetCurrentProfile()
    if profileKey == self._lastKnownProfile and profileKey == currentProfile then
        return  -- No actual change happening - skip all UI modifications
    end
    self._lastKnownProfile = profileKey

    -- Update spec tracking (kept for reference)
    self._lastKnownSpec = GetSpecialization() or 0

    -- Wipe the font registry so stale FontStrings from the old profile's frames
    -- are released. Modules will re-register via ApplyFont when they rebuild.
    if self.CleanupFontRegistry then
        self:CleanupFontRegistry()
    end

    -- Helper to apply UIParent scale safely (defers if in combat or protected state)
    -- pcall wraps SetScale because M+ keystone activation can enter a protected
    -- state while InCombatLockdown() still returns false.
    local function DeferUIScale(scale)
        QUICore._pendingUIScale = scale
        if not QUICore._scaleRegenFrame then
            QUICore._scaleRegenFrame = CreateFrame("Frame")
            QUICore._scaleRegenFrame:SetScript("OnEvent", function(self)
                if QUICore._pendingUIScale and not InCombatLockdown() then
                    local ok = pcall(UIParent.SetScale, UIParent, QUICore._pendingUIScale)
                    if ok then
                        QUICore._pendingUIScale = nil
                        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    end
                end
            end)
        end
        QUICore._scaleRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        QUICore._scaleRegenFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    local function ApplyUIScale(scale)
        if InCombatLockdown() then
            DeferUIScale(scale)
        else
            local ok = pcall(UIParent.SetScale, UIParent, scale)
            if not ok then
                DeferUIScale(scale)
            end
        end
    end

    -- Handle UI scale on profile change
    if self.db.profile.general then
        local newProfileScale = self.db.profile.general.uiScale

        if not newProfileScale or newProfileScale == 0 then
            -- New/reset profile has no scale - use the preserved one
            local scaleToUse = self._preservedUIScale

            -- If no preserved scale, use smart default based on resolution
            if not scaleToUse then
                if self.GetSmartDefaultScale then
                    scaleToUse = self:GetSmartDefaultScale()
                else
                    -- Inline fallback
                    local _, screenHeight = GetPhysicalScreenSize()
                    if screenHeight >= 2160 then
                        scaleToUse = 0.53
                    elseif screenHeight >= 1440 then
                        scaleToUse = 0.64
                    else
                        scaleToUse = 1.0
                    end
                end
            end

            self.db.profile.general.uiScale = scaleToUse
            ApplyUIScale(scaleToUse)
        else
            -- Scale change invalidates all stored frame offsets — force reload
            local currentScale = UIParent:GetScale()
            if currentScale and math.abs(newProfileScale - currentScale) > 0.001 then
                self._preservedUIScale = newProfileScale
                C_Timer.After(0, function()
                    QUICore:RequestReload()
                end)
                return
            end
            -- Existing profile has a saved scale - apply it
            ApplyUIScale(newProfileScale)
            -- Only update preserved scale when switching to a profile with a valid saved scale
            self._preservedUIScale = newProfileScale
        end

        -- Update pixel perfect calculations (skip if deferred to combat end)
        if not InCombatLockdown() and self.UIMult then
            self:UIMult()
        end
    end
    
    -- Handle Panel Scale and Alpha preservation
    -- Always restore the preserved panel settings on profile change (new, reset, or switch)
    -- This keeps the panel consistent across all profile operations
    if self._preservedPanelScale then
        self.db.profile.configPanelScale = self._preservedPanelScale
    end
    if self._preservedPanelAlpha then
        self.db.profile.configPanelAlpha = self._preservedPanelAlpha
    end


    -- Invalidate options panel — cached widgets hold stale profile table references
    if QUI.GUI and QUI.GUI.MainFrame then
        pcall(QUI.GUI.MainFrame.Hide, QUI.GUI.MainFrame)
        pcall(QUI.GUI.MainFrame.SetParent, QUI.GUI.MainFrame, nil)
        QUI.GUI.MainFrame = nil
        QUI.GUI._searchIndexBuilt = false
        QUI.GUI._allTabsAdded = false
        QUI.GUI.SettingsRegistry = {}
        QUI.GUI.SettingsRegistryKeys = {}
    end

    if self.RefreshAll then
        local ok, err = pcall(self.RefreshAll, self)
        if not ok then
            print("|cFFFF6666QUI:|r RefreshAll error: " .. tostring(err))
        end
    end
    
    -- Refresh Minimap module on profile change
    if QUICore.Minimap then
        -- Small delay to ensure profile data is fully loaded
        C_Timer.After(0.1, function()
            if QUICore.Minimap.Refresh then
                QUICore.Minimap:Refresh()
            end
        end)
    end
    
    -- Reset castbar previewMode flags before refreshing unit frames.
    -- previewMode is a transient UI state (options panel toggle) that should not
    -- persist across profile changes, but it lives in the DB and gets copied along.
    if self.db.profile.quiUnitFrames then
        for _, unitKey in ipairs({"player", "target", "focus", "pet", "targettarget"}) do
            local unitDB = self.db.profile.quiUnitFrames[unitKey]
            if unitDB and unitDB.castbar then
                unitDB.castbar.previewMode = false
            end
        end
        -- Also clear boss castbar previews
        for i = 1, 8 do
            local bossDB = self.db.profile.quiUnitFrames["boss" .. i]
            if bossDB and bossDB.castbar then
                bossDB.castbar.previewMode = false
            end
        end
    end

    -- Refresh Spec Profiles tab if options panel is open (immediate, no delay needed)
    if _G.QUI_RefreshSpecProfilesTab then
        _G.QUI_RefreshSpecProfilesTab()
    end

    -- Module refreshes via registry: 0.2s delay for gameplay modules,
    -- 0.5s for skinning (avoids stacking too much work at once).
    -- Priority ordering within the registry ensures correct refresh sequence
    -- (cooldowns → frames → qol → combat → trackers → anchoring).
    C_Timer.After(0.2, function()
        if ns.Registry then
            -- Refresh all non-skinning modules in priority order
            for _, group in ipairs({"cooldowns", "frames", "castbars", "qol", "combat", "trackers", "data", "chat", "character", "utility", "ui", "anchoring"}) do
                ns.Registry:RefreshAll(group)
            end
        end
        self:ShowProfileChangeNotification()
    end)

    -- Skinning refreshes: slightly later to avoid stacking too much work at 0.2s
    C_Timer.After(0.5, function()
        if ns.Registry then
            ns.Registry:RefreshAll("skinning")
        end
        SafeCall(_G.QUI_RefreshStatusTrackingBarSkin)
    end)

    -- Safety re-position pass: Blizzard's Edit Mode system re-applies per-spec
    -- layouts on spec change (EDIT_MODE_LAYOUTS_UPDATED), which can override
    -- QUI's frame positions set at 0.2s. Re-apply both anchoring overrides AND
    -- unit frame positions to catch any Blizzard layout passes that fired late.
    C_Timer.After(1.0, function()
        if not InCombatLockdown() then
            local ApplyAnchors = _G.QUI_ApplyAllFrameAnchors
            if ApplyAnchors then pcall(ApplyAnchors, true) end
            local RefreshUnitFrames = _G.QUI_RefreshUnitFrames
            if RefreshUnitFrames then pcall(RefreshUnitFrames) end
            local RefreshGroupFrames = _G.QUI_RefreshGroupFrames
            if RefreshGroupFrames then pcall(RefreshGroupFrames) end
        end
    end)
end

function QUICore:ShowProfileChangeNotification()
    -- Simple chat notification instead of a popup that forces Edit Mode entry.
    -- The popup was causing an ApplyAllFrameAnchors feedback loop by entering
    -- Edit Mode during the profile transition.
    local profileName = self.db and self.db:GetCurrentProfile() or "Unknown"
    print(format("|cff60A5FAQUI:|r Profile switched to |cFFFFD700%s|r. Use |cFFFFD700/editmode|r to adjust frame positions.", profileName))
end

-- ============================================================================
-- UNLOCK MODE / EDIT MODE CALLBACK REGISTRY
-- Modules call RegisterEditModeEnter/Exit to register callbacks.
-- These now forward to QUI_LayoutMode (layoutmode.lua) and fire when
-- Layout Mode opens/closes rather than Blizzard Edit Mode.
-- ============================================================================

QUICore._editModeEnterCallbacks = {}
QUICore._editModeExitCallbacks = {}
QUICore._postInitializeCallbacks = QUICore._postInitializeCallbacks or {}
QUICore._postEnableCallbacks = QUICore._postEnableCallbacks or {}

function QUICore:RegisterEditModeEnter(callback)
    -- Forward to Layout Mode if available, otherwise queue for later bridging
    local um = ns.QUI_LayoutMode
    if um then
        um:RegisterEnterCallback(callback)
    else
        table.insert(self._editModeEnterCallbacks, callback)
    end
end

function QUICore:RegisterEditModeExit(callback)
    local um = ns.QUI_LayoutMode
    if um then
        um:RegisterExitCallback(callback)
    else
        table.insert(self._editModeExitCallbacks, callback)
    end
end

function QUICore:RegisterPostInitialize(callback)
    if type(callback) ~= "function" then
        return
    end
    if self._didInitialize then
        local ok, err = pcall(callback, self)
        if not ok and geterrorhandler then
            geterrorhandler()(err)
        end
        return
    end
    table.insert(self._postInitializeCallbacks, callback)
end

function QUICore:RegisterLayoutModeEnter(callback)
    local um = ns.QUI_LayoutMode
    if um then
        um:RegisterEnterCallback(callback)
    else
        table.insert(self._editModeEnterCallbacks, callback)
    end
end

function QUICore:RegisterLayoutModeExit(callback)
    local um = ns.QUI_LayoutMode
    if um then
        um:RegisterExitCallback(callback)
    else
        table.insert(self._editModeExitCallbacks, callback)
    end
end

function QUICore:RegisterPostEnable(callback)
    if type(callback) == "function" then
        table.insert(self._postEnableCallbacks, callback)
    end
end

-- ============================================================================

function QUICore:OnEnable()
    -- Override Blizzard's /reload command to use SafeReload
    -- (Must happen in OnEnable, after Blizzard's slash commands are registered)
    SlashCmdList["RELOAD"] = function()
        QUI:SafeReload()
    end

    -- IMMEDIATE (<1ms): Critical sync-only work
    if self.InitializePixelPerfect then
        self:InitializePixelPerfect()
    end

    -- OnEnable runs synchronously inside the ADDON_LOADED handler — protected
    -- calls are allowed even during combat reloads. Set a namespace flag so
    -- subsystems (e.g. frame anchoring) can bypass their combat guards.
    ns._inInitSafeWindow = true

    -- Apply UI scale (uses pixel perfect system if available)
    if self.ApplyUIScale then
        self:ApplyUIScale()
    elseif self.db.profile.general then
        -- Fallback if pixel perfect not loaded
        local savedScale = self.db.profile.general.uiScale
        local scaleToApply
        if savedScale and savedScale > 0 then
            scaleToApply = savedScale
        else
            -- Smart default based on resolution
            local _, screenHeight = GetPhysicalScreenSize()
            if screenHeight >= 2160 then      -- 4K
                scaleToApply = 0.53
            elseif screenHeight >= 1440 then  -- 1440p
                scaleToApply = 0.64
            else                              -- 1080p or lower
                scaleToApply = 1.0
            end
            self.db.profile.general.uiScale = scaleToApply
        end
        UIParent:SetScale(scaleToApply)
    end

    -- Capture preserved UI scale (after it's been properly applied)
    self._preservedUIScale = UIParent:GetScale()
    self._preservedPanelScale = self.db.profile.configPanelScale
    self._preservedPanelAlpha = self.db.profile.configPanelAlpha

    -- Helper: apply frame anchoring overrides — marks frames in the gatekeeper set
    -- and positions them. Called after each init stage to catch newly created frames.
    local function ApplyFrameOverrides()
        if ns.QUI_Anchoring then
            ns.QUI_Anchoring:ApplyAllFrameAnchors()
        end
    end

    -- IMMEDIATE: Apply frame anchoring synchronously during ADDON_LOADED
    -- safe window. Protected calls work here even during combat reloads.
    ApplyFrameOverrides()

    -- Close the safe window — all subsequent C_Timer callbacks run outside
    -- the ADDON_LOADED handler and cannot make protected calls in combat.
    ns._inInitSafeWindow = false

    -- DEFERRED 0.1s: Hook setup (spreads work across frames)
    -- Combat-safe: uses hooksecurefunc + CreateFrame only. Must always run so
    -- the PLAYER_REGEN_ENABLED recovery handler inside HookEditMode is created
    -- even after a combat reload.
    C_Timer.After(0.1, function()
        self:HookEditMode()
    end)

    -- DEFERRED 0.5s: Unit frames (secure APIs now safe) + global font override + alerts
    C_Timer.After(0.5, function()
        if self.UnitFrames and self.db.profile.unitFrames and self.db.profile.unitFrames.enabled then
            self.UnitFrames:Initialize()
        end
        -- Initialize alert/toast skinning
        if self.Alerts and self.db.profile.general and self.db.profile.general.skinAlerts then
            self.Alerts:Initialize()
        end
        -- Apply global font to Blizzard UI elements
        if self.ApplyGlobalFont then
            self:ApplyGlobalFont()
        end
        -- Mark newly created frames + position overrides. Non-protected frames
        -- positioned immediately; protected frames deferred to PLAYER_REGEN_ENABLED
        -- via pendingAnchoredFrameUpdateAfterCombat in the anchoring system.
        ApplyFrameOverrides()
    end)

    -- DEFERRED 1.0s: UI hider + buff borders
    C_Timer.After(1.0, function()
        -- Cache _G function lookups at point of use
        local RefreshUIHider = _G.QUI_RefreshUIHider
        local RefreshBuffBorders = _G.QUI_RefreshBuffBorders
        if RefreshUIHider then
            RefreshUIHider()
        end
        if RefreshBuffBorders then
            RefreshBuffBorders()
        end
        ApplyFrameOverrides()
    end)

    -- DEFERRED 2.0s: Safety retry for late-loading frames
    C_Timer.After(2.0, function()
        ApplyFrameOverrides()
    end)

    -- DEFERRED 3.0s: Register all frames as anchor targets + final override apply
    C_Timer.After(3.0, function()
        if ns.QUI_Anchoring then
            ns.QUI_Anchoring:RegisterAllFrameTargets()
        end
        ApplyFrameOverrides()
    end)

    self:SetupEncounterWarningsSecretValuePatch()
end

function QUICore:OpenConfig()
    -- Open the new custom GUI instead of AceConfig
    if QUI and QUI.GUI then
        QUI.GUI:Toggle()
    end
end

function QUICore:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    
    if not LDB or not LibDBIcon then
        return
    end
    
    -- Initialize minimap button database (separate from minimap module settings)
    if not self.db.profile.minimapButton then
        self.db.profile.minimapButton = {
            hide = false,
        }
    end
    
    -- Create DataBroker object
    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        icon = "Interface\\AddOns\\QUI\\assets\\QUI.tga",
        label = "QUI",
        OnClick = function(clickedframe, button)
            if button == "LeftButton" then
                self:OpenConfig()
            elseif button == "RightButton" then
                if _G.QUI_ToggleLayoutMode then
                    _G.QUI_ToggleLayoutMode()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText("|cFF30D1FFQUI|r")
            tooltip:AddLine("Left-click to open configuration", 1, 1, 1)
            tooltip:AddLine("Right-click to toggle Edit Mode", 1, 1, 1)
        end,
    })
    
    -- Register with LibDBIcon using separate minimapButton settings
    LibDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimapButton)
end

-- Hook Edit Mode to suppress Blizzard selection overlays on QUI-managed frames
function QUICore:HookEditMode()
    if self.__editModeHooked then return end
    self.__editModeHooked = true
    
    -- Hook EditModeManagerFrame if it exists
    if EditModeManagerFrame then
        -- Track whether we've already hooked BossTargetFrameContainer.GetScaledSelectionSides
        local _bossContainerScaledSidesHooked = false

        -- Blizzard Edit Mode movers to suppress for frames QUI replaces.
        -- Hook HighlightSystem/SelectSystem on each so the blue selection overlay never appears.
        local _editModeSuppressionInstalled = false
        local _editModeSuppressedFrameNames = {
            -- Unit frames
            "PlayerFrame", "PetFrame", "PartyFrame",
            "BossTargetFrameContainer",
            -- Aura frames
            "BuffFrame", "DebuffFrame",
            -- Action bars
            "StanceBar", "MicroMenuContainer", "BagsBar",
            "PetActionBar", "ExtraAbilityContainer",
            -- Cooldown viewers
            "EssentialCooldownViewer", "UtilityCooldownViewer",
            "BuffIconCooldownViewer", "BuffBarCooldownViewer",
            -- Objective tracker
            "ObjectiveTrackerFrame",
            -- Cast bar
            "PlayerCastingBarFrame",
            -- Tooltip
            "GameTooltipDefaultContainer",
            -- Chat
            "ChatFrame1",
        }

        local function InstallEditModeSuppression()
            if _editModeSuppressionInstalled then return end
            _editModeSuppressionInstalled = true
            for _, name in ipairs(_editModeSuppressedFrameNames) do
                local frame = _G[name]
                if frame and frame.HighlightSystem then
                    hooksecurefunc(frame, "HighlightSystem", function(f)
                        if f.ClearHighlight then f:ClearHighlight() end
                    end)
                    if frame.SelectSystem then
                        hooksecurefunc(frame, "SelectSystem", function(f)
                            if f.ClearHighlight then f:ClearHighlight() end
                        end)
                    end
                end
            end
        end

        -- Install on PLAYER_ENTERING_WORLD (all frames exist by then)
        local suppressFrame = CreateFrame("Frame")
        suppressFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        suppressFrame:SetScript("OnEvent", function(f)
            f:UnregisterAllEvents()
            InstallEditModeSuppression()
        end)

        -- Hook when Edit Mode is entered (minimal — no callback dispatch)
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
            -- Ensure hooks are installed (fallback if PEW hasn't fired yet)
            InstallEditModeSuppression()
            -- Deferred force-clear: Blizzard's ShowSystemSelections iterates frames
            -- via secureexecuterange after EnterEditMode, so clear on next frame
            C_Timer.After(0, function()
                for _, name in ipairs(_editModeSuppressedFrameNames) do
                    local frame = _G[name]
                    if frame and frame.ClearHighlight then
                        pcall(frame.ClearHighlight, frame)
                    end
                end
            end)

            -- TAINT NOTE: Direct method replacement on secure frame. Required to prevent nil crash
            -- when GetRect() returns nil during Edit Mode. Edit Mode is combat-exclusive, so this
            -- taint cannot propagate to secure combat execution paths.
            if not InCombatLockdown() and BossTargetFrameContainer and not _bossContainerScaledSidesHooked then
                if BossTargetFrameContainer.GetScaledSelectionSides then
                    local original = BossTargetFrameContainer.GetScaledSelectionSides
                    BossTargetFrameContainer.GetScaledSelectionSides = function(frame)
                        local left = frame:GetLeft()
                        if left == nil then
                            -- Return off-screen fallback sides (left, right, bottom, top)
                            return -10000, -9999, 10000, 10001
                        end
                        return original(frame)
                    end
                    _bossContainerScaledSidesHooked = true
                end
            end
        end)
        
        -- Hook when Edit Mode is exited (minimal — no callback dispatch)
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            -- Hide power bar edit overlays that persist after edit mode exits
            C_Timer.After(0.15, function()
                for _, barName in ipairs({"QUIPrimaryPowerBar", "QUISecondaryPowerBar"}) do
                    local bar = _G[barName]
                    if bar and bar.editOverlay and bar.editOverlay:IsShown() then
                        bar.editOverlay:Hide()
                    end
                end
            end)
        end)
    end
            
    -- Hook combat end to reapply frame anchoring overrides deferred during combat
    local combatEndFrame = CreateFrame("Frame")
    combatEndFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatEndFrame:SetScript("OnEvent", function(frame, event)
        if event == "PLAYER_REGEN_ENABLED" then
            C_Timer.After(0.3, function()
                local ApplyAllFrameAnchors = _G.QUI_ApplyAllFrameAnchors
                if ApplyAllFrameAnchors then
                    ApplyAllFrameAnchors()
                end
            end)
        end
    end)
end

-- Patch Blizzard EncounterWarnings to avoid secret value compare errors in Edit Mode
function QUICore:SetupEncounterWarningsSecretValuePatch()
    if self.__encounterWarningsPatchSetup then return end
    self.__encounterWarningsPatchSetup = true

    local function TryPatch()
        if self.__encounterWarningsPatched then return true end
        if not EncounterWarningsTextElementMixin
            or type(EncounterWarningsTextElementMixin.Init) ~= "function"
            or not EncounterWarningsViewElementMixin
            or not EncounterWarningsUtil then
            return false
        end

        local originalInit = EncounterWarningsTextElementMixin.Init
        EncounterWarningsTextElementMixin.Init = function(textElement, encounterWarningInfo, parentView)
            local ok, err = pcall(originalInit, textElement, encounterWarningInfo, parentView)
            if ok then
                return
            end

            if type(err) == "string" and err:find("secret value") then
                pcall(EncounterWarningsViewElementMixin.Init, textElement, encounterWarningInfo, parentView)

                local maximumTextSize = EncounterWarningsUtil.GetMaximumTextSizeForSeverity(encounterWarningInfo.severity)
                if type(maximumTextSize) ~= "table" then
                    maximumTextSize = { width = 0, height = 0 }
                end
                local textFontObject = EncounterWarningsUtil.GetFontObjectForSeverity(encounterWarningInfo.severity)
                local textColor = EncounterWarningsUtil.GetTextColorForSeverity(encounterWarningInfo.severity)

                if textFontObject then
                    textElement:SetFontObject(textFontObject)
                end
                if textColor and textColor.GetRGB then
                    textElement:SetTextColor(textColor:GetRGB())
                end
                textElement:SetTextScale(1)

                local setOk = pcall(textElement.SetTextToFit, textElement, encounterWarningInfo.text)
                if not setOk then
                    pcall(textElement.SetText, textElement, "")
                end

                local maxHeight = maximumTextSize.height or 0
                local maxWidth = maximumTextSize.width or 0
                textElement:SetHeight(maxHeight)

                local widthOk, tooWide = pcall(function()
                    return textElement:GetStringWidth() > maxWidth
                end)
                if widthOk and tooWide then
                    textElement:SetWidth(maxWidth)
                    pcall(textElement.ScaleTextToFit, textElement)
                end
                return
            end

            error(err, 0)
        end

        -- NOTE: The EncounterWarnings instance is NOT wrapped here.
        -- Replacing ew.SetIsEditing with addon code causes the original to run
        -- in a tainted execution context, tainting every value it sets on view
        -- elements. RefreshEncounterEvents then reads those tainted values via
        -- secureexecuterange, generating 3x LUA_WARNING on every Edit Mode enter.
        -- The mixin Init patch above handles secret-value errors for new element
        -- instances; pre-existing XML instances are left to Blizzard's own error
        -- handling (non-fatal).

        self.__encounterWarningsPatched = true
        return true
    end

    local patched = TryPatch()

    for _, callback in ipairs(self._postEnableCallbacks or {}) do
        local ok, err = pcall(callback, self)
        if not ok and geterrorhandler then
            geterrorhandler()(err)
        end
    end

    if patched then
        return
    end

    local patchFrame = CreateFrame("Frame")
    patchFrame:RegisterEvent("ADDON_LOADED")
    patchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    patchFrame:SetScript("OnEvent", function(_, event, addonName)
        if event == "ADDON_LOADED" and addonName == "Blizzard_EncounterWarnings" then
            if TryPatch() then
                patchFrame:UnregisterAllEvents()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            patchFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            if not self.__encounterWarningsPatched then
                TryPatch()
            end
            if self.__encounterWarningsPatched then
                patchFrame:UnregisterAllEvents()
            end
        end
    end)

    self.__encounterWarningsPatchFrame = patchFrame
end

function QUI:GetAddonAccentColor()
    local db = QUI.db and QUI.db.profile
    if not db then
        return 0.376, 0.647, 0.980, 1  -- Fallback to sky blue
    end
    -- Resolve via theme preset if available
    local preset = db.general and db.general.themePreset
    if preset and QUI.GUI and QUI.GUI.ResolveThemePreset then
        local r, g, b = QUI.GUI:ResolveThemePreset(preset)
        return r, g, b, 1
    end
    local c = (db.general and db.general.addonAccentColor)
        or db.addonAccentColor
        or {0.376, 0.647, 0.980, 1}
    return c[1], c[2], c[3], c[4] or 1
end

function QUI:GetSkinColor()
    local db = QUI.db and QUI.db.profile
    if not db then
        return 0.376, 0.647, 0.980, 1  -- Fallback to sky blue
    end

    -- Resolve via theme preset if available
    local preset = db.general and db.general.themePreset
    if preset and QUI.GUI and QUI.GUI.ResolveThemePreset then
        local r, g, b = QUI.GUI:ResolveThemePreset(preset)
        return r, g, b, 1
    end

    -- Legacy fallback
    if db.general and db.general.skinUseClassColor then
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS[class]
        if color then
            return color.r, color.g, color.b, 1
        end
    end

    local c = (db.general and db.general.addonAccentColor)
        or db.addonAccentColor
        or {0.376, 0.647, 0.980, 1}
    return c[1], c[2], c[3], c[4] or 1
end

function QUI:GetSkinBgColor()
    local db = QUI.db and QUI.db.profile
    if not db or not db.general then
        return 0.05, 0.05, 0.05, 0.95  -- Fallback to neutral dark
    end

    local c = db.general.skinBgColor or { 0.05, 0.05, 0.05, 0.95 }
    return c[1], c[2], c[3], c[4] or 0.95
end

-- Safe font setter with fallback for missing font files
-- LSM:Fetch returns a path even if the file doesn't exist, so SetFont() can silently fail
-- SafeSetFont, ApplyGlobalFont, and font system are in core/font_system.lua

function QUICore:RefreshAll()
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
    -- Also refresh Blizzard UI fonts when global font changes
    if self.ApplyGlobalFont then
        self:ApplyGlobalFont()
    end
    -- Refresh skyriding HUD fonts
    local RefreshSkyriding = _G.QUI_RefreshSkyriding
    if RefreshSkyriding then
        RefreshSkyriding()
    end
end

