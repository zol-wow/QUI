-- tests/unit/tooltip_inspect_secret_probe_test.lua
-- Run: lua tests/unit/tooltip_inspect_secret_probe_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("modules/qol/tooltip_inspect.lua")
assert(src:find("issecretvalue and issecretvalue(classID)", 1, true),
    "classID must be probed before truth-test")
assert(src:find("issecretvalue and issecretvalue(specID)", 1, true),
    "specID must be probed before truth-test/arithmetic")
assert(src:find("issecretvalue and issecretvalue(localizedClassName)", 1, true),
    "localizedClassName must be probed before the `or` truth-test")
assert(src:find("issecretvalue and issecretvalue(classToken)", 1, true),
    "classToken must be probed before the `or` truth-test / use as fallback")
local classProbe = src:find("issecretvalue and issecretvalue(classID)", 1, true)
local classBranch = src:find("if classID and", 1, true)
assert(classProbe and classBranch and classProbe < classBranch,
    "classID probe must precede its truth-test branch")
local specProbe = src:find("issecretvalue and issecretvalue(specID)", 1, true)
local specBranch = src:find("if specID and specID > 0", 1, true)
assert(specProbe and specBranch and specProbe < specBranch,
    "specID probe must precede its truth-test branch")

-- GetClassData's return line is the single use site for both
-- localizedClassName and classToken (the `or` truth-test plus the second
-- return value) — both probes must anchor uniquely and precede it.
local returnLine = "return localizedClassName or classToken, classToken"
local returnPos = src:find(returnLine, 1, true)
assert(returnPos, "GetClassData return line not found (anchor stale?)")
do
    local first = src:find(returnLine, 1, true)
    local second = src:find(returnLine, first + 1, true)
    assert(not second, "return line anchor must be unique in the file")
end

local nameProbeAnchor = "issecretvalue and issecretvalue(localizedClassName)"
local nameProbe = src:find(nameProbeAnchor, 1, true)
assert(nameProbe, "localizedClassName probe anchor not found")
do
    local second = src:find(nameProbeAnchor, nameProbe + 1, true)
    assert(not second, "localizedClassName probe anchor must be unique in the file")
end
assert(nameProbe < returnPos,
    "localizedClassName probe must precede the return-line use site")

local tokenProbeAnchor = "issecretvalue and issecretvalue(classToken)"
local tokenProbe = src:find(tokenProbeAnchor, 1, true)
assert(tokenProbe, "classToken probe anchor not found")
do
    local second = src:find(tokenProbeAnchor, tokenProbe + 1, true)
    assert(not second, "classToken probe anchor must be unique in the file")
end
assert(tokenProbe < returnPos,
    "classToken probe must precede the return-line use site")

print("OK tooltip_inspect_secret_probe_test")
