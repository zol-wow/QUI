-- tests/unit/options_provider_rebuild_on_show_test.lua
-- Regression: re-showing an options provider surface (a settings subpage) must
-- NOT tear down and fully rebuild it when nothing changed while it was hidden.
-- The OnShow hook used to schedule a full ClearHost + provider.build on every
-- show -- the CreateFrame storm that froze the client on every settings tab
-- switch. A rebuild on show must happen only when the provider's data actually
-- changed since the surface was last built (e.g. an edit on another tab).
-- Run: lua tests/unit/options_provider_rebuild_on_show_test.lua

-- Headless WoW-ish stubs --------------------------------------------------
local timers = {}
_G.C_Timer = {
    After = function(delay, fn)
        timers[#timers + 1] = fn
    end,
}
local function flushTimers()
    local guard = 0
    while #timers > 0 and guard < 100 do
        guard = guard + 1
        local pending = timers
        timers = {}
        for _, fn in ipairs(pending) do fn() end
    end
end

_G.geterrorhandler = function() return function(err) error(tostring(err)) end end
_G.QUI = { GUI = {} } -- no TeardownFrameTree/CleanupWidgetTree -> ClearHost uses child loop

local buildCount = 0
local fakeProvider = {
    build = function(_parent, _key, _width, _opts)
        buildCount = buildCount + 1
        return 120
    end,
}

local ns = {
    Settings = {
        Providers = {
            Get = function(_, key)
                return key == "foo" and fakeProvider or nil
            end,
        },
    },
}

assert(loadfile("core/settings_builders.lua"))("QUI", ns)
local SB = ns.SettingsBuilders
assert(type(SB.BuildProvider) == "function", "SettingsBuilders must expose BuildProvider")
assert(type(SB.NotifyProviderChanged) == "function", "SettingsBuilders must expose NotifyProviderChanged")

-- A minimal options-body frame stub. ----------------------------------------
local function NewBody()
    local body = { _scripts = {}, _visible = true, _height = 80 }
    function body:HookScript(name, fn) self._scripts[name] = fn end
    function body:IsVisible() return self._visible end
    function body:GetWidth() return 400 end
    function body:GetHeight() return self._height end
    function body:SetHeight(h) self._height = h end
    function body:GetChildren() return end
    function body:GetRegions() return end
    function body:SetParent() end
    function body:Hide() end
    function body:GetParent() return nil end
    return body
end

local body = NewBody()

-- Initial build of the subpage.
SB.BuildProvider("foo", body, 400, {})
assert(buildCount == 1, "expected exactly one build on first render, got " .. buildCount)
assert(type(body._scripts.OnShow) == "function", "BuildProvider must install an OnShow hook")
assert(type(body._scripts.OnHide) == "function", "BuildProvider must install an OnHide hook")

-- First show after build: the deferred post-show refresh is intentionally
-- preserved (some providers finalize width-dependent layout on it), so this
-- one rebuild is expected.
body._scripts.OnShow(body)
flushTimers()
assert(buildCount == 2,
    "first show after build should run the one-time post-show refresh (got " .. buildCount .. ")")

-- Re-show with NO intervening change: must NOT rebuild. This is the every-tab-
-- switch case that used to freeze the client.
body._scripts.OnShow(body)
flushTimers()
assert(buildCount == 2,
    "re-showing an unchanged, already-shown subpage must not rebuild it (rose to " .. buildCount .. ")")

-- Hide it (unregisters the live surface), then change the provider while hidden.
body._scripts.OnHide(body)
SB.NotifyProviderChanged("foo")
flushTimers()
assert(buildCount == 2, "a change while hidden must not rebuild the hidden surface, got " .. buildCount)

-- Now show it again: because the provider changed while hidden, it must rebuild.
body._scripts.OnShow(body)
flushTimers()
assert(buildCount == 3,
    "showing a subpage after a change-while-hidden must rebuild it once (got " .. buildCount .. ")")

-- Show yet again with no further change: must not rebuild.
body._scripts.OnShow(body)
flushTimers()
assert(buildCount == 3,
    "re-showing an unchanged (already caught-up) subpage must not rebuild it (got " .. buildCount .. ")")

print("OK: options_provider_rebuild_on_show_test")
