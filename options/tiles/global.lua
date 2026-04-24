--[[
    QUI Options V2 — General tile
    Cross-cutting settings: profiles, import/export, keybind mode,
    third-party integration, click-cast.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options or {}

local V2 = {}
ns.QUI_GlobalTile = V2

local function Unavailable(body, label)
    local t = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 20, -20)
    t:SetText(label .. " settings unavailable (module not loaded).")
end

local function delegate(ownerName, fnName, labelIfMissing)
    return function(body)
        local owner = ns[ownerName]
        local fn = owner and owner[fnName]
        if type(fn) == "function" then
            fn(body)
        else
            Unavailable(body, labelIfMissing)
        end
    end
end

function V2.Register(frame)
    GUI:RegisterV2NavRoute(13, 0, "global", 1)   -- Profiles (sub-page 1)
    GUI:RegisterV2NavRoute(14, 0, "global", 3)   -- Import/Export (sub-page 3)
    -- Keybind Mode moved to the Cooldown Manager tile (container tab strip).
    GUI:RegisterV2NavRoute(4, 7,  "cooldown_manager", 1)
    GUI:RegisterV2NavRoute(7, 0,  "global", 5)   -- Click-Cast (sub-page 5)
    GUI:RegisterV2NavRoute(7, 1,  "global", 5)   -- Click-Cast search page
    -- The legacy General sub-tab (tab 2, subtab 1) no longer maps cleanly to
    -- a single V2 page. Pass nil sub-page so the breadcrumb shows just
    -- "General" rather than a misleading sub-page name.
    GUI:RegisterV2NavRoute(2, 1,  "global")
    -- Third-party: no SetSearchContext route registered; reachable by
    -- clicking the tile (fallback).

    GUI:AddFeatureTile(frame, {
        id = "global",
        icon = "*",
        name = "General",
        subPages = {
            { name = "Profiles",        noScroll = true, buildFunc = Opts.MakeFeatureDirectBuilder("profilesPage",
                { tabIndex = 13, tabName = "Profiles", subTabIndex = 0, subTabName = "Profiles" },
                delegate("QUI_ProfilesOptions", "CreateSpecProfilesPage", "Profiles")) },
            { name = "Pinned Globals",  noScroll = true, buildFunc = Opts.MakeFeatureDirectBuilder("pinnedGlobalsPage",
                nil, delegate("QUI_PinnedSettingsOptions", "BuildPinnedGlobalsPage", "Pinned Globals")) },
            { name = "Import / Export", noScroll = true, buildFunc = Opts.MakeFeatureDirectBuilder("importExportPage",
                { tabIndex = 14, tabName = "Import / Export", subTabIndex = 0, subTabName = "Import / Export" },
                delegate("QUI_ImportOptions", "CreateImportExportPage", "Import/Export")) },
            { name = "Third-party",                     buildFunc = Opts.MakeFeatureDirectBuilder("thirdPartyAnchoring",
                nil, delegate("QUI_ThirdPartyAnchoringOptions", "BuildThirdPartyTab", "Third-party Integrations")) },
            { name = "Click-Cast",      noScroll = true, buildFunc = Opts.MakeFeatureDirectBuilder("clickCastPage",
                { tabIndex = 7, tabName = "Group Frames", subTabIndex = 1, subTabName = "Click-Cast" },
                delegate("QUI_GroupFramesOptions", "CreateClickCastPage", "Click-Cast")) },
        },
    })
end
