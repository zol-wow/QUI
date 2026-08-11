-- QUI i18n locale-runtime tests. Run: lua5.1 tools/test_i18n_locale.lua
--
-- The overlays are POSITIONAL: core/locale/enUS.lua ships an ordered key
-- array (ns.LocaleData.keys) and each core/locale/<loc>.lua ships an array of
-- translations where slot N belongs to keys[N]. locale.lua turns that into the
-- ns.L metatable. The old shape -- a keyed identity base plus a keyed overlay --
-- is gone; it repeated every English key eleven times for a mapping that
-- carried nothing but the key order.
local failures = 0
local function check(name, cond)
    if cond then print("ok   - " .. name)
    else failures = failures + 1; print("FAIL - " .. name) end
end

-- Build a fake core namespace with locale data, then load locale.lua against it.
local function buildL(activeArray, keyArray)
    local ns = { LocaleData = { keys = keyArray, active = activeArray } }
    local chunk = assert(loadfile("core/locale/locale.lua"))
    chunk("QUI", ns)            -- mimic WoW's (ADDON_NAME, ns) vararg
    return ns.L
end

local keys   = { "Active Profile", "Cancel", "Close" }
local active = { nil, "Abbrechen" }   -- partial translation, slot 1 held nil

local L1 = buildL(active, keys)
check("active value wins",        L1["Cancel"] == "Abbrechen")
check("held nil slot falls back", L1["Active Profile"] == "Active Profile")
check("missing tail falls back",  L1["Close"] == "Close")
check("unknown key returns key",  L1["Not Extracted"] == "Not Extracted")

local L2 = buildL(nil, keys)     -- enUS client: no active table
check("enUS client returns key",  L2["Active Profile"] == "Active Profile")
check("enUS unknown returns key", L2["Whatever"] == "Whatever")

-- Slot N must mean key N: a translation may not leak onto its neighbour.
local L3 = buildL({ "Aktives Profil", "Abbrechen", "Schliessen" }, keys)
check("id 1 resolves to id 1",    L3["Active Profile"] == "Aktives Profil")
check("id 2 resolves to id 2",    L3["Cancel"] == "Abbrechen")
check("id 3 resolves to id 3",    L3["Close"] == "Schliessen")

if failures > 0 then os.exit(1) end
print(("\n%d checks passed"):format(9))
