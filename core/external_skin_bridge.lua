-- core/external_skin_bridge.lua
---------------------------------------------------------------------------
-- QUI External Skin Bridge
-- Optional integration with a third-party button-skinning library. This is
-- the ONLY file in the addon that references that library's LibStub id; keep
-- it that way. When the library is present AND general.externalSkinning is
-- enabled, surfaces register their buttons here instead of applying QUI's own
-- in-house skin, so the user's chosen external skin themes the button (and,
-- when the skin supplies one, the proc glow too).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Bridge = { groups = {} }
ns.ExternalSkinBridge = Bridge

local lib  -- resolved once at load
if _G.LibStub then
    lib = _G.LibStub("Masque", true)
end

function Bridge.IsAvailable()
    return lib ~= nil
end

local function GetGroup(surfaceKey)
    if not lib then return nil end
    local g = Bridge.groups[surfaceKey]
    if not g then
        g = lib:Group("QUI", surfaceKey)
        Bridge.groups[surfaceKey] = g
    end
    return g
end

--- Hand a button (with its normalized region table) to the external group.
function Bridge.AddButton(surfaceKey, button, regions)
    local g = GetGroup(surfaceKey)
    if g and g.AddButton then g:AddButton(button, regions) end
end

function Bridge.RemoveButton(surfaceKey, button)
    local g = Bridge.groups[surfaceKey]
    if g and g.RemoveButton then g:RemoveButton(button) end
end

--- Whether the active external skin draws its own proc/spell-alert glow.
--- Conservative: only true when the lib is present (skins generally theme the
--- SpellAlert region). Surfaces use this to stand down QUI suppression.
function Bridge.SkinProvidesGlow()
    return lib ~= nil
end

return Bridge
