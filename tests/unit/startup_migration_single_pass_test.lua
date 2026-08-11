-- tests/unit/startup_migration_single_pass_test.lua
-- Run: lua tests/unit/startup_migration_single_pass_test.lua
--
-- Startup ran the all-profile Tier 0/1 walk twice: QUICore:OnInitialize
-- (core/main.lua) and QUI:OnEnable → BackwardsCompat (init.lua:698), both
-- inside ADDON_LOADED with no raw-SV writes in between. OnInitialize stamps
-- a one-shot latch; BackwardsCompat consumes it and skips its Tier 0/1 walk
-- exactly once. Profile switches (main.lua OnProfileChanged), imports
-- (profile_io.lua), and the fixture harness (tools/test_profiles.lua) call
-- BackwardsCompat with the latch unset, so their tier semantics are
-- unchanged. Tier 2 reseed must NEVER be gated — it consumes the
-- _needsStarterReseed flags the Tier 1 pass left behind.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local mainSrc = readFile("core/main.lua")
local compatSrc = readFile("core/compatibility.lua")

-- latch is stamped in OnInitialize after the Tier 0/1 pair
local initStart = assert(mainSrc:find("function QUICore:OnInitialize()", 1, true))
local latchSet = assert(mainSrc:find("ns._startupTierPassDone = true", initStart, true),
    "OnInitialize must stamp the one-shot tier-pass latch")
local initMigrate = assert(mainSrc:find("ns.Migrations.Run(self.db)", initStart, true))
assert(initMigrate < latchSet, "latch must be stamped AFTER the OnInitialize tier pass")

-- BackwardsCompat consumes the latch (one-shot) before the tiers
local bcStart = assert(compatSrc:find("function QUI:BackwardsCompat()", 1, true))
local consume = assert(compatSrc:find("local skipTierPass = ns._startupTierPassDone", bcStart, true),
    "BackwardsCompat must read the latch")
local clear = assert(compatSrc:find("ns._startupTierPassDone = nil", bcStart, true),
    "BackwardsCompat must clear the latch (one-shot) so later calls re-run tiers")

-- both tiers gated on the latch
assert(compatSrc:find("if not skipTierPass and self.db then", bcStart, true),
    "Tier 0 must be gated on the consumed latch")
assert(compatSrc:find("if not skipTierPass and ns.Migrations and ns.Migrations.Run then", bcStart, true),
    "Tier 1 must be gated on the consumed latch")

-- Tier 2 reseed must remain unconditional
local tier2 = assert(compatSrc:find("ReseedStarterFlaggedProfiles(self.db)", bcStart, true))
assert(consume < tier2 and clear < tier2, "latch handling precedes Tier 2")
local tier2Slice = compatSrc:sub(tier2 - 80, tier2)
assert(not tier2Slice:find("skipTierPass", 1, true),
    "Tier 2 reseed must never be gated — it consumes flags Tier 1 left")

print("PASS startup_migration_single_pass_test")
