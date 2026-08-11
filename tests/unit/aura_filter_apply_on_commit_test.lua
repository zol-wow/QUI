-- tests/unit/aura_filter_apply_on_commit_test.lua
-- Wave 4 Task 4 (4b): no per-keystroke path may reach
-- core/aura_skin.lua Configure through a filter-affecting edit.
--
-- Path map (every write to a filterStrip element's filter-affecting fields —
-- auraType, filterMode, filterFlags, classifications — from
-- QUI_Options/aura_elements_editor.lua):
--   :614  auraType         <- GUI:CreateFormDropdown (discrete selection commit)
--   :642  filterMode       <- GUI:CreateFormDropdown (discrete selection commit)
--   :704  classifications  <- GUI:CreateFormCheckbox  (discrete click commit)
--   :719  filterFlags      <- GUI:CreateFormDropdown, tri-state scratch-cell
--                              (discrete selection commit; see the "scratch
--                              cell" comment at :714 — CreateFormDropdown
--                              writes dbTable[dbKey] on SELECTION, there is
--                              no keystroke concept for a dropdown)
-- None of these four is an EditBox, so there is no "typing" phase to reach
-- Configure through — every commit is a single discrete user action
-- (click/select), matching the required granularity by construction.
--
-- The ONLY EditBox reachable from a filterStrip element's detail is the
-- whitelist/blacklist manual spell-ID input (:457-494, AddSpellMapEditor) —
-- it writes candidateFilters (includeSpellIDs/excludeSpellIDs), NEVER
-- element.filterFlags/classifications/auraType, so it cannot affect
-- core/aura_skin.lua Configure's group KEY at all (only the mutator path
-- SetAuraGroupCandidateFilters — see core/aura_skin.lua Configure, the
-- `registered[key]` branch — which never calls AddAuraGroup). It commits on
-- OnEnterPressed only (:494); it has no OnTextChanged handler, so there is
-- no live-typing write path here either. The Browse popup's onToggle
-- (:505-513) is scoped the same way — `map`/element.whitelist/blacklist
-- only, never a filter-affecting field. It may therefore update the inline
-- selected-spell list immediately: this control never reaches a
-- group-key-affecting write.
--
-- This file has two parts:
--   1. Source-text pins locking the above path map in place (so a FUTURE
--      edit that adds a live-typing filter control gets caught here).
--   2. An EXECUTABLE spy test proving the underlying framework contract
--      those discrete widgets (and any future filter editbox) would rely
--      on: QUI_Options/framework.lua's GUI:CreateFormEditBox commits on
--      Enter/focus-loss, NOT per keystroke. Loaded via the SAME technique
--      tests/unit/test_form_slider_init.lua established (the search-cache
--      generator's WoW-API stub preamble, cut before its own page walk) —
--      this runs the REAL framework.lua code, not a re-implementation.
--
-- Run: lua tests/unit/aura_filter_apply_on_commit_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Part 1: source-text pins (path map above).
----------------------------------------------------------------------------
local function read(p)
    local h = io.open(p, "rb")
    if not h then return nil end
    local s = h:read("*a")
    h:close()
    return s
end

local EDITOR_PATH = "QUI_Options/aura_elements_editor.lua"
local editor = read(EDITOR_PATH)
check("editor file readable: " .. EDITOR_PATH, editor ~= nil)

if editor then
    -- Every filter-affecting field is written through a discrete-commit
    -- widget (Dropdown/Checkbox), never through a raw EditBox.
    check("auraType written via CreateFormDropdown",
        editor:find('CreateFormDropdown(ctx.detailArea, nil, AURA_TYPE_OPTIONS, "auraType"', 1, true) ~= nil)
    check("filterMode written via CreateFormDropdown",
        editor:find('CreateFormDropdown(ctx.detailArea, nil, FILTER_MODE_OPTIONS, "filterMode"', 1, true) ~= nil)
    check("classifications written via CreateFormCheckbox",
        editor:find("CreateFormCheckbox(ctx.detailArea, nil, entry.key, element.classifications, onChange", 1, true) ~= nil)
    check("filterFlags written via CreateFormDropdown (tri-state scratch cell)",
        editor:find("CreateFormDropdown(ctx.detailArea, nil, TRI_STATE_OPTIONS, \"value\", scratch", 1, true) ~= nil)

    -- The ONE EditBox in this file (manual whitelist/blacklist spell-ID
    -- entry) commits on Enter only — no live OnTextChanged write path.
    check("manual spell-ID input commits via OnEnterPressed",
        editor:find('inputBox:SetScript("OnEnterPressed", CommitManual)', 1, true) ~= nil)
    check("manual spell-ID input has NO OnTextChanged handler (no per-keystroke write)",
        editor:find('inputBox:SetScript("OnTextChanged"', 1, true) == nil)

    -- Whole-file invariant: no editor control anywhere reaches
    -- element.filterFlags/classifications/auraType through an OnTextChanged
    -- handler (the per-keystroke path this task must rule out). There is
    -- exactly one OnTextChanged-adjacent construct in this file at all
    -- (there should be none), so a bare absence check is precise here.
    check("aura_elements_editor.lua has NO OnTextChanged handler anywhere",
        editor:find("OnTextChanged", 1, true) == nil)

    -- The Browse popup's onToggle (whitelist/blacklist) never touches a
    -- filter-affecting field — grep the onToggle closure body for the
    -- filter-affecting field names; none should appear between the
    -- "local toggleSpell = browseCfg.onToggle or function(spellID)" open and its
    -- closing "end," (a few lines below it).
    local onToggleStart = editor:find("local toggleSpell = browseCfg.onToggle or function(spellID)", 1, true)
    check("Browse popup onToggle located", onToggleStart ~= nil)
    if onToggleStart then
        local onToggleBody = editor:sub(onToggleStart, onToggleStart + 400)
        local closeAt = onToggleBody:find("\n%s*end,", 1)
        if closeAt then onToggleBody = onToggleBody:sub(1, closeAt) end
        check("Browse popup onToggle body never writes filterFlags",
            onToggleBody:find("filterFlags", 1, true) == nil)
        check("Browse popup onToggle body never writes classifications",
            onToggleBody:find("classifications", 1, true) == nil)
        check("Browse popup onToggle body never writes auraType",
            onToggleBody:find("auraType", 1, true) == nil)
    end
end

----------------------------------------------------------------------------
-- Part 2: executable spy test on the shared framework commit contract
-- (GUI:CreateFormEditBox — QUI_Options/framework.lua), the mechanism every
-- filter-affecting EditBox in this addon relies on (present ones and any
-- future one alike).
----------------------------------------------------------------------------
do
    local GEN_PATH = "tools/generate_search_cache.lua"
    local CUT_MARKER = 'local frame = create_stub_node("Frame", nil, false)'
    local fh = io.open(GEN_PATH, "rb")
    if not fh then
        check("generate_search_cache.lua preamble available", false, "file not found")
    else
        local src = fh:read("*a"); fh:close()
        local cut = src:find(CUT_MARKER, 1, true)
        check("preamble cut marker found", cut ~= nil)
        if cut then
            assert((loadstring or load)(src:sub(1, cut - 1), "@gen-preamble"))()

            local GUI = _G.QUI and _G.QUI.GUI
            check("framework GUI table initialized", GUI ~= nil)
            check("GUI exposes the real CreateFormEditBox", type(GUI and GUI.CreateFormEditBox) == "function")

            if GUI and type(GUI.CreateFormEditBox) == "function" then
                -- The generator's stub SetScript/GetScript are blanket
                -- no-ops (fine for "does it construct" checks; useless for
                -- "does the handler behave correctly"). Give EditBox nodes
                -- REAL script storage so this test can actually fire the
                -- handlers framework.lua wires. Mirrors
                -- tests/unit/test_form_slider_init.lua's Slider/
                -- GetThumbTexture patch (same file, same technique).
                local realCreateFrame = _G.CreateFrame
                _G.CreateFrame = function(frameType, name, parent, ...)
                    local node = realCreateFrame(frameType, name, parent, ...)
                    if frameType == "EditBox" then
                        local scripts = {}
                        node.SetScript = function(_, script, fn) scripts[script] = fn end
                        node.GetScript = function(_, script) return scripts[script] end
                        node.HasFocus = function() return false end
                    end
                    return node
                end

                local parent = _G.CreateFrame("Frame")

                -- Control case: liveUpdate = true DOES fire onChange per
                -- keystroke — proves the spy/harness actually distinguishes
                -- committed vs. live-typed, rather than trivially never
                -- firing for any reason.
                do
                    local store = {}
                    local calls = 0
                    local w = GUI:CreateFormEditBox(parent, nil, "k", store,
                        function() calls = calls + 1 end, { live = true })
                    local eb = w and w.editBox
                    if eb and eb:GetScript("OnTextChanged") then
                        eb:SetText("a"); eb:GetScript("OnTextChanged")(eb, true)
                        eb:SetText("ab"); eb:GetScript("OnTextChanged")(eb, true)
                    end
                    check("control: options.live=true DOES fire onChange per keystroke (harness sanity)",
                        calls == 2, tostring(calls))
                end

                -- The actual contract: DEFAULT options (live unset/false) —
                -- zero onChange calls while "typing", exactly one on commit.
                do
                    local store = {}
                    local calls, lastVal = 0, nil
                    local w = GUI:CreateFormEditBox(parent, nil, "filterText", store,
                        function(v) calls = calls + 1; lastVal = v end, {})
                    local eb = w and w.editBox
                    check("editbox constructed", eb ~= nil)
                    check("construction does not call onChange", calls == 0, tostring(calls))
                    -- Baseline AFTER construction, not an assumed nil: the
                    -- widget's own init pass (SetValue(GetValue(), true))
                    -- writes dbTable[dbKey] unconditionally even though it
                    -- skips onChange (same init-write shape Wave 1 Task 1
                    -- fixed for CreateFormSlider — CreateFormEditBox was out
                    -- of that task's scope and still does it; out of THIS
                    -- task's scope too, so this test pins what typing does
                    -- FROM that baseline rather than asserting the baseline
                    -- itself is nil).
                    local baseline = store.filterText

                    if eb then
                        local onTextChanged = eb:GetScript("OnTextChanged")
                        local onEnterPressed = eb:GetScript("OnEnterPressed")
                        local onFocusLost = eb:GetScript("OnEditFocusLost")
                        check("OnTextChanged handler present", onTextChanged ~= nil)
                        check("OnEnterPressed handler present", onEnterPressed ~= nil)
                        check("OnEditFocusLost handler present", onFocusLost ~= nil)

                        if onTextChanged then
                            eb:SetText("H"); onTextChanged(eb, true)
                            eb:SetText("HE"); onTextChanged(eb, true)
                            eb:SetText("HEL"); onTextChanged(eb, true)
                            eb:SetText("HELP"); onTextChanged(eb, true)
                        end
                        check("Configure-spy proxy (onChange) NOT called during simulated typing",
                            calls == 0, tostring(calls))
                        check("store UNCHANGED from its post-construction baseline during simulated typing",
                            store.filterText == baseline,
                            ("baseline=%s after-typing=%s"):format(tostring(baseline), tostring(store.filterText)))

                        if onEnterPressed then onEnterPressed(eb) end
                        check("onChange called EXACTLY once on commit (Enter)", calls == 1, tostring(calls))
                        check("store written on commit", store.filterText == "HELP", tostring(store.filterText))
                        check("committed value matches the typed text", lastVal == "HELP", tostring(lastVal))

                        -- FocusLost also commits (second field, so it does
                        -- not interact with the first assertion sequence).
                        local store2 = {}
                        local calls2 = 0
                        local w2 = GUI:CreateFormEditBox(parent, nil, "k2", store2,
                            function() calls2 = calls2 + 1 end, {})
                        local eb2 = w2 and w2.editBox
                        if eb2 then
                            local typed = eb2:GetScript("OnTextChanged")
                            local lost = eb2:GetScript("OnEditFocusLost")
                            if typed then eb2:SetText("x"); typed(eb2, true) end
                            check("second field: typing alone still zero calls", calls2 == 0, tostring(calls2))
                            if lost then lost(eb2) end
                            check("OnEditFocusLost commits exactly once", calls2 == 1, tostring(calls2))
                        end
                    end
                end

                _G.CreateFrame = realCreateFrame
            end
        end
    end
end

if fails > 0 then error(fails .. " failure(s) in aura_filter_apply_on_commit_test") end
print("OK: aura_filter_apply_on_commit_test (all checks passed)")
