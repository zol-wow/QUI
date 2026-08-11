-- tests/unit/cdm_reanchor_boot_helpers_test.lua
-- Run: lua tests/unit/cdm_reanchor_boot_helpers_test.lua
local ns = {}
-- Task 45f: cdm_reanchor_boot.lua routes discarded-result pcall guards
-- through ns.SafeCall. Additive stub (T1d/T1e precedent).
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_boot.lua", "cdm_reanchor_boot.lua")("QUI", ns)
local B = assert(ns.CDMReanchorBoot, "CDMReanchorBoot should be exported")

-- positionOwned: SetScale(1) only if needed, ClearAllPoints, SetPoint, Show, onIconPlaced
local ops = {}
local placed
local icon = {
    GetScale = function() return 2 end,
    SetScale = function(_, s) ops[#ops+1] = { "scale", s } end,
    ClearAllPoints = function() ops[#ops+1] = { "clear" } end,
    SetPoint = function(_, p, c, rp, x, y) ops[#ops+1] = { "set", p, c, rp, x, y } end,
    Show = function() ops[#ops+1] = { "show" } end,
}
local container = { c = 1 }
local placedRowConfig
local rowCfg = { row = 3 }
local positionOwned = B._MakePositionOwned({ onIconPlaced = function(i, rc) placed = i; placedRowConfig = rc end })
positionOwned(icon, container, "CENTER", "CENTER", 5, -5, rowCfg)
assert(ops[1][1] == "scale" and ops[1][2] == 1, "rescales to 1 when scale != 1")
assert(ops[2][1] == "clear", "clears points")
assert(ops[3][1] == "set" and ops[3][3] == container and ops[3][5] == 5 and ops[3][6] == -5, "sets point onto container")
assert(ops[4][1] == "show", "shows")
assert(placed == icon, "onIconPlaced fired")
assert(placedRowConfig == rowCfg, "rowConfig forwarded to onIconPlaced (for ConfigureIcon)")

-- applySize: SetSize only when w>0 and h>0; onMetrics fires
local sized, metricsSeen
local cont2 = { SetSize = function(_, w, h) sized = { w, h } end }
local applySize = B._MakeApplySize({ onMetrics = function(c, m) metricsSeen = m end })
applySize(cont2, { iconWidth = 40, totalHeight = 30 })
assert(sized[1] == 40 and sized[2] == 30, "SetSize(iconWidth, totalHeight)")
assert(metricsSeen.iconWidth == 40, "onMetrics fired")
sized = nil
applySize(cont2, { iconWidth = 0, totalHeight = 30 })
assert(sized == nil, "no SetSize when a dimension is 0")

-- mintOwned: resolves container by key then acquireIcon; nil container -> nil
local acquired
local mintOwned = B._MakeMintOwned({
    getContainer = function(k) return k == "essential" and container or nil end,
    acquireIcon = function(c, e) acquired = { c, e }; return "OWNED" end,
})
local entry = { id = 7 }
assert(mintOwned(entry, "essential") == "OWNED", "mints owned icon")
assert(acquired[1] == container and acquired[2] == entry, "acquireIcon(container, entry)")
assert(mintOwned(entry, "nope") == nil, "no container -> nil")

-- getAdditional: delegates to resolveAdditional; default empty
local getAdd = B._MakeGetAdditional({ resolveAdditional = function(k) return { k } end })
assert(getAdd("utility")[1] == "utility", "delegates to resolveAdditional")
assert(#B._MakeGetAdditional({})("x") == 0, "no resolver -> empty")

print("OK: cdm_reanchor_boot_helpers_test")
