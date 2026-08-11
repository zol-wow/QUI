local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local loadchunk = loadstring or load

local FIXTURE = table.concat({
    "-- a prose comment that must be stripped",
    "local M = {}",
    "",
    "",
    "M.text = [[first   ",
    "",
    "",
    "\tindented\t",
    "last]]",
    "",
    "M.n = 1 -- trailing prose",
    "return M",
}, "\n") .. "\n"

local srcPath = os.tmpname() .. ".lua"
local outPath = os.tmpname() .. ".out"
local fh = assert(io.open(srcPath, "wb"))
fh:write(FIXTURE)
fh:close()

local interp = arg and arg[-1] or "lua"
os.execute(("%s tools/strip_comments.lua %s > %s"):format(interp, srcPath, outPath))

local oh = assert(io.open(outPath, "rb"))
local stripped = oh:read("*a")
oh:close()
os.remove(srcPath)
os.remove(outPath)

check("stripper produced output", #stripped > 0, "empty")
check("prose comments removed", not stripped:find("prose", 1, true), stripped)

local origChunk = assert(loadchunk(FIXTURE, "orig"))
local strippedChunk, loadErr = loadchunk(stripped, "stripped")
check("stripped output still compiles", strippedChunk ~= nil, tostring(loadErr))

if strippedChunk then
    local want = origChunk().text
    local got = strippedChunk().text
    check("long-string value byte-identical", want == got,
        ("want %q got %q"):format(want, got))
end

if failures > 0 then
    print(("%d failure(s)"):format(failures))
    os.exit(1)
end
print("strip_comments long-string test: ok")
