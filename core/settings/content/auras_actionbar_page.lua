local ADDON_NAME, ns = ...
local QUI = QUI
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local function BuildAurasActionBarContent(host, ctx, section)
    local AB = ns.QUI_BuffDebuffOptions

    if AB and type(AB.BuildBuffDebuffTab) == "function" then
        AB.BuildBuffDebuffTab(host)
    end

    return host:GetHeight() or 80
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasActionBarPage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 4 },
    noSearch = true,
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = BuildAurasActionBarContent,
        }),
    },
}))
