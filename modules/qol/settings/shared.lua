local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local CompatRender = Settings and Settings.CompatRender

local LegacyQoLSettings = ns.QUI_LegacyQoLSettings or {}
ns.QUI_LegacyQoLSettings = LegacyQoLSettings

local function RenderGeneralSection(host, spec)
    local Opts = ns.QUI_QoLOptions
    local sectionTitle = spec and spec.sectionTitle
    local searchContext = spec and spec.searchContext

    if type(sectionTitle) ~= "string" or sectionTitle == "" then
        return nil
    end

    if not host or not CompatRender or type(CompatRender.WithOnlySections) ~= "function"
        or not Opts or type(Opts.BuildGeneralTab) ~= "function" then
        return nil
    end

    CompatRender.WithOnlySections({ [sectionTitle] = true }, function()
        Opts.BuildGeneralTab(host, searchContext)
    end)

    return host.GetHeight and host:GetHeight() or nil
end

function LegacyQoLSettings.RegisterGeneralSectionFeature(spec)
    if not Registry or type(Registry.RegisterFeature) ~= "function"
        or not Schema or type(Schema.Feature) ~= "function"
        or type(Schema.Section) ~= "function" then
        return nil
    end

    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
        return nil
    end

    return Registry:RegisterFeature(Schema.Feature({
        id = spec.id,
        moverKey = spec.moverKey or spec.id,
        category = spec.category,
        nav = spec.nav,
        getDB = spec.getDB,
        apply = spec.apply,
        searchContext = spec.searchContext,
        sectionTitle = spec.sectionTitle,
        sections = {
            Schema.Section({
                id = "settings",
                kind = "custom",
                minHeight = 80,
                render = function(host)
                    return RenderGeneralSection(host, spec)
                end,
            }),
        },
    }))
end
