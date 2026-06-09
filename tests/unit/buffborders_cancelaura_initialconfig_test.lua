-- tests/unit/buffborders_cancelaura_initialconfig_test.lua
-- Run: lua tests/unit/buffborders_cancelaura_initialconfig_test.lua
--
-- Regression guard for right-click-to-remove on buff/debuff border icons.
--
-- The secure aura header declares `type=cancelaura` on its children via the
-- header's `initialConfigFunction` attribute snippet (run once per child, in
-- the restricted environment, at child construction — see Blizzard_FrameXML
-- SecureGroupHeaders.lua SetupAuraButtonConfiguration). That `type` is what
-- routes a right-click through SECURE_ACTIONS.cancelaura -> CancelUnitBuff
-- (SecureTemplates.lua). It is the ONLY place QUI wires cancellation.
--
-- CreateHeader installs that snippet correctly, but SyncHeaderAttributes
-- rewrites initialConfigFunction on every settings change and every
-- combat-end refresh. If the synced snippet only sets the icon size and drops
-- the cancel wiring, every child constructed after the first sync reaches
-- SecureActionButton_OnClick with no `type` attribute and right-click silently
-- does nothing. Guard that the synced snippet keeps the cancel wiring.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_ActionBars/actionbars/buffborders.lua")

-- Isolate the SyncHeaderAttributes body so we assert on the snippet it
-- installs, not on cancelaura references elsewhere in the file (CreateHeader,
-- comments).
local syncStart = source:find("local function SyncHeaderAttributes", 1, true)
assert(syncStart, "SyncHeaderAttributes must exist in buffborders.lua")
local nextFn = source:find("\nlocal function ", syncStart + 1, true)
assert(nextFn, "expected another local function after SyncHeaderAttributes")
local syncBody = source:sub(syncStart, nextFn)

assert(syncBody:find("initialConfigFunction", 1, true),
    "SyncHeaderAttributes must (re)install the header's initialConfigFunction")

assert(syncBody:find("cancelaura", 1, true),
    "SyncHeaderAttributes' initialConfigFunction must keep type=cancelaura so "
    .. "header children created after a settings/combat-end refresh stay "
    .. "right-click cancellable")

assert(syncBody:find("SetFrameLevel", 1, true),
    "SyncHeaderAttributes' initialConfigFunction must preserve the child frame "
    .. "level declared at header creation")

print("OK: buffborders_cancelaura_initialconfig_test")
