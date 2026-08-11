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

local DESCS = {
    QUI_ActionBars   = ns.L["Action bars, keybinds, and buff borders."],
    QUI_CDM          = ns.L["Cooldown Manager bars and icons."],
    QUI_Chat         = ns.L["QUI chat display, windows, and whisper tabs."],
    QUI_GroupFrames  = ns.L["Party and raid frames."],
    QUI_Nameplates   = ns.L["Custom enemy and friendly nameplates."],
    QUI_ResourceBars = ns.L["Personal resource and power bars."],
    QUI_UnitFrames   = ns.L["Player, target, focus, and boss frames."],
    QUI_DamageMeter  = ns.L["Built-in damage meter."],
    QUI_Bags         = ns.L["Bag, bank, guild bank, and storage windows with a cross-character cache."],
    minimap          = ns.L["Minimap reskin and button drawer."],
    infobar          = ns.L["Full-width top/bottom info bar with datatext widgets."],
    alts             = ns.L["Alt roster window over the account-wide character cache."],
    datatexts        = ns.L["Standalone datatext panels."],
    skinning         = ns.L["Reskin of Blizzard frames, tooltips, and windows."],
}

local function ShowReloadPrompt()
    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI
    if GUI and type(GUI.ShowConfirmation) == "function" then
        GUI:ShowConfirmation({
            title      = ns.L["Reload UI?"],
            message    = ns.L["This change takes full effect after a reload."],
            acceptText = ns.L["Reload"],
            cancelText = ns.L["Later"],
            onAccept   = function() QUI:SafeReload() end,
        })
    end
end

local function AddonExists(folder)
    if C_AddOns and type(C_AddOns.DoesAddOnExist) == "function" then
        return C_AddOns.DoesAddOnExist(folder)
    end
    return true
end

local function ReadLegacyFlag(flagPath)
    local profile = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    if not profile then return true end
    local node = profile
    for i = 1, #flagPath do
        if type(node) ~= "table" then return true end
        node = node[flagPath[i]]
    end
    return node ~= false
end

local function WriteLegacyFlag(flagPath, value)
    local profile = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    if not profile then return end
    local node = profile
    for i = 1, #flagPath - 1 do
        if type(node) ~= "table" then return end
        local next = node[flagPath[i]]
        if type(next) ~= "table" then return end
        node = next
    end
    if type(node) == "table" then
        node[flagPath[#flagPath]] = value
    end
end

local LABELS = {
    QUI_ActionBars   = ns.L["Action Bars"],
    QUI_CDM          = ns.L["Cooldown Manager"],
    QUI_Chat         = ns.L["Chat"],
    QUI_GroupFrames  = ns.L["Group Frames"],
    QUI_Nameplates   = ns.L["Nameplates"],
    QUI_ResourceBars = ns.L["Resource Bars"],
    QUI_UnitFrames   = ns.L["Unit Frames"],
    QUI_DamageMeter  = ns.L["Damage Meter"],
    QUI_Bags         = ns.L["Bags"],
    minimap          = ns.L["Minimap"],
    infobar          = ns.L["Info Bar"],
    alts             = ns.L["Alts"],
    datatexts        = ns.L["Datatexts"],
    skinning         = ns.L["Skinning"],
}

local function ShowDependencyPrompt(folder, depFolder)
    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI
    local label    = LABELS[folder] or folder
    local depLabel = LABELS[depFolder] or depFolder
    if GUI and type(GUI.ShowConfirmation) == "function" then
        GUI:ShowConfirmation({
            title      = ns.L["Dependency Disabled"],
            message    = (label .. ns.L[" requires the "] .. depLabel
                .. ns.L[" module addon, which is disabled. Enable "] .. depLabel .. ns.L[" too?"]),
            acceptText = ns.L["Enable"],
            cancelText = ns.L["Later"],
            onAccept   = function()
                local depResult = ns.AddonLoader.SetModuleAddonEnabled(depFolder, true)
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
    local flagPath  = entry.legacyFlag

    if entry.hostAddon or entry.coreModule then
        local mod = entry.module or entry.coreModule
        local hostFlagPath = entry.flag
        if LABELS[mod] then
            local hostEntry = {
                group        = ns.L["Module Addons"],
                label        = LABELS[mod],
                caption      = DESCS[mod] or "",
                combatLocked = false,
                isEnabled    = function()
                    return ReadLegacyFlag(hostFlagPath)
                end,
                setEnabled   = function(val)
                    WriteLegacyFlag(hostFlagPath, val and true or false)
                    ShowReloadPrompt()
                end,
            }
            Registry:RegisterFeature(Schema.Feature({
                id          = "moduleFlag_" .. mod,
                category    = "global",
                moduleEntry = hostEntry,
            }))
        end

    elseif folder and AddonExists(folder) then
        local moduleEntry = {
            group        = ns.L["Module Addons"],
            label        = LABELS[folder] or folder:match("^QUI_(.+)$") or folder,
            caption      = DESCS[folder] or "",
            combatLocked = false,
            isEnabled    = function()
                local addonOn = ns.AddonLoader.IsModuleAddonEnabled(folder)
                if flagPath then
                    return addonOn and ReadLegacyFlag(flagPath)
                end
                return addonOn
            end,
            setEnabled   = function(val)
                local flipped = false
                if flagPath then
                    if val then
                        flipped = (ReadLegacyFlag(flagPath) == false)
                    end
                    WriteLegacyFlag(flagPath, val and true or false)
                end
                local result, depFolder = ns.AddonLoader.SetModuleAddonEnabled(folder, val and true or false)
                if ns.QUI_Modules then
                    ns.QUI_Modules:NotifyChanged("moduleAddon_" .. folder)
                end
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
