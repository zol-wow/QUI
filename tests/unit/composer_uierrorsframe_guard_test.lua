-- tests/unit/composer_uierrorsframe_guard_test.lua
-- Run: lua tests/unit/composer_uierrorsframe_guard_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("QUI_CDM/cdm/settings/composer.lua")
-- Every AddMessage on UIErrorsFrame must be presence-guarded.
for pre in src:gmatch("([%w_%. \t]-)UIErrorsFrame:AddMessage") do
    assert(src:find("if UIErrorsFrame then", 1, true) or
           src:find("UIErrorsFrame and UIErrorsFrame.AddMessage", 1, true),
        "unguarded UIErrorsFrame:AddMessage in composer.lua")
end
-- Direct check: the bare two-line pattern must be gone.
assert(select(2, src:gsub("\n%s*UIErrorsFrame:AddMessage", "")) == 0,
    "bare statement-leading UIErrorsFrame:AddMessage remains")
print("OK composer_uierrorsframe_guard_test")
