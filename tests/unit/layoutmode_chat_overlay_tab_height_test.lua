-- tests/unit/layoutmode_chat_overlay_tab_height_test.lua
-- Run: lua tests/unit/layoutmode_chat_overlay_tab_height_test.lua
--
-- Regression guard: the Layout Mode mover for every QUI chat window must grow
-- upward far enough to cover the custom chat tab row. The inset logic lives
-- in the shared SetupChatWindowOverlay factory; the primary chatFrame1
-- element and the dynamic windows 2+ elements must both delegate to it with
-- their own tab-bar getters.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a")
    f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/layout/layoutmode.lua")

-- Shared factory: owns the tab-row inset + top-edge offset.
local factoryPos = assert(source:find("local function SetupChatWindowOverlay(", 1, true),
    "shared chat overlay factory must exist")
local chatElemPos = assert(source:find('key = "chatFrame1"', factoryPos, true),
    "chatFrame1 layout element must exist after the factory")
local factoryBlock = source:sub(factoryPos, chatElemPos - 1)

assert(factoryBlock:find("getTabBar and getTabBar()", 1, true),
    "chat mover overlay must inspect the window's tab bar")
assert(factoryBlock:find("extraTop = h", 1, true),
    "chat mover overlay must include the tab bar height")
assert(factoryBlock:find('overlay:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -4,  4 + extraTop)', 1, true),
    "chat mover top edge must be offset by tab bar height")

-- Primary element delegates to the factory with the named (window 1) tab bar.
local endPos = assert(source:find("onOpen = function()", chatElemPos, true),
    "chatFrame1 layout element must define onOpen after setupOverlay")
local chatBlock = source:sub(chatElemPos, endPos - 1)

assert(chatBlock:find("SetupChatWindowOverlay(overlay, frame", 1, true),
    "chatFrame1 setupOverlay must delegate to the shared factory")
assert(chatBlock:find("_G.QUI_CustomChatTabBar", 1, true),
    "chatFrame1 must pass the primary tab bar to the factory")

-- Dynamic windows 2+ delegate too, with their own (unnamed) bars via TabUI.
local syncPos = assert(source:find("function um:SyncChatWindowElements()", 1, true),
    "per-window chat mover sync must exist")
local syncBlock = source:sub(syncPos)

assert(syncBlock:find("SetupChatWindowOverlay(overlay, frame", 1, true),
    "windows 2+ setupOverlay must delegate to the shared factory")
assert(syncBlock:find("TabUI.GetBar(windowID)", 1, true),
    "windows 2+ must pass their own tab bar to the factory")

print("OK: layoutmode_chat_overlay_tab_height_test")
