-- tests/character_pane_bottom_tab_anchoring_test.lua
-- Run: lua tests/character_pane_bottom_tab_anchoring_test.lua

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

local source = readFile("modules/skinning/character_pane/character.lua")

assertContains(
    source,
    "local function AnchorCharacterFrameBottomTabs(firstTabYOffset)",
    "Character pane must centralize bottom tab anchoring")

assertContains(
    source,
    "CharacterFrameTab2:SetPoint(\"TOPLEFT\", CharacterFrameTab1, \"TOPRIGHT\", -5, 0)",
    "CharacterFrameTab2 must be reattached to CharacterFrameTab1 after the first tab moves")

assertContains(
    source,
    "CharacterFrameTab3:SetPoint(\"TOPLEFT\", CharacterFrameTab2, \"TOPRIGHT\", -5, 0)",
    "CharacterFrameTab3 must be reattached to CharacterFrameTab2 after the first tab moves")

local adjustStart = assert(
    source:find("local function AdjustForNonCharacterTab()", 1, true),
    "AdjustForNonCharacterTab should exist")
local adjustEnd = assert(
    source:find("local function RestoreCharacterTabPositions()", adjustStart, true),
    "RestoreCharacterTabPositions should follow AdjustForNonCharacterTab")
local adjustBlock = source:sub(adjustStart, adjustEnd)
assertContains(
    adjustBlock,
    "AnchorCharacterFrameBottomTabs(2)",
    "Non-character tabs must move the whole bottom tab chain up")

local restoreEnd = assert(
    source:find("-- Helper to hide all custom elements", adjustEnd, true),
    "HideCustomElements marker should follow RestoreCharacterTabPositions")
local restoreBlock = source:sub(adjustEnd, restoreEnd)
assertContains(
    restoreBlock,
    "AnchorCharacterFrameBottomTabs(-48)",
    "Character tab must move the whole bottom tab chain to the extended pane position")

assertAbsent(
    source,
    "pendingTabMode",
    "Bottom tab reanchoring must not be queued behind combat lockdown")

print("OK: character_pane_bottom_tab_anchoring_test")
