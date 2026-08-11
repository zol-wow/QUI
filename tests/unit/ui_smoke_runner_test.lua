-- tests/unit/ui_smoke_runner_test.lua
-- Run: lua tests/unit/ui_smoke_runner_test.lua

local originalPrint = print

local ns = {
    SkinBase = {},
}

local now = 100
_G.GetTime = function()
    return now
end

_G.InCombatLockdown = function()
    return false
end

_G.C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

assert(loadfile("QUI_Debug/ui_smoke.lua"))("QUI_Debug", ns)

local UISmoke = assert(ns.UISmoke, "ui smoke runner should export ns.UISmoke")

assert(UISmoke.ParseCommand("").action == "help", "empty command should show help")
assert(UISmoke.ParseCommand("list").action == "list", "list command should parse")
assert(UISmoke.ParseCommand("last").action == "last", "last command should parse")

local parsed = UISmoke.ParseCommand("run auctionhouse")
assert(parsed.action == "run", "run command should parse")
assert(parsed.suite == "auctionhouse", "run command should keep suite name")

parsed = UISmoke.ParseCommand("run all")
assert(parsed.action == "run", "run all command should parse")
assert(parsed.suite == "all", "run all should keep all target")

local bad = UISmoke.ParseCommand("run")
assert(bad.action == "help", "run without suite should fall back to help")
assert(bad.error and bad.error:find("suite", 1, true), "bad run should explain missing suite")

local suites = UISmoke.ListSuites()
local hasAuctionHouse = false
for _, name in ipairs(suites) do
    if name == "auctionhouse" then
        hasAuctionHouse = true
    end
end
assert(hasAuctionHouse, "auctionhouse smoke suite should be registered")

assert(UISmoke.RegisterSuite("unit_pass", function(ctx)
    ctx:Step("passes", function()
        ctx:Assert(true, "expected true")
    end)
end), "registering a unit suite should succeed")

now = 101
local passResult = UISmoke.RunSuite("unit_pass", { quiet = true })
assert(passResult.status == "PASS", "passing suite should pass")
assert(passResult.passed == 1, "passing suite should count passed step")
assert(passResult.failed == 0, "passing suite should count no failures")
assert(UISmoke.GetLastResult() == passResult, "run should store last result")

assert(UISmoke.RegisterSuite("unit_fail", function(ctx)
    ctx:Step("fails", function()
        ctx:Assert(false, "expected failure", { frame = "UnitFrame", shown = false })
    end)
end), "registering a failing unit suite should succeed")

now = 102
local failResult = UISmoke.RunSuite("unit_fail", { quiet = true })
assert(failResult.status == "FAIL", "failing suite should fail")
assert(failResult.failed == 1, "failing suite should count failed step")
assert(failResult.failures[1].message == "expected failure", "first failure should keep message")
assert(failResult.failures[1].details.frame == "UnitFrame", "failure details should be preserved")

local lines = UISmoke.FormatResult(failResult)
assert(lines[1]:find("FAIL", 1, true), "summary should include FAIL")
assert(lines[1]:find("unit_fail", 1, true), "summary should include suite name")
assert(lines[1]:find("expected failure", 1, true), "summary should include first failure")
assert(table.concat(lines, "\n"):find("frame=UnitFrame", 1, true), "detail lines should include fields")

local printed = {}
UISmoke.HandleSlash("last", {
    print = function(line)
        printed[#printed + 1] = line
    end,
})
assert(#printed > 0, "last command should print the stored result")
assert(printed[1]:find("unit_fail", 1, true), "last command should print last suite name")

for name in pairs(UISmoke._suites) do
    UISmoke._suites[name] = nil
end

assert(UISmoke.RegisterSuite("all_one", function(ctx)
    ctx:Step("one", function()
        ctx:Assert(true, "one passed")
    end)
end), "registering all_one should succeed")

assert(UISmoke.RegisterSuite("all_two", function(ctx)
    ctx:Step("two", function()
        ctx:Assert(true, "two passed")
    end)
end), "registering all_two should succeed")

now = 103
local allResult = UISmoke.RunSuite("all", { quiet = true })
assert(allResult.status == "PASS", "run all should pass when every suite passes")
assert(allResult.passed == 2, "run all should count each synchronous suite once")
assert(allResult.failed == 0, "run all should not add phantom failures")
assert(#allResult.steps == 2, "run all should report one aggregate step per suite")

_G.C_Timer.After = function(_, callback)
    now = now + 1
    callback()
end

assert(UISmoke.RegisterSuite("wait_fail", function(ctx)
    ctx:WaitFor("never ready", function()
        return false
    end, 0.5, 0.1)
end), "registering wait_fail should succeed")

now = 200
local waitResult = UISmoke.RunSuite("wait_fail", { quiet = true })
assert(waitResult.status == "FAIL", "timed-out wait should fail the suite")
assert(waitResult.failed == 1, "timed-out wait should count as a failed step")
assert(waitResult.failures[1].step == "never ready", "timed-out wait should keep step name")

originalPrint("OK: ui_smoke_runner_test")
