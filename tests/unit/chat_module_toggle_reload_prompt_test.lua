-- tests/unit/chat_module_toggle_reload_prompt_test.lua
-- Run: lua tests/unit/chat_module_toggle_reload_prompt_test.lua
--
-- The Modules-page "Chat Engine" toggle must require a UI reload and pop the
-- standard confirmation on enable/disable, exactly like the unit-frames and
-- group-frames module toggles in the same onboarding file. Guards against the
-- chat entry silently reverting to the no-prompt MakeSubtableEntry path.

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

-- Mock the settings Registry + Schema the onboarding file registers into.
local features = {}
local Registry = {
    GetFeature = function(_, id) return features[id] end,
    RegisterFeature = function(_, spec) features[spec.id] = spec; return spec end,
}
local Schema = { Feature = function(def) return def end }

local ns = { Settings = { Registry = Registry, Schema = Schema } }

-- _G.QUI surface the chat entry touches: profile DB, GUI confirmation, reload.
local confirmCalls = {}
local refreshCalls = 0
local reloadCalls = 0
_G.QUI = {
    db = { profile = { chat = { enabled = true } }, char = {} },
    GUI = { ShowConfirmation = function(_, opts) confirmCalls[#confirmCalls + 1] = opts end },
    SafeReload = function() reloadCalls = reloadCalls + 1 end,
}
_G.QUI_RefreshChat = function() refreshCalls = refreshCalls + 1 end
ns.QUI_Modules = { NotifyChanged = function() end }

assert(loadfile("core/settings/content/modules_nonvisual_onboarding.lua"))("QUI", ns)

local chat = features["chat"]
check("chat feature registered", chat ~= nil)
local entry = chat and chat.moduleEntry
check("chat moduleEntry present", entry ~= nil, "no moduleEntry on chat feature")
if not entry then
    print(("\n%d failure(s)"):format(failures))
    os.exit(1)
end

check("isEnabled reflects db (true by default)", entry.isEnabled() == true)

-- Disable: writes the DB, runs the live refresh, AND prompts for reload.
entry.setEnabled(false)
check("disable writes db.enabled=false", _G.QUI.db.profile.chat.enabled == false)
check("disable runs QUI_RefreshChat (live teardown)", refreshCalls >= 1)
check("disable shows reload confirmation", #confirmCalls == 1,
    ("expected 1 confirmation, got %d"):format(#confirmCalls))
check("confirmation message mentions reload",
    confirmCalls[1] and tostring(confirmCalls[1].message):lower():find("reload") ~= nil,
    confirmCalls[1] and confirmCalls[1].message or "nil")

-- Accept -> SafeReload, like the sibling modules.
if confirmCalls[1] and type(confirmCalls[1].onAccept) == "function" then
    confirmCalls[1].onAccept()
end
check("accepting the prompt calls SafeReload", reloadCalls == 1)

-- Re-enable: prompts again.
entry.setEnabled(true)
check("enable writes db.enabled=true", _G.QUI.db.profile.chat.enabled == true)
check("enable shows reload confirmation", #confirmCalls == 2,
    ("expected 2 confirmations, got %d"):format(#confirmCalls))

-- Toggling to the current value is a no-op: no extra prompt.
entry.setEnabled(true)
check("no prompt when value unchanged", #confirmCalls == 2,
    ("expected 2 confirmations, got %d"):format(#confirmCalls))

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
