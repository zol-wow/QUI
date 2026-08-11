local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

_G.InCombatLockdown = function() return false end
_G.AuraContainerSortMethod = { Default = 1 }
_G.AuraContainerSortDirection = { Normal = 1 }
_G.AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 }, FlowLayoutAxis = { Horizontal = 0, Vertical = 1 } }
_G.Enum = _G.Enum or {}
_G.Enum.CustomAuraButtonDispelTypeTextureStyle = { PreserveAsset = 3, CustomAsset = 4 }

local function Region()
    local t = {}
    t._shownCallsAfterHandover = 0
    local function bump()
        if t._handedOver then t._shownCallsAfterHandover = t._shownCallsAfterHandover + 1 end
    end
    function t:SetAllPoints() end
    function t:SetPoint() end
    function t:SetSize() end
    function t:ClearAllPoints() end
    function t:SetColorTexture() end
    function t:SetTexture(tex) t._texture = tex end
    function t:SetTexCoord() end
    function t:SetBlendMode(mode) t._blend = mode end
    function t:DisablePixelSnap() end
    function t:SetTextColor() end
    function t:SetAlpha(a) t._alpha = a end
    function t:SetVertexColor(r, g, b, a) t._vertexColor = { r, g, b, a } end
    function t:SetFont() end
    function t:SetHideCountdownNumbers() end
    function t:SetDrawSwipe() end
    function t:SetReverse() end
    function t:SetText() end
    function t:SetStatusBarTexture() end
    function t:SetOrientation() end
    function t:SetStatusBarColor() end
    function t:Show() bump() end
    function t:Hide() bump() end
    function t:SetShown() bump() end
    function t:CreateTexture() return Region() end
    function t:CreateFontString() return Region() end
    return t
end
_G.CreateFrame = function() return Region() end

local function MakeButton(name, noPandemicAPI)
    local b = Region()
    b._name = name
    function b:SetCancelAuraButtons() end
    function b:SetIcon() end
    function b:AddDispelTypeTexture() end
    function b:ClearDispelTypeTextures() end
    function b:SetDispelTypeText() end
    function b:SetHideTooltipInCombat() end
    function b:SetDurationCooldown() end
    function b:SetDurationText() end
    function b:SetApplicationCount() end
    if not noPandemicAPI then
        function b:AddPandemicRegion(region)
            b._pandemicRegions = b._pandemicRegions or {}
            table.insert(b._pandemicRegions, region)
            region._handedOver = true
            return #b._pandemicRegions
        end
    end
    return b
end

local function MakeContainer(noPandemicAPI)
    local c = { _addCalls = {}, _registeredKeys = {} }
    function c:HasAuraGroup(key) return self._registeredKeys[key] == true end
    function c:AddAuraGroup(key, filter, opts)
        c._addCalls[#c._addCalls + 1] = { key = key, filter = filter }
        c._registeredKeys[key] = true
        c._birthedButton = MakeButton(key .. "#1", noPandemicAPI)
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
assert(loadfile("core/icon_skin.lua"))("QUI", ns)
assert(loadfile("core/aura_skin.lua"))("QUI", ns)
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
local AuraSkin = ns.Addon.AuraSkin
check("core/aura_skin.lua publishes ns.Addon.AuraSkin", AuraSkin ~= nil)

local function ConfigureOne(profile, noPandemicAPI)
    profile.iconSize = profile.iconSize or 20
    local c = MakeContainer(noPandemicAPI)
    AuraSkin.Configure(c, profile,
        { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
    return c, c._birthedButton
end

local c1, b1 = ConfigureOne({})
check("buildButtonArt creates _quiPandemic", b1 and b1._quiPandemic ~= nil)
check("_quiPandemic is handed over exactly once at birth",
    b1 and b1._pandemicRegions ~= nil and #b1._pandemicRegions == 1
        and b1._pandemicRegions[1] == b1._quiPandemic)
AuraSkin.Restyle(c1, { iconSize = 20 })
check("restyle does not hand the region over again",
    b1 and b1._pandemicRegions ~= nil and #b1._pandemicRegions == 1)
check("glow uses the Flash asset with ADD blend",
    b1 and b1._quiPandemic ~= nil
        and b1._quiPandemic._texture == ns.IconSkin.FlashTexture
        and b1._quiPandemic._blend == "ADD")

local _, b2 = ConfigureOne({}, true)
check("no AddPandemicRegion API means no handover and no error",
    b2 and b2._quiPandemic ~= nil and b2._pandemicRegions == nil)

local c3, b3 = ConfigureOne({ pandemicGlow = { color = { 0.2, 0.4, 0.6, 0.8 } } })
b3 = b3 and b3._quiPandemic ~= nil and b3 or nil
check("styleButton drives tint from profile.pandemicGlow.color",
    b3 and b3._quiPandemic._vertexColor ~= nil
        and b3._quiPandemic._vertexColor[1] == 0.2
        and b3._quiPandemic._vertexColor[2] == 0.4
        and b3._quiPandemic._vertexColor[3] == 0.6)
check("styleButton drives alpha from the color's fourth component",
    b3 and b3._quiPandemic._alpha == 0.8)
AuraSkin.Restyle(c3, { iconSize = 20 })
check("restyle without pandemicGlow zeroes the alpha",
    b3 and b3._quiPandemic._alpha == 0)
AuraSkin.Restyle(c3, { iconSize = 20, pandemicGlow = { color = { 1, 0.85, 0.2, 1 } } })
check("restyle re-enables the glow on the live button",
    b3 and b3._quiPandemic._alpha == 1
        and b3._quiPandemic._vertexColor[1] == 1)
check("QUI never calls Show/Hide/SetShown on the region after handover",
    b3 and b3._quiPandemic._shownCallsAfterHandover == 0)

local _, b4 = ConfigureOne({ pandemicGlow = { color = "nope" } })
check("malformed pandemicGlow.color disables instead of erroring",
    b4 and b4._quiPandemic._alpha == 0)

if fails > 0 then
    print("FAIL: aura_skin_pandemic_glow_test (" .. fails .. " failing)")
    os.exit(1)
end
print("OK: aura_skin_pandemic_glow_test (all checks passed)")
