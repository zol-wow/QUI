---------------------------------------------------------------------------
-- QUI Skinning: Status Tracking Bars (XP, Reputation, Honor, etc.)
-- Styles Blizzard's StatusTrackingBarManager HUD bars to match QUI:
-- configurable fill color, dimensions, backdrop, border, bar text.
---------------------------------------------------------------------------
local _, ns = ...
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local LSM = LibStub("LibSharedMedia-3.0", true)

local FALLBACK_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local managerHooked = false

local function GetGeneralSettings()
    local core = Helpers.GetCore()
    return core and core.db and core.db.profile and core.db.profile.general
end

local function IsModuleEnabled()
    local g = GetGeneralSettings()
    if not g then return false end
    if g.skinStatusTrackingBars == nil then return true end
    return g.skinStatusTrackingBars
end

local function GetModuleSkinColors()
    local g = GetGeneralSettings()
    return SkinBase.GetSkinColors(g, "statusTrackingBars")
end

--- Resolve bar fill RGBA. mode overrides g.statusTrackingBarsBarColorMode when passed.
local function GetBarFillRGBA(g, mode)
    if not g then return 1, 1, 1, 1 end
    mode = mode or g.statusTrackingBarsBarColorMode or "accent"
    if mode == "blizzard" then
        return nil
    end
    if mode == "class" then
        local r, gCol, b = Helpers.GetPlayerClassColor()
        local ctab = g.statusTrackingBarsBarColor
        local a = (type(ctab) == "table" and ctab[4]) or 1
        return r, gCol, b, a
    end
    if mode == "accent" then
        return Helpers.GetSkinAccentColor()
    end
    local c = g.statusTrackingBarsBarColor
    if type(c) ~= "table" then
        return 0.2, 0.5, 1.0, 1.0
    end
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

local function GetBarTextFontPath(g)
    if not g then return Helpers.GetGeneralFont() end
    local name = g.statusTrackingBarsBarTextFont
    if not name or name == "" or name == "__QUI_GLOBAL__" then
        return Helpers.GetGeneralFont()
    end
    if LSM then
        local p = LSM:Fetch("font", name)
        if p then return p end
    end
    return Helpers.GetGeneralFont()
end

local function GetBarTextOutline(g)
    if not g then return Helpers.GetGeneralFontOutline() or "" end
    local o = g.statusTrackingBarsBarTextOutline
    if o == nil or o == "_inherit" then
        return Helpers.GetGeneralFontOutline() or ""
    end
    if o == "_none" or o == "NONE" then
        return ""
    end
    return o
end

--- Hide default art on the StatusBar widget (not the rested / level-up extras on the parent bar).
local function HideStatusBarChrome(statusBar)
    if statusBar.Background then statusBar.Background:SetAlpha(0) end
    if statusBar.Underlay then statusBar.Underlay:SetAlpha(0) end
    if statusBar.Overlay then statusBar.Overlay:SetAlpha(0) end
end

local function ApplyBarDimensions(bar, statusBar)
    if not bar or not statusBar then return end

    local g = GetGeneralSettings()
    local defW = SkinBase.GetFrameData(bar, "quiStbDefSbW")
    local defH = SkinBase.GetFrameData(bar, "quiStbDefSbH")
    if not defW or not defH then return end

    local pct = g.statusTrackingBarsBarWidthPercent
    if pct == nil then pct = 100 end
    pct = math.max(25, math.min(100, pct))
    local scale = pct / 100

    local newW = defW * scale
    local container = bar:GetParent()
    if container and container.GetWidth then
        local cap = container:GetWidth() - 6
        if cap > 0 and newW > cap then
            newW = cap
        end
    end

    local newH = defH
    local hSet = g.statusTrackingBarsBarHeight
    if hSet and hSet > 0 then
        newH = math.min(math.max(hSet, 4), 40)
    end

    statusBar:SetSize(newW, newH)
    bar:SetSize(newW, newH)
end

local function UpdateBackdropLayout(backdrop)
    if not backdrop then return end
    local g = GetGeneralSettings()
    local thick = g and g.statusTrackingBarsBorderThickness
    local px = (thick and thick > 0) and thick or SkinBase.GetPixelSize(backdrop, 1)
    backdrop:SetBackdrop({
        bgFile = FALLBACK_TEXTURE,
        edgeFile = FALLBACK_TEXTURE,
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
end

--- Font, size, outline, color, anchors (does not change visibility).
local function ApplyBarTextStyle(bar)
    if not bar or not bar.OverlayFrame or not bar.OverlayFrame.Text then return end
    local fs = bar.OverlayFrame.Text
    local g = GetGeneralSettings()
    if not g then return end

    local fontPath = GetBarTextFontPath(g)
    local outline = GetBarTextOutline(g)
    local size = g.statusTrackingBarsBarTextFontSize or 11
    size = math.max(6, math.min(24, size))
    fs:SetFont(fontPath, size, outline or "")

    local c = g.statusTrackingBarsBarTextColor
    if type(c) == "table" then
        fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        fs:SetTextColor(0.95, 0.95, 0.95, 1)
    end

    local anchor = g.statusTrackingBarsBarTextAnchor or "CENTER"
    if anchor ~= "LEFT" and anchor ~= "RIGHT" then
        anchor = "CENTER"
    end

    local ox = g.statusTrackingBarsBarTextOffsetX or 0
    local oy = g.statusTrackingBarsBarTextOffsetY or 0

    fs:ClearAllPoints()
    local rel = bar.StatusBar or bar.OverlayFrame
    if rel then
        if anchor == "LEFT" then
            fs:SetPoint("LEFT", rel, "LEFT", 4 + ox, 1 + oy)
            fs:SetJustifyH("LEFT")
        elseif anchor == "RIGHT" then
            fs:SetPoint("RIGHT", rel, "RIGHT", -4 + ox, 1 + oy)
            fs:SetJustifyH("RIGHT")
        else
            fs:SetPoint("CENTER", rel, "CENTER", 0 + ox, 1 + oy)
            fs:SetJustifyH("CENTER")
        end
    end
end

--- After Blizzard's UpdateTextVisibility: enforce hide, or force show when "always".
local function FinalizeBarTextVisibility(bar)
    if not IsModuleEnabled() or not bar then return end
    local g = GetGeneralSettings()
    local fs = bar.OverlayFrame and bar.OverlayFrame.Text
    if not fs then return end

    if not g or g.statusTrackingBarsShowBarText == false then
        fs:Hide()
        return
    end

    if g.statusTrackingBarsBarTextAlways then
        fs:Show()
    end
end

local function SyncBarTextLockedAndVisibility(bar)
    if not bar or not bar.OverlayFrame or not bar.OverlayFrame.Text then return end
    local g = GetGeneralSettings()
    if not g then return end

    ApplyBarTextStyle(bar)

    if not bar.SetTextLocked then
        FinalizeBarTextVisibility(bar)
        return
    end

    if g.statusTrackingBarsShowBarText == false then
        bar:SetTextLocked(false)
        bar:UpdateTextVisibility()
        FinalizeBarTextVisibility(bar)
        return
    end

    if g.statusTrackingBarsBarTextAlways then
        bar:SetTextLocked(true)
    else
        bar:SetTextLocked(false)
    end
    bar:UpdateTextVisibility()
    FinalizeBarTextVisibility(bar)
end

--- Re-apply texture + fill after Blizzard bar:Update() resets colors.
local function RefreshBarFillAndTexture(bar)
    if not IsModuleEnabled() or not bar or not bar.StatusBar then return end

    local statusBar = bar.StatusBar
    local g = GetGeneralSettings()
    local tex = Helpers.GetGeneralTexture and Helpers.GetGeneralTexture() or FALLBACK_TEXTURE
    if tex and statusBar.SetStatusBarTexture then
        statusBar:SetStatusBarTexture(tex)
    end

    local mode = g.statusTrackingBarsBarColorMode or "accent"
    if mode == "blizzard" then
        return
    end

    local r, gFill, b, a = GetBarFillRGBA(g, mode)
    if r and statusBar.SetStatusBarColor then
        statusBar:SetStatusBarColor(r, gFill, b, a or 1)
    end
end

local function HookBarUpdate(bar)
    if not bar or SkinBase.GetFrameData(bar, "quiStbUpdateHooked") then return end
    if type(bar.Update) ~= "function" then return end

    SkinBase.SetFrameData(bar, "quiStbUpdateHooked", true)
    hooksecurefunc(bar, "Update", function(b)
        if not IsModuleEnabled() then return end
        if not SkinBase.GetFrameData(b, "quiStbSkinned") then return end
        C_Timer.After(0, function()
            if b and b.StatusBar and SkinBase.GetFrameData(b, "quiStbSkinned") then
                RefreshBarFillAndTexture(b)
                ApplyBarDimensions(b, b.StatusBar)
                ApplyBarTextStyle(b)
                FinalizeBarTextVisibility(b)
            end
        end)
    end)
end

local function HookBarTextVisibility(bar)
    if not bar or SkinBase.GetFrameData(bar, "quiStbTextVisHooked") then return end
    if type(bar.UpdateTextVisibility) ~= "function" then return end

    SkinBase.SetFrameData(bar, "quiStbTextVisHooked", true)
    hooksecurefunc(bar, "UpdateTextVisibility", function(b)
        FinalizeBarTextVisibility(b)
    end)
end

local function RefreshBarAppearance(bar)
    local statusBar = bar and bar.StatusBar
    if not statusBar then return end

    local backdrop = SkinBase.GetFrameData(bar, "quiStbBackdrop")
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetModuleSkinColors()
    local g = GetGeneralSettings()

    ApplyBarDimensions(bar, statusBar)

    if backdrop then
        UpdateBackdropLayout(backdrop)
        backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        local borderA = sa
        if g and g.statusTrackingBarsShowBorder == false then
            borderA = 0
        end
        backdrop:SetBackdropBorderColor(sr, sg, sb, borderA)
    end

    SyncBarTextLockedAndVisibility(bar)
    RefreshBarFillAndTexture(bar)
end

local function EnsureBarSkinned(bar)
    if not bar or not bar.StatusBar then return end

    local statusBar = bar.StatusBar

    if not SkinBase.GetFrameData(bar, "quiStbDefSbW") then
        SkinBase.SetFrameData(bar, "quiStbDefSbW", statusBar:GetWidth())
        SkinBase.SetFrameData(bar, "quiStbDefSbH", statusBar:GetHeight())
    end

    if SkinBase.GetFrameData(bar, "quiStbSkinned") then
        RefreshBarAppearance(bar)
        HookBarUpdate(bar)
        HookBarTextVisibility(bar)
        return
    end

    HideStatusBarChrome(statusBar)

    if not SkinBase.GetFrameData(bar, "quiStbBackdrop") then
        local backdrop = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        local barLevel = statusBar:GetFrameLevel()
        backdrop:SetFrameLevel(barLevel > 0 and (barLevel - 1) or 0)
        backdrop:SetPoint("TOPLEFT", statusBar, "TOPLEFT", -2, 2)
        backdrop:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 2, -2)
        UpdateBackdropLayout(backdrop)
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(bar, "quiStbBackdrop", backdrop)
    end

    SkinBase.SetFrameData(bar, "quiStbSkinned", true)
    SkinBase.MarkStyled(bar)
    HookBarUpdate(bar)
    HookBarTextVisibility(bar)
    RefreshBarAppearance(bar)
end

local function SkinBarContainer(container)
    if not container then return end

    if container.BarFrameTexture then
        container.BarFrameTexture:SetAlpha(0)
    end

    local bars = container.bars
    if not bars then return end

    for _, bar in pairs(bars) do
        EnsureBarSkinned(bar)
    end
end

local function ApplyAll()
    if not IsModuleEnabled() then return end

    local mgr = _G.StatusTrackingBarManager
    if not mgr or not mgr.barContainers then return end

    for _, container in ipairs(mgr.barContainers) do
        SkinBarContainer(container)
    end
end

local function HookManager()
    if managerHooked then return end
    local mgr = _G.StatusTrackingBarManager
    if not mgr or not mgr.UpdateBarsShown then return end

    managerHooked = true
    hooksecurefunc(mgr, "UpdateBarsShown", function()
        C_Timer.After(0, ApplyAll)
    end)
end

---------------------------------------------------------------------------
-- Live refresh (options / profile change)
---------------------------------------------------------------------------
local function RefreshStatusTrackingBarSkin()
    if not IsModuleEnabled() then return end

    local mgr = _G.StatusTrackingBarManager
    if not mgr or not mgr.barContainers then return end

    for _, container in ipairs(mgr.barContainers) do
        local bars = container.bars
        if bars then
            for _, bar in pairs(bars) do
                if SkinBase.GetFrameData(bar, "quiStbSkinned") then
                    RefreshBarAppearance(bar)
                end
            end
        end
    end
end

_G.QUI_RefreshStatusTrackingBarSkin = RefreshStatusTrackingBarSkin

---------------------------------------------------------------------------
-- Init: Blizzard_ActionBar provides StatusTrackingBarManager
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_ActionBar" then
        C_Timer.After(0.1, function()
            HookManager()
            ApplyAll()
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, ApplyAll)
    end
end)
