-- tests/unit/cdm_buff_layout_reanchor_repair_net_test.lua
-- Run: lua tests/unit/cdm_buff_layout_reanchor_repair_net_test.lua
--
-- Repair net under test: the player UNIT_AURA coalesce in cdm_buff_layout was
-- blind under the re-anchor engine -- its combat gate counted visible icons from
-- CDMIconFactory:GetIconPool("buff"), which the engine leaves EMPTY (matched buff
-- entries are direct-anchored native Blizzard frames), and LayoutBuffIcons
-- early-returns when the engine owns the surface. So one lost/dropped
-- OnActiveStateChanged event left the buff surface stuck (invisible active buff
-- or stale expired icon) until unrelated churn. The reference addon layers
-- redundant repair triggers; the QUI equivalent is routing the aura coalesce to
-- the re-anchor hooks' throttled re-claim (MarkDirty -> Flush -> RefreshBuiltin).

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_CDM/cdm/cdm_buff_layout.lua")

assert(not src:find(":MarkClean()", 1, true),
    "buff layout must not write Blizzard viewer dirty state")

local bodyStart = assert(src:find("local iconAuraCoalesce = CreateFrame", 1, true),
    "icon aura coalesce frame not found")
local bodyEnd = assert(src:find("if ns.AuraEvents then", bodyStart, true),
    "icon aura coalesce end marker not found")
local body = src:sub(bodyStart, bodyEnd)

assert(body:find('ns._cdmReanchorHooks:MarkDirty("buff")', 1, true),
    "aura coalesce must route a re-anchor repair re-claim (MarkDirty 'buff') when the engine owns the buff surface")

local reanchorPos = body:find("_cdmBoot", 1, true)
local legacyPos = body:find('GetIconPool("buff")', 1, true)
assert(reanchorPos, "re-anchor routing must gate on ns._cdmBoot (engine active)")
assert(legacyPos, "legacy owned-pool count path should remain for the non-engine path")
assert(reanchorPos < legacyPos,
    "re-anchor routing must run BEFORE the legacy owned-pool count (the pool is empty under the engine, so the legacy gate is blind)")

-- INSTALL must be UNCONDITIONAL. ADDON_LOADED handlers fire in registration
-- (TOC) order: cdm_buff_layout registers BEFORE cdm_containers, so when
-- Initialize() runs the provider engine is not initialized yet and
-- GetBuffIconViewer() (-> CDMProvider:GetViewerFrame) returns nil. Gating the
-- UNIT_AURA subscription install on that init-time viewer skipped it EVERY
-- session -- the repair net never existed in-game (proven by GetLastDiag:
-- aura live, last refresh pass 60s stale). The coalesce handler and the
-- subscriber both re-fetch the viewer per-event, so install-time presence
-- is irrelevant.
local regionStart = assert(src:find("local lastAuraIconCount = 0", 1, true),
    "event-based updates header not found")
local regionEnd = assert(src:find("InstallBarViewerLayoutHook()", regionStart, true),
    "bar viewer hook marker not found")
local region = src:sub(regionStart, regionEnd)
assert(region:find('AuraEvents:Subscribe("player"', 1, true),
    "player UNIT_AURA subscription must exist in the icon repair-net region")
assert(not region:find("if iconViewer then", 1, true),
    "UNIT_AURA subscription install must NOT be gated on the init-time viewer "
    .. "(nil during ADDON_LOADED on every boot -- provider engine initializes later)")

print("OK: cdm_buff_layout_reanchor_repair_net_test")
