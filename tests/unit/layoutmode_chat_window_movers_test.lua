-- tests/unit/layoutmode_chat_window_movers_test.lua
-- Run: lua tests/unit/layoutmode_chat_window_movers_test.lua
--
-- Regression guard: chat windows 2+ must get the full damage-meter-style
-- Layout Mode wiring — a mover element, a frame resolver (anchor target +
-- key recognition for QUI_ApplyFrameAnchor), a lookup key pointing at the
-- shared drawer feature, and a saved-anchor apply. The shared feature must
-- build BOTH the Position and Size collapsibles, dispatching by providerKey.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a")
    f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/layout/layoutmode.lua")

-- Shared drawer feature.
local featPos = assert(source:find('local CHAT_WINDOW_LAYOUT_FEATURE_ID = "chatWindowLayout"', 1, true),
    "shared chat-window layout feature id must exist")
local syncPos = assert(source:find("function um:SyncChatWindowElements()", featPos, true),
    "per-window chat mover sync must exist after the feature registration")
local featBlock = source:sub(featPos, syncPos - 1)

assert(featBlock:find('providerKey:match("^chatWindow(%d+)$")', 1, true),
    "feature render must dispatch by chatWindow<N> providerKey")
assert(featBlock:find("U.BuildPositionCollapsible(host, providerKey", 1, true),
    "feature must build the Position collapsible (anchor settings)")
assert(featBlock:find("U.BuildSizeCollapsible(host", 1, true),
    "feature must build the Size collapsible")
assert(featBlock:find("D.PersistGeometry(windowID)", 1, true),
    "size slider writes must persist via PersistGeometry(windowID)")

-- Per-window sync wiring.
local syncBlock = source:sub(syncPos)
assert(syncBlock:find("um:RegisterElement({", 1, true),
    "sync must register a mover element per window")
assert(syncBlock:find("_G.QUI_RegisterFrameResolver(key", 1, true),
    "sync must register a frame resolver per window (anchor target)")
assert(syncBlock:find("Registry:RegisterLookupKey(CHAT_WINDOW_LAYOUT_FEATURE_ID, key)", 1, true),
    "sync must point each window key at the shared drawer feature")
assert(syncBlock:find("_G.QUI_ApplyFrameAnchor(key)", 1, true),
    "sync must apply a saved frame anchor per window")
assert(syncBlock:find("D.PersistGeometry(windowID)", 1, true),
    "mover drags must persist via PersistGeometry(windowID)")

print("OK: layoutmode_chat_window_movers_test")
