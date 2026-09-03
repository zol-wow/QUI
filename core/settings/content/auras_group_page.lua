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

local HINT_SCHOOLS = {
    { key = "Magic", label = "Magic" },
    { key = "Curse", label = "Curse" },
    { key = "Disease", label = "Disease" },
    { key = "Poison", label = "Poison" },
}

local function BuildDispelHintBlock(host, y)
    local C = GUI.Colors or {}

    local header = GUI:CreateLabel(host, ns.L["What You Can Dispel"], 13, C.accent)
    header:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    y = y + 20

    local dispellable = (ns.QUI_DispelRoles and type(ns.QUI_DispelRoles.PlayerDispelSchools) == "function")
        and ns.QUI_DispelRoles.PlayerDispelSchools() or {}

    for _, school in ipairs(HINT_SCHOOLS) do
        local canDispel = dispellable[school.key] == true
        local hintText = canDispel and ns.L["You can dispel this"] or ns.L["Your class can't dispel this"]
        local color = canDispel and C.accent or C.textMuted
        local row = GUI:CreateLabel(host, string.format("%s — %s", ns.L[school.label], hintText), 12, color)
        row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
        y = y + 18
    end

    local bleedRow = GUI:CreateLabel(
        host,
        string.format("%s — %s", ns.L["Bleed"], ns.L["Show only — can't be dispelled"]),
        12,
        C.textMuted
    )
    bleedRow:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    y = y + 18

    return y
end

local function BuildAurasGroupContent(host, ctx, section)
    local FullSurface = Settings and Settings.FullSurface
    local GF = ns.QUI_GroupFramesSettingsSchema
    local GFModel = ns.QUI_GroupFramesSettingsModel
    local GFSurface = ns.QUI_GroupFramesSettingsSurface

    local contextMode = (GFSurface and type(GFSurface.GetContextMode) == "function" and GFSurface.GetContextMode()) or "party"

    local y = 0
    local built
    if FullSurface and type(FullSurface.BuildContextDropdownRow) == "function" then
        local options = (GFModel and type(GFModel.GetContextOptions) == "function" and GFModel.GetContextOptions())
            or {
                { value = "party", text = ns.L["Party"] },
                { value = "raid", text = ns.L["Raid"] },
            }
        built = FullSurface.BuildContextDropdownRow(host, {
            gui = GUI,
            label = ns.L["Unit Group"],
            stateKey = "_contextMode",
            selectedValue = contextMode,
            options = options,
            meta = { description = ns.L["Switch between Party and Raid group-frame aura settings."] },
            height = 30,
            onChanged = function(value)
                if GFSurface and type(GFSurface.SetContextMode) == "function" then
                    GFSurface.SetContextMode(value)
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
        subTabIndex = 2,
        subTabName = ns.L["Group Frames"],
        tileId = "auras",
        subPageIndex = 2,
        featureId = "aurasGroupPage",
    }
    local h = 1
    if GF and type(GF.RenderAurasTab) == "function" then
        if SearchRoute and type(SearchRoute.With) == "function" then
            h = SearchRoute.With(HUB_ROUTE, GF.RenderAurasTab, editorHost, contextMode) or 1
        else
            h = GF.RenderAurasTab(editorHost, contextMode) or 1
        end
    end

    local dispelHost = CreateFrame("Frame", nil, host)
    dispelHost:SetPoint("TOPLEFT", editorHost, "BOTTOMLEFT", 0, -16)
    dispelHost:SetPoint("TOPRIGHT", editorHost, "BOTTOMRIGHT", 0, -16)
    dispelHost:SetHeight(1)
    local dispelHeight = 1
    if GF and type(GF.RenderDispelTab) == "function" then
        if SearchRoute and type(SearchRoute.With) == "function" then
            dispelHeight = SearchRoute.With(HUB_ROUTE, GF.RenderDispelTab, dispelHost, contextMode) or 1
        else
            dispelHeight = GF.RenderDispelTab(dispelHost, contextMode) or 1
        end
    end
    local hintHost = CreateFrame("Frame", nil, host)
    hintHost:SetPoint("TOPLEFT", dispelHost, "BOTTOMLEFT", 0, -16)
    hintHost:SetPoint("TOPRIGHT", dispelHost, "BOTTOMRIGHT", 0, -16)
    hintHost:SetHeight(1)
    local hintHeight = BuildDispelHintBlock(hintHost, 0)
    hintHost:SetHeight(hintHeight)

    local function ResizePage()
        local editorHeight = (editorHost.GetHeight and editorHost:GetHeight()) or tonumber(h) or 1
        local currentDispelHeight = (dispelHost.GetHeight and dispelHost:GetHeight()) or tonumber(dispelHeight) or 1
        local total = y + editorHeight + 16 + currentDispelHeight + 16 + hintHeight
        host:SetHeight(total)
        local mountedHeight = ctx and ctx.runtime and ctx.runtime.sectionHeights
            and ctx.runtime.sectionHeights[section.id]
        if type(mountedHeight) == "number" and type(ctx.ResizeSection) == "function" then
            ctx:ResizeSection(section.id, total)
        end
        return total
    end
    editorHost:HookScript("OnSizeChanged", ResizePage)
    dispelHost:HookScript("OnSizeChanged", ResizePage)

    local previewHost = (ctx and ctx.host) or host
    if GFSurface and type(GFSurface.ShowPreviewOn) == "function" then
        GFSurface.ShowPreviewOn(previewHost, function()
            local db = built and built.dropdownDB
            return (db and db._contextMode) or contextMode
        end)
    end

    return ResizePage()
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasGroupPage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 2 },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = BuildAurasGroupContent,
        }),
    },
}))
