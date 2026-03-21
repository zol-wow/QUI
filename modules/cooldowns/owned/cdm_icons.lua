--[[
    QUI CDM Icon Factory

    Creates and manages addon-owned icon frames for the CDM system.
    All icons are simple Frame objects (not Buttons) with no protected
    attributes, eliminating all combat taint concerns for frame operations.

    Absorbs cdm_custom.lua functionality — custom entries use the same
    icon pool as harvested entries.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local LSM = ns.LSM

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMIcons = {}
ns.CDMIcons = CDMIcons

-- CustomCDM exposed on CDMIcons for engine access (provider wires to ns.CustomCDM)
local CustomCDM = {}
CDMIcons.CustomCDM = CustomCDM

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local IsSecretValue = Helpers.IsSecretValue
local SafeToNumber = Helpers.SafeToNumber
local SafeValue = Helpers.SafeValue

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local CreateFrame = CreateFrame
local GetTime = GetTime

local function IsSafeNumeric(val)
    if IsSecretValue(val) then return false end
    return type(val) == "number"
end

-- Per-spell override lookup helper.  Returns the cached override table
-- for the icon's spell/container, or nil.  Cheap (two table lookups).
local function GetIconSpellOverride(icon)
    local entry = icon and icon._spellEntry
    if not entry then return nil end
    local CDMSpellData = ns.CDMSpellData
    if not CDMSpellData then return nil end
    local spellID = entry.spellID or entry.id
    local containerKey = entry.viewerType
    if not spellID or not containerKey then return nil end
    return CDMSpellData:GetSpellOverride(containerKey, spellID)
end

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local MAX_RECYCLE_POOL_SIZE = 20
local DEFAULT_ICON_SIZE = 39
local BASE_CROP = 0.08

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local iconPools = {
    essential = {},
    utility   = {},
    buff      = {},
}
-- Phase G: Pools for custom containers are created dynamically via EnsurePool().
local recyclePool = {}
local iconCounter = 0
local updateTicker = nil

-- Forward declarations (defined in AURA LOOKUP / CACHE sections below)
local LookupAura
local _spellToAuraInstance = {}  -- [spellId] = auraInstanceID (for GetAuraDuration)

---------------------------------------------------------------------------
-- DYNAMIC CHILD LOOKUP: Scan ALL viewer children to find the one with
-- auraInstanceID matching a tracked spell.  Blizzard recycles children
-- across auras, so the child→spell assignment changes at runtime.
-- This runs per-icon per-tick but is cheap (~20-30 children total).
---------------------------------------------------------------------------
local VIEWER_FRAMES = {}  -- populated lazily
local function EnsureViewerFrames()
    if #VIEWER_FRAMES > 0 then return end
    for _, name in ipairs({
        "EssentialCooldownViewer", "UtilityCooldownViewer",
        "BuffIconCooldownViewer", "BuffBarCooldownViewer"
    }) do
        local vf = _G[name]
        if vf then VIEWER_FRAMES[#VIEWER_FRAMES+1] = vf end
    end
end

--- Find ANY viewer child whose spell identity matches one of the given IDs
--- AND has a non-nil auraInstanceID (i.e., is currently showing an active aura).
--- Returns the child frame or nil.
local function FindActiveAuraChild(id1, id2, id3)
    EnsureViewerFrames()
    for _, viewer in ipairs(VIEWER_FRAMES) do
        local ok, children = pcall(function() return { viewer:GetChildren() } end)
        if ok and children then
            for _, ch in ipairs(children) do
                -- Only consider shown children — Blizzard hides children
                -- C-side when buffs drop but doesn't nil auraInstanceID.
                local sok, shown = pcall(ch.IsShown, ch)
                if ch and ch.auraInstanceID and sok and shown then
                    -- Match by cooldownInfo IDs
                    local ci = ch.cooldownInfo
                    if ci then
                        local sid = ci.spellID
                        local ov = ci.overrideSpellID
                        local safeSid = sid and SafeValue(sid, nil)
                        local safeOv = ov and SafeValue(ov, nil)
                        if (safeSid and (safeSid == id1 or safeSid == id2 or safeSid == id3))
                            or (safeOv and (safeOv == id1 or safeOv == id2 or safeOv == id3)) then
                            return ch
                        end
                    end
                    -- Match by cooldownID
                    local cdID = ch.cooldownID
                    if cdID and (cdID == id1 or cdID == id2 or cdID == id3) then
                        return ch
                    end
                    -- Match by frame methods (GetAuraSpellID, GetSpellID)
                    if ch.GetAuraSpellID then
                        local aok, auraSid = pcall(ch.GetAuraSpellID, ch)
                        local safeAura = aok and auraSid and SafeValue(auraSid, nil)
                        if safeAura and (safeAura == id1 or safeAura == id2 or safeAura == id3) then
                            return ch
                        end
                    end
                    if ch.GetSpellID then
                        local sok, fid = pcall(ch.GetSpellID, ch)
                        local safeFid = sok and fid and SafeValue(fid, nil)
                        if safeFid and (safeFid == id1 or safeFid == id2 or safeFid == id3) then
                            return ch
                        end
                    end
                    -- Match by linkedSpellIDs from cooldown info (ability→debuff mapping)
                    local cdID = ch.cooldownID
                    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                        if iok and info and info.linkedSpellIDs then
                            for _, lsid in ipairs(info.linkedSpellIDs) do
                                local safeLsid = SafeValue(lsid, nil)
                                if safeLsid and (safeLsid == id1 or safeLsid == id2 or safeLsid == id3) then
                                    return ch
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetCustomData(trackerKey)
    if Helpers and Helpers.GetNCDMCustomEntries then
        return Helpers.GetNCDMCustomEntries(trackerKey)
    end

    if QUICore and QUICore.db and QUICore.db.char and QUICore.db.char.ncdm
        and QUICore.db.char.ncdm[trackerKey] and QUICore.db.char.ncdm[trackerKey].customEntries then
        return QUICore.db.char.ncdm[trackerKey].customEntries
    end
    return nil
end

---------------------------------------------------------------------------
-- TEXTURE HELPERS
---------------------------------------------------------------------------
local function GetSpellTexture(spellID)
    if not spellID then return nil end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.iconID or nil
end

---------------------------------------------------------------------------
-- MACRO RESOLUTION
-- Resolve a macro custom entry to its current spell or item via
-- #showtooltip / GetMacroSpell / GetMacroItem.  Re-evaluated every tick
-- so the icon tracks conditional changes (target, modifiers, stance).
---------------------------------------------------------------------------
local function ResolveMacro(entry)
    local macroName = entry.macroName
    if not macroName then return nil, nil, nil end
    local macroIndex = GetMacroIndexByName(macroName)
    if not macroIndex or macroIndex == 0 then return nil, nil, nil end

    -- GetMacroSpell returns the spellID that #showtooltip resolves to
    local spellID = GetMacroSpell(macroIndex)
    if spellID then
        return spellID, "spell", nil
    end

    -- GetMacroItem returns itemName, itemLink for /use macros
    local itemName, itemLink = GetMacroItem(macroIndex)
    if itemLink then
        local itemID = C_Item.GetItemInfoInstant(itemLink)
        if itemID then
            return itemID, "item", nil
        end
    end

    -- Fallback: macro's own icon (no resolvable cooldown)
    local _, _, macroIcon = GetMacroInfo(macroIndex)
    return nil, nil, macroIcon
end

local function GetEntryTexture(entry)
    if not entry then return nil end
    if entry.type == "macro" then
        local resolvedID, resolvedType, fallbackTex = ResolveMacro(entry)
        if resolvedID then
            if resolvedType == "item" then
                local _, _, _, _, icon = C_Item.GetItemInfoInstant(resolvedID)
                return icon
            else
                return GetSpellTexture(resolvedID)
            end
        end
        return fallbackTex
    end
    if entry.type == "trinket" then
        -- Trinket entries store the equipment slot number (13/14), not the item ID.
        -- Resolve to the actual equipped item ID before looking up the icon.
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
            return icon
        end
        return nil
    end
    if entry.type == "item" then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(entry.id)
        return icon
    end
    return GetSpellTexture(entry.id)
end

---------------------------------------------------------------------------
-- COOLDOWN RESOLUTION
-- Ported from cdm_custom.lua:116-181 (GetBestSpellCooldown)
---------------------------------------------------------------------------
local function GetBestSpellCooldown(spellID)
    if not spellID then return nil, nil end

    local candidates = { spellID }

    -- Add override spell if present
    if C_Spell.GetOverrideSpell then
        local overrideID = C_Spell.GetOverrideSpell(spellID)
        if overrideID and overrideID ~= spellID then
            candidates[#candidates + 1] = overrideID
        end
    end

    local bestStart, bestDuration = nil, nil
    local secretStart, secretDuration = nil, nil

    local function Consider(startTime, duration)
        if IsSecretValue(startTime) or IsSecretValue(duration) then
            if not secretStart and not secretDuration then
                secretStart, secretDuration = startTime, duration
            end
            return
        end

        if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) or duration <= 0 then
            return
        end

        if not bestDuration or duration > bestDuration then
            bestStart, bestDuration = startTime, duration
        end
    end

    for _, identifier in ipairs(candidates) do
        local cdInfo = C_Spell.GetSpellCooldown(identifier)
        if cdInfo then
            Consider(cdInfo.startTime, cdInfo.duration)
        end

        -- Check charges
        if C_Spell.GetSpellCharges then
            local chargeInfo = C_Spell.GetSpellCharges(identifier)
            if chargeInfo then
                local currentCharges = SafeToNumber(chargeInfo.currentCharges, 0)
                local maxCharges = SafeToNumber(chargeInfo.maxCharges, 0)
                if currentCharges < maxCharges then
                    Consider(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration)
                end
            end
        end
    end

    -- Return secret fallback if no safe value found
    if not bestStart and secretStart then
        return secretStart, secretDuration
    end
    return bestStart, bestDuration
end

-- Item cooldown resolution
local function GetItemCooldown(itemID)
    if not itemID or not C_Item.GetItemCooldown then return nil, nil end
    local startTime, duration = C_Item.GetItemCooldown(itemID)
    if IsSecretValue(startTime) or IsSecretValue(duration) then
        return startTime, duration -- CooldownFrame can handle secret values
    end
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) or duration <= 0 then
        return nil, nil
    end
    return startTime, duration
end

-- Expose for external use
CDMIcons.GetBestSpellCooldown = GetBestSpellCooldown

---------------------------------------------------------------------------
-- SWIPE STYLING
---------------------------------------------------------------------------

-- Re-apply QUI swipe styling to the addon-owned CooldownFrame.
local function ReapplySwipeStyle(cd, icon)
    if not cd then return end
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    local CooldownSwipe = QUI.CooldownSwipe
    if CooldownSwipe and CooldownSwipe.ApplyToIcon then
        CooldownSwipe.ApplyToIcon(icon)
    end
end

-- Keep CooldownFrame ready-flash ("bling") hidden when icon is effectively invisible.
-- This prevents GCD-ready glow from leaking through when row/container alpha is 0.
local function SyncCooldownBling(icon)
    if not icon or not icon.Cooldown or not icon.Cooldown.SetDrawBling then return end
    local effectiveAlpha = (icon.GetEffectiveAlpha and icon:GetEffectiveAlpha()) or icon:GetAlpha() or 1
    local shouldDrawBling = (effectiveAlpha > 0.001) and icon:IsShown()
    if icon._drawBlingEnabled ~= shouldDrawBling then
        icon._drawBlingEnabled = shouldDrawBling
        icon.Cooldown:SetDrawBling(shouldDrawBling)
    end
end


---------------------------------------------------------------------------
-- ICON CREATION
-- Frame structure: Frame parent with .Icon, .Cooldown, .Border,
-- .DurationText, .StackText children.
---------------------------------------------------------------------------
local function CreateIcon(parent, spellEntry)
    iconCounter = iconCounter + 1
    local frameName = "QUICDMIcon" .. iconCounter

    local icon = CreateFrame("Frame", frameName, parent)
    local size = DEFAULT_ICON_SIZE
    icon:SetSize(size, size)

    -- .Icon texture (ARTWORK layer)
    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetAllPoints(icon)

    -- .Cooldown frame (CooldownFrameTemplate for swipe/countdown)
    icon.Cooldown = CreateFrame("Cooldown", frameName .. "Cooldown", icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints(icon)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)
    icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    icon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    icon.Cooldown:SetDrawBling(true)

    -- .TextOverlay (sits above the CooldownFrame so text is never behind the swipe)
    icon.TextOverlay = CreateFrame("Frame", nil, icon)
    icon.TextOverlay:SetAllPoints(icon)
    icon.TextOverlay:SetFrameLevel(icon.Cooldown:GetFrameLevel() + 2)

    -- .TextOverlay (sits above the CooldownFrame so text is never behind the swipe)
    icon.TextOverlay = CreateFrame("Frame", nil, icon)
    icon.TextOverlay:SetAllPoints(icon)
    icon.TextOverlay:SetFrameLevel(icon.Cooldown:GetFrameLevel() + 2)

    -- .Border texture (BACKGROUND, sublayer -8, pre-created)
    icon.Border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    icon.Border:Hide()

    -- .DurationText (OVERLAY, sublayer 7 — parented to TextOverlay, above swipe)
    icon.DurationText = icon.TextOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.DurationText:SetPoint("CENTER")

    -- .StackText (OVERLAY, sublayer 7 — parented to TextOverlay, above swipe)
    icon.StackText = icon.TextOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.StackText:SetPoint("BOTTOMRIGHT")

    -- Set a default font so SetText() never fires before ConfigureIcon styles them
    local defaultFont = GetGeneralFont()
    local defaultOutline = GetGeneralFontOutline()
    icon.DurationText:SetFont(defaultFont, 10, defaultOutline)
    icon.StackText:SetFont(defaultFont, 10, defaultOutline)

    -- Metadata
    icon._spellEntry = spellEntry
    icon._isQUICDMIcon = true

    -- Set texture
    if spellEntry then
        local texID
        if spellEntry.type then
            texID = GetEntryTexture(spellEntry)
        else
            texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
        end
        if texID then
            icon.Icon:SetTexture(texID)
        end
    end

    -- Tooltip support
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
        local entry = self._spellEntry
        if not entry then return end
        local tooltipProvider = ns.TooltipProvider
        if tooltipProvider and tooltipProvider.ShouldShowTooltip then
            if not tooltipProvider:ShouldShowTooltip("cdm") then
                pcall(GameTooltip.Hide, GameTooltip)
                return
            end
        end
        local tooltipSettings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.tooltip
        if tooltipSettings and tooltipSettings.anchorToCursor then
            local anchorTooltip = ns.QUI_AnchorTooltipToCursor
            if anchorTooltip then
                anchorTooltip(GameTooltip, self, tooltipSettings)
            else
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            end
        else
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        end
        local sid = entry.overrideSpellID or entry.spellID or (entry.type and entry.id)
        if sid then
            if entry.type == "trinket" then
                -- Trinket entries store slot number; resolve to item ID for tooltip
                local itemID = GetInventoryItemID("player", sid)
                if itemID then
                    pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
                end
            elseif entry.type == "item" then
                pcall(GameTooltip.SetItemByID, GameTooltip, sid)
            else
                pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
            end
        end
        pcall(GameTooltip.Show, GameTooltip)
    end)
    icon:SetScript("OnLeave", function()
        pcall(GameTooltip.Hide, GameTooltip)
    end)

    icon:Show()
    return icon
end

---------------------------------------------------------------------------
-- CLICK-TO-CAST: Secure overlay button for CDM icons
-- Creates a SecureActionButtonTemplate child that receives clicks and
-- forwards them to the WoW secure action system.  The parent icon
-- stays as a plain Frame so layout/pooling remain taint-free.
---------------------------------------------------------------------------
local function SyncClickButtonFrameLevel(icon)
    if not icon or not icon.clickButton or not icon.TextOverlay then return end
    local requiredLevel = icon.TextOverlay:GetFrameLevel() + 2
    if icon.clickButton:GetFrameLevel() ~= requiredLevel then
        icon.clickButton:SetFrameLevel(requiredLevel)
    end
end

-- Keep text above cooldown (baseline) and optionally above another frame level.
-- Also keeps clickButton above text if one exists.
function CDMIcons:EnsureTextOverlayLevel(icon, minLevel)
    if not icon or not icon.TextOverlay then return end

    local requiredLevel = minLevel
    if icon.Cooldown and icon.Cooldown.GetFrameLevel then
        local baselineLevel = icon.Cooldown:GetFrameLevel() + 2
        if not requiredLevel or requiredLevel < baselineLevel then
            requiredLevel = baselineLevel
        end
    end

    if requiredLevel and icon.TextOverlay:GetFrameLevel() < requiredLevel then
        icon.TextOverlay:SetFrameLevel(requiredLevel)
    end

    SyncClickButtonFrameLevel(icon)
end

local function EnsureClickButton(icon)
    if icon.clickButton then
        CDMIcons:EnsureTextOverlayLevel(icon)
        return icon.clickButton
    end

    local btn = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
    btn:SetAllPoints()
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:EnableMouse(true)
    btn:Hide()

    -- Forward tooltip events to the parent icon's handler
    btn:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        if parent then
            local onEnter = parent:GetScript("OnEnter")
            if onEnter then onEnter(parent) end
        end
    end)
    btn:SetScript("OnLeave", function()
        pcall(GameTooltip.Hide, GameTooltip)
    end)

    icon.clickButton = btn
    CDMIcons:EnsureTextOverlayLevel(icon)
    return btn
end

local function ClearClickButtonAttributes(btn)
    btn:SetAttribute("type", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("item", nil)
    btn:SetAttribute("macro", nil)
end

---------------------------------------------------------------------------
-- MACRO RESOLUTION
-- Scan all player macros for one that casts the given spell.
-- If found, clicking the CDM icon will execute through the macro,
-- preserving all conditionals (@mouseover, /cancelaura, modifiers, etc.).
--
-- Scans macro indices directly (1-120 account, 121-138 character) instead
-- of action bar slots, because GetActionInfo returns bogus "macro" entries
-- with spell IDs instead of real macro indices in WoW 12.0+.
--
-- Match priority (highest → lowest):
--   1. GetMacroSpell — WoW resolved the macro's tooltip to our spell
--   2. #showtooltip / #show line names our spell — the macro's declared identity
--   3. /cast or /use line names our spell — broadest fallback
-- Multi-spell macros (e.g. Lichborne + Death Coil) only match via their
-- tooltip identity, not via a /cast line for a secondary spell.
---------------------------------------------------------------------------
local MAX_ACCOUNT_MACROS = 120
local MAX_CHARACTER_MACROS = 18

-- Extract the spell name from #showtooltip or #show lines.
-- Returns lowercase name or nil.  Handles:
--   #showtooltip              → nil (bare, no explicit spell)
--   #showtooltip Spell Name   → "spell name"
--   #show Spell Name          → "spell name"
local function GetMacroTooltipSpell(body)
    if not body then return nil end
    local name = body:match("^#showtooltip%s+(.+)") or body:match("\n#showtooltip%s+(.+)")
    if not name then
        name = body:match("^#show%s+(.+)") or body:match("\n#show%s+(.+)")
    end
    if name then
        name = name:match("^(.-)%s*$")
        if name and name ~= "" then return name:lower() end
    end
    return nil
end

local function FindMacroForSpell(spellID, overrideSpellID)
    if not spellID and not overrideSpellID then return nil end

    -- Build lowercase spell name set for matching
    local names = {}
    if spellID and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then names[info.name:lower()] = true end
    end
    if overrideSpellID and overrideSpellID ~= spellID and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(overrideSpellID)
        if info and info.name then names[info.name:lower()] = true end
    end
    if not next(names) then return nil end

    -- Pass 1: GetMacroSpell (WoW-resolved tooltip spell ID)
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local macroName = GetMacroInfo(i)
        if macroName then
            local macroSpell = GetMacroSpell(i)
            if macroSpell and (macroSpell == spellID or macroSpell == overrideSpellID) then
                return macroName
            end
        end
    end

    -- Pass 2: #showtooltip / #show declares the macro's identity spell
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local macroName = GetMacroInfo(i)
        if macroName then
            local tooltipSpell = GetMacroTooltipSpell(GetMacroBody(i))
            if tooltipSpell and names[tooltipSpell] then
                return macroName
            end
        end
    end

    -- Pass 3: /cast or /use line mentions our spell (broadest, skips
    -- multi-spell macros whose tooltip identity is a different spell)
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local macroName = GetMacroInfo(i)
        if macroName then
            local body = GetMacroBody(i)
            if body then
                local tooltipSpell = GetMacroTooltipSpell(body)
                if tooltipSpell and not names[tooltipSpell] then
                    -- Tooltip declares a different spell — skip
                else
                    local lowerBody = body:lower()
                    for name in pairs(names) do
                        if lowerBody:find(name, 1, true) then
                            return macroName
                        end
                    end
                end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- SECURE ATTRIBUTE MANAGEMENT
-- Sets or clears the click-to-cast secure button attributes on a CDM icon.
---------------------------------------------------------------------------
local function UpdateIconSecureAttributes(icon, entry, viewerType)
    if not icon then return end

    -- Can't modify secure attributes during combat
    if InCombatLockdown() then
        icon._pendingSecureUpdate = true
        return
    end

    -- Never clickable for buff icons
    if viewerType == "buff" then
        if icon.clickButton then
            ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
        return
    end

    local db = GetDB()
    local viewerDB = db and db[viewerType]

    -- Feature disabled or no config
    if not viewerDB or not viewerDB.clickableIcons then
        if icon.clickButton then
            ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
        return
    end

    -- No entry assigned
    if not entry then
        if icon.clickButton then
            ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
        return
    end

    local btn = EnsureClickButton(icon)

    -- Determine secure attributes based on entry type
    if entry.type == "macro" and entry.macroName then
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macro", entry.macroName)
        btn:Show()
    elseif entry.type == "trinket" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            local itemName = C_Item.GetItemNameByID(itemID)
            if itemName then
                btn:SetAttribute("type", "item")
                btn:SetAttribute("item", itemName)
                btn:Show()
            else
                ClearClickButtonAttributes(btn)
                btn:Hide()
            end
        else
            ClearClickButtonAttributes(btn)
            btn:Hide()
        end
    elseif entry.type == "item" then
        local itemName = C_Item.GetItemNameByID(entry.id)
        if itemName then
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item", itemName)
            btn:Show()
        else
            ClearClickButtonAttributes(btn)
            btn:Hide()
        end
    else
        -- Spell (harvested or custom spell type)
        -- Prefer player macro if one casts this spell, so clicking
        -- the CDM icon executes through the macro's conditionals.
        local spellID = entry.overrideSpellID or entry.spellID
        local macroName = FindMacroForSpell(entry.spellID, entry.overrideSpellID)
        if macroName then
            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macro", macroName)
            btn:Show()
        elseif spellID then
            local spellInfo = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                btn:SetAttribute("type", "spell")
                btn:SetAttribute("spell", spellInfo.name)
                btn:Show()
            else
                ClearClickButtonAttributes(btn)
                btn:Hide()
            end
        else
            ClearClickButtonAttributes(btn)
            btn:Hide()
        end
    end

    icon._pendingSecureUpdate = nil
end

---------------------------------------------------------------------------
-- ICON CONFIGURATION
-- Applies size, border, zoom, texcoord, text styling to an icon.
-- No combat guards needed — all addon-owned frames.
---------------------------------------------------------------------------
local function ApplyTexCoord(icon, zoom, aspectRatioCrop)
    if not icon then return end
    local z = zoom or 0
    local aspectRatio = aspectRatioCrop or 1.0

    local left = BASE_CROP + z
    local right = 1 - BASE_CROP - z
    local top = BASE_CROP + z
    local bottom = 1 - BASE_CROP - z

    -- Apply aspect ratio crop on top of existing crop
    if aspectRatio > 1.0 then
        local cropAmount = 1.0 - (1.0 / aspectRatio)
        local availableHeight = bottom - top
        local offset = (cropAmount * availableHeight) / 2.0
        top = top + offset
        bottom = bottom - offset
    end

    if icon.Icon and icon.Icon.SetTexCoord then
        icon.Icon:SetTexCoord(left, right, top, bottom)
    end
end

local function ConfigureIcon(icon, rowConfig)
    if not icon or not rowConfig then return end

    local size = rowConfig.size or DEFAULT_ICON_SIZE
    local aspectRatio = rowConfig.aspectRatioCrop or 1.0
    local width = size
    local height = size / aspectRatio

    -- Pixel-snap dimensions
    if QUICore and QUICore.PixelRound then
        width = QUICore:PixelRound(width, icon)
        height = QUICore:PixelRound(height, icon)
    end

    icon:SetSize(width, height)

    -- Icon texture fills the frame
    if icon.Icon then
        icon.Icon:ClearAllPoints()
        icon.Icon:SetAllPoints(icon)
    end

    -- Cooldown frame matches icon size
    if icon.Cooldown then
        icon.Cooldown:ClearAllPoints()
        icon.Cooldown:SetAllPoints(icon)
    end

    -- Border
    local borderSize = rowConfig.borderSize or 0
    if borderSize > 0 then
        local bs = (QUICore and QUICore.Pixels) and QUICore:Pixels(borderSize, icon) or borderSize
        local bc = rowConfig.borderColorTable or {0, 0, 0, 1}

        icon.Border:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        icon.Border:ClearAllPoints()
        icon.Border:SetPoint("TOPLEFT", icon, "TOPLEFT", -bs, bs)
        icon.Border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", bs, -bs)
        icon.Border:Show()

        icon:SetHitRectInsets(-bs, -bs, -bs, -bs)
        if icon.clickButton then
            icon.clickButton:SetHitRectInsets(-bs, -bs, -bs, -bs)
        end
    else
        icon.Border:Hide()
        icon:SetHitRectInsets(0, 0, 0, 0)
        if icon.clickButton then
            icon.clickButton:SetHitRectInsets(0, 0, 0, 0)
        end
    end

    -- TexCoord (zoom + aspect ratio crop)
    ApplyTexCoord(icon, rowConfig.zoom or 0, aspectRatio)

    -- Duration text styling
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()

    local durationSize = rowConfig.durationSize or 14
    local hideDurationText = rowConfig.hideDurationText
    if durationSize > 0 and not hideDurationText then
        local dtc = rowConfig.durationTextColor or {1, 1, 1, 1}
        local dAnchor = rowConfig.durationAnchor or "CENTER"
        local dox = rowConfig.durationOffsetX or 0
        local doy = rowConfig.durationOffsetY or 0

        -- Style the Cooldown frame's built-in text
        if icon.Cooldown then
            local ok, regions = pcall(function() return { icon.Cooldown:GetRegions() } end)
            if ok and regions then
                for _, region in ipairs(regions) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        region:SetFont(generalFont, durationSize, generalOutline)
                        region:SetTextColor(dtc[1], dtc[2], dtc[3], dtc[4] or 1)
                        region:Show()
                        pcall(function()
                            region:ClearAllPoints()
                            region:SetPoint(dAnchor, icon, dAnchor, dox, doy)
                            region:SetDrawLayer("OVERLAY", 7)
                        end)
                    end
                end
            end
        end

        -- Also style our DurationText
        icon.DurationText:SetFont(generalFont, durationSize, generalOutline)
        icon.DurationText:SetTextColor(dtc[1], dtc[2], dtc[3], dtc[4] or 1)
        icon.DurationText:ClearAllPoints()
        icon.DurationText:SetPoint(dAnchor, icon, dAnchor, dox, doy)
        icon.DurationText:Show()
    elseif hideDurationText then
        -- Hide all duration text elements
        if icon.Cooldown then
            local ok, regions = pcall(function() return { icon.Cooldown:GetRegions() } end)
            if ok and regions then
                for _, region in ipairs(regions) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        region:Hide()
                    end
                end
            end
        end
        icon.DurationText:Hide()
    end

    -- Stack text styling
    local stackSize = rowConfig.stackSize or 14
    if stackSize > 0 then
        local stc = rowConfig.stackTextColor or {1, 1, 1, 1}
        local sAnchor = rowConfig.stackAnchor or "BOTTOMRIGHT"
        local sox = rowConfig.stackOffsetX or 0
        local soy = rowConfig.stackOffsetY or 0

        icon.StackText:SetFont(generalFont, stackSize, generalOutline)
        icon.StackText:SetTextColor(stc[1], stc[2], stc[3], stc[4] or 1)
        icon.StackText:ClearAllPoints()
        icon.StackText:SetPoint(sAnchor, icon, sAnchor, sox, soy)
        icon.StackText:SetDrawLayer("OVERLAY", 7)
    end

    -- Apply row opacity
    local opacity = rowConfig.opacity or 1.0
    icon:SetAlpha(opacity)
    icon._rowOpacity = opacity

    ---------------------------------------------------------------------------
    -- Per-spell overrides (additive on top of row-level settings)
    ---------------------------------------------------------------------------
    local spellOvr = GetIconSpellOverride(icon)
    if spellOvr then
        -- iconSizeOverride: override icon + sub-region sizes
        if spellOvr.iconSizeOverride then
            local ovrSize = spellOvr.iconSizeOverride
            local aspectRatio = rowConfig.aspectRatioCrop or 1.0
            local ovrW = ovrSize
            local ovrH = ovrSize / aspectRatio
            if QUICore and QUICore.PixelRound then
                ovrW = QUICore:PixelRound(ovrW, icon)
                ovrH = QUICore:PixelRound(ovrH, icon)
            end
            icon:SetSize(ovrW, ovrH)
            if icon.Cooldown then
                icon.Cooldown:ClearAllPoints()
                icon.Cooldown:SetAllPoints(icon)
            end
            if icon.Icon then
                icon.Icon:ClearAllPoints()
                icon.Icon:SetAllPoints(icon)
            end
        end

        -- showDurationText: per-spell duration text visibility override
        if spellOvr.showDurationText == false then
            if icon.Cooldown then
                local ok, regions = pcall(function() return { icon.Cooldown:GetRegions() } end)
                if ok and regions then
                    for _, region in ipairs(regions) do
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            region:Hide()
                        end
                    end
                end
            end
            icon.DurationText:Hide()
        elseif spellOvr.showDurationText == true then
            icon.DurationText:Show()
        end

        -- customBorderColor: per-spell border color override
        if spellOvr.customBorderColor and icon.Border and icon.Border:IsShown() then
            local bc = spellOvr.customBorderColor
            icon.Border:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
        end

        -- desaturate: cache for UpdateIconCooldown to use per-icon
        icon._spellOverrideDesaturate = spellOvr.desaturate
    else
        icon._spellOverrideDesaturate = nil
    end

    SyncCooldownBling(icon)
end

---------------------------------------------------------------------------
-- COOLDOWN UPDATE
-- Update cooldown state for a single icon.
---------------------------------------------------------------------------
local function GetTrackerSettings(viewerType)
    local db = GetDB()
    if not db or not viewerType then return nil end
    return db[viewerType]
end

local function UpdateIconCooldown(icon)
    if not icon or not icon._spellEntry then return end
    local entry = icon._spellEntry

        -- Aura-driven update for aura/auraBar containers:
        -- Use C_UnitAuras.GetPlayerAuraBySpellID for cooldown swipe + stacks
        if entry._ownedEntry then
            local ownedDB = nil
            if ns.CDMSpellData then
                local QUICore = ns.Addon
                local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
                ownedDB = ncdm and ncdm[entry.viewerType]
            end
            local cType = ownedDB and ownedDB.containerType
            if not cType then
                local vt = entry.viewerType
                cType = (vt == "buff" or vt == "trackedBar") and "aura" or "cooldown"
            end
            if cType == "aura" or cType == "auraBar" then
                local auraSpellID = entry.overrideSpellID or entry.spellID or entry.id
                -- Resolve ability→aura mapping (e.g. Marrowrend→Bone Shield,
                -- Death and Decay ability→DnD buff).  The entry's spellID may
                -- be the ability ID rather than the actual buff spell ID.
                local auraMap = ns.CDMSpellData and ns.CDMSpellData._abilityToAuraSpellID
                if auraMap and auraMap[auraSpellID] then
                    auraSpellID = auraMap[auraSpellID]
                end
                if auraSpellID then
                    -- Try to get full auraData via spell ID lookups
                    local auraData = LookupAura(auraSpellID, entry)

                    -- Resolve auraInstanceID from auraData, Blizzard child frame,
                    -- or UNIT_AURA event cache.  The child frame's auraInstanceID
                    -- is the most reliable combat source — maintained by C-side code.
                    local blzChild = entry._blizzChild
                    local childAuraInstID
                    -- Only trust child's auraInstanceID if the child is still
                    -- shown — Blizzard hides children C-side when buffs drop
                    -- but doesn't nil their auraInstanceID field.
                    if blzChild and blzChild.auraInstanceID then
                        local cok, cshown = pcall(blzChild.IsShown, blzChild)
                        if cok and cshown then
                            childAuraInstID = SafeValue(blzChild.auraInstanceID, nil)
                        else
                            -- Child is hidden/stale — clear cached reference
                            entry._blizzChild = nil
                            blzChild = nil
                        end
                    end
                    -- Dynamic fallback: scan ALL viewer children for one with
                    -- auraInstanceID matching our spell IDs.  Handles cases where
                    -- the static _blizzChild was nil or points to a recycled child.
                    if not childAuraInstID then
                        local dynChild = FindActiveAuraChild(auraSpellID, entry.spellID, entry.id)
                        if dynChild then
                            childAuraInstID = SafeValue(dynChild.auraInstanceID, nil)
                            -- Cache for next tick so we don't scan every time
                            entry._blizzChild = dynChild
                        end
                    end
                    local auraInstID = (auraData and auraData.auraInstanceID)
                        or childAuraInstID
                        or _spellToAuraInstance[auraSpellID]
                        or (entry.spellID and _spellToAuraInstance[entry.spellID])
                        or (entry.id and _spellToAuraInstance[entry.id])

                    -- Validate cache-sourced auraInstID is still active.
                    -- GetAuraDataByAuraInstanceID returns nil for expired auras
                    -- even during combat (secret fields, but non-nil result).
                    if auraInstID and not auraData and not childAuraInstID then
                        local auraUnit = (blzChild and blzChild.auraDataUnit) or "player"
                        local vok, vdata = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, auraUnit, auraInstID)
                        if vok and not vdata then
                            auraInstID = nil
                        end
                    end

                    -- Hook cache: DurationObject + raw start/dur from Blizzard viewer child.
                    -- CRITICAL: For aura containers, only trust data from buff viewer
                    -- children (BuffIconCooldownViewer / BuffBarCooldownViewer).
                    -- Cooldown viewer children have SPELL COOLDOWN timers (30-45s),
                    -- not aura duration timers (5-10s).
                    local hookDurObj, hookStart, hookDur

                    -- Only use direct _blizzChild if it belongs to a buff viewer
                    local buffViewer = _G["BuffIconCooldownViewer"]
                    local buffBarViewer = _G["BuffBarCooldownViewer"]
                    local childIsBuff = blzChild and blzChild.viewerFrame
                        and (blzChild.viewerFrame == buffViewer or blzChild.viewerFrame == buffBarViewer)
                    if childIsBuff and ns.CDMSpellData then
                        hookDurObj = ns.CDMSpellData._durObjCache[blzChild]
                        hookStart = ns.CDMSpellData._rawStartCache[blzChild]
                        hookDur = ns.CDMSpellData._rawDurCache[blzChild]
                    end

                    -- Fallback: search by spell ID, restricted to buff viewer children
                    if not hookDurObj and not hookStart and ns.CDMSpellData and ns.CDMSpellData.GetCachedAuraDurObj then
                        hookDurObj, hookStart, hookDur = ns.CDMSpellData:GetCachedAuraDurObj(auraSpellID)
                        if not hookDurObj and not hookStart and entry.spellID and entry.spellID ~= auraSpellID then
                            hookDurObj, hookStart, hookDur = ns.CDMSpellData:GetCachedAuraDurObj(entry.spellID)
                        end
                        if not hookDurObj and not hookStart and entry.id and entry.id ~= auraSpellID and entry.id ~= entry.spellID then
                            hookDurObj, hookStart, hookDur = ns.CDMSpellData:GetCachedAuraDurObj(entry.id)
                        end
                    end

                    -- GCD filter on raw hook values: duration ≤ 1.5s (when readable)
                    -- is from the global cooldown.  When secret, keep it — C-side
                    -- handles it and it's better than showing nothing.
                    local hookRawIsGCD = false
                    if hookStart and hookDur then
                        local safeDur = SafeToNumber(hookDur, nil)
                        if safeDur and safeDur > 0 and safeDur <= 1.5 then
                            hookRawIsGCD = true
                        end
                    end

                    -- Active if: API returned data, cache has instance ID, or hook
                    -- has aura data from buff viewer children.
                    local hookRawValid = (hookStart and hookDur and not hookRawIsGCD)
                    if auraData or auraInstID or hookDurObj or hookRawValid then
                        icon._auraActive = true

                        local swipeSet = false

                        -- 1. API path: GetAuraDuration → SetCooldownFromDurationObject
                        -- Use auraDataUnit from Blizzard child (supports target debuffs like Reaper's Mark)
                        local auraUnit = (blzChild and blzChild.auraDataUnit) or "player"
                        if not swipeSet and icon.Cooldown and auraInstID and C_UnitAuras.GetAuraDuration then
                            local dok, durObj = pcall(C_UnitAuras.GetAuraDuration, auraUnit, auraInstID)
                            if dok and durObj and icon.Cooldown.SetCooldownFromDurationObject then
                                pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, durObj, true)
                                pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                                swipeSet = true
                            end
                        end

                        -- 2. Hook cache: DurationObject from buff viewer child
                        if not swipeSet and icon.Cooldown and hookDurObj and icon.Cooldown.SetCooldownFromDurationObject then
                            pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, hookDurObj, true)
                            pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                            swipeSet = true
                        end

                        -- 3. Hook cache: raw start/duration from buff viewer (GCD-filtered)
                        if not swipeSet and icon.Cooldown and hookRawValid then
                            pcall(icon.Cooldown.SetCooldown, icon.Cooldown, hookStart, hookDur)
                            pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                            swipeSet = true
                        end

                        -- Show stacks — TruncateWhenZero is C-side, handles
                        -- secret values natively: returns "" for 0, number string otherwise.
                        -- Just get applications and set — no Lua comparisons.
                        local apps = auraData and auraData.applications
                        local appsSource = apps and "auraData" or "none"
                        if not apps and auraInstID and C_UnitAuras.GetAuraDataByAuraInstanceID then
                            local aok, instData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, auraUnit, auraInstID)
                            if aok and instData then
                                apps = instData.applications
                                if apps then appsSource = "instData" end
                            end
                        end
                        if apps then
                            pcall(icon.StackText.SetText, icon.StackText, C_StringUtil.TruncateWhenZero(apps))
                            icon.StackText:Show()
                        else
                            icon.StackText:SetText("")
                            icon.StackText:Hide()
                        end

                        -- Update texture from API (for spell overrides)
                        if icon.Icon and entry.type == "spell" then
                            local texID = GetSpellTexture(auraSpellID)
                            if texID then
                                icon.Icon:SetTexture(texID)
                            end
                        end

                        ReapplySwipeStyle(icon.Cooldown, icon)
                        return  -- Aura path complete, skip cooldown path below
                    else
                        -- Aura genuinely absent
                        icon._auraActive = false
                        if icon.Cooldown then
                            icon.Cooldown:Clear()
                        end
                        icon.StackText:SetText("")
                        icon.StackText:Hide()
                        return  -- Aura path complete
                    end
                end
            end
        end

        local startTime, duration
        if entry.type == "macro" then
            local resolvedID, resolvedType = ResolveMacro(entry)
            if resolvedID then
                if resolvedType == "item" then
                    startTime, duration = GetItemCooldown(resolvedID)
                else
                    startTime, duration = GetBestSpellCooldown(resolvedID)
                end
            end
            -- Update icon texture dynamically (resolved spell may change each tick)
            local newTex = GetEntryTexture(entry)
            if newTex and icon.Icon then
                icon.Icon:SetTexture(newTex)
            end
        elseif entry.type == "trinket" or entry.type == "slot" then
            -- Trinket/slot entries store equipment slot (13/14), resolve to item ID
            local slotID = entry.id
            local itemID = GetInventoryItemID("player", slotID)
            if itemID then
                -- Use GetInventoryItemCooldown for equipped items (not GetItemCooldown)
                if GetInventoryItemCooldown then
                    local s, d, e = GetInventoryItemCooldown("player", slotID)
                    if s and d and d > 1.5 and e == 1 then
                        startTime = s
                        duration = d
                    end
                end
                -- Update texture in case trinket was swapped
                if icon.Icon then
                    local ok, tex = pcall(C_Item.GetItemIconByID, itemID)
                    if ok and tex then icon.Icon:SetTexture(tex) end
                end
            end
            -- Hide stack text for trinkets
            icon.StackText:SetText("")
            icon.StackText:Hide()
        elseif entry.type == "item" then
            startTime, duration = GetItemCooldown(entry.id)
            -- Show item count as stack text (includeUses=true for charge items)
            if C_Item and C_Item.GetItemCount then
                local ok, count = pcall(C_Item.GetItemCount, entry.id, false, true)
                if ok and count and count > 0 then
                    icon.StackText:SetText(tostring(count))
                    icon.StackText:Show()
                else
                    icon.StackText:SetText("0")
                    icon.StackText:Show()
                end
            end
        else
            startTime, duration = GetBestSpellCooldown(entry.overrideSpellID or entry.spellID or entry.id)

            -- Sync texture for spell overrides (e.g., Judgment → Hammer of Wrath).
            -- Check the override API directly and update if the active spell changed.
            if C_Spell.GetOverrideSpell and icon.Icon then
                local baseID = entry.spellID or entry.id
                if baseID then
                    local overrideID = C_Spell.GetOverrideSpell(baseID)
                    local newTex = GetSpellTexture(overrideID or baseID)
                    if newTex then
                        icon.Icon:SetTexture(newTex)
                    end
                end
            end
        end

        local safeDur = SafeToNumber(duration, nil)
        local safeStartVal = SafeToNumber(startTime, nil)
        -- Only update when safe values are available.  Defaulting to 0 on
        -- secret values would make the desaturation code think the spell
        -- is off cooldown mid-combat.
        if safeDur then icon._lastDuration = safeDur end
        if safeStartVal then icon._lastStart = safeStartVal end
        if safeDur == 0 then
            icon._lastStart = 0
            icon._lastDuration = 0
        end

        if icon.Cooldown then
            if startTime and duration then
                pcall(icon.Cooldown.SetCooldown, icon.Cooldown, startTime, duration)
            else
                icon.Cooldown:Clear()
            end
        end

    -- Stack/charge text: API-driven on each tick.
    if entry.type == "item" then
        -- Item stack text was already set above in the cooldown section;
        -- nothing to do here — just prevent the else clause from clearing it.
    elseif entry.type == "spell" then
        -- Cooldown entry: check charges/stacks via API
        local spellID = entry.overrideSpellID or entry.spellID or entry.id
        local stackText = nil

        -- Check spell charges
        if spellID and C_Spell.GetSpellCharges then
            local ok, chargeInfo = pcall(C_Spell.GetSpellCharges, spellID)
            if ok and chargeInfo and chargeInfo.maxCharges then
                if not IsSecretValue(chargeInfo.maxCharges) and chargeInfo.maxCharges > 1 then
                    local current = chargeInfo.currentCharges
                    if not IsSecretValue(current) and current and current >= 0 then
                        stackText = tostring(current)
                    end
                end
            end
        end

        -- Check secondary resource counts
        if not stackText and spellID and C_Spell.GetSpellCastCount then
            local ok, val = pcall(C_Spell.GetSpellCastCount, spellID)
            if ok and val and not IsSecretValue(val) and val > 0 then
                stackText = tostring(val)
            end
        end

        if stackText and stackText ~= "" then
            icon.StackText:SetText(stackText)
            icon.StackText:Show()
        else
            icon.StackText:SetText("")
            icon.StackText:Hide()
        end
    else
        icon.StackText:SetText("")
        icon.StackText:Hide()
    end

    -- Desaturation for cooldown entries based on cooldown state.
    if icon.Icon and icon.Icon.SetDesaturated then
        local viewerType = entry.viewerType

        -- Skip buff viewer icons and aura-active icons (they show buff timers)
        if viewerType ~= "buff" and not icon._auraActive and not icon._rangeTinted and not icon._usabilityTinted then
            -- Per-spell desaturate override takes precedence over tracker-wide setting
            local desatOverride = icon._spellOverrideDesaturate
            local db = GetDB()
            local settings = db and db[viewerType]
            local shouldDesaturate = settings and settings.desaturateOnCooldown
            if desatOverride == true then
                shouldDesaturate = true
            elseif desatOverride == false then
                shouldDesaturate = false
            end
            if shouldDesaturate then
                local dur = icon._lastDuration or 0
                local start = icon._lastStart or 0

                if dur > 1.5 and start > 0 then
                    local remaining = (start + dur) - GetTime()
                    if remaining > 0 then
                        -- On cooldown — check charges before desaturating
                        local spellID = entry.overrideSpellID or entry.spellID or entry.id
                        if spellID and C_Spell.GetSpellCharges then
                            local chargeInfo = C_Spell.GetSpellCharges(spellID)
                            if chargeInfo then
                                -- Secret charge data → keep current state (don't flicker)
                                if IsSecretValue(chargeInfo.currentCharges) then
                                    return
                                end
                                local current = SafeToNumber(chargeInfo.currentCharges, 0)
                                if current > 0 then
                                    icon.Icon:SetDesaturated(false)
                                    icon._cdDesaturated = nil
                                    return
                                end
                            end
                        end
                        icon.Icon:SetDesaturated(true)
                        icon._cdDesaturated = true
                        return
                    end
                end

                -- Off cooldown or GCD-only — clear desaturation
                icon.Icon:SetDesaturated(false)
                icon._cdDesaturated = nil
            else
                icon.Icon:SetDesaturated(false)
                icon._cdDesaturated = nil
            end
        else
            icon.Icon:SetDesaturated(false)
            icon._cdDesaturated = nil
        end
    end
end

---------------------------------------------------------------------------
-- ICON POOL MANAGEMENT
---------------------------------------------------------------------------
function CDMIcons:AcquireIcon(parent, spellEntry)
    local icon = table.remove(recyclePool)
    if icon then
        icon:SetParent(parent)
        icon:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
        icon._spellEntry = spellEntry
        icon._isQUICDMIcon = true
        icon._lastStart = nil
        icon._lastDuration = nil
        icon._isOnGCD = nil

        -- Update texture
        local texID
        if spellEntry.type then
            texID = GetEntryTexture(spellEntry)
        else
            texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
        end
        if icon.Icon then
            if texID then
                icon.Icon:SetTexture(texID)
            else
                -- Clear stale texture from previous owner to prevent
                -- recycled icons showing the wrong spell/item icon.
                icon.Icon:SetTexture(nil)
            end
            icon.Icon:SetDesaturated(false)
        end

        if icon.Cooldown then
            icon.Cooldown:Clear()
        end
        icon.StackText:SetText("")
        icon.StackText:Hide()
        -- Update click-to-cast secure attributes for recycled icons
        if spellEntry.viewerType ~= "buff" then
            UpdateIconSecureAttributes(icon, spellEntry, spellEntry.viewerType)
        end
        icon:Show()
        return icon
    end
    local newIcon = CreateIcon(parent, spellEntry)
    -- Update click-to-cast secure attributes for new icons
    if spellEntry.viewerType ~= "buff" then
        UpdateIconSecureAttributes(newIcon, spellEntry, spellEntry.viewerType)
    end
    return newIcon
end

function CDMIcons:ReleaseIcon(icon)
    if not icon then return end
    icon:Hide()
    icon:ClearAllPoints()
    icon._spellEntry = nil
    icon._rangeTinted = nil
    icon._usabilityTinted = nil
    icon._cdDesaturated = nil
    icon._spellOverrideDesaturate = nil
    icon._lastStart = nil
    icon._lastDuration = nil
    icon._isOnGCD = nil
    if icon.Icon then
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon.Icon:SetDesaturated(false)
    end
    if icon.Cooldown then
        icon.Cooldown:Clear()
    end
    icon.StackText:SetText("")
    icon.Border:Hide()

    -- Clear click-to-cast secure button
    if icon.clickButton then
        if not InCombatLockdown() then
            ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
    end
    icon._pendingSecureUpdate = nil

    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        icon:SetParent(UIParent)
        recyclePool[#recyclePool + 1] = icon
    end
end

function CDMIcons:GetIconPool(viewerType)
    return iconPools[viewerType] or {}
end

--- Ensure an icon pool exists for the given container key (Phase G).
function CDMIcons:EnsurePool(viewerType)
    if not iconPools[viewerType] then
        iconPools[viewerType] = {}
    end
end

function CDMIcons:ClearPool(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        for _, icon in ipairs(pool) do
            self:ReleaseIcon(icon)
        end
    end
    iconPools[viewerType] = {}
end


---------------------------------------------------------------------------
-- BUILD ICONS: Create icons from harvested spell data + custom entries
---------------------------------------------------------------------------
function CDMIcons:BuildIcons(viewerType, container)
    if not container then return {} end

    -- Release old icons
    self:ClearPool(viewerType)

    local pool = {}
    local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList(viewerType) or {}

    -- Create icons from harvested spell data
    for _, entry in ipairs(spellData) do
        local icon = self:AcquireIcon(container, entry)
        pool[#pool + 1] = icon
    end

    -- Merge custom entries (essential and utility only)
    if viewerType == "essential" or viewerType == "utility" then
        local customData = GetCustomData(viewerType)
        if customData and customData.enabled and customData.entries then
            local placement = customData.placement or "after"

            -- Separate positioned and unpositioned custom entries
            local positioned = {}
            local unpositioned = {}
            for idx, entry in ipairs(customData.entries) do
                if entry.enabled ~= false then
                    local spellEntry = {
                        spellID = entry.id,
                        overrideSpellID = entry.id,
                        name = "",
                        isAura = false,
                        layoutIndex = 99000 + idx,
                        viewerType = viewerType,
                        type = entry.type,
                        id = entry.id,
                        _isCustomEntry = true,
                    }
                    -- Get name and resolve IDs per entry type
                    if entry.type == "macro" then
                        spellEntry.macroName = entry.macroName
                        spellEntry.name = entry.macroName or ""
                        -- Resolve current spell for initial texture (updates dynamically)
                        local resolvedID, resolvedType = ResolveMacro(spellEntry)
                        if resolvedID then
                            spellEntry.spellID = resolvedID
                            spellEntry.overrideSpellID = resolvedID
                        end
                    elseif entry.type == "trinket" then
                        -- Trinket entries store equipment slot (13/14), resolve to item ID
                        local itemID = GetInventoryItemID("player", entry.id)
                        if itemID then
                            local itemName = C_Item.GetItemNameByID(itemID)
                            spellEntry.name = itemName or ""
                        end
                    elseif entry.type == "item" then
                        local itemName = C_Item.GetItemNameByID(entry.id)
                        spellEntry.name = itemName or ""
                    else
                        local spellInfo = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.id)
                        spellEntry.name = spellInfo and spellInfo.name or ""
                    end

                    if entry.position and entry.position > 0 then
                        positioned[#positioned + 1] = { entry = spellEntry, position = entry.position, origIndex = idx }
                    else
                        unpositioned[#unpositioned + 1] = spellEntry
                    end
                end
            end

            -- Insert unpositioned entries (before or after harvested icons)
            if #unpositioned > 0 then
                if placement == "before" then
                    local merged = {}
                    for _, entry in ipairs(unpositioned) do
                        local icon = self:AcquireIcon(container, entry)
                        merged[#merged + 1] = icon
                    end
                    for _, icon in ipairs(pool) do
                        merged[#merged + 1] = icon
                    end
                    pool = merged
                else
                    for _, entry in ipairs(unpositioned) do
                        local icon = self:AcquireIcon(container, entry)
                        pool[#pool + 1] = icon
                    end
                end
            end

            -- Insert positioned entries at specific slots (descending to avoid shifts)
            table.sort(positioned, function(a, b)
                if a.position ~= b.position then return a.position > b.position end
                return a.origIndex < b.origIndex
            end)
            for _, item in ipairs(positioned) do
                local icon = self:AcquireIcon(container, item.entry)
                local insertAt = math.min(item.position, #pool + 1)
                table.insert(pool, insertAt, icon)
            end
        end
    end

    -- Initialize owned icons: configure addon CD and mark aura containers
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry then
            local addonCD = icon.Cooldown
            if addonCD then
                addonCD:SetDrawSwipe(true)
                addonCD:SetHideCountdownNumbers(false)
                addonCD:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
                addonCD:SetSwipeColor(0, 0, 0, 0.8)
                addonCD:Show()
            end
            -- Mark aura containers so visibility handling works correctly
            local QUICore = ns.Addon
            local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
            local containerDB = ncdm and ncdm[entry.viewerType]
            local cType = containerDB and containerDB.containerType
            if not cType then
                local vt = entry.viewerType
                cType = (vt == "buff" or vt == "trackedBar") and "aura" or "cooldown"
            end
            if cType == "aura" or cType == "auraBar" then
                icon._auraActive = false  -- will be set true by UpdateIconCooldown when aura present
            end
        end
    end

    -- Update click-to-cast secure attributes for essential/utility icons.
    -- AcquireIcon sets attrs per-icon, but this catches any pending updates
    -- (e.g., from combat-deferred rebuilds via PLAYER_REGEN_ENABLED).
    if viewerType == "essential" or viewerType == "utility" then
        for _, icon in ipairs(pool) do
            if icon._pendingSecureUpdate then
                UpdateIconSecureAttributes(icon, icon._spellEntry, viewerType)
            end
        end
    end

    iconPools[viewerType] = pool

    -- Immediately update cooldown state so icons reflect correct
    -- desaturation/stack text without waiting for the next ticker.
    self:UpdateCooldownsForType(viewerType)

    return pool
end

---------------------------------------------------------------------------
-- RESOLVED AURA ID CACHE
-- OOC: resolve the correct spell ID that GetPlayerAuraBySpellID succeeds
-- with.  Combat: use the cached resolved ID for faster lookups.
---------------------------------------------------------------------------
local _resolvedAuraIDs = {}  -- [ownedSpellID] = resolvedSpellID

---------------------------------------------------------------------------
-- AURA LOOKUP WITH FALLBACK CHAIN
-- Try: resolved ID → primary ID → alt IDs.
-- Returns auraData or nil.  When all ID lookups fail during combat,
-- callers fall back to the presence cache + _spellToAuraInstance for
-- the DurationObject path (auraInstanceID is known from UNIT_AURA events).
---------------------------------------------------------------------------
LookupAura = function(spellID, entry)
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end

    local primaryID = entry and (entry.overrideSpellID or entry.spellID or entry.id) or spellID

    -- 1. Try resolved ID (cached from OOC)
    local resolvedID = _resolvedAuraIDs[primaryID]
    if resolvedID then
        local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedID)
        if ok and ad then return ad end
    end

    -- 2. Try primary ID (if different from resolved)
    if not resolvedID or resolvedID ~= spellID then
        local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and ad then
            if not InCombatLockdown() then _resolvedAuraIDs[primaryID] = spellID end
            return ad
        end
    end

    -- 3. Try alt IDs
    if entry then
        local altIDs = {}
        if entry.spellID and entry.spellID ~= spellID and entry.spellID ~= resolvedID then
            altIDs[#altIDs+1] = entry.spellID
        end
        if entry.id and entry.id ~= spellID and entry.id ~= entry.spellID and entry.id ~= resolvedID then
            altIDs[#altIDs+1] = entry.id
        end
        for _, altID in ipairs(altIDs) do
            local ok2, ad2 = pcall(C_UnitAuras.GetPlayerAuraBySpellID, altID)
            if ok2 and ad2 then
                if not InCombatLockdown() then _resolvedAuraIDs[primaryID] = altID end
                return ad2
            end
        end
    end

    -- 4. Target debuff fallback (e.g. Reaper's Mark)
    if entry and entry.name and entry.name ~= "" and C_UnitAuras.GetAuraDataBySpellName then
        local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", entry.name, "HARMFUL")
        if ok and ad then return ad end
        -- Also try HELPFUL on target (some abilities are buffs on friendly target)
        local ok2, ad2 = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", entry.name, "HELPFUL")
        if ok2 and ad2 then return ad2 end
    end

    return nil
end

CDMIcons.LookupAura = LookupAura  -- exposed for CDMBars

---------------------------------------------------------------------------
-- COMBAT AURA CACHE
-- Used by custom aura/auraBar containers (Composer-created) that have
-- ownedSpells and poll GetPlayerAuraBySpellID.  Built-in buff/trackedBar
-- containers use direct aura lookup instead (no cache needed).
-- GetPlayerAuraBySpellID is restricted during combat for most spell IDs.
-- The cache snapshots aura state on PLAYER_REGEN_DISABLED and patches
-- incrementally from UNIT_AURA addedAuras/removedAuraInstanceIDs.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Aura presence cache for owned aura containers (Composer-configured).
--
-- Problem: GetPlayerAuraBySpellID(abilityID) works OOC but returns
-- nil during combat (WoW 12.0 secret-value restriction).  The ability
-- spell ID stored in ownedSpells often differs from the actual buff
-- aura spell ID on the player (e.g. Marrowrend → Bone Shield).
--
-- Solution:
--   OOC ticks — call GetPlayerAuraBySpellID(ownedID) for each tracked
--     spell.  When it returns data, record the REAL aura spellId from
--     the result.  Also build a set of all active aura spell IDs via
--     ForEachAura.
--   PLAYER_REGEN_DISABLED — one final OOC rebuild, then freeze.
--   During combat — use the frozen set + the ownedID→realID mapping.
--   UNIT_AURA addedAuras/removedAuraInstanceIDs — patch incrementally.
--   PLAYER_REGEN_ENABLED — unfreeze.
---------------------------------------------------------------------------
local _auraInstanceToSpell = {}  -- [auraInstanceID] = spellId (for removal)
-- _spellToAuraInstance is forward-declared near top of file
local _inCombatCaching = false

local function ProcessAuraEntry(ad)
    if not ad then return end
    local iid = ad.auraInstanceID
    if not iid then return end
    local safeIid = SafeValue(iid, nil)
    if not safeIid then return end

    local sid = ad.spellId
    local safeSid = sid and SafeValue(sid, nil)
    if safeSid then
        _auraInstanceToSpell[safeIid] = safeSid
        _spellToAuraInstance[safeSid] = safeIid
        -- Create reverse aliases: ability IDs that map to this aura spell ID
        -- via _abilityToAuraSpellID should also resolve to the same instance.
        -- This is critical in combat where GetPlayerAuraBySpellID(abilityID)
        -- returns nil — the ability ID needs a direct path to the instance.
        local auraMap = ns.CDMSpellData and ns.CDMSpellData._abilityToAuraSpellID
        if auraMap then
            for abilityID, auraID in pairs(auraMap) do
                if auraID == safeSid and not _spellToAuraInstance[abilityID] then
                    _spellToAuraInstance[abilityID] = safeIid
                end
            end
        end
    end
    -- If spellId is secret, we still record the iid; the caller
    -- (PatchAuraCacheFromEvent) handles orphan reassignment.
    return safeIid, safeSid
end

local function FullRebuildAuraCache(wipe)
    if wipe then
        table.wipe(_auraInstanceToSpell)
        table.wipe(_spellToAuraInstance)
    end
    if not AuraUtil or not AuraUtil.ForEachAura then return end
    for _, auraUnit in ipairs({"player", "target"}) do
        for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
            pcall(function()
                AuraUtil.ForEachAura(auraUnit, filter, nil, function(ad)
                    ProcessAuraEntry(ad)
                end, true)
            end)
        end
    end

    -- Build ability ID → auraInstanceID aliases.
    -- Tracked spells use ability/override IDs that differ from the real buff
    -- spell ID in _spellToAuraInstance.  Query GetPlayerAuraBySpellID for
    -- each tracked icon's IDs; when found, alias them to the same instance.
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon._spellEntry
            if entry and entry._isOwnedEntry then
                local ids = {}
                if entry.overrideSpellID then ids[#ids+1] = entry.overrideSpellID end
                if entry.spellID and entry.spellID ~= entry.overrideSpellID then ids[#ids+1] = entry.spellID end
                if entry.id and entry.id ~= entry.spellID and entry.id ~= entry.overrideSpellID then ids[#ids+1] = entry.id end
                for _, queryID in ipairs(ids) do
                    if not _spellToAuraInstance[queryID] then
                        local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, queryID)
                        if ok and ad then
                            local realSid = ad.spellId and SafeValue(ad.spellId, nil)
                            local iid = realSid and _spellToAuraInstance[realSid]
                            if iid then
                                -- Alias: ability ID → same auraInstanceID
                                _spellToAuraInstance[queryID] = iid
                            elseif ad.auraInstanceID then
                                -- Direct: store from auraData
                                local safeIid = SafeValue(ad.auraInstanceID, nil)
                                if safeIid then
                                    _spellToAuraInstance[queryID] = safeIid
                                    _auraInstanceToSpell[safeIid] = queryID
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function PatchAuraCacheFromEvent(updateInfo)
    if not updateInfo then return end

    -- 1. Process removals first — collect orphaned spellIds (auras that
    --    lost their instance, likely being refreshed with a new one).
    local orphanedSpells = nil
    local auraMap = ns.CDMSpellData and ns.CDMSpellData._abilityToAuraSpellID
    if updateInfo.removedAuraInstanceIDs then
        for _, iid in ipairs(updateInfo.removedAuraInstanceIDs) do
            local safeIid = SafeValue(iid, nil)
            if safeIid then
                local sid = _auraInstanceToSpell[safeIid]
                if sid then
                    _auraInstanceToSpell[safeIid] = nil
                    _spellToAuraInstance[sid] = nil
                    -- Clear ability ID aliases that pointed to this instance
                    if auraMap then
                        for abilityID, auraID in pairs(auraMap) do
                            if auraID == sid and _spellToAuraInstance[abilityID] == safeIid then
                                _spellToAuraInstance[abilityID] = nil
                            end
                        end
                    end
                    -- Stash as orphan for reassignment
                    if not orphanedSpells then orphanedSpells = {} end
                    orphanedSpells[#orphanedSpells + 1] = sid
                end
            end
        end
    end

    -- 2. Process additions — map new auraInstanceIDs to spellIds.
    --    When spellId is secret (combat), reassign orphaned spells
    --    (auras that were just removed and immediately re-added = refresh).
    local unmappedIIDs = nil
    if updateInfo.addedAuras then
        for _, ad in ipairs(updateInfo.addedAuras) do
            local safeIid, safeSid = ProcessAuraEntry(ad)
            if safeIid and not safeSid then
                -- auraInstanceID readable but spellId secret
                if not unmappedIIDs then unmappedIIDs = {} end
                unmappedIIDs[#unmappedIIDs + 1] = safeIid
            end
        end
    end

    -- 3. Reassign: pair orphaned spellIds with unmapped auraInstanceIDs.
    --    For a single aura refresh this is a 1:1 match.  For multiple
    --    simultaneous refreshes the pairing is best-effort (order-based).
    if orphanedSpells and unmappedIIDs then
        for i = 1, math.min(#orphanedSpells, #unmappedIIDs) do
            local sid = orphanedSpells[i]
            local iid = unmappedIIDs[i]
            _auraInstanceToSpell[iid] = sid
            _spellToAuraInstance[sid] = iid
            -- Update alias entries (ability IDs that pointed to old instance)
            for key, oldIid in pairs(_spellToAuraInstance) do
                if key ~= sid and oldIid ~= iid and _auraInstanceToSpell[oldIid] == nil then
                    -- This alias pointed to a removed instance — update it
                    _spellToAuraInstance[key] = iid
                end
            end
            -- Create ability→instance aliases for this reassigned spell
            if auraMap then
                for abilityID, auraID in pairs(auraMap) do
                    if auraID == sid and not _spellToAuraInstance[abilityID] then
                        _spellToAuraInstance[abilityID] = iid
                    end
                end
            end
        end
    end

    -- 4. New aura applications in combat (no orphan to pair with).
    --    Try to identify unmapped IIDs by finding tracked aura spells
    --    that currently lack an instance.  Only attempt when there is
    --    exactly one candidate to avoid mismatches.
    if unmappedIIDs and auraMap then
        for _, iid in ipairs(unmappedIIDs) do
            if not _auraInstanceToSpell[iid] then
                -- Collect tracked aura spell IDs that have no active instance
                local candidates = nil
                local candidateCount = 0
                for _, auraSpellID in pairs(auraMap) do
                    if not _spellToAuraInstance[auraSpellID] then
                        -- Deduplicate (multiple ability IDs can map to same aura)
                        if not candidates or not candidates[auraSpellID] then
                            if not candidates then candidates = {} end
                            candidates[auraSpellID] = true
                            candidateCount = candidateCount + 1
                        end
                    end
                end
                -- Only pair when exactly one candidate — avoid mismatches
                if candidateCount == 1 then
                    local targetSid = next(candidates)
                    _auraInstanceToSpell[iid] = targetSid
                    _spellToAuraInstance[targetSid] = iid
                    -- Create ability aliases
                    for abilityID, auraID in pairs(auraMap) do
                        if auraID == targetSid then
                            _spellToAuraInstance[abilityID] = iid
                        end
                    end
                end
            end
        end
    end
end

local _auraCacheFrame = CreateFrame("Frame")
_auraCacheFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
_auraCacheFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_auraCacheFrame:RegisterUnitEvent("UNIT_AURA", "player", "target")
_auraCacheFrame:SetScript("OnEvent", function(_, event, unit, updateInfo)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Don't wipe — preserve OOC cache (aliases, Bone Shield, etc.).
        -- Just augment with any new aura data from ForEachAura.
        FullRebuildAuraCache(false)
        _inCombatCaching = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        _inCombatCaching = false
        -- OOC: full wipe + rebuild with clean API data
        FullRebuildAuraCache(true)
    elseif event == "UNIT_AURA" then
        PatchAuraCacheFromEvent(updateInfo)
    end
end)

local function RebuildAuraCache()
    if _inCombatCaching then return end
    FullRebuildAuraCache(true)  -- OOC: wipe + fresh rebuild
end

---------------------------------------------------------------------------
-- UPDATE ALL COOLDOWNS
---------------------------------------------------------------------------
function CDMIcons:UpdateAllCooldowns()
    local editMode = Helpers.IsEditModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())

    -- Rebuild aura cache for custom aura/auraBar containers (Composer).
    -- Built-in buff/trackedBar use direct aura lookup instead.
    RebuildAuraCache()

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon._spellEntry
            -- Update cooldown/aura state BEFORE visibility so _auraActive,
            -- _lastDuration, etc. are fresh for Show/Hide decisions.
            -- pcall: errors in cooldown polling (e.g. secret values from
            -- Blizzard frames during combat) must not abort the entire
            -- visibility loop for all icon pools.
            pcall(UpdateIconCooldown, icon)

            -- Per-spell hidden override: always hide regardless of display mode
            local spellOvr = (not editMode) and GetIconSpellOverride(icon) or nil
            local isHiddenOverride = spellOvr and spellOvr.hidden

            if entry then
                -- Visibility based on container type + display mode
                local QUICore = ns.Addon
                local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
                -- Built-in containers at ncdm[key], custom containers at ncdm.containers[key]
                local containerDB = ncdm and (ncdm[entry.viewerType] or (ncdm.containers and ncdm.containers[entry.viewerType]))
                local cType = containerDB and containerDB.containerType
                if not cType then
                    -- Built-in buff and trackedBar are aura containers even without
                    -- an explicit containerType (they predate the Composer).
                    local vt = entry.viewerType
                    cType = (vt == "buff" or vt == "trackedBar") and "aura" or "cooldown"
                end
                local displayMode = containerDB and containerDB.iconDisplayMode or "always"

                if isHiddenOverride then
                    -- Per-spell hidden override: always hide owned entries
                    if icon:IsShown() then icon:Hide() end
                elseif editMode then
                    icon:SetAlpha(1)
                    icon:Show()
                elseif cType == "aura" or cType == "auraBar" then
                    -- Aura containers: visibility depends on display mode + aura state
                    local isActive = icon._auraActive
                    local effectiveMode = displayMode
                    if effectiveMode == "combat" then
                        effectiveMode = InCombatLockdown() and "always" or "active"
                    end

                    if effectiveMode == "always" then
                        local rowOpacity = icon._rowOpacity or 1
                        if isActive then
                            icon:SetAlpha(rowOpacity)
                        else
                            -- Desaturate placeholder when aura is absent
                            icon:SetAlpha(rowOpacity * 0.3)
                            if icon.Icon and icon.Icon.SetDesaturated then
                                icon.Icon:SetDesaturated(true)
                            end
                        end
                        if not icon:IsShown() then icon:Show() end
                    elseif effectiveMode == "active" then
                        if isActive then
                            local rowOpacity = icon._rowOpacity or 1
                            icon:SetAlpha(rowOpacity)
                            if not icon:IsShown() then icon:Show() end
                        else
                            if icon:IsShown() then icon:Hide() end
                        end
                    end

                    -- Clear desaturation when aura is active
                    if isActive and icon.Icon and icon.Icon.SetDesaturated then
                        icon.Icon:SetDesaturated(false)
                    end
                else
                    -- Cooldown containers: visibility depends on display mode
                    local isOnCD = false
                    local dur = icon._lastDuration or 0
                    local start = icon._lastStart or 0
                    if dur > 1.5 and start > 0 then
                        local remaining = (start + dur) - GetTime()
                        if remaining > 0 then
                            isOnCD = true
                        end
                    end
                    -- Also check charge-based cooldowns
                    if not isOnCD and entry.hasCharges then
                        local spellID = entry.overrideSpellID or entry.spellID or entry.id
                        if spellID and C_Spell.GetSpellCharges then
                            local ok, ci = pcall(C_Spell.GetSpellCharges, spellID)
                            if ok and ci then
                                local current = SafeToNumber(ci.currentCharges, nil)
                                local maxC = SafeToNumber(ci.maxCharges, nil)
                                if current and maxC and current < maxC then
                                    isOnCD = true
                                end
                            end
                        end
                    end

                    local effectiveMode = displayMode
                    if effectiveMode == "combat" then
                        effectiveMode = InCombatLockdown() and "always" or "active"
                    end

                    if effectiveMode == "always" then
                        if not icon:IsShown() then icon:Show() end
                    elseif effectiveMode == "active" then
                        if isOnCD then
                            if not icon:IsShown() then icon:Show() end
                        else
                            if icon:IsShown() then icon:Hide() end
                        end
                    end
                end
                SyncCooldownBling(icon)
            end
            SyncCooldownBling(icon)
        end
    end
end

function CDMIcons:UpdateCooldownsForType(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        for _, icon in ipairs(pool) do
            UpdateIconCooldown(icon)
        end
    end
end

function CDMIcons:StartUpdateTicker()
    if updateTicker then return end
    updateTicker = C_Timer.NewTicker(0.5, function()
        self:UpdateAllCooldowns()
        -- Also update owned bars (aura-driven, no Blizzard mirror hooks)
        if ns.CDMBars and ns.CDMBars.UpdateOwnedBars then
            ns.CDMBars:UpdateOwnedBars()
        end
    end)
end

function CDMIcons:StopUpdateTicker()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

---------------------------------------------------------------------------
-- CONFIGURE ICON (public wrapper)
---------------------------------------------------------------------------
CDMIcons.ConfigureIcon = ConfigureIcon
CDMIcons.UpdateIconCooldown = UpdateIconCooldown
CDMIcons.ApplyTexCoord = ApplyTexCoord
CDMIcons._spellToAuraInstance = _spellToAuraInstance  -- exposed for CDMBars DurationObject lookup
CDMIcons.FindActiveAuraChild = FindActiveAuraChild   -- exposed for CDMBars dynamic child lookup
CDMIcons.UpdateIconSecureAttributes = UpdateIconSecureAttributes

---------------------------------------------------------------------------
-- CUSTOM ENTRY MANAGEMENT (backward-compatible API surface)
-- These methods are called by the options panel via ns.CustomCDM
---------------------------------------------------------------------------
function CustomCDM:GetEntryName(entry)
    if not entry then return "Unknown" end
    if entry.type == "macro" then
        return entry.macroName or "Macro"
    end
    if entry.type == "trinket" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            return C_Item.GetItemNameByID(itemID) or "Trinket (Slot " .. tostring(entry.id) .. ")"
        end
        return "Trinket (Slot " .. tostring(entry.id) .. ")"
    end
    if entry.type == "item" then
        return C_Item.GetItemNameByID(entry.id) or "Item #" .. tostring(entry.id)
    end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.id)
    return info and info.name or "Spell #" .. tostring(entry.id)
end

function CustomCDM:AddEntry(trackerKey, entryType, entryID)
    if entryType == "macro" then
        -- entryID is the macro name (string)
        if not entryID or type(entryID) ~= "string" or entryID == "" then return false end
        local macroIndex = GetMacroIndexByName(entryID)
        if not macroIndex or macroIndex == 0 then return false end
    else
        if not entryID or type(entryID) ~= "number" then return false end
    end
    if entryType ~= "spell" and entryType ~= "item" and entryType ~= "trinket" and entryType ~= "macro" then return false end

    local customData = GetCustomData(trackerKey)
    if not customData then return false end
    if not customData.entries then customData.entries = {} end

    -- Duplicate check
    for _, entry in ipairs(customData.entries) do
        if entryType == "macro" then
            if entry.type == "macro" and entry.macroName == entryID then
                return false
            end
        else
            if entry.type == entryType and entry.id == entryID then
                return false
            end
        end
    end

    local newEntry
    if entryType == "macro" then
        newEntry = { macroName = entryID, type = "macro", enabled = true }
    else
        newEntry = { id = entryID, type = entryType, enabled = true }
    end
    customData.entries[#customData.entries + 1] = newEntry

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
    return true
end

function CustomCDM:RemoveEntry(trackerKey, entryIndex)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries then return end
    if entryIndex < 1 or entryIndex > #customData.entries then return end

    table.remove(customData.entries, entryIndex)
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end

function CustomCDM:SetEntryEnabled(trackerKey, entryIndex, enabled)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries or not customData.entries[entryIndex] then return end

    customData.entries[entryIndex].enabled = enabled
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end

function CustomCDM:MoveEntry(trackerKey, fromIndex, direction)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries then return end

    local entries = customData.entries
    local toIndex = fromIndex + direction
    if toIndex < 1 or toIndex > #entries then return end

    entries[fromIndex], entries[toIndex] = entries[toIndex], entries[fromIndex]
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end


-- Legacy compat: GetIcons returns the pool for a viewer name.
-- Returns empty when called from the classic engine's LayoutViewer context
-- (which passes Blizzard viewer names) to prevent the classic engine from
-- repositioning our addon-owned icons onto the Blizzard viewer during combat.
function CustomCDM:GetIcons(viewerName)
    -- Only return icons when asked for addon-owned container names
    -- (internal callers from the owned engine).  The classic engine passes
    -- Blizzard viewer names ("EssentialCooldownViewer", etc.) — return
    -- empty so it doesn't adopt and reposition our icons.
    if viewerName == "QUI_EssentialContainer" then
        return iconPools["essential"] or {}
    elseif viewerName == "QUI_UtilityContainer" then
        return iconPools["utility"] or {}
    end
    return {}
end

function CustomCDM:StartUpdateTicker() CDMIcons:StartUpdateTicker() end
function CustomCDM:StopUpdateTicker() CDMIcons:StopUpdateTicker() end
function CustomCDM:UpdateAllCooldowns() CDMIcons:UpdateAllCooldowns() end

---------------------------------------------------------------------------
-- RANGE INDICATOR
-- Tints CDM icon textures red when the spell/item is out of range,
-- matching action-bar behavior. Uses C_Spell.IsSpellInRange for spells.
-- Polled at 250ms (no "player moved" event) + instant on target change.
---------------------------------------------------------------------------
local RANGE_POLL_INTERVAL = 0.25
local rangePollElapsed = 0

-- Safe wrapper: C_Spell.IsSpellInRange can return secret values in Midnight
local function SafeIsSpellInRange(spellID)
    if not spellID or not C_Spell or not C_Spell.IsSpellInRange then return nil end
    local ok, result = pcall(function()
        local inRange = C_Spell.IsSpellInRange(spellID, "target")
        if inRange == false then return false end
        if inRange == true then return true end
        return nil
    end)
    if not ok then return nil end
    return result
end

-- Safe wrapper: C_Spell.IsSpellUsable can return secret values in Midnight
local function SafeIsSpellUsable(spellID)
    if not spellID or not C_Spell or not C_Spell.IsSpellUsable then return true, false end
    local ok, isUsable, notEnoughMana = pcall(function()
        local usable, noMana = C_Spell.IsSpellUsable(spellID)
        -- Convert potential secret booleans to real booleans
        return usable and true or false, noMana and true or false
    end)
    if not ok then return true, false end  -- Secret value: assume usable
    return isUsable, notEnoughMana
end

-- Reset icon to normal visual state (clear any tinting)
local function ResetIconVisuals(icon)
    icon.Icon:SetVertexColor(1, 1, 1, 1)
    icon._rangeTinted = nil
    icon._usabilityTinted = nil
end

local function UpdateIconVisualState(icon)
    if not icon or not icon._spellEntry then return end
    local entry = icon._spellEntry
    local viewerType = entry.viewerType
    if not viewerType then return end

    local settings = GetTrackerSettings(viewerType)
    if not settings then
        if icon._rangeTinted or icon._usabilityTinted then
            ResetIconVisuals(icon)
        end
        return
    end

    local rangeEnabled = settings.rangeIndicator
    local usabilityEnabled = settings.usabilityIndicator

    -- Nothing enabled — reset and bail
    if not rangeEnabled and not usabilityEnabled then
        if icon._rangeTinted or icon._usabilityTinted then
            ResetIconVisuals(icon)
        end
        return
    end

    -- Skip buff viewer icons
    if viewerType == "buff" then return end

    -- Skip items/trinkets (self-use, no range/usability concept)
    if entry.type == "item" or entry.type == "trinket" then return end

    -- Resolve current spell ID (prefer runtime override for accurate checks)
    local spellID = entry.overrideSpellID or entry.spellID or entry.id
    if C_Spell and C_Spell.GetOverrideSpell then
        local currentOverride = C_Spell.GetOverrideSpell(entry.spellID or entry.id)
        if currentOverride then spellID = currentOverride end
    end
    if not spellID then return end

    ---------------------------------------------------------------------------
    -- Priority 1: Out of range (red tint) — only when target exists + ranged
    ---------------------------------------------------------------------------
    if rangeEnabled and UnitExists("target") then
        local hasRange = true
        if C_Spell.SpellHasRange then
            hasRange = C_Spell.SpellHasRange(spellID)
        end
        if hasRange then
            local inRange = SafeIsSpellInRange(spellID)
            if inRange == false then
                -- Clear usability darkening if switching to range tint
                if icon._usabilityTinted then
                    icon._usabilityTinted = nil
                end
                local c = settings.rangeColor
                local r = c and c[1] or 0.8
                local g = c and c[2] or 0.1
                local b = c and c[3] or 0.1
                local a = c and c[4] or 1
                icon.Icon:SetVertexColor(r, g, b, a)
                icon._rangeTinted = true
                return
            end
        end
    end

    -- If was range-tinted but now in range, clear it
    if icon._rangeTinted then
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon._rangeTinted = nil
    end

    ---------------------------------------------------------------------------
    -- Priority 2: Unusable / resource-starved (darken)
    ---------------------------------------------------------------------------
    if usabilityEnabled then
        local isUsable = SafeIsSpellUsable(spellID)
        if not isUsable then
            -- Clear cooldown desaturation so vertex color darkening is visible
            if icon._cdDesaturated then
                icon.Icon:SetDesaturated(false)
                icon._cdDesaturated = nil
            end
            icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
            icon._usabilityTinted = true
            return
        end
    end

    -- If was usability-tinted but now usable, clear it
    if icon._usabilityTinted then
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon._usabilityTinted = nil
    end
end

function CDMIcons:UpdateAllIconRanges()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            UpdateIconVisualState(icon)
        end
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLING: Update cooldowns on relevant events
---------------------------------------------------------------------------
local cdEventFrame = CreateFrame("Frame")
cdEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
cdEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
cdEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
cdEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
-- UNIT_AURA triggers coalesced icon updates so aura-container icons
-- refresh within 50ms of a buff gain/loss instead of waiting for the
-- 0.5s ticker.  Registered for both player and target (target debuffs
-- like Reaper's Mark need prompt updates too).
cdEventFrame:RegisterUnitEvent("UNIT_AURA", "player", "target")

-- Coalesce rapid cooldown events (SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_CHARGES,
-- BAG_UPDATE_COOLDOWN) into a single UpdateAllCooldowns call per 50ms window.
local CD_COALESCE_WINDOW = 0.05
local cdCoalesceRunning = false

local function FlushCooldownUpdate()
    cdCoalesceRunning = false
    CDMIcons:UpdateAllCooldowns()
    -- Also update owned bars so they respond to aura events within 50ms
    -- instead of waiting for the 0.5s ticker.
    if ns.CDMBars and ns.CDMBars.UpdateOwnedBars then
        ns.CDMBars:UpdateOwnedBars()
    end
end

cdEventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        CDMIcons:UpdateAllIconRanges()
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Trinket slots 13-14: refresh textures and cooldowns immediately
        if arg1 == 13 or arg1 == 14 then
            CDMIcons:UpdateAllCooldowns()
        end
        return
    end
    -- Coalesce cooldown events
    if not cdCoalesceRunning then
        cdCoalesceRunning = true
        C_Timer.After(CD_COALESCE_WINDOW, FlushCooldownUpdate)
    end
end)

-- Visual state polling: 250ms OnUpdate for range + usability checks.
-- Only active when at least one tracker has rangeIndicator or usabilityIndicator.
local function RangePollOnUpdate(self, elapsed)
    rangePollElapsed = rangePollElapsed + elapsed
    if rangePollElapsed < RANGE_POLL_INTERVAL then return end
    rangePollElapsed = 0
    CDMIcons:UpdateAllIconRanges()
end

local rangePollActive = false

--- Call after settings change to start/stop the range poll OnUpdate.
function CDMIcons:SyncRangePoll()
    local db = GetDB()
    local anyEnabled = db
        and ((db.essential and (db.essential.rangeIndicator or db.essential.usabilityIndicator))
          or (db.utility and (db.utility.rangeIndicator or db.utility.usabilityIndicator)))
    if anyEnabled and not rangePollActive then
        rangePollActive = true
        rangePollElapsed = 0
        cdEventFrame:SetScript("OnUpdate", RangePollOnUpdate)
    elseif not anyEnabled and rangePollActive then
        rangePollActive = false
        cdEventFrame:SetScript("OnUpdate", nil)
    end
end

-- Start disabled — SyncRangePoll is called from Refresh/init paths
cdEventFrame:SetScript("OnUpdate", nil)
