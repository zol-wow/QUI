-- tests/unit/encounter_journal_monthly_text_test.lua
-- Run: lua tests/unit/encounter_journal_monthly_text_test.lua
--
-- The Encounter Journal monthly activities panel creates and refreshes its
-- activity rows, filter rows, and threshold reward text after the top-level
-- journal skin pass. Those updates must re-apply QUI text styling.

-- luacheck: globals _G C_Timer hooksecurefunc MonthlyActivitiesFrameMixin

MonthlyActivitiesFrameMixin = {
    OnShow = function() end,
    UpdateActivities = function() end,
    SetActivities = function() end,
    SetThresholds = function() end,
    SetRewardsEarnedAndCollected = function() end,
    UpdateTime = function() end,
}

C_Timer = { After = function(_, fn) fn() end }

local namedHooks = {}
local tableHooks = {}
function hooksecurefunc(target, methodOrCallback, callback)
    if type(target) == "string" then
        namedHooks[target] = methodOrCallback
        return
    end

    tableHooks[target] = tableHooks[target] or {}
    tableHooks[target][methodOrCallback] = callback
end

local callbacks = {}
local calls = {}
local scrollHooks = {}
local frameData = setmetatable({}, { __mode = "k" })

local activityTextContainer = {
    name = "activityTextContainer",
    UpdateTextColor = function() end,
}
local activityRow = {
    name = "activityRow",
    TextContainer = activityTextContainer,
    UpdateButtonStateShared = function() end,
}
local filterRow = {
    name = "filterRow",
    UpdateStateInternal = function() end,
}
local thresholdFrame = {
    name = "thresholdFrame",
    RewardCurrency = {
        name = "rewardCurrency",
        SetThresholdInfo = function() end,
    },
}

local activityScrollBox = {
    name = "activityScrollBox",
    ForEachFrame = function(_, callback)
        callback(activityRow)
    end,
}

local filterScrollBox = {
    name = "filterScrollBox",
    ForEachFrame = function(_, callback)
        callback(filterRow)
    end,
}

local monthlyFrame = {
    name = "MonthlyActivitiesFrame",
    HeaderContainer = { name = "HeaderContainer" },
    ThresholdContainer = { name = "ThresholdContainer" },
    BarComplete = { name = "BarComplete" },
    FilterList = { name = "FilterList", ScrollBox = filterScrollBox },
    ScrollBox = activityScrollBox,
    thresholdFrames = { thresholdFrame },
    OnShow = function() end,
    UpdateActivities = function() end,
    SetActivities = function() end,
    SetThresholds = function() end,
    SetRewardsEarnedAndCollected = function() end,
    UpdateTime = function() end,
}

_G.EncounterJournal = {
    name = "EncounterJournal",
    MonthlyActivitiesFrame = monthlyFrame,
    encounter = {
        infoFrame = { name = "infoFrame" },
        overviewFrame = { name = "overviewFrame" },
    },
}

local ns = {
    Helpers = {
        GetCore = function()
            return {
                db = {
                    profile = {
                        general = {
                            skinEncounterJournal = true,
                        },
                    },
                },
            }
        end,
    },
    Registry = {
        Register = function() end,
    },
}

ns.SkinBase = {
    RefreshFrameBackdropColors = function() end,
    IsSkinned = function() return false end,
    SkinButtonFrameTemplate = function(frame)
        calls.buttonFrame = frame
    end,
    SkinFrameText = function(frame, opts)
        calls[frame] = opts or {}
    end,
    MarkSkinned = function(frame)
        calls.marked = frame
    end,
    SetFrameData = function(frame, key, value)
        frameData[frame] = frameData[frame] or {}
        frameData[frame][key] = value
    end,
    GetFrameData = function(frame, key)
        local data = frameData[frame]
        return data and data[key]
    end,
    HookScrollBoxAcquired = function(scrollBox, callback)
        if not scrollBox then return end
        scrollHooks[scrollBox] = callback
    end,
    OnAddOnLoaded = function(addon, callback)
        callbacks[addon] = callback
    end,
}

assert(loadfile("modules/skinning/frames/journals.lua"))("QUI", ns)
assert(type(callbacks.Blizzard_EncounterJournal) == "function", "Encounter Journal load hook must be registered")

callbacks.Blizzard_EncounterJournal()

local function AssertChromeText(frame, message)
    assert(calls[frame] and calls[frame].recurse == true and calls[frame].chrome == true, message)
end

AssertChromeText(monthlyFrame, "monthly activities frame must receive recursive QUI text styling")
AssertChromeText(monthlyFrame.HeaderContainer, "monthly header text must receive QUI text styling")
AssertChromeText(thresholdFrame.RewardCurrency, "monthly threshold reward text must receive QUI text styling")
AssertChromeText(activityRow, "existing monthly activity rows must receive QUI text styling")
AssertChromeText(activityRow.TextContainer, "monthly activity row text containers must receive QUI text styling")
AssertChromeText(filterRow, "existing monthly filter rows must receive QUI text styling")

assert(scrollHooks[activityScrollBox], "monthly activity ScrollBox must style acquired rows")
assert(scrollHooks[filterScrollBox], "monthly filter ScrollBox must style acquired rows")

calls = {}
scrollHooks[activityScrollBox](activityRow)
AssertChromeText(activityRow, "acquired monthly activity rows must receive QUI text styling")
AssertChromeText(activityRow.TextContainer, "acquired monthly activity text containers must receive QUI text styling")

calls = {}
scrollHooks[filterScrollBox](filterRow)
AssertChromeText(filterRow, "acquired monthly filter rows must receive QUI text styling")

assert(tableHooks[MonthlyActivitiesFrameMixin]
    and tableHooks[MonthlyActivitiesFrameMixin].UpdateActivities,
    "monthly activity frame mixin refreshes must be hooked as a fallback")
assert(tableHooks[monthlyFrame]
    and tableHooks[monthlyFrame].UpdateActivities,
    "monthly activity frame instance refreshes must be hooked")
assert(tableHooks[activityRow]
    and tableHooks[activityRow].UpdateButtonStateShared,
    "monthly activity row instance state refreshes must be hooked")
assert(tableHooks[activityRow.TextContainer]
    and tableHooks[activityRow.TextContainer].UpdateTextColor,
    "monthly activity text container instance refreshes must be hooked")
assert(tableHooks[filterRow]
    and tableHooks[filterRow].UpdateStateInternal,
    "monthly filter row instance state refreshes must be hooked")
assert(tableHooks[thresholdFrame.RewardCurrency]
    and tableHooks[thresholdFrame.RewardCurrency].SetThresholdInfo,
    "monthly threshold reward instance refreshes must be hooked")

calls = {}
tableHooks[monthlyFrame].UpdateActivities(monthlyFrame)
AssertChromeText(monthlyFrame, "monthly frame updates must reskin the monthly text tree")
AssertChromeText(activityRow, "monthly frame updates must reskin visible activity rows")
AssertChromeText(filterRow, "monthly frame updates must reskin visible filter rows")

calls = {}
tableHooks[activityRow].UpdateButtonStateShared(activityRow)
AssertChromeText(activityRow, "monthly row state updates must reskin the refreshed row")
assert(not calls[monthlyFrame], "monthly row state updates should not rescan the entire monthly frame")

calls = {}
tableHooks[activityRow.TextContainer].UpdateTextColor(activityRow.TextContainer)
AssertChromeText(activityRow.TextContainer, "monthly row text color updates must reskin the text container")

calls = {}
tableHooks[filterRow].UpdateStateInternal(filterRow)
AssertChromeText(filterRow, "monthly filter state updates must reskin the refreshed filter row")

calls = {}
tableHooks[thresholdFrame.RewardCurrency].SetThresholdInfo(thresholdFrame.RewardCurrency)
AssertChromeText(thresholdFrame.RewardCurrency, "monthly threshold reward updates must reskin reward text")

print("OK: encounter_journal_monthly_text_test")
