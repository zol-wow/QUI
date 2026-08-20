local path = "QUI_GroupFrames/groupframes/groupframes.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name)
    end
end

local refreshStart = assert(source:find("function QUI_GF:RefreshAllFrames(_reason)", 1, true))
local refreshEnd = assert(source:find("function QUI_GF:RefreshSettings()", refreshStart, true))
local refresh = source:sub(refreshStart, refreshEnd)

check("roster refresh has a distinct path", refresh:find("local rosterRefresh = _reason == \"roster\"", 1, true) ~= nil)
check("roster refresh skips aura layout invalidation", refresh:find("if not rosterRefresh and GFA and GFA.InvalidateLayout", 1, true) ~= nil)
check("roster aura work is dirty-gated", refresh:find("local auraDirty = not rosterRefresh or frame._quiRosterAuraDirty", 1, true) ~= nil)
check("aura scans require dirty frames", refresh:find("local auraCacheRender = auraCacheAvailable and auraDirty", 1, true) ~= nil)
check("roster refresh only visits dirty frames",
    refresh:find("if frame and frame:IsShown() and (not rosterRefresh or frame._quiRosterAuraDirty) then", 1, true) ~= nil)
check("roster refresh renders cached aura elements for dirty frames",
    refresh:find("if auraCacheAvailable then\n                    GFA:RenderFrame(frame)", 1, true) ~= nil)
check("roster refresh does not rebuild assigned aura strips twice",
    refresh:find("if not rosterRefresh and GFA and GFA.UpdateStripContainers then", 1, true) ~= nil)
check("roster dirty state is cleared after refresh", refresh:find("frame._quiRosterAuraDirty = nil", 1, true) ~= nil)

local decoratedStart = assert(source:find("local function DecorateGroupFrame(frame)", 1, true))
local decoratedEnd = assert(source:find("QUI_GF.DecorateGroupFrame = DecorateGroupFrame", decoratedStart, true))
local decorated = source:sub(decoratedStart, decoratedEnd)
check("unit reassignment marks aura state dirty", decorated:find("self._quiRosterAuraDirty = true", 1, true) ~= nil)
check("initial unit assignment marks aura state dirty", decorated:find("frame._quiRosterAuraDirty = true", 1, true) ~= nil)

local mrbFile = assert(io.open("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua", "rb"))
local mrbSource = mrbFile:read("*a")
mrbFile:close()
check("missing raid buffs does not schedule a second roster refresh",
    mrbSource:find("C_Timer.After(0.25, RefreshAll)", 1, true) == nil)

print("PASS groupframes_roster_aura_refresh_test")
