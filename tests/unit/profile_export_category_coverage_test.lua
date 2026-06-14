-- Guard: every persisted profile setting must be reachable by SELECTIVE
-- import/export, not just the full export.
--
-- Full export (QUICore:ExportProfileToString) copies the whole db.profile, so
-- it can never miss a setting. Selective export/import is driven by the
-- hand-maintained category key-lists in core/profile_io.lua
-- (PROFILE_IMPORT_CATEGORIES + the PROFILE_*_GENERAL_KEYS lists). Any key those
-- lists don't reference is silently dropped on selective export and is invisible
-- in the import analyzer. Those lists drift behind defaults.lua every time
-- settings are added (it has happened repeatedly), and there was no automated
-- guard — this is it.
--
-- Strategy (behavioral, robust to internal refactors): realize the full defaults
-- schema into a live profile, then assert that a "select everything" selective
-- export carries the same top-level keys (and the same general.* keys) as a full
-- export. A key in the full export but missing from the selective export means
-- no category covers it.
--
-- Run from repo root: lua tests/unit/profile_export_category_coverage_test.lua

local env = dofile("tools/_addon_env.lua")
-- noSeed: this test asserts every DEFAULTS key is export-covered. The
-- new-profile seed (Starter Profile) is a separate artifact that may carry
-- extra keys not in defaults.lua; it must not contaminate the defaults
-- coverage check. Seed/preset parity is guarded by
-- tests/unit/starter_preset_matches_seed_test.lua.
local h = env.BuildHarness({ noSeed = true })

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate    = LibStub("LibDeflate")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

-- Keys the full export legitimately emits (or that exist on the profile) which
-- are deliberately NOT individually owned by a selective category.
--   _quiBundledGlobals : synthetic export-only bundle of db.global tracker
--                        spells; not a profile setting (PROFILE_EXPORT_GLOBALS_KEY).
-- Per-character data (chat history/edit-box entries, click-cast bindings) lives
-- on db.char, never db.profile, so it needs no entry here.
local TOPLEVEL_ALLOWLIST = {
    _quiBundledGlobals = true,
}
local GENERAL_ALLOWLIST = {}

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = DeepCopy(vv) end
    return out
end

-- Mirror of DeserializeProfileImportPayload in core/profile_io.lua: strip
-- whitespace + the "QUI1:" prefix, then DecodeForPrint -> DecompressDeflate ->
-- Deserialize. Kept in-test (rather than reaching the file-local) so the test
-- exercises the real on-the-wire format the export emits.
local function decode(str)
    if type(str) ~= "string" then return nil, "not a string: " .. tostring(str) end
    str = str:gsub("%s+", "")
    local prefix = str:match("^([A-Z][A-Z0-9]*%d):")
    if prefix then str = str:sub(#prefix + 2) end
    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then return nil, "DecodeForPrint failed" end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil, "DecompressDeflate failed" end
    local ok, payload = AceSerializer:Deserialize(serialized)
    if not ok or type(payload) ~= "table" then return nil, "Deserialize failed" end
    return payload
end

-- AceDB resolves scalar defaults lazily through a metatable, so pairs() over a
-- fresh profile sees nothing. Write every default key as a real key so the full
-- export (which iterates pairs) emits the complete schema. Keys whose default is
-- nil (e.g. fpsBackup) stay absent — they are not exportable settings.
for k, v in pairs(h.defaults.profile) do
    h.db.profile[k] = DeepCopy(v)
end

-- Ground truth: the full export's key set.
local fullStr = h.QUICore:ExportProfileToString()
check("full export returns a QUI1 string",
      type(fullStr) == "string" and fullStr:match("^QUI1:") ~= nil,
      tostring(fullStr):sub(1, 60))
local fullPayload, fullErr = decode(fullStr)
check("full export decodes", fullPayload ~= nil, fullErr)

-- Selective export of EVERY category (parents + children).
local allIDs = {}
local function collectIDs(cats)
    for _, c in ipairs(cats or {}) do
        allIDs[#allIDs + 1] = c.id
        if c.children then collectIDs(c.children) end
    end
end
collectIDs(h.QUICore:GetProfileExportCategories())
check("export exposes categories", #allIDs > 0, "GetProfileExportCategories returned none")

local selStr, selErr = h.QUICore:ExportProfileSelectionToString(allIDs)
check("select-all export returns a QUI1 string",
      type(selStr) == "string" and selStr:match("^QUI1:") ~= nil,
      tostring(selErr or selStr):sub(1, 60))
local selPayload, selDErr = decode(selStr)
check("select-all export decodes", selPayload ~= nil, selDErr)

if fullPayload and selPayload then
    -- Top-level coverage.
    local missingTop = {}
    for k in pairs(fullPayload) do
        if not TOPLEVEL_ALLOWLIST[k] and selPayload[k] == nil then
            missingTop[#missingTop + 1] = k
        end
    end
    table.sort(missingTop)
    check("every top-level profile key is covered by a selective category",
          #missingTop == 0,
          (#missingTop > 0)
            and ("uncovered: { " .. table.concat(missingTop, ", ")
                 .. " } -- add each to a PROFILE_IMPORT_CATEGORIES category"
                 .. " (topLevelKeys) in core/profile_io.lua")
            or nil)

    -- general.* coverage (split across PROFILE_THEME/QOL/SKINNING_GENERAL_KEYS).
    local fullGeneral = fullPayload.general or {}
    local selGeneral  = selPayload.general or {}
    local missingGeneral = {}
    for k in pairs(fullGeneral) do
        if not GENERAL_ALLOWLIST[k] and selGeneral[k] == nil then
            missingGeneral[#missingGeneral + 1] = k
        end
    end
    table.sort(missingGeneral)
    check("every general.* profile key is covered by a selective category",
          #missingGeneral == 0,
          (#missingGeneral > 0)
            and ("uncovered: { " .. table.concat(missingGeneral, ", ")
                 .. " } -- add each to PROFILE_THEME_GENERAL_KEYS,"
                 .. " PROFILE_QOL_GENERAL_KEYS, or PROFILE_SKINNING_GENERAL_KEYS"
                 .. " in core/profile_io.lua")
            or nil)
end

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
