-- tests/unit/uikit_border_refresh_bad_edge_test.lua
-- Run: lua tests/unit/uikit_border_refresh_bad_edge_test.lua
-- luacheck: globals CreateFrame

local refreshDrivers = {}
local currentPixelSize = 0.5

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
    }

    function texture:ClearAllPoints()
        if self.failClearAllPoints then
            error("calling 'ClearAllPoints' on bad self")
        end
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
        CHROME = {
            BORDER_PX = 1,
            BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 },
            BORDER_FALLBACK = { 0, 0, 0, 1 },
            BUTTON_BOOST = 0.07,
            SCROLLROW_BOOST = 0.03,
            DEPTH = {
                PANEL = { boost = 0, alpha = 0.95 },
                SUBPANEL = { boost = 0.04, alpha = 0.85 },
                ROW = { boost = 0.07, alpha = 0.75 },
            },
        },
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
local frame = NewFrame()
local edges = UIKit.CreateBorderLines(frame)

assert(#frame.textures == 4, "initial border creation should create four edge textures")

edges.top.failClearAllPoints = true
local ok, err = pcall(UIKit.RefreshPixelBorders)
assert(ok, "RefreshPixelBorders must not surface a stale edge error: " .. tostring(err))

UIKit.UpdateBorderLines(frame, 2, 1, 0, 0, 1, false)

assert(#frame.textures == 8,
    "UpdateBorderLines should recreate border edge textures after a failed refresh")
assert(frame.textures[5].height == 1,
    "recreated top edge should be refreshed with the requested pixel size")

print("OK: uikit_border_refresh_bad_edge_test")
