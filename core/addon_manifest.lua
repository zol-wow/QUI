local MANIFEST = {
    { folder = "QUI_ActionBars",   class = "login",                                                  sources = { "modules/actionbars" } },
    { folder = "QUI_CDM",          class = "login",                                                  sources = { "modules/cdm" } },
    { folder = "QUI_Chat",         class = "login", legacyFlag = { "chat", "enabled" },              sources = { "modules/chat" } },
    { folder = "QUI_GroupFrames",  class = "login", legacyFlag = { "quiGroupFrames", "enabled" },    sources = { "modules/groupframes" } },
    { folder = "QUI_Nameplates",   class = "login", legacyFlag = { "nameplates", "enabled" },        sources = {} },
    { folder = "QUI_ResourceBars", class = "login",                                                  sources = { "modules/resourcebars" } },
    { folder = "QUI_UnitFrames",   class = "login", legacyFlag = { "quiUnitFrames", "enabled" },   sources = { "modules/unitframes" } },
    { coreModule = "minimap",   flag = { "minimap",      "enabled" } },
    { coreModule = "infobar",   flag = { "infobar",      "enabled" } },
    { coreModule = "alts",      flag = { "alts",         "enabled" } },
    { coreModule = "datatexts", flag = { "quiDatatexts", "enabled" } },
    { coreModule = "skinning",  flag = { "skinning",     "enabled" } },
    { folder = "QUI_DamageMeter",  class = "lod",                                                    sources = { "modules/damage_meter" } },
    { folder = "QUI_Bags",         class = "lod", legacyFlag = { "bags", "enabled" }, loadPolicy = "profile", sources = { "modules/bags" } },
}

local ADDON_NAME, ns = ...
if type(ns) == "table" then
    ns.AddonManifest = MANIFEST
end
return MANIFEST
