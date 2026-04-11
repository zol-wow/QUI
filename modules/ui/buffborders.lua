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
local CancelUnitBuff = CancelUnitBuff

-- Private aura API (WoW 10.1.0+)
local AddPrivateAuraAnchor = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor

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
    buffInvertSwipeDarkening = false,
    buffRowSpacing = 0,
    debuffIconsPerRow = 0,
    debuffIconSpacing = 0,
    debuffIconSize = 0,
    debuffGrowLeft = false,
    debuffGrowUp = false,
    debuffInvertSwipeDarkening = false,
    debuffRowSpacing = 0,
    buffBottomPadding = 10,
    debuffBottomPadding = 10,
    showStacks = true,
    hideSwipe = false,
    -- Text positioning (per-frame)
    buffStackTextAnchor = "BOTTOMRIGHT",
    buffStackTextOffsetX = -1,
    buffStackTextOffsetY = 1,
    buffDurationTextAnchor = "CENTER",
    buffDurationTextOffsetX = 0,
    buffDurationTextOffsetY = 0,
    debuffStackTextAnchor = "BOTTOMRIGHT",
    debuffStackTextOffsetX = -1,
    debuffStackTextOffsetY = 1,
    debuffDurationTextAnchor = "CENTER",
    debuffDurationTextOffsetX = 0,
    debuffDurationTextOffsetY = 0,
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

-- Weapon enchant icons keyed by inventory slot (16 = mainhand, 17 = offhand)
local enchantActiveIcons = {}
local enchantCachedDuration = {} -- cached total duration per slot

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


-- Layout mode preview state
local previewActive = false
local previewBuffIcons = {}
local previewDebuffIcons = {}

-- Private aura state (player debuffs hidden from addon APIs)
local PA_MAX_SLOTS = 3
local paSlots = {}
local paAnchorIDs = {}
local paPendingSetup = false   -- deferred AddPrivateAuraAnchor after combat

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
    icon.Cooldown:EnableMouse(false)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)
    icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    icon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    icon.Cooldown:SetDrawBling(false)
    local baseSwipeReverse = false
    if icon.Cooldown.GetReverse then
        local ok, reverse = pcall(icon.Cooldown.GetReverse, icon.Cooldown)
        if ok then
            baseSwipeReverse = not not reverse
        end
    end

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
    icon.Stacks:SetPoint("BOTTOMRIGHT", icon.TextOverlay, "BOTTOMRIGHT", -1, 1)

    -- Default font
    local defaultFont = GetGeneralFont()
    local defaultOutline = GetGeneralFontOutline()
    icon.Stacks:SetFont(defaultFont, 10, defaultOutline)

    -- Metadata
    icon._auraInstanceID = nil
    icon._auraSlot = nil
    icon._spellId = nil
    icon._filter = nil
    icon._rawDuration = nil
    icon._rawExpirationTime = nil
    icon._baseSwipeReverse = baseSwipeReverse
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
        if InCombatLockdown() then
            -- Combat: SetUnitAuraByAuraInstanceID taints GameTooltip with
            -- secret values causing BackdropTemplate errors. Use SetSpellByID
            -- instead (static spell data, no secret values).
            if self._spellId then
                pcall(GameTooltip.SetSpellByID, GameTooltip, self._spellId)
            end
        elseif self._auraInstanceID and self._auraInstanceID > 0 then
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

    -- Right-click to cancel buff (out of combat only).
    -- CancelUnitBuff requires a sequential buff index, so look it up from
    -- the stored aura instance ID via C_UnitAuras.GetAuraDataByIndex.
    icon:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if InCombatLockdown() then return end
        if not self._auraInstanceID or self._auraInstanceID <= 0 then return end
        if self._filter ~= "HELPFUL" then return end

        local target = self._auraInstanceID
        for i = 1, 40 do
            local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not data then break end
            if data.auraInstanceID == target then
                CancelUnitBuff("player", i, "HELPFUL")
                return
            end
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
        icon._spellId = nil
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
    if icon._cancelBtn then icon._cancelBtn:Hide() end
    icon:Hide()
    icon:ClearAllPoints()
    icon._auraInstanceID = nil
    icon._auraSlot = nil
    icon._spellId = nil
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

    -- Swipe visibility (swipe = dark fill, edge = bright leading line)
    if icon.Cooldown then
        local showSwipe = not settings.hideSwipe
        icon.Cooldown:SetDrawSwipe(showSwipe)
        icon.Cooldown:SetDrawEdge(showSwipe)
    end

    -- Font settings
    local font = GetGeneralFont()
    local outline = GetGeneralFontOutline()
    local fontSize = settings.fontSize or 12
    icon.Stacks:SetFont(font, fontSize, outline)

    -- Stack text positioning (per-frame keys)
    local tp = isBuff and "buff" or "debuff"
    local stackAnchor = settings[tp .. "StackTextAnchor"] or "BOTTOMRIGHT"
    local stackOffX = settings[tp .. "StackTextOffsetX"]
    if stackOffX == nil then stackOffX = -1 end
    local stackOffY = settings[tp .. "StackTextOffsetY"]
    if stackOffY == nil then stackOffY = 1 end
    icon.Stacks:ClearAllPoints()
    icon.Stacks:SetPoint(stackAnchor, icon.TextOverlay, stackAnchor, stackOffX, stackOffY)
    -- Adjust text justification based on anchor
    if stackAnchor == "TOPLEFT" or stackAnchor == "LEFT" or stackAnchor == "BOTTOMLEFT" then
        icon.Stacks:SetJustifyH("LEFT")
    elseif stackAnchor == "TOPRIGHT" or stackAnchor == "RIGHT" or stackAnchor == "BOTTOMRIGHT" then
        icon.Stacks:SetJustifyH("RIGHT")
    else
        icon.Stacks:SetJustifyH("CENTER")
    end

    -- Style and position Blizzard's auto-managed countdown FontString
    if icon.Cooldown.GetCountdownFontString then
        local cdText = icon.Cooldown:GetCountdownFontString()
        if cdText and cdText.SetFont then
            cdText:SetFont(font, fontSize, outline)
            local cdAnchor = settings[tp .. "DurationTextAnchor"] or "CENTER"
            local cdOffX = settings[tp .. "DurationTextOffsetX"] or 0
            local cdOffY = settings[tp .. "DurationTextOffsetY"] or 0
            pcall(cdText.ClearAllPoints, cdText)
            pcall(cdText.SetPoint, cdText, cdAnchor, icon.Cooldown, cdAnchor, cdOffX, cdOffY)
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

    local rowSpacing = settings[prefix .. "RowSpacing"] or 0
    if rowSpacing <= 0 then rowSpacing = spacing end

    local growLeft = settings[prefix .. "GrowLeft"]
    local growUp = settings[prefix .. "GrowUp"]

    local count = #sortedIcons
    if count == 0 then
        container:SetSize(1, 1)
        return
    end

    -- Growth-direction anchor — the corner that should stay fixed on screen.
    -- Used to position icons within the container. The container itself is
    -- positioned by ApplyFrameAnchor's growAnchor branch.
    local anchor
    if growUp then
        anchor = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        anchor = growLeft and "TOPRIGHT" or "TOPLEFT"
    end

    -- Compute grid dimensions and resize the container.
    local numCols = math.min(count, iconsPerRow)
    local numRows = math.ceil(count / iconsPerRow)
    local totalW = numCols * iconSize + math.max(0, numCols - 1) * spacing
    local bottomPadding = settings[prefix .. "BottomPadding"] or 10
    local totalH = numRows * iconSize + math.max(0, numRows - 1) * rowSpacing + bottomPadding

    container:SetSize(totalW, totalH)
    -- Cache the natural size so layout mode proxy movers can read it
    -- (frame.GetSize returns handle size when reparented via SetAllPoints).
    container._naturalW = totalW
    container._naturalH = totalH

    -- Re-apply the container's frame anchor now that we know its real size.
    -- ApplyFrameAnchor's growAnchor branch reads the current container size
    -- and computes the correct corner-anchored SetPoint to keep the visible
    -- icons stable as the container grows/shrinks. Skip during layout mode —
    -- the handle system owns the container position there.
    if not Helpers.IsLayoutModeActive() then
        local faKey
        local name = container:GetName()
        if name == "QUI_BuffIconContainer" then
            faKey = "buffFrame"
        elseif name == "QUI_DebuffIconContainer" then
            faKey = "debuffFrame"
        end
        if faKey and _G.QUI_ApplyFrameAnchor then
            _G.QUI_ApplyFrameAnchor(faKey)
        end
    end

    local colStep = iconSize + spacing
    local rowStep = iconSize + rowSpacing

    for i, icon in ipairs(sortedIcons) do
        local idx = i - 1
        local col = idx % iconsPerRow
        local row = math.floor(idx / iconsPerRow)

        local xOff = growLeft and -(col * colStep) or (col * colStep)
        local yOff = growUp and (row * rowStep) or -(row * rowStep)

        icon:SetSize(iconSize, iconSize)
        icon:ClearAllPoints()
        icon:SetPoint(anchor, container, anchor, xOff, yOff)
    end

    -- Re-sync layout mode handle to match the updated container size.
    -- Needed for proxy movers (which don't auto-track via SetAllPoints).
    if Helpers.IsLayoutModeActive() and _G.QUI_LayoutModeSyncHandle then
        local name = container:GetName()
        if name == "QUI_BuffIconContainer" then
            _G.QUI_LayoutModeSyncHandle("buffFrame")
        elseif name == "QUI_DebuffIconContainer" then
            _G.QUI_LayoutModeSyncHandle("debuffFrame")
        end
    end
end

---------------------------------------------------------------------------
-- BANISH / RESTORE BLIZZARD FRAMES
---------------------------------------------------------------------------

-- Recursively enable/disable mouse on all descendant frames.
-- Blizzard child buttons remain mouse-interactive at alpha 0,
-- producing phantom tooltips from the banished BuffFrame/DebuffFrame.
local function SetDescendantMouse(frame, enable)
    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
        if child then
            if child.EnableMouse then child:EnableMouse(enable) end
            SetDescendantMouse(child, enable)
        end
    end
end

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
    SetDescendantMouse(frame, false)

    -- Hook Show to re-enforce hiding
    if not showHookedFlag then
        showHookedFlag = true
        hooksecurefunc(frame, "Show", function(self)
            C_Timer.After(0, function()
                if self._quiBanished then
                    self:SetAlpha(0)
                    self:EnableMouse(false)
                    SetDescendantMouse(self, false)
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
                        SetDescendantMouse(self, false)
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
    SetDescendantMouse(frame, true)
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

    -- Scan current auras via instance-ID API (covers all aura types including
    -- consumable buffs like augment runes that ForEachAura's slot iteration can miss)
    local currentAuras = {}

    if C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs then
        local ids = C_UnitAuras.GetUnitAuraInstanceIDs("player", filter)
        if ids then
            for _, auraID in ipairs(ids) do
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraID)
                if auraData then
                    currentAuras[auraID] = auraData
                end
            end
        end
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
        icon._spellId = auraData.spellId
        icon._filter = filter

        -- Texture: prefer spell-specific lookup — auraData.icon can return
        -- the granting spell's icon instead of the buff's own icon for some auras
        local texID
        if auraData.spellId and C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, auraData.spellId)
            if ok and tex then texID = tex end
        end
        texID = texID or auraData.icon
        if texID and icon.Icon then
            icon.Icon:SetTexture(texID)
        end

        -- Cooldown swipe (secret-safe via pcall to C-side)
        local duration = auraData.duration
        local expirationTime = auraData.expirationTime

        -- Store raw values (may be secret) — C-side functions handle them
        icon._rawDuration = duration
        icon._rawExpirationTime = expirationTime

        -- Optional inversion so users can choose whether darkening ramps up
        -- toward expiration or ramps down from full duration.
        if icon.Cooldown and icon.Cooldown.SetReverse then
            local invertKey = isBuff and "buffInvertSwipeDarkening" or "debuffInvertSwipeDarkening"
            local invert = not not settings[invertKey]
            local baseReverse = not not icon._baseSwipeReverse
            local targetReverse = invert and (not baseReverse) or baseReverse
            pcall(icon.Cooldown.SetReverse, icon.Cooldown, targetReverse)
        end

        -- Cooldown swipe: prefer numeric path (correct remaining-time display),
        -- fall back to DurationObject only when values are secret (combat).
        if expirationTime and duration then
            if not IsSecretValue(expirationTime) and not IsSecretValue(duration) then
                -- Non-secret: SetCooldown with computed start time — always
                -- shows correct remaining time for long-duration auras.
                local startTime = expirationTime - duration
                pcall(icon.Cooldown.SetCooldown, icon.Cooldown, startTime, duration)
            elseif icon._auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration
                   and icon.Cooldown.SetCooldownFromDurationObject then
                -- Combat (secret values): DurationObject is C-side safe
                local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, "player", icon._auraInstanceID)
                if ok and durObj then
                    pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, durObj, true)
                else
                    icon.Cooldown:Clear()
                end
            else
                icon.Cooldown:Clear()
            end
        else
            icon.Cooldown:Clear()
        end

        -- Stacks
        if settings.showStacks ~= false then
            local applications = auraData.applications
            if applications then
                if not IsSecretValue(applications) then
                    -- Out of combat: filter single-stack display
                    if applications > 1 then
                        icon.Stacks:SetText(applications)
                        icon.Stacks:Show()
                    else
                        icon.Stacks:SetText("")
                        icon.Stacks:Hide()
                    end
                else
                    -- Combat secret: C_StringUtil.TruncateWhenZero is C-side,
                    -- accepts secret values and returns "" for zero stacks
                    pcall(icon.Stacks.SetText, icon.Stacks, C_StringUtil.TruncateWhenZero(applications))
                    icon.Stacks:Show()
                end
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

---------------------------------------------------------------------------
-- PRIVATE AURAS (player debuffs hidden from addon APIs)
-- These auras are invisible to AuraUtil.ForEachAura and can only be
-- displayed via C_UnitAuras.AddPrivateAuraAnchor (client-side rendering).
---------------------------------------------------------------------------
local function ClearPrivateAuraAnchors()
    if not RemovePrivateAuraAnchor then return end
    if InCombatLockdown() then
        paPendingSetup = true
        return
    end
    for i = 1, #paAnchorIDs do
        local id = paAnchorIDs[i]
        if id then pcall(RemovePrivateAuraAnchor, id) end
    end
    wipe(paAnchorIDs)
    -- Hide any stale WoW-rendered children left on anchor slots
    for i = 1, PA_MAX_SLOTS do
        local slot = paSlots[i]
        if slot then
            for j = 1, slot:GetNumChildren() do
                local child = select(j, slot:GetChildren())
                if child then child:Hide() end
            end
        end
    end
end

local function EnsureSlotBorders(slot)
    if slot.BorderTop then return end
    slot.BorderTop = slot:CreateTexture(nil, "OVERLAY", nil, 7)
    slot.BorderBottom = slot:CreateTexture(nil, "OVERLAY", nil, 7)
    slot.BorderLeft = slot:CreateTexture(nil, "OVERLAY", nil, 7)
    slot.BorderRight = slot:CreateTexture(nil, "OVERLAY", nil, 7)

    slot.BorderTop:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
    slot.BorderTop:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)
    slot.BorderBottom:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0, 0)
    slot.BorderBottom:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
    slot.BorderLeft:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
    slot.BorderLeft:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0, 0)
    slot.BorderRight:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)
    slot.BorderRight:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
end

local function SlotHasVisibleAura(slot)
    for i = 1, slot:GetNumChildren() do
        local child = select(i, slot:GetChildren())
        if child and child:IsShown() then return true end
    end
    return false
end

local function StyleSlotBorders(slot, settings)
    if not slot.BorderTop then return end
    local borderSize = settings and settings.borderSize or 2
    local r, g, b = BORDER_COLOR_DEBUFF_DEFAULT[1], BORDER_COLOR_DEBUFF_DEFAULT[2], BORDER_COLOR_DEBUFF_DEFAULT[3]

    slot.BorderTop:SetColorTexture(r, g, b, 1)
    slot.BorderBottom:SetColorTexture(r, g, b, 1)
    slot.BorderLeft:SetColorTexture(r, g, b, 1)
    slot.BorderRight:SetColorTexture(r, g, b, 1)

    slot.BorderTop:SetHeight(borderSize)
    slot.BorderBottom:SetHeight(borderSize)
    slot.BorderLeft:SetWidth(borderSize)
    slot.BorderRight:SetWidth(borderSize)

    -- Only show borders when the client has rendered a visible aura child
    local visible = SlotHasVisibleAura(slot)
    slot.BorderTop:SetShown(visible)
    slot.BorderBottom:SetShown(visible)
    slot.BorderLeft:SetShown(visible)
    slot.BorderRight:SetShown(visible)
end

local function StyleSlotTextRecursive(node, settings, depth)
    if not node or depth > 5 then return end

    local font = GetGeneralFont()
    local outline = GetGeneralFontOutline()
    local fontSize = settings.fontSize or 12

    -- Style FontString regions on this node
    for i = 1, (node.GetNumRegions and node:GetNumRegions() or 0) do
        local region = select(i, node:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("FontString") and region.SetFont then
            pcall(region.SetFont, region, font, fontSize, outline)
            -- Reposition duration/stack text using debuff settings
            local text = region:GetText()
            if text then
                local anchor = settings.debuffDurationTextAnchor or "CENTER"
                local offX = settings.debuffDurationTextOffsetX or 0
                local offY = settings.debuffDurationTextOffsetY or 0
                pcall(region.ClearAllPoints, region)
                pcall(region.SetPoint, region, anchor, region:GetParent(), anchor, offX, offY)
            end
        end
    end

    -- Style Cooldown countdown FontStrings
    if node.IsObjectType and node:IsObjectType("Cooldown") and node.GetCountdownFontString then
        local cdText = node:GetCountdownFontString()
        if cdText and cdText.SetFont then
            pcall(cdText.SetFont, cdText, font, fontSize, outline)
            local anchor = settings.debuffDurationTextAnchor or "CENTER"
            local offX = settings.debuffDurationTextOffsetX or 0
            local offY = settings.debuffDurationTextOffsetY or 0
            pcall(cdText.ClearAllPoints, cdText)
            pcall(cdText.SetPoint, cdText, anchor, node, anchor, offX, offY)
        end
    end

    -- Recurse into children
    for i = 1, (node.GetNumChildren and node:GetNumChildren() or 0) do
        local child = select(i, node:GetChildren())
        if child then
            StyleSlotTextRecursive(child, settings, depth + 1)
        end
    end
end

local function DeferStyleSlotText(slot, settings)
    C_Timer.After(0, function()
        if not slot:IsShown() then return end
        StyleSlotBorders(slot, settings)
        StyleSlotTextRecursive(slot, settings, 1)
    end)
end

local function SetupPrivateAuras()
    if not AddPrivateAuraAnchor or not debuffContainer then return end
    if InCombatLockdown() then
        paPendingSetup = true
        return
    end
    ClearPrivateAuraAnchors()

    local settings = GetSettings()
    local iconSize = DEFAULT_ICON_SIZE
    if settings then
        local s = settings.debuffIconSize or 0
        if s > 0 then iconSize = s end
    end

    local borderSize = settings and settings.borderSize or 2

    for i = 1, PA_MAX_SLOTS do
        local slot = paSlots[i]
        if not slot then
            slot = CreateFrame("Frame", "QUI_PlayerPrivateAura" .. i, debuffContainer)
            slot:SetIgnoreParentAlpha(true)
            paSlots[i] = slot
        end
        slot:SetParent(debuffContainer)
        slot:SetSize(iconSize, iconSize)
        slot:SetFrameLevel(debuffContainer:GetFrameLevel() + 5)
        slot:Show()

        -- Add and style border textures to match normal debuff icons
        EnsureSlotBorders(slot)
        StyleSlotBorders(slot, settings)

        -- Inset the icon by borderSize so the border is visible around it
        local ok, anchorID = pcall(AddPrivateAuraAnchor, {
            unitToken = "player",
            auraIndex = i,
            parent = slot,
            showCountdownFrame = true,
            showCountdownNumbers = true,
            iconInfo = {
                iconWidth = iconSize - borderSize * 2,
                iconHeight = iconSize - borderSize * 2,
                borderScale = -1000,
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = slot,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            },
        })
        paAnchorIDs[i] = ok and anchorID or nil
    end

    -- Defer text styling — client creates children asynchronously
    for _, slot in ipairs(paSlots) do
        DeferStyleSlotText(slot, settings)
    end
end

local function LayoutPrivateAuraSlots()
    if not AddPrivateAuraAnchor or #paSlots == 0 then return end

    local settings = GetSettings()
    if not settings or not settings.enableDebuffs or settings.hideDebuffFrame then
        for _, slot in ipairs(paSlots) do
            slot:Hide()
        end
        return
    end

    local iconSize = settings.debuffIconSize or 0
    if iconSize <= 0 then iconSize = DEFAULT_ICON_SIZE end
    local iconsPerRow = settings.debuffIconsPerRow or 0
    if iconsPerRow <= 0 then iconsPerRow = 10 end
    local spacing = settings.debuffIconSpacing or 0
    if spacing <= 0 then spacing = 2 end
    local growLeft = settings.debuffGrowLeft
    local growUp = settings.debuffGrowUp

    local anchor
    if growUp then
        anchor = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        anchor = growLeft and "TOPRIGHT" or "TOPLEFT"
    end

    local debuffCount = #debuffSortedIcons
    local step = iconSize + spacing

    for i, slot in ipairs(paSlots) do
        local idx = debuffCount + i - 1
        local col = idx % iconsPerRow
        local row = math.floor(idx / iconsPerRow)

        local xOff = growLeft and -(col * step) or (col * step)
        local yOff = growUp and (row * step) or -(row * step)

        slot:SetSize(iconSize, iconSize)
        slot:ClearAllPoints()
        slot:SetPoint(anchor, debuffContainer, anchor, xOff, yOff)
        StyleSlotBorders(slot, settings)
        slot:Show()
    end
end

---------------------------------------------------------------------------
-- WEAPON ENCHANT ICONS (oils, whetstones, etc.)
-- Owned icons in the buff container, driven by GetWeaponEnchantInfo()
---------------------------------------------------------------------------
local ENCHANT_SLOTS = { 16, 17 } -- INVSLOT_MAINHAND, INVSLOT_OFFHAND

local function ReleaseEnchantIcon(slot)
    local icon = enchantActiveIcons[slot]
    if icon then
        ReleaseIcon(icon)
        enchantActiveIcons[slot] = nil
        enchantCachedDuration[slot] = nil
    end
end

local function UpdateWeaponEnchantIcons()
    if not buffContainer then return end
    local settings = GetSettings()
    if not settings or not settings.enableBuffs or settings.hideBuffFrame then
        for _, slot in ipairs(ENCHANT_SLOTS) do
            ReleaseEnchantIcon(slot)
        end
        return
    end

    local hasMain, mainExp, _, mainID, hasOff, offExp, _, offID = GetWeaponEnchantInfo()
    local slotData = {
        [16] = hasMain and { expiration = mainExp, enchantID = mainID },
        [17] = hasOff  and { expiration = offExp,  enchantID = offID  },
    }

    for _, slot in ipairs(ENCHANT_SLOTS) do
        local data = slotData[slot]
        if data then
            -- Secret-value guard: expiration can be secret in combat
            local expMs = data.expiration
            local isSecret = IsSecretValue(expMs)

            local icon = enchantActiveIcons[slot]
            if not icon then
                icon = AcquireIcon(buffContainer)
                enchantActiveIcons[slot] = icon
                icon._enchantSlot = slot
                icon._auraInstanceID = nil
                icon._spellId = nil
                icon._filter = "HELPFUL"
            end

            -- Texture: use the equipped weapon's icon
            local texture = GetInventoryItemTexture("player", slot)
            if texture and icon.Icon then
                icon.Icon:SetTexture(texture)
            end

            -- Cooldown sweep
            if not isSecret and expMs and expMs > 0 then
                local remainingSec = expMs / 1000
                -- Cache total duration on first sight so the sweep is proportional
                if not enchantCachedDuration[slot] then
                    enchantCachedDuration[slot] = remainingSec
                end
                local total = enchantCachedDuration[slot]
                local startTime = GetTime() - (total - remainingSec)
                pcall(icon.Cooldown.SetCooldown, icon.Cooldown, startTime, total)
            else
                icon.Cooldown:Clear()
            end

            icon.Stacks:SetText("")
            icon.Stacks:Hide()
            StyleIcon(icon, settings, true, nil)
            icon:Show()

            -- Tooltip: show weapon tooltip (includes enchant line)
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
                pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", self._enchantSlot)
                pcall(GameTooltip.Show, GameTooltip)
                local container = self:GetParent()
                if container and container._fadeEnabled then
                    container:SetAlpha(1)
                end
            end)
            icon:SetScript("OnLeave", function(self)
                pcall(GameTooltip.Hide, GameTooltip)
                local container = self:GetParent()
                if container and container._fadeEnabled then
                    local s = GetSettings()
                    container:SetAlpha(s and s.fadeOutAlpha or 0)
                end
            end)
            -- CancelItemTempEnchantment is protected, so we overlay a secure
            -- button whose cancelaura action calls it via Blizzard's own
            -- SECURE_ACTIONS handler (target-slot → CANCELABLE_ITEMS lookup).
            if not icon._cancelBtn then
                local btn = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
                btn:SetAllPoints(icon)
                btn:RegisterForClicks("RightButtonUp")
                btn:SetAttribute("type2", "cancelaura")
                -- Pass tooltip events through to the underlying icon
                btn:SetScript("OnEnter", function(self)
                    local parent = self:GetParent()
                    if parent and parent:GetScript("OnEnter") then
                        parent:GetScript("OnEnter")(parent)
                    end
                end)
                btn:SetScript("OnLeave", function(self)
                    local parent = self:GetParent()
                    if parent and parent:GetScript("OnLeave") then
                        parent:GetScript("OnLeave")(parent)
                    end
                end)
                icon._cancelBtn = btn
            end
            icon._cancelBtn:SetAttribute("target-slot2", slot)
            icon._cancelBtn:Show()
        else
            ReleaseEnchantIcon(slot)
        end
    end
end

---------------------------------------------------------------------------
-- AURA UPDATE WRAPPERS
---------------------------------------------------------------------------
local function UpdateBuffIcons()
    local settings = GetSettings()
    if not settings then return end
    if previewActive then return end
    UpdateAuraIcons(buffContainer, buffActiveIcons, buffSortedIcons, "HELPFUL", true, settings, "buff")
    UpdateWeaponEnchantIcons()
    -- Prepend weapon enchant icons before aura icons and re-layout
    local hasEnchants = false
    for _, slot in ipairs(ENCHANT_SLOTS) do
        if enchantActiveIcons[slot] then
            hasEnchants = true
            break
        end
    end
    if hasEnchants then
        local combined = {}
        for _, slot in ipairs(ENCHANT_SLOTS) do
            if enchantActiveIcons[slot] then
                combined[#combined + 1] = enchantActiveIcons[slot]
            end
        end
        for _, icon in ipairs(buffSortedIcons) do
            combined[#combined + 1] = icon
        end
        LayoutIcons(buffContainer, combined, settings, "buff")
    end
end

-- Rate-limited private aura anchor re-registration to clean up stale renders.
-- WoW's AddPrivateAuraAnchor rendering can persist after the aura expires;
-- re-registering forces the client to re-evaluate active private auras.
local paLastRefresh = 0
local PA_REFRESH_CD = 1.0

local function RefreshPrivateAuraAnchors()
    if not AddPrivateAuraAnchor or not debuffContainer then return end
    if InCombatLockdown() then
        paPendingSetup = true
        return
    end
    local now = GetTime()
    if now - paLastRefresh < PA_REFRESH_CD then return end
    paLastRefresh = now
    ClearPrivateAuraAnchors()
    SetupPrivateAuras()
end

local function UpdateDebuffIcons()
    local settings = GetSettings()
    if not settings then return end
    if previewActive then return end
    UpdateAuraIcons(debuffContainer, debuffActiveIcons, debuffSortedIcons, "HARMFUL", false, settings, "debuff")
    RefreshPrivateAuraAnchors()
    LayoutPrivateAuraSlots()
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

    -- Hide private aura slots during preview
    for _, slot in ipairs(paSlots) do
        slot:Hide()
    end
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
-- Frame-show coalescing for buff/debuff border updates.
-- Show() is a no-op if already shown — automatic event batching.
local buffCoalesceFrame = CreateFrame("Frame")
buffCoalesceFrame:Hide()
buffCoalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    UpdateBuffIcons()
end)

local debuffCoalesceFrame = CreateFrame("Frame")
debuffCoalesceFrame:Hide()
debuffCoalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    UpdateDebuffIcons()
end)

local function ScheduleBuffUpdate()
    buffCoalesceFrame:Show()
end

local function ScheduleDebuffUpdate()
    debuffCoalesceFrame:Show()
end

---------------------------------------------------------------------------
-- FULL REFRESH (called from settings / profile switch)
---------------------------------------------------------------------------
-- Derive the growth-corner anchor for a buff/debuff container based on the
-- user's grow direction settings, and write it to the frame anchoring DB
-- entry.
--
-- Two cases depending on the entry's current format:
--
-- 1) Legacy CENTER format (point=CENTER, relative=CENTER): just set the
--    growAnchor metadata field. The apply path's CENTER→corner self-heal
--    branch will pick it up on the next apply, convert to corner format,
--    and write back.
--
-- 2) New corner format (point=<corner>, relative=<corner>): the stored
--    offsets are relative to the OLD corner. Changing grow direction
--    means changing which corner the frame anchors at. To preserve the
--    visual position of the growth origin (i.e. the first icon), we
--    recompute the offsets so the NEW corner lands at the same screen
--    position the OLD corner was at:
--      parent.newCorner + (newX, newY) = parent.oldCorner + (oldX, oldY)
--      newX = oldX + (FRAC_X[oldCorner] - FRAC_X[newCorner]) * pw
--      newY = oldY + (FRAC_Y[oldCorner] - FRAC_Y[newCorner]) * ph
--    Formula is independent of container size — the growth-anchor corner
--    stays at exactly the same screen point.
--
-- Called from FullRefresh whenever the user toggles a grow direction
-- checkbox, and from Init so the field is present on first load.
local GROW_ANCHOR_FRAC_X = { TOPLEFT = 0, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 1 }
local GROW_ANCHOR_FRAC_Y = { TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }

local function UpdateGrowAnchor(faKey)
    if not faKey then return end
    local profile = QUI and QUI.db and QUI.db.profile
    if not profile then return end
    local bbDB = profile.buffBorders
    if type(bbDB) ~= "table" then return end

    local growLeft, growUp
    if faKey == "buffFrame" then
        growLeft = bbDB.buffGrowLeft
        growUp   = bbDB.buffGrowUp
    elseif faKey == "debuffFrame" then
        growLeft = bbDB.debuffGrowLeft
        growUp   = bbDB.debuffGrowUp
    else
        return
    end

    local newCorner
    if growUp then
        newCorner = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        newCorner = growLeft and "TOPRIGHT" or "TOPLEFT"
    end

    if not profile.frameAnchoring then
        profile.frameAnchoring = {}
    end
    if not profile.frameAnchoring[faKey] then
        profile.frameAnchoring[faKey] = {}
    end
    local entry = profile.frameAnchoring[faKey]
    local oldCorner = entry.growAnchor

    if oldCorner == newCorner then return end  -- no change, skip

    -- Detect entry format: new corner format has point==relative==corner.
    local isNewCornerFormat = entry.point == oldCorner
        and entry.relative == oldCorner
        and GROW_ANCHOR_FRAC_X[oldCorner] ~= nil

    -- Free-position entries (pinned to the screen itself): recompute corner
    -- offsets so the NEW corner lands at the same screen point the OLD one
    -- was at. UIParent is the reference frame in both disabled and screen
    -- parent modes, so the math is identical.
    local isFreePosition = entry.parent == "disabled" or entry.parent == "screen"
    if isNewCornerFormat and oldCorner and isFreePosition then
        local pw = UIParent:GetWidth()
        local ph = UIParent:GetHeight()
        local dX = (GROW_ANCHOR_FRAC_X[oldCorner] - GROW_ANCHOR_FRAC_X[newCorner]) * pw
        local dY = (GROW_ANCHOR_FRAC_Y[oldCorner] - GROW_ANCHOR_FRAC_Y[newCorner]) * ph
        entry.offsetX = math.floor((entry.offsetX or 0) + dX + 0.5)
        entry.offsetY = math.floor((entry.offsetY or 0) + dY + 0.5)
        entry.point = newCorner
        entry.relative = newCorner
    end
    -- For legacy CENTER format: don't touch point/relative/offsets. The
    -- apply path's self-heal will convert on next apply using the current
    -- container size.

    entry.growAnchor = newCorner

    -- Re-apply so the new anchor takes effect immediately.
    if _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor(faKey)
    end
end

local function FullRefresh()
    ManageBlizzardFrames()

    -- Sync growAnchor from the user's grow direction settings. This catches
    -- any toggle of the Grow Left / Grow Up checkboxes in the layout mode
    -- settings panel — Refresh fires after the checkbox writes to bbDB.
    UpdateGrowAnchor("buffFrame")
    UpdateGrowAnchor("debuffFrame")

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

    -- Re-setup private aura anchors with current settings
    SetupPrivateAuras()

    -- Release weapon enchant icons and reset cached durations
    for _, slot in ipairs(ENCHANT_SLOTS) do
        ReleaseEnchantIcon(slot)
    end
    wipe(enchantCachedDuration)

    UpdateBuffIcons()
    UpdateDebuffIcons()
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
local function Init()
    -- Create containers
    buffContainer = CreateContainer("QUI_BuffIconContainer")
    debuffContainer = CreateContainer("QUI_DebuffIconContainer")

    -- Offset debuff container below buff container by default. This is a
    -- pre-anchor placeholder that gets immediately overridden by the
    -- applyAnchor calls below; it's just here in case applyAnchor bails
    -- (e.g. before the anchoring system is ready).
    debuffContainer:ClearAllPoints()
    debuffContainer:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -205, -58)

    -- Sync growAnchor from the user's grow direction settings BEFORE
    -- applyAnchor runs, so the apply path's growAnchor branch finds a
    -- corner value to convert against.
    UpdateGrowAnchor("buffFrame")
    UpdateGrowAnchor("debuffFrame")

    -- Re-apply saved anchoring positions now that QUI containers exist.
    -- ApplyAllFrameAnchors may have already run (via EDIT_MODE_LAYOUTS_UPDATED)
    -- before these containers were created, causing the resolver to fall back
    -- to Blizzard's BuffFrame/DebuffFrame instead of QUI's owned containers.
    -- UpdateGrowAnchor above already calls applyAnchor as part of writing
    -- the corner, but call again to be safe in case the field was already
    -- set and UpdateGrowAnchor short-circuited.
    local applyAnchor = _G.QUI_ApplyFrameAnchor
    if applyAnchor then
        applyAnchor("buffFrame")
        applyAnchor("debuffFrame")
    end

    -- Manage Blizzard frames
    ManageBlizzardFrames()

    -- Setup private aura display for player
    SetupPrivateAuras()

    -- Initial scan
    UpdateBuffIcons()
    UpdateDebuffIcons()
end

---------------------------------------------------------------------------
-- EVENT HANDLING: Subscribe to centralized aura dispatcher (player only)
---------------------------------------------------------------------------
if ns.AuraEvents then
    ns.AuraEvents:Subscribe("player", function(unit, updateInfo)
        ScheduleBuffUpdate()
        ScheduleDebuffUpdate()
    end)
end

-- Weapon enchant events: inventory changes and periodic expiration polling
local enchantEventFrame = CreateFrame("Frame")
enchantEventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
enchantEventFrame:SetScript("OnEvent", function(self, event, unit)
    if unit == "player" then
        -- Weapon changed — clear cached durations so new enchants get fresh totals
        wipe(enchantCachedDuration)
        ScheduleBuffUpdate()
    end
end)

-- Combat-end handler: process deferred private aura anchor work
local paRegenFrame = CreateFrame("Frame")
paRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
paRegenFrame:SetScript("OnEvent", function()
    if paPendingSetup then
        paPendingSetup = false
        SetupPrivateAuras()
        LayoutPrivateAuraSlots()
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
