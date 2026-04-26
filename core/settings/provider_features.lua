local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local ProviderFeatures = Settings.ProviderFeatures or {}
Settings.ProviderFeatures = ProviderFeatures

local Registry = Settings.Registry
local Schema = Settings.Schema

local function CopyTable(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end

    for key, value in pairs(source) do
        copy[key] = value
    end

    return copy
end

local function BuildProviderSections(spec)
    local sections = {}

    if type(spec.sections) == "table" and #spec.sections > 0 then
        for _, definition in ipairs(spec.sections) do
            if type(definition) == "table"
                and type(definition.id) == "string"
                and definition.id ~= "" then
                local section = CopyTable(definition)
                section.kind = section.kind or "provider"
                if section.providerKey == nil then
                    section.providerKey = spec.providerKey
                end
                if section.sectionTitle == nil
                    and section.sectionTitles == nil
                    and type(section.title) == "string"
                    and section.title ~= "" then
                    section.sectionTitle = section.title
                end
                sections[#sections + 1] = Schema.Section(section)
            end
        end
    end

    if #sections == 0 then
        sections[1] = Schema.Section({
            id = spec.sectionId or "settings",
            kind = "provider",
            minHeight = spec.minHeight or 80,
            providerKey = spec.providerKey,
            providerOptions = spec.providerOptions,
            sectionTitle = spec.sectionTitle,
            sectionTitles = spec.sectionTitles,
        })
    end

    return sections
end

local function FindPositionSectionId(sections)
    for _, section in ipairs(sections) do
        if section.id == "position" then
            return "position"
        end
    end
    return nil
end

local function BuildSurfaces(spec, sections)
    local surfaces = CopyTable(spec.surfaces)
    local positionSectionId = FindPositionSectionId(sections)
    if not positionSectionId then
        return next(surfaces) and surfaces or nil
    end

    local layout = CopyTable(surfaces.layout)
    if layout.sections == nil then
        layout.sections = { positionSectionId }
    end
    surfaces.layout = layout

    return surfaces
end

function ProviderFeatures:Register(spec)
    if not Registry or type(Registry.RegisterFeature) ~= "function"
        or not Schema or type(Schema.Feature) ~= "function"
        or type(spec) ~= "table"
        or type(spec.id) ~= "string"
        or spec.id == "" then
        return nil
    end

    local sections = BuildProviderSections(spec)
    local feature = {
        id = spec.id,
        moverKey = spec.moverKey or spec.id,
        lookupKeys = spec.lookupKeys,
        lookupRoutes = spec.lookupRoutes,
        lookupAliases = spec.lookupAliases,
        category = spec.category,
        nav = spec.nav,
        getDB = spec.getDB,
        apply = spec.apply,
        createState = spec.createState,
        onNavigate = spec.onNavigate,
        searchContext = spec.searchContext,
        preview = spec.preview,
        providerKey = spec.providerKey,
        render = spec.render,
        sections = sections,
        surfaces = BuildSurfaces(spec, sections),
    }

    return Registry:RegisterFeature(Schema.Feature(feature))
end
