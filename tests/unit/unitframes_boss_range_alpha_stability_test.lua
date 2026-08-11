-- tests/unit/unitframes_boss_range_alpha_stability_test.lua
-- Run: lua tests/unit/unitframes_boss_range_alpha_stability_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local source = readAll("QUI_UnitFrames/unitframes/unitframes.lua")

local startPos = assert(source:find("local bossRange = {", 1, true),
    "Boss Range Alpha section should exist")
local endPos = assert(source:find("local function CreateUnitFrame(", startPos, true),
    "Boss Range Alpha section should end before CreateUnitFrame")
local body = source:sub(startPos, endPos)

-- Event-driven design: range alpha is driven by the engine's edge-triggered
-- UNIT_IN_RANGE_UPDATE event, never by a polling ticker. The secret in-range
-- payload is resolved by a secret-safe sink, so there is no per-tick flicker.
assert(body:find('RegisterUnitEvent("UNIT_IN_RANGE_UPDATE"', 1, true),
    "boss range alpha should register the per-unit UNIT_IN_RANGE_UPDATE event")
-- SecretPayloads = true: the payload unit is ALWAYS secret, so the design is
-- one listener per LEXICAL boss token, never payload-keyed dispatch.
assert(body:find('local token = "boss" .. i', 1, true),
    "boss range alpha should build one listener per lexical boss token")
assert(body:find("QUI_UF.frames[token]", 1, true),
    "boss range handler must index frames by the lexical token, not the secret payload unit")
assert(body:find("isInRange", 1, true),
    "boss range alpha should consume the UNIT_IN_RANGE_UPDATE isInRange payload")
assert(body:find("EvaluateColorValueFromBoolean", 1, true),
    "boss range alpha should resolve the secret in-range bool via the C_CurveUtil sink")
assert(not body:find("C_Timer.NewTicker", 1, true),
    "boss range alpha must be event-driven, not polled on a ticker")
assert(not body:find("IsSpellInRange", 1, true),
    "event-driven boss range alpha must not poll spell range each tick")
assert(not body:find("BOSS_RANGE_CHANGE_CONFIRMATIONS", 1, true),
    "event-driven boss range alpha has no debounce-confirmation counter")

do
    local rangeStart = assert(source:find("local bossRange = {", 1, true),
        "boss range alpha state table should exist")
    local rangeEnd = assert(source:find("local function CreateUnitFrame(",
        rangeStart, true), "boss range alpha section should end before CreateUnitFrame")
    local loader = loadstring or load
    local chunk = "local UpdateBossRangeAlpha, SeedBossFrameRangeAlpha\n"
        .. source:sub(rangeStart, rangeEnd - 1)
        .. "\nreturn { StartBossRangeCheck = StartBossRangeCheck,"
        .. " UpdateBossRangeAlpha = UpdateBossRangeAlpha,"
        .. " SeedBossFrameRangeAlpha = SeedBossFrameRangeAlpha }"

    local boss1Alpha
    local bossFrame = {
        unit = "boss1",
        SetAlpha = function(_, alpha) boss1Alpha = alpha end,
    }

    Helpers = {
        IsLayoutModeActive = function() return false end,
    }
    QUI_UF = {
        frames = { boss1 = bossFrame },
        -- Live code keeps unit tokens in weak side state (ping-taint fix);
        -- the stub mirrors the accessor over the mock's plain field.
        GetFrameUnit = function(frame) return frame and frame.unit end,
    }

    function GetUnitSettings()
        return { range = { enabled = true, outOfRangeAlpha = 0.4 } }
    end

    function UnitExists(unit)
        return unit == "boss1"
    end

    -- Secret-safe sink: resolve the (possibly secret) boolean to an alpha.
    C_CurveUtil = {
        EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
            if value then return ifTrue end
            return ifFalse
        end,
    }

    -- A polling ticker must never be created in the event-driven design.
    C_Timer = {
        NewTicker = function()
            error("boss range alpha must not create a polling ticker")
        end,
    }

    local createdFrames = {}
    function CreateFrame()
        local frame = { unitEvents = {}, events = {} }
        function frame:RegisterUnitEvent(event, ...)
            self.unitEvents[event] = { ... }
        end
        function frame:RegisterEvent(event)
            self.events[event] = true
        end
        function frame:SetScript(script, handler)
            if script == "OnEvent" then self.onEvent = handler end
        end
        createdFrames[#createdFrames + 1] = frame
        return frame
    end

    local api = assert(loader(chunk))()

    api.StartBossRangeCheck()
    -- One listener per lexical boss token (SecretPayloads: the payload unit
    -- is always secret; dispatch must never key on it), plus the shared
    -- transitions frame.
    local listeners = {}
    for _, frame in ipairs(createdFrames) do
        local reg = frame.unitEvents["UNIT_IN_RANGE_UPDATE"]
        if reg then
            assert(#reg == 1, "each range listener should register exactly one boss token")
            listeners[reg[1]] = frame
            assert(frame.onEvent, "each range listener should install an OnEvent handler")
        end
    end
    for i = 1, 5 do
        assert(listeners["boss" .. i],
            "UNIT_IN_RANGE_UPDATE should have a dedicated listener for boss" .. i)
    end
    assert(boss1Alpha == 1,
        "StartBossRangeCheck should baseline existing boss frames to full alpha")

    -- The payload unit is SECRET in-game: simulate with an opaque sentinel
    -- the handler must never consume (it uses the captured lexical token).
    local SECRET_UNIT = setmetatable({}, { __tostring = function() error("secret unit consumed") end })

    -- Out of range: dim to the configured out-of-range alpha (single apply, no flicker).
    local l1 = listeners.boss1
    l1.onEvent(l1, "UNIT_IN_RANGE_UPDATE", SECRET_UNIT, false)
    assert(boss1Alpha == 0.4,
        "out-of-range boss should dim to outOfRangeAlpha via the secret-safe sink")

    -- Back in range: restore full alpha.
    l1.onEvent(l1, "UNIT_IN_RANGE_UPDATE", SECRET_UNIT, true)
    assert(boss1Alpha == 1,
        "in-range boss should return to full alpha")

    -- A range update for an absent boss slot must not touch existing frames.
    local l3 = listeners.boss3
    l3.onEvent(l3, "UNIT_IN_RANGE_UPDATE", SECRET_UNIT, false)
    assert(boss1Alpha == 1,
        "range update for an absent boss slot should not change other frames")

    -- Spawn seed keeps the frame fully visible until the engine reports range.
    boss1Alpha = nil
    api.SeedBossFrameRangeAlpha(bossFrame)
    assert(boss1Alpha == 1,
        "a freshly spawned boss frame should seed to full alpha")
end

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

    -- Aura setup runs its full OOC path so the engage-frame assertions below
    -- exercise real event registration (not the deferred combat queue).
    function InCombatLockdown()
        return false
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
            -- Live code keeps unit tokens in weak side state (ping-taint fix);
            -- the stub mirrors the accessor over the mock's plain field.
            GetFrameUnit = function(frame) return frame and frame.unit end,
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
