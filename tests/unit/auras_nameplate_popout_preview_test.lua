local function read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local tile = read("QUI_Options/tiles/auras.lua")
local page = read("core/settings/content/auras_nameplate_page.lua")
local driver = read("QUI_Nameplates/nameplates/settings/nameplates_preview_driver.lua")
local surface = read("QUI_Nameplates/nameplates/settings/nameplates_surface.lua")
local groupSurface = read("QUI_GroupFrames/groupframes/settings/group_frames_surface.lua")
local power = read("QUI_Nameplates/nameplates/plate_power.lua")

local failures = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name)
    end
end

local nameplateAt = assert(tile:find('id = "aurasNameplate"', 1, true),
    "auras tile must still register the Nameplates sub-page")
local nameplateBlock = tile:sub(nameplateAt, nameplateAt + 800)

check("Auras Nameplates sub-page no longer reserves an in-page preview band",
    nameplateBlock:find("preview = {", 1, true) == nil
    and tile:find("QUI_MountNameplatePreview", 1, true) == nil)

check("aura page hands its host to the surface instead of building a band",
    page:find("NPSurface.ShowPreviewOn(previewHost)", 1, true) ~= nil
    and page:find("BuildPreviewBand", 1, true) == nil
    and page:find("QUI_BuildNameplatePreview", 1, true) == nil
    and page:find("PREVIEW_BAND_HEIGHT", 1, true) == nil)

check("driver dropped the band chrome, mount and auto-height exports",
    driver:find("QUI_DecorateNameplatePreviewBand", 1, true) == nil
    and driver:find("QUI_MountNameplatePreview", 1, true) == nil
    and driver:find("QUI_GetNameplatePreviewHeight", 1, true) == nil
    and driver:find("CreateBorderLines", 1, true) == nil)

check("driver reports its measured extent through an observer",
    driver:find("function ns.QUI_SetNameplatePreviewObserver(fn)", 1, true) ~= nil
    and driver:find("function ns.QUI_GetNameplatePreviewExtent()", 1, true) ~= nil
    and driver:find("state.observer(contentW, contentH)", 1, true) ~= nil)

check("driver pins the mock to the host top-left and never scales it",
    driver:find('plate:SetPoint("TOPLEFT", host, "TOPLEFT", state.offsetX, state.offsetY)', 1, true) ~= nil
    and driver:find("plate:SetScale(", 1, true) == nil)

check("surface owns the docked pop-out panel",
    surface:find("FullSurface.CreateDockedPreviewPanel({", 1, true) ~= nil
    and surface:find('idSuffix = "Nameplates"', 1, true) ~= nil
    and surface:find("sessionState = State.previewSession", 1, true) ~= nil
    and surface:find("ns.QUI_BuildNameplatePreview(panel.contentHost)", 1, true) ~= nil)

check("a single plate gets more zoom headroom, and opens at it",
    surface:find("local PREVIEW_SCALE_MAX = 3", 1, true) ~= nil
    and surface:find("scaleMax = PREVIEW_SCALE_MAX", 1, true) ~= nil
    and surface:find("defaultScale = PREVIEW_SCALE_MAX", 1, true) ~= nil)

check("surface resizes the panel from the driver observer",
    surface:find("ns.QUI_SetNameplatePreviewObserver(function(w, h)", 1, true) ~= nil
    and surface:find("p.Resize(w, h)", 1, true) ~= nil)

check("the panel is created and shown BEFORE the first build+measure",
    surface:find("local panel = EnsurePreviewPanel()\n    if panel then panel.Show() end\n    RefreshPreviewPanel()", 1, true) ~= nil)

check("surface shows and hides the panel with the bound body",
    surface:find('body:HookScript("OnShow"', 1, true) ~= nil
    and surface:find('body:HookScript("OnHide"', 1, true) ~= nil
    and surface:find("State.previewPanel.Hide()", 1, true) ~= nil
    and surface:find("ShowPreviewOn = ShowPreviewOn", 1, true) ~= nil
    and surface:find("HidePreview = HidePreview", 1, true) ~= nil)

check("surface no longer reserves a PREVIEW band above the tab strip, only the type dropdown row",
    surface:find("PREVIEW_BAND_HEIGHT", 1, true) == nil
    and surface:find("PREVIEW_BAND_GAP", 1, true) == nil
    and surface:find('result.tabStrip:SetPoint("TOPLEFT", band', 1, true) == nil
    and surface:find("tabTopOffset = -(DROPDOWN_ROW_H + 8)", 1, true) ~= nil)

check("the panel carries a preview-state control strip like group frames",
    surface:find("controlStripHeight = STRIP_HEIGHT", 1, true) ~= nil
    and surface:find("local function BuildControlStrip(panel)", 1, true) ~= nil
    and surface:find("optionsAPI.CreateSettingsCardGroup(strip, 0)", 1, true) ~= nil
    and surface:find("GUI:CreateFormToggle(card.frame, nil, def.key, previewState", 1, true) ~= nil
    and surface:find("panel.RefreshControlStrip = function()", 1, true) ~= nil)

check("preview state is session-owned and handed to the driver",
    surface:find("ns.QUI_SetNameplatePreviewState(State.previewState)", 1, true) ~= nil
    and surface:find("State.previewState = defaults", 1, true) ~= nil
    and driver:find("function ns.QUI_SetNameplatePreviewState(previewState)", 1, true) ~= nil
    and driver:find("function ns.QUI_GetNameplatePreviewStateDefaults()", 1, true) ~= nil)

check("the mock resolves colours through the real resolver, not a fixed state",
    driver:find("np.Colors.Resolve(fakeState, settings,", 1, true) ~= nil
    and driver:find("npThreat = (ps.aggro == true) and \"high\" or nil", 1, true) ~= nil
    and driver:find("npTapDenied = reaction == \"tapped\"", 1, true) ~= nil)

check("class power keeps ONE layout path for the live row and the preview row",
    power:find("local function NewInstance(parent)", 1, true) ~= nil
    and power:find("local function LayoutPips(inst, count, power)", 1, true) ~= nil
    and power:find("local function AnchorRow(inst, plate, power)", 1, true) ~= nil
    and power:find("function NPPower.RenderPreview(plate)", 1, true) ~= nil
    and power:find("previewRows = setmetatable({}, { __mode = \"k\" })", 1, true) ~= nil
    and driver:find("np.Power.RenderPreview(plate)", 1, true) ~= nil)

check("nameplates and group frames share one panel factory",
    groupSurface:find("FullSurface.CreateDockedPreviewPanel({", 1, true) ~= nil
    and groupSurface:find("ShowPreviewOn = ShowPreviewOn", 1, true) ~= nil)

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("auras_nameplate_popout_preview_test: all checks passed")
