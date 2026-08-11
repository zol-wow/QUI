local function fail(msg)
    print("FAIL: nameplates_auras_hub_type_test - " .. msg)
    os.exit(1)
end

local function test(name, fn)
    print(name)
    fn()
    print("  ok")
end

local function NewMockFrame()
    local f = { _height = 0 }
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetHeight(h) self._height = h end
    function f:GetHeight() return self._height end
    return f
end

CreateFrame = function(_, _, _) return NewMockFrame() end

local capturedFeature
local ns = {
    L = setmetatable({}, { __index = function(_, k) return k end }),
}
local capturedDropdownOpts
ns.Settings = {
    Registry = {
        RegisterFeature = function(_self, definition)
            capturedFeature = definition
            return definition
        end,
    },
    Schema = {
        Feature = function(definition) return definition end,
        Section = function(definition) return definition end,
    },
    FullSurface = {
        BuildContextDropdownRow = function(_parent, opts)
            capturedDropdownOpts = opts
            local row = NewMockFrame()
            row:SetHeight(30)
            return { row = row, dropdown = {}, dropdownDB = {} }
        end,
    },
}

local TYPE_OPTIONS = {
    { value = "petMinion", text = "Pets & Minions" },
    { value = "friendly", text = "Friendly" },
    { value = "bossElite", text = "Bosses & Elites" },
    { value = "minorTrivial", text = "Minor & Trivial" },
    { value = "enemyPlayer", text = "Enemy Players" },
    { value = "enemyNPC", text = "Enemy NPCs" },
}
ns.QUI_NameplatesSettingsModel = {
    GetTypeOptions = function() return TYPE_OPTIONS end,
}
assert(loadfile("core/settings/search_route.lua"))("QUI", ns)

local renderCalls = {}
ns.QUI_NameplatesSettingsSchema = {
    RenderAurasTab = function(host, typeKey, hideCopyFrom)
        renderCalls[#renderCalls + 1] = { host = host, typeKey = typeKey, hideCopyFrom = hideCopyFrom }
        return true
    end,
}

local selectedType = "bossElite"
local setTypeCalls = {}
ns.QUI_NameplatesSettingsSurface = {
    GetSelectedType = function() return selectedType end,
    SetSelectedType = function(value)
        setTypeCalls[#setTypeCalls + 1] = value
        selectedType = value
    end,
    ShowPreviewOn = function() end,
}

assert(loadfile("core/settings/content/auras_nameplate_page.lua"))("QUI", ns)

local build = capturedFeature and capturedFeature.sections and capturedFeature.sections[1]
    and capturedFeature.sections[1].build
if type(build) ~= "function" then
    fail("could not capture BuildAurasNameplateContent from the registered feature")
end

test("the hub page threads the surface's currently-selected type into RenderAurasTab", function()
    renderCalls = {}
    build(NewMockFrame(), {})
    if #renderCalls ~= 1 then
        fail("expected exactly one RenderAurasTab call, got " .. #renderCalls)
    end
    if renderCalls[1].typeKey ~= "bossElite" then
        fail("RenderAurasTab must receive the surface's selected type, got " .. tostring(renderCalls[1].typeKey))
    end
end)

test("a different surface selection changes what the hub page renders", function()
    selectedType = "minorTrivial"
    renderCalls = {}
    build(NewMockFrame(), {})
    if renderCalls[1].typeKey ~= "minorTrivial" then
        fail("expected minorTrivial, got " .. tostring(renderCalls[1].typeKey))
    end
end)

test("the hub page always suppresses Copy From -- a whole-type overwrite is a main-panel action", function()
    selectedType = "bossElite"
    renderCalls = {}
    build(NewMockFrame(), {})
    if renderCalls[1].hideCopyFrom ~= true then
        fail("expected hideCopyFrom == true, got " .. tostring(renderCalls[1].hideCopyFrom))
    end
end)

test("the hub names the type it is editing, with a selector offering every type", function()
    selectedType = "bossElite"
    capturedDropdownOpts = nil
    build(NewMockFrame(), {})

    if not capturedDropdownOpts then
        fail("the hub edits a nameplate type without ever naming it -- no selector and no label rendered")
    end
    if capturedDropdownOpts.selectedValue ~= "bossElite" then
        fail("the selector must show the type actually being edited, got "
            .. tostring(capturedDropdownOpts.selectedValue))
    end
    if #(capturedDropdownOpts.options or {}) ~= #TYPE_OPTIONS then
        fail("the selector must offer every nameplate type")
    end
    if type(capturedDropdownOpts.label) ~= "string" or capturedDropdownOpts.label == "" then
        fail("the selector row must carry a visible label")
    end
end)

test("changing the hub selector re-renders the hub against the newly chosen type", function()
    selectedType = "bossElite"
    capturedDropdownOpts = nil
    local rerendered = {}
    local ctx = {
        RerenderSection = function(_self, id) rerendered[#rerendered + 1] = id end,
    }
    build(NewMockFrame(), ctx, { id = "settings" })

    setTypeCalls = {}
    capturedDropdownOpts.onChanged("minorTrivial")

    if setTypeCalls[1] ~= "minorTrivial" then
        fail("the selector must drive the shared surface selection, got " .. tostring(setTypeCalls[1]))
    end
    if #rerendered ~= 1 or rerendered[1] ~= "settings" then
        fail("changing the type must re-render the hub's own section, got " .. #rerendered .. " re-renders")
    end

    renderCalls = {}
    build(NewMockFrame(), {})
    if renderCalls[1].typeKey ~= "minorTrivial" then
        fail("after the selector change the hub must edit minorTrivial, got " .. tostring(renderCalls[1].typeKey))
    end
    selectedType = "bossElite"
end)

test("the hub reserves room for the selector so the editor does not overlap it", function()
    selectedType = "bossElite"
    local host = NewMockFrame()
    local total = build(host, {})
    if type(total) ~= "number" or total <= 30 then
        fail("the reported height must include the selector row, got " .. tostring(total))
    end
end)

test("a missing surface degrades to no typeKey instead of erroring", function()
    ns.QUI_NameplatesSettingsSurface = nil
    renderCalls = {}
    capturedDropdownOpts = nil
    local ok = pcall(build, NewMockFrame(), {})
    if not ok then fail("build must not error when the surface module is unavailable") end
    if renderCalls[1].typeKey ~= nil then
        fail("expected no typeKey without a surface, got " .. tostring(renderCalls[1].typeKey))
    end
    if capturedDropdownOpts ~= nil then
        fail("without a surface there is no type to name, so no selector must render")
    end
end)

print("OK: nameplates_auras_hub_type_test")
