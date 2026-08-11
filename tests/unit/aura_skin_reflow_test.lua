-- tests/unit/aura_skin_reflow_test.lua
-- Restyle is the combat-legal subset of Configure: style only, no group
-- registration, no layout, no button creation.
local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("core/aura_skin.lua")

local restyleBody = src:match("function AuraSkin%.Restyle(.-)\nend")
assert(restyleBody, "AuraSkin.Restyle must exist")
assert(not restyleBody:find("AddAuraGroup", 1, true), "Restyle must not register groups (combat)")
assert(not restyleBody:find("SetAuraGroupLayout", 1, true), "Restyle must not touch layout (combat)")
assert(not restyleBody:find("CreateFrame", 1, true), "Restyle must not create frames (combat)")
assert(restyleBody:find("styleButton", 1, true), "Restyle must re-apply styleButton")
print("aura_skin_reflow_test OK")
