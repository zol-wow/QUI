-- tests/unit/toc_libopenraid_dead_datasets_test.lua
-- Run: lua tests/unit/toc_libopenraid_dead_datasets_test.lua
--
-- QUI.toc compiled all nine LibOpenRaid expansion datasets (457,693 bytes);
-- eight are version-guarded to `return` immediately on 12.x clients
-- (gameVersion window checks at the top of each ThingsToMantain_*.lua) but
-- still parse+compile at login. Only the Midnight dataset (guard:
-- gameVersion >= 120000 and < 130000) can execute — it must be the only one
-- in the TOC. Vendored files stay on disk for lib upgrades.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local toc = readFile("QUI.toc")

assert(toc:find("ThingsToMantain_Midnight.lua", 1, true),
    "the live 12.x LibOpenRaid dataset must stay in the TOC")

for _, dead in ipairs({
    "WarWithin", "Dragonflight", "Shadowlands", "Wrath",
    "Era", "BurningCrusade", "Cata", "Pandaria",
}) do
    assert(not toc:find("ThingsToMantain_" .. dead .. ".lua", 1, true),
        "dead dataset ThingsToMantain_" .. dead .. " must not compile at login")
end

print("PASS toc_libopenraid_dead_datasets_test")
