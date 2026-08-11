-- tests/unit/setup_wizard_pages_test.lua
-- Run: lua tests/unit/setup_wizard_pages_test.lua
--
-- Behavioral test for QUI_Options/wizard.lua: loads the real file with a
-- stub GUI/QUI environment and drives the paged flow:
--   * Show renders page 1; Next/Back navigate; pages rebuild on entry
--   * scale page writes profile.general.uiScale and calls ApplyUIScale
--   * profile page routes Starter/pasted imports through
--     ImportProfileFromString and re-renders after the deferred timer
--   * feature toggles pass NO registryInfo (no search-index leakage)
--   * the Edit Mode apply adds an Account layout named "QUI" with the
--     preset-offset SetActiveLayout index, updates (not duplicates) on
--     re-apply, and fails soft on an unrecognized string
--   * Finish stamps db.global.setupWizard.completedAt

local function noop() end

local timers = {}
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
end

_G.InCombatLockdown = function() return false end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.time = function() return 1234567 end

local function NewFrame()
    local f = { shown = false, points = {} }
    f.SetSize = noop; f.SetPoint = noop; f.SetAllPoints = noop
    f.SetFrameStrata = noop; f.SetFrameLevel = noop; f.SetToplevel = noop
    f.EnableMouse = noop; f.SetMovable = noop; f.RegisterForDrag = noop
    f.SetScript = noop; f.SetClampedToScreen = noop; f.SetParent = noop
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    return f
end
_G.CreateFrame = function() return NewFrame() end
_G.UIParent = NewFrame()
_G.UIParent.GetScale = function() return 1.0 end

-- ---------------------------------------------------------------------------
-- Stub GUI
-- ---------------------------------------------------------------------------
local buttons = {}          -- every CreateButton: { text, onClick, SetText... }
local toggleRegistryInfos = {}
local labels = {}

local function NewLabel(text)
    local l = { text = text or "" }
    l.SetPoint = noop; l.SetJustifyH = noop; l.SetWordWrap = noop
    l.SetText = function(self, t) self.text = t end
    l.GetStringHeight = function() return 14 end
    l.SetShown = noop
    labels[#labels + 1] = l
    return l
end

local GUIStub = {
    Colors = {
        border = { 0.2, 0.2, 0.2 }, bg = { 0.05, 0.07, 0.1 },
        text = { 0.9, 0.9, 0.9 }, accentLight = { 0.3, 0.9, 0.7 },
    },
    CreateLabel = function(_, _, text) return NewLabel(text) end,
    CreateButton = function(_, _, text, _, _, onClick)
        local b = NewFrame()
        b.text = text
        b.onClick = onClick
        b.SetText = function(self, t) self.text = t end
        b.SetShown = function(self, s) self.shownFlag = s end
        buttons[#buttons + 1] = b
        return b
    end,
    CreateFormToggle = function(_, _, label, key, tbl, onChange, registryInfo)
        local w = NewFrame()
        w.label = label
        w.toggle = function() tbl[key] = not tbl[key]; if onChange then onChange(tbl[key]) end end
        toggleRegistryInfos[#toggleRegistryInfos + 1] = { label = label, registryInfo = registryInfo, widget = w }
        return w
    end,
    CreateSectionHeader = function(_, _, text) return NewLabel(text) end,
    CreateScrollableTextBox = function()
        local box = NewFrame()
        box.editBox = { text = "", GetText = function(self) return self.text end }
        return box
    end,
}

-- ---------------------------------------------------------------------------
-- Stub QUI / core
-- ---------------------------------------------------------------------------
local applyUIScaleCalls = 0
local imports = {}
local coreStub = {
    db = { GetCurrentProfile = function() return "Default" end },
    GetSmartDefaultScale = function() return 0.64 end,
    ApplyUIScale = function() applyUIScaleCalls = applyUIScaleCalls + 1 end,
    ImportProfileFromString = function(_, str, name)
        imports[#imports + 1] = { str = str, name = name }
        return true, "Profile imported successfully."
    end,
}

_G.QUI = {
    db = {
        global = {},
        profile = { general = {} },
    },
    GUI = GUIStub,
    imports = {
        StarterProfile = { data = "QUI1:STARTERDATA" },
        QUIEditMode = { data = "2 50 0 0 0" },
    },
    _presetProfiles = {
        { key = "StarterProfile", profileName = "Starter Profile" },
    },
    SafeReload = function() _G.QUI._reloaded = true end,
}

local ns = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Helpers = {
        GetCore = function() return coreStub end,
        PlaceRow = function(_, _, sy) return (sy or 0) - 32 end,
    },
}

local printed = {}
local realPrint = print
print = function(msg) printed[#printed + 1] = tostring(msg) end
assert(loadfile("QUI_Options/wizard.lua"))("QUI_Options", ns)
print = realPrint

local Wizard = assert(ns.QUI_SetupWizard, "wizard should export ns.QUI_SetupWizard")

local function FindButton(text)
    for i = #buttons, 1, -1 do
        if buttons[i].text == text then return buttons[i] end
    end
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------
Wizard:Show()
assert(Wizard:IsShown(), "Show should display the wizard")
assert(#Wizard:_GetPages() == 7, "wizard should have seven pages")

local nextBtn = assert(FindButton("Start Setup") or FindButton("Next"), "footer next button exists")

-- Page 2: scale
nextBtn.onClick()
local applyScale = assert(FindButton("Apply Recommended Scale"), "scale page offers the recommended apply")
applyScale.onClick()
assert(_G.QUI.db.profile.general.uiScale == 0.64, "scale apply writes profile.general.uiScale")
assert(applyUIScaleCalls == 1, "scale apply routes through QUICore:ApplyUIScale")
RunTimers()  -- deferred re-render after apply

-- Page 3: profile
nextBtn.onClick()
local starterBtn = assert(FindButton("Apply Starter Profile"), "profile page offers the starter preset")
starterBtn.onClick()
assert(#imports == 1 and imports[1].name == "Starter Profile" and imports[1].str == "QUI1:STARTERDATA",
    "starter apply imports the bundled preset into its profile")
RunTimers()

local importBtn = assert(FindButton("Import"), "profile page offers string import")
importBtn.onClick()
assert(#imports == 1, "empty paste must not import")

-- Page 4: features — registryInfo must never be passed
nextBtn.onClick()
assert(#toggleRegistryInfos >= 2, "feature page builds toggles")
for _, info in ipairs(toggleRegistryInfos) do
    assert(info.registryInfo == nil,
        "wizard toggles must not register with the options search index: " .. tostring(info.label))
end

-- Page 5: nameplates
nextBtn.onClick()
local function FindToggle(label)
    for i = #toggleRegistryInfos, 1, -1 do
        if toggleRegistryInfos[i].label == label then return toggleRegistryInfos[i] end
    end
end
local npEnable = assert(FindToggle("Enable QUI Nameplates"), "nameplates page offers the enable toggle")
assert(npEnable.registryInfo == nil, "nameplates toggles must stay out of the search index")
npEnable.widget.toggle()
assert(_G.QUI.db.profile.nameplates and _G.QUI.db.profile.nameplates.enabled == true,
    "enable toggle writes profile.nameplates.enabled")

local npFriendly = assert(FindToggle("Friendly health bars (open world)"), "nameplates page offers the friendly style toggle")
npFriendly.widget.toggle()
assert(_G.QUI.db.profile.nameplates.types.friendly.renderMode == "bars",
    "friendly toggle on writes types.friendly.renderMode 'bars', not the retired friendly.mode key")
npFriendly.widget.toggle()
assert(_G.QUI.db.profile.nameplates.types.friendly.renderMode == "nameonly",
    "friendly toggle off writes types.friendly.renderMode 'nameonly'")
assert(rawget(_G.QUI.db.profile.nameplates.friendly, "mode") == nil,
    "the wizard must not resurrect the retired friendly.mode key")

-- Page 6: Edit Mode layout apply
nextBtn.onClick()

local saved, activated
_G.Enum = {
    EditModeLayoutType = { Account = 0, Character = 1, Preset = 2 },
    EditModePresetLayoutsMeta = { NumValues = 2 },
}
local layoutList = {}
_G.C_EditMode = {
    ConvertStringToLayoutInfo = function(str)
        if str == "2 50 0 0 0" then return { systems = { "SYSTEMS" } } end
        return nil
    end,
    GetLayouts = function() return { layouts = layoutList } end,
    SaveLayouts = function(info) saved = info end,
    SetActiveLayout = function(i) activated = i end,
}

local applyLayout = assert(FindButton("Apply QUI Edit Mode Layout"), "layout page offers the apply")
applyLayout.onClick()
assert(saved and #layoutList == 1, "layout apply adds one layout")
assert(layoutList[1].layoutName == "QUI" and layoutList[1].layoutType == 0,
    "added layout is an Account layout named QUI")
assert(activated == 3, "SetActiveLayout must offset past the presets (1 user layout + 2 presets)")

-- Re-apply updates in place instead of duplicating
layoutList[1].systems = "STALE"
applyLayout.onClick()
assert(#layoutList == 1, "re-apply must update the existing QUI layout, not duplicate it")
assert(layoutList[1].systems[1] == "SYSTEMS", "re-apply refreshes the layout systems")

-- Failure path: unrecognized string fails soft with a reason
_G.QUI.imports.QUIEditMode.data = "garbage"
local ok, err = Wizard._ApplyEditModeBaseLayout()
assert(ok == false and type(err) == "string", "unrecognized layout string fails soft")
_G.QUI.imports.QUIEditMode.data = "2 50 0 0 0"

-- Page 7: finish
nextBtn.onClick()
assert(nextBtn.text == "Finish", "last page relabels the footer button")
print = function(msg) printed[#printed + 1] = tostring(msg) end
nextBtn.onClick()
print = realPrint
assert(_G.QUI.db.global.setupWizard and _G.QUI.db.global.setupWizard.completedAt == 1234567,
    "Finish stamps the account-wide completedAt flag")
assert(not Wizard:IsShown(), "Finish closes the wizard")

-- Re-run resets the applied summary
Wizard:Show()
assert(#Wizard.applied == 0, "re-running the wizard resets the applied summary")

print("OK: setup_wizard_pages")
