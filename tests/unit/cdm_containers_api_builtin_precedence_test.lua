local file = assert(io.open("QUI_CDM/cdm/cdm_containers.lua", "rb"))
local source = file:read("*a")
file:close()

local startAt = assert(source:find("function CDMContainers_API:GetContainers()", 1, true))
local endAt = assert(source:find("function CDMContainers_API:CreateContainer", startAt, true))
local apiSource = source:sub(startAt, endAt - 1)

local activeEssential = { containerType = "cooldown", marker = "active" }
local staleEssential = { containerType = "cooldown", marker = "stale" }
local custom = { containerType = "customBar", marker = "custom" }
local db = {
    essential = activeEssential,
    containers = {
        essential = staleEssential,
        custom = custom,
    },
}

local chunk = assert(loadstring([[
local db = ...
local BUILTIN_KEYS = { "essential", "utility", "buff", "trackedBar" }
local BUILTIN_NAMES = { essential = true, utility = true, buff = true, trackedBar = true }
local CDMContainers_API = {}
local function GetDB() return db end
local Shared = { IsBuiltinContainerKey = function(key) return BUILTIN_NAMES[key] == true end }
]] .. apiSource .. [[
return CDMContainers_API
]], "@cdm_containers_api"))
local api = chunk(db)
local containers = api:GetContainers()

assert(containers[1].key == "essential" and containers[1].settings == activeEssential)
assert(containers[2].key == "custom" and containers[2].settings == custom)
assert(api:GetContainerSettings("essential") == activeEssential)
assert(api:GetContainersByType("cooldown")[1].settings == activeEssential)

print("OK: cdm_containers_api_builtin_precedence_test")
