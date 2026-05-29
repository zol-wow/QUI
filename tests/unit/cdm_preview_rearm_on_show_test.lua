-- tests/unit/cdm_preview_rearm_on_show_test.lua
-- Regression: the CDM live preview tears down on OnHide (so it doesn't burn CPU
-- while hidden), but the options window is HIDDEN (not destroyed) on close and
-- tiles are built once and cached. So when the preview host is shown again --
-- reopening the panel on the CDM page, tabbing back, or reopening the composer
-- -- the torn-down preview must be re-armed. Without a symmetric OnShow handler
-- the preview stays blank until a manual container switch calls RefreshPreview.
-- Run: lua tests/unit/cdm_preview_rearm_on_show_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"), "cannot open " .. path)
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local source = readAll("modules/cdm/settings/composer.lua")

-- Isolate the BuildPreviewSection body: from its declaration up to the
-- forward-declared `local RefreshPreview` that immediately follows it.
local startPos = assert(source:find("local function BuildPreviewSection(", 1, true),
    "BuildPreviewSection must exist in composer.lua")
local afterStart = source:sub(startPos)
local endRel = afterStart:find("\nlocal RefreshPreview", 1, true)
local body = afterStart:sub(1, endRel or #afterStart)

-- Sanity / false-pass guard: the teardown half of the lifecycle must be present.
assert(body:find('SetScript("OnHide"', 1, true),
    "sanity: BuildPreviewSection should tear the live preview down on hide")

-- The fix: a symmetric OnShow re-arm.
assert(body:find('SetScript("OnShow"', 1, true),
    "BuildPreviewSection must re-arm the live preview on show (symmetric to its "
    .. "OnHide teardown); otherwise the preview is blank after the options window "
    .. "is closed and reopened on the CDM page")

assert(body:find("QUI_RefreshCDMPreview", 1, true) or body:find("RefreshPreview", 1, true),
    "the OnShow re-arm must actually refresh the preview")

print("OK: cdm_preview_rearm_on_show_test")
