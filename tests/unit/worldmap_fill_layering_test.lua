-- tests/unit/worldmap_fill_layering_test.lua
-- Run: lua tests/unit/worldmap_fill_layering_test.lua
local capturedCallbacks = {}
local frameState = setmetatable({}, { __mode = "k" })
local appliedBackdrops = {}

local function NewTexture()
    local texture = {}

    function texture:SetAllPoints(relativeTo)
        self.allPoints = true
        self.relativeTo = relativeTo
    end

    function texture:SetTexture(file)
        self.file = file
    end

    function texture:SetVertexColor(r, g, b, a)
        self.vertexColor = { r, g, b, a }
    end

    return texture
end

local function NewLayeredFrame()
    local frame = {}

    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end

    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end

    return frame
end

local hidden = 0
local backdrop = {}

function backdrop:SetBackdropColor(r, g, b, a)
    self.bgColor = { r, g, b, a }
end

function backdrop:SetBackdropBorderColor(r, g, b, a)
    self.borderColor = { r, g, b, a }
end

local worldMapFrame = {
    textures = {},
    ScrollContainer = NewLayeredFrame(),
    NavBar = NewLayeredFrame(),
    BorderFrame = {
        Underlay = {
            Hide = function()
                hidden = hidden + 1
            end,
        },
        InsetBorderTop = {
            Hide = function()
                hidden = hidden + 1
            end,
        },
    },
}
worldMapFrame.overlayFrames = {
    worldMapFrame.NavBar,
    NewLayeredFrame(),
    NewLayeredFrame(),
}

function worldMapFrame:CreateTexture(name, drawLayer, templateName, subLevel)
    local texture = NewTexture()
    texture.name = name
    texture.drawLayer = drawLayer
    texture.templateName = templateName
    texture.subLevel = subLevel
    self.textures[#self.textures + 1] = texture
    return texture
end

_G.WorldMapFrame = worldMapFrame

local ns = {
    Helpers = {
        GetCore = function()
            return {
                db = {
                    profile = {
                        general = {
                            skinWorldMap = true,
                        },
                    },
                },
            }
        end,
    },
    Registry = {
        Register = function() end,
    },
}

ns.SkinBase = {
    GetFrameData = function(frame, key)
        local data = frameState[frame]
        return data and data[key]
    end,
    SetFrameData = function(frame, key, value)
        local data = frameState[frame]
        if not data then
            data = {}
            frameState[frame] = data
        end
        data[key] = value
    end,
    GetSkinColors = function()
        return 0.1, 0.2, 0.3, 1, 0.05, 0.06, 0.07, 0.88
    end,
    IsSkinned = function()
        return false
    end,
    MarkSkinned = function(frame)
        frame.markedSkinned = true
    end,
    SkinButtonFrameTemplate = function(frame)
        frame.buttonTemplateSkinned = true
    end,
    GetBackdrop = function()
        return backdrop
    end,
    ApplyPixelBackdrop = function(frame, borderPixels, withBackground, withInsets, borderColor, bgColor)
        appliedBackdrops[#appliedBackdrops + 1] = {
            frame = frame,
            borderPixels = borderPixels,
            withBackground = withBackground,
            withInsets = withInsets,
            borderColor = borderColor,
            bgColor = bgColor,
        }
        if bgColor and frame.SetBackdropColor then
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        end
        if borderColor and frame.SetBackdropBorderColor then
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        end
    end,
    -- Canonical recolor of an already-managed pixel-backdrop child: updates the
    -- persisted backdrop state (data.borderColor/data.bgColor) and re-renders. Mirrors
    -- ApplyPixelBackdrop's color application so the persistence assertions below hold.
    SetBackdropColors = function(frame, borderColor, bgColor)
        appliedBackdrops[#appliedBackdrops + 1] = {
            frame = frame,
            borderColor = borderColor,
            bgColor = bgColor,
        }
        if bgColor and frame.SetBackdropColor then
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        end
        if borderColor and frame.SetBackdropBorderColor then
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        end
    end,
    SkinFrameText = function() end,
    OnAddOnLoaded = function(addon, callback)
        capturedCallbacks[addon] = callback
    end,
}

assert(loadfile("QUI_Skinning/skinning/frames/worldmap.lua"))("QUI", ns)
-- worldmap.lua registers several addon-loaded callbacks (WorldMap, FlightMap);
-- target the WorldMap one specifically.
local capturedCallback = capturedCallbacks["Blizzard_WorldMap"]
assert(type(capturedCallback) == "function", "World map skinning must register an addon-loaded callback")

capturedCallback()

assert(worldMapFrame.ScrollContainer.frameStrata == "HIGH",
    "World map scroll container must be raised above the skinned BorderFrame backdrop")
assert(worldMapFrame.ScrollContainer.frameLevel == 100,
    "World map scroll container must stay below the frame's 510-level title controls")
assert(worldMapFrame.NavBar.frameStrata == "HIGH", "World map navbar must be raised with other map overlays")
assert(worldMapFrame.NavBar.frameLevel == 200, "World map navbar must render above the raised scroll container")
for _, overlayFrame in ipairs(worldMapFrame.overlayFrames) do
    assert(overlayFrame.frameStrata == "HIGH", "World map overlay frames must be raised above the skinned backdrop")
    assert(overlayFrame.frameLevel == 200, "World map overlay frames must render above the raised scroll container")
end
assert(#worldMapFrame.textures == 0, "World map skinning should not create a separate map fill texture")

assert(worldMapFrame.BorderFrame.buttonTemplateSkinned == true, "World map border frame should still be skinned")
assert(hidden == 2, "World map native underlay and separator should still be hidden")
assert(worldMapFrame.markedSkinned == true, "World map should still be marked skinned")
assert(backdrop.bgColor and backdrop.bgColor[4] == 0.88, "World map border backdrop fill must stay opaque")
assert(appliedBackdrops[1] and appliedBackdrops[1].frame == backdrop,
    "World map border backdrop must refresh stored pixel-backdrop state")
assert(appliedBackdrops[1].bgColor and appliedBackdrops[1].bgColor[4] == 0.88,
    "World map border backdrop stored background alpha must remain opaque across scale refresh")

_G.QUI_RefreshWorldMapColors()
assert(#worldMapFrame.textures == 0, "World map color refresh must not create a separate fill texture")
assert(worldMapFrame.NavBar.frameStrata == "HIGH", "World map color refresh must keep navbar on the raised strata")
assert(worldMapFrame.NavBar.frameLevel == 200, "World map color refresh must keep navbar above the scroll container")
assert(appliedBackdrops[2] and appliedBackdrops[2].frame == backdrop,
    "World map color refresh must update stored pixel-backdrop state")
assert(appliedBackdrops[2].bgColor and appliedBackdrops[2].bgColor[4] == 0.88,
    "World map color refresh must keep stored border backdrop background opaque")

print("OK: worldmap_fill_layering_test")
