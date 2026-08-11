-- tests/unit/aura_skin_api_test.lua
-- Source-text assertion test for core/aura_skin.lua (12.1 PTR4 contract).
-- Run: lua tests/unit/aura_skin_api_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("core/aura_skin.lua")

-- Public namespace exposure
assert(src:find("QUI.AuraSkin", 1, true), "must expose QUI.AuraSkin")
assert(src:find("ns.Addon.AuraSkin", 1, true), "must register on ns.Addon.AuraSkin")

-- PTR4 public API surface
assert(src:find("AuraSkin.Configure", 1, true), "must define AuraSkin.Configure")
assert(src:find("AuraSkin.Restyle", 1, true), "must define AuraSkin.Restyle")
assert(src:find("AuraSkin.LayoutAnchor", 1, true), "must define AuraSkin.LayoutAnchor")
assert(src:find("AddAuraGroup", 1, true), "must register groups via AddAuraGroup")
assert(src:find("SetFlowLayoutGrowthDirection", 1, true), "must set container-wide flow direction")
assert(src:find("SetFlowLayoutMaximumLineSize", 1, true), "must derive the line cap from maxPerRow (pixels)")
assert(src:find("SetFlowLayoutAxis", 1, true), "must pick the flow axis (columns = Vertical) per grow")
assert(src:find("initializeFrame", 1, true), "must style buttons via the initializeFrame callback")

-- Groups are unremovable + filter-immutable: reconcile, never clear.
assert(not src:find("ClearAuraGroups", 1, true), "ClearAuraGroups is not addon-callable")
assert(not src:find("ClearAuraFilters", 1, true), "PTR3 filter API is gone")
assert(src:find("SetAuraGroupMaxFrameCount", 1, true), "stale groups retire via maxFrameCount 0")
assert(src:find("_quiGroups", 1, true), "must track registered group keys per container")

-- REMOVED 12.1 PTR4 APIs — using any of these is a hard error on live PTR
assert(not src:find("AddAuraFrame", 1, true), "AddAuraFrame was removed in PTR4")
assert(not src:find('CreateFrame("AuraButton"', 1, true), "addons may not create AuraButtons in PTR4")
assert(not src:find("SecureAuraHeader", 1, true), "SecureAuraHeaderTemplate was removed from Mainline")

-- The engine owns button layout now — AuraSkin must not size/position buttons
-- or fake a 1x1 container rect (containers auto-resize in PTR4).
assert(not src:find("button:SetPoint", 1, true), "engine anchors buttons; no addon SetPoint on buttons")
assert(not src:find("container:SetSize", 1, true), "containers auto-resize; no manual container SetSize")
assert(not src:find("GridOffset", 1, true), "addon grid math replaced by SetAuraGroupLayout")

-- No script on the forbidden buttons (UntrustedScriptExecution).
assert(not src:find("button:SetScript", 1, true), "no scripts on forbidden buttons (taint)")

-- Restyle registry: engine-created buttons are tracked for combat-legal restyle.
assert(src:find("_quiButtons", 1, true), "must track engine-created buttons on container._quiButtons")
assert(src:find("_quiWired", 1, true), "art build must keep the per-button idempotency guard")

-- Cancel support rides the initializer.
assert(src:find("SetCancelAuraButtons", 1, true), "must wire SetCancelAuraButtons for cancelButtons groups")

-- The engine's flow layout only positions buttons (SetPoint) and never sizes
-- them, so styleButton must size engine-created buttons itself.
assert(src:find("button:SetSize", 1, true), "must size engine-created buttons (engine flow layout never sizes them)")

-- In-combat AddAuraGroup runs forbidden frame creation synchronously; Configure
-- must refuse to register a new group while in combat.
assert(src:find("InCombatLockdown", 1, true), "Configure must refuse new-group creation in combat")

-- WireButton: wiring pair for slot buttons (core/aura_slots.lua), outside the
-- group initializeFrame path.
assert(src:find("function AuraSkin.WireButton", 1, true), "must define and export AuraSkin.WireButton")
assert(src:find("function AuraSkin.WirePreviewButton", 1, true),
    "must expose a plain-frame preview adapter over the same art/style functions")
assert(src:find("function AuraSkin.ReleasePreviewButton", 1, true),
    "must release preview-only external-skin ownership when placeholders hide")
assert(src:find("if button.SetIcon then", 1, true)
    and src:find("if button.SetDurationCooldown then", 1, true),
    "buildButtonArt must feature-detect secure inbound setters for plain preview frames")

-- styleButton is sub-table aware: duration{}/stack{} config drives text-region
-- styling (element model), with the legacy flat fontSize as fallback.
assert(src:find("profile.duration", 1, true), "styleButton must apply the duration text sub-table")
assert(src:find("profile.stack", 1, true), "styleButton must apply the stack text sub-table")

-- Text regions are re-anchored (ClearAllPoints before SetPoint) so a config
-- change moves them without a /reload; _quiDuration is the region restyled.
assert(src:find("button._quiDuration", 1, true), "must restyle the _quiDuration text region")
assert(src:find("fs:ClearAllPoints()", 1, true), "text regions must ClearAllPoints before re-anchoring")

print("aura_skin_api_test OK")
