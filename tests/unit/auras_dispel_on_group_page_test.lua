local function read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then
        handle:close()
        return true
    end
    return false
end

local tile = read("QUI_Options/tiles/auras.lua")
local groupPage = read("core/settings/content/auras_group_page.lua")
local optionsToc = read("QUI_Options/QUI_Options.toc")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

check("the standalone Dispel Colors sub-page is gone",
    tile:find('id = "aurasDispel"', 1, true) == nil
    and tile:find("aurasDispelPage", 1, true) == nil
    and exists("core/settings/content/auras_dispel_page.lua") == false
    and optionsToc:find("auras_dispel_page.lua", 1, true) == nil)

check("dispel colors render on the Group Frames sub-page",
    groupPage:find("GF.RenderDispelTab(dispelHost, contextMode)", 1, true) ~= nil
    and groupPage:find("BuildDispelHintBlock(hintHost, 0)", 1, true) ~= nil
    and groupPage:find('ns.L["What You Can Dispel"]', 1, true) ~= nil)

check("dispel rows inherit the Group Frames hub route",
    groupPage:find("SearchRoute.With(HUB_ROUTE, GF.RenderDispelTab, dispelHost, contextMode)", 1, true) ~= nil)

local order = {}
for id in tile:gmatch('id = "(auras%a+)"') do
    order[#order + 1] = id
end
local EXPECTED = { "aurasWizard", "aurasGroup", "aurasUnit", "aurasActionBar", "aurasNameplate", "aurasDisplays" }
local orderOk = #order == #EXPECTED
if orderOk then
    for i, id in ipairs(EXPECTED) do
        if order[i] ~= id then orderOk = false end
    end
end
check("auras sub-pages are renumbered without a gap", orderOk,
    "got " .. table.concat(order, ", "))

local ROUTES = {
    { file = "core/settings/content/auras_wizard_page.lua", index = 1 },
    { file = "core/settings/content/auras_group_page.lua", index = 2 },
    { file = "core/settings/content/auras_unit_page.lua", index = 3 },
    { file = "core/settings/content/auras_actionbar_page.lua", index = 4 },
    { file = "core/settings/content/auras_nameplate_page.lua", index = 5 },
}
for _, route in ipairs(ROUTES) do
    local source = read(route.file)
    local wanted = ('nav = { tileId = "auras", subPageIndex = %d }'):format(route.index)
    check(route.file .. " registers sub-page " .. route.index,
        source:find(wanted, 1, true) ~= nil)
end

local satellites = {
    { file = "QUI_ActionBars/actionbars/settings/action_bars.lua",
      needle = 'tileId = "auras",\n        subPageIndex = 4,' },
    { file = "QUI_ActionBars/actionbars/settings/action_bars_buffdebuff_content.lua",
      needle = "local BUFF_DEBUFF_SUB_PAGE_INDEX = 4" },
    { file = "QUI_Options/tiles/cooldown_manager.lua",
      needle = 'tileId = "auras", subPageIndex = 4' },
}
for _, satellite in ipairs(satellites) do
    local source = read(satellite.file)
    check(satellite.file .. " points at Buff/Debuff Frames",
        source:find(satellite.needle, 1, true) ~= nil)
end

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("auras_dispel_on_group_page_test: all checks passed")
