-- luacheck: globals issecretvalue

local sentinel = dofile("tests/helpers/secret_sentinel.lua")
local instrument = dofile("tests/helpers/secret_instrument.lua")

local prev = sentinel.InstallSecretStub()

local source
do
    local f = assert(io.open("modules/dungeon/mplus_timer.lua", "r"))
    source = f:read("*a")
    f:close()
end

local beginMark = "-- >>> QUI_TEST_EXTRACT mplus_objectives_secret"
local endMark = "-- <<< QUI_TEST_EXTRACT mplus_objectives_secret"
local s = assert(source:find(beginMark, 1, true), "begin sentinel")
local e = assert(source:find(endMark, 1, true), "end sentinel")
local slice = source:sub(s + #beginMark, e - 1)

local function NewHarness(criteria, stepInfo)
    local env = setmetatable({
        MPlusTimer = nil,
        C_ScenarioInfo = {
            GetScenarioStepInfo = function() return stepInfo end,
            GetCriteriaInfo = function(i) return criteria[i] end,
        },
    }, { __index = _G })

    local timer = {
        state = {
            timer = 0,
            objectivesList = {},
            objectivesByIndex = {},
            weightedByIndex = {},
        },
    }
    env.MPlusTimer = timer

    function timer:SetObjectives(objectives)
        self.captureObjectives = objectives
    end

    function timer:SetForces(quantity, total, quantityString)
        self.captureForces = { quantity = quantity, total = total, quantityString = quantityString }
    end

    local chunk, err = instrument.loadString(slice, "mplus_objectives_secret")
    assert(chunk, err)
    setfenv(chunk, env)
    chunk()

    return timer
end

do
    local criteria = {
        { description = "Boss A", completed = false, isWeightedProgress = false },
        { description = "Boss B", completed = true, isWeightedProgress = false },
        { description = "Enemy Forces", completed = false, isWeightedProgress = true,
          quantity = 42.5, totalQuantity = 300, quantityString = "128/300" },
    }
    local timer = NewHarness(criteria, { numCriteria = 3 })
    timer.state.timer = 100

    timer:UpdateObjectives()

    assert(timer.captureObjectives, "plain pass reaches SetObjectives")
    assert(#timer.captureObjectives == 2, "weighted criteria excluded from boss list")
    assert(timer.captureObjectives[1].name == "Boss A")
    assert(timer.captureObjectives[1].time == nil)
    assert(timer.captureObjectives[2].time == 100, "completed boss stamped with current timer")
    assert(timer.state.forcesIndex == 3)
    assert(timer.state.plainNumCriteria == 3)
    assert(timer.state.weightedByIndex[1] == false)
    assert(timer.state.weightedByIndex[3] == true)

    timer:UpdateForces()
    assert(timer.captureForces.quantity == 42.5)
    assert(timer.captureForces.total == 300)
    assert(timer.captureForces.quantityString == "128/300")

    timer.state.timer = 200
    timer:UpdateObjectives()
    assert(timer.captureObjectives[2].time == 100, "split time survives later passes")
end

do
    local secretName = sentinel.MakeSecretSentinel()
    local criteria = {
        { description = "Boss A", completed = sentinel.MakeSecretSentinel(),
          isWeightedProgress = sentinel.MakeSecretSentinel() },
        { description = secretName, completed = sentinel.MakeSecretSentinel(),
          isWeightedProgress = sentinel.MakeSecretSentinel() },
        { description = "Enemy Forces", completed = false,
          isWeightedProgress = sentinel.MakeSecretSentinel() },
    }
    local timer = NewHarness(criteria, { numCriteria = sentinel.MakeSecretSentinel() })
    timer.state.plainNumCriteria = 3
    timer.state.weightedByIndex = { false, false, true }
    timer.state.objectivesByIndex = { {}, { name = "Boss B", time = 55 }, {} }
    timer.state.forcesIndex = nil
    timer.state.timer = 300

    local ok, err = pcall(function() timer:UpdateObjectives() end)
    assert(ok, "secret storm must not throw: " .. tostring(err))

    assert(timer.captureObjectives and #timer.captureObjectives == 2)
    assert(timer.captureObjectives[2].time == 55, "secret completed holds prior split")
    assert(rawequal(timer.captureObjectives[2].name, secretName), "secret name passed along raw")
    assert(timer.state.forcesIndex == 3, "cached weighted flag still routes forces index")
    assert(timer.state.plainNumCriteria == 3)
end

do
    local secretQuantity = sentinel.MakeSecretSentinel()
    local secretQuantityString = sentinel.MakeSecretSentinel()
    local secretTotal = sentinel.MakeSecretSentinel()
    local criteria = {
        { description = "Enemy Forces", completed = false, isWeightedProgress = true,
          quantity = secretQuantity, totalQuantity = secretTotal, quantityString = secretQuantityString },
    }
    local timer = NewHarness(criteria, { numCriteria = 1 })
    timer.state.forcesIndex = 1

    local ok, err = pcall(function() timer:UpdateForces() end)
    assert(ok, "secret forces fields must not throw: " .. tostring(err))
    assert(timer.captureForces, "secret fields still reach the sink path")
    assert(rawequal(timer.captureForces.quantity, secretQuantity), "quantity passed along raw")
    assert(rawequal(timer.captureForces.total, secretTotal), "totalQuantity passed along raw")
    assert(rawequal(timer.captureForces.quantityString, secretQuantityString), "quantityString passed along raw")
end

do
    local timer = NewHarness({}, { numCriteria = sentinel.MakeSecretSentinel() })

    local ok, err = pcall(function() timer:UpdateObjectives() end)
    assert(ok, "no plain count yet must not throw: " .. tostring(err))
    assert(timer.captureObjectives == nil, "list held when structure is unreadable")
end

sentinel.RestoreSecretStub(prev)
print("mplus_timer_objectives_secret_test: OK")
