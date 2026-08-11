-- tests/unit/main_toc_no_subaddon_bootstrap_proxy_test.lua
-- Regression guard for the QUI_UI->main merge.
--
-- The sub-addon bootstrap (core/templates/subaddon_bootstrap.lua) installs a
-- metatable proxy on a SEPARATE addon's private `ns`, bridging it to the core
-- `QUI._ns`. That is correct for sibling addons whose `ns` is a distinct table.
--
-- In the MAIN QUI addon, every file's `ns` already IS `QUI._ns` (init.lua:93
-- `QUI._ns = ns`). Listing a bootstrap proxy in QUI.toc therefore runs
-- `setmetatable(ns, { __index = ns, __newindex = function(_,k,v) ns[k]=v end })`
-- against the shared table — a self-reference that infinite-loops on the first
-- read (loop in gettable) or write (C stack overflow). This crashed the whole
-- addon at login when modules/ui_bundle_bootstrap.lua (the renamed former
-- QUI_UI/bootstrap.lua) was mistakenly kept in QUI.toc.
--
-- headless luac/luacheck/unit harnesses do NOT reproduce it (they don't wire
-- `QUI._ns == ns` and execute the metatable), so this structural guard stands
-- in for the runtime check.
--
-- Run: lua5.1 tests/unit/main_toc_no_subaddon_bootstrap_proxy_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local function readFile(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local text = fh:read("*a"); fh:close()
    return text
end

-- Signatures UNIQUE to a sub-addon bootstrap namespace-proxy. Deliberately
-- precise: init.lua legitimately uses both `setmetatable` (for QUI.imports)
-- and `QUI._ns`, so the test keys on the proxy's distinctive comment lines and
-- its `__index = mainNS` metatable, none of which appear outside the template.
local function looksLikeProxy(src)
    if not src then return false end
    return src:find("requires the QUI core addon to load first", 1, true)
        or src:find("pure metatable proxy", 1, true)
        or src:find("__index%s*=%s*mainNS")
end

-- The proxy template itself must still exist (real sibling addons use it).
check("subaddon_bootstrap template still present (used by sibling addons)",
    readFile("core/templates/subaddon_bootstrap.lua") ~= nil,
    "core/templates/subaddon_bootstrap.lua should exist")

-- Walk every .lua file listed in the main QUI.toc and assert none is a proxy.
local toc = readFile("QUI.toc")
check("QUI.toc readable", toc ~= nil)

local listed, proxyHits = 0, {}
if toc then
    for line in toc:gmatch("[^\r\n]+") do
        -- strip whitespace; skip comments/blank/directives
        local entry = line:match("^%s*(.-)%s*$")
        if entry ~= "" and not entry:match("^#") and entry:lower():match("%.lua$") then
            listed = listed + 1
            local path = entry:gsub("\\", "/")
            local src = readFile(path)
            check("QUI.toc entry resolves on disk: " .. path, src ~= nil)
            if looksLikeProxy(src) then
                proxyHits[#proxyHits + 1] = path
            end
        end
    end
end

check("QUI.toc lists at least the core + merged files", listed > 100,
    "expected >100 lua entries, got " .. listed)

check("NO sub-addon bootstrap proxy listed in main QUI.toc",
    #proxyHits == 0,
    "proxy files would self-reference ns (== QUI._ns) and crash at login: "
        .. table.concat(proxyHits, ", "))

-- Belt-and-suspenders: the specific offender must be gone.
check("modules/ui_bundle_bootstrap.lua does not exist",
    readFile("modules/ui_bundle_bootstrap.lua") == nil,
    "the former QUI_UI bootstrap proxy must not ship in the main addon")

if failures > 0 then
    print(("\n%d failure(s)"):format(failures))
    os.exit(1)
end
print("\nmain_toc_no_subaddon_bootstrap_proxy_test OK")
