-- tests/unit/cdm_reanchor_runtime_assemble_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_assemble_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

-- stub wiring: MatchCuratedToFrames returns a fixed split
local fMatch = { f = "blizz" }
local eMatched  = { name = "matched",  _assignedRow = 1 }
local eFrameless= { name = "frameless",_assignedRow = 2 }
local eAdd      = { name = "additional",_assignedRow = 3 }
local wiring = {
    MatchCuratedToFrames = function(_, curated, frameMap)
        -- eMatched -> fMatch; eFrameless -> none
        return { { entry = eMatched, frame = fMatch } }, { eFrameless }, { [fMatch] = true }
    end,
}

local mintCalls, shellCalls = {}, {}
local ownedIconF, ownedIconA = { o = "F" }, { o = "A" }
local runtime = R.New({
    bridge = {}, wiring = wiring,
    getCurated = function() return { eMatched, eFrameless } end,
    getAdditional = function() return { eAdd } end,
    mintOwned = function(entry)
        mintCalls[#mintCalls+1] = entry
        if entry == eFrameless then return ownedIconF end
        if entry == eAdd then return ownedIconA end
        return nil
    end,
    mintShell = function(entry) shellCalls[#shellCalls+1] = entry; return { s = "unused" } end,
})

local entries, claimed = runtime:AssembleEntries("essential", {})

assert(#entries == 3, "matched + frameless + additional assembled")
-- matched -> live Blizzard frame is the layout icon; no QUI shell is minted.
assert(entries[1].reanchored == true and entries[1].directAnchor == true and entries[1].frame == fMatch
    and entries[1].liveFrame == fMatch and entries[1].src == eMatched,
    "matched -> native live blizz frame")
assert(entries[2].reanchored == false and entries[2].frame == ownedIconF and entries[2].src == eFrameless, "frameless is an owned icon")
assert(entries[3].reanchored == false and entries[3].frame == ownedIconA and entries[3].src == eAdd, "additional is an owned icon")
assert(entries[1]._assignedRow == 1 and entries[2]._assignedRow == 2 and entries[3]._assignedRow == 3, "row carried from source entry")
assert(claimed[fMatch] == true, "claimedFrames passed through from match")
assert(#shellCalls == 0, "mintShell is not called for matched native entries")
assert(mintCalls[1] == eFrameless and mintCalls[2] == eAdd, "mintOwned called for frameless then additional, not for matched")

-- Curated order is the composer order. A frameless/manual entry between two
-- native matches must stay in that saved slot instead of being pushed after
-- all matched Blizzard frames.
local eFirstNative = { name = "first-native", _assignedRow = 1 }
local eMiddleOwned = { name = "middle-owned", _assignedRow = 1 }
local eLastNative = { name = "last-native", _assignedRow = 1 }
local fFirst, fLast = { f = "first" }, { f = "last" }
local orderedWiring = {
    MatchCuratedToFrames = function()
        return {
            { entry = eFirstNative, frame = fFirst },
            { entry = eLastNative, frame = fLast },
        }, {
            eMiddleOwned,
        }, {
            [fFirst] = true,
            [fLast] = true,
        }
    end,
}
local orderedRuntime = R.New({
    bridge = {},
    wiring = orderedWiring,
    getCurated = function() return { eFirstNative, eMiddleOwned, eLastNative } end,
    getAdditional = function() return {} end,
    mintOwned = function(entry) return { owned = entry.name } end,
    mintShell = function(entry) error("mintShell not expected for " .. entry.name) end,
})
local orderedEntries = orderedRuntime:AssembleEntries("essential", {})
assert(#orderedEntries == 3, "ordered native/owned entries assembled")
assert(orderedEntries[1].src == eFirstNative
    and orderedEntries[2].src == eMiddleOwned
    and orderedEntries[3].src == eLastNative,
    "reanchor assembly must preserve composer order across native/owned boundaries")

-- mintOwned returning nil drops that owned entry; matched native frame still present
local runtime2 = R.New({
    bridge = {}, wiring = wiring,
    getCurated = function() return { eMatched, eFrameless } end,
    getAdditional = function() return {} end,
    mintOwned = function() return nil end,
    mintShell = function() error("mintShell not expected") end,
})
local entries2 = runtime2:AssembleEntries("essential", {})
assert(#entries2 == 1 and entries2[1].src == eMatched and entries2[1].liveFrame == fMatch,
    "owned entry dropped when mintOwned returns nil; matched native frame still present")

-- Active-mode checks need the container key so the real env can use the
-- BuffIcon-specific "shown means active" fallback without changing
-- cooldown/utility semantics.
do
    local seenKey, seenEntry
    local activeRuntime = R.New({
        bridge = {},
        wiring = wiring,
        getCurated = function() return { eMatched } end,
        getAdditional = function() return {} end,
        getSettings = function() return { iconDisplayMode = "active" } end,
        frameIsActive = function(_, key, entry)
            seenKey = key
            seenEntry = entry
            return true
        end,
    })
    local activeEntries = activeRuntime:AssembleEntries("buff", {}, { iconDisplayMode = "active" })
    assert(#activeEntries == 1, "active buff match should assemble")
    assert(seenKey == "buff", "frameIsActive should receive the container key")
    assert(seenEntry == eMatched,
        "frameIsActive should receive the curated entry (aura-truth override needs its spellIDs)")
end

-- Blizzard-backed BuffIcon entries are native-only in the live path. If the
-- native item is stale or missing, QUI queues/retries reanchor elsewhere and
-- renders nothing here; it must not derive aura truth and mint a replacement
-- icon for a Blizzard-CDM buff.
do
    local eLive = { name = "live-aura", spellID = 48707, source = "blizzardCDM", _assignedRow = 1 }
    local staleFrame = { f = "stale-native" }
    local function mk(opts)
        local minted, auraCalls = {}, 0
        local runtime = R.New({
            bridge = {},
            wiring = {
                MatchCuratedToFrames = function()
                    if opts.matched then
                        return { { entry = eLive, frame = staleFrame } }, {}, { [staleFrame] = true }
                    end
                    return {}, { eLive }, {}
                end,
            },
            getCurated = function() return { eLive } end,
            getAdditional = function() return {} end,
            frameIsActive = function() return opts.nativeUsable and true or false end,
            entryAuraIsPresent = function(e)
                auraCalls = auraCalls + 1
                return opts.auraLive and e == eLive
            end,
            isEditMode = function() return false end,
            mintOwned = function() local icon = { owned = true }; minted[#minted + 1] = icon; return icon end,
        })
        local entries, claimed = runtime:AssembleEntries("buff", {}, { iconDisplayMode = "active" })
        return entries, claimed, minted, auraCalls
    end

    -- native healthy -> native claim, no owned mint
    local entries, claimed, minted, auraCalls = mk({ matched = true, nativeUsable = true, auraLive = true })
    assert(#entries == 1 and entries[1].reanchored == true and entries[1].liveFrame == staleFrame,
        "healthy native frame claims native (no fallback)")
    assert(#minted == 0, "no owned mint when native is usable")
    assert(auraCalls == 0, "healthy native Blizzard-CDM buff does not query aura truth")

    -- native STALE + aura live -> nothing; wait for native repair
    entries, claimed, minted, auraCalls = mk({ matched = true, nativeUsable = false, auraLive = true })
    assert(#entries == 0 and #minted == 0,
        "stale native Blizzard-CDM buff renders nothing instead of an owned fallback")
    assert(claimed[staleFrame] == nil, "stale native frame is unclaimed (left to Blizzard)")
    assert(auraCalls == 0, "stale native Blizzard-CDM buff does not query aura truth")

    -- native stale + aura NOT live -> nothing
    entries, claimed, minted, auraCalls = mk({ matched = true, nativeUsable = false, auraLive = false })
    assert(#entries == 0 and #minted == 0, "inactive entry renders nothing")
    assert(auraCalls == 0, "inactive Blizzard-CDM buff does not query aura truth")

    -- no native frame at all + aura live -> nothing in active mode
    entries, claimed, minted, auraCalls = mk({ matched = false, auraLive = false })
    assert(#entries == 0 and #minted == 0, "frameless inactive entry stays hidden in active mode")
    assert(auraCalls == 0, "frameless inactive Blizzard-CDM buff does not query aura truth")
    entries, claimed, minted, auraCalls = mk({ matched = false, auraLive = true })
    assert(#entries == 0 and #minted == 0,
        "frameless Blizzard-CDM buff with a live aura renders nothing until Blizzard creates the frame")
    assert(auraCalls == 0, "frameless live Blizzard-CDM buff does not query aura truth")
end

-- BOUNDARY INSTRUMENTATION: every assemble pass records a per-container diag
-- snapshot (GetLastDiag) so in-game diagnostics can pin WHICH link of the
-- native-only chain fails on a cold boot, without a debug-mode reload.
do
    local eLive = { name = "live-aura", spellID = 48707, source = "blizzardCDM", _assignedRow = 1 }
    local staleFrame = { f = "stale-native" }
    local staleWiring = {
        MatchCuratedToFrames = function()
            return { { entry = eLive, frame = staleFrame } }, {}, { [staleFrame] = true }
        end,
    }
    local rt = R.New({
        bridge = {},
        wiring = staleWiring,
        getCurated = function() return { eLive } end,
        getAdditional = function() return {} end,
        frameIsActive = function() return false end,
        entryAuraIsPresent = function(e) return e == eLive end,
        isEditMode = function() return false end,
        mintOwned = function() return { owned = true } end,
    })
    rt:AssembleEntries("buff", {}, { iconDisplayMode = "active" })
    local diag = rt:GetLastDiag("buff")
    assert(type(diag) == "table", "assemble records a diag snapshot")
    assert(diag.seq == 1, "diag: per-container pass sequence")
    assert(diag.displayMode == "active" and diag.filterInactive == true,
        "diag: display mode + active filter recorded")
    assert(diag.auraProbe == true, "diag: aura probe availability recorded")
    assert(diag.curated == 1 and diag.matched == 1 and diag.frameless == 0,
        "diag: curated/matched/frameless classification counts")
    assert(diag.staleNative == 1, "diag: stale-native (matched-but-inactive) count")
    assert(diag.fallbackLive == 0, "diag: no aura-live fallback for Blizzard-CDM buffs")
    assert(diag.minted == 0 and diag.mintFailed == 0, "diag: no owned mint for native-only miss")
    assert(diag.nativeClaimed == 0 and diag.entriesOut == 0,
        "diag: native claims + assembled entry count")
    rt:AssembleEntries("buff", {}, { iconDisplayMode = "active" })
    assert(rt:GetLastDiag("buff").seq == 2, "diag: sequence increments per pass")

    -- mintOwned must not be reached for native-only Blizzard-CDM misses.
    local rtFail = R.New({
        bridge = {},
        wiring = staleWiring,
        getCurated = function() return { eLive } end,
        getAdditional = function() return {} end,
        frameIsActive = function() return false end,
        entryAuraIsPresent = function(e) return e == eLive end,
        isEditMode = function() return false end,
        mintOwned = function() error("native-only Blizzard-CDM miss must not mint owned icon") end,
    })
    rtFail:AssembleEntries("buff", {}, { iconDisplayMode = "active" })
    local dFail = rtFail:GetLastDiag("buff")
    assert(dFail.minted == 0 and dFail.mintFailed == 0, "diag: no mint failure when minting is skipped")

    -- non-active mode: filter off, matched stale frame claimed natively
    local rtAlways = R.New({
        bridge = {},
        wiring = staleWiring,
        getCurated = function() return { eLive } end,
        getAdditional = function() return {} end,
        frameIsActive = function() return false end,
        entryAuraIsPresent = function(e) return e == eLive end,
        isEditMode = function() return false end,
        mintOwned = function() return { owned = true } end,
    })
    rtAlways:AssembleEntries("buff", {}, { iconDisplayMode = "always" })
    local dAlways = rtAlways:GetLastDiag("buff")
    assert(dAlways.filterInactive == false and dAlways.nativeClaimed == 1
        and dAlways.staleNative == 0,
        "diag: always mode claims natively, no stale-branch traffic")
end

print("OK: cdm_reanchor_runtime_assemble_test")
