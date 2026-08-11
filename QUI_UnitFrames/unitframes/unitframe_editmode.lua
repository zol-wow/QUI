local ADDON_NAME, ns = ...

local QUI_UF = ns.QUI_UnitFrames
if not QUI_UF then return end

_G.QUI_IsUnitFrameEditModeActive = function()
    return _G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive() or false
end

function QUI_UF:RestoreEditOverlayIfNeeded() end
function QUI_UF:HookBlizzardEditMode() end
