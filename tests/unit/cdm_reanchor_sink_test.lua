-- tests/unit/cdm_reanchor_sink_test.lua
-- Run: lua tests/unit/cdm_reanchor_sink_test.lua
-- G10: Sink hides an unclaimed pool frame with SetAlpha(0) ONLY -- NO ClearAllPoints,
-- NO offscreen SetPoint, NO Cooldown writes. The anchor guard's unclaimed-branch
-- alpha-0 + Blizzard's next Layout pass (which overwrites any point we set) already hide
-- it, so the offscreen move was a redundant extra combat SetPoint + ClearAllPoints churn
-- on a managed GridLayout child.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor.lua", "cdm_reanchor.lua")("QUI", ns)
local CDMReanchor = assert(ns.CDMReanchor)

local calls = {}
local raw = {
    ClearAllPoints = function(f) calls[#calls+1] = { op = "clear", f = f } end,
    SetPoint = function(f, p, rel, rp, x, y)
        calls[#calls+1] = { op = "set", f = f, rel = rel, x = x, y = y }
    end,
    SetAlpha = function(f, a) calls[#calls+1] = { op = "alpha", f = f, a = a } end,
}
local sink = {}
local hideCalled = false
local drawSwipeCalls = {}
local cd = { SetDrawSwipe = function(_, v) drawSwipeCalls[#drawSwipeCalls+1] = v end }
local frame = { Hide = function() hideCalled = true end, Cooldown = cd }

local bridge = CDMReanchor.New({ raw = raw, securecall = function(fn, ...) return fn(...) end, sinkAnchor = sink })
bridge:Overlay(frame, {})
-- Measure Sink in isolation: drop the points Overlay recorded.
calls = {}
bridge:Sink(frame)

assert(bridge:IsClaimed(frame) == false, "sunk frame is not claimed")
assert(hideCalled == false, "Sink must NEVER call Hide() (pool-rebuild loops)")

local sawAlpha0, sawClear, sawOffscreen = false, false, false
for _, c in ipairs(calls) do
    if c.op == "alpha" and c.a == 0 then sawAlpha0 = true end
    if c.op == "clear" then sawClear = true end
    if c.op == "set" and c.rel == sink then sawOffscreen = true end
end
assert(sawAlpha0, "G10: Sink sets alpha 0")
assert(not sawClear, "G10: Sink must NOT ClearAllPoints (redundant churn on managed GridLayout child)")
assert(not sawOffscreen, "G10: Sink must NOT re-anchor offscreen (redundant extra combat SetPoint)")
assert(#drawSwipeCalls == 0,
    "G10: Sink must NOT write Cooldown:SetDrawSwipe -- Blizzard owns that channel; "
    .. "alpha 0 already hides the frame and a false here re-creates the swipe flicker fight")

local keyCount = 0
for _ in pairs(frame) do keyCount = keyCount + 1 end
assert(keyCount == 2, "Sink must NOT add keys onto the Blizzard frame (only pre-seeded Hide + Cooldown remain)")

print("OK: cdm_reanchor_sink_test")
