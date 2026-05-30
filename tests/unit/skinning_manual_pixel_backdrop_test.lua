-- tests/unit/skinning_manual_pixel_backdrop_test.lua
-- Run: lua tests/unit/skinning_manual_pixel_backdrop_test.lua
-- luacheck: globals CreateFrame

local createdFrames = {}
local safeBackdropCalls = {}
local registeredRefresh

local function NewTexture()
    local texture = {
        points = {},
        visible = false,
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

    function texture:SetTexture(file)
        self.file = file
    end

    function texture:SetColorTexture(r, g, b, a)
        self.colorTexture = { r, g, b, a }
    end

    function texture:SetVertexColor(r, g, b, a)
        self.color = { r, g, b, a }
    end

    function texture:Show()
        self.visible = true
    end

    function texture:Hide()
        self.visible = false
    end

    return texture
end

local function NewFrame(parent)
    local frame = {
        parent = parent,
        textures = {},
        points = {},
        shown = false,
        frameLevel = 4,
    }

    function frame:CreateTexture()
        local texture = NewTexture()
        self.textures[#self.textures + 1] = texture
        return texture
    end

    function frame:SetAllPoints()
        self.allPoints = true
    end

    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end

    function frame:GetFrameLevel()
        return self.frameLevel
    end

    function frame:EnableMouse(enabled)
        self.mouseEnabled = enabled
    end

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(...)
        self.points[#self.points + 1] = { ... }
    end

    function frame:Show()
        self.shown = true
    end

    createdFrames[#createdFrames + 1] = frame
    return frame
end

function CreateFrame(_, _, parent)
    return NewFrame(parent)
end

local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = function()
            return setmetatable({}, { __mode = "k" })
        end,
        GetCore = function()
            return {
                GetPixelSize = function()
                    return 0.5
                end,
                SafeSetBackdrop = function(frame, info, borderColor, bgColor)
                    safeBackdropCalls[#safeBackdropCalls + 1] = {
                        frame = frame,
                        info = info,
                        borderColor = borderColor,
                        bgColor = bgColor,
                    }
                    return true
                end,
            }
        end,
        SafeToNumber = function(value, default)
            return tonumber(value) or default
        end,
    },
    UIKit = {
        RegisterScaleRefresh = function(_, _, callback)
            registeredRefresh = callback
        end,
    },
}

assert(loadfile("modules/skinning/base.lua"))("QUI", ns)

local SkinBase = ns.SkinBase
local owner = NewFrame()

SkinBase.CreateBackdrop(owner, 0.6, 0.7, 0.8, 1, 0.1, 0.2, 0.3, 0.9)

local backdrop = SkinBase.GetBackdrop(owner)
assert(backdrop, "CreateBackdrop must create a cached backdrop frame")
assert(type(backdrop.SetBackdropColor) == "function",
    "plain pixel backdrop frames must expose SetBackdropColor for later refresh callers")
assert(type(backdrop.SetBackdropBorderColor) == "function",
    "plain pixel backdrop frames must expose SetBackdropBorderColor for later refresh callers")
assert(backdrop.textures[1].colorTexture[1] == 0.1 and backdrop.textures[1].colorTexture[4] == 0.9,
    "manual pixel backdrop background must use a solid color texture with the configured color")

backdrop:SetBackdropColor(0.2, 0.3, 0.4, 0.5)
backdrop:SetBackdropBorderColor(0.7, 0.8, 0.9, 1)

assert(backdrop._quiBgR == 0.2 and backdrop._quiBgA == 0.5,
    "manual SetBackdropColor must store the current background color")
assert(backdrop._quiBorderR == 0.7 and backdrop._quiBorderA == 1,
    "manual SetBackdropBorderColor must store the current border color")
assert(backdrop.textures[1].colorTexture[1] == 0.2 and backdrop.textures[1].colorTexture[4] == 0.5,
    "manual SetBackdropColor must recolor solid background textures directly")
assert(backdrop.textures[2].colorTexture[1] == 0.7 and backdrop.textures[2].colorTexture[4] == 1,
    "manual SetBackdropBorderColor must recolor solid border textures directly")

-- A frame that also has SetBackdrop (a "native" Blizzard backdrop frame). After
-- render-path unification (#3) it goes through the same manual 4-texture path as
-- every other frame, so colors stored in _quiBg*/_quiBorder* must still survive a
-- scale-refresh rebuild via that path.
local native = NewFrame()
function native:SetBackdrop(info)
    self.backdropInfo = info
end

SkinBase.ApplyPixelBackdrop(native, 1, true, true)
native._quiBgR, native._quiBgG, native._quiBgB, native._quiBgA = 0.11, 0.12, 0.13, 0.91
native._quiBorderR, native._quiBorderG, native._quiBorderB, native._quiBorderA = 0.61, 0.62, 0.63, 1
registeredRefresh(native)

-- After unification the manual-path SetBackdropColor/SetBackdropBorderColor stubs
-- are installed by EnsureManualBackdrop; they store colors in _qui* fields. Verify
-- the rebuild picked up the pre-stored colors via those fields.
assert(native._quiBgR == 0.11 and native._quiBgA == 0.91,
    "scale refresh must preserve stored native pixel backdrop background colors (#3 unified path)")
assert(native._quiBorderR == 0.61 and native._quiBorderA == 1,
    "scale refresh must preserve stored native pixel backdrop border colors (#3 unified path)")
assert(native.backdropInfo == nil,
    "unified path must not call frame:SetBackdrop on a native frame (#3)")

print("OK: skinning_manual_pixel_backdrop_test")
