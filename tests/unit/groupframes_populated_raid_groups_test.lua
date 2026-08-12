local SRC = "QUI_GroupFrames/groupframes/groupframes.lua"

local fh = assert(io.open(SRC, "rb"))
local source = fh:read("*a")
fh:close()

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

local fnStart = assert(source:find("local function GetPopulatedRaidGroups", 1, true))
local fnEnd = assert(source:find("local function NormalizeRaidRole", fnStart, true))
local fnSrc = source:sub(fnStart, fnEnd - 1)

local calls = 0
local roster = { 1, 1, 1, 3, 3, 8, 8, 8, 8, 8 }
local allowed = { [1] = true, [3] = true, [8] = true }

local chunk = assert((loadstring or load)([[
local _state, GetLayoutSettings, GetNumGroupMembers, GetRaidRosterInfo = ...
]] .. fnSrc .. "\nreturn GetPopulatedRaidGroups\n"))

local GetPopulatedRaidGroups = chunk(
    { IsRaidSubgroupAllowed = function(subgroup) return allowed[subgroup] == true end },
    function() return {} end,
    function() return #roster end,
    function(i) calls = calls + 1; return "Unit" .. i, nil, roster[i] end)

local populated = GetPopulatedRaidGroups()

check("each allowed subgroup carries its member count",
    populated[1] == 3 and populated[3] == 2 and populated[8] == 5)

check("counts stay truthy so existing populated[g] gates are unchanged",
    populated[1] and populated[3] and populated[8] and true)

check("subgroups the layout disallows are absent",
    populated[2] == nil and populated[4] == nil and populated[7] == nil)

check("one roster pass, not one per subgroup", calls == #roster, "calls=" .. calls)

allowed = {}
calls = 0
check("empty allowlist yields no groups and still one pass",
    next(GetPopulatedRaidGroups()) == nil and calls == #roster)

local sizesStart = assert(source:find("local function UpdateHeaderSizes", 1, true))
local sizesEnd = assert(source:find("local function ShowRaidGroupHeaders", sizesStart, true))
check("UpdateHeaderSizes reads the roster only through GetPopulatedRaidGroups",
    source:sub(sizesStart, sizesEnd):find("GetRaidRosterInfo", 1, true) == nil)

if fails > 0 then
    print(("FAILED %d check(s)"):format(fails))
    os.exit(1)
end
print("PASS groupframes_populated_raid_groups_test")
