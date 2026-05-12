-- tests/memaudit_cdm_cache_test.lua
-- Run: lua tests/memaudit_cdm_cache_test.lua

local printed = {}
local originalPrint = print
local now = 0
local inCombat = false
local addonKB = 1000
local frames = {}

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    printed[#printed + 1] = table.concat(parts, " ")
end

function GetTime()
    return now
end

function InCombatLockdown()
    return inCombat
end

function UpdateAddOnMemoryUsage() end

function GetAddOnMemoryUsage(addonName)
    assert(addonName == "QUI", "unexpected addon name")
    return addonKB
end

function CreateFrame()
    local frame = {
        scripts = {},
        shown = false,
        events = {},
    }
    function frame:Hide()
        self.shown = false
    end
    function frame:Show()
        self.shown = true
    end
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:SetScript(script, handler)
        self.scripts[script] = handler
    end
    frames[#frames + 1] = frame
    return frame
end

C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

local mirrorStates = 1
local packedStates = 1

local ns = {
    CDMSpellData = {
        GetCacheStats = function()
            return {
                capturedAuraEntries = 2,
                capturedAuraUnits = 1,
                capturedAuraSpellKeys = 2,
                capturedAuraNameKeys = 1,
                learnedSize = 3,
                tickAuraData = 4,
                tickAuraDuration = 5,
                tickAuraExpiration = 6,
                tickAuraApplication = 7,
                resolveIconMemo = 8,
                resolveAuraMemo = 9,
                totemSlotMap = 1,
            }
        end,
    },
    CDMIcons = {
        GetCacheStats = function()
            return {
                textureCycleCache = 2,
                activeIconPools = 3,
                activeIcons = 10,
                recycleIcons = 4,
            }
        end,
    },
    CDMBars = {
        GetCacheStats = function()
            return {
                activeBars = 5,
            }
        end,
    },
    CDMBlizzMirror = {
        GetCacheStats = function()
            return {
                mirrorStates = mirrorStates,
                packedStates = packedStates,
                childFrames = 1,
                cooldownInfo = 2,
                spellMapEntries = 3,
                directSpellMapEntries = 4,
                spellNameEntries = 5,
                totemSpellIDEntries = 6,
                activeTotems = 7,
            }
        end,
    },
    CDMRuntimeStore = {
        GetStats = function()
            return {
                states = 6,
            }
        end,
    },
    GetCDMFrameCacheStats = function()
        return {
            size = 11,
        }
    end,
}

assert(loadfile("QUI_Debug/memaudit.lua"))("QUI", ns)

local autoFrame = assert(frames[1], "memaudit should create an auto frame")
assert(type(_G.QUI_MemAudit) == "function", "memaudit slash handler should be exported")

_G.QUI_MemAudit("auto", "1")

inCombat = true
now = 1
autoFrame.scripts.OnEvent(autoFrame, "PLAYER_REGEN_DISABLED")

mirrorStates = 3
packedStates = 4
now = 2.1
autoFrame.scripts.OnUpdate(autoFrame, 1.1)

local foundCacheDelta = false
for _, line in ipairs(printed) do
    if line:find("CDM_cache_blizzMirror %+5", 1) then
        foundCacheDelta = true
        break
    end
end

assert(foundCacheDelta, "memaudit auto should report CDM cache growth even when total addon KB is flat")

originalPrint("OK: memaudit_cdm_cache_test")
