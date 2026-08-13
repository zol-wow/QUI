local SRC = "QUI_GroupFrames/groupframes/groupframes.lua"

local fh = assert(io.open(SRC, "rb"))
local source = fh:read("*a")
fh:close()

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

local guardStart = assert(source:find("_state.SetHeaderAttributeIfChanged = function", 1, true),
    "SetHeaderAttributeIfChanged must exist")
local guardEnd = assert(source:find("\nend\n", guardStart, true)) + 4
local guardSrc = source:sub(guardStart, guardEnd)

local _state = {}
local chunk = assert((loadstring or load)("local _state = ...\n" .. guardSrc))
chunk(_state)

local writes = {}
local header = {
    attrs = {},
    GetAttribute = function(self, name) return self.attrs[name] end,
    SetAttribute = function(self, name, value)
        writes[#writes + 1] = name
        self.attrs[name] = value
    end,
}

_state.SetHeaderAttributeIfChanged(header, "showRaid", true)
check("first write reaches SetAttribute", #writes == 1 and header.attrs.showRaid == true)

_state.SetHeaderAttributeIfChanged(header, "showRaid", true)
check("identical rewrite is suppressed", #writes == 1)

_state.SetHeaderAttributeIfChanged(header, "showRaid", false)
check("changed value reaches SetAttribute", #writes == 2 and header.attrs.showRaid == false)

_state.SetHeaderAttributeIfChanged(header, "groupFilter", nil)
check("nil-to-nil write is suppressed", #writes == 2)

local REGIONS = {
    { "ConfigurePartyHeader/RaidHeader/RaidGroupHeaders", "local function ConfigurePartyHeader", "function _state.UpdateRaidGroupLabel" },
    { "UpdateHeaderSizes", "local function UpdateHeaderSizes", "local function ShowRaidGroupHeaders" },
    { "UpdateHeaderVisibility", "local function UpdateHeaderVisibility", "ApplyChildFrameLayout = function" },
    { "UpdateFrameScaling", "local function UpdateFrameScaling", "local function ResolveRangeSpells" },
}

for _, region in ipairs(REGIONS) do
    local label, from, to = region[1], region[2], region[3]
    local a = assert(source:find(from, 1, true), from)
    local b = assert(source:find(to, a, true), to)
    local body = source:sub(a, b):gsub("_state%.SetHeaderAttributeIfChanged = function.-\nend\n", "")
    local raw = {}
    for line in body:gmatch("[^\n]+") do
        if line:find(":SetAttribute(", 1, true) then
            raw[#raw + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    check(label .. " never calls SetAttribute unguarded", #raw == 0,
        #raw > 0 and (tostring(#raw) .. " raw call(s), first: " .. raw[1]) or nil)
end

if fails > 0 then
    print(("FAILED %d check(s)"):format(fails))
    os.exit(1)
end
print("PASS groupframes_header_attribute_guard_test")
