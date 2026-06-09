-- tests/unit/chat_settings_master_toggle_reload_prompt_test.lua
-- Run: lua tests/unit/chat_settings_master_toggle_reload_prompt_test.lua
--
-- The chat module's master enable toggle lives on TWO surfaces and both must
-- offer a UI reload, matching every other module master switch:
--   1) the Module Addons tile (moduleAddon_QUI_Chat) — covered by
--      chat_module_toggle_reload_prompt_test.lua;
--   2) the chat SETTINGS page master checkbox ("Enable Chat Module") in
--      chat_frame1_provider.lua — covered here.
--
-- Regression guard: the takeover redesign (commit 2a0c7fd9) rewrote the
-- settings-page toggle as a bare live `Refresh` with no reload prompt, so the
-- two surfaces disagreed — the Module Addons tile prompted, the chat tile did
-- not. The settings-page toggle must Refresh AND prompt for a reload.

local function readAll(path)
    local f, err = io.open(path, "r")
    assert(f, err)
    local text = f:read("*a")
    f:close()
    return text
end

local src = readAll("QUI_Chat/chat/settings/chat_frame1_provider.lua")

-- Isolate the master-toggle section: from its CreateChatSection("chatModule"
-- call to the start of the next section builder.
local s = assert(src:find('CreateChatSection("chatModule"', 1, true),
    "chat master toggle section must exist")
local e = src:find("CreateChatSection(", s + 1, true)
        or src:find("CreateChatCustomSection(", s + 1, true)
        or #src
local block = src:sub(s, e)

-- The "enabled" checkbox must NOT pass a bare Refresh as its onChange — that is
-- the broken state that skipped the reload prompt.
assert(not block:find('"enabled", chat, Refresh', 1, true),
    "master toggle must not use a bare Refresh onChange (no reload prompt)")

-- The "enabled" checkbox onChange must both Refresh (live flip) and prompt.
assert(block:find('"enabled", chat,', 1, true),
    "master toggle must bind the chat.enabled key")
assert(block:find("Refresh()", 1, true),
    "master toggle onChange must still Refresh() for the live flip")
assert(block:find("ShowChatModuleReloadPrompt()", 1, true),
    "master toggle onChange must call ShowChatModuleReloadPrompt() for reload parity")

-- The reload-prompt helper must exist and wire the standard confirm -> reload.
assert(src:find("local function ShowChatModuleReloadPrompt", 1, true),
    "ShowChatModuleReloadPrompt helper must be defined")
local hs = src:find("local function ShowChatModuleReloadPrompt", 1, true)
local helper = src:sub(hs, hs + 600)
assert(helper:find("ShowConfirmation", 1, true),
    "reload prompt must use GUI:ShowConfirmation")
assert(helper:lower():find("reload", 1, true),
    "reload prompt copy must mention a reload")
assert(helper:find("SafeReload", 1, true),
    "reload prompt accept must call SafeReload")

print("OK: chat_settings_master_toggle_reload_prompt_test")
