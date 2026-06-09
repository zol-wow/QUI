-- tests/unit/unitframes_boss_range_alpha_stability_test.lua
-- Run: lua tests/unit/unitframes_boss_range_alpha_stability_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local source = readAll("QUI_UnitFrames/unitframes/unitframes.lua")

local startPos = assert(source:find("%-%- Boss Range Alpha"),
    "Boss Range Alpha section should exist")
local endPos = assert(source:find("%-%-%-+%s*\n%-%- CREATE: Unit Frame", startPos),
    "Boss Range Alpha section should end before CreateUnitFrame")
local body = source:sub(startPos, endPos)

assert(body:find("BOSS_RANGE_CHANGE_CONFIRMATIONS", 1, true),
    "boss range alpha should debounce range flips instead of applying single-sample changes")
assert(body:find("local inRange, checkedRange = UnitInRange(unit)", 1, true),
    "boss range fallback must read UnitInRange's checkedRange result")
assert(body:find("checkedRange == false", 1, true),
    "boss range fallback must treat unchecked UnitInRange results as indeterminate")
assert(body:find("return nil", body:find("checkedRange == false", 1, true), true),
    "unchecked boss range results should be skipped, not treated as in or out of range")
assert(body:find("if inRange == nil then", 1, true),
    "boss range alpha should skip indeterminate samples from spell range checks")
assert(body:find("bossRange.pending", 1, true),
    "boss range alpha should keep pending samples until a range change is stable")

local auraSource = readAll("QUI_UnitFrames/unitframes/unitframe_auras.lua")
assert(auraSource:find("local bossEngageFrame", 1, true),
    "boss engage aura refresh should use one shared event frame")
assert(not auraSource:find("bossEngageState", 1, true),
    "boss engage aura refresh must not cache per-slot boss GUIDs")
assert(not auraSource:find("UnitGUID", 1, true),
    "boss engage aura refresh must not read secret UnitGUID values")
assert(not auraSource:find("BossUnitStateChanged", 1, true),
    "boss engage aura refresh should not compare cached boss identity")
assert(auraSource:find("RefreshBossFrameForEngage", 1, true),
    "boss engage aura refresh should be scoped to boss frames")
assert(not auraSource:find('frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT"', 1, true),
    "boss frames should not each register the global engage event")
assert(auraSource:find('bossEngageFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT"', 1, true),
    "boss engage aura refresh should register the global event once")

do
    local createdFrames = {}

    local function newFrame(name)
        local frame = {
            name = name,
            events = {},
            unitEvents = {},
            scripts = {},
            hooks = {},
        }

        function frame:RegisterEvent(event)
            self.events[event] = true
        end

        function frame:RegisterUnitEvent(event, unit)
            self.unitEvents[event] = unit
        end

        function frame:GetScript(script)
            return self.scripts[script]
        end

        function frame:SetScript(script, handler)
            self.scripts[script] = handler
        end

        function frame:HookScript(script, handler)
            self.hooks[script] = self.hooks[script] or {}
            table.insert(self.hooks[script], handler)
        end

        function frame:Hide()
            self.hidden = true
        end

        return frame
    end

    function CreateFrame(frameType, name)
        local frame = newFrame(name or ("created" .. (#createdFrames + 1)))
        createdFrames[#createdFrames + 1] = frame
        return frame
    end

    local now = 100
    function GetTime()
        now = now + 1
        return now
    end

    local units = {}
    function UnitExists(unit)
        return units[unit] ~= nil
    end

    local unitGuidCalls = 0
    local secretGUIDMT = {
        __eq = function()
            error("attempted to compare a secret boss UnitGUID")
        end,
    }

    function UnitGUID(unit)
        unitGuidCalls = unitGuidCalls + 1
        local data = units[unit]
        return data and data.guid or nil
    end

    C_Timer = {
        After = function()
            -- Initial delayed aura refreshes are irrelevant to this event test.
        end,
    }

    C_UnitAuras = {
        GetAuraDataByIndex = function()
            return nil
        end,
    }

    local updateFrameCalls = {}
    local ns = {
        Addon = {},
        Helpers = {
            ApplyCooldownFromAura = function()
                return false
            end,
            CreateStateTable = function()
                return setmetatable({}, { __mode = "k" })
            end,
            IsSecretValue = function()
                return false
            end,
        },
        QUI_UnitFrames = {
            frames = {},
            auraPreviewMode = {},
            _GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end,
            _GetFontOutline = function() return "OUTLINE" end,
            _GetUnitSettings = function()
                return {
                    auras = {
                        showBuffs = true,
                        showDebuffs = true,
                    },
                }
            end,
            _UpdateFrame = function(frame)
                updateFrameCalls[#updateFrameCalls + 1] = frame.unit
            end,
        },
    }

    assert(loadfile("QUI_UnitFrames/unitframes/unitframe_auras.lua"))("QUI", ns)

    for i = 1, 5 do
        local key = "boss" .. i
        local frame = newFrame("unit-" .. key)
        frame.unit = key
        frame.unitKey = "boss"
        ns.QUI_UnitFrames.frames[key] = frame
        ns.QUI_UnitFrames.SetupAuraTracking(frame)
    end

    for i = 1, 5 do
        local key = "boss" .. i
        assert(not ns.QUI_UnitFrames.frames[key].events.INSTANCE_ENCOUNTER_ENGAGE_UNIT,
            "boss aura tracking should not register the global engage event on every boss frame")
    end

    local engageFrame
    for _, frame in ipairs(createdFrames) do
        if frame.events.INSTANCE_ENCOUNTER_ENGAGE_UNIT then
            assert(engageFrame == nil, "boss aura tracking should use exactly one shared engage event frame")
            engageFrame = frame
        end
    end

    assert(engageFrame and engageFrame.scripts.OnEvent,
        "boss aura tracking should install a shared engage event handler")

    units.boss1 = { guid = setmetatable({}, secretGUIDMT) }
    engageFrame.scripts.OnEvent(engageFrame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    assert(#updateFrameCalls == 1 and updateFrameCalls[1] == "boss1",
        "first engage should refresh only the newly available boss slot")

    engageFrame.scripts.OnEvent(engageFrame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    assert(#updateFrameCalls == 2 and updateFrameCalls[2] == "boss1",
        "duplicate engage events should refresh existing boss slots without GUID comparisons")

    units.boss2 = { guid = setmetatable({}, secretGUIDMT) }
    engageFrame.scripts.OnEvent(engageFrame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    assert(#updateFrameCalls == 4 and updateFrameCalls[3] == "boss1" and updateFrameCalls[4] == "boss2",
        "a later boss slot should refresh alongside existing boss slots")

    units.boss1 = nil
    engageFrame.scripts.OnEvent(engageFrame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    assert(#updateFrameCalls == 5 and updateFrameCalls[5] == "boss2",
        "despawning boss slots should skip UpdateFrame while existing boss slots refresh")

    assert(unitGuidCalls == 0,
        "boss engage aura refresh must never read UnitGUID secret values")
end

print("OK: unitframes_boss_range_alpha_stability_test")
