-- tests/unit/focuscastalert_spellcast_secret_boundary_test.lua
-- Run: lua5.1 tests/unit/focuscastalert_spellcast_secret_boundary_test.lua
--
-- Wave 2b Task C: modules/qol/focuscastalert.lua registers
-- UNIT_SPELLCAST_SUCCEEDED via RegisterUnitEvent(..., "player") (already
-- player-only) but the shared OnEvent handler still re-checked
-- `event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player"` before calling
-- OnPlayerInterruptCast(spellID). Fix: drop the redundant/unproven-safe unit
-- compare (registration is already the C-side filter). The spellID probe
-- itself was PRE-EXISTING inside OnPlayerInterruptCast (IsSecretValue(spellID)
-- before INTERRUPT_SPELL_LOOKUP[spellID]/state.interruptCasts[spellID]) --
-- this test pins both the pre-existing probe and the newly dropped compare,
-- with BEHAVIORAL assertions (not just no-throw): state.interruptCasts isn't
-- exported, so we observe it indirectly through the alert frame's
-- Show()/Hide() gate (IsInterruptReady checks state.interruptCasts[spellID]
-- against GetTime()).
--
-- Caveat (numeric secrets are headlessly untestable, honestly): a REAL WoW
-- secret spellID is an opaque engine value that throws on table-index and
-- numeric compare. This harness's throwing sentinel (secret_sentinel.lua)
-- stands in for that and pins the "probe before touch" discipline / call
-- ordering, but cannot reproduce the engine's actual throw-on-index
-- semantics for a real secret number -- what IS verified here is the
-- observable effect: a secret spellID never records an interrupt-CD entry.
-- luacheck: globals CreateFrame UIParent UnitExists UnitCanAttack UnitCastingInfo UnitChannelInfo UnitClass IsPlayerSpell GetTime C_Timer PlaySoundFile UnitName

local function noop() end

local eventFrame
local alertFrame

local function newFrame(name)
    local frame = {
        name = name,
        shown = false,
        alpha = 1,
        points = {},
        events = {},
    }

    function frame:SetSize() end
    function frame:SetFrameStrata() end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:IsShown() return self.shown end
    function frame:SetAlpha(a) self.alpha = a end
    function frame:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)
        self.alphaFromBoolean = { value = value, alphaIfTrue = alphaIfTrue, alphaIfFalse = alphaIfFalse }
    end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, unit) self.events[event] = { unit = unit } end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(scriptName, handler) self.scripts = self.scripts or {}; self.scripts[scriptName] = handler end
    function frame:GetScript(scriptName) return self.scripts and self.scripts[scriptName] end
    function frame:CreateFontString()
        local fs = {}
        function fs:SetPoint() end
        function fs:SetJustifyH() end
        function fs:SetJustifyV() end
        function fs:SetFont() return true end
        function fs:SetText(text) self.text = text end
        function fs:SetFormattedText(format, ...) self.text = string.format(format, ...) end
        function fs:SetTextColor() end
        return fs
    end

    return frame
end

UIParent = newFrame("UIParent")

function CreateFrame(_, name)
    local frame = newFrame(name)
    if name == "QUI_FocusCastAlertFrame" then
        alertFrame = frame
    elseif not eventFrame then
        eventFrame = frame
    end
    return frame
end

function UnitExists(unit) return unit == "focus" end
function UnitCanAttack(player, unit) return player == "player" and unit == "focus" end
function UnitCastingInfo(unit)
    if unit == "focus" then
        -- name, text, texture, startTime, endTime, isTradeSkill, castID,
        -- notInterruptible, spellID, ... -- notInterruptible plain-false so
        -- this test's Show()/Hide() assertions turn only on IsInterruptReady.
        return "Kick Target", "Kick Target", 135846, 100000, 103000, false, "CastGUID", false, 1766, nil, 0
    end
    return nil
end
function UnitChannelInfo() return nil end
function UnitClass(unit)
    if unit == "player" then return "Player", "ROGUE" end
    return nil
end
function IsPlayerSpell() return true end -- every interrupt spell is "known" for this test
function UnitName() return "Focus Target" end

local now = 100
function GetTime() return now end

C_Timer = {
    NewTicker = function() return { Cancel = noop } end,
}

local settings = {
    enabled = true,
    soundEnabled = false,
}

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIssecretvalue = SecretSentinel.InstallSecretStub()

local ns = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Helpers = {
        SafeToString = function(value, fallback) return value == nil and fallback or tostring(value) end,
        IsSecretValue = function(value) return issecretvalue and issecretvalue(value) or false end,
        GetModuleDB = function(module)
            assert(module == "general", "focus cast alert should read general DB")
            return { focusCastAlert = settings }
        end,
        EnsureDefaults = function(tbl, defaults)
            for key, value in pairs(defaults) do
                if tbl[key] == nil then tbl[key] = value end
            end
        end,
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
        GetPlayerClassColor = function() return 0.25, 0.78, 0.92 end,
    },
    LSM = {
        Fetch = function() return nil end,
    },
    SafeCall = function(_policy, fn, ...)
        return pcall(fn, ...)
    end,
    SafeCallMethod = function(_policy, obj, name, ...)
        return pcall(function(...) return obj[name](obj, ...) end, ...)
    end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}

-- Instrumented load (Task 7): truthiness/==/# on sentinels now THROW
-- inside the module, matching in-game 12.1 secret semantics.
assert(SecretSentinel.LoadInstrumented("modules/qol/focuscastalert.lua"))("QUI", ns)
assert(eventFrame and eventFrame.scripts and eventFrame.scripts.OnEvent, "focus cast alert event handler missing")

----------------------------------------------------------------------------
-- Registration proof: player-only via RegisterUnitEvent (unchanged by this
-- task, but pinned so a future regression to a global RegisterEvent is
-- caught here too).
----------------------------------------------------------------------------
assert(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED and eventFrame.events.UNIT_SPELLCAST_SUCCEEDED.unit == "player",
    "UNIT_SPELLCAST_SUCCEEDED must be RegisterUnitEvent'd to player")

local onEvent = eventFrame.scripts.OnEvent

----------------------------------------------------------------------------
-- Case 1: secret spellID -- OnPlayerInterruptCast's pre-existing probe must
-- skip the table index/store; no throw, AND (behaviorally) Kick's interrupt
-- CD must NOT be considered started: with nothing cast yet this session,
-- IsInterruptReady() is true, so the alert (focus is casting, mocked above)
-- must Show().
----------------------------------------------------------------------------
local secretSpellID = SecretSentinel.MakeSecretSentinel()
local ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-1", secretSpellID)
assert(ok, "OnEvent must not throw on a secret spellID: " .. tostring(err))
assert(alertFrame and alertFrame.shown,
    "a secret spellID must not record an interrupt-CD entry -- alert should still show (interrupt ready)")

----------------------------------------------------------------------------
-- Case 2: secret UNIT token, normal numeric spellID (1766 = Kick) -- the
-- redundant unit compare was dropped, so a secret/garbage unit must NOT
-- block a real interrupt-CD record. Observable effect: right after this
-- event, Kick is now "on cooldown" per internal tracking, so IsInterruptReady()
-- goes false and the alert must Hide() even though focus is still casting.
----------------------------------------------------------------------------
local secretUnit = SecretSentinel.MakeSecretSentinel()
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", secretUnit, "guid-2", 1766)
assert(ok, "OnEvent must not throw on a secret unit token: " .. tostring(err))
assert(not alertFrame.shown,
    "a normal spellID must still be recorded even when the payload unit is secret/garbage " ..
    "(registration is already player-scoped; the payload unit arg is unused) -- alert should hide (interrupt on CD)")

----------------------------------------------------------------------------
-- Case 3: time advances past Kick's 15s base CD -- the CD entry recorded in
-- Case 2 must actually have been real (not a phantom skip): refreshing now
-- must bring the alert back.
----------------------------------------------------------------------------
now = now + 20
_G.QUI_RefreshFocusCastAlert()
assert(alertFrame.shown, "interrupt should be ready again once the recorded CD (from case 2) elapses")

----------------------------------------------------------------------------
-- Case 4: plain regression check -- normal unit, normal spellID, common case
-- still records the CD and hides the alert.
----------------------------------------------------------------------------
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-3", 1766)
assert(ok, "OnEvent must not throw on the common case: " .. tostring(err))
assert(not alertFrame.shown, "the common-case cast must still record the interrupt CD")

_G.issecretvalue = restoreIssecretvalue

print("OK: focuscastalert_spellcast_secret_boundary_test")
