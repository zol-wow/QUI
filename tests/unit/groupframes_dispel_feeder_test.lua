-- Dispel overlay feeder: engine-slot presence for the healer dispel overlay
-- and cleanse glow (groupframes_dispel_feeder.lua). Verifies the slot plan
-- (filters, candidate filters, parking), the dispel-type color-map
-- conversion, the secret/combat incompleteness contract, and the hard
-- feeder invariant that no script handler is ever installed in the slot
-- subtree (the engine refuses secret SetShown on buttons with scripts).

local failures = 0
local function check(label, ok, detail)
    if ok then
        print("PASS: " .. label)
    else
        failures = failures + 1
        print("FAIL: " .. label .. (detail and (" -- " .. tostring(detail)) or ""))
    end
end

----------------------------------------------------------------------------
-- WoW stubs
----------------------------------------------------------------------------
local combat = false
local secret = false
_G.InCombatLockdown = function() return combat end
_G.C_Secrets = { ShouldAurasBeSecret = function() return secret end }
_G.Enum = _G.Enum or {}
_G.Enum.CustomAuraButtonDispelTypeTextureStyle = {
    Border = 0, BorderWithIcon = 1, Icon = 2, PreserveAsset = 3, CustomAsset = 4,
}

local scriptInstalls = 0

local function MakeTexture()
    local t = { _alpha = 1, _shown = false }
    function t:SetIgnoreParentAlpha(v) self._ignoreParentAlpha = v end
    function t:DisablePixelSnap() end
    function t:SetColorTexture() end
    function t:SetTexture(path) self._texture = path end
    function t:SetBlendMode(mode) self._blend = mode end
    function t:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
    function t:ClearAllPoints() self._points = {} end
    function t:SetPoint(...) self._points = self._points or {}; self._points[#self._points + 1] = { ... } end
    function t:SetAllPoints(region) self._allPoints = region end
    function t:SetHeight(h) self._h = h end
    function t:SetWidth(w) self._w = w end
    function t:SetSize(w, h) self._w, self._h = w, h end
    function t:SetAlpha(a) self._alpha = a end
    function t:Show() self._shown = true end
    function t:Hide() self._shown = false end
    function t:SetScript() scriptInstalls = scriptInstalls + 1 end
    return t
end

local function MakeSlotButton(key)
    local b = { _key = key, _dispelRegs = {}, _clearCalls = 0 }
    function b:SetAlpha(a) self._alpha = a end
    function b:SetSize(w, h) self._w, self._h = w, h end
    function b:EnableMouse(v) self._mouse = v end
    function b:SetMouseClickEnabled(v) self._mouseClick = v end
    function b:CreateTexture() return MakeTexture() end
    function b:ClearDispelTypeTextures()
        self._clearCalls = self._clearCalls + 1
        self._dispelRegs = {}
    end
    function b:AddDispelTypeTexture(tex, opts)
        self._dispelRegs[#self._dispelRegs + 1] = { texture = tex, opts = opts }
    end
    function b:SetScript() scriptInstalls = scriptInstalls + 1 end
    return b
end

local function MakeContainer()
    local c = { _slots = {}, _filters = {}, _cf = {}, _level = 1 }
    function c:SetSize() end
    function c:SetPoint() end
    function c:SetUnit(unit) self._unit = unit end
    function c:SetEnabled(v) self._enabled = v end
    function c:Show() self._shown = true end
    function c:Hide() self._shown = false end
    function c:SetFrameLevel(l) self._level = l end
    function c:GetFrameLevel() return self._level end
    function c:AddAuraSlot(key, filter, opts)
        local slot = MakeSlotButton(key)
        self._slots[key] = slot
        self._filters[key] = filter
        self._cf[key] = opts and opts.candidateFilters
        if opts and opts.initializeFrame then opts.initializeFrame(slot) end
        return slot
    end
    function c:SetAuraSlotFilterString(key, filter) self._filters[key] = filter end
    function c:SetAuraSlotCandidateFilters(key, cf) self._cf[key] = cf end
    return c
end

local lastContainer
_G.CreateFrame = function(ftype, _name, _parent, template)
    assert(ftype == "AuraContainer" and template == "CustomAuraContainerTemplate",
        "feeder must create a CustomAuraContainerTemplate AuraContainer")
    lastContainer = MakeContainer()
    return lastContainer
end

local function MakeHostFrame()
    local f = { _level = 5 }
    function f:GetFrameLevel() return self._level end
    return f
end

----------------------------------------------------------------------------
-- Load the module
----------------------------------------------------------------------------
local ns = { QUI_GroupFrameChrome = { LEVELS = { DISPEL = 8 } } }
local F = assert(loadfile("QUI_GroupFrames/groupframes/groupframes_dispel_feeder.lua"))("QUI_GroupFrames", ns)
check("module publishes ns.QUI_GFDispelFeeder", ns.QUI_GFDispelFeeder == F and type(F.Sync) == "function")

-- HARMFUL|RAID = harmful auras the PLAYER can dispel (AuraUtil.AuraFilters);
-- RAID_PLAYER_DISPELLABLE would match anything anyone in the raid can dispel.
local BY_ME = "HARMFUL|RAID"

local function isParked(cf)
    return type(cf) == "table" and cf.maxDuration == 0 and next(cf, next(cf)) == nil
end

----------------------------------------------------------------------------
-- (1) Default scope (PLAYER_DISPELLABLE), border on, glow off
----------------------------------------------------------------------------
local frame = MakeHostFrame()
local settings = {
    dispelOverlay = {
        enabled = true, scope = "PLAYER_DISPELLABLE",
        opacity = 0.8, fillOpacity = 0.18, borderSize = 3,
        colors = {
            Magic = { 0.2, 0.6, 1.0, 1 },
            Bleed = { 0.8, 0.0, 0.0, 1 },
        },
    },
}
local complete = F.Sync(frame, "party1", true, settings)
local c = lastContainer
check("sync completes out of combat", complete == true)
check("container tracks the frame unit", c and c._unit == "party1")
check("container enabled and shown", c and c._enabled == true and c._shown == true)
check("container seated at frame level + DISPEL", c and c._level == 13)
check("visual slot uses the pure engine dispellable token", c and c._filters.visual == BY_ME)
check("visual slot carries no candidate filters in by-me scope", c and c._cf.visual == nil)
check("glow slot exists but is parked when cleanse glow is off",
    c and c._filters.glow == BY_ME and isParked(c._cf.glow))
check("frame flagged feeder-active for the legacy path gate", frame._quiDispelFeederActive == true)

local visual = c and c._slots.visual
check("visual slot muted (alpha 0, 1x1, mouse off)",
    visual and visual._alpha == 0 and visual._w == 1 and visual._mouse == false)

-- Art bindings: 4 borders + fill share PreserveAsset + the color map; no icon.
local borderRegs, iconRegs = 0, 0
local colorMapSeen
for _, reg in ipairs(visual and visual._dispelRegs or {}) do
    if reg.opts.style == 3 then
        borderRegs = borderRegs + 1
        colorMapSeen = colorMapSeen or reg.opts.customDispelColorMap
    elseif reg.opts.style == 2 then
        iconRegs = iconRegs + 1
    end
end
check("borders + fill bound via PreserveAsset dispel textures", borderRegs == 5, borderRegs)
check("no icon binding when showIcon is off", iconRegs == 0, iconRegs)
check("color map converts {r,g,b,a} arrays to {r=,g=,b=}",
    colorMapSeen and colorMapSeen.Magic and colorMapSeen.Magic.r == 0.2
        and colorMapSeen.Magic.g == 0.6 and colorMapSeen.Magic.b == 1.0)
check("Enrage aliases the Bleed color",
    colorMapSeen and colorMapSeen.Enrage == colorMapSeen.Bleed)
check("None (typeless) falls back to the Magic color",
    colorMapSeen and colorMapSeen.None == colorMapSeen.Magic)
check("no script handler installed anywhere in the slot subtree", scriptInstalls == 0)

----------------------------------------------------------------------------
-- (2) ALL_TYPED scope + icon + glow
----------------------------------------------------------------------------
settings.dispelOverlay.scope = "ALL_TYPED"
settings.dispelOverlay.showIcon = true
settings.cleanseGlow = { enabled = true, color = { 0.3, 1, 0.3, 0.9 } }
complete = F.Sync(frame, "party1", true, settings)
check("re-sync completes", complete == true)
check("ALL_TYPED swaps the visual filter to bare HARMFUL", c._filters.visual == "HARMFUL")
local cf = c._cf.visual
check("ALL_TYPED includes the five dispel types plus Enrage",
    type(cf) == "table" and type(cf.includeDispelTypes) == "table"
        and cf.includeDispelTypes.Magic and cf.includeDispelTypes.Curse
        and cf.includeDispelTypes.Disease and cf.includeDispelTypes.Poison
        and cf.includeDispelTypes.Bleed and cf.includeDispelTypes.Enrage)
check("glow slot unparks when cleanse glow turns on", c._cf.glow == nil)

iconRegs = 0
for _, reg in ipairs(visual._dispelRegs) do
    if reg.opts.style == 2 then iconRegs = iconRegs + 1 end
end
check("icon binding added with the engine Icon style", iconRegs == 1, iconRegs)

local glowSlot = c._slots.glow
local glowTex = glowSlot and glowSlot._quiDispelArt and glowSlot._quiDispelArt.glow
check("glow art styled with the configured color",
    glowTex and glowTex._vertex and glowTex._vertex[1] == 0.3 and glowTex._vertex[2] == 1
        and glowTex._blend == "ADD")
check("still no script handlers after restyle", scriptInstalls == 0)

----------------------------------------------------------------------------
-- (2b) Life gate: dead/ghost/nonexistent units wear no dispel visuals
----------------------------------------------------------------------------
check("container shown while configured and alive", c._shown == true)
F.SetLifeGate(frame, false)
check("life gate hides the container on a dead unit", c._shown == false)
complete = F.Sync(frame, "party1", true, settings)
check("re-sync while dead keeps the container hidden",
    complete == true and c._shown == false)
F.SetLifeGate(frame, true)
check("life gate re-shows the container after resurrection", c._shown == true)
F.SetLifeGate(MakeHostFrame(), false)
check("life gate on a frame without a feeder is a safe no-op", true)

----------------------------------------------------------------------------
-- (3) Feature fully off: park everything, disable the container
----------------------------------------------------------------------------
settings.dispelOverlay.enabled = false
settings.dispelOverlay.showIcon = false
settings.cleanseGlow.enabled = false
complete = F.Sync(frame, "party1", true, settings)
check("disable sync completes", complete == true)
check("visual slot parked when the feature is off", isParked(c._cf.visual))
check("glow slot parked when the feature is off", isParked(c._cf.glow))
check("container disabled and hidden when the feature is off",
    c._enabled == false and c._shown == false)
F.SetLifeGate(frame, false)
F.SetLifeGate(frame, true)
check("life gate cannot re-show a config-disabled container", c._shown == false)
check("legacy gate stays armed while a feeder exists", frame._quiDispelFeederActive == true)

----------------------------------------------------------------------------
-- (4) Secrecy: styling refused -> incomplete, but filters still applied
----------------------------------------------------------------------------
settings.dispelOverlay.enabled = true
settings.dispelOverlay.scope = "PLAYER_DISPELLABLE"
secret = true
local clearsBefore = visual._clearCalls
complete = F.Sync(frame, "party2", true, settings)
check("sync reports incomplete while auras are secret", complete == false)
check("no slot-subtree writes while secret", visual._clearCalls == clearsBefore)
check("container-level unit tracking still applies while secret", c._unit == "party2")
check("filter mutations still apply while secret", c._filters.visual == BY_ME)
secret = false

----------------------------------------------------------------------------
-- (5) Combat with no pre-built feeder: no structural work, incomplete
----------------------------------------------------------------------------
combat = true
local freshFrame = MakeHostFrame()
local containersBefore = lastContainer
complete = F.Sync(freshFrame, "party3", true, settings)
check("no container creation in combat", lastContainer == containersBefore)
check("sync reports incomplete so the caller requeues", complete == false)
check("fresh frame not flagged active without a feeder", freshFrame._quiDispelFeederActive == nil)
combat = false

----------------------------------------------------------------------------
-- (6) Feature off with no feeder built: nothing to do, complete
----------------------------------------------------------------------------
local idleFrame = MakeHostFrame()
complete = F.Sync(idleFrame, "party4", true, { dispelOverlay = { enabled = false } })
check("disabled feature without a feeder is a complete no-op",
    complete == true and idleFrame._quiDispelFeeder == nil
        and idleFrame._quiDispelFeederActive == nil)

if failures > 0 then
    print(string.format("FAILED: %d check(s)", failures))
    os.exit(1)
end
print("OK: groupframes_dispel_feeder_test")
