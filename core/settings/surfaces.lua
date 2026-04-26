local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Surfaces = Settings.Surfaces or {
    _definitions = {
        tile = {
            name = "tile",
            includePosition = false,
            inlineNavigation = false,
        },
        layout = {
            name = "layout",
            includePosition = true,
            positionOnly = true,
            inlineNavigation = true,
        },
        full = {
            name = "full",
            includePosition = false,
            inlineNavigation = false,
            fullPage = true,
        },
        composer = {
            name = "composer",
            includePosition = false,
            inlineNavigation = false,
            editorMode = true,
        },
    },
}
Settings.Surfaces = Surfaces

function Surfaces:Get(surfaceName)
    if type(surfaceName) ~= "string" or surfaceName == "" then
        surfaceName = "tile"
    end
    return self._definitions[surfaceName] or self._definitions.tile
end

function Surfaces:IsKnown(surfaceName)
    return self._definitions[surfaceName] ~= nil
end
