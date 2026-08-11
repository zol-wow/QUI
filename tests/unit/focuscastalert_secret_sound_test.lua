-- tests/unit/focuscastalert_secret_sound_test.lua
-- Run: lua tests/unit/focuscastalert_secret_sound_test.lua
--
-- Regression guard: when cast interruptibility is a secret value, the alert can
-- still become visible through SetAlphaFromBoolean. The sound cue must not be
-- dropped solely because Lua cannot compare that secret boolean.
-- luacheck: globals CreateFrame UIParent UnitExists UnitCanAttack UnitCastingInfo UnitChannelInfo UnitClass IsPlayerSpell GetTime C_Timer PlaySoundFile

local secret = { __secret = "notInterruptible" }
local soundsPlayed = 0
local eventFrame
local alertFrame

local function newFrame(name)
    local frame = {
        name = name,
        shown = false,
        alpha = 1,
        points = {},
    }

    function frame:SetSize(width, height) self.width = width; self.height = height end
    function frame:SetFrameStrata(strata) self.frameStrata = strata end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:IsShown() return self.shown end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)
        self.alphaFromBoolean = { value = value, alphaIfTrue = alphaIfTrue, alphaIfFalse = alphaIfFalse }
    end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function frame:RegisterUnitEvent(event, ...) self.unitEvents = self.unitEvents or {}; self.unitEvents[event] = { ... } end
    function frame:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    function frame:SetScript(scriptName, handler) self.scripts = self.scripts or {}; self.scripts[scriptName] = handler end
    function frame:CreateFontString()
        local fs = {}
        function fs:SetPoint() end
        function fs:SetJustifyH() end
        function fs:SetJustifyV() end
        function fs:SetFont() return true end
        function fs:SetText(text) self.text = text end
        function fs:SetFormattedText(format, ...) self.text = string.format(format, ...) end
        function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
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
        return "Frostbolt", "Frostbolt", 135846, 100000, 103000, false, "CastGUID", secret, 116, nil, 0
    end
    return nil
end
function UnitChannelInfo() return nil end
function UnitClass(unit)
    if unit == "player" then return "Player", "MAGE" end
    return nil
end
function IsPlayerSpell(spellID) return spellID == 2139 end
function GetTime() return 100 end
function PlaySoundFile(path, channel)
    assert(path == "Interface\\AddOns\\QUI\\sounds\\alert.ogg", "unexpected sound path: " .. tostring(path))
    assert(channel == "Master", "focus cast alert should play on Master")
    soundsPlayed = soundsPlayed + 1
end

C_Timer = {
    NewTicker = function()
        return { Cancel = function() end }
    end,
}

local settings = {
    enabled = true,
    text = "Focus is casting. Kick!",
    soundEnabled = true,
    sound = "Alert",
}

local ns = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Helpers = {
        SafeToString = function(value, fallback) return value == nil and fallback or tostring(value) end,
        IsSecretValue = function(value) return value == secret end,
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
        Fetch = function(_, kind, name)
            assert(kind == "sound", "expected sound media lookup")
            assert(name == "Alert", "expected configured sound")
            return "Interface\\AddOns\\QUI\\sounds\\alert.ogg"
        end,
    },
    SafeCall = function(_policy, fn, ...)
        return pcall(fn, ...)
    end,
    SafeCallMethod = function(_policy, obj, name, ...)
        return pcall(function(...) return obj[name](obj, ...) end, ...)
    end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}

assert(loadfile("modules/qol/focuscastalert.lua"))("QUI", ns)
assert(eventFrame and eventFrame.scripts and eventFrame.scripts.OnEvent, "focus cast alert event handler missing")

eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_START", "focus", "CastGUID", 116)
assert(alertFrame and alertFrame.shown, "focus cast alert frame should be shown for active cast")
assert(alertFrame.alphaFromBoolean and alertFrame.alphaFromBoolean.value == secret,
    "secret interruptibility should be passed to SetAlphaFromBoolean")
-- Audio is Lua-only logic with no absorbing C-sink: a SECRET flag is
-- indeterminate, and playing on it could announce a secretly
-- NON-interruptible cast. No sound until READABLE evidence arrives.
assert(soundsPlayed == 0, "secret interruptibility must NOT trigger the sound, got " .. soundsPlayed)

_G.QUI_RefreshFocusCastAlert()
assert(soundsPlayed == 0, "refresh polling must not play on a still-secret flag")

-- UNIT_SPELLCAST_INTERRUPTIBLE stores a PLAIN false — that is the readable
-- evidence the audio path requires.
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_INTERRUPTIBLE", "focus")
assert(soundsPlayed == 1, "readable interruptible evidence should play exactly one sound, got " .. soundsPlayed)

_G.QUI_RefreshFocusCastAlert()
assert(soundsPlayed == 1, "refresh polling should not replay a latched focus cast sound")

print("OK: focuscastalert_secret_sound_test")
