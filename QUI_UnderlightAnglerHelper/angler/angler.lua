-- QUI_UnderlightAnglerHelper/angler/angler.lua -- the two ways into the window:
-- a slash command, and a button on Blizzard's artifact window that appears
-- only while the Underlight Angler is the artifact being viewed.
local _, ns = ...

local Angler = ns.UnderlightAngler
local UIKit = ns.UIKit

local STANDALONE_ADDON = "UnderlightAnglerUI"

-- The standalone addon this module was ported from owns /angler and adds its
-- own artifact-window button. When it is enabled alongside QUI, leave both to
-- it and stay reachable through /quiangler.
local function StandaloneIsEnabled()
    if not (C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(STANDALONE_ADDON)) then
        return false
    end
    return ns.AddonLoader.IsModuleAddonEnabled(STANDALONE_ADDON)
end

local standalone = StandaloneIsEnabled()

-- luacheck: globals SLASH_QUIANGLER1 SLASH_QUIANGLER2
SLASH_QUIANGLER1 = "/quiangler"
if not standalone then
    SLASH_QUIANGLER2 = "/angler"
end
SlashCmdList["QUIANGLER"] = function()
    Angler.Window.Toggle("checklist")
end

local launcher

local function UpdateLauncher()
    if not launcher then return end
    launcher:SetShown(Angler.IsArtifactOpen())
end

local function CreateLauncher()
    local artifactFrame = _G.ArtifactFrame
    if launcher or not artifactFrame then return end

    launcher = UIKit.CreateButton(artifactFrame, {
        text = ns.L["Underlight Angler Tree"], width = 210, height = 28,
        onClick = function() Angler.Window.Toggle("tree") end,
    })
    launcher:SetPoint("TOPRIGHT", artifactFrame, "TOPRIGHT", -165, -88)
    launcher:SetFrameLevel(artifactFrame:GetFrameLevel() + 20)
    launcher:Hide()

    -- The artifact's power list is not readable until the frame after OnShow.
    artifactFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateLauncher)
    end)
    artifactFrame:HookScript("OnHide", function()
        launcher:Hide()
    end)
    if artifactFrame:IsShown() then UpdateLauncher() end
end

if not standalone then
    ns.SkinBase.OnAddOnLoaded("Blizzard_ArtifactUI", CreateLauncher)
end
