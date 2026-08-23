local function fail(msg)
    print("FAIL: aura_displays_quick_create_test - " .. msg)
    os.exit(1)
end

local profile = {}
local ns = {}
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Helpers = {
    GetProfile = function() return profile end,
    GetModuleSettings = function(name, defaults)
        if not profile[name] then
            profile[name] = {}
            for k, v in pairs(defaults or {}) do profile[name][k] = v end
        end
        return profile[name]
    end,
}
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
assert(loadfile("modules/trackers/aura_displays.lua"))("QUI", ns)
assert(loadfile("modules/trackers/settings/aura_displays_content.lua"))("QUI", ns)
local Page = ns.QUI_AuraDisplaysOptions
if type(Page._QuickCreate) ~= "function" then fail("_QuickCreate must be exported") end

local tracked = Page._QuickCreate({ kind = "tracked", name = "Immolate",
    unitChoice = "target", spellID = 348 })
if not tracked then fail("tracked quick-create must return a display") end
if tracked.unitMode ~= "token" or tracked.unit ~= "target" then
    fail("unit choice must land in unitMode/unit")
end
local bucket = tracked.auras.elements["*"]
if #bucket ~= 1 then fail("quick-create must seed exactly ONE element, got " .. #bucket) end
if bucket[1].mode ~= "tracked" or bucket[1].spells[1] ~= 348 then
    fail("seeded element must track the given spell")
end
if bucket[1].iconSize ~= 100 then
    fail("new tracked Aura Display icons must default to 100px")
end
if type(bucket[1].id) ~= "string" and type(bucket[1].id) ~= "number" then
    fail("seeded element must carry a minted id")
end

local strip = Page._QuickCreate({ kind = "filterStrip", name = "",
    unitChoice = "__cotank" })
if strip.unitMode ~= "cotank" or strip.unit ~= nil then
    fail("cotank choice must set unitMode cotank")
end
if strip.auras.elements["*"][1].mode ~= "filterStrip" then
    fail("filter strip quick-create must seed a filter strip element")
end
if strip.name ~= "New Filter Strip" then
    fail("empty name must fall back to the filter strip default, got " .. tostring(strip.name))
end

local named = Page._QuickCreate({ kind = "filterStrip", name = "Watch",
    unitChoice = "__name" })
if named.unitMode ~= "name" or named.unit ~= "" then
    fail("name choice must set unitMode name with empty unit for later entry")
end

local unresolved = Page._QuickCreate({ kind = "tracked", name = "Mystery",
    unitChoice = "player" })
local unresolvedElement = unresolved.auras.elements["*"][1]
if unresolvedElement.mode ~= "tracked" or #unresolvedElement.spells ~= 0 then
    fail("tracked quick-create without a resolved spell must stay tracked with empty spells")
end

print("OK: aura_displays_quick_create_test")
