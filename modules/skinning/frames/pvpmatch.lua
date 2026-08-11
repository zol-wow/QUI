local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function SkinPVPMatchFrame(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { depth = 5 })
    SkinBase.MarkSkinned(frame)
end

local function SkinPVPMatch()
    if not IsSettingEnabled("skinPVPMatch") then return end
    SkinPVPMatchFrame(_G.PVPMatchScoreboard)
    SkinPVPMatchFrame(_G.PVPMatchResults)
end

local function RefreshPVPMatch()
    SkinBase.RefreshFrameBackdropColors(_G.PVPMatchScoreboard)
    SkinBase.RefreshFrameBackdropColors(_G.PVPMatchResults)
end
if ns.Registry then
    ns.Registry:Register("skinPVPMatch", {
        refresh = RefreshPVPMatch,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_PVPMatch", SkinPVPMatch, 0)
