-- tests/unit/cdm_debug_disabled_hotpath_test.lua
-- Run: lua tests/unit/cdm_debug_disabled_hotpath_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertAbsent(path, needle, reason)
    local text = readFile(path)
    assert(not text:find(needle, 1, true), reason .. " in " .. path)
end

assertAbsent(
    "QUI_CDM/cdm/cdm_icon_renderer.lua",
    "if CDMIcons.DebugIconEvent then",
    "icon debug call sites must be guarded by QUI_CDM_ICON_DEBUG before building debug args")

assertAbsent(
    "QUI_CDM/cdm/cdm_icon_renderer.lua",
    "if CDMIcons.DebugIconEvent then",
    "icon debug call sites must be guarded by QUI_CDM_ICON_DEBUG before building debug args")

assertAbsent(
    "QUI_CDM/cdm/cdm_icon_renderer.lua",
    "if CDMIcons.DebugEntryBuild then",
    "icon entry-build debug must be guarded by QUI_CDM_ICON_DEBUG before building debug args")

assertAbsent(
    "QUI_CDM/cdm/cdm_containers.lua",
    "if ns.CDMIcons and ns.CDMIcons.DebugLayoutFilter then",
    "layout filter debug must be guarded by QUI_CDM_ICON_DEBUG before building debug args")

assertAbsent(
    "QUI_CDM/cdm/cdm_bar_renderer.lua",
    "DebugBarLabel(entry, spellID,",
    "bar debug label emission must be guarded by QUI_CDM_BAR_DEBUG before building debug args")

assertAbsent(
    "QUI_CDM/cdm/cdm_blizz_mirror.lua",
    "if CDMBlizzMirror.TaintLog then",
    "taint debug calls must be guarded by QUI_CDM_TAINT_DEBUG before building debug args")

assertAbsent(
    "QUI_CDM/cdm/cdm_icon_renderer.lua",
    "if mirrorMod and mirrorMod.TaintLog then",
    "taint debug calls must be guarded by QUI_CDM_TAINT_DEBUG before building debug args")

assertAbsent(
    "QUI_CDM/cdm/cdm_icon_renderer.lua",
    "if ns.CDMBlizzMirror and ns.CDMBlizzMirror.TaintLog then",
    "taint debug calls must be guarded by QUI_CDM_TAINT_DEBUG before building debug args")

assertAbsent(
    "QUI_CDM/cdm/cdm_blizz_mirror.lua",
    "TaintLog(\"Sanitize\"",
    "direct taint debug calls must be guarded by QUI_CDM_TAINT_DEBUG before building debug args")

print("OK: cdm_debug_disabled_hotpath_test")
