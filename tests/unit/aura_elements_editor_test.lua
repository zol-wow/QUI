-- tests/unit/aura_elements_editor_test.lua
-- Run: lua tests/unit/aura_elements_editor_test.lua
--
-- Source-text pins for the shared aura element editor (Task 8): the GF auras
-- editor + spell list were moved into QUI_Options/ and generalized by a
-- capabilities table so unit frames / buff borders can share ONE editor. This
-- file is a headless WoW-frame builder, so we pin its contract by source text
-- rather than executing it.

local function read(p)
    local h = io.open(p, "rb")
    if not h then return nil end
    local s = h:read("*a")
    h:close()
    return s
end

local fails = 0
local function check(n, ok)
    if ok then print("  ok  " .. n) else fails = fails + 1; print("FAIL  " .. n) end
end

local EDITOR = "QUI_Options/aura_elements_editor.lua"
local SPELLLIST = "QUI_Options/aura_spell_list.lua"
local OLD_EDITOR = "QUI_GroupFrames/groupframes/settings/group_frames_auras_editor.lua"
local OLD_SPELLLIST = "QUI_GroupFrames/groupframes/settings/group_frames_spell_list.lua"

local editor = read(EDITOR)
local spelllist = read(SPELLLIST)

-- Files moved -------------------------------------------------------------
check("new editor exists at " .. EDITOR, editor ~= nil)
check("new spell list exists at " .. SPELLLIST, spelllist ~= nil)
check("old editor deleted", read(OLD_EDITOR) == nil)
check("old spell list deleted", read(OLD_SPELLLIST) == nil)

if not editor then
    print(("%d failures"):format(fails))
    os.exit(1)
end

-- Exports -----------------------------------------------------------------
check("editor exports ns.QUI_AuraElementsEditor", editor:find("ns.QUI_AuraElementsEditor", 1, true) ~= nil)
check("editor exports RenderAuras", editor:find("function AurasEditor.RenderAuras", 1, true) ~= nil)
check("spell list exports ns.QUI_AuraSpellList", spelllist:find("ns.QUI_AuraSpellList", 1, true) ~= nil)

-- Model import: core AuraElements, NOT the GF shim ------------------------
check("editor consumes ns.AuraElements", editor:find("ns.AuraElements", 1, true) ~= nil)
check("editor does NOT import the ns.QUI_GroupFramesAuraModel shim",
    editor:find("= ns.QUI_GroupFramesAuraModel", 1, true) == nil
    and editor:find("QUI_GroupFramesAuraModel.", 1, true) == nil)
check("editor consumes moved spell list ns.QUI_AuraSpellList",
    editor:find("ns.QUI_AuraSpellList", 1, true) ~= nil)

-- Capability gates present ------------------------------------------------
for _, gate in ipairs({
    "capabilities", "elementTypes", "trackedDisplayTypes",
    "maxStripElements", "cancelEligible", "allowSpecOverride",
    "defaultBucketFn", "singleStrip", "fixedAuraType",
}) do
    check("editor references capability field: " .. gate, editor:find(gate, 1, true) ~= nil)
end
check("editor reads caps.cancelEligible for the cancel toggle gate",
    editor:find("caps.cancelEligible", 1, true) ~= nil)
check("editor reads caps.allowSpecOverride to constrain the bucket",
    editor:find("caps.allowSpecOverride", 1, true) ~= nil)
check("editor counts against caps.maxStripElements",
    editor:find("caps.maxStripElements", 1, true) ~= nil)
check("editor gates the add menu on caps.elementTypes",
    editor:find("caps.elementTypes", 1, true) ~= nil or editor:find("elementTypes.filterStrip", 1, true) ~= nil)

-- EnsureSeeded threads defaultBucketFn (never the one-arg legacy form) -----
check("editor calls EnsureSeeded with the capability default bucket fn",
    editor:find("EnsureSeeded(auras, caps.defaultBucketFn)", 1, true) ~= nil)

-- New per-element controls write the right fields -------------------------
check("sort dropdown writes element.sortRule",
    editor:find("SORT_OPTIONS", 1, true) ~= nil and editor:find('"sortRule"', 1, true) ~= nil)
check("sort has a reverse toggle (sortReverse)", editor:find('"sortReverse"', 1, true) ~= nil)
check("right-click cancel toggle writes rightClickCancel",
    editor:find('"rightClickCancel"', 1, true) ~= nil)
check("filter mode gains the flags option", editor:find('"flags"', 1, true) ~= nil)
check("flags mode writes element.filterFlags", editor:find("element.filterFlags", 1, true) ~= nil)
check("filter mode uses the canonical classify value (not legacy classification)",
    editor:find('value = "classify"', 1, true) ~= nil)
check("shared text-region widgets factored (AddTextRegionWidgets)",
    editor:find("AddTextRegionWidgets", 1, true) ~= nil)
check("text region wires duration and stack sub-tables",
    editor:find('"duration"', 1, true) ~= nil and editor:find('"stack"', 1, true) ~= nil)

-- Wave 4 Task 2: classification honesty trio + dedupeDefensives removal ----
check("2a: classify-mode cap row relabels to 'Max Icons Per Category'",
    editor:find('ns.L["Max Icons Per Category"]', 1, true) ~= nil)
check("2a: relabel is gated on filterMode == classify (not a blanket rename)",
    editor:find('element.filterMode == "classify"', 1, true) ~= nil)
check("2b: exclusivity lives in core, not duplicated in the editor",
    editor:find("PRIORITY", 1, true) == nil)
check("2c: polarity hint gated on caps.unitPolarity",
    editor:find("caps.unitPolarity", 1, true) ~= nil)
check("2c: polarity hint covers both disabled-combo directions",
    editor:find('unitPolarity == "friendly" and element.auraType == "HARMFUL"', 1, true) ~= nil
    and editor:find('unitPolarity == "hostile" and element.auraType == "HELPFUL"', 1, true) ~= nil)
check("2d: 'Deduplicate Defensives' row removed", editor:find("Deduplicate Defensives", 1, true) == nil)
check("2d: dedupeDefensives no longer referenced anywhere in the editor",
    editor:find("dedupeDefensives", 1, true) == nil)

check("list row hides the icon when GetElementLabel returns none (strips)",
    editor:find("row.icon:Hide()", 1, true) ~= nil
    and editor:find("row.icon:SetTexture(icon or FALLBACK_ICON)", 1, true) == nil)
check("filterStrip is the mode GetElementLabel returns no icon for",
    editor:match('if element%.mode == "filterStrip" then.-return ns%.L%["Buffs"%], nil')
        ~= nil)
check("missingRaidBuff and tracked still return an icon",
    editor:find('return ns.L["Missing Raid Buff"], icon', 1, true) ~= nil
    and editor:find('return ns.L["Tracked (empty)"], FALLBACK_ICON', 1, true) ~= nil
    and editor:find("return name, GetSpellTexture(first)", 1, true) ~= nil)
check("iconless rows re-anchor the label onto the toggle, closing the gap",
    editor:find('row.name:SetPoint("LEFT", row.enable, "RIGHT", 6, 0)', 1, true) ~= nil)
check("both branches re-anchor every render (rows are pooled and reused)",
    editor:match("row%.name:ClearAllPoints%(%).-row%.icon:Show%(%).-"
        .. 'row%.name:SetPoint%("LEFT", row%.icon.-row%.icon:Hide%(%)') ~= nil)

-- Defensives fold-in: optional per-element border color -----------------
check("editor exposes borderColor", editor:find("\"borderColor\"", 1, true) ~= nil)
check("editor gates borderColor behind a custom-border toggle",
    editor:find("Custom Border Color", 1, true) ~= nil)

-- Tracked editor restoration ----------------------------------------------
check("tracked display type dropdown", editor:find('"displayType"', 1, true) ~= nil)
check("tracked builds display options from capabilities.trackedDisplayTypes",
    editor:find("BuildTrackedDisplayOptions", 1, true) ~= nil)
check("tracked Buff/Debuff dropdown writes element.auraType",
    editor:find('"auraType"', 1, true) ~= nil)
check("tracked bar sliders write element.bar.thickness / length",
    editor:find('"thickness"', 1, true) ~= nil and editor:find('"length"', 1, true) ~= nil
    and editor:find("element.bar", 1, true) ~= nil)
check("tracked spell list uses the moved CreateListFrame",
    editor:find("SpellList.CreateListFrame", 1, true) ~= nil)

-- Schema mount ------------------------------------------------------------
local schema = read("QUI_GroupFrames/groupframes/settings/group_frames_schema.lua")
check("schema resolves editor via ns.QUI_AuraElementsEditor",
    schema and schema:find("ns.QUI_AuraElementsEditor", 1, true) ~= nil)
check("schema no longer imports ns.QUI_GroupFramesAurasSettings",
    schema and schema:find("QUI_GroupFramesAurasSettings", 1, true) == nil)
check("schema passes capabilities.maxStripElements = 4",
    schema and schema:find("maxStripElements", 1, true) ~= nil and schema:find("= 4", 1, true) ~= nil)
check("schema passes defaultBucketFn = AuraDefaults.DefaultStripBucket",
    schema and schema:find("AuraDefaults.DefaultStripBucket", 1, true) ~= nil)
check("2c: GF passes unitPolarity = friendly (party/raid are always assistable)",
    schema and schema:find('unitPolarity        = "friendly"', 1, true) ~= nil)
local coreSchema = read("core/settings/schema.lua")
check("settings schema exposes in-place section resize",
    coreSchema and coreSchema:find("function Schema:ResizeSection", 1, true) ~= nil)
check("GF aura editor resizes its schema section without repainting it",
    schema and schema:find('ctx:ResizeSection("auras"', 1, true) ~= nil)
-- Suggestion grid removed: tracked elements are created empty via an "Add
-- Tracked Aura" button; spell picking lives ONLY in the per-element detail
-- (preset toggle list + manual spell ID).
check("schema no longer passes a suggestions capability",
    schema and schema:find("AuraDefaults.GetSuggestionSpells", 1, true) == nil)
check("editor no longer renders a suggestion grid",
    editor:find("AcquireSuggestCell", 1, true) == nil)
check("editor offers the Add Tracked Aura button",
    editor:find('ns.L["Add Tracked Aura"]', 1, true) ~= nil)
check("editor keeps the per-element spell picker (AddTrackedSpellListEditor)",
    editor:find("AddTrackedSpellListEditor", 1, true) ~= nil)

-- Browse popup (spell picker modal): preset groups moved out of the inline
-- toggle list into a shared floating popup (mirrors click-cast Browse). The
-- editor re-binds opts every detail render so popup closures never go stale,
-- and scope guards close the popup when its spell list stops rendering.
check("spell list exports the Browse popup toggle",
    spelllist:find("function SpellList.ToggleBrowsePopup", 1, true) ~= nil)
check("spell list exports the per-render opts re-bind",
    spelllist:find("function SpellList.RefreshBrowsePopup", 1, true) ~= nil)
check("spell list exports the browse scope guards",
    spelllist:find("function SpellList.BeginBrowseScope", 1, true) ~= nil
    and spelllist:find("function SpellList.EndBrowseScope", 1, true) ~= nil)
check("editor wires the Browse button through the shared popup",
    editor:find("SpellList.ToggleBrowsePopup", 1, true) ~= nil)
check("editor re-binds popup opts on every detail render",
    editor:find("SpellList.RefreshBrowsePopup", 1, true) ~= nil)
check("editor wraps list rebuilds in a browse scope",
    editor:find("SpellList.BeginBrowseScope", 1, true) ~= nil
    and editor:find("SpellList.EndBrowseScope", 1, true) ~= nil)
check("editor's inline list renders current spells only (no preset groups)",
    editor:find("SpellList.CreateListFrame(ctx.detailArea, map, nil,", 1, true) ~= nil)

-- Aura-editor interaction contract: subsection disclosure is quiet by default,
-- toggles reflow the already-built detail rows instead of allocating a fresh
-- widget tree, and Browse batches its one editor rebuild until the popup closes.
check("filter-strip subsections default collapsed",
    editor:find("s = { basics = false, filters = false, advanced = false }", 1, true) ~= nil)
check("subsection headers use the normal QUI text palette",
    editor:find("local textColor = ctx.C.text or { 1, 1, 1, 1 }", 1, true) ~= nil
    and editor:find("fs:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)", 1, true) ~= nil)
check("subsection toggles locally reflow retained detail rows",
    editor:find("ctx.BeginDetailSection(header, FORM_ROW, sectionKey)", 1, true) ~= nil
    and editor:find("RelayoutDetail()", 1, true) ~= nil
    and editor:find("ctx.RelayoutList()", 1, true) ~= nil)
check("What to Show Custom latches manual mode and opens Advanced",
    editor:find("state.manualCustom = true", 1, true) ~= nil
    and editor:find("state.manualCustom = false", 1, true) ~= nil
    and editor:find('ctx.SetDetailSectionExpanded("advanced", true)', 1, true) ~= nil
    and editor:find("state.manualCustom and \"custom\" or EffectiveWhatToShow(element)", 1, true) ~= nil)
check("Browse refreshes the inline spell list while it stays open",
    spelllist:find("function frame:Refresh()", 1, true) ~= nil
    and editor:find("listFrame:Refresh()", 1, true) ~= nil
    and editor:find("ctx.UpdateDetailWidgetHeight(listFrame, newHeight)", 1, true) ~= nil)
check("tracked Browse keeps its inline map view synchronized",
    editor:find("mapView[spellID] = nil", 1, true) ~= nil
    and editor:find("mapView[spellID] = true", 1, true) ~= nil)

-- TOC surgery -------------------------------------------------------------
local optsToc = read("QUI_Options/QUI_Options.toc")
local gfToc = read("QUI_GroupFrames/QUI_GroupFrames.toc")
check("QUI_Options.toc loads aura_spell_list.lua",
    optsToc and optsToc:find("aura_spell_list.lua", 1, true) ~= nil)
check("QUI_Options.toc loads aura_elements_editor.lua",
    optsToc and optsToc:find("aura_elements_editor.lua", 1, true) ~= nil)
check("QUI_Options.toc no longer loads the old GF editor path",
    optsToc and optsToc:find("group_frames_auras_editor.lua", 1, true) == nil)
check("QUI_Options.toc no longer loads the old GF spell-list path",
    optsToc and optsToc:find("group_frames_spell_list.lua", 1, true) == nil)
check("QUI_GroupFrames.toc does not reference the moved editor",
    gfToc and gfToc:find("group_frames_auras_editor.lua", 1, true) == nil)
check("QUI_GroupFrames.toc does not reference the moved spell list",
    gfToc and gfToc:find("group_frames_spell_list.lua", 1, true) == nil)

-- Task 9: UF + BB mounts -----------------------------------------------------
-- The unit-frames Icons tab and the action-bars Buff/Debuff tab replace their
-- old inline aura builders (which read flat auraDB/buffBorders keys migration
-- v50 pruned once elements shipped) with mounts of this same shared editor.
local ufSchema = read("QUI_UnitFrames/unitframes/settings/unit_frames_schema.lua")
local ufAuras = read("QUI_UnitFrames/unitframes/unitframe_auras.lua")
local bbContent = read("QUI_ActionBars/actionbars/settings/action_bars_buffdebuff_content.lua")
local bbAuras = read("QUI_ActionBars/actionbars/buffborders.lua")

check("UF schema mounts RenderAuras",
    ufSchema and ufSchema:find("AurasEditor.RenderAuras(editorHost, auraDB", 1, true) ~= nil)
check("UF mount offers tracked elements (tracked = true)",
    ufSchema and ufSchema:find("tracked = true", 1, true) ~= nil)
check("UF mount gates cancelEligible on unitKey == player",
    ufSchema and ufSchema:find('cancelEligible      = (unitKey == "player")', 1, true) ~= nil)
check("UF mount forces allowSpecOverride = false (no per-spec buckets on UF)",
    ufSchema and ufSchema:find("allowSpecOverride   = false", 1, true) ~= nil)
check("UF mount threads defaultBucketFn = ns.QUI_UnitFrameAuras.DefaultUnitAuraBucket",
    ufSchema and ufSchema:find("UnitFrameAuras.DefaultUnitAuraBucket", 1, true) ~= nil)
check("unitframe_auras.lua publishes ns.QUI_UnitFrameAuras.DefaultUnitAuraBucket",
    ufAuras and ufAuras:find("ns.QUI_UnitFrameAuras", 1, true) ~= nil
    and ufAuras:find("UnitFrameAuras.DefaultUnitAuraBucket = DefaultUnitAuraBucket", 1, true) ~= nil)
check("2c: UF mount threads unitPolarity from a per-unit resolver",
    ufSchema and ufSchema:find("unitPolarity        = UnitPolarity(unitKey)", 1, true) ~= nil)
check("2c: UF polarity resolver pins player/pet friendly, boss hostile, target/focus ambiguous (nil)",
    ufSchema and ufSchema:find('unitKey == "player" or unitKey == "pet"', 1, true) ~= nil
    and ufSchema:find('return "friendly"', 1, true) ~= nil
    and ufSchema:find('elseif unitKey == "boss" then', 1, true) ~= nil
    and ufSchema:find('return "hostile"', 1, true) ~= nil)
check("UF aura editor resizes its schema section without repainting it",
    ufSchema and ufSchema:find('ctx:ResizeSection("auraElements"', 1, true) ~= nil)

check("BB content mounts RenderAuras for buffAuras",
    bbContent and bbContent:find('AurasEditor.RenderAuras(editorHost, auras, "*"', 1, true) ~= nil
    and bbContent:find('"buffAuras"', 1, true) ~= nil)
check("BB content mounts RenderAuras for debuffAuras",
    bbContent and bbContent:find('"debuffAuras"', 1, true) ~= nil)
check("BB mounts are filterStrip-only (no tracked icons/squares/bars)",
    bbContent and bbContent:find("elementTypes      = { filterStrip = true }", 1, true) ~= nil
    and bbContent:find("tracked = true", 1, true) == nil)
check("BB debuff mount is cancelEligible = false (engine cancel is buff-only)",
    bbContent and bbContent:find('BB.DefaultDebuffBucket, false, "HARMFUL")', 1, true) ~= nil)
check("BB buff mount is cancelEligible = true",
    bbContent and bbContent:find('BB.DefaultBuffBucket, true, "HELPFUL")', 1, true) ~= nil)
check("2c: BB passes unitPolarity = friendly (always the player's own auras)",
    bbContent and bbContent:find('unitPolarity      = "friendly"', 1, true) ~= nil)
check("buffborders.lua publishes ns.QUI_BuffBorders.DefaultBuffBucket/DefaultDebuffBucket",
    bbAuras and bbAuras:find("ns.QUI_BuffBorders", 1, true) ~= nil
    and bbAuras:find("BB.DefaultBuffBucket = DefaultBuffBucket", 1, true) ~= nil
    and bbAuras:find("BB.DefaultDebuffBucket = DefaultDebuffBucket", 1, true) ~= nil)

-- Frame-level BB toggles SURVIVED migration (Blizzard-frame banish gates the
-- runtime still reads: enableBuffs/enableDebuffs, hide*/fade*, iconSkin,
-- externalSkinning, borderSize, fontSize) — their rows must still exist.
check("BB keeps the enableBuffs row (frame-level gate, survived migration)",
    bbContent and bbContent:find('"enableBuffs"', 1, true) ~= nil)
check("BB keeps the enableDebuffs row (frame-level gate, survived migration)",
    bbContent and bbContent:find('"enableDebuffs"', 1, true) ~= nil)

-- Deleted per-strip dbKeys (pruned by migrations.lua's SeedAuraElements) must
-- not reappear in either settings file.
for _, deadKey in ipairs({ "buffIconSize", "debuffMaxIcons", "buffFilterPlayer" }) do
    check("dead dbKey removed from UF schema: " .. deadKey,
        ufSchema and ufSchema:find(deadKey, 1, true) == nil)
    check("dead dbKey removed from BB content: " .. deadKey,
        bbContent and bbContent:find(deadKey, 1, true) == nil)
end

-- SORT_OPTIONS expansion: new sort methods --------------------------------
check("editor: SORT_OPTIONS carries IMPORTANT_ONLY", editor:find('"IMPORTANT_ONLY"', 1, true) ~= nil)
check("editor: SORT_OPTIONS carries UF_DEBUFF", editor:find('"UF_DEBUFF"', 1, true) ~= nil)

-- Whitelist filter mode + blacklist spell list (Task 5) -------------------
check("editor: whitelist filter mode offered", editor:find('value = "whitelist"', 1, true) ~= nil)
check("editor: spell map helper exists", editor:find("AddSpellMapEditor", 1, true) ~= nil)
check("editor: blacklist bound", editor:find("element.blacklist", 1, true) ~= nil)
check("editor: whitelist bound", editor:find("element.whitelist", 1, true) ~= nil)

-- Tri-state filter-flag dropdowns (Task 6) ---------------------------------
check("editor: tri-state flag options table", editor:find("TRI_STATE_OPTIONS", 1, true) ~= nil)
check("editor: flags no longer plain checkboxes",
    editor:find('CreateFormCheckbox%(ctx%.detailArea, nil, entry%.token') == nil)

-- Dispel filter, max duration, boolean gates (Task 7) ----------------------
check("editor: dispel mode options table", editor:find("DISPEL_FILTER_MODE_OPTIONS", 1, true) ~= nil)
check("editor: Bleed dispel type offered", editor:find('key = "Bleed"', 1, true) ~= nil)
check("editor: max duration slider bound", editor:find('"maxDurationSec"', 1, true) ~= nil)
check("editor: stealable gate bound", editor:find('"gateStealable"', 1, true) ~= nil)
check("editor: boss-or-role gate bound", editor:find('"gateBossOrRoleAura"', 1, true) ~= nil)

if fails > 0 then
    print(("%d failures"):format(fails))
    os.exit(1)
end
print("aura_elements_editor_test: all checks passed")
