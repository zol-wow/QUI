-- tests/unit/uikit_border_refresh_no_n2_test.lua
-- Regression: creating a bordered widget must NOT synchronously walk and
-- re-snap every previously-created bordered widget. That immediate global
-- registry walk made each options page build O(n^2) in bordered-widget count
-- (sliders / dropdowns / editboxes), freezing the client while a settings tab
-- loaded. The global catch-up resnap must be coalesced onto the OnUpdate driver;
-- each widget still snaps its OWN border synchronously on creation.
-- Run: lua tests/unit/uikit_border_refresh_no_n2_test.lua
-- luacheck: globals CreateFrame

local refreshDrivers = {}
function CreateFrame()
    local frame = { scripts = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:GetScript(name) return self.scripts[name] end
    refreshDrivers[#refreshDrivers + 1] = frame
    return frame
end

local currentPixelSize = 0.5

local function NewTexture()
    local texture = { points = {} }
    function texture:ClearAllPoints() self.points = {} end
    function texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function texture:SetHeight(height) self.height = height end
    function texture:SetWidth(width) self.width = width end
    function texture:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function texture:SetSnapToPixelGrid(snap) self.snap = snap end
    function texture:SetTexelSnappingBias(bias) self.bias = bias end
    function texture:Show() self.visible = true end
    function texture:Hide() self.visible = false end
    return texture
end

local function NewFrame()
    local frame = { textures = {} }
    function frame:CreateTexture()
        local texture = NewTexture()
        self.textures[#self.textures + 1] = texture
        return texture
    end
    return frame
end

local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = function()
            return setmetatable({}, { __mode = "k" })
        end,
    },
}

local core = {}
function core:GetPixelSize() return currentPixelSize end
function core:Pixels(value) return value * currentPixelSize end
function ns.Helpers.GetCore() return core end

assert(loadfile("core/uikit.lua"))("QUI", ns)

local UIKit = ns.UIKit
assert(type(UIKit.QueueScaleRefresh) == "function", "UIKit must expose QueueScaleRefresh")

-- Frame A bordered while the pixel size is 0.5.
local frameA = NewFrame()
local edgesA = UIKit.CreateBorderLines(frameA)
assert(edgesA.top.height == 0.5, "frame A should snap its own border on creation")

-- Change the pixel size, then create frame B. Creating B must not synchronously
-- re-snap A: that immediate full-registry walk is the O(n^2) page-build freeze.
-- A is only re-snapped later, once the coalesced OnUpdate driver runs.
currentPixelSize = 0.25
local frameB = NewFrame()
UIKit.CreateBorderLines(frameB)

assert(edgesA.top.height == 0.5,
    "creating a new bordered widget must not synchronously re-snap existing widgets "
    .. "(got " .. tostring(edgesA.top.height) .. "); the global refresh must be deferred")

-- The deferred refresh must still eventually run and catch existing widgets up.
local driver = refreshDrivers[#refreshDrivers]
assert(driver and driver.scripts.OnUpdate, "a coalesced OnUpdate refresh driver must be installed")
driver.scripts.OnUpdate(driver, 0)
assert(edgesA.top.height == 0.25,
    "deferred refresh should re-snap existing widgets to the new pixel size")

print("OK: uikit_border_refresh_no_n2_test")
