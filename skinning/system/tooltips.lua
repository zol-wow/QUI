local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local GetCore = Helpers.GetCore
local issecretvalue = issecretvalue

---------------------------------------------------------------------------
-- TOOLTIP SKINNING
-- Hides Blizzard's NineSlice via :Hide(), renders a QUI-owned
-- BackdropTemplate overlay. Falls back to NineSlice when styling fails
-- (combat secret values, forbidden frames, errors).
---------------------------------------------------------------------------

local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8x8"

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
-- NOTE: Do NOT modify shared global font objects (GameTooltipText, etc.).
-- Blizzard's UIWidget templates inherit their FontStrings from these.
-- Font sizing is applied per-tooltip via ApplyFontSize() instead.
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
    local ok, path, _, flags = pcall(fs.GetFont, fs)
    if not ok or not path then
        path = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
        flags = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
    end
    pcall(fs.SetFont, fs, path, size, flags or "")
end

local function ApplyFontSize(tooltip)
    if not tooltip then return end
    local base = GetEffectiveFontSize()
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

local styleFrames = Helpers.CreateStateTable()   -- tooltip → overlay frame
local hookedTooltips = Helpers.CreateStateTable() -- tooltip → true
local pendingGameTooltipRestyle = false           -- deferred restyle for GameTooltip

---------------------------------------------------------------------------
-- NineSlice Management
---------------------------------------------------------------------------

local function HideNineSlice(tooltip)
    local ns = tooltip.NineSlice
    if not ns then return end
    pcall(ns.Hide, ns)
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
end

---------------------------------------------------------------------------
-- Style Frame
---------------------------------------------------------------------------

local function GetStyleFrame(tooltip)
    local frame = styleFrames[tooltip]
    if frame then return frame end

    frame = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
    frame:SetAllPoints()
    frame.ignoreInLayout = true
    if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(true) end
    if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end

    -- Guard backdrop methods against secret-value arithmetic in combat.
    -- The C engine fires OnBackdropSizeChanged as a cached script handler,
    -- bypassing Lua table overrides. But self:SetupTextureCoordinates() and
    -- self:SetupPieceVisuals() inside it use normal Lua method dispatch, so
    -- overriding these on the frame instance intercepts the error path.
    local origSetupTexCoords = frame.SetupTextureCoordinates
    local origSetupVisuals = frame.SetupPieceVisuals
    if origSetupTexCoords then
        frame.SetupTextureCoordinates = function(self)
            if issecretvalue then
                local ok, w = pcall(self.GetWidth, self)
                if not ok or issecretvalue(w) then return end
            end
            return origSetupTexCoords(self)
        end
    end
    if origSetupVisuals then
        frame.SetupPieceVisuals = function(self)
            if issecretvalue then
                local ok, w = pcall(self.GetWidth, self)
                if not ok or issecretvalue(w) then return end
            end
            return origSetupVisuals(self)
        end
    end

    -- Re-apply colors after piece recreation on resize (SetupPieceVisuals
    -- creates pieces with raw WHITE8x8 color, losing stored colors).
    -- Use HookScript to run after the C-dispatched handler completes.
    pcall(frame.HookScript, frame, "OnBackdropSizeChanged", function(self)
        if issecretvalue then
            local ok, w = pcall(self.GetWidth, self)
            if not ok or issecretvalue(w) then return end
        end
        if self.backdropColor then
            pcall(self.SetBackdropColor, self, self.backdropColor:GetRGBA())
        end
        if self.backdropBorderColor then
            pcall(self.SetBackdropBorderColor, self, self.backdropBorderColor:GetRGBA())
        end
    end)

    -- Mark as QUI-owned for global OnBackdropSizeChanged fallback
    frame._quiBgR = 0.05

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

local function StyleTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    pcall(function()
        -- Embedded tooltips: strip border, no overlay (parent has one)
        if IsEmbedded(tooltip) then
            HideNineSlice(tooltip)
            if tooltip.SetBackdrop then pcall(tooltip.SetBackdrop, tooltip, nil) end
            local sf = styleFrames[tooltip]
            if sf then sf:Hide() end
            return
        end

        HideNineSlice(tooltip)
        -- Clear any backdrop on the tooltip frame itself (some tooltips have
        -- both NineSlice AND BackdropTemplate, creating a doubled border)
        if tooltip.SetBackdrop then pcall(tooltip.SetBackdrop, tooltip, nil) end

        -- Fall back to NineSlice if dimensions are inaccessible (secret values)
        local dimOk = pcall(function() local _ = tooltip:GetWidth() + 0 end)
        if not dimOk then
            local ns = tooltip.NineSlice
            if ns then pcall(ns.Show, ns) end
            local sf = styleFrames[tooltip]
            if sf then sf:Hide() end
            return
        end

        -- Create/get overlay and apply backdrop
        local frame = GetStyleFrame(tooltip)
        local ok, level = pcall(tooltip.GetFrameLevel, tooltip)
        if ok and type(level) == "number" then frame:SetFrameLevel(level) end

        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
        local thickness = GetEffectiveBorderThickness()
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = math.max(thickness, 1) * px

        -- Only re-set backdrop when edge size changes (avoids piece recreation)
        if frame._lastEdge ~= edge or not frame.backdropInfo then
            frame:SetBackdrop({
                bgFile = FLAT_TEXTURE, edgeFile = FLAT_TEXTURE,
                edgeSize = edge,
                insets = { left = edge, right = edge, top = edge, bottom = edge },
            })
            frame._lastEdge = edge
        end

        frame:SetBackdropColor(bgr, bgg, bgb, bga)
        frame:SetBackdropBorderColor(sr, sg, sb, sa)
        -- Store for global OnBackdropSizeChanged fallback
        frame._quiBgR = bgr or 0.05
        frame._quiBgG = bgg or 0.05
        frame._quiBgB = bgb or 0.05
        frame._quiBgA = bga or 0.95
        frame._quiBorderR = sr or 0
        frame._quiBorderG = sg or 0
        frame._quiBorderB = sb or 0
        frame._quiBorderA = sa or 1
        frame:Show()

        -- Strip CompareHeader on shopping tooltips
        if tooltip.CompareHeader then
            local h = tooltip.CompareHeader
            if h.SetBackdrop then pcall(h.SetBackdrop, h, nil) end
            if h.NineSlice then pcall(h.NineSlice.Hide, h.NineSlice) end
        end
    end)
end

-- Combat-safe: re-hide NineSlice and refresh colors on addon-owned overlay.
-- All operations are C-side or target addon-owned frames (never taint-restricted).
local function CombatRefreshTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    pcall(function()
        HideNineSlice(tooltip)

        local frame = styleFrames[tooltip]
        if not frame then
            -- First encounter in combat: create overlay (addon-owned, always safe)
            frame = GetStyleFrame(tooltip)
            local ok, level = pcall(tooltip.GetFrameLevel, tooltip)
            if ok and type(level) == "number"
                and not (issecretvalue and issecretvalue(level)) then
                frame:SetFrameLevel(level)
            end
            local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
            local edge = math.max(GetEffectiveBorderThickness(), 1)
            frame:SetBackdrop({
                bgFile = FLAT_TEXTURE, edgeFile = FLAT_TEXTURE,
                edgeSize = edge,
                insets = { left = edge, right = edge, top = edge, bottom = edge },
            })
            frame._lastEdge = edge
            frame:SetBackdropColor(bgr, bgg, bgb, bga)
            frame:SetBackdropBorderColor(sr, sg, sb, sa)
            frame._quiBgR = bgr or 0.05
        else
            -- Existing overlay: just refresh colors
            local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
            frame:SetBackdropColor(bgr, bgg, bgb, bga)
            frame:SetBackdropBorderColor(sr, sg, sb, sa)
        end
        frame:Show()
    end)
end

-- Dispatch: combat vs normal path
local function OnTooltipShow(tooltip)
    if not IsEnabled() then return end
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

HookTooltipOnShow = function(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end

    -- TAINT SAFETY: Never hook GameTooltip's Show method directly.
    -- In Midnight's taint model, hooksecurefunc(GameTooltip, "Show") taints
    -- the frame's dispatch table, causing ADDON_ACTION_BLOCKED errors when
    -- the world map's secure context uses GameTooltip. A separate watcher
    -- frame handles GameTooltip instead (see initialization below).
    if tooltip == GameTooltip then
        hookedTooltips[tooltip] = true
        return
    end

    hooksecurefunc(tooltip, "Show", function(self)
        if not IsEnabled() then return end

        -- Synchronous: hide NineSlice + apply overlay (no 1-frame flash)
        if InCombatLockdown() then
            CombatRefreshTooltip(self)
            return
        end

        StyleTooltip(self)
        -- Defer font sizing out of the securecall chain to avoid tainting
        -- tooltip width calculations
        _pendingFontSet[self] = true
        C_Timer.After(0, _FlushPendingFonts)
    end)

    hookedTooltips[tooltip] = true
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
            if not (tooltip.GetObjectType and tooltip:GetObjectType() == "GameTooltip") then return end

            -- TAINT SAFETY: Defer GameTooltip styling to the watcher's
            -- OnUpdate to avoid modifying frame properties during the
            -- synchronous show chain.  Callers (AreaPoiUtil, etc.) call
            -- SharedTooltip_SetBackdropStyle → Show() → AddWidgetSet in
            -- one Lua stack; any addon property writes here taint the
            -- execution context, causing secret-value errors in the
            -- widget layout's GetExtents / GetScaledRect calls.
            if tooltip == GameTooltip then
                pendingGameTooltipRestyle = true
                -- gtWatcher runs continuously; just setting the flag is sufficient
                return
            end

            if isEmbedded or tooltip.IsEmbedded then
                HideNineSlice(tooltip)
                if tooltip.SetBackdrop then pcall(tooltip.SetBackdrop, tooltip, nil) end
                local sf = styleFrames[tooltip]
                if sf then sf:Hide() end
            else
                OnTooltipShow(tooltip)
                SafeHookTooltipOnShow(tooltip)
            end
        end)
    end

    -- Blizzard can call this directly, bypassing SharedTooltip
    if GameTooltip_SetBackdropStyle then
        hooksecurefunc("GameTooltip_SetBackdropStyle", function(tooltip, style)
            if not IsEnabled() or not tooltip then return end
            if not (tooltip.GetObjectType and tooltip:GetObjectType() == "GameTooltip") then return end
            -- Defer GameTooltip — same taint safety concern as above.
            if tooltip == GameTooltip then
                pendingGameTooltipRestyle = true
                -- gtWatcher runs continuously; just setting the flag is sufficient
                return
            end
            OnTooltipShow(tooltip)
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
    -- Clear edge cache to force backdrop recreation on next style
    for _, frame in pairs(styleFrames) do
        if frame then frame._lastEdge = nil end
    end
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
        if tooltip then ApplyFontSize(tooltip) end
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

    if event ~= "ADDON_LOADED" or arg1 ~= ADDON_NAME then return end

    RebuildTooltipList()

    -------------------------------------------------------------------
    -- GameTooltip watcher (separate frame — no hooks on GT directly)
    --
    -- TAINT SAFETY: Do NOT use HookScript("OnShow"/"OnHide") or
    -- hooksecurefunc(GameTooltip, "Show") on GameTooltip.  In
    -- Midnight's taint model, any HookScript on GameTooltip permanently
    -- taints its dispatch tables, causing secret-value errors when the
    -- world map's secure context uses GameTooltip (AreaPoiUtil,
    -- QuestOfferDataProvider, GameTooltip_InsertFrame, etc.).
    -- Instead, a continuously-running watcher detects visibility
    -- changes by polling IsShown() every frame.
    -------------------------------------------------------------------
    do
        local wasShown = false
        local watcher = CreateFrame("Frame")
        -- Watcher runs continuously — no HookScript on GameTooltip.
        watcher:SetScript("OnUpdate", function()
            -- Handle deferred restyle from SharedTooltip_SetBackdropStyle /
            -- GameTooltip_SetBackdropStyle hooks (taint safety).
            if pendingGameTooltipRestyle then
                pendingGameTooltipRestyle = false
                local isShown = GameTooltip:IsShown()
                if isShown then
                    OnTooltipShow(GameTooltip)
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
                -- Sync wasShown so the initial-show branch below doesn't
                -- fire again and duplicate the styling we just applied.
                wasShown = isShown
                return
            end

            local shown = GameTooltip:IsShown()
            if shown == wasShown then return end
            wasShown = shown
            if not shown then
                pendingGameTooltipRestyle = false
                return
            end

            -- GameTooltip just became visible
            OnTooltipShow(GameTooltip)
            _pendingFontSet[GameTooltip] = true
            C_Timer.After(0, function()
                _FlushPendingFonts()
                if not GameTooltip:IsShown() then return end
                -- Discover comparison tooltips (lazily created by C-side)
                for i = 1, 2 do
                    local st = _G["ShoppingTooltip" .. i]
                    if st and st:IsShown() then
                        SafeHookTooltipOnShow(st)
                        OnTooltipShow(st)
                    end
                end
            end)
        end)
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
    initialized = true
end)

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

ns.QUI_RefreshTooltipSkinColors = RefreshAllColors
ns.QUI_RefreshTooltipFontSize = RefreshAllFonts
