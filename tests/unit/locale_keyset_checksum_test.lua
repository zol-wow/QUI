-- tests/unit/locale_keyset_checksum_test.lua
-- Run: lua tests/unit/locale_keyset_checksum_test.lua
--
-- Locale overlays are positional: value N belongs to key N of the sorted
-- enUS key set. If enUS gains or loses a key without every overlay being
-- regenerated, every ID after that point shifts and the overlay mistranslates
-- silently. The checksum makes that mismatch loud.

local LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT",
                  "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local function readAll(path)
    local file = assert(io.open(path, "rb"), "missing " .. path)
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local function checksumOf(path)
    local sum = readAll(path):match("\n%-%- keyset: (%x+)\n")
    assert(sum, path .. " has no '-- keyset: <hex>' line")
    return sum
end

local base = checksumOf("core/locale/enUS.lua")

for _, loc in ipairs(LOCALES) do
    local got = checksumOf("core/locale/" .. loc .. ".lua")
    -- NOT gen_all_caches.sh: that script regenerates enUS.lua and the search
    -- cache and never writes an overlay, so running it here changes nothing.
    -- Nor translate_delta.py, which needs a translation API key -- no new
    -- translation is required to fix this, only a new slot number.
    assert(got == base, ("%s keyset %s does not match enUS %s — the overlays are "
        .. "numbered for a different enUS key set, so every slot after the added or "
        .. "removed key is the WRONG translation. Fix: "
        .. "python3 tools/i18n/reslot_overlays.py"):format(loc, got, base))
end

print("OK: locale_keyset_checksum_test (" .. #LOCALES .. " overlays)")
