-- buffborders.lua
-- Addon-owned buff/debuff icon display via SecureAuraHeaderTemplate
-- The header handles aura scanning, child creation, and positioning in
-- Blizzard's secure context; addon code mirrors non-protected visual state.

local _, ns = ...
local Helpers = ns.Helpers

local GetCore = Helpers.GetCore
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local ApplyCooldownFromAura = Helpers.ApplyCooldownFromAura

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
local format = string.format

-- Private aura API (WoW 10.1.0+)
local AddPrivateAuraAnchor = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor

-- 12.0.5+ requires `isContainer` on AddPrivateAuraAnchor args; non-container
-- anchors must pass `isContainer = false` or registration silently fails.
local CLIENT_VERSION = select(4, GetBuildInfo())
local IS_CONTAINER_SUPPORTED = CLIENT_VERSION and CLIENT_VERSION >= 120005

---------------------------------------------------------------------------
-- DEFAULTS
---------------------------------------------------------------------------
local DEFAULTS = {
    enableBuffs = true,
    enableDebuffs = true,
    showBuffBorders = true,
    showDebuffBorders = true,
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

local function GetBorderSizePx(frame, settings)
    local borderSize = settings and settings.borderSize
    if type(borderSize) ~= "number" then
        borderSize = DEFAULTS.borderSize
    end
    if borderSize <= 0 then return 0 end

    local core = GetCore and GetCore()
    if core and core.Pixels then
        return core:Pixels(borderSize, frame)
    end
    if core and core.GetPixelSize then
        return borderSize * core:GetPixelSize(frame)
    end
    return borderSize
end

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local DEFAULT_ICON_SIZE = 30
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
-- AURA FILTER / SORT CONFIG
--
-- Filter flags and sort rules are exposed as user options. Both the secure
-- header (string attributes) and C_UnitAuras.GetUnitAuras (enum args) must
-- receive equivalent values so child[i] in the header pairs to auras[i] in
-- the API result. Anything that diverges breaks the slot/index mapping the
-- way GetAuraDataByIndex(child:GetID()) used to.
---------------------------------------------------------------------------

-- DB key (per-frame) → AuraFilters flag appended to the filter string.
-- HELPFUL/HARMFUL is implicit on the per-frame call site.
local BUFF_FILTER_FLAGS = {
    { dbKey = "buffFilterPlayer",        flag = "PLAYER" },
    { dbKey = "buffFilterRaid",          flag = "RAID" },
    { dbKey = "buffFilterCancelable",    flag = "CANCELABLE" },
    { dbKey = "buffFilterNotCancelable", flag = "NOT_CANCELABLE" },
    { dbKey = "buffFilterBigDefensive",  flag = "BIG_DEFENSIVE" },
}

local DEBUFF_FILTER_FLAGS = {
    { dbKey = "debuffFilterPlayer",                flag = "PLAYER" },
    { dbKey = "debuffFilterRaid",                  flag = "RAID" },
    { dbKey = "debuffFilterIncludeNameplateOnly",  flag = "INCLUDE_NAME_PLATE_ONLY" },
    { dbKey = "debuffFilterRaidPlayerDispellable", flag = "RAID_PLAYER_DISPELLABLE" },
    { dbKey = "debuffFilterImportant",             flag = "IMPORTANT" },
    { dbKey = "debuffFilterCrowdControl",          flag = "CROWD_CONTROL" },
}

-- DB sort key → { rule = UnitAuraSortRule enum, legacy = SecureAuraHeader sortMethod }.
-- The legacy header has only INDEX/TIME/NAME, so Default and BigDefensive map
-- to their nearest legacy fit; the API side gets the precise enum.
local _sortRules = (Enum and Enum.UnitAuraSortRule) or {}
local SORT_TRANSLATIONS = {
    INDEX        = { rule = _sortRules.Unsorted       or 0, legacy = "INDEX" },
    DEFAULT      = { rule = _sortRules.Default        or 1, legacy = "INDEX" },
    EXPIRY       = { rule = _sortRules.Expiration     or 3, legacy = "TIME"  },
    EXPIRY_ONLY  = { rule = _sortRules.ExpirationOnly or 4, legacy = "TIME"  },
    NAME         = { rule = _sortRules.Name           or 5, legacy = "NAME"  },
    NAME_ONLY    = { rule = _sortRules.NameOnly       or 6, legacy = "NAME"  },
    BIG_DEFENSIVE = { rule = _sortRules.BigDefensive  or 2, legacy = "INDEX" },
}

local _sortDirs = (Enum and Enum.UnitAuraSortDirection) or {}
local SORT_DIR_NORMAL  = _sortDirs.Normal  or 0
local SORT_DIR_REVERSE = _sortDirs.Reverse or 1

local function BuildAuraFilter(settings, isBuff)
    local s = isBuff and "HELPFUL" or "HARMFUL"
    if not settings then return s end
    local list = isBuff and BUFF_FILTER_FLAGS or DEBUFF_FILTER_FLAGS
    for i = 1, #list do
        local entry = list[i]
        if settings[entry.dbKey] then
            s = s .. " " .. entry.flag
        end
    end
    return s
end

-- Returns: enumRule, legacyMethod, legacyDirection, enumDirection
local function GetSortConfig(settings, isBuff)
    local key = isBuff and (settings and settings.buffSortRule) or (settings and settings.debuffSortRule)
    local cfg = SORT_TRANSLATIONS[key] or SORT_TRANSLATIONS.INDEX
    local reverse = isBuff and (settings and settings.buffSortReverse) or (settings and settings.debuffSortReverse)
    if reverse then
        return cfg.rule, cfg.legacy, "-", SORT_DIR_REVERSE
    end
    return cfg.rule, cfg.legacy, "+", SORT_DIR_NORMAL
end

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
-- Weapon enchant cached total duration per slot
local enchantCachedDuration = {}

-- Sorted icon lists (kept as empty tables for legacy references)
local buffSortedIcons = {}
local debuffSortedIcons = {}

-- Containers (created in Init)
local buffContainer = nil
local debuffContainer = nil
local initialized = false

-- Blizzard frame banish state
local blizzBuffBanished = false
local blizzDebuffBanished = false
local blizzardBanishState = Helpers.CreateStateTable()
local blizzardBanishParent

local function GetBlizzardBanishState(frame)
    local state = blizzardBanishState[frame]
    if not state then
        state = {}
        blizzardBanishState[frame] = state
    end
    return state
end

-- Layout mode preview state
local previewActive = false

-- Private aura state (player debuffs hidden from addon APIs)
local PA_MAX_SLOTS = 3
local paSlots = {}
local paAnchorIDs = {}

---------------------------------------------------------------------------
-- ICON STYLING
---------------------------------------------------------------------------
-- Countdown text formatter shared by every aura cooldown. Exact clone of
-- Blizzard's SecondsToTimeAbbrev (Blizzard_SharedXML/TimeUtil.lua), which is
-- what the stock buff frame's duration text and the aura tooltip's remaining
-- line follow: ceil of the displayed unit, with each band starting at 1.5x the
-- unit (>=90s -> minutes, >=90m -> hours, >=36h -> days). So 2h00m01s left
-- renders "3h" and 3h00m01s renders "4h", in lockstep with the tooltip. The
-- default C-side countdown format disagreed with the tooltip on long auras,
-- which is the whole reason for a custom formatter; rendering stays fully
-- C-side (secret-safe) via SetCountdownFormatter.
local auraCountdownFormatter = false -- false = not yet built; nil = unsupported client
local function GetAuraCountdownFormatter()
    if auraCountdownFormatter == false then
        auraCountdownFormatter = nil
        local rounding = Enum.NumericRuleFormatRounding
        if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and rounding then
            local ok, formatter = pcall(C_StringUtil.CreateNumericRuleFormatter)
            if ok and formatter then
                local applied = pcall(formatter.SetBreakpoints, formatter, {
                    { threshold = 0, step = 1, rounding = rounding.Up, format = "%ds" },
                    { threshold = 90, format = "%dm",
                        components = { { div = 60, step = 1, rounding = rounding.Up } } },
                    { threshold = 5400, format = "%dh",
                        components = { { div = 3600, step = 1, rounding = rounding.Up } } },
                    { threshold = 129600, format = "%dd",
                        components = { { div = 86400, step = 1, rounding = rounding.Up } } },
                })
                if applied then
                    auraCountdownFormatter = formatter
                end
            end
        end
    end
    return auraCountdownFormatter
end

local function ConfigureAuraCooldownFrame(cooldown)
    if not cooldown then return end

    if cooldown.SetUseAuraDisplayTime then
        pcall(cooldown.SetUseAuraDisplayTime, cooldown, true)
    end
    -- Always render Blizzard's C-side countdown. The aura's remaining time
    -- can be secret in combat; only the C-side renderer can format secret
    -- numbers without surfacing them to Lua. No QUI Lua-side timer.
    if cooldown.SetHideCountdownNumbers then
        pcall(cooldown.SetHideCountdownNumbers, cooldown, false)
    end
    if cooldown.SetCountdownFormatter then
        local formatter = GetAuraCountdownFormatter()
        if formatter then
            pcall(cooldown.SetCountdownFormatter, cooldown, formatter)
        end
    end
end

---------------------------------------------------------------------------
-- DURATION TEXT
---------------------------------------------------------------------------
-- Duration is rendered ENTIRELY by Blizzard's C-side cooldown countdown
-- (ConfigureAuraCooldownFrame -> SetHideCountdownNumbers(false), fed by
-- ApplyCooldownFromAura -> SetCooldownFromDurationObject). There is NO QUI
-- Lua-side duration text. In combat the remaining time is a secret number
-- (both the GetUnitAuras expirationTime/duration fields and
-- DurationObject:GetRemainingDuration go secret), so only the C-side renderer
-- can format it. A Lua timer that read those values had to gate on
-- IsSecretValue and then froze at a stale value or blanked once combat made
-- them secret — most visibly on hour-long flasks, which span many combat
-- transitions with no per-aura structural refresh to heal the stale state.
local buffBorderStats -- debug counters; nil until QUI_Debug activates instrumentation (populated by SetupDebugInstrumentation at the bottom of this file)

local buffAuraChildrenByID = {}
local debuffAuraChildrenByID = {}

local function ClearAuraChildMapEntry(child)
    if not child then return end

    local map = child._quiAuraChildMap
    local key = child._quiAuraChildMapKey
    if map and key ~= nil then
        map[key] = nil
        if buffBorderStats then buffBorderStats.auraChildMapClears = buffBorderStats.auraChildMapClears + 1 end
    end

    child._quiAuraChildMap = nil
    child._quiAuraChildMapKey = nil
end

local function SetAuraChildMapEntry(child, auraChildMap, auraInstanceID)
    if not child or not auraChildMap then return end
    if IsSecretValue(auraInstanceID) or auraInstanceID == nil then
        ClearAuraChildMapEntry(child)
        return
    end

    local oldMap = child._quiAuraChildMap
    local oldKey = child._quiAuraChildMapKey
    if oldMap == auraChildMap and oldKey == auraInstanceID then
        return
    end

    if oldMap and oldKey ~= nil then
        oldMap[oldKey] = nil
        if buffBorderStats then buffBorderStats.auraChildMapClears = buffBorderStats.auraChildMapClears + 1 end
    end

    auraChildMap[auraInstanceID] = child
    child._quiAuraChildMap = auraChildMap
    child._quiAuraChildMapKey = auraInstanceID
    if buffBorderStats then buffBorderStats.auraChildMapWrites = buffBorderStats.auraChildMapWrites + 1 end
end

local function ClearStaleHeaderAuraChildMapEntries(header, firstIndex)
    if not header or not firstIndex then return end
    for i = firstIndex, 40 do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        ClearAuraChildMapEntry(child)
    end
end

local function StyleIcon(icon, settings, isBuff, debuffType)
    if not icon or not settings then return end

    local borderSizePx = GetBorderSizePx(icon, settings)

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

    icon.BorderTop:SetHeight(borderSizePx)
    icon.BorderBottom:SetHeight(borderSizePx)
    icon.BorderLeft:SetWidth(borderSizePx)
    icon.BorderRight:SetWidth(borderSizePx)

    local showBorders
    if isBuff then
        showBorders = settings.showBuffBorders ~= false
    else
        showBorders = settings.showDebuffBorders ~= false
    end
    icon.BorderTop:SetShown(showBorders)
    icon.BorderBottom:SetShown(showBorders)
    icon.BorderLeft:SetShown(showBorders)
    icon.BorderRight:SetShown(showBorders)

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
    if icon.Stacks and icon.Stacks.SetFont then
        icon.Stacks:SetFont(font, fontSize, outline)
    end

    -- Stack text positioning (per-frame keys)
    local tp = isBuff and "buff" or "debuff"
    local stackAnchor = settings[tp .. "StackTextAnchor"] or "BOTTOMRIGHT"
    local stackOffX = settings[tp .. "StackTextOffsetX"]
    if stackOffX == nil then stackOffX = -1 end
    local stackOffY = settings[tp .. "StackTextOffsetY"]
    if stackOffY == nil then stackOffY = 1 end
    if icon.Stacks then
        icon.Stacks:ClearAllPoints()
        -- TextOverlay may not exist on header children; anchor to icon itself
        local stackParent = icon.TextOverlay or icon
        icon.Stacks:SetPoint(stackAnchor, stackParent, stackAnchor, stackOffX, stackOffY)
        -- Adjust text justification based on anchor
        if stackAnchor == "TOPLEFT" or stackAnchor == "LEFT" or stackAnchor == "BOTTOMLEFT" then
            icon.Stacks:SetJustifyH("LEFT")
        elseif stackAnchor == "TOPRIGHT" or stackAnchor == "RIGHT" or stackAnchor == "BOTTOMRIGHT" then
            icon.Stacks:SetJustifyH("RIGHT")
        else
            icon.Stacks:SetJustifyH("CENTER")
        end
    end

    -- Style and position Blizzard's C-side countdown FontString — this IS the
    -- duration text (SetHideCountdownNumbers(false) keeps it visible), so font
    -- and DurationText anchor settings apply to it directly.
    local cdAnchor = settings[tp .. "DurationTextAnchor"] or "CENTER"
    local cdOffX = settings[tp .. "DurationTextOffsetX"] or 0
    local cdOffY = settings[tp .. "DurationTextOffsetY"] or 0
    if icon.Cooldown and icon.Cooldown.GetCountdownFontString then
        local cdText = icon.Cooldown:GetCountdownFontString()
        if cdText and cdText.SetFont then
            cdText:SetFont(font, fontSize, outline)
            pcall(cdText.ClearAllPoints, cdText)
            pcall(cdText.SetPoint, cdText, cdAnchor, icon.Cooldown, cdAnchor, cdOffX, cdOffY)
        end
    end
end

---------------------------------------------------------------------------
-- SECURE AURA HEADER CHILD REGIONS
-- Builds the visual regions the old QUIAuraTemplate XML provided, lazily and
-- idempotently, on secure aura-header children. Creating regions on a
-- protected frame is not a protected operation, so this is combat-safe for
-- children the header creates mid-fight. RegisterForClicks IS protected in
-- combat and is retried on every styling pass until it lands out of combat
-- (right-click cancelaura on a combat-born child is dead until then).
---------------------------------------------------------------------------
local function EnsureIconRegions(child)
    if not child.Icon then
        local iconTexture = child:CreateTexture(nil, "BACKGROUND")
        iconTexture:SetAllPoints(child)
        iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        child.Icon = iconTexture

        local function CreateEdge()
            local edge = child:CreateTexture(nil, "OVERLAY")
            edge:SetColorTexture(0, 0, 0, 1)
            return edge
        end
        child.BorderTop = CreateEdge()
        child.BorderTop:SetPoint("TOPLEFT")
        child.BorderTop:SetPoint("TOPRIGHT")
        child.BorderTop:SetHeight(2)
        child.BorderBottom = CreateEdge()
        child.BorderBottom:SetPoint("BOTTOMLEFT")
        child.BorderBottom:SetPoint("BOTTOMRIGHT")
        child.BorderBottom:SetHeight(2)
        child.BorderLeft = CreateEdge()
        child.BorderLeft:SetPoint("TOPLEFT")
        child.BorderLeft:SetPoint("BOTTOMLEFT")
        child.BorderLeft:SetWidth(2)
        child.BorderRight = CreateEdge()
        child.BorderRight:SetPoint("TOPRIGHT")
        child.BorderRight:SetPoint("BOTTOMRIGHT")
        child.BorderRight:SetWidth(2)

        child.Stacks = child:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        child.Stacks:SetPoint("BOTTOMRIGHT", -1, 1)

        child.Cooldown = CreateFrame("Cooldown", nil, child, "CooldownFrameTemplate")
        child.Cooldown:SetPoint("TOPLEFT")
        child.Cooldown:SetPoint("BOTTOMRIGHT")
    end

    if not child._quiClicksRegistered and (not InCombatLockdown() or ns._inInitSafeWindow) then
        child:RegisterForClicks("RightButtonUp", "RightButtonDown")
        child._quiClicksRegistered = true
    end
end

---------------------------------------------------------------------------
-- BLANK AN UNPAINTED CHILD
-- The secure header lays out children synchronously on UNIT_AURA and hides
-- truly-dead children itself (SecureGroupHeaders configureAuras), but our
-- styling is coalesced a frame later, so the header can briefly show a pooled
-- child that GetUnitAuras has no live aura for this pass. The border/icon/
-- cooldown/stacks are QUI-owned regions parented to the child — they only
-- vanish when the child frame hides, which is the header's job, NOT ours
-- (hiding a secure child from insecure code taints / is protected in combat).
-- So clear our own regions, or a stale border is left sitting on an
-- apparently-empty slot. All operations target QUI-created regions, so none
-- are protected — safe in combat.
---------------------------------------------------------------------------
local function BlankAuraChild(child)
    if not child then return end
    if child.Icon then pcall(child.Icon.SetTexture, child.Icon, nil) end
    if child.BorderTop then
        child.BorderTop:SetShown(false)
        child.BorderBottom:SetShown(false)
        child.BorderLeft:SetShown(false)
        child.BorderRight:SetShown(false)
    end
    if child.Cooldown then
        pcall(child.Cooldown.Clear, child.Cooldown)
    end
    if child.Stacks then
        pcall(child.Stacks.SetText, child.Stacks, "")
        pcall(child.Stacks.Hide, child.Stacks)
    end
    child._auraInstanceID = nil
    child._spellId = nil
    ClearAuraChildMapEntry(child)
end

---------------------------------------------------------------------------
-- SECURE AURA HEADER
---------------------------------------------------------------------------
local function CreateHeader(name, filter)
    -- Don't pass name to CreateFrame — C-side name registration makes the
    local header = CreateFrame("Frame", nil, UIParent, "SecureAuraHeaderTemplate")
    if name then _G[name] = header end
    header:SetClampedToScreen(true)
    header:SetAttribute("unit", "player")
    header:SetAttribute("filter", filter)
    header:SetAttribute("template", "SecureActionButtonTemplate")
    -- Secure per-child config (replaces the old QUIAuraTemplate XML): runs in
    -- the header's restricted env as each child is created. Size/frame level
    -- let the header lay the child out; type=cancelaura makes right clicks
    -- flow through SECURE_ACTIONS.cancelaura even for children born in combat.
    header:SetAttribute("initialConfigFunction", [=[
        self:SetWidth(30)
        self:SetHeight(30)
        self:SetFrameLevel(4)
        self:SetAttribute("type", "cancelaura")
    ]=])
    header:SetAttribute("minWidth", 1)
    header:SetAttribute("minHeight", 1)
    header:SetAttribute("sortMethod", "INDEX")
    header:SetAttribute("sortDirection", "+")
    if filter == "HELPFUL" then
        header:SetAttribute("includeWeapons", 1)
        header:SetAttribute("weaponTemplate", "SecureActionButtonTemplate")
    end

    header._fadeEnabled = false
    return header
end

---------------------------------------------------------------------------
-- SYNC HEADER ATTRIBUTES (settings → header layout attributes)
-- MUST only be called out of combat, except during the addon-load safe window.
---------------------------------------------------------------------------
local function SyncHeaderAttributes(header, settings, prefix)
    if InCombatLockdown() and not ns._inInitSafeWindow then return end
    if not header or not settings then return end

    -- Filter string + sort attributes are settings-driven. SetAttribute on a
    -- secure aura header is protected in combat — the early return above
    -- defers all such writes until PLAYER_REGEN_ENABLED triggers a refresh.
    local isBuff = (prefix == "buff")
    local filterString = BuildAuraFilter(settings, isBuff)
    header:SetAttribute("filter", filterString)
    local _, legacyMethod, legacyDir = GetSortConfig(settings, isBuff)
    header:SetAttribute("sortMethod", legacyMethod)
    header:SetAttribute("sortDirection", legacyDir)

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

    -- Growth direction → point attribute + offset signs
    local point, xDir, yDir
    if growUp then
        point = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
        yDir = 1
    else
        point = growLeft and "TOPRIGHT" or "TOPLEFT"
        yDir = -1
    end
    xDir = growLeft and -1 or 1

    header:SetAttribute("point", point)
    header:SetAttribute("xOffset", xDir * (iconSize + spacing))
    header:SetAttribute("yOffset", 0)
    header:SetAttribute("wrapAfter", iconsPerRow)
    header:SetAttribute("wrapXOffset", 0)
    header:SetAttribute("wrapYOffset", yDir * (iconSize + rowSpacing))

    header:SetAttribute("minWidth", iconSize)
    header:SetAttribute("minHeight", iconSize)

    -- initialConfigFunction: restricted Lua run in secure context when the
    -- header creates a new child. 'self' is the new child button. Bake the
    -- icon size directly into the snippet — updated each time SyncHeaderAttributes
    -- runs (out of combat). During combat, new children use the last-set size.
    -- CRITICAL: this OVERWRITES the snippet CreateHeader installed, so it must
    -- carry the same secure wiring — frame level AND type=cancelaura. Dropping
    -- type=cancelaura here silently kills right-click-to-remove for every child
    -- constructed after a settings/combat-end refresh (the child reaches
    -- SecureActionButton_OnClick with no `type` and SECURE_ACTIONS.cancelaura
    -- never runs). Inner quotes must be single — the format string is double-quoted.
    header:SetAttribute("initialConfigFunction",
        ("self:SetWidth(%d) self:SetHeight(%d) self:SetFrameLevel(4) self:SetAttribute('type', 'cancelaura')"):format(iconSize, iconSize)
    )
end

---------------------------------------------------------------------------
-- STYLE HEADER CHILDREN (replaces UpdateAuraIcons)
-- The header's secure code handles Show/Hide/SetPoint. We only do
-- non-protected visual operations (textures, borders, cooldowns).
---------------------------------------------------------------------------
local function StyleHeaderChildren(header, settings, isBuff)
    if not header or not settings then return end

    local iconSize = settings[(isBuff and "buff" or "debuff") .. "IconSize"] or 0
    if iconSize <= 0 then iconSize = DEFAULT_ICON_SIZE end
    local prefix = isBuff and "buff" or "debuff"
    local visibleCount = 0
    local auraChildMap = isBuff and buffAuraChildrenByID or debuffAuraChildrenByID
    local firstStaleChildIndex = nil

    -- Filter string and sort rule MUST match what SyncHeaderAttributes wrote
    -- to the secure header — child[i] in the header pairs to auras[i] only
    -- when both sides see the same flags + ordering. Single source of truth:
    -- BuildAuraFilter / GetSortConfig, both keyed off `settings`.
    local filter = BuildAuraFilter(settings, isBuff)
    local enumRule, _, _, enumDir = GetSortConfig(settings, isBuff)
    if buffBorderStats then buffBorderStats.unitAuraScans = buffBorderStats.unitAuraScans + 1 end
    local auras = C_UnitAuras.GetUnitAuras("player", filter, 40, enumRule, enumDir)

    for i = 1, 40 do
        local child = header:GetAttribute("child" .. i)
        if not child or not child:IsShown() then
            firstStaleChildIndex = i
            break
        end
        EnsureIconRegions(child)

        -- Pair child[i] to auras[i] — both are in slot order. AuraData fields
        -- can be ConditionalSecretContents in combat; pass directly to C-side
        -- sinks (SetTexture, SetText, SetCooldownFromDurationObject) without
        -- comparing or arithmetic. The auraInstanceID itself is the only
        -- field we use as a Lua handle — and only as an arg to C_UnitAuras.*
        -- calls that accept it.
        local data = auras and auras[i]
        if not data then
            -- GetUnitAuras returns a dense, never-nil table (UnitAura doc:
            -- auras Nilable=false), so a nil slot means this shown child has
            -- NO live aura — a surplus the secure header is still showing this
            -- frame (it lays out synchronously on UNIT_AURA; our styling is
            -- coalesced a frame later) or a pooled child mid-reuse. The header
            -- hides truly-dead children itself, but our borders/icon/cooldown
            -- are QUI-owned regions — blank every remaining shown child (the
            -- array is dense, so all later slots are empty too) so no stale
            -- border is left on an apparently-empty slot, then stop.
            for j = i, 40 do
                local staleChild = header:GetAttribute("child" .. j)
                if not staleChild or not staleChild:IsShown() then break end
                BlankAuraChild(staleChild)
            end
            firstStaleChildIndex = i
            break
        end

        visibleCount = visibleCount + 1

        -- Resize child (out of combat only — protected on secure children)
        if not InCombatLockdown() or ns._inInitSafeWindow then
            child:SetSize(iconSize, iconSize)
        end

        -- Texture: pass data.icon directly to C-side SetTexture (no branching)
        pcall(child.Icon.SetTexture, child.Icon, data.icon)

        -- Store metadata for tooltips (storing secret values, not branching)
        local auraInstanceID = data.auraInstanceID
        child._auraInstanceID = auraInstanceID
        child._spellId = data.spellId
        child._filter = filter
        child._quiHeaderSlot = i
        SetAuraChildMapEntry(child, auraChildMap, auraInstanceID)

        -- Buff cancellation (type=cancelaura) is declared securely via the
        -- header's initialConfigFunction so right clicks flow through
        -- SECURE_ACTIONS.cancelaura in combat.

        -- Tooltip handlers (set once, check flag)
        if not child._quiTooltipHooked then
            child._quiTooltipHooked = true
            child:HookScript("OnEnter", function(self)
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
                    if self._spellId then
                        pcall(GameTooltip.SetSpellByID, GameTooltip, self._spellId)
                    end
                else
                    local shown = false
                    if self._auraInstanceID and GameTooltip.SetUnitAuraByAuraInstanceID then
                        shown = pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, "player", self._auraInstanceID)
                    end
                    if not shown and self._spellId then
                        pcall(GameTooltip.SetSpellByID, GameTooltip, self._spellId)
                    end
                end
                pcall(GameTooltip.Show, GameTooltip)
                local container = self:GetParent()
                if container and container._fadeEnabled then
                    container:SetAlpha(1)
                end
            end)
            child:HookScript("OnLeave", function(self)
                pcall(GameTooltip.Hide, GameTooltip)
                local container = self:GetParent()
                if container and container._fadeEnabled then
                    local s = GetSettings()
                    container:SetAlpha(s and s.fadeOutAlpha or 0)
                end
            end)
        end

        -- Cooldown swipe + countdown text:
        --   • ApplyCooldownFromAura prefers SetCooldownFromDurationObject (the
        --     secret-safe path) and falls back to the numeric expiration only
        --     when readable. This drives BOTH the swipe and the countdown text.
        --   • The countdown text is Blizzard's built-in C-side renderer
        --     (ConfigureAuraCooldownFrame -> SetHideCountdownNumbers(false)).
        --     It is the ONLY thing that can format secret combat durations, so
        --     QUI does not render duration in Lua and never re-hides it here.
        if child.Cooldown then
            ConfigureAuraCooldownFrame(child.Cooldown)
            ApplyCooldownFromAura(
                child.Cooldown,
                "player",
                data.auraInstanceID,
                data.expirationTime,
                data.duration,
                true,
                data.timeMod
            )
            -- Swipe settings
            local showSwipe = not settings.hideSwipe
            child.Cooldown:SetDrawSwipe(showSwipe)
            child.Cooldown:SetDrawEdge(showSwipe)
            child.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
            child.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
            -- Swipe inversion
            local invertKey = prefix .. "InvertSwipeDarkening"
            local invert = not not settings[invertKey]
            pcall(child.Cooldown.SetReverse, child.Cooldown, invert)
        end

        -- Stacks (data.applications holds the stack count)
        -- Lazily create the Stacks FontString on header children (secure
        -- aura header does not provide one — only preview icons have it).
        if not child.Stacks then
            child.Stacks = child:CreateFontString(nil, "OVERLAY")
            child.Stacks:SetText("")
            child.Stacks:Hide()
        end
        pcall(child.Stacks.SetText, child.Stacks,
            C_StringUtil.TruncateWhenZero(data.applications))
        pcall(child.Stacks.Show, child.Stacks)

        -- Borders (via StyleIcon — reuse existing function)
        StyleIcon(child, settings, isBuff, data.dispelName)
    end

    ClearStaleHeaderAuraChildMapEntries(header, firstStaleChildIndex)

    -- Style weapon enchant children (buff header only)
    if isBuff then
        for _, key in ipairs({"tempEnchant1", "tempEnchant2", "tempEnchant3"}) do
            local child = header:GetAttribute(key)
            if child and child:IsShown() then
                visibleCount = visibleCount + 1
                EnsureIconRegions(child)
                if not InCombatLockdown() or ns._inInitSafeWindow then
                    child:SetSize(iconSize, iconSize)
                end
                -- Weapon enchant texture: use the equipped item icon
                local slot = key == "tempEnchant1" and 16 or key == "tempEnchant2" and 17 or 18
                local texture = GetInventoryItemTexture("player", slot)
                if child.Icon and texture then
                    pcall(child.Icon.SetTexture, child.Icon, texture)
                end
                -- Enchant cooldown from GetWeaponEnchantInfo. Text rendered
                -- by Blizzard's C-side countdown via ConfigureAuraCooldownFrame.
                if child.Cooldown then
                    ConfigureAuraCooldownFrame(child.Cooldown)
                    local hasMain, mainExp, _, _, hasOff, offExp = GetWeaponEnchantInfo()
                    local expMs = (slot == 16) and (hasMain and mainExp) or (slot == 17) and (hasOff and offExp) or nil
                    if expMs and not IsSecretValue(expMs) and expMs > 0 then
                        local remainingSec = expMs / 1000
                        if not enchantCachedDuration[slot] then
                            enchantCachedDuration[slot] = remainingSec
                        end
                        local total = enchantCachedDuration[slot]
                        local startTime = GetTime() - (total - remainingSec)
                        pcall(child.Cooldown.SetCooldown, child.Cooldown, startTime, total)
                    else
                        pcall(child.Cooldown.Clear, child.Cooldown)
                    end
                end
                StyleIcon(child, settings, true, nil)
                -- Tooltip for enchants
                if not child._quiEnchantTooltipHooked then
                    child._quiEnchantTooltipHooked = true
                    child._enchantSlot = slot
                    child:HookScript("OnEnter", function(self)
                        if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
                        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                        pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", self._enchantSlot)
                        pcall(GameTooltip.Show, GameTooltip)
                        local container = self:GetParent()
                        if container and container._fadeEnabled then
                            container:SetAlpha(1)
                        end
                    end)
                    child:HookScript("OnLeave", function(self)
                        pcall(GameTooltip.Hide, GameTooltip)
                        local container = self:GetParent()
                        if container and container._fadeEnabled then
                            local s = GetSettings()
                            container:SetAlpha(s and s.fadeOutAlpha or 0)
                        end
                    end)
                end
            end
        end
    end

    -- Cache visible count for private aura slot positioning
    if isBuff then
        header._visibleBuffCount = visibleCount
    else
        header._visibleDebuffCount = visibleCount
    end

    -- Compute container size from visible children for frame anchoring
    local iconsPerRow = settings[prefix .. "IconsPerRow"] or 0
    if iconsPerRow <= 0 then iconsPerRow = 10 end
    local spacing = settings[prefix .. "IconSpacing"] or 0
    if spacing <= 0 then spacing = 2 end
    local rowSpacing = settings[prefix .. "RowSpacing"] or 0
    if rowSpacing <= 0 then rowSpacing = spacing end

    -- Cache computed natural size for layout mode proxy movers.
    -- Cache computed size for the mover system (getSize callback).
    if visibleCount > 0 then
        local numCols = math.min(visibleCount, iconsPerRow)
        local numRows = math.ceil(visibleCount / iconsPerRow)
        local totalW = numCols * iconSize + math.max(0, numCols - 1) * spacing
        local totalH = numRows * iconSize + math.max(0, numRows - 1) * rowSpacing
        header._naturalW = totalW
        header._naturalH = totalH
    else
        header._naturalW = 1
        header._naturalH = 1
    end

    -- Re-anchor dependents and sync layout mode handles
    local faKey = isBuff and "buffFrame" or "debuffFrame"
    if not Helpers.IsLayoutModeActive() then
        if _G.QUI_ApplyFrameAnchor then
            _G.QUI_ApplyFrameAnchor(faKey)
            if _G.QUI_UpdateFramesAnchoredTo then
                _G.QUI_UpdateFramesAnchoredTo(faKey)
            end
        end
    else
        if _G.QUI_LayoutModeSyncHandle then
            _G.QUI_LayoutModeSyncHandle(faKey)
        end
    end

    -- Visibility (alpha-based, keep :Show() for layout mode overlays).
    -- SetAlpha is NOT protected — always update so containers become
    -- visible when auras appear during combat
    local fadeKey = isBuff and "fadeBuffFrame" or "fadeDebuffFrame"
    if visibleCount == 0 then
        header._fadeEnabled = false
        header:SetAlpha(0)
    elseif settings[fadeKey] then
        header._fadeEnabled = true
        header:SetAlpha(settings.fadeOutAlpha or 0)
    else
        header._fadeEnabled = false
        header:SetAlpha(1)
    end

    header._quiAuraChildMapReady = true
end

local function RefreshUpdatedAuraChild(child)
    local auraInstanceID = child and child._auraInstanceID
    if IsSecretValue(auraInstanceID) then return false end
    if auraInstanceID == nil then return false end

    if child.Cooldown then
        -- Re-apply the cooldown so Blizzard's C-side countdown refreshes for a
        -- reapplied aura. auraInstanceID is non-secret here (guarded above), so
        -- ApplyCooldownFromAura can fetch the DurationObject; the C-side
        -- renderer owns the countdown text (ConfigureAuraCooldownFrame keeps
        -- SetHideCountdownNumbers(false)).
        ConfigureAuraCooldownFrame(child.Cooldown)
        ApplyCooldownFromAura(child.Cooldown, "player", auraInstanceID, nil, nil, true)
    end

    if child.Stacks and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, countText = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, "player", auraInstanceID, 2, 99)
        if ok then
            pcall(child.Stacks.SetText, child.Stacks, countText or "")
            pcall(child.Stacks.Show, child.Stacks)
        end
    end

    return true
end

local function RefreshUpdatedAuraChildren(auraChildMap, updated)
    if not auraChildMap or not updated then return 0, false end
    local refreshed = 0

    for i = 1, #updated do
        local auraInstanceID = updated[i]
        if IsSecretValue(auraInstanceID) then
            return refreshed, true
        end

        if auraInstanceID ~= nil then
            local child = auraChildMap[auraInstanceID]
            if child and child:IsShown() then
                if RefreshUpdatedAuraChild(child) then
                    refreshed = refreshed + 1
                end
            end
        end
    end

    return refreshed, false
end

local function IsPureAuraUpdate(updateInfo)
    return type(updateInfo) == "table"
        and updateInfo.isFullUpdate ~= true
        and not updateInfo.addedAuras
        and not updateInfo.removedAuraInstanceIDs
        and type(updateInfo.updatedAuraInstanceIDs) == "table"
        and #updateInfo.updatedAuraInstanceIDs > 0
end

local function RefreshPureAuraUpdate(updateInfo)
    if not IsPureAuraUpdate(updateInfo) then return false end

    local settings = GetSettings()
    if not settings then return false end

    local refreshBuffs = buffContainer and settings.enableBuffs and not settings.hideBuffFrame
    local refreshDebuffs = debuffContainer and settings.enableDebuffs and not settings.hideDebuffFrame
    if refreshBuffs and not buffContainer._quiAuraChildMapReady then return false end
    if refreshDebuffs and not debuffContainer._quiAuraChildMapReady then return false end

    local updated = updateInfo.updatedAuraInstanceIDs
    local refreshed = 0
    local unresolved = false

    if refreshBuffs then
        local n, hasUnresolved = RefreshUpdatedAuraChildren(buffAuraChildrenByID, updated)
        refreshed = refreshed + n
        unresolved = unresolved or hasUnresolved
    end

    if refreshDebuffs then
        local n, hasUnresolved = RefreshUpdatedAuraChildren(debuffAuraChildrenByID, updated)
        refreshed = refreshed + n
        unresolved = unresolved or hasUnresolved
    end

    if unresolved then return false end
    if refreshed > 0 then
        if buffBorderStats then buffBorderStats.fastAuraUpdates = buffBorderStats.fastAuraUpdates + 1 end
    end
    return true
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

local function EnsureBlizzardBanishParent()
    if not blizzardBanishParent then
        blizzardBanishParent = CreateFrame("Frame", "QUI_BuffBordersHiddenParent", UIParent)
        blizzardBanishParent:Hide()
    end
    return blizzardBanishParent
end

local function RemoveFromManagedContainer(frame)
    if not frame then return nil end
    local currentParent = frame.GetParent and frame:GetParent() or nil
    if currentParent and currentParent.RemoveManagedFrame then
        pcall(currentParent.RemoveManagedFrame, currentParent, frame)
    end
    frame.ignoreFramePositionManager = true
    return currentParent
end

local function BanishBlizzardFrame(frame)
    if not frame then return false end
    if InCombatLockdown() and not ns._inInitSafeWindow then return false end

    local state = GetBlizzardBanishState(frame)
    if not state.banished then
        state.originalParent = frame.GetParent and frame:GetParent() or UIParent
        state.originalAlpha = frame.GetAlpha and frame:GetAlpha() or 1
        state.originalMouse = frame.IsMouseEnabled and frame:IsMouseEnabled()
        state.originalIgnoreFramePositionManager = frame.ignoreFramePositionManager
    end

    RemoveFromManagedContainer(frame)

    local hiddenParent = EnsureBlizzardBanishParent()
    if frame.SetParent and frame:GetParent() ~= hiddenParent then
        pcall(frame.SetParent, frame, hiddenParent)
    end
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
    SetDescendantMouse(frame, false)

    state.banished = true
    return true
end

local function RestoreBlizzardFrame(frame)
    if not frame then return false end
    if InCombatLockdown() and not ns._inInitSafeWindow then return false end

    local state = blizzardBanishState[frame]
    if state and state.originalIgnoreFramePositionManager ~= nil then
        frame.ignoreFramePositionManager = state.originalIgnoreFramePositionManager
    else
        frame.ignoreFramePositionManager = nil
    end

    local parent = state and state.originalParent or UIParent
    if frame.SetParent and parent then
        pcall(frame.SetParent, frame, parent)
    end

    local alpha = (state and state.originalAlpha ~= nil) and state.originalAlpha or 1
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, alpha) end

    local mouse = not (state and state.originalMouse == false)
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, mouse) end
    SetDescendantMouse(frame, mouse)

    if frame.Show then pcall(frame.Show, frame) end
    if state then state.banished = false end
    return true
end

---------------------------------------------------------------------------
-- PRIVATE AURAS (player debuffs hidden from addon APIs)
-- These auras are invisible to AuraUtil.ForEachAura and can only be
-- displayed via C_UnitAuras.AddPrivateAuraAnchor (client-side rendering).
---------------------------------------------------------------------------
local function ClearPrivateAuraAnchors()
    if not RemovePrivateAuraAnchor then return end
    for i = 1, #paAnchorIDs do
        local id = paAnchorIDs[i]
        if id then pcall(RemovePrivateAuraAnchor, id) end
    end
    wipe(paAnchorIDs)
    -- Hide any stale WoW-rendered children left on anchor slots. pcall in
    -- case any child is a protected C-side frame that can't be hidden in combat.
    for i = 1, PA_MAX_SLOTS do
        local slot = paSlots[i]
        if slot then
            for j = 1, slot:GetNumChildren() do
                local child = select(j, slot:GetChildren())
                if child then pcall(child.Hide, child) end
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

local function IsForbiddenObject(object)
    if not object or not object.IsForbidden then return false end
    local ok, forbidden = pcall(object.IsForbidden, object)
    return ok and forbidden
end

local function IsObjectTypeSafe(object, objectType)
    if not object or not object.IsObjectType then return false end
    local ok, matches = pcall(object.IsObjectType, object, objectType)
    return ok and matches
end

local function SlotHasVisibleAura(slot)
    if not slot or not slot.GetNumChildren then return false end
    local numOk, numChildren = pcall(slot.GetNumChildren, slot)
    if not numOk or not numChildren or numChildren == 0 then return false end
    local childrenOk, children = pcall(function() return { slot:GetChildren() } end)
    if not childrenOk or not children then return false end
    for i = 1, numChildren do
        local child = children[i]
        if child and not IsForbiddenObject(child) and child.IsShown then
            local ok, shown = pcall(child.IsShown, child)
            if ok and shown then return true end
        end
    end
    return false
end

local function StyleSlotBorders(slot, settings)
    if not slot.BorderTop then return end
    local borderSizePx = GetBorderSizePx(slot, settings)
    local r, g, b = BORDER_COLOR_DEBUFF_DEFAULT[1], BORDER_COLOR_DEBUFF_DEFAULT[2], BORDER_COLOR_DEBUFF_DEFAULT[3]

    slot.BorderTop:SetColorTexture(r, g, b, 1)
    slot.BorderBottom:SetColorTexture(r, g, b, 1)
    slot.BorderLeft:SetColorTexture(r, g, b, 1)
    slot.BorderRight:SetColorTexture(r, g, b, 1)

    slot.BorderTop:SetHeight(borderSizePx)
    slot.BorderBottom:SetHeight(borderSizePx)
    slot.BorderLeft:SetWidth(borderSizePx)
    slot.BorderRight:SetWidth(borderSizePx)

    -- Only show borders when the client has rendered a visible aura child
    -- and the user has borders enabled for debuffs.
    local showBorders = settings and settings.showDebuffBorders ~= false
    local visible = showBorders and SlotHasVisibleAura(slot)
    slot.BorderTop:SetShown(visible)
    slot.BorderBottom:SetShown(visible)
    slot.BorderLeft:SetShown(visible)
    slot.BorderRight:SetShown(visible)
end

local function StyleSlotTextRecursive(node, settings, depth)
    if not node or depth > 5 or IsForbiddenObject(node) then return end
    settings = settings or DEFAULTS

    local font = GetGeneralFont()
    local outline = GetGeneralFontOutline()
    local fontSize = settings.fontSize or 12

    -- Style FontString regions on this node
    local numRegions = 0
    local regions
    if node.GetNumRegions and node.GetRegions then
        local numOk, count = pcall(node.GetNumRegions, node)
        if numOk and type(count) == "number" and count > 0 then
            local regionsOk, regionList = pcall(function() return { node:GetRegions() } end)
            if regionsOk and regionList then
                numRegions = count
                regions = regionList
            end
        end
    end
    for i = 1, numRegions do
        local region = regions and regions[i]
        if region and not IsForbiddenObject(region) and IsObjectTypeSafe(region, "FontString") and region.SetFont then
            pcall(region.SetFont, region, font, fontSize, outline)
            -- Reposition duration/stack text using debuff settings
            local text
            if region.GetText then
                local textOk, textValue = pcall(region.GetText, region)
                if textOk then
                    text = SafeValue(textValue, nil)
                end
            end
            if text then
                local anchor = settings.debuffDurationTextAnchor or "CENTER"
                local offX = settings.debuffDurationTextOffsetX or 0
                local offY = settings.debuffDurationTextOffsetY or 0
                local parent
                if region.GetParent then
                    local parentOk, parentValue = pcall(region.GetParent, region)
                    if parentOk then parent = parentValue end
                end
                pcall(region.ClearAllPoints, region)
                pcall(region.SetPoint, region, anchor, parent or node, anchor, offX, offY)
            end
        end
    end

    -- Style Cooldown countdown FontStrings
    if IsObjectTypeSafe(node, "Cooldown") and node.GetCountdownFontString then
        local cdOk, cdText = pcall(node.GetCountdownFontString, node)
        if cdOk and cdText and not IsForbiddenObject(cdText) and cdText.SetFont then
            pcall(cdText.SetFont, cdText, font, fontSize, outline)
            local anchor = settings.debuffDurationTextAnchor or "CENTER"
            local offX = settings.debuffDurationTextOffsetX or 0
            local offY = settings.debuffDurationTextOffsetY or 0
            pcall(cdText.ClearAllPoints, cdText)
            pcall(cdText.SetPoint, cdText, anchor, node, anchor, offX, offY)
        end
    end

    -- Recurse into children
    local numChildren = 0
    local children
    if node.GetNumChildren and node.GetChildren then
        local numOk, count = pcall(node.GetNumChildren, node)
        if numOk and type(count) == "number" and count > 0 then
            local childrenOk, childList = pcall(function() return { node:GetChildren() } end)
            if childrenOk and childList then
                numChildren = count
                children = childList
            end
        end
    end
    for i = 1, numChildren do
        local child = children and children[i]
        if child and not IsForbiddenObject(child) then
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
    ClearPrivateAuraAnchors()

    local settings = GetSettings()
    local iconSize = DEFAULT_ICON_SIZE
    if settings then
        local s = settings.debuffIconSize or 0
        if s > 0 then iconSize = s end
    end

    local borderSizePx = GetBorderSizePx(debuffContainer, settings)

    for i = 1, PA_MAX_SLOTS do
        local slot = paSlots[i]
        if not slot then
            slot = CreateFrame("Frame", "QUI_PlayerPrivateAura" .. i, debuffContainer)
            slot:SetIgnoreParentAlpha(true)
            paSlots[i] = slot
        end
        slot:SetSize(iconSize, iconSize)
        slot:Show()

        -- Add and style border textures to match normal debuff icons
        EnsureSlotBorders(slot)
        StyleSlotBorders(slot, settings)

        -- Inset the icon by borderSize so the border is visible around it
        local anchorArgs = {
            unitToken = "player",
            auraIndex = i,
            parent = slot,
            showCountdownFrame = true,
            showCountdownNumbers = true,
            iconInfo = {
                iconWidth = iconSize - borderSizePx * 2,
                iconHeight = iconSize - borderSizePx * 2,
                borderScale = -1000,
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = slot,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            },
        }
        if IS_CONTAINER_SUPPORTED then anchorArgs.isContainer = false end
        local ok, anchorID = pcall(AddPrivateAuraAnchor, anchorArgs)
        paAnchorIDs[i] = ok and anchorID or nil
    end

    -- Defer text styling — client creates children asynchronously
    for _, slot in ipairs(paSlots) do
        DeferStyleSlotText(slot, settings)
    end
end

local function LayoutPrivateAuraSlots()
    if not AddPrivateAuraAnchor or #paSlots == 0 or not debuffContainer then return end

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
    local rowSpacing = settings.debuffRowSpacing or 0
    if rowSpacing <= 0 then rowSpacing = spacing end
    local growLeft = settings.debuffGrowLeft
    local growUp = settings.debuffGrowUp
    local xDir = growLeft and -1 or 1
    local yDir = growUp and 1 or -1
    local point = growUp
        and (growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT")
        or (growLeft and "TOPRIGHT" or "TOPLEFT")

    local debuffCount = debuffContainer._visibleDebuffCount or 0

    for i, slot in ipairs(paSlots) do
        local idx = debuffCount + i - 1
        local col = idx % iconsPerRow
        local row = math.floor(idx / iconsPerRow)

        slot:SetSize(iconSize, iconSize)
        slot:ClearAllPoints()
        slot:SetPoint(point, debuffContainer, point,
            xDir * col * (iconSize + spacing),
            yDir * row * (iconSize + rowSpacing))
        StyleSlotBorders(slot, settings)
        slot:Show()
    end
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
        if BanishBlizzardFrame(BuffFrame) then
            blizzBuffBanished = true
        end
    else
        if blizzBuffBanished then
            if RestoreBlizzardFrame(BuffFrame) then
                blizzBuffBanished = false
            end
        end
    end

    -- Debuff frame: banish when enabled, restore when disabled
    if settings.enableDebuffs then
        if BanishBlizzardFrame(DebuffFrame) then
            blizzDebuffBanished = true
        end
    else
        if blizzDebuffBanished then
            if RestoreBlizzardFrame(DebuffFrame) then
                blizzDebuffBanished = false
            end
        end
    end
end

---------------------------------------------------------------------------
-- LAYOUT MODE PREVIEW
---------------------------------------------------------------------------
-- Forward declarations (defined after preview section)
local UpdateBuffIcons
local UpdateDebuffIcons
local Init

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

local previewBuffIcons = {}
local previewDebuffIcons = {}
local previewBuffOverlay = nil
local previewDebuffOverlay = nil

local function GetPreviewCount(settings, prefix)
    local perRow = settings[prefix .. "IconsPerRow"] or 0
    if perRow <= 0 then perRow = 10 end
    return math.max(3, math.min(perRow + math.ceil(perRow / 2), 20))
end

-- Create a grid of preview icons on a given parent frame.
-- Returns the icon table. Sets parent._naturalW/_naturalH.
local function CreatePreviewGrid(parent, textures, debuffTypes, settings, prefix, isBuff)
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

    local anchor
    if growUp then
        anchor = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        anchor = growLeft and "TOPRIGHT" or "TOPLEFT"
    end

    local count = GetPreviewCount(settings, prefix)
    local icons = {}

    for i = 1, count do
        local icon = CreateFrame("Frame", nil, parent)
        icon:SetSize(iconSize, iconSize)

        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(BASE_CROP, 1 - BASE_CROP, BASE_CROP, 1 - BASE_CROP)
        tex:SetTexture(textures[((i - 1) % #textures) + 1])
        icon.Icon = tex

        icon.BorderTop = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        icon.BorderBottom = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        icon.BorderLeft = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        icon.BorderRight = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        icon.BorderTop:SetPoint("TOPLEFT") icon.BorderTop:SetPoint("TOPRIGHT")
        icon.BorderBottom:SetPoint("BOTTOMLEFT") icon.BorderBottom:SetPoint("BOTTOMRIGHT")
        icon.BorderLeft:SetPoint("TOPLEFT") icon.BorderLeft:SetPoint("BOTTOMLEFT")
        icon.BorderRight:SetPoint("TOPRIGHT") icon.BorderRight:SetPoint("BOTTOMRIGHT")

        icon.Stacks = icon:CreateFontString(nil, "OVERLAY")
        icon.Stacks:SetFont(GetGeneralFont(), 10, GetGeneralFontOutline())
        icon.Stacks:SetPoint("BOTTOMRIGHT", -1, 1)
        icon.Stacks:SetText("")
        icon.Stacks:Hide()

        icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        icon.Cooldown:SetAllPoints()
        icon.Cooldown:Clear()
        icon.TextOverlay = CreateFrame("Frame", nil, icon)
        icon.TextOverlay:SetAllPoints()

        local debuffType = debuffTypes and debuffTypes[((i - 1) % #debuffTypes) + 1]
        StyleIcon(icon, settings, isBuff, debuffType)

        local idx = i - 1
        local col = idx % iconsPerRow
        local row = math.floor(idx / iconsPerRow)
        local colStep = iconSize + spacing
        local rowStep = iconSize + rowSpacing
        local xOff = growLeft and -(col * colStep) or (col * colStep)
        local yOff = growUp and (row * rowStep) or -(row * rowStep)
        icon:SetPoint(anchor, parent, anchor, xOff, yOff)
        icon:Show()

        icons[#icons + 1] = icon
    end

    local numCols = math.min(count, iconsPerRow)
    local numRows = math.ceil(count / iconsPerRow)
    local totalW = numCols * iconSize + math.max(0, numCols - 1) * spacing
    local totalH = numRows * iconSize + math.max(0, numRows - 1) * rowSpacing
    parent:SetSize(totalW, totalH)
    parent._naturalW = totalW
    parent._naturalH = totalH

    return icons
end

local function ShowPreview()
    if previewActive then return end
    previewActive = true

    local settings = GetSettings()
    if not settings then return end

    -- Ensure containers are shown so the layout mode reparenting code
    -- (which checks IsShown()) can attach them to the proxy mover.
    -- Out of combat, so Show() is safe on SecureAuraHeaders.
    if not buffContainer:IsShown() then buffContainer:Show() end
    if not debuffContainer:IsShown() then debuffContainer:Show() end

    -- Hide real header children (layout mode = out of combat, so alpha works)
    buffContainer:SetAlpha(0)
    debuffContainer:SetAlpha(0)

    -- Create overlay frames parented to the HEADERS (not UIParent) so they
    -- inherit the header's position from the mover/anchoring system. The
    -- overlay is a regular Frame whose size we control — the mover reads
    -- the header's _naturalW/_naturalH which we set from the overlay grid.
    if not previewBuffOverlay then
        previewBuffOverlay = CreateFrame("Frame", nil, buffContainer)
    end
    previewBuffOverlay:SetAllPoints(buffContainer)
    previewBuffOverlay:SetIgnoreParentAlpha(true)
    previewBuffOverlay:SetFrameStrata("HIGH")
    previewBuffOverlay:Show()

    if not previewDebuffOverlay then
        previewDebuffOverlay = CreateFrame("Frame", nil, debuffContainer)
    end
    previewDebuffOverlay:SetAllPoints(debuffContainer)
    previewDebuffOverlay:SetIgnoreParentAlpha(true)
    previewDebuffOverlay:SetFrameStrata("HIGH")
    previewDebuffOverlay:Show()

    previewBuffIcons = CreatePreviewGrid(previewBuffOverlay, PREVIEW_BUFF_TEXTURES, nil, settings, "buff", true)
    previewDebuffIcons = CreatePreviewGrid(previewDebuffOverlay, PREVIEW_DEBUFF_TEXTURES, PREVIEW_DEBUFF_TYPES, settings, "debuff", false)

    -- Copy computed grid size to the header's _naturalW/_naturalH so the
    -- layout mode handle system picks up the preview dimensions.
    -- Also SetSize on the containers so the overlay (SetAllPoints) has
    -- real bounds — SecureAuraHeaders auto-size from children, but the
    -- real children are hidden during preview.
    buffContainer._naturalW = previewBuffOverlay._naturalW
    buffContainer._naturalH = previewBuffOverlay._naturalH
    buffContainer:SetSize(previewBuffOverlay._naturalW, previewBuffOverlay._naturalH)
    debuffContainer._naturalW = previewDebuffOverlay._naturalW
    debuffContainer._naturalH = previewDebuffOverlay._naturalH
    debuffContainer:SetSize(previewDebuffOverlay._naturalW, previewDebuffOverlay._naturalH)

    -- Sync layout handles to match preview size
    if _G.QUI_LayoutModeSyncHandle then
        _G.QUI_LayoutModeSyncHandle("buffFrame")
        _G.QUI_LayoutModeSyncHandle("debuffFrame")
    end

    -- Hide private aura slots during preview
    for _, slot in ipairs(paSlots) do slot:Hide() end
end

local function HidePreview()
    if not previewActive then return end
    previewActive = false

    -- Clean up preview icons
    for _, icon in ipairs(previewBuffIcons) do icon:Hide() end
    wipe(previewBuffIcons)
    for _, icon in ipairs(previewDebuffIcons) do icon:Hide() end
    wipe(previewDebuffIcons)

    if previewBuffOverlay then previewBuffOverlay:Hide() end
    if previewDebuffOverlay then previewDebuffOverlay:Hide() end

    -- Restore header visibility
    buffContainer:SetAlpha(1)
    debuffContainer:SetAlpha(1)

    -- Resume real display
    UpdateBuffIcons()
    UpdateDebuffIcons()
end

---------------------------------------------------------------------------
-- AURA UPDATE WRAPPERS
---------------------------------------------------------------------------
UpdateBuffIcons = function()
    if not buffContainer then return end
    local settings = GetSettings()
    if not settings then return end
    if previewActive then return end
    if not settings.enableBuffs or settings.hideBuffFrame then
        buffContainer:SetAlpha(0)
        return
    end
    buffContainer:SetAlpha(1)
    if buffBorderStats then buffBorderStats.buffUpdates = buffBorderStats.buffUpdates + 1 end
    StyleHeaderChildren(buffContainer, settings, true)
end

-- Rate-limited private aura anchor re-registration to clean up stale renders.
-- WoW's AddPrivateAuraAnchor rendering can persist after the aura expires;
-- re-registering forces the client to re-evaluate active private auras.
local paLastRefresh = 0
local PA_REFRESH_CD = 1.0

local function RefreshPrivateAuraAnchors()
    if not AddPrivateAuraAnchor or not debuffContainer then return end
    local now = GetTime()
    if now - paLastRefresh < PA_REFRESH_CD then return end
    paLastRefresh = now
    ClearPrivateAuraAnchors()
    SetupPrivateAuras()
end

UpdateDebuffIcons = function()
    if not debuffContainer then return end
    local settings = GetSettings()
    if not settings then return end
    if previewActive then return end
    if not settings.enableDebuffs or settings.hideDebuffFrame then
        debuffContainer:SetAlpha(0)
        return
    end
    debuffContainer:SetAlpha(1)
    if buffBorderStats then buffBorderStats.debuffUpdates = buffBorderStats.debuffUpdates + 1 end
    StyleHeaderChildren(debuffContainer, settings, false)
    RefreshPrivateAuraAnchors()
    LayoutPrivateAuraSlots()
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
    if not buffContainer or not debuffContainer then return end
    if InCombatLockdown() and not ns._inInitSafeWindow then return end

    ManageBlizzardFrames()

    -- Sync growAnchor from the user's grow direction settings. This catches
    -- any toggle of the Grow Left / Grow Up checkboxes in the layout mode
    -- settings panel — Refresh fires after the checkbox writes to bbDB.
    UpdateGrowAnchor("buffFrame")
    UpdateGrowAnchor("debuffFrame")

    -- Sync layout attributes from settings
    local settings = GetSettings()
    if settings and (not InCombatLockdown() or ns._inInitSafeWindow) then
        SyncHeaderAttributes(buffContainer, settings, "buff")
        SyncHeaderAttributes(debuffContainer, settings, "debuff")
        -- Keep secure headers alive in normal gameplay. Layout mode preview
        -- already does this explicitly; without it, first login/reload can
        -- leave the headers hidden until layout mode is toggled once.
        if settings.enableBuffs and not settings.hideBuffFrame and not buffContainer:IsShown() then
            buffContainer:Show()
        end
        if settings.enableDebuffs and not settings.hideDebuffFrame and not debuffContainer:IsShown() then
            debuffContainer:Show()
        end
    end

    if previewActive then
        -- Re-style preview icons with new settings
        HidePreview()
        ShowPreview()
        return
    end

    -- Re-setup private aura anchors with current settings
    SetupPrivateAuras()

    -- Reset cached enchant durations
    wipe(enchantCachedDuration)

    UpdateBuffIcons()
    UpdateDebuffIcons()
end

-- Secure aura headers can populate a little after Init() finishes on
-- /reload. If the first Update*Icons pass lands before real children exist,
-- the container stays at its 1x1 bootstrap size until something else
-- (layout mode, a new aura event) forces another pass. Use a couple of
-- out-of-combat retries so the headers settle into their real anchored size.
local function TryDeferredFullRefresh()
    if previewActive then return end
    if not initialized then
        Init()
        return
    end
    if not buffContainer or not debuffContainer then return end
    if InCombatLockdown() and not ns._inInitSafeWindow then return end
    FullRefresh()
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
Init = function()
    if initialized then return true end
    if InCombatLockdown() and not ns._inInitSafeWindow then return false end

    initialized = true

    -- Create secure aura headers
    buffContainer = CreateHeader("QUI_BuffIconContainer", "HELPFUL")
    debuffContainer = CreateHeader("QUI_DebuffIconContainer", "HARMFUL")

    -- Apply settings-driven layout attributes
    local settings = GetSettings()
    if settings then
        SyncHeaderAttributes(buffContainer, settings, "buff")
        SyncHeaderAttributes(debuffContainer, settings, "debuff")
        -- Secure aura headers are visible by default after CreateFrame. Do NOT
        -- call :Show() here — on /reload during combat, an addon-initiated
        -- Show() runs SecureAuraHeader_Update in the tainted stack, which
        -- compares the secret `expires` field and poisons the secure env.
        -- Blizzard's own OnShow/OnUpdate path handles initial rendering safely
        -- during the addon-load window.
    end

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
    local applyAnchor = _G.QUI_ApplyFrameAnchor
    if applyAnchor then
        applyAnchor("buffFrame")
        applyAnchor("debuffFrame")
    end

    -- Manage Blizzard frames
    ManageBlizzardFrames()

    -- Setup private aura display for player
    SetupPrivateAuras()

    -- Keep secure headers alive and drive runtime visibility with alpha.
    -- Addon-driven Show()/Hide() on SecureAuraHeaderTemplate can taint
    -- Blizzard's restricted aura sort path when it compares secret values.
    buffContainer:SetAlpha((settings and settings.enableBuffs and not settings.hideBuffFrame) and 1 or 0)
    debuffContainer:SetAlpha((settings and settings.enableDebuffs and not settings.hideDebuffFrame) and 1 or 0)

    -- Hook the header's OnEvent to coalesce child styling when auras change.
    buffContainer:HookScript("OnEvent", function()
        if previewActive then return end
        local s = GetSettings()
        if not s or not s.enableBuffs or s.hideBuffFrame then return end
        if buffBorderStats then buffBorderStats.headerAuraEvents = buffBorderStats.headerAuraEvents + 1 end
        if ns.AuraEvents then return end
        ScheduleBuffUpdate()
    end)
    buffContainer:RegisterUnitEvent("UNIT_AURA", "player")

    debuffContainer:HookScript("OnEvent", function()
        if previewActive then return end
        local s = GetSettings()
        if not s or not s.enableDebuffs or s.hideDebuffFrame then return end
        if buffBorderStats then buffBorderStats.headerAuraEvents = buffBorderStats.headerAuraEvents + 1 end
        if ns.AuraEvents then return end
        ScheduleDebuffUpdate()
    end)
    debuffContainer:RegisterUnitEvent("UNIT_AURA", "player")

    -- Style children after a short delay to let the header populate
    C_Timer.After(0.1, function()
        UpdateBuffIcons()
        UpdateDebuffIcons()
    end)

    C_Timer.After(0.5, TryDeferredFullRefresh)
    C_Timer.After(2.0, TryDeferredFullRefresh)
    return true
end

---------------------------------------------------------------------------
-- EVENT HANDLING: Subscribe to centralized aura dispatcher (player only)
---------------------------------------------------------------------------
if ns.AuraEvents then
    ns.AuraEvents:Subscribe("player", function(unit, updateInfo)
        if buffBorderStats then buffBorderStats.busAuraEvents = buffBorderStats.busAuraEvents + 1 end
        if RefreshPureAuraUpdate(updateInfo) then return end
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

-- Combat-end handler: re-sync secure header attributes (SetAttribute on
-- SecureAuraHeaderTemplate is protected in combat) and force a restyle.
local paRegenFrame = CreateFrame("Frame")
paRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
paRegenFrame:SetScript("OnEvent", function()
    TryDeferredFullRefresh()
end)

-- SetupDebugInstrumentation is defined here so all the frames and tables it references
-- are already declared above. buffBorderStats itself is declared up near the aura child maps.
local function SetupDebugInstrumentation()
    buffBorderStats = {
        unitAuraScans = 0,
        fastAuraUpdates = 0,
        buffUpdates = 0,
        debuffUpdates = 0,
        headerAuraEvents = 0,
        busAuraEvents = 0,
        auraChildMapWrites = 0,
        auraChildMapClears = 0,
    }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "BB_enchantCache", tbl = enchantCachedDuration }
    mp[#mp + 1] = { name = "BB_unitAuraScans", counter = true, fn = function() return buffBorderStats.unitAuraScans end }
    mp[#mp + 1] = { name = "BB_fastAuraUpdates", counter = true, fn = function() return buffBorderStats.fastAuraUpdates end }
    mp[#mp + 1] = { name = "BB_buffUpdates", counter = true, fn = function() return buffBorderStats.buffUpdates end }
    mp[#mp + 1] = { name = "BB_debuffUpdates", counter = true, fn = function() return buffBorderStats.debuffUpdates end }
    mp[#mp + 1] = { name = "BB_headerAuraEvents", counter = true, fn = function() return buffBorderStats.headerAuraEvents end }
    mp[#mp + 1] = { name = "BB_busAuraEvents", counter = true, fn = function() return buffBorderStats.busAuraEvents end }
    mp[#mp + 1] = { name = "BB_auraChildMapWrites", counter = true, fn = function() return buffBorderStats.auraChildMapWrites end }
    mp[#mp + 1] = { name = "BB_auraChildMapClears", counter = true, fn = function() return buffBorderStats.auraChildMapClears end }
    mp[#mp + 1] = { name = "BB_buffAuraChildrenByID", tbl = buffAuraChildrenByID }
    mp[#mp + 1] = { name = "BB_debuffAuraChildrenByID", tbl = debuffAuraChildrenByID }
    local reg = ns.QUI_PerfRegistry or {}; ns.QUI_PerfRegistry = reg
    reg[#reg + 1] = { name = "BuffBorders_CombatEnd",     frame = paRegenFrame }
    reg[#reg + 1] = { name = "BuffBorders_BuffCoalesce",  frame = buffCoalesceFrame,   scriptType = "OnUpdate" }
    reg[#reg + 1] = { name = "BuffBorders_DebuffCoalesce",frame = debuffCoalesceFrame, scriptType = "OnUpdate" }
    reg[#reg + 1] = { name = "BuffBorders_EnchantEvent",  frame = enchantEventFrame }
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

-- Primary initialization is called from core/main.lua during the ADDON_LOADED
-- safe window. Keep this retry for unusual load orders and for combat-end
-- recovery if the safe-window call was missed.
C_Timer.After(1, TryDeferredFullRefresh)

---------------------------------------------------------------------------
-- EXPORTS
---------------------------------------------------------------------------
local function RefreshBuffBorders()
    if not initialized and not Init() then return end
    FullRefresh()
end

QUI.BuffBorders = {
    Init = Init,
    Apply = RefreshBuffBorders,
    ShowPreview = ShowPreview,
    HidePreview = HidePreview,
}

-- Global function for config panel / layout mode to call
_G.QUI_RefreshBuffBorders = RefreshBuffBorders

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
