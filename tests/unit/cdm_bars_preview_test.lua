-- tests/unit/cdm_bars_preview_test.lua
-- Run: lua tests/unit/cdm_bars_preview_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    data = data:gsub("\r\n", "\n")
    return data
end

local source = readAll("QUI_CDM/cdm/cdm_bar_renderer.lua")

assert(source:find("function CDMBars.CreateForPreview", 1, true)
    or source:find("CDMBars.CreateForPreview = function", 1, true),
    "CDMBars.CreateForPreview must be defined")

local fnStart = assert(
    source:find("function CDMBars.CreateForPreview", 1, true)
        or source:find("CDMBars.CreateForPreview = function", 1, true),
    "CreateForPreview definition not located")
local fnEnd = assert(source:find("\nend\n", fnStart, true),
    "CreateForPreview must terminate with end")
assert(source:find("CreateBar(parent)", fnStart, true) and
       source:find("CreateBar(parent)", fnStart, true) < fnEnd,
    "CreateForPreview must delegate to the file-local CreateBar")

-- ConfigureBar must remain public (driver depends on it)
assert(source:find("function CDMBars.ConfigureBar", 1, true),
    "CDMBars.ConfigureBar must remain public for the driver to call")

print("OK: cdm_bars_preview_test")
