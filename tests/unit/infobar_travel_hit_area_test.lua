local file = assert(io.open("modules/infobar/travel.lua", "rb"))
local source = file:read("*a")
file:close()

assert(source:find("hearth:SetSize(slotFrame._quiFixedWidth or size, size)", 1, true))
assert(source:find("hearthIcon:SetSize(size, size)", 1, true))
assert(source:find("hearthIcon:SetPoint(\"LEFT\", hearth, \"LEFT\", 0, 0)", 1, true))
print("ALL TESTS PASSED")
