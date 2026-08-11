local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function SkinDelvesFrame(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    if frame.Border and SkinBase.StripTextures then SkinBase.StripTextures(frame.Border) end
    SkinBase.SkinWindow(frame)
    SkinBase.MarkSkinned(frame)
end

local function SkinDelvesCompanion()
    if not IsSettingEnabled("skinDelves") then return end
    SkinDelvesFrame(_G.DelvesCompanionConfigurationFrame)
end

local function SkinDelvesDifficulty()
    if not IsSettingEnabled("skinDelves") then return end
    SkinDelvesFrame(_G.DelvesDifficultyPickerFrame)
end

local function RefreshDelves()
    SkinBase.RefreshFrameBackdropColors(_G.DelvesCompanionConfigurationFrame)
    SkinBase.RefreshFrameBackdropColors(_G.DelvesDifficultyPickerFrame)
end
if ns.Registry then
    ns.Registry:Register("skinDelves", {
        refresh = RefreshDelves,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_DelvesCompanionConfiguration", SkinDelvesCompanion, 0)
SkinBase.OnAddOnLoaded("Blizzard_DelvesDifficultyPicker", SkinDelvesDifficulty, 0)
