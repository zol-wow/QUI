-- tests/unit/actionbars_owned_dispatch_purge_test.lua
-- Run: lua tests/unit/actionbars_owned_dispatch_purge_test.lua
--
-- QUI-owned action buttons must never sit in Blizzard's shared
-- ActionBarActionEventsFrame.frames registry: one addon-created (tainted)
-- entry taints the rest of the pairs() dispatch loop, and every suppressed
-- original Blizzard button visited afterwards runs Update -> SetCooldown
-- under taint and errors on secret cooldown values in combat.
-- Registration into that registry happens lazily inside Blizzard's
-- ActionBarActionButtonMixin:Update() whenever a button holds an action,
-- so the purge must both sweep at build time and re-purge on RegisterFrame.

local actionBarsDB = {
    enabled = true,
    global = {},
    bars = {},
}

local function noop() end

local frameMT
local function NewFrame()
    local frame = {
        attributes = {},
        scripts = {},
        frameRefs = {},
        shown = false,
        frameLevel = 1,
    }
    frameMT = frameMT or {
        __index = function(t, key)
            if key == "SetAttribute" then
                return function(self, name, value)
                    self.attributes[name] = value
                end
            elseif key == "GetAttribute" then
                return function(self, name)
                    return self.attributes[name]
                end
            elseif key == "SetScript" then
                return function(self, script, handler)
                    self.scripts[script] = handler
                end
            elseif key == "GetScript" then
                return function(self, script)
                    return self.scripts[script]
                end
            elseif key == "SetFrameRef" then
                return function(self, name, ref)
                    self.frameRefs[name] = ref
                end
            elseif key == "GetFrameRef" then
                return function(self, name)
                    return self.frameRefs[name]
                end
            elseif key == "Show" then
                return function(self)
                    self.shown = true
                end
            elseif key == "Hide" then
                return function(self)
                    self.shown = false
                end
            elseif key == "IsShown" then
                return function(self)
                    return self.shown
                end
            elseif key == "GetParent" then
                return function(self)
                    return self.parent
                end
            elseif key == "SetParent" then
                return function(self, parent)
                    self.parent = parent
                end
            elseif key == "CreateTexture" or key == "CreateFontString" then
                return function()
                    return NewFrame()
                end
            end
            return noop
        end,
    }
    return setmetatable(frame, frameMT)
end

UIParent = NewFrame()
SlashCmdList = {}
BINDING_HEADER_QUI_ACTIONBARS = ""
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_ID = WOW_PROJECT_MAINLINE
RANGE_INDICATOR = ""

function GetBuildInfo()
    return "12.0.5", "66562", "May 1 2026", 120005
end

local function templateOnShow() end
local function templateOnHide() end

function CreateFrame(_, _, parent)
    local frame = NewFrame()
    frame.parent = parent
    frame.scripts.OnShow = templateOnShow
    frame.scripts.OnHide = templateOnHide
    return frame
end

function InCombatLockdown() return false end
function GetTime() return 1 end
function HasAction(action) return action and action > 0 end
function RegisterStateDriver() end
function UnregisterStateDriver() end
function LibStub() return nil end
function GetCVar() return "0" end

-- Functional table-method form so the RegisterFrame purge hook really runs;
-- the global-name form (used elsewhere at chunk load) stays a no-op.
function hooksecurefunc(target, name, hook)
    if type(target) ~= "table" then return end
    local orig = target[name]
    target[name] = function(...)
        orig(...)
        hook(...)
    end
end

C_Timer = {
    After = function(_, callback)
        if callback then callback() end
    end,
}

-- Fake Blizzard shared dispatch registries (ActionButton.lua mixins).
ActionBarButtonEventsFrame = { frames = {} }
ActionBarActionEventsFrame = { frames = {} }
function ActionBarActionEventsFrame:RegisterFrame(frame)
    self.frames[frame] = frame
end
function ActionBarActionEventsFrame:UnregisterFrame(frame)
    self.frames[frame] = nil
end

local ns = {
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
    Helpers = {
        GetCore = function() return {} end,
        CreateDBGetter = function()
            return function()
                return actionBarsDB
            end
        end,
        CreateStateTable = function()
            local state = setmetatable({}, { __mode = "k" })
            local function get(frame)
                local entry = state[frame]
                if not entry then
                    entry = {}
                    state[frame] = entry
                end
                return entry
            end
            return state, get
        end,
        SafeToNumber = function(value, fallback)
            return type(value) == "number" and value or fallback
        end,
        SafeValue = function(value, fallback)
            return value == nil and fallback or value
        end,
        IsSecretValue = function()
            return false
        end,
        IsEditModeShown = function()
            return false
        end,
    },
    LSM = {
        Fetch = function() return nil end,
    },
}

setmetatable(_G, {
    __index = function(_, key)
        -- Button-name lookups must be nil-able or the create branch of
        -- EnsureOwnedActionButton never runs.
        if key:match("^QUI_Bar%d") then
            return nil
        end
        local cTable = key:match("^C_[A-Z].*")
        if cTable then
            local tbl = setmetatable({}, {
                __index = function()
                    return noop
                end,
            })
            rawset(_G, key, tbl)
            return tbl
        end
        return noop
    end,
})

assert(loadfile("QUI_ActionBars/actionbars/actionbars_env.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_helpers.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_layout.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_builder.lua"))("QUI", ns)

local env = ns.ActionBarsEnv
local dispatcher = _G.ActionBarActionEventsFrame
local container = NewFrame()

-- Reuse path: a button left registered from before the purge existed is
-- swept out when the bars rebuild.
local staleOwned = NewFrame()
_G.QUI_Bar3Button2 = staleOwned
dispatcher:RegisterFrame(staleOwned)
assert(dispatcher.frames[staleOwned] ~= nil, "sanity: stale owned button registered")

local function laterHookedOnShow() end
staleOwned.scripts.OnShow = laterHookedOnShow

local reusedBtn = env.EnsureOwnedActionButton(container, "bar3", "QUI_Bar3Button2", 2)
assert(reusedBtn == staleOwned, "sanity: reuse branch must return the existing frame")
assert(dispatcher.frames[staleOwned] == nil,
    "EnsureOwnedActionButton must sweep reused owned buttons out of ActionBarActionEventsFrame.frames")
assert(staleOwned.scripts.OnShow == laterHookedOnShow,
    "the reuse branch must not touch script handlers hooked after creation")

-- Create path + lazy re-registration: Blizzard's Update() re-registers a
-- button whenever it holds an action; the hook must purge it immediately.
local createdBtn = env.EnsureOwnedActionButton(container, "bar3", "QUI_Bar3Button1", 1)
assert(createdBtn ~= nil, "sanity: create branch must return a button")
assert(createdBtn.scripts.OnShow == nil,
    "the create branch must clear the template's OnShow handler")
assert(createdBtn.scripts.OnHide == nil,
    "the create branch must clear the template's OnHide handler")

dispatcher:RegisterFrame(createdBtn)
assert(dispatcher.frames[createdBtn] == nil,
    "RegisterFrame on an owned button must be purged by the standing hook")

dispatcher:RegisterFrame(staleOwned)
assert(dispatcher.frames[staleOwned] == nil,
    "RegisterFrame on a reused owned button must be purged by the standing hook")

-- Blizzard's own (secure) buttons must keep registering normally.
local blizzButton = NewFrame()
dispatcher:RegisterFrame(blizzButton)
assert(dispatcher.frames[blizzButton] == blizzButton,
    "non-owned buttons must stay registered in ActionBarActionEventsFrame.frames")

print("OK: actionbars_owned_dispatch_purge_test")
