-- tests/unit/settings_search_route_test.lua
-- Run: lua tests/unit/settings_search_route_test.lua
--
-- The route stack that lets a hosting page (an Auras hub sub-page, or an
-- Action Bars sub-page mounting the buff/debuff editor) override WHERE the
-- widgets rendered beneath it are indexed, without touching WHAT they are.

local function fail(msg)
    print("FAIL: settings_search_route_test - " .. msg)
    os.exit(1)
end

local ns = {}
assert(loadfile("core/settings/search_route.lua"), "could not load core/settings/search_route.lua")("QUI", ns)

local SearchRoute = ns.Settings and ns.Settings.SearchRoute
if not SearchRoute then fail("must export ns.Settings.SearchRoute") end

local function test(name, fn) print(name); fn(); print("  ok") end

local HUB = {
    tabIndex = 21, tabName = "Auras",
    subTabIndex = 2, subTabName = "Group Frames",
    tileId = "auras", subPageIndex = 2, featureId = "aurasGroupPage",
}

local function ModuleContext()
    return {
        tabIndex = 6, tabName = "Group Frames",
        subTabIndex = 6, subTabName = "Auras",
        tileId = "group_frames", subPageIndex = 2, featureId = "groupFramesPage",
        providerKey = "partyFrames", category = "frames", surfaceTabKey = "auras",
    }
end

test("Apply is the identity function when nothing is pushed", function()
    if SearchRoute.Depth() ~= 0 then fail("stack must start empty") end
    local context = ModuleContext()
    local result = SearchRoute.Apply(context)
    if result ~= context then fail("Apply must return the same table it was given") end
    if context.tileId ~= "group_frames" then fail("empty stack must not rewrite tileId") end
    if context.tabIndex ~= 6 then fail("empty stack must not rewrite tabIndex") end
end)

test("Apply overrides route fields and preserves identity fields", function()
    SearchRoute.Push(HUB)
    local context = SearchRoute.Apply(ModuleContext())
    SearchRoute.Pop()

    if context.tabIndex ~= 21 then fail("tabIndex must be overridden, got " .. tostring(context.tabIndex)) end
    if context.tabName ~= "Auras" then fail("tabName must be overridden") end
    if context.subTabIndex ~= 2 then fail("subTabIndex must be overridden") end
    if context.subTabName ~= "Group Frames" then fail("subTabName must be overridden") end
    if context.tileId ~= "auras" then fail("tileId must be overridden") end
    if context.subPageIndex ~= 2 then fail("subPageIndex must be overridden") end
    if context.featureId ~= "aurasGroupPage" then fail("featureId must be overridden") end

    -- The whole point: these describe WHAT the widget is, not where it shows.
    if context.providerKey ~= "partyFrames" then fail("providerKey must survive the override") end
    if context.category ~= "frames" then fail("category must survive the override") end
    if context.surfaceTabKey ~= "auras" then fail("surfaceTabKey must survive the override") end
end)

test("a route that sets identity fields still cannot override them", function()
    -- ROUTE_FIELDS is an allowlist, and these four are deliberately outside
    -- it. Without a route that actually SETS them, the preservation
    -- assertions above pass trivially: Apply skips nil route fields, so an
    -- over-broad ROUTE_FIELDS would go undetected.
    local GREEDY = {
        tabIndex = 21, tileId = "auras",
        providerKey = "raidFrames",
        category = "cooldowns",
        surfaceTabKey = "display",
        surfaceUnitKey = "target",
    }
    SearchRoute.Push(GREEDY)
    local context = SearchRoute.Apply(ModuleContext())
    SearchRoute.Pop()

    if context.tileId ~= "auras" then fail("route fields must still be overridden") end
    if context.providerKey ~= "partyFrames" then fail("providerKey must NOT be overridable, got " .. tostring(context.providerKey)) end
    if context.category ~= "frames" then fail("category must NOT be overridable, got " .. tostring(context.category)) end
    if context.surfaceTabKey ~= "auras" then fail("surfaceTabKey must NOT be overridable -- the module surface reads it to activate the right tab, got " .. tostring(context.surfaceTabKey)) end
    if context.surfaceUnitKey ~= nil then fail("surfaceUnitKey must NOT be overridable, got " .. tostring(context.surfaceUnitKey)) end
end)

test("With forwards return values and unwinds", function()
    local depth = SearchRoute.Depth()
    local got = SearchRoute.With(HUB, function(a, b) return a + b end, 2, 3)
    if got ~= 5 then fail("With must forward the callee's return value, got " .. tostring(got)) end
    if SearchRoute.Depth() ~= depth then fail("With must unwind to its entry depth") end
end)

test("With nests and restores the outer route", function()
    local INNER = { tileId = "inner", tabIndex = 99 }
    local seen
    SearchRoute.With(HUB, function()
        SearchRoute.With(INNER, function()
            seen = SearchRoute.Apply({}).tileId
        end)
        -- Outer route must be back in force once the inner frame returns.
        if SearchRoute.Apply({}).tileId ~= "auras" then
            fail("nested With must restore the outer route on exit")
        end
    end)
    if seen ~= "inner" then fail("inner With must win while active, got " .. tostring(seen)) end
    if SearchRoute.Depth() ~= 0 then fail("stack must be empty after nested With") end
end)

test("With pops even when the callee errors", function()
    local depth = SearchRoute.Depth()
    local ok, err = pcall(function()
        SearchRoute.With(HUB, function() error("editor blew up", 0) end)
    end)
    if ok then fail("With must re-raise the callee's error") end
    if tostring(err) ~= "editor blew up" then fail("With must preserve the error message, got " .. tostring(err)) end
    if SearchRoute.Depth() ~= depth then fail("With must unwind after an error -- a leaked route mistags every later render") end
end)

test("With survives a callee that corrupts the stack", function()
    SearchRoute.With(HUB, function()
        SearchRoute.Push({ tileId = "leaked" })  -- callee forgets to pop
    end)
    if SearchRoute.Depth() ~= 0 then fail("With must unwind to its entry depth regardless of callee pushes") end
end)

print("OK: settings_search_route_test")
