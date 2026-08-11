-- tests/unit/actionbars_unit_aura_secret_boundary_test.lua
-- Run: lua tests/unit/actionbars_unit_aura_secret_boundary_test.lua
--
-- Wave 2 Task 7 (H4): ownedEventFrame registers UNIT_AURA player-only
-- (RegisterUnitEvent("UNIT_AURA", "player"),
-- QUI_ActionBars/actionbars/actionbars_public.lua:75) — the C-level filter
-- already guarantees OnOwnedEvent's UNIT_AURA branch only ever fires for the
-- player unit. The actual dispatch/guard logic is NOT in actionbars_public
-- .lua (which only registers the event inside Initialize()); it lives in the
-- sibling chunk QUI_ActionBars/actionbars/actionbars_events.lua (OnOwnedEvent,
-- the UNIT_AURA branch around :611-618), which pre-fix additionally compared
-- the payload `unit` against the literal string "player".
--
-- PTR 68569 marks the whole UNIT_AURA event SecretWhenAurasRestricted, so in
-- combat/encounter/challenge/PvP the payload unit may arrive as an opaque
-- secret value. tests/helpers/secret_sentinel.lua CAVEAT 1 documents that a
-- secret-vs-string `==` compare is a cross-type comparison in Lua 5.1: it
-- does NOT throw, it silently evaluates to `false`. So the old guard didn't
-- crash under restriction — it silently dropped ScheduleABCountUpdate()
-- (Soul Fragments / resource-overlay count refresh) every time the event
-- fired while restricted, exactly when combat resource tracking matters
-- most. This test pins the fix (drop the unit read/guard) via that
-- silent-skip behavior, not a throw.

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
                return function(self, name, value) self.attributes[name] = value end
            elseif key == "GetAttribute" then
                return function(self, name) return self.attributes[name] end
            elseif key == "SetScript" then
                return function(self, script, handler) self.scripts[script] = handler end
            elseif key == "GetScript" then
                return function(self, script) return self.scripts[script] end
            elseif key == "SetFrameRef" then
                return function(self, name, ref) self.frameRefs[name] = ref end
            elseif key == "GetFrameRef" then
                return function(self, name) return self.frameRefs[name] end
            elseif key == "Show" then
                return function(self) self.shown = true end
            elseif key == "Hide" then
                return function(self) self.shown = false end
            elseif key == "IsShown" then
                return function(self) return self.shown end
            elseif key == "GetFrameLevel" then
                return function(self) return self.frameLevel end
            elseif key == "SetFrameLevel" then
                return function(self, level) self.frameLevel = level end
            elseif key == "CreateTexture" or key == "CreateFontString" or key:match("^Get.*Texture$") then
                return function() return NewFrame() end
            elseif key == "GetChildren" then
                return function() return nil end
            elseif key == "GetParent" then
                return function(self) return self.parent end
            elseif key == "SetParent" then
                return function(self, parent) self.parent = parent end
            elseif key == "SetPoint" then
                return noop
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

function GetBuildInfo() return "12.0.5", "66562", "May 1 2026", 120005 end

function CreateFrame(_, _, parent)
    local frame = NewFrame()
    frame.parent = parent
    return frame
end

local inCombat = false
function InCombatLockdown() return inCombat end
function GetTime() return 1 end
function HasAction(action) return action and action > 0 end
function hooksecurefunc() end
function RegisterStateDriver() end
function UnregisterStateDriver() end
function LibStub() return nil end
function GetActionInfo() return nil end
function GetActionTexture() return nil end
function GetActionText() return nil end
function GetActionCount() return 0 end
function IsCurrentAction() return false end
function IsAutoRepeatAction() return false end
function IsEquippedAction() return false end
function GetCVar() return "0" end
function SetActionUIButton() end

C_Timer = { After = function(_, callback) if callback then callback() end end }
C_ActionBar = {
    GetActionCooldownDuration = function() return { type = "cooldown-duration" } end,
    GetActionCooldown = function() return { isActive = false } end,
    GetActionCharges = function() return { currentCharges = 0, maxCharges = 0, isActive = false } end,
    GetActionLossOfControlCooldownInfo = function() return { isActive = false, shouldReplaceNormalCooldown = false } end,
    GetActionChargeDuration = function() return nil end,
    GetActionLossOfControlCooldownDuration = function() return { type = "loc-duration" } end,
}

local ns = {
    Helpers = {
        GetCore = function() return {} end,
        CreateDBGetter = function()
            return function() return actionBarsDB end
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
        SafeToNumber = function(value, fallback) return type(value) == "number" and value or fallback end,
        SafeValue = function(value, fallback) return value == nil and fallback or value end,
        IsSecretValue = function() return false end,
        IsEditModeShown = function() return false end,
    },
    LSM = { Fetch = function() return nil end },
}

setmetatable(_G, {
    __index = function(_, key)
        local cTable = key:match("^C_[A-Z].*")
        if cTable then
            local tbl = setmetatable({}, { __index = function() return noop end })
            rawset(_G, key, tbl)
            return tbl
        end
        return noop
    end,
})

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIssecretvalue = SecretSentinel.InstallSecretStub()

assert(loadfile("QUI_ActionBars/actionbars/actionbars_env.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_helpers.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_layout.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_builder.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_petstance.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_cooldowns.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_glow.lua"))("QUI", ns)
-- Instrumented load (Task 7): the module under test — truthiness/==/#
-- on sentinels now THROW inside it, matching in-game 12.1 semantics.
assert(SecretSentinel.LoadInstrumented("QUI_ActionBars/actionbars/actionbars_events.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_skinning.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_usability.lua"))("QUI", ns)

local actionBars = assert(ns.ActionBarsOwned, "ActionBarsOwned should be exported")
local envNs = assert(ns.ActionBarsEnv, "ActionBarsEnv chunk-env should be exported")

local ownedEventFrame = assert(envNs.ownedEventFrame, "ownedEventFrame should be created at actionbars_petstance.lua load")
local onOwnedEvent = ownedEventFrame:GetScript("OnEvent")
assert(type(onOwnedEvent) == "function", "ownedEventFrame should have an OnEvent handler bound (actionbars_events.lua:754)")

local abUpdateFrame = assert(envNs.abUpdateFrame, "abUpdateFrame should be created at actionbars_events.lua load")

-- OnOwnedEvent bails immediately unless ActionBarsOwned.initialized is true
-- (actionbars_events.lua:301) — set directly rather than driving the full
-- Initialize() (RegisterEvent storm + BuildBar for every managed bar),
-- which is disproportionate setup for a single-branch boundary test.
actionBars.initialized = true

local function resetDirtyCounts()
    abUpdateFrame._dirtyCounts = false
    abUpdateFrame:Hide()
end

-- Secret/opaque unit token (simulates PTR 68569 restriction).
resetDirtyCounts()
onOwnedEvent(ownedEventFrame, "UNIT_AURA", SecretSentinel.MakeSecretSentinel())
assert(abUpdateFrame._dirtyCounts == true,
    "UNIT_AURA branch must call ScheduleABCountUpdate regardless of the payload unit's identity (registration is already player-only)")
assert(abUpdateFrame:IsShown() == true,
    "ScheduleABCountUpdate should wake the shared update frame even when the payload unit is secret")

-- Plain "player" string still works (no regression on the common case).
resetDirtyCounts()
onOwnedEvent(ownedEventFrame, "UNIT_AURA", "player")
assert(abUpdateFrame._dirtyCounts == true,
    "UNIT_AURA branch should still fire for the literal 'player' token")

_G.issecretvalue = restoreIssecretvalue

print("OK: actionbars_unit_aura_secret_boundary_test")
