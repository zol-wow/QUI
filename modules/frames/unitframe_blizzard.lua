---------------------------------------------------------------------------
-- QUI Unit Frames - Blizzard Frame Hiding
-- Hides/kills default Blizzard unit frames when QUI replacements are active.
-- Extracted from modules/frames/unitframes.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiUnitFrames")

-- Upvalue caching for hot-path performance
local pcall = pcall
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

local QUI = _G.QuaziiUI or _G.QUI

-- QUI_UF is created in unitframes.lua and exported to ns.QUI_UnitFrames.
-- This file loads after unitframes.lua, so the reference is available.
local QUI_UF = ns.QUI_UnitFrames
if not QUI_UF then return end

-- TAINT SAFETY: Track hook/fix guards in local table, NOT on Blizzard frames.
local _blizzFrameGuards = {}

-- TAINT SAFETY: Weak-keyed table to track which frames have had their OnShow
-- hooked via hooksecurefunc, so we never store addon keys on Blizzard frames.
local _hookedOnShowFrames = Helpers.CreateStateTable()

---------------------------------------------------------------------------
-- LOCAL HELPERS
---------------------------------------------------------------------------

local function KillBlizzardFrame(frame, allowInEditMode)
    if not frame then return end

    -- Unregister events to stop updates
    frame:UnregisterAllEvents()

    -- For secure frames like PlayerFrame, we can't call Hide() directly
    -- Instead, make it invisible and non-interactive
    frame:SetAlpha(0)
    frame:EnableMouse(false)

    -- Move it off-screen as extra measure
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)

    -- NOTE: Do NOT use RegisterStateDriver(frame, "visibility", "hide") here.
    -- Hidden frames return nil from GetRect(), which crashes Blizzard's
    -- GetScaledSelectionSides() when the Edit Mode magnetic snap system
    -- iterates all registered systems.  Alpha 0 + off-screen is sufficient.
end

local function KillBlizzardChildFrame(frame)
    if not frame then return end
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end

    -- Use pcall to safely try Hide() - some child frames may be protected
    pcall(function() frame:Hide() end)

    if frame.EnableMouse then
        frame:EnableMouse(false)
    end

    -- Set alpha to 0 as fallback
    frame:SetAlpha(0)

    -- TAINT SAFETY: Use hooksecurefunc instead of SetScript("OnShow") to avoid
    -- replacing secure handlers on Blizzard frames. Defer the Hide() via
    -- C_Timer.After(0) to break the taint chain from the secure execution context.
    if not _hookedOnShowFrames[frame] then
        _hookedOnShowFrames[frame] = true
        Helpers.DeferredHideOnShow(frame, { clearAlpha = true, combatCheck = false })
    end
end

local function HideBlizzardTargetVisuals()
    if not TargetFrame then return end

    -- Hide main art & bars but keep the frame alive for tooltips/buffs
    KillBlizzardChildFrame(TargetFrame.TargetFrameContainer)
    KillBlizzardChildFrame(TargetFrame.TargetFrameContent)
    KillBlizzardChildFrame(TargetFrame.healthbar)
    KillBlizzardChildFrame(TargetFrame.manabar)
    KillBlizzardChildFrame(TargetFrame.powerBarAlt)
    KillBlizzardChildFrame(TargetFrame.overAbsorbGlow)
    KillBlizzardChildFrame(TargetFrame.overHealAbsorbGlow)
    KillBlizzardChildFrame(TargetFrame.totalAbsorbBar)
    KillBlizzardChildFrame(TargetFrame.tempMaxHealthLossBar)
    KillBlizzardChildFrame(TargetFrame.myHealPredictionBar)
    KillBlizzardChildFrame(TargetFrame.otherHealPredictionBar)
    KillBlizzardChildFrame(TargetFrame.name)
    KillBlizzardChildFrame(TargetFrame.portrait)
    KillBlizzardChildFrame(TargetFrame.threatIndicator)
    KillBlizzardChildFrame(TargetFrame.threatNumericIndicator)

    -- Hide buff/debuff frames (modern WoW structure)
    KillBlizzardChildFrame(TargetFrame.BuffFrame)
    KillBlizzardChildFrame(TargetFrame.DebuffFrame)
    KillBlizzardChildFrame(TargetFrame.buffsContainer)
    KillBlizzardChildFrame(TargetFrame.debuffsContainer)

    -- Hide old-style aura buttons
    for i = 1, 40 do
        KillBlizzardChildFrame(_G["TargetFrameBuff"..i])
        KillBlizzardChildFrame(_G["TargetFrameDebuff"..i])
    end

    -- Release aura pools (Dragonflight+)
    if TargetFrame.auraPools and TargetFrame.auraPools.ReleaseAll then
        TargetFrame.auraPools:ReleaseAll()
    end

    -- Hide the entire TargetFrame since we have our own
    KillBlizzardFrame(TargetFrame)
end

local function HideBlizzardFocusVisuals()
    if not FocusFrame then return end

    KillBlizzardChildFrame(FocusFrame.TargetFrameContainer)
    KillBlizzardChildFrame(FocusFrame.TargetFrameContent)
    KillBlizzardChildFrame(FocusFrame.healthbar)
    KillBlizzardChildFrame(FocusFrame.manabar)
    KillBlizzardChildFrame(FocusFrame.powerBarAlt)
    KillBlizzardChildFrame(FocusFrame.overAbsorbGlow)
    KillBlizzardChildFrame(FocusFrame.overHealAbsorbGlow)
    KillBlizzardChildFrame(FocusFrame.totalAbsorbBar)
    KillBlizzardChildFrame(FocusFrame.tempMaxHealthLossBar)
    KillBlizzardChildFrame(FocusFrame.myHealPredictionBar)
    KillBlizzardChildFrame(FocusFrame.otherHealPredictionBar)
    KillBlizzardChildFrame(FocusFrame.name)
    KillBlizzardChildFrame(FocusFrame.portrait)
    KillBlizzardChildFrame(FocusFrame.threatIndicator)
    KillBlizzardChildFrame(FocusFrame.threatNumericIndicator)

    -- Hide buff/debuff frames (modern WoW structure)
    KillBlizzardChildFrame(FocusFrame.BuffFrame)
    KillBlizzardChildFrame(FocusFrame.DebuffFrame)
    KillBlizzardChildFrame(FocusFrame.buffsContainer)
    KillBlizzardChildFrame(FocusFrame.debuffsContainer)

    -- Hide old-style aura buttons
    for i = 1, 40 do
        KillBlizzardChildFrame(_G["FocusFrameBuff"..i])
        KillBlizzardChildFrame(_G["FocusFrameDebuff"..i])
    end

    -- Release aura pools
    if FocusFrame.auraPools and FocusFrame.auraPools.ReleaseAll then
        FocusFrame.auraPools:ReleaseAll()
    end

    -- Hide the entire FocusFrame since we have our own
    KillBlizzardFrame(FocusFrame)
end

---------------------------------------------------------------------------
-- HIDE BLIZZARD DEFAULT FRAMES
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Hide Blizzard castbars (player + pet).
-- Safe to call repeatedly (e.g. on every zone transition) — the Show hook
-- is guarded so it's only installed once.
---------------------------------------------------------------------------
function QUI_UF:HideBlizzardCastbars()
    if InCombatLockdown() then return end
    local db = GetDB()
    if not db then return end
    local playerDB = db.player
    local playerFrameEnabled = db.enabled and playerDB and playerDB.enabled
    local playerCastbarEnabled = playerDB and (playerDB.castbar == nil or playerDB.castbar.enabled ~= false)
    local standaloneActive = playerDB and playerDB.standaloneCastbar and not playerFrameEnabled and playerCastbarEnabled
    local shouldHidePlayerCastbar = (playerFrameEnabled and playerCastbarEnabled) or standaloneActive
    if not shouldHidePlayerCastbar then return end

    -- NOTE: As of 12.0.x beta, CastingBarFrame can be a forbidden/restricted frame.
    -- All interactions are wrapped in pcall to prevent errors from blocking initialization.
    if PlayerCastingBarFrame then
        pcall(function()
            PlayerCastingBarFrame:SetAlpha(0)
            PlayerCastingBarFrame:SetScale(0.0001)
            PlayerCastingBarFrame:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -10000, 10000)
            PlayerCastingBarFrame:UnregisterAllEvents()
        end)
        pcall(function()
            PlayerCastingBarFrame:SetUnit(nil)
        end)
        -- TAINT SAFETY: Do NOT use hooksecurefunc on PlayerCastingBarFrame (secure frame).
        -- Even deferred callbacks taint the secure execution context.
        -- Use an OnUpdate watcher to re-hide if Blizzard shows it again.
        if not _blizzFrameGuards.castbarShowHooked then
            _blizzFrameGuards.castbarShowHooked = true
            local castbarHideWatcher = CreateFrame("Frame", nil, UIParent)
            castbarHideWatcher:SetScript("OnUpdate", function()
                -- Skip re-hiding during Edit Mode — PlayerCastingBarFrame visibility
                -- is used as a signal for the Cast Bar toggle checkbox. Re-hiding it
                -- would immediately undo the toggle and cause castbar previews to flash.
                if Helpers.IsEditModeActive() then return end
                if PlayerCastingBarFrame:IsShown() then
                    C_Timer.After(0, function()
                        if InCombatLockdown() then return end
                        pcall(function() PlayerCastingBarFrame:Hide() end)
                    end)
                end
            end)
        end
    end
    -- Hide pet castbar only when QUI pet frame is enabled.
    if db.enabled and db.pet and db.pet.enabled and PetCastingBarFrame then
        pcall(function()
            PetCastingBarFrame:SetAlpha(0)
            PetCastingBarFrame:SetScale(0.0001)
            PetCastingBarFrame:UnregisterAllEvents()
        end)
    end
end

function QUI_UF:HideBlizzardFrames()
    if InCombatLockdown() then return end
    local db = GetDB()
    if not db or not db.enabled then return end

    -- Hide Player frame
    if db.player and db.player.enabled then
        KillBlizzardFrame(PlayerFrame)
    end

    -- Hide Blizzard castbars
    self:HideBlizzardCastbars()

    -- Hide Target frame visuals (keep frame for auras/tooltips)
    if db.target and db.target.enabled then
        HideBlizzardTargetVisuals()
    end

    -- Hide Target of Target
    if db.targettarget and db.targettarget.enabled then
        KillBlizzardFrame(TargetFrameToT)
    end

    -- Hide Pet frame. Nil all four heal prediction bar references so
    -- UnitFrameHealPredictionBars_Update hits its early return:
    --   if (not myHealPredictionBar and not otherHealPredictionBar
    --       and not healAbsorbBar and not totalAbsorbBar) then return end
    -- Blizzard's managed frame system can re-initialize PetFrame after our
    -- kill, so a persistent watcher keeps these nil.
    if db.pet and db.pet.enabled and PetFrame then
        if PetFrame.healthbar then
            PetFrame.healthbar:UnregisterAllEvents()
            PetFrame.healthbar:SetScript("OnUpdate", nil)
        end
        if PetFrame.manabar then
            PetFrame.manabar:UnregisterAllEvents()
            PetFrame.manabar:SetScript("OnUpdate", nil)
        end
        PetFrame.myHealPredictionBar = nil
        PetFrame.otherHealPredictionBar = nil
        PetFrame.healAbsorbBar = nil
        PetFrame.totalAbsorbBar = nil
        KillBlizzardFrame(PetFrame)
        -- Persistent watcher: re-nil heal prediction refs if Blizzard restores them
        if not _blizzFrameGuards.petHealPredKill then
            _blizzFrameGuards.petHealPredKill = true
            local watcher = CreateFrame("Frame", nil, UIParent)
            watcher:SetScript("OnUpdate", function()
                if PetFrame.myHealPredictionBar or PetFrame.otherHealPredictionBar
                    or PetFrame.healAbsorbBar or PetFrame.totalAbsorbBar then
                    PetFrame.myHealPredictionBar = nil
                    PetFrame.otherHealPredictionBar = nil
                    PetFrame.healAbsorbBar = nil
                    PetFrame.totalAbsorbBar = nil
                end
            end)
        end
    end

    -- Hide Focus frame visuals (always hide Blizzard focus frame when QUI unit frames are enabled)
    HideBlizzardFocusVisuals()

    -- Hide Boss frames (allow in Edit Mode)
    if db.boss and db.boss.enabled then
        for i = 1, 5 do
            local bf = _G["Boss" .. i .. "TargetFrame"]
            KillBlizzardFrame(bf, true)
        end

        -- Fix Edit Mode crash: BossTargetFrameContainer.GetScaledSelectionSides() crashes
        -- when GetRect() returns nil (children moved off-screen).
        -- TAINT SAFETY: Do NOT replace GetScaledSelectionSides with an addon function.
        -- Direct method replacement taints the method in Midnight's taint model,
        -- causing ADDON_ACTION_FORBIDDEN when Edit Mode calls it in secure context.
        -- Instead, ensure the container always has valid bounds so GetRect() never
        -- returns nil, making the crash impossible.
        if BossTargetFrameContainer and not _blizzFrameGuards.bossContainerEditModeFixed then
            _blizzFrameGuards.bossContainerEditModeFixed = true

            -- Give container valid size and position so GetRect() always returns values
            BossTargetFrameContainer:SetSize(1, 1)
            if not BossTargetFrameContainer:GetPoint() then
                BossTargetFrameContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- HIDE BLIZZARD SELECTION FRAMES (Edit Mode)
---------------------------------------------------------------------------

-- Hide Blizzard's selection frames when QUI frames are enabled
-- Called during EnableEditMode() to prevent visual conflicts
-- TAINT SAFETY: All operations deferred to avoid tainting the secure frame context.
-- Selection frames are children of secure unit frames (PlayerFrame, TargetFrame, etc).
-- Synchronous Hide()/HookScript calls on these taint CompactUnitFrame values,
-- causing "secret number tainted by QUI" errors when Edit Mode reads them.
-- NOTE: Use SetAlpha(0) instead of Hide(). Hidden frames return nil from
-- GetRect(), crashing GetScaledSelectionSides() in Blizzard's magnetic snap loop.

