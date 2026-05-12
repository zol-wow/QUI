-- tests/actionbars_cooldown_charge_cache_test.lua
-- Run: lua tests/actionbars_cooldown_charge_cache_test.lua

local originalPrint = print
local actionBarsDB = {
    enabled = true,
    global = {},
    bars = {},
}

local function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

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
            elseif key == "GetFrameLevel" then
                return function(self)
                    return self.frameLevel
                end
            elseif key == "SetFrameLevel" then
                return function(self, level)
                    self.frameLevel = level
                end
            elseif key == "SetCooldownFromDurationObject" then
                return function(self, durationObject)
                    self.lastDurationObject = durationObject
                end
            elseif key == "Clear" then
                return function(self)
                    self.cleared = (rawget(self, "cleared") or 0) + 1
                    self.lastDurationObject = nil
                end
            elseif key == "CreateTexture" or key == "CreateFontString" or key:match("^Get.*Texture$") then
                return function()
                    return NewFrame()
                end
            elseif key == "GetChildren" then
                return function()
                    return nil
                end
            elseif key == "GetParent" then
                return function(self)
                    return self.parent
                end
            elseif key == "SetParent" then
                return function(self, parent)
                    self.parent = parent
                end
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

function GetBuildInfo()
    return "12.0.5", "66562", "May 1 2026", 120005
end

function CreateFrame(_, _, parent)
    local frame = NewFrame()
    frame.parent = parent
    return frame
end

function InCombatLockdown() return false end
local currentTime = 1
function GetTime() return currentTime end
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

local timerAfterCalls = 0
C_Timer = {
    After = function(_, callback)
        timerAfterCalls = timerAfterCalls + 1
        if callback then callback() end
    end,
}

C_ActionBar = {
    GetActionCooldownDuration = function() return { type = "cooldown-duration" } end,
}

local chargeCalls = 0
local chargeDurationCalls = 0
local actionCooldownDurationCalls = 0
local actionCooldownIgnoreGCDCalls = 0
local chargeInfoByAction = {}
local chargeDurationByAction = {}
local cooldownInfoByAction = {}
local cooldownDurationByAction = {}
local secretCurrentCharges = setmetatable({}, {
    __tostring = function()
        error("currentCharges should not be read")
    end,
    __tonumber = function()
        error("currentCharges should not be converted")
    end,
    __lt = function()
        error("currentCharges should not be compared")
    end,
    __le = function()
        error("currentCharges should not be compared")
    end,
})

function C_ActionBar.GetActionCooldown(action)
    return cooldownInfoByAction[action] or { isActive = false }
end

function C_ActionBar.GetActionCharges(action)
    chargeCalls = chargeCalls + 1
    return chargeInfoByAction[action] or {
        currentCharges = secretCurrentCharges,
        maxCharges = 0,
        isActive = false,
    }
end

function C_ActionBar.GetActionLossOfControlCooldownInfo()
    return { isActive = false, shouldReplaceNormalCooldown = false }
end

function C_ActionBar.GetActionChargeDuration(action)
    chargeDurationCalls = chargeDurationCalls + 1
    return chargeDurationByAction[action]
end

function C_ActionBar.GetActionLossOfControlCooldownDuration()
    return { type = "loc-duration" }
end

local ns = {
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

assert(loadfile("modules/actionbars/actionbars.lua"))("QUI", ns)

local actionBars = assert(ns.ActionBarsOwned, "ActionBarsOwned should be exported")

local clears = 0
local sets = 0
local button = {
    action = 1,
    GetFrameLevel = function()
        return 1
    end,
    cooldown = {
        Clear = function()
            clears = clears + 1
        end,
        SetCooldownFromDurationObject = function()
            sets = sets + 1
        end,
    },
}

actionBars.UpdateCooldown(button)
actionBars.UpdateCooldown(button)

assert(chargeCalls == 1, "idle non-charge actions should only query charge info once")
assert(chargeDurationCalls == 0, "idle non-charge actions should not query charge DurationObjects")
assert(clears == 0, "idle inactive buttons should not churn Clear calls")
assert(sets == 0, "idle inactive buttons should not set cooldowns")

button.action = 2
actionBars.UpdateCooldown(button)
assert(chargeCalls == 2, "changing the action should invalidate the charge-capability cache")

button.action = 3
local chargeDuration = { token = "charge-duration" }
chargeDurationByAction[3] = chargeDuration
chargeInfoByAction[3] = {
    currentCharges = secretCurrentCharges,
    maxCharges = 2,
    isActive = true,
}
actionBars.UpdateCooldown(button)
assert(chargeCalls == 3, "charge-capable actions should query charge info")
assert(chargeDurationCalls == 1, "active charge cooldowns should query the charge DurationObject")
assert(button.chargeCooldown and button.chargeCooldown.lastDurationObject == chargeDuration,
    "active charge cooldowns should use the charge DurationObject")

chargeInfoByAction[3].isActive = false
button.chargeCooldown.lastDurationObject = nil
actionBars.UpdateCooldown(button)
assert(chargeCalls == 4, "known charge-capable actions should keep querying charge activity")
assert(chargeDurationCalls == 1, "inactive charge cooldowns should not query charge DurationObjects")

local gcdDurationA = { token = "gcd-duration-a" }
local gcdDurationB = { token = "gcd-duration-b" }
function C_ActionBar.GetActionCooldownDuration(action, ignoreGCD)
    if ignoreGCD then
        actionCooldownIgnoreGCDCalls = actionCooldownIgnoreGCDCalls + 1
        return nil
    end
    actionCooldownDurationCalls = actionCooldownDurationCalls + 1
    return cooldownDurationByAction[action]
end

local batchButtonA = {
    action = 10,
    GetFrameLevel = function() return 1 end,
    cooldown = NewFrame(),
}
local batchButtonB = {
    action = 11,
    GetFrameLevel = function() return 1 end,
    cooldown = NewFrame(),
}
cooldownInfoByAction[10] = { isActive = true, isOnGCD = true }
cooldownInfoByAction[11] = { isActive = true, isOnGCD = true }
cooldownDurationByAction[10] = gcdDurationA
cooldownDurationByAction[11] = gcdDurationB
actionBars._activeButtons[batchButtonA] = true
actionBars._activeButtons[batchButtonB] = true

actionBars.UpdateAllCooldowns()

assert(actionCooldownIgnoreGCDCalls == 0,
    "GCD action bar swipes should not use the ignoreGCD cooldown-duration probe")
assert(actionCooldownDurationCalls == 2,
    "GCD swipes should fetch one DurationObject per action button")
assert(batchButtonA.cooldown.lastDurationObject == gcdDurationA,
    "first GCD button should receive its own action DurationObject")
assert(batchButtonB.cooldown.lastDurationObject == gcdDurationB,
    "second GCD button should receive its own action DurationObject")

local chargeBatchButtonA = {
    action = 20,
    GetFrameLevel = function() return 1 end,
    cooldown = NewFrame(),
}
local chargeBatchButtonB = {
    action = 20,
    GetFrameLevel = function() return 1 end,
    cooldown = NewFrame(),
}
local sharedChargeDuration = { token = "shared-charge-duration" }
cooldownInfoByAction[20] = { isActive = false }
chargeInfoByAction[20] = {
    currentCharges = secretCurrentCharges,
    maxCharges = 2,
    isActive = true,
}
chargeDurationByAction[20] = sharedChargeDuration
local chargeCallsBeforeBatch = chargeCalls
local chargeDurationCallsBeforeBatch = chargeDurationCalls
wipe(actionBars._activeButtons)
actionBars._activeButtons[chargeBatchButtonA] = true
actionBars._activeButtons[chargeBatchButtonB] = true
currentTime = currentTime + 1

actionBars.UpdateAllCooldowns()

assert(chargeCalls - chargeCallsBeforeBatch == 1,
    "duplicate action slots in one cooldown batch should share charge activity queries")
assert(chargeDurationCalls - chargeDurationCallsBeforeBatch == 1,
    "duplicate action slots in one cooldown batch should share charge DurationObjects")
assert(chargeBatchButtonA.chargeCooldown.lastDurationObject == sharedChargeDuration,
    "first charge button should receive the shared charge DurationObject")
assert(chargeBatchButtonB.chargeCooldown.lastDurationObject == sharedChargeDuration,
    "second charge button should receive the shared charge DurationObject")

assert(type(actionBars._sharedHandlers) == "table",
    "shared action button handlers should be exported for all button instances")
assert(type(actionBars._sharedHandlers.UpdateCooldown) == "function",
    "cooldown updates should use one shared handler instead of per-button closures")
assert(type(actionBars._sharedHandlers.UpdateCount) == "function",
    "count updates should use one shared handler instead of per-button closures")

actionBarsDB.global = {
    skinEnabled = true,
    iconSize = 36,
    buttonSpacing = 2,
}
actionBarsDB.bars = {
    bar1 = {
        iconSize = 40,
    },
    bar2 = {
        iconSize = 44,
    },
}

local settingsA = actionBars.GetEffectiveSettings("bar1")
local settingsB = actionBars.GetEffectiveSettings("bar1")
local settingsBar2 = actionBars.GetEffectiveSettings("bar2")
assert(settingsA == settingsB, "effective per-bar settings should be cached between reads")
assert(settingsA.skinEnabled == true, "cached settings should include global values")
assert(settingsA.iconSize == 40, "cached settings should include per-bar overrides")

actionBarsDB.bars.bar1.iconSize = 48
actionBars.InvalidateEffectiveSettingsCache("bar1")
local settingsC = actionBars.GetEffectiveSettings("bar1")
assert(settingsC ~= settingsA, "invalidating a bar should rebuild only that bar cache")
assert(settingsC.iconSize == 48, "rebuilt settings should include updated per-bar values")
assert(actionBars.GetEffectiveSettings("bar2") == settingsBar2,
    "invalidating one bar should not clear other cached bar settings")

local usabilityCalls = 0
local visibleCalls = 0
actionBarsDB.global.rangeIndicator = false
actionBarsDB.global.usabilityIndicator = true
function IsUsableAction(action)
    usabilityCalls = usabilityCalls + 1
    return action ~= 102, false
end
local activeUsabilityButton = {
    action = 101,
    GetName = function()
        return "QUI_Bar1Button1"
    end,
    IsVisible = function()
        visibleCalls = visibleCalls + 1
        return true
    end,
}
local inactiveUsabilityButton = {
    action = 102,
    GetName = function()
        return "QUI_Bar1Button2"
    end,
    IsVisible = function()
        visibleCalls = visibleCalls + 1
        return true
    end,
}
wipe(actionBars._activeButtons)
assert(type(actionBars._activeStandardButtons) == "table",
    "standard action buttons should have a dedicated active registry")
actionBars.nativeButtons.bar1 = { activeUsabilityButton, inactiveUsabilityButton }
actionBars._activeButtons[activeUsabilityButton] = true
actionBars._activeStandardButtons[activeUsabilityButton] = true

actionBars.UpdateAllButtonUsability()

assert(usabilityCalls == 1, "usability refresh should scan active action buttons only")
assert(visibleCalls == 1, "usability refresh should avoid visible checks for inactive buttons")

local visibleSlotButton = {
    action = 201,
    _quiBarKey = "bar1",
    _quiButtonIndex = 1,
    IsVisible = function()
        visibleCalls = visibleCalls + 1
        return true
    end,
}
local hiddenByLayoutButton = {
    action = 202,
    _quiBarKey = "bar1",
    _quiButtonIndex = 2,
    IsVisible = function()
        visibleCalls = visibleCalls + 1
        return true
    end,
}
actionBarsDB.bars.bar1 = {
    ownedLayout = {
        iconCount = 1,
    },
}
actionBars.nativeButtons.bar1 = { visibleSlotButton, hiddenByLayoutButton }
wipe(actionBars._activeButtons)
wipe(actionBars._activeStandardButtons)
actionBars._activeButtons[visibleSlotButton] = true
actionBars._activeButtons[hiddenByLayoutButton] = true
actionBars._activeStandardButtons[visibleSlotButton] = true
actionBars._activeStandardButtons[hiddenByLayoutButton] = true
usabilityCalls = 0
visibleCalls = 0

actionBars.UpdateAllButtonUsability()

assert(usabilityCalls == 1,
    "usability refresh should respect the configured visible button count")
assert(visibleCalls == 1,
    "buttons hidden by visible-count layout should not be visibility-probed")

assert(actionBars._perfProbesEnabled == false,
    "split actionbar perf probes should be disabled unless explicitly requested")

assert(type(actionBars.ScheduleUsabilityUpdate) == "function",
    "usability scheduling should be exposed for the persistent scheduler")
timerAfterCalls = 0
actionBars.ScheduleUsabilityUpdate()
assert(timerAfterCalls == 0,
    "usability scheduling should not allocate C_Timer.After callbacks")
assert(actionBars._usabilityUpdateFrame and actionBars._usabilityUpdateFrame:IsShown(),
    "usability scheduling should wake one persistent update frame")
local usabilityOnUpdate = actionBars._usabilityUpdateFrame:GetScript("OnUpdate")
assert(type(usabilityOnUpdate) == "function",
    "usability scheduler frame should have one shared OnUpdate handler")
usabilityOnUpdate(actionBars._usabilityUpdateFrame, 0.05)
assert(not actionBars._usabilityUpdateFrame:IsShown(),
    "usability scheduler frame should hide after flushing")

assert(type(actionBars.MarkSpellIdMapDirty) == "function",
    "spell reverse map should support dirty marking")
assert(type(actionBars.EnsureSpellIdMap) == "function",
    "spell reverse map should support lazy rebuilds")
assert(type(actionBars.GetSpellIdMapStats) == "function",
    "spell reverse map should expose lightweight test stats")
local spellMapStats = actionBars.GetSpellIdMapStats()
local rebuildsBefore = spellMapStats.rebuilds
actionBars.MarkSpellIdMapDirty()
actionBars.EnsureSpellIdMap()
assert(spellMapStats.rebuilds == rebuildsBefore + 1,
    "dirty spell reverse map should rebuild on demand")
actionBars.EnsureSpellIdMap()
assert(spellMapStats.rebuilds == rebuildsBefore + 1,
    "clean spell reverse map should not rebuild on repeated visual refreshes")

originalPrint("OK: actionbars_cooldown_charge_cache_test")
