-- tests/unit/cdm_reanchor_wiring_identity_cache_test.lua
-- Run: lua tests/unit/cdm_reanchor_wiring_identity_cache_test.lua
--
-- Cross-pass identity cache (combat-secret re-match). The frame map is rebuilt
-- from LIVE reads on every pass; in combat (12.1 secret aura phase) the
-- cooldownID/spellID reads resolve to nil, the frame drops out of every match
-- map, its curated entry goes frameless, and the anchor guard/Sink hold the
-- natively-SHOWN active frame at alpha 0 -- invisible until a clean read.
-- Reference model: cache per-frame identity whenever a read comes back CLEAN
-- (out of combat, acquire, OnCooldownIDSet) and fall back to the cache when the
-- live read is secret. Pool re-keys self-correct on the next clean pass.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
local W = assert(ns.CDMReanchorWiring)

local mode = "clean1"   -- "clean1" | "secret" | "clean2" | "recycleSecret" | "clean3"
local frame = {
    GetSpellID = function()
        if mode == "clean1" then return 777 end
        if mode == "clean2" then return 888 end
        if mode == "clean3" then return 999 end
        error("secret spell id read in combat")
    end,
}
local bridge = {
    EnumerateItems = function(_, viewer) return viewer.items end,
    ResolveIdentity = function(_, f)
        if f ~= frame then return nil end
        if mode == "clean1" then return 42 end
        if mode == "clean2" then return 43 end
        -- Pool recycle mid-combat: the cooldownID FIELD stays a plain read
        -- (secure layout assigns it) while the spell getters are secret.
        if mode == "recycleSecret" or mode == "clean3" then return 99 end
        return nil   -- secret cooldownID resolves to nil identity
    end,
}
local index = {
    ToBaseSpellID = function(id)
        if type(id) == "number" and id > 0 then return id end
        return nil
    end,
}
local wiring = W.New({ bridge = bridge, index = index })
local viewer = { items = { frame } }

-- Pass 1: clean reads prime the map (and the cache).
mode = "clean1"
local map = wiring:BuildFrameMap(viewer)
assert(map[42] == frame, "clean pass maps cooldownID")
assert(map._bySpell[777] == frame, "clean pass maps spell alias")
assert(map._canonicalByFrame[frame] == 777, "clean pass captures canonical id")

-- Pass 2: every live read is secret. The frame must still be matchable from the
-- cached identity (this is the combat flavor of 'active buff invisible').
mode = "secret"
local items
map, items = wiring:BuildFrameMap(viewer)
assert(items[1] == frame, "raw item list still carries the frame (sink pass input)")
assert(map[42] == frame, "combat-secret pass falls back to the CACHED cooldownID")
assert(map._bySpell[777] == frame, "combat-secret pass falls back to the CACHED spell alias")
assert(map._canonicalByFrame[frame] == 777, "combat-secret pass falls back to the CACHED canonical id")

-- Pass 3: pool re-key read CLEAN overwrites the cache (staleness self-corrects).
mode = "clean2"
map = wiring:BuildFrameMap(viewer)
assert(map[43] == frame and map[42] == nil, "clean re-key pass overwrites the cached cooldownID")
assert(map._bySpell[888] == frame and map._bySpell[777] == nil,
    "clean re-key pass overwrites the cached spell alias")
assert(map._canonicalByFrame[frame] == 888, "clean re-key pass overwrites the cached canonical id")

-- Pass 4: secret again -> the UPDATED identity is used, not the original.
mode = "secret"
map = wiring:BuildFrameMap(viewer)
assert(map[43] == frame and map[42] == nil, "secret pass after re-key uses the updated cache")
assert(map._bySpell[888] == frame and map._bySpell[777] == nil,
    "secret pass after re-key uses the updated spell alias")

-- Pass 5: pool RECYCLE with combat-secret spell reads. The cooldownID re-keys
-- CLEAN (plain field) while GetSpellID is secret -- the cached spell/canonical
-- ids belong to the PREVIOUS occupant and must be WIPED, not consulted: a stale
-- spell alias binds the recycled frame to the OLD entry's slot (in-game: Death
-- Coil's slot rendering a health-potion icon after Blizzard re-pooled the frame).
mode = "recycleSecret"
map = wiring:BuildFrameMap(viewer)
assert(map[99] == frame and map[43] == nil, "recycle: clean cooldownID re-key maps the NEW id")
assert(map._bySpell[888] == nil and map._bySpell[777] == nil,
    "recycle: stale spell alias from the previous occupant is NOT served")
assert(map._canonicalByFrame[frame] == nil,
    "recycle: stale canonical id is NOT served (exact pass cannot stale-bind)")

-- Pass 6: still secret, same recycled key -- cooldownID fallback works, spell
-- identity stays empty until a clean read primes it under the NEW cooldownID.
mode = "secret"
map = wiring:BuildFrameMap(viewer)
assert(map[99] == frame, "post-recycle secret pass keeps the new cooldownID from cache")
assert(map._bySpell[888] == nil and map._canonicalByFrame[frame] == nil,
    "post-recycle secret pass never resurrects the previous occupant's identity")

-- Pass 7: clean read under the new cooldownID re-primes spell/canonical.
mode = "clean3"
map = wiring:BuildFrameMap(viewer)
assert(map[99] == frame and map._bySpell[999] == frame and map._canonicalByFrame[frame] == 999,
    "clean pass under the new cooldownID re-primes the spell/canonical identity")

-- A frame NEVER seen clean stays unmapped (current sink-only behavior preserved:
-- present in items, absent from every match map).
do
    local ghost = { GetSpellID = function() error("secret") end }
    mode = "secret"
    local m2, it2 = wiring:BuildFrameMap({ items = { ghost } })
    assert(it2[1] == ghost, "never-clean frame still enumerated for sinking")
    assert(m2._canonicalByFrame[ghost] == nil, "never-clean frame has no canonical id")
    local claimed = false
    for k, v in pairs(m2) do
        if type(k) == "number" and v == ghost then claimed = true end
    end
    assert(not claimed, "never-clean frame is not claimable from thin air")
end

-- Cache is per wiring instance: a fresh instance has nothing to fall back on.
do
    local wiring2 = W.New({ bridge = bridge, index = index })
    mode = "secret"
    local m3 = wiring2:BuildFrameMap(viewer)
    assert(m3[42] == nil and m3[43] == nil,
        "fresh wiring instance has no cached identity (cache primed only by clean reads)")
end

print("OK: cdm_reanchor_wiring_identity_cache_test")
