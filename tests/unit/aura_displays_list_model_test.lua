local function fail(msg)
    print("FAIL: aura_displays_list_model_test - " .. msg)
    os.exit(1)
end

local ns = {}
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Helpers = {}
assert(loadfile("modules/trackers/settings/aura_displays_content.lua"))("QUI", ns)
local Page = ns.QUI_AuraDisplaysOptions
if type(Page) ~= "table" or type(Page.BuildListModel) ~= "function" then
    fail("BuildListModel must be exported")
end

local displays = {
    { id = "d1", name = "Immolate", group = "Raid" },
    { id = "d2", name = "Doom", group = "Raid" },
    { id = "d3", name = "HoTs", group = "" },
}

local model = Page.BuildListModel(displays, nil, function() return false end)
if #model ~= 5 then fail("expected 5 nodes, got " .. #model) end
if model[1].kind ~= "header" or model[1].group ~= "Raid" or model[1].count ~= 2 then
    fail("first node must be the Raid header with count 2")
end
if model[2].kind ~= "display" or model[2].display.id ~= "d1" then
    fail("Raid displays must follow their header in order")
end
if model[4].kind ~= "header" or model[4].group ~= "" then
    fail("ungrouped header must come after grouped displays")
end

local collapsed = Page.BuildListModel(displays, nil, function(g) return g == "Raid" end)
if #collapsed ~= 3 then fail("collapsed Raid must hide its 2 displays") end
if collapsed[1].collapsed ~= true then fail("header must carry collapsed state") end

local filtered = Page.BuildListModel(displays, "doom", function(g) return g == "Raid" end)
local found = false
for i = 1, #filtered do
    if filtered[i].kind == "display" and filtered[i].display.id == "d2" then found = true end
    if filtered[i].kind == "display" and filtered[i].display.id ~= "d2" then
        fail("search must exclude non-matching displays")
    end
end
if not found then fail("search must find Doom and override collapse") end

local byGroup = Page.BuildListModel(displays, "raid", function() return false end)
local count = 0
for i = 1, #byGroup do
    if byGroup[i].kind == "display" then count = count + 1 end
end
if count ~= 2 then fail("group-name search must keep the group's displays") end

print("OK: aura_displays_list_model_test")
