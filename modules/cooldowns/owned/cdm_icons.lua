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
local LSM = LibStub("LibSharedMedia-3.0")

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

local function IsSafeNumeric(val)
    if IsSecretValue(val) then return false end
    return type(val) == "number"
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
local recyclePool = {}
local iconCounter = 0
local updateTicker = nil

-- TAINT SAFETY: Blizzard CD adoption state tracked in a weak-keyed table
-- instead of writing _quiIcon/_quiBypass/_quiHooked directly to Blizzard's
-- Cooldown widget. Direct writes taint the frame, causing module-level
-- CooldownViewer state (wasOnGCDLookup, chargeGainedAlertTimes) to become
-- forbidden tables.
local blizzCDState = setmetatable({}, { __mode = "k" })

-- TAINT SAFETY: Blizzard Icon texture hook state tracked in a weak-keyed table.
-- Maps Blizzard child Icon regions → { icon = quiIcon } so the SetTexture hook
-- can mirror texture changes (e.g., Judgment → Hammer of Wrath via Wake of Ashes)
-- to the addon-owned icon without reading restricted frames during combat.
local blizzTexState = setmetatable({}, { __mode = "k" })

-- TAINT SAFETY: Blizzard buff child visibility hook state tracked in a weak-keyed table.
-- Maps Blizzard buff children → { icon = quiIcon, hooked = bool } so Hide/Show hooks
-- can mirror visibility to the addon-owned icon via SetAlpha without polling.
local blizzVisState = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetCustomData(trackerKey)
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
    if entry.type == "item" or entry.type == "trinket" then
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
-- BLIZZARD COOLDOWN ADOPTION
-- Reparent Blizzard viewer children's Cooldown frames onto QUI icons.
-- This gives us a secure CooldownFrame that can render secret values
-- natively (charge recharge, aura durations, etc.), while our icon
-- controls the position and size.
--
-- For charge+aura spells: aura duration shows while active. When the
-- aura expires, the ticker forces charge recharge display.
-- _auraActive flag is set by the SetCooldownFromDurationObject hook
-- using the isAura parameter (a regular boolean from Blizzard's CDM
-- Lua code, NOT a restricted API secret value).
---------------------------------------------------------------------------

-- Force charge recharge display on an adopted CD.
-- Returns true if charges were applied.
local function ForceChargeRecharge(cd, entry)
    if not entry or not entry.hasCharges then return false end
    local sid = entry.overrideSpellID or entry.spellID or entry.id
    if not sid or not C_Spell.GetSpellCharges then return false end
    local chargeInfo = C_Spell.GetSpellCharges(sid)
    if not chargeInfo then return false end
    local state = blizzCDState[cd]
    if state then state.bypass = true end
    pcall(cd.SetCooldown, cd, chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration)
    if state then state.bypass = false end
    return true
end

-- Re-apply QUI swipe styling after Blizzard resets texture/color.
local function ReapplySwipeStyle(cd, icon)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    local CooldownSwipe = QUI.CooldownSwipe
    if CooldownSwipe and CooldownSwipe.ApplyToIcon then
        CooldownSwipe.ApplyToIcon(icon)
    end
end

local function AdoptBlizzCooldown(icon, blizzChild)
    if not blizzChild or not blizzChild.Cooldown then return end
    local blizzCD = blizzChild.Cooldown

    -- Store our addon-created CD so we can restore on release
    icon._addonCooldown = icon.Cooldown
    icon._addonCooldown:Hide()

    -- TAINT SAFETY: Track CD→icon association in a weak-keyed table instead
    -- of writing directly to Blizzard's Cooldown widget.
    -- Set bypass BEFORE reparenting so post-hooks (installed on re-adoption)
    -- don't fight the new anchor target.
    local state = blizzCDState[blizzCD]
    if not state then
        state = {}
        blizzCDState[blizzCD] = state
    end
    state.bypass = true

    -- Reparent Blizzard's secure CooldownFrame onto our icon.
    -- The viewer is alpha=0 (not hidden), so Blizzard's CDM system
    -- continues updating this frame. It renders at our icon's position.
    blizzCD:SetParent(icon)
    blizzCD:ClearAllPoints()
    blizzCD:SetAllPoints(icon)
    blizzCD:SetFrameLevel(icon:GetFrameLevel() + 1)
    blizzCD:Show()

    -- Style it to match QUI defaults
    blizzCD:SetDrawSwipe(true)
    blizzCD:SetHideCountdownNumbers(false)
    blizzCD:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    blizzCD:SetSwipeColor(0, 0, 0, 0.8)

    -- Replace icon.Cooldown so all existing code operates on the secure frame
    icon.Cooldown = blizzCD
    icon._blizzCooldown = blizzCD

    -- Update icon reference and clear bypass
    state.icon = icon
    state.bypass = false

    -- Install hooks (once per CD, survives re-adoption).
    -- SetCooldownFromDurationObject: tracks _auraActive via the isAura param.
    --   When isAura=true, the aura display stands (ticker skips).
    --   When isAura=false (aura expired), forces charge recharge immediately.
    -- SetCooldown: only re-applies QUI styling (doesn't touch aura state).
    if not state.hooked then
        state.hooked = true

        if blizzCD.SetCooldownFromDurationObject then
            hooksecurefunc(blizzCD, "SetCooldownFromDurationObject", function(self, durationObj, isAura)
                local s = blizzCDState[self]
                if not s or s.bypass then return end
                local targetIcon = s.icon
                if not targetIcon or not targetIcon._spellEntry then return end
                local entry = targetIcon._spellEntry

                -- Track aura state for swipe color classification
                -- (swipe.lua uses _auraActive to pick overlay vs swipe color).
                -- Let Blizzard's CooldownFrame handle the actual display.
                -- isAura may be secret in combat; only update when safe
                if not IsSecretValue(isAura) then
                    targetIcon._auraActive = isAura or false
                end
                ReapplySwipeStyle(self, targetIcon)
            end)
        end

        hooksecurefunc(blizzCD, "SetCooldown", function(self, start, duration)
            local s = blizzCDState[self]
            if not s or s.bypass then return end
            local targetIcon = s.icon
            if not targetIcon or not targetIcon._spellEntry then return end

            -- Capture cooldown values from Blizzard's native update so
            -- the desaturation ticker uses hook-driven data instead of
            -- API calls that return secret values during combat.
            local safeStart = SafeToNumber(start, nil)
            local safeDur = SafeToNumber(duration, nil)
            if safeStart then targetIcon._lastStart = safeStart end
            if safeDur then targetIcon._lastDuration = safeDur end
            if safeDur == 0 then
                targetIcon._lastStart = 0
                targetIcon._lastDuration = 0
            end

            ReapplySwipeStyle(self, targetIcon)
        end)

        -- Prevent Blizzard from re-anchoring the adopted CooldownFrame back
        -- to its original parent during combat layout updates.
        -- If Blizzard calls SetAllPoints(blizzChild) or SetPoint to a non-icon
        -- frame, immediately re-anchor to our addon icon.
        hooksecurefunc(blizzCD, "SetAllPoints", function(self, relativeTo)
            local s = blizzCDState[self]
            if not s or s.bypass then return end
            local targetIcon = s.icon
            if targetIcon and relativeTo ~= targetIcon then
                s.bypass = true
                self:ClearAllPoints()
                self:SetAllPoints(targetIcon)
                s.bypass = false
            end
        end)

        hooksecurefunc(blizzCD, "SetPoint", function(self, _, relativeTo)
            local s = blizzCDState[self]
            if not s or s.bypass then return end
            local targetIcon = s.icon
            if targetIcon and relativeTo and relativeTo ~= targetIcon then
                s.bypass = true
                self:ClearAllPoints()
                self:SetAllPoints(targetIcon)
                s.bypass = false
            end
        end)

        hooksecurefunc(blizzCD, "SetParent", function(self, newParent)
            local s = blizzCDState[self]
            if not s or s.bypass then return end
            local targetIcon = s.icon
            if targetIcon and newParent ~= targetIcon then
                s.bypass = true
                self:SetParent(targetIcon)
                self:ClearAllPoints()
                self:SetAllPoints(targetIcon)
                self:SetFrameLevel(targetIcon:GetFrameLevel() + 1)
                s.bypass = false
            end
        end)
    end
end

local function RestoreAddonCooldown(icon)
    if not icon._blizzCooldown then return end

    -- Disconnect hook references before returning (via weak table)
    local state = blizzCDState[icon._blizzCooldown]
    if state then state.icon = nil end

    -- Return Blizzard's CD to its original parent
    local blizzChild = icon._spellEntry and icon._spellEntry._blizzChild
    if blizzChild then
        icon._blizzCooldown:SetParent(blizzChild)
        icon._blizzCooldown:ClearAllPoints()
        icon._blizzCooldown:SetAllPoints(blizzChild)
    end

    -- Restore our addon-created CD (was hidden during adoption)
    if icon._addonCooldown then
        icon.Cooldown = icon._addonCooldown
        icon.Cooldown:Show()
        icon._addonCooldown = nil
    end
    icon._blizzCooldown = nil
    icon._auraActive = nil
end

---------------------------------------------------------------------------
-- BLIZZARD ICON TEXTURE HOOK
-- Mirrors texture changes from Blizzard's hidden viewer Icon to our
-- addon-owned icon via a SetTexture hook.  Spell replacements (e.g.,
-- Judgment → Hammer of Wrath when Wake of Ashes is active) update the
-- Blizzard child's Icon; the hook forwards those changes immediately
-- without reading restricted frame properties during combat.
---------------------------------------------------------------------------
local function HookBlizzTexture(icon, blizzChild)
    if not blizzChild then return end
    local iconRegion = blizzChild.Icon or blizzChild.icon
    if not iconRegion then return end

    -- Update the mapping (may point to a different QUI icon after pool recycle)
    local state = blizzTexState[iconRegion]
    if not state then
        state = {}
        blizzTexState[iconRegion] = state
    end
    state.icon = icon

    -- Install hooks once per Blizzard texture region
    if not state.hooked then
        state.hooked = true
        hooksecurefunc(iconRegion, "SetTexture", function(self, texture)
            local s = blizzTexState[self]
            if not s or not s.icon then return end
            local quiIcon = s.icon
            if quiIcon.Icon and texture then
                quiIcon.Icon:SetTexture(texture)
            end
        end)

        -- Mirror desaturation from Blizzard's icon so our icon reflects
        -- the same visual state without needing API calls in combat.
        hooksecurefunc(iconRegion, "SetDesaturated", function(self, desaturated)
            local s = blizzTexState[self]
            if not s or not s.icon then return end
            local quiIcon = s.icon
            if not quiIcon.Icon then return end
            local entry = quiIcon._spellEntry
            if not entry then return end
            if entry.viewerType == "buff" or (entry.isAura and quiIcon._auraActive) then
                return
            end
            quiIcon.Icon:SetDesaturated(desaturated)
        end)
    end
end

local function UnhookBlizzTexture(icon)
    local entry = icon._spellEntry
    if not entry or not entry._blizzChild then return end
    local iconRegion = entry._blizzChild.Icon or entry._blizzChild.icon
    if not iconRegion then return end
    local state = blizzTexState[iconRegion]
    if state then state.icon = nil end
end

---------------------------------------------------------------------------
-- BLIZZARD BUFF VISIBILITY HOOK
-- Mirrors Blizzard buff child Show/Hide to addon-owned icon alpha.
-- Uses hooksecurefunc (one-time install) so we never call IsShown()
-- during combat — only out-of-combat initial sync.
---------------------------------------------------------------------------
local function HookBlizzVisibility(icon, blizzChild)
    if not blizzChild then return end

    local state = blizzVisState[blizzChild]
    if not state then
        state = {}
        blizzVisState[blizzChild] = state
    end
    state.icon = icon

    -- Sync initial state (safe — BuildIcons runs out of combat only)
    if blizzChild:IsShown() then
        icon:SetAlpha(icon:GetAlpha())  -- keep current alpha
    else
        icon:SetAlpha(0)
    end

    if not state.hooked then
        state.hooked = true
        hooksecurefunc(blizzChild, "Hide", function(self)
            local s = blizzVisState[self]
            if not s or not s.icon then return end
            s.icon:SetAlpha(0)
        end)
        hooksecurefunc(blizzChild, "Show", function(self)
            local s = blizzVisState[self]
            if not s or not s.icon then return end
            s.icon:SetAlpha(1)
        end)
    end
end

local function UnhookBlizzVisibility(icon)
    local entry = icon._spellEntry
    if not entry or not entry._blizzChild then return end
    local state = blizzVisState[entry._blizzChild]
    if state then state.icon = nil end
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

    -- .Border texture (BACKGROUND, sublayer -8, pre-created)
    icon.Border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    icon.Border:Hide()

    -- .DurationText (OVERLAY, sublayer 7)
    icon.DurationText = icon.Cooldown:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.DurationText:SetPoint("CENTER")

    -- .StackText (OVERLAY, sublayer 7)
    icon.StackText = icon:CreateFontString(nil, "OVERLAY", nil, 7)
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
        if spellEntry.viewerType == "buff" and spellEntry._blizzChild then
            -- Buff icons: read the texture Blizzard set on the child.
            -- The spell lookup returns the ability icon which can differ
            -- from the actual buff/aura icon.
            local iconRegion = spellEntry._blizzChild.Icon or spellEntry._blizzChild.icon
            if iconRegion then
                if iconRegion.GetTexture then
                    texID = iconRegion:GetTexture()
                else
                    local tex = iconRegion.Icon or iconRegion.icon or iconRegion.texture or iconRegion.Texture
                    if tex and tex.GetTexture then
                        texID = tex:GetTexture()
                    end
                end
            end
        end
        -- Essential/Utility (and buff fallback): spell/item texture lookup
        if not texID then
            if spellEntry.type then
                texID = GetEntryTexture(spellEntry)
            else
                texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
            end
        end
        if texID then
            icon.Icon:SetTexture(texID)
        end
    end

    -- Tooltip support
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        local entry = self._spellEntry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local sid = entry.overrideSpellID or entry.spellID or (entry.type and entry.id)
        if sid then
            if entry.type == "item" or entry.type == "trinket" then
                pcall(GameTooltip.SetItemByID, GameTooltip, sid)
            else
                pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
            end
        end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    icon:Show()
    return icon
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
    else
        icon.Border:Hide()
        icon:SetHitRectInsets(0, 0, 0, 0)
    end

    -- TexCoord (zoom + aspect ratio crop)
    ApplyTexCoord(icon, rowConfig.zoom or 0, aspectRatio)

    -- Duration text styling
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()

    local durationSize = rowConfig.durationSize or 14
    if durationSize > 0 then
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
    if entry._blizzChild then
        -- Adopted Blizzard CooldownFrame: Blizzard drives the display
        -- natively (aura duration, charge recharge, transitions).
        -- We only track state for swipe color classification.

        -- Track duration + start for swipe classification and desaturation.
        -- Primary source during combat is the SetCooldown hook in
        -- AdoptBlizzCooldown; this API query is a fallback that works
        -- outside combat (secrets → no update).
        local sid = entry.overrideSpellID or entry.spellID or entry.id
        if sid and not (entry.type == "item" or entry.type == "trinket") then
            local cdStart, dur = GetBestSpellCooldown(sid)
            local safeDurVal = SafeToNumber(dur, nil)
            local safeStartVal = SafeToNumber(cdStart, nil)
            if safeDurVal then icon._lastDuration = safeDurVal end
            if safeStartVal then icon._lastStart = safeStartVal end
            if safeDurVal == 0 then
                icon._lastStart = 0
                icon._lastDuration = 0
            end
        end

        -- Re-apply swipe styling (colors) in case state changed
        if icon.Cooldown then
            ReapplySwipeStyle(icon.Cooldown, icon)
        end

        -- NOTE: Texture sync for spell replacements (e.g., Judgment → Hammer of
        -- Wrath) is handled by HookBlizzTexture's SetTexture hook, not polling.
        -- GetTexture() on Blizzard frames returns secret values during combat.
    else
        -- Custom entry: use addon-created CD with our cooldown resolution
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
        elseif entry.type == "item" or entry.type == "trinket" then
            startTime, duration = GetItemCooldown(entry.id)
        else
            startTime, duration = GetBestSpellCooldown(entry.overrideSpellID or entry.spellID or entry.id)

            -- Sync texture for spell overrides (e.g., Judgment → Hammer of Wrath).
            -- Custom spell entries don't have _blizzChild to mirror, so check the
            -- override API directly and update if the active spell changed.
            if C_Spell.GetOverrideSpell and icon.Icon then
                local baseID = entry.spellID or entry.id
                if baseID then
                    local overrideID = C_Spell.GetOverrideSpell(baseID)
                    local texID = GetSpellTexture(overrideID or baseID)
                    if texID and not IsSecretValue(texID) then
                        local curTex = icon.Icon:GetTexture()
                        if texID ~= curTex then
                            icon.Icon:SetTexture(texID)
                        end
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
                local safeStart = SafeToNumber(startTime, nil)
                if safeStart and safeDur and safeDur > 0 then
                    icon.Cooldown:SetCooldown(safeStart, safeDur)
                else
                    pcall(icon.Cooldown.SetCooldown, icon.Cooldown, startTime, duration)
                end
            else
                icon.Cooldown:Clear()
            end
        end
    end

    -- Mirror charge/stack/resource text from Blizzard's native FontStrings.
    -- Check ChargeCount first — secondary resources like DH Soul Fragments
    -- use ChargeCount without registering via C_Spell.GetSpellCharges.
    -- Only use ChargeCount when Blizzard is actually showing it (IsShown);
    -- spells like Wraith Walk have ChargeCount with spurious text (alpha=1)
    -- but Blizzard keeps the frame hidden (shown=false).
    -- IsShown() may return a secret boolean in combat but we only write to
    -- addon-owned StackText so taint spread is harmless.
    -- Fall through to Applications for aura stacks if ChargeCount is hidden.
    if entry._blizzChild then
        local shown = false
        local chargeFrame = entry._blizzChild.ChargeCount
        local appFrame = entry._blizzChild.Applications

        if chargeFrame and chargeFrame.Current then
            if SafeValue(chargeFrame:IsShown(), false) then
               icon.StackText:SetText(chargeFrame.Current:GetText())
               icon.StackText:Show()
               shown = true
            end
        end
        if not shown then
            if appFrame and appFrame.Applications then
                if SafeValue(appFrame:IsShown(), false) then
                   icon.StackText:SetText(appFrame.Applications:GetText())
                   icon.StackText:Show()
                   shown = true
                end
            end
        end
        if not shown then
            icon.StackText:SetText("")
            icon.StackText:Hide()
        end
    else
        icon.StackText:SetText("")
        icon.StackText:Hide()
    end

    -- Desaturation for _blizzChild entries is driven entirely by the
    -- SetDesaturated hook in HookBlizzTexture — Blizzard's CooldownViewer
    -- calls RefreshIconDesaturation natively, and the hook mirrors that
    -- state onto our icon.  The ticker only handles custom entries (macros,
    -- manually-added spells) that have no Blizzard source to mirror.
    if icon.Icon and icon.Icon.SetDesaturated and not entry._blizzChild then
        local viewerType = entry.viewerType

        -- Skip buff viewer icons and aura-active icons (they show buff timers)
        if viewerType ~= "buff" and not icon._auraActive and not icon._rangeTinted and not icon._usabilityTinted then
            local dur = icon._lastDuration or 0
            local start = icon._lastStart or 0

            local ok, shouldDesat = pcall(function()
                if dur > 1.5 and start > 0 then
                    local remaining = (start + dur) - GetTime()
                    if remaining > 0 then
                        local sid = entry.overrideSpellID or entry.spellID or entry.id
                        if sid and C_Spell.GetSpellCharges then
                            local chargeInfo = C_Spell.GetSpellCharges(sid)
                            if chargeInfo and chargeInfo.currentCharges > 0 then
                                return false
                            end
                        end
                        return true
                    end
                end
                return false
            end)

            if ok then
                if shouldDesat then
                    icon.Icon:SetDesaturated(true)
                    icon._cdDesaturated = true
                else
                    icon.Icon:SetDesaturated(false)
                    icon._cdDesaturated = nil
                end
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

        -- Update texture
        local texID
        if spellEntry.viewerType == "buff" and spellEntry._blizzChild then
            local iconRegion = spellEntry._blizzChild.Icon or spellEntry._blizzChild.icon
            if iconRegion then
                if iconRegion.GetTexture then
                    texID = iconRegion:GetTexture()
                else
                    local tex = iconRegion.Icon or iconRegion.icon or iconRegion.texture or iconRegion.Texture
                    if tex and tex.GetTexture then
                        texID = tex:GetTexture()
                    end
                end
            end
        end
        if not texID then
            if spellEntry.type then
                texID = GetEntryTexture(spellEntry)
            else
                texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
            end
        end
        if texID and icon.Icon then
            icon.Icon:SetTexture(texID)
        end
        -- Ensure clean visual state for recycled icon
        if icon.Icon then
            icon.Icon:SetDesaturated(false)
        end

        if icon.Cooldown then
            icon.Cooldown:Clear()
        end
        icon.StackText:SetText("")
        icon.StackText:Hide()
        icon:Show()
        return icon
    end
    return CreateIcon(parent, spellEntry)
end

function CDMIcons:ReleaseIcon(icon)
    if not icon then return end
    -- Disconnect hooks before clearing _spellEntry (needs blizzChild ref)
    RestoreAddonCooldown(icon)
    UnhookBlizzTexture(icon)
    UnhookBlizzVisibility(icon)
    icon:Hide()
    icon:ClearAllPoints()
    icon._spellEntry = nil
    icon._rangeTinted = nil
    icon._usabilityTinted = nil
    icon._cdDesaturated = nil
    icon._lastStart = nil
    if icon.Icon then
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon.Icon:SetDesaturated(false)
    end
    if icon.Cooldown then
        icon.Cooldown:Clear()
    end
    icon.StackText:SetText("")
    icon.Border:Hide()

    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        icon:SetParent(UIParent)
        recyclePool[#recyclePool + 1] = icon
    end
end

function CDMIcons:GetIconPool(viewerType)
    return iconPools[viewerType] or {}
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

function CDMIcons:SetPool(viewerType, pool)
    iconPools[viewerType] = pool or {}
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
                    elseif entry.type == "item" or entry.type == "trinket" then
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

    -- Adopt Blizzard viewer children's CooldownFrames and texture hooks onto
    -- QUI icons.  Cooldown adoption gives us secure frames that render secret
    -- values natively.  Texture hooks mirror spell-replacement icon changes
    -- (e.g., Judgment → Hammer of Wrath) without polling restricted frames.
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry and entry._blizzChild then
            AdoptBlizzCooldown(icon, entry._blizzChild)
            HookBlizzTexture(icon, entry._blizzChild)
            -- Buff icons are always auras — initialize _auraActive so the
            -- swipe module classifies them correctly before the
            -- SetCooldownFromDurationObject hook fires.
            if entry.viewerType == "buff" then
                icon._auraActive = true
                HookBlizzVisibility(icon, entry._blizzChild)
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
-- UPDATE ALL COOLDOWNS
---------------------------------------------------------------------------
function CDMIcons:UpdateAllCooldowns()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            -- Sync non-buff icon visibility with Blizzard child.
            -- Buff icons use hook-based approach (HookBlizzVisibility).
            local entry = icon._spellEntry
            if entry and entry._blizzChild and entry.viewerType ~= "buff" then
                local blizzShown = entry._blizzChild:IsShown()
                local iconShown = icon:IsShown()
                if blizzShown and not iconShown then
                    icon:Show()
                elseif not blizzShown and iconShown then
                    icon:Hide()
                end
            end
            UpdateIconCooldown(icon)
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

---------------------------------------------------------------------------
-- CUSTOM ENTRY MANAGEMENT (backward-compatible API surface)
-- These methods are called by the options panel via ns.CustomCDM
---------------------------------------------------------------------------
function CustomCDM:GetEntryName(entry)
    if not entry then return "Unknown" end
    if entry.type == "macro" then
        return entry.macroName or "Macro"
    end
    if entry.type == "item" or entry.type == "trinket" then
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

function CustomCDM:TransferEntry(fromTrackerKey, entryIndex, toTrackerKey)
    if fromTrackerKey == toTrackerKey then return false end

    local fromData = GetCustomData(fromTrackerKey)
    if not fromData or not fromData.entries then return false end
    if entryIndex < 1 or entryIndex > #fromData.entries then return false end

    local toData = GetCustomData(toTrackerKey)
    if not toData then return false end
    if not toData.entries then toData.entries = {} end

    local entry = fromData.entries[entryIndex]

    -- Duplicate check in destination
    for _, existing in ipairs(toData.entries) do
        if existing.type == entry.type and existing.id == entry.id then
            return false
        end
    end

    entry.position = nil
    toData.entries[#toData.entries + 1] = entry
    table.remove(fromData.entries, entryIndex)

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
    return true
end

function CustomCDM:SetEntryPosition(trackerKey, entryIndex, position)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries or not customData.entries[entryIndex] then return end

    if position == nil or position == 0 or position == "" then
        customData.entries[entryIndex].position = nil
    else
        local num = tonumber(position)
        if num then
            customData.entries[entryIndex].position = math.max(1, math.floor(num))
        else
            customData.entries[entryIndex].position = nil
        end
    end

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

-- Legacy compat: RebuildIcons (no-op, handled by BuildIcons in containers)
function CustomCDM:RebuildIcons() end
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
    if not viewerType or viewerType == "buff" then return end

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
    if UnitExists("target") then
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
                local settings = GetTrackerSettings(viewerType)
                local c = settings and settings.rangeColor
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
    -- Priority 2: Unusable / resource-starved (darken + desaturate)
    ---------------------------------------------------------------------------
    local isUsable, insufficientPower
    if C_Spell and C_Spell.IsSpellUsable then
        isUsable, insufficientPower = C_Spell.IsSpellUsable(spellID)
    end

    -- Try to evaluate usability (works when values aren't secret)
    local ok, notUsable = pcall(function()
        if not isUsable then return true end
        -- C_Spell.IsSpellUsable returns true for charge spells even at 0 charges.
        -- Check charges explicitly: 0 charges remaining = not usable.
        if entry.hasCharges and C_Spell.GetSpellCharges then
            local chargeInfo = C_Spell.GetSpellCharges(spellID)
            if chargeInfo and chargeInfo.currentCharges == 0 then
                return true
            end
        end
        return false
    end)
    if ok then
        -- Clean values: full visual logic
        if notUsable then
            -- Clear cooldown desaturation so vertex color darkening is visible
            if icon._cdDesaturated then
                icon.Icon:SetDesaturated(false)
                icon._cdDesaturated = nil
            end
            icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
            icon._usabilityTinted = true
            return
        end
    elseif insufficientPower ~= nil and not icon._cdDesaturated then
        -- Secret values (combat): pass raw insufficientPower to SetDesaturated.
        -- insufficientPower is already correct polarity (true = can't cast).
        -- Gate on not _cdDesaturated to avoid clearing cooldown desaturation
        -- when the spell has enough resources but is on CD.
        icon.Icon:SetDesaturated(insufficientPower)
        return
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

cdEventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        CDMIcons:UpdateAllIconRanges()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Trinket slots 13-14: refresh textures and cooldowns
        if arg1 == 13 or arg1 == 14 then
            CDMIcons:UpdateAllCooldowns()
        end
    else
        CDMIcons:UpdateAllCooldowns()
    end
end)

-- Visual state polling: 250ms OnUpdate for range + usability checks.
-- Always on for owned engine icons.
cdEventFrame:SetScript("OnUpdate", function(self, elapsed)
    rangePollElapsed = rangePollElapsed + elapsed
    if rangePollElapsed < RANGE_POLL_INTERVAL then return end
    rangePollElapsed = 0
    CDMIcons:UpdateAllIconRanges()
end)
