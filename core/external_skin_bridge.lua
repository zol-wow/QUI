local ADDON_NAME, ns = ...

local Bridge = { groups = {} }
ns.ExternalSkinBridge = Bridge

local lib
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

function Bridge.AddButton(surfaceKey, button, regions)
    local g = GetGroup(surfaceKey)
    if g and g.AddButton then g:AddButton(button, regions) end
end

function Bridge.RemoveButton(surfaceKey, button)
    local g = Bridge.groups[surfaceKey]
    if g and g.RemoveButton then g:RemoveButton(button) end
end

function Bridge.SkinProvidesGlow()
    return lib ~= nil
end

return Bridge
