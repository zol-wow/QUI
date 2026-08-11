local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local eventFrame = CreateFrame("Frame")
local combatEventsRegistered = false

local GetSettings = Helpers.CreateDBGetter("general")

local PET_SPEC_IDS = {
    [253] = true,
    [255] = true,
    [265] = true,
    [266] = true,
    [267] = true,
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

local PetWarningFrame = CreateFrame("Frame", "QUI_PetWarningFrame", UIParent, "BackdropTemplate")
PetWarningFrame:SetSize(220, 50)
PetWarningFrame:SetFrameStrata("HIGH")
PetWarningFrame:Hide()

do
    local bgr, bgg, bgb = 0.1, 0.1, 0.1
    if Helpers and Helpers.GetSkinBgColor then
        bgr, bgg, bgb = Helpers.GetSkinBgColor()
    end
    local sr, sg, sb = 1, 0.3, 0.3
    if SkinBase and SkinBase.CreateBackdrop then
        SkinBase.CreateBackdrop(PetWarningFrame, sr, sg, sb, 1, bgr, bgg, bgb, 0.9)
    elseif SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(PetWarningFrame, 2, true, false, { sr, sg, sb, 1 }, { bgr, bgg, bgb, 0.9 })
    end
end

PetWarningFrame.icon = PetWarningFrame:CreateTexture(nil, "ARTWORK")
PetWarningFrame.icon:SetSize(32, 32)
PetWarningFrame.icon:SetPoint("LEFT", PetWarningFrame, "LEFT", 10, 0)
PetWarningFrame.icon:SetTexture(132599)

PetWarningFrame.text = PetWarningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
PetWarningFrame.text:SetPoint("LEFT", PetWarningFrame.icon, "RIGHT", 10, 0)
PetWarningFrame.text:SetPoint("RIGHT", PetWarningFrame, "RIGHT", -30, 0)
PetWarningFrame.text:SetTextColor(1, 0.3, 0.3, 1)
PetWarningFrame.text:SetText(ns.L["NO PET!"])

PetWarningFrame.closeBtn = CreateFrame("Button", nil, PetWarningFrame)
PetWarningFrame.closeBtn:SetSize(20, 20)
PetWarningFrame.closeBtn:SetPoint("RIGHT", PetWarningFrame, "RIGHT", -8, 0)

PetWarningFrame.closeBtn.bg = PetWarningFrame.closeBtn:CreateTexture(nil, "BACKGROUND")
PetWarningFrame.closeBtn.bg:SetAllPoints()
PetWarningFrame.closeBtn.bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)

PetWarningFrame.closeBtn.text = PetWarningFrame.closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
PetWarningFrame.closeBtn.text:SetPoint("CENTER")
PetWarningFrame.closeBtn.text:SetText(ns.L["X"])
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

local function PositionPetWarningFrame()
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("petWarning") then return end

    local settings = GetSettings()
    local xOffset = (settings and settings.petWarningOffsetX) or 0
    local yOffset = (settings and settings.petWarningOffsetY) or -200

    PetWarningFrame:ClearAllPoints()
    PetWarningFrame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)
end

PositionPetWarningFrame()

local petWarningTicker = nil
local currentWarningState = nil

local function ClearPetWarning()
    PetWarningFrame:Hide()
    if LCG and PetWarningFrame.glowActive then
        LCG.PixelGlow_Stop(PetWarningFrame, "_QUIPetWarning")
        PetWarningFrame.glowActive = false
    end
    currentWarningState = nil
end

local function UpdatePetWarningState()
    if PetWarningFrame.dismissedThisFight then
        return false
    end

    local settings = GetSettings()
    if not settings or settings.petCombatWarning == false then
        ClearPetWarning()
        return false
    end

    if not IsPetSpec() then
        ClearPetWarning()
        return false
    end

    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
        ClearPetWarning()
        return false
    end

    if not UnitExists("pet") then
        PetWarningFrame.text:SetText(ns.L["NO PET SUMMONED!"])
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

    if IsPetOnPassive() then
        PetWarningFrame.text:SetText(ns.L["PET IS ON PASSIVE!"])
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

    ClearPetWarning()
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

    ClearPetWarning()

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

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        StartPetWarningPolling()
    elseif event == "PLAYER_REGEN_ENABLED" then
        StopPetWarningPolling()
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        UpdatePetWarningEventRegistration()
        if InCombatLockdown() and combatEventsRegistered then
            StartPetWarningPolling()
        end
    end)
end

_G.QUI_RepositionPetWarning = PositionPetWarningFrame
_G.QUI_RefreshPetWarning = function()
    PositionPetWarningFrame()
    UpdatePetWarningEventRegistration()
    local bgr, bgg, bgb = 0.1, 0.1, 0.1
    if Helpers and Helpers.GetSkinBgColor then
        bgr, bgg, bgb = Helpers.GetSkinBgColor()
    end
    local sr, sg, sb = 1, 0.3, 0.3
    if SkinBase and SkinBase.CreateBackdrop then
        SkinBase.CreateBackdrop(PetWarningFrame, sr, sg, sb, 1, bgr, bgg, bgb, 0.9)
    else
        PetWarningFrame:SetBackdropColor(bgr, bgg, bgb, 0.9)
    end
    if InCombatLockdown() and combatEventsRegistered then
        StartPetWarningPolling()
    else
        StopPetWarningPolling()
    end
end

_G.QUI_TogglePetWarningPreview = function(show)
    if show then
        PositionPetWarningFrame()
        PetWarningFrame.text:SetText(ns.L["PET WARNING PREVIEW"])
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

if ns.Registry then
    ns.Registry:Register("petWarning", {
        refresh = _G.QUI_RefreshPetWarning,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
    ns.Registry:Register("petWarningSkin", {
        refresh = _G.QUI_RefreshPetWarning,
        priority = 30,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
