-- tests/unit/cdm_reanchor_live_tooltip_test.lua
-- Run: lua tests/unit/cdm_reanchor_live_tooltip_test.lua
-- Task B3 (G9 Option B): buff retired the per-slot shell (B2 direct-anchors
-- the live Blizzard frame to the container), so the shell no longer hosts the tooltip.
-- ensureLiveTooltip restores it via an OWN-CHILD mouse-catcher overlay on the LIVE frame.
-- CRITICAL: every mouse/script write rides OUR overlay; the live Blizzard frame is NEVER
-- SetScript'd / EnableMouse'd (that would clobber Blizzard's native scripts + risk taint).

function InCombatLockdown() return false end
UIParent = {}

local shownTooltip, hiddenTooltip
local ns = {
    CDMIconFactory = {
        ShowEntryTooltip = function(owner, entry, context)
            shownTooltip = { owner = owner, entry = entry, context = context }
        end,
        HideEntryTooltip = function() hiddenTooltip = true end,
    },
}

-- Overlays created by ensureLiveTooltip. GetFrameLevel reflects SetFrameLevel so the
-- raise-above-live assertion is exact.
local createdOverlays = {}
function CreateFrame(_frameType, _name, parent)
    local f = { parent = parent, shown = false, scripts = {}, level = 0 }
    function f:GetParent() return self.parent end
    function f:SetAllPoints(rel) self.allPoints = rel; self.allPointsCount = (self.allPointsCount or 0) + 1 end
    function f:EnableMouse(v) self.mouseEnabled = v ~= false end
    function f:SetMouseClickEnabled(v) self.mouseClickEnabled = v == true end
    function f:SetMouseMotionEnabled(v) self.mouseMotionEnabled = v == true end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:GetScript(name) return self.scripts[name] end
    function f:Show() self.shown = true; self.showCount = (self.showCount or 0) + 1 end
    function f:Hide() self.shown = false end
    createdOverlays[#createdOverlays + 1] = f
    return f
end

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_realenv.lua", "cdm_reanchor_realenv.lua")("QUI", ns)

local env = ns.CDMReanchorRealEnv.BuildEnv({})
assert(type(env.ensureLiveTooltip) == "function", "BuildEnv exposes ensureLiveTooltip on the env table")

-- LIVE Blizzard frame: records SetScript / EnableMouse so we can PROVE they are never called.
local liveSetScriptCalls, liveEnableMouseCalls = 0, 0
local live = {
    frameLevel = 7,
    GetFrameLevel = function(self) return self.frameLevel end,
    SetScript = function() liveSetScriptCalls = liveSetScriptCalls + 1 end,
    EnableMouse = function() liveEnableMouseCalls = liveEnableMouseCalls + 1 end,
}

local entry = { id = 111, spellID = 111 }
local overlay = assert(env.ensureLiveTooltip(live, entry), "ensureLiveTooltip returns the overlay")

-- Own-child of the live frame (parent == live), exactly one created.
assert(overlay:GetParent() == live, "overlay is a CHILD of the LIVE frame (parent == live)")
assert(#createdOverlays == 1, "exactly one overlay frame created")

-- Mouse-catcher: motion on, click off.
assert(overlay.mouseEnabled == true, "overlay is mouse-enabled")
assert(overlay.mouseMotionEnabled == true, "overlay receives mouse motion")
assert(overlay.mouseClickEnabled == false, "overlay does NOT take click ownership")

-- Raised above the live frame's own content so it catches the mouse over the icon/swipe.
assert(overlay:GetFrameLevel() > live:GetFrameLevel(),
    "overlay raised above the live frame level")
assert(overlay:GetFrameLevel() == live:GetFrameLevel() + 4, "overlay raised +4 above the live level")

-- Scripts wired on OUR overlay.
assert(type(overlay:GetScript("OnEnter")) == "function", "overlay has OnEnter")
assert(type(overlay:GetScript("OnLeave")) == "function", "overlay has OnLeave")

-- Entry stamped on OUR overlay (never a custom key on the Blizzard frame).
assert(overlay._entry == entry, "entry stamped on overlay._entry")
assert(overlay.shown == true, "overlay is shown")

-- CRITICAL: NO SetScript / EnableMouse on the LIVE Blizzard frame itself.
assert(liveSetScriptCalls == 0, "ensureLiveTooltip NEVER SetScript's the live Blizzard frame")
assert(liveEnableMouseCalls == 0, "ensureLiveTooltip NEVER EnableMouse's the live Blizzard frame")

-- OnEnter reads the entry off OUR overlay and shows the CDM entry tooltip.
overlay:GetScript("OnEnter")(overlay)
assert(shownTooltip and shownTooltip.owner == overlay and shownTooltip.entry == entry
    and shownTooltip.context == "cdm", "OnEnter shows the entry tooltip read from overlay._entry")
overlay:GetScript("OnLeave")(overlay)
assert(hiddenTooltip == true, "OnLeave hides the entry tooltip")

-- Reused (cached) on the second call; entry refreshed; no second frame created.
local entry2 = { id = 222, spellID = 222 }
local overlay2 = env.ensureLiveTooltip(live, entry2)
assert(overlay2 == overlay, "second call reuses the cached overlay for the same live frame")
assert(#createdOverlays == 1, "no new overlay frame created on reuse")
assert(overlay._entry == entry2, "overlay._entry refreshed to the new entry on reuse")
assert(liveSetScriptCalls == 0 and liveEnableMouseCalls == 0,
    "reuse still never SetScript's / EnableMouse's the live frame")

-- hideLiveTooltip: overlay must be hidden + mouse disabled when the frame is sunk.
-- BuildEnv must expose the function on the env table.
assert(type(env.hideLiveTooltip) == "function", "BuildEnv exposes hideLiveTooltip on the env table")

-- nil-safe: calling with no live frame must not error.
env.hideLiveTooltip(nil)

-- Call on a live frame that has no overlay yet: must be a no-op.
local liveFresh = { GetFrameLevel = function() return 0 end }
env.hideLiveTooltip(liveFresh)

-- Hide the overlay for the live frame we set up above.
env.hideLiveTooltip(live)
assert(overlay.shown == false, "hideLiveTooltip: overlay:Hide() is called (shown → false)")
assert(overlay.mouseEnabled == false, "hideLiveTooltip: overlay:EnableMouse(false) is called")

-- Re-claim: ensureLiveTooltip must re-show + re-enable mouse + refresh entry.
local entry3 = { id = 333, spellID = 333 }
local overlay3 = env.ensureLiveTooltip(live, entry3)
assert(overlay3 == overlay, "re-claim reuses the same cached overlay")
assert(overlay.shown == true, "re-claim: overlay:Show() is called (shown → true)")
assert(overlay.mouseEnabled == true, "re-claim: overlay:EnableMouse(true) restores mouse on re-claimed frame")
assert(overlay._entry == entry3, "re-claim: overlay._entry refreshed to the new entry")

print("OK: cdm_reanchor_live_tooltip_test")
