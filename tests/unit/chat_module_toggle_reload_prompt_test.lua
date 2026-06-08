-- tests/unit/chat_module_toggle_reload_prompt_test.lua
-- Run: lua tests/unit/chat_module_toggle_reload_prompt_test.lua
--
-- The chat module switch lives on the Module Addons row (moduleAddon_QUI_Chat)
-- — the legacy "Chat Engine" onboarding row was deleted in the module-toggle
-- consolidation. The row must AND-read the dormant-guard flag (chat.enabled)
-- with the addon enable state, heal/clear the flag on toggle, and pop the
-- standard reload confirmation (QUI_Chat is login-class, so both enable and
-- disable return "reload" from the loader).

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

-- Mock the settings Registry + Schema the Module Addons file registers into.
local features = {}
local Registry = {
    GetFeature = function(_, id) return features[id] end,
    RegisterFeature = function(_, spec) features[spec.id] = spec; return spec end,
}
local Schema = { Feature = function(def) return def end }

local ns = { Settings = { Registry = Registry, Schema = Schema } }

-- _G.QUI surface the row touches: profile DB, GUI confirmation, reload.
local confirmCalls = {}
local reloadCalls = 0
_G.QUI = {
    db = { profile = { chat = { enabled = true } }, char = {} },
    GUI = { ShowConfirmation = function(_, opts) confirmCalls[#confirmCalls + 1] = opts end },
    SafeReload = function() reloadCalls = reloadCalls + 1 end,
}
ns.QUI_Modules = { NotifyChanged = function() end }

-- Real manifest (source of truth for the QUI_Chat legacyFlag wiring).
assert(loadfile("core/addon_manifest.lua"))("QUI", ns)

-- Mocked loader: track Set calls, controllable addon-enabled state.
local addonEnabled = { QUI_Chat = true }
local setCalls = {}
ns.AddonLoader = {
    IsModuleAddonEnabled = function(folder)
        return addonEnabled[folder] == true
    end,
    SetModuleAddonEnabled = function(folder, on)
        setCalls[#setCalls + 1] = { folder = folder, on = on }
        addonEnabled[folder] = on
        return "reload"  -- login-class addon: both directions need a reload
    end,
}

assert(loadfile("core/settings/content/module_addons_content.lua"))("QUI", ns)

local chat = features["moduleAddon_QUI_Chat"]
check("Module Addons chat feature registered", chat ~= nil)
local entry = chat and chat.moduleEntry
check("chat moduleEntry present", entry ~= nil, "no moduleEntry on moduleAddon_QUI_Chat")
if not entry then
    print(("\n%d failure(s)"):format(failures))
    os.exit(1)
end

-- AND-read: addon on + flag true → on.
check("isEnabled true when addon on and flag true", entry.isEnabled() == true)

-- AND-read: dormant-guard flag false → row shows OFF even with the addon on.
_G.QUI.db.profile.chat.enabled = false
check("isEnabled false when dormant-guard flag is false", entry.isEnabled() == false)
_G.QUI.db.profile.chat.enabled = true

-- Disable: clears the flag, disables the addon, prompts for reload.
entry.setEnabled(false)
check("disable writes chat.enabled=false", _G.QUI.db.profile.chat.enabled == false)
check("disable routes through SetModuleAddonEnabled(QUI_Chat,false)",
    #setCalls == 1 and setCalls[1].folder == "QUI_Chat" and setCalls[1].on == false)
check("disable shows reload confirmation", #confirmCalls == 1,
    ("expected 1 confirmation, got %d"):format(#confirmCalls))
check("confirmation message mentions reload",
    confirmCalls[1] and tostring(confirmCalls[1].message):lower():find("reload") ~= nil,
    confirmCalls[1] and confirmCalls[1].message or "nil")

-- Accept -> SafeReload, like every other module-level prompt.
if confirmCalls[1] and type(confirmCalls[1].onAccept) == "function" then
    confirmCalls[1].onAccept()
end
check("accepting the prompt calls SafeReload", reloadCalls == 1)

-- Re-enable: heals the dormant-guard flag and prompts again.
entry.setEnabled(true)
check("enable heals chat.enabled=true", _G.QUI.db.profile.chat.enabled == true)
check("enable routes through SetModuleAddonEnabled(QUI_Chat,true)",
    #setCalls == 2 and setCalls[2].on == true)
check("enable shows reload confirmation", #confirmCalls == 2,
    ("expected 2 confirmations, got %d"):format(#confirmCalls))

-- Already-loaded path (Fix 1): when the loader returns "loaded" (addon code is
-- present) but the dormant-guard flag was false, the module cannot have activated
-- (its init checks the flag at load time).  The row must still prompt for a reload.
-- Rebuild the feature with a loader stub that always returns "loaded".
do
    local features2 = {}
    local Registry2 = {
        RegisterFeature = function(_, spec) features2[spec.id] = spec; return spec end,
    }
    local Schema2 = { Feature = function(def) return def end }
    local ns2 = {
        Settings = { Registry = Registry2, Schema = Schema2 },
        QUI_Modules = { NotifyChanged = function() end },
    }
    assert(loadfile("core/addon_manifest.lua"))("QUI", ns2)
    local setCalls2 = {}
    ns2.AddonLoader = {
        IsModuleAddonEnabled = function() return true end,
        SetModuleAddonEnabled = function(folder, on)
            setCalls2[#setCalls2 + 1] = { folder = folder, on = on }
            return "loaded"  -- simulate: addon is already present in memory
        end,
    }
    assert(loadfile("core/settings/content/module_addons_content.lua"))("QUI", ns2)
    local entry2 = features2["moduleAddon_QUI_Chat"] and features2["moduleAddon_QUI_Chat"].moduleEntry
    check("already-loaded path: feature registered", entry2 ~= nil)
    if entry2 then
        -- Guard flag was explicitly false (dormant); addon code loaded but init skipped.
        _G.QUI.db.profile.chat.enabled = false
        local confirmsBefore = #confirmCalls
        entry2.setEnabled(true)
        check("already-loaded + flag-was-false: flag healed to true",
            _G.QUI.db.profile.chat.enabled == true)
        check("already-loaded + flag-was-false: reload prompt shown",
            #confirmCalls == confirmsBefore + 1,
            ("expected %d confirmations, got %d"):format(confirmsBefore + 1, #confirmCalls))
        -- Sanity: flag was already true before enable → "loaded" → no prompt.
        _G.QUI.db.profile.chat.enabled = true
        local confirmsAfterHeal = #confirmCalls
        entry2.setEnabled(true)
        check("already-loaded + flag-was-true: no redundant reload prompt",
            #confirmCalls == confirmsAfterHeal,
            ("expected no new confirmation, got %d total"):format(#confirmCalls))
    end
end

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
