-- tests/unit/castbar_getunitsettings_per_frame_test.lua
-- Run: lua tests/unit/castbar_getunitsettings_per_frame_test.lua
--
-- Perf: CastBar_OnUpdate runs every frame while a cast is active. In the
-- normal-mode (non-timer-driven) path it fetched GetUnitSettings(self.unitKey)
-- once, then RE-FETCHED the same object in several later branches (channel-tick
-- refresh, empowered level text, time-text visibility) — 2-4 identical profile
-- walks per frame for a value that cannot change within a single frame. The fix
-- hoists the fetch once after the active-cast early-returns and reuses
-- `currentSettings` in those branches (each branch keeps its own
-- currentCastSettings derivation, which differs in fallback semantics).
--
-- This bounds the number of GetUnitSettings(self.unitKey) calls inside
-- CastBar_OnUpdate so re-introducing per-branch re-fetches is caught. The two
-- permitted sites are: (1) the throttled timer-driven channel-tick branch, which
-- early-returns before the normal path, and (2) the single hoisted per-frame
-- fetch in the normal path.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local castbar = readAll("modules/unitframes/castbar.lua")

local s = assert(castbar:find("local function CastBar_OnUpdate(self, elapsed)", 1, true),
    "expected to find CastBar_OnUpdate handler")
local e = assert(castbar:find("castbar.castbarOnUpdate = CastBar_OnUpdate", s, true),
    "expected to find the end-of-handler marker (castbar.castbarOnUpdate = CastBar_OnUpdate)")
local body = castbar:sub(s, e)

local count = 0
for _ in body:gmatch("GetUnitSettings%(self%.unitKey%)") do
    count = count + 1
end

assert(count <= 2, string.format(
    "CastBar_OnUpdate should fetch GetUnitSettings(self.unitKey) at most twice "
    .. "(throttled timer-driven branch + one hoisted per-frame fetch reused across "
    .. "branches); found %d — per-branch re-fetches were not consolidated", count))

print("castbar_getunitsettings_per_frame_test: OK")
