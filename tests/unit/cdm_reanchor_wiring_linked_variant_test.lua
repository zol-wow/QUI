-- tests/unit/cdm_reanchor_wiring_linked_variant_test.lua
-- Run: lua tests/unit/cdm_reanchor_wiring_linked_variant_test.lua
--
-- G7: Eclipse-style linked-variant siblings (Balance Druid Solar + Lunar, Outlaw
-- Roll-the-Bones forms) share cooldownInfo.linkedSpellIDs, so first-wins frame
-- matching collapses BOTH curated configs onto the SAME frame -- only one renders.
-- The distinguishing identity is the live frame's GetAuraSpellID(). This suite
-- asserts each curated variant resolves to a DISTINCT frame, and that ordinary
-- single spells with no linked siblings still resolve as before.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
local W = assert(ns.CDMReanchorWiring)

local index = {
    ToBaseSpellID = function(id)
        if type(id) == "number" and id > 0 then return id end
        return nil
    end,
    IsUsableID = function(id) return type(id) == "number" and id > 0 end,
    ForEachCooldownInfoID = function(info, cb)
        cb(info.overrideSpellID)
        cb(info.spellID)
        if info.linkedSpellIDs then
            for i = 1, #info.linkedSpellIDs do cb(info.linkedSpellIDs[i]) end
        end
    end,
}

-------------------------------------------------------------------------------
-- Case 1: Eclipse Solar + Lunar share linkedSpellIDs {A,B}, distinct GetAuraSpellID.
-------------------------------------------------------------------------------
local A, B = 48517, 48518
local frameSolar = { GetAuraSpellID = function() return A end }
local frameLunar = { GetAuraSpellID = function() return B end }
-- Both frames carry the SAME shared cooldownInfo (the collapse cause).
local sharedInfo = { linkedSpellIDs = { A, B } }
local bridge = {
    EnumerateItems = function(_, viewer) return viewer.items end,
    -- No stable cooldownID identity -> resolution goes through the alias path,
    -- where the shared linkedSpellIDs would first-wins-collapse onto one frame.
    ResolveIdentity = function() return nil end,
    GetFrameCooldownInfo = function() return sharedInfo end,
}
local wiring = W.New({ bridge = bridge, index = index })
local viewer = { items = { frameSolar, frameLunar } }
local map = wiring:BuildFrameMap(viewer)

-- per-frame canonical map is populated from GetAuraSpellID
assert(map._canonicalByFrame[frameSolar] == A, "frameSolar canonical = A (GetAuraSpellID)")
assert(map._canonicalByFrame[frameLunar] == B, "frameLunar canonical = B (GetAuraSpellID)")

local eSolar = { spellID = A, source = "blizzardCDM" }
local eLunar = { spellID = B, source = "blizzardCDM" }
-- resolveEntryCooldownID returns nil so both fall to the alias/exact path.
local matched, frameless = wiring:MatchCuratedToFrames({ eSolar, eLunar }, map, "trackedBar")

assert(#matched == 2, "both Eclipse variants matched (got " .. #matched .. ")")
assert(#frameless == 0, "no Eclipse variant left frameless (got " .. #frameless .. ")")
local frameFor = {}
for i = 1, #matched do frameFor[matched[i].entry] = matched[i].frame end
assert(frameFor[eSolar] == frameSolar, "Solar entry -> frameSolar")
assert(frameFor[eLunar] == frameLunar, "Lunar entry -> frameLunar")
assert(frameFor[eSolar] ~= frameFor[eLunar], "the two variants must NOT collapse onto one frame")

-------------------------------------------------------------------------------
-- Case 2: ordinary single spell, no linked siblings -> still resolves (regression).
-------------------------------------------------------------------------------
local C = 12294
local frameC = { GetAuraSpellID = function() return C end }
local infoC = { linkedSpellIDs = { C } }
local bridge2 = {
    EnumerateItems = function(_, v) return v.items end,
    ResolveIdentity = function() return nil end,
    GetFrameCooldownInfo = function() return infoC end,
}
local wiring2 = W.New({ bridge = bridge2, index = index })
local map2 = wiring2:BuildFrameMap({ items = { frameC } })
local eC = { spellID = C, source = "blizzardCDM" }
local matchedC, framelessC = wiring2:MatchCuratedToFrames({ eC }, map2, "essential")
assert(#matchedC == 1 and matchedC[1].frame == frameC, "single spell still matches its frame")
assert(#framelessC == 0, "single spell not left frameless")

-------------------------------------------------------------------------------
-- Case 3: manually-built frameMap WITHOUT canonical structures -> exact pass is a
-- no-op; existing first-wins cooldownID matching is preserved unchanged.
-------------------------------------------------------------------------------
local fX = { f = "X" }
local plainWiring = W.New({ resolveEntryCooldownID = function(e) return e.cd end })
local m3, fl3 = plainWiring:MatchCuratedToFrames({ { cd = 7 } }, { [7] = fX }, nil)
assert(#m3 == 1 and m3[1].frame == fX, "no-canonical frameMap still resolves first-wins")
assert(#fl3 == 0, "no-canonical single match not frameless")

print("OK: cdm_reanchor_wiring_linked_variant_test")
