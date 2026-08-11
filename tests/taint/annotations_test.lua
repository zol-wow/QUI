-- tests/taint/annotations_test.lua
local Annotations = dofile("tests/taint/annotations.lua")

local function assert_eq(a, e, msg)
    if a ~= e then error((msg or "") .. ": expected " .. tostring(e) ..
        ", got " .. tostring(a), 2) end
end

local source = [[
local x = 1
local y = x + 1  -- @secret-safe: trailing-style on line 2
-- @secret-safe: applies-to-line-4
local z = x + 2
local bad = x + 3  -- @secret-safe:
]]

local annots = Annotations.scan(source)
assert_eq(annots[2].reason, "trailing-style on line 2",
    "line 2 has trailing annotation")
assert_eq(annots[4].reason, "applies-to-line-4",
    "line 4 inherits annotation from preceding comment line 3")
assert_eq(annots[5].reason, nil, "line 5 has empty reason")
assert(annots[5].emptyReason, "line 5 emptyReason flagged")

print("annotations test passed")

do
    local ann = Annotations.scan("state.active = true -- @secret-policy: keep-visible-when-unknown\n")
    assert(ann[1] and ann[1].kind == "policy", "policy annotation scanned with kind")
    assert(ann[1].reason == "keep-visible-when-unknown", "policy name captured")

    local safeAnn = Annotations.scan("x = 1 -- @secret-safe: doc fact\n")
    assert(safeAnn[1].kind == "safe", "safe annotation carries kind")

    local findings = {
        { file = "f.lua", line = 1, sink = "<secret-collapse>", suppressed = false },
        { file = "f.lua", line = 1, sink = "<comparison>",      suppressed = false },
    }
    Annotations.apply(findings, ann)  -- policy annotation on line 1
    assert(findings[1].suppressed == true,  "policy suppresses collapse findings")
    assert(findings[2].suppressed == false, "policy does NOT suppress other findings")

    local findings2 = {
        { file = "f.lua", line = 1, sink = "<secret-collapse>", suppressed = false },
        { file = "f.lua", line = 1, sink = "<comparison>",      suppressed = false },
    }
    Annotations.apply(findings2, safeAnn)
    assert(findings2[1].suppressed == false, "@secret-safe never suppresses collapse — policies must be NAMED")
    assert(findings2[2].suppressed == true,  "@secret-safe still suppresses ordinary findings")
end
print("secret-policy annotation tests passed")
