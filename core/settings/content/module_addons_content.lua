---------------------------------------------------------------------------
-- Module Addons — one toggle row per QUI sub-addon.
--
-- The toggle drives Blizzard's addon enable state, which controls whether
-- the sub-addon's code is present at all (zero cost when off after reload).
--
-- Three entries carry a manifest legacyFlag (chat.enabled, quiGroupFrames.enabled, bags.enabled).
-- These flags act as dormant guards: their module's own init skips setup when
-- the flag is false.  For those entries the row shows OFF when either the
-- addon is disabled OR the flag is false, and heals the flag to true on
-- enable so the module becomes fully active after reload.
--
--   isEnabled  (with legacyFlag): IsModuleAddonEnabled(folder) AND flag ~= false
--   setEnabled(true):  write flag → true (if path materialized), then
--                      SetModuleAddonEnabled(folder, true)
--   setEnabled(false): write flag → false (same nil-safe walk), then
--                      SetModuleAddonEnabled(folder, false)
--
--   off             → DisableAddOn + reload prompt (zero cost next reload)
--   on  (LOD class) → EnableAddOn + LoadAddOn live, no reload needed
--   on  (login cls) → EnableAddOn + reload prompt
--   on  (dep disabled) → dependency prompt (enable dep + retry)
--   on  (legacyFlag, already loaded) → healed flag + reload prompt
--       Enabling a dormant-guarded module that is already loaded (login-class)
--       returns "loaded" from the loader, but the module's activation runs at
--       load time — so a reload is still needed when the flag was false.
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
    QUI_Datatexts    = "Datatext registry, providers, and custom datapanels.",
    QUI_Minimap      = "Minimap reskin and button drawer.",
    QUI_QoL          = "Quality-of-life features, dungeon tools, and trackers.",
    QUI_DamageMeter  = "Built-in damage meter.",
    QUI_InfoBar      = "Full-width top/bottom info bar with datatext widgets.",
    QUI_Bags         = "Bag, bank, guild bank, and storage windows with a cross-character cache.",
    QUI_Alts         = "Alt roster window over the account-wide character cache.",
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
-- legacyFlag helpers: nil-safe flag read + write against QUI.db.profile.
-- AceDB materializes defaults so intermediate tables are normally present at
-- runtime; absent tables are treated as not-false (flag defaults to on).
-- On disable we write false to preserve the module's live-teardown semantics.
---------------------------------------------------------------------------

-- Read a legacyFlag path from the live profile.  Returns false only when the
-- final value is explicitly false; absent tables / nil value → treat as on.
-- Guards against QUI.db being absent (headless context).
local function ReadLegacyFlag(flagPath)
    local profile = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    if not profile then return true end  -- DB absent → treat as on
    local node = profile
    for i = 1, #flagPath do
        if type(node) ~= "table" then return true end
        node = node[flagPath[i]]
    end
    return node ~= false
end

-- Write a legacyFlag path in the live profile.  Walks the path, skipping the
-- write silently if an intermediate table is missing (AceDB materializes them
-- in practice; missing → flag was never set → heal is a no-op, fine).
local function WriteLegacyFlag(flagPath, value)
    local profile = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    if not profile then return end
    local node = profile
    for i = 1, #flagPath - 1 do
        if type(node) ~= "table" then return end  -- intermediate missing; skip
        local next = node[flagPath[i]]
        if type(next) ~= "table" then return end  -- not materialized yet; skip
        node = next
    end
    if type(node) == "table" then
        node[flagPath[#flagPath]] = value
    end
end

---------------------------------------------------------------------------
-- One moduleEntry + stub feature per manifest entry.
-- Entries whose folder is absent from disk are silently skipped.
---------------------------------------------------------------------------
-- Display labels (match the sub-addon TOC titles); search keywords are built
-- from these, so spaced names keep e.g. "damage meter" findable.
local LABELS = {
    QUI_ActionBars   = "Action Bars",
    QUI_CDM          = "Cooldown Manager",
    QUI_Chat         = "Chat",
    QUI_GroupFrames  = "Group Frames",
    QUI_ResourceBars = "Resource Bars",
    QUI_UnitFrames   = "Unit Frames",
    QUI_Skinning     = "Skinning",
    QUI_Datatexts    = "Datatexts",
    QUI_Minimap      = "Minimap",
    QUI_QoL          = "Quality of Life",
    QUI_DamageMeter  = "Damage Meter",
    QUI_InfoBar      = "Info Bar",
    QUI_Bags         = "Bags",
    QUI_Alts         = "Alts",
}

---------------------------------------------------------------------------
-- Dependency prompt: enabling a module whose hard TOC dependency is disabled
-- can't load it (the client refuses DEP_DISABLED loads, and a reload won't
-- fix it). Offer to enable the dependency too; on accept, retry the original
-- module so an LOD pair comes up live without a reload when possible.
---------------------------------------------------------------------------
local function ShowDependencyPrompt(folder, depFolder)
    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI
    local label    = LABELS[folder] or folder
    local depLabel = LABELS[depFolder] or depFolder
    if GUI and type(GUI.ShowConfirmation) == "function" then
        GUI:ShowConfirmation({
            title      = "Dependency Disabled",
            message    = (label .. " requires the " .. depLabel
                .. " module addon, which is disabled. Enable " .. depLabel .. " too?"),
            acceptText = "Enable",
            cancelText = "Later",
            onAccept   = function()
                local depResult = ns.AddonLoader.SetModuleAddonEnabled(depFolder, true)
                -- Retry the original module now that the dependency is enabled.
                local result = ns.AddonLoader.SetModuleAddonEnabled(folder, true)
                if ns.QUI_Modules then
                    ns.QUI_Modules:NotifyChanged("moduleAddon_" .. depFolder)
                    ns.QUI_Modules:NotifyChanged("moduleAddon_" .. folder)
                end
                if depResult == "reload" or result == "reload" then
                    ShowReloadPrompt()
                end
            end,
        })
    end
end

for _, entry in ipairs(ns.AddonManifest) do
    local folder    = entry.folder
    local flagPath  = entry.legacyFlag  -- nil for most entries

    -- Skip sub-addons not installed in this client.
    if AddonExists(folder) then
        local moduleEntry = {
            group        = "Module Addons",
            label        = LABELS[folder] or folder:match("^QUI_(.+)$") or folder,
            caption      = DESCS[folder] or "",
            combatLocked = false,
            isEnabled    = function()
                local addonOn = ns.AddonLoader.IsModuleAddonEnabled(folder)
                if flagPath then
                    -- AND with the dormant-guard flag: if the flag is false the
                    -- row shows OFF even when the addon itself is enabled.
                    return addonOn and ReadLegacyFlag(flagPath)
                end
                return addonOn
            end,
            setEnabled   = function(val)
                local flipped = false
                if flagPath then
                    -- Detect whether the dormant-guard flag was explicitly false
                    -- BEFORE writing, so we can decide whether a reload is needed
                    -- even when the addon is already loaded (login-class path).
                    if val then
                        flipped = (ReadLegacyFlag(flagPath) == false)
                    end
                    -- Heal (or clear) the dormant-guard flag so the module
                    -- becomes fully active (or correctly dormant) after reload.
                    WriteLegacyFlag(flagPath, val and true or false)
                end
                local result, depFolder = ns.AddonLoader.SetModuleAddonEnabled(folder, val and true or false)
                if ns.QUI_Modules then
                    ns.QUI_Modules:NotifyChanged("moduleAddon_" .. folder)
                end
                -- "depDisabled" = hard TOC dependency disabled; a reload can't
                --   help, so name the dependency and offer to enable it.
                -- "reload" = login-class addon or disable; always prompt.
                -- "loaded" = LOD addon brought live; no prompt needed UNLESS
                --   the dormant-guard flag was false (module activation runs at
                --   load time, so it won't activate until a reload clears it).
                if result == "depDisabled" then
                    ShowDependencyPrompt(folder, depFolder)
                elseif result == "reload" or (flipped and result == "loaded") then
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
