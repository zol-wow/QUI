-- tests/unit/blizzard_mover_lod_deferred_registry_test.lua
-- Run: lua tests/unit/blizzard_mover_lod_deferred_registry_test.lua
--
-- Regression guard for the suite-split ordering bug: QUI_QoL is LoadOnDemand,
-- so it loads AFTER core init (_didInitialize == true). That makes
-- ns.Addon:RegisterPostInitialize run boot() SYNCHRONOUSLY mid-load — before the
-- next TOC entry (blizzard_mover_frames.lua) has set M._FrameRegistryData. The old
-- boot() called InitRegistry() inline, which bailed on the nil pack and left the
-- panel registry permanently empty: dead movers + an empty settings toggle list.
--
-- The fix defers InitRegistry one frame when the data isn't ready yet. This test
-- reproduces that exact sequence: boot fires with no data (must NOT init inline),
-- then the data arrives and the deferred tick must populate the registry.
--
-- luacheck: globals CreateFrame InCombatLockdown C_AddOns C_Timer UIParent

local frameMeta = {}
frameMeta.__index = function(_, _)
	-- Every widget method is a no-op for this test; we only exercise registry
	-- bookkeeping, not real frame behavior.
	return function() end
end

local function newFrame(name)
	return setmetatable({ name = name }, frameMeta)
end

UIParent = newFrame("UIParent")

function CreateFrame(_, name)
	local frame = newFrame(name or "anonymousFrame")
	if name then _G[name] = frame end
	return frame
end

function InCombatLockdown() return false end

-- Return false so attachEventFrame() skips its Blizzard-addon catch-up paths.
C_AddOns = {
	IsAddOnLoaded = function() return false end,
}

-- Capture deferred callbacks instead of running them, so the test controls the
-- "next frame" boundary.
local deferred = {}
C_Timer = {
	After = function(_, callback) deferred[#deferred + 1] = callback end,
}

local profile = {
	blizzardMover = {
		enabled = true,
		requireModifier = true,
		modifier = "SHIFT",
		scaleEnabled = false,
		positionPersistence = "reset",
		frames = {},
	},
}

-- ns.Addon.RegisterPostInitialize runs the callback IMMEDIATELY (mirrors the real
-- main.lua path when _didInitialize is already true — the LOD case). This is what
-- makes boot() fire synchronously during loadfile below, before any frame data.
local ns = {
	Helpers = { GetProfile = function() return profile end },
	Addon = {
		RegisterPostInitialize = function(_, callback)
			callback({})  -- core stub: no .db, so profile-callback wiring is skipped
		end,
	},
}

assert(loadfile("QUI_QoL/qol/blizzard_mover.lua"))("QUI", ns)
local mover = assert(ns.QUI_BlizzardMover, "mover module should load")

-- boot() has now run synchronously via RegisterPostInitialize, with no
-- _FrameRegistryData present. It must have DEFERRED registry init (not run it
-- inline and silently bailed), so a deferred callback is queued...
assert(#deferred >= 1, "boot() must defer registry init when frame data isn't loaded yet")
-- ...and the registry must still be empty (nothing registered inline).
assert(#mover.functions.GetGroups() == 0, "registry must be empty before the frame data loads")

-- Simulate blizzard_mover_frames.lua loading next: it sets _FrameRegistryData.
mover._FrameRegistryData = {
	groups = {
		system = { label = "System Frames", order = 10, expanded = true },
	},
	frames = {
		{
			id = "TestPanel",
			label = "Test",
			group = "system",
			names = { "TestPanel" },
			defaultEnabled = true,
		},
	},
}

-- Fire the deferred "next frame" work. THIS is the line the old code never reached.
for _, callback in ipairs(deferred) do callback() end

local groups = mover.functions.GetGroups()
assert(#groups == 1, "deferred init must register the group once frame data is present, got " .. #groups)
assert(groups[1].id == "system", "registered group id should be 'system'")

local entries = mover.functions.GetEntriesForGroup("system")
assert(#entries == 1 and entries[1].id == "TestPanel",
	"deferred init must register the panel under its group")

-- Idempotency: re-running init (e.g. the settings page's self-heal call) must not
-- duplicate or wipe the registry.
mover.functions.InitRegistry()
assert(#mover.functions.GetGroups() == 1, "InitRegistry must be idempotent")

print("OK: blizzard_mover_lod_deferred_registry_test")
