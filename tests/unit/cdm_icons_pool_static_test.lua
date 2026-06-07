-- tests/unit/cdm_icons_pool_static_test.lua
-- Run: lua tests/unit/cdm_icons_pool_static_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local icons = readAll("QUI_CDM/cdm/cdm_icon_renderer.lua")
local factory = readAll("QUI_CDM/cdm/cdm_icon_factory.lua")

assert(not icons:find("function CDMIcons:GetIconPool", 1, true),
    "CDMIcons should not expose icon pool lookup")
assert(not icons:find("function CDMIcons:EnsurePool", 1, true),
    "CDMIcons should not expose icon pool creation")
assert(not icons:find("function CDMIcons:ClearPool", 1, true),
    "CDMIcons should not expose icon pool release")
assert(factory:find("function CDMIconFactory:GetIconPool", 1, true),
    "CDMIconFactory compatibility surface should own icon pool lookup inside cdm_icon_factory.lua")
assert(factory:find("function CDMIconFactory:EnsurePool", 1, true),
    "CDMIconFactory compatibility surface should own icon pool creation inside cdm_icon_factory.lua")
assert(factory:find("function CDMIconFactory:ClearPool", 1, true),
    "CDMIconFactory compatibility surface should own icon pool release inside cdm_icon_factory.lua")
assert(factory:find("wipe(pool)", factory:find("function CDMIconFactory:ClearPool", 1, true), true),
    "ClearPool should wipe and reuse the existing viewer pool table instead of replacing it")
assert(icons:find("BuildIconListSignature", 1, true),
    "BuildIcons should compute a stable icon list signature")
assert(icons:find("_lastBuildSignature", 1, true),
    "BuildIcons should store the last icon list signature on the container")
assert(icons:find("_lastBuildPool", 1, true),
    "BuildIcons should keep the last unchanged pool for signature hits")
assert(icons:find("_assignedRow", icons:find("local function AppendEntrySignature", 1, true), true),
    "BuildIcons signature must include assigned rows so spec/loadout restores rebind icons when only row placement changes")

print("OK: cdm_icons_pool_static_test")
