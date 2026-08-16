-- tests/unit/taint_clean_fields_test.lua
-- Run: lua tests/unit/taint_clean_fields_test.lua

local DOC_DIR = "tests/api-docs/blizzard"

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local function docFiles()
    local files = {}
    local pipe = assert(io.popen('find "' .. DOC_DIR .. '" -name "*.lua" -type f'))
    for line in pipe:lines() do files[#files + 1] = line end
    pipe:close()
    assert(#files > 0, "no generated API docs found under " .. DOC_DIR)
    return files
end

local fails = 0
local function check(name, ok, detail)
    if ok then
        print("  ok  " .. name)
    else
        fails = fails + 1
        print("FAIL  " .. name .. (detail and ("\n        " .. detail) or ""))
    end
end

local GUARDED_STRUCTURE_MARKERS = {
    "SecretWhen", "SecretReturns", "SecretArguments",
    "NeverSecret", "AlwaysSecret", "SecretReturnsForAspect",
}

local fieldsByName = {}

local function flush(block)
    if not block then return end
    for _, entry in ipairs(block.fields) do
        entry.guarded = block.guarded
        local entries = fieldsByName[entry.field] or {}
        fieldsByName[entry.field] = entries
        entries[#entries + 1] = entry
    end
end

for _, path in ipairs(docFiles()) do
    local block, lastName = nil, nil
    local lineNumber = 0
    for line in readAll(path):gmatch("[^\n]*") do
        lineNumber = lineNumber + 1
        local standaloneName = line:match('^%s*Name%s*=%s*"([%w_]+)"%s*,%s*$')
        if standaloneName then lastName = standaloneName end
        if line:match('^%s*Type%s*=%s*"Structure"%s*,%s*$') then
            flush(block)
            block = { structure = lastName, guarded = false, fields = {} }
        elseif line:match('^%s*Type%s*=%s*"[%w_]+"%s*,%s*$') then
            flush(block)
            block = nil
        end
        if block then
            for _, marker in ipairs(GUARDED_STRUCTURE_MARKERS) do
                if line:find(marker, 1, true) then block.guarded = true end
            end
            local field = line:match('{%s*Name%s*=%s*"([%w_]+)"%s*,%s*Type%s*=%s*"[%w_]+"')
            if field and line:find("Nilable", 1, true) then
                block.fields[#block.fields + 1] = {
                    field = field,
                    structure = block.structure,
                    never = line:find("NeverSecret = true", 1, true) ~= nil,
                    where = path .. ":" .. lineNumber,
                }
            end
        end
    end
    flush(block)
end

local config = assert(loadfile("tests/.taintrc.lua"))()
local cleanFields = assert(config.clean_fields, ".taintrc.lua must declare clean_fields")

check("the generated docs parsed into a usable field index",
    next(fieldsByName) ~= nil and fieldsByName.isActive ~= nil)

for _, field in ipairs(cleanFields) do
    local entries = fieldsByName[field]
    if not entries then
        check("clean_fields entry '" .. field .. "' names a real documented field", false,
            "no structure in " .. DOC_DIR .. " declares a field called " .. field)
    else
        local offenders = {}
        local sawGuarded = false
        for _, entry in ipairs(entries) do
            if entry.guarded then
                sawGuarded = true
                if not entry.never then
                    offenders[#offenders + 1] = entry.structure .. " (" .. entry.where .. ")"
                end
            end
        end
        check("clean_fields entry '" .. field .. "' is NeverSecret on every secret-guarded structure",
            sawGuarded and #offenders == 0,
            (not sawGuarded)
                and ("no secret-guarded structure declares " .. field
                    .. " — the entry buys nothing and hides real taint")
                or ("secret-capable on: " .. table.concat(offenders, ", ")))
    end
end

print(string.format("taint_clean_fields_test: checks complete, %d failed", fails))
if fails > 0 then os.exit(1) end
print("OK: taint_clean_fields_test")
