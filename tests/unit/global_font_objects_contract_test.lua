-- Contract: object-override mechanism present and excludes the bare secure roots.
local function read(path) local fh = assert(io.open(path, "r")); local s = fh:read("*a"); fh:close(); return s end
local src = read("core/font_system.lua")

assert(src:find("function QUICore:ApplyGlobalFontObjects"), "ApplyGlobalFontObjects must exist")
assert(src:find("FONT_OBJECT_SET"), "FONT_OBJECT_SET table must exist")
assert(src:find('"NumberFontNormal"'), "set must include NumberFontNormal (reference-proven)")

-- Bare secure roots MUST be excluded (quoted as standalone list entries).
for _, root in ipairs({ '"GameFontNormal"', '"GameFontHighlight"', '"GameFontDisable"', '"GameFontNormalSmall"' }) do
    assert(not src:find(root, 1, true), "bare root must be excluded from FONT_OBJECT_SET: " .. root)
end

-- SCT object stays out of the always-on set (owned by overrideSCTFont).
assert(not src:find('"CombatTextFont"', 1, true), "CombatTextFont must not be in FONT_OBJECT_SET")

-- Outline must come from the QUI option, size preserved (no hardcoded size in SetFont call).
assert(src:find("GetGeneralFontOutline"), "must apply general.fontOutline")

-- Outline TIERING: the user's outline is applied ONLY to fonts that natively
-- carry an outline; native flags are preserved otherwise, so a forced outline
-- never blobs dark quest/mail/parchment body text into black-on-black. Pin the
-- native-flag gate so a future edit can't silently revert to blanket-outline.
assert(src:find('nativeFlags:find("OUTLINE")', 1, true),
    "outline must be tiered on native-outline fonts, not blanket-applied")
print("OK global_font_objects_contract_test")
