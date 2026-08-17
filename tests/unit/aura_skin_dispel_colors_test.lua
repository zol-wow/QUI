-- tests/unit/aura_skin_dispel_colors_test.lua
-- Task 10 + PTR7 follow-up: dispel border custom colors/assets are
-- profile-driven and applied in styleButton (Clear + AddDispelTypeTexture per
-- style pass), NOT frozen at button birth — so Configure births carry them
-- AND Restyle updates/resets live buttons. dispelColors -> customDispelColorMap
-- (68824); dispelAssets -> customDispelAssetMap under the CustomAsset style.
-- Run: lua tests/unit/aura_skin_dispel_colors_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Part A: brief's source-text floor (verbatim from task-10-brief.md).
----------------------------------------------------------------------------
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local skin = readAll("core/aura_skin.lua")
assert(skin:find("customDispelColorMap", 1, true),
    "buildButtonArt must pass customDispelColorMap when profile provides dispelColors")
local glue = readAll("core/aura_glue.lua")
assert(glue:find("dispelColors", 1, true),
    "ElementProfile whitelist must map dispelColors (passthrough pin)")
print("OK aura_skin_dispel_colors_test (source-text floor)")

----------------------------------------------------------------------------
-- Part B: behavioral harness (mirrors tests/unit/
-- aura_skin_button_enumeration_test.lua's stub pattern). Drives
-- MakeInitializer's initializer through the REAL call site
-- (AuraSkin.Configure -> AddAuraGroup -> initializeFrame -> buildButtonArt)
-- against a stub button + container, proving customDispelColorMap actually
-- reaches AddDispelTypeTexture's options table -- present when the profile carries
-- a dispelColors table, absent (not merely falsy) when it doesn't -- not
-- just that the source text mentions the field somewhere.
----------------------------------------------------------------------------
_G.InCombatLockdown = function() return false end
_G.AuraContainerSortMethod = { Default = 1 }
_G.AuraContainerSortDirection = { Normal = 1 }
_G.AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 }, FlowLayoutAxis = { Horizontal = 0, Vertical = 1 } }
_G.Enum = _G.Enum or {}
_G.Enum.CustomAuraButtonDispelTypeTextureStyle = { PreserveAsset = 3, CustomAsset = 4 }
_G.Enum.CustomAuraButtonDispelTypeStealableFilter = { Stealable = 0, NotStealable = 1 }

local function Stub()
    local t = {}
    function t:SetAllPoints() end
    function t:SetPoint() end
    function t:SetSize() end
    function t:ClearAllPoints() end
    function t:SetColorTexture() end
    function t:SetTexCoord(...) self.texCoords = { ... } end
    function t:DisablePixelSnap() end
    function t:SetTextColor() end
    function t:SetAlpha() end
    function t:SetFont() end
    function t:SetHideCountdownNumbers() end
    function t:SetDrawSwipe() end
    function t:SetReverse() end
    function t:SetText() end
    function t:SetStatusBarTexture() end
    function t:SetOrientation() end
    function t:SetStatusBarColor() end
    function t:Show() end
    function t:Hide() end
    function t:CreateTexture() return Stub() end
    function t:CreateFontString() return Stub() end
    return t
end
_G.CreateFrame = function() return Stub() end

-- Extends the established MakeButton pattern (aura_skin_button_enumeration_
-- test.lua) with a RECORDING AddDispelTypeTexture -- that suite's stub discards
-- its options argument; this test needs to inspect it.
local function MakeButton(name)
    local b = Stub()
    b._name = name
    b._auraBorderOpts = nil
    function b:SetCancelAuraButtons() end
    function b:SetSize() end
    function b:SetIcon() end
    function b:AddDispelTypeTexture(dispelTexture, opts)
        b._addDispelCalls = (b._addDispelCalls or 0) + 1
        b._auraBorderOpts = b._auraBorderOpts or opts
        b._dispelRegs = b._dispelRegs or {}
        b._dispelRegs[#b._dispelRegs + 1] = { texture = dispelTexture, opts = opts }
    end
    function b:ClearDispelTypeTextures()
        b._clearCalls = (b._clearCalls or 0) + 1
        b._auraBorderOpts = nil
        b._dispelRegs = {}
    end
    function b:SetDispelTypeText() end
    -- Engine-faithful tooltip anchor stub: template KeyValues pre-seed
    -- ANCHOR_BOTTOMLEFT,0,0 (Blizzard_AuraButton.xml:11-13) and the setter
    -- hard-asserts on non-token values (Blizzard_AuraButton.lua:53).
    b._tipAnchor = { "ANCHOR_BOTTOMLEFT", 0, 0 }
    local VALID_TIP_ANCHORS = {
        ANCHOR_LEFT = true, ANCHOR_RIGHT = true, ANCHOR_BOTTOMLEFT = true,
        ANCHOR_BOTTOM = true, ANCHOR_BOTTOMRIGHT = true, ANCHOR_TOPLEFT = true,
        ANCHOR_TOP = true, ANCHOR_TOPRIGHT = true, ANCHOR_CURSOR = true,
        ANCHOR_NONE = true, ANCHOR_PRESERVE = true,
        ANCHOR_CURSOR_LEFT = true, ANCHOR_CURSOR_RIGHT = true,
    }
    function b:GetTooltipAnchorPoint()
        return self._tipAnchor[1], self._tipAnchor[2], self._tipAnchor[3]
    end
    function b:SetTooltipAnchorPoint(point, x, y)
        assert(VALID_TIP_ANCHORS[point], "point must be a valid tooltip anchor point name")
        self._tipAnchor = { point, x or 0, y or 0 }
    end
    function b:SetHideTooltipInCombat() end
    function b:SetDurationCooldown() end
    function b:SetDurationText() end
    function b:SetApplicationCount() end
    return b
end

-- Minimal fake container: one group, births a single button synchronously
-- through the real MakeInitializer closure (same shape as
-- MakeIncapableContainer in the enumeration test) and stashes it for
-- inspection.
local function MakeContainer()
    local c = { _addCalls = {}, _registeredKeys = {} }
    function c:HasAuraGroup(key) return self._registeredKeys[key] == true end
    function c:AddAuraGroup(key, filter, opts)
        c._addCalls[#c._addCalls + 1] = { key = key, filter = filter }
        c._registeredKeys[key] = true
        c._birthedButton = MakeButton(key .. "#1")
        opts.initializeFrame(c._birthedButton)
    end
    function c:SetAuraGroupMaxFrameCount() end
    function c:SetAuraGroupSortMethod() end
    function c:SetAuraGroupCandidateFilters() end
    function c:SetAuraGroupLayout() end
    function c:SetFlowLayoutAnchorPoint() end
    function c:SetFlowLayoutGrowthDirection() end
    function c:SetFlowLayoutPadding() end
    function c:SetFlowLayoutAxis() end
    function c:SetFlowLayoutMaximumLineSize() end
    return c
end

local ns = {}
assert(loadfile("core/safecall.lua"))("QUI", ns)
assert(loadfile("core/aura_theme.lua"))("QUI", ns)
assert(loadfile("core/aura_skin.lua"))("QUI", ns)
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
local AuraSkin = ns.Addon.AuraSkin
check("core/aura_skin.lua publishes ns.Addon.AuraSkin", AuraSkin ~= nil)

local plainPreview = Stub()
AuraSkin.WirePreviewButton(plainPreview, {
    iconSize = 20,
    showDispelBorder = false,
})
check("plain preview adapter builds shared art without secure inbound setters",
    plainPreview._quiWired == true
        and plainPreview.Icon ~= nil
        and plainPreview._quiDuration ~= nil
        and plainPreview._quiCount ~= nil)

----------------------------------------------------------------------------
-- (1) Profile carries dispelColors: the birthed button's AddDispelTypeTexture
-- options must carry customDispelColorMap == the SAME table (buildButtonArt
-- passes the profile's table straight through -- AddDispelTypeTexture itself
-- securecopies it, not QUI -- so identity, not a deep copy, is expected
-- here).
----------------------------------------------------------------------------
local withColors = MakeContainer()
local dispelMap = { SILENCE = { r = 1, g = 0, b = 0 } }
local profileWithColors = { iconSize = 20, dispelColors = dispelMap }
AuraSkin.Configure(withColors, profileWithColors,
    { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })

local btn1 = withColors._birthedButton
check("button born", btn1 ~= nil)
if btn1 then
    check("AddDispelTypeTexture options carry customDispelColorMap when profile has dispelColors",
        btn1._auraBorderOpts ~= nil and btn1._auraBorderOpts.customDispelColorMap == dispelMap,
        btn1._auraBorderOpts and tostring(btn1._auraBorderOpts.customDispelColorMap))
    check("customDispelColorMap does not clobber the style/showWhen fields",
        btn1._auraBorderOpts.style == 3 and btn1._auraBorderOpts.showWhenHarmful == true
            and btn1._auraBorderOpts.showWhenHelpful == false)
end

----------------------------------------------------------------------------
-- (2) Profile carries NO dispelColors: the key must be entirely ABSENT
-- (nil), not merely falsy -- guards against a stray unconditional
-- `customDispelColorMap = nil` field write, which is indistinguishable from
-- "not present" only at the value level, not the intent level.
----------------------------------------------------------------------------
local noColors = MakeContainer()
local profileNoColors = { iconSize = 20 }
AuraSkin.Configure(noColors, profileNoColors,
    { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })

local btn2 = noColors._birthedButton
check("second button born", btn2 ~= nil)
if btn2 then
    check("AddDispelTypeTexture options omit customDispelColorMap when profile has no dispelColors",
        btn2._auraBorderOpts ~= nil and btn2._auraBorderOpts.customDispelColorMap == nil,
        btn2._auraBorderOpts and tostring(btn2._auraBorderOpts.customDispelColorMap))
end

----------------------------------------------------------------------------
-- (3) Non-table dispelColors (defensive: a stray non-table value on the
-- profile field) must NOT be passed through -- proves buildButtonArt's own
-- type(prof.dispelColors) == "table" guard, not just presence-checking.
----------------------------------------------------------------------------
local badColors = MakeContainer()
local profileBadColors = { iconSize = 20, dispelColors = "not-a-table" }
AuraSkin.Configure(badColors, profileBadColors,
    { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })

local btn3 = badColors._birthedButton
check("third button born", btn3 ~= nil)
if btn3 then
    check("non-table dispelColors is not passed through as customDispelColorMap",
        btn3._auraBorderOpts ~= nil and btn3._auraBorderOpts.customDispelColorMap == nil,
        btn3._auraBorderOpts and tostring(btn3._auraBorderOpts.customDispelColorMap))
end

----------------------------------------------------------------------------
-- (4) PTR7 dispelAssets: profile carries a dispelAssets table -> options must
-- carry customDispelAssetMap == the SAME table AND flip style to CustomAsset
-- (4), since the engine only consults the asset map under that style.
-- dispelColors composes (engine tints the asset after styling).
----------------------------------------------------------------------------
local withAssets = MakeContainer()
local assetMap = { Magic = { asset = "Interface\\Foo\\Bar" } }
local profileWithAssets = { iconSize = 20, dispelColors = dispelMap, dispelAssets = assetMap }
AuraSkin.Configure(withAssets, profileWithAssets,
    { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })

local btn4 = withAssets._birthedButton
check("fourth button born", btn4 ~= nil)
if btn4 then
    check("dispelAssets passes through as customDispelAssetMap (same table)",
        btn4._auraBorderOpts ~= nil and btn4._auraBorderOpts.customDispelAssetMap == assetMap,
        btn4._auraBorderOpts and tostring(btn4._auraBorderOpts.customDispelAssetMap))
    check("dispelAssets flips style to CustomAsset (4)",
        btn4._auraBorderOpts.style == 4)
    check("dispelColors still composes alongside dispelAssets",
        btn4._auraBorderOpts.customDispelColorMap == dispelMap)
end

----------------------------------------------------------------------------
-- (5) No dispelAssets: customDispelAssetMap absent and style stays
-- PreserveAsset (3) -- pins that the CustomAsset flip is asset-gated, and a
-- non-table value is rejected like dispelColors.
----------------------------------------------------------------------------
local badAssets = MakeContainer()
local profileBadAssets = { iconSize = 20, dispelAssets = "not-a-table" }
AuraSkin.Configure(badAssets, profileBadAssets,
    { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })

local btn5 = badAssets._birthedButton
check("fifth button born", btn5 ~= nil)
if btn5 then
    check("non-table dispelAssets is not passed through as customDispelAssetMap",
        btn5._auraBorderOpts ~= nil and btn5._auraBorderOpts.customDispelAssetMap == nil,
        btn5._auraBorderOpts and tostring(btn5._auraBorderOpts.customDispelAssetMap))
    check("style stays PreserveAsset (3) without a dispelAssets table",
        btn5._auraBorderOpts.style == 3)
end

----------------------------------------------------------------------------
-- (6) Group-frame Debuff Border by Type can suppress the engine registration
-- entirely, and a later settings refresh can restore it on the same button.
----------------------------------------------------------------------------
local borderDisabled = MakeContainer()
AuraSkin.Configure(borderDisabled, { iconSize = 20, showDispelBorder = false },
    { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
local btnDisabled = borderDisabled._birthedButton
check("showDispelBorder=false clears without registering a dispel texture",
    btnDisabled ~= nil
        and (btnDisabled._clearCalls or 0) >= 1
        and (btnDisabled._addDispelCalls or 0) == 0)
if btnDisabled then
    AuraSkin.Restyle(borderDisabled, { iconSize = 20, showDispelBorder = true })
    check("re-enabling the setting registers the dispel texture on the live button",
        (btnDisabled._addDispelCalls or 0) == 1 and btnDisabled._auraBorderOpts ~= nil)
end

local withCurve = MakeContainer()
local dispelCurve = {}
AuraSkin.Configure(withCurve, {
    iconSize = 20,
    showDispelBorder = true,
    dispelColorCurve = dispelCurve,
}, { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
local btnCurve = withCurve._birthedButton
check("group dispel palette curve reaches the engine texture options",
    btnCurve ~= nil
        and btnCurve._auraBorderOpts.customDispelColorCurve == dispelCurve)

----------------------------------------------------------------------------
-- (7) LIVE RESTYLE (stop-gate): dispel options apply in styleButton, not at
-- button birth, so Restyle on an existing container must re-register the
-- dispel texture with the NEW profile's options — including full reset when
-- an override is removed. Clear must precede every re-add (no texture
-- stacking on the engine side).
----------------------------------------------------------------------------
if btn1 then
    local clearsBefore = btn1._clearCalls or 0
    AuraSkin.Restyle(withColors, { iconSize = 20 })
    check("restyle without dispelColors RESETS the live button's map",
        btn1._auraBorderOpts ~= nil and btn1._auraBorderOpts.customDispelColorMap == nil,
        btn1._auraBorderOpts and tostring(btn1._auraBorderOpts.customDispelColorMap))
    check("restyle reset returns to PreserveAsset (3)",
        btn1._auraBorderOpts.style == 3)
    check("re-add is preceded by ClearDispelTypeTextures",
        (btn1._clearCalls or 0) > clearsBefore)

    local liveAssets = { Curse = { asset = "Interface\\Foo\\Baz" } }
    AuraSkin.Restyle(withColors, { iconSize = 20, dispelAssets = liveAssets, dispelColors = dispelMap })
    check("restyle applies dispelAssets to the LIVE button (CustomAsset flip)",
        btn1._auraBorderOpts.style == 4
            and btn1._auraBorderOpts.customDispelAssetMap == liveAssets)
    check("restyle re-applies dispelColors to the LIVE button",
        btn1._auraBorderOpts.customDispelColorMap == dispelMap)
end

----------------------------------------------------------------------------
-- (8) Tooltip anchor lifecycle (stop-gate): valid set -> clear must restore
-- the CACHED pre-override triple (template default), and an invalid imported
-- token must neither error, nor apply, nor mark the button customized (a
-- later clear pass must not disturb the engine state).
----------------------------------------------------------------------------
if btn1 then
    -- valid set (with offsets), then clear -> template default restored
    AuraSkin.Restyle(withColors,
        { iconSize = 20, tooltipAnchor = "ANCHOR_TOPRIGHT", tooltipAnchorX = 5, tooltipAnchorY = -2 })
    check("valid tooltip anchor applies to the live button",
        btn1._tipAnchor[1] == "ANCHOR_TOPRIGHT" and btn1._tipAnchor[2] == 5 and btn1._tipAnchor[3] == -2)
    AuraSkin.Restyle(withColors, { iconSize = 20 })
    check("clearing the override restores the cached template default",
        btn1._tipAnchor[1] == "ANCHOR_BOTTOMLEFT" and btn1._tipAnchor[2] == 0 and btn1._tipAnchor[3] == 0)

    -- second customize -> clear still restores the ORIGINAL default (the
    -- pre-override cache is captured once, not overwritten by later passes)
    AuraSkin.Restyle(withColors, { iconSize = 20, tooltipAnchor = "ANCHOR_CURSOR" })
    AuraSkin.Restyle(withColors, { iconSize = 20 })
    check("re-customize then clear restores the original default again",
        btn1._tipAnchor[1] == "ANCHOR_BOTTOMLEFT")
end

-- invalid imported token on a FRESH button: pcall swallows the assert, no
-- state applied, no customized flag -> a later clear pass leaves the engine
-- default untouched (never stamps a spurious reset)
local importCase = MakeContainer()
AuraSkin.Configure(importCase, { iconSize = 20, tooltipAnchor = "TOPRIGHT" },
    { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
local btn6 = importCase._birthedButton
check("sixth button born", btn6 ~= nil)
if btn6 then
    check("invalid imported token does not apply (engine default intact)",
        btn6._tipAnchor[1] == "ANCHOR_BOTTOMLEFT")
    AuraSkin.Restyle(importCase, { iconSize = 20 })
    check("clear after failed set leaves the engine default untouched",
        btn6._tipAnchor[1] == "ANCHOR_BOTTOMLEFT" and btn6._tipAnchor[2] == 0 and btn6._tipAnchor[3] == 0)
end

----------------------------------------------------------------------------
-- (9) Surface icon-skin ownership: built-in profiles reach IconSkin, while an
-- available external bridge owns the button until the setting is disabled.
----------------------------------------------------------------------------
local appliedSkin
ns.IconSkin = {
    GlossTexture = "gloss",
    ApplySkin = function(_, regions, skinName)
        appliedSkin = { regions = regions, skinName = skinName }
    end,
}
local builtinSkin = MakeContainer()
AuraSkin.Configure(builtinSkin, { iconSize = 20, iconSkin = "Gloss" },
    { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
check("built-in group icon skin reaches the shared IconSkin applier",
    appliedSkin ~= nil
        and appliedSkin.skinName == "Gloss"
        and appliedSkin.regions.Backdrop ~= nil
        and appliedSkin.regions.Gloss ~= nil)

local bridgeCalls = { add = 0, remove = 0 }
ns.ExternalSkinBridge = {
    IsAvailable = function() return true end,
    AddButton = function(key, button, regions)
        bridgeCalls.add = bridgeCalls.add + 1
        bridgeCalls.key, bridgeCalls.button, bridgeCalls.regions = key, button, regions
        regions.Icon:SetTexCoord(0.2, 0.8, 0.3, 0.7)
    end,
    RemoveButton = function(key, button)
        bridgeCalls.remove = bridgeCalls.remove + 1
        bridgeCalls.removeKey, bridgeCalls.removedButton = key, button
    end,
}
local externalSkin = MakeContainer()
AuraSkin.Configure(externalSkin, {
    iconSize = 20,
    externalSkinning = true,
    externalSkinKey = "groupauras",
}, { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
local externalButton = externalSkin._birthedButton
check("available external skin bridge receives the live aura button",
    bridgeCalls.add == 1
        and bridgeCalls.key == "groupauras"
        and bridgeCalls.button == externalButton
        and bridgeCalls.regions.Icon == externalButton.Icon
        and table.concat(externalButton.Icon.texCoords, ",") == "0.2,0.8,0.3,0.7")
AuraSkin.Restyle(externalSkin, {
    iconSize = 20,
    externalSkinning = false,
    externalSkinKey = "groupauras",
})
check("disabling external skinning releases the same button",
    bridgeCalls.remove == 1
        and bridgeCalls.removeKey == "groupauras"
        and bridgeCalls.removedButton == externalButton)

local function StyleWith(profile)
    profile.iconSize = profile.iconSize or 20
    local c = MakeContainer()
    AuraSkin.Configure(c, profile, { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
    return c._birthedButton, c
end

local modeDefault = StyleWith({})
check("default mode registers one harmful-only border",
    modeDefault ~= nil and modeDefault._dispelRegs ~= nil
        and #modeDefault._dispelRegs == 1
        and modeDefault._dispelRegs[1].opts.showWhenHarmful == true
        and modeDefault._dispelRegs[1].opts.showWhenHelpful == false
        and modeDefault._dispelRegs[1].opts.showAlways == nil
        and modeDefault._dispelRegs[1].opts.stealableFilter == nil)

local modeAll = StyleWith({ dispelBorderMode = "all" })
check("mode all sets showAlways on the single registration",
    modeAll ~= nil and modeAll._dispelRegs ~= nil
        and #modeAll._dispelRegs == 1
        and modeAll._dispelRegs[1].opts.showAlways == true)

local stealMap = { Magic = { r = 0, g = 0, b = 1 } }
local modeSteal, modeStealContainer = StyleWith({ dispelBorderMode = "stealable", dispelColors = stealMap })
check("mode stealable adds a second helpful-only stealable registration",
    modeSteal ~= nil and modeSteal._dispelRegs ~= nil
        and #modeSteal._dispelRegs == 2
        and modeSteal._dispelRegs[1].texture == modeSteal._quiDispel
        and modeSteal._dispelRegs[2].texture == modeSteal._quiDispelSteal
        and modeSteal._dispelRegs[2].opts.showWhenHarmful == false
        and modeSteal._dispelRegs[2].opts.showWhenHelpful == true
        and modeSteal._dispelRegs[2].opts.stealableFilter == 0
        and modeSteal._dispelRegs[2].opts.showAlways == nil)
check("stealable registration shares the color map with the primary",
    modeSteal ~= nil and modeSteal._dispelRegs ~= nil
        and #modeSteal._dispelRegs == 2
        and modeSteal._dispelRegs[1].opts.customDispelColorMap == stealMap
        and modeSteal._dispelRegs[2].opts.customDispelColorMap == stealMap)

local modeStealOff = StyleWith({ dispelBorderMode = "stealable", showDispelBorder = false })
check("showDispelBorder false suppresses both registrations",
    modeStealOff ~= nil
        and (modeStealOff._addDispelCalls or 0) == 0
        and (modeStealOff._dispelRegs == nil or #modeStealOff._dispelRegs == 0))

if modeSteal then
    AuraSkin.Restyle(modeStealContainer, { iconSize = 20, dispelBorderMode = "debuffs" })
    check("restyle back to debuffs drops the stealable registration",
        modeSteal._dispelRegs ~= nil and #modeSteal._dispelRegs == 1
            and modeSteal._dispelRegs[1].texture == modeSteal._quiDispel)
end

if fails > 0 then error(fails .. " failure(s) in aura_skin_dispel_colors_test") end
print("OK: aura_skin_dispel_colors_test (all checks passed)")
