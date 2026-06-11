---------------------------------------------------------------------------
-- QUI suite manifest — single source of truth for the sub-addon split.
-- Consumed by core/addon_loader.lua (runtime), tools/split_suite_tocs.lua
-- (one-shot splitter) and tests/unit/suite_toc_consistency_test.lua (CI).
--
--   folder     — sibling addon folder name
--   class      — "login" (loads with the loading screen) | "lod" (LoadOnDemand,
--                loaded by the core post-login, in manifest order)
--   legacyFlag — profile-DB path of the module's dormant-guard flag, or nil.
--                Present on three entries (QUI_Chat, QUI_GroupFrames, QUI_Bags)
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
    -- Datatext registry + providers + custom datapanels + LDB host. Must load
    -- BEFORE QUI_Minimap (its 3-slot panel consumes the registry; minimap
    -- soft-guards if this addon is disabled).
    -- sources: "modules/datatexts" is a forward-looking name; the files originated in modules/minimap.
    { folder = "QUI_Datatexts",    class = "lod",                                                    sources = { "modules/datatexts" } },
    -- No legacyFlag: minimap.enabled was retired (v43); addon state alone
    -- gates this module.
    -- Eager (no lateLoad): loads on the loading screen so the minimap is
    -- skinned, reparented, and anchored BEFORE the first frame renders — no
    -- post-login unskinned/mis-anchored pop. This is reparent-safe against
    -- Blizzard EditMode: EditMode's layout apply (ApplySystemAnchor) only
    -- ClearAllPoints/SetPoints a system frame — it never SetParent/Show/Hide's
    -- it — so reparenting MinimapCluster to a hidden frame survives EditMode
    -- untouched, and EditMode never reparents Minimap back into the cluster.
    -- The module re-applies the full minimap once the UI has settled (first
    -- PLAYER_ENTERING_WORLD) and on each EDIT_MODE_LAYOUTS_UPDATED, which
    -- corrects any value (UI scale / UIParent dims) that wasn't final during
    -- the loading-screen init — the symptom the old post-login defer papered
    -- over.
    { folder = "QUI_Minimap",      class = "lod",                                                    sources = { "modules/minimap" } },
    { folder = "QUI_QoL",          class = "lod",                                                    sources = { "modules/qol", "modules/dungeon", "modules/trackers", "modules/combat", "modules/utility" } },
    { folder = "QUI_DamageMeter",  class = "lod",                                                    sources = { "modules/damage_meter" } },
    -- Full-width info bar. Hard-depends on QUI_Datatexts (TOC Dependencies).
    { folder = "QUI_InfoBar",      class = "lod",                                                    sources = { "modules/infobar" } },
    -- Opt-in, default-off (legacyFlag bags.enabled): ships enabled but stays
    -- dormant until the user turns it on via the Module Addons row. Loads via
    -- the eager LOD pass like its siblings; bags.lua self-gates on the flag.
    { folder = "QUI_Bags",         class = "lod", legacyFlag = { "bags", "enabled" },                sources = { "modules/bags" } },
}

local ADDON_NAME, ns = ...
if type(ns) == "table" then
    ns.AddonManifest = MANIFEST
end
return MANIFEST
