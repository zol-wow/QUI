local capturedCallbacks = {}
local frameState = setmetatable({}, { __mode = "k" })
local appliedBackdrops = {}

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

local worldMapFrame = {
    ScrollContainer = NewLayeredFrame(),
    NavBar = NewLayeredFrame(),
    BorderFrame = {
        Underlay = { Hide = function() end },
        InsetBorderTop = { Hide = function() end },
    },
}
worldMapFrame.overlayFrames = {
    worldMapFrame.NavBar,
    NewLayeredFrame(),
}

_G.WorldMapFrame = worldMapFrame

local ns = {
    Helpers = {
        GetCore = function()
            return {
                db = {
                    profile = {
                        general = {
                            skinWorldMap = false,
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
    IsSkinned = function(frame)
        return frame.markedSkinned == true
    end,
    MarkSkinned = function(frame)
        frame.markedSkinned = true
    end,
    SkinButtonFrameTemplate = function(frame)
        frame.buttonTemplateSkinned = true
    end,
    GetBackdrop = function()
        return {}
    end,
    SetBackdropColors = function(frame, borderColor, bgColor)
        appliedBackdrops[#appliedBackdrops + 1] = { frame = frame, borderColor = borderColor, bgColor = bgColor }
    end,
    SkinFrameText = function() end,
    OnAddOnLoaded = function(addon, callback)
        capturedCallbacks[addon] = callback
    end,
}

assert(loadfile("modules/skinning/frames/worldmap.lua"))("QUI", ns)

local capturedCallback = capturedCallbacks["Blizzard_WorldMap"]
assert(type(capturedCallback) == "function", "World map skinning must register an addon-loaded callback")

capturedCallback()

assert(worldMapFrame.markedSkinned == nil,
    "World map must not be skinned when skinWorldMap is disabled")
assert(worldMapFrame.ScrollContainer.frameLevel == nil,
    "World map scroll container must keep its native frame level when the skin is disabled")

_G.QUI_RefreshWorldMapColors()

assert(worldMapFrame.ScrollContainer.frameLevel == nil,
    "World map color refresh must not raise the scroll container when the map was never skinned")
assert(worldMapFrame.ScrollContainer.frameStrata == nil,
    "World map color refresh must not change the scroll container strata when the map was never skinned")
assert(worldMapFrame.NavBar.frameLevel == nil,
    "World map color refresh must not raise the navbar when the map was never skinned")
assert(#appliedBackdrops == 0,
    "World map color refresh must not restyle the border when the map was never skinned")

print("OK: worldmap_refresh_unskinned_gate_test")
