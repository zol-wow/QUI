local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiUnitFrames")

local pcall = pcall
local issecretvalue = issecretvalue or function() return false end
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

local QUI = _G.QuaziiUI or _G.QUI

local QUI_UF = ns.QUI_UnitFrames
if not QUI_UF then return end

local _blizzFrameGuards = {}

local _hookedOnShowFrames = Helpers.CreateStateTable()

local function KillBlizzardFrame(frame, allowInEditMode)
    if not frame then return end

    frame:UnregisterAllEvents()

    frame:SetAlpha(0)
    frame:EnableMouse(false)

end

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

    ns.SafeCallMethod("best-effort-style", PetFrame, "SetAlpha", 0)
    ns.SafeCallMethod("best-effort-style", PetFrame, "EnableMouse", false)
end

local function KillBlizzardChildFrame(frame)
    if not frame then return end
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end

    ns.SafeCall("best-effort-style", function() frame:Hide() end)

    if frame.EnableMouse then
        frame:EnableMouse(false)
    end

    frame:SetAlpha(0)

    if not _hookedOnShowFrames[frame] then
        _hookedOnShowFrames[frame] = true
        Helpers.DeferredHideOnShow(frame, { clearAlpha = true, combatCheck = false })
    end
end

local function SuppressPlayerCastingBarFrame()
    local frame = PlayerCastingBarFrame
    if not frame then return end

    ns.SafeCall("best-effort-style", function()
        frame:SetAlpha(0)
        frame:SetScale(0.0001)
        frame:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -10000, 10000)
        frame:SetUnit(nil)
        frame:UnregisterAllEvents()
        frame:Hide()
    end)

    if frame.Icon then
        ns.SafeCall("best-effort-style", function()
            frame.Icon:SetAlpha(0)
            frame.Icon:Hide()
        end)
    end
end

local function QueuePlayerCastingBarSuppression()
    if _blizzFrameGuards.castbarSuppressPending then return end
    _blizzFrameGuards.castbarSuppressPending = true

    C_Timer.After(0, function()
        _blizzFrameGuards.castbarSuppressPending = false
        if InCombatLockdown() or Helpers.IsEditModeActive() then return end
        SuppressPlayerCastingBarFrame()
    end)
end

local castbarHideWatcher
local castbarWatcherCanIdle = false

local function CastbarWatcherOnUpdate()
    if Helpers.IsEditModeActive() then return end

    local frame = PlayerCastingBarFrame
    if not frame then return end

    local ok, isShown = ns.SafeCallMethod("best-effort-style", frame, "IsShown")
    if not ok or issecretvalue(isShown) then return end
    if isShown then
        QueuePlayerCastingBarSuppression()
    elseif castbarWatcherCanIdle then
        castbarHideWatcher:Hide()
    end
end

local function ResumeCastbarHideWatcher()
    if castbarHideWatcher then
        castbarHideWatcher:Show()
    end
end

local function EnsurePlayerCastbarHideWatcher()
    if _blizzFrameGuards.castbarShowHooked then return end
    _blizzFrameGuards.castbarShowHooked = true

    castbarHideWatcher = CreateFrame("Frame", nil, UIParent)
    castbarHideWatcher:SetScript("OnUpdate", CastbarWatcherOnUpdate)

    local hooked = ns.SafeCallMethodIfPresent("best-effort-style", PlayerCastingBarFrame,
        "HookScript", "OnShow", ResumeCastbarHideWatcher)
    castbarWatcherCanIdle = hooked == true
end

local function HideBlizzardSecondaryUnitVisuals(frame, globalPrefix)
    if not frame then return end

    KillBlizzardChildFrame(frame.TargetFrameContainer)
    KillBlizzardChildFrame(frame.TargetFrameContent)
    KillBlizzardChildFrame(frame.healthbar)
    KillBlizzardChildFrame(frame.manabar)
    KillBlizzardChildFrame(frame.powerBarAlt)
    KillBlizzardChildFrame(frame.overAbsorbGlow)
    KillBlizzardChildFrame(frame.overHealAbsorbGlow)
    KillBlizzardChildFrame(frame.totalAbsorbBar)
    KillBlizzardChildFrame(frame.tempMaxHealthLossBar)
    KillBlizzardChildFrame(frame.myHealPredictionBar)
    KillBlizzardChildFrame(frame.otherHealPredictionBar)
    KillBlizzardChildFrame(frame.name)
    KillBlizzardChildFrame(frame.portrait)
    KillBlizzardChildFrame(frame.threatIndicator)
    KillBlizzardChildFrame(frame.threatNumericIndicator)

    KillBlizzardChildFrame(frame.BuffFrame)
    KillBlizzardChildFrame(frame.DebuffFrame)
    KillBlizzardChildFrame(frame.buffsContainer)
    KillBlizzardChildFrame(frame.debuffsContainer)

    for i = 1, 40 do
        KillBlizzardChildFrame(_G[globalPrefix.."Buff"..i])
        KillBlizzardChildFrame(_G[globalPrefix.."Debuff"..i])
    end

    if frame.auraPools and frame.auraPools.ReleaseAll then
        frame.auraPools:ReleaseAll()
    end

    KillBlizzardFrame(frame)
end

local function HideBlizzardTargetVisuals()
    HideBlizzardSecondaryUnitVisuals(TargetFrame, "TargetFrame")
end

local function HideBlizzardFocusVisuals()
    HideBlizzardSecondaryUnitVisuals(FocusFrame, "FocusFrame")
end

function QUI_UF:HideBlizzardCastbars()
    if InCombatLockdown() then return end
    local db = GetDB()
    if not db then return end
    local playerDB = db.player
    local playerFrameEnabled = playerDB and playerDB.enabled
    local playerCastbarEnabled = playerDB and (playerDB.castbar == nil or playerDB.castbar.enabled ~= false)
    local standaloneActive = playerDB and playerDB.standaloneCastbar and not playerFrameEnabled and playerCastbarEnabled
    local shouldHidePlayerCastbar = (playerFrameEnabled and playerCastbarEnabled) or standaloneActive
    if not shouldHidePlayerCastbar then return end

    EnsurePlayerCastbarHideWatcher()
    SuppressPlayerCastingBarFrame()

    if db.pet and db.pet.enabled and PetCastingBarFrame then
        ns.SafeCall("best-effort-style", function()
            PetCastingBarFrame:SetAlpha(0)
            PetCastingBarFrame:SetScale(0.0001)
            PetCastingBarFrame:UnregisterAllEvents()
        end)
    end
end

function QUI_UF:HideBlizzardFrames()
    if InCombatLockdown() then return end
    local db = GetDB()
    if not db then return end

    if db.player and db.player.enabled then
        KillBlizzardFrame(PlayerFrame)
    end

    self:HideBlizzardCastbars()

    if db.target and db.target.enabled then
        HideBlizzardTargetVisuals()
    end

    if db.targettarget and db.targettarget.enabled then
        KillBlizzardFrame(TargetFrameToT)
    end

    if db.pet and db.pet.enabled and PetFrame then
        SuppressBlizzardPetFrame()
    end

    if db.focus and db.focus.enabled then
        HideBlizzardFocusVisuals()
    end

    if db.boss and db.boss.enabled then
        if BossTargetFrameContainer and not _blizzFrameGuards.bossContainerRemovedFromManaged then
            _blizzFrameGuards.bossContainerRemovedFromManaged = true
            local parent = BossTargetFrameContainer:GetParent()
            ns.SafeCallMethodIfPresent("best-effort-style", parent, "RemoveManagedFrame", BossTargetFrameContainer)
            BossTargetFrameContainer.ignoreFramePositionManager = true
        end

        for i = 1, 5 do
            local bf = _G["Boss" .. i .. "TargetFrame"]
            KillBlizzardFrame(bf, true)
        end

        if BossTargetFrameContainer and not _blizzFrameGuards.bossContainerEditModeFixed then
            _blizzFrameGuards.bossContainerEditModeFixed = true

            BossTargetFrameContainer:SetSize(1, 1)
            if not BossTargetFrameContainer:GetPoint() then
                BossTargetFrameContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    end
end
