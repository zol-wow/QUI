---------------------------------------------------------------------------
-- QUI suite manifest — single source of truth for the sub-addon split.
-- Consumed by core/addon_loader.lua (runtime), tools/split_suite_tocs.lua
-- (one-shot splitter) and tests/unit/suite_toc_consistency_test.lua (CI).
--
--   folder     — sibling addon folder name
--   class      — "login" (loads with the loading screen) | "lod" (LoadOnDemand,
--                loaded by the core post-login, in manifest order)
--   legacyFlag — profile-DB path of the module's dormant-guard flag, or nil.
--                Present on exactly two entries (QUI_Chat and QUI_GroupFrames)
--                that default to off for stock-chat / opt-in users.  Consumed
--                by the Module Addons rows (AND-read for isEnabled, heal-on-
--                enable) and honored by each module's own init.
--                NOT consumed by the loader — addon enable state alone gates
--                LOD loading.
--   sources    — original modules/<dir> roots (repo-relative, forward slashes);
--                inside the sub-addon each keeps its dir name (modules/cdm →
--                QUI_CDM/cdm/...)
---------------------------------------------------------------------------
local MANIFEST = {
    -- login class: secure frames / taint-load-bearing hooks; order here is
    -- documentation only (the client loads by dependency + folder name).
    { folder = "QUI_ActionBars",   class = "login",                                                  sources = { "modules/actionbars" } },
    { folder = "QUI_CDM",          class = "login",                                                  sources = { "modules/cdm" } },
    { folder = "QUI_Chat",         class = "login", legacyFlag = { "chat", "enabled" },              sources = { "modules/chat" } },
    { folder = "QUI_GroupFrames",  class = "login", legacyFlag = { "quiGroupFrames", "enabled" },    sources = { "modules/groupframes" } },
    { folder = "QUI_ResourceBars", class = "login",                                                  sources = { "modules/resourcebars" } },
    { folder = "QUI_UnitFrames",   class = "login",                                                  sources = { "modules/unitframes" } },
    -- lod class: loaded post-login in THIS order (cosmetics first)
    { folder = "QUI_Skinning",     class = "lod",                                                    sources = { "modules/skinning" } },
    -- No legacyFlag: minimap.enabled was retired (v43); addon state alone
    -- gates this module.
    { folder = "QUI_Minimap",      class = "lod",                                                    sources = { "modules/minimap" } },
    { folder = "QUI_QoL",          class = "lod",                                                    sources = { "modules/qol", "modules/dungeon", "modules/trackers", "modules/combat", "modules/utility" } },
    { folder = "QUI_DamageMeter",  class = "lod",                                                    sources = { "modules/damage_meter" } },
}

local ADDON_NAME, ns = ...
if type(ns) == "table" then
    ns.AddonManifest = MANIFEST
end
return MANIFEST
