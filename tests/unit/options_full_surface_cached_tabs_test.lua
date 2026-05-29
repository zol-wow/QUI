-- tests/unit/options_full_surface_cached_tabs_test.lua
-- Run: lua tests/unit/options_full_surface_cached_tabs_test.lua
-- luacheck: globals CreateFrame

local function NewFrame()
    local frame = {
        children = {},
        regions = {},
        scripts = {},
        shown = true,
    }

    function frame:SetPoint() end
    function frame:SetAllPoints() end
    function frame:SetHeight(height) self.height = height end
    function frame:GetHeight() return self.height or 0 end
    function frame:SetScript(script, handler) self.scripts[script] = handler end
    function frame:HookScript(script, handler) self.scripts[script] = handler end
    function frame:GetChildren() return unpack(self.children) end
    function frame:GetRegions() return unpack(self.regions) end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end

    return frame
end

function CreateFrame(_, _, parent)
    local frame = NewFrame()
    frame.parent = parent
    if parent and parent.children then
        parent.children[#parent.children + 1] = frame
    end
    return frame
end

local ns = {}
assert(loadfile("core/settings/full_surface.lua"))("QUI", ns)

local FullSurface = assert(ns.Settings and ns.Settings.FullSurface)

local body = NewFrame()
local state = { activeTab = "general" }
local tabClicks = {}
local renderCounts = {}
local clearCounts = {}

local function ClearFrame(frame)
    clearCounts[frame] = (clearCounts[frame] or 0) + 1
end

local function CreateTabStrip()
    local strip = NewFrame()
    local function Paint(_, _, onClick)
        tabClicks.general = function() onClick("general") end
        tabClicks.text = function() onClick("text") end
    end
    return strip, Paint
end

FullSurface.BuildScrollTabBody(body, {
    cacheTabBodies = true,
    state = state,
    clearFrame = ClearFrame,
    createTabStrip = CreateTabStrip,
    getTabs = function()
        return {
            { key = "general", label = "General" },
            { key = "text", label = "Text" },
        }
    end,
    getActiveTab = function()
        return state.activeTab
    end,
    setActiveTab = function(tabKey)
        state.activeTab = tabKey
    end,
    render = function()
        renderCounts[state.activeTab] = (renderCounts[state.activeTab] or 0) + 1
    end,
})

assert(renderCounts.general == 1, "initial active tab should render once")

tabClicks.text()
assert(renderCounts.text == 1, "new tab should render on first visit")

tabClicks.general()
assert(renderCounts.general == 1, "cached tab should not rerender when revisited")

state.repaintTabs()
assert(renderCounts.general == 2, "explicit repaint should refresh the active cached tab")

local multiBody = NewFrame()
local multiState = { activeTab = "entries" }
local multiClicks = {}
local multiRenderCounts = {}

local function CreateMultiTabStrip()
    local strip = NewFrame()
    local function Paint(_, _, onClick)
        multiClicks.entries = function() onClick("entries") end
        multiClicks.effects = function() onClick("effects") end
    end
    return strip, Paint
end

FullSurface.BuildMultiHostTabBody(multiBody, {
    cacheTabBodies = true,
    state = multiState,
    clearFrame = ClearFrame,
    createTabStrip = CreateMultiTabStrip,
    hosts = {
        composer = { kind = "plain", clearFrame = ClearFrame },
        scroll = { kind = "plain", clearFrame = ClearFrame },
    },
    defaultHostKey = "scroll",
    resolveHostKey = function(activeTab)
        return activeTab == "entries" and "composer" or "scroll"
    end,
    getTabs = function()
        return {
            { key = "entries", label = "Entries" },
            { key = "effects", label = "Effects" },
        }
    end,
    getActiveTab = function()
        return multiState.activeTab
    end,
    setActiveTab = function(tabKey)
        multiState.activeTab = tabKey
    end,
    render = function(_, activeTab)
        multiRenderCounts[activeTab] = (multiRenderCounts[activeTab] or 0) + 1
    end,
})

assert(multiRenderCounts.entries == 1, "initial multi-host tab should render once")

multiClicks.effects()
assert(multiRenderCounts.effects == 1, "new multi-host tab should render on first visit")

multiClicks.entries()
assert(multiRenderCounts.entries == 1, "cached multi-host tab should not rerender when revisited")

multiState.repaintTabs()
assert(multiRenderCounts.entries == 2, "explicit repaint should refresh the active cached multi-host tab")

print("OK: options_full_surface_cached_tabs_test")
