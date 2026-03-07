--[[
    QUI CDM Bar Factory

    Creates and manages addon-owned bar frames for the CDM tracked bar system.
    All bars are simple Frame objects with StatusBar children — no protected
    attributes, eliminating combat taint concerns for frame operations.

    Data is mirrored from hidden Blizzard BuffBarCooldownViewer children via
    hooksecurefunc. Blizzard C-side methods (SetValue, SetMinMaxValues, etc.)
    handle secret values natively.

    Pattern mirrors cdm_icons.lua pool management.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMBars = {}
ns.CDMBars = CDMBars

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local MAX_RECYCLE_POOL_SIZE = 20

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local barPool = {}       -- active bars (array)
local recyclePool = {}   -- recycled bars (array, max MAX_RECYCLE_POOL_SIZE)

-- Weak-keyed: Blizzard statusBar → owned bar (handles Blizzard frame recycling)
local mirrorMap = setmetatable({}, { __mode = "k" })

-- Track which Blizzard bar children have been hooked (weak-keyed)
local hookedBars = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- BAR FRAME FACTORY
---------------------------------------------------------------------------
local function CreateBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(200, 25)

    -- StatusBar for duration progress
    local statusBar = CreateFrame("StatusBar", nil, bar)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    bar.StatusBar = statusBar

    -- Background texture (BACKGROUND, sublevel -8)
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0, 0, 0, 1)
    bar.Background = bg

    -- Icon container frame
    local iconContainer = CreateFrame("Frame", nil, bar)
    iconContainer:SetSize(25, 25)
    bar.IconContainer = iconContainer

    -- Icon texture inside container
    local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconContainer)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.IconTexture = iconTex

    -- Border container with 4-edge textures
    local borderFrame = CreateFrame("Frame", nil, bar)
    borderFrame:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 1) + 5)
    borderFrame._top = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._top:SetColorTexture(0, 0, 0, 1)
    borderFrame._bottom = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._bottom:SetColorTexture(0, 0, 0, 1)
    borderFrame._left = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._left:SetColorTexture(0, 0, 0, 1)
    borderFrame._right = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._right:SetColorTexture(0, 0, 0, 1)
    bar.BorderContainer = borderFrame

    -- Text overlay frame (renders above StatusBar fill texture)
    local textOverlay = CreateFrame("Frame", nil, statusBar)
    textOverlay:SetAllPoints(statusBar)
    textOverlay:SetFrameLevel((statusBar.GetFrameLevel and statusBar:GetFrameLevel() or 1) + 2)
    bar.TextOverlay = textOverlay

    -- Name text (spell name)
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    nameText:SetFont(GetGeneralFont(), 14, GetGeneralFontOutline())
    nameText:SetPoint("LEFT", statusBar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetShadowOffset(1, -1)
    bar.NameText = nameText

    -- Duration text (remaining time)
    local durationText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    durationText:SetFont(GetGeneralFont(), 14, GetGeneralFontOutline())
    durationText:SetPoint("RIGHT", statusBar, "RIGHT", -4, 0)
    durationText:SetJustifyH("RIGHT")
    durationText:SetTextColor(1, 1, 1, 1)
    durationText:SetShadowColor(0, 0, 0, 1)
    durationText:SetShadowOffset(1, -1)
    bar.DurationText = durationText

    -- State tracking
    bar._spellEntry = nil
    bar._blizzBar = nil
    bar._spellID = nil
    bar._active = false

    bar:Hide()
    return bar
end

---------------------------------------------------------------------------
-- CONFIGURE BAR (clean rewrite of ApplyBarStyle for owned frames)
---------------------------------------------------------------------------
function CDMBars.ConfigureBar(bar, settings, overrideWidth)
    if not bar then return end

    local barHeight = settings.barHeight or 25
    local barWidth = overrideWidth or settings.barWidth or 215
    local texture = settings.texture or "Quazii v5"
    local useClassColor = settings.useClassColor
    local barColor = settings.barColor or {0.204, 0.827, 0.6, 1}
    local barOpacity = settings.barOpacity or 1.0
    local borderSize = settings.borderSize or 2
    local bgColor = settings.bgColor or {0, 0, 0, 1}
    local bgOpacity = settings.bgOpacity or 0.5
    local textSize = settings.textSize or 14
    local hideIcon = settings.hideIcon
    local hideText = settings.hideText

    -- Inactive visual settings
    local inactiveMode = settings.inactiveMode or "hide"
    if inactiveMode ~= "always" and inactiveMode ~= "fade" and inactiveMode ~= "hide" then
        inactiveMode = "always"
    end
    local inactiveAlpha = settings.inactiveAlpha or 0.3
    if inactiveAlpha < 0 then inactiveAlpha = 0 end
    if inactiveAlpha > 1 then inactiveAlpha = 1 end
    local desaturateInactive = (settings.desaturateInactive == true)

    -- Vertical bar settings
    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local fillDirection = settings.fillDirection or "up"
    local iconPosition = settings.iconPosition or "top"
    local showTextOnVertical = settings.showTextOnVertical or false

    local isActive = bar._active

    -- For vertical bars: swap width/height conceptually
    local frameWidth, frameHeight
    if isVertical then
        frameWidth = barHeight
        frameHeight = barWidth
    else
        frameWidth = barWidth
        frameHeight = barHeight
    end

    -- Set bar dimensions
    bar:SetSize(frameWidth, frameHeight)

    local statusBar = bar.StatusBar
    if statusBar then
        statusBar:SetSize(frameWidth, frameHeight)
        if statusBar.SetOrientation then
            statusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        end
        if isVertical and statusBar.SetReverseFill then
            statusBar:SetReverseFill(fillDirection == "down")
        end
    end

    -- Icon container
    local iconContainer = bar.IconContainer
    if iconContainer then
        if hideIcon then
            iconContainer:Hide()
            iconContainer:SetAlpha(0)
        else
            iconContainer:Show()
            iconContainer:SetAlpha(1)
            local iconSize = isVertical and frameWidth or frameHeight
            iconContainer:SetSize(iconSize, iconSize)

            -- Apply optional desaturation for inactive entries
            if bar.IconTexture and bar.IconTexture.SetDesaturated then
                bar.IconTexture:SetDesaturated((not isActive) and desaturateInactive and inactiveMode ~= "always")
            end
        end
    end

    -- Position statusBar and icon based on orientation
    if statusBar then
        statusBar:ClearAllPoints()
        if isVertical then
            if hideIcon or not iconContainer then
                statusBar:SetAllPoints(bar)
            else
                iconContainer:ClearAllPoints()
                if iconPosition == "bottom" then
                    iconContainer:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
                    statusBar:SetPoint("TOP", bar, "TOP", 0, 0)
                    statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
                    statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
                    statusBar:SetPoint("BOTTOM", iconContainer, "TOP", 0, 0)
                else -- "top" (default)
                    iconContainer:SetPoint("TOP", bar, "TOP", 0, 0)
                    statusBar:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
                    statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
                    statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
                    statusBar:SetPoint("TOP", iconContainer, "BOTTOM", 0, 0)
                end
            end
        else
            if hideIcon or not iconContainer then
                statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
            else
                iconContainer:ClearAllPoints()
                iconContainer:SetPoint("LEFT", bar, "LEFT", 0, 0)
                statusBar:SetPoint("LEFT", iconContainer, "RIGHT", 0, 0)
            end
            statusBar:SetPoint("TOP", bar, "TOP", 0, 0)
            statusBar:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
            statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        end
    end

    -- Apply StatusBar texture
    if statusBar and statusBar.SetStatusBarTexture then
        local texturePath = LSM:Fetch("statusbar", texture) or LSM:Fetch("statusbar", "Quazii v5")
        if texturePath then
            statusBar:SetStatusBarTexture(texturePath)
        end
    end

    -- Apply bar color (class or custom) with opacity
    if statusBar and statusBar.SetStatusBarColor then
        local c = barColor
        if useClassColor then
            local _, class = UnitClass("player")
            local safeClass = Helpers.SafeToString(class, nil)
            local color = safeClass and RAID_CLASS_COLORS[safeClass]
            if color then
                statusBar:SetStatusBarColor(color.r, color.g, color.b, barOpacity)
            else
                statusBar:SetStatusBarColor(c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity)
            end
        else
            statusBar:SetStatusBarColor(c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity)
        end
    end

    -- Background
    local bg = bar.Background
    if bg then
        local bgR, bgG, bgB = bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0
        bg:SetColorTexture(bgR, bgG, bgB, 1)
        if statusBar then
            bg:ClearAllPoints()
            bg:SetAllPoints(statusBar)
        end
        bg:SetAlpha(bgOpacity)
        bg:Show()
    end

    -- Border (4-edge technique)
    local borderFrame = bar.BorderContainer
    if borderFrame then
        if borderSize > 0 then
            borderFrame:ClearAllPoints()
            borderFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -borderSize, borderSize)
            borderFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", borderSize, -borderSize)

            borderFrame._top:ClearAllPoints()
            borderFrame._top:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
            borderFrame._top:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
            borderFrame._top:SetHeight(borderSize)

            borderFrame._bottom:ClearAllPoints()
            borderFrame._bottom:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
            borderFrame._bottom:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
            borderFrame._bottom:SetHeight(borderSize)

            borderFrame._left:ClearAllPoints()
            borderFrame._left:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
            borderFrame._left:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
            borderFrame._left:SetWidth(borderSize)

            borderFrame._right:ClearAllPoints()
            borderFrame._right:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
            borderFrame._right:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
            borderFrame._right:SetWidth(borderSize)

            borderFrame:Show()
        else
            borderFrame:Hide()
        end
    end

    -- Text
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()
    local showText = not hideText and (not isVertical or showTextOnVertical)

    if bar.NameText then
        bar.NameText:SetFont(generalFont, textSize, generalOutline)
        bar.NameText:SetAlpha(showText and 1 or 0)
    end
    if bar.DurationText then
        bar.DurationText:SetFont(generalFont, textSize, generalOutline)
        bar.DurationText:SetAlpha(showText and 1 or 0)
    end

    -- Apply frame alpha based on active state
    local targetAlpha = 1
    if not isActive then
        if inactiveMode == "fade" then
            targetAlpha = inactiveAlpha
        elseif inactiveMode == "hide" then
            targetAlpha = 0
        end
    end
    bar:SetAlpha(targetAlpha)
end

---------------------------------------------------------------------------
-- SPELL ID EXTRACTION: Get spellID from a Blizzard bar child via
-- cooldownInfo, cooldownID + C_CooldownViewer API, or name lookup.
---------------------------------------------------------------------------
local function ExtractSpellID(blizzBarChild)
    if not blizzBarChild then return nil end

    -- 1. Direct cooldownInfo (same property icons use)
    local cdInfo = blizzBarChild.cooldownInfo
    if cdInfo then
        local override = SafeToNumber(cdInfo.overrideSpellID, nil)
        if override then return override end
        local spell = SafeToNumber(cdInfo.spellID, nil)
        if spell then return spell end
    end

    -- 2. cooldownID + C_CooldownViewer API
    local cdID = blizzBarChild.cooldownID
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info then
            local override = SafeToNumber(info.overrideSpellID, nil)
            if override then return override end
            local spell = SafeToNumber(info.spellID, nil)
            if spell then return spell end
        end
    end

    -- 3. Name-based lookup: read name from bar FontStrings, look up spellID
    local function GetBarName(frame)
        if not frame or not frame.GetRegions then return nil end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and region:GetObjectType() == "FontString" then
                local okT, text = pcall(region.GetText, region)
                if okT and type(text) == "string" and text ~= "" then
                    local justify = region:GetJustifyH()
                    if justify ~= "RIGHT" then return text end
                end
            end
        end
        return nil
    end
    local name = GetBarName(blizzBarChild) or GetBarName(blizzBarChild.Bar)
    if name and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and info and info.spellID then
            return info.spellID
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- ACTIVE STATE: Check if a Blizzard bar child is active.
-- Blizzard calls Show/Hide on bar children even when the viewer is alpha=0,
-- so IsShown() is a reliable signal for active state.
---------------------------------------------------------------------------
local function CheckBarActive(blizzBarChild)
    if not blizzBarChild then return false end
    local ok, shown = pcall(blizzBarChild.IsShown, blizzBarChild)
    return ok and shown or false
end

---------------------------------------------------------------------------
-- MIRROR BLIZZARD BAR DATA → OWNED BAR
-- Uses hooksecurefunc to forward data from hidden Blizzard bar children.
-- C-side StatusBar methods handle secret values natively.
---------------------------------------------------------------------------
local function MirrorBlizzBar(ownedBar, blizzBarChild)
    if not blizzBarChild then return end
    if hookedBars[blizzBarChild] then
        -- Already hooked — just update the mapping and resync initial state
        mirrorMap[blizzBarChild] = ownedBar
        -- Resync current state since the owned bar is new (from pool rebuild)
        local blizzStatusBar = blizzBarChild.Bar
        if blizzStatusBar then
            local ok1, minVal, maxVal = pcall(blizzStatusBar.GetMinMaxValues, blizzStatusBar)
            if ok1 then
                pcall(ownedBar.StatusBar.SetMinMaxValues, ownedBar.StatusBar, minVal, maxVal)
            end
            local ok2, val = pcall(blizzStatusBar.GetValue, blizzStatusBar)
            if ok2 then
                pcall(ownedBar.StatusBar.SetValue, ownedBar.StatusBar, val)
            end
        end
        -- Resync icon texture
        local blizzIcon = blizzBarChild.Icon
        local blizzIconTex = blizzIcon and (blizzIcon.Icon or blizzIcon.icon or blizzIcon.texture)
        if blizzIconTex then
            local ok, currentTex = pcall(blizzIconTex.GetTexture, blizzIconTex)
            if ok and currentTex then
                pcall(ownedBar.IconTexture.SetTexture, ownedBar.IconTexture, currentTex)
            end
        end
        return
    end
    hookedBars[blizzBarChild] = true
    mirrorMap[blizzBarChild] = ownedBar

    -- Active state is tracked via CheckBarActive(IsShown()) in BuildBars,
    -- called on every Refresh cycle. No Show/Hide hooks on Blizzard frames
    -- needed — avoids tainting Blizzard's secure execution context during
    -- Edit Mode frame iteration.

    -- Hook StatusBar value/range forwarding
    local blizzStatusBar = blizzBarChild.Bar
    if blizzStatusBar then
        -- Mirror SetValue: forward progress to owned StatusBar
        hooksecurefunc(blizzStatusBar, "SetValue", function(self, value)
            local target = mirrorMap[blizzBarChild]
            if not target then return end
            -- Forward value to owned StatusBar (C-side handles secret values)
            pcall(target.StatusBar.SetValue, target.StatusBar, value)
        end)

        -- Mirror SetMinMaxValues
        hooksecurefunc(blizzStatusBar, "SetMinMaxValues", function(self, minVal, maxVal)
            local target = mirrorMap[blizzBarChild]
            if not target then return end
            pcall(target.StatusBar.SetMinMaxValues, target.StatusBar, minVal, maxVal)
        end)
    end

    -- Hook icon texture (SetTexture and SetAtlas)
    local blizzIcon = blizzBarChild.Icon
    local blizzIconTex = blizzIcon and (blizzIcon.Icon or blizzIcon.icon or blizzIcon.texture)
    if blizzIconTex then
        if blizzIconTex.SetTexture then
            hooksecurefunc(blizzIconTex, "SetTexture", function(self, tex)
                local target = mirrorMap[blizzBarChild]
                if not target or not target.IconTexture then return end
                pcall(target.IconTexture.SetTexture, target.IconTexture, tex)
            end)
        end
        if blizzIconTex.SetAtlas then
            hooksecurefunc(blizzIconTex, "SetAtlas", function(self, atlas)
                local target = mirrorMap[blizzBarChild]
                if not target or not target.IconTexture then return end
                pcall(target.IconTexture.SetAtlas, target.IconTexture, atlas)
            end)
        end
        -- Initial texture copy
        local ok, currentTex = pcall(blizzIconTex.GetTexture, blizzIconTex)
        if ok and currentTex then
            pcall(ownedBar.IconTexture.SetTexture, ownedBar.IconTexture, currentTex)
        end
    end

    -- Hook text: Blizzard bar children have .Name and .Duration FontString
    -- properties on sub-children. Both FontStrings can be LEFT-justified so
    -- we identify them by reference identity, not justify direction.
    local hookedFontStrings = {}  -- track to avoid double-hooking
    local knownNameFS = {}        -- FontStrings identified as spell name
    local knownDurationFS = {}    -- FontStrings identified as duration

    -- Discover .Name and .Duration FontString references from all frames
    local function DiscoverNamedFontStrings(frame)
        if not frame then return end
        if frame.Name and type(frame.Name) == "table"
            and frame.Name.GetObjectType and frame.Name:GetObjectType() == "FontString" then
            knownNameFS[frame.Name] = true
        end
        if frame.Duration and type(frame.Duration) == "table"
            and frame.Duration.GetObjectType and frame.Duration:GetObjectType() == "FontString" then
            knownDurationFS[frame.Duration] = true
        end
    end

    -- Discover from bar child, .Bar, and all sub-children first
    DiscoverNamedFontStrings(blizzBarChild)
    if blizzStatusBar then
        DiscoverNamedFontStrings(blizzStatusBar)
    end
    if blizzBarChild.GetChildren then
        for _, subChild in ipairs({ blizzBarChild:GetChildren() }) do
            DiscoverNamedFontStrings(subChild)
        end
    end

    local function ForwardText(fs, text)
        local target = mirrorMap[blizzBarChild]
        if not target then return end
        if knownDurationFS[fs] then
            pcall(target.DurationText.SetText, target.DurationText, text or "")
        elseif knownNameFS[fs] then
            pcall(target.NameText.SetText, target.NameText, text or "")
        else
            -- Fallback: use justify for unknown FontStrings
            local justify = fs:GetJustifyH()
            if justify == "RIGHT" then
                pcall(target.DurationText.SetText, target.DurationText, text or "")
            else
                pcall(target.NameText.SetText, target.NameText, text or "")
            end
        end
    end

    local function HookFontString(fs)
        if hookedFontStrings[fs] then return end
        hookedFontStrings[fs] = true

        hooksecurefunc(fs, "SetText", function(self, text)
            ForwardText(self, text)
        end)
        if fs.SetFormattedText then
            hooksecurefunc(fs, "SetFormattedText", function(self, fmt, ...)
                local okT, finalText = pcall(self.GetText, self)
                if okT then
                    ForwardText(self, finalText)
                end
            end)
        end
        -- Initial text copy
        local ok, text = pcall(fs.GetText, fs)
        if ok and text then
            ForwardText(fs, text)
        end
    end

    -- Hook all FontString regions on a frame
    local function HookFrameRegions(frame)
        if not frame or not frame.GetRegions then return end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and region:GetObjectType() == "FontString" then
                HookFontString(region)
            end
        end
    end

    -- Hook bar child, .Bar, and all sub-children
    HookFrameRegions(blizzBarChild)
    if blizzStatusBar then
        HookFrameRegions(blizzStatusBar)
    end
    if blizzBarChild.GetChildren then
        for _, subChild in ipairs({ blizzBarChild:GetChildren() }) do
            HookFrameRegions(subChild)
        end
    end

    -- Initial value sync (C-side forwarding, handles secret values)
    if blizzStatusBar then
        local ok1, minVal, maxVal = pcall(blizzStatusBar.GetMinMaxValues, blizzStatusBar)
        if ok1 then
            pcall(ownedBar.StatusBar.SetMinMaxValues, ownedBar.StatusBar, minVal, maxVal)
        end
        local ok2, val = pcall(blizzStatusBar.GetValue, blizzStatusBar)
        if ok2 then
            pcall(ownedBar.StatusBar.SetValue, ownedBar.StatusBar, val)
        end
    end
end

---------------------------------------------------------------------------
-- POOL MANAGEMENT
---------------------------------------------------------------------------
local function AcquireBar(parent)
    local bar
    if #recyclePool > 0 then
        bar = table.remove(recyclePool)
        bar:SetParent(parent)
    else
        bar = CreateBar(parent)
    end
    bar:Show()
    barPool[#barPool + 1] = bar
    return bar
end

local function ReleaseBar(bar)
    bar:Hide()
    bar:ClearAllPoints()
    bar._spellEntry = nil
    bar._blizzBar = nil
    bar._spellID = nil
    bar._active = false
    bar.NameText:SetText("")
    bar.DurationText:SetText("")
    bar.IconTexture:SetTexture(nil)
    bar.StatusBar:SetValue(0)

    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        recyclePool[#recyclePool + 1] = bar
    end
end

function CDMBars:ClearPool()
    for i = #barPool, 1, -1 do
        ReleaseBar(barPool[i])
        barPool[i] = nil
    end
end

function CDMBars:GetActiveBars()
    return barPool
end

---------------------------------------------------------------------------
-- BUILD BARS: Scan Blizzard BuffBarCooldownViewer children, create owned
-- bars for each, and set up hooks for data mirroring.
---------------------------------------------------------------------------
function CDMBars:BuildBars(container)
    if not container then return end

    local blizzViewer = _G["BuffBarCooldownViewer"]
    if not blizzViewer then return end

    -- Collect Blizzard bar children
    local blizzBars = {}
    local sel = blizzViewer.Selection
    local okc, children = pcall(function()
        return { blizzViewer:GetChildren() }
    end)
    if okc and children then
        for _, child in ipairs(children) do
            if child and child ~= sel and child:IsObjectType("Frame") then
                -- Bar children have a .Bar StatusBar + cooldownID/layoutIndex
                -- Skip Blizzard's empty pool frames (no cooldownID and no layoutIndex)
                if child.Bar and child.Bar.IsObjectType and child.Bar:IsObjectType("StatusBar")
                    and (child.cooldownID or child.layoutIndex) then
                    blizzBars[#blizzBars + 1] = child
                end
            end
        end
    end

    -- Sort by layoutIndex
    table.sort(blizzBars, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)

    -- Check if we need to rebuild: compare blizzard bar count with current pool
    local needsRebuild = (#blizzBars ~= #barPool)
    if not needsRebuild then
        for i, bar in ipairs(barPool) do
            if bar._blizzBar ~= blizzBars[i] then
                needsRebuild = true
                break
            end
        end
    end

    -- Force rebuild if bars are parented to wrong frame (e.g. initial build
    -- happened before owned container existed)
    if not needsRebuild and #barPool > 0 then
        local firstParent = barPool[1]:GetParent()
        if firstParent ~= container then
            needsRebuild = true
        end
    end

    -- No rebuild needed — just update active state from Blizzard IsShown
    if not needsRebuild then
        for _, bar in ipairs(barPool) do
            if bar._blizzBar then
                bar._active = CheckBarActive(bar._blizzBar)
            end
        end
        return
    end

    -- Clear existing pool
    self:ClearPool()

    -- Create owned bars for each Blizzard bar child
    for _, blizzChild in ipairs(blizzBars) do
        local bar = AcquireBar(container)
        bar._blizzBar = blizzChild

        -- Extract spellID for reliable active state detection
        bar._spellID = ExtractSpellID(blizzChild)

        -- Check active state from Blizzard IsShown (reliable even with alpha=0 viewer)
        bar._active = CheckBarActive(blizzChild)

        -- Set up data mirroring hooks
        MirrorBlizzBar(bar, blizzChild)
    end
end

---------------------------------------------------------------------------
-- FORCE ALL ACTIVE: For Edit Mode, force all bars with names visible
-- so the mover overlay shows the full expected area.
---------------------------------------------------------------------------
function CDMBars:ForceAllActive()
    for _, bar in ipairs(barPool) do
        local name = bar.NameText and bar.NameText:GetText()
        if name and name ~= "" then
            bar._active = true
        end
    end
end

---------------------------------------------------------------------------
-- LAYOUT BARS: Pure math positioning, no Blizzard frame interaction.
-- Stacks bars vertically (default) or horizontally (vertical orientation).
---------------------------------------------------------------------------
function CDMBars:LayoutBars(container, settings)
    if not container then return end
    if not settings then return end

    local barHeight = settings.barHeight or 25
    local barWidth = settings.barWidth or 215

    local count = #barPool

    -- Even with 0 bars, set a minimum container size so the Edit Mode
    -- overlay is draggable and visible (not 1x1).
    if count == 0 then
        local orientation = settings.orientation or "horizontal"
        local w, h
        if orientation == "vertical" then
            w, h = barHeight, barWidth
        else
            w, h = barWidth, barHeight
        end
        container:SetSize(w, h)
        if _G.QUI_SetCDMViewerBounds then
            _G.QUI_SetCDMViewerBounds(container, w, h)
        end
        return
    end

    local stylingEnabled = settings.enabled
    local spacing = settings.spacing or 2
    local growFromBottom = (settings.growUp ~= false)
    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local inactiveMode = settings.inactiveMode or "hide"
    local reserveSlotWhenInactive = (settings.reserveSlotWhenInactive == true)

    -- For vertical bars, swap dimensions
    local effectiveBarWidth, effectiveBarHeight
    if isVertical then
        effectiveBarWidth = barHeight
        effectiveBarHeight = barWidth
    else
        effectiveBarWidth = barWidth
        effectiveBarHeight = barHeight
    end

    -- Apply HUD layer priority
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering.buffBar or 5
    local frameLevel = 200
    if QUICore and QUICore.GetHUDFrameLevel then
        frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
    end
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(frameLevel)

    -- Configure and position each bar
    local visibleIndex = 0
    for _, bar in ipairs(barPool) do
        -- Apply styling
        CDMBars.ConfigureBar(bar, settings, barWidth)

        -- Apply strata/level
        bar:SetFrameStrata("MEDIUM")
        bar:SetFrameLevel(frameLevel)
        if bar.StatusBar then
            bar.StatusBar:SetFrameStrata("MEDIUM")
            bar.StatusBar:SetFrameLevel(frameLevel + 1)
        end
        if bar.TextOverlay then
            bar.TextOverlay:SetFrameStrata("MEDIUM")
            bar.TextOverlay:SetFrameLevel(frameLevel + 3)
        end
        if bar.IconContainer then
            bar.IconContainer:SetFrameStrata("MEDIUM")
            bar.IconContainer:SetFrameLevel(frameLevel + 1)
        end

        -- Determine visibility
        local shouldShow = true
        if not bar._active then
            if inactiveMode == "hide" and not reserveSlotWhenInactive then
                shouldShow = false
            end
        end

        if shouldShow then
            bar:ClearAllPoints()
            local offsetIndex = visibleIndex

            if isVertical then
                local x
                if growFromBottom then
                    x = QUICore:PixelRound(offsetIndex * (effectiveBarWidth + spacing))
                    bar:SetPoint("LEFT", container, "LEFT", x, 0)
                else
                    x = QUICore:PixelRound(-offsetIndex * (effectiveBarWidth + spacing))
                    bar:SetPoint("RIGHT", container, "RIGHT", x, 0)
                end
            else
                local y
                if growFromBottom then
                    y = QUICore:PixelRound(offsetIndex * (effectiveBarHeight + spacing))
                    bar:SetPoint("BOTTOM", container, "BOTTOM", 0, y)
                else
                    y = QUICore:PixelRound(-offsetIndex * (effectiveBarHeight + spacing))
                    bar:SetPoint("TOP", container, "TOP", 0, y)
                end
            end

            bar:Show()
            visibleIndex = visibleIndex + 1
        else
            bar:Hide()
        end
    end

    -- Set container size from calculated bounds
    local totalW, totalH
    if visibleIndex == 0 then
        -- All bars hidden by inactiveMode — use settings dimensions so
        -- the container (and Edit Mode overlay) stays a reasonable size.
        totalW = effectiveBarWidth
        totalH = effectiveBarHeight
    elseif isVertical then
        totalW = (visibleIndex * effectiveBarWidth) + ((visibleIndex - 1) * spacing)
        totalH = effectiveBarHeight
    else
        totalW = effectiveBarWidth
        totalH = (visibleIndex * effectiveBarHeight) + ((visibleIndex - 1) * spacing)
    end
    totalW = QUICore:PixelRound(totalW)
    totalH = QUICore:PixelRound(totalH)
    container:SetSize(totalW, totalH)

    -- Write calculated dimensions to viewer state for proxy sizing
    if _G.QUI_SetCDMViewerBounds then
        _G.QUI_SetCDMViewerBounds(container, totalW, totalH)
    end
end

---------------------------------------------------------------------------
-- REFRESH: Rebuild + re-layout (called from buffbar.lua)
---------------------------------------------------------------------------
function CDMBars:Refresh(container, settings, overrideWidth)
    if not container then return end
    if not settings then return end

    -- Update barWidth if autoWidth provides an override
    if overrideWidth then
        settings = setmetatable({ barWidth = overrideWidth }, { __index = settings })
    end

    self:BuildBars(container)
    self:LayoutBars(container, settings)
end

---------------------------------------------------------------------------
-- DEBUG SLASH COMMAND: /buffbardebug
---------------------------------------------------------------------------
SLASH_BUFFBARDEBUG1 = "/buffbardebug"
local P = "|cff00ccff[BuffBar-Debug]|r"

SlashCmdList["BUFFBARDEBUG"] = function()
    print(P, "=== Owned BuffBar Container Debug ===")

    -- 1. Engine check
    local isOwned = ns.CDMProvider and ns.CDMProvider:GetActiveEngineName() == "owned"
    print(P, "Engine:", isOwned and "owned" or "classic/unknown")

    -- 2. Container state
    local container = ns.CDMContainers and ns.CDMContainers.GetTrackedBarContainer and ns.CDMContainers.GetTrackedBarContainer()
    if container then
        local w, h = container:GetWidth(), container:GetHeight()
        local shown = container:IsShown()
        local alpha = container:GetAlpha()
        local cx, cy = container:GetCenter()
        print(P, "QUI_BuffBarContainer: size=", string.format("%.1fx%.1f", w or 0, h or 0),
            "shown=", tostring(shown), "alpha=", string.format("%.2f", alpha or 0))
        if cx and cy then
            print(P, "  center=", string.format("%.1f, %.1f", cx, cy))
        else
            print(P, "  center= nil (not positioned)")
        end
        print(P, "  numChildren=", container:GetNumChildren())
    else
        print(P, "QUI_BuffBarContainer: NOT FOUND")
    end

    -- 3. GetBuffBarViewer resolution
    local viewerFrame = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffBar")
    if viewerFrame then
        local name = viewerFrame:GetName() or "unnamed"
        local w, h = viewerFrame:GetWidth(), viewerFrame:GetHeight()
        print(P, "GetCDMViewerFrame('buffBar'):", name, "size=", string.format("%.1fx%.1f", w or 0, h or 0))
        print(P, "  isOwnedContainer=", tostring(viewerFrame == container))
    else
        print(P, "GetCDMViewerFrame('buffBar'): nil")
    end

    -- 4. Blizzard BuffBarCooldownViewer
    local blizzViewer = _G["BuffBarCooldownViewer"]
    if blizzViewer then
        local bw, bh = blizzViewer:GetWidth(), blizzViewer:GetHeight()
        local balpha = blizzViewer:GetAlpha()
        local bshown = blizzViewer:IsShown()
        print(P, "Blizzard BuffBarCooldownViewer: size=", string.format("%.1fx%.1f", bw or 0, bh or 0),
            "shown=", tostring(bshown), "alpha=", string.format("%.2f", balpha or 0))

        -- Dump bar children with all available identifiers
        local barCount = 0
        local shownBars = 0
        local sel = blizzViewer.Selection
        for i = 1, blizzViewer:GetNumChildren() do
            local child = select(i, blizzViewer:GetChildren())
            if child and child ~= sel and child:IsObjectType("Frame") then
                if child.Bar and child.Bar.IsObjectType and child.Bar:IsObjectType("StatusBar") then
                    barCount = barCount + 1
                    if child:IsShown() then shownBars = shownBars + 1 end
                    -- Dump identifiers
                    local cdID = child.cooldownID
                    local cdInfo = child.cooldownInfo
                    local spellID = cdInfo and cdInfo.spellID
                    local li = child.layoutIndex
                    print(P, string.format("  bar[%d] shown=%s li=%s cdID=%s spell=%s",
                        barCount, tostring(child:IsShown()), tostring(li),
                        tostring(cdID), tostring(spellID)))
                end
            end
        end
        print(P, "  barChildren=", barCount, "shown=", shownBars)
    else
        print(P, "Blizzard BuffBarCooldownViewer: NOT FOUND (addon not loaded?)")
    end

    -- 5. CDMBars pool state
    print(P, "CDMBars pool: active=", #barPool, "recycled=", #recyclePool)
    for i, bar in ipairs(barPool) do
        local bw, bh = bar:GetWidth(), bar:GetHeight()
        local shown = bar:IsShown()
        local active = bar._active
        local blizz = bar._blizzBar
        local blizzShown = blizz and blizz:IsShown()
        local spellID = bar._spellID
        local blizzActive = bar._blizzBar and CheckBarActive(bar._blizzBar) or false
        local parent = bar:GetParent()
        local parentName = parent and (parent:GetName() or "unnamed") or "nil"
        print(P, string.format("  [%d] size=%.0fx%.0f shown=%s active=%s blizzShown=%s",
            i, bw or 0, bh or 0, tostring(shown), tostring(active), tostring(blizzShown)))
        print(P, string.format("       name='%s' dur='%s'",
            bar.NameText and bar.NameText:GetText() or "nil",
            bar.DurationText and bar.DurationText:GetText() or "nil"))
        print(P, string.format("       spellID=%s blizzActive=%s parent=%s",
            tostring(spellID), tostring(blizzActive), parentName))
    end

    -- 6. DB settings
    local QUICore2 = ns.Addon
    local ncdmDB = QUICore2 and QUICore2.db and QUICore2.db.profile and QUICore2.db.profile.ncdm
    local tbSettings = ncdmDB and ncdmDB.trackedBar
    if tbSettings then
        print(P, "trackedBar DB: enabled=", tostring(tbSettings.enabled),
            "barWidth=", tostring(tbSettings.barWidth),
            "barHeight=", tostring(tbSettings.barHeight))
        print(P, "  anchorTo=", tostring(tbSettings.anchorTo),
            "pos=", tbSettings.pos and string.format("ox=%.1f oy=%.1f", tbSettings.pos.ox or 0, tbSettings.pos.oy or 0) or "nil")
    else
        print(P, "trackedBar DB: NOT FOUND")
    end

    -- 7. Hook state
    local hookCount = 0
    for _ in pairs(hookedBars) do hookCount = hookCount + 1 end
    local mirrorCount = 0
    for _ in pairs(mirrorMap) do mirrorCount = mirrorCount + 1 end
    print(P, "Hooks: hookedBars=", hookCount, "mirrorMap=", mirrorCount)

    print(P, "=== End Debug ===")
end
