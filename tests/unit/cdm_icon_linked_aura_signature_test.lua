-- tests/unit/cdm_icon_linked_aura_signature_test.lua
-- Run: lua tests/unit/cdm_icon_linked_aura_signature_test.lua
--
-- Regression: during cold login, render entries can be built before
-- Blizzard's aura alias catalog has populated. When linkedSpellIDs or other
-- runtime alias facts arrive later, icon pools and tracked bars must refresh
-- their spell entries; otherwise stale entries persist until /reload.

local function readAll(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return text:gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function sliceBetween(text, startMarker, stopMarker)
    local startPos = assert(text:find(startMarker, 1, true),
        "expected to find: " .. startMarker)
    local stopPos = stopMarker
        and select(1, text:find(stopMarker, startPos + #startMarker, true))
    return text:sub(startPos, (stopPos or (#text + 1)) - 1)
end

local icons = readAll("QUI_CDM/cdm/cdm_icon_renderer.lua")
local containers = readAll("QUI_CDM/cdm/cdm_containers.lua")
local bars = readAll("QUI_CDM/cdm/cdm_bar_renderer.lua")

local entrySignature = sliceBetween(
    icons,
    "local function AppendEntrySignature(parts, prefix, entry, idx)",
    "local function AppendEntryListSignature(parts, prefix, list)")

assert(entrySignature:find("entry.linkedSpellIDs", 1, true),
    "icon pool signature must include linkedSpellIDs so linked aura aliases rebuild stale icons")

local buffFingerprint = sliceBetween(
    containers,
    "-- Fingerprint: skip rebuild when the same buff spellIDs are active.",
    "local fingerprint = table.concat(parts, \",\")")

assert(buffFingerprint:find("entry.linkedSpellIDs", 1, true),
    "buff layout fingerprint must include linkedSpellIDs before it skips BuildIcons")

local iconListSignature = sliceBetween(
    icons,
    "local function BuildIconListSignature(viewerType, container, spellData)",
    "local function PoolMatchesContainer(pool, container)")

assert(iconListSignature:find("AppendCustomRuntimeEntrySignature", 1, true),
    "custom container signatures must include synthesized runtime entry facts")

local barReuse = sliceBetween(
    bars,
    "-- No rebuild needed",
    "    -- Clear existing pool")

assert(barReuse:find("bar._spellEntry = entry", 1, true),
    "tracked bars must adopt refreshed spell entries when only linkedSpellIDs changed")

print("OK: cdm_icon_linked_aura_signature_test")
