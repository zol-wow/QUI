-- QUI i18n locale-runtime tests. Run: lua5.1 tools/test_i18n_locale.lua
local failures = 0
local function check(name, cond)
    if cond then print("ok   - " .. name)
    else failures = failures + 1; print("FAIL - " .. name) end
end

-- Build a fake core namespace with locale data, then load locale.lua against it.
local function buildL(activeTbl, baseTbl)
    local ns = { LocaleData = { enUS = baseTbl, active = activeTbl } }
    local chunk = assert(loadfile("core/locale/locale.lua"))
    chunk("QUI", ns)            -- mimic WoW's (ADDON_NAME, ns) vararg
    return ns.L
end

local base   = { ["Active Profile"] = "Active Profile", ["Cancel"] = "Cancel" }
local active  = { ["Cancel"] = "Abbrechen" }   -- partial translation

local L1 = buildL(active, base)
check("active value wins",        L1["Cancel"] == "Abbrechen")
check("falls back to enUS base",  L1["Active Profile"] == "Active Profile")
check("unknown key returns key",  L1["Not Extracted"] == "Not Extracted")

local L2 = buildL(nil, base)     -- enUS client: no active table
check("enUS client uses base",    L2["Active Profile"] == "Active Profile")
check("enUS unknown returns key", L2["Whatever"] == "Whatever")

if failures > 0 then os.exit(1) end
print(("\n%d checks passed"):format(5))
