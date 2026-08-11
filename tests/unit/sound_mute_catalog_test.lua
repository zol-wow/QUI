-- tests/unit/sound_mute_catalog_test.lua
-- Run: lua tests/unit/sound_mute_catalog_test.lua
--
-- Guards the Sound Mute curated database (modules/qol/sound_mute_catalog.lua):
--   * every entry key is globally unique (the DB is keyed by entry key, and the
--     settings checkbox binds to soundMute[key] — a collision would silently
--     make two checkboxes toggle the same mute)
--   * category keys are unique
--   * every fileDataID is a positive integer
--   * no duplicate ids within a single entry
-- The catalog file only reads ns.L (passthrough here) and writes
-- ns.SoundMuteCatalog, so we load it with a mock ns and inspect the result.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

-- Mock ns: L returns its key (passthrough), captures SoundMuteCatalog on write.
local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
local source = readAll("modules/qol/sound_mute_catalog.lua")
local chunk = assert(loadstring(source, "sound_mute_catalog"))
chunk("QUI_QoL", ns)

local catalog = ns.SoundMuteCatalog

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

check("catalog loaded", type(catalog) == "table" and type(catalog.categories) == "table")

local seenCatKeys, seenEntryKeys = {}, {}
local totalEntries, totalIds = 0, 0

for _, category in ipairs(catalog.categories) do
    check("category has key", type(category.key) == "string" and category.key ~= "")
    check("category key unique: " .. tostring(category.key), not seenCatKeys[category.key])
    seenCatKeys[category.key] = true
    check("category has label: " .. category.key, type(category.label) == "string" and category.label ~= "")
    check("category has entries: " .. category.key, type(category.entries) == "table" and #category.entries > 0)

    for _, entry in ipairs(category.entries) do
        totalEntries = totalEntries + 1
        check("entry has key in " .. category.key, type(entry.key) == "string" and entry.key ~= "")
        check("entry key unique: " .. tostring(entry.key), not seenEntryKeys[entry.key],
            entry.key and seenEntryKeys[entry.key] and "duplicate" or nil)
        seenEntryKeys[entry.key] = true
        check("entry has label: " .. tostring(entry.key), type(entry.label) == "string" and entry.label ~= "")
        check("entry has ids: " .. tostring(entry.key), type(entry.ids) == "table" and #entry.ids > 0)

        local seenIds = {}
        for _, id in ipairs(entry.ids) do
            totalIds = totalIds + 1
            local okId = type(id) == "number" and id > 0 and math.floor(id) == id
            check("id positive integer in " .. tostring(entry.key), okId, tostring(id))
            check("id not duplicated in " .. tostring(entry.key), not seenIds[id], tostring(id))
            seenIds[id] = true
        end
    end
end

-- Sanity floor: the curated DB should have real breadth, not a stub.
check("has many entries (>= 40)", totalEntries >= 40, "got " .. totalEntries)
check("has many ids (>= 400)", totalIds >= 400, "got " .. totalIds)

print(("-- %d entries, %d ids across %d categories"):format(totalEntries, totalIds, #catalog.categories))

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
