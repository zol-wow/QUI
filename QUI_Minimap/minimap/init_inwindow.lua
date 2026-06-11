---------------------------------------------------------------------------
-- IN-WINDOW MINIMAP INIT (combat /reload safe)
---------------------------------------------------------------------------
--
-- The minimap's one-time init does protected layout on the Minimap — a Blizzard
-- protected frame — via SetPoint/SetParent/SetSize/SetScale. Those are blocked
-- in combat UNLESS they run inside the core's ADDON_LOADED safe window
-- (ns._inInitSafeWindow), where protected calls are permitted even during a
-- combat /reload. The core eager-loads QUI_Minimap synchronously inside that
-- window, executing every TOC sibling in order; this file is the LAST sibling,
-- so by here all dependencies are loaded AND we are still in the window. Fire
-- the init NOW, synchronously, so a /reload issued in combat lands the minimap
-- correctly instead of throwing ADDON_ACTION_BLOCKED.
--
-- History: this block used to live at the bottom of datapanels.lua when that
-- file was this addon's last TOC sibling. The datatext extraction moved
-- datapanels out; the block stays behind here because the safe window is a
-- property of THIS addon's load, not of the datapanels feature.
-- minimap.lua's WhenLoggedIn path is retained as the live-toggle / headless
-- fallback (InitializeOnce is idempotent); the login path is driven here,
-- in-window. Outside the window (live toggle, headless), this is a no-op and
-- the fallback path runs instead.
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

if ns._inInitSafeWindow and QUICore and QUICore.Minimap and QUICore.Minimap.InitializeOnce then
    QUICore.Minimap:InitializeOnce()
end
