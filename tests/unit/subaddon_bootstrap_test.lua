-- The bridge must proxy reads AND writes to the core namespace so moved
-- module files (local _, ns = ...) keep sharing one namespace suite-wide.
local mainNS = { Helpers = { marker = 1 } }
_G.QUI = { _ns = mainNS }

local subNS = {}
assert(loadfile("core/templates/subaddon_bootstrap.lua"))("QUI_Fake", subNS)

assert(subNS.Helpers and subNS.Helpers.marker == 1, "read proxies to core ns")
subNS.QUI_FakeExport = "X"
assert(mainNS.QUI_FakeExport == "X", "write lands in core ns")
assert(rawget(subNS, "QUI_FakeExport") == nil, "sub ns stays empty (pure proxy)")

-- Core missing: file must RAISE and the message must mention the core addon;
-- the orphan ns must still have no metatable.
_G.QUI = nil
local orphanNS = {}
local ok, err = pcall(
    assert(loadfile("core/templates/subaddon_bootstrap.lua")),
    "QUI_Fake", orphanNS)
assert(not ok, "expected error when QUI core absent")
assert(type(err) == "string" and err:find("QUI"), "error mentions QUI core: " .. tostring(err))
assert(getmetatable(orphanNS) == nil, "no bridge when core absent")

print("subaddon_bootstrap_test OK")
