local ADDON_NAME, ns = ...
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

if not (Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function") then
    return
end

local function MakeSubtableEntry(id, group, label, caption, combatLocked, dbParentPath, dbField, refreshGlobal)
    local function GetDB()
        return type(dbParentPath) == "function" and dbParentPath() or nil
    end

    return {
        group        = group,
        label        = label,
        caption      = caption,
        combatLocked = combatLocked,
        isEnabled    = function()
            local db = GetDB()
            if not db then return false end
            return db[dbField] ~= false
        end,
        setEnabled   = function(val)
            local db = GetDB()
            if not db then return end
            db[dbField] = val and true or false
            if ns.QUI_Modules then
                ns.QUI_Modules:NotifyChanged(id)
            end
            if refreshGlobal and type(_G[refreshGlobal]) == "function" then
                _G[refreshGlobal]()
            end
        end,
    }
end

local function RegisterNonVisualFeature(id, moduleEntry)
    local existing = Registry:GetFeature(id)
    if existing then
        existing.moduleEntry = moduleEntry
        return
    end
    Registry:RegisterFeature(Schema.Feature({
        id          = id,
        category    = "global",
        moduleEntry = moduleEntry,
    }))
end

local function Register(id, group, label, caption, combatLocked, dbParentPath, dbField, refreshGlobal)
    RegisterNonVisualFeature(id, MakeSubtableEntry(
        id, group, label, caption, combatLocked, dbParentPath, dbField, refreshGlobal
    ))
end

local function DBGeneral()
    local QUI = _G.QUI
    local p = QUI and QUI.db and QUI.db.profile
    return p and p.general
end

local function DBProfile(key)
    return function()
        local QUI = _G.QUI
        local p = QUI and QUI.db and QUI.db.profile
        return p and p[key]
    end
end

local function DBChar(key)
    return function()
        local QUI = _G.QUI
        local c = QUI and QUI.db and QUI.db.char
        if key then
            return c and c[key]
        end
        return c
    end
end

RegisterNonVisualFeature("clickCast", {
    group        = ns.L["Frames"],
    label        = ns.L["Click-Cast"],
    caption      = ns.L["Mouse and key bindings on unit, party, and raid frames."],
    combatLocked = true,
    isEnabled    = function()
        local db = DBChar("clickCast")()
        return db and db.enabled ~= false
    end,
    setEnabled   = function(val)
        local db = DBChar("clickCast")()
        if not db then return end
        db.enabled = val ~= false
        if ns.QUI_Modules then
            ns.QUI_Modules:NotifyChanged("clickCast")
        end
        local cc = ns.QUI_GroupFrameClickCast
        local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown()
        if cc and type(cc.RefreshBindings) == "function" and not inCombat then
            cc:RefreshBindings()
        end
    end,
})

Register(
    "popupBlocker",
    ns.L["QoL"],
    ns.L["Popup Blocker"],
    ns.L["Hides Blizzard tutorial popups, micro-button glows, and collection toasts."],
    false,
    function() local g = DBGeneral(); return g and g.popupBlocker end,
    "enabled",
    "QUI_RefreshPopupBlocker"
)

Register(
    "quickSalvage",
    ns.L["QoL"],
    ns.L["Quick Salvage"],
    ns.L["Alt-click bag items to instantly disenchant, mill, or prospect them."],
    false,
    function() local g = DBGeneral(); return g and g.quickSalvage end,
    "enabled",
    "QUI_RefreshQuickSalvage"
)

Register(
    "autoCombatLog",
    ns.L["QoL"],
    ns.L["Auto Log M+"],
    ns.L["Automatically starts and stops combat logging when entering Mythic+ dungeons."],
    false,
    DBGeneral,
    "autoCombatLog",
    "QUI_RefreshAutoCombatLogging"
)

Register(
    "autoCombatLogRaid",
    ns.L["QoL"],
    ns.L["Auto Log Raids"],
    ns.L["Automatically starts and stops combat logging when entering raid instances."],
    false,
    DBGeneral,
    "autoCombatLogRaid",
    "QUI_RefreshAutoCombatLogging"
)

Register(
    "reticle",
    ns.L["QoL"],
    ns.L["Reticle"],
    ns.L["GCD ring and reticle drawn at the cursor for cast timing feedback."],
    false,
    DBProfile("reticle"),
    "enabled",
    "QUI_RefreshReticle"
)

Register(
    "mplusProgress",
    ns.L["QoL"],
    ns.L["M+ Progress"],
    ns.L["Displays enemy forces contribution on nameplates and unit tooltips in Mythic+."],
    false,
    DBProfile("mplusProgress"),
    "enabled",
    "QUI_RefreshMPlusProgress"
)

Register(
    "combatText",
    ns.L["QoL"],
    ns.L["Combat Text"],
    ns.L["Shows a brief text flash when entering or leaving combat."],
    false,
    DBProfile("combatText"),
    "enabled",
    "QUI_RefreshCombatText"
)

Register(
    "blizzardMover",
    ns.L["QoL"],
    ns.L["Blizzard Frame Mover"],
    ns.L["Enables modifier-drag repositioning and scaling of Blizzard's built-in frames."],
    false,
    DBProfile("blizzardMover"),
    "enabled",
    nil
)

Register(
    "tooltip",
    ns.L["Tooltip"],
    ns.L["Tooltip Engine"],
    ns.L["Custom tooltip skin, cursor anchoring, item level overlay, and unit info lines."],
    false,
    DBProfile("tooltip"),
    "enabled",
    nil
)

do
    local function GetConsumableMacrosDB()
        local QUI = _G.QUI
        local p = QUI and QUI.db and QUI.db.profile
        local g = p and p.general
        return g and g.consumableMacros
    end

    RegisterNonVisualFeature("consumableMacros", {
        group        = ns.L["QoL"],
        label        = ns.L["Consumable Macros"],
        caption      = ns.L["Auto-maintains bag-aware macros for flasks, potions, augment runes, and weapon oils."],
        combatLocked = false,
        isEnabled    = function()
            local db = GetConsumableMacrosDB()
            return db and db.enabled == true
        end,
        setEnabled   = function(val)
            local db = GetConsumableMacrosDB()
            if not db then return end
            db.enabled = val and true or false
            if ns.QUI_Modules then
                ns.QUI_Modules:NotifyChanged("consumableMacros")
            end
            local cm = ns.ConsumableMacros
            if cm and type(cm.ForceRefresh) == "function" then
                if val then
                    cm:ForceRefresh()
                end
            end
        end,
    })
end

Register(
    "character",
    ns.L["Character"],
    ns.L["Character Pane"],
    ns.L["Custom character panel showing item level, enchants, gem slots, and stat overlays."],
    false,
    DBProfile("character"),
    "enabled",
    "QUI_RefreshCharacterPane"
)

Register(
    "datatext",
    ns.L["Subsystems"],
    ns.L["Datatext Panel"],
    ns.L["Info panel below the minimap displaying FPS, latency, durability, time, and more."],
    false,
    DBProfile("datatext"),
    "enabled",
    "QUI_RefreshDatapanels"
)
