-- tests/unit/pixel_border_refresh_test.lua
-- Run: lua tests/unit/pixel_border_refresh_test.lua
-- luacheck: globals CreateFrame

local currentPixelSize = 0.5
local refreshDrivers = {}

function CreateFrame()
    local frame = { scripts = {} }

    function frame:SetScript(scriptName, fn)
        self.scripts[scriptName] = fn
    end

    function frame:GetScript(scriptName)
        return self.scripts[scriptName]
    end

    refreshDrivers[#refreshDrivers + 1] = frame
    return frame
end

local function NewTexture()
    local texture = {
        points = {},
        visible = false,
        snap = nil,
        bias = nil,
    }

    function texture:ClearAllPoints()
        self.points = {}
    end

    function texture:SetPoint(...)
        self.points[#self.points + 1] = { ... }
    end

    function texture:SetHeight(height)
        self.height = height
    end

    function texture:SetWidth(width)
        self.width = width
    end

    function texture:SetColorTexture(r, g, b, a)
        self.color = { r, g, b, a }
    end

    function texture:SetSnapToPixelGrid(snap)
        self.snap = snap
    end

    function texture:SetTexelSnappingBias(bias)
        self.bias = bias
    end

    function texture:Show()
        self.visible = true
    end

    function texture:Hide()
        self.visible = false
    end

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
function core:GetPixelSize()
    return currentPixelSize
end

function core:Pixels(value)
    return value * currentPixelSize
end

function ns.Helpers.GetCore()
    return core
end

assert(loadfile("core/uikit.lua"))("QUI", ns)

local UIKit = ns.UIKit
assert(type(UIKit.QueueScaleRefresh) == "function", "UIKit must expose QueueScaleRefresh")
assert(type(UIKit.RefreshPixelBorders) == "function", "UIKit must expose RefreshPixelBorders")

local frame = NewFrame()
local edges = UIKit.CreateBorderLines(frame)

assert(edges.top.height == 0.5, "initial border height should be one physical pixel")
assert(edges.left.width == 0.5, "initial border width should be one physical pixel")

currentPixelSize = 0.25
UIKit.QueueScaleRefresh(2)

local driver = refreshDrivers[#refreshDrivers]
assert(driver and driver.scripts.OnUpdate, "QueueScaleRefresh must install an OnUpdate refresh driver")
driver.scripts.OnUpdate(driver, 0)

assert(edges.top.height == 0.25, "queued refresh should recompute border height from current pixel size")
assert(edges.left.width == 0.25, "queued refresh should recompute border width from current pixel size")

print("OK: pixel_border_refresh_test")
