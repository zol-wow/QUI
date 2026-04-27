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

    -- NOTE: Do NOT use RegisterStateDriver(frame, "visibility", "hide") here.
    -- Hidden frames return nil from GetRect(), which crashes Blizzard's
    -- GetScaledSelectionSides() when the Edit Mode magnetic snap system
    -- iterates all registered systems. Keep the original geometry intact:
    -- touching ClearAllPoints/SetPoint on secure Blizzard unit frames taints
    -- their layout data and later trips ADDON_ACTION_BLOCKED inside Blizzard's
    -- secure position managers (for example PetFrame:ClearAllPointsBase()).
end

-- Hidden parent for evicted protected frames. Sized to UIParent so children's
-- GetRect() returns valid geometry (matters for EditMode magnetic-snap loop's
-- GetScaledSelectionSides() which crashes on nil-rect frames). Mirrors the
-- ElvUI/oUF hiddenParent pattern.
local _hiddenPetParent
local _petReevictPending = false

local function GetHiddenPetParent()
    if not _hiddenPetParent then
        _hiddenPetParent = CreateFrame("Frame", nil, UIParent)
        _hiddenPetParent:SetAllPoints()
        _hiddenPetParent:Hide()
    end
    return _hiddenPetParent
end

local function EvictPetFrameToHiddenParent()
    if not PetFrame then return end
    local hidden = GetHiddenPetParent()
    if PetFrame:GetParent() == hidden then return end
    if InCombatLockdown() then
        _petReevictPending = true
        return
    end
    PetFrame:SetParent(hidden)
end

local function SuppressBlizzardPetFrame()
    if not PetFrame then return end

    -- Reparent PetFrame off PlayerFrameBottomManagedFramesContainer so the
    -- container's combat-triggered Layout pass (fired by TotemFrame/pet/vehicle
    -- SetShown events) no longer iterates PetFrame via :GetChildren() and
    -- never reads any field from it. Mirrors ElvUI/oUF's approach.
    --
    -- Why reparent instead of ignoreInLayout: setting PetFrame.ignoreInLayout
    -- works to skip PetFrame in iteration, but the addon-write taints the
    -- field. LayoutMixin reads region.ignoreInLayout for every region in every
    -- Layout pass; that read propagates the addon taint into Layout's secure
    -- execution context, which then surfaces at the parent's self:SetSize()
    -- call (verified empirically: ignoreInLayout fix moved the block from
    -- PetFrame:ClearAllPointsBase to PlayerFrameBottomManagedFramesContainer
    -- :SetSize). Reparenting removes PetFrame from :GetChildren() entirely,
    -- so no field on PetFrame is read by any Layout pass — no taint surface.
    --
    -- The SetParent call from insecure code does taint PetFrame, but with
    -- PetFrame outside the Layout iteration, that taint has no surface.
    --
    -- Hook on PetFrame:SetParent re-evicts whenever Blizzard re-parents back
    -- (pet summon, vehicle exit, login). Combat-deferred via _petReevictPending
    -- + PLAYER_REGEN_ENABLED watcher because SetParent on a protected frame
    -- is itself protected during combat.
    if not _blizzFrameGuards.petFrameReparented then
        _blizzFrameGuards.petFrameReparented = true

        hooksecurefunc(PetFrame, "SetParent", function(self, parent)
            if parent ~= GetHiddenPetParent() then
                EvictPetFrameToHiddenParent()
            end
        end)

        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        watcher:SetScript("OnEvent", function()
            if _petReevictPending then
                _petReevictPending = false
                EvictPetFrameToHiddenParent()
            end
        end)

        EvictPetFrameToHiddenParent()
    end

    -- Visual suppression. Method calls only — no frame-table writes.
    pcall(PetFrame.SetAlpha, PetFrame, 0)
    pcall(PetFrame.EnableMouse, PetFrame, false)
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

    -- Hide Pet frame without mutating Blizzard's protected frame internals.
    -- Warlock pets make PetFrame participate in managed Edit Mode layout
    -- passes; nil'ing heal prediction fields or unregistering child scripts
    -- taints the frame and surfaces as PetFrame:ClearAllPointsBase() blocks
    -- when the user's saved Blizzard layout is malformed.
    if db.pet and db.pet.enabled and PetFrame then
        SuppressBlizzardPetFrame()
    end

    -- Hide Focus frame visuals (always hide Blizzard focus frame when QUI unit frames are enabled)
    HideBlizzardFocusVisuals()

    -- Hide Boss frames (allow in Edit Mode)
    if db.boss and db.boss.enabled then
        -- TAINT SAFETY: Remove BossTargetFrameContainer from the managed layout
        -- chain BEFORE touching any geometry. The container is a child of
        -- UIParentRightManagedFrameContainer; addon-code SetSize/SetPoint/
        -- ClearAllPoints calls taint its geometry data, and the next
        -- UIParentManageRightFrameContainer layout pass propagates the taint to
        -- ClearAllPoints() on the container -> ADDON_ACTION_BLOCKED.
        if BossTargetFrameContainer and not _blizzFrameGuards.bossContainerRemovedFromManaged then
            _blizzFrameGuards.bossContainerRemovedFromManaged = true
            local parent = BossTargetFrameContainer:GetParent()
            if parent and parent.RemoveManagedFrame then
                pcall(parent.RemoveManagedFrame, parent, BossTargetFrameContainer)
            end
            BossTargetFrameContainer.ignoreFramePositionManager = true
        end

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

