local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local GetCore = Helpers.GetCore
local issecretvalue = issecretvalue

---------------------------------------------------------------------------
-- TOOLTIP SKINNING
-- Hides Blizzard's NineSlice via :Hide(), renders QUI-owned
-- manual chrome (background + border lines). Falls back to NineSlice when styling fails
-- (combat secret values, forbidden frames, errors).
---------------------------------------------------------------------------

-- Settings
---------------------------------------------------------------------------

local function GetSettings()
    local core = GetCore()
    return core and core.db and core.db.profile and core.db.profile.tooltip
end

local function IsEnabled()
    local settings = GetSettings()
    return settings and settings.enabled and settings.skinTooltips
end

local function ShouldHideHealthBar()
    local settings = GetSettings()
    return settings and settings.enabled and settings.hideHealthBar
end

---------------------------------------------------------------------------
-- Colors & Border
---------------------------------------------------------------------------

local function GetPlayerClassColor()
    local _, classToken = UnitClass("player")
    if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        local c = RAID_CLASS_COLORS[classToken]
        return c.r, c.g, c.b, 1
    end
    return 0.376, 0.647, 0.980, 1
end

local function GetEffectiveColors()
    local settings = GetSettings()
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor()
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColor()

    if settings then
        if settings.bgColor then
            bgr = settings.bgColor[1] or bgr
            bgg = settings.bgColor[2] or bgg
            bgb = settings.bgColor[3] or bgb
        end
        if settings.bgOpacity then bga = settings.bgOpacity end

        if settings.borderUseClassColor then
            sr, sg, sb, sa = GetPlayerClassColor()
        elseif settings.borderUseAccentColor then
            local QUI = _G.QUI
            if QUI and QUI.GetAddonAccentColor then
                sr, sg, sb, sa = QUI:GetAddonAccentColor()
            end
        elseif settings.borderColor then
            sr = settings.borderColor[1] or sr
            sg = settings.borderColor[2] or sg
            sb = settings.borderColor[3] or sb
            sa = settings.borderColor[4] or sa
        end

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

---------------------------------------------------------------------------
-- Font Sizing
-- TAINT SAFETY: GameTooltip uses Font-object-level sizing ONLY.
-- Calling SetFont() directly on GameTooltipTextLeft* FontStrings taints
-- them permanently; Blizzard's secure code (QuestMapLogTitleButton_OnEnter
-- etc.) later calls GetStringWidth() on those FontStrings and gets secret
-- values during combat → arithmetic errors. Modifying the Font objects
-- (GameTooltipHeaderText, GameTooltipText) instead propagates the size
-- change to derived FontStrings WITHOUT tainting them individually.
-- Other tooltips (ItemRefTooltip, ShoppingTooltip, etc.) are safe to
-- modify per-FontString since Blizzard doesn't call GetStringWidth() on
-- their lines from secure code.
---------------------------------------------------------------------------

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
        return  -- already at target size; skip SetFont to avoid relayout
    end
    pcall(fs.SetFont, fs, path, size, flags or "")
end

-- Cache default Font object metrics for reset
local defaultHeaderFont, defaultHeaderSize, defaultHeaderFlag
local defaultBodyFont, defaultBodySize, defaultBodyFlag
local function CacheDefaultFontMetrics()
    if defaultHeaderFont then return end
    if GameTooltipHeaderText then
        defaultHeaderFont, defaultHeaderSize, defaultHeaderFlag = GameTooltipHeaderText:GetFont()
    end
    if GameTooltipText then
        defaultBodyFont, defaultBodySize, defaultBodyFlag = GameTooltipText:GetFont()
    end
end

-- Apply font size via Font objects for GameTooltip (taint-safe).
-- Modifying the Font object propagates to derived FontStrings without
-- tainting them individually, so GetStringWidth() remains non-secret.
local function ApplyFontSizeViaFontObjects(size)
    CacheDefaultFontMetrics()
    local headerSize = size + 2
    if GameTooltipHeaderText and defaultHeaderFont then
        local _, curSize = GameTooltipHeaderText:GetFont()
        if not curSize or math.abs(curSize - headerSize) >= 0.5 then
            GameTooltipHeaderText:SetFont(defaultHeaderFont, headerSize, defaultHeaderFlag or "")
        end
    end
    if GameTooltipText and defaultBodyFont then
        local _, curSize = GameTooltipText:GetFont()
        if not curSize or math.abs(curSize - size) >= 0.5 then
            GameTooltipText:SetFont(defaultBodyFont, size, defaultBodyFlag or "")
        end
    end
end

local function ApplyFontSize(tooltip)
    if not tooltip then return end
    local base = GetEffectiveFontSize()

    -- GameTooltip: use Font-object-level sizing to avoid tainting FontStrings
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

    -- Fallback: iterate regions
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

---------------------------------------------------------------------------
-- State Tables
---------------------------------------------------------------------------

local styleFrames = Helpers.CreateStateTable()   -- tooltip → chrome frame
local hookedTooltips = Helpers.CreateStateTable() -- tooltip → true
local hookedNineSlices = Helpers.CreateStateTable() -- NineSlice → true
local pendingGameTooltipRestyle = false           -- deferred restyle for GameTooltip
local suppressNSHook = false                      -- suppress NineSlice hook during intentional re-show

---------------------------------------------------------------------------
-- NineSlice Management
---------------------------------------------------------------------------

local function HideNineSlice(tooltip)
    local ns = tooltip.NineSlice
    if not ns then return end
    pcall(ns.Hide, ns)
    -- Drop NineSlice below the tooltip's frame level so that even if
    -- Blizzard briefly re-shows it (before our hook re-hides it), its
    -- textures render behind QUI's overlay at the tooltip's own level.
    pcall(ns.SetFrameLevel, ns, 0)
    -- TAINT SAFETY: Do NOT write to ns.layoutType / ns.layoutTextureKit /
    -- ns.backdropInfo from addon code.  Writing nil here taints those keys;
    -- the taint persists across Show() cycles and can propagate into
    -- Blizzard's widget-layout code (LayoutFrame.lua GetExtents), causing
    -- "attempt to compare a secret number value" errors when the tainted
    -- execution context makes GetScaledRect() return secret values.
    -- NineSliceUtil.ApplyLayout already overwrites these keys from secure
    -- code before reading them, so the nil write is unnecessary.  Hiding
    -- the NineSlice frame (C-side Hide above) is sufficient; QUI's
    -- SharedTooltip_SetBackdropStyle hook re-hides it on every restyle.
    -- Do NOT call SetAlpha(0) here — it can propagate taint into
    -- Blizzard's layout code, making GetWidth() return secret values
    -- even after combat ends.
end

-- Hook NineSlice:Show() directly so that ANY Blizzard code path that
-- re-shows NineSlice (not just SharedTooltip_SetBackdropStyle) is caught
-- and immediately reversed.  C-side Hide/Show/SetFrameLevel do not taint,
-- so this is safe even inside a secure call stack.
local function HookNineSlice(tooltip)
    local ns = tooltip and tooltip.NineSlice
    if not ns or hookedNineSlices[ns] then return end
    hookedNineSlices[ns] = true

    hooksecurefunc(ns, "Show", function(self)
        if suppressNSHook then return end
        if not IsEnabled() then return end

        pcall(self.Hide, self)
        pcall(self.SetFrameLevel, self, 0)

        local sf = styleFrames[tooltip]
        if sf then pcall(sf.Show, sf) end
    end)
end

---------------------------------------------------------------------------
-- Style Frame
---------------------------------------------------------------------------

local function HideStyleFrame(tooltip)
    local frame = tooltip and styleFrames[tooltip]
    if frame then frame:Hide() end
end

local function FallbackToNineSlice(tooltip)
    suppressNSHook = true
    local ns = tooltip and tooltip.NineSlice
    if ns then pcall(ns.Show, ns) end
    suppressNSHook = false
    HideStyleFrame(tooltip)
end

local function HasAccessibleDimensions(tooltip)
    if not tooltip then return false end
    local okWidth, width = pcall(tooltip.GetWidth, tooltip)
    if not okWidth or type(width) ~= "number" or (issecretvalue and issecretvalue(width)) then
        return false
    end
    local okHeight, height = pcall(tooltip.GetHeight, tooltip)
    if not okHeight or type(height) ~= "number" or (issecretvalue and issecretvalue(height)) then
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
    frame.bg = UIKit.CreateBackground(frame, 0.05, 0.05, 0.05, 0.95)
    UIKit.CreateBorderLines(frame)

    styleFrames[tooltip] = frame
    return frame
end

-- Is this tooltip embedded inside a visible parent tooltip?
local function IsEmbedded(tooltip)
    local ok, parent = pcall(tooltip.GetParent, tooltip)
    if not ok or not parent then return false end
    local visible = parent.IsShown and parent:IsShown()
    return visible
        and (tooltip.IsEmbedded
            or (parent.NineSlice and parent ~= UIParent and parent ~= WorldFrame))
end

---------------------------------------------------------------------------
-- Skin Application
---------------------------------------------------------------------------

local function ApplyTooltipChrome(tooltip)
    if not tooltip then return end

    -- Embedded tooltips: strip border, no overlay (parent has one)
    if IsEmbedded(tooltip) then
        HideNineSlice(tooltip)
        if tooltip.SetBackdrop then pcall(tooltip.SetBackdrop, tooltip, nil) end
        HideStyleFrame(tooltip)
        return
    end

    HideNineSlice(tooltip)
    -- Do NOT call tooltip:SetBackdrop(nil) here.  Clearing the tooltip's
    -- own backdrop triggers Blizzard to re-call SharedTooltip_SetBackdropStyle
    -- which re-shows NineSlice and sets pendingGameTooltipRestyle, creating
    -- an infinite per-frame loop.  Our chrome frame at the same frame level
    -- covers the tooltip's own backdrop anyway.

    -- Fall back to NineSlice if dimensions are inaccessible (secret values).
    -- Suppress the NineSlice:Show hook so we don't fight our own fallback.
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

    -- Strip CompareHeader on shopping tooltips
    if tooltip.CompareHeader then
        local h = tooltip.CompareHeader
        if h.SetBackdrop then pcall(h.SetBackdrop, h, nil) end
        if h.NineSlice then pcall(h.NineSlice.Hide, h.NineSlice) end
    end
end

local function StyleTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    pcall(function()
        ApplyTooltipChrome(tooltip)
    end)
end

-- Combat-safe: refresh addon-owned chrome without touching Blizzard's backdrop.
local function CombatRefreshTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    pcall(function()
        ApplyTooltipChrome(tooltip)
    end)
end

-- Quest/world map reward tooltips can attach Blizzard MoneyFrame children to
-- GameTooltip. Mutating the tooltip frame while those children are active can
-- taint MoneyFrame_Update width arithmetic.
local function HasActiveMoneyFrame(tooltip)
    if not tooltip or not tooltip.GetChildren then return false end

    local ok, result = pcall(function()
        for i = 1, select("#", tooltip:GetChildren()) do
            local child = select(i, tooltip:GetChildren())
            if child then
                local childName = child.GetName and child:GetName() or nil
                if child.moneyType ~= nil or child.staticMoney ~= nil or child.lastArgMoney ~= nil or
                    (type(childName) == "string" and childName:find("MoneyFrame")) then
                    if child.IsShown then
                        local okShown, shown = pcall(child.IsShown, child)
                        if not okShown or shown then
                            return true
                        end
                    else
                        return true
                    end
                end
            end
        end
        return false
    end)

    return ok and result == true
end

local function HasActiveWidgetContainer(tooltip)
    if not tooltip or not tooltip.GetChildren then return false end

    local ok, result = pcall(function()
        for i = 1, select("#", tooltip:GetChildren()) do
            local child = select(i, tooltip:GetChildren())
            if child and (child.RegisterForWidgetSet or child.shownWidgetCount ~= nil or child.widgetSetID ~= nil) then
                local widgetSetID = child.widgetSetID
                if widgetSetID ~= nil then
                    return true
                end

                local shownWidgetCount = child.shownWidgetCount
                if shownWidgetCount ~= nil then
                    if Helpers.IsSecretValue(shownWidgetCount) then
                        return true
                    end
                    shownWidgetCount = tonumber(shownWidgetCount)
                    if shownWidgetCount and shownWidgetCount > 0 then
                        return true
                    end
                end

                local numWidgetsShowing = child.numWidgetsShowing
                if numWidgetsShowing ~= nil then
                    if Helpers.IsSecretValue(numWidgetsShowing) then
                        return true
                    end
                    numWidgetsShowing = tonumber(numWidgetsShowing)
                    if numWidgetsShowing and numWidgetsShowing > 0 then
                        return true
                    end
                end

                if child.IsShown and child:IsShown() then
                    return true
                end
            end
        end
        return false
    end)

    return ok and result == true
end

local function RefreshTooltipLayout(tooltip)
    if not tooltip or not (tooltip.IsShown and tooltip:IsShown()) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    if tooltip == GameTooltip then
        if HasActiveMoneyFrame(tooltip) or HasActiveWidgetContainer(tooltip) then
            return
        end
    end

    if type(tooltip.UpdateTooltipSize) == "function" then
        pcall(tooltip.UpdateTooltipSize, tooltip)
    end
end

-- Dispatch: combat vs normal path
local function OnTooltipShow(tooltip)
    if not IsEnabled() then return end
    -- MoneyFrame children can taint tooltip width arithmetic on some Blizzard
    -- GameTooltip update paths, so keep the conservative show-existing-chrome path.
    if tooltip == GameTooltip and HasActiveMoneyFrame(tooltip) then
        pcall(function()
            HideNineSlice(tooltip)
            local sf = styleFrames[tooltip]
            if sf then sf:Show() end
        end)
        return
    end
    if InCombatLockdown() then
        CombatRefreshTooltip(tooltip)
    else
        StyleTooltip(tooltip)
    end
end

---------------------------------------------------------------------------
-- Tooltip Lists
---------------------------------------------------------------------------

local gameTooltipFamily = {
    "GameTooltip", "ItemRefTooltip",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
    "ShoppingTooltip1", "ShoppingTooltip2",
    "GameTooltipTooltip", "SmallTextTooltip",
    "ReputationParagonTooltip", "NamePlateTooltip",
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
        -- NamePlateTooltip excluded (causes taint)
        if name ~= "NamePlateTooltip" then
            tooltipsToSkin[#tooltipsToSkin + 1] = name
        end
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

---------------------------------------------------------------------------
-- Hooking
---------------------------------------------------------------------------

-- Forward-declare so upvalues are captured by functions defined below
local SafeHookTooltipOnShow, HookTooltipOnShow

-- Pre-allocated callback tables to avoid closure allocation in C_Timer.After
local _pendingHookQueue = {}
local function _FlushHookQueue()
    for i = 1, #_pendingHookQueue do
        local tt = _pendingHookQueue[i]
        _pendingHookQueue[i] = nil
        if tt then HookTooltipOnShow(tt) end
    end
end

local _pendingFontSet = {}
local function _FlushPendingFonts()
    for tt in pairs(_pendingFontSet) do
        _pendingFontSet[tt] = nil
        if tt.IsShown and tt:IsShown() and not InCombatLockdown() then
            pcall(ApplyFontSize, tt)
            RefreshTooltipLayout(tt)
        end
    end
end

SafeHookTooltipOnShow = function(tooltip)
    if hookedTooltips[tooltip] then return end
    if InCombatLockdown() then
        _pendingHookQueue[#_pendingHookQueue + 1] = tooltip
        C_Timer.After(0, _FlushHookQueue)
    else
        HookTooltipOnShow(tooltip)
    end
end

-- Detect protected/forbidden tooltip context (world map secure code, etc.).
-- When the tooltip is owned by a protected frame, addon styling would taint
-- the execution context.  Fall back to NineSlice in these cases.
local function IsProtectedTooltip(tip)
    if not tip then return true end
    if tip.IsForbidden and tip:IsForbidden() then return true end
    local owner = tip.GetOwner and tip:GetOwner()
    if not owner then return false end
    local current = owner
    for _ = 1, 10 do
        if not current then break end
        if current.IsForbidden and current:IsForbidden() then return true end
        local ok, parent = pcall(current.GetParent, current)
        current = ok and parent or nil
    end
    return false
end

HookTooltipOnShow = function(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end

    -- GameTooltip: use HookScript("OnShow"/"OnHide") with protected-
    -- tooltip detection.  OnShow fires before the first render, so
    -- NineSlice is hidden before the user ever sees it — no 1-frame flash.
    -- Protected tooltips (world map, AreaPoiUtil) fall back to NineSlice
    -- to avoid tainting Blizzard's secure execution context.
    if tooltip == GameTooltip then
        hookedTooltips[tooltip] = true
        HookNineSlice(tooltip)

        -- TAINT SAFETY: Must use hooksecurefunc, NOT HookScript("OnShow").
        -- HookScript runs addon code INSIDE the Show() call, tainting the
        -- caller's execution context.  When secure callers (AreaPoiUtil,
        -- etc.) do Show() then AddWidgetSet() in one Lua stack, the taint
        -- propagates into widget processing — GetStringHeight() returns
        -- secret values and UIWidgetTemplateTextWithState:Setup() errors.
        -- hooksecurefunc runs in a separate taint bubble that does NOT
        -- propagate back, while still firing before the next rendered frame
        -- (no 1-frame NineSlice flash).
        hooksecurefunc(tooltip, "Show", function(self)
            if not IsEnabled() then
                FallbackToNineSlice(self)
                return
            end
            HideNineSlice(self)
            local sf = styleFrames[self]
            if sf then pcall(sf.Show, sf) end
            pendingGameTooltipRestyle = true
        end)

        return
    end

    hooksecurefunc(tooltip, "Show", function(self)
        if not IsEnabled() then
            FallbackToNineSlice(self)
            return
        end

        -- Synchronous: hide NineSlice + apply overlay (no 1-frame flash)
        if InCombatLockdown() then
            CombatRefreshTooltip(self)
            return
        end

        -- Skip if already styled — prevents the same restyle loop that
        -- affects GameTooltip (StyleTooltip side-effects can re-trigger
        -- SharedTooltip_SetBackdropStyle → Show hook → StyleTooltip).
        local _ns = self.NineSlice
        local _sf = styleFrames[self]
        if _sf and _sf:IsShown() and (not _ns or not _ns:IsShown()) then
            return
        end

        StyleTooltip(self)
        -- Defer font sizing out of the securecall chain to avoid tainting
        -- tooltip width calculations
        _pendingFontSet[self] = true
        C_Timer.After(0, _FlushPendingFonts)
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
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    SafeHookTooltipOnShow(tooltip)
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

---------------------------------------------------------------------------
-- Backdrop Style Hooks (Blizzard re-applies styles on show/restyle)
---------------------------------------------------------------------------

local function SetupBackdropStyleHooks()
    if SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip, style, isEmbedded)
            if not IsEnabled() or not tooltip then return end
            local ok, objType = pcall(tooltip.GetObjectType, tooltip)
            if not ok or objType ~= "GameTooltip" then return end

            -- TAINT SAFETY: Defer GameTooltip styling to the watcher's
            -- OnUpdate to avoid modifying frame properties during the
            -- synchronous show chain.  Callers (AreaPoiUtil, etc.) call
            -- SharedTooltip_SetBackdropStyle → Show() → AddWidgetSet in
            -- one Lua stack; any addon property writes here taint the
            -- execution context, causing secret-value errors in the
            -- widget layout's GetExtents / GetScaledRect calls.
            if tooltip == GameTooltip then
                -- Immediately suppress NineSlice and show existing overlay
                -- to prevent 1-frame flash.  These are C-side calls (no Lua
                -- property writes) so they do not taint the caller's context.
                HideNineSlice(tooltip)
                local sf = styleFrames[tooltip]
                if sf then sf:Show() end
                pendingGameTooltipRestyle = true
                return
            end

            if isEmbedded or tooltip.IsEmbedded then
                HideNineSlice(tooltip)
                if tooltip.SetBackdrop then pcall(tooltip.SetBackdrop, tooltip, nil) end
                local sf = styleFrames[tooltip]
                if sf then sf:Hide() end
            else
                -- Skip if already styled (same guard as GameTooltip watcher)
                local _ns2 = tooltip.NineSlice
                local _sf2 = styleFrames[tooltip]
                if not (_sf2 and _sf2:IsShown() and (not _ns2 or not _ns2:IsShown())) then
                    OnTooltipShow(tooltip)
                end
                SafeHookTooltipOnShow(tooltip)
            end
        end)
    end

    -- Blizzard can call this directly, bypassing SharedTooltip
    if GameTooltip_SetBackdropStyle then
        hooksecurefunc("GameTooltip_SetBackdropStyle", function(tooltip, style)
            if not IsEnabled() or not tooltip then return end
            local ok, objType = pcall(tooltip.GetObjectType, tooltip)
            if not ok or objType ~= "GameTooltip" then return end
            -- Defer GameTooltip — same taint safety concern as above.
            if tooltip == GameTooltip then
                HideNineSlice(tooltip)
                local sf = styleFrames[tooltip]
                if sf then sf:Show() end
                pendingGameTooltipRestyle = true
                return
            end
            local _ns3 = tooltip.NineSlice
            local _sf3 = styleFrames[tooltip]
            if not (_sf3 and _sf3:IsShown() and (not _ns3 or not _ns3:IsShown())) then
                OnTooltipShow(tooltip)
            end
            SafeHookTooltipOnShow(tooltip)
        end)
    end

    -- EmbeddedItemTooltip: lives inside GameTooltip for world quest rewards
    -- but also shows standalone (objective tracker)
    if EmbeddedItemTooltip then
        hooksecurefunc(EmbeddedItemTooltip, "Show", function(self)
            if not IsEnabled() then return end
            if IsEmbedded(self) then
                HideNineSlice(self)
                if self.SetBackdrop then pcall(self.SetBackdrop, self, nil) end
                local sf = styleFrames[self]
                if sf then sf:Hide() end
            else
                OnTooltipShow(self)
            end
        end)
        -- Initial strip for embedded context
        if IsEnabled() then
            HideNineSlice(EmbeddedItemTooltip)
            if EmbeddedItemTooltip.SetBackdrop then
                pcall(EmbeddedItemTooltip.SetBackdrop, EmbeddedItemTooltip, nil)
            end
        end
    end

    -- GameTooltip.ItemTooltip NineSlice
    if GameTooltip and GameTooltip.ItemTooltip and GameTooltip.ItemTooltip.NineSlice then
        hooksecurefunc(GameTooltip.ItemTooltip, "Show", function(self)
            if not IsEnabled() then return end
            if self.NineSlice then pcall(self.NineSlice.Hide, self.NineSlice) end
        end)
    end
end

---------------------------------------------------------------------------
-- TooltipDataProcessor
---------------------------------------------------------------------------

local function SetupPostProcessor()
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then return end

    local function DeferFont(tooltip)
        if not IsEnabled() then return end
        _pendingFontSet[tooltip] = true
        C_Timer.After(0, _FlushPendingFonts)
    end

    local function HandlePostCall(tooltip)
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        SafeHookTooltipOnShow(tooltip)
        -- TAINT SAFETY: Defer GameTooltip to the watcher (same as backdrop hooks).
        if tooltip == GameTooltip then
            HideNineSlice(tooltip)
            local sf = styleFrames[tooltip]
            if sf then sf:Show() end
            pendingGameTooltipRestyle = true
            return
        end
        if InCombatLockdown() then
            CombatRefreshTooltip(tooltip)
        else
            DeferFont(tooltip)
            if IsEnabled() then StyleTooltip(tooltip) end
        end
    end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, HandlePostCall)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, HandlePostCall)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        HandlePostCall(tooltip)
        -- Health bar hiding (independent of skinning)
        if ShouldHideHealthBar() and tooltip and not InCombatLockdown() then
            local bar = tooltip.StatusBar or (tooltip == GameTooltip and GameTooltipStatusBar)
            if bar and not (bar.IsForbidden and bar:IsForbidden()) then
                Helpers.SafeHide(bar)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Health Bar
---------------------------------------------------------------------------

local function SetupHealthBarHook()
    if not GameTooltip then return end
    local bar = GameTooltip.StatusBar or GameTooltipStatusBar
    if not bar then return end
    hooksecurefunc(bar, "Show", function(self)
        if InCombatLockdown() then return end
        if ShouldHideHealthBar() then Helpers.SafeHide(self) end
    end)
end

---------------------------------------------------------------------------
-- Refresh Functions (called from settings UI)
---------------------------------------------------------------------------

local function RefreshAllColors()
    if InCombatLockdown() then return end
    -- Re-style all visible tooltips
    for tooltip in pairs(styleFrames) do
        if tooltip.IsShown and tooltip:IsShown() then
            StyleTooltip(tooltip)
        end
    end
    -- Handle embedded tooltip
    if EmbeddedItemTooltip and IsEnabled() and IsEmbedded(EmbeddedItemTooltip) then
        HideNineSlice(EmbeddedItemTooltip)
        if EmbeddedItemTooltip.SetBackdrop then
            pcall(EmbeddedItemTooltip.SetBackdrop, EmbeddedItemTooltip, nil)
        end
    end
end

local function RefreshAllFonts()
    if InCombatLockdown() then return end
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip then
            ApplyFontSize(tooltip)
            RefreshTooltipLayout(tooltip)
        end
    end
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local initialized = false
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    -- After initialization, discover addon tooltips on each ADDON_LOADED
    if event == "ADDON_LOADED" and initialized then
        if not InCombatLockdown() then DiscoverExtraTooltips() end
        return
    end

    -- Post-combat: restore full tooltip styling and deferred font/layout sync.
    if event == "PLAYER_REGEN_ENABLED" then
        _FlushHookQueue()
        pendingGameTooltipRestyle = false
        if IsEnabled() then
            -- Full restyle of all visible tooltips (both named and dynamic)
            for _, name in ipairs(tooltipsToSkin) do
                local tooltip = _G[name]
                if tooltip and tooltip.IsShown and tooltip:IsShown() then
                    StyleTooltip(tooltip)
                end
            end
            for tooltip in pairs(styleFrames) do
                if tooltip.IsShown and tooltip:IsShown() then
                    StyleTooltip(tooltip)
                end
            end
            RefreshAllFonts()
        end
        DiscoverExtraTooltips()
        return
    end

    if event ~= "ADDON_LOADED" or arg1 ~= ADDON_NAME then return end

    RebuildTooltipList()

    -------------------------------------------------------------------
    -- GameTooltip deferred-restyle handler.
    -- The OnShow HookScript handles initial show styling.  This frame
    -- processes pendingGameTooltipRestyle from SharedTooltip hooks
    -- (backdrop restyles that fire AFTER our OnShow has already run).
    -------------------------------------------------------------------
    do
        local fontsApplied = false
        local wasShown = false
        local deferFrame = CreateFrame("Frame")
        deferFrame:SetScript("OnUpdate", function()
            -- TAINT SAFETY: Detect GameTooltip hide via IsShown() polling
            -- instead of HookScript("OnHide").  HookScript runs addon code
            -- inside the secure execution context, tainting the caller
            -- (e.g. QuestMapLogTitleButton_OnEnter → SetOwner → OnHide).
            -- That taint makes GetStringWidth() return secret values,
            -- breaking Blizzard's tooltip width arithmetic in combat.
            local shown = GameTooltip:IsShown()
            if wasShown and not shown then
                fontsApplied = false
                pendingGameTooltipRestyle = false
            end
            wasShown = shown

            if not pendingGameTooltipRestyle then return end
            pendingGameTooltipRestyle = false

            if not shown then
                fontsApplied = false
                return
            end

            -- If skinning was disabled mid-show, restore NineSlice.
            if not IsEnabled() then
                FallbackToNineSlice(GameTooltip)
                fontsApplied = false
                return
            end

            -- Always re-suppress NineSlice — Blizzard may have re-shown it
            -- through a code path our SharedTooltip hook didn't catch.
            HideNineSlice(GameTooltip)

            local _sf = styleFrames[GameTooltip]
            if not (_sf and _sf:IsShown()) then
                if not IsProtectedTooltip(GameTooltip) then
                    OnTooltipShow(GameTooltip)
                end
            end

            -- Font sizing: once per show cycle
            if not fontsApplied then
                fontsApplied = true
                _pendingFontSet[GameTooltip] = true
                C_Timer.After(0, function()
                    _FlushPendingFonts()
                    if not GameTooltip:IsShown() then return end
                    for i = 1, 2 do
                        local st = _G["ShoppingTooltip" .. i]
                        if st and st:IsShown() then
                            SafeHookTooltipOnShow(st)
                            OnTooltipShow(st)
                        end
                    end
                end)
            end
        end)

        -- Hide-state reset is handled by the wasShown transition check
        -- above.  Do NOT use HookScript("OnHide") — it taints the secure
        -- execution context of callers like QuestMapLogTitleButton_OnEnter.
    end

    -- Hook + initial skin
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
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    initialized = true
end)

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

ns.QUI_RefreshTooltipSkinColors = RefreshAllColors
ns.QUI_RefreshTooltipFontSize = RefreshAllFonts

