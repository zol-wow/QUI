-- tests/unit/castbar_spellcast_secret_boundary_test.lua
-- Run: lua5.1 tests/unit/castbar_spellcast_secret_boundary_test.lua
--
-- Wave 2b Task D: QUI_UnitFrames/unitframes/castbar.lua UNIT_SPELLCAST_SUCCEEDED
-- consumers.
--
-- Dispatch-layer finding (documented, not a bug): the player/target/focus
-- castbar's single OnEvent handler is
--   castbar:SetScript("OnEvent", function(self, event, eventUnit, castGUID, spellID)
--       local handler = eventHandlers[event]
--       if handler then handler(self, spellID) end
--   end)
-- This unpacks the real UNIT_SPELLCAST_SUCCEEDED payload order per
-- tests/api-docs/blizzard/UnitDocumentation.lua:4670-4673 (unitTarget,
-- castGUID, spellID, castBarID) correctly: eventUnit=unitTarget,
-- castGUID=castGUID, spellID=spellID. So eventHandlers.UNIT_SPELLCAST_SUCCEEDED
-- = function(self, spellID) genuinely receives spellID, NOT unit -- the brief's
-- suspected arg-mismatch does not exist in this file. Case 1 below pins the
-- real wiring behaviorally (not just by reading the source) so a future
-- refactor that swaps the wrapper's forwarded argument is caught.
--
-- Boundary: eventHandlers.UNIT_SPELLCAST_SUCCEEDED (player-only, ~:2886) was
-- ALREADY probing spellID via the file's pre-existing SafeToNumber() helper
-- (which itself checks IsSecretValue() before trusting type(v)=="number")
-- before this task started -- no production fix was needed. Cases 2-3 pin
-- that existing discipline behaviorally: a secret spellID/eventUnit must not
-- corrupt self._lastGCDSpellID (the GCD-cache field this handler writes) and
-- must not throw.
--
-- The registered-token discipline is structural: the dispatcher above never
-- forwards eventUnit to eventHandlers.UNIT_SPELLCAST_SUCCEEDED at all (only
-- `self` and `spellID` are passed) -- the handler always uses the closure's
-- own self.unit, never the payload unit. Case 3 proves this by making the
-- payload unit a maximally hostile throwing sentinel and confirming it is
-- never touched.
--
-- Caveat (numeric secrets are headlessly untestable, honestly, same as the
-- sibling Wave 2b tests): a REAL WoW secret spellID is an opaque engine value
-- whose type() still reports "number" but which throws on comparison/
-- arithmetic. tests/helpers/secret_sentinel.lua's sentinel is a Lua *table*
-- (type() == "table"), so it cannot reproduce that specific "looks like a
-- number, throws on compare" shape -- it stands in for the general
-- "probe before touch" discipline, not the engine's exact throw semantics.
-- What IS verified here, honestly: (a) the real arg plumbing end to end, and
-- (b) that a secret payload value never gets stored into castbar state that
-- a later frame could compare/index -- the corruption case, mutation-checked
-- by temporarily deleting the SafeToNumber() call at the handler's first line
-- during development (see task report) and confirming Case 2 then fails.
-- luacheck: globals GetTime CreateFrame InCombatLockdown UnitCastingInfo UnitChannelInfo UnitClass UnitGUID UIParent RAID_CLASS_COLORS C_Timer EventRegistry

local function noop() end

local function newRegion(frameType, parent)
    local region = {
        frameType = frameType or "Frame",
        parent = parent,
        width = 0,
        height = 0,
        shown = true,
        alpha = 1,
        frameLevel = 1,
        frameStrata = "MEDIUM",
        points = {},
    }

    function region:SetSize(width, height) self.width = width; self.height = height end
    function region:SetWidth(width) self.width = width end
    function region:SetHeight(height) self.height = height end
    function region:GetWidth() return self.width end
    function region:GetHeight() return self.height end
    function region:SetPoint(...) self.points[#self.points + 1] = {...} end
    function region:ClearAllPoints() self.points = {} end
    function region:SetAllPoints(anchor) self.allPoints = anchor or self.parent or true end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown and self.alpha ~= 0 end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:GetAlpha() return self.alpha end
    function region:SetFrameStrata(strata) self.frameStrata = strata end
    function region:GetFrameStrata() return self.frameStrata end
    function region:SetFrameLevel(level) self.frameLevel = level end
    function region:GetFrameLevel() return self.frameLevel end
    function region:GetParent() return self.parent end
    function region:CreateTexture() return newRegion("Texture", self) end

    function region:CreateFontString()
        local fs = newRegion("FontString", self)
        fs.fontPath = "Fonts\\FRIZQT__.TTF"
        fs.fontSize = 12
        fs.fontFlags = ""
        function fs:SetFont(path, size, flags) self.fontPath = path; self.fontSize = size; self.fontFlags = flags end
        function fs:GetFont() return self.fontPath, self.fontSize, self.fontFlags end
        function fs:SetText(text) self.text = text end
        function fs:SetFormattedText(format, value) self.text = string.format(format, value) end
        function fs:GetStringWidth() return #(self.text or "") * 6 end
        function fs:SetTextColor(r, g, b, a) self.textColor = {r, g, b, a} end
        function fs:SetWordWrap(value) self.wordWrap = value end
        function fs:SetJustifyH(value) self.justifyH = value end
        function fs:SetJustifyV(value) self.justifyV = value end
        return fs
    end

    function region:SetScript(scriptName, handler) self.scripts = self.scripts or {}; self.scripts[scriptName] = handler end
    function region:RegisterUnitEvent(event, ...) self.unitEvents = self.unitEvents or {}; self.unitEvents[event] = {...} end
    function region:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function region:UnregisterAllEvents() self.unitEvents = {}; self.events = {} end
    function region:SetMovable(value) self.movable = value end
    function region:EnableMouse(value) self.mouseEnabled = value end
    function region:RegisterForDrag(...) self.dragButtons = {...} end
    function region:SetClampedToScreen(value) self.clampedToScreen = value end
    function region:GetCenter() return 0, 0 end
    function region:SetMinMaxValues(minValue, maxValue) self.minValue = minValue; self.maxValue = maxValue end
    function region:SetValue(value) self.value = value end
    function region:SetStatusBarColor(r, g, b, a) self.statusBarColor = {r, g, b, a} end
    function region:SetStatusBarTexture(texture) self.statusBarTexture = texture end
    function region:GetStatusBarTexture()
        if not self.statusBarTextureRegion then
            self.statusBarTextureRegion = newRegion("Texture", self)
        end
        return self.statusBarTextureRegion
    end
    function region:SetReverseFill(value) self.reverseFill = value end
    function region:SetTexture(texture) self.texture = texture end
    function region:GetTexture() return self.texture end
    function region:SetColorTexture(r, g, b, a) self.colorTexture = {r, g, b, a} end
    function region:SetVertexColor(r, g, b, a) self.vertexColor = {r, g, b, a} end
    function region:SetTexCoord(...) self.texCoord = {...} end
    function region:SetSnapToPixelGrid(value) self.snapToPixelGrid = value end
    function region:SetTexelSnappingBias(value) self.texelSnappingBias = value end

    return region
end

local now = 100
local inCombat = false -- ShowGCDCast requires combat; keeping this false means
                        -- the UNIT_SPELLCAST_SUCCEEDED handler's GCD-display
                        -- retry path bails immediately after the probe under
                        -- test runs -- exactly what isolates the probe itself.

function GetTime() return now end
function CreateFrame(frameType, name, parent)
    local frame = newRegion(frameType, parent)
    frame.name = name
    return frame
end
function InCombatLockdown() return inCombat end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function UnitClass() return "Player", "MAGE" end
function UnitGUID() return "Player-0000-00000001" end

UIParent = newRegion("Frame")
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
C_Timer = { After = function(_, callback) callback() end }
EventRegistry = { RegisterCallback = noop }

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIssecretvalue = SecretSentinel.InstallSecretStub()

local ns = { Helpers = {}, Addon = {} }
local pixelScale = 1
-- Load-order note (secret_sentinel.lua): castbar.lua captures
-- `local IsSecretValue = nsHelpers.IsSecretValue` at module load, so this
-- must be wired to the real issecretvalue() BEFORE loadfile below (unlike
-- the other castbar tests in this directory, which stub it to always-false
-- because they don't exercise the secret path).
ns.Helpers.IsSecretValue = function(value) return issecretvalue and issecretvalue(value) or false end
ns.Helpers.SafeValue = function(value) return value end
ns.Helpers.EnsureDefaults = function(tbl, defaults)
    for key, value in pairs(defaults) do
        if tbl[key] == nil then tbl[key] = value end
    end
end
ns.Helpers.GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end
ns.Helpers.GetGeneralFontOutline = function() return "" end
ns.Helpers.GetCore = function() return ns.Addon end
ns.Helpers.Clamp = function(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
ns.Helpers.CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end
ns.Helpers.CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } }

function ns.Addon:PixelRound(value) return math.floor((value / pixelScale) + 0.5) * pixelScale end
function ns.Addon:Pixels(value) return value * pixelScale end
function ns.Addon:GetPixelSize() return pixelScale end
function ns.Addon:SetPixelPerfectSize(frame, width, height) frame:SetSize(math.floor(width + 0.5) * pixelScale, math.floor(height + 0.5) * pixelScale) end
function ns.Addon:SetPixelPerfectHeight(frame, height) frame:SetHeight(math.floor(height + 0.5) * pixelScale) end
function ns.Addon:SetPixelPerfectPoint(frame, point, relativeTo, relativePoint, x, y) frame:SetPoint(point, relativeTo, relativePoint, x, y) end
function ns.Addon:ApplyPixelSnapping() end
function ns.Addon:ApplyFont(fontString, _, size, path, outline) fontString:SetFont(path, size, outline) end

assert(loadfile("core/uikit.lua"))("QUI", ns)
-- Instrumented load (Task 7): truthiness/==/# on sentinels now THROW
-- inside the module, matching in-game 12.1 secret semantics.
assert(SecretSentinel.LoadInstrumented("QUI_UnitFrames/unitframes/castbar.lua"))("QUI", ns)

local settings = {
    player = {
        castbar = {
            enabled = true,
            showIcon = true,
            iconSize = 22,
            iconScale = 1,
            iconSpacing = 0,
            iconAnchor = "LEFT",
            iconBorderSize = 1,
            iconBorderColor = {0, 0, 0, 1},
            width = 220,
            height = 18,
            borderSize = 1,
            borderColor = {0, 0, 0, 1},
            color = {1, 0.7, 0, 1},
            bgColor = {0.149, 0.149, 0.149, 1},
            texture = "Flat",
            showSpellText = true,
            showTimeText = true,
        },
    },
}

ns.QUI_Castbar:SetHelpers({
    GetUnitSettings = function(unit) return settings[unit] end,
    GetGeneralSettings = function() return {} end,
    GetDB = function() return { general = {} } end,
    GetTexturePath = function() return "Interface\\Buttons\\WHITE8x8" end,
    GetUnitClassColor = function() return 1, 1, 1, 1 end,
    TruncateName = function(name) return name end,
})

local unitFrame = newRegion("Frame", UIParent)
unitFrame:SetSize(220, 40)

local castbar = assert(ns.QUI_Castbar:CreateCastbar(unitFrame, "player", "player"))
local onEvent = assert(castbar.scripts and castbar.scripts.OnEvent,
    "player castbar should wire an OnEvent handler")

----------------------------------------------------------------------------
-- Registration proof: UNIT_SPELLCAST_SUCCEEDED must be RegisterUnitEvent'd
-- to the per-frame unit (registered-token discipline: the C-side filter,
-- not a payload compare, is what scopes this handler to "player").
----------------------------------------------------------------------------
assert(castbar.unitEvents and castbar.unitEvents.UNIT_SPELLCAST_SUCCEEDED
    and castbar.unitEvents.UNIT_SPELLCAST_SUCCEEDED[1] == "player",
    "UNIT_SPELLCAST_SUCCEEDED must be RegisterUnitEvent'd to player")

----------------------------------------------------------------------------
-- Case 1: dispatch arg-plumbing pin. Real payload order is
-- (unitTarget, castGUID, spellID, castBarID); OnEvent's wrapper signature is
-- (self, event, eventUnit, castGUID, spellID). Firing with three
-- DISTINCT, type-distinguishable values in the eventUnit/castGUID/spellID
-- slots proves which one lands in self._lastGCDSpellID: if the wrapper ever
-- regressed to forwarding eventUnit or castGUID instead of spellID, this
-- would either store a non-number (SafeToNumber rejects the string tokens,
-- _lastGCDSpellID stays nil) or the wrong number, not 4321.
----------------------------------------------------------------------------
onEvent(castbar, "UNIT_SPELLCAST_SUCCEEDED", "not-the-spell-id-unit-token", "not-the-spell-id-castguid", 4321)
assert(castbar._lastGCDSpellID == 4321,
    "eventHandlers.UNIT_SPELLCAST_SUCCEEDED's spellID parameter must receive the real " ..
    "spellID payload field (got " .. tostring(castbar._lastGCDSpellID) .. ") -- dispatch wrapper " ..
    "forwards handler(self, spellID) from (self, event, eventUnit, castGUID, spellID)")

----------------------------------------------------------------------------
-- Case 2: a secret spellID must not corrupt the GCD-cache field. Baseline
-- from Case 1 (4321) must survive a secret-payload event untouched -- the
-- pre-existing SafeToNumber(spellID) probe (which checks IsSecretValue()
-- before trusting type(v)=="number") must resolve to nil for a secret, so
-- the `if resolvedSpellID then self._lastGCDSpellID = resolvedSpellID end`
-- guard never fires.
----------------------------------------------------------------------------
local secretSpellID = SecretSentinel.MakeSecretSentinel()
local ok, err = pcall(onEvent, castbar, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-2", secretSpellID)
assert(ok, "OnEvent must not throw on a secret spellID: " .. tostring(err))
assert(castbar._lastGCDSpellID == 4321,
    "a secret spellID must not overwrite the cached GCD spellID (got " ..
    tostring(castbar._lastGCDSpellID) .. ")")

----------------------------------------------------------------------------
-- Case 3: registered-token discipline. The dispatch wrapper never forwards
-- eventUnit to eventHandlers.UNIT_SPELLCAST_SUCCEEDED at all -- only
-- (self, spellID). Making the payload unit a maximally hostile throwing
-- sentinel and confirming (a) no throw and (b) a normal numeric spellID
-- still updates the cache proves the handler genuinely never reads it.
----------------------------------------------------------------------------
local secretUnit = SecretSentinel.MakeSecretSentinel()
ok, err = pcall(onEvent, castbar, "UNIT_SPELLCAST_SUCCEEDED", secretUnit, "guid-3", 777)
assert(ok, "OnEvent must not throw on a secret/hostile payload unit token: " .. tostring(err))
assert(castbar._lastGCDSpellID == 777,
    "a normal spellID must still be recorded even when the payload unit is a throwing sentinel " ..
    "(the handler never reads the payload unit -- self.unit is used elsewhere via closure)")

_G.issecretvalue = restoreIssecretvalue

----------------------------------------------------------------------------
-- Part B: boss castbar's UNIT_SPELLCAST_SUCCEEDED branch (~:3282/:3289).
-- CreateBossCastbar has no test harness in this repo (heavy anchor/preview
-- setup unrelated to this event) and, unlike the player castbar, its
-- OnEvent wrapper signature is `function(self, event, eventUnit)` -- it
-- never captures castGUID or spellID at all, and the UNIT_SPELLCAST_SUCCEEDED
-- branch calls `self:Cast()` with zero arguments (Cast() re-derives cast
-- state from UnitCastingInfo/UnitChannelInfo, not the event payload). There
-- is structurally nothing to probe. Pin the source shape textually (same
-- style as this file's existing castbar_getunitsettings_per_frame_test.lua)
-- so a future edit that starts reading the payload here doesn't silently
-- skip the boundary discipline.
----------------------------------------------------------------------------
local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local source = readAll("QUI_UnitFrames/unitframes/castbar.lua")

local wrapperStart = assert(source:find(
    'anchorFrame:SetScript("OnEvent", function(self, event, eventUnit)', 1, true),
    "boss castbar OnEvent wrapper signature must stay (self, event, eventUnit) -- " ..
    "if it starts capturing castGUID/spellID, this event's payload boundary needs a real probe")
local wrapperEnd = assert(source:find("end)", wrapperStart, true),
    "expected to find the end of the boss OnEvent handler")
local wrapperBody = source:sub(wrapperStart, wrapperEnd)

assert(wrapperBody:find('event == "UNIT_SPELLCAST_SUCCEEDED"', 1, true),
    "expected the boss OnEvent handler to branch on UNIT_SPELLCAST_SUCCEEDED")
assert(not wrapperBody:find("castGUID", 1, true) and not wrapperBody:find("spellID", 1, true),
    "boss OnEvent handler must not reference castGUID/spellID -- it currently re-derives cast " ..
    "state via self:Cast() (zero args) instead of trusting the event payload; if this changes, " ..
    "add a real IsSecretValue probe before any table index/==")

print("OK: castbar_spellcast_secret_boundary_test")
