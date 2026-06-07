-- tests/unit/suite_split_tool_test.lua
-- TDD test for tools/split_suite_tocs.lua (Task 3: one-shot TOC splitter).
-- Run standalone: lua tests/unit/suite_split_tool_test.lua

local T = assert(loadfile("tools/split_suite_tocs.lua"))()

-- Path classification: QUI.toc line → owning manifest folder (or nil = stays core)
local manifest = assert(loadfile("core/addon_manifest.lua"))()
assert(T.ClassifyLine([[modules\cdm\cdm_shared.lua]], manifest) == "QUI_CDM")
assert(T.ClassifyLine([[modules\dungeon\mplus_timer.lua]], manifest) == "QUI_QoL")
assert(T.ClassifyLine([[modules\layout\anchoring.lua]], manifest) == nil, "layout stays core")
assert(T.ClassifyLine([[core\utils.lua]], manifest) == nil)
assert(T.ClassifyLine([[# == comment ==]], manifest) == nil)
-- nil means "core-or-unknown"; --run validation resolves which (unknown dirs exit 1)
assert(T.ClassifyLine([[modules\newthing\foo.lua]], manifest) == nil)

-- Path rewrite inside a sub-addon TOC: strip the modules\ prefix only
assert(T.RewriteForSubAddon([[modules\cdm\cdm_shared.lua]]) == [[cdm\cdm_shared.lua]])
assert(T.RewriteForSubAddon([[modules\damage_meter\damage_meter.lua]]) == [[damage_meter\damage_meter.lua]])

-- QUI_Options path rewrite: ..\QUI\modules\<dir>\ → ..\<Folder>\<dir>\
assert(T.RewriteOptionsLine([[..\QUI\modules\skinning\settings\x.lua]], manifest)
    == [[..\QUI_Skinning\skinning\settings\x.lua]])
assert(T.RewriteOptionsLine([[..\QUI\modules\utility\settings\keybinds_content.lua]], manifest)
    == [[..\QUI_QoL\utility\settings\keybinds_content.lua]])
assert(T.RewriteOptionsLine([[..\QUI\core\settings\foo.lua]], manifest)
    == [[..\QUI\core\settings\foo.lua]], "core-side lines untouched")
assert(T.RewriteOptionsLine([[shared.lua]], manifest) == [[shared.lua]])

-- Sub-addon TOC header
local hdr = T.BuildHeader({ folder = "QUI_Skinning", class = "lod" },
    "## Interface: 120000, 120001, 120005, 120007")
assert(hdr:match("## Interface: 120000, 120001, 120005, 120007"), "interface copied")
assert(hdr:match("## Dependencies: QUI"), "dep on core")
assert(hdr:match("## LoadOnDemand: 1"), "lod flag")
assert(hdr:match("## Group: QUI"), "group")
local hdr2 = T.BuildHeader({ folder = "QUI_Chat", class = "login" }, "## Interface: 1")
assert(not hdr2:match("LoadOnDemand"), "login class: no LOD flag")
assert(hdr2:match("## SavedVariablesPerCharacter: QUI_ChatHistory"), "chat keeps per-char SV")
assert(hdr2:match("## LoadSavedVariablesFirst: 1"), "chat SV loads first")
-- Version extraction: versionLine argument is forwarded into the header
assert(T.BuildHeader({folder="QUI_Skinning",class="lod"}, "## Interface: 1", "## Version: 9.9.9"):match("## Version: 9.9.9"),
    "custom versionLine forwarded")

-- CORE_DIRS export: exactly layout, ui, integrations — nothing else
assert(type(T.CORE_DIRS) == "table", "CORE_DIRS exported")
assert(T.CORE_DIRS.layout == true, "layout in CORE_DIRS")
assert(T.CORE_DIRS.ui == true, "ui in CORE_DIRS")
assert(T.CORE_DIRS.integrations == true, "integrations in CORE_DIRS")
local coreDirsCount = 0
for _ in pairs(T.CORE_DIRS) do coreDirsCount = coreDirsCount + 1 end
assert(coreDirsCount == 3, "CORE_DIRS has exactly 3 entries, got " .. coreDirsCount)

print("suite_split_tool_test OK")
