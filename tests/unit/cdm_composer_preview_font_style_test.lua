-- tests/unit/cdm_composer_preview_font_style_test.lua
-- Run: lua tests/unit/cdm_composer_preview_font_style_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local source = readAll("modules/cdm/settings/composer.lua")

local rowsStart = assert(source:find("local function ReadPreviewConfigValue", 1, true),
    "preview row config helper must exist")
local buildRowsStart = assert(source:find("local function BuildPreviewRows", rowsStart, true),
    "BuildPreviewRows helper must exist")
local rowsEnd = assert(source:find("-- SORT_PREVIEW_ENTRIES", rowsStart, true),
    "preview row config section terminator must exist")
local rowsBody = source:sub(rowsStart, rowsEnd)

assert(rowsBody:find("ApplyPreviewIconTextConfig", buildRowsStart - rowsStart + 1, true),
    "BuildPreviewRows must apply the preview icon text config helper")

for _, fieldName in ipairs({
    "durationFont",
    "stackFont",
    "durationSize",
    "stackSize",
    "durationTextColor",
    "stackTextColor",
    "hideDurationText",
    "hideStackText",
}) do
    assert(rowsBody:find(fieldName, 1, true),
        "BuildPreviewRows must carry " .. fieldName ..
        " into preview row config so the renderer applies font settings")
end

local styleStart = assert(source:find("local function StylePreviewIconsImpl", 1, true),
    "StylePreviewIconsImpl helper must exist")
local styleEnd = assert(source:find("-- LayoutPreviewBarsImpl", styleStart, true),
    "StylePreviewIconsImpl section terminator must exist")
local styleBody = source:sub(styleStart, styleEnd)

assert(styleBody:find("OnIconRowConfigApplied", 1, true),
    "StylePreviewIconsImpl must pass each preview icon through " ..
    "CDMIcons.OnIconRowConfigApplied so duration/stack font settings match")

print("OK: cdm_composer_preview_font_style_test")
