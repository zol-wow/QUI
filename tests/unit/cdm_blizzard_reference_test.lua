-- tests/unit/cdm_blizzard_reference_test.lua
-- Run: lua tests/unit/cdm_blizzard_reference_test.lua

local reference = dofile("tests/api-docs/cdm_blizzard_reference.lua")
local apiIndex = dofile("tests/api-docs/api-index.lua")

local function readFile(path)
    local f = assert(io.open(path, "rb"), "missing file: " .. tostring(path))
    local src = f:read("*a")
    f:close()
    return src
end

local function assertContains(source, needle, message)
    if not source:find(needle, 1, true) then
        error(message or ("missing text: " .. needle), 2)
    end
end

local function functionBlock(docKey, functionName)
    local path = assert(reference.sourceDocs[docKey], "unknown doc key: " .. tostring(docKey))
    local source = readFile(path)
    local marker = 'Name = "' .. functionName .. '"'
    local start = assert(source:find(marker, 1, true),
        "missing " .. functionName .. " in " .. path)
    return source:sub(start, start + 1200)
end

for _, path in pairs(reference.sourceDocs) do
    readFile(path)
end

for functionName, expected in pairs(reference.apiIndexContracts) do
    local meta = assert(apiIndex[functionName], "missing API index entry: " .. functionName)
    if expected.secretArguments then
        assert(meta.secretArguments == expected.secretArguments,
            functionName .. " secretArguments mismatch")
    end
end

for functionName, spec in pairs(reference.durationObjectSources) do
    local block = functionBlock(spec.doc, spec.runtimeName or functionName:match("[^.]+$") or functionName)
    assertContains(block, "Type = \"LuaDurationObject\"",
        functionName .. " should return LuaDurationObject")
end

for methodName, spec in pairs(reference.durationObjectSinks) do
    local block = functionBlock(spec.doc, methodName)
    assertContains(block, "Type = \"LuaDurationObject\"",
        methodName .. " should accept LuaDurationObject")
end

for _, methodName in ipairs(reference.cooldownFrame.unsafeSecretSetters) do
    local block = functionBlock("cooldownFrame", methodName)
    assertContains(block, "SecretArgumentsAddAspect = { Enum.SecretAspect.Cooldown }",
        methodName .. " should add the cooldown secret aspect")
    assertContains(block, "SecretArguments = \"AllowedWhenUntainted\"",
        methodName .. " should be untained-only for secret args")
end

do
    local spec = reference.secretBooleanDecode
    local block = functionBlock(spec.doc, spec.docFunctionName)
    assertContains(block, "SecretArguments = \"" .. spec.secretArguments .. "\"",
        "CurveUtil boolean decode should allow tainted secret arguments")
    assertContains(block, "Type = \"" .. spec.returnType .. "\"",
        "CurveUtil boolean decode return type mismatch")
end

local function discoverCdmLuaFiles()
    local files = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd
    if isWindows then
        cmd = 'cmd /c "dir /s /b QUI_CDM\\cdm\\*.lua 2>nul"'
    else
        cmd = 'find "QUI_CDM/cdm" -type f -name "*.lua"'
    end
    local p = assert(io.popen(cmd, "r"))
    for line in p:lines() do
        line = line:gsub("\\", "/")
        local rel = line:match("(QUI_CDM/cdm/.*)$") or line
        files[#files + 1] = rel
    end
    p:close()
    return files
end

local unsafeSetters = {}
for _, methodName in ipairs(reference.cooldownFrame.unsafeSecretSetters) do
    unsafeSetters[methodName] = true
end

local directCalls = {}
for _, path in ipairs(discoverCdmLuaFiles()) do
    local lineNo = 0
    local source = readFile(path)
    for line in (source .. "\n"):gmatch("(.-)\n") do
        lineNo = lineNo + 1
        local code = line:gsub("%-%-.*$", "")
        for methodName in pairs(unsafeSetters) do
            if code:find("[%.:]" .. methodName .. "%s*%(") then
                directCalls[#directCalls + 1] = {
                    path = path,
                    line = lineNo,
                    method = methodName,
                }
            end
        end
    end
end

local allowedNumeric = reference.cooldownFrame.numericFallback
local allowedSites = allowedNumeric.allowedCallSites or {}
-- Preview-only exception sites may call SetCooldown directly any number
-- of times (out-of-combat, never secret-derived, never reaches runtime).
local previewExceptionSites = allowedNumeric.previewExceptionSites or {}
local allowedDirectCount = 0
for _, call in ipairs(directCalls) do
    if call.method ~= allowedNumeric.method then
        error(string.format("unsafe cooldown setter call outside numeric facade: %s:%d %s",
            call.path, call.line, call.method), 2)
    elseif allowedSites[call.path] then
        allowedDirectCount = allowedDirectCount + 1
    elseif not previewExceptionSites[call.path] then
        error(string.format("unsafe cooldown setter call outside numeric facade: %s:%d %s",
            call.path, call.line, call.method), 2)
    end
end

assert(allowedDirectCount == 1,
    "expected exactly one approved numeric SetCooldown facade call")

local docs = readFile("docs/blizzard/cdm-api-reference.md")
assertContains(docs, "tests/api-docs/cdm_blizzard_reference.lua",
    "maintainer docs should link the machine-readable reference")
assertContains(docs, "SetCooldownFromDurationObject",
    "maintainer docs should document the DurationObject cooldown sink")
assertContains(docs, "C_CurveUtil.EvaluateColorValueFromBoolean",
    "maintainer docs should document the secret boolean decode path")

print("OK: cdm_blizzard_reference_test")
