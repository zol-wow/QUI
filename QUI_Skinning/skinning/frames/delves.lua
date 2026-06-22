---------------------------------------------------------------------------
-- DELVES SKINNING
--
-- Skins the Delves endgame frames (opt-in, default OFF):
--   - DelvesCompanionConfigurationFrame (InsetFrameTemplate, LOD
--     Blizzard_DelvesCompanionConfiguration)
--   - DelvesDifficultyPickerFrame       (DialogBorderTemplate, LOD
--     Blizzard_DelvesDifficultyPicker)
--
-- Defensive baseline: QUI backdrop + themed fonts + close button. Bespoke Delves
-- art (companion portraits, curio/reward icons) is left intact; chrome-hiding is
-- conservative (only the frame's own NineSlice / Border / Bg) so nothing in the
-- content area is nuked. Visual tuning is a follow-up in-game pass.
---------------------------------------------------------------------------

local addonName, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function SkinDelvesFrame(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    -- Delves-specific: DialogBorderTemplate's .Border container isn't part of the
    -- standard chrome SkinWindow's HidePortraitFrameChrome hides, so strip it first.
    if frame.Border and SkinBase.StripTextures then SkinBase.StripTextures(frame.Border) end
    SkinBase.SkinWindow(frame) -- chrome + backdrop + close + durable font trio
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
