-- buffborders.lua
-- Addon-owned buff/debuff icon display
-- Replaces Blizzard's BuffFrame/DebuffFrame with event-driven owned containers

local _, ns = ...
local Helpers = ns.Helpers

local GetCore = Helpers.GetCore
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber

-- Upvalue caching
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local wipe = wipe
local sort = table.sort
local tremove = table.remove
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown

---------------------------------------------------------------------------
-- DEFAULTS
---------------------------------------------------------------------------
local DEFAULTS = {
    enableBuffs = true,
    enableDebuffs = true,
    hideBuffFrame = false,
    hideDebuffFrame = false,
    fadeBuffFrame = false,
    fadeDebuffFrame = false,
    fadeOutAlpha = 0,
    borderSize = 2,
    fontSize = 12,
    fontOutline = true,
    buffIconsPerRow = 0,
    buffIconSpacing = 0,
    buffIconSize = 0,
    buffGrowLeft = false,
    buffGrowUp = false,
    debuffIconsPerRow = 0,
    debuffIconSpacing = 0,
    debuffIconSize = 0,
    debuffGrowLeft = false,
    debuffGrowUp = false,
    buffBottomPadding = 10,
    debuffBottomPadding = 10,
}

local function GetSettings()
    return Helpers.GetModuleSettings("buffBorders", DEFAULTS)
end

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local DEFAULT_ICON_SIZE = 30
local MAX_RECYCLE_POOL_SIZE = 30
local BASE_CROP = 0.08
local DEBOUNCE_INTERVAL = 0.1

-- Debuff type → border color (r, g, b)
local DEBUFF_TYPE_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    [""]    = { 0.50, 0.00, 0.00 },
}
local BORDER_COLOR_BUFF = { 0, 0, 0 }
local BORDER_COLOR_DEBUFF_DEFAULT = { 0.50, 0.00, 0.00 }

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local recyclePool = {}
local iconCounter = 0

-- Active icon sets keyed by auraInstanceID
local buffActiveIcons = {}
local debuffActiveIcons = {}

-- Sorted icon lists for layout (rebuilt on each update)
local buffSortedIcons = {}
local debuffSortedIcons = {}

-- Containers (created in Init)
local buffContainer = nil
local debuffContainer = nil

-- Blizzard frame banish state
local blizzBuffBanished = false
local blizzDebuffBanished = false
local blizzBuffShowHooked = false
local blizzDebuffShowHooked = false
local blizzBuffAlphaHooked = false
local blizzDebuffAlphaHooked = false

-- Debounce state
local buffUpdatePending = false
local debuffUpdatePending = false

-- Layout mode preview state
local previewActive = false
local previewBuffIcons = {}
local previewDebuffIcons = {}

---------------------------------------------------------------------------
-- ICON FACTORY
---------------------------------------------------------------------------
local function CreateAuraIcon(parent)
    iconCounter = iconCounter + 1
    local frameName = "QUIAuraIcon" .. iconCounter

    local icon = CreateFrame("Frame", frameName, parent)
    icon:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)

    -- .Icon texture (ARTWORK layer)
    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetAllPoints(icon)
    icon.Icon:SetTexCoord(BASE_CROP, 1 - BASE_CROP, BASE_CROP, 1 - BASE_CROP)

    -- .Cooldown frame (CooldownFrameTemplate for swipe + countdown)
    icon.Cooldown = CreateFrame("Cooldown", frameName .. "Cooldown", icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints(icon)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)
    icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    icon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    icon.Cooldown:SetDrawBling(false)

    -- .TextOverlay (above swipe so text is never behind it)
    icon.TextOverlay = CreateFrame("Frame", nil, icon)
    icon.TextOverlay:SetAllPoints(icon)
    icon.TextOverlay:SetFrameLevel(icon.Cooldown:GetFrameLevel() + 2)

    -- 4 edge border textures (BACKGROUND layer, behind icon)
    icon.BorderTop = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.BorderBottom = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.BorderLeft = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.BorderRight = icon:CreateTexture(nil, "OVERLAY", nil, 7)

    icon.BorderTop:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    icon.BorderTop:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    icon.BorderBottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    icon.BorderBottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    icon.BorderLeft:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    icon.BorderLeft:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    icon.BorderRight:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    icon.BorderRight:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)

    -- .Stacks text (OVERLAY, bottom-right)
    icon.Stacks = icon.TextOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.Stacks:SetPoint("BOTTOMRIGHT", -1, 1)

    -- Default font
    local defaultFont = GetGeneralFont()
    local defaultOutline = GetGeneralFontOutline()
    icon.Stacks:SetFont(defaultFont, 10, defaultOutline)

    -- Metadata
    icon._auraInstanceID = nil
    icon._auraSlot = nil
    icon._filter = nil
    icon._rawDuration = nil
    icon._rawExpirationTime = nil
    icon._isQUIAuraIcon = true

    -- Tooltip
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
        local tooltipSettings = QUI and QUI.db and QUI.db.profile and QUI.db.profile.tooltip
        if tooltipSettings and tooltipSettings.anchorToCursor then
            local anchorTooltip = ns.QUI_AnchorTooltipToCursor
            if anchorTooltip then
                anchorTooltip(GameTooltip, self, tooltipSettings)
            else
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            end
        else
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        end
        if self._auraInstanceID and self._auraInstanceID > 0 then
            if GameTooltip.SetUnitAuraByAuraInstanceID then
                pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, "player", self._auraInstanceID)
            elseif GameTooltip.SetUnitBuffByAuraInstanceID then
                pcall(GameTooltip.SetUnitBuffByAuraInstanceID, GameTooltip, "player", self._auraInstanceID, self._filter)
            end
        end
        pcall(GameTooltip.Show, GameTooltip)

        -- Fade in container on icon hover
        local container = self:GetParent()
        if container and container._fadeEnabled then
            container:SetAlpha(1)
        end
    end)
    icon:SetScript("OnLeave", function(self)
        pcall(GameTooltip.Hide, GameTooltip)

        -- Fade out container on icon leave
        local container = self:GetParent()
        if container and container._fadeEnabled then
            local s = GetSettings()
            container:SetAlpha(s and s.fadeOutAlpha or 0)
        end
    end)

    icon:Hide()
    return icon
end

---------------------------------------------------------------------------
-- ICON POOL
---------------------------------------------------------------------------
local function AcquireIcon(parent)
    local icon = tremove(recyclePool)
    if icon then
        icon:SetParent(parent)
        icon:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
        icon._auraInstanceID = nil
        icon._auraSlot = nil
        icon._filter = nil
        icon._rawDuration = nil
        icon._rawExpirationTime = nil
        if icon.Icon then
            icon.Icon:SetTexture(nil)
            icon.Icon:SetDesaturated(false)
        end
        if icon.Cooldown then
            icon.Cooldown:Clear()
        end
        icon.Stacks:SetText("")
        icon.Stacks:Hide()
        icon:Show()
        return icon
    end
    return CreateAuraIcon(parent)
end

local function ReleaseIcon(icon)
    if not icon then return end
    icon:Hide()
    icon:ClearAllPoints()
    icon._auraInstanceID = nil
    icon._auraSlot = nil
    icon._filter = nil
    icon._rawDuration = nil
    icon._rawExpirationTime = nil
    if icon.Icon then
        icon.Icon:SetTexture(nil)
        icon.Icon:SetDesaturated(false)
    end
    if icon.Cooldown then
        icon.Cooldown:Clear()
    end
    icon.Stacks:SetText("")
    icon.Stacks:Hide()
    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        icon:SetParent(UIParent)
        recyclePool[#recyclePool + 1] = icon
    end
end

---------------------------------------------------------------------------
-- ICON STYLING
---------------------------------------------------------------------------
local function StyleIcon(icon, settings, isBuff, debuffType)
    if not icon or not settings then return end

    local borderSize = settings.borderSize or 2

    -- Border color
    local r, g, b
    if isBuff then
        r, g, b = BORDER_COLOR_BUFF[1], BORDER_COLOR_BUFF[2], BORDER_COLOR_BUFF[3]
    else
        local safeType = Helpers.SafeValue(debuffType, "")
        local colors = DEBUFF_TYPE_COLORS[safeType] or BORDER_COLOR_DEBUFF_DEFAULT
        r, g, b = colors[1], colors[2], colors[3]
    end

    icon.BorderTop:SetColorTexture(r, g, b, 1)
    icon.BorderBottom:SetColorTexture(r, g, b, 1)
    icon.BorderLeft:SetColorTexture(r, g, b, 1)
    icon.BorderRight:SetColorTexture(r, g, b, 1)

    icon.BorderTop:SetHeight(borderSize)
    icon.BorderBottom:SetHeight(borderSize)
    icon.BorderLeft:SetWidth(borderSize)
    icon.BorderRight:SetWidth(borderSize)

    icon.BorderTop:Show()
    icon.BorderBottom:Show()
    icon.BorderLeft:Show()
    icon.BorderRight:Show()

    -- Font settings
    local font = GetGeneralFont()
    local outline = GetGeneralFontOutline()
    local fontSize = settings.fontSize or 12
    icon.Stacks:SetFont(font, fontSize, outline)

    -- Style Blizzard's auto-managed countdown FontString
    if icon.Cooldown.GetCountdownFontString then
        local cdText = icon.Cooldown:GetCountdownFontString()
        if cdText and cdText.SetFont then
            cdText:SetFont(font, fontSize, outline)
        end
    end
end

---------------------------------------------------------------------------
-- CONTAINER FRAMES
---------------------------------------------------------------------------
local function CreateContainer(name)
    local container = CreateFrame("Frame", name, UIParent)
    container:SetSize(1, 1)
    container:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -205, -13)
    container:Show()

    -- Fade support
    container._fadeEnabled = false
    container:EnableMouse(true)
    container:SetScript("OnEnter", function(self)
        if self._fadeEnabled then
            self:SetAlpha(1)
        end
    end)
    container:SetScript("OnLeave", function(self)
        if self._fadeEnabled then
            local s = GetSettings()
            self:SetAlpha(s and s.fadeOutAlpha or 0)
        end
    end)

    return container
end

---------------------------------------------------------------------------
-- LAYOUT
---------------------------------------------------------------------------

-- Fractional position of each anchor point within a frame's bounding box.
-- Used to convert between anchor points while preserving screen position.
-- X: 0 = left, 1 = right.  Y: 0 = bottom, 1 = top (WoW convention).
local ANCHOR_FRAC_X = {
    TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1,
    LEFT = 0, CENTER = 0.5, RIGHT = 1,
    BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1,
}
local ANCHOR_FRAC_Y = {
    TOPLEFT = 1, TOP = 1, TOPRIGHT = 1,
    LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
    BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0,
}

local function LayoutIcons(container, sortedIcons, settings, prefix)
    if not container or not settings then return end

    local iconSize = settings[prefix .. "IconSize"] or 0
    if iconSize <= 0 then iconSize = DEFAULT_ICON_SIZE end

    local iconsPerRow = settings[prefix .. "IconsPerRow"] or 0
    if iconsPerRow <= 0 then iconsPerRow = 10 end

    local spacing = settings[prefix .. "IconSpacing"] or 0
    if spacing <= 0 then spacing = 2 end

    local growLeft = settings[prefix .. "GrowLeft"]
    local growUp = settings[prefix .. "GrowUp"]

    local count = #sortedIcons
    if count == 0 then
        container:SetSize(1, 1)
        return
    end

    -- Growth-direction anchor — the corner that should stay fixed on screen.
    local anchor
    if growUp then
        anchor = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        anchor = growLeft and "TOPRIGHT" or "TOPLEFT"
    end

    -- Re-anchor the container at the growth corner so it stays fixed when
    -- SetSize changes the dimensions.  The anchoring system (or layout mode)
    -- may have positioned the container at a different anchor (e.g. CENTER).
    -- We convert the SetPoint to the growth corner, preserving screen position,
    -- so the icon grid never shifts during resize.
    local pt, rel, rp, ox, oy = container:GetPoint(1)
    if pt and pt ~= anchor then
        local W, H = container:GetWidth(), container:GetHeight()
        local fx1, fy1 = ANCHOR_FRAC_X[pt], ANCHOR_FRAC_Y[pt]
        local fx2, fy2 = ANCHOR_FRAC_X[anchor], ANCHOR_FRAC_Y[anchor]
        if fx1 and fy1 and fx2 and fy2 then
            container:ClearAllPoints()
            container:SetPoint(anchor, rel, rp,
                (ox or 0) + (fx2 - fx1) * W,
                (oy or 0) + (fy2 - fy1) * H)
        end
    end

    local step = iconSize + spacing

    for i, icon in ipairs(sortedIcons) do
        local idx = i - 1
        local col = idx % iconsPerRow
        local row = math.floor(idx / iconsPerRow)

        local xOff = growLeft and -(col * step) or (col * step)
        local yOff = growUp and (row * step) or -(row * step)

        icon:SetSize(iconSize, iconSize)
        icon:ClearAllPoints()
        icon:SetPoint(anchor, container, anchor, xOff, yOff)
    end

    -- Resize container to fit grid + configurable bottom padding
    local numCols = math.min(count, iconsPerRow)
    local numRows = math.ceil(count / iconsPerRow)
    local totalW = numCols * iconSize + math.max(0, numCols - 1) * spacing
    local bottomPadding = settings[prefix .. "BottomPadding"] or 10
    local totalH = numRows * iconSize + math.max(0, numRows - 1) * spacing + bottomPadding
    container:SetSize(totalW, totalH)
end

---------------------------------------------------------------------------
-- BANISH / RESTORE BLIZZARD FRAMES
---------------------------------------------------------------------------
local function BanishBlizzardFrame(frame, showHookedFlag, alphaHookedFlag)
    if not frame then return false, false end

    if InCombatLockdown() then
        -- Defer to after combat
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            BanishBlizzardFrame(frame, showHookedFlag, alphaHookedFlag)
        end)
        return showHookedFlag, alphaHookedFlag
    end

    frame:SetAlpha(0)
    frame:EnableMouse(false)

    -- Hook Show to re-enforce hiding
    if not showHookedFlag then
        showHookedFlag = true
        hooksecurefunc(frame, "Show", function(self)
            C_Timer.After(0, function()
                if self._quiBanished then
                    self:SetAlpha(0)
                    self:EnableMouse(false)
                end
            end)
        end)
    end

    -- Hook SetAlpha to prevent Blizzard from restoring visibility
    if not alphaHookedFlag then
        alphaHookedFlag = true
        hooksecurefunc(frame, "SetAlpha", function(self, alpha)
            if self._quiBanished and alpha > 0 then
                C_Timer.After(0, function()
                    if self._quiBanished and self:GetAlpha() > 0 then
                        self:SetAlpha(0)
                    end
                end)
            end
        end)
    end

    frame._quiBanished = true
    return showHookedFlag, alphaHookedFlag
end

local function RestoreBlizzardFrame(frame)
    if not frame then return end

    if InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            RestoreBlizzardFrame(frame)
        end)
        return
    end

    frame._quiBanished = nil
    frame:SetAlpha(1)
    frame:EnableMouse(true)
end

---------------------------------------------------------------------------
-- AURA SCANNING
---------------------------------------------------------------------------
local function UpdateAuraIcons(container, activeIcons, sortedList, filter, isBuff, settings, prefix)
    if not container or not settings then return end

    local enableKey = isBuff and "enableBuffs" or "enableDebuffs"
    local hideKey = isBuff and "hideBuffFrame" or "hideDebuffFrame"

    -- If disabled or hidden, release all and make container invisible
    -- (keep :Show() so child overlays in layout mode always have a valid parent)
    if not settings[enableKey] or settings[hideKey] then
        for id, icon in pairs(activeIcons) do
            ReleaseIcon(icon)
            activeIcons[id] = nil
        end
        wipe(sortedList)
        container._fadeEnabled = false
        container:SetAlpha(0)
        container:EnableMouse(false)
        return
    end

    -- Scan current auras
    local currentAuras = {}

    -- Use AuraUtil.ForEachAura for reliable iteration
    if AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura("player", filter, nil, function(auraData)
            if auraData and auraData.auraInstanceID then
                currentAuras[auraData.auraInstanceID] = auraData
            end
        end, true) -- usePackedAura = true for C_UnitAuras data
    end

    -- Phase 1: Collect expired auras (don't mutate during iteration)
    local expired = {}
    for id, icon in pairs(activeIcons) do
        if not currentAuras[id] then
            expired[#expired + 1] = id
        end
    end

    -- Phase 2: Release expired
    for _, id in ipairs(expired) do
        ReleaseIcon(activeIcons[id])
        activeIcons[id] = nil
    end

    -- Phase 3: Acquire/update icons for current auras
    for id, auraData in pairs(currentAuras) do
        local icon = activeIcons[id]
        if not icon then
            -- New aura — acquire icon
            icon = AcquireIcon(container)
            activeIcons[id] = icon
        end

        -- Update icon data
        icon._auraInstanceID = id
        icon._filter = filter

        -- Texture
        local texID = auraData.icon
        if texID and icon.Icon then
            icon.Icon:SetTexture(texID)
        end

        -- Cooldown swipe (secret-safe via pcall to C-side)
        local duration = auraData.duration
        local expirationTime = auraData.expirationTime

        -- Store raw values (may be secret) — C-side functions handle them
        icon._rawDuration = duration
        icon._rawExpirationTime = expirationTime

        -- Cooldown swipe: pass secret values directly to C-side API
        if expirationTime and duration then
            pcall(icon.Cooldown.SetCooldownFromExpirationTime, icon.Cooldown, expirationTime, duration)
        else
            icon.Cooldown:Clear()
        end

        -- Stacks
        local applications = auraData.applications
        if applications then
            local safeApps = SafeToNumber(applications, 0)
            if safeApps > 1 then
                icon.Stacks:SetText(safeApps)
                icon.Stacks:Show()
            else
                icon.Stacks:SetText("")
                icon.Stacks:Hide()
            end
        else
            icon.Stacks:SetText("")
            icon.Stacks:Hide()
        end

        -- Style (borders, font)
        local debuffType = not isBuff and (auraData.dispelName or "") or nil
        StyleIcon(icon, settings, isBuff, debuffType)

        icon:Show()
    end

    -- Phase 4: Build sorted list and layout
    wipe(sortedList)
    for id, icon in pairs(activeIcons) do
        sortedList[#sortedList + 1] = icon
    end
    -- Sort by auraInstanceID for stable ordering
    sort(sortedList, function(a, b)
        return (a._auraInstanceID or 0) < (b._auraInstanceID or 0)
    end)

    LayoutIcons(container, sortedList, settings, prefix)

    -- Apply visibility: alpha-based so container stays :Show() for layout mode overlays
    container:EnableMouse(#sortedList > 0)
    local fadeKey = isBuff and "fadeBuffFrame" or "fadeDebuffFrame"
    if #sortedList == 0 then
        container._fadeEnabled = false
        container:SetAlpha(0)
    elseif settings[fadeKey] then
        container._fadeEnabled = true
        container:SetAlpha(settings.fadeOutAlpha or 0)
    else
        container._fadeEnabled = false
        container:SetAlpha(1)
    end
end

local function UpdateBuffIcons()
    local settings = GetSettings()
    if not settings then return end
    if previewActive then return end
    UpdateAuraIcons(buffContainer, buffActiveIcons, buffSortedIcons, "HELPFUL", true, settings, "buff")
end

local function UpdateDebuffIcons()
    local settings = GetSettings()
    if not settings then return end
    if previewActive then return end
    UpdateAuraIcons(debuffContainer, debuffActiveIcons, debuffSortedIcons, "HARMFUL", false, settings, "debuff")
end

---------------------------------------------------------------------------
-- BLIZZARD FRAME MANAGEMENT
-- Banish/restore Blizzard frames based on enable settings
---------------------------------------------------------------------------
local function ManageBlizzardFrames()
    local settings = GetSettings()
    if not settings then return end

    -- Buff frame: banish when enabled, restore when disabled
    if settings.enableBuffs then
        if not blizzBuffBanished then
            blizzBuffShowHooked, blizzBuffAlphaHooked = BanishBlizzardFrame(
                BuffFrame, blizzBuffShowHooked, blizzBuffAlphaHooked)
            blizzBuffBanished = true
        end
    else
        if blizzBuffBanished then
            RestoreBlizzardFrame(BuffFrame)
            blizzBuffBanished = false
        end
    end

    -- Debuff frame: banish when enabled, restore when disabled
    if settings.enableDebuffs then
        if not blizzDebuffBanished then
            blizzDebuffShowHooked, blizzDebuffAlphaHooked = BanishBlizzardFrame(
                DebuffFrame, blizzDebuffShowHooked, blizzDebuffAlphaHooked)
            blizzDebuffBanished = true
        end
    else
        if blizzDebuffBanished then
            RestoreBlizzardFrame(DebuffFrame)
            blizzDebuffBanished = false
        end
    end
end

---------------------------------------------------------------------------
-- TEMPORARY ENCHANT FRAME
-- Keep existing simple border logic for TemporaryEnchantFrame
---------------------------------------------------------------------------
local borderedEnchantButtons = {}
local _enchantBorders = Helpers.CreateStateTable()

local function AddBorderToEnchantButton(button)
    if not button or borderedEnchantButtons[button] then return end
    local icon = button.Icon or button.icon
    if not icon then return end
    if not button.CreateTexture or type(button.CreateTexture) ~= "function" then return end

    local settings = GetSettings()
    if not settings then return end
    local borderSize = settings.borderSize or 2

    _enchantBorders[button] = _enchantBorders[button] or {}
    local borders = _enchantBorders[button]
    if not borders.top then
        borders.top = button:CreateTexture(nil, "OVERLAY", nil, 7)
        borders.top:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        borders.top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)

        borders.bottom = button:CreateTexture(nil, "OVERLAY", nil, 7)
        borders.bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        borders.bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)

        borders.left = button:CreateTexture(nil, "OVERLAY", nil, 7)
        borders.left:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        borders.left:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)

        borders.right = button:CreateTexture(nil, "OVERLAY", nil, 7)
        borders.right:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
        borders.right:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    end

    borders.top:SetColorTexture(0, 0, 0, 1)
    borders.bottom:SetColorTexture(0, 0, 0, 1)
    borders.left:SetColorTexture(0, 0, 0, 1)
    borders.right:SetColorTexture(0, 0, 0, 1)

    borders.top:SetHeight(borderSize)
    borders.bottom:SetHeight(borderSize)
    borders.left:SetWidth(borderSize)
    borders.right:SetWidth(borderSize)

    borders.top:Show()
    borders.bottom:Show()
    borders.left:Show()
    borders.right:Show()

    borderedEnchantButtons[button] = true
end

local function ProcessTemporaryEnchants()
    if not TemporaryEnchantFrame then return end
    local settings = GetSettings()
    if not settings or not settings.enableBuffs then return end

    local frames = { TemporaryEnchantFrame:GetChildren() }
    for _, frame in ipairs(frames) do
        AddBorderToEnchantButton(frame)
    end
end

---------------------------------------------------------------------------
-- LAYOUT MODE PREVIEW
---------------------------------------------------------------------------
local PREVIEW_BUFF_TEXTURES = {
    136012,  -- Mark of the Wild
    136085,  -- Power Word: Fortitude
    135932,  -- Arcane Intellect
    132333,  -- Well Fed
    136247,  -- Blessing of Kings
    135987,  -- Renew
    136048,  -- Rejuvenation
    135964,  -- Haste
}

local PREVIEW_DEBUFF_TEXTURES = {
    135849,  -- Corruption
    135813,  -- Shadow Word: Pain
    132851,  -- Frost Shock
    136139,  -- Curse of Tongues
    136066,  -- Moonfire
    135959,  -- Immolate
}

local PREVIEW_DEBUFF_TYPES = { "Magic", "Curse", "Disease", "Poison", "Magic", "" }

--- Compute how many preview icons to show based on Icons Per Row setting.
--- Shows enough to fill 2 rows (or a minimum of 3) so the user can see
--- row wrapping as they adjust the slider.
local function GetPreviewCount(settings, prefix)
    local perRow = settings[prefix .. "IconsPerRow"] or 0
    if perRow <= 0 then perRow = 10 end
    return math.max(3, math.min(perRow + math.ceil(perRow / 2), 20))
end

local function ShowPreview()
    if previewActive then return end
    previewActive = true

    local settings = GetSettings()
    if not settings then return end

    -- Hide real icons (but keep state so we can restore)
    for _, icon in pairs(buffActiveIcons) do
        icon:Hide()
    end
    for _, icon in pairs(debuffActiveIcons) do
        icon:Hide()
    end

    -- Always show both containers in layout mode (even if currently hidden/disabled)
    -- so the handles are visible and draggable for positioning.

    -- Create buff preview icons (count adapts to Icons Per Row setting)
    local buffCount = GetPreviewCount(settings, "buff")
    for i = 1, buffCount do
        local texID = PREVIEW_BUFF_TEXTURES[((i - 1) % #PREVIEW_BUFF_TEXTURES) + 1]
        local icon = AcquireIcon(buffContainer)
        icon._auraInstanceID = -i
        icon._filter = "HELPFUL"
        icon.Icon:SetTexture(texID)
        icon.Cooldown:Clear()
        icon.Stacks:SetText("")
        icon.Stacks:Hide()
        StyleIcon(icon, settings, true, nil)
        icon:Show()
        previewBuffIcons[#previewBuffIcons + 1] = icon
    end

    LayoutIcons(buffContainer, previewBuffIcons, settings, "buff")
    buffContainer._fadeEnabled = false
    buffContainer:SetAlpha(1)
    buffContainer:Show()

    -- Create debuff preview icons (count adapts to Icons Per Row setting)
    local debuffCount = GetPreviewCount(settings, "debuff")
    for i = 1, debuffCount do
        local texIdx = ((i - 1) % #PREVIEW_DEBUFF_TEXTURES) + 1
        local texID = PREVIEW_DEBUFF_TEXTURES[texIdx]
        local debuffType = PREVIEW_DEBUFF_TYPES[texIdx]
        local icon = AcquireIcon(debuffContainer)
        icon._auraInstanceID = -100 - i
        icon._filter = "HARMFUL"
        icon.Icon:SetTexture(texID)
        icon.Cooldown:Clear()
        icon.Stacks:SetText("")
        icon.Stacks:Hide()
        StyleIcon(icon, settings, false, debuffType)
        icon:Show()
        previewDebuffIcons[#previewDebuffIcons + 1] = icon
    end

    LayoutIcons(debuffContainer, previewDebuffIcons, settings, "debuff")
    debuffContainer._fadeEnabled = false
    debuffContainer:SetAlpha(1)
    debuffContainer:Show()
end

local function HidePreview()
    if not previewActive then return end
    previewActive = false

    -- Release preview icons
    for _, icon in ipairs(previewBuffIcons) do
        ReleaseIcon(icon)
    end
    wipe(previewBuffIcons)

    for _, icon in ipairs(previewDebuffIcons) do
        ReleaseIcon(icon)
    end
    wipe(previewDebuffIcons)

    -- Restore real icons
    for _, icon in pairs(buffActiveIcons) do
        icon:Show()
    end
    for _, icon in pairs(debuffActiveIcons) do
        icon:Show()
    end

    -- Resume real display
    UpdateBuffIcons()
    UpdateDebuffIcons()
end

---------------------------------------------------------------------------
-- DEBOUNCED UPDATE SCHEDULING
---------------------------------------------------------------------------
local function ScheduleBuffUpdate()
    if buffUpdatePending then return end
    buffUpdatePending = true
    C_Timer.After(DEBOUNCE_INTERVAL, function()
        buffUpdatePending = false
        UpdateBuffIcons()
    end)
end

local function ScheduleDebuffUpdate()
    if debuffUpdatePending then return end
    debuffUpdatePending = true
    C_Timer.After(DEBOUNCE_INTERVAL, function()
        debuffUpdatePending = false
        UpdateDebuffIcons()
    end)
end

---------------------------------------------------------------------------
-- FULL REFRESH (called from settings / profile switch)
---------------------------------------------------------------------------
local function FullRefresh()
    ManageBlizzardFrames()

    if previewActive then
        -- Re-style preview icons with new settings
        HidePreview()
        ShowPreview()
        return
    end

    -- Release all and rebuild
    for id, icon in pairs(buffActiveIcons) do
        ReleaseIcon(icon)
        buffActiveIcons[id] = nil
    end
    wipe(buffSortedIcons)

    for id, icon in pairs(debuffActiveIcons) do
        ReleaseIcon(icon)
        debuffActiveIcons[id] = nil
    end
    wipe(debuffSortedIcons)

    UpdateBuffIcons()
    UpdateDebuffIcons()

    -- Temporary enchants
    wipe(borderedEnchantButtons)
    ProcessTemporaryEnchants()
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
local function Init()
    -- Create containers
    buffContainer = CreateContainer("QUI_BuffIconContainer")
    debuffContainer = CreateContainer("QUI_DebuffIconContainer")

    -- Offset debuff container below buff container by default
    debuffContainer:ClearAllPoints()
    debuffContainer:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -205, -58)

    -- Re-apply saved anchoring positions now that QUI containers exist.
    -- ApplyAllFrameAnchors may have already run (via EDIT_MODE_LAYOUTS_UPDATED)
    -- before these containers were created, causing the resolver to fall back
    -- to Blizzard's BuffFrame/DebuffFrame instead of QUI's owned containers.
    local applyAnchor = _G.QUI_ApplyFrameAnchor
    if applyAnchor then
        applyAnchor("buffFrame")
        applyAnchor("debuffFrame")
    end

    -- Manage Blizzard frames
    ManageBlizzardFrames()

    -- Initial scan
    UpdateBuffIcons()
    UpdateDebuffIcons()
    ProcessTemporaryEnchants()
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_AURA" and unit == "player" then
        ScheduleBuffUpdate()
        ScheduleDebuffUpdate()
    end
end)

-- Initialize after AceDB is ready (called from core/main.lua OnEnable)
C_Timer.After(1, Init)

---------------------------------------------------------------------------
-- EXPORTS
---------------------------------------------------------------------------
QUI.BuffBorders = {
    Apply = function() FullRefresh() end,
    ShowPreview = ShowPreview,
    HidePreview = HidePreview,
}

-- Global function for config panel / layout mode to call
_G.QUI_RefreshBuffBorders = FullRefresh

-- Layout mode preview hooks
_G.QUI_BuffBordersShowPreview = ShowPreview
_G.QUI_BuffBordersHidePreview = HidePreview

if ns.Registry then
    ns.Registry:Register("buffBorders", {
        refresh = _G.QUI_RefreshBuffBorders,
        priority = 60,
        group = "ui",
        importCategories = { "cdm" },
    })
end
