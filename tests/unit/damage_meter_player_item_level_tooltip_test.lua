local timerQueue = {}
local eventFrames = {}
local guid = "Player-1-ABCDEF"
local notifyCalls = {}
local callbackCalls = {}

C_Timer = {
    After = function(_, callback) timerQueue[#timerQueue + 1] = callback end,
    NewTimer = function() return { Cancel = function() end } end,
}
function GetTime() return 1000 end
function InCombatLockdown() return false end
function UnitExists(unit) return unit == "raid2" end
function UnitGUID(unit) return unit == "raid2" and guid or nil end
function UnitIsPlayer(unit) return unit == "raid2" end
function UnitIsUnit(a, b) return a == b end
function UnitClass() return "Mage", "MAGE", 8 end
function CanInspect() return true end
function NotifyInspect(unit) notifyCalls[#notifyCalls + 1] = unit end
function ClearInspectPlayer() end
function GetInspectSpecialization() return 63 end
function GetSpecializationInfoByID() return 63, "Fire" end

local slot = 0
for _, name in ipairs({
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WAIST", "LEGS", "FEET",
    "WRIST", "HAND", "FINGER1", "FINGER2", "TRINKET1", "TRINKET2", "MAINHAND", "OFFHAND",
}) do
    slot = slot + 1
    _G["INVSLOT_" .. name] = slot
end

C_PaperDollInfo = { GetInspectItemLevel = function(unit)
    assert(unit == "raid2")
    return 678.5
end }
GameTooltip = { IsForbidden = function() return false end, GetUnit = function() return nil, nil end }

function CreateFrame()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(script, handler)
        if script == "OnEvent" then
            self.OnEvent = handler
            eventFrames[#eventFrames + 1] = self
        end
    end
    return frame
end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        SafeCompare = function(a, b) return a == b end,
    },
    SafeCall = function(_, fn, ...)
        local ok, result = pcall(fn, ...)
        return ok, result
    end,
}

assert(loadfile("modules/qol/tooltip_inspect.lua"))("QUI", ns)
local inspect = assert(ns.TooltipInspect)
assert(inspect:RegisterRefreshCallback(function(_, data) callbackCalls[#callbackCalls + 1] = data.itemLevel end))
assert(inspect:RegisterRefreshCallback(function(_, data) callbackCalls[#callbackCalls + 1] = data.itemLevel end))

assert(inspect:GetPlayerDataByGUID(guid) == nil)
assert(#timerQueue == 1)
timerQueue[1]()
assert(notifyCalls[1] == "raid2")

for _, frame in ipairs(eventFrames) do
    if frame.events.INSPECT_READY then frame:OnEvent("INSPECT_READY", guid) end
end

local data = assert(inspect:GetPlayerDataByGUID(guid))
assert(data.itemLevel == 678.5)
assert(callbackCalls[1] == 678.5 and callbackCalls[2] == 678.5)

local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local tooltip = read("modules/qol/tooltip.lua")
local meter = read("QUI_DamageMeter/damage_meter/damage_meter.lua")
assert(tooltip:find("ns.QUI_AddPlayerItemLevelByGUIDToTooltip = AddPlayerItemLevelByGUIDToTooltip", 1, true))
assert(meter:find("addPlayerItemLevel(GameTooltip, src.sourceGUID, true, true)", 1, true))
assert(meter:find("ns.TooltipInspect:RegisterRefreshCallback", 1, true))

print("PASS damage_meter_player_item_level_tooltip_test")
