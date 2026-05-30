---------------------------------------------------------------------------
-- JOURNAL FRAMES SKINNING
--
--   - PlayerSpellsFrame  (PortraitFrameTemplate, LOD Blizzard_PlayerSpells)
--                        — modern combined SpellBook + Talents window
--   - EncounterJournal   (PortraitFrameTemplate, LOD Blizzard_EncounterJournal)
--                        — Adventure Guide
--   - CollectionsJournal (PortraitFrameTemplate, LOD Blizzard_Collections)
--                        — parent of MountJournal / PetJournal / ToyBox /
--                          WardrobeFrame / HeirloomsJournal sub-tabs
--
-- All inherit PortraitFrameTemplate, so SkinBase.SkinButtonFrameTemplate
-- handles chrome strip + backdrop + close-button styling. The Collections
-- sub-tab frames render inside CollectionsJournal so the parent skin
-- covers most visible chrome; per-tab work is a follow-up if needed.
---------------------------------------------------------------------------

local addonName, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function RefreshBackdropColors(frame)
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    bd:SetBackdropColor(bgr, bgg, bgb, bga)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

---------------------------------------------------------------------------
-- PlayerSpellsFrame (SpellBook + Talents)
---------------------------------------------------------------------------
local function SkinPlayerSpells()
    if not IsSettingEnabled("skinSpellBook") then return end
    local frame = _G.PlayerSpellsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    -- Modern TabSystemTemplate tabs live at frame.TabSystem.tabs.
    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.SkinTabGroup(frame.TabSystem.tabs, frame)
        if not SkinBase.GetFrameData(frame.TabSystem, "qTabSysHooked") then
            hooksecurefunc(frame.TabSystem, "SetTab", function()
                C_Timer.After(0, function()
                    for _, t in ipairs(frame.TabSystem.tabs) do
                        SkinBase.RefreshTabSelected(t, frame)
                    end
                end)
            end)
            SkinBase.SetFrameData(frame.TabSystem, "qTabSysHooked", true)
        end
    end
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RefreshPlayerSpells() RefreshBackdropColors(_G.PlayerSpellsFrame) end
_G.QUI_RefreshSpellBookColors = RefreshPlayerSpells
if ns.Registry then
    ns.Registry:Register("skinSpellBook", {
        refresh = RefreshPlayerSpells,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- EncounterJournal
---------------------------------------------------------------------------
local function SkinEncounterJournal()
    if not IsSettingEnabled("skinEncounterJournal") then return end
    local frame = _G.EncounterJournal
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RefreshEncounterJournal() RefreshBackdropColors(_G.EncounterJournal) end
_G.QUI_RefreshEncounterJournalColors = RefreshEncounterJournal
if ns.Registry then
    ns.Registry:Register("skinEncounterJournal", {
        refresh = RefreshEncounterJournal,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- CollectionsJournal
---------------------------------------------------------------------------
local function SkinCollections()
    if not IsSettingEnabled("skinCollections") then return end
    local frame = _G.CollectionsJournal
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    -- CollectionsJournalTab1..6: Mounts / Pets / Toys / Heirlooms / Wardrobe / WarbandScenes
    local tabs = {}
    for i = 1, 6 do
        local tab = _G["CollectionsJournalTab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    SkinBase.SkinTabGroup(tabs, frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RefreshCollections() RefreshBackdropColors(_G.CollectionsJournal) end
_G.QUI_RefreshCollectionsColors = RefreshCollections
if ns.Registry then
    ns.Registry:Register("skinCollections", {
        refresh = RefreshCollections,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
SkinBase.OnAddOnLoaded("Blizzard_PlayerSpells",     SkinPlayerSpells,     0.1)
SkinBase.OnAddOnLoaded("Blizzard_EncounterJournal", SkinEncounterJournal, 0.1)
SkinBase.OnAddOnLoaded("Blizzard_Collections",      SkinCollections,      0.1)
