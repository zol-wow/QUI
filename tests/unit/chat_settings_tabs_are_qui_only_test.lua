-- tests/unit/chat_settings_tabs_are_qui_only_test.lua
-- Run: lua tests/unit/chat_settings_tabs_are_qui_only_test.lua
-- Verifies: chat settings expose QUI tabs as the only tab model.

local function readAll(path)
    local f, err = io.open(path, "r")
    assert(f, err)
    local text = f:read("*a")
    f:close()
    return text
end

local src = readAll("QUI_Chat/chat/settings/chat_frame1_provider.lua")

assert(src:find('"customDisplayTabs"', 1, true),
    "Filters preset must edit QUI chat tabs, not a separate stock-tab filter section")
local generalStart = assert(src:find("general = {", 1, true), "general preset must exist")
local generalStop = assert(src:find("filters = {", generalStart, true), "filters preset must follow general preset")
local generalBlock = src:sub(generalStart, generalStop)
assert(not generalBlock:find('"customDisplayTabs"', 1, true),
    "general Chat preset must not embed the Filters tab editor")
assert(src:find('CreateChatCustomSection("customDisplayTabs", "Chat Tabs"', 1, true),
    "QUI tab editor must be labeled as the chat tab settings surface")
assert(src:find("selectedCustomDisplayTabIndex", 1, true),
    "QUI tab editor selection must persist across provider rebuilds")
assert(src:find("_selected = selectedCustomDisplayTabIndex", 1, true),
    "Editing tab dropdown must bind to persistent selected tab state")
assert(not src:find('CreateChatCustomSection("tabFilters"', 1, true),
    "legacy stock-tab filter section must not be rendered")
assert(not src:find("selectedTabFilterFrame", 1, true),
    "settings must not keep a selected stock-tab filter frame")
assert(src:find("#tabs <= 1", 1, true),
    "settings must prevent deleting the final QUI tab")
assert(not src:find("Reset to Blizzard defaults", 1, true),
    "QUI tabs must not offer stock-tab reset controls")

local defaultStart = assert(src:find('CreateChatCustomSection("defaultTab"', 1, true),
    "default tab section must exist")
local defaultStop = src:find("-- Chat Background", defaultStart, true) or #src
local defaultBlock = src:sub(defaultStart, defaultStop)

assert(defaultBlock:find("GetWindowTabs", 1, true),
    "default tab dropdown must source options from QUI window tabs")
assert(not defaultBlock:find("buildFrameOptions", 1, true),
    "default tab dropdown must not source options from stock chat frames")
assert(not defaultBlock:find("GetChatWindowInfo", 1, true),
    "default tab dropdown must not inspect stock chat frame names")

print("OK: chat_settings_tabs_are_qui_only_test")
