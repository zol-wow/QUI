--[[
    QUI Nameplates — shared state and settings access.

    Loads first in the suite. Owns the module table (ns.QUI_Nameplates), the
    unit → plate registry, the appearance generation counter, and the
    settings getter. Satellites nil-guard on ns.QUI_Nameplates.

    THE SECRET-VALUE RULEBOOK (all suite files; strict taint tier enforces it)
    ------------------------------------------------------------------------
    Sinks that accept secrets: SetValue/SetMinMaxValues, SetText/
    SetFormattedText (C-side; %.0f/%.1f/%s ONLY, never %d — integer coercion
    on a secret silently no-ops the whole call), SetTexture, SetAlpha,
    SetAlphaFromBoolean, SetCooldownFromDurationObject, SetTimerDuration,
    SetCountdownFormatter, curve evaluation, C_StringUtil.*, AbbreviateNumbers.

    House idioms:
    * Health/absorb VALUES flow raw into StatusBars; zero-checks only behind
      Helpers.IsSecretValue gates + SafeToNumber.
    * Health PERCENT is never computed: UnitHealthPercent(unit, usePredicted,
      CurveConstants.ScaleTo100) under pcall (returns secret at full HP —
      never nil-compare), formatted with SetFormattedText("%.0f%%", ...).
    * Dirty-checks: `if IsSecretValue(v) or v ~= cache then ... if not
      IsSecretValue(v) then cache = v end` — secret ⇒ always write, never cache.
    * Existence checks on possibly-secret returns: type(x) == "nil" (type()
      is safe); NEVER truthiness, equality, or #.
    * Names: Helpers.TruncateUTF8 (secret-safe) straight into SetText;
      keep-last-good on transient !UnitExists.
    * Secret booleans route into SetAlphaFromBoolean /
      EvaluateColorValueFromBoolean chains; a user toggle (clean boolean)
      gates whether the secret is consumed at all.
    * End-of-cast/teardown decisions use UnitExists (plain false), never
      UnitCastingInfo truthiness ("stale secret channel info" hazard).

    Verified 12.0 environmental facts (each earned a scar in the references):
    * There is ONE C_NamePlate.SetNamePlateSize(w, h) — per-reaction variants
      are gone. It grows from CENTER (no Y-compensation).
    * SetStackingBoundsFrame reads RENDERED region bounds — the bounds frame
      needs an alpha-0 full-size texture or it contributes nothing.
    * SetFillStyle re-enables pixel snapping — re-disable after, or fill-edge
      ticks dance.
    * Blizzard UnitFrame suppression must be UNCONDITIONAL — first-frame
      UnitCanAttack lies.
    * C_NamePlateManager.SetNamePlateHitTestInsets is SecretArguments =
      NotAllowed — plain numbers only.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local NP = {}
ns.QUI_Nameplates = NP

NP.plates = {}

NP.platesByBase = setmetatable({}, { __mode = "k" })

NP.appearanceGen = 1

function NP.BumpAppearanceGeneration()
    NP.appearanceGen = NP.appearanceGen + 1
end

NP.SIMPLIFIED_AVAILABLE = (C_NamePlateManager ~= nil
    and C_NamePlateManager.SetNamePlateSimplified ~= nil)

NP.SIMPLIFIED_SCALE_MIN = 0.5
NP.SIMPLIFIED_SCALE_MAX = 2.0

NP.PLATE_SCALE_MIN = 0.5
NP.PLATE_SCALE_MAX = 2.0

function NP.IsLightweightMode(mode)
    return mode == "nameonly" or mode == "simplified"
end

local RENDER_MODES = { bars = true, simplified = true, nameonly = true }

function NP.ResolveRenderMode(typeSettings)
    local mode = type(typeSettings) == "table" and typeSettings.renderMode or nil
    if RENDER_MODES[mode] then return mode end
    return "bars"
end

local IsSecretValue = Helpers.IsSecretValue
function NP.Plain(value, expectedType)
    if value == nil or IsSecretValue(value) then return nil end
    if type(value) == expectedType then return value end
    return nil
end

local DEFAULTS = {
    enabled = false,
}

function NP.GetSettings()
    return Helpers.GetModuleSettings("nameplates", DEFAULTS)
end

function NP.IsEnabled()
    local s = NP.GetSettings()
    return s and s.enabled == true
end

function NP.SimplifiedScale(settings)
    if type(settings) ~= "table" then settings = NP.GetSettings() end
    local simplified = type(settings) == "table" and settings.simplified or nil
    local scale = type(simplified) == "table" and tonumber(simplified.scale) or nil
    if not scale then return 1.0 end
    if scale < NP.SIMPLIFIED_SCALE_MIN then return NP.SIMPLIFIED_SCALE_MIN end
    if scale > NP.SIMPLIFIED_SCALE_MAX then return NP.SIMPLIFIED_SCALE_MAX end
    return scale
end

function NP.PlateScale(settings)
    if type(settings) ~= "table" then settings = NP.GetSettings() end
    local layout = type(settings) == "table" and settings.layout or nil
    local scale = type(layout) == "table" and tonumber(layout.scale) or nil
    if not scale then return 1.0 end
    if scale < NP.PLATE_SCALE_MIN then return NP.PLATE_SCALE_MIN end
    if scale > NP.PLATE_SCALE_MAX then return NP.PLATE_SCALE_MAX end
    return scale
end

local VALID_OUTLINES = { OUTLINE = true, THICKOUTLINE = true, [""] = true }

function NP.ResolveFont(plate)
    local s = NP.GetTypeSettings(plate)
    local f = (s and s.font) or {}
    local path
    if f.face and f.face ~= "" and ns.LSM then
        local ok, fetched = pcall(ns.LSM.Fetch, ns.LSM, "font", f.face, true)
        if ok and fetched then path = fetched end
    end
    if not path then path = ns.UIKit.ResolveFontPath() end
    local outline = f.outline
    if not VALID_OUTLINES[outline] then outline = "OUTLINE" end
    return path, outline
end

function NP.GetBarTexture(name)
    local LSM = ns.LSM
    if LSM and name then
        local ok, path = pcall(LSM.Fetch, LSM, "statusbar", name, true)
        if ok and path then return path end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

function NP:GetPlateAnchor(unit)
    if not unit then return nil end
    local plate = NP.plates[unit]
    if plate and plate.healthBar and plate:IsShown() then
        return plate.healthBar
    end
    return nil
end

local PER_TYPE_KEYS = {
    "health", "healthText", "name", "npcTitle", "power", "level",
    "questIcon", "pvpIcon", "font", "castbar", "absorbs",
    "healPrediction", "powerBar", "colors", "highlight",
    "raidMarker", "auras",
}
NP.PER_TYPE_KEYS = PER_TYPE_KEYS

local function CopyDeep(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDeep(v)
        else
            dst[k] = v
        end
    end
    return dst
end
NP.CopyDeep = CopyDeep

local function IsArrayLike(t)
    return type(t) == "table" and rawget(t, 1) ~= nil
end
NP.IsArrayLike = IsArrayLike

local function MergeLegacyPatch(dst, patch)
    for k, v in pairs(patch) do
        if type(v) == "table" and not IsArrayLike(v) then
            local sub = rawget(dst, k)
            if type(sub) ~= "table" then
                sub = {}
                rawset(dst, k, sub)
            end
            MergeLegacyPatch(sub, v)
        else
            rawset(dst, k, CopyDeep(v))
        end
    end
end

local function EnsureTypeTable(types, typeKey)
    local dst = rawget(types, typeKey)
    if type(dst) ~= "table" then
        dst = {}
        rawset(types, typeKey, dst)
    end
    return dst
end

local INSTANCE_MODES = { never = true, nameonly = true, always = true }
NP.FRIENDLY_INSTANCE_MODES = INSTANCE_MODES

local function FoldLegacyInstanceMode(settings)
    local friendly = rawget(settings, "friendly")
    if type(friendly) ~= "table" then return end

    local stored = rawget(friendly, "showInInstances")
    if stored == true then
        rawset(friendly, "showInInstances", "always")
    elseif stored == false then
        rawset(friendly, "showInInstances", "never")
    elseif not INSTANCE_MODES[stored] then
        rawset(friendly, "showInInstances", "never")
    end
end

local function FoldLegacyRenderMode(settings)
    local types = rawget(settings, "types")
    if type(types) ~= "table" then return end

    local friendly = rawget(settings, "friendly")
    if type(friendly) == "table" then
        local legacyMode = rawget(friendly, "mode")
        if legacyMode == "nameonly" or legacyMode == "bars" then
            rawset(EnsureTypeTable(types, "friendly"), "renderMode", legacyMode)
            rawset(friendly, "mode", "show")
        end
    end

    for _, typeKey in ipairs(NP.PlateType.ORDER) do
        local dst = rawget(types, typeKey)
        if type(dst) == "table" then
            local legacyFlag = rawget(dst, "useSimplified")
            if legacyFlag ~= nil then
                if legacyFlag == true then rawset(dst, "renderMode", "simplified") end
                rawset(dst, "useSimplified", nil)
            end
            if not RENDER_MODES[rawget(dst, "renderMode")] then
                rawset(dst, "renderMode", "bars")
            end
        end
    end
end

local function FoldLegacyFriendlyEnabled(settings)
    local friendly = rawget(settings, "friendly")
    if type(friendly) ~= "table" then return end

    local legacyMode = rawget(friendly, "mode")
    if legacyMode ~= nil then
        rawset(friendly, "enabled", legacyMode ~= "off")
        rawset(friendly, "mode", nil)
    end
    if rawget(friendly, "enabled") == nil then
        rawset(friendly, "enabled", true)
    end
end

function NP.NormalizeTypes(settings)
    if type(settings) ~= "table" then return settings end

    local legacy = {}
    local hasLegacy = false
    for _, key in ipairs(PER_TYPE_KEYS) do
        local v = rawget(settings, key)
        if v ~= nil then
            legacy[key] = v
            hasLegacy = true
        end
    end

    if hasLegacy then
        local types = rawget(settings, "types")
        if type(types) ~= "table" then
            types = {}
            rawset(settings, "types", types)
        end

        for _, typeKey in ipairs(NP.PlateType.ORDER) do
            MergeLegacyPatch(EnsureTypeTable(types, typeKey), legacy)
        end

        for _, key in ipairs(PER_TYPE_KEYS) do
            rawset(settings, key, nil)
        end
    end

    FoldLegacyRenderMode(settings)
    FoldLegacyFriendlyEnabled(settings)
    FoldLegacyInstanceMode(settings)

    return settings
end

local normalizedSettings = setmetatable({}, { __mode = "k" })

function NP.GetTypeSettings(plate)
    local settings = NP.GetSettings()
    if type(settings) ~= "table" then return nil end
    if not normalizedSettings[settings] then
        NP.NormalizeTypes(settings)
        normalizedSettings[settings] = true
    end
    local types = settings.types
    if type(types) ~= "table" then return nil end
    local key = plate and plate.npType
    if type(key) == "string" and types[key] then
        return types[key]
    end
    return types[NP.PlateType.DEFAULT_KEY]
end
