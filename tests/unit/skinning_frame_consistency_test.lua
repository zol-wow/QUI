-- tests/unit/skinning_frame_consistency_test.lua
-- Run: lua tests/unit/skinning_frame_consistency_test.lua

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

-- The skinning engine was relocated into core/uikit.lua (loaded first, exposed as
-- both ns.UIKit and ns.SkinBase); modules/skinning/base.lua is now a thin stub.
-- The shared-widget SkinBase.* definitions this gate checks live in uikit.lua.
local base = readFile("core/uikit.lua")
local professions = readFile("modules/skinning/frames/professions.lua")
local auctionHouse = readFile("modules/skinning/frames/auctionhouse.lua")
local craftingOrders = readFile("modules/skinning/frames/craftingorders.lua")
local instanceFrames = readFile("modules/skinning/frames/instanceframes.lua")

-- SkinBase exposes the shared widget API
for _, fn in ipairs({
    "function SkinBase.SkinButton", "function SkinBase.SkinEditBox",
    "function SkinBase.SkinDropdown", "function SkinBase.SkinScrollRow",
    "function SkinBase.SkinListContainer", "function SkinBase.RefreshWidget",
    "function SkinBase.SkinTab", "function SkinBase.SkinTabGroup",
    "function SkinBase.RefreshTabGroup",
}) do
    assertContains(base, fn, "base.lua must define " .. fn)
end

-- belowChildren backdrop ordering now lives in SkinBase.SkinDropdown
assertContains(base, "bd:SetFrameLevel(math.max(0, dropdown:GetFrameLevel() - 1))",
    "SkinDropdown must support backdrop-below-children ordering for clear-filter controls")

-- All four files adopt the shared helpers and no longer hand-roll stylers
for _, file in ipairs({ auctionHouse, craftingOrders, professions, instanceFrames }) do
    assertContains(file, "SkinBase.SkinButton", "migrated file must use SkinBase.SkinButton")
    assertAbsent(file, "local function StyleButton", "migrated file must not hand-roll StyleButton")
end

-- Professions preserves its three guarded behaviors via SkinBase options
assertContains(professions, "SkinBase.SkinDropdown(recipeList.FilterDropdown, { noStrip = true, belowChildren = true }",
    "Professions filter dropdown must use noStrip + belowChildren to preserve the clear-filter X")
assertContains(professions, "SkinBase.SkinTabGroup(tabs, frame, { hover = true })",
    "Professions main tabs must keep selected-state-aware hover")
assertContains(professions, "SkinBase.SkinTab(tab, owner, { hover = true })",
    "Professions spec pool tabs must keep hover via the shared single-tab helper")
assertAbsent(professions, "local function StyleFilterDropdown",
    "Professions must no longer hand-roll the filter dropdown styler")
assertAbsent(professions, "local function StyleTabSystemTab",
    "Professions must no longer hand-roll the TabSystem tab styler")

-- Instance frames keep the arrow-preserving, inset dropdown treatment
assertContains(instanceFrames, "SkinBase.SkinDropdown(",
    "Instance frame dropdowns must use SkinBase.SkinDropdown")
assertContains(instanceFrames, "keepArrow = true",
    "Instance frame dropdowns must keep the dropdown arrow visible")

print("OK: skinning_frame_consistency_test")
