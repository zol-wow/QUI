local addonName, ns = ...

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore

local iconOverlays = Helpers.CreateStateTable()
local cooldownRefreshPending = false

local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.mplusTeleportEnabled ~= false
end

local function UpdateCooldown(overlay)
    local cooldown = overlay and overlay.cooldown
    if not cooldown then return end

    if not Helpers.CanMutateCooldown(cooldown) then
        cooldownRefreshPending = true
        return
    end
    local duration = overlay.spellID and C_Spell and C_Spell.GetSpellCooldownDuration
        and C_Spell.GetSpellCooldownDuration(overlay.spellID, true)
    if duration then
        cooldown:SetCooldownFromDurationObject(duration)
    else
        cooldown:Clear()
    end
end

local function CreateSecureOverlay(dungeonIcon)
    if not dungeonIcon or not dungeonIcon.mapID then return end
    if InCombatLockdown() then return end

    local spellID = _G.QUI_DungeonData and _G.QUI_DungeonData.GetTeleportSpellID(dungeonIcon.mapID)
    local overlay = iconOverlays[dungeonIcon]

    if overlay then
        overlay.dungeonIcon = dungeonIcon
        overlay.mapID = dungeonIcon.mapID
        overlay.spellID = spellID

        if spellID then
            overlay:SetAttribute("type", "spell")
            overlay:SetAttribute("spell", spellID)
            overlay:EnableMouse(true)
            overlay:Show()
        else
            overlay:SetAttribute("spell", nil)
            overlay:EnableMouse(false)
            overlay:Hide()
        end

        return overlay
    end

    if not spellID then return end

    overlay = CreateFrame("Button", nil, dungeonIcon, "SecureActionButtonTemplate")
    overlay:SetAllPoints(dungeonIcon)
    overlay:SetFrameLevel(dungeonIcon:GetFrameLevel() + 10)

    overlay:SetAttribute("type", "spell")
    overlay:SetAttribute("spell", spellID)
    overlay:RegisterForClicks("AnyUp", "AnyDown")

    overlay.spellID = spellID
    overlay.mapID = dungeonIcon.mapID
    overlay.dungeonIcon = dungeonIcon

    overlay.cooldown = CreateFrame("Cooldown", nil, overlay, "CooldownFrameTemplate")
    overlay.cooldown:SetAllPoints()
    overlay.cooldown:Show()

    local highlight = overlay:CreateTexture(nil, "OVERLAY")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 1, 0.5, 0.3)
    highlight:Hide()
    overlay.highlight = highlight

    overlay:SetScript("OnEnter", function(self)
        local currentSpellID = self.spellID
        local icon = self.dungeonIcon

        if currentSpellID and IsSpellKnown(currentSpellID) then
            highlight:Show()
        end
        if icon and icon.OnEnter then
            icon:OnEnter()
        end
    end)

    overlay:SetScript("OnLeave", function(self)
        highlight:Hide()
        local icon = self.dungeonIcon
        if icon and icon.OnLeave then
            icon:OnLeave()
        end
    end)

    iconOverlays[dungeonIcon] = overlay
    return overlay
end

local function HookDungeonIcons()
    if not ChallengesFrame or not ChallengesFrame.DungeonIcons then return end

    for _, dungeonIcon in ipairs(ChallengesFrame.DungeonIcons) do
        if dungeonIcon.mapID then
            UpdateCooldown(CreateSecureOverlay(dungeonIcon))
        end
    end
end

local function UpdateCooldowns()
    cooldownRefreshPending = false
    for _, overlay in pairs(iconOverlays) do
        UpdateCooldown(overlay)
    end
end

local function OnChallengesFrameUpdate()
    if not IsEnabled() then return end
    C_Timer.After(0.1, HookDungeonIcons)
end

local hooked = false

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "SPELL_UPDATE_COOLDOWN" or (event == "PLAYER_REGEN_ENABLED" and cooldownRefreshPending) then
        UpdateCooldowns()
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
        if not hooked and ChallengesFrame then
            hooksecurefunc(ChallengesFrame, "Update", OnChallengesFrameUpdate)
            hooked = true
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

if C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
    if not hooked and ChallengesFrame then
        hooksecurefunc(ChallengesFrame, "Update", OnChallengesFrameUpdate)
        hooked = true
    end
end
