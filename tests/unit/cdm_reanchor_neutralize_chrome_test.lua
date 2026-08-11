-- tests/unit/cdm_reanchor_neutralize_chrome_test.lua
-- Run: lua tests/unit/cdm_reanchor_neutralize_chrome_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame C_Timer
-- Contract for CDMIcons.NeutralizeBlizzardItemChrome: the re-anchor decorate dep
-- that makes a native Blizzard CooldownViewer item frame read like a QUI owned
-- icon -- alpha-0 the IconOverlay bevel (anonymous OVERLAY atlas texture), drop
-- the rounding mask, and crop the icon to the QUI zoom. The OOR shadow is kept
-- (native out-of-range feedback retained; G5 fix). Never hides/reparents the
-- frame or the icon texture itself.

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(tbl) for k in pairs(tbl) do tbl[k] = nil end end
function CreateFrame()
    return { RegisterEvent = noop, RegisterUnitEvent = noop, UnregisterAllEvents = noop, SetScript = noop }
end
C_Timer = { After = function(_, cb) cb() end, NewTimer = function() return { Cancel = noop } end }

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function() return function() return {} end end,
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
        SafeToNumber = function(v) return v end,
        CanAccessTable = function(t) return type(t) == "table" end,
    },
    Addon = { db = { profile = { ncdm = {} }, char = { ncdm = {} } } },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        IsSafeNumeric = function(v) return type(v) == "number" end,
    },
    CDMSources = {
        QuerySpellUsable = function() return true, false end,
        QuerySpellCharges = function() return nil end,
        QuerySpellCooldown = function() return nil end,
        QuerySpellCooldownDuration = function() return nil end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = function() return {} end,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        GetSpellTexture = function() return nil end,
        GetEntryTexture = function() return nil end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return false end,
        ResolveCooldownState = function() return nil end,
    },
    CDMIconFactory = { _FinalizeImports = noop, AcquireIcon = noop, ReleaseIcon = noop },
    CDMRuntimeStore = { SetIconState = noop },
    _OwnedGlows = { ClearPandemicState = noop },
}

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local Neutralize = assert(ns.CDMIcons and ns.CDMIcons.NeutralizeBlizzardItemChrome,
    "CDMIcons.NeutralizeBlizzardItemChrome should be exported")
assert(type(ns.CDMIcons.UpdateSecureClickOverlay) == "function",
    "CDMIcons.UpdateSecureClickOverlay should be exported for reanchored shells")

-- A mock Texture region tracking alpha / texcoord / mask membership.
local function MakeTexture(atlas)
    local t = { _atlas = atlas, alpha = 1, texcoord = nil, masks = {} }
    function t:GetObjectType() return "Texture" end
    function t:GetAtlas() return self._atlas end
    function t:SetAlpha(a) self.alpha = a end
    function t:SetTexCoord(l, r, tp, b) self.texcoord = { l, r, tp, b } end
    function t:GetNumMaskTextures() return #self.masks end
    function t:GetMaskTexture(i) return self.masks[i] end
    function t:RemoveMaskTexture(m)
        for i = #self.masks, 1, -1 do if self.masks[i] == m then table.remove(self.masks, i) end end
    end
    return t
end

-- ===== Case 1: flat item (essential/utility/buffIcon): frame.Icon is the texture
do
    local iconTex = MakeTexture(nil)          -- the spell icon (no atlas)
    iconTex.masks = { {}, {} }                -- rounding mask(s) applied
    local overlay = MakeTexture("UI-HUD-CoolDownManager-IconOverlay")  -- bevel
    local oor = MakeTexture("UI-CooldownManager-OORshadow")            -- range shadow
    local frame = { Icon = iconTex }
    function frame:GetRegions() return iconTex, overlay, oor end

    Neutralize(frame, { zoom = 0, aspectRatioCrop = 1.0 })

    assert(overlay.alpha == 0, "IconOverlay bevel alpha-0'd")
    assert(oor.alpha == 1, "OOR shadow kept -- native range feedback retained (G5)")
    assert(iconTex.alpha == 1, "the icon texture itself is NEVER hidden")
    assert(#iconTex.masks == 0, "rounding mask(s) removed -> square icon")
    assert(iconTex.texcoord and iconTex.texcoord[1] == 0.08,
        "icon cropped to QUI base crop (0.08) at zoom 0")
    assert(iconTex.texcoord[2] == 1 - 0.08, "right crop symmetric")
end

-- ===== Case 2: zoom applied on top of base crop
do
    local iconTex = MakeTexture(nil)
    local frame = { Icon = iconTex }
    function frame:GetRegions() return iconTex end
    Neutralize(frame, { zoom = 0.1 })
    assert(math.abs(iconTex.texcoord[1] - 0.18) < 1e-9, "zoom 0.1 -> left crop 0.18")
end

-- ===== Case 3: nested item (BuffBar): frame.Icon is a Frame whose .Icon is the texture
do
    local nestedTex = MakeTexture(nil)
    nestedTex.masks = { {} }
    local overlay = MakeTexture("UI-HUD-CoolDownManager-IconOverlay")
    local iconFrame = { Icon = nestedTex }
    function iconFrame:GetObjectType() return "Frame" end
    function iconFrame:GetRegions() return nestedTex, overlay end
    local barFrame = { Icon = iconFrame }

    Neutralize(barFrame, { zoom = 0 })

    assert(overlay.alpha == 0, "nested IconOverlay alpha-0'd via the icon-host frame")
    assert(#nestedTex.masks == 0, "nested rounding mask removed")
    assert(nestedTex.texcoord ~= nil, "nested icon texture cropped")
end

-- ===== Case 4: nil-safety -- no frame, no Icon, no rowConfig
do
    Neutralize(nil)
    Neutralize({})                                   -- no .Icon
    local lone = MakeTexture(nil)
    Neutralize({ Icon = lone })                      -- nil rowConfig -> default crop
    assert(lone.texcoord and lone.texcoord[1] == 0.08, "nil rowConfig falls back to base crop")
end

print("OK: cdm_reanchor_neutralize_chrome_test")
