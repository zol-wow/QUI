--- QUI Core
--- All branding changed to QUI

local ADDON_NAME, ns = ...
local QUI = QUI
local ADDON_NAME = "QUI"

-- Create QUICore as an Ace3 module within QUI
local QUICore = QUI:NewModule("QUICore", "AceConsole-3.0", "AceEvent-3.0")
QUI.QUICore = QUICore

-- Expose QUICore to namespace for other files
ns.Addon = QUICore

-- Shared utility functions (ns.Utils created by utils.lua, extend here)
ns.Utils = ns.Utils or {}
-- Note: IsSecretValue and other secret value utilities are in utils.lua
-- They're available via ns.Helpers.IsSecretValue and ns.Utils.IsSecretValue (alias)

-- Check if player is in instanced content (dungeon or raid)
function ns.Utils.IsInInstancedContent()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

-- Global pending reload system
QUICore.__pendingReload = false
QUICore.__reloadEventFrame = nil

-- Safe reload function - queues if in combat, reloads immediately if not
function QUICore:SafeReload()
    if InCombatLockdown() then
        if not self.__pendingReload then
            self.__pendingReload = true
            print("|cFF30D1FFQUI:|r Reload queued - will execute when combat ends.")

            -- Create event frame if needed
            if not self.__reloadEventFrame then
                self.__reloadEventFrame = CreateFrame("Frame")
                self.__reloadEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                self.__reloadEventFrame:SetScript("OnEvent", function(frame, event)
                    if event == "PLAYER_REGEN_ENABLED" and QUICore.__pendingReload then
                        QUICore.__pendingReload = false
                        -- Show popup with reload button (user click = allowed)
                        QUICore:ShowReloadPopup()
                    end
                end)
            end
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
        if InCombatLockdown() then
            print("|cFF30D1FFQUI:|r Cannot reload during combat.")
        else
            ReloadUI()
        end
    end
end

local LSM = LibStub("LibSharedMedia-3.0")
local LCG = LibStub("LibCustomGlow-1.0", true)

local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub("LibDeflate", true)
local LibDualSpec   = LibStub("LibDualSpec-1.0", true)

-- Texture registration handled in media.lua

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

function QUICore:ImportProfileFromString(str)
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
    str = str:gsub("^QUI1:", "")  -- QUI prefix
    str = str:gsub("^QUI1:", "")  -- Strip QUI1 prefix
    str = str:gsub("^CDM1:", "")  -- Backwards compatibility

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, t = AceSerializer:Deserialize(serialized)
    if not ok or type(t) ~= "table" then
        return false, "Could not deserialize profile."
    end

    local profile = self.db.profile

    for k in pairs(profile) do
        profile[k] = nil
    end
    for k, v in pairs(t) do
        profile[k] = v
    end

    if self.RefreshAll then
        self:RefreshAll()
    end

    return true
end

---=================================================================================
--- CUSTOM TRACKER BAR IMPORT/EXPORT
---=================================================================================

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
-- Generate a collision-safe unique tracker ID
local function GenerateUniqueTrackerID(self)
    local used = {}
    local bars = self.db.profile.customTrackers and self.db.profile.customTrackers.bars or {}
    for _, b in ipairs(bars) do
        if b.id then used[b.id] = true end
    end
    if self.db.global and self.db.global.specTrackerSpells then
        for id in pairs(self.db.global.specTrackerSpells) do
            used[id] = true
        end
    end
    local id
    repeat
        id = "tracker" .. time() .. math.random(1000, 9999)
    until not used[id]
    return id
end

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

    -- Ensure customTrackers structure exists
    if not self.db.profile.customTrackers then
        self.db.profile.customTrackers = { bars = {} }
    end
    if not self.db.profile.customTrackers.bars then
        self.db.profile.customTrackers.bars = {}
    end

    -- Generate collision-safe unique ID for the imported bar
    local oldID = data.bar.id
    local newID = GenerateUniqueTrackerID(self)
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
            local newID = GenerateUniqueTrackerID(self)
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
--- SAFE BACKDROP UTILITY (Combat/Secret Value Protection)
---=================================================================================

-- Global SafeSetBackdrop function that defers SetBackdrop calls when frame dimensions
-- are secret values (Midnight 12.0 protection) or when in combat lockdown.
-- This prevents the "attempt to perform arithmetic on a secret value" error that occurs
-- when Blizzard's Backdrop.lua tries to use GetWidth()/GetHeight() during protected contexts.
--
-- @param frame The frame to set backdrop on (must have BackdropTemplate mixed in)
-- @param backdropInfo The backdrop info table, or nil to remove backdrop
-- @param borderColor Optional {r,g,b,a} table for border color after backdrop is set
-- @return boolean True if backdrop was set immediately, false if deferred
function QUICore.SafeSetBackdrop(frame, backdropInfo, borderColor)
    if not frame or not frame.SetBackdrop then return false end

    -- Check if frame has valid (non-secret) dimensions
    -- SetBackdrop internally calls GetWidth/GetHeight which can error on secret values
    local hasValidSize = false
    local ok, result = pcall(function()
        local w = frame:GetWidth()
        local h = frame:GetHeight()
        -- Try to do arithmetic - this will fail if they're secret values
        if w and h then
            local test = w + h  -- This will error if secret
            if test > 0 then
                return true
            end
        end
        return false
    end)
    if ok and result then
        hasValidSize = true
    end

    -- If dimensions are secret/invalid, defer the backdrop setup
    if not hasValidSize then
        frame.__quiBackdropPending = backdropInfo
        frame.__quiBackdropBorderColor = borderColor
        QUICore.__pendingBackdrops = QUICore.__pendingBackdrops or {}
        QUICore.__pendingBackdrops[frame] = true

        -- Set up deferred processing via OnUpdate (for when dimensions become valid)
        if not QUICore.__backdropUpdateFrame then
            local updateFrame = CreateFrame("Frame")
            local elapsed = 0
            updateFrame:SetScript("OnUpdate", function(self, delta)
                elapsed = elapsed + delta
                if elapsed < 0.1 then return end  -- Check every 0.1s
                elapsed = 0

                local processed = {}
                for pendingFrame in pairs(QUICore.__pendingBackdrops or {}) do
                    if pendingFrame and pendingFrame.__quiBackdropPending ~= nil then
                        -- Re-check if dimensions are now valid
                        local checkOk, checkResult = pcall(function()
                            local w = pendingFrame:GetWidth()
                            local h = pendingFrame:GetHeight()
                            if w and h then
                                local test = w + h
                                return test > 0
                            end
                            return false
                        end)

                        if checkOk and checkResult and not InCombatLockdown() then
                            local setOk = pcall(pendingFrame.SetBackdrop, pendingFrame, pendingFrame.__quiBackdropPending)
                            if setOk and pendingFrame.__quiBackdropPending and pendingFrame.__quiBackdropBorderColor then
                                local c = pendingFrame.__quiBackdropBorderColor
                                pendingFrame:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
                            end
                            pendingFrame.__quiBackdropPending = nil
                            pendingFrame.__quiBackdropBorderColor = nil
                            table.insert(processed, pendingFrame)
                        end
                    else
                        table.insert(processed, pendingFrame)
                    end
                end

                for _, pf in ipairs(processed) do
                    QUICore.__pendingBackdrops[pf] = nil
                end

                -- Stop OnUpdate if no more pending
                local hasAny = false
                for _ in pairs(QUICore.__pendingBackdrops or {}) do
                    hasAny = true
                    break
                end
                if not hasAny then
                    self:Hide()
                end
            end)
            QUICore.__backdropUpdateFrame = updateFrame
        end
        QUICore.__backdropUpdateFrame:Show()
        return false
    end

    -- If in combat, defer backdrop setup to avoid secret value errors
    if InCombatLockdown() then
        local alreadyPending = QUICore.__pendingBackdrops and QUICore.__pendingBackdrops[frame]
        if not alreadyPending then
            frame.__quiBackdropPending = backdropInfo
            frame.__quiBackdropBorderColor = borderColor

            if not QUICore.__backdropEventFrame then
                local eventFrame = CreateFrame("Frame")
                eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                eventFrame:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    for pendingFrame in pairs(QUICore.__pendingBackdrops or {}) do
                        if pendingFrame and pendingFrame.__quiBackdropPending ~= nil then
                            if not InCombatLockdown() then
                                local setOk = pcall(pendingFrame.SetBackdrop, pendingFrame, pendingFrame.__quiBackdropPending)
                                if setOk and pendingFrame.__quiBackdropPending and pendingFrame.__quiBackdropBorderColor then
                                    local c = pendingFrame.__quiBackdropBorderColor
                                    pendingFrame:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
                                end
                            end
                            pendingFrame.__quiBackdropPending = nil
                            pendingFrame.__quiBackdropBorderColor = nil
                        end
                    end
                    QUICore.__pendingBackdrops = {}
                end)
                QUICore.__backdropEventFrame = eventFrame
            end

            QUICore.__pendingBackdrops = QUICore.__pendingBackdrops or {}
            QUICore.__pendingBackdrops[frame] = true
            QUICore.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return false
    end

    -- Safe to set backdrop now
    local setOk = pcall(frame.SetBackdrop, frame, backdropInfo)
    if setOk and backdropInfo and borderColor then
        frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    end
    return setOk
end

---=================================================================================
--- VIEWER LIST
---=================================================================================

-- NOTE: All cooldown viewers are now handled by dedicated modules:
-- EssentialCooldownViewer/UtilityCooldownViewer → qui_ncdm.lua
-- BuffIconCooldownViewer/BuffBarCooldownViewer → qui_buffbar.lua
QUICore.viewers = {
    -- "EssentialCooldownViewer",  -- Handled by NCDM
    -- "UtilityCooldownViewer",    -- Handled by NCDM
    -- "BuffIconCooldownViewer",   -- Handled by qui_buffbar.lua
}

local defaults = {
    profile = {
        -- Nudge amount for moving frames
        nudgeAmount = 1,

        -- General Settings
        general = {
            uiScale = 0.64,  -- Default UI scale for 1440p+ monitors
            font = "Quazii",  -- Default font face
            fontOutline = "OUTLINE",  -- Default font outline: "", "OUTLINE", "THICKOUTLINE"
            texture = "Quazii v5",  -- Default bar texture
            darkMode = false,
            darkModeHealthColor = { 0, 0, 0, 1 },
            darkModeBgColor = { 0.592, 0.592, 0.592, 1 },
            darkModeOpacity = 0.7,
            darkModeHealthOpacity = 0.7,
            darkModeBgOpacity = 0.7,
            masterColorNameText = false,
            masterColorToTText = false,
            masterColorPowerText = false,
            masterColorHealthText = false,
            masterColorCastbarText = false,
            defaultUseClassColor = true,
            defaultHealthColor = { 0.2, 0.2, 0.2, 1 },
            hostilityColorHostile = { 0.8, 0.2, 0.2, 1 },
            hostilityColorNeutral = { 1, 1, 0.2, 1 },
            hostilityColorFriendly = { 0.2, 0.8, 0.2, 1 },
            defaultBgColor = { 0, 0, 0, 1 },
            defaultOpacity = 1.0,
            defaultHealthOpacity = 1.0,
            defaultBgOpacity = 1.0,
            applyGlobalFontToBlizzard = true,  -- Apply font to Blizzard UI elements
            autoInsertKey = true,  -- Auto-insert keystone in M+ UI
            skinKeystoneFrame = true,  -- Skin keystone insertion window
            skinGameMenu = false,  -- Skin ESC menu (opt-in)
            addQUIButton = false,  -- Add QUI button to ESC menu (opt-in)
            gameMenuFontSize = 12,  -- Game menu button font size
            gameMenuDim = true,  -- Dim background when game menu is open
            skinPowerBarAlt = true,  -- Skin encounter/quest power bar (PlayerPowerBarAlt)
            skinOverrideActionBar = false,  -- Skin override/vehicle action bar (opt-in)
            skinObjectiveTracker = false,  -- Skin objective tracker (opt-in)
            objectiveTrackerHeight = 600,  -- Objective tracker max height
            objectiveTrackerModuleFontSize = 12,  -- Module headers (QUESTS, ACHIEVEMENTS, etc.)
            objectiveTrackerTitleFontSize = 10,  -- Quest/achievement titles
            objectiveTrackerTextFontSize = 10,  -- Objective text lines
            hideObjectiveTrackerBorder = false,  -- Hide the class-colored border
            objectiveTrackerModuleColor = { 1.0, 0.82, 0.0, 1.0 },  -- Module header color (Blizzard gold)
            objectiveTrackerTitleColor = { 1.0, 1.0, 1.0, 1.0 },  -- Quest title color (white)
            objectiveTrackerTextColor = { 0.8, 0.8, 0.8, 1.0 },  -- Objective text color (light gray)
            skinInstanceFrames = false,  -- Skin PVE/Dungeon/PVP frames (opt-in)
            skinBgColor = { 0.008, 0.008, 0.008, 1 },  -- Skinning background color (with alpha)
            skinAlerts = true,  -- Skin alert/toast frames
            skinCharacterFrame = true,  -- Skin Character Frame (Character, Reputation, Currency tabs)
            skinInspectFrame = true,  -- Skin Inspect Frame to match Character Frame
            skinLootWindow = true,  -- Skin custom loot window
            skinLootUnderMouse = true,  -- Position loot window at cursor
            skinLootHistory = true,  -- Skin loot history frame
            skinRollFrames = true,  -- Skin loot roll frames
            skinRollSpacing = 6,  -- Spacing between roll frames
            skinUseClassColor = true,  -- Use class color for skin accents
            -- QoL Automation
            sellJunk = true,
            autoRepair = "personal",      -- "off", "personal", "guild"
            autoRoleAccept = true,
            autoAcceptInvites = "all",    -- "off", "all", "friends", "guild", "both"
            autoAcceptQuest = false,
            autoTurnInQuest = false,
            questHoldShift = true,
            fastAutoLoot = true,
            autoSelectGossip = false,  -- Auto-select single gossip options
            autoCombatLog = false,  -- Auto start/stop combat logging in M+ (opt-in)
            autoDeleteConfirm = true,  -- Auto-fill DELETE confirmation text
            -- Pet Warning (pet-spec classes: Hunter, Warlock, DK, Mage)
            petCombatWarning = true,    -- Show combat warning in instances when pet missing/passive
            petWarningOffsetX = 0,      -- Warning frame X offset from center
            petWarningOffsetY = -200,   -- Warning frame Y offset from center
            -- Consumable Check (disabled by default)
            consumableCheckEnabled = false,       -- Master toggle
            consumableOnReadyCheck = true,        -- Show on ready check
            consumableOnDungeon = false,          -- Show on dungeon entrance
            consumableOnRaid = false,             -- Show on raid entrance
            consumableOnResurrect = false,        -- Show on instanced resurrect
            consumableFood = true,                -- Track food buff
            consumableFlask = true,               -- Track flask buff
            consumableOilMH = true,               -- Track main hand weapon enchant
            consumableOilOH = true,               -- Track off hand weapon enchant
            consumableRune = true,                -- Track augment rune
            consumableHealthstone = true,         -- Track healthstones (warlock in group)
            consumableExpirationWarning = false,  -- Warn when buffs expiring
            consumableExpirationThreshold = 300,  -- Seconds before expiration warning
            consumableAnchorMode = true,          -- Anchor to ready check frame
            consumableIconOffset = 5,             -- Icon offset from anchor
            consumableIconSize = 40,              -- Icon size in pixels
            -- Quick Salvage settings
            quickSalvage = {
                enabled = false,  -- Opt-in, OFF by default
                modifier = "ALT",  -- "ALT", "ALTCTRL", "ALTSHIFT"
            },
            -- M+ Dungeon Teleport
            mplusTeleportEnabled = true,  -- Click-to-teleport on M+ tab icons
            keyTrackerEnabled = true,     -- Show party keys on M+ tab
            keyTrackerFontSize = 9,       -- Font size for key tracker (7-12)
            keyTrackerFont = nil,         -- Font name from LSM (nil = global QUI font "Quazii")
            keyTrackerTextColor = {1, 1, 1, 1},  -- RGBA text color for dungeon/player text
            keyTrackerPoint = "TOPRIGHT",         -- Anchor point on KeyTracker frame
            keyTrackerRelPoint = "BOTTOMRIGHT",   -- Relative point on PVEFrame
            keyTrackerOffsetX = 0,                -- X offset from anchor
            keyTrackerOffsetY = 0,                -- Y offset from anchor
            keyTrackerWidth = 170,                -- Frame width in pixels
        },

        -- Alert & Toast Skinning Settings (enabled via general.skinAlerts)
        alerts = {
            enabled = true,
            alertPosition = { point = "TOP", relPoint = "TOP", x = 1.667, y = -293.333 },
            toastPosition = { point = "CENTER", relPoint = "CENTER", x = -5.833, y = 268.333 },
        },

        -- Missing Raid Buffs Display Settings
        raidBuffs = {
            enabled = true,
            showOnlyInGroup = true,
            providerMode = false,
            hideLabelBar = false,  -- Hide the "Missing Buffs" label bar
            iconSize = 32,
            iconSpacing = 4,
            labelFontSize = 12,
            labelTextColor = nil,  -- nil = white, otherwise {r, g, b, a}
            position = nil,
            growDirection = "RIGHT",  -- LEFT, RIGHT, UP, DOWN, CENTER_H, CENTER_V
            iconBorder = {
                show = true,
                width = 1,
                useClassColor = false,
                color = { 0.2, 1.0, 0.6, 1 },  -- Default mint accent
            },
            buffCount = {
                show = true,
                position = "BOTTOM",  -- TOP, BOTTOM, LEFT, RIGHT
                fontSize = 10,
                font = "Quazii",  -- Font name from LibSharedMedia
                color = { 1, 1, 1, 1 },  -- White default
                offsetX = 0,
                offsetY = 0,
            },
        },

        -- Custom M+ Timer Settings
        mplusTimer = {
            enabled = false,
            layoutMode = "sleek",
            showTimer = true,
            showBorder = true,
            showDeaths = true,
            showAffixes = true,
            showObjectives = true,
            position = { x = -11.667, y = -204.998 },
        },

        -- Character Pane Settings
        character = {
            enabled = true,
            showItemName = true,            -- Show equipment name (line 1)
            showItemLevel = true,           -- Show item level & track (line 2)
            showEnchants = true,            -- Show enchant status (line 3)
            showGems = true,                -- Show gem indicators
            showDurability = false,         -- Show durability bars
            inspectEnabled = true,
            showModelBackground = true,     -- Show background behind model
            -- Inspect-specific overlay settings (separate from character)
            showInspectItemName = true,
            showInspectItemLevel = true,
            showInspectEnchants = true,
            showInspectGems = true,

            -- In-pane customization
            panelScale = 1.0,               -- Panel scale (0.75 - 1.5 multiplier, base 1.30)
            overlayScale = 0.75,            -- Overlay scale for slot info
            backgroundColor = {0, 0, 0, 0.762},  -- Black with transparency
            statsTextSize = 13,             -- Stats text size in pixels (6 - 40)
            statsTextColor = {1, 1, 1, 1},  -- Stats text color (white)
            ilvlTextSize = 8,               -- Item level text size in pixels (8 - 16)
            headerTextSize = 16,            -- Header text size in pixels (10 - 18)
            secondaryStatFormat = "both",   -- Secondary stat format: "percent", "rating", "both"
            compactStats = true,            -- Compact stats mode (reduced spacing)
            headerClassColor = true,        -- Use class color for headers (default on)
            headerColor = {0.204, 0.827, 0.6},  -- Header color (default accent/mint, used when headerClassColor is off)
            enchantTextSize = 10,           -- Enchant text size in pixels (8 - 14) [DEPRECATED - use slotTextSize]
            enchantClassColor = true,       -- Use class color for enchants (default on)
            enchantTextColor = {0.204, 0.827, 0.6},  -- Enchant text color (used when enchantClassColor is off)
            enchantFont = nil,              -- Enchant font (nil = use global font)
            noEnchantTextColor = {1, 0.341, 0.314, 1},  -- "No Enchant" text color (red tint)
            slotTextSize = 12,              -- Unified text size for all 3 slot lines (6 - 40)
            slotPadding = 0,                -- Padding between slot elements
            upgradeTrackColor = {1, 0.816, 0.145, 1},  -- Upgrade track text color (gold)
        },

        -- Loot Window Settings
        loot = {
            enabled = true,           -- Enable custom loot window
            lootUnderMouse = false,   -- Position loot window at cursor
            showTransmogMarker = true, -- Show marker on uncollected appearances
            position = { point = "TOP", relPoint = "TOP", x = 289.166, y = -165.667 },
        },

        -- Loot Roll Frame Settings
        lootRoll = {
            enabled = true,           -- Enable custom roll frames
            growDirection = "DOWN",   -- Roll frame stacking direction (UP/DOWN)
            spacing = 4,              -- Spacing between roll frames
            position = { point = "TOP", relPoint = "TOP", x = -11.667, y = -166 },
        },

        -- Loot History (Results) Settings
        lootResults = {
            enabled = true,           -- Skin GroupLootHistoryFrame
        },

        -- Keybind Overrides (stored per character/spec in db.char.keybindOverrides[specID])
        keybindOverridesEnabledCDM = true,
        keybindOverridesEnabledTrackers = true,

        -- FPS Settings Backup (stores user's CVars before applying Quazii's settings)
        fpsBackup = nil,

        -- QUI New Cooldown Display Manager (NCDM)
        -- Per-row configuration for Essential and Utility viewers
        ncdm = {
            essential = {
                enabled = true,
                layoutDirection = "HORIZONTAL",
                row1 = {
                    iconCount = 8,      -- How many icons in row 1 (0 = disabled)
                    iconSize = 39,      -- Icon size in pixels (width)
                    borderSize = 1,     -- Border thickness around icon (0 to 5)
                    borderColorTable = {0, 0, 0, 1}, -- Border color (RGBA)
                    aspectRatioCrop = 1.0,  -- 1.0 = square, higher = flatter
                    zoom = 0,           -- Icon texture zoom (0 to 0.2)
                    padding = 2,        -- Spacing between icons (-20 to 20)
                    xOffset = 0,        -- Horizontal offset for this row
                    yOffset = 0,        -- Vertical offset for this row (-50 to 50)
                    durationSize = 16,  -- Duration text font size (8 to 24)
                    durationOffsetX = 0, -- Duration text X offset
                    durationOffsetY = 0, -- Duration text Y offset
                    stackSize = 12,     -- Stack count text font size (8 to 24)
                    stackOffsetX = 0,   -- Stack text X offset
                    stackOffsetY = 2,   -- Stack text Y offset
                    durationTextColor = {1, 1, 1, 1}, -- Duration text color (white default)
                    durationAnchor = "CENTER",        -- Duration text anchor point
                    stackTextColor = {1, 1, 1, 1},    -- Stack text color (white default)
                    stackAnchor = "BOTTOMRIGHT",      -- Stack text anchor point
                },
                row2 = {
                    iconCount = 8,
                    iconSize = 39,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 3,
                    durationSize = 16,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 12,
                    stackOffsetX = 0,
                    stackOffsetY = 2,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                row3 = {
                    iconCount = 8,      -- 0 = row disabled by default
                    iconSize = 39,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 0,
                    durationSize = 16,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 12,
                    stackOffsetX = 0,
                    stackOffsetY = 2,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
            },
            utility = {
                enabled = true,
                layoutDirection = "HORIZONTAL",
                row1 = {
                    iconCount = 6,
                    iconSize = 30,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 0,
                    durationSize = 14,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 14,
                    stackOffsetX = 0,
                    stackOffsetY = 0,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                row2 = {
                    iconCount = 0,
                    iconSize = 30,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 8,
                    durationSize = 14,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 14,
                    stackOffsetX = 0,
                    stackOffsetY = 0,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                row3 = {
                    iconCount = 0,
                    iconSize = 30,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 4,
                    durationSize = 14,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 14,
                    stackOffsetX = 0,
                    stackOffsetY = 0,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                anchorBelowEssential = false,
                anchorGap = 0,
            },
            buff = {
                enabled = true,
                iconSize = 32,      -- Icon size in pixels
                borderSize = 1,     -- Border thickness (0 to 8)
                shape = "square",   -- DEPRECATED: use aspectRatioCrop instead
                aspectRatioCrop = 1.0,  -- Aspect ratio (0.5-2.0): <1=taller, 1=square, >1=wider
                growthDirection = "CENTERED_HORIZONTAL",  -- CENTERED_HORIZONTAL, LEFT, or RIGHT
                zoom = 0,           -- Icon texture zoom (0 to 0.2)
                padding = 4,        -- Spacing between icons (-20 to 20)
                durationSize = 14,  -- Duration text font size (8 to 24)
                durationOffsetX = 0,
                durationOffsetY = 8,
                durationAnchor = "TOP",
                stackSize = 14,     -- Stack count text font size (8 to 24)
                stackOffsetX = 0,
                stackOffsetY = -8,
                stackAnchor = "BOTTOM",
            },
            trackedBar = {
                enabled = true,
                hideIcon = false,
                barHeight = 25,
                barWidth = 215,
                texture = "Quazii v5",
                useClassColor = true,
                barColor = {0.204, 0.827, 0.6, 1},  -- mint accent fallback
                borderSize = 2,
                bgOpacity = 0.5,
                textSize = 14,
                spacing = 2,
                growUp = true,  -- true = grow upward, false = grow downward
                orientation = "horizontal",
                fillDirection = "UP",
                iconPosition = "top",
                showTextOnVertical = false,
            },
            customBuffs = {
                enabled = true,
                spellIDs = { 1254638 },
            },
        },

        -- CDM Visibility (essentials, utility, buffs, power bars)
        cdmVisibility = {
            showAlways = true,
            showWhenTargetExists = true,
            showInCombat = false,
            showInGroup = false,
            showInInstance = false,
            showOnMouseover = false,
            fadeDuration = 0.2,
            fadeOutAlpha = 0,
            hideWhenMounted = false,
        },

        -- Unitframes Visibility (player, target, focus, pet, tot, boss)
        unitframesVisibility = {
            showAlways = true,
            showWhenTargetExists = false,
            showInCombat = false,
            showInGroup = false,
            showInInstance = false,
            showOnMouseover = false,
            fadeDuration = 0.2,
            fadeOutAlpha = 0,
            alwaysShowCastbars = false,  -- When true, castbars ignore UF visibility
            hideWhenMounted = false,
        },

        -- Custom Trackers Visibility (all custom item/spell bars)
        customTrackersVisibility = {
            showAlways = true,
            showWhenTargetExists = false,
            showInCombat = false,
            showInGroup = false,
            showInInstance = false,
            showOnMouseover = false,
            fadeDuration = 0.2,
            fadeOutAlpha = 0,
            hideWhenMounted = false,
        },

        viewers = {
            EssentialCooldownViewer = {
                enabled          = true,
                iconSize         = 50,
                aspectRatioCrop  = 1.0,
                spacing          = -11,
                zoom             = 0,
                borderSize       = 1,
                borderColor      = { 0, 0, 0, 1 },
                chargeTextAnchor = "BOTTOMRIGHT",
                countTextSize    = 14,
                countTextOffsetX = 0,
                countTextOffsetY = 0,
                durationTextSize = 14,
                rowLimit         = 8,
                -- Row pattern: icons per row (0 = row disabled)
                row1Icons        = 6,
                row2Icons        = 6,
                row3Icons        = 6,
                useRowPattern    = false,  -- false = use rowLimit, true = use row pattern
                rowAlignment     = "CENTER", -- LEFT, CENTER, RIGHT
                -- Keybind display
                showKeybinds      = false,
                keybindTextSize   = 12,
                keybindTextColor  = { 1, 0.82, 0, 1 },  -- Gold/Yellow
                keybindAnchor     = "TOPLEFT",
                keybindOffsetX    = 2,
                keybindOffsetY    = 2,
                -- Rotation Helper overlay (uses C_AssistedCombat)
                showRotationHelper = false,
                rotationHelperColor = { 0, 1, 0.84, 1 },  -- #00FFD6 cyan/mint border
                rotationHelperThickness = 2,  -- Border thickness in pixels
            },
            UtilityCooldownViewer = {
                enabled          = true,
                iconSize         = 42,
                aspectRatioCrop  = 1.0,
                spacing          = -11,
                zoom             = 0.08,
                borderSize       = 1,
                borderColor      = { 0, 0, 0, 1 },
                chargeTextAnchor = "BOTTOMRIGHT",
                countTextSize    = 14,
                countTextOffsetX = 0,
                countTextOffsetY = 0,
                durationTextSize = 14,
                rowLimit         = 0,
                -- Row pattern: icons per row (0 = row disabled)
                row1Icons        = 8,
                row2Icons        = 8,
                useRowPattern    = false,  -- false = use rowLimit, true = use row pattern
                rowAlignment     = "CENTER", -- LEFT, CENTER, RIGHT
                -- Auto-anchor to Essential
                anchorToEssential = false,  -- When true, Utility anchors below Essential's last row
                anchorGap         = 10,     -- Gap between Essential and Utility when anchored
                -- Keybind display
                showKeybinds      = false,
                keybindTextSize   = 12,
                keybindTextColor  = { 1, 0.82, 0, 1 },  -- Gold/Yellow
                keybindAnchor     = "TOPLEFT",
                keybindOffsetX    = 2,
                keybindOffsetY    = 2,
                -- Rotation Helper overlay (uses C_AssistedCombat)
                showRotationHelper = false,
                rotationHelperColor = { 0, 1, 0.84, 1 },  -- #00FFD6 cyan/mint border
                rotationHelperThickness = 2,  -- Border thickness in pixels
            },
            -- BuffIconCooldownViewer removed - now handled by qui_buffbar.lua
            -- Settings are at db.profile.ncdm.buff instead
        },

        -- Rotation Assist Icon (standalone icon showing next recommended ability)
        rotationAssistIcon = {
            enabled = false,
            isLocked = true,
            iconSize = 56,
            visibility = "always",  -- "always", "combat", "hostile"
            frameStrata = "MEDIUM",
            -- Border
            showBorder = true,
            borderThickness = 2,
            borderColor = { 0, 0, 0, 1 },
            -- Cooldown
            cooldownSwipeEnabled = true,
            -- Keybind
            showKeybind = true,
            keybindFont = nil,  -- nil = use general.font
            keybindSize = 13,
            keybindColor = { 1, 1, 1, 1 },
            keybindOutline = true,
            keybindAnchor = "BOTTOMRIGHT",
            keybindOffsetX = -2,
            keybindOffsetY = 2,
            -- Position (anchored to CENTER of screen)
            positionX = 0,
            positionY = -180,
        },

        powerBar = {
            enabled           = true,
            autoAttach        = false,
            standaloneMode    = false,
            attachTo          = "EssentialCooldownViewer",
            height            = 8,
            borderSize        = 1,
            offsetY           = -204,      -- Snapped to top of Essential CDM (default position)
            offsetX           = 0,
            width             = 326,       -- Matches Essential CDM width
            useRawPixels      = true,
            texture           = "Quazii v5",
            colorMode         = "power",  -- "power" = power type color, "class" = class color
            usePowerColor     = true,     -- Use power type color (customizable in Power Colors section)
            useClassColor     = false,    -- Use class color
            customColor       = { 0.2, 0.6, 1, 1 },  -- Custom power bar color
            showPercent       = true,
            showText          = true,
            textSize          = 16,
            textX             = 1,
            textY             = 3,
            textUseClassColor = false,    -- Use class color for text
            textCustomColor   = { 1, 1, 1, 1 },  -- Custom text color (white default)
            bgColor           = { 0.078, 0.078, 0.078, 1 },
            showTicks         = false,    -- Show tick marks for segmented resources (Holy Power, Chi, etc.)
            tickThickness     = 2,        -- Thickness of tick marks in pixels
            tickColor         = { 0, 0, 0, 1 },  -- Color of tick marks (default black)
            lockedToEssential = false,  -- Auto-resize width when Essential CDM changes
            lockedToUtility   = false,  -- Auto-resize width when Utility CDM changes
            snapGap           = 5,      -- Gap when snapped to CDM
            orientation       = "HORIZONTAL",  -- Bar orientation
            visibility        = "always",  -- "always", "combat", "hostile"
        },
        castBar = {
            enabled       = true,
            attachTo      = "EssentialCooldownViewer",
            height        = 24,
            offsetX       = 0,
            offsetY       = -108.5,
            texture       = "Quazii",
            color         = { 0.188, 1, 0.988, 1 },
            useClassColor = false,
            textSize      = 16,
            width         = 0,
            bgColor       = { 0.078, 0.078, 0.067, 0.85 },
            showTimeText  = true,
            showIcon      = true,
        },
        targetCastBar = {
            enabled       = true,
            attachTo      = "QUICore_Target",
            height        = 18,
            offsetX       = 0,
            offsetY       = -32,
            texture       = "Quazii",
            color         = { 1.0, 0.0, 0.0, 1.0 },
            textSize      = 16,
            width         = 241.2,
            bgColor       = { 0.1, 0.1, 0.1, 1 },
            showTimeText  = true,
            showIcon      = true,
        },
        focusCastBar = {
            enabled       = true,
            attachTo      = "QUICore_Focus",
            height        = 18,
            offsetX       = 0,
            offsetY       = -32,
            texture       = "Quazii",
            color         = { 1.0, 0.0, 0.0, 1.0 },
            textSize      = 16,
            width         = 241.2,
            bgColor       = { 0.1, 0.1, 0.1, 1 },
            showTimeText  = true,
            showIcon      = true,
        },
        secondaryPowerBar = {
            enabled       = true,
            autoAttach    = false,
            standaloneMode = false,
            attachTo      = "EssentialCooldownViewer",
            height        = 8,
            borderSize    = 1,
            offsetY       = 0,        -- User adjustment when locked to primary (0 = no offset)
            offsetX       = 0,
            width         = 326,      -- Matches Primary bar width
            useRawPixels  = true,
            texture       = "Quazii v5",
            colorMode     = "power",  -- "power" = power type color, "class" = class color
            usePowerColor = true,     -- Use power type color (customizable in Power Colors section)
            useClassColor = false,    -- Use class color
            customColor   = { 1, 0.8, 0.2, 1 },  -- Custom power bar color
            showPercent   = false,
            showText      = false,
            textSize      = 14,
            textX         = 0,
            textY         = 2,
            textUseClassColor = false,    -- Use class color for text
            textCustomColor   = { 1, 1, 1, 1 },  -- Custom text color (white default)
            bgColor       = { 0.078, 0.078, 0.078, 0.83 },
            showTicks     = true,     -- Show tick marks for segmented resources (Holy Power, Chi, etc.)
            tickThickness = 2,        -- Thickness of tick marks in pixels
            tickColor     = { 0, 0, 0, 1 },  -- Color of tick marks (default black)
            lockedToEssential = false,  -- Auto-resize width when Essential CDM changes
            lockedToUtility   = false,  -- Auto-resize width when Utility CDM changes
            lockedToPrimary   = true,   -- Position above + match Primary bar width
            snapGap       = 5,        -- Gap when snapped
            orientation   = "AUTO",   -- Bar orientation
            visibility    = "always",  -- "always", "combat", "hostile"
            showFragmentedPowerBarText = false,  -- Show text on fragmented power bars
        },
        -- Power Colors (global, used by both Primary and Secondary power bars)
        powerColors = {
            -- Core Resources
            rage = { 1.00, 0.00, 0.00, 1 },
            energy = { 1.00, 1.00, 0.00, 1 },
            mana = { 0.00, 0.00, 1.00, 1 },
            focus = { 1.00, 0.50, 0.25, 1 },
            runicPower = { 0.00, 0.82, 1.00, 1 },
            fury = { 0.79, 0.26, 0.99, 1 },
            insanity = { 0.40, 0.00, 0.80, 1 },
            maelstrom = { 0.00, 0.50, 1.00, 1 },
            maelstromWeapon = { 0.00, 0.69, 1.00, 1 },
            lunarPower = { 0.30, 0.52, 0.90, 1 },

            -- Builder Resources
            holyPower = { 0.95, 0.90, 0.60, 1 },
            chi = { 0.00, 1.00, 0.59, 1 },
            comboPoints = { 1.00, 0.96, 0.41, 1 },
            soulShards = { 0.58, 0.51, 0.79, 1 },
            arcaneCharges = { 0.10, 0.10, 0.98, 1 },
            essence = { 0.20, 0.58, 0.50, 1 },

            -- Specialized Resources
            stagger = { 0.00, 1.00, 0.59, 1 },
            staggerLight = { 0.52, 1.00, 0.52, 1 },     -- Green (0-30% of max health)
            staggerModerate = { 1.00, 0.98, 0.72, 1 },  -- Yellow (30-60% of max health)
            staggerHeavy = { 1.00, 0.42, 0.42, 1 },     -- Red (60%+ of max health)
            useStaggerLevelColors = true,               -- Enable dynamic stagger colors
            soulFragments = { 0.64, 0.19, 0.79, 1 },
            runes = { 0.77, 0.12, 0.23, 1 },
            bloodRunes = { 0.77, 0.12, 0.23, 1 },
            frostRunes = { 0.00, 0.82, 1.00, 1 },
            unholyRunes = { 0.00, 0.80, 0.00, 1 },
        },
        -- Reticle (GCD tracker around cursor)
        reticle = {
            enabled = false,
            -- Reticle
            reticleStyle = "dot",         -- "dot", "cross", "chevron", "diamond"
            reticleSize = 10,             -- Size in pixels (4-20)
            -- Ring
            ringStyle = "standard",       -- "thin", "standard", "thick", "solid"
            ringSize = 40,                -- Ring diameter (20-80)
            -- Colors
            useClassColor = false,        -- Use class color vs custom
            customColor = {1, 1, 1, 1},   -- White default (#ffffff)
            -- Visibility
            inCombatAlpha = 1.0,
            outCombatAlpha = 1.0,
            hideOutOfCombat = false,
            -- Positioning
            offsetX = 0,
            offsetY = 0,
            -- GCD
            gcdEnabled = true,
            gcdFadeRing = 0.35,           -- Fade ring during GCD (0-1)
            gcdReverse = false,           -- Reverse swipe direction
            -- Behavior
            hideOnRightClick = false,
        },
        -- Screen Center Crosshair
        crosshair = {
            enabled = false,         -- Disabled by default
            onlyInCombat = false,    -- Show all the time when enabled
            size = 9,                -- Line length (half-length from center)
            thickness = 3,           -- Line thickness in pixels
            borderSize = 3,          -- Border thickness around lines
            offsetX = 0,             -- X offset from screen center
            offsetY = 0,             -- Y offset from screen center
            r = 0.796,               -- Crosshair color red
            g = 1,                   -- Crosshair color green
            b = 0.780,               -- Crosshair color blue
            a = 1,                   -- Crosshair alpha
            borderR = 0,             -- Border color red
            borderG = 0,             -- Border color green
            borderB = 0,             -- Border color blue
            borderA = 1,             -- Border alpha
            strata = "LOW",          -- Frame strata
            lineColor = { 0.796, 1, 0.780, 1 },
            borderColorTable = { 0, 0, 0, 1 },
            -- Range-based color changes
            changeColorOnRange = false,           -- Master toggle for range checking
            enableMeleeRangeCheck = true,         -- Check melee range (5 yards)
            enableMidRangeCheck = false,          -- Check mid-range (25 yards) for Evokers/Devourers
            outOfRangeColor = { 1, 0.2, 0.2, 1 },  -- Red color when out of range
            midRangeColor = { 1, 0.6, 0.2, 1 },   -- Orange color for 25-yard range (when both checks enabled)
            rangeColorInCombatOnly = false,       -- Only change color in combat
            hideUntilOutOfRange = false,          -- Only show crosshair when in combat AND out of range
        },

        -- Skyriding Vigor Bar
        skyriding = {
            enabled = true,
            width = 250,
            vigorHeight = 20,
            secondWindHeight = 20,
            offsetX = 0,
            offsetY = 135,
            locked = false,
            useClassColorVigor = false,
            barColor = { 0.2, 0.8, 1.0, 1 },              -- 33CCFF
            backgroundColor = { 0.102, 0.102, 0.102, 0.353 }, -- 1A1A1A with lower alpha
            segmentColor = { 0, 0, 0, 1 },                -- 000000
            rechargeColor = { 0.4, 0.9, 1.0, 1 },         -- 66E6FF
            borderSize = 1,
            borderColor = { 0, 0, 0, 1 },
            barTexture = "Quazii v4",
            showSegments = true,
            segmentThickness = 1,
            showSpeed = true,
            speedFormat = "PERCENT",
            speedFontSize = 11,
            showVigorText = true,
            vigorTextFormat = "FRACTION",
            vigorFontSize = 11,
            secondWindMode = "MINIBAR",
            secondWindScale = 2.1,
            useClassColorSecondWind = false,
            secondWindColor = { 1.0, 0.8, 0.2, 1 },       -- FFCC33
            secondWindBackgroundColor = { 0.102, 0.102, 0.102, 0.301 }, -- 1A1A1A with lower alpha
            visibility = "FLYING_ONLY",
            fadeDelay = 1,
            fadeDuration = 0.3,
        },

        -- Chat Frame Customization
        chat = {
            enabled = true,
            -- Glass visual effect
            glass = {
                enabled = true,
                bgAlpha = 0.25,          -- Background transparency (0-1.0)
                bgColor = {0, 0, 0},     -- Background color (RGB)
            },
            -- Message fade after inactivity (uses native API)
            fade = {
                enabled = false,         -- Off by default
                delay = 15,              -- Seconds before fade starts
                duration = 0.6,          -- Fade animation duration
            },
            -- Font settings
            font = {
                forceOutline = false,    -- Force font outline
            },
            -- URL detection and copying
            urls = {
                enabled = true,
                color = {0.078, 0.608, 0.992, 1},  -- Clickable URL color (blue)
            },
            -- UI cleanup
            hideButtons = true,          -- Hide social/channel/scroll buttons
            -- Input box styling
            editBox = {
                enabled = true,          -- Apply glass styling to input box
                bgAlpha = 0.25,          -- Background transparency (0-1.0)
                bgColor = {0, 0, 0},     -- Background color (RGB)
                height = 20,             -- Input box height
                positionTop = false,     -- Position input box above chat tabs
            },
            -- Timestamps
            timestamps = {
                enabled = false,         -- Off by default
                format = "24h",          -- "24h" or "12h"
                color = {0.6, 0.6, 0.6}, -- Gray color
            },
            -- Copy button mode: "always", "hover", "hidden", "disabled"
            copyButtonMode = "always",
            -- Intro message on login
            showIntroMessage = true,
        },

        -- Tooltip Management
        tooltip = {
            enabled = true,                    -- Master toggle for tooltip module
            anchorToCursor = true,             -- Follow cursor vs default anchor
            hideInCombat = true,               -- Suppress tooltips during combat
            classColorName = false,            -- Color player names by class
            skinTooltips = true,               -- Apply QUI theme to tooltips
            bgColor = {0.05, 0.05, 0.05, 1},  -- Custom background color
            bgOpacity = 0.95,                  -- Background opacity (0-1)
            showBorder = true,                 -- Toggle border visibility
            borderThickness = 1,               -- Border thickness (1-10)
            borderColor = {0.2, 1.0, 0.6, 1}, -- Border color (default = mint accent)
            borderUseClassColor = false,       -- Use player class color for border
            borderUseAccentColor = false,      -- Use addon accent color for border
            hideHealthBar = false,             -- Hide health bar on unit tooltips
            showSpellIDs = false,              -- Show spell ID and icon ID on buff/debuff tooltips
            -- Per-Context Visibility (SHOW/HIDE/SHIFT/CTRL/ALT)
            visibility = {
                npcs = "SHOW",                 -- NPCs/players in world
                abilities = "SHOW",            -- Action bar buttons
                items = "SHOW",                -- Bag/bank items
                frames = "SHOW",               -- Unit frame mouseover
                cdm = "SHOW",                  -- CDM views (Essential, Utility, Buff)
                customTrackers = "SHOW",       -- Custom Items/Spells bars
            },
            combatKey = "SHIFT",               -- NONE/SHIFT/CTRL/ALT
            hideHealthBar = true,              -- Hide the health bar on unit tooltips
        },

        -- QUI Action Bars - Button Skinning and Fade System
        actionBars = {
            enabled = true,
            -- Global settings (apply to all bars)
            global = {
                skinEnabled = true,         -- Apply button skinning
                iconSize = 36,              -- Base icon size (36x36)
                iconZoom = 0.05,            -- Icon texture crop (0.05-0.15)
                showBackdrop = true,        -- Show backdrop behind icons
                backdropAlpha = 0.8,        -- Backdrop opacity (0-1)
                showGloss = true,           -- Show gloss/shine overlay
                glossAlpha = 0.6,           -- Gloss opacity (0-1)
                showBorders = true,         -- Show button borders
                showKeybinds = true,        -- Show hotkey text
                showMacroNames = false,     -- Show macro name text
                showCounts = true,          -- Show stack/charge count
                hideEmptyKeybinds = false,  -- Hide placeholder keybinds
                keybindFontSize = 16,       -- Keybind text size
                keybindColor = {1, 1, 1, 1},-- Keybind text color
                keybindAnchor = "TOPRIGHT", -- Keybind text anchor point
                keybindOffsetX = 0,         -- Keybind text X offset
                keybindOffsetY = -5,        -- Keybind text Y offset
                macroNameFontSize = 10,     -- Macro name text size
                macroNameColor = {1, 1, 1, 1}, -- Macro name text color
                macroNameAnchor = "BOTTOM", -- Macro name text anchor point
                macroNameOffsetX = 0,       -- Macro name text X offset
                macroNameOffsetY = 0,       -- Macro name text Y offset
                countFontSize = 14,         -- Count text size
                countColor = {1, 1, 1, 1},  -- Count text color
                countAnchor = "BOTTOMRIGHT", -- Stack count text anchor point
                countOffsetX = 0,           -- Stack count text X offset
                countOffsetY = 0,           -- Stack count text Y offset
                -- Bar Layout settings
                barScale = 1.0,             -- Global scale multiplier (0.5 - 2.0)
                hideEmptySlots = false,     -- Hide buttons with no ability assigned
                lockButtons = false,        -- Prevent dragging abilities off buttons
                -- Range indicator settings
                rangeIndicator = false,     -- Tint out-of-range buttons
                rangeColor = {0.8, 0.1, 0.1, 1}, -- Red tint color
                -- Usability indicator settings
                usabilityIndicator = false,     -- Dim unusable buttons
                usabilityDesaturate = false,    -- Use desaturation (grey) for unusable
                usabilityColor = {0.4, 0.4, 0.4, 1},  -- Fallback color if not desaturating
                manaColor = {0.5, 0.5, 1.0, 1}, -- Out of mana color (blue tint)
                fastUsabilityUpdates = false, -- 5x faster range/usability checks (50ms vs 250ms)
                showTooltips = true,        -- Show tooltips when hovering action buttons
            },
            -- Mouseover fade settings
            fade = {
                enabled = true,             -- Master toggle for mouseover fade
                fadeInDuration = 0.2,       -- Fade in speed (seconds)
                fadeOutDuration = 0.3,      -- Fade out speed (seconds)
                fadeOutAlpha = 0.0,         -- Alpha when faded out (0-1)
                fadeOutDelay = 0.5,         -- Delay before fading out (seconds)
                alwaysShowInCombat = false, -- Force full opacity during combat
                linkBars1to8 = false,       -- Link all action bars 1-8 for mouseover
            },
            -- Per-bar settings (nil = use global, value = override)
            -- alwaysShow = true means bar stays visible even when mouseover hide is enabled
            bars = {
                bar1 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    hidePageArrow = true,
                    -- Style overrides (nil = use global)
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = 8,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = -20, keybindOffsetY = -20,
                    showMacroNames = nil, macroNameFontSize = 8, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = -20, macroNameOffsetY = -20,
                    showCounts = nil, countFontSize = 8, countColor = nil,
                    countAnchor = nil, countOffsetX = -20, countOffsetY = -20,
                },
                bar2 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = 8,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = -20, keybindOffsetY = -20,
                    showMacroNames = nil, macroNameFontSize = 8, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = -20, macroNameOffsetY = -20,
                    showCounts = nil, countFontSize = 8, countColor = nil,
                    countAnchor = nil, countOffsetX = -20, countOffsetY = -20,
                },
                bar3 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = 8,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = -20, keybindOffsetY = -20,
                    showMacroNames = nil, macroNameFontSize = 8, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = -20, macroNameOffsetY = -20,
                    showCounts = nil, countFontSize = 8, countColor = nil,
                    countAnchor = nil, countOffsetX = -20, countOffsetY = -20,
                },
                bar4 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = 8,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = -20, keybindOffsetY = -20,
                    showMacroNames = nil, macroNameFontSize = 8, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = -20, macroNameOffsetY = -20,
                    showCounts = nil, countFontSize = 8, countColor = nil,
                    countAnchor = nil, countOffsetX = -20, countOffsetY = -20,
                },
                bar5 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = 8,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = -20, keybindOffsetY = -20,
                    showMacroNames = nil, macroNameFontSize = 8, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = -20, macroNameOffsetY = -20,
                    showCounts = nil, countFontSize = 8, countColor = nil,
                    countAnchor = nil, countOffsetX = -20, countOffsetY = -20,
                },
                bar6 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = 8,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = -20, keybindOffsetY = -20,
                    showMacroNames = nil, macroNameFontSize = 8, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = -20, macroNameOffsetY = -20,
                    showCounts = nil, countFontSize = 8, countColor = nil,
                    countAnchor = nil, countOffsetX = -20, countOffsetY = -20,
                },
                bar7 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = 8,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = -20, keybindOffsetY = -20,
                    showMacroNames = nil, macroNameFontSize = 8, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = -20, macroNameOffsetY = -20,
                    showCounts = nil, countFontSize = 8, countColor = nil,
                    countAnchor = nil, countOffsetX = -20, countOffsetY = -20,
                },
                bar8 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = 8,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = -20, keybindOffsetY = -20,
                    showMacroNames = nil, macroNameFontSize = 8, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = -20, macroNameOffsetY = -20,
                    showCounts = nil, countFontSize = 8, countColor = nil,
                    countAnchor = nil, countOffsetX = -20, countOffsetY = -20,
                },
                -- Pet/Stance/Microbar/Bags/Extra do NOT have style overrides
                pet = { enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false },
                stance = { enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false },
                microbar = { enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false },
                bags = { enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false },
                -- Extra Action Button (boss encounters, quests)
                extraActionButton = {
                    enabled = true,
                    fadeEnabled = nil,
                    fadeOutAlpha = nil,
                    alwaysShow = true,
                    scale = 1.0,
                    offsetX = 0,
                    offsetY = 0,
                    position = { point = "CENTER", relPoint = "CENTER", x = -120.833, y = -25.833 },
                    hideArtwork = false,
                },
                -- Zone Ability Button (garrison, covenant, zone powers)
                zoneAbility = {
                    enabled = true,
                    fadeEnabled = nil,
                    fadeOutAlpha = nil,
                    alwaysShow = true,
                    scale = 1.0,
                    offsetX = 0,
                    offsetY = 0,
                    position = { point = "CENTER", relPoint = "CENTER", x = 150, y = -27.5 },
                    hideArtwork = false,
                },
            },
        },

        -- QUI Unit Frames (New Implementation)
        quiUnitFrames = {
            enabled = true,
            -- General settings (applies to all frames)
            general = {
                darkMode = false,                         -- Instant dark mode toggle (disabled by default)
                darkModeHealthColor = { 0.15, 0.15, 0.15, 1 },  -- #262626
                darkModeBgColor = { 0.25, 0.25, 0.25, 1 },      -- #404040
                darkModeOpacity = 1.0,                          -- Frame opacity when dark mode enabled (0.1 to 1.0)
                darkModeHealthOpacity = 1.0,                    -- Health bar opacity when dark mode enabled
                darkModeBgOpacity = 1.0,                        -- Background opacity when dark mode enabled
                -- Default unitframe colors (when dark mode is OFF)
                defaultUseClassColor = true,                    -- Use class color for health bar (default ON)
                defaultHealthColor = { 0.2, 0.2, 0.2, 1 },      -- Default health bar color (when class color OFF)
                defaultBgColor = { 0, 0, 0, 1 },                -- Default background color (pure black)
                defaultOpacity = 1.0,                           -- Default bar opacity
                defaultHealthOpacity = 1.0,                     -- Health bar opacity when dark mode disabled
                defaultBgOpacity = 1.0,                         -- Background opacity when dark mode disabled
                classColorText = false,                   -- LEGACY: Use class color for all unit frame text (kept for migration)
                -- Master text color overrides (new system - takes precedence over per-unit settings)
                masterColorNameText = false,              -- Apply class/reaction color to ALL name text
                masterColorHealthText = false,            -- Apply class/reaction color to ALL health text
                masterColorPowerText = false,             -- Apply class/reaction color to ALL power text
                masterColorCastbarText = false,           -- Apply class/reaction color to ALL castbar text (spell + timer)
                masterColorToTText = false,               -- Apply class/reaction color to ALL inline ToT text
                font = "Quazii",
                fontSize = 12,
                fontOutline = "OUTLINE",                  -- NONE, OUTLINE, THICKOUTLINE
                showTooltips = true,                      -- Show tooltips on unit frame mouseover
                smootherAnimation = false,                -- Uncap 60 FPS throttle for smoother castbar animation
                -- Hostility colors (for NPC unit frames)
                hostilityColorHostile = { 0.8, 0.2, 0.2, 1 },   -- Red (enemies)
                hostilityColorNeutral = { 1, 1, 0.2, 1 },       -- Yellow (neutral NPCs)
                hostilityColorFriendly = { 0.2, 0.8, 0.2, 1 },  -- Green (friendly NPCs)
            },
            -- Player frame settings
            player = {
                enabled = true,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 240,
                height = 40,
                offsetX = -290,
                offsetY = -219,
                -- Anchor to frame (disabled, essential, utility, primary, secondary)
                anchorTo = "disabled",
                anchorGap = 10,
                anchorYOffset = 0,
                texture = "Quazii v5",
                useClassColor = true,
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Portrait
                showPortrait = false,
                portraitSide = "LEFT",
                portraitSize = 40,
                portraitBorderSize = 1,
                portraitBorderUseClassColor = false,
                portraitBorderColor = { 0, 0, 0, 1 },
                portraitGap = 0,
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 16,
                nameAnchor = "LEFT",
                nameOffsetX = 12,
                nameOffsetY = 0,
                maxNameLength = 0,              -- 0 = no limit, otherwise truncate to N characters
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = true,
                healthDisplayStyle = "both",    -- "percent", "absolute", "both", "both_reverse"
                healthDivider = " | ",          -- " | ", " - ", " / "
                healthFontSize = 16,
                healthAnchor = "RIGHT",
                healthOffsetX = -12,
                healthOffsetY = 0,
                healthTextUseClassColor = false, -- Independent from name class color
                healthTextColor = { 1, 1, 1, 1 }, -- Custom health text color
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",    -- "percent", "current", "both"
                powerTextUsePowerColor = true,  -- Use power type color (mana blue, rage red, etc.)
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 12,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -9,
                powerTextOffsetY = 4,
                -- Power bar
                showPowerBar = false,
                powerBarHeight = 4,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = false,
                    color = { 1, 1, 1, 1 },
                    opacity = 0.3,
                    texture = "QUI Stripes",
                },
                -- Heal prediction (incoming heals)
                healPrediction = {
                    enabled = false,
                    color = { 0.2, 1, 0.2 },
                    opacity = 0.5,
                },
                -- Castbar
                castbar = {
                    enabled = true,
                    showIcon = true,
                    width = 333,
                    height = 25,
                    offsetX = 0,
                    offsetY = -35,
                    widthAdjustment = 0,
                    fontSize = 14,
                    color = {0.404, 1, 0.984, 1},  -- Cyan color from your profile
                    anchor = "none",
                    texture = "Quazii v5",
                    bgColor = {0.149, 0.149, 0.149, 1},
                    borderSize = 1,
                    useClassColor = false,
                    highlightInterruptible = false,
                    interruptibleColor = {0.2, 0.8, 0.2, 1},
                    maxLength = 0,
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 22,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 22,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                    -- Duration text
                    iconSpacing = 2,
                    buffSpacing = 2,
                    debuffSpacing = 2,
                    durationColor = {1, 1, 1, 1},
                    showDuration = false,
                    durationSize = 12,
                    durationAnchor = "CENTER",
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    -- Stack text
                    stackColor = {1, 1, 1, 1},
                    showStack = true,
                    stackSize = 10,
                    stackAnchor = "BOTTOMRIGHT",
                    stackOffsetX = -1,
                    stackOffsetY = 1,
                    -- Buff duration/stack
                    buffDuration = { show = true, fontSize = 12, anchor = "CENTER", offsetX = 0, offsetY = 0, color = {1, 1, 1, 1} },
                    buffStack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = {1, 1, 1, 1} },
                    buffShowStack = true,
                    buffStackSize = 10,
                    buffStackAnchor = "BOTTOMRIGHT",
                    buffStackOffsetX = -1,
                    buffStackOffsetY = 1,
                    buffStackColor = {1, 1, 1, 1},
                    -- Debuff duration/stack
                    debuffDuration = { show = false, fontSize = 10, anchor = "CENTER", offsetX = 0, offsetY = 0, color = {1, 1, 1, 1} },
                    debuffStack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = {1, 1, 1, 1} },
                    debuffShowStack = true,
                    debuffStackSize = 10,
                    debuffStackAnchor = "BOTTOMRIGHT",
                    debuffStackOffsetX = -1,
                    debuffStackOffsetY = 1,
                    debuffStackColor = {1, 1, 1, 1},
                },
                -- Status indicators (player only)
                indicators = {
                    rested = {
                        enabled = false,      -- Disabled by default
                        size = 16,
                        anchor = "TOPLEFT",
                        offsetX = -2,
                        offsetY = 2,
                    },
                    combat = {
                        enabled = false,      -- Disabled by default
                        size = 16,
                        anchor = "TOPRIGHT",
                        offsetX = -2,
                        offsetY = 2,
                    },
                    stance = {
                        enabled = false,      -- Disabled by default (opt-in)
                        fontSize = 12,
                        anchor = "BOTTOM",
                        offsetX = 0,
                        offsetY = -2,
                        useClassColor = true,
                        customColor = { 1, 1, 1, 1 },
                        showIcon = false,
                        iconSize = 14,
                        iconOffsetX = -2,
                    },
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,    -- Disabled by default for player (rarely marked)
                    size = 20,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 8,
                },
                -- Leader/Assistant icon (crown for leader, flag for assistant)
                leaderIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "TOPLEFT",
                    xOffset = -8,
                    yOffset = 8,
                },
            },
            -- Target frame settings
            target = {
                enabled = true,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 240,
                height = 40,
                offsetX = 290,
                offsetY = -219,
                -- Anchor to frame (disabled, essential, utility, primary, secondary)
                anchorTo = "disabled",
                anchorGap = 10,
                anchorYOffset = 0,
                texture = "Quazii v5 Inverse",
                useClassColor = true,
                useHostilityColor = true,  -- Use red/yellow/green based on unit hostility
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Portrait
                showPortrait = false,
                portraitSide = "RIGHT",
                portraitSize = 40,
                portraitBorderSize = 1,
                portraitBorderUseClassColor = false,
                portraitBorderColor = { 0, 0, 0, 1 },
                portraitGap = 0,
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 16,
                nameAnchor = "RIGHT",
                nameOffsetX = -9,
                nameOffsetY = 0,
                maxNameLength = 10,              -- 0 = no limit, otherwise truncate to N characters
                -- Inline Target of Target (shows ">> ToT Name" after target name)
                showInlineToT = false,
                totSeparator = " >> ",
                totUseClassColor = true,
                totDividerUseClassColor = false,    -- Color divider by class/reaction
                totDividerColor = {1, 1, 1, 1},     -- Custom divider color (white default)
                totNameCharLimit = 0,               -- 0 = no limit, otherwise limit ToT name length
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = true,
                healthDisplayStyle = "both",    -- "percent", "absolute", "both", "both_reverse"
                healthDivider = " | ",          -- " | ", " - ", " / "
                healthFontSize = 16,
                healthAnchor = "LEFT",
                healthOffsetX = 9,
                healthOffsetY = 0,
                healthTextUseClassColor = false, -- Independent from name class color
                healthTextColor = { 1, 1, 1, 1 }, -- Custom health text color
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",    -- "percent", "current", "both"
                powerTextUsePowerColor = false,  -- Use power type color (mana blue, rage red, etc.)
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 14,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -2,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = false,
                powerBarHeight = 4,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1, 1 },
                    opacity = 0.3,
                    texture = "QUI Stripes",
                },
                -- Heal prediction (incoming heals)
                healPrediction = {
                    enabled = false,
                    color = { 0.2, 1, 0.2 },
                    opacity = 0.5,
                },
                -- Castbar
                castbar = {
                    enabled = true,
                    showIcon = true,
                    width = 245,
                    height = 25,
                    offsetX = 0,
                    offsetY = 0,
                    widthAdjustment = 0,
                    fontSize = 14,
                    color = {0.2, 0.6, 1, 1},
                    anchor = "unitframe",
                    texture = "Quazii v5",
                    bgColor = {0.149, 0.149, 0.149, 1},
                    borderSize = 1,
                    highlightInterruptible = true,
                    interruptibleColor = {0.2, 0.8, 0.2, 1},
                    maxLength = 12,
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 26,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 18,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                    -- Duration text
                    iconSpacing = 2,
                    buffSpacing = 2,
                    debuffSpacing = 2,
                    durationColor = {1, 1, 1, 1},
                    showDuration = false,
                    durationSize = 12,
                    durationAnchor = "CENTER",
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    -- Stack text
                    stackColor = {1, 1, 1, 1},
                    showStack = true,
                    stackSize = 10,
                    stackAnchor = "BOTTOMRIGHT",
                    stackOffsetX = -1,
                    stackOffsetY = 1,
                    -- Buff duration/stack
                    buffDuration = { show = true, fontSize = 12, anchor = "CENTER", offsetX = 0, offsetY = 0, color = {1, 1, 1, 1} },
                    buffStack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = {1, 1, 1, 1} },
                    buffShowStack = true,
                    buffStackSize = 10,
                    buffStackAnchor = "BOTTOMRIGHT",
                    buffStackOffsetX = -1,
                    buffStackOffsetY = 1,
                    buffStackColor = {1, 1, 1, 1},
                    -- Debuff duration/stack
                    debuffDuration = { show = false, fontSize = 10, anchor = "CENTER", offsetX = 0, offsetY = 0, color = {1, 1, 1, 1} },
                    debuffStack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = {1, 1, 1, 1} },
                    debuffShowStack = true,
                    debuffStackSize = 10,
                    debuffStackAnchor = "BOTTOMRIGHT",
                    debuffStackOffsetX = -1,
                    debuffStackOffsetY = 1,
                    debuffStackColor = {1, 1, 1, 1},
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,
                    size = 20,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 8,
                },
                -- Leader/Assistant icon (crown for leader, flag for assistant)
                leaderIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "TOPLEFT",
                    xOffset = -8,
                    yOffset = 8,
                },
            },
            -- Target of Target
            targettarget = {
                enabled = false,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 160,
                height = 30,
                offsetX = 496,
                offsetY = -214,
                texture = "Quazii",
                useClassColor = true,
                useHostilityColor = true,  -- Use red/yellow/green based on unit hostility
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 14,
                nameAnchor = "LEFT",
                nameOffsetX = 4,
                nameOffsetY = 0,
                maxNameLength = 0,
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = false,
                healthDisplayStyle = "percent",
                healthDivider = " | ",
                healthFontSize = 14,
                healthAnchor = "RIGHT",
                healthOffsetX = -4,
                healthOffsetY = 0,
                healthTextUseClassColor = false,
                healthTextColor = { 1, 1, 1, 1 },
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",
                powerTextUsePowerColor = true,
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 10,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -4,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = false,
                powerBarHeight = 3,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1, 1 },
                    opacity = 0.7,
                    texture = "QUI Stripes",
                },
                -- Castbar
                castbar = {
                    enabled = false,
                    showIcon = true,
                    width = 50,
                    height = 12,
                    offsetX = 0,
                    offsetY = -20,
                    widthAdjustment = 0,
                    fontSize = 10,
                    color = {1, 0.7, 0, 1},
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 22,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 22,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,    -- Disabled by default for ToT (small frame)
                    size = 16,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 6,
                },
            },
            -- Pet frame
            pet = {
                enabled = true,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 140,
                height = 25,
                offsetX = -340,
                offsetY = -254,
                texture = "Quazii",
                useClassColor = true,
                useHostilityColor = true,
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 10,
                nameAnchor = "LEFT",
                nameOffsetX = 4,
                nameOffsetY = 0,
                maxNameLength = 0,
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = false,
                healthDisplayStyle = "percent",
                healthDivider = " | ",
                healthFontSize = 10,
                healthAnchor = "RIGHT",
                healthOffsetX = -4,
                healthOffsetY = 0,
                healthTextUseClassColor = false,
                healthTextColor = { 1, 1, 1, 1 },
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",
                powerTextUsePowerColor = true,
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 10,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -4,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = true,
                powerBarHeight = 3,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1 },
                    opacity = 0.7,
                    texture = "QUI Stripes",
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 22,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 22,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,    -- Disabled by default for pet (rarely marked)
                    size = 16,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 6,
                },
                -- Castbar (opt-in for vehicle/RP casts)
                castbar = {
                    enabled = false,  -- Disabled by default (opt-in feature)
                    showIcon = true,
                    width = 140,
                    height = 15,
                    offsetX = 0,
                    offsetY = -20,
                    widthAdjustment = 0,
                    fontSize = 10,
                    color = {0.404, 1, 0.984, 1},
                },
            },
            -- Focus frame
            focus = {
                enabled = false,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 160,
                height = 30,
                offsetX = -496,
                offsetY = -214,
                texture = "Quazii v5",
                useClassColor = true,
                useHostilityColor = true,  -- Use red/yellow/green based on unit hostility
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Portrait
                showPortrait = false,
                portraitSide = "RIGHT",
                portraitSize = 30,
                portraitBorderSize = 1,
                portraitBorderUseClassColor = false,
                portraitBorderColor = { 0, 0, 0, 1 },
                portraitGap = 0,
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 14,
                nameAnchor = "LEFT",
                nameOffsetX = 4,
                nameOffsetY = 0,
                maxNameLength = 0,
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = true,
                healthDisplayStyle = "percent",
                healthDivider = " | ",
                healthFontSize = 14,
                healthAnchor = "RIGHT",
                healthOffsetX = -4,
                healthOffsetY = 0,
                healthTextUseClassColor = false,
                healthTextColor = { 1, 1, 1, 1 },
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",
                powerTextUsePowerColor = true,
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 10,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -4,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = true,
                powerBarHeight = 3,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1, 1 },
                    opacity = 0.7,
                    texture = "QUI Stripes",
                },
                -- Castbar
                castbar = {
                    enabled = true,
                    showIcon = false,
                    width = 160,
                    height = 20,
                    offsetX = 0,
                    offsetY = 0,
                    widthAdjustment = 0,
                    fontSize = 14,
                    color = {0.2, 0.6, 1, 1},
                    anchor = "unitframe",
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 20,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 16,
                    debuffOffsetX = 0,
                    debuffOffsetY = 2,
                    -- Buff settings
                    buffIconSize = 20,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 16,
                    buffOffsetX = 0,
                    buffOffsetY = -2,
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,
                    size = 18,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 6,
                },
                -- Leader/Assistant icon (crown for leader, flag for assistant)
                leaderIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "TOPLEFT",
                    xOffset = -8,
                    yOffset = 8,
                },
            },
            -- Boss frames
            boss = {
                enabled = true,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 162,
                height = 36,
                offsetX = 974,
                offsetY = 106,
                spacing = 35,           -- Vertical spacing between boss frames
                texture = "Quazii v5",
                useClassColor = true,
                useHostilityColor = true,
                customHealthColor = { 0.6, 0.2, 0.2, 1 },
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 11,
                nameAnchor = "LEFT",
                nameOffsetX = 4,
                nameOffsetY = 0,
                maxNameLength = 0,
                -- Health text
                showHealth = true,
                healthDisplayStyle = "both",
                healthDivider = " | ",
                healthFontSize = 11,
                healthAnchor = "RIGHT",
                healthOffsetX = -4,
                healthOffsetY = 0,
                healthTextUseClassColor = false,
                healthTextColor = { 1, 1, 1, 1 },
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",
                powerTextUsePowerColor = true,
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 10,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -4,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = true,
                powerBarHeight = 3,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1 },
                    opacity = 0.7,
                    texture = "QUI Stripes",
                },
                -- Castbar
                castbar = {
                    enabled = true,
                    showIcon = true,
                    width = 162,
                    height = 16,
                    offsetX = 0,
                    offsetY = 0,
                    widthAdjustment = 0,
                    fontSize = 11,
                    color = {1, 0.7, 0, 1},
                    anchor = "unitframe",
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 22,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 22,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,
                    size = 20,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 8,
                },
            },
        },
        unitFrames = {
            enabled = true,
            General = {
                Font = "Quazii",
                FontFlag = "OUTLINE",
                FontShadows = {
                    Color = {0, 0, 0, 0},
                    OffsetX = 0,
                    OffsetY = 0
                },
                ForegroundTexture = "Quazii_v5",
                BackgroundTexture = "Solid",
                -- Dark Mode: overrides class colors on unit frame health bars (not resource bars)
                DarkMode = {
                    Enabled = false,
                    ForegroundColor = {0.15, 0.15, 0.15, 1},  -- Very dark for health bar
                    BackgroundColor = {0.25, 0.25, 0.25, 1},  -- Slightly lighter for background
                    UseSolidTexture = true,  -- Force solid texture when dark mode is enabled
                },
                CustomColors = {
                    Reaction = {
                        [1] = {204/255, 64/255, 64/255},    -- Hated
                        [2] = {204/255, 64/255, 64/255},    -- Hostile
                        [3] = {204/255, 128/255, 64/255},   -- Unfriendly
                        [4] = {255/255, 234/255, 126/255},   -- Neutral
                        [5] = {64/255, 204/255, 64/255},    -- Friendly
                        [6] = {64/255, 204/255, 64/255},    -- Honored
                        [7] = {64/255, 204/255, 64/255},    -- Revered
                        [8] = {64/255, 204/255, 64/255},    -- Exalted
                    },
                    Power = {
                        [0] = {0, 0.50, 1},            -- Mana
                        [1] = {1, 0, 0},            -- Rage
                        [2] = {1, 0.5, 0.25},       -- Focus
                        [3] = {1, 1, 0},            -- Energy
                        [6] = {0, 0.82, 1},         -- Runic Power
                        [8] = {0.3, 0.52, 0.9},     -- Lunar Power
                        [11] = {0, 0.5, 1},         -- Maelstrom
                        [13] = {0.4, 0, 0.8},       -- Insanity
                        [17] = {0.79, 0.26, 0.99},  -- Fury
                        [18] = {1, 0.61, 0}         -- Pain
                    },
                },
            },
            player = {
                Enabled = true,
                Frame = {
                    Width = 244,
                    Height = 42,
                    AnchorFrom = "CENTER",
                    AnchorTo = "CENTER",
                    Texture = "Quazii",
                    ClassColor = true,
                    ReactionColor = false,
                    FGColor = {26/255, 26/255, 26/255, 1.0},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                PowerBar = {
                    Enabled = true,
                    Height = 2,
                    ColorByType = true,
                    ColorBackgroundByType = false,
                    FGColor = {8/255, 8/255, 8/255, 0.8},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                Tags = {
                    Name = {
                        Enabled = true,
                        AnchorFrom = "LEFT",
                        AnchorTo = "LEFT",
                        OffsetX = 3,
                        OffsetY = 0,
                        FontSize = 14,
                        Color = {1, 1, 1, 1},
                        ColorByStatus = false,
                    },
                    Health = {
                        Enabled = true,
                        AnchorFrom = "RIGHT",
                        AnchorTo = "RIGHT",
                        OffsetX = -3,
                        OffsetY = 0,
                        FontSize = 14,
                        Color = {1, 1, 1, 1},
                        DisplayPercent = true,
                    },
                    Power = {
                        Enabled = false,
                        AnchorFrom = "BOTTOMRIGHT",
                        AnchorTo = "BOTTOMRIGHT",
                        OffsetX = -4,
                        OffsetY = 4,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                    },
                },
                Absorb = {
                    Enabled = true,
                    Color = {0, 1, 0.96, 0.2},  -- #00FFF5 (cyan) with 20% opacity
                },
            },
            target = {
                Enabled = true,
                Frame = {
                    Width = 244,
                    Height = 42,
                    AnchorFrom = "CENTER",
                    AnchorTo = "CENTER",
                    Texture = "Quazii",
                    ClassColor = true,
                    ReactionColor = true,
                    FGColor = {26/255, 26/255, 26/255, 1.0},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                PowerBar = {
                    Enabled = true,
                    Height = 2,
                    ColorByType = true,
                    ColorBackgroundByType = false,
                    FGColor = {8/255, 8/255, 8/255, 0.8},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                Tags = {
                    Name = {
                        Enabled = true,
                        AnchorFrom = "LEFT",
                        AnchorTo = "LEFT",
                        OffsetX = 3,
                        OffsetY = 0,
                        FontSize = 14,
                        Color = {1, 1, 1, 1},
                        ColorByStatus = false,
                    },
                    Health = {
                        Enabled = true,
                        AnchorFrom = "RIGHT",
                        AnchorTo = "RIGHT",
                        OffsetX = -3,
                        OffsetY = 0,
                        FontSize = 14,
                        Color = {1, 1, 1, 1},
                        DisplayPercent = true,
                    },
                    Power = {
                        Enabled = false,
                        AnchorFrom = "BOTTOMRIGHT",
                        AnchorTo = "BOTTOMRIGHT",
                        OffsetX = -4,
                        OffsetY = 4,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                    },
                },
                Auras = {
                    Width = 0,  -- 0 = use frame width
                    Height = 18,
                    Scale = 2.5,
                    Alpha = 1,
                    RowLimit = 0,  -- 0 = unlimited
                    -- Border settings (applies to both buffs and debuffs)
                    BorderSize = 1,
                    BorderColor = {0, 0, 0, 1},  -- Black border
                    -- Debuff settings
                    ShowDebuffs = true,
                    DebuffOffsetX = 0,
                    DebuffOffsetY = 2,
                    -- Buff settings
                    ShowBuffs = true,
                    BuffOffsetX = 0,
                    BuffOffsetY = 40,
                },
                Absorb = {
                    Enabled = true,
                    Color = {0, 1, 0.96, 0.2},  -- #00FFF5 (cyan) with 20% opacity
                },
            },
            targettarget = {
                Enabled = true,
                Frame = {
                    Width = 122,
                    Height = 21,
                    XPosition = 183.1,
                    YPosition = -10,
                    AnchorFrom = "CENTER",
                    AnchorParent = "QUICore_Target",
                    AnchorTo = "CENTER",
                    Texture = "Quazii",
                    ClassColor = true,
                    ReactionColor = true,
                    FGColor = {26/255, 26/255, 26/255, 1.0},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                Tags = {
                    Name = {
                        Enabled = true,
                        AnchorFrom = "CENTER",
                        AnchorTo = "CENTER",
                        OffsetX = 0,
                        OffsetY = 0,
                        FontSize = 14,
                        Color = {1, 1, 1, 1},
                        ColorByStatus = false,
                    },
                    Health = {
                        Enabled = false,
                        AnchorFrom = "RIGHT",
                        AnchorTo = "RIGHT",
                        OffsetX = -3,
                        OffsetY = 0,
                        FontSize = 14,
                        Color = {1, 1, 1, 1},
                        DisplayPercent = true,
                    },
                },
            },
            pet = {
                Enabled = true,
                Frame = {
                    Width = 244,
                    Height = 21,
                    AnchorFrom = "CENTER",
                    AnchorTo = "CENTER",
                    Texture = "Quazii",
                    ClassColor = true,
                    ReactionColor = false,
                    FGColor = {26/255, 26/255, 26/255, 1.0},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                Tags = {
                    Name = {
                        Enabled = true,
                        AnchorFrom = "CENTER",
                        AnchorTo = "CENTER",
                        OffsetX = 0,
                        OffsetY = 0,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                        ColorByStatus = false,
                    },
                    Health = {
                        Enabled = false,
                        AnchorFrom = "RIGHT",
                        AnchorTo = "RIGHT",
                        OffsetX = -3,
                        OffsetY = 0,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                        DisplayPercent = true,
                    },
                    Power = {
                        Enabled = false,
                        AnchorFrom = "BOTTOMRIGHT",
                        AnchorTo = "BOTTOMRIGHT",
                        OffsetX = -4,
                        OffsetY = 4,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                    },
                },
            },
            focus = {
                Enabled = true,
                Frame = {
                    Width = 122,
                    Height = 21,
                    AnchorFrom = "CENTER",
                    AnchorTo = "CENTER",
                    Texture = "Quazii",
                    ClassColor = true,
                    ReactionColor = true,
                    FGColor = {26/255, 26/255, 26/255, 1.0},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                PowerBar = {
                    Enabled = true,
                    Height = 2,
                    ColorByType = true,
                    ColorBackgroundByType = true,
                    FGColor = {8/255, 8/255, 8/255, 0.8},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                Tags = {
                    Name = {
                        Enabled = true,
                        AnchorFrom = "CENTER",
                        AnchorTo = "CENTER",
                        OffsetX = 0,
                        OffsetY = 0,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                        ColorByStatus = false,
                    },
                    Health = {
                        Enabled = false,
                        AnchorFrom = "RIGHT",
                        AnchorTo = "RIGHT",
                        OffsetX = -3,
                        OffsetY = 0,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                        DisplayPercent = true,
                    },
                    Power = {
                        Enabled = false,
                        AnchorFrom = "BOTTOMRIGHT",
                        AnchorTo = "BOTTOMRIGHT",
                        OffsetX = -4,
                        OffsetY = 4,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                    },
                },
            },
            focus = {
                Enabled = true,
                Frame = {
                    Width = 122,
                    Height = 21,
                    AnchorFrom = "CENTER",
                    AnchorTo = "CENTER",
                    ClassColor = true,
                    ReactionColor = true,
                    FGColor = {26/255, 26/255, 26/255, 1.0},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                PowerBar = {
                    Enabled = true,
                    Height = 2,
                    ColorByType = true,
                    ColorBackgroundByType = true,
                    FGColor = {8/255, 8/255, 8/255, 0.8},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                Tags = {
                    Name = {
                        Enabled = true,
                        AnchorFrom = "CENTER",
                        AnchorTo = "CENTER",
                        OffsetX = 0,
                        OffsetY = 0,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                        ColorByStatus = false,
                    },
                    Health = {
                        Enabled = false,
                        AnchorFrom = "RIGHT",
                        AnchorTo = "RIGHT",
                        OffsetX = -3,
                        OffsetY = 0,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                        DisplayPercent = true,
                    },
                    Power = {
                        Enabled = false,
                        AnchorFrom = "BOTTOMRIGHT",
                        AnchorTo = "BOTTOMRIGHT",
                        OffsetX = -4,
                        OffsetY = 4,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                    },
                },
            },
            boss = {
                Enabled = true,
                Frame = {
                    Width = 200,
                    Height = 36,
                    XPosition = 350,
                    YPosition = 0,
                    AnchorFrom = "LEFT",
                    AnchorParent = "QUICore_Target",
                    AnchorTo = "RIGHT",
                    Texture = "Quazii",
                    ClassColor = true,
                    ReactionColor = true,
                    FGColor = {26/255, 26/255, 26/255, 1.0},
                    BGColor = {45/255, 45/255, 45/255, 1.0},
                },
                Tags = {
                    Name = {
                        Enabled = true,
                        AnchorFrom = "LEFT",
                        AnchorTo = "LEFT",
                        OffsetX = 4,
                        OffsetY = 0,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                        ColorByClass = false,
                        ColorByStatus = true,
                    },
                    Health = {
                        Enabled = true,
                        AnchorFrom = "RIGHT",
                        AnchorTo = "RIGHT",
                        OffsetX = -4,
                        OffsetY = 0,
                        FontSize = 12,
                        Color = {1, 1, 1, 1},
                    },
                },
            },
        },
        -- Config Panel Scale, Width, and Alpha (for the settings UI, not the in-game HUD)
        configPanelScale = 1.0,
        configPanelWidth = 750,
        configPanelAlpha = 0.97,

        -- Addon Accent Color (drives options panel theme + default fallback for skinned elements)
        addonAccentColor = {0.204, 0.827, 0.6, 1},  -- #34D399 Mint

        -- Combat Text Indicator
        combatText = {
            enabled = true,
            displayTime = 0.8,    -- Time text is visible before fade starts (seconds)
            fadeTime = 0.3,       -- Fade animation duration (seconds)
            fontSize = 14,        -- Text size
            xOffset = 0,          -- Horizontal offset from screen center
            yOffset = 0,          -- Vertical offset from screen center (positive = above)
            enterCombatColor = {1, 0.98, 0.2, 1},      -- +Combat text color (#FFFA33 yellow)
            leaveCombatColor = {1, 0.98, 0.2, 1},      -- -Combat text color (#FFFA33 yellow)
        },

        -- Battle Res Counter (displays brez charges and timer)
        brzCounter = {
            enabled = true,
            width = 50,
            height = 50,
            fontSize = 14,
            timerFontSize = 12,
            xOffset = 500,
            yOffset = -50,
            showBackdrop = true,
            backdropColor = { 0, 0, 0, 0.6 },
            textColor = { 1, 1, 1, 1 },
            timerColor = { 1, 1, 1, 1 },
            noChargesColor = { 1, 0.3, 0.3, 1 },
            hasChargesColor = { 0.3, 1, 0.3, 1 },
            useClassColorText = false,
            borderSize = 1,
            hideBorder = false,
            borderColor = { 0, 0, 0, 1 },
            useClassColorBorder = false,
            useAccentColorBorder = false,
            borderTexture = "None",
            useCustomFont = false,
            font = nil,
        },

        -- Combat Timer (displays elapsed combat time)
        combatTimer = {
            enabled = false,       -- Opt-in feature (disabled by default)
            xOffset = 0,           -- Horizontal offset from screen center
            yOffset = -150,        -- Vertical offset (below center by default)
            width = 80,            -- Frame width
            height = 30,           -- Frame height
            fontSize = 16,         -- Font size for timer text
            useCustomFont = false, -- If false, use global addon font
            font = "Quazii",       -- Font name (from LibSharedMedia)
            useClassColorText = false,  -- If true, use player class color for text
            textColor = {1, 1, 1, 1},  -- White text
            -- Backdrop settings
            showBackdrop = true,
            backdropColor = {0, 0, 0, 0.6},  -- Semi-transparent black
            -- Border settings
            borderSize = 1,
            borderTexture = "None", -- Border texture from LibSharedMedia (or "None" for solid)
            useClassColorBorder = false,  -- If true, use player class color
            useAccentColorBorder = false,  -- If true, use addon accent color
            borderColor = {0, 0, 0, 1},  -- Black border
            hideBorder = false,  -- If true, hide border completely (overrides other border settings)
            onlyShowInEncounters = false,  -- If true, only show during boss encounters (not general combat)
        },

        -- Cooldown Manager Effects
        cooldownSwipe = {
            showBuffSwipe = false,      -- Buff/aura duration swipe (Essential/Utility)
            showBuffIconSwipe = false,  -- BuffIcon viewer swipe (opt-in)
            showGCDSwipe = false,       -- GCD swipe (~1.5s)
            showCooldownSwipe = false,  -- Actual spell cooldown swipe
            showRechargeEdge = false,   -- Yellow edge on multi-charge abilities
            showActionSwipe = true,     -- Action bar cooldown swipe
            showNcdmSwipe = true,       -- NCDM cooldown swipe
            showCustomTrackerSwipe = true, -- Custom tracker cooldown swipe
            migratedToV2 = true,        -- Migration marker from old hideEssential/hideUtility
        },
        cooldownEffects = {
            hideEssential = true,
            hideUtility = true,
        },
        cooldownManager = {
            -- hideSwipe removed - now handled by cooldownSwipe
        },
        
        -- Custom Glow Settings (for Essential/Utility cooldown viewers)
        customGlow = {
            -- Essential Cooldowns
            essentialEnabled = true,
            essentialGlowType = "Pixel Glow",  -- "Pixel Glow", "Autocast Shine", "Button Glow"
            essentialColor = {0.95, 0.95, 0.32, 1},  -- Default yellow/gold
            essentialLines = 14,       -- Number of lines for Pixel Glow / spots for Autocast Shine
            essentialFrequency = 0.25, -- Animation speed
            essentialLength = nil,     -- nil = auto-calculate based on icon size
            essentialThickness = 2,    -- Line thickness for Pixel Glow
            essentialScale = 1,        -- Scale for Autocast Shine
            essentialXOffset = 0,
            essentialYOffset = 0,

            -- Utility Cooldowns
            utilityEnabled = true,
            utilityGlowType = "Pixel Glow",
            utilityColor = {0.95, 0.95, 0.32, 1},
            utilityLines = 14,
            utilityFrequency = 0.25,
            utilityLength = nil,
            utilityThickness = 2,
            utilityScale = 1,
            utilityXOffset = 0,
            utilityYOffset = 0,
        },
        
        -- Buff/Debuff Visuals
        buffBorders = {
            enableBuffs = true,
            enableDebuffs = true,
            borderSize = 2,
            fontSize = 12,
            fontOutline = true,
        },
        
        -- QUI Autohides
        uiHider = {
            hideObjectiveTrackerAlways = false,  -- Hide Objective Tracker always
            hideObjectiveTrackerInstanceTypes = {
                mythicPlus = false,
                mythicDungeon = false,
                normalDungeon = false,
                heroicDungeon = false,
                followerDungeon = false,
                raid = false,
                pvp = false,
                arena = false,
            },
            hideMinimapBorder = true,
            hideTimeManager = true,
            hideGameTime = true,
            hideMinimapTracking = true,
            hideRaidFrameManager = true,
            hideMinimapZoneText = true,
            hideBuffCollapseButton = true,
            hideFriendlyPlayerNameplates = true,
            hideFriendlyNPCNameplates = true,
            hideTalkingHead = true,
            muteTalkingHead = false,
            hideErrorMessages = false,
            hideMinimapZoomButtons = true,
            hideWorldMapBlackout = true,
            hideTalkingHeadFrame = true,
            hideXPAtMaxLevel = false,
            hideExperienceBar = false,
            hideReputationBar = false,
            hideMainActionBarArt = false,
        },
        
        -- Minimap Settings
        minimap = {
            enabled = true,  -- Enabled by default for clean minimap experience
            
            -- Shape and Size
            shape = "SQUARE",  -- SQUARE or ROUND
            size = 160,
            scale = 1.0,  -- Scale multiplier for minimap frame
            borderSize = 2,
            borderColor = {0, 0, 0, 1},  -- Black border
            useClassColorBorder = false,
            useAccentColorBorder = false,
            buttonRadius = 2,  -- LibDBIcon button radius for square minimap
            
            -- Position
            lock = false,  -- Unlocked by default so users can position it
            position = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 790, y = 285 },
            
            -- Features
            autoZoom = false,  -- Auto zoom out after 10 seconds
            hideAddonButtons = true,  -- Show addon buttons on hover only
            
            -- Button Visibility
            showZoomButtons = false,
            showMail = false,
            showCraftingOrder = false,
            showAddonCompartment = false,
            showDifficulty = false,
            showMissions = false,
            showCalendar = true,
            showTracking = false,

            -- Dungeon Eye (LFG Queue Status Button) - repositions to minimap when in queue
            dungeonEye = {
                enabled = true,
                corner = "BOTTOMLEFT",
                scale = 0.6,
                offsetX = 0,
                offsetY = 0,
            },

            -- Clock (anchored top-left) - disabled by default, user can enable
            showClock = false,
            clockConfig = {
                offsetX = 0,
                offsetY = 0,
                align = "LEFT",
                font = "Quazii",
                fontSize = 12,
                monochrome = false,
                outline = "OUTLINE",
                color = {1, 1, 1, 1},
                useClassColor = false,
                timeFormat = "local",  -- "local" or "server"
            },
            
            -- Coordinates (anchored top-right)
            showCoords = false,
            coordPrecision = "%d,%d",  -- %d,%d = normal, %.1f,%.1f = high, %.2f,%.2f = very high
            coordUpdateInterval = 1,  -- Update every 1 second
            coordsConfig = {
                offsetX = 0,
                offsetY = 0,
                align = "RIGHT",
                font = "Quazii",
                fontSize = 12,
                monochrome = false,
                outline = "OUTLINE",
                color = {1, 1, 1, 1},
                useClassColor = false,
            },
            
            -- Zone Text (anchored top-center)
            showZoneText = true,
            zoneTextConfig = {
                offsetX = 0,
                offsetY = 0,
                align = "CENTER",
                font = "Quazii",
                fontSize = 12,
                allCaps = false,
                monochrome = false,
                outline = "OUTLINE",
                useClassColor = false,
                colorNormal = {1, 0.82, 0, 1},      -- Gold
                colorSanctuary = {0.41, 0.8, 0.94, 1},  -- Light blue
                colorArena = {1.0, 0.1, 0.1, 1},    -- Red
                colorFriendly = {0.1, 1.0, 0.1, 1}, -- Green
                colorHostile = {1.0, 0.1, 0.1, 1},  -- Red
                colorContested = {1.0, 0.7, 0.0, 1}, -- Orange
            },
        },
        
        -- Minimap Button (LibDBIcon) - separate from minimap module
        minimapButton = {
            hide = false,
            minimapPos = 180,  -- 9 o'clock position (left side)
        },
        
        -- Datatext Panel (fixed below minimap - slot-based architecture)
        datatext = {
            enabled = true,
            slots = {"fps", "durability", "time"},  -- 3 configurable datatext slots

            -- Per-slot configuration (shortLabel, noLabel, xOffset, yOffset)
            slot1 = { shortLabel = false, noLabel = false, xOffset = -1, yOffset = 0 },
            slot2 = { shortLabel = false, noLabel = false, xOffset = 6, yOffset = 0 },
            slot3 = { shortLabel = true, noLabel = false, xOffset = 3, yOffset = 0 },

            forceSingleLine = true,  -- If true, ignores wrapping and forces single line
            
            -- Panel Settings (width auto-matches minimap)
            height = 22,
            offsetY = 0,  -- Y offset from minimap bottom
            bgOpacity = 60,  -- 0-100
            borderSize = 2,  -- Border thickness (0-8, 0=hidden)
            borderColor = {0, 0, 0, 1},  -- Black border (#90)

            -- Font Settings
            font = "Quazii",
            fontSize = 13,
            fontOutline = "OUTLINE",  -- "OUTLINE" = Thin

            -- Color Settings
            useClassColor = false,
            valueColor = {0.1, 1.0, 0.1, 1},  -- #1AFF1A green
            
            -- Separator
            separator = "  ",
            
            -- Legacy Composite Mode Toggles
            showFPS = true,
            showLatency = false,
            showDurability = true,
            showGold = false,
            showTime = true,
            showCoords = false,
            showFriends = false,
            showGuild = false,
            showLootSpec = false,
            
            -- Time Settings (for Time datatext or legacy mode)
            timeFormat = "local",  -- "local" or "server"
            use24Hour = true,
            useLocalTime = true,  -- For datatext registry
            lockoutCacheMinutes = 5,  -- minutes between lockout data refresh (min 1)

            -- Social datatext settings
            showTotal = true,  -- Show total count (friends/guild)
            showGuildName = false,  -- Show guild name in text

            -- Player Spec datatext settings
            specDisplayMode = "full",  -- "icon" = icon only, "loadout" = icon + loadout, "full" = icon + spec/loadout

            -- System datatext settings (combined FPS + Latency)
            system = {
                latencyType = "home",      -- "home" or "world" latency on main display
                showLatency = true,        -- Show Home/World latency in tooltip
                showProtocols = true,      -- Show IPv4/IPv6 protocols in tooltip
                showBandwidth = true,      -- Show bandwidth/download % when downloading
                showAddonMemory = true,    -- Show addon memory usage in tooltip
                addonCount = 10,           -- Number of addons to show (sorted by memory)
                showFpsStats = true,       -- Show FPS avg/low/high when Shift held
            },

            -- Volume datatext settings
            volume = {
                volumeStep = 5,            -- Volume change per scroll (1-20)
                controlType = "master",    -- Which volume to control: "master", "music", "sfx", "ambience", "dialog"
                showIcon = false,          -- Show speaker icon instead of "Vol:" label
            },
        },
        
        -- Additional Datapanels (user-created, independent of minimap)
        quiDatatexts = {
            panels = {},  -- Array of panel configurations
        },

        -- Custom Tracker Bars (consumables, trinkets, custom spells)
        customTrackers = {
            bars = {
                {
                    id = "default_tracker_1",
                    name = "Trinket & Pot",
                    enabled = false,
                    locked = false,
                    -- Position (offset from screen center, use snap buttons to align to player)
                    offsetX = -406,
                    offsetY = -152,
                    -- Layout
                    growDirection = "RIGHT",
                    iconSize = 28,
                    spacing = 4,
                    borderSize = 2,
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    -- Duration text
                    durationSize = 13,
                    durationColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    hideDurationText = false,
                    -- Stack text
                    stackSize = 9,
                    stackColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                    stackOffsetX = 3,
                    stackOffsetY = -1,
                    hideStackText = false,
                    showItemCharges = true,  -- Show item charges (e.g., Healthstone 3 charges) instead of item count
                    -- Background
                    bgOpacity = 0,
                    bgColor = {0, 0, 0, 1},
                    hideGCD = true,
                    hideNonUsable = false,
                    showOnlyOnCooldown = false,
                    showOnlyWhenActive = false,
                    showOnlyWhenOffCooldown = false,
                    showOnlyInCombat = false,
                    -- Click behavior
                    clickableIcons = false,  -- Allow clicking icons to use items/cast spells
                    -- Active state (buff/cast/channel display)
                    showActiveState = true,
                    activeGlowEnabled = true,
                    activeGlowType = "Pixel Glow",
                    activeGlowColor = {1, 0.85, 0.3, 1},
                    -- Pre-populated with Algari Healing Potion
                    entries = {
                        { type = "item", id = 224022 },
                    },
                },
            },
            -- Global keybind settings for custom trackers
            keybinds = {
                showKeybinds = false,
                keybindTextSize = 12,
                keybindTextColor = { 1, 0.82, 0, 1 },  -- Gold
                keybindOffsetX = 2,
                keybindOffsetY = -2,
            },
            -- CDM buff tracking (trinket proc detection)
            cdmBuffTracking = {
                trinketData = {},
                learnedBuffs = {},
            },
        },

        -- Shaman Totem Bar (active totem display)
        totemBar = {
            enabled = false,
            locked = false,
            offsetX = 0,
            offsetY = -200,
            growDirection = "RIGHT",
            iconSize = 36,
            spacing = 4,
            borderSize = 2,
            zoom = 0,
            durationSize = 13,
            durationColor = {1, 1, 1, 1},
            durationAnchor = "CENTER",
            durationOffsetX = 0,
            durationOffsetY = 0,
            hideDurationText = false,
            showSwipe = true,
            swipeColor = {0, 0, 0, 0.6},
        },

        -- HUD Layering: Control frame level ordering for HUD elements
        -- Higher values appear above lower values (range 0-10)
        hudLayering = {
            -- CDM viewers (default 5 - middle)
            essential = 5,
            utility = 5,
            buffIcon = 5,
            buffBar = 5,
            -- Power bars (higher defaults so text visible above CDM)
            primaryPowerBar = 7,
            secondaryPowerBar = 6,
            -- Unit frames (lower defaults, background elements)
            playerFrame = 4,
            playerIndicators = 6,  -- Above player frame for visibility
            targetFrame = 4,
            totFrame = 3,
            petFrame = 3,
            focusFrame = 4,
            bossFrames = 4,
            -- Castbars (middle)
            playerCastbar = 5,
            targetCastbar = 5,
            -- Custom trackers
            customBars = 5,
            -- Totem bar
            totemBar = 5,
        },
    },
    -- Account-wide storage (shared across all characters)
    global = {
        -- Gold tracking per character (realm-name = copper)
        goldData = {},
        -- Spell Scanner: cross-character spell/item duration mappings
        spellScanner = {
            spells = {},   -- [castSpellID] = { buffSpellID, duration, icon, name, scannedAt }
            items = {},    -- [itemID] = { useSpellID, buffSpellID, duration, icon, name, scannedAt }
            autoScan = false,  -- Auto-scan setting (off by default)
        },
    },
    char = {
        keybindOverrides = {},  -- [specID] = { [spellID] = keybindText, [-itemID] = keybindText }
    },
}

function QUICore:OnInitialize()
    -- Migrate old QuaziiUIDB to QUIDB if needed
    if QuaziiUIDB and not QUIDB then
        QUIDB = QuaziiUIDB
    end

    self.db = LibStub("AceDB-3.0"):New("QUIDB", defaults, true)
    QUI.db = self.db  -- Make database accessible to other QUI modules

    -- Migrate visibility settings to SHOW logic
    -- Old hideWhenX → new showX (semantic conversion)
    -- hideOutOfCombat=true → showInCombat=true (user wants combat-only)
    -- hideWhenNotInGroup=true → showInGroup=true (user wants group-only)
    -- hideWhenNotInInstance=true → showInInstance=true (user wants instance-only)
    -- hideWhenMounted has no equivalent (can't express "hide when mounted" in SHOW logic)
    local profile = self.db.profile

    -- Migrate legacy skin accent color into addonAccentColor
    if profile.general and profile.general.skinCustomColor and not profile.general.addonAccentColor then
        if type(profile.general.skinCustomColor) == "table" then
            profile.general.addonAccentColor = { unpack(profile.general.skinCustomColor) }
        else
            profile.general.addonAccentColor = profile.general.skinCustomColor
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

    -- Migrate from old classHud table (pre-split)
    if profile.classHud then
        if not profile.cdmVisibility then
            profile.cdmVisibility = {}
        end
        if not profile.unitframesVisibility then
            profile.unitframesVisibility = {}
        end
        -- Copy hideOutOfCombat → showInCombat for both
        if profile.classHud.hideOutOfCombat then
            profile.cdmVisibility.showInCombat = true
            profile.unitframesVisibility.showInCombat = true
        end
        -- Preserve fade duration
        profile.cdmVisibility.fadeDuration = profile.cdmVisibility.fadeDuration or profile.classHud.fadeDuration or 0.2
        profile.unitframesVisibility.fadeDuration = profile.unitframesVisibility.fadeDuration or profile.classHud.fadeDuration or 0.2
        profile.classHud = nil
    end

    -- Migrate recently-added hideWhenX keys to showX (if user reloaded after first implementation)
    migrateToShowLogic(profile.cdmVisibility)
    migrateToShowLogic(profile.unitframesVisibility)

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
    self:RegisterChatCommand("quicorerefresh", "ForceRefreshBuffIcons")

    -- Defer minimap button creation to reduce load-time CPU
    C_Timer.After(0.1, function()
        self:CreateMinimapButton()
    end)
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
    if inChallengeMode then
        -- We're in a challenge mode dungeon - skip profile changes entirely during M+
        -- The protected state during keystone activation doesn't play nice with SetScale
        -- Profile will be applied correctly on next /reload or when leaving the dungeon
        return
    end

    -- Skip if "switching" to the same profile (happens during M+ entry false events)
    -- LibDualSpec triggers profile switch even when already on correct profile
    local currentProfile = self.db:GetCurrentProfile()
    if profileKey == self._lastKnownProfile and profileKey == currentProfile then
        return  -- No actual change happening - skip all UI modifications
    end
    self._lastKnownProfile = profileKey

    -- Update spec tracking (kept for reference)
    self._lastKnownSpec = GetSpecialization() or 0

    -- Helper to apply UIParent scale safely (defers if in combat or protected state)
    local function ApplyUIScale(scale)
        if InCombatLockdown() then
            QUICore._pendingUIScale = scale
            if not QUICore._scaleRegenFrame then
                QUICore._scaleRegenFrame = CreateFrame("Frame")
                QUICore._scaleRegenFrame:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    if QUICore._pendingUIScale and not InCombatLockdown() then
                        pcall(function() UIParent:SetScale(QUICore._pendingUIScale) end)
                        QUICore._pendingUIScale = nil
                    end
                end)
            end
            QUICore._scaleRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            -- Use pcall to catch protected states not detected by InCombatLockdown
            -- (e.g., instance transitions during M+ keystone activation)
            local success = pcall(function() UIParent:SetScale(scale) end)
            if not success then
                -- Protected state detected - defer to combat end
                QUICore._pendingUIScale = scale
                if not QUICore._scaleRegenFrame then
                    QUICore._scaleRegenFrame = CreateFrame("Frame")
                    QUICore._scaleRegenFrame:SetScript("OnEvent", function(self)
                        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                        if QUICore._pendingUIScale and not InCombatLockdown() then
                            pcall(function() UIParent:SetScale(QUICore._pendingUIScale) end)
                            QUICore._pendingUIScale = nil
                        end
                    end)
                end
                QUICore._scaleRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    
    if self.RefreshAll then
        self:RefreshAll()
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
    
    -- Refresh Unit Frames (including castbars) on profile change
    C_Timer.After(0.2, function()
        if _G.QUI_RefreshUnitFrames then
            _G.QUI_RefreshUnitFrames()
        end
    end)
    
    -- Refresh NCDM (Cooldown Display Manager) on profile change
    C_Timer.After(0.3, function()
        if _G.QUI_RefreshNCDM then
            _G.QUI_RefreshNCDM()
        end
    end)

    -- Refresh CDM Visibility on profile change
    C_Timer.After(0.4, function()
        if _G.QUI_RefreshCDMVisibility then
            _G.QUI_RefreshCDMVisibility()
        end
    end)

    -- Refresh Reticle on profile change
    C_Timer.After(0.45, function()
        if _G.QUI_RefreshReticle then
            _G.QUI_RefreshReticle()
        end
    end)

    -- Refresh Custom Trackers on profile change
    C_Timer.After(0.47, function()
        if _G.QUI_RefreshCustomTrackers then
            _G.QUI_RefreshCustomTrackers()
        end
    end)

    -- Refresh Spec Profiles tab if options panel is open
    if _G.QUI_RefreshSpecProfilesTab then
        _G.QUI_RefreshSpecProfilesTab()
    end

    -- Show popup notification about profile change
    -- Delay slightly to ensure UI is ready
    C_Timer.After(0.5, function()
        self:ShowProfileChangeNotification()
    end)
end

function QUICore:ShowProfileChangeNotification()
    -- Create a simple popup frame if it doesn't exist
    if not self.profileChangePopup then
        local popup = CreateFrame("Frame", "QUICore_ProfileChangePopup", UIParent, "BackdropTemplate")
        popup:SetSize(400, 120)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        popup:SetFrameStrata("DIALOG")
        popup:SetFrameLevel(1000)
        popup:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 }
        })
        popup:SetBackdropColor(0, 0, 0, 0.9)
        popup:Hide()
        
        -- Title
        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", popup, "TOP", 0, -20)
        title:SetText("Profile Changed")
        popup.title = title
        
        -- Message
        local message = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        message:SetPoint("CENTER", popup, "CENTER", 0, -10)
        message:SetWidth(360)
        message:SetJustifyH("CENTER")
        message:SetText("Profile changed please open edit mode for unit frame position updates")
        popup.message = message
        
        -- Close button (opens edit mode)
        local closeButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 30)
        closeButton:SetPoint("BOTTOM", popup, "BOTTOM", 0, 15)
        closeButton:SetText("OK")
        closeButton:SetScript("OnClick", function(self)
            self:GetParent():Hide()
            -- Open edit mode the same way as the config button
            DEFAULT_CHAT_FRAME.editBox:SetText("/editmode")
            ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
        end)
        popup.closeButton = closeButton
        
        self.profileChangePopup = popup
    end
    
    -- Show the popup
    if self.profileChangePopup then
        self.profileChangePopup:Show()
        -- Auto-hide after 10 seconds if not manually closed
        C_Timer.After(10, function()
            if self.profileChangePopup and self.profileChangePopup:IsShown() then
                self.profileChangePopup:Hide()
            end
        end)
    end
end

-- ============================================================================
-- EDIT MODE SELECTION MANAGER
-- Tracks which element is currently selected for nudge arrows
-- ============================================================================

QUICore.EditModeSelection = {
    selectedType = nil,  -- "unitframe", "powerbar", "cdm"
    selectedKey = nil,   -- "player", "primary", "EssentialCooldownViewer", etc.
}

-- Select an element and show its nudge arrows (hides arrows on previous selection)
function QUICore:SelectEditModeElement(elementType, elementKey)
    -- Skip if already selected
    if self.EditModeSelection.selectedType == elementType and self.EditModeSelection.selectedKey == elementKey then
        return
    end

    -- Hide arrows on previously selected element
    self:HideCurrentSelectionArrows()

    -- Update selection
    self.EditModeSelection.selectedType = elementType
    self.EditModeSelection.selectedKey = elementKey

    -- Show arrows on newly selected element
    self:ShowSelectionArrows(elementType, elementKey)
end

-- Clear selection (called when exiting Edit Mode)
function QUICore:ClearEditModeSelection()
    self:HideCurrentSelectionArrows()
    self.EditModeSelection.selectedType = nil
    self.EditModeSelection.selectedKey = nil
end

-- Hide nudge arrows on the currently selected element
function QUICore:HideCurrentSelectionArrows()
    local sel = self.EditModeSelection
    if not sel.selectedType then return end

    if sel.selectedType == "unitframe" then
        -- Unit frames store their overlay on the frame itself
        if ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames then
            local frame = ns.QUI_UnitFrames.frames[sel.selectedKey]
            if frame and frame.editOverlay then
                self:HideNudgeButtons(frame.editOverlay)
            end
        end
    elseif sel.selectedType == "powerbar" then
        local bar = (sel.selectedKey == "primary") and self.powerBar or self.secondaryPowerBar
        if bar and bar.editOverlay then
            self:HideNudgeButtons(bar.editOverlay)
        end
    elseif sel.selectedType == "cdm" then
        if self.cdmOverlays and self.cdmOverlays[sel.selectedKey] then
            self:HideNudgeButtons(self.cdmOverlays[sel.selectedKey])
        end
    elseif sel.selectedType == "blizzard" then
        if self.blizzardOverlays and self.blizzardOverlays[sel.selectedKey] then
            self:HideNudgeButtons(self.blizzardOverlays[sel.selectedKey])
        end
    elseif sel.selectedType == "minimap" then
        if self.minimapOverlay then
            self:HideNudgeButtons(self.minimapOverlay)
        end
    elseif sel.selectedType == "castbar" then
        -- Castbars store their overlay on the castbar frame itself
        if ns.QUI_Castbar and ns.QUI_Castbar.castbars then
            local castbar = ns.QUI_Castbar.castbars[sel.selectedKey]
            if castbar and castbar.editOverlay then
                self:HideNudgeButtons(castbar.editOverlay)
            end
        end
    end
end

-- Show nudge arrows on the specified element
function QUICore:ShowSelectionArrows(elementType, elementKey)
    if elementType == "unitframe" then
        if ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames then
            local frame = ns.QUI_UnitFrames.frames[elementKey]
            if frame and frame.editOverlay then
                self:ShowNudgeButtons(frame.editOverlay)
            end
        end
    elseif elementType == "powerbar" then
        local bar = (elementKey == "primary") and self.powerBar or self.secondaryPowerBar
        if bar and bar.editOverlay then
            self:ShowNudgeButtons(bar.editOverlay)
        end
    elseif elementType == "cdm" then
        if self.cdmOverlays and self.cdmOverlays[elementKey] then
            self:ShowNudgeButtons(self.cdmOverlays[elementKey])
        end
    elseif elementType == "blizzard" then
        if self.blizzardOverlays and self.blizzardOverlays[elementKey] then
            self:ShowNudgeButtons(self.blizzardOverlays[elementKey])
        end
    elseif elementType == "minimap" then
        if self.minimapOverlay then
            self:ShowNudgeButtons(self.minimapOverlay)
            -- Update info text with current position
            local settings = self.db and self.db.profile and self.db.profile.minimap
            if settings and settings.position and self.minimapOverlay.infoText then
                self.minimapOverlay.infoText:SetText(string.format("Minimap  X:%d Y:%d",
                    math.floor(settings.position[3] or 0),
                    math.floor(settings.position[4] or 0)))
            end
        end
    elseif elementType == "castbar" then
        if ns.QUI_Castbar and ns.QUI_Castbar.castbars then
            local castbar = ns.QUI_Castbar.castbars[elementKey]
            if castbar and castbar.editOverlay then
                -- Only show nudge buttons if not anchored
                if not castbar.editOverlay._isAnchored then
                    self:ShowNudgeButtons(castbar.editOverlay)
                end
            end
        end
    end
end

-- Helper to show nudge buttons on an overlay
function QUICore:ShowNudgeButtons(overlay)
    if not overlay then return end
    if overlay.nudgeUp then overlay.nudgeUp:Show() end
    if overlay.nudgeDown then overlay.nudgeDown:Show() end
    if overlay.nudgeLeft then overlay.nudgeLeft:Show() end
    if overlay.nudgeRight then overlay.nudgeRight:Show() end
    if overlay.infoText then overlay.infoText:Show() end
end

-- Helper to hide nudge buttons on an overlay
function QUICore:HideNudgeButtons(overlay)
    if not overlay then return end
    if overlay.nudgeUp then overlay.nudgeUp:Hide() end
    if overlay.nudgeDown then overlay.nudgeDown:Hide() end
    if overlay.nudgeLeft then overlay.nudgeLeft:Hide() end
    if overlay.nudgeRight then overlay.nudgeRight:Hide() end
    if overlay.infoText then overlay.infoText:Hide() end
end

-- ============================================================================
-- ARROW KEY NUDGING
-- When an element is selected in Edit Mode, arrow keys nudge its position
-- ============================================================================

local EditModeKeyHandler = CreateFrame("Frame", "QUIEditModeKeyHandler", UIParent)
EditModeKeyHandler:EnableKeyboard(false)
EditModeKeyHandler:SetPropagateKeyboardInput(true)

-- Nudge the currently selected element by deltaX, deltaY
function QUICore:NudgeSelectedElement(deltaX, deltaY)
    local sel = self.EditModeSelection
    if not sel or not sel.selectedType or not sel.selectedKey then return false end

    local shift = IsShiftKeyDown()
    local step = shift and 10 or 1
    local dx = deltaX * step
    local dy = deltaY * step

    if sel.selectedType == "unitframe" then
        if ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames then
            local frame = ns.QUI_UnitFrames.frames[sel.selectedKey]
            local settingsKey = sel.selectedKey
            if settingsKey and settingsKey:match("^boss%d+$") then
                settingsKey = "boss"
            end
            -- Unit frames database is stored at quiUnitFrames
            local ufdb = self.db and self.db.profile and self.db.profile.quiUnitFrames
            local settings = ufdb and ufdb[settingsKey]

            -- Block nudging for anchored frames
            local isAnchored = settings and settings.anchorTo and settings.anchorTo ~= "disabled"
            if isAnchored and (settingsKey == "player" or settingsKey == "target") then
                return false
            end

            if settings and frame then
                settings.offsetX = (settings.offsetX or 0) + dx
                settings.offsetY = (settings.offsetY or 0) + dy
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX, settings.offsetY)
                -- Update info text
                if frame.editOverlay and frame.editOverlay.infoText then
                    frame.editOverlay.infoText:SetText(string.format("%s  X:%d Y:%d",
                        sel.selectedKey, settings.offsetX, settings.offsetY))
                end
                -- Notify options panel
                if ns.QUI_UnitFrames and ns.QUI_UnitFrames.NotifyPositionChanged then
                    ns.QUI_UnitFrames:NotifyPositionChanged(settingsKey, settings.offsetX, settings.offsetY)
                end
                return true
            end
        end
    elseif sel.selectedType == "powerbar" then
        local cfg = (sel.selectedKey == "primary") and self.db.profile.powerBar or self.db.profile.secondaryPowerBar
        local bar = (sel.selectedKey == "primary") and self.powerBar or self.secondaryPowerBar
        if cfg and bar then
            cfg.offsetX = (cfg.offsetX or 0) + dx
            cfg.offsetY = (cfg.offsetY or 0) + dy
            cfg.autoAttach = false
            cfg.useRawPixels = true
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", cfg.offsetX, cfg.offsetY)
            -- Update info text
            if bar.editOverlay and bar.editOverlay.infoText then
                local label = (sel.selectedKey == "primary") and "Primary" or "Secondary"
                bar.editOverlay.infoText:SetText(string.format("%s  X:%d Y:%d", label, cfg.offsetX, cfg.offsetY))
            end
            -- Notify options panel
            self:NotifyPowerBarPositionChanged(sel.selectedKey, cfg.offsetX, cfg.offsetY)
            return true
        end
    elseif sel.selectedType == "castbar" then
        if ns.QUI_Castbar and ns.QUI_Castbar.castbars then
            local castbar = ns.QUI_Castbar.castbars[sel.selectedKey]
            -- Castbar settings are stored within unit frame settings at quiUnitFrames
            local ufdb = self.db and self.db.profile and self.db.profile.quiUnitFrames
            local settings = ufdb and ufdb[sel.selectedKey]
            local castSettings = settings and settings.castbar
            -- Only nudge if not anchored
            if castSettings and castSettings.anchor == "none" and castbar then
                castSettings.offsetX = (castSettings.offsetX or 0) + dx
                castSettings.offsetY = (castSettings.offsetY or 0) + dy
                castSettings.freeOffsetX = castSettings.offsetX
                castSettings.freeOffsetY = castSettings.offsetY
                castbar:ClearAllPoints()
                castbar:SetPoint("CENTER", UIParent, "CENTER", castSettings.offsetX, castSettings.offsetY)
                -- Update info text
                if castbar.editOverlay and castbar.editOverlay.infoText then
                    local displayName = sel.selectedKey == "player" and "Player" or
                                        sel.selectedKey == "target" and "Target" or
                                        sel.selectedKey == "focus" and "Focus" or "Castbar"
                    castbar.editOverlay.infoText:SetText(string.format("%s Castbar  X:%d Y:%d",
                        displayName, castSettings.offsetX, castSettings.offsetY))
                end
                return true
            end
        end
    end
    return false
end

EditModeKeyHandler:SetScript("OnKeyDown", function(self, key)
    if not QUICore.EditModeSelection or not QUICore.EditModeSelection.selectedType then
        return
    end

    local handled = false
    if key == "UP" then
        handled = QUICore:NudgeSelectedElement(0, 1)
    elseif key == "DOWN" then
        handled = QUICore:NudgeSelectedElement(0, -1)
    elseif key == "LEFT" then
        handled = QUICore:NudgeSelectedElement(-1, 0)
    elseif key == "RIGHT" then
        handled = QUICore:NudgeSelectedElement(1, 0)
    end

    if handled then
        self:SetPropagateKeyboardInput(false)
    else
        self:SetPropagateKeyboardInput(true)
    end
end)

EditModeKeyHandler:SetScript("OnKeyUp", function(self, key)
    self:SetPropagateKeyboardInput(true)
end)

-- Enable/disable keyboard handling based on selection
function QUICore:UpdateEditModeKeyHandler()
    if self.EditModeSelection and self.EditModeSelection.selectedType then
        EditModeKeyHandler:EnableKeyboard(true)
    else
        EditModeKeyHandler:EnableKeyboard(false)
    end
end

-- Hook into selection changes to enable/disable key handler
local origSelectEditModeElement = QUICore.SelectEditModeElement
function QUICore:SelectEditModeElement(elementType, elementKey)
    origSelectEditModeElement(self, elementType, elementKey)
    self:UpdateEditModeKeyHandler()
end

local origClearEditModeSelection = QUICore.ClearEditModeSelection
function QUICore:ClearEditModeSelection()
    origClearEditModeSelection(self)
    self:UpdateEditModeKeyHandler()
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
        -- Use pcall to catch protected states
        pcall(function() UIParent:SetScale(scaleToApply) end)
    end

    -- Capture preserved UI scale (after it's been properly applied)
    self._preservedUIScale = UIParent:GetScale()
    self._preservedPanelScale = self.db.profile.configPanelScale
    self._preservedPanelAlpha = self.db.profile.configPanelAlpha

    -- DEFERRED 0.1s: Hook setup (spreads work across frames)
    C_Timer.After(0.1, function()
        if not InCombatLockdown() then
            self:HookViewers()
            self:HookEditMode()
        end
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
    end)

    -- DEFERRED 1.0s: First viewer reskin + UI hider + buff borders
    C_Timer.After(1.0, function()
        if not InCombatLockdown() then
            self:ForceReskinAllViewers()
        end
        if _G.QUI_RefreshUIHider then
            _G.QUI_RefreshUIHider()
        end
        if _G.QUI_RefreshBuffBorders then
            _G.QUI_RefreshBuffBorders()
        end
    end)

    -- DEFERRED 2.0s: Safety retry for late-loading frames
    C_Timer.After(2.0, function()
        if not InCombatLockdown() then
            self:ForceReskinAllViewers()
        end
    end)
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
                -- Right click could toggle something or show a menu
                -- For now, just open config
                self:OpenConfig()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText("|cFF30D1FFQUI|r")
            tooltip:AddLine("Left-click to open configuration", 1, 1, 1)
            tooltip:AddLine("Right-click to open configuration", 1, 1, 1)
        end,
    })
    
    -- Register with LibDBIcon using separate minimapButton settings
    LibDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimapButton)
end

-- Helper Functions

local function CreateBorder(frame)
    if frame.border then return frame.border end

    local bord = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(bord)) or 1
    bord:SetPoint("TOPLEFT", frame, -px, px)
    bord:SetPoint("BOTTOMRIGHT", frame, px, -px)
    bord:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    bord:SetBackdropBorderColor(0, 0, 0, 1)

    frame.border = bord
    return bord
end

local function IsCooldownIconFrame(frame)
    return frame and (frame.icon or frame.Icon) and frame.Cooldown
end

local function StripBlizzardOverlay(icon)
    for _, region in ipairs({ icon:GetRegions() }) do
        if region:IsObjectType("Texture") and region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
            region:SetTexture("")
            region:Hide()
            region.Show = function() end
        end
    end
end

local function GetIconCountFont(icon)
    if not icon then return nil end

    -- 1. ChargeCount (charges)
    local charge = icon.ChargeCount
    if charge then
        local fs = charge.Current or charge.Text or charge.Count or nil

        if not fs and charge.GetRegions then
            for _, region in ipairs({ charge:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    fs = region
                    break
                end
            end
        end

        if fs then
            return fs
        end
    end

    -- 2. Applications (Buff stacks)
    local apps = icon.Applications
    if apps and apps.GetRegions then
        for _, region in ipairs({ apps:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                return region
            end
        end
    end

    -- 3. Fallback: look for named stack text
    for _, region in ipairs({ icon:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            local name = region:GetName()
            if name and (name:find("Stack") or name:find("Applications")) then
                return region
            end
        end
    end

    return nil
end

-- Icon Skinning

function QUICore:SkinIcon(icon, settings)
    -- Get the icon texture frame (handle both .icon and .Icon for compatibility)
    local iconTexture = icon.icon or icon.Icon
    if not icon or not iconTexture then return end

    -- Calculate icon dimensions from iconSize and aspectRatio (crop slider)
    local iconSize = settings.iconSize or 40
    local aspectRatioValue = 1.0 -- Default to square
    
    -- Get aspect ratio from crop slider or convert from string format
    if settings.aspectRatioCrop then
        aspectRatioValue = settings.aspectRatioCrop
    elseif settings.aspectRatio then
        -- Convert "16:9" format to numeric ratio
        local aspectW, aspectH = settings.aspectRatio:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        if aspectW and aspectH then
            aspectRatioValue = tonumber(aspectW) / tonumber(aspectH)
        end
    end
    
    local iconWidth = iconSize
    local iconHeight = iconSize
    
    -- Calculate width/height based on aspect ratio value
    -- aspectRatioValue is width:height ratio (e.g., 1.78 for 16:9, 0.56 for 9:16)
    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            -- Wider - width is longest, so width = iconSize
            iconWidth = iconSize
            iconHeight = iconSize / aspectRatioValue
        elseif aspectRatioValue < 1.0 then
            -- Taller - height is longest, so height = iconSize
            iconWidth = iconSize * aspectRatioValue
            iconHeight = iconSize
        end
    end
    
    local padding   = settings.padding or 5
    local zoom      = settings.zoom or 0
    local border    = icon.__CDM_Border
    local cdPadding = math.floor(padding * 0.7 + 0.5)

    -- This prevents stretching by cropping the texture to match the container aspect ratio
    iconTexture:ClearAllPoints()
    
    -- Fill the container
    iconTexture:SetPoint("TOPLEFT", icon, "TOPLEFT", padding, -padding)
    iconTexture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -padding, padding)
    
    -- Calculate texture coordinates based on aspect ratio to prevent stretching
    -- Use the same aspectRatioValue calculated above
    local left, right, top, bottom = 0, 1, 0, 1
    
    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            -- Wider than tall (e.g., 1.78 for 16:9) - crop top/bottom
            local cropAmount = 1.0 - (1.0 / aspectRatioValue)
            local offset = cropAmount / 2.0
            top = offset
            bottom = 1.0 - offset
        elseif aspectRatioValue < 1.0 then
            -- Taller than wide (e.g., 0.56 for 9:16) - crop left/right
            local cropAmount = 1.0 - aspectRatioValue
            local offset = cropAmount / 2.0
            left = offset
            right = 1.0 - offset
        end
    end
    
    -- Apply zoom on top of aspect ratio crop
    if zoom > 0 then
        local currentWidth = right - left
        local currentHeight = bottom - top
        local visibleSize = 1.0 - (zoom * 2)
        
        local zoomedWidth = currentWidth * visibleSize
        local zoomedHeight = currentHeight * visibleSize
        
        local centerX = (left + right) / 2.0
        local centerY = (top + bottom) / 2.0
        
        left = centerX - (zoomedWidth / 2.0)
        right = centerX + (zoomedWidth / 2.0)
        top = centerY - (zoomedHeight / 2.0)
        bottom = centerY + (zoomedHeight / 2.0)
    end
    
    -- Apply texture coordinates - this zooms/crops instead of stretching
    iconTexture:SetTexCoord(left, right, top, bottom)
    
    -- Use SetWidth and SetHeight separately AND SetSize to ensure both dimensions are set independently
    -- Wrap in pcall to handle protected frames gracefully
    local sizeSet = pcall(function()
    icon:SetWidth(iconWidth)
    icon:SetHeight(iconHeight)
    icon:SetSize(iconWidth, iconHeight)
    end)
    
    -- If size couldn't be set, reset texture coords to avoid visual mismatch
    -- and mark icon as NOT skinned so we retry later
    if not sizeSet then
        iconTexture:SetTexCoord(0, 1, 0, 1)
        icon.__cdmSkinFailed = true  -- Mark for retry
    else
        icon.__cdmSkinFailed = nil
    end

    -- Cooldown glow
    if icon.CooldownFlash then
        icon.CooldownFlash:ClearAllPoints()
        icon.CooldownFlash:SetPoint("TOPLEFT", icon, "TOPLEFT", cdPadding, -cdPadding)
        icon.CooldownFlash:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -cdPadding, cdPadding)
    end

    -- Cooldown swipe
    if icon.Cooldown then
        icon.Cooldown:ClearAllPoints()
        icon.Cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", cdPadding, -cdPadding)
        icon.Cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -cdPadding, cdPadding)
    end

    -- Pandemic icon
    local picon = icon.PandemicIcon or icon.pandemicIcon or icon.Pandemic or icon.pandemic
    if not picon then
        for _, region in ipairs({ icon:GetChildren() }) do
            if region:GetName() and region:GetName():find("Pandemic") then
                picon = region
                break
            end
        end
    end

    if picon and picon.ClearAllPoints then
        picon:ClearAllPoints()
        picon:SetPoint("TOPLEFT", icon, "TOPLEFT", padding, -padding)
        picon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -padding, padding)
    end

    -- Out of range highlight
    local oor = icon.OutOfRange or icon.outOfRange or icon.oor
    if oor and oor.ClearAllPoints then
        oor:ClearAllPoints()
        oor:SetPoint("TOPLEFT", icon, "TOPLEFT", padding, -padding)
        oor:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -padding, padding)
    end

    -- Charge/stack text
    local fs = GetIconCountFont(icon)
    if fs and fs.ClearAllPoints then
        fs:ClearAllPoints()

        local point   = settings.chargeTextAnchor or "BOTTOMRIGHT"
        if point == "MIDDLE" then point = "CENTER" end
        
        local offsetX = settings.countTextOffsetX or 0
        local offsetY = settings.countTextOffsetY or 0

        fs:SetPoint(point, iconTexture, point, offsetX, offsetY)

        local desiredSize = settings.countTextSize
        if desiredSize and desiredSize > 0 then
            local font, _, flags = fs:GetFont()
            fs:SetFont(font, desiredSize, flags or "OUTLINE")
        end
    end
    
    -- Duration text (cooldown countdown) - find and style the cooldown text
    local cooldown = icon.cooldown or icon.Cooldown
    if cooldown then
        -- Try to find the cooldown's text region
        local durationSize = settings.durationTextSize
        if durationSize and durationSize > 0 then
            -- Method 1: Check for OmniCC text
            if cooldown.text then
                local font, _, flags = cooldown.text:GetFont()
                if font then
                    cooldown.text:SetFont(font, durationSize, flags or "OUTLINE")
                end
            end
            
            -- Method 2: Check for Blizzard's built-in cooldown text (GetRegions)
            for _, region in pairs({cooldown:GetRegions()}) do
                if region:GetObjectType() == "FontString" then
                    local font, _, flags = region:GetFont()
                    if font then
                        region:SetFont(font, durationSize, flags or "OUTLINE")
                    end
                end
            end
        end
    end

    -- Strip Blizzard overlay
    StripBlizzardOverlay(icon)

    -- Border (using BACKGROUND texture to avoid secret value errors during combat)
    -- BackdropTemplate causes "arithmetic on secret value" crashes when frame is resized during combat
    if icon.IsForbidden and icon:IsForbidden() then
        icon.__cdmSkinned = true
        return
    end

    local edgeSize = tonumber(settings.borderSize) or 1

    if edgeSize > 0 then
        if not border then
            border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
            icon.__CDM_Border = border
        end

        local r, g, b, a = unpack(settings.borderColor or { 0, 0, 0, 1 })
        border:SetColorTexture(r, g, b, a or 1)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", -edgeSize, edgeSize)
        border:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", edgeSize, -edgeSize)
        border:Show()
    else
        if border then
            border:Hide()
        end
    end

    -- Only mark as fully skinned if size was successfully set
    if not icon.__cdmSkinFailed then
    icon.__cdmSkinned = true
    end
    icon.__cdmSkinPending = nil  -- Clear pending flag
end

function QUICore:SkinAllIconsInViewer(viewer)
    if not viewer or not viewer.GetName then return end

    local name     = viewer:GetName()
    local settings = self.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    local container = viewer.viewerFrame or viewer
    local children  = { container:GetChildren() }

    for _, icon in ipairs(children) do
        if IsCooldownIconFrame(icon) and (icon.icon or icon.Icon) then
            local ok, err = pcall(self.SkinIcon, self, icon, settings)
            if not ok then
                icon.__cdmSkinError = true
                print("|cffff4444[QUICore] SkinIcon error for", name, "icon:", err, "|r")
            end
        end
    end
end

-- Viewer Layout

-- Helper: Build row pattern array from settings
local function BuildRowPattern(settings, viewerName)
    local pattern = {}
    
    if viewerName == "EssentialCooldownViewer" then
        -- Essential has 3 rows
        if (settings.row1Icons or 0) > 0 then table.insert(pattern, settings.row1Icons) end
        if (settings.row2Icons or 0) > 0 then table.insert(pattern, settings.row2Icons) end
        if (settings.row3Icons or 0) > 0 then table.insert(pattern, settings.row3Icons) end
    elseif viewerName == "UtilityCooldownViewer" then
        -- Utility has 2 rows
        if (settings.row1Icons or 0) > 0 then table.insert(pattern, settings.row1Icons) end
        if (settings.row2Icons or 0) > 0 then table.insert(pattern, settings.row2Icons) end
    end
    
    -- If all rows are 0 or pattern is empty, default to unlimited single row
    if #pattern == 0 then
        return nil
    end
    
    return pattern
end

-- Helper: Compute grid from icons and pattern
local function ComputeGrid(icons, pattern)
    local grid = {}
    local idx = 1
    
    for _, rowSize in ipairs(pattern) do
        if rowSize > 0 then
            local row = {}
            for i = 1, rowSize do
                if idx <= #icons then
                    row[#row + 1] = icons[idx]
                    idx = idx + 1
                end
            end
            if #row > 0 then
                grid[#grid + 1] = row
            end
        end
    end
    
    -- If there are remaining icons beyond the pattern, add them to extra rows
    -- using the last row's size as the template
    local lastRowSize = pattern[#pattern] or 6
    while idx <= #icons do
        local row = {}
        for i = 1, lastRowSize do
            if idx <= #icons then
                row[#row + 1] = icons[idx]
                idx = idx + 1
            end
        end
        if #row > 0 then
            grid[#grid + 1] = row
        end
    end
    
    return grid
end

-- Helper: Calculate max row width for centering
local function MaxRowWidth(grid, iconWidth, spacing)
    local maxW = 0
    for _, row in ipairs(grid) do
        local rowW = (#row * iconWidth) + ((#row - 1) * spacing)
        if rowW > maxW then
            maxW = rowW
        end
    end
    return maxW
end

function QUICore:ApplyViewerLayout(viewer)
    if not viewer or not viewer.GetName then return end
    local name     = viewer:GetName()
    local settings = self.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    local container = viewer.viewerFrame or viewer
    local icons = {}

    for _, child in ipairs({ container:GetChildren() }) do
        if IsCooldownIconFrame(child) and child:IsShown() then
            table.insert(icons, child)
        end
    end

    local count = #icons
    if count == 0 then return end

    -- Sort icons with fallback to creation order
    table.sort(icons, function(a, b)
        local la = a.layoutIndex or a:GetID() or a.__cdmCreationOrder or 0
        local lb = b.layoutIndex or b:GetID() or b.__cdmCreationOrder or 0
        return la < lb
    end)

    -- Calculate icon dimensions from iconSize and aspectRatio (crop slider)
    local iconSize = settings.iconSize or 32
    local aspectRatioValue = 1.0 -- Default to square
    
    -- Get aspect ratio from crop slider or convert from string format
    if settings.aspectRatioCrop then
        aspectRatioValue = settings.aspectRatioCrop
    elseif settings.aspectRatio then
        -- Convert "16:9" format to numeric ratio
        local aspectW, aspectH = settings.aspectRatio:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        if aspectW and aspectH then
            aspectRatioValue = tonumber(aspectW) / tonumber(aspectH)
        end
    end
    
    local iconWidth = iconSize
    local iconHeight = iconSize
    
    -- Calculate width/height based on aspect ratio value
    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            -- Wider - width is longest, so width = iconSize
            iconWidth = iconSize
            iconHeight = iconSize / aspectRatioValue
        elseif aspectRatioValue < 1.0 then
            -- Taller - height is longest, so height = iconSize
            iconWidth = iconSize * aspectRatioValue
            iconHeight = iconSize
        end
    end
    
    local spacing    = settings.spacing or 4
    local rowLimit   = settings.rowLimit or 0

    -- Apply icon sizes
    for _, icon in ipairs(icons) do
        icon:ClearAllPoints()
        icon:SetWidth(iconWidth)
        icon:SetHeight(iconHeight)
        icon:SetSize(iconWidth, iconHeight)
    end

    -- Check if we should use row pattern (for Essential/Utility only)
    local useRowPattern = settings.useRowPattern
    local rowPattern = nil
    
    if useRowPattern and (name == "EssentialCooldownViewer" or name == "UtilityCooldownViewer") then
        rowPattern = BuildRowPattern(settings, name)
    end
    
    -- Calculate Y offset if Utility is anchored to Essential
    local yOffset = 0
    if name == "UtilityCooldownViewer" and settings.anchorToEssential then
        local essentialViewer = _G.EssentialCooldownViewer
        if essentialViewer and essentialViewer.__cdmTotalHeight then
            local anchorGap = settings.anchorGap or 10
            -- Offset by Essential's total height plus gap
            yOffset = -(essentialViewer.__cdmTotalHeight + anchorGap)
        end
    end
    
    -- Use row pattern layout if enabled and valid
    if rowPattern and #rowPattern > 0 then
        local grid = ComputeGrid(icons, rowPattern)
        local maxW = MaxRowWidth(grid, iconWidth, spacing)
        local alignment = settings.rowAlignment or "CENTER"
        local rowSpacing = iconHeight + spacing
        
        viewer.__cdmIconWidth = maxW
        -- Store total height for anchoring (number of rows * row height, minus last spacing)
        viewer.__cdmTotalHeight = (#grid * iconHeight) + ((#grid - 1) * spacing)
        
        local y = yOffset
        for rowIdx, row in ipairs(grid) do
            local rowW = (#row * iconWidth) + ((#row - 1) * spacing)
            
            -- Calculate starting X based on alignment
            local startX
            if alignment == "LEFT" then
                startX = -maxW / 2 + iconWidth / 2
            elseif alignment == "RIGHT" then
                startX = maxW / 2 - rowW + iconWidth / 2
            else -- CENTER
                startX = -rowW / 2 + iconWidth / 2
            end
            
            -- Position icons in this row
            for idx, icon in ipairs(row) do
                local x = startX + (idx - 1) * (iconWidth + spacing)
                icon:SetPoint("CENTER", container, "CENTER", x, y)
            end
            
            -- Move down for next row
            y = y - rowSpacing
        end
        
    -- Legacy rowLimit behavior (for backwards compatibility)
    elseif rowLimit <= 0 then
        -- Single row (original behavior)
        local totalWidth = count * iconWidth + (count - 1) * spacing
        viewer.__cdmIconWidth = totalWidth
        viewer.__cdmTotalHeight = iconHeight  -- Single row height

        local startX = -totalWidth / 2 + iconWidth / 2

        for i, icon in ipairs(icons) do
            local x = startX + (i - 1) * (iconWidth + spacing)
            icon:SetPoint("CENTER", container, "CENTER", x, yOffset)
        end
    else
        -- Multi-row layout with centered horizontal growth (legacy rowLimit)
        local numRows = math.ceil(count / rowLimit)
        local rowSpacing = iconHeight + spacing
        
        local maxRowWidth = 0
        for row = 1, numRows do
            local rowStart = (row - 1) * rowLimit + 1
            local rowEnd = math.min(row * rowLimit, count)
            local rowCount = rowEnd - rowStart + 1
            if rowCount > 0 then
                local rowWidth = rowCount * iconWidth + (rowCount - 1) * spacing
                if rowWidth > maxRowWidth then
                    maxRowWidth = rowWidth
                end
            end
        end
        
        viewer.__cdmIconWidth = maxRowWidth
        viewer.__cdmTotalHeight = (numRows * iconHeight) + ((numRows - 1) * spacing)
        
        local growDirection = "down"

        for i, icon in ipairs(icons) do
            local row = math.ceil(i / rowLimit)
            local rowStart = (row - 1) * rowLimit + 1
            local rowEnd = math.min(row * rowLimit, count)
            local rowCount = rowEnd - rowStart + 1
            local positionInRow = i - rowStart + 1
            
            local rowWidth = rowCount * iconWidth + (rowCount - 1) * spacing
            local startX = -rowWidth / 2 + iconWidth / 2
            local x = startX + (positionInRow - 1) * (iconWidth + spacing)
            
            local y
            if growDirection == "up" then
                y = yOffset + (row - 1) * rowSpacing
            else
                y = yOffset - (row - 1) * rowSpacing
            end
            
            icon:SetPoint("CENTER", container, "CENTER", x, y)
        end
    end
end

function QUICore:RescanViewer(viewer)
    if not viewer or not viewer.GetName then return end
    local name     = viewer:GetName()
    local settings = self.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    local container = viewer.viewerFrame or viewer
    local icons = {}
    local changed = false
    local inCombat = InCombatLockdown()

    for _, child in ipairs({ container:GetChildren() }) do
        if IsCooldownIconFrame(child) and child:IsShown() then
            table.insert(icons, child)

            -- Retry skinning if it failed before or hasn't been done
            if not child.__cdmSkinned or child.__cdmSkinFailed then
                -- Mark as pending to avoid multiple attempts
                if not child.__cdmSkinPending then
                    child.__cdmSkinPending = true
                    
                    if inCombat then
                        -- Defer skinning until out of combat
                        if not self.__cdmPendingIcons then
                            self.__cdmPendingIcons = {}
                        end
                        self.__cdmPendingIcons[child] = { icon = child, settings = settings, viewer = viewer }
                        
                        -- Ensure we have an event frame for combat end
                        if not self.__cdmIconSkinEventFrame then
                            local eventFrame = CreateFrame("Frame")
                            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                            eventFrame:SetScript("OnEvent", function(self)
                                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                                QUICore:ProcessPendingIcons()
                            end)
                            self.__cdmIconSkinEventFrame = eventFrame
                        end
                        self.__cdmIconSkinEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                    else
                        -- Not in combat, try to skin immediately
                        local success = pcall(self.SkinIcon, self, child, settings)
                        if success then
                            child.__cdmSkinPending = nil
                        end
                    end
                    changed = true
                end
            end
        end
    end

    local count = #icons

    -- Check if icon count changed
    if count ~= viewer.__cdmIconCount then
        viewer.__cdmIconCount = count
        changed = true
    end

    if changed then
        -- Re-apply layout when the viewer's icon set changes
        self:ApplyViewerLayout(viewer)

        -- Keep resource bars in sync with the viewer width immediately
        if self.UpdatePowerBar then
            self:UpdatePowerBar()
        end
        if self.UpdateSecondaryPowerBar then
            self:UpdateSecondaryPowerBar()
        end
    end
end

function QUICore:ApplyViewerSkin(viewer)
    if not viewer or not viewer.GetName then return end
    local name     = viewer:GetName()
    local settings = self.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    -- Apply layout first to set container sizes, then skin to handle textures
    self:ApplyViewerLayout(viewer)
    self:SkinAllIconsInViewer(viewer)
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
    
    -- Try to process any pending icons if not in combat
    if not InCombatLockdown() then
        self:ProcessPendingIcons()
    end
end

function QUICore:ProcessPendingIcons()
    if not self.__cdmPendingIcons then return end
    if InCombatLockdown() then return end
    
    local processed = {}
    for icon, data in pairs(self.__cdmPendingIcons) do
        if icon and icon:IsShown() and not icon.__cdmSkinned then
            local success = pcall(self.SkinIcon, self, icon, data.settings)
            if success then
                icon.__cdmSkinPending = nil
                processed[icon] = true
            end
        elseif not icon or not icon:IsShown() then
            -- Icon no longer exists or is hidden, remove from pending
            processed[icon] = true
        end
    end
    
    -- Remove processed icons from pending list
    for icon in pairs(processed) do
        self.__cdmPendingIcons[icon] = nil
    end
    
    -- If no more pending icons, clear the table
    if not next(self.__cdmPendingIcons) then
        self.__cdmPendingIcons = nil
    end
end

function QUICore:HookViewers()
    for _, name in ipairs(self.viewers) do
        local viewer = _G[name]
        if viewer and not viewer.__cdmHooked then
            viewer.__cdmHooked = true

            viewer:HookScript("OnShow", function(f)
                self:ApplyViewerSkin(f)
            end)

            viewer:HookScript("OnSizeChanged", function(f)
                self:ApplyViewerLayout(f)
            end)

            -- Reduced update rate - layout operations don't need high frequency
            -- 1 FPS fallback polling (primary updates via events/hooks)
            local updateInterval = 1.0

            viewer:HookScript("OnUpdate", function(f, elapsed)
                f.__cdmElapsed = (f.__cdmElapsed or 0) + elapsed
                if f.__cdmElapsed > updateInterval then
                    f.__cdmElapsed = 0
                    if f:IsShown() then
                        self:RescanViewer(f)
                        -- Only process pending if there actually are pending items
                        if not InCombatLockdown() then
                            if self.__cdmPendingIcons then
                            self:ProcessPendingIcons()
                            end
                            if self.__cdmPendingBackdrops then
                                self:ProcessPendingBackdrops()
                            end
                        end
                    end
                end
            end)

            self:ApplyViewerSkin(viewer)
        end
    end
end

function QUICore:ForceRefreshBuffIcons()
    local viewer = _G["BuffIconCooldownViewer"]
    if viewer and viewer:IsShown() then
        viewer.__cdmIconCount = nil
        self:RescanViewer(viewer)
        -- Process any pending icons if not in combat
        if not InCombatLockdown() then
            self:ProcessPendingIcons()
        end
    end
end

-- Force re-skin all icons in all viewers (used when Edit Mode changes)
function QUICore:ForceReskinAllViewers()
    for _, name in ipairs(self.viewers) do
        local viewer = _G[name]
        if viewer then
            local container = viewer.viewerFrame or viewer
            local children = { container:GetChildren() }
            for _, child in ipairs(children) do
                -- Clear skinned flag to force re-skinning
                child.__cdmSkinned = nil
                child.__cdmSkinPending = nil
                child.__cdmSkinFailed = nil
            end
            -- Reset icon count to force layout refresh
            viewer.__cdmIconCount = nil
            
            -- Note: We avoid calling viewer.Layout() directly as it can trigger
            -- Blizzard's internal code that accesses "secret" values and errors
        end
    end
    
    -- Trigger immediate rescan of all viewers
    for _, name in ipairs(self.viewers) do
        local viewer = _G[name]
        if viewer and viewer:IsShown() then
            self:RescanViewer(viewer)
            -- Also force apply viewer skin which does layout + skinning
            self:ApplyViewerSkin(viewer)
        end
    end
end

-- Hook Edit Mode to force re-skinning when it opens/closes
function QUICore:HookEditMode()
    if self.__editModeHooked then return end
    self.__editModeHooked = true
    
    -- Hook EditModeManagerFrame if it exists
    if EditModeManagerFrame then
        -- Hook when Edit Mode is entered
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
            C_Timer.After(0.1, function()
                self:ForceReskinAllViewers()
            end)

            -- Fix BossTargetFrameContainer crash: GetScaledSelectionSides fails when GetRect returns nil
            -- Apply hook here because the method may not exist at addon init time
            if BossTargetFrameContainer and not BossTargetFrameContainer._quiScaledSidesHooked then
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
                    BossTargetFrameContainer._quiScaledSidesHooked = true
                end
            end
        end)
        
        -- Hook when Edit Mode is exited
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            C_Timer.After(0.1, function()
                self:ForceReskinAllViewers()

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
        end)
            end
            
    -- Also hook combat end to retry any failed skinning
    local combatEndFrame = CreateFrame("Frame")
    combatEndFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatEndFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    combatEndFrame:SetScript("OnEvent", function(frame, event)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Small delay to let things settle after combat
            C_Timer.After(0.2, function()
                -- Check if any icons need re-skinning
                local needsReskin = false
                for _, viewerName in ipairs(self.viewers) do
                    local viewer = _G[viewerName]
                    if viewer then
                        local container = viewer.viewerFrame or viewer
                        for _, child in ipairs({ container:GetChildren() }) do
                            if child.__cdmSkinFailed then
                                needsReskin = true
                                break
                            end
                end
            end
                    if needsReskin then break end
                end
                
                if needsReskin then
                    self:ForceReskinAllViewers()
                end
            end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Re-skin after zone changes/loading screens
            C_Timer.After(1, function()
                if not InCombatLockdown() then
                    self:ForceReskinAllViewers()
            end
        end)
            end
        end)
    end

-- Process pending backdrops that were deferred due to secret values
function QUICore:ProcessPendingBackdrops()
    if not self.__cdmPendingBackdrops then return end

    local processed = {}
    for frame, _ in pairs(self.__cdmPendingBackdrops) do
        if frame then
            -- Check if dimensions are now valid (must be able to do arithmetic)
            local ok, isValid = pcall(function()
                local w = frame:GetWidth()
                local h = frame:GetHeight()
                if w and h then
                    local test = w + h  -- This will error if secret values
                    return test > 0
                end
                return false
            end)
            
            if ok and isValid then
                -- Dimensions are valid, try to set backdrop
                local pendingInfo = frame.__cdmBackdropPending
                local pendingSettings = frame.__cdmBackdropSettings
                
                if pendingSettings then
                    if pendingSettings.backdropInfo then
                        local setOk = pcall(frame.SetBackdrop, frame, pendingSettings.backdropInfo)
                        if setOk and pendingSettings.borderColor then
                            pcall(frame.SetBackdropBorderColor, frame, unpack(pendingSettings.borderColor))
end
                    elseif pendingInfo then
                        pcall(frame.SetBackdrop, frame, pendingInfo)
                    end
                elseif pendingInfo then
                    pcall(frame.SetBackdrop, frame, pendingInfo)
                end
                
                frame.__cdmBackdropPending = nil
                frame.__cdmBackdropSettings = nil
                table.insert(processed, frame)
                end
            end
        end
        
    -- Remove processed frames
    for _, frame in ipairs(processed) do
        self.__cdmPendingBackdrops[frame] = nil
            end
        end
        
function QUI:GetGlobalFont()
    local LSM = LibStub("LibSharedMedia-3.0")
    local fontName = "Quazii"  -- Default fallback

    -- Read font from user settings
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        fontName = QUICore.db.profile.general.font or fontName
    end

    return LSM:Fetch("font", fontName) or [[Interface\AddOns\QUI\assets\Quazii.ttf]]
end

function QUI:GetGlobalTexture()
    local LSM = LibStub("LibSharedMedia-3.0")
    -- For now, return Quazii texture. Will be configurable in General Tab (Feature #3)
    local textureName = "Quazii"
    return LSM:Fetch("statusbar", textureName) or "Interface\\AddOns\\QUI\\assets\\Quazii"
end

function QUI:GetAddonAccentColor()
    local db = QUI.db and QUI.db.profile
    if not db then
        return 0.204, 0.827, 0.6, 1  -- Fallback to mint
    end
    local c = (db.general and db.general.addonAccentColor)
        or db.addonAccentColor
        or {0.204, 0.827, 0.6, 1}
    return c[1], c[2], c[3], c[4] or 1
end

function QUI:GetSkinColor()
    local db = QUI.db and QUI.db.profile
    if not db then
        return 0.2, 1.0, 0.6, 1  -- Fallback to mint
    end

    if db.general and db.general.skinUseClassColor then
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS[class]
        if color then
            return color.r, color.g, color.b, 1
        end
    end

    local c = (db.general and db.general.addonAccentColor)
        or db.addonAccentColor
        or {0.204, 0.827, 0.6, 1}
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
function QUICore:SafeSetFont(fontString, fontPath, size, flags)
    if not fontString then return end
    fontString:SetFont(fontPath, size, flags or "")
    -- Check if font was actually set (GetFont returns nil if failed)
    local actualFont = fontString:GetFont()
    if not actualFont then
        -- Fallback to guaranteed Blizzard font
        fontString:SetFont("Fonts\\FRIZQT__.TTF", size, flags or "")
    end
end

function QUICore:RefreshAll()
    for _, name in ipairs(self.viewers) do
        local viewer = _G[name]
        if viewer and viewer:IsShown() then
            self:ApplyViewerSkin(viewer)
        end
    end
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
    -- Also refresh Blizzard UI fonts when global font changes
    if self.ApplyGlobalFont then
        self:ApplyGlobalFont()
    end
    -- Refresh skyriding HUD fonts
    if _G.QUI_RefreshSkyriding then
        _G.QUI_RefreshSkyriding()
    end
end

-- ============================================================================
-- Global Font Override for Blizzard UI
-- ============================================================================

-- Fallback to bundled Quazii font (always available, loaded early in media.lua)
local QUAZII_FONT_PATH = [[Interface\AddOns\QUI\assets\Quazii.ttf]]

-- Font objects to override (preserves original size/flags, only changes font file)
local BLIZZARD_FONT_OBJECTS = {
    -- Game fonts (menus, dialogs, general UI)
    "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall",
    "GameFontHighlightSmall", "GameFontNormalLarge", "GameFontHighlightLarge",
    "GameFontDisable", "GameFontDisableSmall", "GameFontDisableLarge",
    -- Number fonts
    "NumberFontNormal", "NumberFontNormalSmall", "NumberFontNormalLarge",
    "NumberFontNormalHuge", "NumberFontNormalSmallGray",
    -- Quest fonts
    "QuestFont", "QuestFontHighlight", "QuestFontNormalSmall",
    "QuestFontHighlightSmall",
    -- Tooltip fonts
    "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall",
    -- Chat fonts
    "ChatFontNormal", "ChatFontSmall", "ChatFontLarge",
}

-- Track if hooks are already set up (one-time)
local globalFontHooksInitialized = false

-- Debounce for hook callbacks
local globalFontPending = false

local function GetGlobalFontPath()
    if not QUICore.db or not QUICore.db.profile or not QUICore.db.profile.general then
        return QUAZII_FONT_PATH
    end
    local fontName = QUICore.db.profile.general.font or "Quazii"
    local fontPath = LSM:Fetch("font", fontName)
    return fontPath or QUAZII_FONT_PATH
end

-- Apply font to a single FontString (preserving size/flags)
local function ApplyFontToFontString(fontString, fontPath)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    local _, size, flags = fontString:GetFont()
    if size and size > 0 then
        fontString:SetFont(fontPath, size, flags or "")
    end
end

-- Recursively apply font to all FontStrings in a frame
local function ApplyFontToFrameRecursive(frame, fontPath)
    if not frame then return end

    -- Apply to direct regions
    local regions = { frame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("FontString") then
            ApplyFontToFontString(region, fontPath)
        end
    end

    -- Recurse into children
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        ApplyFontToFrameRecursive(child, fontPath)
    end
end

-- Schedule debounced font application (for hooks)
local function ScheduleGlobalFontApply()
    if globalFontPending then return end
    globalFontPending = true
    C_Timer.After(0.05, function()
        globalFontPending = false
        if QUICore.ApplyGlobalFont then
            QUICore:ApplyGlobalFont()
        end
    end)
end

function QUICore:ApplyGlobalFont()
    -- Check if feature is enabled
    if not self.db or not self.db.profile or not self.db.profile.general then return end
    if not self.db.profile.general.applyGlobalFontToBlizzard then return end

    local fontPath = GetGlobalFontPath()

    -- Override Blizzard font objects
    for _, fontObjName in ipairs(BLIZZARD_FONT_OBJECTS) do
        local fontObj = _G[fontObjName]
        if fontObj and fontObj.GetFont and fontObj.SetFont then
            local _, size, flags = fontObj:GetFont()
            if size then
                fontObj:SetFont(fontPath, size, flags or "")
            end
        end
    end

    -- Set up hooks (one-time)
    if not globalFontHooksInitialized then
        globalFontHooksInitialized = true

        -- Hook ObjectiveTracker updates (check if function exists - API varies by expansion)
        if ObjectiveTrackerFrame then
            if type(ObjectiveTracker_Update) == "function" then
                hooksecurefunc("ObjectiveTracker_Update", function()
                    if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
                    local fp = GetGlobalFontPath()
                    ApplyFontToFrameRecursive(ObjectiveTrackerFrame, fp)
                end)
            else
                -- Fallback: hook frame's OnShow for expansion versions without ObjectiveTracker_Update
                ObjectiveTrackerFrame:HookScript("OnShow", function(self)
                    if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
                    local fp = GetGlobalFontPath()
                    ApplyFontToFrameRecursive(self, fp)
                end)
            end
        end

        -- Hook Tooltip display
        if GameTooltip then
            hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
                if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
                local fp = GetGlobalFontPath()
                ApplyFontToFrameRecursive(tooltip, fp)
            end)
        end

        -- Hook chat frame font size changes
        if FCF_SetChatWindowFontSize then
            hooksecurefunc("FCF_SetChatWindowFontSize", function(chatFrame, fontSize)
                if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
                local fp = GetGlobalFontPath()
                if chatFrame and type(chatFrame.GetFont) == "function" and type(chatFrame.SetFont) == "function" then
                    -- Apply global font directly to ScrollingMessageFrame (not just children)
                    local _, size, flags = chatFrame:GetFont()
                    chatFrame:SetFont(fp, fontSize or size or 14, flags or "")
                end
            end)
        end

        -- Event handler for chat window resets (font persistence across new messages)
        local chatFontEventFrame = CreateFrame("Frame")
        chatFontEventFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
        chatFontEventFrame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
        chatFontEventFrame:SetScript("OnEvent", function()
            if not QUICore.db or not QUICore.db.profile then return end
            if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
            C_Timer.After(0.05, function()
                local fp = GetGlobalFontPath()
                for i = 1, NUM_CHAT_WINDOWS do
                    local chatFrame = _G["ChatFrame" .. i]
                    if chatFrame and chatFrame.SetFont then
                        local _, size, flags = chatFrame:GetFont()
                        if size then
                            chatFrame:SetFont(fp, size, flags or "")
                        end
                    end
                end
            end)
        end)
    end

    -- Apply to existing chat frames (SetFont on the frame itself for new message persistence)
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame.SetFont then
            local _, size, flags = chatFrame:GetFont()
            if size then
                chatFrame:SetFont(fontPath, size, flags or "")
            end
        end
    end

    -- Apply to existing tooltips
    if GameTooltip then
        ApplyFontToFrameRecursive(GameTooltip, fontPath)
    end
end
