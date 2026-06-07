---------------------------------------------------------------------------
-- QUI suite manifest — single source of truth for the sub-addon split.
-- Consumed by core/addon_loader.lua (runtime), tools/split_suite_tocs.lua
-- (one-shot splitter) and tests/unit/suite_toc_consistency_test.lua (CI).
--
--   folder  — sibling addon folder name
--   class   — "login" (loads with the loading screen) | "lod" (LoadOnDemand,
--             loaded by the core post-login, in manifest order)
--   flag    — profile-DB path of the module's master enable flag, or nil
--             (nil = module has no single master flag; addon state alone
--             gates it)
--   sources — original modules/<dir> roots (repo-relative, forward slashes);
--             inside the sub-addon each keeps its dir name (modules/cdm →
--             QUI_CDM/cdm/...)
---------------------------------------------------------------------------
local MANIFEST = {
    -- login class: secure frames / taint-load-bearing hooks; order here is
    -- documentation only (the client loads by dependency + folder name).
    { folder = "QUI_ActionBars",   class = "login", flag = { "actionBars", "enabled" },             sources = { "modules/actionbars" } },
    { folder = "QUI_CDM",          class = "login", flag = { "ncdm", "enabled" },                   sources = { "modules/cdm" } },
    { folder = "QUI_Chat",         class = "login", flag = { "chat", "enabled" },                   sources = { "modules/chat" } },
    { folder = "QUI_GroupFrames",  class = "login", flag = { "quiGroupFrames", "enabled" },         sources = { "modules/groupframes" } },
    { folder = "QUI_ResourceBars", class = "login", flag = nil,                                     sources = { "modules/resourcebars" } },
    { folder = "QUI_UnitFrames",   class = "login", flag = { "quiUnitFrames", "enabled" },          sources = { "modules/unitframes" } },
    -- lod class: loaded post-login in THIS order (cosmetics first)
    { folder = "QUI_Skinning",     class = "lod",   flag = nil,                                     sources = { "modules/skinning" } },
    -- flag = nil deliberately: the minimap feature toggle lives inside this
    -- addon (Layout Mode element); gating the load on the flag would make
    -- the toggle unreachable when off. The module's own init checks the flag.
    { folder = "QUI_Minimap",      class = "lod",   flag = nil,                                      sources = { "modules/minimap" } },
    { folder = "QUI_QoL",          class = "lod",   flag = nil,                                     sources = { "modules/qol", "modules/dungeon", "modules/trackers", "modules/combat", "modules/utility" } },
    { folder = "QUI_DamageMeter",  class = "lod",   flag = { "damageMeter", "native", "enabled" },  sources = { "modules/damage_meter" } },
}

local ADDON_NAME, ns = ...
if type(ns) == "table" then
    ns.AddonManifest = MANIFEST
end
return MANIFEST
