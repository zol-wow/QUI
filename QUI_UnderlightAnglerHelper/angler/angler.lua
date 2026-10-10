-- QUI_UnderlightAnglerHelper/angler/angler.lua -- the two ways into the window:
-- a slash command, which opens it free-standing on the checklist, and
-- Blizzard's artifact window, which the helper covers while the Underlight
-- Angler is the artifact being viewed.
local _, ns = ...

local Angler = ns.UnderlightAngler
local Window = Angler.Window

local STANDALONE_ADDON = "UnderlightAnglerUI"
-- Artifact data can settle later than the frame after the event announcing it.
local RESYNC_DELAY = 0.2

-- The standalone addon this module was ported from owns /angler and draws its
-- own overlay on the artifact window. When it is enabled alongside QUI, leave
-- both to it and stay reachable through /quiangler.
local function StandaloneIsEnabled()
    if not (C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(STANDALONE_ADDON)) then
        return false
    end
    return ns.AddonLoader.IsModuleAddonEnabled(STANDALONE_ADDON)
end

local standalone = StandaloneIsEnabled()

-- Blizzard's artifact window, while it is showing the Underlight Angler and the
-- overlay is ours to draw.
local function ArtifactHost()
    local artifactFrame = _G.ArtifactFrame
    if standalone or not (artifactFrame and artifactFrame:IsShown() and Angler.IsArtifactOpen()) then
        return nil
    end
    return artifactFrame
end

-- luacheck: globals SLASH_QUIANGLER1 SLASH_QUIANGLER2
SLASH_QUIANGLER1 = "/quiangler"
if not standalone then
    SLASH_QUIANGLER2 = "/angler"
end
SlashCmdList["QUIANGLER"] = function()
    if Window.IsShown() then
        Window.Hide()
        return
    end
    Window.SetHost(nil)
    Window.Show("checklist")
end

local watcher
local hosted = false

-- Opens the overlay when the Underlight Angler comes up in the artifact window
-- and takes it away when it goes. Only the change is acted on, so an overlay
-- the player closed with the slash command stays closed.
local function SyncOverlay()
    local artifactHost = ArtifactHost()
    if artifactHost and not hosted then
        Window.SetHost(artifactHost)
        Window.Show("tree")
    elseif hosted and not artifactHost then
        if Window.IsEmbedded() then Window.Hide() end
        Window.SetHost(nil)
    end
    hosted = artifactHost ~= nil
    Window.QueueRefresh()
end

-- Which artifact is open changed, or none is any more: the overlay and an open
-- helper window both read state that is only settled afterwards.
local function OnArtifactChanged()
    C_Timer.After(0, SyncOverlay)
    C_Timer.After(RESYNC_DELAY, SyncOverlay)
end

-- Blizzard's artifact window swaps artifacts while shown (ARTIFACT_UPDATE) and
-- clears the artifact data from its OnHide without a closing event, so both
-- the events and the frame scripts are watched.
local function WatchArtifactFrame()
    local artifactFrame = _G.ArtifactFrame
    if watcher or not artifactFrame then return end

    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ARTIFACT_UPDATE")
    watcher:RegisterEvent("ARTIFACT_XP_UPDATE")
    watcher:RegisterEvent("ARTIFACT_CLOSE")
    watcher:SetScript("OnEvent", OnArtifactChanged)
    artifactFrame:HookScript("OnShow", OnArtifactChanged)
    artifactFrame:HookScript("OnHide", OnArtifactChanged)
    if artifactFrame:IsShown() then SyncOverlay() end
end

ns.SkinBase.OnAddOnLoaded("Blizzard_ArtifactUI", WatchArtifactFrame)
