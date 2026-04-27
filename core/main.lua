--- QUI Core
--- All branding changed to QUI

local ADDON_NAME, ns = ...
local QUI = QUI

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

    -- Run all profile migrations (consolidated in migrations.lua)
    if ns.Migrations and ns.Migrations.Run then
        ns.Migrations.Run(self.db)
    end

    -- Late migrations run at PLAYER_LOGIN once Blizzard runtime state
    -- (EditModeManagerFrame, live frame positions) is available. The
    -- handler unregisters itself after a successful pass.
    if ns.Migrations and ns.Migrations.RunLate then
        self:RegisterEvent("PLAYER_LOGIN", function(event)
            ns.Migrations.RunLate(self.db)
            self:UnregisterEvent("PLAYER_LOGIN")
        end)
    end

    local profile = self.db.profile

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

    -- Normalize callback payloads that don't pass the active destination profile.
    local currentProfile = self.db:GetCurrentProfile()
    local effectiveProfileKey = profileKey
    if event == "OnProfileCopied" or event == "OnProfileReset" then
        effectiveProfileKey = currentProfile
    end
    if type(effectiveProfileKey) ~= "string" or effectiveProfileKey == "" then
        effectiveProfileKey = currentProfile
    end

    -- Skip if "switching" to the same profile (happens during M+ entry false events)
    -- LibDualSpec triggers profile switch even when already on correct profile
    if effectiveProfileKey == self._lastKnownProfile and effectiveProfileKey == currentProfile then
        return  -- No actual change happening - skip all UI modifications
    end
    self._lastKnownProfile = effectiveProfileKey

    -- Update spec tracking (kept for reference)
    self._lastKnownSpec = GetSpecialization() or 0

    local pins = ns.Settings and ns.Settings.Pins
    if pins and type(pins.HandleProfileEvent) == "function" then
        pins:HandleProfileEvent(event, self.db, effectiveProfileKey)
    end

    -- Run migrations on the newly-activated profile
    local addon = _G.QUI
    if addon and addon.BackwardsCompat then
        addon:BackwardsCompat()
    end

    -- Late migrations also run on profile switch — by this point (well
    -- past PLAYER_LOGIN) EditModeManagerFrame is loaded, so we can call
    -- synchronously rather than waiting for an event.
    if ns.Migrations and ns.Migrations.RunLate then
        ns.Migrations.RunLate(self.db)
    end

    -- Wipe the font registry so stale FontStrings from the old profile's frames
    -- are released. Modules will re-register via ApplyFont when they rebuild.
    if self.CleanupFontRegistry then
        self:CleanupFontRegistry()
    end

    -- Helper to apply UIParent scale safely (defers if in combat or protected state)
    -- pcall wraps SetScale because M+ keystone activation can enter a protected
    -- state while InCombatLockdown() still returns false.
    local profileScaleChanged = false
    local function FinalizeProfileScale(scale)
        self.uiscale = scale or UIParent:GetScale()
        self.screenWidth, self.screenHeight = GetScreenWidth(), GetScreenHeight()
        if self.RefreshAllFonts then
            self:RefreshAllFonts()
        end
        if ns.UIKit and ns.UIKit.RefreshScaleBoundWidgets then
            ns.UIKit.RefreshScaleBoundWidgets()
        end
        if not InCombatLockdown() and self.UIMult then
            self:UIMult()
        end
    end
    local function DeferUIScale(scale)
        QUICore._pendingUIScale = scale
        if not QUICore._scaleRegenFrame then
            QUICore._scaleRegenFrame = CreateFrame("Frame")
            QUICore._scaleRegenFrame:SetScript("OnEvent", function(self)
                if QUICore._pendingUIScale and not InCombatLockdown() then
                    local ok = pcall(UIParent.SetScale, UIParent, QUICore._pendingUIScale)
                    if ok then
                        FinalizeProfileScale(QUICore._pendingUIScale)
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
            else
                FinalizeProfileScale(scale)
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
            local currentScale = UIParent:GetScale()
            if currentScale and math.abs(newProfileScale - currentScale) > 0.001 then
                profileScaleChanged = true
            end

            -- Profile switches can re-apply positions after a live scale change,
            -- so continue through the normal refresh path instead of forcing /reload.
            ApplyUIScale(newProfileScale)
            -- Only update preserved scale when switching to a profile with a valid saved scale
            self._preservedUIScale = newProfileScale
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
        if type(QUI.GUI.TeardownFrameTree) == "function" then
            pcall(QUI.GUI.TeardownFrameTree, QUI.GUI, QUI.GUI.MainFrame, { includeRoot = true })
        else
            pcall(QUI.GUI.MainFrame.Hide, QUI.GUI.MainFrame)
            pcall(QUI.GUI.MainFrame.SetParent, QUI.GUI.MainFrame, nil)
        end
        QUI.GUI.MainFrame = nil
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
    local refreshGroups = { "cooldowns", "frames", "castbars", "qol", "combat", "trackers", "data", "chat", "character", "utility", "ui", "anchoring" }
    C_Timer.After(0.2, function()
        if ns.Registry then
            -- Refresh all non-skinning modules in priority order
            for _, group in ipairs(refreshGroups) do
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
        if _G.QUI_RefreshStatusTrackingBarSkin then
            _G.QUI_RefreshStatusTrackingBarSkin()
        end
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

    -- Profile switches that also change the UI scale need one more pass after
    -- Blizzard's layout code and scale-dependent widgets have fully settled.
    if profileScaleChanged then
        C_Timer.After(1.8, function()
            if InCombatLockdown() then
                return
            end

            if self.UIMult then
                self:UIMult()
            end

            if ns.Registry then
                for _, group in ipairs(refreshGroups) do
                    ns.Registry:RefreshAll(group)
                end
            end

            local ApplyAnchors = _G.QUI_ApplyAllFrameAnchors
            if ApplyAnchors then pcall(ApplyAnchors, true) end
            local RefreshUnitFrames = _G.QUI_RefreshUnitFrames
            if RefreshUnitFrames then pcall(RefreshUnitFrames) end
            local RefreshGroupFrames = _G.QUI_RefreshGroupFrames
            if RefreshGroupFrames then pcall(RefreshGroupFrames) end
        end)
    end
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

    -- Create secure player buff/debuff headers while the addon-load safe
    -- window is still open. A delayed timer misses this window on combat
    -- reloads, and SecureAuraHeaderTemplate cannot be safely bootstrapped
    -- from addon code once combat lockdown is active.
    if QUI.BuffBorders and QUI.BuffBorders.Init then
        QUI.BuffBorders.Init()
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
        icon = ns.Helpers.AssetPath .. "QUI.tga",
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
        -- Hook HighlightSystem/SelectSystem on each so the blue selection
        -- overlay and magnetic snap registration get cleared immediately.
        local _editModeSuppressedFrames = {}
        local _editModeSuppressedFrameNames = {
            -- Unit frames
            -- PetFrame intentionally stays out of this list: bad server-side
            -- Edit Mode layouts can replay protected PetFrame layout during
            -- TotemFrame updates, and touching its Edit Mode selection state
            -- makes Blizzard blame QUI for PetFrame:ClearAllPointsBase().
            "PlayerFrame", "PartyFrame",
            "BossTargetFrameContainer",
            -- Aura frames
            "BuffFrame", "DebuffFrame",
            -- Action bars
            "MainMenuBar", "MainActionBar",
            "MultiBarBottomLeft", "MultiBarBottomRight",
            "MultiBarRight", "MultiBarLeft",
            "MultiBar5", "MultiBar6", "MultiBar7",
            "StanceBar", "MicroMenuContainer", "BagsBar",
            "PetActionBar", "ExtraAbilityContainer",
            "ExtraActionBarFrame", "ZoneAbilityFrame",
            "OverrideActionBar", "MainMenuBarVehicleLeaveButton",
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

        -- PartyFrame is only suppressed when QUI group frames own party frames.
        -- When disabled, the user needs Blizzard's Edit Mode selection to drag it.
        local function ShouldSuppressEditModeFrame(name)
            if name == "PartyFrame" then
                local gfDB = QUI.db and QUI.db.profile and QUI.db.profile.quiGroupFrames
                return gfDB and gfDB.enabled ~= false
            end
            return true
        end

        local function SuppressEditModeSelection(frame)
            if not frame then return end
            if frame.ClearHighlight then
                pcall(frame.ClearHighlight, frame)
            end
            local selection = frame.Selection
            if selection and selection.Hide then
                pcall(selection.Hide, selection)
            end
            if EditModeMagnetismManager and EditModeMagnetismManager.UnregisterFrame then
                pcall(EditModeMagnetismManager.UnregisterFrame, EditModeMagnetismManager, frame)
            end
        end

        local function InstallEditModeSuppression()
            for _, name in ipairs(_editModeSuppressedFrameNames) do
                if ShouldSuppressEditModeFrame(name) then
                    local frame = _G[name]
                    if frame and not _editModeSuppressedFrames[frame] then
                        _editModeSuppressedFrames[frame] = true
                        if frame.HighlightSystem then
                            hooksecurefunc(frame, "HighlightSystem", function(f)
                                SuppressEditModeSelection(f)
                            end)
                        end
                        if frame.SelectSystem then
                            hooksecurefunc(frame, "SelectSystem", function(f)
                                SuppressEditModeSelection(f)
                            end)
                        end
                        SuppressEditModeSelection(frame)
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
                    if ShouldSuppressEditModeFrame(name) then
                        local frame = _G[name]
                        SuppressEditModeSelection(frame)
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

