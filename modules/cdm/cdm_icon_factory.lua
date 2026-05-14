-- cdm_icon_factory.lua
-- Icon pool lifecycle and the UpdateIconCooldown driver for the QUI CDM
-- owned engine. Frame writes happen here (and in cdm_icons.lua's view layer);
-- this file is allowed to call frame:Set*. It depends on cdm_resolvers.lua
-- for pure resolution and tick-cache reads.

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local Resolvers = ns.CDMResolvers
local Sources = ns.CDMSources

-- Forward reference to ns.CDMIcons. Bound by _FinalizeImports() at the
-- end of cdm_icons.lua's load. Cannot be `local CDMIcons = ns.CDMIcons`
-- here because cdm_icon_factory.lua loads before cdm_icons.lua per cdm.xml.
local CDMIcons

local CDMIconFactory = {}
ns.CDMIconFactory = CDMIconFactory

---------------------------------------------------------------------------
-- LOCAL UPVALUE ALIASES
---------------------------------------------------------------------------
local GetGeneralFont        = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local GetEntryTexture       = Resolvers.GetEntryTexture
local GetSpellTexture       = Resolvers.GetSpellTexture
-- Tick-cache reads used by UpdateIconCooldown driver
local QueryCharges        = Resolvers.QueryCharges
local QueryCooldown       = Resolvers.QueryCooldown
local QueryOverrideSpell  = Resolvers.QueryOverrideSpell
local QueryDisplayCount   = Resolvers.QueryDisplayCount
-- Pure resolvers used by UpdateIconCooldown driver
local ResolveAuraStateForIcon    = Resolvers.ResolveAuraStateForIcon
local HasRealCooldownState       = Resolvers.HasRealCooldownState
local ResolveMacro               = Resolvers.ResolveMacro
local IsAuraEntry                = Resolvers.IsAuraEntry
-- Helpers from cdm_icons.lua (local functions or namespace exposures there;
-- factory uses bare names via these upvalues so call sites stay clean).
-- All bound late by _FinalizeImports() at the end of cdm_icons.lua's load
-- because ns.CDMIcons is still nil at this point in the load order.
local GetBestSpellCooldown
local GetItemCooldown
local GetSlotCooldown
local IsTotemSlotEntry
local ApplyAuraStateToIcon
local ApplyResolvedCooldown
local ReapplySwipeStyle
local UpdateIconProfessionQuality
local HookTextHasDisplay
-- ChargeDebug lives in the load-on-demand debug addon and is bound via
-- _BindDebugImports. Initialized as a no-op so calls before binding don't crash.
local ChargeDebug = function() end

local InCombatLockdown = InCombatLockdown
local CreateFrame      = CreateFrame
local type             = type

local function SafeValue(value, fallback)
    if Helpers and Helpers.SafeValue then
        return Helpers.SafeValue(value, fallback)
    end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value) then
        return fallback
    end
    if issecretvalue and issecretvalue(value) then
        return fallback
    end
    return value
end

---------------------------------------------------------------------------
-- CONSTANTS (mirrors cdm_icons.lua; both refer to the same design values)
---------------------------------------------------------------------------
local DEFAULT_ICON_SIZE      = 39
local MAX_RECYCLE_POOL_SIZE  = 20
local GCD_MAX_DURATION       = 1.75

local function IsMouseoverRevealContext(context)
    local core = ns.Addon
    local profile = core and core.db and core.db.profile
    local visibility
    if context == "customTrackers" then
        visibility = profile and profile.customTrackersVisibility
    else
        visibility = profile and profile.cdmVisibility
    end
    return visibility and not visibility.showAlways and visibility.showOnMouseover
end

---------------------------------------------------------------------------
-- POOL STATE
---------------------------------------------------------------------------
local iconPools = {
    essential = {},
    utility   = {},
    buff      = {},
}
-- Pools for custom containers are created dynamically via EnsurePool().
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
    icon.Cooldown:SetDrawBling(false)
    icon._drawBlingEnabled = false
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
        -- Aura entries: dynamic buff icon (e.g., Roll the Bones → Broadside)
        -- arrives via the per-tick UpdateIconCooldown path, which reads the
        -- live aura's icon from r.auraData.icon. Initial icon is the
        -- composer-resolved entry texture.
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
        local tooltipContext = self._quiTooltipContext
            or self.__quiTooltipContext
            or (self.__customTrackerIcon and "customTrackers")
            or "cdm"
        if tooltipProvider then
            if tooltipProvider.IsOwnerFadedOut
               and tooltipProvider:IsOwnerFadedOut(self)
               and not IsMouseoverRevealContext(tooltipContext) then
                GameTooltip.Hide(GameTooltip)
                return
            end
            if tooltipProvider.ShouldShowTooltip and not tooltipProvider:ShouldShowTooltip(tooltipContext) then
                GameTooltip.Hide(GameTooltip)
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
        -- Prefer the resolver's active aura identity. Avoid ad-hoc live aura
        -- lookups here; tooltip hover should not bypass the same filtering
        -- rules that drive the icon face and swipe.
        local sid = self._activeAuraSpellID
        if not sid then
            sid = self._runtimeSpellID
        end
        if not sid then
            sid = ns.CDMSpellData:ResolveDisplaySpellID(entry)
        end
        if sid then
            if entry.type == "trinket" or entry.type == "slot" then
                local itemID = entry.itemID
                if not itemID and Sources and Sources.QueryInventoryItemID then
                    itemID = Sources.QueryInventoryItemID("player", entry.id)
                end
                if itemID then
                    GameTooltip.SetItemByID(GameTooltip, itemID)
                end
            elseif entry.type == "item" then
                GameTooltip.SetItemByID(GameTooltip, entry.id)
            else
                GameTooltip.SetSpellByID(GameTooltip, sid)
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
                GameTooltip.AddLine(GameTooltip, ("Source: %s"):format(label), 0.75, 0.85, 1, true)
            end
        end
        GameTooltip.Show(GameTooltip)
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip.Hide(GameTooltip)
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
        if _G.QUI_CDM_CHARGE_DEBUG then
            CDMIcons.ChargeDebug(spellEntry and spellEntry.name, "ACQUIRE", "reused", "viewerType=", spellEntry and spellEntry.viewerType)
        end

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
        -- Bind to a Blizzard CDM child if this entry has one. On a recycled
        -- icon this also clears any stale binding from the previous owner.
        -- Routed through CDMIconFactory.* (table lookup) because the helper
        -- is defined later in this file and the local upvalue isn't visible
        -- here at parse time.
        CDMIconFactory.TryBindIconToBlizz(icon, spellEntry)
        -- Notify rotation helper that an icon was assigned a spell
        if ns._onIconAssigned then ns._onIconAssigned(icon) end
        return icon
    end
    local newIcon = CreateIcon(parent, spellEntry)
    if _G.QUI_CDM_CHARGE_DEBUG then
        CDMIcons.ChargeDebug(spellEntry and spellEntry.name, "ACQUIRE", "new", "viewerType=", spellEntry and spellEntry.viewerType)
    end
    -- Update click-to-cast secure attributes for new icons
    if spellEntry.viewerType ~= "buff" then
        CDMIcons.UpdateIconSecureAttributes(newIcon, spellEntry, spellEntry.viewerType)
    end
    -- Bind to a Blizzard mirror child if this entry has one.
    CDMIconFactory.TryBindIconToBlizz(newIcon, spellEntry)
    -- Notify rotation helper that an icon was assigned a spell
    if ns._onIconAssigned then ns._onIconAssigned(newIcon) end
    return newIcon
end

function CDMIconFactory:ReleaseIcon(icon)
    if not icon then return end
    if _G.QUI_CDM_CHARGE_DEBUG then
        CDMIcons.ChargeDebug(icon._spellEntry and icon._spellEntry.name, "RELEASE",
            "viewerType=", icon._spellEntry and icon._spellEntry.viewerType,
            "shown=", icon.IsShown and icon:IsShown())
    end
    -- Drop any Blizzard mirror binding before the rest of release-state
    -- cleanup runs. Table-routed because the helper is defined later here.
    CDMIconFactory.ClearIconBlizzMirrorBinding(icon)
    CDMIcons.CancelCooldownExpiryRefresh(icon)
    if ns.CDMRuntimeStore and ns.CDMRuntimeStore.ClearFrame then
        ns.CDMRuntimeStore.ClearFrame(icon)
    end
    -- Disconnect hooks before clearing _spellEntry
    CDMIcons.UnmirrorBlizzCooldown(icon)
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
    icon._activeAuraSpellID = nil
    icon._auraIsHarmful = nil
    icon._lastTexture = nil
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

-- Keep CooldownFrame ready-flash ("bling") disabled on owned cooldowns.
-- The Blizzard ready-flash is especially visible after short GCD bindings and
-- HUD visibility transitions; QUI uses its own glow/highlight systems instead.
local function SyncCooldownBling(icon)
    if not icon or not icon.Cooldown or not icon.Cooldown.SetDrawBling then return end
    if icon._drawBlingEnabled ~= false then
        icon._drawBlingEnabled = false
        icon.Cooldown:SetDrawBling(false)
    end
end

CDMIconFactory.SyncCooldownBling = SyncCooldownBling


---------------------------------------------------------------------------
-- BLIZZARD MIRROR CONSUMERS
--
-- For entries that map to a Blizzard CDM cooldownID, the Blizzard child stays
-- in Blizzard's hidden viewer and acts only as the producer for the mirror.
-- QUI icons keep their native widgets and render from that exact cID state.
-- Aura entries use the mirror for visibility plus duration; cooldown entries
-- use it only as a preferred duration source.
---------------------------------------------------------------------------
local function ShowNativeIconWidgets(icon)
    if icon.Icon then icon.Icon.Show(icon.Icon) end
    if icon.Cooldown then
        -- Restore the QUI native Cooldown's rendering primitives to their
        -- factory defaults (mirrors CreateIcon's setup). The swipe color is
        -- intentionally black at 0.8 alpha — that's the QUI swipe style.
        icon.Cooldown.SetDrawSwipe(icon.Cooldown, true)
        icon.Cooldown.SetDrawBling(icon.Cooldown, false)
        icon._drawBlingEnabled = false
        icon.Cooldown.SetSwipeTexture(icon.Cooldown, "Interface\\Buttons\\WHITE8X8")
        icon.Cooldown.SetSwipeColor(icon.Cooldown, 0, 0, 0, 0.8)
        icon.Cooldown.SetHideCountdownNumbers(icon.Cooldown, false)
        icon.Cooldown.Show(icon.Cooldown)
    end
    -- DurationText / StackText / Border are content-driven (only Show'd when
    -- they have text/atlas). Don't force Show — let the per-tick driver
    -- restore visibility based on actual state.
    if icon.TextOverlay  then icon.TextOverlay.Show(icon.TextOverlay)  end
end

local function SetIconBlizzMirrorBinding(icon, cooldownID, viewerCategory)
    if not (icon and cooldownID) then return end
    icon._mirrorNativeDurObjApplied = nil
    -- Three-field change-detection state for SyncBlizzMirrorIconState. Used
    -- to be a single concatenated string `_lastMirrorNativeAuraSourceID` —
    -- per-tick string allocation was ~150 KB/s of garbage.
    icon._lastMirrorNativeAuraSourceCat = nil
    icon._lastMirrorNativeAuraSourceCDID = nil
    icon._lastMirrorNativeAuraSourceEpoch = nil
    icon._blizzMirrorCooldownID = cooldownID
    icon._blizzMirrorCategory = viewerCategory
    if CDMIcons and CDMIcons.RegisterBlizzMirrorIcon then
        CDMIcons.RegisterBlizzMirrorIcon(icon, cooldownID, viewerCategory)
    end
    ShowNativeIconWidgets(icon)
    local icons = ns.CDMIcons
    if icons and icons.ConfigureIcon and icon._rowConfig then
        icons.ConfigureIcon(icon, icon._rowConfig)
    end
end

local function ClearIconBlizzMirrorBinding(icon)
    if not icon or not icon._blizzMirrorCooldownID then return end
    if CDMIcons and CDMIcons.UnregisterBlizzMirrorIcon then
        CDMIcons.UnregisterBlizzMirrorIcon(icon)
    end
    icon._mirrorNativeDurObjApplied = nil
    icon._lastMirrorNativeAuraSourceCat = nil
    icon._lastMirrorNativeAuraSourceCDID = nil
    icon._lastMirrorNativeAuraSourceEpoch = nil
    icon._blizzMirrorCooldownID = nil
    icon._blizzMirrorCategory = nil
    ShowNativeIconWidgets(icon)
end

CDMIconFactory.SetIconBlizzMirrorBinding   = SetIconBlizzMirrorBinding
CDMIconFactory.ClearIconBlizzMirrorBinding = ClearIconBlizzMirrorBinding

-- Blizzard mirror debug helpers live in the load-on-demand debug addon.
-- Placeholders below are rebound by cdm_debug.lua's BindAll() when loaded.
local ShouldDebugBlizzEntry = function() return false end
local FormatMirrorState     = function() return "nil" end
local FormatIDList          = function() return "nil" end
local DebugBlizzEntry       = function() end

local function DebugSafeShown(frame)
    if frame and frame.IsShown then
        return frame:IsShown() and true or false
    end
    return nil
end

local function DebugSafeAlpha(frame)
    if frame and frame.GetAlpha then
        local alpha = frame:GetAlpha()
        if not (Helpers.IsSecretValue and Helpers.IsSecretValue(alpha)) then
            return alpha
        end
    end
    return nil
end

local function DebugBlizzSyncSnapshot(enabled, icon, entry, mirrorState, resolvedState,
                                      active, mirrorActive, fallbackFoundAura,
                                      durObj, durObjSource)
    if not enabled or not icon then return end

    local signature = table.concat({
        tostring(active == true),
        tostring(mirrorActive == true),
        tostring(mirrorState and mirrorState.durObj and true or false),
        tostring(mirrorState and mirrorState.hasAuraInstanceID == true),
        tostring(mirrorState and mirrorState.auraUnit),
        tostring(resolvedState and resolvedState.isActive == true),
        tostring(resolvedState and resolvedState.durObj and true or false),
        tostring(resolvedState and resolvedState.auraInstanceID and true or false),
        tostring(resolvedState and resolvedState.auraUnit),
        tostring(resolvedState and resolvedState.durationStateUnknown == true),
        tostring(fallbackFoundAura == true),
        tostring(durObj and true or false),
        tostring(durObjSource),
        tostring(DebugSafeShown(icon)),
        tostring(DebugSafeAlpha(icon)),
    }, "|")

    if icon._lastBlizzSyncTraceSig == signature then return end
    icon._lastBlizzSyncTraceSig = signature

    DebugBlizzEntry(enabled, entry, "state-sync-trace",
        "active=", tostring(active == true),
        "mirrorActive=", tostring(mirrorActive == true),
        "mirrorDur=", tostring(mirrorState and mirrorState.durObj and true or false),
        "mirrorInst=", tostring(mirrorState and mirrorState.hasAuraInstanceID == true),
        "mirrorUnit=", tostring(mirrorState and mirrorState.auraUnit),
        "resolverActive=", tostring(resolvedState and resolvedState.isActive == true),
        "resolverDur=", tostring(resolvedState and resolvedState.durObj and true or false),
        "resolverInst=", tostring(resolvedState and resolvedState.auraInstanceID and true or false),
        "resolverUnit=", tostring(resolvedState and resolvedState.auraUnit),
        "unknown=", tostring(resolvedState and resolvedState.durationStateUnknown == true),
        "fallbackAura=", tostring(fallbackFoundAura == true),
        "durObj=", tostring(durObj and true or false),
        "durObjSource=", tostring(durObjSource),
        "hostShown=", tostring(DebugSafeShown(icon)),
        "hostAlpha=", tostring(DebugSafeAlpha(icon)),
        FormatMirrorState(mirrorState))
end

-- Resolve entry -> exact Blizzard mirror identity. Bars use the same resolver,
-- so entry type/category semantics stay centralized.
local function ResolveBlizzCooldownIDForEntry(entry)
    local resolver = Resolvers and Resolvers.ResolveBlizzardMirrorIdentity
    if not (entry and resolver) then return nil end

    local debugBlizz
    if _G.QUI_CDM_BLIZZ_DEBUG or _G.QUI_CDM_ICON_DEBUG then
        debugBlizz = ShouldDebugBlizzEntry(entry)
        if debugBlizz then
            DebugBlizzEntry(debugBlizz, entry, "begin-shared")
        end
    end

    local cooldownID, category, state = resolver(entry)
    if not cooldownID then
        if debugBlizz then
            DebugBlizzEntry(debugBlizz, entry, "miss")
        end
        return nil
    end

    if debugBlizz then
        DebugBlizzEntry(debugBlizz, entry, "resolved", FormatMirrorState(state))
    end
    return cooldownID, category
end

local function TryBindIconToBlizz(icon, spellEntry)
    local cdID, catName = ResolveBlizzCooldownIDForEntry(spellEntry)
    if not cdID then
        -- Recycled icon may carry a stale Blizzard binding; clear it so
        -- native rendering takes over.
        ClearIconBlizzMirrorBinding(icon)
        return false
    end
    -- Same binding as before: no-op.
    if icon._blizzMirrorCooldownID == cdID
        and icon._blizzMirrorCategory == catName then
        return true
    end
    -- Different binding — clear and rebind
    if icon._blizzMirrorCooldownID then ClearIconBlizzMirrorBinding(icon) end
    SetIconBlizzMirrorBinding(icon, cdID, catName)
    return true
end

CDMIconFactory.TryBindIconToBlizz = TryBindIconToBlizz

-- Retry binding for icons that lost their initial bind because Blizzard's
-- viewer hadn't created a child for the cdID yet. The mirror invokes this
-- via its OnChildBound listener (fired from BindNewChildren) after a new
-- cdID is freshly indexed mid-session — typical case: DT's buff cdID is
-- created lazily by BuffIconCooldownViewer when the buff applies, well
-- after addon load.
--
-- Filter heuristic: only retry icons whose entry's viewerType matches
-- the bound child's category (or that have no Blizzard-mapping
-- viewerType — custom-bar entries probe all categories during bind).
-- Skips icons that are already bound; TryBindIconToBlizz would otherwise
-- clear-and-rebind on a transient miss, which we want to avoid.
local function CategoryMatchesViewerType(catName, viewerType)
    if not catName then return false end
    if catName == "essential" or catName == "utility" then
        return viewerType == "essential" or viewerType == "utility"
            or viewerType == nil or type(viewerType) ~= "string"
            or not (viewerType == "buff" or viewerType == "trackedBar")
    end
    if catName == "buff" or catName == "trackedBar" then
        return viewerType == "buff" or viewerType == "trackedBar"
            or viewerType == nil or type(viewerType) ~= "string"
            or not (viewerType == "essential" or viewerType == "utility")
    end
    return false
end

local function RetryUnboundIconsForChild(cdID, catName)
    if not (cdID and catName) then return end
    for _, pool in pairs(iconPools) do
        if type(pool) == "table" then
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry
                    and icon._blizzMirrorCooldownID == nil
                    and CategoryMatchesViewerType(catName, entry.viewerType) then
                    TryBindIconToBlizz(icon, entry)
                end
            end
        end
    end
end

local function ApplyMirrorStackText(icon, mirrorState, showZero)
    if not (icon and mirrorState and mirrorState.stackTextShown == true) then
        return false
    end
    if not (CDMIcons and CDMIcons.ApplyAuraCountText) then
        return false
    end

    local stackText = mirrorState.stackText
    if stackText == nil then
        return false
    end

    local count = icon._mirrorStackCountPayload
    if not count then
        count = {}
        icon._mirrorStackCountPayload = count
    end
    count.sinkText = stackText
    count.value = stackText
    count.shown = true
    count.source = mirrorState.stackTextSource or "Applications"

    CDMIcons.ApplyAuraCountText(icon, count, showZero, true)
    icon._lastMirrorStackTextEpoch = mirrorState.stackTextEpoch
    return true
end

-- Register the listener with the mirror as soon as the mirror module is
-- available. The icon factory loads after the mirror per cdm.xml, so
-- ns.CDMBlizzMirror should be present already; gate on existence to keep
-- load-order assumptions explicit.
if ns.CDMBlizzMirror and ns.CDMBlizzMirror.AddOnChildBoundListener then
    ns.CDMBlizzMirror.AddOnChildBoundListener(RetryUnboundIconsForChild)
end


-- DRIVER

local function SyncBlizzMirrorIconState(icon)
    local entry = icon and icon._spellEntry
    local cooldownID = icon and icon._blizzMirrorCooldownID
    if not (entry and cooldownID) then return false end

    local runtimeSid = entry.spellID or entry.overrideSpellID or entry.id
    if runtimeSid and not IsAuraEntry(entry) then
        local ovId = QueryOverrideSpell(runtimeSid)
        if ovId then runtimeSid = ovId end
    end
    icon._runtimeSpellID = runtimeSid
    local debugBlizz
    if _G.QUI_CDM_BLIZZ_DEBUG or _G.QUI_CDM_ICON_DEBUG then
        debugBlizz = ShouldDebugBlizzEntry(entry, {
            runtimeSid,
            entry.spellID,
            entry.overrideSpellID,
            entry.id,
        })
    end

    local mirror = ns.CDMBlizzMirror
    local m = mirror and mirror.GetStateByCooldownID
        and mirror.GetStateByCooldownID(cooldownID, icon._blizzMirrorCategory)
    if not m then
        if debugBlizz then
            DebugBlizzEntry(debugBlizz, entry, "state-sync-missing", "cdID=", tostring(cooldownID))
        end
        return false
    end

    local isAuraBacked = IsAuraEntry(entry)
        or m.viewerCategory == "buff"
        or m.viewerCategory == "trackedBar"
    if not isAuraBacked then
        if debugBlizz then
            DebugBlizzEntry(debugBlizz, entry, "state-sync-skip-cooldown", FormatMirrorState(m))
        end
        return false
    end

    local r
    if ResolveAuraStateForIcon and runtimeSid then
        r = ResolveAuraStateForIcon(icon, entry, runtimeSid)
    end

    -- Mirror is authoritative for Blizzard-mirrored icons. `m` is the mirror
    -- state for the exact cdID this icon is bound to.
    -- The resolver's `r.isActive` can come from a different cdID's aura
    -- (spellID→cdID maps have collisions: e.g. VP and Dread Plague both
    -- carry info.spellID=77575, so Outbreak's spellID resolves to whichever
    -- cdID was written last in the per-category map). Trusting `r` for
    -- this icon's display would let an unrelated aura's state — including
    -- its durObj — leak onto this icon. Use the mirror only.
    local mirrorActive = m.isActive == true
    local auraUnit = (m.selfAura == false) and "target" or "player"

    -- Taint diagnostic: log the m.* fields we're about to compare against
    -- so we can see whether they're secret in the user's environment.
    -- m.selfAura should be a clean bool/nil after CleanBool; if it shows
    -- as <SECRET> here, the sanitization missed it (probably need a
    -- broader strip or the C_CurveUtil decode is failing).
    local mirrorMod = ns.CDMBlizzMirror
    if _G.QUI_CDM_TAINT_DEBUG and mirrorMod and mirrorMod.TaintLog then
        mirrorMod.TaintLog("Sync.in",
            "cdID", cooldownID,
            "runtimeSid", runtimeSid,
            "m.isActive", m.isActive,
            "m.selfAura", m.selfAura,
            "m.hasAura", m.hasAura,
            "m.spellID", m.spellID,
            "m.overrideTooltipSpellID", m.overrideTooltipSpellID,
            "m.durObj", m.durObj,
            "m.hasAuraInstanceID", m.hasAuraInstanceID,
            "m.auraUnit", m.auraUnit,
            "r.isActive", r and r.isActive,
            "r.durObj", r and r.durObj,
            "r.auraInstanceID", r and r.auraInstanceID,
            "r.auraUnit", r and r.auraUnit,
            "r.durationStateUnknown", r and r.durationStateUnknown,
            "m.viewerCategory", m.viewerCategory,
            "auraUnit", auraUnit,
            "mirrorActive", mirrorActive)
    end

    -- Aura duration is owned by the mirror. Prefer the Blizzard child
    -- DurationObject when it exists; UNIT_AURA duration objects are the
    -- fallback. Icon sync is a pure consumer: if m.durObj is nil, render the
    -- active aura without a swipe and wait for the next mirror stamp.
    local durObj = m.durObj
    local durObjSource = durObj and (m.durObjSource or "mirror") or nil
    local fallbackFoundAura = false
    local fallbackInstID

    -- Activeness is "is the aura on the unit", NOT "do we have a swipe
    -- duration". A durationless aura (form, stance, permanent buff) is
    -- active without a durObj — the icon should display, just without
    -- a countdown swipe.
    local active = mirrorActive or fallbackFoundAura or (durObj and true or false)
    DebugBlizzSyncSnapshot(debugBlizz, icon, entry, m, r, active, mirrorActive,
        fallbackFoundAura, durObj, durObjSource)
    local priorActive = icon._auraActive == true
    local priorEpoch = icon._lastBlizzSwipeEpoch
    local priorHadAuraDurObj = icon._lastAuraDurObj and true or false
    icon._auraActive = active
    icon._auraUnit = auraUnit
    icon._auraInstanceID = active and m.auraInstanceID or nil
    icon._totemSlot = entry._totemSlot or nil
    icon._isTotemInstance = nil

    if _G.QUI_CDM_TAINT_DEBUG and ns.CDMBlizzMirror and ns.CDMBlizzMirror.TaintLog then
        ns.CDMBlizzMirror.TaintLog("Sync.out",
            "cdID", cooldownID,
            "active", active,
            "mirrorActive", mirrorActive,
            "fallbackFoundAura", fallbackFoundAura,
            "durObjSource", durObjSource,
            "durObj", durObj,
            "fallbackInstID", fallbackInstID)
    end

    if active then
        icon._lastAuraDurObj = durObj
        icon._lastAuraSourceID = (durObjSource or "mirror")
            .. ":" .. tostring(cooldownID)
            .. ":" .. tostring(m.mirrorEpoch or 0)
        icon._activeAuraSpellID = m.overrideTooltipSpellID or runtimeSid
        -- Aura type for pandemic glow gating. The mirror path doesn't
        -- carry auraData; use auraUnit as a proxy — same convention as
        -- the spellID-fallback's HARMFUL/HELPFUL filter selection above
        -- (target → harmful, player/non-target → helpful).
        icon._auraIsHarmful = (auraUnit == "target") and true or false
    else
        icon._lastAuraDurObj = nil
        icon._lastAuraSourceID = nil
        icon._activeAuraSpellID = nil
        icon._auraIsHarmful = nil
    end

    local priorPandemicKnown = icon._blizzPandemicStateKnown == true
    local priorPandemicActive = icon._blizzPandemicActive == true
    if m.pandemicStateKnown == true then
        icon._blizzPandemicActive = m.pandemicActive == true
        icon._blizzPandemicStateKnown = true
    else
        icon._blizzPandemicActive = nil
        icon._blizzPandemicStateKnown = nil
    end
    if priorPandemicKnown ~= (icon._blizzPandemicStateKnown == true)
        or priorPandemicActive ~= (icon._blizzPandemicActive == true) then
        local glows = ns._OwnedGlows
        if glows and glows.UpdatePandemicGlow then
            glows.UpdatePandemicGlow(icon)
        end
    end

    if active then
        local mirrorStackApplied = ApplyMirrorStackText(icon, m, entry.hasCharges)
        if m.stackTextShown == false then
            if CDMIcons and CDMIcons.ClearIconStackText then
                CDMIcons.ClearIconStackText(icon)
            end
            icon._lastMirrorStackTextEpoch = m.stackTextEpoch
        elseif not mirrorStackApplied
            and r and r.isActive and not r.isTotemInstance
            and CDMIcons and CDMIcons.ApplyAuraCountText then
            local preserveMissingCount = InCombatLockdown()
            CDMIcons.ApplyAuraCountText(icon, r.count, entry.hasCharges, preserveMissingCount)
            icon._lastMirrorStackTextEpoch = m.stackTextEpoch
        elseif not mirrorStackApplied
            and not InCombatLockdown()
            and CDMIcons and CDMIcons.ClearIconStackText then
            -- Only clear when neither mirror nor resolver applied a count.
            -- Without the mirrorStackApplied guard, this branch erases the
            -- text that ApplyMirrorStackText just wrote whenever stackText
            -- is shown but the resolver fallback didn't fire (regression
            -- introduced when stack-text apply moved into ApplyMirrorStackText).
            CDMIcons.ClearIconStackText(icon)
        end
    else
        if CDMIcons and CDMIcons.ClearIconStackText then
            CDMIcons.ClearIconStackText(icon)
        end
        if icon.Icon then
            local baseTex = GetEntryTexture(entry) or GetSpellTexture(runtimeSid)
            icon._desiredTexture = nil
            if baseTex and baseTex ~= icon._lastTexture then
                icon.Icon.SetTexture(icon.Icon, baseTex)
                icon._lastTexture = baseTex
            end
        end
    end

    local epoch = m.mirrorEpoch or 0
    -- Multi-field change-detection (replaces a per-tick `cat..":"..tostring(cdID)..":"..tostring(epoch)`
    -- string concatenation that was ~150 KB/s of garbage in raid combat).
    local mirrorActiveDur = active and durObj
    local newSrcCat   = mirrorActiveDur and (durObjSource or "mirror") or nil
    local newSrcCDID  = mirrorActiveDur and cooldownID or nil
    local newSrcEpoch = mirrorActiveDur and epoch or nil
    local priorSrcCat   = icon._lastMirrorNativeAuraSourceCat
    local priorSrcCDID  = icon._lastMirrorNativeAuraSourceCDID
    local priorSrcEpoch = icon._lastMirrorNativeAuraSourceEpoch
    icon._lastMirrorNativeAuraSourceCat   = newSrcCat
    icon._lastMirrorNativeAuraSourceCDID  = newSrcCDID
    icon._lastMirrorNativeAuraSourceEpoch = newSrcEpoch
    icon._mirrorNativeDurObjApplied = nil

    icon._lastBlizzSwipeEpoch = epoch
    if priorActive ~= active
       and entry.viewerType == "buff"
       and CDMIcons
       and CDMIcons.RequestBuffIconLayoutRefresh then
        CDMIcons.RequestBuffIconLayoutRefresh()
    end
    local durationSourceChanged = priorSrcCat ~= newSrcCat
        or priorSrcCDID ~= newSrcCDID
        or priorSrcEpoch ~= newSrcEpoch
        or priorHadAuraDurObj ~= (durObj and true or false)
    if debugBlizz and (priorActive ~= active or priorEpoch ~= epoch or durationSourceChanged) then
        DebugBlizzEntry(debugBlizz, entry, "state-sync",
            FormatMirrorState(m),
            "runtimeSid=", tostring(runtimeSid),
            "durObjSource=", tostring(durObjSource),
            "fallbackInstID=", tostring(fallbackInstID),
            "source=", tostring(icon._lastAuraSourceID),
            "durationSourceChanged=", tostring(durationSourceChanged))
    end
    return priorActive ~= active or priorEpoch ~= epoch or durationSourceChanged
end

local function UpdateIconCooldown(icon)
    if not icon or not icon._spellEntry then return end
    -- Blizzard-mirrored aura icons render with QUI-native widgets from the
    -- exact cID mirror. The Blizzard child stays in its own viewer.
    if icon._blizzMirrorCooldownID and IsAuraEntry(icon._spellEntry) then
        local refreshSwipe = SyncBlizzMirrorIconState(icon)
        local resolvedSwipe = false
        if ApplyResolvedCooldown then
            resolvedSwipe = ApplyResolvedCooldown(icon) == true
        end
        if refreshSwipe or resolvedSwipe then
            local swipe = ns._OwnedSwipe
            if swipe and swipe.ApplyToIcon then
                swipe.ApplyToIcon(icon)
            end
        end
        return
    end
    local entry = icon._spellEntry
    local stackTextWritesAllowed = CDMIcons.ShouldAllowStackTextWrites and CDMIcons.ShouldAllowStackTextWrites() == true

    -- Runtime override: resolve from the BASE spell each tick so dynamic
    -- transforms (Glacial Spike ↔ Frostbolt, Mind Blast → Void Blast)
    -- are always current.  Shared across all paths in this function.
    local _runtimeSid = entry.spellID or entry.overrideSpellID or entry.id
    if _runtimeSid and not IsAuraEntry(entry) then
        local ovId = QueryOverrideSpell(_runtimeSid)
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

                    if r.isActive then
                        ApplyAuraStateToIcon(icon, entry, auraSpellID, r)

                        -- Count text: forward resolver sink text directly to
                        -- C-side where possible. Blizzard aura APIs can return
                        -- secret values in combat, so Lua only reads the safe
                        -- count.value field.
                        if r.isTotemInstance then
                            CDMIcons.ClearIconStackText(icon)
                        else
                            CDMIcons.ApplyAuraCountText(icon, r.count, entry.hasCharges, InCombatLockdown())
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
                                    icon.Icon.SetTexture(icon.Icon, totemTex)
                                    icon._lastTexture = totemTex
                                    mirrored = true
                                end
                            end
                            -- Drive icon from r.auraData.icon (live aura icon
                            -- for buff-cycle spells like Roll the Bones), then
                            -- fall back to the base aura spell texture.
                            if not mirrored and not r.isTotemInstance then
                                local texID
                                if r.auraData then
                                    local aIcon = SafeValue(r.auraData.icon, nil)
                                    if aIcon and aIcon ~= 0 then texID = aIcon end
                                end
                                if not texID then
                                    texID = GetSpellTexture(r.resolvedAuraSpellID or auraSpellID)
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

                        if icon.Icon then
                            local baseTex = GetEntryTexture(entry) or GetSpellTexture(auraSpellID)
                            icon._desiredTexture = nil
                            if baseTex and baseTex ~= icon._lastTexture then
                                icon.Icon.SetTexture(icon.Icon, baseTex)
                                icon._lastTexture = baseTex
                            end
                        end

                        CDMIcons.ClearIconStackText(icon)
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
                    local _, _, _, _, tex
                    if Sources and Sources.QueryItemInfoInstant then
                        _, _, _, _, tex = Sources.QueryItemInfoInstant(resolvedID)
                    end
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
            local itemID
            if Sources and Sources.QueryInventoryItemID then
                itemID = Sources.QueryInventoryItemID("player", slotID)
            end
            if itemID then
                startTime, duration, durObj = GetSlotCooldown(slotID)
                -- Update texture in case trinket was swapped
                if icon.Icon then
                    local tex
                    if Sources and Sources.QueryItemIconByID then
                        tex = Sources.QueryItemIconByID(itemID)
                    end
                    if tex and tex ~= icon._lastTexture then
                        icon.Icon:SetTexture(tex)
                        icon._lastTexture = tex
                        UpdateIconProfessionQuality(icon)
                    end
                end
            end
            -- Hide stack text for trinkets
            if stackTextWritesAllowed then
                CDMIcons.HideIconStackText(icon, "slot-clear")
            end
        elseif entry.type == "item" then
            startTime, duration, durObj = GetItemCooldown(entry.id)
            -- Show item count/charges as stack text using legacy custom tracker semantics.
            if stackTextWritesAllowed and Sources and Sources.QueryItemCount then
                local containerDB = CDMIcons.GetTrackerSettings(entry.viewerType)
                local includeUses = containerDB and containerDB.showItemCharges == true
                local count = Sources.QueryItemCount(entry.id, false, includeUses, true)
                if count then
                    local stackColor = icon._rowConfig and icon._rowConfig.stackTextColor or {1, 1, 1, 1}
                    do
                        local numericCount = count or 0
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
            -- Unified non-item path: entries detect aura state via the
            -- resolver unless cooldown-icon aura phase is disabled. No
            -- Blizzard CDM viewer child reads.
            local _chargedAuraActive = false
            local _chargedTotemTexture = nil
            local useBuffSwipe = CDMIcons.ShouldUseBuffSwipeForIcon(icon, entry)
            if useBuffSwipe then
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
                    -- Non-charged aura entries (e.g. Mana Tea added via the
                    -- cooldown CDM picker / a custom container) write count
                    -- text here from the shared resolver payload. Charged
                    -- entries skip this so the cooldownChargesCount forwarding
                    -- path can drive the StackText for them.
                    if not entry.hasCharges and not IsTotemSlotEntry(entry) then
                        CDMIcons.ApplyAuraCountText(icon, r.count, false, InCombatLockdown())
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
            elseif icon._auraActive then
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
                then
                    local aliasID = CDMIcons.GetRecentCastAliasForEntry(entry)
                    if aliasID and aliasID ~= _runtimeSid then
                        local aStart, aDuration, aDurObj, aActive, aRealActive = GetBestSpellCooldown(aliasID)
                        if aDurObj or (CDMIcons.IsSafeNumeric(aStart) and CDMIcons.IsSafeNumeric(aDuration) and aDuration > GCD_MAX_DURATION) then
                            if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
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
                -- the cooldown source isActive signal in
                -- ApplyResolvedCooldown.
            end

            -- isOnGCD was captured synchronously in SPELL_UPDATE_COOLDOWN;
            -- this query is for active/duration data only.
            local _tickCi = QueryCooldown(_runtimeSid)
            if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
                CDMIcons.DebugIconEvent(icon, "resolve",
                    "sid=", tostring(_runtimeSid),
                    "start=", tostring(startTime),
                    "duration=", tostring(duration),
                    "durObj=", durObj and "yes" or "no",
                    "apiActive=", tostring(apiIsActive),
                    "isOnGCD=", tostring(icon._isOnGCD),
                    "hasCharges=", tostring(entry.hasCharges),
                    "kind=", tostring(entry.kind),
                    "type=", tostring(entry.type))
            end
            -- Texture: mirror runtime override each tick. Keeps
            -- _desiredTexture set so per-tick texture writes never
            -- regress to a stale value, while updating for talent swaps.
            -- Aura entries leave _desiredTexture nil so the active aura's
            -- icon (set on the active branch above) wins.
            if icon.Icon and _chargedAuraActive and _chargedTotemTexture then
                icon._desiredTexture = nil
                icon.Icon.SetTexture(icon.Icon, _chargedTotemTexture)
                icon._lastTexture = _chargedTotemTexture
            elseif icon.Icon and not entry.isAura then
                local texID = GetSpellTexture(_runtimeSid)
                if texID then
                    if icon._desiredTexture ~= texID then
                        icon._desiredTexture = texID
                        icon.Icon.SetTexture(icon.Icon, texID)
                    end
                end
            elseif icon.Icon then
                icon._desiredTexture = nil
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
            -- aura-kind state, then real cooldown/recharge, then GCD.
            -- isOnGCD is only used when this batch came from
            -- SPELL_UPDATE_COOLDOWN; outside that event it can be stale.
            local auraSwipeActive = icon._auraActive or IsAuraEntry(entry)
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
            -- (cooldown source isActive in ApplyResolvedCooldown).
            if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
                CDMIcons.DebugIconEvent(icon, "classify",
                    "real=", tostring(realCooldownActive),
                    "gcdOnly=", tostring(gcdOnlyActive),
                    "gcdTrusted=", tostring(trustIsOnGCD),
                    "gcdSnapshot=", tostring(gcdStateTrusted),
                    "durationOwned=", tostring(activeDurationOwned),
                    "blizzReal=", tostring(blizzRealCooldownActive),
                    "durObj=", durObj and "yes" or "no")
            end
            -- Per-tick chain does NOT touch cooldown flags or icon.Cooldown.
            -- ApplyResolvedCooldown (event-driven via UNIT_SPELLCAST_SUCCEEDED,
            -- owned UNIT_AURA refresh, SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_USABLE) is the
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
                -- desaturation gate opens. Reset _lastVisualState so the
                -- range poll can reapply usability tint after the CD ends.
                --
                -- Gate on the resolver's current mode classification, NOT
                -- on HasRealCooldownState. The resolver is the single
                -- authority on real-CD state; reading any other signal here
                -- (numeric durations, _lastDuration, etc.) re-introduces
                -- the stale-state flicker we removed from the resolver
                -- helpers. Allowed real-CD modes are exactly the modes
                -- ApplyCooldownDesaturation classifies as hasRealCD=true
                -- (cdm_icons.lua:1217-1220): cooldown / charge /
                -- item-cooldown.
                local resolvedMode = icon._resolvedCooldownMode
                local cooldownActiveForState =
                    resolvedMode == "cooldown"
                    or resolvedMode == "charge"
                    or resolvedMode == "item-cooldown"
                if cooldownActiveForState and icon._usabilityTinted then
                    icon.Icon:SetVertexColor(1, 1, 1, 1)
                    icon._usabilityTinted = nil
                    icon._lastVisualState = nil
                end
                -- _hasCooldownActive is owned by the resolver
                -- (cooldown source isActive in
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

    -- Stack/charge text: mirror-first. API charge text is only a fallback
    -- for icons without a mirror-backed stack decision.
    -- Cache chargeInfo for this icon — reused by desaturation check below
    -- (was called 3x per cooldown icon per tick, now 1x)
    local _cachedChargeInfo = nil
    local _cachedChargeOk = false

    -- Populate _cachedChargeInfo unconditionally (needed for desaturation
    -- check below), independent of whether hooks are driving stack text.
    do
        local spellID = _runtimeSid
        if spellID then
            local chargeInfo = QueryCharges(spellID)
            _cachedChargeOk = chargeInfo ~= nil
            _cachedChargeInfo = chargeInfo
        end
    end

    local _stackTextResolved = false
    local _stackVal  -- raw value (may be secret), forwarded to C-side
    local _stackSource
    local _stackMirrorBacked = false
    local _stackMirrorEmpty = false

    if stackTextWritesAllowed and entry.type == "spell" and CDMIcons.ResolveIconStackText then
        _stackVal, _stackSource, _stackMirrorBacked = CDMIcons.ResolveIconStackText(icon)
        _stackTextResolved = true
        if _stackMirrorBacked and CDMIcons.ValueIsMissing(_stackVal) then
            _stackMirrorEmpty = true
            CDMIcons.HideIconStackText(icon, "mirror-stack-empty")
            icon._stackTextSource = nil
        end
    end

    -- Forward charge count from the source facade only when the mirror did
    -- not already decide stack text for this icon.
    local _chargeCountForwarded = false
    if not _stackMirrorBacked then
        local baseSid = entry.spellID or entry.id
        local ci = baseSid and QueryCharges(baseSid)
        local ciMax = ci and ci.maxCharges
        -- When the base spell transforms (e.g., Holy Bulwark → Sacred Weapon),
        -- GetSpellCharges on the base ID may return nil/<=1 even though the
        -- spell is still multi-charge.  Try the override spell ID as fallback.
        if (not ciMax or ciMax <= 1)
            and entry.overrideSpellID and entry.overrideSpellID ~= baseSid then
            local oci = QueryCharges(entry.overrideSpellID)
            local ociMax = oci and oci.maxCharges
            if ociMax and ociMax > 1 then
                ci = oci
                ciMax = ociMax
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "FWD override fallback: overrideSpellID=", entry.overrideSpellID,
                        "maxCharges=", ociMax, "currentCharges=", oci.currentCharges)
                end
            end
        end
        if ciMax and ciMax > 1 then
            -- Source the live charge count through the facade so we don't
            -- depend on any Blizzard CDM viewer child carrying the field.
            -- ci.currentCharges is the same value Blizzard's own viewer reads
            -- when populating cooldownChargesCount for charge spells.
            local ccc = ci.currentCharges
            if _G.QUI_CDM_CHARGE_DEBUG then
                local _dbgCccSource = ccc ~= nil and "api" or nil
                ChargeDebug(entry.name, "FWD path: baseSid=", baseSid,
                    "maxCharges=", ciMax, "currentCharges=", ci.currentCharges,
                    "ccc=", ccc, "cccSource=", _dbgCccSource or "nil",
                    "hasCharges=", entry.hasCharges,
                    "overrideSpellID=", entry.overrideSpellID)
            end
            if ccc ~= nil and stackTextWritesAllowed then
                CDMIcons.ShowIconStackText(icon, ccc, CDMIcons.GetTrackerSettings(entry.viewerType), "fwd-charge-count")
                _chargeCountForwarded = true
            end
        end
    end

    -- Charged entries where the FWD path couldn't find charges fall through
    -- to the API path below for the owned StackText value.

    if _G.QUI_CDM_CHARGE_DEBUG and _chargeCountForwarded then
        ChargeDebug(entry.name, "SKIP API path: chargeCountForwarded=", _chargeCountForwarded)
    end
    if not _chargeCountForwarded and stackTextWritesAllowed then
        if entry.type == "item" then
            -- Item stack text was already set above in the cooldown section;
            -- nothing to do here — just prevent the else clause from clearing it.
        elseif entry.type == "spell" then
            -- Custom spell entry: prefer mirror-captured text. Values may be
            -- secret in combat; pass directly to C-side functions when shown.
            local spellID = _runtimeSid
            local stackVal = _stackVal
            local stackSource = _stackSource
            local stackMirrorBacked = _stackMirrorBacked
            local stackMirrorEmpty = _stackMirrorEmpty

            if not _stackTextResolved and CDMIcons.ResolveIconStackText then
                stackVal, stackSource, stackMirrorBacked = CDMIcons.ResolveIconStackText(icon)
            end

            -- Only show charge count when maxCharges is readable and > 1
            -- (multi-charge spell).
            local cachedMaxCharges = _cachedChargeInfo and _cachedChargeInfo.maxCharges
            local isMultiCharge = cachedMaxCharges and cachedMaxCharges > 1

            if stackMirrorBacked and CDMIcons.ValueIsMissing(stackVal) then
                if not stackMirrorEmpty then
                    stackMirrorEmpty = true
                    CDMIcons.HideIconStackText(icon, "mirror-stack-empty")
                    icon._stackTextSource = nil
                end
            elseif CDMIcons.ValueIsMissing(stackVal) and isMultiCharge then
                -- GetSpellDisplayCount is the canonical charge display API.
                if spellID then
                    stackVal = QueryDisplayCount(spellID)
                    if CDMIcons.ValueIsPresent(stackVal) then
                        stackSource = "spell-display-count"
                    end
                end
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "API path: spellID=", spellID,
                        "maxCharges=", _cachedChargeInfo.maxCharges,
                        "currentCharges=", _cachedChargeInfo.currentCharges,
                        "displayCount=", stackVal, "isMultiCharge=", isMultiCharge)
                end
            elseif CDMIcons.ValueIsMissing(stackVal) then
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "no stack text: spellID=", spellID,
                        "mirrorBacked=", tostring(stackMirrorBacked),
                        "isMultiCharge=", tostring(isMultiCharge))
                end
            end


            -- Forward to C-side for display. Multi-charge spells always
            -- show their count (including "0" when depleted). Non-charge
            -- mirror text uses TruncateWhenZero to hide zero.
            if CDMIcons.ValueIsPresent(stackVal) then
                if isMultiCharge then
                    -- Always show charge count — "0" is meaningful
                    CDMIcons.ShowIconStackText(icon, stackVal, CDMIcons.GetTrackerSettings(entry.viewerType), "api-charge-count")
                else
                    local displayText
                    if type(stackVal) == "number" then
                        displayText = C_StringUtil.TruncateWhenZero(stackVal)
                    else
                        displayText = stackVal
                    end
                    local hasText = HookTextHasDisplay(displayText)
                    if hasText then
                        CDMIcons.ShowIconStackText(icon, displayText, CDMIcons.GetTrackerSettings(entry.viewerType), stackSource or "api-aura-stack")
                    else
                        CDMIcons.HideIconStackText(icon, "api-aura-stack-empty")
                    end
                end
            elseif stackMirrorEmpty then
                -- Mirror-backed icons with no mirror stack text intentionally stay empty.
            elseif not InCombatLockdown() and not (entry and entry.hasCharges) then
                -- Don't hide charged-ability stack text on a transient API
                -- nil. UNIT_AURA on the target (from other players' buffs/
                -- debuffs) and PLAYER_SOFT_ENEMY_CHANGED both schedule full
                -- CDM updates; during those Blizzard's charge data and
                -- QueryDisplayCount can momentarily return nil even
                -- when the spell still has charges. Hiding here and
                -- re-showing on the next tick produced the visible "stacks
                -- flicker show/hide" symptom on every target aura change.
                -- The FWD path or the next tick's API read will restore the
                -- correct value; preserve the previous text in the gap.
                CDMIcons.HideIconStackText(icon, "api-stack-nil")
            end
        else
            -- Harvested entries and other types: API-read aura applications
            -- per-icon so each container renders the count independently.
            local stackVal = CDMIcons.GetAuraApplicationsForSpell(_runtimeSid, entry, icon)
            if CDMIcons.ValueIsPresent(stackVal) then
                local displayText
                if type(stackVal) == "number" then
                    displayText = C_StringUtil.TruncateWhenZero(stackVal)
                else
                    displayText = stackVal
                end
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

    -- Desaturation is owned by the resolver (ApplyResolvedCooldown).
    -- Per-tick batch must not re-apply it here — that race against the
    -- resolver's release for mirror-backed icons produced visible flicker.

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

---------------------------------------------------------------------------
-- DEFERRED IMPORT BINDING
-- Called from the tail of cdm_icons.lua once ns.CDMIcons is fully populated
-- (including all `CDMIcons.X = X` exposure lines). Reassigns the file-level
-- upvalues; every function defined in this file closes over those upvalues,
-- so they all see the late-bound values.
---------------------------------------------------------------------------
function CDMIconFactory._FinalizeImports(icons)
    CDMIcons                    = icons
    GetBestSpellCooldown        = icons.GetBestSpellCooldown
    GetItemCooldown             = icons.GetItemCooldown
    GetSlotCooldown             = icons.GetSlotCooldown
    IsTotemSlotEntry            = icons.IsTotemSlotEntry
    ApplyAuraStateToIcon        = icons.ApplyAuraStateToIcon
    ApplyResolvedCooldown       = icons.ApplyResolvedCooldown
    ReapplySwipeStyle           = icons.ReapplySwipeStyle
    UpdateIconProfessionQuality = icons.UpdateIconProfessionQuality
    HookTextHasDisplay          = icons.HookTextHasDisplay
end

---------------------------------------------------------------------------
-- DEBUG IMPORT BINDING
-- ChargeDebug, ShouldDebugBlizzEntry, FormatMirrorState, DebugBlizzEntry
-- are defined by the load-on-demand debug addon. Hot-path callers in this file
-- keep their existing local-upvalue calls.
---------------------------------------------------------------------------
function CDMIconFactory._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        ChargeDebug            = d.Charge        or ChargeDebug
        ShouldDebugBlizzEntry  = d.ShouldBlizz   or ShouldDebugBlizzEntry
        FormatMirrorState      = d.FormatMirrorState or FormatMirrorState
        FormatIDList           = d.FormatIDList  or FormatIDList
        DebugBlizzEntry        = d.Blizz         or DebugBlizzEntry
    end
end
