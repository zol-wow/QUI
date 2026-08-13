local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_ResourceBars/resourcebars/resourcebars.lua")

local function countCreates(name)
    local count = 0
    for _ in src:gmatch('CreateFrame%("Frame", "' .. name .. '"') do
        count = count + 1
    end
    return count
end

local function countReuses(name)
    local count = 0
    for _ in src:gmatch('_G%["' .. name .. '"%] or CreateFrame%("Frame", "' .. name .. '"') do
        count = count + 1
    end
    return count
end

for _, name in ipairs({ "QUIPowerBar", "QUISecondaryPowerBar" }) do
    local creates, reuses = countCreates(name), countReuses(name)

    assert(creates == 2, name .. " should appear exactly twice: the load-time pre-create and GetPowerBar")
    assert(reuses == 1,
        name .. " is pre-created at load for Edit Mode anchoring, so the bar builder MUST adopt " ..
        "_G[\"" .. name .. "\"] instead of creating a second frame under the same global name — " ..
        "otherwise the global stays the empty placeholder and ticks/indicatorLines/StatusBar are " ..
        "only ever set on an unreachable frame")
end

print("OK: resourcebars_bar_globals_single_frame_test")
