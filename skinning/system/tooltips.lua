local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local GetCore = Helpers.GetCore
local issecretvalue = issecretvalue

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
local gameTooltipRestyleFrame
local gameTooltipRestyleOnUpdate
local gameTooltipRestyleActive = false
local gameTooltipShowToken = 0
local gameTooltipFontToken = 0
local suppressNSHook = false                      -- suppress NineSlice hook during intentional re-show

local function QueueGameTooltipRestyle()
    if pendingGameTooltipRestyle then
        TooltipDebugCount("skin.restyleCoalesced")
        if gameTooltipRestyleFrame and gameTooltipRestyleOnUpdate and not gameTooltipRestyleActive then
            gameTooltipRestyleActive = true
            gameTooltipRestyleFrame:SetScript("OnUpdate", gameTooltipRestyleOnUpdate)
        end
        return
    end

    TooltipDebugCount("skin.restyleQueued")
    pendingGameTooltipRestyle = true
    if gameTooltipRestyleFrame and gameTooltipRestyleOnUpdate and not gameTooltipRestyleActive then
        gameTooltipRestyleActive = true
        gameTooltipRestyleFrame:SetScript("OnUpdate", gameTooltipRestyleOnUpdate)
    end
end

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
    TooltipDebugCount("skin.applyChrome")

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

    -- Re-fit chrome to actual content extents on every show. GameTooltip is
    -- a single Lua object reused across player/NPC/object hovers, so any
    -- extend offsets cached from a prior show (e.g. player Target/M+ Rating
    -- pushing the chrome 61px down) must be re-evaluated for the new content,
    -- otherwise NPC/object tooltips display chrome much larger than needed.
    -- For tooltips that fit inside their reported rect, this resolves to
    -- extend = 0 and re-anchors the chrome flush with the tooltip.
    local refit = ns.QUI_RefitTooltipChromeToContent
    if refit then
        pcall(refit, tooltip)
    end
end

local function StyleTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    TooltipDebugCount("skin.style")
    local dbg, dbgStart, dbgHeap = TooltipDebugBegin()
    pcall(ApplyTooltipChrome, tooltip)
    TooltipDebugEnd(dbg, "skin.style", dbgStart, nil, dbgHeap)
end

-- Combat-safe: refresh addon-owned chrome without touching Blizzard's backdrop.
local function CombatRefreshTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    TooltipDebugCount("skin.combatRefresh")
    local dbg, dbgStart, dbgHeap = TooltipDebugBegin()
    pcall(ApplyTooltipChrome, tooltip)
    TooltipDebugEnd(dbg, "skin.combatRefresh", dbgStart, nil, dbgHeap)
end

-- Quest/world map reward tooltips can attach Blizzard MoneyFrame children to
-- GameTooltip. Mutating the tooltip frame while those children are active can
-- taint MoneyFrame_Update width arithmetic.
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

local function HasActiveWidgetContainer(tooltip)
    if not tooltip or not tooltip.GetChildren or not tooltip.GetNumChildren then return false end
    TooltipDebugCount("skin.widgetScan")

    local okCount, numChildren = pcall(tooltip.GetNumChildren, tooltip)
    if not okCount or not numChildren then return false end

    for i = 1, numChildren do
        local child = select(i, tooltip:GetChildren())
        if child and (child.RegisterForWidgetSet or child.shownWidgetCount ~= nil or child.widgetSetID ~= nil) then
            local widgetSetID = child.widgetSetID
            if widgetSetID ~= nil then
                TooltipDebugCount("skin.widgetHit")
                return true
            end

            local shownWidgetCount = child.shownWidgetCount
            if shownWidgetCount ~= nil then
                if Helpers.IsSecretValue(shownWidgetCount) then
                    TooltipDebugCount("skin.widgetHit")
                    return true
                end
                shownWidgetCount = tonumber(shownWidgetCount)
                if shownWidgetCount and shownWidgetCount > 0 then
                    TooltipDebugCount("skin.widgetHit")
                    return true
                end
            end

            local numWidgetsShowing = child.numWidgetsShowing
            if numWidgetsShowing ~= nil then
                if Helpers.IsSecretValue(numWidgetsShowing) then
                    TooltipDebugCount("skin.widgetHit")
                    return true
                end
                numWidgetsShowing = tonumber(numWidgetsShowing)
                if numWidgetsShowing and numWidgetsShowing > 0 then
                    TooltipDebugCount("skin.widgetHit")
                    return true
                end
            end

            if child.IsShown then
                local okShown, shown = pcall(child.IsShown, child)
                if okShown and shown then
                    TooltipDebugCount("skin.widgetHit")
                    return true
                end
            end
        end
    end

    return false
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
        pcall(ShowExistingChrome, tooltip)
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
local _pendingHookTimerActive = false
local function _FlushHookQueue()
    _pendingHookTimerActive = false
    for i = 1, #_pendingHookQueue do
        local tt = _pendingHookQueue[i]
        _pendingHookQueue[i] = nil
        if tt then HookTooltipOnShow(tt) end
    end
end

local _pendingFontSet = {}
local _pendingFontTimerActive = false
local function _FlushPendingFonts()
    TooltipDebugCount("skin.fontFlush")
    _pendingFontTimerActive = false
    for tt in pairs(_pendingFontSet) do
        _pendingFontSet[tt] = nil
        if tt.IsShown and tt:IsShown() and not InCombatLockdown() then
            pcall(ApplyFontSize, tt)
            RefreshTooltipLayout(tt)
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

SafeHookTooltipOnShow = function(tooltip)
    if hookedTooltips[tooltip] then return end
    if InCombatLockdown() then
        _pendingHookQueue[#_pendingHookQueue + 1] = tooltip
        if not _pendingHookTimerActive then
            _pendingHookTimerActive = true
            C_Timer.After(0, _FlushHookQueue)
        end
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
            TooltipDebugCount("skin.gameTooltipShow")
            gameTooltipShowToken = gameTooltipShowToken + 1
            if not IsEnabled() then
                FallbackToNineSlice(self)
                return
            end
            ShowExistingChrome(self)
            -- Always queue a restyle, even when ShowExistingChrome found the
            -- chrome already stable. The restyle OnUpdate is the path that
            -- runs RefitChromeToContent once per show cycle, and without it
            -- chrome offsets (extendY/X) cached from the prior tooltip stay
            -- on the new tooltip — making NPC/object tooltips render with
            -- chrome much larger than needed after a player tooltip extended
            -- it for Target/M+ Rating.
            QueueGameTooltipRestyle()
        end)

        return
    end

    hooksecurefunc(tooltip, "Show", function(self)
        TooltipDebugCount("skin.tooltipShow")
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
            TooltipDebugCount("skin.sharedBackdrop")
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
                if IsChromeStable(tooltip) then
                    TooltipDebugCount("skin.backdropStableSkip")
                    return
                end
                -- Quest-reward tooltips (TaskPOI_OnEnter → AddQuestRewardsToTooltip
                -- → SetTooltipMoney → MoneyFrame_Update) are extremely sensitive
                -- to any addon touching the tooltip mid-build.  When a MoneyFrame
                -- child is already attached, skip the restyle entirely so we
                -- don't taint MoneyFrame_Update's width arithmetic.
                if HasActiveMoneyFrame(tooltip) then return end
                -- Immediately suppress NineSlice and show existing overlay
                -- to prevent 1-frame flash.  These are C-side calls (no Lua
                -- property writes) so they do not taint the caller's context.
                if ShowExistingChrome(tooltip) then
                    QueueGameTooltipRestyle()
                end
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
            TooltipDebugCount("skin.gameBackdrop")
            if not IsEnabled() or not tooltip then return end
            local ok, objType = pcall(tooltip.GetObjectType, tooltip)
            if not ok or objType ~= "GameTooltip" then return end
            -- Defer GameTooltip — same taint safety concern as above.
            if tooltip == GameTooltip then
                if IsChromeStable(tooltip) then
                    TooltipDebugCount("skin.backdropStableSkip")
                    return
                end
                -- Quest-reward MoneyFrame mid-build: bail to avoid tainting
                -- MoneyFrame_Update's width arithmetic.
                if HasActiveMoneyFrame(tooltip) then return end
                if ShowExistingChrome(tooltip) then
                    QueueGameTooltipRestyle()
                end
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
                -- World-quest reward path: GameTooltip is mid-build with a
                -- MoneyFrame child.  Mutating the embedded child's backdrop
                -- here can taint MoneyFrame_Update's width arithmetic.
                if HasActiveMoneyFrame(GameTooltip) then return end
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
        QueueFontUpdate(tooltip)
    end

    local function HandlePostCall(tooltip)
        TooltipDebugCount("skin.postCall")
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        SafeHookTooltipOnShow(tooltip)
        -- TAINT SAFETY: Defer GameTooltip to the watcher (same as backdrop hooks).
        if tooltip == GameTooltip then
            if IsChromeStable(tooltip) then
                TooltipDebugCount("skin.postStableSkip")
                return
            end
            TooltipDebugCount("skin.postGameTooltip")
            -- Quest-reward MoneyFrame mid-build: bail to avoid tainting
            -- MoneyFrame_Update's width arithmetic.
            if HasActiveMoneyFrame(tooltip) then return end
            if ShowExistingChrome(tooltip) then
                QueueGameTooltipRestyle()
            end
            return
        end
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
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        RunHandlePostCall(tooltip)
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
        if not (tooltip.IsForbidden and tooltip:IsForbidden())
            and tooltip.IsShown and tooltip:IsShown() then
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

local pendingShoppingTooltipSync = false
local function FlushShoppingTooltipSync()
    TooltipDebugCount("skin.shoppingFlush")
    pendingShoppingTooltipSync = false
    if not GameTooltip:IsShown() then return end
    for i = 1, 2 do
        local st = _G["ShoppingTooltip" .. i]
        if st and st:IsShown() then
            SafeHookTooltipOnShow(st)
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
        gameTooltipRestyleActive = false
        if gameTooltipRestyleFrame then
            gameTooltipRestyleFrame:SetScript("OnUpdate", nil)
        end
        if IsEnabled() then
            -- Full restyle of all visible tooltips (both named and dynamic)
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

    if event ~= "ADDON_LOADED" or arg1 ~= ADDON_NAME then return end

    RebuildTooltipList()

    -------------------------------------------------------------------
    -- GameTooltip deferred-restyle handler.
    -- The Show hook handles initial show styling. This frame processes
    -- queued backdrop restyles outside the synchronous tooltip build.
    -------------------------------------------------------------------
    do
        gameTooltipRestyleFrame = CreateFrame("Frame")
        gameTooltipRestyleOnUpdate = function(self)
            TooltipDebugCount("skin.restyleTick")
            local dbg, dbgStart, dbgHeap = TooltipDebugBegin()
            gameTooltipRestyleActive = false
            self:SetScript("OnUpdate", nil)

            if not pendingGameTooltipRestyle then
                TooltipDebugEnd(dbg, "skin.restyleTick", dbgStart, "idle", dbgHeap)
                return
            end
            pendingGameTooltipRestyle = false
            TooltipDebugCount("skin.restyleRun")

            local shown = GameTooltip:IsShown()
            if not shown then
                pendingShoppingTooltipSync = false
                TooltipDebugEnd(dbg, "skin.restyleTick", dbgStart, "hidden", dbgHeap)
                return
            end

            -- If skinning was disabled mid-show, restore NineSlice.
            if not IsEnabled() then
                FallbackToNineSlice(GameTooltip)
                TooltipDebugEnd(dbg, "skin.restyleTick", dbgStart, "disabled", dbgHeap)
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
            if gameTooltipFontToken ~= gameTooltipShowToken then
                gameTooltipFontToken = gameTooltipShowToken
                QueueFontUpdate(GameTooltip)
                QueueShoppingTooltipSync()
            end

            -- Re-fit chrome to the actual rendered FontString extents on every
            -- show cycle. ApplyTooltipChrome only runs when chrome is hidden
            -- (avoiding flicker), so the chrome's extendY/X anchors carried
            -- over from the prior tooltip stay until something explicitly
            -- recomputes them. Running the refit here covers every show,
            -- including the player → NPC transition where chrome was previously
            -- extended for Target/M+ Rating overflow.
            local refit = ns.QUI_RefitTooltipChromeToContent
            if refit then
                pcall(refit, GameTooltip)
            end
            TooltipDebugEnd(dbg, "skin.restyleTick", dbgStart, "run", dbgHeap)
        end
        gameTooltipRestyleFrame:SetScript("OnUpdate", nil)
        if pendingGameTooltipRestyle then
            gameTooltipRestyleActive = true
            gameTooltipRestyleFrame:SetScript("OnUpdate", gameTooltipRestyleOnUpdate)
        end

        -- Do NOT use HookScript("OnHide") here — it taints the secure
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
-- Chrome Refit (post-AddLine extent recovery)
---------------------------------------------------------------------------
-- Midnight's GameTooltip stopped exposing Lua-callable Layout/MarkDirty/
-- UpdateTooltipSize. After AddLine/AddDoubleLine on a shown tooltip, the
-- C-side renders the new FontStrings but the Lua-facing :GetHeight() does
-- not grow. Our chrome (anchored via SetAllPoints) tracks :GetHeight(), so
-- it ends up shorter than the actual rendered extent — exposing Blizzard's
-- backdrop on the appended lines (Target / M+ Rating).
--
-- RefitChromeToContent measures the lowest visible FontString and extends
-- the chrome's bottom anchor below the tooltip's reported bottom by the
-- overflow delta. Called by qol/tooltip after deferred line additions.

-- Walks the tooltip's active line FontStrings and returns:
--   lowestBottom    — lowest visible FontString bottom edge (smallest screen Y)
--   rightmostRight  — rightmost edge of any visible RIGHT-side double-line FontString
--   ttBottom, ttRight
--
-- DIRECTIONAL MEASUREMENT (the result of two false starts):
--
--   Vertical: any visible FontString counts. AddLine on a shown Midnight
--   tooltip doesn't grow GetHeight, so chrome must extend past stale
--   ttBottom to cover appended FontStrings.
--
--   Horizontal: only RIGHT-side FontStrings of double-lines (those with
--   non-empty text) count. LEFT-side FontStrings of wrapping description
--   text return their *natural unwrapped* width (a trinket "Use:" line
--   reports GetRight=2344 while tooltip is rendered at 1317), which once
--   inflated chrome by 1000+px to the right. Right-side FontStrings of
--   double-lines are short non-wrapping text anchored TOPRIGHT to the
--   tooltip — their GetRight is reliable. Empty/hidden right FontStrings
--   on description lines naturally filter out via the IsShown+text check.
--   This catches the QoL case: AddDoubleLine("Mount:", longMountName)
--   appended after Show, where tooltip:GetWidth() doesn't grow on
--   Midnight and the right text spills past the tooltip's reported
--   right edge.
--
-- STALE-STATE SAFETY: Iterate via NumLines+GetLeftLine/GetRightLine
-- (or the named global FontString fallback) instead of GetRegions().
-- GameTooltip pre-allocates FontStrings and reuses them across hovers;
-- a raw GetRegions walk picks up stale FontStrings from previous
-- (taller / wider) tooltips that Blizzard cleared but left IsShown=true.

-- Per-call diagnostics: which line contributed the lowest / rightmost edge.
local _diagWorstBottom, _diagWorstBottomLine, _diagWorstBottomSide, _diagWorstBottomText
local _diagWorstRight, _diagWorstRightLine, _diagWorstRightText

local function MeasureBottom(fs, lowest, lineIndex, side)
    if not fs then return lowest end
    local okShown, shown = pcall(fs.IsShown, fs)
    if not okShown or not shown then return lowest end
    local okB, b = pcall(fs.GetBottom, fs)
    if okB and b and b < lowest then
        lowest = b
        if lineIndex then
            _diagWorstBottom = b
            _diagWorstBottomLine = lineIndex
            _diagWorstBottomSide = side
            local okT, t = pcall(fs.GetText, fs)
            _diagWorstBottomText = (okT and t) or nil
        end
    end
    return lowest
end

-- Right-side measurement: only counts FontStrings with non-empty visible text.
-- This filters out the stale/empty right FontStrings on description-only
-- lines, where Blizzard's NumLines includes the line but the right slot is
-- unused. Their phantom widths would otherwise inflate the chrome.
local function MeasureRightOfDoubleLine(rightFS, rightmost, lineIndex)
    if not rightFS then return rightmost end
    local okShown, shown = pcall(rightFS.IsShown, rightFS)
    if not okShown or not shown then return rightmost end
    local okT, text = pcall(rightFS.GetText, rightFS)
    if not okT or not text or text == "" then return rightmost end
    local okR, rx = pcall(rightFS.GetRight, rightFS)
    if okR and rx and rx > rightmost then
        rightmost = rx
        if lineIndex then
            _diagWorstRight = rx
            _diagWorstRightLine = lineIndex
            _diagWorstRightText = text
        end
    end
    return rightmost
end

local function FindContentExtents(tooltip)
    if not tooltip then return nil end
    local okBottom, ttBottom = pcall(tooltip.GetBottom, tooltip)
    if not okBottom or not ttBottom then return nil end
    local okRight, ttRight = pcall(tooltip.GetRight, tooltip)
    if not okRight or not ttRight then return nil end
    local lowestBottom = ttBottom
    local rightmostRight = ttRight

    _diagWorstBottom, _diagWorstBottomLine, _diagWorstBottomSide, _diagWorstBottomText = nil, nil, nil, nil
    _diagWorstRight, _diagWorstRightLine, _diagWorstRightText = nil, nil, nil

    if tooltip.NumLines then
        local okCount, count = pcall(tooltip.NumLines, tooltip)
        if okCount and count and count > 0 then
            local hasGetters = tooltip.GetLeftLine and tooltip.GetRightLine
            local name
            if not hasGetters and tooltip.GetName then
                local okName, n = pcall(tooltip.GetName, tooltip)
                if okName then name = n end
            end
            for i = 1, count do
                local left, right
                if hasGetters then
                    left = tooltip:GetLeftLine(i)
                    right = tooltip:GetRightLine(i)
                elseif name then
                    left = _G[name .. "TextLeft" .. i]
                    right = _G[name .. "TextRight" .. i]
                end
                lowestBottom = MeasureBottom(left, lowestBottom, i, "L")
                lowestBottom = MeasureBottom(right, lowestBottom, i, "R")
                rightmostRight = MeasureRightOfDoubleLine(right, rightmostRight, i)
            end
            return lowestBottom, rightmostRight, ttBottom, ttRight
        end
    end

    -- Fallback for specialized tooltips without a NumLines API.  These are
    -- not GameTooltip-style reused frames, so stale FontString carryover is
    -- not a concern. Bottom only — without NumLines we can't reliably
    -- distinguish left from right FontStrings.
    if not tooltip.GetNumRegions then return nil end
    local okCount2, count2 = pcall(tooltip.GetNumRegions, tooltip)
    if not okCount2 or not count2 then return nil end
    for i = 1, count2 do
        local r = select(i, tooltip:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then
            lowestBottom = MeasureBottom(r, lowestBottom, i, "?")
        end
    end
    return lowestBottom, rightmostRight, ttBottom, ttRight
end

local function RefitChromeToContent(tooltip)
    if not tooltip or not IsEnabled() then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    local frame = styleFrames[tooltip]
    if not frame then return end
    if not (frame.IsShown and frame:IsShown()) then return end

    TooltipDebugCount("skin.refit")

    local lowest, rightmost, ttBottom, ttRight = FindContentExtents(tooltip)
    if not lowest or not ttBottom then
        TooltipDebugCount("skin.refitNoExtents")
        return
    end

    local yOverflow = ttBottom - lowest
    if yOverflow < 0 then yOverflow = 0 end
    local xOverflow = (rightmost or ttRight) - ttRight
    if xOverflow < 0 then xOverflow = 0 end

    -- Add a small inset so the chrome's borders match Blizzard's visual
    -- padding around the last line / right column.
    local extendY = yOverflow > 0 and (yOverflow + 4) or 0
    local extendX = xOverflow > 0 and (xOverflow + 4) or 0

    local dbg = ns.QUI_TooltipDebug
    if dbg and dbg.enabled and (extendY > 6 or extendX > 6) then
        local ttName = "?"
        if tooltip.GetName then
            local okName, n = pcall(tooltip.GetName, tooltip)
            if okName and n then ttName = n end
        end
        local nLines
        if tooltip.NumLines then
            local okN, n = pcall(tooltip.NumLines, tooltip)
            if okN then nLines = n end
        end
        print(string.format(
            "|cff60A5FA[refit]|r %s lines=%s extendY=%.0f extendX=%.0f (ttBottom=%.1f lowest=%.1f ttRight=%.1f rightmost=%.1f)",
            ttName, tostring(nLines), extendY, extendX, ttBottom, lowest, ttRight, rightmost or ttRight))
        if extendY > 6 and _diagWorstBottomLine then
            local txt = _diagWorstBottomText
            if txt and #txt > 40 then txt = txt:sub(1, 40) .. "..." end
            print(string.format(
                "  |cffFF8844worstBottom:|r line %d %s bottom=%.1f text=%q",
                _diagWorstBottomLine,
                tostring(_diagWorstBottomSide or "?"),
                _diagWorstBottom or -1,
                tostring(txt or "")))
        end
        if extendX > 6 and _diagWorstRightLine then
            local txt = _diagWorstRightText
            if txt and #txt > 40 then txt = txt:sub(1, 40) .. "..." end
            print(string.format(
                "  |cffFF8844worstRight:|r line %d R right=%.1f text=%q",
                _diagWorstRightLine,
                _diagWorstRight or -1,
                tostring(txt or "")))
        end
        TooltipDebugCount("skin.refitVisibleExtend")
    elseif extendY == 0 and extendX == 0 then
        TooltipDebugCount("skin.refitNoOverflow")
    else
        TooltipDebugCount("skin.refitTinyOverflow")
    end

    -- Cache so repeat refits with the same extents no-op.
    if frame.qExtendY == extendY and frame.qExtendX == extendX then
        TooltipDebugCount("skin.refitCacheSkip")
        return
    end
    frame.qExtendY = extendY
    frame.qExtendX = extendX
    TooltipDebugCount("skin.refitApplied")

    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, "TOPLEFT", tooltip, "TOPLEFT", 0, 0)
    pcall(frame.SetPoint, frame, "TOPRIGHT", tooltip, "TOPRIGHT", extendX, 0)
    pcall(frame.SetPoint, frame, "BOTTOMLEFT", tooltip, "BOTTOMLEFT", 0, -extendY)
    pcall(frame.SetPoint, frame, "BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", extendX, -extendY)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

ns.QUI_RefreshTooltipSkinColors = RefreshAllColors
ns.QUI_RefreshTooltipFontSize = RefreshAllFonts
ns.QUI_RefitTooltipChromeToContent = RefitChromeToContent

