-- Run: lua5.1 tools/test_i18n_format.lua
local failures = 0
local function check(n,c) if c then print("ok   - "..n) else failures=failures+1; print("FAIL - "..n) end end
local V = assert(loadfile("tools/i18n/validate_format.lua"))()

-- tokens(s) -> sorted multiset string of specifiers+escapes
check("plain equal",     V.tokens("Hello") == V.tokens("Hallo"))
check("pct preserved",   V.tokens("Delete '%1$s'?") == V.tokens("'%1$s' loeschen?"))
check("count mismatch",  V.tokens("%d of %d") ~= V.tokens("%d von"))
check("color preserved", V.tokens("|cff60A5FAQUI:|r x") == V.tokens("|cff60A5FAQUI:|r y"))
check("color dropped",   V.tokens("|cff60A5FAQUI:|r x") ~= V.tokens("QUI: y"))

-- prose % (not a real specifier) must NOT be treated as one
check("prose pct no token",  V.tokens("Set to 100% for best") == V.tokens("Auf 100% optimal"))

-- validate(pairs) -> list of {key, reason}; empty = OK
local bad = V.validate({ ["%d items"] = "%d von %d" })   -- ADDED a %d -> unsafe
check("validate flags added spec", #bad == 1)
local ok = V.validate({ ["%d items"] = "%d Dinge" })
check("validate passes clean", #ok == 0)
-- dropping a surplus specifier is SAFE (Lua format ignores extra args)
check("dropped spec OK",     #V.validate({ ["%d pin%s detected"] = "%d Pins erkannt" }) == 0)
-- prose % passes validate
check("prose pct validates", #V.validate({ ["Scale to 100% now"] = "Jetzt auf 100% skalieren" }) == 0)
-- a dropped |r (color bleed) MUST be flagged
check("dropped escape flagged", #V.validate({ ["|cffAAAAAAx|r"] = "|cffAAAAAAy" }) == 1)

if failures > 0 then os.exit(1) end
print("\nformat tests passed")
