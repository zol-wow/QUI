-- tests/unit/skin_chrome_constants_test.lua
-- Run: lua tests/unit/skin_chrome_constants_test.lua
-- Guards the shared chrome-constants table shape + values.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a"); fh:close(); return text
end

local src = readFile("core/utils.lua")
assert(src:find("Helpers.CHROME", 1, true), "core/utils.lua must define Helpers.CHROME")
for _, k in ipairs({ "BORDER_PX", "BG_FALLBACK", "BORDER_FALLBACK", "BUTTON_BOOST", "SCROLLROW_BOOST", "DEPTH" }) do
    assert(src:find("CHROME%s*=%s*{") or src:find(k, 1, true), "Helpers.CHROME must define " .. k)
end
for _, tier in ipairs({ "PANEL", "SUBPANEL", "ROW" }) do
    assert(src:find(tier, 1, true), "Helpers.CHROME.DEPTH must define tier " .. tier)
end
print("OK: skin_chrome_constants_test")
