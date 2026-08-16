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

local customEntryBuilder = sliceBetween(
    icons,
    "local function BuildSpellEntryFromCustom(entry, idx, viewerType)",
    "function CDMIcons.ResolveCustomSpellEntries(viewerType)")

assert(customEntryBuilder:find("IsSelfAuraSpell", 1, true),
    "custom aura entries must carry Blizzard selfAura routing metadata")

local globals = _G
local builderEnv = setmetatable({
    ns = {
        CDMCustomAuraRuns = {
            ShouldUseSettings = function() return true end,
            HasAuraEntries = function() return true end,
        },
        CDMSpellData = {
            IsSelfAuraSpell = function(_, spellID) return spellID == 222 end,
        },
    },
    Sources = {},
    Shared = {},
    CDMIcons = {},
    GetTrackerSettings = function() return { containerType = "customBar" } end,
    GetBuiltinContainerEntryKind = function() return nil end,
    ResolveMacro = function() return nil end,
    GetCachedSpellName = function() return nil end,
}, { __index = globals })
builderEnv._G = builderEnv
local builderSource = customEntryBuilder:gsub(
    "^local function BuildSpellEntryFromCustom", "return function", 1)
local builderChunk = assert(loadstring(builderSource, "@cdm_icon_renderer.lua#BuildSpellEntryFromCustom"))
setfenv(builderChunk, builderEnv)
local builtAura = builderChunk()({
    id = 222,
    type = "spell",
    kind = "aura",
    name = "Managed Aura",
    linkedSpellIDs = { 333 },
}, 1, "custom")
assert(builtAura._useManagedAura == true and builtAura._selfAura == true,
    "eligible custom auras must carry managed and self-aura routing state")

local placeSource = sliceBetween(
    icons,
    "function CDMIcons.ShouldContainerLayoutPlaceIcon(icon, entry, containerDB, inCombat)",
    "function _resolverRuntimePolicy.WakeBuffIconContainer()")
placeSource = "return function" .. placeSource:sub(
    #"function CDMIcons.ShouldContainerLayoutPlaceIcon" + 1)
local placeEnv = setmetatable({
    visibilityPolicy = { ShouldPlaceLayoutIcon = function() return false end },
}, { __index = globals })
local placeChunk = assert(loadstring(placeSource, "@cdm_icon_renderer.lua#ShouldContainerLayoutPlaceIcon"))
setfenv(placeChunk, placeEnv)
local shouldPlace = placeChunk()
assert(shouldPlace({}, { _useManagedAura = true }, {}, false) == true,
    "managed aura proxies must remain in layout plans")
assert(shouldPlace({}, {}, {}, false) == false,
    "ordinary icons must still use the visibility policy")

local updateSource = sliceBetween(
    icons,
    "UpdateIconCooldown = function(icon)",
    "local function IsCustomBarEntryUsableOnCurrentClass(entry, viewerType)")
updateSource = updateSource:gsub("^UpdateIconCooldown =", "return", 1)
local ownedUpdates = 0
local updateEnv = setmetatable({
    UpdateIconCooldownOwned = function() ownedUpdates = ownedUpdates + 1 end,
}, { __index = globals })
local updateChunk = assert(loadstring(updateSource, "@cdm_icon_renderer.lua#UpdateIconCooldown"))
setfenv(updateChunk, updateEnv)
local updateCooldown = updateChunk()
updateCooldown({ _spellEntry = { _useManagedAura = true } })
assert(ownedUpdates == 0, "managed aura proxies must skip Lua cooldown resolution")
updateCooldown({ _spellEntry = {} })
assert(ownedUpdates == 1, "ordinary icons must retain Lua cooldown resolution")

local buffFingerprint = sliceBetween(
    containers,
    "local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList(\"buff\")",
    "local fingerprint = table.concat(parts, \",\")")

assert(buffFingerprint:find("entry.linkedSpellIDs", 1, true),
    "buff layout fingerprint must include linkedSpellIDs before it skips BuildIcons")

local iconListSignature = sliceBetween(
    icons,
    "local function BuildIconListSignature(viewerType, container, spellData)",
    "local function PoolMatchesContainer(pool, container)")

assert(iconListSignature:find("AppendCustomRuntimeEntrySignature", 1, true),
    "custom container signatures must include synthesized runtime entry facts")
assert(iconListSignature:find("IsSelfAuraSpell", 1, true),
    "custom container signatures must rebuild when selfAura routing metadata changes")

local barReuse = sliceBetween(
    bars,
    "if not needsRebuild then",
    "    -- self:ClearPool()")

assert(barReuse:find("bar._spellEntry = entry", 1, true),
    "tracked bars must adopt refreshed spell entries when only linkedSpellIDs changed")

print("OK: cdm_icon_linked_aura_signature_test")
