-- tests/unit/party_targets_class_probe_order_test.lua
-- Run: lua tests/unit/party_targets_class_probe_order_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("QUI_GroupFrames/groupframes/groupframes_party_targets.lua")
assert(not src:find("if class and not issecretvalue(class)", 1, true),
    "class must not be truth-tested before the secret probe")
assert(src:find("issecretvalue and issecretvalue(class)", 1, true),
    "binary probe for class required")
-- PTR7 wave: collapse-in-place (`if <probe>(class) then class = nil end`)
-- replaced the stored-flag shape — the truth-test below is then provably on
-- a non-secret value, which is what the analyzer's path-local contract
-- can actually credit.
local probePos = src:find("if issecretvalue and issecretvalue(class) then class = nil end", 1, true)
local branchPos = src:find("if class then", 1, true)
assert(probePos and branchPos and probePos < branchPos,
    "collapse-in-place probe must precede the class branch")
print("OK party_targets_class_probe_order_test")
