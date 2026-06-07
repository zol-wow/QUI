---------------------------------------------------------------------------
-- SOCIAL FRAMES SKINNING
--
--   - FriendsFrame      (ButtonFrameTemplate,            LOD Blizzard_FriendsFrame)
--   - CommunitiesFrame  (ButtonFrameTemplateMinimizable, LOD Blizzard_Communities)
--
-- Both inherit a ButtonFrameTemplate variant, so SkinBase.SkinButtonFrameTemplate
-- handles chrome strip + backdrop + close-button styling. Frame-specific
-- sub-elements (friends scroll list, club channel tree, member list) are
-- left for follow-up commits.
---------------------------------------------------------------------------

local addonName, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors

---------------------------------------------------------------------------
-- FriendsFrame
---------------------------------------------------------------------------
local function SkinFriends()
    if not IsSettingEnabled("skinFriends") then return end
    local frame = _G.FriendsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    -- FriendsFrameTab1..4: Friends / Quick Join / Who / Raid
    -- (per Blizzard_FriendsFrame/Mainline/FriendsFrame.lua:273-276).
    local tabs = {}
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    SkinBase.SkinTabGroup(tabs, frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RefreshFriends() RefreshBackdropColors(_G.FriendsFrame) end
_G.QUI_RefreshFriendsColors = RefreshFriends
if ns.Registry then
    ns.Registry:Register("skinFriends", {
        refresh = RefreshFriends,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- CommunitiesFrame
---------------------------------------------------------------------------
local function SkinCommunities()
    if not IsSettingEnabled("skinCommunities") then return end
    local frame = _G.CommunitiesFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RefreshCommunities() RefreshBackdropColors(_G.CommunitiesFrame) end
_G.QUI_RefreshCommunitiesColors = RefreshCommunities
if ns.Registry then
    ns.Registry:Register("skinCommunities", {
        refresh = RefreshCommunities,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
SkinBase.OnAddOnLoaded("Blizzard_FriendsFrame", SkinFriends,     0.1)
SkinBase.OnAddOnLoaded("Blizzard_Communities",  SkinCommunities, 0.1)
