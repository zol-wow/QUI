-- cdm_icon_factory.lua
-- Icon pool lifecycle and the UpdateIconCooldown driver for the QUI CDM
-- owned engine. Frame writes happen here (and in cdm_icons.lua's view layer);
-- this file is allowed to call frame:Set*. It depends on cdm_resolvers.lua
-- for pure resolution and tick-cache reads.

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local Resolvers = ns.CDMResolvers
local CDMIcons = ns.CDMIcons

local CDMIconFactory = {}
ns.CDMIconFactory = CDMIconFactory

---------------------------------------------------------------------------
-- LOCAL UPVALUE ALIASES
---------------------------------------------------------------------------
local GetGeneralFont        = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local SafeValue             = Helpers.SafeValue
local SafeToNumber          = Helpers.SafeToNumber
local IsSecretValue         = Helpers.IsSecretValue
local GetEntryTexture       = Resolvers.GetEntryTexture
local GetSpellTexture       = Resolvers.GetSpellTexture
-- Tick-cache reads used by UpdateIconCooldown driver
local TickCacheGetCharges        = Resolvers.TickCacheGetCharges
local TickCacheGetCooldown       = Resolvers.TickCacheGetCooldown
local TickCacheGetOverrideSpell  = Resolvers.TickCacheGetOverrideSpell
local TickCacheGetDisplayCount   = Resolvers.TickCacheGetDisplayCount
-- Pure resolvers used by UpdateIconCooldown driver
local ResolveAuraStateForIcon    = Resolvers.ResolveAuraStateForIcon
local HasRealCooldownState       = Resolvers.HasRealCooldownState
local ResolveMacro               = Resolvers.ResolveMacro
local IsAuraEntry                = Resolvers.IsAuraEntry
-- Cooldown getters + entry helpers from cdm_icons.lua (local functions there;
-- imported via CDMIcons shims so the factory never calls bare globals).
local GetBestSpellCooldown  = CDMIcons.GetBestSpellCooldown
local GetItemCooldown       = CDMIcons.GetItemCooldown
local GetSlotCooldown       = CDMIcons.GetSlotCooldown
local IsTotemSlotEntry      = CDMIcons.IsTotemSlotEntry

local InCombatLockdown = InCombatLockdown
local CreateFrame      = CreateFrame
local type             = type
local pcall            = pcall

---------------------------------------------------------------------------
-- CONSTANTS (mirrors cdm_icons.lua; both refer to the same design values)
---------------------------------------------------------------------------
local DEFAULT_ICON_SIZE      = 39
local MAX_RECYCLE_POOL_SIZE  = 20
local GCD_MAX_DURATION       = 1.75

---------------------------------------------------------------------------
-- POOL STATE
---------------------------------------------------------------------------
local iconPools = {
    essential = {},
    utility   = {},
    buff      = {},
}
-- Phase G: Pools for custom containers are created dynamically via EnsurePool().
-- Phase G: Pools for custom containers are created dynamically via EnsurePool().
local recyclePool = {}
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_iconRecyclePool", tbl = recyclePool }
    -- iconPools is a multi-key map of arrays; count across every sub-pool
    -- (incl. dynamically created Composer pools) so retention growth surfaces.
    mp[#mp + 1] = { name = "CDM_iconPools", fn = function()
        local count, deep = 0, 0
        for _, pool in pairs(iconPools) do
            count = count + 1
            if type(pool) == "table" then
                for _ in pairs(pool) do deep = deep + 1 end
            end
        end
        return count, deep
    end }
end
local iconCounter = 0

-- Expose pool tables so cdm_icons.lua can alias them as upvalues
-- (same table object — not a copy).
CDMIconFactory._iconPools   = iconPools
CDMIconFactory._recyclePool = recyclePool

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
    icon.Cooldown:EnableMouse(false)

    -- .TextOverlay (sits above the CooldownFrame so text is never behind the swipe)
    icon.TextOverlay = CreateFrame("Frame", nil, icon)
    icon.TextOverlay:SetAllPoints(icon)
    icon.TextOverlay:SetFrameLevel(icon.Cooldown:GetFrameLevel() + 2)
    icon.TextOverlay:EnableMouse(false)

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
    if ns.HookFrameForMouseover then
        ns.HookFrameForMouseover(icon)
    end

    -- Set texture
    if spellEntry then
        local texID
        if spellEntry.type then
            texID = GetEntryTexture(spellEntry)
        else
            texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
        end
        -- Aura entries: try the child's linkedSpellIDs for the actual buff
        -- icon (e.g., Roll the Bones → Broadside). The tick update also
        -- resolves this, but setting it at init avoids a 1-frame flash.
        if spellEntry.isAura and spellEntry._blizzChild then
            local ci = spellEntry._blizzChild.cooldownInfo
            if ci and ci.linkedSpellIDs then
                local lsid = SafeValue(ci.linkedSpellIDs[1], nil)
                if lsid and lsid > 0 then
                    local linkedTex = GetSpellTexture(lsid)
                    if linkedTex then texID = linkedTex end
                end
            end
        end
        if texID then
            icon.Icon:SetTexture(texID)
            -- Only lock texture for cooldown entries — aura icons rely on
            -- the tick update + Blizzard texture hook for dynamic changes.
            if not spellEntry.isAura then
                icon._desiredTexture = texID
            end
        end
        CDMIcons.UpdateIconProfessionQuality(icon)
    end

    -- Tooltip support
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
        local tooltipProvider = ns.TooltipProvider
        if tooltipProvider then
            if tooltipProvider.IsOwnerFadedOut and tooltipProvider:IsOwnerFadedOut(self) then
                pcall(GameTooltip.Hide, GameTooltip)
                return
            end
            local tooltipContext = self._quiTooltipContext
                or self.__quiTooltipContext
                or (self.__customTrackerIcon and "customTrackers")
                or "cdm"
            if tooltipProvider.ShouldShowTooltip and not tooltipProvider:ShouldShowTooltip(tooltipContext) then
                pcall(GameTooltip.Hide, GameTooltip)
                return
            end
        end
        local entry = self._spellEntry
        if not entry then return end
        local tooltipSettings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.tooltip
        if (not tooltipProvider) and tooltipSettings and tooltipSettings.hideInCombat and InCombatLockdown() then return end
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
        -- Aura entries: use the Blizzard child's live GetSpellID()
        -- which dynamically tracks the active buff (e.g. Roll the
        -- Bones cycling between Broadside/One of a Kind/etc.).
        -- Non-aura entries: use _runtimeSpellID (live override).
        -- Both may be secret in combat — pass directly to C-side
        -- SetSpellByID which handles secrets natively.
        local sid
        if entry.isAura and entry._blizzChild and entry._blizzChild.GetSpellID then
            local ok, childSid = pcall(entry._blizzChild.GetSpellID, entry._blizzChild)
            if ok and childSid then sid = childSid end
        end
        if not sid then
            sid = self._runtimeSpellID
        end
        if not sid then
            sid = ns.CDMSpellData:ResolveDisplaySpellID(entry)
        end
        if sid then
            if entry.type == "trinket" or entry.type == "slot" then
                local itemID = entry.itemID or GetInventoryItemID("player", entry.id)
                if itemID then
                    pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
                end
            elseif entry.type == "item" then
                pcall(GameTooltip.SetItemByID, GameTooltip, entry.id)
            else
                pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
            end
        end
        -- Append a source-spec line for entries migrated from a legacy
        -- spec-specific bar so the user can see at a glance where the
        -- entry came from (e.g. "Source: Discipline Priest"). Resolver
        -- writes _sourceSpecID at migration time.
        local srcSpecID = entry._sourceSpecID
        if type(srcSpecID) == "number" and GetSpecializationInfoByID then
            local _, specName, _, _, _, classToken = GetSpecializationInfoByID(srcSpecID)
            if specName then
                local label = classToken and ("%s %s"):format(specName, classToken) or specName
                pcall(GameTooltip.AddLine, GameTooltip, ("Source: %s"):format(label), 0.75, 0.85, 1, true)
            end
        end
        pcall(GameTooltip.Show, GameTooltip)
    end)
    icon:SetScript("OnLeave", function()
        pcall(GameTooltip.Hide, GameTooltip)
    end)

    icon:Hide()
    return icon
end

---------------------------------------------------------------------------
-- ICON POOL LIFECYCLE
---------------------------------------------------------------------------
function CDMIconFactory:AcquireIcon(parent, spellEntry)
    local icon = table.remove(recyclePool)
    if icon then
        CDMIcons.CancelCooldownExpiryRefresh(icon)
        icon:SetParent(parent)
        icon:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
        icon._spellEntry = spellEntry
        icon._isQUICDMIcon = true
        icon._lastStart = nil
        icon._lastDuration = nil
        icon._isOnGCD = nil
        icon._isOnGCDTrustedAt = nil
        icon._showingGCDSwipe = nil
        icon._showingRealCooldownSwipe = nil
        icon._wasShowingGCDSwipe = nil
        icon._lastAuraDurObj = nil
        icon._lastAuraSourceID = nil
        icon._hasCooldownActive = nil
        icon._hasRealCooldownActive = nil
        icon._resolvedCooldownMode = nil
        icon._isTotemInstance = nil
        icon._totemSlot = spellEntry and spellEntry._totemSlot or nil
        icon._totemIconCache = nil
        icon._pendingTotemSlotRefresh = nil
        icon._customBarActive = nil
        icon._customBarActiveType = nil
        icon._customBarActiveStart = nil
        icon._customBarActiveDuration = nil
        CDMIcons.StopCustomBarActiveGlow(icon)
        CDMIcons.ChargeDebug(spellEntry and spellEntry.name, "ACQUIRE", "reused", "viewerType=", spellEntry and spellEntry.viewerType)

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
                -- Only lock texture for cooldown entries — aura icons rely on
                -- the Blizzard texture hook for the correct aura icon.
                icon._desiredTexture = (not spellEntry.isAura) and texID or nil
            else
                -- Clear stale texture from previous owner to prevent
                -- recycled icons showing the wrong spell/item icon.
                icon.Icon:SetTexture(nil)
                icon._desiredTexture = nil
            end
            icon.Icon:SetDesaturated(false)
        end
        CDMIcons.UpdateIconProfessionQuality(icon)

        if icon.Cooldown then
            icon.Cooldown:Clear()
        end
        icon.StackText:SetText("")
        icon.StackText:Hide()
        -- Update click-to-cast secure attributes for recycled icons
        if spellEntry.viewerType ~= "buff" then
            CDMIcons.UpdateIconSecureAttributes(icon, spellEntry, spellEntry.viewerType)
        end
        icon:Hide()
        -- Notify rotation helper that an icon was assigned a spell
        if ns._onIconAssigned then pcall(ns._onIconAssigned, icon) end
        return icon
    end
    local newIcon = CreateIcon(parent, spellEntry)
    CDMIcons.ChargeDebug(spellEntry and spellEntry.name, "ACQUIRE", "new", "viewerType=", spellEntry and spellEntry.viewerType)
    -- Update click-to-cast secure attributes for new icons
    if spellEntry.viewerType ~= "buff" then
        CDMIcons.UpdateIconSecureAttributes(newIcon, spellEntry, spellEntry.viewerType)
    end
    -- Notify rotation helper that an icon was assigned a spell
    if ns._onIconAssigned then pcall(ns._onIconAssigned, newIcon) end
    return newIcon
end

function CDMIconFactory:ReleaseIcon(icon)
    if not icon then return end
    if _G.QUI_CDM_CHARGE_DEBUG then
        CDMIcons.ChargeDebug(icon._spellEntry and icon._spellEntry.name, "RELEASE",
            "viewerType=", icon._spellEntry and icon._spellEntry.viewerType,
            "shown=", icon.IsShown and icon:IsShown())
    end
    CDMIcons.CancelCooldownExpiryRefresh(icon)
    -- Disconnect hooks before clearing _spellEntry (needs blizzChild ref)
    CDMIcons.UnmirrorBlizzCooldown(icon)
    CDMIcons.UnhookBlizzTexture(icon)
    CDMIcons.UnhookBlizzStackText(icon)
    if ns._OwnedGlows and ns._OwnedGlows.ClearPandemicState then
        ns._OwnedGlows.ClearPandemicState(icon)
    end
    -- The keybind FontString and rotation-helper overlay are parented to the
    -- icon and travel with it through the shared recycle pool. Clear them so
    -- a recycled icon doesn't bring a previous viewer's keybind text into a
    -- container whose Show Keybinds is off (or which never paints keybinds).
    if _G.QUI_ClearKeybindIconState then
        _G.QUI_ClearKeybindIconState(icon)
    end
    icon:Hide()
    icon:ClearAllPoints()
    icon._spellEntry = nil
    icon._rangeTinted = nil
    icon._usabilityTinted = nil
    icon._cdDesaturated = nil
    icon._spellOverrideDesaturate = nil
    icon._desaturateIgnoreAura = nil
    icon._lastStart = nil
    icon._lastDuration = nil
    icon._isOnGCD = nil
    icon._isOnGCDTrustedAt = nil
    icon._showingGCDSwipe = nil
    icon._showingRealCooldownSwipe = nil
    icon._wasShowingGCDSwipe = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
    icon._hasCooldownActive = nil
    icon._hasRealCooldownActive = nil
    icon._resolvedCooldownMode = nil
    icon._isTotemInstance = nil
    icon._totemSlot = nil
    icon._totemIconCache = nil
    icon._pendingTotemSlotRefresh = nil
    icon._lastLayoutFilterHidden = nil
    icon._customBarActive = nil
    icon._customBarActiveType = nil
    icon._customBarActiveStart = nil
    icon._customBarActiveDuration = nil
    icon._rowConfig = nil
    icon._quiTooltipContext = nil
    icon.__quiTooltipContext = nil
    icon.__customTrackerIcon = nil
    CDMIcons.StopCustomBarActiveGlow(icon)
    -- Reset grey-out child alpha (set by greyOutInactive/greyOutInactiveBuffs)
    icon._greyType = nil
    if icon._greyedOut then
        icon._greyedOut = nil
        if icon.Icon then icon.Icon:SetAlpha(1) end
        if icon.Cooldown then icon.Cooldown:SetAlpha(1) end
        if icon.Border then icon.Border:SetAlpha(1) end
        if icon.DurationText then icon.DurationText:SetAlpha(1) end
        if icon.StackText then icon.StackText:SetAlpha(1) end
    end
    if icon.Icon then
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon.Icon:SetDesaturated(false)
    end
    if icon.Cooldown then
        icon.Cooldown:Clear()
    end
    icon.StackText:SetText("")
    icon.StackText:Hide()
    icon.Border:Hide()
    CDMIcons.ClearIconProfessionQuality(icon)

    -- Clear click-to-cast secure button
    if icon.clickButton then
        if not InCombatLockdown() then
            CDMIcons.ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
    end
    icon._pendingSecureUpdate = nil

    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        icon:SetParent(UIParent)
        recyclePool[#recyclePool + 1] = icon
    end
end


-- BLIZZ MIRROR

-- Keep CooldownFrame ready-flash ("bling") hidden when icon is effectively invisible.
-- This prevents GCD-ready glow from leaking through when row/container alpha is 0.
local function SyncCooldownBling(icon)
    if not icon or not icon.Cooldown or not icon.Cooldown.SetDrawBling then return end
    local effectiveAlpha = SafeToNumber((icon.GetEffectiveAlpha and icon:GetEffectiveAlpha()) or icon:GetAlpha(), 1)
    local shouldDrawBling = (effectiveAlpha > 0.001) and icon:IsShown()
    if icon._drawBlingEnabled ~= shouldDrawBling then
        icon._drawBlingEnabled = shouldDrawBling
        icon.Cooldown:SetDrawBling(shouldDrawBling)
    end
end

---------------------------------------------------------------------------
-- BLIZZARD COOLDOWN BINDING
-- We never reparent Blizzard's CooldownFrame (which would taint it and
-- cause isActive / wasOnGCDLookup errors in Blizzard_CooldownViewer).
-- Instead we leave the Blizzard CooldownFrame untouched and bind our
-- addon-owned CooldownFrame to the spell's secret-safe DurationObject
-- via SetCooldownFromDurationObject. Item-only cooldowns use guarded
-- numeric fallback inside ApplyResolvedCooldown. Refresh triggers come from
-- events (UNIT_SPELLCAST_SUCCEEDED, AuraEvents, SPELL_UPDATE_COOLDOWN,
-- BAG_UPDATE_COOLDOWN).
---------------------------------------------------------------------------
local function MirrorBlizzCooldown(icon, blizzChild)
    if not blizzChild or not blizzChild.Cooldown then return end
    local blizzCD = blizzChild.Cooldown

    -- The addon-created CooldownFrame stays as icon.Cooldown (the display).
    -- Style it to match QUI defaults.
    local addonCD = icon.Cooldown
    addonCD:SetDrawSwipe(true)
    addonCD:SetHideCountdownNumbers(false)
    addonCD:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    addonCD:SetSwipeColor(0, 0, 0, 0.8)
    addonCD:Show()

    -- Track the Blizzard CD reference for cleanup
    icon._blizzCooldown = blizzCD

    -- Initial cooldown sync: on reload, the Blizzard CD may already have
    -- an active cooldown running. Forward its current state to the addon CD
    -- so swipe/countdown display correctly without waiting for the next update.
    if addonCD and CDMIcons.ChildStillBoundToIcon(icon, blizzChild) then
        CDMIcons.ApplyResolvedCooldown(icon)
        CDMIcons.ReapplySwipeStyle(addonCD, icon)
    end
end

CDMIconFactory.SyncCooldownBling = SyncCooldownBling
CDMIconFactory.MirrorBlizzCooldown = MirrorBlizzCooldown


-- DRIVER

local function UpdateIconCooldown(icon)
    if not icon or not icon._spellEntry then return end
    local entry = icon._spellEntry

    -- Runtime override: resolve from the BASE spell each tick so dynamic
    -- transforms (Glacial Spike ↔ Frostbolt, Mind Blast → Void Blast)
    -- are always current.  Shared across all paths in this function.
    local _runtimeSid = entry.spellID or entry.overrideSpellID or entry.id
    if _runtimeSid and C_Spell.GetOverrideSpell then
        local ovId = TickCacheGetOverrideSpell(_runtimeSid)
        if ovId then _runtimeSid = ovId end
    end
    -- Stash live override on icon so tooltip/display can pass it
    -- directly to C-side functions (handles secret values natively).
    icon._runtimeSpellID = _runtimeSid

        -- Aura-driven update: delegates to shared CDMSpellData:ResolveAuraState().
        -- Icons apply result to swipe/stacks display on CooldownFrame.
        do
            if IsAuraEntry(entry) then
                local auraSpellID = _runtimeSid
                if not auraSpellID then
                    return
                end

                local r = ResolveAuraStateForIcon(icon, entry, auraSpellID)
                if not r then
                    return
                end
                    local isTotemSlot = IsTotemSlotEntry(entry)
                    icon._totemSlot = entry._totemSlot or nil
                    if r.blizzChild and r.blizzChild ~= entry._blizzChild then
                        -- Blizzard child changed — reconnect mirror/texture/stack
                        -- hooks to the new child. Old hooks on the previous child
                        -- self-disable via stale mapping guards in each callback.
                        entry._blizzChild = r.blizzChild
                        if not isTotemSlot then
                            MirrorBlizzCooldown(icon, r.blizzChild)
                            CDMIcons.HookBlizzTexture(icon, r.blizzChild)
                            CDMIcons.HookBlizzStackText(icon, r.blizzChild)
                        end
                    end
                    -- Cache bar-viewer counterpart so the next tick passes it
                    -- through without rescanning BuffBarCooldownViewer.
                    entry._blizzBarChild = r.blizzBarChild

                    if r.isActive then
                        ApplyAuraStateToIcon(icon, entry, auraSpellID, r)

                        -- Stacks: forward r.stacks directly to C-side where
                        -- possible. Blizzard aura APIs can return secret or
                        -- otherwise non-finite values in combat, so keep stack
                        -- formatting behind pcall and collapse invalid counts
                        -- to empty text.
                        local _auraHookActive = (not r.isTotemInstance) and CDMIcons.IsHookStackActive(entry, icon)
                        if not _auraHookActive then
                            if r.isTotemInstance then
                                CDMIcons.ClearIconStackText(icon)
                                CDMIcons.ClearAuraHookStackText(entry, icon)
                            else
                                CDMIcons.ApplyAuraStackText(icon, r.stacks, entry.hasCharges, InCombatLockdown(), r.stackSource)
                            end
                        end

                        -- Keep texture showing the active aura buff.
                        -- Totem instances use slot payloads from GetTotemInfo:
                        -- active state comes from GetTotemDuration(slot),
                        -- display icon comes from the same slot.
                        if icon.Icon then
                            local mirrored = false
                            if r.isTotemInstance then
                                if r.totemIcon then
                                    icon._totemIconCache = r.totemIcon
                                end
                                local totemTex = r.totemIcon or icon._totemIconCache
                                if totemTex then
                                    icon._desiredTexture = nil
                                    pcall(icon.Icon.SetTexture, icon.Icon, totemTex)
                                    icon._lastTexture = totemTex
                                    mirrored = true
                                end
                            elseif entry._blizzChild then
                                local tex = CDMIcons.GetChildIconTexture(entry._blizzChild)
                                if tex then
                                    pcall(icon.Icon.SetTexture, icon.Icon, tex)
                                    mirrored = true
                                end
                            end
                            -- Fallback: auraData.icon then base aura spell
                            -- texture (used when child Icon region isn't
                            -- yet resolvable, e.g. first show).
                            if not mirrored and not r.isTotemInstance then
                                local texID
                                if r.auraData then
                                    local aIcon = SafeValue(r.auraData.icon, nil)
                                    if aIcon and aIcon ~= 0 then texID = aIcon end
                                end
                                if not texID then
                                    texID = GetSpellTexture(auraSpellID)
                                end
                                if texID and texID ~= icon._lastTexture then
                                    icon.Icon:SetTexture(texID)
                                    icon._lastTexture = texID
                                end
                            end
                        end

                        ApplyResolvedCooldown(icon)
                        ReapplySwipeStyle(icon.Cooldown, icon)
                        return  -- Aura path complete
                    else
                        local wasAuraActive = icon._auraActive
                        ApplyAuraStateToIcon(icon, entry, auraSpellID, r)

                        -- Only clear our StackText overlay if Blizzard's
                        -- native stack frames aren't actively displaying.
                        if r.isTotemInstance or not CDMIcons.IsHookStackActive(entry, icon) then
                            CDMIcons.ClearIconStackText(icon)
                        end
                        CDMIcons.ClearAuraHookStackText(entry, icon)
                        -- Aura→CD transition: re-resolve so the resolver picks
                        -- up the underlying spell CD now that _auraActive is
                        -- cleared. One-shot on transition; no per-tick cost.
                        if wasAuraActive then
                            ApplyResolvedCooldown(icon)
                        end
                        return  -- Aura path complete
                    end
            end
        end

        -- Custom entry: use addon-created CD with our cooldown resolution
        local startTime, duration, durObj, apiIsActive, blizzRealCooldownActive
        if entry.type == "macro" then
            local resolvedID, resolvedType, fallbackTex = ResolveMacro(entry)
            if resolvedID then
                if resolvedType == "item" then
                    startTime, duration, durObj = GetItemCooldown(resolvedID)
                else
                    startTime, duration, durObj, apiIsActive, blizzRealCooldownActive = GetBestSpellCooldown(resolvedID)
                end
            end
            -- Update icon texture from already-resolved macro result
            -- (eliminates a redundant second ResolveMacro call via GetEntryTexture)
            local newTex
            if resolvedID then
                if resolvedType == "item" then
                    local _, _, _, _, tex = C_Item.GetItemInfoInstant(resolvedID)
                    newTex = tex
                else
                    newTex = GetSpellTexture(resolvedID)
                end
            else
                newTex = fallbackTex
            end
            if newTex and icon.Icon and newTex ~= icon._lastTexture then
                icon.Icon:SetTexture(newTex)
                icon._lastTexture = newTex
                UpdateIconProfessionQuality(icon)
            end
        elseif entry.type == "trinket" or entry.type == "slot" then
            -- Trinket/slot entries store equipment slot (13/14), resolve to item ID
            local slotID = entry.id
            local itemID = GetInventoryItemID("player", slotID)
            if itemID then
                startTime, duration, durObj = GetSlotCooldown(slotID)
                -- Update texture in case trinket was swapped
                if icon.Icon then
                    local ok, tex = pcall(C_Item.GetItemIconByID, itemID)
                    if ok and tex and tex ~= icon._lastTexture then
                        icon.Icon:SetTexture(tex)
                        icon._lastTexture = tex
                        UpdateIconProfessionQuality(icon)
                    end
                end
            end
            -- Hide stack text for trinkets
            CDMIcons.HideIconStackText(icon, "slot-clear")
        elseif entry.type == "item" then
            startTime, duration, durObj = GetItemCooldown(entry.id)
            -- Show item count/charges as stack text using legacy custom tracker semantics.
            if C_Item and C_Item.GetItemCount then
                local containerDB = CDMIcons.GetTrackerSettings(entry.viewerType)
                local includeUses = containerDB and containerDB.showItemCharges == true
                local ok, count = pcall(C_Item.GetItemCount, entry.id, false, includeUses, true)
                if ok and count then
                    local stackColor = icon._rowConfig and icon._rowConfig.stackTextColor or {1, 1, 1, 1}
                    if IsSecretValue and IsSecretValue(count) then
                        if icon.StackText.SetTextColor then
                            icon.StackText:SetTextColor(stackColor[1], stackColor[2], stackColor[3], stackColor[4] or 1)
                        end
                        CDMIcons.ShowIconStackText(icon, count, containerDB, "item-count-secret")
                    else
                        local numericCount = SafeToNumber(count, 0)
                        if numericCount > 1 then
                            if icon.StackText.SetTextColor then
                                icon.StackText:SetTextColor(stackColor[1], stackColor[2], stackColor[3], stackColor[4] or 1)
                            end
                            CDMIcons.ShowIconStackText(icon, tostring(numericCount), containerDB, "item-count")
                        elseif numericCount == 1 then
                            CDMIcons.HideIconStackText(icon, "item-count-one")
                        else
                            if icon.StackText.SetTextColor then
                                icon.StackText:SetTextColor((stackColor[1] or 1) * 0.5, (stackColor[2] or 1) * 0.5, (stackColor[3] or 1) * 0.5, stackColor[4] or 1)
                            end
                            CDMIcons.ShowIconStackText(icon, "0", containerDB, "item-count-zero")
                        end
                    end
                else
                    CDMIcons.ShowIconStackText(icon, "0", containerDB, "item-count-fallback")
                end
            end
        else
            if entry._blizzChild and not entry.hasCharges then
                local sid = _runtimeSid

                -- Non-charged abilities may have an aura phase (e.g.,
                -- defensive CDs that grant a buff). Detect active aura
                -- and show it; mirror hook is suppressed via _auraActive
                -- so the cooldown DurationObject doesn't overwrite it.
                -- Many utility/defensive CDs grant a buff with the same
                -- spell ID but aren't in Blizzard's buff CDM categories,
                -- so we always try ResolveAuraState (not gated on the
                -- _abilityToAuraSpellID mapping).
                -- When buff/debuff swipe is disabled, skip aura detection
                -- so the icon shows the recharge/cooldown timer instead.
                local _ncAuraActive = false
                local _ncTotemTexture = nil
                local useBuffSwipe = CDMIcons.ShouldUseBuffSwipeForIcon(icon, entry)
                if useBuffSwipe then
                    local r = ResolveAuraStateForIcon(icon, entry, sid)
                    if r and r.isActive then
                        _ncAuraActive = true
                        ApplyAuraStateToIcon(icon, entry, sid, r)
                        if IsTotemSlotEntry(entry) then
                            icon._isTotemInstance = true
                            if r.totemIcon then
                                icon._totemIconCache = r.totemIcon
                            end
                            _ncTotemTexture = r.totemIcon or icon._totemIconCache
                            icon.StackText:SetText("")
                            icon.StackText:Hide()
                        else
                            icon._isTotemInstance = nil
                        end
                        if icon.Cooldown and r.durObj then
                            -- Resolver owns icon.Cooldown writes; only restyle here.
                            ReapplySwipeStyle(icon.Cooldown, icon)
                        end
                    elseif r then
                        local wasAuraActive = icon._auraActive
                        ApplyAuraStateToIcon(icon, entry, sid, r)
                        if wasAuraActive then
                            if icon.Cooldown then ReapplySwipeStyle(icon.Cooldown, icon) end
                            -- Aura→CD transition: re-resolve so the resolver
                            -- picks up the underlying spell CD now that
                            -- _auraActive is cleared.
                            ApplyResolvedCooldown(icon)
                        end
                    end
                elseif not useBuffSwipe and icon._auraActive then
                    -- Buff/debuff swipe was just disabled: clear aura state
                    -- so the resolver resumes producing cooldown data.
                    CDMIcons.ClearAuraStateForIcon(icon, entry)
                    if icon.Cooldown then ReapplySwipeStyle(icon.Cooldown, icon) end
                    -- Aura→CD transition: re-resolve so the resolver picks up
                    -- the underlying spell CD now that _auraActive is cleared.
                    ApplyResolvedCooldown(icon)
                end

                -- Use runtime-resolved override for cooldown queries + texture.
                local cdSid = _runtimeSid

                if not _ncAuraActive then
                    -- Blizzard-backed non-charged entries still use API reads
                    -- for visibility/style classification. The owned cooldown
                    -- frame itself is bound only by ApplyResolvedCooldown.
                    local childCi = TickCacheGetCooldown(cdSid)
                    local childCooldownActive, childRealCooldownActive = CDMIcons.ClassifySpellCooldownState(cdSid, childCi)
                    if childCooldownActive ~= nil then
                        apiIsActive = childCooldownActive
                    end
                    -- isOnGCD was captured synchronously in the
                    -- SPELL_UPDATE_COOLDOWN handler; do not refresh it here.
                    if childCi and CDMIcons.IsSafeNumeric(childCi.startTime) and CDMIcons.IsSafeNumeric(childCi.duration) then
                        startTime = childCi.startTime
                        duration = childCi.duration
                    end
                    if CDMIcons.DebugIconEvent then
                        CDMIcons.DebugIconEvent(icon, "spell-api",
                            "sid=", tostring(cdSid),
                            "start=", childCi and tostring(SafeValue(childCi.startTime, "secret")) or "nil",
                            "duration=", childCi and tostring(SafeValue(childCi.duration, "secret")) or "nil",
                            "isActive=", childCi and tostring(SafeValue(childCi.isActive, "secret")) or "nil",
                            "isOnGCD=", childCi and tostring(SafeValue(childCi.isOnGCD, "secret")) or "nil")
                    end
                    -- Real cooldown classification can restyle the owned frame,
                    -- but the resolver is the only path that binds a DurationObject.
                    local childCooldownMaybeReal = childRealCooldownActive == true
                        or (childRealCooldownActive == nil
                            and childCooldownActive == true
                            and CDMIcons.SpellHasBaseCooldownLongerThanGCD
                            and CDMIcons.SpellHasBaseCooldownLongerThanGCD(cdSid))
                    if childCooldownMaybeReal and entry._blizzChild
                       and icon.Cooldown and not icon._auraActive then
                        ReapplySwipeStyle(icon.Cooldown, icon)
                        if entry._blizzChild.Cooldown then
                            if CDMIcons.DebugIconEvent then
                                local okChildID, childSpellID = false, nil
                                if entry._blizzChild.GetSpellID then
                                    okChildID, childSpellID = pcall(entry._blizzChild.GetSpellID, entry._blizzChild)
                                end
                                CDMIcons.DebugIconEvent(icon, "blizz-child",
                                    "childSpellID=", okChildID and tostring(SafeValue(childSpellID, "secret")) or "nil",
                                    "cooldownID=", tostring(SafeValue(rawget(entry._blizzChild, "cooldownID"), "secret")),
                                    "apiActive=", tostring(apiIsActive),
                                    "iconHasCD=", tostring(icon._hasCooldownActive),
                                    "lastStart=", tostring(icon._lastStart),
                                    "lastDuration=", tostring(icon._lastDuration))
                            end
                        end
                        if icon._hasCooldownActive
                           and CDMIcons.IsSafeNumeric(icon._lastStart)
                           and CDMIcons.IsSafeNumeric(icon._lastDuration)
                           and icon._lastStart > 0
                           and icon._lastDuration > 0 then
                            startTime = icon._lastStart
                            duration = icon._lastDuration
                            if duration > GCD_MAX_DURATION then
                                blizzRealCooldownActive = true
                            end
                        elseif CDMIcons.IsSafeNumeric(startTime)
                           and CDMIcons.IsSafeNumeric(duration)
                           and startTime > 0
                           and duration > 0 then
                            if duration > GCD_MAX_DURATION and apiIsActive == true then
                                blizzRealCooldownActive = true
                            end
                        else
                            startTime, duration, durObj = nil, nil, nil
                        end
                    end
                else
                    -- Aura active: resolver owns _hasCooldownActive via
                    -- C_Spell.GetSpellCooldown(sid).isActive in
                    -- ApplyResolvedCooldown. Nothing to do per tick.
                end

                -- Texture: mirror the current runtime spell each tick.
                -- Non-aura cooldown entries keep _desiredTexture set so
                -- CDMIcons.HookBlizzTexture's wasSetFromAura guard blocks debuff
                -- texture bleed (e.g. Outbreak → Virulent Plague).
                -- Uses persistent _textureCycleCache (wiped on SPELLS_CHANGED)
                -- so GetSpellInfo isn't called 20×/sec per icon.
                if icon.Icon and _ncAuraActive and _ncTotemTexture then
                    icon._desiredTexture = nil
                    pcall(icon.Icon.SetTexture, icon.Icon, _ncTotemTexture)
                    icon._lastTexture = _ncTotemTexture
                elseif icon.Icon and entry._blizzChild and not entry.isAura then
                    local texID = GetSpellTexture(cdSid)
                    if texID then
                        if icon._desiredTexture ~= texID then
                            icon._desiredTexture = texID
                            pcall(icon.Icon.SetTexture, icon.Icon, texID)
                        end
                    end
                elseif icon.Icon and entry._blizzChild then
                    icon._desiredTexture = nil
                elseif icon.Icon then
                    local texID = GetSpellTexture(cdSid)
                    if texID then
                        icon._desiredTexture = texID
                        pcall(icon.Icon.SetTexture, icon.Icon, texID)
                    end
                end
            else
                -- Aura-phase detection. Originally for charged entries with
                -- a buff phase before the recharge timer (e.g. utility CDs
                -- granting a timed buff). Also runs when the entry has no
                -- Blizzard child at all — that's the cooldown-typed aura
                -- entry case (Mana Tea added via the cooldown CDM picker
                -- on Utility / a custom container has no essential/utility
                -- viewer child, so the line-2746 _blizzChild path doesn't
                -- run, leaving the swipe / duration text blank). When the
                -- aura fades, falls through to GetBestSpellCooldown so the
                -- recharge swipe still renders for charged entries (no-op
                -- for non-charged entries, which have no recharge).
                -- When buff/debuff swipe is disabled, skip detection so
                -- the icon shows the recharge/cooldown timer instead.
                local _chargedAuraActive = false
                local _chargedTotemTexture = nil
                local useBuffSwipe = CDMIcons.ShouldUseBuffSwipeForIcon(icon, entry)
                if (entry.hasCharges or not entry._blizzChild)
                    and useBuffSwipe then
                    local _cBaseID = _runtimeSid

                    local r = ResolveAuraStateForIcon(icon, entry, _cBaseID)
                    if r and r.isActive then
                        ApplyAuraStateToIcon(icon, entry, _cBaseID, r)
                        if IsTotemSlotEntry(entry) then
                            icon._isTotemInstance = true
                            if r.totemIcon then
                                icon._totemIconCache = r.totemIcon
                            end
                            _chargedTotemTexture = r.totemIcon or icon._totemIconCache
                            icon.StackText:SetText("")
                            icon.StackText:Hide()
                        else
                            icon._isTotemInstance = nil
                        end
                        -- Only block the normal cooldown path when we have
                        -- a DurationObject to display. If ResolveAuraState
                        -- reports active but has no durObj (spurious match),
                        -- fall through to GetBestSpellCooldown so the
                        -- recharge swipe still renders.
                        if icon.Cooldown and r.durObj then
                            _chargedAuraActive = true
                            -- Resolver owns icon.Cooldown writes; only restyle here.
                            ReapplySwipeStyle(icon.Cooldown, icon)
                        end
                        -- Non-charged, no-blizzChild aura entries (e.g. Mana
                        -- Tea added via the cooldown CDM picker on Utility /
                        -- a custom container) write stacks here from r.stacks.
                        -- CDMIcons.ApplyAuraStackText has explicit IsSecretValue handling
                        -- and routes through the same C-side pcall pattern as
                        -- the kind="aura" branch — much more robust mid-combat
                        -- than the API path's GetAuraDataBySpellName fallback,
                        -- which can return nil when fed a secret name. Charged
                        -- entries skip this so the cooldownChargesCount path
                        -- (which forwards from the Blizzard child) can drive
                        -- the StackText for them.
                        if not entry.hasCharges
                            and not entry._blizzChild
                            and not IsTotemSlotEntry(entry) then
                            CDMIcons.ApplyAuraStackText(icon, r.stacks, false, InCombatLockdown(), r.stackSource)
                        end
                    elseif r then
                        local wasAuraActive = icon._auraActive
                        ApplyAuraStateToIcon(icon, entry, _cBaseID, r)
                        if wasAuraActive then
                            if icon.Cooldown then ReapplySwipeStyle(icon.Cooldown, icon) end
                            -- Aura→CD transition: re-resolve so the underlying
                            -- spell CD takes hold via the resolver.
                            ApplyResolvedCooldown(icon)
                        end
                    end
                elseif (entry.hasCharges or not entry._blizzChild) and not useBuffSwipe and icon._auraActive then
                    -- Buff/debuff swipe was just disabled: clear aura state
                    -- so the resolver resumes producing cooldown data.
                    CDMIcons.ClearAuraStateForIcon(icon, entry)
                    if icon.Cooldown then ReapplySwipeStyle(icon.Cooldown, icon) end
                    -- Aura→CD transition: re-resolve so the underlying spell
                    -- CD takes hold via the resolver.
                    ApplyResolvedCooldown(icon)
                end

                if not _chargedAuraActive then
                    -- Custom entry / charged recharge: full API resolution.
                    startTime, duration, durObj, apiIsActive, blizzRealCooldownActive = GetBestSpellCooldown(_runtimeSid)
                    if not durObj
                       and not (CDMIcons.IsSafeNumeric(startTime) and CDMIcons.IsSafeNumeric(duration) and duration > GCD_MAX_DURATION)
                       and not entry._blizzChild
                    then
                        local aliasID = CDMIcons.GetRecentCastAliasForEntry(entry)
                        if aliasID and aliasID ~= _runtimeSid then
                            local aStart, aDuration, aDurObj, aActive, aRealActive = GetBestSpellCooldown(aliasID)
                            if aDurObj or (CDMIcons.IsSafeNumeric(aStart) and CDMIcons.IsSafeNumeric(aDuration) and aDuration > GCD_MAX_DURATION) then
                                if CDMIcons.DebugIconEvent then
                                    CDMIcons.DebugIconEvent(icon, "alias",
                                        "from=", tostring(_runtimeSid),
                                        "to=", tostring(aliasID),
                                        "aStart=", tostring(aStart),
                                        "aDuration=", tostring(aDuration),
                                        "aDurObj=", aDurObj and "yes" or "no",
                                        "aActive=", tostring(aActive))
                                end
                                _runtimeSid = aliasID
                                icon._runtimeSpellID = aliasID
                                startTime, duration, durObj, apiIsActive, blizzRealCooldownActive = aStart, aDuration, aDurObj, aActive, aRealActive
                            end
                        end
                    end
                else
                    -- Aura active: resolver owns _hasCooldownActive via
                    -- C_Spell.GetSpellCooldown(sid).isActive in
                    -- ApplyResolvedCooldown.
                end

                -- isOnGCD was captured synchronously in SPELL_UPDATE_COOLDOWN;
                -- this query is for active/duration data only.
                local _tickCi = TickCacheGetCooldown(_runtimeSid)
                if CDMIcons.DebugIconEvent then
                    CDMIcons.DebugIconEvent(icon, "resolve",
                        "sid=", tostring(_runtimeSid),
                        "start=", tostring(startTime),
                        "duration=", tostring(duration),
                        "durObj=", durObj and "yes" or "no",
                        "apiActive=", tostring(apiIsActive),
                        "isOnGCD=", tostring(icon._isOnGCD),
                        "hasCharges=", tostring(entry.hasCharges),
                        "blizzChild=", entry._blizzChild and "yes" or "no",
                        "kind=", tostring(entry.kind),
                        "type=", tostring(entry.type))
                end
                -- Texture: mirror runtime override each tick (same as
                -- non-charged path). Keeps _desiredTexture set to block
                -- debuff bleed, but updates it for talent swaps.
                -- Uses persistent _textureCycleCache (wiped on SPELLS_CHANGED).
                if icon.Icon and _chargedAuraActive and _chargedTotemTexture then
                    icon._desiredTexture = nil
                    pcall(icon.Icon.SetTexture, icon.Icon, _chargedTotemTexture)
                    icon._lastTexture = _chargedTotemTexture
                elseif icon.Icon and entry._blizzChild and not entry.isAura then
                    local texID = GetSpellTexture(_runtimeSid)
                    if texID then
                        if icon._desiredTexture ~= texID then
                            icon._desiredTexture = texID
                            pcall(icon.Icon.SetTexture, icon.Icon, texID)
                        end
                    end
                elseif icon.Icon and entry._blizzChild then
                    icon._desiredTexture = nil
                elseif icon.Icon then
                    local texID = GetSpellTexture(_runtimeSid)
                    if texID then
                        icon._desiredTexture = texID
                        pcall(icon.Icon.SetTexture, icon.Icon, texID)
                    end
                end
            end
        end

        -- _lastStart / _lastDuration: always update from API when readable.
        -- These are used by the desaturation check and visibility logic below.
        local hasSafeStart = CDMIcons.IsSafeNumeric(startTime)
        local hasSafeDuration = CDMIcons.IsSafeNumeric(duration)
        if hasSafeDuration then
            icon._lastDuration = duration
        end
        if hasSafeStart then
            icon._lastStart = startTime
        end
        if hasSafeDuration and duration == 0 then
            icon._lastStart = 0
            icon._lastDuration = 0
        end
        -- When API returns no data (fully charged / off CD), clear stale
        -- values so desaturation doesn't persist from a previous recharge.
        if not startTime and not duration then
            icon._lastStart = 0
            icon._lastDuration = 0
        end

        if icon.Cooldown then
            -- Decide what to draw from the actual rendered state first:
            -- aura swipe wins, then real cooldown/recharge, then GCD.
            -- isOnGCD is only used when this batch came from
            -- SPELL_UPDATE_COOLDOWN; outside that event it can be stale.
            local auraSwipeActive = icon._auraActive or entry.viewerType == "buff"
            local realCooldownActive = HasRealCooldownState(icon, entry, duration, apiIsActive, blizzRealCooldownActive, durObj, _runtimeSid)
            -- GCD is simple: isOnGCD says the current active display is the
            -- global cooldown. isActive is the non-secret "render cooldown UI"
            -- bit. Aura and real cooldown owners win; the resolver owns the
            -- actual cooldown-frame binding.
            local trustIsOnGCD = CDMIcons._trustIsOnGCDForBatch == true
            local gcdStateTrusted = trustIsOnGCD
                and icon._isOnGCDTrustedAt == CDMIcons._trustedGCDStamp
            local iconIsOnGCD = gcdStateTrusted and icon._isOnGCD == true
            local hasLongDisplayDuration = CDMIcons.IsSafeNumeric(duration) and duration > GCD_MAX_DURATION
            local activeDisplayActive = apiIsActive == true
                and not auraSwipeActive
                and ((gcdStateTrusted and iconIsOnGCD ~= true)
                    or realCooldownActive
                    or durObj ~= nil
                    or hasLongDisplayDuration)
            local activeDurationOwned = auraSwipeActive
                or activeDisplayActive
                or realCooldownActive
                or durObj ~= nil
            local gcdOnlyActive = iconIsOnGCD == true
                and apiIsActive == true
                and not activeDurationOwned
            -- _hasRealCooldownActive is owned by the resolver
            -- (C_Spell.GetSpellCooldown(sid).isActive in ApplyResolvedCooldown).
            if CDMIcons.DebugIconEvent then
                CDMIcons.DebugIconEvent(icon, "classify",
                    "real=", tostring(realCooldownActive),
                    "gcdOnly=", tostring(gcdOnlyActive),
                    "gcdTrusted=", tostring(trustIsOnGCD),
                    "gcdSnapshot=", tostring(gcdStateTrusted),
                    "durationOwned=", tostring(activeDurationOwned),
                    "blizzReal=", tostring(blizzRealCooldownActive),
                    "durObj=", durObj and "yes" or "no",
                    "baseLong=", tostring(CDMIcons.SpellHasBaseCooldownLongerThanGCD(_runtimeSid)))
            end
            -- Per-tick chain does NOT touch cooldown flags or icon.Cooldown.
            -- ApplyResolvedCooldown (event-driven via UNIT_SPELLCAST_SUCCEEDED,
            -- AuraEvents, SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_USABLE) is the
            -- sole writer of _hasCooldownActive / _hasRealCooldownActive /
            -- _showingRealCooldownSwipe / _showingGCDSwipe and the sole binder
            -- of icon.Cooldown via SetCooldownFromDurationObject.

            -- Reapply swipe styling when GCD or cooldown-active state
            -- transitions so SetDrawSwipe/SetDrawEdge and colors update.
            -- GCD transition: e.g., GCD → cooldown mode re-hides the swipe
            -- when radial darkening is off.
            -- isActive transition: ensures edge/color switches correctly
            -- when a cooldown starts (ready → active) or ends (active → ready)
            -- without waiting for a later resolver event.
            local prevGCD = icon._wasShowingGCDSwipe or false
            local curGCD = icon._showingGCDSwipe or false
            local prevActive = icon._wasApiActive
            local curActive = apiIsActive
            if prevGCD ~= curGCD or prevActive ~= curActive then
                icon._wasShowingGCDSwipe = curGCD
                icon._wasApiActive = curActive
                ReapplySwipeStyle(icon.Cooldown, icon)
            end

            -- Real cooldown state drives desaturation/visibility. Raw
            -- apiIsActive may also mean GCD or resource recovery.
            if apiIsActive ~= nil then
                -- When a real cooldown starts, clear usability tint so the
                -- desaturation gate opens.  Reset _lastVisualState so the
                -- range poll can reapply usability tint after the CD ends.
                local cooldownActiveForState = realCooldownActive and true or false
                if cooldownActiveForState and icon._usabilityTinted then
                    icon.Icon:SetVertexColor(1, 1, 1, 1)
                    icon._usabilityTinted = nil
                    icon._lastVisualState = nil
                end
                -- _hasCooldownActive is owned by the resolver
                -- (C_Spell.GetSpellCooldown(sid).isActive in
                -- ApplyResolvedCooldown).
            end
        end

    do
        local containerDB = CDMIcons.GetTrackerSettings(entry.viewerType)
        if CDMIcons.IsCustomBarContainer(containerDB) then
            CDMIcons.ApplyCustomBarActiveState(icon, entry, containerDB)
        else
            icon._customBarActive = nil
            CDMIcons.StopCustomBarActiveGlow(icon)
        end
    end

    -- Stack/charge text: API-driven on each tick.
    -- Cache chargeInfo for this icon — reused by desaturation check below
    -- (was called 3x per cooldown icon per tick, now 1x)
    local _cachedChargeInfo = nil
    local _cachedChargeOk = false

    -- Populate _cachedChargeInfo unconditionally (needed for desaturation
    -- check below), independent of whether hooks are driving stack text.
    do
        local spellID = _runtimeSid
        if spellID then
            local chargeInfo = TickCacheGetCharges(spellID)
            _cachedChargeOk = chargeInfo ~= nil
            _cachedChargeInfo = chargeInfo
        end
    end

    -- When hooks are actively driving stack text for this icon, skip all
    -- API-based stack writes.  Our event handler runs AFTER Blizzard's
    -- hooks in the same frame — API writes would overwrite the correct
    -- hook-driven values, causing visible flicker every tick.
    local _hookActive = CDMIcons.IsHookStackActive(entry, icon)

    -- Forward cooldownChargesCount from the Blizzard child only until a native
    -- hook is actively driving this icon. Hook-driven text may be secret, so
    -- once it is active we let Blizzard changes push updates instead of
    -- repainting the same owned FontString every refresh.
    --
    -- Gate: GetSpellCharges on the base spell returns maxCharges > 1.
    -- maxCharges is non-secret (12.0.5+) and updates dynamically when
    -- the spell gains charges (e.g., Mind Blast base ID reports max=2
    -- when Void Blast is active). Single-charge spells (max=1) excluded.
    local _chargeCountForwarded = false
    if not _hookActive and entry._blizzChild and C_Spell.GetSpellCharges then
        local baseSid = entry.spellID or entry.id
        local ci = baseSid and TickCacheGetCharges(baseSid)
        local ciMax = ci and SafeToNumber(ci.maxCharges, nil)
        -- When the base spell transforms (e.g., Holy Bulwark → Sacred Weapon),
        -- GetSpellCharges on the base ID may return nil/<=1 even though the
        -- spell is still multi-charge.  Try the override spell ID as fallback.
        if (not ciMax or ciMax <= 1)
            and entry.overrideSpellID and entry.overrideSpellID ~= baseSid then
            local oci = TickCacheGetCharges(entry.overrideSpellID)
            local ociMax = oci and SafeToNumber(oci.maxCharges, nil)
            if ociMax and ociMax > 1 then
                ci = oci
                ciMax = ociMax
                ChargeDebug(entry.name, "FWD override fallback: overrideSpellID=", entry.overrideSpellID,
                    "maxCharges=", ociMax, "currentCharges=", oci.currentCharges)
            end
        end
        if ciMax and ciMax > 1 then
            -- Read cooldownChargesCount from the correct viewer child.
            -- entry._blizzChild can get reassigned to the buff viewer
            -- child (which lacks charge data), so we look up an alternate
            -- child from any cooldown viewer in _spellIDToChild. The QUI
            -- container the user picked (essential vs utility) is independent
            -- of where Blizzard places the spell — accept a child from either
            -- cooldown viewer so cross-category placement still mirrors charge
            -- data.
            local ccc = entry._blizzChild.cooldownChargesCount
            local _dbgCccSource = ccc ~= nil and "direct" or nil
            if ccc == nil and ns.CDMSpellData then
                local essentialViewer = _G["EssentialCooldownViewer"]
                local utilityViewer = _G["UtilityCooldownViewer"]
                local essentialContainer = essentialViewer and (essentialViewer.viewerFrame or essentialViewer)
                local utilityContainer = utilityViewer and (utilityViewer.viewerFrame or utilityViewer)
                local childMap = ns.CDMSpellData._spellIDToChild
                local children = childMap and childMap[baseSid]
                if children then
                    for _, altChild in ipairs(children) do
                        local vf = altChild.viewerFrame
                        local isCooldownViewerChild = vf and (
                            vf == essentialViewer or vf == utilityViewer
                            or vf == essentialContainer or vf == utilityContainer
                        )
                        if isCooldownViewerChild and altChild.cooldownChargesCount ~= nil then
                            ccc = altChild.cooldownChargesCount
                            _dbgCccSource = "altChild"
                            break
                        end
                    end
                end
            end
            ChargeDebug(entry.name, "FWD path: baseSid=", baseSid,
                "maxCharges=", ciMax, "currentCharges=", ci.currentCharges,
                "ccc=", ccc, "cccSource=", _dbgCccSource or "nil",
                "hasCharges=", entry.hasCharges,
                "overrideSpellID=", entry.overrideSpellID)
            CDMIcons.DebugNativeChargeText(icon, "fwd-before-stacktext")
            if ccc ~= nil then
                CDMIcons.ShowIconStackText(icon, ccc, CDMIcons.GetTrackerSettings(entry.viewerType), "fwd-charge-count")
                _chargeCountForwarded = true
            end
        elseif ciMax then
            local ccc, cccSource = CDMIcons._GetAuraBackedCooldownChargesCount(icon, entry, baseSid)
            if CDMIcons.ValueIsPresent(ccc) then
                local truncOk, truncText = pcall(C_StringUtil.TruncateWhenZero, ccc)
                local displayText = truncOk and truncText or ccc
                if HookTextHasDisplay(displayText) then
                    CDMIcons.ShowIconStackText(icon, displayText, CDMIcons.GetTrackerSettings(entry.viewerType), cccSource)
                    _chargeCountForwarded = true
                    ChargeDebug(entry.name, "FWD path SINGLE-CHARGE-AURA: baseSid=", baseSid,
                        "maxCharges=", ciMax, "ccc=", ccc, "displayText=", displayText)
                end
            else
                ChargeDebug(entry.name, "FWD path CLEAR: baseSid=", baseSid,
                    "maxCharges=", ciMax, "(<=1, clearing stacks)",
                    "overrideSpellID=", entry.overrideSpellID)
            end
        else
            local ccc, cccSource = CDMIcons._GetAuraBackedCooldownChargesCount(icon, entry, baseSid)
            if CDMIcons.ValueIsPresent(ccc) then
                local truncOk, truncText = pcall(C_StringUtil.TruncateWhenZero, ccc)
                local displayText = truncOk and truncText or ccc
                if HookTextHasDisplay(displayText) then
                    CDMIcons.ShowIconStackText(icon, displayText, CDMIcons.GetTrackerSettings(entry.viewerType), cccSource)
                    _chargeCountForwarded = true
                    ChargeDebug(entry.name, "FWD path STACKING-AURA: baseSid=", baseSid,
                        "ccc=", ccc, "displayText=", displayText)
                end
            end
        end
    end

    -- Charged entries where the FWD path couldn't find charges use the native
    -- SetText hook if one is active; otherwise the API fallback below gets a
    -- chance to provide the owned StackText value.

    if _hookActive or _chargeCountForwarded then
        ChargeDebug(entry.name, "SKIP API path: hookActive=", _hookActive,
            "chargeCountForwarded=", _chargeCountForwarded)
    end
    if not _hookActive and not _chargeCountForwarded then
        if entry.type == "item" then
            -- Item stack text was already set above in the cooldown section;
            -- nothing to do here — just prevent the else clause from clearing it.
        elseif entry.type == "spell" then
            -- Custom spell entry: check charges/stacks via API.
            -- Values may be secret in combat — pass directly to C-side functions
            -- (TruncateWhenZero, SetText) without reading in Lua.
            local spellID = _runtimeSid
            local stackVal  -- raw value (may be secret), forwarded to C-side
            local stackSource

            -- Only show charge count when maxCharges is readable and > 1
            -- (multi-charge spell).
            -- Resource overlay counts (Soul Fragments etc.) use
            -- GetSpellDisplayCount in the non-charge branch below.
            local cachedMaxCharges = _cachedChargeInfo and SafeToNumber(_cachedChargeInfo.maxCharges, nil)
            local isMultiCharge = cachedMaxCharges and cachedMaxCharges > 1

            if isMultiCharge then
                -- GetSpellDisplayCount is the canonical charge display API.
                if spellID and C_Spell.GetSpellDisplayCount then
                    stackVal = TickCacheGetDisplayCount(spellID)
                    if CDMIcons.ValueIsPresent(stackVal) then
                        stackSource = "spell-display-count"
                    end
                end
                ChargeDebug(entry.name, "API path: spellID=", spellID,
                    "maxCharges=", _cachedChargeInfo.maxCharges,
                    "currentCharges=", _cachedChargeInfo.currentCharges,
                    "displayCount=", stackVal, "isMultiCharge=", isMultiCharge)
            else
                -- Prefer stacking aura applications before generic display
                -- counts so buff-backed spell entries show their real stacks.
                stackVal, stackSource = CDMIcons.GetAuraApplicationsForSpell(spellID, entry, icon)
                if CDMIcons.ValueIsMissing(stackVal) then
                    stackVal, stackSource = CDMIcons._GetAuraBackedCooldownChargesCount(icon, entry, spellID)
                end

                -- Non-charge resource overlays (Soul Fragments, etc.) fall
                -- back to SpellDisplayCount. This mirrors action-button count
                -- text without trusting the CooldownViewer child's native
                -- cooldownChargesCount, which can carry unrelated counts for
                -- ordinary cooldown spells.
                local displayCount
                if CDMIcons.ValueIsMissing(stackVal) and spellID and C_Spell.GetSpellDisplayCount then
                    displayCount = TickCacheGetDisplayCount(spellID)
                    stackVal = displayCount
                    if CDMIcons.ValueIsPresent(displayCount) then
                        stackSource = "spell-display-count"
                        local displayOk, displayText = pcall(C_StringUtil.TruncateWhenZero, displayCount)
                        if displayOk and not HookTextHasDisplay(displayText) then
                            stackVal = nil
                            stackSource = nil
                        end
                    end
                end
                ChargeDebug(entry.name, "API non-charge stack: spellID=", spellID,
                    "displayCount=", SafeValue(displayCount, "secret"),
                    "stackSource=", stackSource or "nil",
                    "stackVal=", SafeValue(stackVal, "secret"),
                    "childAuraInstanceID=", entry._blizzChild and SafeValue(entry._blizzChild.auraInstanceID, "secret") or "nil",
                    "childAuraDataUnit=", entry._blizzChild and SafeValue(entry._blizzChild.auraDataUnit, "secret") or "nil")
            end


            -- Forward to C-side for display. Multi-charge spells always
            -- show their count (including "0" when depleted). Non-charge
            -- stacks use TruncateWhenZero to hide zero (resource overlays,
            -- non-charge spells that return 0 from GetSpellDisplayCount).
            if CDMIcons.ValueIsPresent(stackVal) then
                if isMultiCharge then
                    -- Always show charge count — "0" is meaningful
                    CDMIcons.ShowIconStackText(icon, stackVal, CDMIcons.GetTrackerSettings(entry.viewerType), "api-charge-count")
                else
                    local truncOk, truncText = pcall(C_StringUtil.TruncateWhenZero, stackVal)
                    local displayText = truncOk and truncText or stackVal
                    local hasText = HookTextHasDisplay(displayText)
                    if hasText then
                        CDMIcons.ShowIconStackText(icon, displayText, CDMIcons.GetTrackerSettings(entry.viewerType), stackSource or "api-aura-stack")
                    else
                        CDMIcons.HideIconStackText(icon, "api-aura-stack-empty")
                    end
                end
            elseif not InCombatLockdown() and not (entry and entry.hasCharges) then
                -- Don't hide charged-ability stack text on a transient API
                -- nil. UNIT_AURA on the target (from other players' buffs/
                -- debuffs) and PLAYER_SOFT_ENEMY_CHANGED both schedule full
                -- CDM updates; during those Blizzard's charge data and
                -- TickCacheGetDisplayCount can momentarily return nil even
                -- when the spell still has charges. Hiding here and
                -- re-showing on the next tick produced the visible "stacks
                -- flicker show/hide" symptom on every target aura change.
                -- The FWD path or the next tick's API read will restore the
                -- correct value; preserve the previous text in the gap.
                CDMIcons.HideIconStackText(icon, "api-stack-nil")
            end
        else
            -- Harvested entries and other types: hooks drive StackText when
            -- Blizzard emits native values. For icons sharing the same
            -- _blizzChild (same spell in multiple containers), API-read aura
            -- applications per-icon so they render independently of the hook.
            local stackVal = CDMIcons.GetAuraApplicationsForSpell(_runtimeSid, entry, icon)
            if CDMIcons.ValueIsPresent(stackVal) then
                local truncOk, truncText = pcall(C_StringUtil.TruncateWhenZero, stackVal)
                local displayText = truncOk and truncText or stackVal
                local hasText = HookTextHasDisplay(displayText)
                if hasText then
                    CDMIcons.ShowIconStackText(icon, displayText, CDMIcons.GetTrackerSettings(entry.viewerType), "harvested-aura-stack")
                else
                    CDMIcons.HideIconStackText(icon, "harvested-aura-stack-empty")
                end
            elseif not InCombatLockdown() then
                CDMIcons.HideIconStackText(icon, "harvested-stack-nil")
            end
        end
    end

    -- Desaturation for cooldown entries based on resolver-owned cooldown state.
    local desatSettings = CDMIcons._hoistedNcdm and (CDMIcons._hoistedNcdm[entry.viewerType]
        or (CDMIcons._hoistedNcdm.containers and CDMIcons._hoistedNcdm.containers[entry.viewerType]))
    CDMIcons.ApplyCooldownDesaturation(icon, entry, desatSettings or CDMIcons.ResolveTrackerSettingsNow(entry.viewerType), icon._resolvedCooldownMode)

    -- Self-heal usability tint: icon rebuilds (BuildIcons via ScanAll)
    -- wipe _usabilityTinted.  Restore from _lastVisualState which
    -- persists on the recycled table when the same spell is re-acquired.
    if icon._lastVisualState == "unusable"
       and not icon._usabilityTinted
       and not CDMIcons.CooldownHasVisualPriority(icon, entry, CDMIcons.GetTrackerSettings(entry.viewerType), CDMIcons._batchTime) then
        icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
        icon._usabilityTinted = true
    end
end

CDMIconFactory.UpdateIconCooldown = UpdateIconCooldown
