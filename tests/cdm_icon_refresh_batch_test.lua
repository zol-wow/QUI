-- tests/cdm_icon_refresh_batch_test.lua
-- Run: lua tests/cdm_icon_refresh_batch_test.lua

local now = 120
function GetTime() return now end

local ns = {}
assert(loadfile("modules/cdm/cdm_icon_refresh_batch.lua"))("QUI", ns)
local module = assert(ns.CDMIconRefreshBatch, "icon refresh batch module should be exported")

local memprobes = {}
local beginCalls = 0
local endCalls = 0
local stackWrites = {}
local swipeRefreshes = 0
local ncdm = {
    essential = { iconDisplayMode = "always" },
    containers = {
        custom = { iconDisplayMode = "active" },
    },
}

local editMode = false
local layoutMode = true
local globalEditMode = false
local inCombat = true

local controller = module.Create({
    getMemProbes = function() return memprobes end,
    isEditModeActive = function() return editMode end,
    isLayoutModeActive = function() return layoutMode end,
    isGlobalEditModeActive = function() return globalEditMode end,
    getNCDM = function() return ncdm end,
    getTime = function() return now end,
    isInCombat = function() return inCombat end,
    refreshSwipeBatchSettings = function()
        swipeRefreshes = swipeRefreshes + 1
    end,
    beginRuntimeQueryBatch = function()
        beginCalls = beginCalls + 1
    end,
    endRuntimeQueryBatch = function()
        endCalls = endCalls + 1
    end,
    setStackTextWrites = function(enabled)
        stackWrites[#stackWrites + 1] = enabled
    end,
})

local batchEditMode, batchNCDM, batchContainers, batchInCombat = controller:Prepare()
assert(batchEditMode == true, "layout mode should mark the batch as edit-mode")
assert(batchNCDM == ncdm, "prepare should return the current ncdm table")
assert(batchContainers == ncdm.containers, "prepare should return custom containers")
assert(batchInCombat == true, "prepare should return combat state")
assert(controller:GetNCDM() == ncdm, "controller should retain current batch ncdm")
assert(controller:GetTime() == now, "controller should retain current batch time")
assert(swipeRefreshes == 1, "prepare should refresh swipe batch settings once")

controller:Begin("cooldownOnly")
controller:Begin("not-a-real-reason")
controller:End()
assert(beginCalls == 2, "begin should start runtime query batches")
assert(endCalls == 1, "end should close runtime query batches")
local stats = controller:GetStats()
assert(stats.cooldownOnly == 1, "known reasons should increment their own stat")
assert(stats.other == 1, "unknown reasons should increment other stat")

local foundCooldownProbe = false
for _, probe in ipairs(memprobes) do
    if probe.name == "CDM_iconBatch_cooldownOnly" then
        foundCooldownProbe = true
        assert(probe.fn() == 1, "memprobe should read live batch stats")
    end
end
assert(foundCooldownProbe, "batch module should register cooldown-only memprobe")

assert(controller:ConsumeStackTextWriteRequest() == false,
    "stack-text writes should default to not requested")
controller:RequestStackTextUpdate()
assert(controller:ConsumeStackTextWriteRequest() == true,
    "stack-text request should be consumed once")
assert(controller:ConsumeStackTextWriteRequest() == false,
    "stack-text request should clear after consume")

controller:SetStackTextWrites(true)
controller:SetStackTextWrites(false)
assert(stackWrites[1] == true and stackWrites[2] == false,
    "stack-text write gate should delegate to callback")

print("OK: cdm_icon_refresh_batch_test")
