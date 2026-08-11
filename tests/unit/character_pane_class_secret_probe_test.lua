-- tests/unit/character_pane_class_secret_probe_test.lua
-- Run: lua tests/unit/character_pane_class_secret_probe_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("modules/skinning/character_pane/character.lua")

-- Total probe count
local n = 0
for _ in src:gmatch("issecretvalue and issecretvalue%(class%)") do n = n + 1 end
for _ in src:gmatch("issecretvalue and issecretvalue%(cls%)") do n = n + 1 end
for _ in src:gmatch("issecretvalue and issecretvalue%(classTag%)") do n = n + 1 end
assert(n >= 6, "expected >=6 binary class probes in character pane, found " .. n)

-- Site 1: CreateSlotOverlay enchant color (line 1159)
do
    local anchor = src:find("local enchantColor\n    local useClassColor = IsInspectUnit(overlayUnit)", 1, true)
    assert(anchor, "Site 1 (CreateSlotOverlay enchant) anchor not found")
    local window = src:sub(anchor, anchor + 900)
    local probe = window:find("issecretvalue and issecretvalue(class)", 1, true)
    local use = window:find("Helpers.GetClassColorTable(class)", 1, true)
    assert(probe, "Site 1: probe not found")
    assert(use and probe < use, "Site 1: probe must precede GetClassColorTable use")
end

-- Site 2: UpdateSlotOverlay enchant color (line 1389)
do
    local anchor = src:find("local customEnchantColor = isInspect and settings.inspectEnchantTextColor", 1, true)
    assert(anchor, "Site 2 (UpdateSlotOverlay enchant) anchor not found")
    local window = src:sub(anchor, anchor + 900)
    local probe = window:find("issecretvalue and issecretvalue(class)", 1, true)
    local use = window:find("Helpers.GetClassColorTable(class)", 1, true)
    assert(probe, "Site 2: probe not found")
    assert(use and probe < use, "Site 2: probe must precede GetClassColorTable use")
end

-- Site 3: UpdateStatsPanel tooltip HASTE (line 2932)
do
    local anchor = src:find("if stat.statKey == \"CRIT\" then\n            tooltipBody = STAT_CRITICAL_STRIKE_TOOLTIP", 1, true)
    assert(anchor, "Site 3 (tooltip HASTE calc) anchor not found")
    local window = src:sub(anchor, anchor + 900)
    local probe = window:find("issecretvalue and issecretvalue(class)", 1, true)
    local use = window:find("STAT_HASTE_\"..class", 1, true)
    assert(probe, "Site 3: probe not found")
    assert(use and probe < use, "Site 3: probe must precede concat use")
end

-- Site 4: UpdateStatsPanel tooltip callback HASTE (line 2953)
do
    local anchor = src:find("elseif stat.statKey == \"HASTE\" then\n                local _, class = UnitClass(unit)", 1, true)
    assert(anchor, "Site 4 (tooltip callback HASTE) anchor not found")
    local window = src:sub(anchor, anchor + 900)
    local probe = window:find("issecretvalue and issecretvalue(class)", 1, true)
    local use = window:find("STAT_HASTE_\"..class", 1, true)
    assert(probe, "Site 4: probe not found")
    assert(use and probe < use, "Site 4: probe must precede concat use")
end

-- Site 5: UpdateStatsPanel casterClasses filter (line 3120)
do
    local anchor = src:find("local casterClasses = { MAGE = true, PRIEST = true, WARLOCK = true }", 1, true)
    assert(anchor, "Site 5 (casterClasses filter) anchor not found")
    local window = src:sub(anchor - 200, anchor + 400)
    local probe = window:find("issecretvalue and issecretvalue(cls)", 1, true)
    local use = window:find("casterClasses[cls]", 1, true)
    assert(probe, "Site 5: probe not found")
    assert(use and probe < use, "Site 5: probe must precede table-index use")
end

-- Site 6: UpdateStatsPanel brewmaster check (line 3197)
do
    local anchor = src:find("local staggerPercent = 0\n    local _, classTag = UnitClass(unit)", 1, true)
    assert(anchor, "Site 6 (brewmaster check) anchor not found")
    local window = src:sub(anchor, anchor + 600)
    local probe = window:find("issecretvalue and issecretvalue(classTag)", 1, true)
    local use = window:find("classTag == \"MONK\"", 1, true)
    assert(probe, "Site 6: probe not found")
    assert(use and probe < use, "Site 6: probe must precede equality test")
end

print("OK character_pane_class_secret_probe_test")
