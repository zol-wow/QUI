-- tests/unit/module_addons_rows_test.lua
-- Verifies the Module Addons row registrations after coreModule refactor:
--   - NO QUI_UI bundle folder row (bundle gone; modules ship inside QUI core).
--   - moduleFlag_minimap, moduleFlag_infobar, moduleFlag_alts,
--     moduleFlag_datatexts, moduleFlag_skinning rows are registered.
--   - NO moduleFlag_qol (qol stays always-on; its per-feature general.* flags
--     toggle each QoL feature individually).
--   - Toggling moduleFlag_datatexts writes profile.quiDatatexts.enabled
--     (NOT profile.datatexts — the DB key is quiDatatexts).
--   - Toggling moduleFlag_skinning writes profile.skinning.enabled.
--   - Flag rows do NOT call EnableAddOn/DisableAddOn (no addon enable state
--     change — only a profile flag write + reload prompt).
-- Run: lua5.1 tests/unit/module_addons_rows_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

-- Stub Registry + Schema to capture registered features.
local features = {}
local Registry = {
    GetFeature      = function(_, id) return features[id] end,
    RegisterFeature = function(_, spec) features[spec.id] = spec; return spec end,
}
local Schema = { Feature = function(def) return def end }

local ns = { Settings = { Registry = Registry, Schema = Schema } }
;(dofile("tests/helpers/locale.lua"))(ns)

-- Profile stub with all five coreModule flag tables.
local profile = {
    minimap      = { enabled = true  },
    infobar      = { enabled = true  },
    alts         = { enabled = true  },
    skinning     = { enabled = true  },
    quiDatatexts = { enabled = true  },
}
local enableAddonCalls = {}
local disableAddonCalls = {}
_G.QUI = {
    db  = { profile = profile },
    GUI = { ShowConfirmation = function(_, opts) end },
    SafeReload = function() end,
}
_G.C_AddOns = {
    DoesAddOnExist      = function() return true end,
    IsAddOnLoaded       = function() return false end,
    GetAddOnEnableState = function() return 2 end,
    EnableAddOn         = function(n) enableAddonCalls[#enableAddonCalls+1] = n end,
    DisableAddOn        = function(n) disableAddonCalls[#disableAddonCalls+1] = n end,
    SaveAddOns          = function() end,
    LoadAddOn           = function() return true end,
}
ns.QUI_Modules = { NotifyChanged = function() end }

-- Real manifest (has 5 coreModule entries: minimap/infobar/alts/datatexts/skinning).
assert(loadfile("core/addon_manifest.lua"))("QUI", ns)

-- Mocked loader (only used for folder rows; coreModule rows bypass it).
ns.AddonLoader = {
    IsModuleAddonEnabled  = function() return true end,
    SetModuleAddonEnabled = function(folder, on)
        if on then
            _G.C_AddOns.EnableAddOn(folder)
            _G.C_AddOns.LoadAddOn(folder)
            return "loaded"
        else
            _G.C_AddOns.DisableAddOn(folder)
            return "reload"
        end
    end,
}

assert(loadfile("core/settings/content/module_addons_content.lua"))("QUI", ns)

-- ── 1. NO QUI_UI bundle row ────────────────────────────────────────────────────
-- QUI_UI no longer ships as a sub-addon; its modules live in the main QUI core.

check("NO moduleAddon_QUI_UI row registered",
    features["moduleAddon_QUI_UI"] == nil,
    "moduleAddon_QUI_UI must NOT be registered — bundle row is gone")

-- ── 2. coreModule flag rows (minimap/infobar/alts/datatexts/skinning) ─────────

for _, mod in ipairs({ "minimap", "infobar", "alts", "datatexts", "skinning" }) do
    local row = features["moduleFlag_" .. mod]
    check("moduleFlag_" .. mod .. " registered", row ~= nil,
        "expected moduleFlag_" .. mod .. " to be registered")
    check("moduleFlag_" .. mod .. " has moduleEntry",
        row and row.moduleEntry ~= nil)
end

-- ── 3. NO row for qol ─────────────────────────────────────────────────────────
-- qol is always-on; its per-feature general.* flags toggle each feature.

check("no moduleFlag_qol (qol always-on, no master gate)",
    features["moduleFlag_qol"] == nil,
    "moduleFlag_qol must NOT be registered")

-- ── 4. coreModule row flag read / write ───────────────────────────────────────

local minimapRow = features["moduleFlag_minimap"]
check("minimap coreModule row: isEnabled reads profile.minimap.enabled",
    minimapRow and minimapRow.moduleEntry and minimapRow.moduleEntry.isEnabled() == true,
    "isEnabled should return true when profile.minimap.enabled == true")

-- Disable: must write the flag false; must NOT call DisableAddOn.
local disableCallsBefore = #disableAddonCalls
local enableCallsBefore  = #enableAddonCalls
if minimapRow and minimapRow.moduleEntry then
    minimapRow.moduleEntry.setEnabled(false)
end
check("minimap coreModule row: setEnabled(false) writes profile.minimap.enabled=false",
    profile.minimap.enabled == false,
    "profile.minimap.enabled must be false after setEnabled(false)")
check("minimap coreModule row: setEnabled(false) does NOT call DisableAddOn",
    #disableAddonCalls == disableCallsBefore,
    ("DisableAddOn was called %d extra time(s) — coreModule rows must not touch addon enable state"):format(
        #disableAddonCalls - disableCallsBefore))
check("minimap coreModule row: setEnabled(false) does NOT call EnableAddOn",
    #enableAddonCalls == enableCallsBefore,
    "EnableAddOn must not be called for coreModule rows")

-- Re-enable: must write the flag true.
if minimapRow and minimapRow.moduleEntry then
    minimapRow.moduleEntry.setEnabled(true)
end
check("minimap coreModule row: setEnabled(true) writes profile.minimap.enabled=true",
    profile.minimap.enabled == true,
    "profile.minimap.enabled must be true after setEnabled(true)")
check("minimap coreModule row: isEnabled() true after re-enable",
    minimapRow and minimapRow.moduleEntry and minimapRow.moduleEntry.isEnabled() == true)
check("minimap coreModule row: setEnabled(true) does NOT call EnableAddOn",
    #enableAddonCalls == enableCallsBefore,
    "EnableAddOn must not be called for coreModule rows")

-- ── 5. datatexts row: flag path is quiDatatexts (NOT datatexts) ───────────────

local datatextsRow = features["moduleFlag_datatexts"]
check("moduleFlag_datatexts: isEnabled reads profile.quiDatatexts.enabled",
    datatextsRow and datatextsRow.moduleEntry and datatextsRow.moduleEntry.isEnabled() == true,
    "isEnabled should return true when profile.quiDatatexts.enabled == true")

if datatextsRow and datatextsRow.moduleEntry then
    datatextsRow.moduleEntry.setEnabled(false)
end
check("moduleFlag_datatexts: setEnabled(false) writes profile.quiDatatexts.enabled=false",
    profile.quiDatatexts.enabled == false,
    "profile.quiDatatexts.enabled must be false (DB key is quiDatatexts, not datatexts)")
check("moduleFlag_datatexts: plain profile.datatexts key untouched",
    profile.datatexts == nil,
    "profile.datatexts must remain nil — the DB key is quiDatatexts")
if datatextsRow and datatextsRow.moduleEntry then
    datatextsRow.moduleEntry.setEnabled(true)
end

-- ── 6. skinning row writes profile.skinning.enabled ───────────────────────────

local skinningRow = features["moduleFlag_skinning"]
check("moduleFlag_skinning: isEnabled reads profile.skinning.enabled",
    skinningRow and skinningRow.moduleEntry and skinningRow.moduleEntry.isEnabled() == true,
    "isEnabled should return true when profile.skinning.enabled == true")

if skinningRow and skinningRow.moduleEntry then
    skinningRow.moduleEntry.setEnabled(false)
end
check("moduleFlag_skinning: setEnabled(false) writes profile.skinning.enabled=false",
    profile.skinning.enabled == false,
    "profile.skinning.enabled must be false after setEnabled(false)")
if skinningRow and skinningRow.moduleEntry then
    skinningRow.moduleEntry.setEnabled(true)
end

-- ── 7. No legacy folder rows for the old sub-addons-that-were-in-QUI_UI ───────

check("no moduleAddon_QUI_Skinning row",   features["moduleAddon_QUI_Skinning"]  == nil)
check("no moduleAddon_QUI_Datatexts row",  features["moduleAddon_QUI_Datatexts"] == nil)
check("no moduleAddon_QUI_QoL row",        features["moduleAddon_QUI_QoL"]       == nil)
check("no moduleAddon_QUI_Minimap row (coreModule now)",  features["moduleAddon_QUI_Minimap"]  == nil)
check("no moduleAddon_QUI_InfoBar row (coreModule now)",  features["moduleAddon_QUI_InfoBar"]  == nil)
check("no moduleAddon_QUI_Alts row (coreModule now)",     features["moduleAddon_QUI_Alts"]     == nil)

-- ── 8. Sidebar module toggles use the same registered entries ─────────────────

local function readAll(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local source = file:read("*a")
    file:close()
    return source
end

local expectedTiles = {
    action_bars = "moduleAddon_QUI_ActionBars",
    unit_frames = "moduleAddon_QUI_UnitFrames",
    group_frames = "moduleAddon_QUI_GroupFrames",
    nameplates = "moduleAddon_QUI_Nameplates",
    cooldown_manager = "moduleAddon_QUI_CDM",
    resource_bars = "moduleAddon_QUI_ResourceBars",
    chat_tooltips = "moduleAddon_QUI_Chat",
    infobar = "moduleFlag_infobar",
    bags = "moduleAddon_QUI_Bags",
    alts = "moduleFlag_alts",
}

for tile, featureId in pairs(expectedTiles) do
    local source = readAll("QUI_Options/tiles/" .. tile .. ".lua")
    check("sidebar " .. tile .. " maps to " .. featureId,
        source:find('moduleFeatureId = "' .. featureId .. '"', 1, true) ~= nil)
end

local framework = readAll("QUI_Options/framework.lua")
check("sidebar reuses Feature Toggles pill builder",
    framework:find("modulesPage.CreateModuleTogglePill", 1, true) ~= nil)

local mirroredSettings = {
    ["QUI_UnitFrames/unitframes/settings/unit_frames_schema.lua"] = "moduleAddon_QUI_UnitFrames",
    ["QUI_GroupFrames/groupframes/settings/group_frames_schema.lua"] = "moduleAddon_QUI_GroupFrames",
    ["QUI_Nameplates/nameplates/settings/nameplates_schema.lua"] = "moduleAddon_QUI_Nameplates",
    ["QUI_Chat/chat/settings/chat_frame1_provider.lua"] = "moduleAddon_QUI_Chat",
    ["modules/infobar/settings/infobar_content.lua"] = "moduleFlag_infobar",
    ["modules/alts/settings/alts_providers.lua"] = "moduleFlag_alts",
}

for path, featureId in pairs(mirroredSettings) do
    local source = readAll(path)
    check(path .. " routes its master toggle through shared state",
        source:find('QUI_Modules:SetEnabled("' .. featureId .. '"', 1, true) ~= nil)
end

-- ── 9. Shared state dispatches once and refreshes ordinary widgets ────────────

local changedValue
local setterOptions
local refreshes = 0
local notifications = 0
features.testModule = {
    moduleEntry = {
        isEnabled = function() return changedValue == true end,
        setEnabled = function(value, options)
            changedValue = value
            setterOptions = options
        end,
    },
}
_G.QUI.GUI.RefreshWidgetInstances = function()
    refreshes = refreshes + 1
end

assert(loadfile("core/modules.lua"))("QUI", ns)
ns.QUI_Modules:Subscribe("testModule", function()
    notifications = notifications + 1
end)

local setterOpts = { suppressReloadPrompt = true }
check("shared module API accepts registered module",
    ns.QUI_Modules:SetEnabled("testModule", true, setterOpts) == true)
check("shared module API calls moduleEntry.setEnabled", changedValue == true)
check("shared module API passes setter options", setterOptions == setterOpts)
check("shared module API emits one notification", notifications == 1)
check("module change refreshes ordinary settings widgets", refreshes == 1)

features.testModule.moduleEntry.setEnabled = function(value)
    changedValue = value
    ns.QUI_Modules:NotifyChanged("testModule")
end
ns.QUI_Modules:SetEnabled("testModule", false)
check("internally-notifying entries are not double-dispatched", notifications == 2)
check("internally-notifying entries still refresh widgets", refreshes == 2)

-- ── 10. Result ────────────────────────────────────────────────────────────────

if failures > 0 then
    io.stderr:write(("FAIL  module_addons_rows_test: %d assertion(s) failed\n"):format(failures))
    os.exit(1)
end
print("PASS: module_addons_rows_test")
