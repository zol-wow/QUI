-- tests/unit/inspect_pane_lifecycle_regression_test.lua
-- Run: lua tests/unit/inspect_pane_lifecycle_regression_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local source = readFile("QUI_Skinning/skinning/character_pane/inspect.lua")
local inspectGuildFrame = readFile("tests/framexml/Interface/AddOns/Blizzard_InspectUI/InspectGuildFrame.lua")
local inspectFrame = readFile("tests/framexml/Interface/AddOns/Blizzard_InspectUI/Blizzard_InspectUI.lua")
local paperDollDocs = readFile("tests/api-docs/blizzard/PaperDollInfoDocumentation.lua")

assertContains(
    inspectGuildFrame,
    "InspectGuildFrame_Update();",
    "FrameXML should still call InspectGuildFrame_Update from guild-frame handlers")

assertContains(
    inspectGuildFrame,
    "function InspectGuildFrame_OnShow()",
    "Inspect guild OnShow call site should remain documented in local FrameXML")

assertContains(
    inspectGuildFrame,
    "function InspectGuildFrame_OnEvent(self, event, unit, ...)",
    "Inspect guild INSPECT_READY call site should remain documented in local FrameXML")

assertContains(
    inspectFrame,
    "ShowUIPanel(InspectFrame);\n\t\t\tInspectFrame_UpdateTabs();",
    "FrameXML should still run InspectFrame_UpdateTabs after InspectFrame OnShow during INSPECT_READY")

assertContains(
    paperDollDocs,
    "LiteralName = \"INSPECT_READY\"",
    "API docs should keep INSPECT_READY as the inspect-data readiness signal")

assertContains(
    paperDollDocs,
    "SynchronousEvent = true",
    "API docs should identify INSPECT_READY as synchronous before relying on direct lifecycle ordering")

local guildGuardStart = assert(
    source:find("local function PatchInspectGuildNilGuard()", 1, true),
    "Inspect guild nil guard should exist")
local guildGuardEnd = assert(
    source:find("---------------------------------------------------------------------------\n-- Event frame for inspect-specific events", guildGuardStart, true),
    "Inspect guild nil guard block should end before the event frame")
local guildGuardBlock = source:sub(guildGuardStart, guildGuardEnd)

assertAbsent(
    guildGuardBlock,
    "_G.InspectGuildFrame_Update =",
    "Inspect guild nil guard must not replace Blizzard's global updater")

assertContains(
    guildGuardBlock,
    "InspectGuildFrame:GetScript(\"OnShow\")",
    "Inspect guild nil guard should wrap the documented OnShow call site")

assertContains(
    guildGuardBlock,
    "InspectGuildFrame:GetScript(\"OnEvent\")",
    "Inspect guild nil guard should wrap the documented INSPECT_READY call site")

assertContains(
    guildGuardBlock,
    "InspectGuildFrame:SetScript(\"OnShow\"",
    "Inspect guild nil guard should install an OnShow script wrapper")

assertContains(
    guildGuardBlock,
    "InspectGuildFrame:SetScript(\"OnEvent\"",
    "Inspect guild nil guard should install an OnEvent script wrapper")

assertContains(
    guildGuardBlock,
    "ClearInspectGuildFrame()",
    "Guildless inspect targets should clear stale guild text instead of calling Blizzard's unsafe updater")

local resetStart = assert(
    source:find("local resetBtn = GUI:CreateButton", 1, true),
    "Inspect reset button block should exist")
local resetEnd = assert(
    source:find("resetBtn:SetPoint", resetStart, true),
    "Inspect reset button block should end at reset button placement")
local resetBlock = source:sub(resetStart, resetEnd)

assertAbsent(
    resetBlock,
    "C_Timer.After(0.1",
    "Inspect settings reset should refresh through direct panel show lifecycle, not a blind timer")

local layoutStart = assert(
    source:find("ApplyInspectPaneLayout = function(force)", 1, true),
    "Inspect layout entry point should exist")
local layoutEnd = assert(
    source:find("end\n\n---------------------------------------------------------------------------\n-- Initialize slot overlays for inspect frame", layoutStart, true),
    "Inspect layout block should end before overlay initialization")
local layoutBlock = source:sub(layoutStart, layoutEnd)

assertContains(
    layoutBlock,
    "C_Timer.After(0.1",
    "The retained inspect layout defer should be explicit and guarded by a source-backed comment")

assertContains(
    layoutBlock,
    "FrameXML InspectFrame_OnEvent calls ShowUIPanel(InspectFrame) before InspectFrame_UpdateTabs()",
    "The retained inspect layout defer must document the FrameXML readiness ordering it protects")

print("OK: inspect_pane_lifecycle_regression_test")
