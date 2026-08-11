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

local function BuildAurasUnitContent(host, ctx, section)
    local FullSurface = Settings and Settings.FullSurface
    local UF = ns.QUI_UnitFramesSettingsSchema
    local UFModel = ns.QUI_UnitFramesSettingsModel
    local UFSurface = ns.QUI_UnitFramesSettingsSurface

    local unitKey = (UFSurface and type(UFSurface.GetSelectedUnit) == "function" and UFSurface.GetSelectedUnit())
        or (UFModel and type(UFModel.NormalizeUnitKey) == "function" and UFModel.NormalizeUnitKey(nil))
        or "player"

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
    local SearchRoute = Settings and Settings.SearchRoute
    local HUB_ROUTE = {
        tabIndex = 21,
        tabName = ns.L["Auras"],
        subTabIndex = 3,
        subTabName = ns.L["Unit Frames"],
        tileId = "auras",
        subPageIndex = 3,
        featureId = "aurasUnitPage",
    }
    if UF and type(UF.RenderIconsTab) == "function" then
        if SearchRoute and type(SearchRoute.With) == "function" then
            SearchRoute.With(HUB_ROUTE, UF.RenderIconsTab, editorHost, unitKey)
        else
            UF.RenderIconsTab(editorHost, unitKey)
        end
    end

    local total = y + ((editorHost.GetHeight and editorHost:GetHeight()) or 1)
    host:SetHeight(total)

    return total
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasUnitPage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 3 },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = BuildAurasUnitContent,
        }),
    },
}))
