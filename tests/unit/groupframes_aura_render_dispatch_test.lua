-- tests/unit/groupframes_aura_render_dispatch_test.lua
-- Run: lua tests/unit/groupframes_aura_render_dispatch_test.lua
-- The render module DEFINES functions that call WoW API but does not call them at
-- file scope, so it loads with a fresh ns. Only the pure Dispatch router is exercised.
local ns = {}
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_aura_render.lua"))("QUI_GroupFrames", ns)
local R = ns.QUI_GroupFrameAuraRender
local function test(n, f) print(n); f(); print("  ok") end

test("module exposes one renderer per displayType + Dispatch", function()
    assert(type(R.RenderIcon) == "function")
    assert(type(R.RenderSquare) == "function")
    assert(type(R.RenderBar) == "function")
    assert(type(R.RenderHealthTint) == "function")
    assert(type(R.Dispatch) == "function")
end)

test("Dispatch routes by element.displayType", function()
    local calls = {}
    local fakeR = setmetatable({}, { __index = R })
    fakeR.RenderBar  = function() calls.bar  = true end
    fakeR.RenderIcon = function() calls.icon = true end
    R.Dispatch(fakeR, {}, { mode = "tracked", displayType = "bar" }, {})
    assert(calls.bar == true and calls.icon == nil)
end)

test("Dispatch on a filterStrip routes to the icon renderer", function()
    local calls = {}
    local fakeR = setmetatable({}, { __index = R })
    fakeR.RenderIcon = function() calls.icon = true end
    R.Dispatch(fakeR, {}, { mode = "filterStrip", auraType = "HELPFUL" }, {})
    assert(calls.icon == true)
end)

test("Dispatch hands a filterStrip's matches array to RenderIcon unchanged", function()
    -- The consumer (BuildFilterStripMatches) now hands an ORDERED array of
    -- auraData in priority order; Dispatch must forward it to RenderIcon verbatim
    -- (same reference, same order) so the renderer can place icons in that order.
    local captured
    local fakeR = setmetatable({}, { __index = R })
    fakeR.RenderIcon = function(_, _, _, matches) captured = matches end
    local orderedMatches = {
        { auraInstanceID = 11, spellId = 300 }, -- dispellable (highest prio)
        { auraInstanceID = 22, spellId = 100 }, -- boss
        { auraInstanceID = 33, spellId = 200 }, -- normal
    }
    R.Dispatch(fakeR, {}, { mode = "filterStrip", auraType = "HARMFUL" }, orderedMatches)
    assert(captured == orderedMatches, "Dispatch must forward the same array reference")
    -- Order preserved exactly (NOT re-sorted by spellId: 300,100,200 not 100,200,300).
    assert(captured[1].auraInstanceID == 11)
    assert(captured[2].auraInstanceID == 22)
    assert(captured[3].auraInstanceID == 33)
end)

test("RenderIcon's filterStrip branch preserves order (does NOT sort by spellID)", function()
    -- Source-pattern guard: RenderIcon needs real WoW frames to run, so a
    -- behavioral order test isn't possible headless. Instead assert the source
    -- of the iteration branch iterates the matches array with ipairs and never
    -- table.sorts a filterStrip's matches by spellID (the original bug).
    local f = assert(io.open("QUI_GroupFrames/groupframes/groupframes_aura_render.lua", "r"))
    local src = f:read("*a"); f:close()
    -- Isolate the RenderIcon function body up to the next top-level function.
    local body = src:match("function R%.RenderIcon%(.-\n(.-)\nfunction R%.RenderSquare")
    assert(body, "could not locate RenderIcon body")
    -- The matches-ordering block must iterate the array, not sort it.
    assert(body:find("for%s+_,%s*data%s+in%s+ipairs%(matches%)"),
        "filterStrip branch must iterate matches with ipairs to preserve order")
    assert(not body:find("table%.sort"),
        "RenderIcon must NOT table.sort filterStrip matches (would clobber priority order)")
    assert(not body:find("_sid"),
        "RenderIcon must not rebuild a spellID-sorted scratch list")
end)

print("ALL PASS")
