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
    local artifactFrame = _G.ArtifactFrame
    launcher:SetShown(artifactFrame and artifactFrame:IsShown() and Angler.IsArtifactOpen() or false)
end

-- Which artifact is open changed, or none is any more: the launcher and an
-- open helper window both read state that is only settled a frame later.
local function OnArtifactChanged()
    C_Timer.After(0, UpdateLauncher)
    Angler.Window.QueueRefresh()
end

local function CreateLauncher(artifactFrame)
    launcher = UIKit.CreateButton(artifactFrame, {
        text = ns.L["Underlight Angler Tree"], width = 210, height = 28,
        onClick = function() Angler.Window.Toggle("tree") end,
    })
    launcher:SetPoint("TOPRIGHT", artifactFrame, "TOPRIGHT", -165, -88)
    launcher:SetFrameLevel(artifactFrame:GetFrameLevel() + 20)
    launcher:Hide()
end

local watcher

-- Blizzard's artifact window swaps artifacts while shown (ARTIFACT_UPDATE) and
-- clears the artifact data from its OnHide without a closing event, so both
-- the events and the frame scripts are watched.
local function WatchArtifactFrame()
    local artifactFrame = _G.ArtifactFrame
    if watcher or not artifactFrame then return end

    if not standalone then CreateLauncher(artifactFrame) end

    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ARTIFACT_UPDATE")
    watcher:RegisterEvent("ARTIFACT_CLOSE")
    watcher:SetScript("OnEvent", OnArtifactChanged)
    artifactFrame:HookScript("OnShow", OnArtifactChanged)
    artifactFrame:HookScript("OnHide", OnArtifactChanged)
    if artifactFrame:IsShown() then UpdateLauncher() end
end

ns.SkinBase.OnAddOnLoaded("Blizzard_ArtifactUI", WatchArtifactFrame)
