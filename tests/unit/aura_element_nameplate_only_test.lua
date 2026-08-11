local function fail(msg)
    print("FAIL: aura_element_nameplate_only_test - " .. msg)
    os.exit(1)
end

local ns = {}
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
local E = ns.AuraElements

local function hasToken(str)
    for component in str:gmatch("[^| ]+") do
        if component == "INCLUDE_NAME_PLATE_ONLY" then return true end
    end
    return false
end

local function compileOne(element)
    local out = E.CompileFilters(element)
    if #out == 0 then return nil end
    return out[1]
end

local flags = E.NewFilterStripElement("HARMFUL")
flags.filterMode = "flags"
flags.filterFlags = { PLAYER = true }
flags.nameplateOnly = true
local f = compileOne(flags)
if not f or not hasToken(f) then
    fail("flags mode must carry the token, got " .. tostring(f))
end

local classify = E.NewFilterStripElement("HARMFUL")
E.ApplyWhatToShow(classify, "crowdControl")
classify.nameplateOnly = true
local c = compileOne(classify)
if not c or not hasToken(c) then
    fail("classify mode must carry the token, got " .. tostring(c))
end

local white = E.NewFilterStripElement("HARMFUL")
white.filterMode = "whitelist"
white.nameplateOnly = true
local w = compileOne(white)
if not w or not hasToken(w) then
    fail("whitelist mode must carry the token, got " .. tostring(w))
end

local off = E.NewFilterStripElement("HELPFUL")
off.filterMode = "off"
off.nameplateOnly = true
local o = compileOne(off)
if not o or not hasToken(o) then
    fail("off mode must carry the token, got " .. tostring(o))
end

local without = E.NewFilterStripElement("HARMFUL")
without.filterMode = "flags"
without.filterFlags = { PLAYER = true }
local nf = compileOne(without)
if nf and hasToken(nf) then
    fail("token must not appear when nameplateOnly is unset, got " .. nf)
end

local ns2 = { AuraElements = E }
assert(loadfile("core/aura_glue.lua"))("QUI", ns2)
local G = ns2.AuraGlue
_G.AuraUtil = nil
C_UnitAuras = {
    GetUnitAuras = function(_, filterString)
        if filterString == "HELPFUL" or filterString == "HARMFUL" then return {} end
        error("client refuses composite filter: " .. tostring(filterString))
    end,
}
local fallbackEl = E.NewFilterStripElement("HELPFUL")
fallbackEl.filterMode = "off"
fallbackEl.nameplateOnly = true
local fallbackGroups = G.ElementGroups("nameplate1", fallbackEl,
    { maxIcons = 3 }, false)
if type(fallbackGroups) ~= "table" or #fallbackGroups == 0 then
    fail("ElementGroups must emit at least the fallback group")
end
if not hasToken(fallbackGroups[1].filter) then
    fail("bare-polarity fallback must carry the token when the compiled "
        .. "candidate is probe-rejected, got " .. tostring(fallbackGroups[1].filter))
end

local derived = E.NewFilterStripElement("HARMFUL")
E.ApplyWhatToShow(derived, "crowdControl")
local before = E.DeriveWhatToShow(derived)
derived.nameplateOnly = true
local after = E.DeriveWhatToShow(derived)
if before ~= after then
    fail("nameplateOnly must not change DeriveWhatToShow: " .. tostring(before)
        .. " -> " .. tostring(after))
end
if after ~= "crowdControl" then
    fail("expected crowdControl preset to survive, got " .. tostring(after))
end

print("PASS: aura_element_nameplate_only_test")
