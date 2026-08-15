-- luacheck: globals UIParent SlashCmdList BINDING_HEADER_QUI_ACTIONBARS WOW_PROJECT_MAINLINE WOW_PROJECT_ID RANGE_INDICATOR GetBuildInfo CreateFrame InCombatLockdown GetTime HasAction hooksecurefunc RegisterStateDriver UnregisterStateDriver LibStub GetActionInfo GetActionTexture GetActionText GetActionCount IsCurrentAction IsAutoRepeatAction IsEquippedAction GetCVar SetActionUIButton C_Timer C_ActionBar C_Spell C_LossOfControl issecretvalue wipe GetPetActionInfo GetPetActionSlotUsable IsPetAttackAction GetPetActionCooldown GetShapeshiftFormInfo GetShapeshiftFormCooldown CooldownFrame_Set IsUsableAction

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
SecretSentinel.InstallSecretStub()

local originalPrint = print
local actionBarsDB = {
    enabled = true,
    global = {},
    bars = {},
}

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

local function noop() end

local function ActionAttr(slot)
    return function(_, name)
        if name == "action" then return slot end
    end
end

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
    return "12.1.0", "69299", "Aug 1 2026", 120100
end

function CreateFrame(_, _, parent)
    local frame = NewFrame()
    frame.parent = parent
    return frame
end

local inCombat = false
function InCombatLockdown() return inCombat end
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
function IsCurrentAction(action) return action == 40 end
function IsAutoRepeatAction() return false end
function IsEquippedAction() return false end
function GetCVar() return "0" end
function SetActionUIButton() end

C_Timer = {
    After = function(_, callback)
        if callback then callback() end
    end,
}

local cooldownInfoByAction = {}
local cooldownDurationByAction = {}
local chargeInfoByAction = {}
local chargeDurationByAction = {}
local locInfoByAction = {}
local actionCooldownCalls = 0
local chargeCalls = 0

C_ActionBar = {}
function C_ActionBar.GetActionCooldown(action)
    actionCooldownCalls = actionCooldownCalls + 1
    return cooldownInfoByAction[action]
end
function C_ActionBar.GetActionCooldownDuration(action)
    return cooldownDurationByAction[action]
end
function C_ActionBar.GetActionCharges(action)
    chargeCalls = chargeCalls + 1
    return chargeInfoByAction[action]
end
function C_ActionBar.GetActionChargeDuration(action)
    return chargeDurationByAction[action]
end
function C_ActionBar.GetActionLossOfControlCooldownInfo(action)
    return locInfoByAction[action]
end
local locDurationByAction = {}
function C_ActionBar.GetActionLossOfControlCooldownDuration(action)
    return locDurationByAction[action]
end

local activeLossOfControlCount = 0
C_LossOfControl = {}
function C_LossOfControl.GetActiveLossOfControlDataCount()
    return activeLossOfControlCount
end

local spellCdDurationBySpell = {}
C_Spell = {}
function C_Spell.GetSpellCooldownDuration(spellID)
    return spellCdDurationBySpell[spellID]
end

local petSpellID = 1234
function GetPetActionInfo()
    return "PET_ACTION_ATTACK", "tex", false, false, false, false, petSpellID
end
function GetPetActionSlotUsable() return true end
function IsPetAttackAction() return false end
local petNumericCalls = 0
function GetPetActionCooldown()
    petNumericCalls = petNumericCalls + 1
    return 0, 0, 1
end
local stanceSpellID = 5678
function GetShapeshiftFormInfo()
    return "tex", false, true, stanceSpellID
end
local stanceNumericCalls = 0
function GetShapeshiftFormCooldown()
    stanceNumericCalls = stanceNumericCalls + 1
    return 0, 0, 1
end
function CooldownFrame_Set() end

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
        IsSecretValue = function(value)
            return _G.issecretvalue and _G.issecretvalue(value) or false
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

assert(loadfile("QUI_ActionBars/actionbars/actionbars_env.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_helpers.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_layout.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_builder.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_petstance.lua"))("QUI", ns)
assert(SecretSentinel.LoadInstrumented("QUI_ActionBars/actionbars/actionbars_cooldowns.lua"))("QUI", ns)
assert(SecretSentinel.LoadInstrumented("QUI_ActionBars/actionbars/actionbars_glow.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_events.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_skinning.lua"))("QUI", ns)
assert(loadfile("QUI_ActionBars/actionbars/actionbars_usability.lua"))("QUI", ns)

local actionBars = assert(ns.ActionBarsOwned, "ActionBarsOwned should be exported")

local activeDuration = { token = "dur-10" }
cooldownInfoByAction[10] = { isActive = true }
cooldownDurationByAction[10] = activeDuration
chargeInfoByAction[10] = { currentCharges = 0, maxCharges = 0, isActive = false }
locInfoByAction[10] = { isActive = false, shouldReplaceNormalCooldown = false }

local secretFieldBtn = {
    action = SecretSentinel.MakeSecretSentinel(),
    GetAttribute = ActionAttr(10),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
local normalBtn = {
    action = 10,
    GetAttribute = ActionAttr(10),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
local noSlotBtn = {
    action = SecretSentinel.MakeSecretSentinel(),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
actionBars._activeButtons[secretFieldBtn] = true
actionBars._activeButtons[normalBtn] = true
actionBars._activeButtons[noSlotBtn] = true
currentTime = currentTime + 1

local ok, err = pcall(actionBars.UpdateAllCooldowns)
assert(ok, "a secret button.action field must not abort the cooldown batch: " .. tostring(err))
assert(normalBtn.cooldown.lastDurationObject == activeDuration,
    "buttons alongside a secret-field button must still receive their DurationObject")
assert(secretFieldBtn.cooldown.lastDurationObject == activeDuration,
    "a secret action FIELD must not block painting: the attribute slot is the cooldown source")
assert(rawget(noSlotBtn.cooldown, "cleared") == nil
        and rawget(noSlotBtn.cooldown, "lastDurationObject") == nil,
    "a button with no resolvable attribute slot must be skipped, not cleared")

local nilInfoBtn = {
    action = 20,
    GetAttribute = ActionAttr(20),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
wipe(actionBars._activeButtons)
actionBars._activeButtons[nilInfoBtn] = true
actionBars._activeButtons[normalBtn] = true
normalBtn.cooldown.lastDurationObject = nil
currentTime = currentTime + 1

ok, err = pcall(actionBars.UpdateAllCooldowns)
assert(ok, "a ReturnNothing cooldown/charge/LoC struct must not abort the cooldown batch: " .. tostring(err))
assert(normalBtn.cooldown.lastDurationObject == activeDuration,
    "buttons after a nil-struct button must still receive their DurationObject")
assert(rawget(nilInfoBtn.cooldown, "cleared") == nil,
    "a nil-struct button must be treated as inactive without churning Clear")

local secretSchedule = { token = "dur-30" }
cooldownInfoByAction[30] = { isActive = SecretSentinel.MakeSecretSentinel() }
cooldownDurationByAction[30] = secretSchedule
local secretActiveBtn = {
    action = 30,
    GetAttribute = ActionAttr(30),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
wipe(actionBars._activeButtons)
actionBars._activeButtons[secretActiveBtn] = true
currentTime = currentTime + 1

ok, err = pcall(actionBars.UpdateAllCooldowns)
assert(ok, "a secret isActive must not abort the cooldown batch: " .. tostring(err))
assert(secretActiveBtn.cooldown.lastDurationObject == secretSchedule,
    "a secret isActive must pass the DurationObject through to the sink, never collapse to inactive")
assert(rawget(secretActiveBtn.cooldown, "cleared") == nil,
    "a secret isActive must never clear a possibly-running swipe")

wipe(actionBars._activeButtons)
wipe(actionBars._activeStandardButtons)
actionBars.nativeButtons.bar1 = {
    {
        action = SecretSentinel.MakeSecretSentinel(),
        GetAttribute = ActionAttr(10),
        cooldown = NewFrame(),
        GetFrameLevel = function() return 1 end,
        _quiBarKey = "bar1",
        _quiButtonIndex = 1,
    },
}
currentTime = currentTime + 1

ok, err = pcall(actionBars.UpdateAllCooldowns)
assert(ok, "the standard-bar fallback walk must not abort on a secret button.action: " .. tostring(err))
assert(actionBars.nativeButtons.bar1[1].cooldown.lastDurationObject == activeDuration,
    "the fallback walk must paint a secret-field button from its attribute slot")

local checkedStates = {}
local stateSecretBtn = {
    action = SecretSentinel.MakeSecretSentinel(),
    GetAttribute = ActionAttr(40),
    SetChecked = function(_, value) checkedStates.secret = value end,
}
local stateNormalBtn = {
    action = 40,
    GetAttribute = ActionAttr(41),
    SetChecked = function(_, value) checkedStates.normal = value end,
}
local stateNoSlotBtn = {
    action = SecretSentinel.MakeSecretSentinel(),
    SetChecked = function(_, value) checkedStates.noslot = value end,
}
wipe(actionBars._activeButtons)
actionBars._activeButtons[stateSecretBtn] = true
actionBars._activeButtons[stateNormalBtn] = true
actionBars._activeButtons[stateNoSlotBtn] = true
currentTime = currentTime + 1

ok, err = pcall(actionBars.UpdateAllButtonStates)
assert(ok, "a secret button.action field must not abort the checked-state batch: " .. tostring(err))
assert(checkedStates.secret == true,
    "a secret action field must not block checked state: the attribute slot drives it")
assert(checkedStates.normal == false,
    "checked state must follow the attribute slot, never the action field")
assert(checkedStates.noslot == nil,
    "a button with no resolvable attribute slot must be skipped by the checked-state batch")

actionBars.initialized = true
local OnOwnedEvent = assert(ns.ActionBarsEnv.OnOwnedEvent,
    "OnOwnedEvent should be reachable through the shared chunk env")

local longDuration = { token = "dur-50" }
local longCdBtn = {
    action = 50,
    GetAttribute = ActionAttr(50),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
currentTime = 100
cooldownInfoByAction[50] = { isActive = true, startTime = 100, duration = 30 }
cooldownDurationByAction[50] = longDuration
wipe(actionBars._activeButtons)
actionBars._activeButtons[longCdBtn] = true

actionBars.UpdateAllCooldowns()
local callsAfterFirstFetch = actionCooldownCalls
local freshLongDuration = { token = "dur-50-fresh" }
cooldownDurationByAction[50] = freshLongDuration
currentTime = 100.1
actionBars.UpdateAllCooldowns()
assert(actionCooldownCalls == callsAfterFirstFetch + 1,
    "every batch must refetch cooldown info: a shortened schedule is unreadable under combat secrecy, so no per-button memo may serve it")
assert(longCdBtn.cooldown.lastDurationObject == freshLongDuration,
    "every batch must push the FRESH DurationObject: a memoized object strands the swipe on the old schedule")

local secretAttrState = { value = 10 }
local secretAttrBtn = {
    action = SecretSentinel.MakeSecretSentinel(),
    GetAttribute = function(_, name)
        if name == "action" then return secretAttrState.value end
    end,
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
cooldownInfoByAction[10] = { isActive = true }
cooldownDurationByAction[10] = activeDuration
wipe(actionBars._activeButtons)
actionBars._activeButtons[secretAttrBtn] = true
currentTime = 100.2
ok, err = pcall(actionBars.UpdateAllCooldowns)
assert(ok and secretAttrBtn.cooldown.lastDurationObject == activeDuration,
    "a readable attribute slot must paint and seed the last-readable-slot memo: " .. tostring(err))

secretAttrState.value = SecretSentinel.MakeSecretSentinel()
secretAttrBtn.cooldown.lastDurationObject = nil
currentTime = 100.3
ok, err = pcall(actionBars.UpdateAllCooldowns)
assert(ok, "a secret GetAttribute return must not abort the cooldown batch: " .. tostring(err))
assert(secretAttrBtn.cooldown.lastDurationObject == activeDuration,
    "a secret attribute read must fall back to the last readable slot and keep painting")

local throwingBtn = {
    action = 10,
    GetAttribute = ActionAttr(10),
    cooldown = setmetatable({}, { __index = function(_, key)
        if key == "SetCooldownFromDurationObject" then
            return function() error("sink throw") end
        end
        return noop
    end }),
    GetFrameLevel = function() return 1 end,
}
local healthyBtn = {
    action = 10,
    GetAttribute = ActionAttr(10),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
wipe(actionBars._activeButtons)
actionBars._activeButtons[throwingBtn] = true
actionBars._activeButtons[healthyBtn] = true
currentTime = 100.4
ok, err = pcall(actionBars.UpdateAllCooldowns)
assert(ok, "a throwing per-button paint must not abort the cooldown batch: " .. tostring(err))
assert(healthyBtn.cooldown.lastDurationObject == activeDuration,
    "buttons sharing a batch with a throwing button must still receive their DurationObject")

local chargeSwipe = { token = "charge-dur-60" }
local chargeBtn = {
    action = 60,
    GetAttribute = ActionAttr(60),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
chargeInfoByAction[60] = { currentCharges = 0, maxCharges = 0, isActive = false }
wipe(actionBars._activeButtons)
actionBars._activeButtons[chargeBtn] = true
currentTime = 101

actionBars.UpdateAllCooldowns()
local chargeCallsAfterVerdict = chargeCalls
currentTime = 101.3
actionBars.UpdateAllCooldowns()
assert(chargeCalls == chargeCallsAfterVerdict,
    "a no-charges verdict should suppress charge probes between charge events")

chargeInfoByAction[60] = { currentCharges = 1, maxCharges = 2, isActive = true }
chargeDurationByAction[60] = chargeSwipe
OnOwnedEvent(nil, "SPELL_UPDATE_CHARGES")
currentTime = 101.6
actionBars.UpdateAllCooldowns()
assert(chargeCalls == chargeCallsAfterVerdict + 1,
    "SPELL_UPDATE_CHARGES must flush the charge-capability verdicts so a temp-charge grant re-probes")
assert(chargeBtn.chargeCooldown and chargeBtn.chargeCooldown.lastDurationObject == chargeSwipe,
    "a temp-charge grant must paint its recharge swipe on the next batch")

local locDur = { token = "loc-dur-70" }
local locBtn = {
    action = 70,
    GetAttribute = ActionAttr(70),
    cooldown = NewFrame(),
    GetFrameLevel = function() return 1 end,
}
cooldownInfoByAction[70] = { isActive = false }
chargeInfoByAction[70] = { currentCharges = 0, maxCharges = 0, isActive = false }
locInfoByAction[70] = { isActive = true, shouldReplaceNormalCooldown = false }
locDurationByAction[70] = locDur
activeLossOfControlCount = 1
wipe(actionBars._activeButtons)
actionBars._activeButtons[locBtn] = true
currentTime = 102

actionBars.UpdateAllCooldowns()
assert(locBtn._quiLoCCooldown and locBtn._quiLoCCooldown.lastDurationObject == locDur,
    "a pure loss-of-control cooldown must draw even when no action cooldown or charge is active")

activeLossOfControlCount = 0
locInfoByAction[70] = { isActive = false, shouldReplaceNormalCooldown = false }
currentTime = 103
actionBars.UpdateAllCooldowns()
assert(rawget(locBtn._quiLoCCooldown, "cleared") == 1,
    "the loss-of-control swipe must clear on the falling edge")

local SafeIsUsableAction = assert(ns.ActionBarsEnv.SafeIsUsableAction,
    "SafeIsUsableAction should be reachable through the shared chunk env")
function IsUsableAction()
    error("restricted")
end
local usableOnThrow, noManaOnThrow = SafeIsUsableAction(1)
assert(usableOnThrow == true and noManaOnThrow == false,
    "SafeIsUsableAction must contain a throwing IsUsableAction and report neutral usability")
local secretUsable = SecretSentinel.MakeSecretSentinel()
function IsUsableAction()
    return secretUsable, false
end
local usableOnSecret, noManaOnSecret = SafeIsUsableAction(1)
assert(usableOnSecret == true and noManaOnSecret == false,
    "SafeIsUsableAction must reject secret usability values instead of coercing them")

local petDur = { token = "pet-dur" }
spellCdDurationBySpell[petSpellID] = petDur
local petBtn = {
    GetID = function() return 1 end,
    icon = { SetTexture = noop, SetVertexColor = noop, Show = noop, Hide = noop },
    SetChecked = noop,
    StartFlash = noop,
    StopFlash = noop,
    GetCheckedTexture = function() return nil end,
    cooldown = NewFrame(),
}
actionBars.UpdatePetButton(petBtn)
assert(petBtn.cooldown.lastDurationObject == petDur,
    "pet cooldowns must paint through the spell DurationObject when the slot has a spellID")
assert(petNumericCalls == 0,
    "the numeric pet cooldown path must not run when the DurationObject painted")

spellCdDurationBySpell[petSpellID] = nil
petBtn.cooldown.lastDurationObject = nil
actionBars.UpdatePetButton(petBtn)
assert(petNumericCalls == 1,
    "pet cooldowns must fall back to the numeric path when no DurationObject resolves")

local stanceDur = { token = "stance-dur" }
spellCdDurationBySpell[stanceSpellID] = stanceDur
local stanceBtn = {
    GetID = function() return 1 end,
    icon = { SetTexture = noop, SetVertexColor = noop, Show = noop, Hide = noop },
    SetChecked = noop,
    cooldown = NewFrame(),
}
actionBars.UpdateStanceButton(stanceBtn)
assert(stanceBtn.cooldown.lastDurationObject == stanceDur,
    "stance cooldowns must paint through the spell DurationObject when the form has a spellID")
assert(stanceNumericCalls == 0,
    "the numeric stance cooldown path must not run when the DurationObject painted")

originalPrint("OK: actionbars_cooldown_secret_batch_test")
