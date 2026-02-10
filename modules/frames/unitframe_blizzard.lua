---------------------------------------------------------------------------
-- QUI Unit Frames - Blizzard Frame Hiding
-- Hides/kills default Blizzard unit frames when QUI replacements are active.
-- Extracted from modules/frames/unitframes.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiUnitFrames")

local QUI = _G.QuaziiUI or _G.QUI

-- QUI_UF is created in unitframes.lua and exported to ns.QUI_UnitFrames.
-- This file loads after unitframes.lua, so the reference is available.
local QUI_UF = ns.QUI_UnitFrames
if not QUI_UF then return end

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

    -- Use RegisterStateDriver to keep it hidden (works with secure frames)
    if not InCombatLockdown() then
        RegisterStateDriver(frame, "visibility", "hide")
    end
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

    frame:SetScript("OnShow", function(f)
        pcall(function() f:Hide() end)
        f:SetAlpha(0)
    end)
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

function QUI_UF:HideBlizzardFrames()
    local db = GetDB()
    if not db or not db.enabled then return end

    -- Hide Player frame
    if db.player and db.player.enabled then
        KillBlizzardFrame(PlayerFrame)
    end

    -- Hide Blizzard Player Castbar if our QUI player castbar is enabled
    -- NOTE: As of 12.0.x beta, CastingBarFrame can be a forbidden/restricted frame.
    -- All interactions are wrapped in pcall to prevent errors from blocking initialization.
    if db.player and db.player.castbar and db.player.castbar.enabled then
        if PlayerCastingBarFrame then
            local ok, err = pcall(function()
                PlayerCastingBarFrame:SetAlpha(0)
                PlayerCastingBarFrame:SetScale(0.0001)
                PlayerCastingBarFrame:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -10000, 10000)
                PlayerCastingBarFrame:UnregisterAllEvents()
            end)
            if not ok then QUI:DebugPrint("Could not hide PlayerCastingBarFrame: " .. tostring(err)) end
            local ok2, err2 = pcall(function()
                PlayerCastingBarFrame:SetUnit(nil)
            end)
            if not ok2 then QUI:DebugPrint("Could not detach PlayerCastingBarFrame unit: " .. tostring(err2)) end
            local ok3, err3 = pcall(function()
                if not PlayerCastingBarFrame._quiShowHooked then
                    PlayerCastingBarFrame._quiShowHooked = true
                    hooksecurefunc(PlayerCastingBarFrame, "Show", function(self)
                        pcall(function() self:Hide() end)
                    end)
                end
            end)
            if not ok3 then QUI:DebugPrint("Could not hook PlayerCastingBarFrame:Show: " .. tostring(err3)) end
        end
        -- Also hide the pet castbar if it exists
        if PetCastingBarFrame then
            local ok, err = pcall(function()
                PetCastingBarFrame:SetAlpha(0)
                PetCastingBarFrame:SetScale(0.0001)
                PetCastingBarFrame:UnregisterAllEvents()
            end)
            if not ok then QUI:DebugPrint("Could not hide PetCastingBarFrame: " .. tostring(err)) end
        end
    end

    -- Hide Target frame visuals (keep frame for auras/tooltips)
    if db.target and db.target.enabled then
        HideBlizzardTargetVisuals()
    end

    -- Hide Target of Target
    if db.targettarget and db.targettarget.enabled then
        KillBlizzardFrame(TargetFrameToT)
    end

    -- Hide Pet frame
    if db.pet and db.pet.enabled then
        KillBlizzardFrame(PetFrame)
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
        -- Hook the crashing function directly to return safe fallback values.
        if BossTargetFrameContainer and not BossTargetFrameContainer._quiEditModeFixed then
            -- Hook GetScaledSelectionSides to handle nil GetRect case
            if BossTargetFrameContainer.GetScaledSelectionSides then
                local originalGetScaledSelectionSides = BossTargetFrameContainer.GetScaledSelectionSides
                BossTargetFrameContainer.GetScaledSelectionSides = function(self)
                    local left, bottom, width, height = self:GetRect()
                    if left == nil then
                        -- Return off-screen fallback sides (left, right, bottom, top)
                        return -10000, -9999, 10000, 10001
                    end
                    return originalGetScaledSelectionSides(self)
                end
            end

            -- Also try to give container valid bounds as backup
            BossTargetFrameContainer:SetSize(1, 1)
            if not BossTargetFrameContainer:GetPoint() then
                BossTargetFrameContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end

            BossTargetFrameContainer._quiEditModeFixed = true
        end
    end
end

---------------------------------------------------------------------------
-- HIDE BLIZZARD SELECTION FRAMES (Edit Mode)
---------------------------------------------------------------------------

-- Hide Blizzard's selection frames when QUI frames are enabled
-- Called during EnableEditMode() to prevent visual conflicts
function QUI_UF:HideBlizzardSelectionFrames()
    local function HideSelection(parent, unitKey)
        if not parent or not parent.Selection then return end

        local db = GetDB()
        if not db or not db[unitKey] or not db[unitKey].enabled then return end

        parent.Selection:Hide()

        -- Hook OnShow to persistently hide while QUI frames are enabled
        if not parent.Selection._quiHooked then
            parent.Selection._quiHooked = true
            parent.Selection:HookScript("OnShow", function(self)
                local db = GetDB()
                if db and db[unitKey] and db[unitKey].enabled then
                    self:Hide()
                end
            end)
        end
    end

    HideSelection(PlayerFrame, "player")
    HideSelection(TargetFrame, "target")
    HideSelection(FocusFrame, "focus")
    HideSelection(PetFrame, "pet")
    HideSelection(TargetFrameToT, "targettarget")
    -- Boss frames use Blizzard's boss frames which are separate
end
