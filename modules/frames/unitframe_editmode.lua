---------------------------------------------------------------------------
-- QUI Unit Frames - Edit Mode Stubs
-- Old overlay system removed — Layout Mode handles replace these.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- QUI_UF is created in unitframes.lua and exported to ns.QUI_UnitFrames.
local QUI_UF = ns.QUI_UnitFrames
if not QUI_UF then return end

-- Expose edit mode state globally so HUD visibility can
-- force unit frames to full alpha during Layout Mode.
_G.QUI_IsUnitFrameEditModeActive = function()
    return _G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive() or false
end

-- No-op stubs: called from unitframes.lua but edit mode overlays are gone.
function QUI_UF:RestoreEditOverlayIfNeeded() end
function QUI_UF:HookBlizzardEditMode() end
