-- tests/unit/alts_cjk_font_wrappers_test.lua
-- Run: lua tests/unit/alts_cjk_font_wrappers_test.lua
--
-- Alts view helpers create dynamic FontStrings/EditBoxes outside SkinBase.
-- They still need the shared CJK fallback path instead of raw SetFont.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local shared = readFile("QUI_Alts/alts/views/shared.lua")
assertContains(shared, "local function CJKFont(fs, p, s, f)",
    "Alts shared helpers must expose a CJK font wrapper")
assertContains(shared, "CJKFont(fs, Shared.GeneralFont(), size or 11, Shared.GeneralOutline())",
    "Shared.MakeFS must route through the CJK font wrapper")
assertAbsent(shared, "fs:SetFont(Shared.GeneralFont(), size or 11, Shared.GeneralOutline())",
    "Shared.MakeFS must not use raw SetFont")

local filterPopup = readFile("QUI_Alts/alts/views/filter_popup.lua")
assertContains(filterPopup, "CJKFont(sb, GeneralFont(), 11, GeneralOutline())",
    "filter popup search box must route through the CJK font wrapper")
assertAbsent(filterPopup, "sb:SetFont(GeneralFont(), 11, GeneralOutline())",
    "filter popup search box must not use raw SetFont")

print("OK: alts_cjk_font_wrappers_test")
