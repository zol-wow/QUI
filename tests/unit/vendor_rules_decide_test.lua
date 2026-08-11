-- tests/unit/vendor_rules_decide_test.lua
-- Run: lua tests/unit/vendor_rules_decide_test.lua
--
-- Pins DecideSale, the vendor-rules core. Proves the safety properties:
-- protections (equipment set, upgradable gear, unbound tradeables,
-- never-sell, worthless) beat every rule INCLUDING force-sell; rules only
-- ever match equippable gear (classID 2 weapon / 4 armor); quality and
-- item-level caps behave. Extracted from vendor_rules.lua between its
-- QUI_TEST_EXTRACT sentinels (pure function).

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/vendor_rules.lua")
local S = "-- <<< QUI_TEST_EXTRACT decide_sale"
local a1 = assert(source:find(S, 1, true), "start sentinel must exist")
local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist")
local block = source:sub(a1 + #S, a2 - 1)

local chunk = block .. "\nreturn { DecideSale = DecideSale }"
local M = assert(loadstring(chunk, "vendor_rules_decide"))()
local D = M.DecideSale

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

local CFG = { maxQuality = 2, maxIlvl = 600 }
-- NIL sentinel: pairs() can't carry nil overrides, so gear({x = NIL})
-- explicitly REMOVES the field from the baseline facts.
local NIL = {}
local function gear(overrides)
    local f = { quality = 2, classID = 4, ilvl = 500 }
    for k, v in pairs(overrides or {}) do
        if v == NIL then f[k] = nil else f[k] = v end
    end
    return f
end

-- Baseline: green armor below the ilvl cap sells.
check("baseline gear sells", D(CFG, gear()) == true)
check("weapon sells", D(CFG, gear({ classID = 2 })) == true)

-- SAFETY: every protection beats the rules...
check("equipment set protected", D(CFG, gear({ inSet = true })) == false)
check("upgradable protected", D(CFG, gear({ upgradable = true })) == false)
check("unbound tradeable protected", D(CFG, gear({ unboundTradable = true })) == false)
check("never-sell protected", D(CFG, gear({ protected = true })) == false)
check("worthless never sold", D(CFG, gear({ hasNoValue = true })) == false)

-- ...INCLUDING force-sell.
check("force-sell beats class restriction", D(CFG, { classID = 7, forced = true }) == true)
check("force-sell loses to set", D(CFG, gear({ forced = true, inSet = true })) == false)
check("force-sell loses to upgradable", D(CFG, gear({ forced = true, upgradable = true })) == false)
check("force-sell loses to never-sell", D(CFG, gear({ forced = true, protected = true })) == false)
check("force-sell loses to worthless", D(CFG, gear({ forced = true, hasNoValue = true })) == false)

-- Rules only match equippable gear.
check("trade goods never rule-sold", D(CFG, gear({ classID = 7 })) == false)
check("consumables never rule-sold", D(CFG, gear({ classID = 0 })) == false)
check("nil classID never rule-sold", D(CFG, gear({ classID = NIL })) == false)

-- Quality cap.
check("above quality cap kept", D(CFG, gear({ quality = 3 })) == false)
check("at quality cap sells", D(CFG, gear({ quality = 2 })) == true)
check("nil quality kept", D(CFG, gear({ quality = NIL })) == false)

-- Item-level cap.
check("at ilvl cap kept", D(CFG, gear({ ilvl = 600 })) == false)
check("above ilvl cap kept", D(CFG, gear({ ilvl = 650 })) == false)
check("unknown ilvl kept when cap active", D(CFG, gear({ ilvl = NIL })) == false)
check("ilvl cap off ignores ilvl", D({ maxQuality = 2, maxIlvl = 0 }, gear({ ilvl = NIL })) == true)

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
