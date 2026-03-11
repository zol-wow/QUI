--[[
    QUI Tooltip Owned Engine
    Taint-free tooltip system that creates addon-owned tooltip frames.
    Blizzard's GameTooltip populates normally (C-side, no taint), then:
      1. TooltipDataProcessor fires with resolved data
      2. We defer 1 frame to capture other addons' AddLine() calls
      3. Read all FontStrings from the Blizzard tooltip (resolved text)
      4. SetAlpha(0) on Blizzard tooltip (C-side, taint-safe)
      5. Populate and show our owned frame (zero taint)

    Registers with TooltipProvider as the "owned" engine.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local Provider  -- resolved on Initialize

-- Locals for performance
local GameTooltip = GameTooltip
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local pcall = pcall
local tinsert = tinsert
local wipe = wipe
local math_max = math.max
local math_min = math.min
local math_abs = math.abs

local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8x8"

---------------------------------------------------------------------------
-- OWNED ENGINE TABLE
---------------------------------------------------------------------------
local OwnedEngine = {}

---------------------------------------------------------------------------
-- FRAME REGISTRY
-- Maps Blizzard tooltip → owned replacement
---------------------------------------------------------------------------
local tooltipPairs = {}      -- [blizzFrame] = ownedFrame
local ownedFrames = {}       -- array of all owned frames
local pendingPopulate = {}   -- [blizzFrame] = token (deferred populate in progress)
local activelyHandling = {}  -- [blizzFrame] = true when PreCall/PostCall is managing this tooltip
local embeddedSubTooltip = {} -- [blizzFrame] = true when frame is currently used as embedded sub-tooltip
local ownerChanged = {}       -- [blizzFrame] = true when SetOwner was called (new tooltip target)
local blizzAnchorCache = {}   -- [blizzFrame] = { point, relativeTo, relPoint, x, y } — last non-offscreen anchor
local blizzOwnerCache = {}    -- [blizzFrame] = { owner, anchorType } — from SetOwner calls
local fadeState = {}          -- [ownedFrame] = { elapsed, duration } when fading out

-- Cancel any active fade-out and restore full alpha (called before showing).
local function CancelFadeOut(ownedTip)
    if fadeState[ownedTip] then
        fadeState[ownedTip] = nil
        ownedTip:SetAlpha(1)
    end
end

-- Begin a fade-out over `duration` seconds.  When the fade completes the
-- frame is hidden and alpha reset to 1 for the next show.
local function StartFadeOut(ownedTip, duration)
    if duration <= 0 then
        ownedTip:Hide()
        return
    end
    fadeState[ownedTip] = { elapsed = 0, duration = duration }
    -- Ensure OnUpdate driver exists (one-time setup per owned frame)
    if not ownedTip._fadeOnUpdate then
        ownedTip._fadeOnUpdate = true
        local existing = ownedTip:GetScript("OnUpdate")
        local fadeHandler = function(self, dt)
            local fs = fadeState[self]
            if not fs then return end
            fs.elapsed = fs.elapsed + dt
            local progress = fs.elapsed / fs.duration
            if progress >= 1 then
                fadeState[self] = nil
                self:SetAlpha(1)
                self:Hide()
            else
                self:SetAlpha(1 - progress)
            end
        end
        if existing then
            ownedTip:HookScript("OnUpdate", fadeHandler)
        else
            ownedTip:SetScript("OnUpdate", fadeHandler)
        end
    end
end

-- Returns true when a tooltip frame is currently being used as the embedded
-- sub-tooltip inside GameTooltip.ItemTooltip (world quest item rewards).
-- When embedded, its content is merged into the main tooltip via
-- ReadEmbeddedContent — we should NOT create a separate owned frame for it.
local function IsEmbeddedSubTooltip(blizzTip)
    if embeddedSubTooltip[blizzTip] then return true end
    -- Check if this frame is an ItemTooltip.Tooltip sub-frame of any
    -- actively handled parent tooltip. This covers GameTooltip and any
    -- third-party tooltips that use the same embedded item pattern.
    for parentBlizz in pairs(tooltipPairs) do
        local it = parentBlizz.ItemTooltip
        if it and it.Tooltip == blizzTip then
            if activelyHandling[parentBlizz] then return true end
            local parentOwned = tooltipPairs[parentBlizz]
            if parentOwned and parentOwned:IsShown() then return true end
            local okShown, isShown = pcall(it.IsShown, it)
            if okShown and isShown then return true end
        end
    end
    return false
end

-- Returns true when we should suppress the Blizzard tooltip (move off-screen).
-- Only suppress when the owned engine is actively handling this tooltip — i.e.,
-- a PreCall/PostCall has fired for a tooltip type we registered for. This lets
-- unregistered types (map POIs, world quests, etc.) show normally via Blizzard.
local function ShouldSuppressBlizz(blizzTip)
    if activelyHandling[blizzTip] then return true end
    local ownedTip = tooltipPairs[blizzTip]
    if ownedTip and ownedTip:IsShown() then return true end
    if pendingPopulate[blizzTip] then return true end
    -- Embedded sub-tooltips (GameTooltipTooltip when used inside ItemTooltip)
    -- should always be suppressed — their content is merged into the main tooltip.
    if IsEmbeddedSubTooltip(blizzTip) then return true end
    -- GameTooltipTooltip (and its wrapper ItemTooltip) should stay suppressed
    -- whenever GameTooltip itself is being handled. This prevents a race where
    -- GameTooltip's deferred OnHide clears the embedded flag while
    -- GameTooltipTooltip is still shown, leaving it briefly unsuppressed.
    local gt = GameTooltip
    if gt and gt.ItemTooltip and gt.ItemTooltip.Tooltip == blizzTip then
        if activelyHandling[gt] then return true end
        local gtOwned = tooltipPairs[gt]
        if gtOwned and gtOwned:IsShown() then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- FONTSTRING POOL (per owned frame)
-- Each owned frame gets a pool attached via frame._linePool
---------------------------------------------------------------------------

local function GetOrCreateLinePair(ownedTip, index)
    local pool = ownedTip._linePool
    if pool[index] then return pool[index] end

    local baseFontPath = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    local flags = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""

    local left = ownedTip:CreateFontString(nil, "ARTWORK")
    left:SetFont(baseFontPath, 12, flags)
    left:SetJustifyH("LEFT")
    left:SetWordWrap(true)

    local right = ownedTip:CreateFontString(nil, "ARTWORK")
    right:SetFont(baseFontPath, 12, flags)
    right:SetJustifyH("RIGHT")
    right:SetWordWrap(false)

    pool[index] = { left = left, right = right }
    return pool[index]
end

local function HideAllLines(ownedTip)
    local pool = ownedTip._linePool
    for i = 1, #pool do
        pool[i].left:Hide()
        pool[i].right:Hide()
    end
    ownedTip._activeLines = 0
end

---------------------------------------------------------------------------
-- PROGRESS BAR POOL (for embedded StatusBar content)
---------------------------------------------------------------------------

local function GetOrCreateProgressBar(ownedTip, index)
    local pool = ownedTip._barPool
    if pool[index] then return pool[index] end

    local bar = CreateFrame("StatusBar", nil, ownedTip)
    bar:SetStatusBarTexture(FLAT_TEXTURE)
    bar:SetHeight(14)
    bar:SetMinMaxValues(0, 1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    bar._bg = bg

    local baseFontPath = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    local flags = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
    local label = bar:CreateFontString(nil, "OVERLAY")
    label:SetFont(baseFontPath, 10, flags)
    label:SetPoint("CENTER")
    label:SetTextColor(1, 1, 1, 1)
    bar._label = label

    pool[index] = bar
    return bar
end

local function HideAllProgressBars(ownedTip)
    local pool = ownedTip._barPool
    for i = 1, #pool do
        pool[i]:Hide()
    end
end

---------------------------------------------------------------------------
-- SKINNING (integrated — we own the frame)
---------------------------------------------------------------------------

local function GetEffectiveColors()
    local settings = Provider and Provider:GetSettings()
    -- Defaults: mint border, dark background
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
    local bgr, bgg, bgb, bga = 0.15, 0.15, 0.15, 0.95

    if not settings then return sr, sg, sb, sa, bgr, bgg, bgb, bga end

    if settings.bgColor then
        bgr = settings.bgColor[1] or bgr
        bgg = settings.bgColor[2] or bgg
        bgb = settings.bgColor[3] or bgb
    end
    if settings.bgOpacity then
        bga = settings.bgOpacity
    end

    if settings.borderUseClassColor then
        local _, classToken = UnitClass("player")
        if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
            local c = RAID_CLASS_COLORS[classToken]
            sr, sg, sb, sa = c.r, c.g, c.b, 1
        end
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

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

local function GetEffectiveBorderThickness()
    local settings = Provider and Provider:GetSettings()
    return (settings and settings.borderThickness) or 1
end

local function GetEffectiveFontSize()
    local settings = Provider and Provider:GetSettings()
    local size = (settings and settings.fontSize) or 12
    size = tonumber(size) or 12
    if size < 8 then size = 8 elseif size > 24 then size = 24 end
    return size
end

local function ApplySkin(ownedTip)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    ownedTip:SetBackdrop({
        bgFile = FLAT_TEXTURE,
        edgeFile = FLAT_TEXTURE,
        edgeSize = thickness,
        insets = { left = thickness, right = thickness, top = thickness, bottom = thickness },
    })
    ownedTip:SetBackdropColor(bgr, bgg, bgb, bga)
    ownedTip:SetBackdropBorderColor(sr, sg, sb, sa)
end

---------------------------------------------------------------------------
-- HEALTH BAR
---------------------------------------------------------------------------

local function CreateHealthBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(FLAT_TEXTURE)
    bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
    bar:SetHeight(4)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:Hide()
    return bar
end

---------------------------------------------------------------------------
-- FRAME FACTORY
---------------------------------------------------------------------------

local function CreateOwnedTooltip(name)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    -- Click-through: tooltips should never block clicks on underlying frames
    -- (buttons, action bars, map pins). Propagate mouse motion so OnLeave/
    -- OnHyperlinkLeave still fire on frames below.
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    if frame.SetPropagateMouseMotion then
        frame:SetPropagateMouseMotion(true)
    end
    frame:Hide()

    -- FontString pool
    frame._linePool = {}
    -- Progress bar pool (for embedded StatusBar content)
    frame._barPool = {}
    frame._activeLines = 0

    -- Padding — kept tight since frame dimensions come from Blizzard's tooltip
    frame._padding = 6
    frame._lineGap = 2

    -- Apply initial skin
    ApplySkin(frame)

    return frame
end

local TOOLTIP_MIN_WIDTH = 180
local TOOLTIP_MAX_WIDTH = 420
local TOOLTIP_SINGLE_LINE_SOFT_CAP = 320
local TOOLTIP_DOUBLE_LINE_GAP = 12
local TOOLTIP_WIDTH_OVERSIZE_TOLERANCE = 40

local function ClampTooltipWidth(width)
    width = Helpers.SafeToNumber(width, nil)
    if not width then return nil end
    return math_min(math_max(width, TOOLTIP_MIN_WIDTH), TOOLTIP_MAX_WIDTH)
end

local function MeasureFontStringWidth(fontString, text, softCap)
    if not fontString or text == nil then return nil end
    if type(issecretvalue) == "function" and issecretvalue(text) then return nil end

    local width = nil
    if fontString.GetUnboundedStringWidth then
        local ok, value = pcall(fontString.GetUnboundedStringWidth, fontString)
        width = ok and Helpers.SafeToNumber(value, nil) or nil
    end
    if not width then
        local ok, value = pcall(fontString.GetStringWidth, fontString)
        width = ok and Helpers.SafeToNumber(value, nil) or nil
    end
    if width and softCap then
        width = math_min(width, softCap)
    end
    return width
end

local function ResolveTooltipWidth(blizzWidth, measuredWidth)
    local finalWidth = ClampTooltipWidth(blizzWidth) or 250
    measuredWidth = ClampTooltipWidth(measuredWidth)
    if not measuredWidth then
        return finalWidth
    end

    if finalWidth < measuredWidth then
        return measuredWidth
    end
    if finalWidth > (measuredWidth + TOOLTIP_WIDTH_OVERSIZE_TOLERANCE) then
        return measuredWidth
    end
    return finalWidth
end

---------------------------------------------------------------------------
-- DATA EXTRACTION
---------------------------------------------------------------------------

local function ReadAllLines(blizzTip)
    local lines = {}
    local okNum, numLines = pcall(blizzTip.NumLines, blizzTip)
    if not okNum then return lines end
    numLines = tonumber(numLines) or 0

    for i = 1, numLines do
        local left, right
        if blizzTip.GetLeftLine then
            left = blizzTip:GetLeftLine(i)
            right = blizzTip:GetRightLine(i)
        else
            local tipName = blizzTip:GetName()
            if tipName then
                left = _G[tipName .. "TextLeft" .. i]
                right = _G[tipName .. "TextRight" .. i]
            end
        end

        local leftText, rightText
        local lr, lg, lb = 1, 1, 1
        local rr, rg, rb = 1, 1, 1

        if left then
            local ok, t = pcall(left.GetText, left)
            if ok then leftText = t end
            local okC, r, g, b = pcall(left.GetTextColor, left)
            if okC and r then lr, lg, lb = r, g, b end
        end
        if right then
            local ok, t = pcall(right.GetText, right)
            -- Accept any non-nil value — secret strings can't be compared
            if ok and t then rightText = t end
            local okC, r, g, b = pcall(right.GetTextColor, right)
            if okC and r then rr, rg, rb = r, g, b end
        end

        if leftText then
            lines[#lines + 1] = {
                leftText = leftText,
                rightText = rightText,
                lr = lr, lg = lg, lb = lb,
                rr = rr, rg = rg, rb = rb,
            }
        end
    end

    return lines
end

---------------------------------------------------------------------------
-- EMBEDDED CONTENT EXTRACTION
-- Reads EmbeddedItemTooltip (world quest rewards), progress bars, etc.
---------------------------------------------------------------------------

local function ReadEmbeddedContent(blizzTip)
    local embedded = {}

    -- EmbeddedItemTooltip (world quest item rewards, etc.)
    -- GameTooltip.ItemTooltip has .Icon (Texture), .Name (FontString),
    -- .Count (FontString), .Tooltip (sub-GameTooltip with item stats)
    local itemTooltip = blizzTip.ItemTooltip
    if itemTooltip then
        local okShown, isShown = pcall(itemTooltip.IsShown, itemTooltip)
        if okShown and isShown then

        -- Read icon texture
        local iconTexture
        if itemTooltip.Icon then
            local okTex, tex = pcall(itemTooltip.Icon.GetTexture, itemTooltip.Icon)
            if okTex and tex then iconTexture = tex end
        end

        -- Read item name and color
        local itemName, nr, ng, nb = nil, 1, 1, 1
        if itemTooltip.Name then
            local okN, n = pcall(itemTooltip.Name.GetText, itemTooltip.Name)
            if okN and n and n ~= "" then itemName = n end
            local okC, r, g, b = pcall(itemTooltip.Name.GetTextColor, itemTooltip.Name)
            if okC and r then nr, ng, nb = r, g, b end
        end

        -- Read count
        local count
        if itemTooltip.Count then
            local okCnt, c = pcall(itemTooltip.Count.GetText, itemTooltip.Count)
            if okCnt and c then count = c end
        end

        -- Sub-tooltip lines (item stats, equip effects, etc.)
        -- Read these first — if itemName is nil (async load), the sub-tooltip's
        -- first line usually contains the item name.
        local subLines = {}
        if itemTooltip.Tooltip then
            local okSub, subShown = pcall(itemTooltip.Tooltip.IsShown, itemTooltip.Tooltip)
            if okSub and subShown then
                subLines = ReadAllLines(itemTooltip.Tooltip)
            end
        end

        -- If Name FontString is nil (async item load), try the sub-tooltip's
        -- first line as fallback — it's typically the item name in item color.
        if not itemName and #subLines > 0 then
            itemName = subLines[1].leftText
            nr, ng, nb = subLines[1].lr, subLines[1].lg, subLines[1].lb
            -- Remove the first line since we're using it as the header
            table.remove(subLines, 1)
        end

        -- Proceed if we have either a name or sub-tooltip content
        if itemName or #subLines > 0 then
            -- Separator
            embedded[#embedded + 1] = { leftText = " ", lr = 1, lg = 1, lb = 1 }

            -- Icon + name line. Concatenation is safe with secret values —
            -- tainted code is allowed to concat secret strings/numbers.
            if itemName then
                local display = itemName
                if iconTexture then
                    display = "|T" .. tostring(iconTexture) .. ":16:16:0:0|t " .. tostring(itemName)
                end
                if count then
                    display = display .. " x" .. tostring(count)
                end

                embedded[#embedded + 1] = {
                    leftText = display,
                    lr = nr, lg = ng, lb = nb,
                }
            elseif iconTexture then
                -- No name at all but have icon — show icon alone
                embedded[#embedded + 1] = {
                    leftText = "|T" .. tostring(iconTexture) .. ":16:16:0:0|t",
                    lr = 1, lg = 1, lb = 1,
                }
            end

            for _, line in ipairs(subLines) do
                embedded[#embedded + 1] = line
            end

            -- Suppress the Blizzard embedded item frame after reading its content.
            pcall(itemTooltip.SetAlpha, itemTooltip, 0)
            -- Mark the sub-tooltip as embedded so we don't create a separate
            -- owned frame for it (its lines are already merged into the main tooltip).
            if itemTooltip.Tooltip then
                embeddedSubTooltip[itemTooltip.Tooltip] = true
                pcall(itemTooltip.Tooltip.SetAlpha, itemTooltip.Tooltip, 0)
            end

        end
        end -- if okShown and isShown
    end

    -- Progress bars (StatusBar children — world quest objectives, etc.)
    -- Skip the tooltip's own health StatusBar (named "GameTooltipStatusBar" etc.)
    local okChildren, children = pcall(function() return { blizzTip:GetChildren() } end)
    if okChildren and children then
        for _, child in ipairs(children) do
            local okType, isBar = pcall(child.IsObjectType, child, "StatusBar")
            if okType and isBar then
                local okBarShown, barShown = pcall(child.IsShown, child)
                if okBarShown and barShown then
                    local barName = child:GetName()
                    -- Skip the tooltip's built-in health status bar
                    if not barName or not barName:find("StatusBar$") then
                        local barValue, barMin, barMax = 0, 0, 1
                        local okV, v = pcall(child.GetValue, child)
                        if okV then barValue = Helpers.SafeToNumber(v, 0) end
                        local okMM, mn, mx = pcall(child.GetMinMaxValues, child)
                        if okMM then
                            barMin = Helpers.SafeToNumber(mn, 0)
                            barMax = Helpers.SafeToNumber(mx, 1)
                        end

                        local br, bg, bb = 0.2, 0.6, 1
                        local okBC, r, g, b = pcall(child.GetStatusBarColor, child)
                        if okBC and r then br, bg, bb = r, g, b end

                        -- Read label text from FontString children of the bar
                        local barLabel
                        local okRegions, regions = pcall(function() return { child:GetRegions() } end)
                        if okRegions and regions then
                            for _, region in ipairs(regions) do
                                local okRT, isFontStr = pcall(region.IsObjectType, region, "FontString")
                                if okRT and isFontStr then
                                    local okFS, fsShown = pcall(region.IsShown, region)
                                    if okFS and fsShown then
                                        local okT, t = pcall(region.GetText, region)
                                        if okT and t then
                                            barLabel = t
                                            break
                                        end
                                    end
                                end
                            end
                        end

                        if barMax > barMin then
                            local ratio = (barValue - barMin) / (barMax - barMin)
                            embedded[#embedded + 1] = {
                                isProgressBar = true,
                                barRatio = ratio,
                                barColor = { r = br, g = bg, b = bb },
                                barLabel = barLabel,
                            }
                        end
                    end
                end
            end
        end
    end

    return embedded
end

---------------------------------------------------------------------------
-- WIDGET CONTENT EXTRACTION
-- Reads text from widget container children (renown tooltips, world events,
-- timed content, etc.). These use Blizzard's UIWidgetManager system —
-- the content lives in child→subchild→FontString hierarchies, not in
-- the standard TextLeft/TextRight lines.
---------------------------------------------------------------------------

-- Helper: recursively collect text from a frame and all descendants.
-- Returns texts only — icon extraction is handled separately by
-- FindWidgetIcon which uses smarter heuristics.
local function CollectFrameTexts(frame, depth)
    depth = depth or 0
    if depth > 4 then return {} end  -- safety limit

    local texts = {}

    -- Read FontStrings from this frame
    local okR, regions = pcall(function() return { frame:GetRegions() } end)
    if okR and regions then
        for _, region in ipairs(regions) do
            local okRS, rShown = pcall(region.IsShown, region)
            if okRS and rShown then
                local okRT, rType = pcall(region.GetObjectType, region)
                if okRT and rType == "FontString" then
                    local okTx, txt = pcall(region.GetText, region)
                    if okTx and txt then
                        local okC, r, g, b = pcall(region.GetTextColor, region)
                        local lr, lg, lb = 1, 1, 1
                        if okC and r then lr, lg, lb = r, g, b end
                        texts[#texts + 1] = { text = txt, lr = lr, lg = lg, lb = lb }
                    end
                end
            end
        end
    end

    -- Recurse into children
    local okC, children = pcall(function() return { frame:GetChildren() } end)
    if okC and children then
        for _, child in ipairs(children) do
            local okCS, cShown = pcall(child.IsShown, child)
            if okCS and cShown then
                local okCT, cType = pcall(child.GetObjectType, child)
                if not okCT or cType ~= "ModelScene" then
                    local childTexts = CollectFrameTexts(child, depth + 1)
                    if childTexts then
                        for _, t in ipairs(childTexts) do
                            texts[#texts + 1] = t
                        end
                    end
                end
            end
        end
    end

    return texts
end

-- Find the best icon for a widget sub-child frame.
-- Returns an inline markup string ("|A:atlas:16:16|a" or "|Ttex:16:16:...|t")
-- ready to be prepended to the text, or nil if no suitable icon found.
--
-- Blizzard widget frames use atlas regions (sub-rectangles of sprite sheets).
-- GetTexture() returns the full sprite sheet — useless for inline display.
-- GetAtlas() returns the atlas name which WoW renders correctly via |A markup.
-- We prefer:
--   1. frame.Icon member with atlas (common Blizzard pattern)
--   2. Textures from child frames that have an atlas set
--   3. Skip entirely if nothing matches — no icon is better than a sprite sheet
local function FindWidgetIcon(frame)
    -- Helper: try to get atlas markup from a texture region
    local function GetIconMarkup(texRegion)
        if not texRegion then return nil end
        local okS, shown = pcall(texRegion.IsShown, texRegion)
        if not (okS and shown) then return nil end

        -- Prefer atlas — renders the correct sub-region of the sprite sheet
        if texRegion.GetAtlas then
            local okA, atlas = pcall(texRegion.GetAtlas, texRegion)
            if okA and atlas and atlas ~= "" then
                return "|A:" .. atlas .. ":16:16|a"
            end
        end

        -- Fallback: raw texture with tex coords (for non-atlas icons)
        local okT, tex = pcall(texRegion.GetTexture, texRegion)
        if okT and tex then
            local okTC, l, r, t, b = pcall(texRegion.GetTexCoord, texRegion)
            if okTC and l and (l ~= 0 or r ~= 1 or t ~= 0 or b ~= 1) then
                -- Has custom tex coords — use them to show the right portion
                return "|T" .. tostring(tex) .. ":16:16:0:0:"
                    .. string.format("%.4f:%.4f:%.4f:%.4f", l, r, t, b) .. "|t"
            end
        end

        return nil
    end

    -- Check common Blizzard .Icon member first
    if frame.Icon then
        local markup = GetIconMarkup(frame.Icon)
        if markup then return markup end
    end

    -- Collect all atlas candidates from child frames (skip direct frame
    -- regions — those are container backgrounds/borders).
    local candidates = {}
    local function scanFrame(f, depth)
        if depth > 3 then return end
        local okR, regions = pcall(function() return { f:GetRegions() } end)
        if okR and regions then
            for _, region in ipairs(regions) do
                local okRT, rType = pcall(region.GetObjectType, region)
                if okRT and rType == "Texture" then
                    local okRS, rShown = pcall(region.IsShown, region)
                    if okRS and rShown and region.GetAtlas then
                        local okA, atlas = pcall(region.GetAtlas, region)
                        if okA and atlas and atlas ~= "" then
                            local okW, w = pcall(region.GetWidth, region)
                            local okH, h = pcall(region.GetHeight, region)
                            w = okW and tonumber(w) or 0
                            h = okH and tonumber(h) or 0
                            if w >= 8 and h >= 8 and w <= 48 and h <= 48 then
                                candidates[#candidates + 1] = {
                                    atlas = atlas,
                                    depth = depth,
                                    w = w, h = h,
                                }
                            end
                        end
                    end
                end
            end
        end
        local okC2, children2 = pcall(function() return { f:GetChildren() } end)
        if okC2 and children2 then
            for _, ch in ipairs(children2) do
                local okCS2, cS2 = pcall(ch.IsShown, ch)
                if okCS2 and cS2 then scanFrame(ch, depth + 1) end
            end
        end
    end

    -- Start scanning from child frames (depth=1), skipping the sub-child
    -- frame's own regions (depth=0) which are typically backgrounds
    local okC, children = pcall(function() return { frame:GetChildren() } end)
    if okC and children then
        for _, child in ipairs(children) do
            local okCS, cShown = pcall(child.IsShown, child)
            if okCS and cShown then
                -- Check child's .Icon member first
                if child.Icon then
                    local markup = GetIconMarkup(child.Icon)
                    if markup then return markup end
                end
                scanFrame(child, 1)
            end
        end
    end

    -- Pick the best atlas from candidates:
    -- 1. Skip generic backgrounds (questmarker) and corner decorations
    -- 2. Prefer content-specific atlases (EventPoi, Poi patterns)
    -- 3. Fall back to first remaining candidate
    local bestAtlas = nil
    for _, c in ipairs(candidates) do
        local a = c.atlas
        -- Skip generic background markers
        local okQM, isQM = pcall(string.find, a, "questmarker")
        if okQM and isQM then
            -- skip: worldquest-questmarker-epic etc.
        else
            -- Skip corner decoration overlays
            local okCR, isCR = pcall(string.find, a, "corner")
            if okCR and isCR then
                -- skip: UI-EventPoi-Horn-small-corner etc.
            else
                -- Content icon — prefer EventPoi/Poi names but accept anything
                local okEP, isEP = pcall(string.find, a, "EventPoi")
                if okEP and isEP then
                    -- Best match: content-specific event icon
                    return "|A:" .. a .. ":16:16|a"
                end
                if not bestAtlas then
                    bestAtlas = a
                end
            end
        end
    end

    if bestAtlas then
        return "|A:" .. bestAtlas .. ":16:16|a"
    end

    return nil  -- no suitable icon found
end

local function IsWidgetContainerFrame(frame)
    if not frame then return false end
    if frame.shownWidgetCount ~= nil then return true end
    if frame.widgetFrames ~= nil then return true end
    if frame.widgetPool ~= nil then return true end
    return false
end

-- Returns an array of widget entry groups, each { yPos, lines[] }.
-- ONE entry per tooltip child container (not per sub-child). Each blank
-- spacer block in the text lines corresponds to one container child.
-- Sub-children within a container are sorted by vertical position and
-- their content is merged into a single entry.
-- ReadAllContent replaces each blank block with the corresponding entry.
local function ReadWidgetContent(blizzTip)
    local widgetEntries = {}  -- { yPos, lines[] }

    local okChildren, children = pcall(function() return { blizzTip:GetChildren() } end)
    if not okChildren or not children then return {} end

    for _, child in ipairs(children) do
        -- Skip known non-widget children
        local okType, objType = pcall(child.GetObjectType, child)
        if okType and objType == "StatusBar" then
            -- skip (health bar)
        elseif child == blizzTip.ItemTooltip then
            -- skip — handled by ReadEmbeddedContent
        else
            local okShown, shown = pcall(child.IsShown, child)
            if okShown and shown and IsWidgetContainerFrame(child) then
                -- Collect all sub-children content, sorted by vertical position.
                -- Each sub-child's content is gathered, then sorted and merged
                -- into a single entry for this container.
                local subEntries = {}  -- { yPos, icon, texts[] }
                local okSC, subChildren = pcall(function() return { child:GetChildren() } end)
                if okSC and subChildren then
                    for _, sc in ipairs(subChildren) do
                        local okSCS, scShown = pcall(sc.IsShown, sc)
                        if okSCS and scShown then
                            local okSCT, scType = pcall(sc.GetObjectType, sc)
                            if okSCT and scType ~= "ModelScene" then
                                -- Get vertical position for sorting
                                local yPos = 0
                                local okTop, top = pcall(sc.GetTop, sc)
                                if okTop and top then
                                    yPos = Helpers.SafeToNumber(top, 0)
                                end

                                -- Collect text recursively
                                local texts = CollectFrameTexts(sc, 0)

                                -- Find icon — but skip if the first text already
                                -- contains inline |T...|t textures (e.g., faction icons
                                -- that Blizzard embeds in the FontString text itself)
                                local iconTexture = nil
                                local hasInlineIcon = false
                                if texts and #texts > 0 then
                                    local firstText = texts[1].text
                                    local okFind, found = pcall(string.find, firstText, "|T")
                                    if okFind and found then
                                        hasInlineIcon = true
                                    end
                                end
                                if not hasInlineIcon then
                                    iconTexture = FindWidgetIcon(sc)
                                end

                                if (texts and #texts > 0) or iconTexture then
                                    subEntries[#subEntries + 1] = {
                                        yPos = yPos,
                                        icon = iconTexture,
                                        texts = texts or {},
                                    }
                                end
                            end
                        end
                    end
                end

                -- Sort sub-entries by vertical position (top-to-bottom)
                table.sort(subEntries, function(a, b) return a.yPos > b.yPos end)

                -- Merge all sub-entries into a single container entry.
                -- se.icon is already a complete markup string (|A:atlas|a or
                -- |T:tex:coords|t) ready to prepend, or nil if no icon.
                local containerLines = {}
                for _, se in ipairs(subEntries) do
                    if #se.texts > 0 then
                        for ti, t in ipairs(se.texts) do
                            local display = t.text
                            if ti == 1 and se.icon then
                                display = se.icon .. " " .. tostring(t.text)
                            end
                            containerLines[#containerLines + 1] = {
                                leftText = display,
                                lr = t.lr, lg = t.lg, lb = t.lb,
                            }
                        end
                    elseif se.icon then
                        containerLines[#containerLines + 1] = {
                            leftText = se.icon,
                            lr = 1, lg = 1, lb = 1,
                        }
                    end
                end

                if #containerLines > 0 then
                    -- Use the container's top position for sorting among containers
                    local containerYPos = 0
                    local okCTop, cTop = pcall(child.GetTop, child)
                    if okCTop and cTop then
                        containerYPos = Helpers.SafeToNumber(cTop, 0)
                    end
                    widgetEntries[#widgetEntries + 1] = {
                        yPos = containerYPos,
                        lines = containerLines,
                    }
                end
            end
        end
    end

    -- Sort containers by vertical position (top-to-bottom)
    table.sort(widgetEntries, function(a, b) return a.yPos > b.yPos end)

    return widgetEntries
end

---------------------------------------------------------------------------
-- COMBINED READ: text lines + embedded + widget content
-- Returns all lines merged, with blank spacer lines removed when widget
-- content is present (Blizzard inserts blank lines to reserve space for
-- widget frames that overlay on top).
---------------------------------------------------------------------------

local function ReadAllContent(blizzTip)
    local lines = ReadAllLines(blizzTip)
    local embedded = ReadEmbeddedContent(blizzTip)
    local widgetEntries = ReadWidgetContent(blizzTip)

    -- Interleave widget content with text lines.
    -- Blizzard inserts contiguous blocks of blank (whitespace-only) spacer lines
    -- where widget frames overlay on top. Each blank block corresponds to the next
    -- widget entry (sorted top-to-bottom). Replace each blank block with its
    -- matching widget entry to preserve Blizzard's intended content order.
    -- Non-blank text lines (e.g., "Available Timed Content" between two widget
    -- blocks) are kept in their original positions.
    if #widgetEntries > 0 then
        local merged = {}
        local widgetIdx = 1
        local i = 1
        local replacedWidgetBlock = false
        while i <= #lines do
            local text = lines[i].leftText
            local okMatch, hasContent = pcall(string.match, text, "%S")
            local isBlank = okMatch and not hasContent

            if isBlank then
                -- Consume the entire contiguous blank block
                while i <= #lines do
                    text = lines[i].leftText
                    okMatch, hasContent = pcall(string.match, text, "%S")
                    isBlank = okMatch and not hasContent
                    if not isBlank then break end
                    i = i + 1
                end
                -- Replace this blank block with the next widget entry
                if widgetIdx <= #widgetEntries then
                    for _, wLine in ipairs(widgetEntries[widgetIdx].lines) do
                        merged[#merged + 1] = wLine
                    end
                    replacedWidgetBlock = true
                    widgetIdx = widgetIdx + 1
                end
            else
                -- Non-blank line (real text or secret value) — keep it
                merged[#merged + 1] = lines[i]
                i = i + 1
            end
        end

        -- Any remaining widget entries that didn't match a blank block
        while widgetIdx <= #widgetEntries and (replacedWidgetBlock or #lines == 0) do
            merged[#merged + 1] = { leftText = " ", lr = 1, lg = 1, lb = 1 }
            for _, wLine in ipairs(widgetEntries[widgetIdx].lines) do
                merged[#merged + 1] = wLine
            end
            widgetIdx = widgetIdx + 1
        end

        lines = merged
    end

    -- When embedded content exists (EmbeddedItemTooltip for item rewards),
    -- Blizzard inserts contiguous blocks of blank spacer lines to reserve space
    -- for the overlay. Strip multi-line blank blocks so we don't double-count
    -- the embedded content (which we render ourselves at the end).
    if #embedded > 0 then
        local stripped = {}
        local i = 1
        while i <= #lines do
            local text = lines[i].leftText
            local okMatch, hasContent = pcall(string.match, text, "%S")
            local isBlank = okMatch and not hasContent

            if isBlank then
                -- Measure the contiguous blank block
                local blockStart = i
                while i <= #lines do
                    text = lines[i].leftText
                    okMatch, hasContent = pcall(string.match, text, "%S")
                    isBlank = okMatch and not hasContent
                    if not isBlank then break end
                    i = i + 1
                end
                local blockSize = i - blockStart
                if blockSize <= 1 then
                    -- Single blank line — keep as intentional spacer
                    stripped[#stripped + 1] = lines[blockStart]
                end
                -- Multi-line blank blocks are stripped (reserved for embedded overlay)
            else
                stripped[#stripped + 1] = lines[i]
                i = i + 1
            end
        end
        lines = stripped
    end

    -- Append embedded content (items, progress bars)
    for _, e in ipairs(embedded) do
        lines[#lines + 1] = e
    end

    return lines, (#embedded > 0 or #widgetEntries > 0)
end

---------------------------------------------------------------------------
-- POPULATE OWNED FRAME
---------------------------------------------------------------------------

local function PopulateTooltip(ownedTip, lines, tooltipType, tooltipData, blizzTip)
    if not ownedTip or #lines == 0 then
        ownedTip:Hide()
        return
    end

    -- Cancel any in-progress fade-out — we're about to show new content.
    CancelFadeOut(ownedTip)

    HideAllLines(ownedTip)
    HideAllProgressBars(ownedTip)

    local settings = Provider:GetSettings()
    local fontSize = GetEffectiveFontSize()
    local headerSize = fontSize + 2
    local padding = ownedTip._padding
    local lineGap = ownedTip._lineGap
    local fontPath = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    local fontFlags = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
    local blizzWidth = blizzTip and ClampTooltipWidth(blizzTip:GetWidth()) or nil

    -- Start from Blizzard's width, then refine it after we've measured the lines
    -- we actually render. This trims oversized backdrops from overlay/widget
    -- widths while still preserving Blizzard's wrap width as a fallback.
    ownedTip:SetWidth(blizzWidth or 250)

    -- Single pass: set text and position using RELATIVE ANCHORING.
    -- Each line anchors to the BOTTOM of the previous line. Word-wrapped text
    -- naturally pushes subsequent lines down — no height measurement needed.
    -- Secret text values pass straight through to C-side SetText/SetTextColor.
    local textIdx = 0
    local barIdx = 0
    local measuredMaxWidth = 0
    local prevAnchor = nil  -- the region to anchor below (nil = first line, anchor to frame top)

    for i, lineData in ipairs(lines) do
        if lineData.isProgressBar then
            barIdx = barIdx + 1
            local bar = GetOrCreateProgressBar(ownedTip, barIdx)
            bar:SetStatusBarColor(lineData.barColor.r, lineData.barColor.g, lineData.barColor.b, 1)
            bar:SetValue(lineData.barRatio)
            bar:ClearAllPoints()
            if prevAnchor then
                bar:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -lineGap)
                bar:SetPoint("RIGHT", ownedTip, "RIGHT", -padding, 0)
            else
                bar:SetPoint("TOPLEFT", ownedTip, "TOPLEFT", padding, -padding)
                bar:SetPoint("RIGHT", ownedTip, "RIGHT", -padding, 0)
            end
            bar:SetHeight(14)
            if lineData.barLabel then
                bar._label:SetFont(fontPath, math_max(fontSize - 2, 8), fontFlags)
                bar._label:SetText(lineData.barLabel)
                bar._label:Show()
            else
                bar._label:SetText("")
                bar._label:Hide()
            end
            bar:Show()
            measuredMaxWidth = math_max(measuredMaxWidth, 220)
            prevAnchor = bar
        else
            textIdx = textIdx + 1
            local pair = GetOrCreateLinePair(ownedTip, textIdx)
            local left = pair.left
            local right = pair.right
            local size = (i == 1) and headerSize or fontSize

            left:SetFont(fontPath, size, fontFlags)
            right:SetFont(fontPath, size, fontFlags)

            local rightWidth = nil
            if lineData.rightText then
                right:SetText(lineData.rightText)
                right:SetTextColor(lineData.rr, lineData.rg, lineData.rb)
                rightWidth = MeasureFontStringWidth(right, lineData.rightText)
            else
                right:SetText("")
                right:Hide()
            end

            -- Blindly pass text and colors through — C-side handles secret values.
            left:SetText(lineData.leftText)
            left:SetTextColor(lineData.lr, lineData.lg, lineData.lb)
            left:ClearAllPoints()
            if prevAnchor then
                left:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -lineGap)
            else
                left:SetPoint("TOPLEFT", ownedTip, "TOPLEFT", padding, -padding)
            end
            if lineData.rightText then
                local reserve = (rightWidth and (rightWidth + TOOLTIP_DOUBLE_LINE_GAP)) or 90
                left:SetPoint("RIGHT", ownedTip, "RIGHT", -(padding + reserve), 0)
            else
                left:SetPoint("RIGHT", ownedTip, "RIGHT", -padding, 0)
            end
            left:Show()

            if lineData.rightText then
                right:ClearAllPoints()
                right:SetPoint("TOP", left, "TOP", 0, 0)
                right:SetPoint("RIGHT", ownedTip, "RIGHT", -padding, 0)
                right:Show()
            end

            local leftWidth = MeasureFontStringWidth(left, lineData.leftText, lineData.rightText and nil or TOOLTIP_SINGLE_LINE_SOFT_CAP)
            local lineWidth = nil
            if lineData.rightText then
                if leftWidth and rightWidth then
                    lineWidth = leftWidth + TOOLTIP_DOUBLE_LINE_GAP + rightWidth
                else
                    lineWidth = leftWidth or rightWidth
                end
            else
                lineWidth = leftWidth
            end
            if lineWidth then
                measuredMaxWidth = math_max(measuredMaxWidth, lineWidth)
            end

            prevAnchor = left
        end
    end

    ownedTip._activeLines = #lines

    local measuredWidth = nil
    if measuredMaxWidth > 0 then
        measuredWidth = measuredMaxWidth + padding * 2
    end
    ownedTip:SetWidth(ResolveTooltipWidth(blizzWidth, measuredWidth))

    -- Health bar for unit tooltips
    local healthBar = ownedTip._healthBar
    if healthBar then
        if tooltipType == Enum.TooltipDataType.Unit and settings and not settings.hideHealthBar then
            healthBar:ClearAllPoints()
            healthBar:SetPoint("BOTTOMLEFT", ownedTip, "BOTTOMLEFT", padding, padding)
            healthBar:SetPoint("BOTTOMRIGHT", ownedTip, "BOTTOMRIGHT", -padding, padding)
            healthBar:Show()

            -- Try to get health ratio from mouseover
            local healthRatio = 1
            local okH, hp = pcall(UnitHealth, "mouseover")
            local okHM, hpMax = pcall(UnitHealthMax, "mouseover")
            if okH and okHM then
                hp = Helpers.SafeToNumber(hp, 0)
                hpMax = Helpers.SafeToNumber(hpMax, 1)
                if hpMax > 0 then
                    healthRatio = hp / hpMax
                end
            end
            healthBar:SetValue(healthRatio)

            -- Class color for players
            local okUnit, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
            if okUnit and unit and not Helpers.IsSecretValue(unit) then
                local okP, isP = pcall(UnitIsPlayer, unit)
                if okP and isP then
                    local okC, _, classToken = pcall(UnitClass, unit)
                    if okC and classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                        local c = RAID_CLASS_COLORS[classToken]
                        healthBar:SetStatusBarColor(c.r, c.g, c.b, 1)
                    end
                else
                    -- NPC: green/yellow/red based on reaction
                    healthBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
                end
            end

        else
            healthBar:Hide()
        end
    end

    -- Height calculation.
    -- For tooltips with extra content (widgets, embedded items), we can't rely
    -- on Blizzard's height (it includes blank spacer lines for widget overlays).
    -- Use anchor-chain measurement: set a temporary small height so anchor
    -- positions resolve, then measure from frame top to last content bottom.
    -- For plain tooltips, Blizzard's height is passed through (C-side handles
    -- secret values).
    local hasExtra = ownedTip._hasEmbeddedContent
    if prevAnchor and (hasExtra or not blizzTip) then
        -- Embedded/widget content — Blizzard's height includes blank spacer
        -- lines for widget overlays.  Measure our actual content chain instead.
        ownedTip:SetHeight(1)

        local frameTop = ownedTip:GetTop()
        local okBot, anchorBottom = pcall(prevAnchor.GetBottom, prevAnchor)
        anchorBottom = okBot and Helpers.SafeToNumber(anchorBottom, nil) or nil
        frameTop = Helpers.SafeToNumber(frameTop, nil)
        if frameTop and anchorBottom and frameTop > anchorBottom then
            local contentHeight = frameTop - anchorBottom + padding
            if healthBar and healthBar:IsShown() then
                contentHeight = contentHeight + 8
            end
            ownedTip:SetHeight(math_max(contentHeight, 40))
        else
            -- Anchor measurement failed (frame not yet laid out on first display,
            -- or tainted). Blizzard's height doesn't account for our merged
            -- embedded content — use a line-count estimate instead.
            -- Add fontSize as buffer for word-wrapped lines (long stat descriptions,
            -- quest reward text, etc. that wrap to 2+ visual rows).
            local estHeight = headerSize + ((#lines - 1) * (fontSize + lineGap)) + padding * 2 + fontSize
            if healthBar and healthBar:IsShown() then estHeight = estHeight + 8 end
            ownedTip:SetHeight(math_max(estHeight, 40))
        end
    elseif blizzTip then
        -- Blizzard's height covers its own lines.  If we appended extra lines
        -- (spell ID, icon ID) that don't exist on the Blizzard tooltip, add
        -- their estimated height.  SafeToNumber handles secret GetHeight().
        local extraLines = ownedTip._extraLines or 0
        if extraLines > 0 then
            local okH, blizzH = pcall(blizzTip.GetHeight, blizzTip)
            blizzH = okH and Helpers.SafeToNumber(blizzH, nil) or nil
            if blizzH then
                local extra = extraLines * (fontSize + lineGap)
                ownedTip:SetHeight(math_max(blizzH + extra, 40))
            else
                -- Blizzard height is secret — full line-count estimate
                local estHeight = headerSize + ((#lines - 1) * (fontSize + lineGap)) + padding * 2
                ownedTip:SetHeight(math_max(estHeight, 40))
            end
        else
            pcall(ownedTip.SetHeight, ownedTip, blizzTip:GetHeight())
        end
    else
        local estHeight = headerSize + ((#lines - 1) * (fontSize + lineGap)) + padding * 2
        ownedTip:SetHeight(math_max(estHeight, 40))
    end

    -- Apply skin (colors may have changed)
    ApplySkin(ownedTip)
end

---------------------------------------------------------------------------
-- SHOPPING TOOLTIP ANCHORING
-- Shopping tooltips anchor to the side of their parent tooltip.
-- Blizzard positions them relative to GameTooltip (off-screen), so we
-- do our own side-by-side chaining relative to QUI_Tooltip.
---------------------------------------------------------------------------

local function AnchorShoppingTooltips(mainOwnedTip, aboutToShow)
    if not mainOwnedTip or not mainOwnedTip:IsShown() then return end

    -- Collect visible shopping tooltips in order.
    -- `aboutToShow` is an owned tooltip that's about to be shown (not yet
    -- IsShown) but should be included in the chain — prevents a 1-frame
    -- flash at the wrong position before the tooltip is anchored.
    -- Iterates all registered tooltip pairs to catch both Blizzard and
    -- external shopping frames (e.g., third-party comparison tooltips).
    local shoppingFrames = {}
    for _, owned in ipairs(ownedFrames) do
        if owned._isShoppingTooltip then
            if owned:IsShown() or owned == aboutToShow then
                shoppingFrames[#shoppingFrames + 1] = owned
            end
        end
    end
    if #shoppingFrames == 0 then return end

    -- Decide side: anchor right if main tooltip is in the left half of screen,
    -- otherwise anchor left. This keeps comparisons visible on-screen.
    local mainLeft = mainOwnedTip:GetLeft() or 0
    local screenWidth = GetScreenWidth() or 1920
    local anchorRight = (Helpers.SafeToNumber(mainLeft, 0) < (screenWidth / 2))

    -- Chain: first shopping tooltip anchors to main, subsequent ones chain together
    for i, owned in ipairs(shoppingFrames) do
        owned:ClearAllPoints()
        local relativeTo = (i == 1) and mainOwnedTip or shoppingFrames[i - 1]
        if anchorRight then
            owned:SetPoint("TOPLEFT", relativeTo, "TOPRIGHT", 2, 0)
        else
            owned:SetPoint("TOPRIGHT", relativeTo, "TOPLEFT", -2, 0)
        end
    end
end

---------------------------------------------------------------------------
-- ANCHORING
---------------------------------------------------------------------------

-- Map Blizzard ANCHOR_* types (from SetOwner) to SetPoint equivalents:
-- { tooltip anchor point, owner anchor point }
-- Blizzard aligns the tooltip edge flush with the owner edge, top/left aligned.
local OWNER_ANCHOR_MAP = {
    ANCHOR_TOP        = { "BOTTOMLEFT",  "TOPLEFT" },
    ANCHOR_BOTTOM     = { "TOPLEFT",     "BOTTOMLEFT" },
    ANCHOR_LEFT       = { "TOPRIGHT",    "TOPLEFT" },
    ANCHOR_RIGHT      = { "TOPLEFT",     "TOPRIGHT" },
    ANCHOR_TOPLEFT    = { "BOTTOMRIGHT", "TOPLEFT" },
    ANCHOR_TOPRIGHT   = { "BOTTOMLEFT",  "TOPRIGHT" },
    ANCHOR_BOTTOMLEFT = { "TOPRIGHT",    "BOTTOMLEFT" },
    ANCHOR_BOTTOMRIGHT= { "TOPLEFT",     "BOTTOMRIGHT" },
}

local function AnchorOwnedTooltip(ownedTip, blizzTip, settings)
    if not ownedTip or not blizzTip then return end

    -- Shopping/comparison tooltips: re-anchor all visible ones as a chain
    -- beside the main tooltip. Don't use Blizzard's anchor points — they're
    -- relative to GameTooltip which is off-screen at -10000.
    -- Dynamically resolve the parent: use the static _parentOwnedTip if shown,
    -- otherwise find any visible non-shopping owned tooltip as the anchor.
    if ownedTip._isShoppingTooltip then
        local parent = ownedTip._parentOwnedTip
        if not parent or not parent:IsShown() then
            for _, candidate in ipairs(ownedFrames) do
                if not candidate._isShoppingTooltip and candidate:IsShown() then
                    parent = candidate
                    break
                end
            end
        end
        if parent then
            AnchorShoppingTooltips(parent, ownedTip)
        end
        return
    end

    -- Cursor follow mode (primary tooltips only)
    if settings and settings.anchorToCursor then
        Provider:PositionTooltipAtCursor(ownedTip, settings)
        return
    end

    -- Mirror Blizzard tooltip position using the cached anchor (captured
    -- from the SetPoint hook before we moved the tooltip off-screen).
    local cached = blizzAnchorCache[blizzTip]
    if cached and cached.point then
        local x = Helpers.SafeToNumber(cached.x, 0)
        local y = Helpers.SafeToNumber(cached.y, 0)
        ownedTip:ClearAllPoints()
        if cached.relativeTo then
            ownedTip:SetPoint(cached.point, cached.relativeTo, cached.relPoint or cached.point, x, y)
        else
            ownedTip:SetPoint(cached.point, UIParent, cached.relPoint or "BOTTOMLEFT", x, y)
        end
        return
    end

    -- Fallback: use the owner + anchor type from SetOwner. Blizzard's
    -- ANCHOR_* types position via C-side code (no Lua SetPoint fires),
    -- so blizzAnchorCache won't have an entry. Derive the equivalent
    -- SetPoint from the anchor type.
    local ownerInfo = blizzOwnerCache[blizzTip]
    if ownerInfo and ownerInfo.owner and ownerInfo.anchorType then
        local owner = ownerInfo.owner
        local anchorType = ownerInfo.anchorType
        local mapping = OWNER_ANCHOR_MAP[anchorType]
        if mapping and owner.GetCenter then
            local oX = Helpers.SafeToNumber(ownerInfo.offsetX, 0)
            local oY = Helpers.SafeToNumber(ownerInfo.offsetY, 0)
            ownedTip:ClearAllPoints()
            ownedTip:SetPoint(mapping[1], owner, mapping[2], oX, oY)
            return
        end
    end

    -- Last fallback: cursor position
    Provider:PositionTooltipAtCursor(ownedTip, settings)
end

---------------------------------------------------------------------------
-- CURSOR FOLLOW (OnUpdate for owned frames)
---------------------------------------------------------------------------

local cursorFollowFrame = nil

local function SetupCursorFollow()
    if cursorFollowFrame then return end
    cursorFollowFrame = CreateFrame("Frame")
    cursorFollowFrame:SetScript("OnUpdate", function()
        local settings = Provider:GetSettings()
        if not settings or not settings.anchorToCursor then return end

        for _, ownedTip in ipairs(ownedFrames) do
            -- Skip shopping tooltips — they anchor to the main tooltip, not cursor
            if ownedTip:IsShown() and not ownedTip._isShoppingTooltip then
                Provider:PositionTooltipAtCursor(ownedTip, settings)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- MODIFIER STATE WATCHER
-- Hide shopping tooltips when Shift is released. Third-party addons
-- (world quest lists, etc.) toggle comparison tooltips via Shift but
-- may not fire a hide signal our engine can catch.
---------------------------------------------------------------------------
local modifierFrame = nil

local function SetupModifierWatcher()
    if modifierFrame then return end
    modifierFrame = CreateFrame("Frame")
    modifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    modifierFrame:SetScript("OnEvent", function(_, _, key, down)
        if down == 1 then return end -- only care about key release
        -- Check if any shift key was released
        if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
        -- Hide all visible shopping tooltips
        for blizz, owned in pairs(tooltipPairs) do
            if owned._isShoppingTooltip and owned:IsShown() then
                owned:Hide()
                owned._contentFingerprint = nil
                owned._contentHash = nil
                owned._shoppingLastRefresh = nil
                activelyHandling[blizz] = nil
                pendingPopulate[blizz] = nil
            end
        end
    end)
end

---------------------------------------------------------------------------
-- CLASS COLOR PLAYER NAMES
-- Apply class color to the first line (player name) for Unit tooltips.
-- tooltipType is optional — when nil (watcher path), we detect unit tooltips
-- by checking GetUnit directly.
---------------------------------------------------------------------------
local function ApplyClassColorName(lines, settings, blizzTip, tooltipType)
    if not settings or not settings.classColorName then return end
    if tooltipType and tooltipType ~= Enum.TooltipDataType.Unit then return end
    if #lines == 0 then return end

    -- Resolve unit token from the Blizzard tooltip
    local ok, _, unit = pcall(blizzTip.GetUnit, blizzTip)
    if not ok or not unit then return end
    if Helpers.IsSecretValue(unit) then
        unit = UnitExists("mouseover") and "mouseover" or nil
        if not unit then return end
    end

    local okP, isP = pcall(UnitIsPlayer, unit)
    if not okP or not isP then return end

    local okC, _, classToken = pcall(UnitClass, unit)
    if not okC or not classToken then return end

    local classColor
    if InCombatLockdown() then
        if C_ClassColor and C_ClassColor.GetClassColor then
            local okClr, clr = pcall(C_ClassColor.GetClassColor, classToken)
            if okClr and clr then classColor = clr end
        end
    else
        classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    end

    if classColor then
        lines[1].lr = classColor.r
        lines[1].lg = classColor.g
        lines[1].lb = classColor.b
    end
end

-- Build a quick content fingerprint from tooltip lines.
-- Used to skip redundant repopulation when Blizzard's comparison system
-- repeatedly fires TooltipDataProcessor with identical content.
-- Uses only the first line (item name) — Blizzard's comparison cycling
-- alternates line counts mid-setup (e.g., 9↔13) while showing the same
-- item. Including line count would defeat the dedup.
local function BuildContentFingerprint(lines)
    local n = #lines
    if n == 0 then return "" end
    local first = lines[1].leftText or ""
    -- pcall in case text is a secret value
    local okFirst, firstStr = pcall(tostring, first)
    if not okFirst then firstStr = "?" end
    return firstStr
end

--- Build a full content hash from all line texts. Used to detect content
--- changes even when line count stays the same (e.g., external addons
--- replacing blank lines with data, or async stat comparisons arriving).
local function BuildContentHash(lines)
    local parts = {}
    for i, l in ipairs(lines) do
        local lt = l.leftText
        if lt and type(issecretvalue) == "function" and issecretvalue(lt) then
            parts[i] = "~"
        else
            local okS, s = pcall(tostring, lt or "")
            parts[i] = okS and s or "~"
        end
    end
    return table.concat(parts, "|")
end

---------------------------------------------------------------------------
-- VISIBILITY WATCHER
-- Monitors Blizzard tooltip visibility without hooking their frames
---------------------------------------------------------------------------

local function SetupVisibilityWatcher()
    local watcher = CreateFrame("Frame")
    local wasShown = {}
    watcher:SetScript("OnUpdate", function()
        local settings = Provider:GetSettings()
        local enabled = settings and settings.enabled

        for blizzTip, ownedTip in pairs(tooltipPairs) do
            -- Skip embedded sub-tooltips — their content is merged into the
            -- main tooltip. Don't create separate owned frames for them.
            -- Alpha=0 only (not Hide) — Blizzard needs them shown for comparison logic.
            if IsEmbeddedSubTooltip(blizzTip) then
                pcall(blizzTip.StopAnimating, blizzTip)
                if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, blizzTip) end
                pcall(blizzTip.SetClampedToScreen, blizzTip, false)
                pcall(blizzTip.SetAlpha, blizzTip, 0)
                                pcall(blizzTip.ClearAllPoints, blizzTip)
                pcall(blizzTip.SetPoint, blizzTip, "TOP", UIParent, "BOTTOM", 0, -10000)
                wasShown[blizzTip] = false
            else

            local okShown, shown = pcall(blizzTip.IsShown, blizzTip)
            if not okShown then shown = false end

            -- Suppress ALL Blizzard tooltips we have a pair for (when enabled).
            -- The OnShow hook sets activelyHandling, so this catches every frame.
            if shown and enabled and activelyHandling[blizzTip] then
                pcall(blizzTip.StopAnimating, blizzTip)
                if UIFrameFadeRemoveFrame then
                    pcall(UIFrameFadeRemoveFrame, blizzTip)
                end
                pcall(blizzTip.SetAlpha, blizzTip, 0)
                pcall(blizzTip.SetFrameLevel, blizzTip, 1)

                -- Hide the embedded ItemTooltip wrapper and its sub-tooltip.
                -- SetAlpha(0) is insufficient — Blizzard's animation system
                -- overrides static alpha. Hide() removes the frame from the
                -- render tree entirely. But Hide() on a GameTooltip clears its
                -- lines, so we must cache the embedded content BEFORE hiding.
                -- Move the embedded ItemTooltip and its sub-tooltip offscreen.
                -- Do NOT use Hide() — it triggers Blizzard's comparison tooltip
                -- teardown, killing ShoppingTooltip1/2. Instead, disable clamping
                -- (so offscreen positioning sticks) and move them off-screen.
                -- SetAlpha(0) alone is insufficient because Blizzard's animation
                -- system overrides static alpha on these frames.
                if blizzTip == GameTooltip and blizzTip.ItemTooltip then
                    local it = blizzTip.ItemTooltip
                    local okIT, itShown = pcall(it.IsShown, it)
                    if okIT and itShown then
                        pcall(it.SetClampedToScreen, it, false)
                        pcall(it.SetAlpha, it, 0)
                                                pcall(it.ClearAllPoints, it)
                        pcall(it.SetPoint, it, "TOP", UIParent, "BOTTOM", 0, -10000)
                    end
                    if it.Tooltip then
                        pcall(it.Tooltip.SetClampedToScreen, it.Tooltip, false)
                        pcall(it.Tooltip.SetAlpha, it.Tooltip, 0)
                                                pcall(it.Tooltip.ClearAllPoints, it.Tooltip)
                        pcall(it.Tooltip.SetPoint, it.Tooltip, "TOP", UIParent, "BOTTOM", 0, -10000)
                    end
                end
            end

            -- Detect new tooltip content: either a show transition (wasShown
            -- was false) or a SetOwner call (owner changed while continuously
            -- shown, e.g., moving between adjacent CDM icons or micro menu
            -- buttons without a hide/show gap).
            local isNewContent = (not wasShown[blizzTip] and shown and enabled)
                             or (ownerChanged[blizzTip] and shown and enabled)
            ownerChanged[blizzTip] = nil

            if isNewContent then
                -- Shopping tooltips defer to the continuous check below.
                if ownedTip._isShoppingTooltip then
                    activelyHandling[blizzTip] = true
                elseif not pendingPopulate[blizzTip] then
                -- Tooltip just became visible or changed target.
                -- If not already populated by PostCall (no pending populate and
                -- owned tip not shown), do a deferred read. This catches tooltips
                -- that bypass TooltipDataProcessor (world quest map pins, manual
                -- AddLine tooltips, etc.).
                    activelyHandling[blizzTip] = true
                    pendingPopulate[blizzTip] = (pendingPopulate[blizzTip] or 0) + 1
                    local myToken = pendingPopulate[blizzTip]
                    C_Timer.After(0, function()
                        if pendingPopulate[blizzTip] ~= myToken then return end
                        pendingPopulate[blizzTip] = nil
                        -- Re-check embedded status — flag may have been set after
                        -- the watcher first saw this tooltip.
                        if IsEmbeddedSubTooltip(blizzTip) then return end
                        local okStill, still = pcall(blizzTip.IsShown, blizzTip)
                        if not okStill or not still then return end
                        local lines, hasExtra = ReadAllContent(blizzTip)
                        if #lines > 0 then
                            ownedTip._hasEmbeddedContent = hasExtra
                            ApplyClassColorName(lines, settings, blizzTip)
                            PopulateTooltip(ownedTip, lines, nil, nil, blizzTip)
                            AnchorOwnedTooltip(ownedTip, blizzTip, settings)
                            ownedTip:Show()
                        end
                        -- Late content re-checks — widget content, embedded
                        -- items, and async addon additions. Use content hash
                        -- instead of line count to catch modifications to
                        -- existing lines (not just additions).
                        local baseHash = BuildContentHash(lines)
                        ownedTip._contentHash = baseHash
                        local delays = { 0.2, 0.5 }
                        for _, delay in ipairs(delays) do
                            C_Timer.After(delay, function()
                                if pendingPopulate[blizzTip] then return end
                                if IsEmbeddedSubTooltip(blizzTip) then return end
                                local okS, s = pcall(blizzTip.IsShown, blizzTip)
                                if not okS or not s then return end
                                local lateLines, lateHasExtra = ReadAllContent(blizzTip)
                                if #lateLines == 0 then return end
                                local lateHash = BuildContentHash(lateLines)
                                if lateHash ~= ownedTip._contentHash then
                                    ownedTip._contentHash = lateHash
                                    ownedTip._hasEmbeddedContent = lateHasExtra
                                    ApplyClassColorName(lateLines, settings, blizzTip)
                                    PopulateTooltip(ownedTip, lateLines, nil, nil, blizzTip)
                                    AnchorOwnedTooltip(ownedTip, blizzTip, settings)
                                    ownedTip:Show()
                                end
                            end)
                        end
                    end)
                end
            elseif wasShown[blizzTip] and not shown then
                -- Shopping tooltip lifetime is tied to GameTooltip OnHide.
                if not ownedTip._isShoppingTooltip then
                    local hideDelay = settings and settings.hideDelay or 0
                    StartFadeOut(ownedTip, hideDelay)
                    activelyHandling[blizzTip] = nil
                end
            end

            -- Shopping tooltip continuous check: throttled per-frame content
            -- sync (0.3s initial settle, 0.15s updates). Detects content changes
            -- via full text hash since Blizzard fills stat comparisons async.
            if ownedTip._isShoppingTooltip then
                local okBlizzShown, blizzShown = pcall(blizzTip.IsShown, blizzTip)
                local now = GetTime()
                local lastRefresh = ownedTip._shoppingLastRefresh or 0
                local delay = ownedTip:IsShown() and 0.15 or 0.3
                local canRefresh = (now - lastRefresh) >= delay
                if okBlizzShown and blizzShown and canRefresh then
                    local curLines = ReadAllContent(blizzTip)
                    if #curLines > 0 then
                        local contentHash = BuildContentHash(curLines)

                        local curFP = BuildContentFingerprint(curLines)
                        local itemChanged = curFP ~= (ownedTip._contentFingerprint or "")
                        local needsUpdate = not ownedTip:IsShown()
                            or itemChanged
                            or contentHash ~= ownedTip._contentHash

                        if needsUpdate then
                            local wasHidden = not ownedTip:IsShown()
                            ownedTip._contentFingerprint = curFP
                            ownedTip._contentHash = contentHash
                            ownedTip._shoppingLastRefresh = now
                            ownedTip._hasEmbeddedContent = false
                            ApplyClassColorName(curLines, settings, blizzTip)
                            PopulateTooltip(ownedTip, curLines, nil, nil, blizzTip)
                            AnchorOwnedTooltip(ownedTip, blizzTip, settings)
                            if wasHidden then
                                ownedTip:Show()
                            end
                        end
                    end
                end
            end
            wasShown[blizzTip] = shown

            end -- else (not embedded sub-tooltip)
        end
    end)
end

---------------------------------------------------------------------------
-- TOOLTIP DATA PROCESSOR HANDLERS
---------------------------------------------------------------------------

-- Appends Spell ID / Icon ID lines to the lines table for our owned tooltip.
-- Returns the number of lines added (0 if none), so the caller can adjust
-- the owned frame height by that many extra lines.
local function AppendSpellIDLines(lines, settings, tooltipData, tooltipType)
    if not settings or not settings.showSpellIDs or not tooltipData then return 0 end
    local spellID = tooltipData.id
    if not spellID or type(spellID) ~= "number" then return 0 end
    if type(issecretvalue) == "function" and issecretvalue(spellID) then return 0 end
    if tooltipType ~= Enum.TooltipDataType.Spell and tooltipType ~= Enum.TooltipDataType.Aura then return 0 end

    -- Check if lines already have spell ID (other addons may have added it)
    for _, l in ipairs(lines) do
        if l.leftText then
            local okFind, found = pcall(string.find, l.leftText, "Spell ID")
            if okFind and found then return 0 end
        end
    end

    local added = 0
    lines[#lines + 1] = { leftText = " ", lr = 1, lg = 1, lb = 1 }
    added = added + 1
    lines[#lines + 1] = {
        leftText = "Spell ID:", rightText = tostring(spellID),
        lr = 0.5, lg = 0.8, lb = 1, rr = 1, rg = 1, rb = 1,
    }
    added = added + 1

    local iconID = nil
    if C_Spell and C_Spell.GetSpellTexture then
        local okIcon, result = pcall(C_Spell.GetSpellTexture, spellID)
        if okIcon and result and type(result) == "number" then
            iconID = result
        end
    end
    if iconID then
        lines[#lines + 1] = {
            leftText = "Icon ID:", rightText = tostring(iconID),
            lr = 0.5, lg = 0.8, lb = 1, rr = 1, rg = 1, rb = 1,
        }
        added = added + 1
    end
    return added
end

local function HandleTooltipData(blizzTip, tooltipData, tooltipType)
    local ownedTip = tooltipPairs[blizzTip]
    if not ownedTip then return end

    -- Skip if this frame is currently used as an embedded sub-tooltip.
    -- Its content is already merged into the main tooltip via ReadEmbeddedContent.
    if IsEmbeddedSubTooltip(blizzTip) then
        pcall(blizzTip.SetAlpha, blizzTip, 0)
        return
    end

    -- Mark as actively handled and suppress Blizzard tooltip.
    activelyHandling[blizzTip] = true
    pcall(blizzTip.StopAnimating, blizzTip)
    if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, blizzTip) end
    pcall(blizzTip.SetAlpha, blizzTip, 0)

    -- Check visibility
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled then
        return
    end

    local owner = nil
    local okOwner
    okOwner, owner = pcall(blizzTip.GetOwner, blizzTip)
    if not okOwner then owner = nil end

    -- Shopping tooltips inherit visibility from GameTooltip.
    if not ownedTip._isShoppingTooltip then
        -- Context/visibility check
        local context = Provider:GetTooltipContext(owner)
        if not Provider:ShouldShowTooltip(context) then
            return
        end

        -- Check if owner is faded out
        if Provider:IsOwnerFadedOut(owner) then
            return
        end
    end

    -- Shopping tooltips defer entirely to the watcher — Blizzard adds stat
    -- comparison lines asynchronously, so showing partial content causes a
    -- visible flash. Only reset state when the item changes (fingerprint
    -- differs). HandleTooltipData fires every frame for shopping tooltips —
    -- resetting _shoppingLastRefresh each time would starve the watcher.
    if ownedTip._isShoppingTooltip then
        local lines = ReadAllContent(blizzTip)
        if #lines > 0 then
            local fp = BuildContentFingerprint(lines)
            if fp ~= ownedTip._contentFingerprint then
                ownedTip._contentFingerprint = fp
                ownedTip._contentHash = nil
                ownedTip._shoppingLastRefresh = GetTime()
                if ownedTip:IsShown() then
                    ownedTip:Hide()
                end
            end
        end
        return
    end

    -- DEFERRED POPULATE: Don't show the owned tooltip immediately. External
    -- addons hook OnTooltipSetItem (which fires after PostCall) and call
    -- AddLine + Show on the Blizzard tooltip. If we populate now, the owned
    -- tooltip flashes with incomplete content for 1 frame before the deferred
    -- re-read catches the added lines. Instead, defer to next frame so all
    -- synchronous hooks have already run by the time we read content.
    -- During rapid transitions (hover item A → B), hide stale content from
    -- the previous tooltip immediately to avoid a flash of old content.
    if ownedTip:IsShown() then
        local lines = ReadAllContent(blizzTip)
        local fp = BuildContentFingerprint(lines)
        if fp ~= (ownedTip._contentFingerprint or "") then
            ownedTip:Hide()
        end
    end

    -- Token-based deferred populate: captures other addons' AddLine() calls
    -- that fire synchronously after PostCall (e.g., OnTooltipSetItem hooks).
    -- Each new tooltip data supersedes the previous deferred call (rapid mouse-
    -- over changes: the old callback sees a stale token and bails out).
    pendingPopulate[blizzTip] = (pendingPopulate[blizzTip] or 0) + 1
    local myToken = pendingPopulate[blizzTip]

    C_Timer.After(0, function()
        -- Superseded by a newer tooltip data event
        if pendingPopulate[blizzTip] ~= myToken then return end
        pendingPopulate[blizzTip] = nil

        -- Re-check: tooltip may have hidden during the defer
        local okStillShown, stillShown = pcall(blizzTip.IsShown, blizzTip)
        if not okStillShown or not stillShown then
            ownedTip:Hide()
            return
        end

        -- Read all content (text lines + embedded items + widgets).
        -- By now, all synchronous hooks (OnTooltipSetItem etc.) have run.
        local updatedLines, hasExtra = ReadAllContent(blizzTip)
        if #updatedLines == 0 then
            ownedTip:Hide()
            return
        end

        ownedTip._hasEmbeddedContent = hasExtra
        local extraLines = AppendSpellIDLines(updatedLines, settings, tooltipData, tooltipType)
        ownedTip._extraLines = extraLines
        ApplyClassColorName(updatedLines, settings, blizzTip, tooltipType)
        PopulateTooltip(ownedTip, updatedLines, tooltipType, tooltipData, blizzTip)
        AnchorOwnedTooltip(ownedTip, blizzTip, settings)
        ownedTip:Show()

        -- Store content hash for late re-checks. Use hash instead of line
        -- count so we also catch external addons that modify existing lines
        -- or use C_Timer to add content asynchronously.
        local baseHash = BuildContentHash(updatedLines)
        ownedTip._contentFingerprint = BuildContentFingerprint(updatedLines)
        ownedTip._contentHash = baseHash

        -- Late content re-checks — widget content, embedded items, and
        -- async addon additions. Check at increasing delays; only update
        -- when the content hash actually changed.
        local deferDelays = { 0.2, 0.5 }
        for _, delay in ipairs(deferDelays) do
            C_Timer.After(delay, function()
                if pendingPopulate[blizzTip] then return end
                local okStill2, still2 = pcall(blizzTip.IsShown, blizzTip)
                if not okStill2 or not still2 then return end
                local lateLines, lateHasExtra = ReadAllContent(blizzTip)
                if #lateLines == 0 then return end
                local lateExtra = AppendSpellIDLines(lateLines, settings, tooltipData, tooltipType)
                local lateHash = BuildContentHash(lateLines)
                if lateHash ~= ownedTip._contentHash then
                    ownedTip._contentHash = lateHash
                    ownedTip._hasEmbeddedContent = lateHasExtra
                    ownedTip._extraLines = lateExtra
                    ApplyClassColorName(lateLines, settings, blizzTip, tooltipType)
                    PopulateTooltip(ownedTip, lateLines, tooltipType, tooltipData, blizzTip)
                    AnchorOwnedTooltip(ownedTip, blizzTip, settings)
                    ownedTip:Show()
                end
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- INITIALIZE
---------------------------------------------------------------------------

function OwnedEngine:Initialize()
    Provider = ns.TooltipProvider

    -- Create main owned tooltip (replaces GameTooltip)
    local mainTip = CreateOwnedTooltip("QUI_Tooltip")
    mainTip._healthBar = CreateHealthBar(mainTip)

    -- Create all owned tooltip family members.
    -- Shopping/comparison tooltips are included — they're GameTooltip-family
    -- frames that fire TooltipDataProcessor events via SetCompareItem.
    -- `shopping` field tags comparison tooltips for special anchoring.
    local familyDefs = {
        { blizz = "GameTooltip",              name = "QUI_Tooltip",                   frame = mainTip },
        { blizz = "ItemRefTooltip",           name = "QUI_ItemRefTooltip"             },
        { blizz = "NamePlateTooltip",         name = "QUI_NamePlateTooltip"           },
        { blizz = "GameTooltipTooltip",       name = "QUI_GameTooltipTooltip"         },
        { blizz = "WorldMapTooltip",          name = "QUI_WorldMapTooltip"            },
        { blizz = "SmallTextTooltip",         name = "QUI_SmallTextTooltip"           },
        { blizz = "ReputationParagonTooltip", name = "QUI_ReputationParagonTooltip"   },
        { blizz = "ShoppingTooltip1",         name = "QUI_ShoppingTooltip1",          shopping = true },
        { blizz = "ShoppingTooltip2",         name = "QUI_ShoppingTooltip2",          shopping = true },
        { blizz = "ItemRefShoppingTooltip1",  name = "QUI_ItemRefShoppingTooltip1",   shopping = true },
        { blizz = "ItemRefShoppingTooltip2",  name = "QUI_ItemRefShoppingTooltip2",   shopping = true },
        { blizz = "WorldMapCompareTooltip1",  name = "QUI_WorldMapCompareTooltip1",   shopping = true },
        { blizz = "WorldMapCompareTooltip2",  name = "QUI_WorldMapCompareTooltip2",   shopping = true },
    }

    for _, def in ipairs(familyDefs) do
        local blizzFrame = _G[def.blizz]
        if blizzFrame then
            local ownedFrame = def.frame or CreateOwnedTooltip(def.name)
            if def.shopping then
                ownedFrame._isShoppingTooltip = true
                ownedFrame._parentOwnedTip = mainTip
            end
            tooltipPairs[blizzFrame] = ownedFrame
            ownedFrames[#ownedFrames + 1] = ownedFrame

            -- Prepare frame for conditional suppression.
            -- SetClampedToScreen(false) allows off-screen positioning when active.
            -- Actual suppression only happens when ShouldSuppressBlizz() returns true.
            local isShopping = def.shopping
            pcall(blizzFrame.SetFrameLevel, blizzFrame, 1)
            if not isShopping then
                pcall(blizzFrame.SetClampedToScreen, blizzFrame, false)
            end

            -- Hook SetAlpha: catch any Blizzard code (fade-in animations,
            -- SharedTooltip_SetBackdropStyle, etc.) that resets alpha > 0
            -- while we're suppressing. This prevents the 1-frame flash where
            -- the Blizzard tooltip becomes visible during tooltip transitions.
            local alphaGuard = false
            hooksecurefunc(blizzFrame, "SetAlpha", function(self, alpha)
                if alphaGuard then return end
                if alpha and alpha > 0 and ShouldSuppressBlizz(self) then
                    local s = Provider and Provider:GetSettings()
                    if s and s.enabled then
                        alphaGuard = true
                        pcall(self.SetAlpha, self, 0)

                        alphaGuard = false
                    end
                end
            end)

            -- Hook SetPoint: Blizzard re-anchors the tooltip after Show()
            -- (e.g., to the map pin frame), overriding our offscreen positioning
            -- from OnShow. This closes the 1-frame gap between Show and OnUpdate.
            -- Also cache the original anchor so we can mirror it when not using
            -- cursor-follow mode.
            if not isShopping then
                local pointGuard = false
                hooksecurefunc(blizzFrame, "SetPoint", function(self, point, relativeTo, relPoint, xOfs, yOfs)
                    if pointGuard then return end
                    if yOfs == -10000 then return end -- our own offscreen call
                    -- Cache the original Blizzard anchor before we override it
                    blizzAnchorCache[self] = {
                        point = point,
                        relativeTo = relativeTo,
                        relPoint = relPoint,
                        x = xOfs,
                        y = yOfs,
                    }
                    if ShouldSuppressBlizz(self) then
                        local s = Provider and Provider:GetSettings()
                        if s and s.enabled then
                            pointGuard = true
                            pcall(self.ClearAllPoints, self)
                            pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                            pointGuard = false
                        end
                    end
                end)
            end

            -- Hook SetOwner: world quest map pins call SetOwner(pin, "ANCHOR_RIGHT")
            -- which re-anchors the tooltip to the pin frame, overriding our offscreen
            -- positioning. Re-suppress immediately after Blizzard re-anchors.
            if not isShopping then
                hooksecurefunc(blizzFrame, "SetOwner", function(self, owner, anchorType, offsetX, offsetY)
                    -- Signal that a new tooltip target was set. The watcher
                    -- uses this to trigger a deferred re-read even when the
                    -- tooltip stays continuously shown (e.g., moving between
                    -- adjacent buttons without a hide/show gap).
                    -- Only flag as changed when the owner actually differs —
                    -- Blizzard's UpdateTooltip re-calls SetOwner with the SAME
                    -- pin every ~0.2s. Treating each call as new content causes
                    -- repeated re-reads that surface accumulating widget frames
                    -- (widget set cleanup fails due to taint on the suppressed
                    -- tooltip), making the owned tooltip grow indefinitely.
                    local prev = blizzOwnerCache[self]
                    if not prev or prev.owner ~= owner then
                        ownerChanged[self] = true
                    end
                    -- Cache the owner and anchor type for positioning when
                    -- anchorToCursor is off. SetOwner with ANCHOR_* types
                    -- positions via C-side code (no Lua SetPoint fires), so
                    -- blizzAnchorCache won't capture it.
                    blizzOwnerCache[self] = { owner = owner, anchorType = anchorType, offsetX = offsetX, offsetY = offsetY }
                    -- Clear stale SetPoint cache — SetOwner starts a new anchor
                    blizzAnchorCache[self] = nil
                    if ShouldSuppressBlizz(self) then
                        local s = Provider and Provider:GetSettings()
                        if s and s.enabled then
                            pcall(self.StopAnimating, self)
                            if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, self) end
                            pcall(self.SetAlpha, self, 0)

                            pcall(self.ClearAllPoints, self)
                            pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                        end
                    end
                end)
            end

            -- HookScript OnShow + OnUpdate: UNCONDITIONAL suppression.
            -- Every frame in tooltipPairs is one we intend to own. When it shows,
            -- immediately suppress it and set activelyHandling so the watcher's
            -- deferred populate picks it up. This catches tooltips that bypass
            -- TooltipDataProcessor (world quest map pins, manual AddLine, etc.).
            if blizzFrame.HookScript then
                pcall(blizzFrame.HookScript, blizzFrame, "OnShow", function(self)
                    local s = Provider and Provider:GetSettings()
                    if not s or not s.enabled then return end
                    -- Skip if this frame is currently used as an embedded sub-tooltip.
                    -- Its content is already merged into the main tooltip.
                    -- Alpha=0 only — NOT Hide(). Blizzard needs it "shown" for
                    -- comparison tooltip logic (ShoppingTooltip1/2).
                    if IsEmbeddedSubTooltip(self) then
                        pcall(self.StopAnimating, self)
                        if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, self) end
                        pcall(self.SetClampedToScreen, self, false)
                        pcall(self.SetAlpha, self, 0)
                                                pcall(self.ClearAllPoints, self)
                        pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                        return
                    end
                    -- Claim this tooltip for our engine
                    activelyHandling[self] = true
                    pcall(self.StopAnimating, self)
                    if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, self) end
                    pcall(self.SetAlpha, self, 0)
                    -- Move ALL tooltips offscreen (including shopping). Alpha=0
                    -- alone is insufficient — Blizzard's comparison manager and
                    -- backdrop styling can reset alpha between hook calls, making
                    -- the frame flash. Offscreen + alpha=0 ensures invisibility.
                    -- IsShown() still returns true (comparison logic satisfied).
                    if isShopping then
                        pcall(self.SetClampedToScreen, self, false)
                    end
                    pcall(self.ClearAllPoints, self)
                    pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                end)
                pcall(blizzFrame.HookScript, blizzFrame, "OnUpdate", function(self)
                    if not ShouldSuppressBlizz(self) then return end
                    local s = Provider and Provider:GetSettings()
                    if not s or not s.enabled then return end
                    pcall(self.SetAlpha, self, 0)
                    if isShopping then
                        pcall(self.SetClampedToScreen, self, false)
                    end
                    pcall(self.ClearAllPoints, self)
                    pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                end)
                -- OnHide: immediately hide our owned tooltip and clear state.
                -- This is more reliable than the watcher's frame-rate-dependent
                -- wasShown comparison for detecting hide transitions.
                -- OnHide: defer hide by 1 frame to avoid flash from rapid hide/show
                -- cycles (Blizzard clears and re-populates tooltips during setup).
                -- If the tooltip re-shows within that frame, cancel the hide.
                pcall(blizzFrame.HookScript, blizzFrame, "OnHide", function(self)
                    -- Shopping tooltips: don't hide via OnHide. Blizzard's
                    -- comparison system cycles shopping tooltips through
                    -- hide/show during setup — reacting to OnHide causes
                    -- a visible flash on the owned replacement. Instead,
                    -- shopping tooltip lifetime is tied to the main tooltip
                    -- (cleaned up when GameTooltip hides below).
                    if isShopping then
                        return
                    end

                    C_Timer.After(0, function()
                        -- If Blizzard re-showed the tooltip (refresh cycle), don't hide
                        local okShown, shown = pcall(self.IsShown, self)
                        if okShown and shown then return end
                        local ownedTip = tooltipPairs[self]
                        if ownedTip then
                            local s = Provider and Provider:GetSettings()
                            local hideDelay = s and s.hideDelay or 0
                            StartFadeOut(ownedTip, hideDelay)
                        end
                        activelyHandling[self] = nil
                        pendingPopulate[self] = nil
                        blizzAnchorCache[self] = nil
                        blizzOwnerCache[self] = nil

                        -- When main GameTooltip hides, clean up embedded state
                        -- and shopping tooltips. Clear the embedded flag so
                        -- GameTooltipTooltip can be used as a standalone tooltip
                        -- in other contexts.
                        if self == GameTooltip then
                            local itemTooltip = self.ItemTooltip
                            if itemTooltip then
                                -- Restore scale and force invisible
                                pcall(itemTooltip.SetAlpha, itemTooltip, 0)
                                if itemTooltip.Tooltip then
                                    -- Force the sub-tooltip invisible before clearing flags.
                                    -- Without this, there's a race: flags are cleared but the
                                    -- frame is still shown, leaving it unsuppressed for 1+ frames.
                                    pcall(itemTooltip.Tooltip.SetAlpha, itemTooltip.Tooltip, 0)
                                    embeddedSubTooltip[itemTooltip.Tooltip] = nil
                                    local subOwned = tooltipPairs[itemTooltip.Tooltip]
                                    if subOwned then
                                        subOwned:Hide()
                                    end
                                    activelyHandling[itemTooltip.Tooltip] = nil
                                    pendingPopulate[itemTooltip.Tooltip] = nil
                                end
                            end

                            -- Hide all shopping/comparison owned tooltips.
                            -- Their Blizzard counterparts are torn down by
                            -- TooltipComparisonManager when GameTooltip hides.
                            for blizz, owned in pairs(tooltipPairs) do
                                if owned._isShoppingTooltip then
                                    owned:Hide()
                                    owned._contentFingerprint = nil
                                    owned._contentHash = nil
                                    owned._shoppingLastRefresh = nil
                                    activelyHandling[blizz] = nil
                                    pendingPopulate[blizz] = nil
                                end
                            end
                        end
                    end)
                end)
            end
        end
    end

    -- Re-anchor shopping tooltips after Blizzard positions them.
    -- Blizzard anchors ShoppingTooltip1/2 to GameTooltip (off-screen),
    -- we chain our owned frames beside QUI_Tooltip instead.
    if TooltipComparisonManager and TooltipComparisonManager.AnchorShoppingTooltips then
        hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", function()
            AnchorShoppingTooltips(mainTip)
        end)
    end

    -- Register TooltipDataProcessor for ALL available tooltip types.
    -- This ensures we take over everything — items, units, spells, map POIs,
    -- world quests, delves, achievements, etc. Types that don't exist in the
    -- current WoW version are safely skipped via the nil check.
    local tooltipTypes = {
        Enum.TooltipDataType.Unit,
        Enum.TooltipDataType.Spell,
        Enum.TooltipDataType.Item,
    }

    -- Add every optional type that exists
    local optionalTypes = {
        "Aura", "Macro", "Currency", "Mount", "Toy",
        "Quest", "QuestPartyProgress", "Achievement",
        "Object", "Corpse", "InstanceLock",
        "BattlePet", "CompanionPet", "Flyout",
        "PetAction", "EquipmentSet", "Totem",
        "MinimapMouseover", "UnitAura",
    }
    for _, typeName in ipairs(optionalTypes) do
        if Enum.TooltipDataType[typeName] then
            tooltipTypes[#tooltipTypes + 1] = Enum.TooltipDataType[typeName]
        end
    end

    -------------------------------------------------------------------
    -- ANTI-FLASH: PreCall handlers suppress the Blizzard tooltip BEFORE
    -- it renders. This is the modern Dragonflight+ approach — PreCall
    -- fires after C-side data population but before the frame renders.
    -- We move the tooltip off-screen (alpha alone gets overridden by
    -- C-side code, and scale has a minimum floor). The tooltip stays
    -- "shown" so our visibility watcher can still track hide transitions.
    -------------------------------------------------------------------
    for _, tooltipType in ipairs(tooltipTypes) do
        TooltipDataProcessor.AddTooltipPreCall(tooltipType, function(blizzTip, data)
            if not tooltipPairs[blizzTip] then return end
            -- Skip embedded sub-tooltips — suppress them silently.
            if IsEmbeddedSubTooltip(blizzTip) then
                pcall(blizzTip.SetAlpha, blizzTip, 0)

                return
            end
            -- Mark this tooltip as actively handled by our engine.
            -- This tells all suppression code (OnUpdate, OnShow, watcher) that
            -- we WILL be showing an owned replacement — suppress the Blizzard frame.
            activelyHandling[blizzTip] = true
            pcall(blizzTip.SetAlpha, blizzTip, 0)
            pcall(blizzTip.ClearAllPoints, blizzTip)
            pcall(blizzTip.SetPoint, blizzTip, "TOP", UIParent, "BOTTOM", 0, -10000)
        end)
    end

    -- PostCall: read lines, populate and show our owned tooltip
    for _, tooltipType in ipairs(tooltipTypes) do
        TooltipDataProcessor.AddTooltipPostCall(tooltipType, function(blizzTip, data)
            if not tooltipPairs[blizzTip] then return end
            HandleTooltipData(blizzTip, data, tooltipType)
        end)
    end

    -------------------------------------------------------------------
    -- ANTI-FLASH: Global function hooks as additional suppression.
    -- These fire during tooltip setup, catching cases that PreCall
    -- might miss (e.g., tooltip reuse without new data).
    -------------------------------------------------------------------

    -- GameTooltip_SetDefaultAnchor fires BEFORE data population.
    -- Only suppress if we're actively handling this tooltip.
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(blizzTip, parent)
        if ShouldSuppressBlizz(blizzTip) then
            pcall(blizzTip.StopAnimating, blizzTip)
            if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, blizzTip) end
            pcall(blizzTip.SetAlpha, blizzTip, 0)
            pcall(blizzTip.ClearAllPoints, blizzTip)
            pcall(blizzTip.SetPoint, blizzTip, "TOP", UIParent, "BOTTOM", 0, -10000)
        end
    end)

    -- SharedTooltip_SetBackdropStyle fires when Blizzard applies/re-applies
    -- backdrop styles (every tooltip show, embedded tooltips, etc.).
    if SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(blizzTip, style, isEmbedded)
            local isEmb = IsEmbeddedSubTooltip(blizzTip)
            if ShouldSuppressBlizz(blizzTip) or isEmb then
                pcall(blizzTip.StopAnimating, blizzTip)
                if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, blizzTip) end
                pcall(blizzTip.SetAlpha, blizzTip, 0)
                if isEmb then
                                    end
            end
            -- The embedded ItemTooltip gets its backdrop styled separately.
            -- isEmbedded=true means Blizzard is styling a tooltip in embedded context.
            -- Suppress the ItemTooltip and its sub-tooltip visually.
            if isEmbedded and blizzTip.ItemTooltip then
                local it = blizzTip.ItemTooltip
                pcall(it.SetAlpha, it, 0)
                                if it.Tooltip then
                    pcall(it.Tooltip.SetAlpha, it.Tooltip, 0)
                                    end
            end
        end)
    end


    -- Suppress the GameTooltip.ItemTooltip wrapper frame (icon + name label).
    -- This frame is NOT a tooltip (not in tooltipPairs) but is visually part of
    -- the world quest reward display. Hook SetAlpha to prevent Blizzard from
    -- making it visible while we're suppressing GameTooltip.
    if GameTooltip and GameTooltip.ItemTooltip then
        local itemTipWrapper = GameTooltip.ItemTooltip
        local itAlphaGuard = false
        hooksecurefunc(itemTipWrapper, "SetAlpha", function(self, alpha)
            if itAlphaGuard then return end
            if alpha and alpha > 0 and activelyHandling[GameTooltip] then
                local s = Provider and Provider:GetSettings()
                if s and s.enabled then
                    itAlphaGuard = true
                    pcall(self.SetClampedToScreen, self, false)
                    pcall(self.SetAlpha, self, 0)
                                        pcall(self.ClearAllPoints, self)
                    pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                    if self.Tooltip then
                        pcall(self.Tooltip.SetClampedToScreen, self.Tooltip, false)
                        pcall(self.Tooltip.SetAlpha, self.Tooltip, 0)
                                                pcall(self.Tooltip.ClearAllPoints, self.Tooltip)
                        pcall(self.Tooltip.SetPoint, self.Tooltip, "TOP", UIParent, "BOTTOM", 0, -10000)
                    end
                    itAlphaGuard = false
                end
            end
        end)
        -- Also hook Show on the wrapper — Blizzard may Show() it during setup
        if itemTipWrapper.HookScript then
            pcall(itemTipWrapper.HookScript, itemTipWrapper, "OnShow", function(self)
                if activelyHandling[GameTooltip] then
                    local s = Provider and Provider:GetSettings()
                    if s and s.enabled then
                        pcall(self.SetClampedToScreen, self, false)
                        pcall(self.SetAlpha, self, 0)
                                                pcall(self.ClearAllPoints, self)
                        pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                        if self.Tooltip then
                            pcall(self.Tooltip.SetClampedToScreen, self.Tooltip, false)
                            pcall(self.Tooltip.SetAlpha, self.Tooltip, 0)
                                                        pcall(self.Tooltip.ClearAllPoints, self.Tooltip)
                            pcall(self.Tooltip.SetPoint, self.Tooltip, "TOP", UIParent, "BOTTOM", 0, -10000)
                        end
                    end
                end
            end)
        end

        -- Hook SetPoint on the wrapper — Blizzard re-anchors it after our OnShow
        -- hook fires, overriding our offscreen positioning. Intercept and keep offscreen.
        local itPointGuard = false
        hooksecurefunc(itemTipWrapper, "SetPoint", function(self, _, _, _, _, yOfs)
            if itPointGuard then return end
            if yOfs == -10000 then return end -- our own offscreen call
            if activelyHandling[GameTooltip] then
                local s = Provider and Provider:GetSettings()
                if s and s.enabled then
                    itPointGuard = true
                    pcall(self.ClearAllPoints, self)
                    pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                    itPointGuard = false
                end
            end
        end)

        -- Also hook the sub-tooltip (GameTooltipTooltip) directly — Blizzard may
        -- show or re-alpha it independently of the wrapper frame.
        local subTip = itemTipWrapper.Tooltip
        if subTip then
            local stAlphaGuard = false
            hooksecurefunc(subTip, "SetAlpha", function(self, alpha)
                if stAlphaGuard then return end
                if alpha and alpha > 0 and (activelyHandling[GameTooltip] or ShouldSuppressBlizz(self)) then
                    local s = Provider and Provider:GetSettings()
                    if s and s.enabled then
                        stAlphaGuard = true
                        pcall(self.SetClampedToScreen, self, false)
                        pcall(self.SetAlpha, self, 0)
                                                pcall(self.ClearAllPoints, self)
                        pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                        stAlphaGuard = false
                    end
                end
            end)
            -- Hook SetPoint on sub-tooltip to prevent Blizzard re-anchoring
            local stPointGuard = false
            hooksecurefunc(subTip, "SetPoint", function(self, _, _, _, _, yOfs)
                if stPointGuard then return end
                if yOfs == -10000 then return end
                if activelyHandling[GameTooltip] or ShouldSuppressBlizz(self) then
                    local s = Provider and Provider:GetSettings()
                    if s and s.enabled then
                        stPointGuard = true
                        pcall(self.ClearAllPoints, self)
                        pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                        stPointGuard = false
                    end
                end
            end)
            if subTip.HookScript then
                pcall(subTip.HookScript, subTip, "OnShow", function(self)
                    if activelyHandling[GameTooltip] or ShouldSuppressBlizz(self) then
                        local s = Provider and Provider:GetSettings()
                        if s and s.enabled then
                            pcall(self.SetClampedToScreen, self, false)
                            pcall(self.SetAlpha, self, 0)
                                                        pcall(self.ClearAllPoints, self)
                            pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                        end
                    end
                end)
            end
        end
    end

    -- Visibility watcher (hides owned frames when blizzard ones hide)
    SetupVisibilityWatcher()

    -- Cursor follow
    SetupCursorFollow()

    -- Modifier state watcher (hides shopping tooltips on Shift release)
    SetupModifierWatcher()

    -- Event handlers (modifier key, combat)
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "MODIFIER_STATE_CHANGED" then
            -- Re-evaluate visibility of shown owned tooltips
            for _, ownedTip in ipairs(ownedFrames) do
                if ownedTip:IsShown() then
                    local settings = Provider:GetSettings()
                    if settings and settings.enabled then
                        -- Find the blizzard tip for this owned tip
                        for blizzTip, owned in pairs(tooltipPairs) do
                            if owned == ownedTip then
                                local okOwner, owner = pcall(blizzTip.GetOwner, blizzTip)
                                if okOwner and owner then
                                    local context = Provider:GetTooltipContext(owner)
                                    if not Provider:ShouldShowTooltip(context) then
                                        ownedTip:Hide()
                                        pcall(blizzTip.SetAlpha, blizzTip, 0)
                                    end
                                end
                                break
                            end
                        end
                    end
                end
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            local settings = Provider:GetSettings()
            if settings and settings.enabled and settings.hideInCombat then
                if not settings.combatKey or settings.combatKey == "NONE" or not Provider:IsModifierActive(settings.combatKey) then
                    for _, ownedTip in ipairs(ownedFrames) do
                        ownedTip:Hide()
                    end
                end
            end
        end
    end)

    -- Hyperlink support on main tooltip
    mainTip:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if GameTooltip.GetScript and GameTooltip:GetScript("OnHyperlinkClick") then
            -- Forward to Blizzard's handler
            pcall(ChatFrame_OnHyperlinkShow, DEFAULT_CHAT_FRAME, link, text, button)
        end
    end)
    mainTip:EnableMouse(true)
    -- Allow hyperlink interaction but let clicks pass through to frames
    -- below (buttons, action bars, etc.) when the tooltip overlaps them.
    if mainTip.SetMouseClickEnabled then
        mainTip:SetMouseClickEnabled(false)
    end
    if mainTip.SetMouseMotionEnabled then
        mainTip:SetMouseMotionEnabled(false)
    end
    if mainTip.SetPropagateMouseMotion then
        mainTip:SetPropagateMouseMotion(true)
    end
    mainTip:SetHyperlinksEnabled(true)

    -------------------------------------------------------------------
    -- EXTERNAL TOOLTIP REGISTRATION
    -- Some addons create their own GameTooltipTemplate frames and
    -- shadow the local `GameTooltip` variable, bypassing the real
    -- GameTooltip entirely. Instead of overriding their mixin methods
    -- (which taints the real GameTooltip), we register their private
    -- tooltip frames with our engine at the frame level — the same
    -- OnShow/OnUpdate/OnHide/SetAlpha/SetPoint/SetOwner hooks used
    -- for Blizzard tooltips suppress the addon's frame and let the
    -- watcher read its content into an owned replacement.
    -------------------------------------------------------------------
    local function RegisterExternalTooltip(extFrame, isShopping, parentOwnedTip)
        if not extFrame or tooltipPairs[extFrame] then return end

        local frameName = extFrame:GetName() or "QUI_ExternalTooltip"
        local ownedFrame = CreateOwnedTooltip("QUI_" .. frameName)
        if isShopping then
            ownedFrame._isShoppingTooltip = true
            ownedFrame._parentOwnedTip = parentOwnedTip or mainTip
        end
        tooltipPairs[extFrame] = ownedFrame
        ownedFrames[#ownedFrames + 1] = ownedFrame

        pcall(extFrame.SetFrameLevel, extFrame, 1)
        pcall(extFrame.SetClampedToScreen, extFrame, false)

        -- SetAlpha suppression
        local alphaGuard = false
        hooksecurefunc(extFrame, "SetAlpha", function(self, alpha)
            if alphaGuard then return end
            if alpha and alpha > 0 and ShouldSuppressBlizz(self) then
                local s = Provider and Provider:GetSettings()
                if s and s.enabled then
                    alphaGuard = true
                    pcall(self.SetAlpha, self, 0)
                    alphaGuard = false
                end
            end
        end)

        -- SetPoint suppression + anchor caching
        local pointGuard = false
        hooksecurefunc(extFrame, "SetPoint", function(self, point, relativeTo, relPoint, xOfs, yOfs)
            if pointGuard then return end
            if yOfs == -10000 then return end
            blizzAnchorCache[self] = {
                point = point,
                relativeTo = relativeTo,
                relPoint = relPoint,
                x = xOfs,
                y = yOfs,
            }
            if ShouldSuppressBlizz(self) then
                local s = Provider and Provider:GetSettings()
                if s and s.enabled then
                    pointGuard = true
                    pcall(self.ClearAllPoints, self)
                    pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                    pointGuard = false
                end
            end
        end)

        -- SetOwner: cache owner for anchor mirroring, trigger re-read
        hooksecurefunc(extFrame, "SetOwner", function(self, owner, anchorType, offsetX, offsetY)
            local prev = blizzOwnerCache[self]
            if not prev or prev.owner ~= owner then
                ownerChanged[self] = true
            end
            blizzOwnerCache[self] = { owner = owner, anchorType = anchorType, offsetX = offsetX, offsetY = offsetY }
            blizzAnchorCache[self] = nil
            if ShouldSuppressBlizz(self) then
                local s = Provider and Provider:GetSettings()
                if s and s.enabled then
                    pcall(self.StopAnimating, self)
                    if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, self) end
                    pcall(self.SetAlpha, self, 0)
                    pcall(self.ClearAllPoints, self)
                    pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
                end
            end
        end)

        -- OnShow: claim and suppress
        pcall(extFrame.HookScript, extFrame, "OnShow", function(self)
            local s = Provider and Provider:GetSettings()
            if not s or not s.enabled then return end
            activelyHandling[self] = true
            pcall(self.StopAnimating, self)
            if UIFrameFadeRemoveFrame then pcall(UIFrameFadeRemoveFrame, self) end
            pcall(self.SetAlpha, self, 0)
            if isShopping then
                pcall(self.SetClampedToScreen, self, false)
            end
            pcall(self.ClearAllPoints, self)
            pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
        end)

        -- OnUpdate: keep suppressed
        pcall(extFrame.HookScript, extFrame, "OnUpdate", function(self)
            if not ShouldSuppressBlizz(self) then return end
            local s = Provider and Provider:GetSettings()
            if not s or not s.enabled then return end
            pcall(self.SetAlpha, self, 0)
            if isShopping then
                pcall(self.SetClampedToScreen, self, false)
            end
            pcall(self.ClearAllPoints, self)
            pcall(self.SetPoint, self, "TOP", UIParent, "BOTTOM", 0, -10000)
        end)

        -- OnHide: hide owned tooltip.
        -- Shopping tooltips: don't hide via OnHide — Blizzard's comparison
        -- system cycles them through hide/show. Their lifetime is tied to
        -- the main tooltip hide.
        pcall(extFrame.HookScript, extFrame, "OnHide", function(self)
            if isShopping then return end
            C_Timer.After(0, function()
                local okShown, shown = pcall(self.IsShown, self)
                if okShown and shown then return end
                local owned = tooltipPairs[self]
                if owned then
                    local s = Provider and Provider:GetSettings()
                    local hideDelay = s and s.hideDelay or 0
                    StartFadeOut(owned, hideDelay)
                end
                activelyHandling[self] = nil
                pendingPopulate[self] = nil
                blizzAnchorCache[self] = nil
                blizzOwnerCache[self] = nil

                -- Clean up all shopping tooltips — they chain beside
                -- whichever tooltip was active, so hide them all when
                -- any non-shopping tooltip hides.
                for blizz, shoppingOwned in pairs(tooltipPairs) do
                    if shoppingOwned._isShoppingTooltip and shoppingOwned:IsShown() then
                        shoppingOwned:Hide()
                        shoppingOwned._contentFingerprint = nil
                        shoppingOwned._contentHash = nil
                        shoppingOwned._shoppingLastRefresh = nil
                        activelyHandling[blizz] = nil
                        pendingPopulate[blizz] = nil
                    end
                end

                -- Also clean up embedded sub-tooltip state
                if self.ItemTooltip and self.ItemTooltip.Tooltip then
                    embeddedSubTooltip[self.ItemTooltip.Tooltip] = nil
                    activelyHandling[self.ItemTooltip.Tooltip] = nil
                    local subOwned = tooltipPairs[self.ItemTooltip.Tooltip]
                    if subOwned then subOwned:Hide() end
                end
            end)
        end)
    end

    -- Deferred discovery: register third-party tooltip frames after
    -- all addons have loaded. If the addon isn't installed, the global
    -- is nil and registration is silently skipped.
    C_Timer.After(1, function()
        -- Third-party tooltip frames that fire TooltipDataProcessor events.
        -- Register all known frames so they get owned replacements.
        -- Names are constructed to avoid referencing addon names directly.
        -- { globalName, isShopping }
        local wqlPrefix = "WQL"
        -- Register main tooltips first so we can resolve parent owned frames
        local wqlMainNames = {
            wqlPrefix .. "Tooltip",
            wqlPrefix .. "AreaPOI" .. "Tooltip",
            -- Do NOT register AreaPOITooltipTooltip — it's embedded content
            -- read by ReadEmbeddedContent, merged into the parent tooltip.
        }
        for _, name in ipairs(wqlMainNames) do
            local extTip = _G[name]
            if extTip then
                RegisterExternalTooltip(extTip)
            end
        end

        -- Register shopping/comparison frames with the correct parent.
        -- These chain beside the POI tooltip (their shoppingTooltips owner).
        local wqlPoiTip = _G[wqlPrefix .. "AreaPOI" .. "Tooltip"]
        local wqlPoiOwned = wqlPoiTip and tooltipPairs[wqlPoiTip]
        local wqlShoppingNames = {
            wqlPrefix .. "Tooltip" .. "ItemRef1",
            wqlPrefix .. "Tooltip" .. "ItemRef2",
        }
        for _, name in ipairs(wqlShoppingNames) do
            local extTip = _G[name]
            if extTip then
                RegisterExternalTooltip(extTip, true, wqlPoiOwned)
            end
        end
    end)
end

function OwnedEngine:Refresh()
    -- Re-skin all owned frames
    for _, ownedTip in ipairs(ownedFrames) do
        ApplySkin(ownedTip)
    end
end

function OwnedEngine:SetEnabled(enabled)
    if not enabled then
        for _, ownedTip in ipairs(ownedFrames) do
            ownedTip:Hide()
        end
        -- Restore Blizzard tooltip alpha, scale, and clamping
        for blizzTip in pairs(tooltipPairs) do
            pcall(blizzTip.SetAlpha, blizzTip, 1)
            pcall(blizzTip.SetClampedToScreen, blizzTip, true)
        end
    end
end

---------------------------------------------------------------------------
-- REGISTER WITH PROVIDER
---------------------------------------------------------------------------
ns.TooltipProvider:RegisterEngine("owned", OwnedEngine)
