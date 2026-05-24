-- tests/unit/cdm_composer_uses_preview_driver_test.lua
-- Run: lua tests/unit/cdm_composer_uses_preview_driver_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("modules/cdm/settings/composer.lua")

-- T10: composer.lua delegates to the driver
assert(source:find("ns.CDMComposerPreview.Build", 1, true),
    "composer.lua BuildPreviewSection must call ns.CDMComposerPreview.Build")
assert(source:find("ns.CDMComposerPreview.Refresh", 1, true),
    "composer.lua RefreshPreview must call ns.CDMComposerPreview.Refresh")
assert(source:find("ns.CDMComposerPreview.Teardown", 1, true),
    "composer.lua must call ns.CDMComposerPreview.Teardown on container switch / close")
assert(source:find("ns.CDMComposerPreview.SetScale", 1, true),
    "composer.lua scale slider must call ns.CDMComposerPreview.SetScale")

-- T10: composer.lua exposes the layout/style globals the driver depends on
for _, sym in ipairs({
    "QUI_LayoutCDMPreviewIcons",
    "QUI_StyleCDMPreviewIcons",
    "QUI_LayoutCDMPreviewBars",
    "QUI_GetCDMContainerDB",
}) do
    assert(source:find("_G." .. sym .. " =", 1, true) or source:find(sym .. " = function", 1, true),
        "composer.lua must expose _G." .. sym .. " for the driver")
end

-- T10: the old static-texture preview path is removed (previewIcons[i] no
-- longer holds { tex, border } objects; driver owns the frames now)
assert(not source:find("previewIcons[i] = obj", 1, true),
    "composer.lua must no longer build static preview-icon objects")

print("OK: cdm_composer_uses_preview_driver_test")
