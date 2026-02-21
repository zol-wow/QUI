local addonName, ns = ...
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- PET WARNING
-- Warns pet-spec players when pet is missing or on passive
-- Shows during combat in instances (dungeons/raids)
---------------------------------------------------------------------------

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local eventFrame = CreateFrame("Frame")
local combatEventsRegistered = false

local function GetSettings()
    return Helpers.GetModuleDB("general")
end

---------------------------------------------------------------------------
-- PET SPEC DETECTION
---------------------------------------------------------------------------

-- Spec IDs that have permanent pets
local PET_SPEC_IDS = {
    -- Hunter: Beast Mastery (253), Survival (255)
    [253] = true,
    [255] = true,
    -- Warlock: Affliction (265), Demonology (266), Destruction (267)
    [265] = true,
    [266] = true,
    [267] = true,
    -- Death Knight: Unholy (252)
    [252] = true,
}

local function IsPetSpec()
    local specIndex = GetSpecialization()
    if not specIndex then return false end

    local specID = GetSpecializationInfo(specIndex)
    return specID and PET_SPEC_IDS[specID] or false
end

local function IsPetOnPassive()
    if not UnitExists("pet") then return false end

    for i = 1, 10 do
        local name, _, isToken, isActive = GetPetActionInfo(i)
        if name and isToken and isActive and name == "PET_MODE_PASSIVE" then
            return true
        end
    end

    return false
end

---------------------------------------------------------------------------
-- PET COMBAT WARNING FRAME
---------------------------------------------------------------------------

local PetWarningFrame = CreateFrame("Frame", "QUI_PetWarningFrame", UIParent, "BackdropTemplate")
PetWarningFrame:SetSize(220, 50)
PetWarningFrame:SetFrameStrata("HIGH")
PetWarningFrame:Hide()

PetWarningFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 2,
})
PetWarningFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
PetWarningFrame:SetBackdropBorderColor(1, 0.3, 0.3, 1)

PetWarningFrame.icon = PetWarningFrame:CreateTexture(nil, "ARTWORK")
PetWarningFrame.icon:SetSize(32, 32)
PetWarningFrame.icon:SetPoint("LEFT", PetWarningFrame, "LEFT", 10, 0)
PetWarningFrame.icon:SetTexture(132599)

PetWarningFrame.text = PetWarningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
PetWarningFrame.text:SetPoint("LEFT", PetWarningFrame.icon, "RIGHT", 10, 0)
PetWarningFrame.text:SetPoint("RIGHT", PetWarningFrame, "RIGHT", -30, 0)
PetWarningFrame.text:SetTextColor(1, 0.3, 0.3, 1)
PetWarningFrame.text:SetText("NO PET!")

-- Close button to dismiss warning for rest of fight
PetWarningFrame.closeBtn = CreateFrame("Button", nil, PetWarningFrame)
PetWarningFrame.closeBtn:SetSize(20, 20)
PetWarningFrame.closeBtn:SetPoint("RIGHT", PetWarningFrame, "RIGHT", -8, 0)

PetWarningFrame.closeBtn.bg = PetWarningFrame.closeBtn:CreateTexture(nil, "BACKGROUND")
PetWarningFrame.closeBtn.bg:SetAllPoints()
PetWarningFrame.closeBtn.bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)

PetWarningFrame.closeBtn.text = PetWarningFrame.closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
PetWarningFrame.closeBtn.text:SetPoint("CENTER")
PetWarningFrame.closeBtn.text:SetText("X")
PetWarningFrame.closeBtn.text:SetTextColor(0.8, 0.8, 0.8, 1)

PetWarningFrame.closeBtn:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(0.5, 0.2, 0.2, 0.9)
    self.text:SetTextColor(1, 1, 1, 1)
end)
PetWarningFrame.closeBtn:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    self.text:SetTextColor(0.8, 0.8, 0.8, 1)
end)
PetWarningFrame.closeBtn:SetScript("OnClick", function()
    PetWarningFrame.dismissedThisFight = true
    PetWarningFrame:Hide()
    if LCG then
        LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
        PetWarningFrame.glowActive = false
    end
end)

PetWarningFrame.dismissedThisFight = false

---------------------------------------------------------------------------
-- POSITIONING
---------------------------------------------------------------------------

local function PositionPetWarningFrame()
    local settings = GetSettings()
    local xOffset = (settings and settings.petWarningOffsetX) or 0
    local yOffset = (settings and settings.petWarningOffsetY) or -200

    PetWarningFrame:ClearAllPoints()
    PetWarningFrame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)
end

PositionPetWarningFrame()

---------------------------------------------------------------------------
-- COMBAT POLLING
---------------------------------------------------------------------------

local petWarningTicker = nil
local currentWarningState = nil

local function UpdatePetWarningState()
    if PetWarningFrame.dismissedThisFight then
        return false
    end

    local settings = GetSettings()
    if not settings or settings.petCombatWarning == false then
        PetWarningFrame:Hide()
        if LCG and PetWarningFrame.glowActive then
            LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
            PetWarningFrame.glowActive = false
        end
        currentWarningState = nil
        return false
    end

    if not IsPetSpec() then
        PetWarningFrame:Hide()
        if LCG and PetWarningFrame.glowActive then
            LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
            PetWarningFrame.glowActive = false
        end
        currentWarningState = nil
        return false
    end

    -- Only warn in instances
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
        PetWarningFrame:Hide()
        if LCG and PetWarningFrame.glowActive then
            LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
            PetWarningFrame.glowActive = false
        end
        currentWarningState = nil
        return false
    end

    -- Check for missing pet
    if not UnitExists("pet") then
        PetWarningFrame.text:SetText("NO PET SUMMONED!")
        PetWarningFrame.icon:SetTexture(132599)
        PetWarningFrame:Show()
        if LCG and (currentWarningState ~= "nopet" or not PetWarningFrame.glowActive) then
            LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
            LCG.PixelGlow_Start(PetWarningFrame, {1, 0.3, 0.3, 1}, 8, 0.25, nil, 3, 0, 0, false, "_QUIPetWarning")
            PetWarningFrame.glowActive = true
        end
        currentWarningState = "nopet"
        return true
    end

    -- Check for passive stance
    if IsPetOnPassive() then
        PetWarningFrame.text:SetText("PET IS ON PASSIVE!")
        PetWarningFrame.icon:SetTexture(132311)
        PetWarningFrame:Show()
        if LCG and (currentWarningState ~= "passive" or not PetWarningFrame.glowActive) then
            LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
            LCG.PixelGlow_Start(PetWarningFrame, {1, 0.8, 0, 1}, 8, 0.25, nil, 3, 0, 0, false, "_QUIPetWarning")
            PetWarningFrame.glowActive = true
        end
        currentWarningState = "passive"
        return true
    end

    -- Pet is fine
    PetWarningFrame:Hide()
    if LCG and PetWarningFrame.glowActive then
        LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
        PetWarningFrame.glowActive = false
    end
    currentWarningState = nil
    return false
end

local function StartPetWarningPolling()
    if petWarningTicker then
        petWarningTicker:Cancel()
        petWarningTicker = nil
    end

    PositionPetWarningFrame()
    UpdatePetWarningState()

    petWarningTicker = C_Timer.NewTicker(0.5, UpdatePetWarningState)
end

local function StopPetWarningPolling()
    if petWarningTicker then
        petWarningTicker:Cancel()
        petWarningTicker = nil
    end

    PetWarningFrame:Hide()
    if LCG and PetWarningFrame.glowActive then
        LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
        PetWarningFrame.glowActive = false
    end
    currentWarningState = nil

    PetWarningFrame.dismissedThisFight = false
end

local function SetCombatEventsRegistered(shouldRegister)
    if shouldRegister and not combatEventsRegistered then
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        combatEventsRegistered = true
    elseif not shouldRegister and combatEventsRegistered then
        eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        combatEventsRegistered = false
    end
end

local function UpdatePetWarningEventRegistration()
    local settings = GetSettings()
    local enabled = settings and settings.petCombatWarning ~= false
    SetCombatEventsRegistered(enabled)
    if not enabled then
        StopPetWarningPolling()
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            UpdatePetWarningEventRegistration()
            if InCombatLockdown() and combatEventsRegistered then
                StartPetWarningPolling()
            end
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        StartPetWarningPolling()
    elseif event == "PLAYER_REGEN_ENABLED" then
        StopPetWarningPolling()
    end
end)

---------------------------------------------------------------------------
-- GLOBAL API (for options panel)
---------------------------------------------------------------------------

_G.QUI_RepositionPetWarning = PositionPetWarningFrame
_G.QUI_RefreshPetWarning = function()
    PositionPetWarningFrame()
    UpdatePetWarningEventRegistration()
    if InCombatLockdown() and combatEventsRegistered then
        StartPetWarningPolling()
    else
        StopPetWarningPolling()
    end
end

_G.QUI_TogglePetWarningPreview = function(show)
    if show then
        PositionPetWarningFrame()
        PetWarningFrame.text:SetText("PET WARNING PREVIEW")
        PetWarningFrame.icon:SetTexture(132599)
        PetWarningFrame:Show()
        if LCG then
            LCG.PixelGlow_Start(PetWarningFrame, {1, 0.3, 0.3, 1}, 8, 0.25, nil, 3, 0, 0, false, "_QUIPetWarning")
            PetWarningFrame.glowActive = true
        end
    else
        PetWarningFrame:Hide()
        if LCG then
            LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
            PetWarningFrame.glowActive = false
        end
    end
end
