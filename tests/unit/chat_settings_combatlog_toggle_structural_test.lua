-- tests/unit/chat_settings_combatlog_toggle_structural_test.lua
-- Run: lua tests/unit/chat_settings_combatlog_toggle_structural_test.lua
--
-- The "Show Combat Log Tab" checkbox (Chat sub-page) adds/removes the
-- window-1 combat-log tab entry via ReconcileCombatLogTab, but the tab
-- EDITORS live on a different surface: the Filters sub-page's "Editing tab"
-- dropdown captures its option list at build time. Every other control that
-- mutates the tabs array (Add/Delete Tab, Move, window ops) fires
-- NotifyProviderFor(..., { structural = true }) so all chatFrame1 surfaces
-- rebuild (visible ones now, hidden ones on show via the provider-revision
-- stamp).
--
-- Regression guard: the checkbox onChange only did GetWindowsConfig +
-- TabUI.Rebuild + Refresh — no provider notify, no revision bump — so after
-- deleting the combat-log tab (Filters page) and re-enabling it (checkbox),
-- the Filters page's dropdown never showed the re-added Combat Log entry.

local function readAll(path)
    local f, err = io.open(path, "r")
    assert(f, err)
    local text = f:read("*a")
    f:close()
    return text
end

local src = readAll("QUI_Chat/chat/settings/chat_frame1_provider.lua")

-- Isolate the combat-log checkbox onChange: from the combatLogTab binding to
-- the end of its CreateFormCheckbox call (the description table).
local s = assert(src:find('"combatLogTab", chat.customDisplay', 1, true),
    "combat-log tab checkbox must bind customDisplay.combatLogTab")
local e = assert(src:find("Show Blizzard's Combat Log as a pinned tab", s, true),
    "combat-log tab checkbox description must follow the onChange")
local block = src:sub(s, e)

-- The onChange must keep the live-side work...
assert(block:find("GetWindowsConfig", 1, true),
    "combat-log toggle must reconcile through GetWindowsConfig")
assert(block:find("TabUI.Rebuild", 1, true),
    "combat-log toggle must rebuild the live tab bar")
assert(block:find("Refresh()", 1, true),
    "combat-log toggle must Refresh the chat display")

-- ...AND fire the structural provider notify so the Filters sub-page surface
-- (the tab-selector dropdown and editors) rebuilds with the re-added/removed
-- combat-log entry.
assert(block:find("NotifyProviderFor(", 1, true),
    "combat-log toggle must notify its provider")
assert(block:find("structural = true", 1, true),
    "combat-log toggle notify must be structural (tabs array changed shape)")

print("OK: chat_settings_combatlog_toggle_structural_test")
