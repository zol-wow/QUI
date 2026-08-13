local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_ResourceBars/resourcebars/resourcebars.lua")

local start_pos = src:find("local function GetCustomTextColor(textCfg)", 1, true)
assert(start_pos, "could not locate GetCustomTextColor")
local end_pos = src:find("\nend\n", start_pos, true)

local GetCustomTextColor = assert(loadstring(
    src:sub(start_pos, end_pos + 4) .. "\nreturn GetCustomTextColor"))()

do
    local r, g, b, a = GetCustomTextColor({ textCustomColor = { 0.1, 0.2, 0.3, 0.4 } })
    assert(r == 0.1 and g == 0.2 and b == 0.3 and a == 0.4, "array-shaped color must pass through")
end

do
    local r, g, b, a = GetCustomTextColor({ textCustomColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 } })
    assert(r == 0.1 and g == 0.2 and b == 0.3 and a == 0.4,
        "old profiles store textCustomColor keyed {r=,g=,b=,a=} — feeding its nil [1] into " ..
        "SetTextColor threw 'bad argument #1' on every locked secondary bar update")
end

do
    local r, g, b, a = GetCustomTextColor({ textCustomColor = { 0.1, 0.2, 0.3 } })
    assert(r == 0.1 and g == 0.2 and b == 0.3 and a == 1, "missing alpha defaults to opaque")
end

do
    local r, g, b, a = GetCustomTextColor({})
    assert(r == 1 and g == 1 and b == 1 and a == 1, "missing color falls back to white")
end

do
    local r, g, b, a = GetCustomTextColor({ textCustomColor = true })
    assert(r == 1 and g == 1 and b == 1 and a == 1, "non-table garbage falls back to white")
end

do
    local r, g, b, a = GetCustomTextColor(nil)
    assert(r == 1 and g == 1 and b == 1 and a == 1, "nil config falls back to white")
end

print("OK: resourcebars_text_custom_color_test")
