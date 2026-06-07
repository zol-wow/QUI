-- tests/unit/character_module_disabled_native_fallback_test.lua
-- Run: lua tests/unit/character_module_disabled_native_fallback_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local characterFrameSkin = readFile("QUI_Skinning/skinning/frames/character.lua")
local inspectFrameSkin = readFile("QUI_Skinning/skinning/frames/inspect.lua")
local inspectPane = readFile("QUI_Skinning/skinning/character_pane/inspect.lua")

local hideStart = assert(
    characterFrameSkin:find("local function HideBlizzardDecorations()", 1, true),
    "Character frame skin should have a decoration-hiding helper")
local hideEnd = assert(
    characterFrameSkin:find("-- API: Set background extended mode", hideStart, true),
    "Character frame skin helper should precede the background API")
local hideBlock = characterFrameSkin:sub(hideStart, hideEnd)

assertContains(
    characterFrameSkin,
    "local function IsCharacterPaneEnabled()",
    "Frame skinning must know whether the QUI character pane replacement is enabled")

assertContains(
    characterFrameSkin,
    "local function RestoreNativeStatsPane()",
    "Frame skinning must be able to restore Blizzard's native stats pane when the replacement is disabled")

assertContains(
    hideBlock,
    "if IsCharacterPaneEnabled() then",
    "CharacterFrame skin must only mask Blizzard's native stats pane when the QUI stats replacement is enabled")

assertContains(
    hideBlock,
    "RestoreNativeStatsPane()",
    "CharacterFrame skin must leave native stats visible when the QUI character module is disabled")

assertContains(
    inspectFrameSkin,
    "settings.enabled == false",
    "Inspect frame skin background extension must honor the master character module toggle")

assertContains(
    inspectPane,
    "local function IsCharacterModuleEnabled(settings)",
    "Inspect overlay module must treat character.enabled as the master gate")

local hookStart = assert(
    inspectPane:find("local function HookInspectFrame()", 1, true),
    "Inspect overlay hook function should exist")
local hookEnd = assert(
    inspectPane:find('InspectFrame:HookScript("OnShow"', hookStart, true),
    "Inspect OnShow hook should be installed after the module gate")
local hookGateBlock = inspectPane:sub(hookStart, hookEnd)

assertContains(
    hookGateBlock,
    "if not IsCharacterModuleEnabled(settings) then return end",
    "Inspect overlay hooks must not install when the QUI character module is disabled")

local updateStart = assert(
    inspectPane:find("local function UpdateInspectFrame()", 1, true),
    "Inspect update function should exist")
local updateEnd = assert(
    inspectPane:find("-- Hook inspect frame", updateStart, true),
    "Inspect update function should precede the hook section")
local updateBlock = inspectPane:sub(updateStart, updateEnd)

assertContains(
    updateBlock,
    "if not IsCharacterModuleEnabled(settings) then",
    "Inspect update path must hide QUI-owned overlays when the master module is disabled")

assertContains(
    updateBlock,
    "HideDetailedOverlays()",
    "Disabled character module must hide detailed inspect overlays")

assertContains(
    updateBlock,
    "HideLiteDisplays()",
    "Disabled character module must hide lite inspect overlays")

local rosterStart = assert(
    inspectPane:find("RefreshInspectUnitAfterRosterUpdate = function()", 1, true),
    "Inspect roster refresh helper should exist")
local rosterEnd = assert(
    inspectPane:find("RefreshCurrentInspectGUID = function", rosterStart, true),
    "Inspect roster refresh helper should precede GUID refresh helper")
local rosterBlock = inspectPane:sub(rosterStart, rosterEnd)

assertContains(
    rosterBlock,
    "if not IsCharacterModuleEnabled(GetSettings()) then return false end",
    "Inspect roster refresh must not rewrite InspectFrame state when the character module is disabled")

print("OK: character_module_disabled_native_fallback_test")
