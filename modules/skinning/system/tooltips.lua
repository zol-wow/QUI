local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local UIKit = ns.UIKit
local GetCore = Helpers.GetCore
local SafeCall = ns.SafeCall

local function TooltipDebugCount(name, amount)
    local dbg = ns.QUI_TooltipDebug
    if dbg and dbg.enabled then
        dbg:Count(name, amount)
    end
end

local function TooltipDebugBypassSkin()
    local dbg = ns.QUI_TooltipDebug
    return dbg and dbg.bypassSkin == true
end

local function TooltipDebugBegin()
    local dbg = ns.QUI_TooltipDebug
    if dbg and dbg.enabled then
        local startMS, startHeapKB = dbg:Begin()
        return dbg, startMS, startHeapKB
    end
    return nil, nil, nil
end

local function TooltipDebugEnd(dbg, name, startMS, detail, startHeapKB)
    if dbg and startMS then
        dbg:End(name, startMS, detail, startHeapKB)
    end
end

local function GetSettings()
    local core = GetCore()
    return core and core.db and core.db.profile and core.db.profile.tooltip
end

local function IsEnabled()
    if TooltipDebugBypassSkin() then
        return false
    end
    local settings = GetSettings()
    return settings and settings.enabled and settings.skinTooltips
end

local function ShouldHideHealthBar()
    local settings = GetSettings()
    return settings and settings.enabled and settings.hideHealthBar
end

local function GetEffectiveColors()
    local settings = GetSettings()
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor(settings, "")
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColor()

    if settings then
        if settings.bgColor then
            bgr = settings.bgColor[1] or bgr
            bgg = settings.bgColor[2] or bgg
            bgb = settings.bgColor[3] or bgb
        end
        if settings.bgOpacity then bga = settings.bgOpacity end

        if settings.showBorder == false then
            sr, sg, sb, sa = 0, 0, 0, 0
        end
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

local function GetEffectiveBorderThickness()
    local settings = GetSettings()
    return (settings and settings.borderThickness) or 1
end

local AURA_TOOLTIP_BG = "Interface\\Buttons\\WHITE8x8"

local function ApplyAuraTooltipStyle()
    local bridge = _G.AuraContainerInbound
    if not bridge or type(bridge.SetTooltipBackdrop) ~= "function" then
        return false
    end
    if not IsEnabled() then
        if type(bridge.ResetTooltipStyle) == "function" then
            SafeCall("aura-tooltip-reset", bridge.ResetTooltipStyle)
        end
        return true
    end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    SafeCall("aura-tooltip-style", bridge.SetTooltipBackdrop, {
        backdropInfo = {
            bgFile = AURA_TOOLTIP_BG,
            edgeFile = AURA_TOOLTIP_BG,
            edgeSize = GetEffectiveBorderThickness(),
        },
        centerColor = CreateColor(bgr, bgg, bgb, bga),
        borderColor = CreateColor(sr, sg, sb, sa),
    })
    return true
end

local function GetEffectiveFontSize()
    local settings = GetSettings()
    local size = (settings and settings.fontSize) or 12
    size = tonumber(size) or 12
    return math.max(8, math.min(24, math.floor(size + 0.5)))
end

local function SetFontStringSize(fs, size)
    if not fs or not fs.GetFont or not fs.SetFont then return end
    if fs.IsForbidden and fs:IsForbidden() then return end
    local ok, path, curSize, flags = pcall(fs.GetFont, fs)
    if not ok or not path then
        path = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
        flags = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
    elseif type(curSize) == "number" and math.abs(curSize - size) < 0.5 then
        return
    end
    if Helpers and Helpers.ApplyFontWithFallback then
        SafeCall("best-effort-style", Helpers.ApplyFontWithFallback, fs, path, size, flags or "")
    else
        SafeCall("best-effort-style", fs.SetFont, fs, path, size, flags or "")
    end
end

local defaultHeaderFont, defaultHeaderSize, defaultHeaderFlag
local defaultBodyFont, defaultBodySize, defaultBodyFlag
local appliedHeaderFamily, appliedBodyFamily, appliedSmallFamily
local defaultSmallFont, defaultSmallSize, defaultSmallFlag
local function CacheDefaultFontMetrics()
    if defaultHeaderFont then return end
    if GameTooltipHeaderText then
        defaultHeaderFont, defaultHeaderSize, defaultHeaderFlag = GameTooltipHeaderText:GetFont()
    end
    if GameTooltipText then
        defaultBodyFont, defaultBodySize, defaultBodyFlag = GameTooltipText:GetFont()
    end
    if GameTooltipTextSmall then
        defaultSmallFont, defaultSmallSize, defaultSmallFlag = GameTooltipTextSmall:GetFont()
    end
end

local function ApplyFontSizeViaFontObjects(size)
    CacheDefaultFontMetrics()
    local headerSize = size + 2
    local font = (Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or defaultBodyFont or STANDARD_TEXT_FONT
    local outline = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()
    if GameTooltipHeaderText and defaultHeaderFont then
        local curFont, curSize, curFlags = GameTooltipHeaderText:GetFont()
        local targetFlags = outline or curFlags or defaultHeaderFlag or ""
        local family = Helpers.GetFontFamilyObject and Helpers.GetFontFamilyObject(font, headerSize, targetFlags)
        local needsApply = curFont ~= font or curFlags ~= targetFlags or not curSize
            or math.abs(curSize - headerSize) >= 0.5
            or (family ~= nil and appliedHeaderFamily ~= family)
        if needsApply then
            if family then
                if SafeCall("best-effort-style", GameTooltipHeaderText.SetFontObject, GameTooltipHeaderText, family) then
                    appliedHeaderFamily = family
                end
            else
                GameTooltipHeaderText:SetFont(font or defaultHeaderFont, headerSize, targetFlags)
            end
        end
    end
    if GameTooltipText and defaultBodyFont then
        local curFont, curSize, curFlags = GameTooltipText:GetFont()
        local targetFlags = outline or curFlags or defaultBodyFlag or ""
        local family = Helpers.GetFontFamilyObject and Helpers.GetFontFamilyObject(font, size, targetFlags)
        local needsApply = curFont ~= font or curFlags ~= targetFlags or not curSize
            or math.abs(curSize - size) >= 0.5
            or (family ~= nil and appliedBodyFamily ~= family)
        if needsApply then
            if family then
                if SafeCall("best-effort-style", GameTooltipText.SetFontObject, GameTooltipText, family) then
                    appliedBodyFamily = family
                end
            else
                GameTooltipText:SetFont(font or defaultBodyFont, size, targetFlags)
            end
        end
    end
    if GameTooltipTextSmall and defaultSmallFont then
        local curFont, curSize, curFlags = GameTooltipTextSmall:GetFont()
        local smallSize = (type(curSize) == "number" and curSize > 0 and curSize)
            or (type(defaultSmallSize) == "number" and defaultSmallSize > 0 and defaultSmallSize) or size
        local targetFlags = outline or curFlags or defaultSmallFlag or ""
        local family = Helpers.GetFontFamilyObject and Helpers.GetFontFamilyObject(font, smallSize, targetFlags)
        local needsApply = curFont ~= font or curFlags ~= targetFlags
            or (family ~= nil and appliedSmallFamily ~= family)
        if needsApply then
            if family then
                if SafeCall("best-effort-style", GameTooltipTextSmall.SetFontObject, GameTooltipTextSmall, family) then
                    appliedSmallFamily = family
                end
            else
                GameTooltipTextSmall:SetFont(font or defaultSmallFont, smallSize, targetFlags)
            end
        end
    end
end

local function ApplyFontSize(tooltip)
    if not tooltip then return end
    local base = GetEffectiveFontSize()

    if tooltip == GameTooltip then
        ApplyFontSizeViaFontObjects(base)
        return
    end

    local header = base + 2
    local name
    if tooltip.GetName then
        local ok, n = pcall(tooltip.GetName, tooltip)
        if ok then name = n end
    end

    if name and tooltip.NumLines then
        local ok, count = pcall(tooltip.NumLines, tooltip)
        if ok and count and count > 0 then
            if tooltip.GetLeftLine and tooltip.GetRightLine then
                for i = 1, count do
                    local s = (i == 1) and header or base
                    SetFontStringSize(tooltip:GetLeftLine(i), s)
                    SetFontStringSize(tooltip:GetRightLine(i), s)
                end
            else
                for i = 1, count do
                    local s = (i == 1) and header or base
                    SetFontStringSize(_G[name .. "TextLeft" .. i], s)
                    SetFontStringSize(_G[name .. "TextRight" .. i], s)
                end
            end
            return
        end
    end

    local n = tooltip.GetNumRegions and tooltip:GetNumRegions() or 0
    local first = true
    for i = 1, n do
        local r = select(i, tooltip:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then
            SetFontStringSize(r, first and header or base)
            first = false
        end
    end
end

local styleFrames = Helpers.CreateStateTable()
local hookedTooltips = Helpers.CreateStateTable()
local hookedNineSlices = Helpers.CreateStateTable()
local suppressNSHook = false
local StyleGameTooltip
local HasActiveWidgetContainer

local function HideNineSlice(tooltip)
    local ns = tooltip.NineSlice
    if not ns then return end
    SafeCall("best-effort-style", ns.Hide, ns)
    SafeCall("best-effort-style", ns.SetFrameLevel, ns, 0)
end

local function HookNineSlice(tooltip)
    local ns = tooltip and tooltip.NineSlice
    if not ns or hookedNineSlices[ns] then return end
    hookedNineSlices[ns] = true

    hooksecurefunc(ns, "Show", function(self)
        if suppressNSHook then return end
        if not IsEnabled() then return end

        SafeCall("best-effort-style", self.Hide, self)
        SafeCall("best-effort-style", self.SetFrameLevel, self, 0)

        local sf = styleFrames[tooltip]
        if sf then SafeCall("best-effort-style", sf.Show, sf) end
    end)
end

local function HideStyleFrame(tooltip)
    local frame = tooltip and styleFrames[tooltip]
    if frame then
        frame:Hide()
    end
end

local function FallbackToNineSlice(tooltip)
    suppressNSHook = true
    local ns = tooltip and tooltip.NineSlice
    if ns then SafeCall("best-effort-style", ns.Show, ns) end
    suppressNSHook = false
    HideStyleFrame(tooltip)
end

local function IsChromeStable(tooltip)
    local sf = styleFrames[tooltip]
    if not (sf and sf.IsShown and sf:IsShown()) then
        return false
    end

    local ns = tooltip and tooltip.NineSlice
    if not ns then
        return true
    end
    if ns.IsShown then
        local okShown, shown = pcall(ns.IsShown, ns)
        return okShown and not shown
    end
    return false
end

local function ShowExistingChrome(tooltip)
    local sf = styleFrames[tooltip]
    local sfShown = sf and sf.IsShown and sf:IsShown()
    local ns = tooltip and tooltip.NineSlice
    local nsShown = false
    if ns and ns.IsShown then
        local okShown, shown = pcall(ns.IsShown, ns)
        nsShown = not okShown or shown
    elseif ns then
        nsShown = true
    end

    if sfShown and not nsShown then
        TooltipDebugCount("skin.chromeSkip")
        return false
    end

    if nsShown then
        HideNineSlice(tooltip)
    end
    if sf and not sfShown then
        sf:Show()
    end
    return true
end

local function HasAccessibleDimensions(tooltip)
    if not tooltip then return false end
    local okWidth, width = pcall(tooltip.GetWidth, tooltip)
    if not okWidth or type(width) ~= "number" or Helpers.IsSecretValue(width) then
        return false
    end
    local okHeight, height = pcall(tooltip.GetHeight, tooltip)
    if not okHeight or type(height) ~= "number" or Helpers.IsSecretValue(height) then
        return false
    end
    return width >= 0 and height >= 0
end

local function GetStyleFrame(tooltip)
    local frame = styleFrames[tooltip]
    if frame then return frame end

    frame = CreateFrame("Frame", nil, tooltip)
    frame:SetAllPoints()
    frame.ignoreInLayout = true
    frame:EnableMouse(false)
    local bgF = SkinBase.CHROME.BG_FALLBACK
    frame.bg = UIKit.CreateBackground(frame, bgF[1], bgF[2], bgF[3], bgF[4])
    UIKit.CreateBorderLines(frame)

    styleFrames[tooltip] = frame
    return frame
end

local function IsEmbedded(tooltip)
    local ok, parent = pcall(tooltip.GetParent, tooltip)
    if not ok or not parent then return false end
    local visible = parent.IsShown and parent:IsShown()
    return visible
        and (tooltip.IsEmbedded
            or (parent.NineSlice and parent ~= UIParent and parent ~= WorldFrame))
end

local function IsInternalEmbeddedItemRoot(root, tooltip)
    if not root or not tooltip then return false end
    if tooltip == root or tooltip == root.Tooltip or tooltip == root.FollowerTooltip then
        return true
    end
    if tooltip.GetParent then
        local ok, parent = pcall(tooltip.GetParent, tooltip)
        if ok and parent == root then
            return true
        end
    end
    return false
end

local function IsInternalEmbeddedItemTooltipFrame(tooltip)
    if tooltip == EmbeddedItemTooltip then
        return true
    end
    if IsInternalEmbeddedItemRoot(GameTooltip and GameTooltip.ItemTooltip, tooltip) then
        return true
    end
    if IsInternalEmbeddedItemRoot(EmbeddedItemTooltip and EmbeddedItemTooltip.ItemTooltip, tooltip) then
        return true
    end
    return false
end

local function StyleShoppingCompareHeader(header, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not header then return end
    if header.IsForbidden and header:IsForbidden() then return end

    if not SkinBase then
        if header.SetBackdrop then SafeCall("best-effort-style", header.SetBackdrop, header, nil) end
        if header.NineSlice then SafeCall("best-effort-style", header.NineSlice.Hide, header.NineSlice) end
        return
    end

    SkinBase.StripTextures(header)
    SkinBase.CreateBackdrop(header, sr, sg, sb, sa, bgr, bgg, bgb, 0.92)
    local bd = SkinBase.GetBackdrop(header)
    if bd then
        SkinBase.SetPixelInsetPoints(bd, header, 3, 3, 3, 0)
    end

    if header.Label and header.Label.SetTextColor then
        header.Label:SetTextColor(sr, sg, sb, 1)
    end
end

local function ApplyTooltipChrome(tooltip)
    if not tooltip then return end
    if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
    TooltipDebugCount("skin.applyChrome")

    if IsEmbedded(tooltip) then
        HideNineSlice(tooltip)
        if tooltip.SetBackdrop then SafeCall("best-effort-style", tooltip.SetBackdrop, tooltip, nil) end
        HideStyleFrame(tooltip)
        return
    end

    HideNineSlice(tooltip)

    if not HasAccessibleDimensions(tooltip) then
        FallbackToNineSlice(tooltip)
        return
    end

    local frame = GetStyleFrame(tooltip)
    local ok, level = pcall(tooltip.GetFrameLevel, tooltip)
    if ok and type(level) == "number" then
        frame:SetFrameLevel(level)
    end

    local okStrata, strata = pcall(tooltip.GetFrameStrata, tooltip)
    if okStrata and strata then
        frame:SetFrameStrata(strata)
    end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = math.max(GetEffectiveBorderThickness(), 1)

    if frame.bg then
        frame.bg:SetVertexColor(bgr, bgg, bgb, bga)
    end
    UIKit.UpdateBorderLines(frame, thickness, sr, sg, sb, sa, sa <= 0)
    frame:Show()

    if tooltip.CompareHeader then
        StyleShoppingCompareHeader(tooltip.CompareHeader, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
end

local function StyleTooltip(tooltip)
    if not tooltip then return end
    if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end
    if tooltip == GameTooltip and HasActiveWidgetContainer and HasActiveWidgetContainer(tooltip) then
        FallbackToNineSlice(tooltip)
        return
    end

    TooltipDebugCount("skin.style")
    local dbg, dbgStart, dbgHeap = TooltipDebugBegin()
    ns.SafeCall("best-effort-style", ApplyTooltipChrome, tooltip)
    if tooltip.CloseButton and SkinBase.SkinCloseButton then
        local closeButton = tooltip.CloseButton
        ns.SafeCall("best-effort-style", SkinBase.SkinCloseButton, closeButton)
        if closeButton.ClearAllPoints and closeButton.SetPoint then
            SafeCall("best-effort-style", SkinBase.SetPixelPoint, closeButton, "TOPRIGHT", tooltip, "TOPRIGHT", -2, -2)
        end
    end
    TooltipDebugEnd(dbg, "skin.style", dbgStart, nil, dbgHeap)
end

local function CombatRefreshTooltip(tooltip)
    if not tooltip then return end
    if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    TooltipDebugCount("skin.combatRefresh")
    local dbg, dbgStart, dbgHeap = TooltipDebugBegin()
    ns.SafeCall("best-effort-style", ApplyTooltipChrome, tooltip)
    TooltipDebugEnd(dbg, "skin.combatRefresh", dbgStart, nil, dbgHeap)
end

local function HasActiveMoneyFrame(tooltip)
    if not tooltip or not tooltip.GetChildren or not tooltip.GetNumChildren then return false end
    TooltipDebugCount("skin.moneyScan")

    local okCount, numChildren = pcall(tooltip.GetNumChildren, tooltip)
    if not okCount or not numChildren then return false end

    for i = 1, numChildren do
        local child = select(i, tooltip:GetChildren())
        if child then
            local childName
            if child.GetName then
                local okName, name = pcall(child.GetName, child)
                if okName then childName = name end
            end
            if child.moneyType ~= nil or child.staticMoney ~= nil or child.lastArgMoney ~= nil or
                (type(childName) == "string" and childName:find("MoneyFrame")) then
                if child.IsShown then
                    local okShown, shown = pcall(child.IsShown, child)
                    if not okShown or shown then
                        TooltipDebugCount("skin.moneyHit")
                        return true
                    end
                else
                    TooltipDebugCount("skin.moneyHit")
                    return true
                end
            end
        end
    end

    return false
end

HasActiveWidgetContainer = function(tooltip)
    if Helpers.HasTaintedWidgetContainer then
        TooltipDebugCount("skin.widgetScan")
        local active = Helpers.HasTaintedWidgetContainer(tooltip)
        if active then TooltipDebugCount("skin.widgetHit") end
        return active
    end

    if not tooltip or not tooltip.GetChildren then return false end
    TooltipDebugCount("skin.widgetScan")

    local okChildren, children = pcall(function()
        return { tooltip:GetChildren() }
    end)
    if not okChildren or not children then return false end

    for i = 1, #children do
        local child = children[i]
        if child and type(child.RegisterForWidgetSet) == "function" then
            local okShown, shown = pcall(child.IsShown, child)
            if not okShown or Helpers.IsSecretValue(shown) or shown then
                TooltipDebugCount("skin.widgetHit")
                return true -- @secret-policy: keep-native-when-unknown
            end
        end
    end

    return false
end

local function RefreshTooltipLayout(tooltip)
    if not tooltip or not (tooltip.IsShown and tooltip:IsShown()) then return end
    if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    if tooltip == GameTooltip then
        if HasActiveMoneyFrame(tooltip) or HasActiveWidgetContainer(tooltip) then
            return
        end
    end

    if type(tooltip.UpdateTooltipSize) == "function" then
        SafeCall("best-effort-style", tooltip.UpdateTooltipSize, tooltip)
    end
end

local function OnTooltipShow(tooltip)
    if not IsEnabled() then return end
    if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
    if tooltip == GameTooltip then
        if HasActiveWidgetContainer(tooltip) then
            FallbackToNineSlice(tooltip)
            return
        end
        if HasActiveMoneyFrame(tooltip) then
            ns.SafeCall("best-effort-style", ShowExistingChrome, tooltip)
            return
        end
    end
    if InCombatLockdown() then
        CombatRefreshTooltip(tooltip)
    else
        StyleTooltip(tooltip)
    end
end

local gameTooltipFamily = {
    "GameTooltip", "ItemRefTooltip",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
    "ShoppingTooltip1", "ShoppingTooltip2",
    "SmallTextTooltip",
    "ReputationParagonTooltip",
    "FriendsTooltip", "SettingsTooltip",
    "GameSmallHeaderTooltip", "QuickKeybindTooltip",
}

local specializedTooltips = {
    "QueueStatusFrame",
    "FloatingGarrisonFollowerTooltip", "FloatingGarrisonFollowerAbilityTooltip",
    "FloatingGarrisonMissionTooltip", "GarrisonFollowerTooltip",
    "GarrisonFollowerAbilityTooltip", "GarrisonMissionTooltip",
    "BattlePetTooltip", "FloatingBattlePetTooltip",
    "PetBattlePrimaryUnitTooltip", "PetBattlePrimaryAbilityTooltip",
    "FloatingPetBattleAbilityTooltip", "IMECandidatesFrame",
}

local dotPathTooltips = {
    {"QuestScrollFrame", "StoryTooltip"},
    {"QuestScrollFrame", "CampaignTooltip"},
}

local addonTooltipFrames = {
    "WQLTooltip", "WQLTooltipItemRef1", "WQLTooltipItemRef2",
    "WQLAreaPOITooltip", "WorldQuestTrackerGameTooltip",
    "WQT_ShoppingTooltip1", "WQT_ShoppingTooltip2",
}

local tooltipsToSkin = {}

local function RebuildTooltipList()
    wipe(tooltipsToSkin)
    for _, name in ipairs(specializedTooltips) do
        tooltipsToSkin[#tooltipsToSkin + 1] = name
    end
    for _, name in ipairs(gameTooltipFamily) do
        tooltipsToSkin[#tooltipsToSkin + 1] = name
    end
end

local function ResolveDotPath(path)
    local obj = _G[path[1]]
    for i = 2, #path do
        if not obj then return nil end
        obj = obj[path[i]]
    end
    return obj
end

local HookTooltipOnShow

local _pendingFontSet = {}
local _pendingFontTimerActive = false
local function _FlushPendingFonts()
    TooltipDebugCount("skin.fontFlush")
    _pendingFontTimerActive = false
    for tt in pairs(_pendingFontSet) do
        _pendingFontSet[tt] = nil
        if tt.IsShown and tt:IsShown() and not InCombatLockdown() then
            if tt == GameTooltip and HasActiveWidgetContainer and HasActiveWidgetContainer(tt) then
                TooltipDebugCount("skin.fontWidgetSkipped")
            else
                ns.SafeCall("best-effort-style", ApplyFontSize, tt)
                RefreshTooltipLayout(tt)
            end
        end
    end
end

local function QueueFontUpdate(tooltip)
    if not tooltip or not IsEnabled() then return end
    TooltipDebugCount("skin.fontQueued")
    _pendingFontSet[tooltip] = true
    if not _pendingFontTimerActive then
        _pendingFontTimerActive = true
        C_Timer.After(0, _FlushPendingFonts)
    end
end

local GetTooltipOwnerRestriction
local function IsProtectedTooltip(tip)
    if not tip then return true end
    if tip.IsForbidden and tip:IsForbidden() then return true end
    if Helpers.FrameIsProtected and Helpers.FrameIsProtected(tip) then return true end
    local restriction = GetTooltipOwnerRestriction(tip)
    return restriction ~= nil
end

GetTooltipOwnerRestriction = function(tip)
    if not tip then return "missing" end
    local owner = tip.GetOwner and tip:GetOwner()
    if not owner then return nil end
    local current = owner
    for _ = 1, 10 do
        if not current then break end
        if current.IsForbidden and current:IsForbidden() then return "forbidden" end
        if Helpers.FrameIsProtected and Helpers.FrameIsProtected(current) then return "protected" end
        local ok, parent = pcall(current.GetParent, current)
        current = ok and parent or nil
    end
    return nil
end

HookTooltipOnShow = function(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end
    if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end

    if tooltip == GameTooltip then
        hookedTooltips[tooltip] = true
        HookNineSlice(tooltip)
        return
    end

    hooksecurefunc(tooltip, "Show", function(self)
        TooltipDebugCount("skin.tooltipShow")
        if not IsEnabled() then
            FallbackToNineSlice(self)
            return
        end

        if InCombatLockdown() then
            CombatRefreshTooltip(self)
            return
        end

        local _ns = self.NineSlice
        local _sf = styleFrames[self]
        if _sf and _sf:IsShown() and (not _ns or not _ns:IsShown()) then
            return
        end

        StyleTooltip(self)
        QueueFontUpdate(self)
    end)

    hookedTooltips[tooltip] = true
    HookNineSlice(tooltip)
end

local function HookAllTooltips()
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip then HookTooltipOnShow(tooltip) end
    end
end

local function DiscoverAndSkin(tooltip)
    if not tooltip then return end
    if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    HookTooltipOnShow(tooltip)
    if IsEnabled() and not InCombatLockdown() then
        StyleTooltip(tooltip)
    end
end

local function DiscoverExtraTooltips()
    for _, path in ipairs(dotPathTooltips) do
        DiscoverAndSkin(ResolveDotPath(path))
    end
    for _, name in ipairs(addonTooltipFrames) do
        DiscoverAndSkin(_G[name])
    end
end

local extraTooltipDiscoveryQueued = false
local function RunQueuedExtraTooltipDiscovery()
    extraTooltipDiscoveryQueued = false
    if InCombatLockdown() then return end

    DiscoverExtraTooltips()
end

local function QueueExtraTooltipDiscovery()
    if extraTooltipDiscoveryQueued then return end
    extraTooltipDiscoveryQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RunQueuedExtraTooltipDiscovery)
    else
        RunQueuedExtraTooltipDiscovery()
    end
end

local function SetupBackdropStyleHooks()
    if SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip, style, isEmbedded)
            TooltipDebugCount("skin.sharedBackdrop")
            if not IsEnabled() or not tooltip then return end
            if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
            local ok, objType = pcall(tooltip.GetObjectType, tooltip)
            if not ok or objType ~= "GameTooltip" then return end

            if tooltip == GameTooltip then
                StyleGameTooltip(tooltip)
                return
            end

            if isEmbedded or tooltip.IsEmbedded then
                HideNineSlice(tooltip)
                if tooltip.SetBackdrop then SafeCall("best-effort-style", tooltip.SetBackdrop, tooltip, nil) end
                local sf = styleFrames[tooltip]
                if sf then sf:Hide() end
            else
                local _ns2 = tooltip.NineSlice
                local _sf2 = styleFrames[tooltip]
                if not (_sf2 and _sf2:IsShown() and (not _ns2 or not _ns2:IsShown())) then
                    OnTooltipShow(tooltip)
                end
                HookTooltipOnShow(tooltip)
            end
        end)
    end

    if GameTooltip_SetBackdropStyle then
        hooksecurefunc("GameTooltip_SetBackdropStyle", function(tooltip, style)
            TooltipDebugCount("skin.gameBackdrop")
            if not IsEnabled() or not tooltip then return end
            if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
            local ok, objType = pcall(tooltip.GetObjectType, tooltip)
            if not ok or objType ~= "GameTooltip" then return end
            if tooltip == GameTooltip then
                StyleGameTooltip(tooltip)
                return
            end
            local _ns3 = tooltip.NineSlice
            local _sf3 = styleFrames[tooltip]
            if not (_sf3 and _sf3:IsShown() and (not _ns3 or not _ns3:IsShown())) then
                OnTooltipShow(tooltip)
            end
            HookTooltipOnShow(tooltip)
        end)
    end

    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
            if not IsEnabled() or not tooltip then return end
            if tooltip ~= GameTooltip then return end
            StyleGameTooltip(tooltip)
        end)
    end

    if GameTooltip then
        hooksecurefunc(GameTooltip, "SetOwner", function(self)
            if not IsEnabled() or self ~= GameTooltip then return end
            if GetTooltipOwnerRestriction(self) then
                TooltipDebugCount("skin.setOwnerDeferred")
                return
            end
            StyleGameTooltip(self)
        end)
    end

end

local function SetupPostProcessor()
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then return end

    local function DeferFont(tooltip)
        QueueFontUpdate(tooltip)
    end

    local function HandlePostCall(tooltip)
        TooltipDebugCount("skin.postCall")
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
        if tooltip == GameTooltip then
            if GetTooltipOwnerRestriction(tooltip) == "forbidden" then
                FallbackToNineSlice(tooltip)
                return
            end
            HookTooltipOnShow(tooltip)
            TooltipDebugCount("skin.postGameTooltip")
            StyleGameTooltip(tooltip)
            return
        end
        if IsProtectedTooltip(tooltip) then
            TooltipDebugCount("skin.protectedTooltipSkipped")
            return
        end
        HookTooltipOnShow(tooltip)
        if InCombatLockdown() then
            CombatRefreshTooltip(tooltip)
        else
            DeferFont(tooltip)
            if IsEnabled() then StyleTooltip(tooltip) end
        end
    end

    local function RunHandlePostCall(tooltip)
        if TooltipDebugBypassSkin() then
            TooltipDebugCount("skin.bypassed")
            return
        end
        local dbg, dbgStart, dbgHeap = TooltipDebugBegin()
        HandlePostCall(tooltip)
        TooltipDebugEnd(dbg, "skin.postCall", dbgStart, nil, dbgHeap)
    end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, RunHandlePostCall)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, RunHandlePostCall)
    local auraTooltipType = Enum.TooltipDataType.UnitAura or Enum.TooltipDataType.Aura
    if auraTooltipType then
        TooltipDataProcessor.AddTooltipPostCall(auraTooltipType, RunHandlePostCall)
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        RunHandlePostCall(tooltip)
        if ShouldHideHealthBar() and tooltip and not InCombatLockdown() then
            local bar = tooltip.StatusBar or (tooltip == GameTooltip and GameTooltipStatusBar)
            if bar and not (bar.IsForbidden and bar:IsForbidden()) then
                Helpers.SafeHide(bar)
            end
        end
    end)
end

ns.QUI_GetAuraTooltipProbeStatus = function()
    local bridge = _G.AuraContainerInbound
    local supported = type(bridge) == "table"
        and type(bridge.SetTooltipBackdrop) == "function"
    return {
        skinningLoaded = true,
        supported = supported,
        reason = supported and "inbound-bridge" or "secure-environment",
    }
end

local function SetupHealthBarHook()
    if not GameTooltip then return end
    local bar = GameTooltip.StatusBar or GameTooltipStatusBar
    if not bar then return end
    hooksecurefunc(bar, "Show", function(self)
        if InCombatLockdown() then return end
        if ShouldHideHealthBar() then Helpers.SafeHide(self) end
    end)
end

local function RefreshAllColors()
    if InCombatLockdown() then return end
    for tooltip in pairs(styleFrames) do
        if not (tooltip.IsForbidden and tooltip:IsForbidden())
            and tooltip.IsShown and tooltip:IsShown() then
            StyleTooltip(tooltip)
        end
    end
    ApplyAuraTooltipStyle()
end

local function RefreshAllFonts()
    if InCombatLockdown() then return end
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip and not IsInternalEmbeddedItemTooltipFrame(tooltip) then
            if tooltip == GameTooltip and HasActiveWidgetContainer and HasActiveWidgetContainer(tooltip) then
                FallbackToNineSlice(tooltip)
            else
                ApplyFontSize(tooltip)
                RefreshTooltipLayout(tooltip)
            end
        end
    end
end

local pendingShoppingTooltipSync = false
local function FlushShoppingTooltipSync()
    TooltipDebugCount("skin.shoppingFlush")
    pendingShoppingTooltipSync = false
    if not GameTooltip:IsShown() then return end
    for i = 1, 2 do
        local st = _G["ShoppingTooltip" .. i]
        if st and st:IsShown() then
            HookTooltipOnShow(st)
            OnTooltipShow(st)
        end
    end
end

local function QueueShoppingTooltipSync()
    if pendingShoppingTooltipSync then return end
    TooltipDebugCount("skin.shoppingQueued")
    pendingShoppingTooltipSync = true
    C_Timer.After(0, FlushShoppingTooltipSync)
end

StyleGameTooltip = function(tooltip)
    if not tooltip or tooltip ~= GameTooltip then return end
    if IsInternalEmbeddedItemTooltipFrame(tooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    if not IsEnabled() then
        FallbackToNineSlice(tooltip)
        return
    end

    if GetTooltipOwnerRestriction(tooltip) == "forbidden" then
        FallbackToNineSlice(tooltip)
        return
    end

    if HasActiveWidgetContainer(tooltip) then
        FallbackToNineSlice(tooltip)
        return
    end

    if IsChromeStable(tooltip) then
        TooltipDebugCount("skin.backdropStableSkip")
        return
    end

    OnTooltipShow(tooltip)

    QueueFontUpdate(tooltip)
    QueueShoppingTooltipSync()
    if ns.QUI_EnsureTooltipCJKFallback then
        ns.QUI_EnsureTooltipCJKFallback()
    end
end

local eventFrame = CreateFrame("Frame")
local initialized = false
local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "Tooltips_Skin", frame = eventFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and initialized then
        QueueExtraTooltipDiscovery()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if IsEnabled() then
            for _, name in ipairs(tooltipsToSkin) do
                local tooltip = _G[name]
                if tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden())
                    and tooltip.IsShown and tooltip:IsShown() then
                    StyleTooltip(tooltip)
                end
            end
            for tooltip in pairs(styleFrames) do
                if not (tooltip.IsForbidden and tooltip:IsForbidden())
                    and tooltip.IsShown and tooltip:IsShown() then
                    StyleTooltip(tooltip)
                end
            end
            RefreshAllFonts()
        end
        DiscoverExtraTooltips()
        return
    end
end)

local function InitializeTooltipSkinning()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if initialized then return end

    RebuildTooltipList()

    HookAllTooltips()
    if IsEnabled() then
        RefreshAllFonts()
        for _, name in ipairs(tooltipsToSkin) do
            local tooltip = _G[name]
            if tooltip then StyleTooltip(tooltip) end
        end
    end

    SetupBackdropStyleHooks()
    SetupHealthBarHook()
    SetupPostProcessor()
    DiscoverExtraTooltips()
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    initialized = true
end

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(InitializeTooltipSkinning)
end

ns.QUI_RefreshTooltipSkinColors = RefreshAllColors
ns.QUI_RefreshTooltipFontSize = RefreshAllFonts

local CJK_LOCALES = { koKR = true, zhCN = true, zhTW = true }
local function SelectedLocaleNeedsCJK()
    local loc = (QUIDB and QUIDB.global and QUIDB.global.selectedLocale)
        or (GetLocale and GetLocale())
    return loc ~= nil and CJK_LOCALES[loc] == true
end

local cjkAppliedFont = setmetatable({}, { __mode = "k" })
local function EnsureFontObjectCJK(fontObj)
    if not (fontObj and fontObj.GetFont and fontObj.SetFontObject) then return end
    if not (Helpers and Helpers.GetFontFamilyObject) then return end
    local path, size, flags = fontObj:GetFont()
    if not (path and type(size) == "number" and size > 0) then return end
    local family = Helpers.GetFontFamilyObject(path, size, flags or "")
    if not family then return end
    if cjkAppliedFont[fontObj] == family then return end
    if SafeCall("best-effort-style", fontObj.SetFontObject, fontObj, family) then
        cjkAppliedFont[fontObj] = family
    end
end

local function EnsureTooltipCJKFallback()
    if not SelectedLocaleNeedsCJK() then return end
    EnsureFontObjectCJK(GameTooltipHeaderText)
    EnsureFontObjectCJK(GameTooltipText)
    EnsureFontObjectCJK(GameTooltipTextSmall)
end
ns.QUI_EnsureTooltipCJKFallback = EnsureTooltipCJKFallback

do
    if ns.WhenLoggedIn then
        ns.WhenLoggedIn(EnsureTooltipCJKFallback)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(1, EnsureTooltipCJKFallback)
    end
end

do
    if ns.WhenLoggedIn then
        ns.WhenLoggedIn(ApplyAuraTooltipStyle)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(1, ApplyAuraTooltipStyle)
    end
end

if ns.Registry then
    ns.Registry:Register("tooltips", {
        refresh = RefreshAllColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key      = "tooltip",
        label    = ns.L["Tooltip"],
        category = "Skinning",
        prefix   = "",
        db       = function(p) return p.tooltip end,
        refresh  = function() if ns.QUI_RefreshTooltipSkinColors then ns.QUI_RefreshTooltipSkinColors() end end,
        legacy   = {},
    })
end
