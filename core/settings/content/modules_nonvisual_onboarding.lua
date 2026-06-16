---------------------------------------------------------------------------
-- QUI Feature Toggles — Non-visual onboarding (Phase 3)
--
-- Registers feature manifests with moduleEntry blocks for binary-toggleable
-- modules that do NOT have a Layout Mode element. Each entry either:
--   (a) attaches a moduleEntry to an existing feature stub, or
--   (b) creates a new stub feature with the moduleEntry only.
--
-- DB write convention:
--   • If the module exposes a QUI_Refresh<X> global with proper teardown,
--     setEnabled writes the DB key then calls that global.
--   • Otherwise a bare DB write is used (module re-checks enabled on next
--     event or frame update).
--
-- combatLocked policy:
--   false — pure event-handler / hook toggles that touch no frame geometry.
--   true  — would be used if the toggle modifies secure frames or HUD layout.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

if not (Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function") then
    return
end

---------------------------------------------------------------------------
-- Helper: build a moduleEntry for a module whose DB lives in a sub-table
-- (e.g. db.profile.general.popupBlocker) with an "enabled" field.
--
--   dbParentPath  — zero-arg function returning the parent table
--   dbField       — string key inside that table (usually "enabled")
--   refreshGlobal — optional string name of a _G function to call after
--                   toggling (e.g. "QUI_RefreshPopupBlocker")
---------------------------------------------------------------------------
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
            -- Treat nil as true (default-on modules) and explicit false as off.
            return db[dbField] ~= false
        end,
        setEnabled   = function(val)
            local db = GetDB()
            if not db then return end
            db[dbField] = val and true or false
            if ns.QUI_Modules then
                -- NotifyChanged keys on the registered feature id (matches the
                -- per-row Subscribe in modules_page); refreshGlobal/label are a
                -- _G fn name / display string and would miss the right bucket.
                ns.QUI_Modules:NotifyChanged(id)
            end
            if refreshGlobal and type(_G[refreshGlobal]) == "function" then
                _G[refreshGlobal]()
            end
        end,
    }
end

---------------------------------------------------------------------------
-- Helper: register (or attach) a non-visual feature.
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Convenience wrapper used by the simple-table cases.
---------------------------------------------------------------------------
local function Register(id, group, label, caption, combatLocked, dbParentPath, dbField, refreshGlobal)
    RegisterNonVisualFeature(id, MakeSubtableEntry(
        id, group, label, caption, combatLocked, dbParentPath, dbField, refreshGlobal
    ))
end

---------------------------------------------------------------------------
-- DB path helpers
---------------------------------------------------------------------------
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
        -- When a key is requested, return ONLY that subtable (nil if absent) — never
        -- fall back to the whole char root, which would let clickCast read/write
        -- db.char.enabled and pollute the root instead of db.char.clickCast.
        if key then
            return c and c[key]
        end
        return c
    end
end

---------------------------------------------------------------------------
-- Frames group
---------------------------------------------------------------------------

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

---------------------------------------------------------------------------
-- QoL group
---------------------------------------------------------------------------

-- Popup & toast blocker (master toggle; granular sub-toggles live in
-- General > QoL settings panel).
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

-- Quick Salvage: mod-click to disenchant / mill / prospect directly from bags.
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

-- Auto combat log for Mythic+ runs.
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

-- Auto combat log for raid instances.
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

-- Reticle: GCD ring + dot drawn at the cursor position.
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

-- M+ Progress: enemy-forces percentages on nameplates and tooltips.
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

-- Combat text: brief enter/leave combat text indicator near screen center.
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

-- Blizzard Frame Mover: modifier-drag repositioning for Blizzard windows.
Register(
    "blizzardMover",
    ns.L["QoL"],
    ns.L["Blizzard Frame Mover"],
    ns.L["Enables modifier-drag repositioning and scaling of Blizzard's built-in frames."],
    false,
    DBProfile("blizzardMover"),
    "enabled",
    nil   -- no dedicated refresh global; module re-checks DB on each input event
)

---------------------------------------------------------------------------
-- Tooltip group
---------------------------------------------------------------------------

-- Tooltip module master toggle (skinning, anchoring, unit info overlays).
-- The engine's hooks are permanent once installed; toggling enabled only
-- suppresses overlay output on subsequent shows.
Register(
    "tooltip",
    ns.L["Tooltip"],
    ns.L["Tooltip Engine"],
    ns.L["Custom tooltip skin, cursor anchoring, item level overlay, and unit info lines."],
    false,
    DBProfile("tooltip"),
    "enabled",
    nil   -- hooks are permanent; no teardown global required
)

---------------------------------------------------------------------------
-- Consumable Macros (QoL) — custom setEnabled routes through the module API
---------------------------------------------------------------------------

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
            -- Route through the module's public API when available so macro
            -- state is rebuilt (or torn down) immediately.
            local cm = ns.ConsumableMacros
            if cm and type(cm.ForceRefresh) == "function" then
                if val then
                    cm:ForceRefresh()
                end
                -- Disable: module already guards UpdateMacros behind db.enabled,
                -- so the next inventory event will skip macro writes automatically.
            end
        end,
    })
end

---------------------------------------------------------------------------
-- Character group
---------------------------------------------------------------------------

-- Character Pane: custom character panel with equipment overlays and stats.
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

---------------------------------------------------------------------------
-- Subsystems group
---------------------------------------------------------------------------

-- Datatext panel: FPS, latency, durability, gold, time, and other data lines
-- displayed below the minimap.
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
