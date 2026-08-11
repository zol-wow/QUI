-- tests/unit/nameplates_settings_reflow_test.lua
-- Run: lua5.1 tests/unit/nameplates_settings_reflow_test.lua
--
-- Regression test for the Auras -> Nameplates reflow loop (2026-07-28
-- live bug): navigating to Auras -> Nameplates showed duplicated/stale aura
-- options and made every Auras tab slow.
--
-- Root cause: the per-channel filter-strip mount inside RenderSpellListsSection
-- (nameplates_schema.lua) wired its onLayoutChanged callback straight to
-- ScheduleSectionReflow(ctx), which schedules ctx:RerenderFeature() via
-- C_Timer.After(0, ...). RenderAuras fires onLayoutChanged once, synchronously,
-- during its OWN initial mount (aura_elements_editor.lua ends RenderAuras with
-- rebuild(), and RelayoutList's last act is `ctx.onLayoutChanged(hostHeight)`
-- -- see aura_elements_editor.lua:1615-1617 and :2123). The documented
-- contract for that first fire is spelled out at
-- action_bars_buffdebuff_content.lua:130-134 ("the editor's own initial
-- rebuild fires onLayoutChanged"). Scheduling a full feature re-render off
-- that fire re-mounts this same section, which fires onLayoutChanged again:
-- an unbounded one-frame-interval loop. RerenderFeature re-renders every
-- section of the feature (core/settings/schema.lua), which is why the whole
-- Auras tile went slow, not just Nameplates.
--
-- Follow-up (2026-07-28, same day): RenderSpellListsSection ALSO duplicated
-- every channel header ("Debuffs"/"Buffs"/"Crowd Control") that
-- RenderAuraRowsSection already rendered with that channel's row settings --
-- users scrolled past each header twice. The fix moved each channel's filter
-- strip (and its reflow-mount bookkeeping) into RenderAuraRowsSection. This
-- test was retargeted from spellLists to auraRows to follow the mount (the
-- assertion -- mounting never schedules a feature re-render -- is unchanged,
-- just aimed at its new home).
--
-- Later port (shared element model, 2026-07-28): the whole per-channel
-- debuffs/buffs/cc model this fix was reasoning about was deleted.
-- RenderAuraRowsSection now mounts the shared AurasEditor.RenderAuras ONCE
-- against a flat auras.elements["*"] bucket -- no channel loop, no
-- per-channel headers or row-settings cards at all. The reflow contract this
-- file guards is unchanged (onLayoutChanged must re-anchor/resize only,
-- never trigger ctx:RerenderFeature); the channel-header and channel-count
-- assertions were retired along with the channels themselves and replaced
-- with a check that no channel row-card control (Icon Size/Max Icons/
-- Growth/Attach To/Text Size) renders any more.
--
-- This is a new file: none of the other nameplates_*_test.lua files execute
-- nameplates_schema.lua -- they test pure model/color/filter/driver logic
-- that needs no WoW frame mock. This is the first test to actually mount a
-- settings section headlessly. It builds a small CreateFrame/GUI/options-API
-- mock and stubs ns.QUI_AuraElementsEditor.RenderAuras to reproduce ONLY
-- the documented contract above (fire onLayoutChanged once, synchronously,
-- during its own mount) rather than executing the real (much larger) editor
-- -- tests/unit/bb_single_strip_test.lua and aura_elements_editor_test.lua
-- already document that file as un-executable headless, relying on
-- source-text pins instead. A ctx stub's RerenderFeature just counts calls
-- instead of re-rendering, which is enough to catch the wiring defect.
--
-- Rendering auraRows also builds the master card's row settings (checkboxes
-- wrapped in a settings-card group), so the GUI/options-API mocks below keep
-- CreateFormCheckbox/CreateFormSlider/CreateFormDropdown and
-- CreateSettingsCardGroup/BuildSettingRow alongside the original
-- CreateButton/CreateAccentDotLabel -- no-op stubs that hand back a mock
-- frame; BuildSettingRow also records each row's label text.

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()

local fails = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else fails = fails + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

----------------------------------------------------------------------------
-- Minimal WoW frame mock. Richer than _addon_env.lua's CreateFrame (which
-- only stubs event registration, enough to load core/ model files) because
-- this test actually renders a settings section instead of just loading
-- pure-logic modules.
----------------------------------------------------------------------------
local function NewMockFontString()
    local fs = {}
    function fs:SetPoint() end
    function fs:ClearAllPoints() end
    function fs:SetJustifyH() end
    function fs:SetText(t) self._text = t end
    function fs:GetText() return self._text end
    function fs:SetTextColor() end
    return fs
end

local function NewMockFrame()
    local f = { _height = 0, _width = 0 }
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetHeight(h) self._height = h end
    function f:GetHeight() return self._height end
    function f:SetWidth(w) self._width = w end
    function f:GetWidth() return self._width end
    function f:SetSize(w, h) self._width = w; self._height = h end
    function f:SetAlpha(a) self._alpha = a end
    function f:GetAlpha() return self._alpha end
    function f:CreateFontString() return NewMockFontString() end
    function f:SetAutoFocus() end
    function f:SetNumeric() end
    function f:SetMaxLetters() end
    function f:SetFontObject() end
    function f:SetTextInsets() end
    function f:SetScript(event, fn) self._scripts = self._scripts or {}; self._scripts[event] = fn end
    function f:GetText() return self._text or "" end
    function f:SetText(t) self._text = t end
    function f:ClearFocus() end
    function f:Show() end
    function f:Hide() end
    function f:GetChildren() return {} end
    function f:GetRegions() return {} end
    function f:SetParent() end
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:IsEventRegistered() return false end
    return f
end

-- Override _addon_env.lua's minimal CreateFrame with the richer mock above.
CreateFrame = function(_, _, _) return NewMockFrame() end

-- Fake C_Timer.After: capture scheduled callbacks instead of firing them, so
-- the test controls exactly when deferred work runs ("drained").
local timerQueue = {}
C_Timer = {
    After = function(_, fn) timerQueue[#timerQueue + 1] = fn end,
}

local function DrainTimers()
    local ran = 0
    while #timerQueue > 0 and ran < 100 do
        local fn = table.remove(timerQueue, 1)
        fn()
        ran = ran + 1
    end
    return ran
end

----------------------------------------------------------------------------
-- Module dependency stubs. A grep of `ns\.[A-Za-z_]+` across
-- nameplates_schema.lua turns up exactly: QUI_AuraElementsEditor,
-- QUI_Nameplates, QUI_NameplatesSettingsSchema (self-export),
-- QUI_Options, QUI_RefreshNameplate(s|Preview) (both optional-guarded,
-- left nil), Helpers, L (real, from LoadCore), Settings, UIKit (optional,
-- left nil).
----------------------------------------------------------------------------
local function StubWidget(...) return NewMockFrame() end

_G.QUI = _G.QUI or {}
_G.QUI.GUI = {
    CreateButton = StubWidget,
    CreateFormCheckbox = StubWidget,
    CreateFormSlider = StubWidget,
    CreateFormDropdown = StubWidget,
}

-- Captures the text of every header the render pass creates (the section's
-- own top header, e.g. "Auras" -- there is no per-channel header any more).
-- Reset with wipe() between render passes below.
local headerTexts = {}
local renderedLabels = {}

ns.QUI_Options = {
    CreateAccentDotLabel = function(_, text, _)
        headerTexts[#headerTexts + 1] = text
        return NewMockFrame()
    end,
    -- the master card wraps its row settings in a card group; the real
    -- implementation (QUI_Options/shared.lua) builds a bordered frame with
    -- row-management helpers -- none of that matters here, just that
    -- card.frame/AddRow/Finalize exist so builder.Card()/CloseCard() work.
    CreateSettingsCardGroup = function(_parent, _yOffset)
        local card = { frame = NewMockFrame() }
        function card.AddRow(...) end
        function card.Finalize() end
        return card
    end,
    BuildSettingRow = function(_parent, labelText, _widget, _desc)
        if type(labelText) == "string" then
            renderedLabels[labelText] = (renderedLabels[labelText] or 0) + 1
        end
        return NewMockFrame()
    end,
}

local testProfile = { nameplates = { types = { enemyNPC = {} } } }
ns.Helpers = {
    GetProfile = function() return testProfile end,
}

ns.QUI_Nameplates = {
    DefaultNameplateBucket = function() return {} end,
}

-- Reproduces ONLY the documented contract (see header comment) -- not the
-- real editor's widget tree.
local renderAurasCalls = 0
ns.QUI_AuraElementsEditor = {
    RenderAuras = function(_editorHost, _store, _bucketKey, _onChange, opts)
        renderAurasCalls = renderAurasCalls + 1
        local height = 40
        if opts and type(opts.onLayoutChanged) == "function" then
            opts.onLayoutChanged(height)
        end
        return height
    end,
}

-- Capture each section definition as the real file builds its feature
-- tables. Schema.Section is called once per section (in
-- CreateMultiSectionTabFeature) with definition.render set to the actual
-- local RenderXSection function -- capturing it here needs no rendering
-- pipeline (LayoutSections/RerenderFeature/RenderFeature) at all, so this
-- stub stays tiny and cannot itself hide the bug.
local capturedSections = {}
ns.Settings = {
    Renderer = { RenderFeature = function() end },
    Schema = {
        Feature = function(definition) return definition end,
        Section = function(definition)
            if type(definition) == "table" and definition.id then
                capturedSections[definition.id] = definition
            end
            return definition
        end,
    },
}

env.LoadAddonFile(
    "QUI_Nameplates/nameplates/settings/nameplates_schema.lua", "QUI_Nameplates", ns)

local auraRowsSection = capturedSections.auraRows
check("auraRows section captured",
    type(auraRowsSection) == "table" and type(auraRowsSection.render) == "function",
    "capturedSections.auraRows missing or has no render function")

-- auraRows is the ONLY aura section. The three that used to sit beside it
-- were each a second home for something the per-channel filter strip already
-- owns (spellLists: the strips themselves; auraDuration: duration text --
-- whose global copy the runtime honored while the strip's own copy was
-- inert; auraBehavior: mine-only). Re-adding any of them re-creates the
-- duplicate-configuration report this fixed.
for _, deadId in ipairs({ "spellLists", "auraDuration", "auraBehavior" }) do
    check(("no %s section is registered any more"):format(deadId),
        capturedSections[deadId] == nil,
        ("capturedSections.%s exists -- a superseded aura section came back"):format(deadId))
end

if not (auraRowsSection and type(auraRowsSection.render) == "function") then
    print(("%d failures"):format(fails))
    os.exit(1)
end

----------------------------------------------------------------------------
-- The regression test: mounting auraRows (where the shared element editor
-- now lives) must never schedule a feature re-render, synchronously or via
-- a deferred C_Timer callback. This is the same assertion the test always
-- made -- only the section under test moved, following the mount.
----------------------------------------------------------------------------
local rerenderFeatureCalls = 0
local ctx = {
    RerenderFeature = function() rerenderFeatureCalls = rerenderFeatureCalls + 1 end,
}
local sectionHost = NewMockFrame()

wipe(headerTexts)
wipe(renderedLabels)
local height = auraRowsSection.render(sectionHost, ctx)

check("auraRows render mounts the shared element editor exactly once",
    renderAurasCalls == 1,
    ("expected exactly 1 RenderAuras mount, got %d"):format(renderAurasCalls))
check("auraRows render returned a usable height",
    type(height) == "number",
    "render did not return a number")

check("master card still renders its own row (positive control on renderedLabels)",
    renderedLabels[ns.L["Show Auras"]] == 1,
    "expected exactly one 'Show Auras' row, got "
        .. tostring(renderedLabels[ns.L["Show Auras"]]))

for _, label in ipairs({ "Icon Size", "Max Icons", "Growth", "Attach To", "Text Size" }) do
    check(("no channel row-card control renders any more (%s)"):format(label),
        not renderedLabels[label],
        ("channel row-card control still rendered: %s"):format(label))
end

check("RerenderFeature not called synchronously during the mount",
    rerenderFeatureCalls == 0,
    ("rerenderFeatureCalls=%d immediately after the synchronous mount"):format(rerenderFeatureCalls))

local drained = DrainTimers()
check("mounting auraRows schedules no feature re-render, even deferred",
    rerenderFeatureCalls == 0,
    ("rerenderFeatureCalls=%d after draining %d deferred C_Timer callback(s) -- "
        .. "onLayoutChanged firing during the synchronous mount scheduled "
        .. "ctx:RerenderFeature(), which re-renders every section and would "
        .. "re-mount this one, which fires onLayoutChanged again: the "
        .. "reported reflow loop"):format(rerenderFeatureCalls, drained))

----------------------------------------------------------------------------
-- The duplication guard, now entirely within auraRows: the Important Auras
-- list renders exactly once (it is a display concept -- icon scale + pandemic
-- glow -- not a filter, so it has no element equivalent and stays global),
-- and the two headers whose sections were deleted must not reappear anywhere
-- in the tab. Compared against English literals on purpose: those keys are
-- being retired from the locale, so ns.L lookups would stop being meaningful.
----------------------------------------------------------------------------
do
    local sawImportant = false
    for _, text in ipairs(headerTexts) do
        if text == "Important Auras" then sawImportant = true end
    end
    check("auraRows no longer renders an Important Auras header",
        not sawImportant,
        ("Important Auras header must be gone, got: %s"):format(table.concat(headerTexts, " | ")))

    local sawRetired = nil
    for _, text in ipairs(headerTexts) do
        if text == "Duration Text" or text == "Aura Filtering" then
            sawRetired = text
        end
    end
    check("auraRows emits neither retired global header",
        sawRetired == nil,
        ("auraRows rendered the retired %q header -- per-channel config is "
            .. "duplicated globally again: %s")
            :format(tostring(sawRetired), table.concat(headerTexts, " | ")))
end

if fails > 0 then
    print(("%d failures"):format(fails))
    os.exit(1)
end
print("nameplates_settings_reflow_test: all checks passed")
