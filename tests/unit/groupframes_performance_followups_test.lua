local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local groupframes = read("QUI_GroupFrames/groupframes/groupframes.lua")
local rebuildStart = assert(groupframes:find("local function RebuildUnitFrameMap()", 1, true))
local rebuildEnd = assert(groupframes:find("local function EnsureAnchorFrame", rebuildStart, true))
local rebuild = groupframes:sub(rebuildStart, rebuildEnd)
assert(rebuild:find("local previousUnits = {}", 1, true), "roster rebuild should snapshot active units")
assert(rebuild:find("RefreshUnitEventRegistrations(previousUnits)", 1, true),
    "roster rebuild should pass the active-unit snapshot")
assert(not rebuild:find("UnregisterAllUnitEventFrames", 1, true),
    "roster rebuild should not unregister every unit event frame")
assert(groupframes:find("function _state.RefreshUnitEventRegistrations(previousUnits)", 1, true),
    "unit event refresh should accept the active-unit snapshot")
assert(groupframes:find("not _state.unitEventRegistered[unit]", 1, true),
    "unit event refresh should recover reassigned tokens")

local raidbuffs = read("QUI_GroupFrames/groupframes/raidbuffs.lua")
assert(raidbuffs:find("local lastLayoutKey", 1, true), "raid buffs should cache layout state")
assert(raidbuffs:find("local layoutChanged = layoutKey ~= lastLayoutKey", 1, true),
    "raid buffs should detect layout changes")
assert(raidbuffs:find("if not inCombat and layoutChanged then", 1, true),
    "raid buff icons should only re-anchor after layout changes")

local targeted = read("QUI_GroupFrames/groupframes/groupframes_targeted_spells.lua")
local rosterStart = assert(targeted:find("local function HandleRosterChanged()", 1, true))
local rosterEnd = assert(targeted:find("local function HandleWorldChanged", rosterStart, true))
local roster = targeted:sub(rosterStart, rosterEnd)
assert(not roster:find("IndexRoster()", 1, true), "targeted roster handling should not index twice")
assert(roster:find("ClearAllCasts()", 1, true), "targeted roster handling should clear stale casts")
assert(roster:find("RefreshRuntimeState()", 1, true), "targeted roster handling should refresh runtime state")

local clickcast = read("QUI_GroupFrames/groupframes/groupframes_clickcast.lua")
local clickcastRosterStart = assert(clickcast:find('elseif event == "GROUP_ROSTER_UPDATE" then', 1, true))
local clickcastRosterEnd = assert(clickcast:find('elseif event == "PLAYER_REGEN_ENABLED" then', clickcastRosterStart, true))
local clickcastRoster = clickcast:sub(clickcastRosterStart, clickcastRosterEnd)
assert(clickcastRoster:find("RegisterAllFrames()", 1, true),
    "click-cast roster handling should register new group frames")
assert(not clickcastRoster:find("RegisterUnitFrames()", 1, true),
    "click-cast roster handling should not re-register unrelated unit frames")

local visibilityStart = assert(groupframes:find("local function UpdateHeaderVisibility", 1, true))
local visibilityEnd = assert(groupframes:find("ApplyChildFrameLayout = function", visibilityStart, true))
local visibility = groupframes:sub(visibilityStart, visibilityEnd)
assert(visibility:find("skipDeferredRefresh", 1, true),
    "header visibility should support roster-specific refresh suppression")
assert(visibility:find("if skipDeferredRefresh then return end", 1, true),
    "roster visibility should not schedule a generic full refresh")
local coalescerStart = assert(groupframes:find("gruCoalesceFrame:SetScript", 1, true))
local coalescerEnd = assert(groupframes:find("local eventFrame = CreateFrame", coalescerStart, true))
local coalescer = groupframes:sub(coalescerStart, coalescerEnd)
assert(coalescer:find("UpdateHeaderVisibility(true)", 1, true),
    "roster coalescer should use the incremental visibility path")
assert(coalescer:find("UpdateFrameScaling()", 1, true),
    "roster coalescer should not force a second header-size pass")

print("PASS groupframes_performance_followups_test")
