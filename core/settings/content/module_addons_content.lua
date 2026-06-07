---------------------------------------------------------------------------
-- Module Addons — one toggle row per QUI sub-addon.
--
-- The toggle drives Blizzard's addon enable state, which controls whether
-- the sub-addon's code is present at all (zero cost when off after reload).
-- Per-module master flags keep their live feature semantics and are NOT
-- touched here.
--
--   off             → DisableAddOn + reload prompt (zero cost next reload)
--   on  (LOD class) → EnableAddOn + LoadAddOn live, no reload needed
--   on  (login cls) → EnableAddOn + reload prompt
--
-- "not installed" (folder absent from disk): the row is silently skipped so
-- the panel never shows a toggle for a sub-addon the user hasn't deployed.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

if not (Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(ns.AddonManifest) == "table"
    and type(ns.AddonLoader) == "table") then
    return
end

---------------------------------------------------------------------------
-- Human-readable description for each sub-addon.
---------------------------------------------------------------------------
local DESCS = {
    QUI_ActionBars   = "Action bars, keybinds, and buff borders.",
    QUI_CDM          = "Cooldown Manager bars and icons.",
    QUI_Chat         = "QUI chat display, windows, and whisper tabs.",
    QUI_GroupFrames  = "Party and raid frames.",
    QUI_ResourceBars = "Personal resource and power bars.",
    QUI_UnitFrames   = "Player, target, focus, and boss frames.",
    QUI_Skinning     = "Blizzard UI reskin — character pane, popups, tooltips.",
    QUI_Minimap      = "Minimap reskin and data panels.",
    QUI_QoL          = "Quality-of-life features, dungeon tools, and trackers.",
    QUI_DamageMeter  = "Built-in damage meter.",
}

---------------------------------------------------------------------------
-- Reload-prompt helper (mirrors layout mode and non-visual onboarding).
---------------------------------------------------------------------------
local function ShowReloadPrompt()
    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI
    if GUI and type(GUI.ShowConfirmation) == "function" then
        GUI:ShowConfirmation({
            title      = "Reload UI?",
            message    = "This change takes full effect after a reload.",
            acceptText = "Reload",
            cancelText = "Later",
            onAccept   = function() QUI:SafeReload() end,
        })
    end
end

---------------------------------------------------------------------------
-- DoesAddOnExist guard: C_AddOns may be nil in the headless test harness.
-- When nil we assume present (worst case = showing a toggle for a missing
-- addon, which SetModuleAddonEnabled("missing") handles gracefully).
---------------------------------------------------------------------------
local function AddonExists(folder)
    if C_AddOns and type(C_AddOns.DoesAddOnExist) == "function" then
        return C_AddOns.DoesAddOnExist(folder)
    end
    return true  -- headless / API-absent: treat as present
end

---------------------------------------------------------------------------
-- One moduleEntry + stub feature per manifest entry.
-- Entries whose folder is absent from disk are silently skipped.
---------------------------------------------------------------------------
for _, entry in ipairs(ns.AddonManifest) do
    local folder = entry.folder

    -- Skip sub-addons not installed in this client.
    if AddonExists(folder) then
        -- Strip "QUI_" prefix to get a readable short name (e.g. "ActionBars").
        local shortName = folder:match("^QUI_(.+)$") or folder

        local moduleEntry = {
            group        = "Module Addons",
            label        = shortName,
            caption      = DESCS[folder] or "",
            combatLocked = false,
            isEnabled    = function()
                return ns.AddonLoader.IsModuleAddonEnabled(folder)
            end,
            setEnabled   = function(val)
                local result = ns.AddonLoader.SetModuleAddonEnabled(folder, val and true or false)
                if ns.QUI_Modules then
                    ns.QUI_Modules:NotifyChanged(folder)
                end
                -- "loaded" = LOD addon brought live; no prompt needed.
                -- "reload" = login-class or disable; prompt the user.
                if result == "reload" then
                    ShowReloadPrompt()
                end
            end,
        }

        Registry:RegisterFeature(Schema.Feature({
            id          = "moduleAddon_" .. folder,
            category    = "global",
            moduleEntry = moduleEntry,
        }))
    end
end
