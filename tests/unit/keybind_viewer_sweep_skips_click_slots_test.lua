local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/utility/keybinds.lua")

local function extract(name)
    local S = "-- <<< QUI_TEST_EXTRACT " .. name
    local a1 = assert(source:find(S, 1, true), "start sentinel must exist: " .. name)
    local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist: " .. name)
    return source:sub(a1 + #S, a2 - 1)
end

local chunk = table.concat({
    "local _G = ...",
    extract("viewer_children_sweep"),
    "return GetViewerChildren",
}, "\n")

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

local function contains(list, item)
    for _, v in ipairs(list or {}) do
        if v == item then return true end
    end
    return false
end

local function build(container, reanchored)
    local fakeG = {
        QUI_GetCDMViewerFrame = container and function() return container end or nil,
        QUI_GetReanchoredCDMFrames = reanchored and function() return reanchored end or nil,
    }
    return assert(loadstring(chunk, "viewer_children_sweep"))(fakeG)
end

local shell = { _quiCdmClickSlot = true, _spellEntry = { spellID = 1234 } }
local ownedIcon = { _customCDMEntry = { id = 1 } }
local native = { spellID = 1234 }

do
    local container = {
        GetChildren = function() return shell, ownedIcon end,
    }
    local out = build(container, { native })("essential")
    check("click shell is excluded from the sweep", not contains(out, shell))
    check("owned icon survives the sweep", contains(out, ownedIcon))
    check("reanchored native survives the sweep", contains(out, native))
    check("sweep yields exactly one frame per visual icon", out and #out == 2, "got " .. tostring(out and #out))
end

do
    local container = {
        GetChildren = function() return shell end,
    }
    local out = build(container, nil)("essential")
    check("shell-only container yields no keybind targets", out ~= nil and #out == 0,
        "got " .. tostring(out and #out))
end

do
    local out = build(nil, { native })("essential")
    check("reanchored natives are swept without a container", contains(out, native) and #out == 1)
end

if failures > 0 then
    error(failures .. " assertion(s) failed")
end
print("OK: keybind_viewer_sweep_skips_click_slots_test")
