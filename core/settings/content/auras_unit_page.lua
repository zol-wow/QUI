local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local mountedEditor

local function BuildAurasUnitContent(host, ctx, section)
    mountedEditor = { host = host, ctx = ctx, section = section }
    local FullSurface = Settings and Settings.FullSurface
    local UF = ns.QUI_UnitFramesSettingsSchema
    local UFModel = ns.QUI_UnitFramesSettingsModel
    local UFSurface = ns.QUI_UnitFramesSettingsSurface

    local unitKey = (UFSurface and type(UFSurface.GetSelectedUnit) == "function" and UFSurface.GetSelectedUnit())
        or (UFModel and type(UFModel.NormalizeUnitKey) == "function" and UFModel.NormalizeUnitKey(nil))
        or "player"

    mountedEditor.key = unitKey

    local y = 0
    if FullSurface and type(FullSurface.BuildContextDropdownRow) == "function" then
        local options = (UFModel and type(UFModel.GetUnitOptions) == "function" and UFModel.GetUnitOptions()) or {}
        local built = FullSurface.BuildContextDropdownRow(host, {
            gui = GUI,
            label = ns.L["Unit"],
            stateKey = "_selectedUnit",
            selectedValue = unitKey,
            options = options,
            meta = { description = ns.L["Select which unit frame's aura icons to configure."] },
            height = 30,
            onChanged = function(value)
                if UFSurface and type(UFSurface.SetSelectedUnit) == "function" then
                    UFSurface.SetSelectedUnit(value)
                end
                if ctx and type(ctx.RerenderSection) == "function" then
                    ctx:RerenderSection(section.id)
                end
            end,
        })
        local rowHeight = (built and built.row and built.row.GetHeight and built.row:GetHeight()) or 30
        y = rowHeight + 8
    end

    local editorHost = CreateFrame("Frame", nil, host)
    editorHost:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    editorHost:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    editorHost:SetHeight(1)
    if UF and type(UF.RenderIconsTab) == "function" then
        UF.RenderIconsTab(editorHost, unitKey)
    end

    local total = y + ((editorHost.GetHeight and editorHost:GetHeight()) or 1)
    host:SetHeight(total)

    return total
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasUnitPage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 3 },
    getSearchContexts = function()
        local model = ns.QUI_UnitFramesSettingsModel
        return model and model.GetSearchContexts("icons") or {}
    end,
    getNavigationContext = function()
        local surface = ns.QUI_UnitFramesSettingsSurface
        return surface and surface.GetNavigationContext() or {}
    end,
    searchNavigate = function(entry, context)
        local surface = ns.QUI_UnitFramesSettingsSurface
        if not surface then return false end
        local key = entry and entry.surfaceUnitKey
        local model = ns.QUI_UnitFramesSettingsModel
        if type(key) ~= "string" or not model or model.NormalizeUnitKey(key) ~= key then return false end
        local changed = surface.GetSelectedUnit() ~= key
        if changed then surface.SetSelectedUnit(key) end
        local mounted = mountedEditor
        if mounted and mounted.key ~= key and mounted.ctx and mounted.section
            and mounted.ctx.host._quiSettingsRuntime == mounted.ctx.runtime then
            mounted.ctx:RerenderSection(mounted.section.id)
        end
        if context and context.opts and mountedEditor then
            context.opts.searchRoot = mountedEditor.host
        end
        return true
    end,
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            getContextKey = function()
                local surface = ns.QUI_UnitFramesSettingsSurface
                return surface and surface.GetSelectedUnit() or "player"
            end,
            build = BuildAurasUnitContent,
        }),
    },
}))
