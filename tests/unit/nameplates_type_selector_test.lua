local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
env.LoadAddonFile("core/settings/model_kit.lua", "QUI", ns)
env.LoadAddonFile("core/settings/full_surface.lua", "QUI", ns)
ns.QUI_Nameplates = ns.QUI_Nameplates or {}
env.LoadAddonFile("QUI_Nameplates/nameplates/plate_type.lua", "QUI_Nameplates", ns)
env.LoadAddonFile("QUI_Nameplates/nameplates/settings/nameplates_model.lua", "QUI_Nameplates", ns)
env.LoadAddonFile("QUI_Nameplates/nameplates/settings/nameplates_surface.lua", "QUI_Nameplates", ns)

local Model = ns.QUI_NameplatesSettingsModel
local Surface = ns.QUI_NameplatesSettingsSurface
local NP = ns.QUI_Nameplates

local function fail(msg)
    print("FAIL: nameplates_type_selector_test - " .. msg)
    os.exit(1)
end

local function test(name, fn)
    print(name)
    fn()
    print("  ok")
end

test("the dropdown offers all six types in resolution order", function()
    local options = Model.GetTypeOptions()
    if #options ~= 6 then fail("expected 6 options, got " .. #options) end
    if options[1].value ~= "petMinion" then fail("first option must be petMinion") end
    for _, opt in ipairs(options) do
        if type(opt.text) ~= "string" or opt.text == "" then
            fail("option " .. opt.value .. " has no label")
        end
    end
end)

test("an unknown key normalizes to PlateType.DEFAULT_KEY", function()
    if Model.NormalizeTypeKey("nonsense") ~= NP.PlateType.DEFAULT_KEY then
        fail("unknown keys must fall back to PlateType.DEFAULT_KEY")
    end
    if Model.NormalizeTypeKey(nil) ~= NP.PlateType.DEFAULT_KEY then fail("nil must fall back") end
    if NP.PlateType.DEFAULT_KEY ~= "enemyNPC" then
        fail("the nameplates page must open on Enemy NPCs, got " .. tostring(NP.PlateType.DEFAULT_KEY))
    end
end)

test("normalize falls back to the first option when DEFAULT_KEY is not offered", function()
    local originalOrder = NP.PlateType.ORDER
    NP.PlateType.ORDER = { "petMinion", "friendly" }
    local normalized = Model.NormalizeTypeKey(nil)
    NP.PlateType.ORDER = originalOrder
    if normalized ~= "petMinion" then
        fail("an order without DEFAULT_KEY must fall back to its first entry, got " .. tostring(normalized))
    end
end)

test("the six visual tabs are per-type and General/Behavior are not", function()
    for _, key in ipairs({ "frame", "text", "indicators", "auras", "castbars", "colors" }) do
        if Model.IsPerTypeTab(key) ~= true then fail(key .. " must be per-type") end
    end
    if Model.IsPerTypeTab("general") ~= false then fail("general must stay global") end
    if Model.IsPerTypeTab("visibility") ~= false then fail("visibility must stay global") end
end)

test("the surface selection controller round-trips and normalizes the type", function()
    if Surface.GetSelectedType() ~= "enemyNPC" then fail("default selection must be enemyNPC") end
    Surface.SetSelectedType("bossElite")
    if Surface.GetSelectedType() ~= "bossElite" then fail("SetSelectedType must update the selection") end
    Surface.SetSelectedType("nonsense")
    if Surface.GetSelectedType() ~= "enemyNPC" then fail("an unknown type must normalize back to enemyNPC") end
end)

test("NavigateSearchEntry selects the type before honouring the tab", function()
    Surface.SetSelectedType("petMinion")
    local handled = Surface.NavigateSearchEntry({ surfaceTypeKey = "enemyPlayer" })
    if handled ~= true then fail("a surfaceTypeKey entry must report handled") end
    if Surface.GetSelectedType() ~= "enemyPlayer" then fail("NavigateSearchEntry must select the requested type") end
end)

test("GetTypeOptions tracks NP.PlateType.ORDER live, not a private copy", function()
    local originalOrder = NP.PlateType.ORDER
    NP.PlateType.ORDER = { "enemyNPC", "petMinion" }
    local options = Model.GetTypeOptions()
    if #options ~= 2 then fail("expected 2 options after mutating the shared order, got " .. #options) end
    if options[1].value ~= "enemyNPC" or options[2].value ~= "petMinion" then
        fail("GetTypeOptions must reflect NP.PlateType.ORDER's live contents and order")
    end
    NP.PlateType.ORDER = originalOrder
end)

test("GetTypeOptions falls back to the raw key when NP.PlateType.ORDER outruns TYPE_LABELS", function()
    local originalOrder = NP.PlateType.ORDER
    NP.PlateType.ORDER = { "petMinion", "newFutureType" }
    local options = Model.GetTypeOptions()
    if options[2].text ~= "newFutureType" then
        fail("an order key with no matching label must fall back to the raw key, not nil")
    end
    NP.PlateType.ORDER = originalOrder
end)

do
    local FullSurface = ns.Settings.FullSurface
    local realBuildRow = FullSurface.BuildContextDropdownRow
    local fakeDropdown = { _values = {} }
    function fakeDropdown:SetValue(value, skipOnChange)
        self._values[#self._values + 1] = { value, skipOnChange }
    end
    function fakeDropdown:SetEnabled(enabled) self._enabled = enabled end

    FullSurface.BuildContextDropdownRow = function(_, opts)
        return {
            row = {},
            dropdown = fakeDropdown,
            dropdownDB = { [opts.stateKey] = opts.selectedValue },
        }
    end

    test("a programmatic type change moves the dropdown's own label, not just the tab content", function()
        Surface.SetSelectedType("petMinion")
        Surface.BuildTypeDropdown({}, nil)
        fakeDropdown._values = {}

        Surface.SetSelectedType("bossElite")

        if #fakeDropdown._values == 0 then
            fail("selecting a type from search must push the value into the context dropdown, "
                .. "or the dropdown keeps reading the previous type")
        end
        if fakeDropdown._values[1][1] ~= "bossElite" then
            fail("the dropdown received " .. tostring(fakeDropdown._values[1][1]) .. ", expected bossElite")
        end
        if fakeDropdown._values[1][2] ~= true then
            fail("the sync must skip the widget's own onChange, or the selection loops back on itself")
        end
    end)

    test("a search navigation that lands on a type syncs the dropdown too", function()
        Surface.SetSelectedType("petMinion")
        fakeDropdown._values = {}
        Surface.NavigateSearchEntry({ surfaceTypeKey = "enemyPlayer" })
        if #fakeDropdown._values == 0 or fakeDropdown._values[1][1] ~= "enemyPlayer" then
            fail("NavigateSearchEntry must leave the dropdown showing the type it selected")
        end
    end)

    FullSurface.BuildContextDropdownRow = realBuildRow
    Surface.SetSelectedType("petMinion")
end

do
    local bareNS = { L = setmetatable({}, { __index = function(_, k) return k end }) }
    assert(loadfile("core/settings/model_kit.lua"))("QUI", bareNS)
    assert(loadfile("QUI_Nameplates/nameplates/settings/nameplates_model.lua"))("QUI_Nameplates", bareNS)
    local BareModel = bareNS.QUI_NameplatesSettingsModel

    test("GetTypeOptions/NormalizeTypeKey degrade honestly when the Nameplates module is not loaded", function()
        if bareNS.QUI_Nameplates ~= nil then
            fail("test precondition: the Nameplates module must not be loaded in this bare ns")
        end
        local options = BareModel.GetTypeOptions()
        if type(options) ~= "table" or #options ~= 0 then
            fail("without NP.PlateType.ORDER, GetTypeOptions must return an empty list, not a guessed duplicate")
        end
        if BareModel.NormalizeTypeKey("nonsense") ~= nil then
            fail("without NP.PlateType.ORDER, an unresolvable key must not invent a fallback")
        end
    end)
end

do
    local capturedOptions, capturedSelectedValue
    local fakeDropdown = {}
    function fakeDropdown:SetEnabled(enabled) self._enabled = enabled end

    local bareNS = { L = setmetatable({}, { __index = function(_, k) return k end }) }
    bareNS.Settings = {
        FullSurface = {
            BuildContextDropdownRow = function(_, opts)
                capturedOptions = opts.options
                capturedSelectedValue = opts.selectedValue
                return { dropdown = fakeDropdown }
            end,
        },
    }
    assert(loadfile("core/settings/model_kit.lua"))("QUI", bareNS)
    assert(loadfile("QUI_Nameplates/nameplates/settings/nameplates_model.lua"))("QUI_Nameplates", bareNS)
    assert(loadfile("QUI_Nameplates/nameplates/settings/nameplates_surface.lua"))("QUI_Nameplates", bareNS)
    local BareSurface = bareNS.QUI_NameplatesSettingsSurface

    test("the type dropdown degrades to a disabled placeholder, not a blank list, when the module is not loaded", function()
        if bareNS.QUI_Nameplates ~= nil then
            fail("test precondition: the Nameplates module must not be loaded in this bare ns")
        end

        BareSurface.BuildTypeDropdown({}, nil)

        if type(capturedOptions) ~= "table" or #capturedOptions ~= 1 then
            fail("expected exactly one placeholder option, got " .. tostring(capturedOptions and #capturedOptions))
        end
        local placeholder = capturedOptions[1]
        if type(placeholder.text) ~= "string" or placeholder.text == "" then
            fail("the placeholder option must carry visible text, not render blank")
        end
        if placeholder.text:find("not loaded", 1, true) == nil then
            fail("the placeholder text should explain the module is not loaded")
        end
        if capturedSelectedValue ~= placeholder.value then
            fail("selectedValue must match the placeholder's own value, or the widget still renders blank")
        end
        if fakeDropdown._enabled ~= false then
            fail("the dropdown must be disabled when there are no real type options")
        end
    end)
end

print("OK: nameplates_type_selector_test")
