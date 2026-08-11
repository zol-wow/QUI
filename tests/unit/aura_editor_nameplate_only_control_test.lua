local function fail(msg)
    print("FAIL: aura_editor_nameplate_only_control_test - " .. msg)
    os.exit(1)
end

local f = assert(io.open("QUI_Options/aura_elements_editor.lua", "r"))
local src = f:read("*a")
f:close()

local tokenBlock = src:match("local HARMFUL_FLAG_TOKENS = (%b{})")
if not tokenBlock then fail("could not locate HARMFUL_FLAG_TOKENS") end
if tokenBlock:find("INCLUDE_NAME_PLATE_ONLY", 1, true) then
    fail("INCLUDE_NAME_PLATE_ONLY must be removed from HARMFUL_FLAG_TOKENS -"
        .. " the checkbox is its only home")
end

local helpfulBlock = src:match("local HELPFUL_FLAG_TOKENS = (%b{})")
if not helpfulBlock then fail("could not locate HELPFUL_FLAG_TOKENS") end
if helpfulBlock:find("INCLUDE_NAME_PLATE_ONLY", 1, true) then
    fail("INCLUDE_NAME_PLATE_ONLY must not be added to HELPFUL_FLAG_TOKENS")
end

if not src:find('"nameplateOnly"', 1, true) then
    fail("editor must bind a control to element.nameplateOnly")
end
if not src:find("Nameplate Auras Only", 1, true) then
    fail("editor must render the Nameplate Auras Only label")
end

local _, count = src:gsub("Nameplate Auras Only", "")
if count ~= 1 then
    fail("Nameplate Auras Only must appear exactly once, found " .. count)
end

print("PASS: aura_editor_nameplate_only_control_test")
