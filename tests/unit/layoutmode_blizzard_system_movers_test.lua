-- tests/unit/layoutmode_blizzard_system_movers_test.lua
-- Run: lua tests/unit/layoutmode_blizzard_system_movers_test.lua
--
-- Regression guard for simple Blizzard system movers that should use QUI's
-- generic Layout Mode position drawer. The mover must be present in all three
-- wiring paths: Layout Mode element registration, anchoring frame resolution,
-- and shared position-only settings provider registration.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text:gsub("\r\n", "\n")
end

local function blockBetween(source, path, startText, endText)
    local startPos = assert(source:find(startText, 1, true), path .. " missing block start: " .. startText)
    local endPos = assert(source:find(endText, startPos, true), path .. " missing block end: " .. endText)
    return source:sub(startPos, endPos - 1)
end

local layoutUtilsPath = "modules/layout/layoutmode_utils.lua"
local layoutModePath = "modules/layout/layoutmode.lua"
local anchoringPath = "modules/layout/anchoring.lua"
local coreMainPath = "core/main.lua"

local layoutUtils = readFile(layoutUtilsPath)
local layoutMode = readFile(layoutModePath)
local anchoring = readFile(anchoringPath)
local coreMain = readFile(coreMainPath)

local positionProviderBlock = blockBetween(
    layoutUtils,
    layoutUtilsPath,
    "for _, frameKey in ipairs({",
    "        }) do"
)

assert(positionProviderBlock:find('"leaveVehicle"', 1, true),
    "Leave Vehicle must register a position-only settings provider so its mover opens Position controls")
assert(positionProviderBlock:find('"equipmentDurability"', 1, true),
    "Equipment Durability must register a position-only settings provider")

local resolverBlock = blockBetween(
    anchoring,
    anchoringPath,
    "local FRAME_RESOLVERS = {",
    "local CUSTOM_TRACKER_ANCHOR_PREFIX"
)

assert(resolverBlock:find('leaveVehicle = function() return _G["MainMenuBarVehicleLeaveButton"] end', 1, true),
    "Leave Vehicle must resolve to MainMenuBarVehicleLeaveButton")
assert(resolverBlock:find('equipmentDurability = function() return _G["DurabilityFrame"] end', 1, true),
    "Equipment Durability must resolve to DurabilityFrame")

local anchorInfoBlock = blockBetween(
    anchoring,
    anchoringPath,
    "local FRAME_ANCHOR_INFO = {",
    "}\nns.FRAME_ANCHOR_INFO"
)

assert(anchorInfoBlock:find('leaveVehicle    = { displayName = "Leave Vehicle Button"', 1, true),
    "Leave Vehicle must be listed in FRAME_ANCHOR_INFO")
assert(anchorInfoBlock:find('equipmentDurability = { displayName = "Equipment Durability"', 1, true),
    "Equipment Durability must be listed in FRAME_ANCHOR_INFO")

local displayBlock = blockBetween(
    layoutMode,
    layoutModePath,
    "local DISPLAY_ELEMENTS = {",
    "        }\n\n        for _, info in ipairs(DISPLAY_ELEMENTS) do"
)

assert(displayBlock:find('key = "equipmentDurability"', 1, true),
    "Equipment Durability must be registered as a Layout Mode display element")
assert(displayBlock:find('frame = "DurabilityFrame"', 1, true),
    "Equipment Durability must target DurabilityFrame")
assert(layoutMode:find("isInEditMode = true", 1, true)
    and layoutMode:find("isInEditMode = false", 1, true)
    and layoutMode:find("UpdateShownState", 1, true),
    "Equipment Durability preview must use DurabilityFrame.isInEditMode while Layout Mode is open")

local editModeSuppressionBlock = blockBetween(
    coreMain,
    coreMainPath,
    "local _editModeSuppressedFrameNames = {",
    "        }\n\n        -- PartyFrame"
)

assert(editModeSuppressionBlock:find('"MainMenuBarVehicleLeaveButton"', 1, true),
    "Leave Vehicle must stay suppressed in Blizzard Edit Mode")
assert(editModeSuppressionBlock:find('"DurabilityFrame"', 1, true),
    "Equipment Durability must be suppressed in Blizzard Edit Mode")

print("OK: layoutmode_blizzard_system_movers_test")
