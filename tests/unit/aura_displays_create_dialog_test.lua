-- tests/unit/aura_displays_create_dialog_test.lua
-- Run: lua tests/unit/aura_displays_create_dialog_test.lua
--
-- Source-text pins for the "New Display" dialog (Templates / Guided / Custom)
-- and the editor's Simple Mode. The dialog and editor are headless WoW-frame
-- builders, so their contracts are pinned by source text; the executable
-- creation logic is covered by aura_display_templates_test.lua.

local function read(p)
    local h = io.open(p, "rb")
    if not h then return nil end
    local s = h:read("*a")
    h:close()
    return s
end

local fails = 0
local function check(n, ok)
    if ok then print("  ok  " .. n) else fails = fails + 1; print("FAIL  " .. n) end
end

local CREATE = "modules/trackers/settings/aura_displays_create.lua"
local CONTENT = "modules/trackers/settings/aura_displays_content.lua"
local TEMPLATES = "modules/trackers/aura_display_templates.lua"
local EDITOR = "QUI_Options/aura_elements_editor.lua"

local create = read(CREATE)
local content = read(CONTENT)
local templates = read(TEMPLATES)
local editor = read(EDITOR)
local mainToc = read("QUI.toc")
local optionsToc = read("QUI_Options/QUI_Options.toc")

check("create dialog exists", create ~= nil)
check("templates module exists", templates ~= nil)
if not (create and content and templates and editor and mainToc and optionsToc) then
    print(("%d failures"):format(fails + 1))
    os.exit(1)
end

-- Load order ----------------------------------------------------------------
check("QUI.toc loads the templates module",
    mainToc:find("aura_display_templates.lua", 1, true) ~= nil)
check("templates load after the aura displays store",
    mainToc:find("aura_displays.lua", 1, true)
        < mainToc:find("aura_display_templates.lua", 1, true))
check("options toc loads the create dialog",
    optionsToc:find("aura_displays_create.lua", 1, true) ~= nil)
check("create dialog loads before the content page",
    optionsToc:find("aura_displays_create.lua", 1, true)
        < optionsToc:find("aura_displays_content.lua", 1, true))

-- Dialog contract -----------------------------------------------------------
check("dialog exports ns.QUI_AuraDisplaysCreate",
    create:find("ns.QUI_AuraDisplaysCreate = Create", 1, true) ~= nil)
check("dialog exposes ShowDialog", create:find("function Create.ShowDialog", 1, true) ~= nil)
check("dialog exposes HideDialog", create:find("function Create.HideDialog", 1, true) ~= nil)
for _, tab in ipairs({ '"templates"', '"guided"', '"custom"' }) do
    check("dialog has the " .. tab .. " door", create:find(tab, 1, true) ~= nil)
end
check("templates door installs via T.Install", create:find("T.Install(tpl.id)", 1, true) ~= nil)
check("guided door creates via BuildWizardDisplay",
    create:find("T.BuildWizardDisplay", 1, true) ~= nil)
check("custom door reuses quick-create", create:find("Page._QuickCreate", 1, true) ~= nil)
check("wizard has 4 steps", create:find("BuildWizardStep4", 1, true) ~= nil)

-- Content page wiring --------------------------------------------------------
check("New Display routes through the dialog",
    content:find("Create.ShowDialog", 1, true) ~= nil)
check("quick-create popup kept as fallback",
    content:find("ShowQuickCreatePopup()", 1, true) ~= nil)
check("content page enables simpleMode",
    content:find("simpleMode          = true", 1, true) ~= nil)
check("content page passes the unit label for summaries",
    content:find("summaryUnit         = UnitLabelFor(display)", 1, true) ~= nil)
check("quick-create seeds tuned tracked elements",
    content:find("TunedTrackedElement", 1, true) ~= nil)
check("quick-create strips use the DefaultBucket",
    content:find("local seeded = AD.DefaultBucket()", 1, true) ~= nil)

-- Editor Simple Mode ---------------------------------------------------------
check("editor gates on caps.simpleMode", editor:find("caps.simpleMode", 1, true) ~= nil)
check("editor renders the summary sentence",
    editor:find("BuildElementSummary", 1, true) ~= nil)
check("summary refreshes on change", editor:find("ctx.RefreshSummary", 1, true) ~= nil)
check("tracked advanced settings fold into one section",
    editor:find('"appearance", ns.L["Appearance & Placement"]', 1, true) ~= nil)
check("tracked hoists are display-type aware",
    editor:find("SIMPLE_TRACKED_HOISTS", 1, true) ~= nil)
check("strips hoist What to Show above the sections",
    editor:find("AddWhatToShowRow(ctx, element)\n        AddMaxIconsRow", 1, true) ~= nil)
check("placement widgets accept hoist skips",
    editor:find("AddPlacementWidgets(ctx, element, includeStrip, skip)", 1, true) ~= nil)
check("summary text comes from the templates module",
    templates:find("function T.BuildElementSummary", 1, true) ~= nil)

if fails > 0 then
    print(("%d failures"):format(fails))
    os.exit(1)
end
print("OK: aura_displays_create_dialog_test")
