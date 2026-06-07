local addonName, ns = ...

---------------------------------------------------------------------------
-- M+ DUNGEON TELEPORT MODULE
-- Feature: Click-to-teleport on M+ tab dungeon icons
-- Uses shared dungeon data from qui_dungeon_data.lua
---------------------------------------------------------------------------

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore

-- TAINT SAFETY: Store per-icon state in local weak-keyed tables instead of
-- writing custom properties to Blizzard dungeon icon frames.
local iconOverlays = Helpers.CreateStateTable()  -- dungeonIcon → overlay

---------------------------------------------------------------------------
-- SETTINGS ACCESS
---------------------------------------------------------------------------

local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.mplusTeleportEnabled ~= false
end

---------------------------------------------------------------------------
-- CLICK-TO-TELEPORT ON M+ TAB ICONS
---------------------------------------------------------------------------

local function CreateSecureOverlay(dungeonIcon)
    if not dungeonIcon or not dungeonIcon.mapID then return end
    if InCombatLockdown() then return end

    -- Get teleport spell from shared dungeon data
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

    -- Create secure button overlay
    overlay = CreateFrame("Button", nil, dungeonIcon, "SecureActionButtonTemplate")
    overlay:SetAllPoints(dungeonIcon)
    overlay:SetFrameLevel(dungeonIcon:GetFrameLevel() + 10)

    overlay:SetAttribute("type", "spell")
    overlay:SetAttribute("spell", spellID)
    overlay:RegisterForClicks("AnyUp", "AnyDown")

    -- Store reference
    overlay.spellID = spellID
    overlay.mapID = dungeonIcon.mapID
    overlay.dungeonIcon = dungeonIcon

    -- Create highlight texture for hover effect
    local highlight = overlay:CreateTexture(nil, "OVERLAY")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 1, 0.5, 0.3)  -- Green tint when spell known
    highlight:Hide()
    overlay.highlight = highlight

    -- Visual indicator on hover
    overlay:SetScript("OnEnter", function(self)
        local currentSpellID = self.spellID
        local icon = self.dungeonIcon

        -- Show highlight if spell is known
        if currentSpellID and IsSpellKnown(currentSpellID) then
            highlight:Show()
        end
        -- Trigger original tooltip
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
            CreateSecureOverlay(dungeonIcon)
        end
    end
end

local function OnChallengesFrameUpdate()
    if not IsEnabled() then return end
    -- Delay slightly to ensure icons have their mapID set
    C_Timer.After(0.1, HookDungeonIcons)
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local hooked = false

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
        if not hooked and ChallengesFrame then
            hooksecurefunc(ChallengesFrame, "Update", OnChallengesFrameUpdate)
            hooked = true
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Handle case where Blizzard_ChallengesUI is already loaded
if C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
    if not hooked and ChallengesFrame then
        hooksecurefunc(ChallengesFrame, "Update", OnChallengesFrameUpdate)
        hooked = true
    end
end
