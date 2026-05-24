-- cdm_icon_renderer.lua
-- Consolidated hot-path module. Keep former file chunks scoped so Lua 5.1 local limits stay isolated.

do
-- Inlined from cdm_icon_factory.lua
-- cdm_icon_factory.lua
-- Icon pool lifecycle and mirror binding adapters for the QUI CDM owned
-- engine. CDMIcons owns the public runtime update interface.

local _, ns = ...
local Helpers = ns.Helpers
local Resolvers = ns.CDMResolvers
local Sources = ns.CDMSources
local Shared = ns.CDMShared

local CDMIconFactory = {}
ns.CDMIconFactory = CDMIconFactory

local function GetIcons()
    return ns.CDMIcons
end

---------------------------------------------------------------------------
-- LOCAL UPVALUE ALIASES
---------------------------------------------------------------------------
local GetGeneralFont        = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local GetEntryTexture       = Resolvers.GetEntryTexture
local GetSpellTexture       = Resolvers.GetSpellTexture

local InCombatLockdown = InCombatLockdown
local CreateFrame      = CreateFrame
local type             = type

---------------------------------------------------------------------------
-- CONSTANTS (kept local to the icon factory/runtime chunks)
---------------------------------------------------------------------------
local DEFAULT_ICON_SIZE      = 39
local MAX_RECYCLE_POOL_SIZE  = 20

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

local function CreateIconPool()
    return {}
end

function CDMIconFactory:GetIconPool(viewerType)
    return iconPools[viewerType] or {}
end

function CDMIconFactory:ForEachIcon(callback)
    if not callback then return end
    for viewerType, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            callback(icon, viewerType)
        end
    end
end

function CDMIconFactory:EnsurePool(viewerType)
    if not iconPools[viewerType] then
        iconPools[viewerType] = CreateIconPool()
    end
    return iconPools[viewerType]
end

function CDMIconFactory:ClearPool(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        for _, icon in ipairs(pool) do
            self:ReleaseIcon(icon)
        end
        wipe(pool)
    else
        iconPools[viewerType] = CreateIconPool()
    end
    return iconPools[viewerType]
end

-- Expose pool tables so renderer code can read the same table object while
-- factory remains the writer for frame lifecycle and pool membership.
CDMIconFactory._iconPools   = iconPools
CDMIconFactory._recyclePool = recyclePool

---------------------------------------------------------------------------
-- ICON CREATION — BARE
-- Pure frame construction: tree + textures + default fonts + initial
-- spell texture. No runtime hooks (mirror binding, tooltip, mouseover,
-- factory callbacks). Used by both the runtime CreateIcon path and the
-- preview AcquireForPreview path.
---------------------------------------------------------------------------
local function CreateIconBare(parent, spellEntry)
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

    -- Set a default font so SetText() never fires before row styling applies.
    local defaultFont = GetGeneralFont()
    local defaultOutline = GetGeneralFontOutline()
    icon.DurationText:SetFont(defaultFont, 10, defaultOutline)
    icon.StackText:SetFont(defaultFont, 10, defaultOutline)

    -- Metadata
    icon._spellEntry = spellEntry
    icon._isQUICDMIcon = true

    -- Set initial texture.
    -- Aura entries: dynamic buff icon (e.g., Roll the Bones → Broadside)
    -- arrives via the per-tick UpdateIconCooldown path, which reads the
    -- live aura's icon from r.auraData.icon. Initial icon is the
    -- composer-resolved entry texture.
    if spellEntry then
        local texID
        if spellEntry.type then
            texID = GetEntryTexture(spellEntry)
        else
            texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
        end
        if texID then
            icon.Icon:SetTexture(texID)
            -- Only lock texture for cooldown entries — aura icons rely on
            -- the tick update + Blizzard texture hook for dynamic changes.
            if not spellEntry.isAura then
                icon._desiredTexture = texID
            end
        end
    end

    -- Note: frame is NOT hidden here. Runtime callers go through
    -- CreateIcon, which calls icon:Hide() at the end. Preview callers
    -- (CDMIconFactory.AcquireForPreview) manage visibility themselves.
    return icon
end

---------------------------------------------------------------------------
-- ICON CREATION — RUNTIME
-- Adds runtime-only hooks on top of CreateIconBare: mouseover, factory
-- callback, tooltip OnEnter/OnLeave. Preview path skips this layer.
---------------------------------------------------------------------------
local function CreateIcon(parent, spellEntry)
    local icon = CreateIconBare(parent, spellEntry)

    -- Mouseover hover wiring (reads live runtime state)
    if ns.HookFrameForMouseover then
        ns.HookFrameForMouseover(icon)
    end

    -- Notify icons module that a new factory icon was created.
    if spellEntry then
        local icons = GetIcons()
        if icons and icons.OnFactoryIconCreated then
            icons.OnFactoryIconCreated(icon, spellEntry)
        end
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
                local itemID = (Sources and Sources.QueryBestOwnedItemVariant
                    and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
                GameTooltip.SetItemByID(GameTooltip, itemID)
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
    local icons = GetIcons()
    local icon = table.remove(recyclePool)
    if icon then
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
        icon._wasResolvedCooldownActive = nil
        icon._lastAuraDurObj = nil
        icon._lastAuraSourceID = nil
        icon._hasCooldownActive = nil
        icon._hasRealCooldownActive = nil
        icon._resolvedCooldownMode = nil
        icon._runtimeSpellID = nil
        icon._isTotemInstance = nil
        icon._totemSlot = spellEntry and spellEntry._totemSlot or nil
        icon._totemIconCache = nil
        icon._pendingTotemSlotRefresh = nil
        icon._customBarActive = nil
        icon._customBarActiveType = nil
        icon._customBarActiveStart = nil
        icon._customBarActiveDuration = nil
        icon.cooldownChargesCount = nil
        icon.cooldownChargesShown = nil
        icon.chargeCountFrameShown = nil
        icon.chargeTextOwnerShown = nil
        icon.stackText = nil
        icon.stackTextSource = nil
        icon.stackTextShown = nil
        icon.stackTextEpoch = nil
        icon.wasSetFromCooldown = nil
        icon.wasSetFromCharges = nil

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

        if icon.Cooldown then
            icon.Cooldown:Clear()
        end
        icon.StackText:SetText("")
        icon.StackText:Hide()
        if icons and icons.OnFactoryIconAcquired then
            icons.OnFactoryIconAcquired(icon, spellEntry, true)
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
    if icons and icons.OnFactoryIconAcquired then
        icons.OnFactoryIconAcquired(newIcon, spellEntry, false)
    end
    -- Bind to a Blizzard mirror child if this entry has one.
    CDMIconFactory.TryBindIconToBlizz(newIcon, spellEntry)
    -- Notify rotation helper that an icon was assigned a spell
    if ns._onIconAssigned then ns._onIconAssigned(newIcon) end
    return newIcon
end

function CDMIconFactory:ReleaseIcon(icon)
    if not icon then return end
    local icons = GetIcons()
    -- Drop any Blizzard mirror binding before the rest of release-state
    -- cleanup runs. Table-routed because the helper is defined later here.
    CDMIconFactory.ClearIconBlizzMirrorBinding(icon)
    if icons and icons.OnFactoryIconReleased then
        icons.OnFactoryIconReleased(icon)
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
    icon._wasResolvedCooldownActive = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
    icon._activeAuraSpellID = nil
    icon._auraIsHarmful = nil
    icon._lastTexture = nil
    icon._hasCooldownActive = nil
    icon._hasRealCooldownActive = nil
    icon._resolvedCooldownMode = nil
    icon._runtimeSpellID = nil
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
    icon.cooldownChargesCount = nil
    icon.cooldownChargesShown = nil
    icon.chargeCountFrameShown = nil
    icon.chargeTextOwnerShown = nil
    icon.stackText = nil
    icon.stackTextSource = nil
    icon.stackTextShown = nil
    icon.stackTextEpoch = nil
    icon.wasSetFromCooldown = nil
    icon.wasSetFromCharges = nil
    icon._blizzMirrorState = nil
    icon._blizzMirrorStateCooldownID = nil
    icon._blizzMirrorStateCategory = nil
    icon._blizzMirrorSourceID = nil
    icon._blizzMirrorSourceCooldownID = nil
    icon._blizzMirrorSourceEpoch = nil
    icon._blizzMirrorCooldownID = cooldownID
    icon._blizzMirrorCategory = viewerCategory
    ShowNativeIconWidgets(icon)
    local icons = GetIcons()
    if icons and icons.OnFactoryMirrorBound then
        icons.OnFactoryMirrorBound(icon, cooldownID, viewerCategory)
    end
end

local function ClearIconBlizzMirrorBinding(icon)
    if not icon or not icon._blizzMirrorCooldownID then return end
    local icons = GetIcons()
    if icons and icons.OnFactoryMirrorUnbound then
        icons.OnFactoryMirrorUnbound(icon)
    end
    icon._mirrorNativeDurObjApplied = nil
    icon._lastMirrorNativeAuraSourceCat = nil
    icon._lastMirrorNativeAuraSourceCDID = nil
    icon._lastMirrorNativeAuraSourceEpoch = nil
    icon.cooldownChargesCount = nil
    icon.cooldownChargesShown = nil
    icon.chargeCountFrameShown = nil
    icon.chargeTextOwnerShown = nil
    icon.stackText = nil
    icon.stackTextSource = nil
    icon.stackTextShown = nil
    icon.stackTextEpoch = nil
    icon.wasSetFromCooldown = nil
    icon.wasSetFromCharges = nil
    icon._blizzMirrorState = nil
    icon._blizzMirrorStateCooldownID = nil
    icon._blizzMirrorStateCategory = nil
    icon._blizzMirrorSourceID = nil
    icon._blizzMirrorSourceCooldownID = nil
    icon._blizzMirrorSourceEpoch = nil
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
local DebugBlizzEntry       = function() end

-- Resolve entry -> exact Blizzard mirror identity. Bars use the same resolver,
-- so entry type/category semantics stay centralized.
local function ResolveBlizzCooldownIDForEntry(entry)
    local resolver = Resolvers and Resolvers.ResolveBlizzardMirrorIdentityState
    if not (entry and resolver) then return nil end

    local debugBlizz
    if _G.QUI_CDM_BLIZZ_DEBUG or _G.QUI_CDM_ICON_DEBUG then
        debugBlizz = ShouldDebugBlizzEntry(entry)
        if debugBlizz then
            DebugBlizzEntry(debugBlizz, entry, "begin-shared")
        end
    end

    local identity = resolver(entry)
    if not (identity and identity.cooldownID) then
        if debugBlizz then
            DebugBlizzEntry(debugBlizz, entry, "miss")
        end
        return nil
    end

    if debugBlizz then
        DebugBlizzEntry(debugBlizz, entry, "resolved", FormatMirrorState(identity.state))
    end
    return identity.cooldownID, identity.category
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

---------------------------------------------------------------------------
-- PREVIEW ENTRY POINTS
-- Used by modules/cdm/settings/composer_preview_driver.lua to construct
-- icon frames inside the settings preview pane. Bypasses every runtime
-- coupling hook (mirror binding, rotation, tooltip, mouseover, factory
-- callbacks) so the preview can never contaminate the live CDM render.
---------------------------------------------------------------------------
function CDMIconFactory.AcquireForPreview(parent, spellEntry)
    local icon = CreateIconBare(parent, spellEntry)
    icon._isPreview = true
    icon:EnableMouse(false)  -- no tooltip; preview is non-interactive
    return icon
end

function CDMIconFactory.ReleaseForPreview(icon)
    if not icon or not icon._isPreview then return end
    icon:Hide()
    if icon.Cooldown then icon.Cooldown:Clear() end
    if icon.StackText then
        icon.StackText:SetText("")
        icon.StackText:Hide()
    end
    if icon.DurationText then
        icon.DurationText:SetText("")
        icon.DurationText:Hide()
    end
    if icon.Border then icon.Border:Hide() end
    icon:SetParent(nil)
    -- Preview icons are NOT returned to recyclePool: keeping the runtime
    -- pool free of preview-state contamination is a hard invariant.
end

-- Retry binding for icons that lost their initial bind because Blizzard's
-- viewer hadn't created a child for the cdID yet. The mirror invokes this
-- via its OnChildBound listener (fired from BindNewChildren) after a new
-- cdID is freshly indexed mid-session — typical case: DT's buff cdID is
-- created lazily by BuffIconCooldownViewer when the buff applies, well
-- after addon load.
--
-- Filter heuristic: only retry icons whose entry's built-in container
-- family matches the bound child's mirror category. Custom/unknown
-- container keys probe all categories during bind.
-- Skips icons that are already bound; TryBindIconToBlizz would otherwise
-- clear-and-rebind on a transient miss, which we want to avoid.
local function GetBuiltinContainerEntryKind(viewerType)
    if Shared and Shared.GetBuiltinContainerEntryKind then
        return Shared.GetBuiltinContainerEntryKind(viewerType)
    end
    return nil
end

local function IsCooldownMirrorCategory(category)
    if Shared and Shared.IsCooldownMirrorCategory then
        return Shared.IsCooldownMirrorCategory(category)
    end
    return GetBuiltinContainerEntryKind(category) == "cooldown"
end

local function IsAuraMirrorCategory(category)
    if Shared and Shared.IsAuraMirrorCategory then
        return Shared.IsAuraMirrorCategory(category)
    end
    return GetBuiltinContainerEntryKind(category) == "aura"
end

local function CategoryMatchesViewerType(catName, viewerType)
    if not catName then return false end
    local matchesCooldown = IsCooldownMirrorCategory(catName)
    local matchesAura = IsAuraMirrorCategory(catName)
    if not matchesCooldown and not matchesAura then
        return false
    end

    local entryKind = GetBuiltinContainerEntryKind(viewerType)
    if not entryKind then
        return true
    end
    if matchesCooldown then
        return entryKind == "cooldown"
    end
    return entryKind == "aura"
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

-- Register the listener with the mirror as soon as the mirror module is
-- available. The icon factory loads after the mirror per cdm.xml, so
-- ns.CDMBlizzMirror should be present already; gate on existence to keep
-- load-order assumptions explicit.
if ns.CDMBlizzMirror and ns.CDMBlizzMirror.AddOnChildBoundListener then
    ns.CDMBlizzMirror.AddOnChildBoundListener(RetryUnboundIconsForChild)
end

---------------------------------------------------------------------------
-- DEBUG IMPORT BINDING
-- Blizzard mirror debug helpers are defined by the load-on-demand debug addon.
---------------------------------------------------------------------------
function CDMIconFactory._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        ShouldDebugBlizzEntry  = d.ShouldBlizz   or ShouldDebugBlizzEntry
        FormatMirrorState      = d.FormatMirrorState or FormatMirrorState
        DebugBlizzEntry        = d.Blizz         or DebugBlizzEntry
    end
end
end

do
-- Inlined from cdm_icon_stack_text.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Stack Text
--
-- Taint-aware stack/count text sink for icon FontStrings. CDMIconStackPolicy
-- decides what value should be shown; this module owns the write/clear
-- mechanics.
---------------------------------------------------------------------------

local CDMIconStackText = {}
ns.CDMIconStackText = CDMIconStackText

local type = type

local issecretvalue = issecretvalue or function() return false end

local function ApplyVisibilityGate(fontString, gate)
    if not (fontString and fontString.SetAlpha) then return end
    if issecretvalue(gate) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(gate, 1, 0)
            fontString.SetAlpha(fontString, alpha)
        end
        return
    end
    if gate == false then
        fontString.SetAlpha(fontString, 0)
    else
        fontString.SetAlpha(fontString, 1)
    end
end

function CDMIconStackText.TextHasDisplay(text)
    if issecretvalue(text) then
        return true
    end
    if type(text) == "string" then
        return text ~= ""
    end
    return text ~= nil
end

function CDMIconStackText.ValueIsPresent(value)
    if issecretvalue(value) then
        return true
    end
    return value ~= nil
end

function CDMIconStackText.ValueIsMissing(value)
    return not CDMIconStackText.ValueIsPresent(value)
end

function CDMIconStackText.Clear(icon)
    if not icon or not icon.StackText then return end
    if icon.StackText.SetText then
        icon.StackText.SetText(icon.StackText, "")
    end
    if icon.StackText.Hide then
        icon.StackText.Hide(icon.StackText)
    end
    icon._stackTextSource = nil
end

function CDMIconStackText.Show(icon, value, source, visibilityGate)
    if not icon or not icon.StackText then return false end
    local setOk = true
    local setErr = icon.StackText.SetText(icon.StackText, value)
    if not setOk and icon.StackText.SetFormattedText then
        setOk = true
        setErr = icon.StackText.SetFormattedText(icon.StackText, "%s", value)
    end

    local showOk = false
    local showErr
    if setOk then
        showOk = true
        showErr = icon.StackText.Show(icon.StackText)
    end

    local gate = visibilityGate
    if not issecretvalue(gate) and gate == nil and source == "ChargeCount" then
        gate = icon.cooldownChargesShown
        if not issecretvalue(gate) and gate == nil then
            gate = icon.chargeCountFrameShown
        end
    end
    ApplyVisibilityGate(icon.StackText, gate)

    if source ~= nil then
        icon._stackTextSource = source
    end

    return setOk, setErr, showOk, showErr
end
end

do
-- Inlined from cdm_icon_stack_policy.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Stack Policy
--
-- Private controller used by CDMIcons. It owns stack/count resolution,
-- mirror stack authority, aura application fallbacks, and stack text
-- show/hide policy. CDMIconStackText owns only the FontString write sink.
---------------------------------------------------------------------------

local CDMIconStackPolicy = {}
ns.CDMIconStackPolicy = CDMIconStackPolicy

local ipairs = ipairs
local type = type
local tostring = tostring
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local issecretvalue = issecretvalue or function() return false end

local function DefaultTextHasDisplay(text)
    if issecretvalue(text) then
        return true
    end
    if type(text) == "string" then
        return text ~= ""
    end
    return text ~= nil
end

function CDMIconStackPolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}

    local function Sink()
        return callbacks.getSink and callbacks.getSink() or ns.CDMIconStackText
    end

    local function Sources()
        return callbacks.getSources and callbacks.getSources() or ns.CDMSources
    end

    local function AuraRuntime()
        return callbacks.getAuraRuntime and callbacks.getAuraRuntime() or ns.CDMAuraRuntime
    end

    local function Mirror()
        return callbacks.getMirror and callbacks.getMirror() or ns.CDMBlizzMirror
    end

    local function SafeBoolean(value)
        if callbacks.safeBoolean then
            return callbacks.safeBoolean(value)
        end
        if issecretvalue(value) then
            return nil
        end
        return value and true or false
    end

    local function BooleanOrSecret(value)
        if issecretvalue(value) then return value, true end
        if value == nil then return nil, false end
        if value == true then return true, false end
        if value == false then return false, false end
        return nil, false
    end

    local function BooleanOrSecretIsPresent(value, valueIsSecret)
        return valueIsSecret or value ~= nil
    end

    local function IsAuraEntry(entry)
        return callbacks.isAuraEntry and callbacks.isAuraEntry(entry) or false
    end

    local function IsBuiltinAuraContainerKey(containerKey)
        return callbacks.isBuiltinAuraContainerKey
            and callbacks.isBuiltinAuraContainerKey(containerKey)
            or false
    end

    local function MirrorStateEffectiveCooldownChargesShown(m)
        local cooldownChargesShown, cooldownChargesShownSecret =
            BooleanOrSecret(m and m.cooldownChargesShown)
        if BooleanOrSecretIsPresent(cooldownChargesShown, cooldownChargesShownSecret) then
            return cooldownChargesShown, cooldownChargesShownSecret
        end
        local chargeCountFrameShown, chargeCountFrameShownSecret =
            BooleanOrSecret(m and m.chargeCountFrameShown)
        if BooleanOrSecretIsPresent(chargeCountFrameShown, chargeCountFrameShownSecret) then
            return chargeCountFrameShown, chargeCountFrameShownSecret
        end
        if m
            and (m.stackTextSource == "ChargeCount"
                or controller:ValueIsPresent(m.cooldownChargesCount)) then
            return false, false
        end
        return nil, false
    end

    local function MirrorStateChargeCountShown(m)
        local shown, shownSecret = MirrorStateEffectiveCooldownChargesShown(m)
        return shownSecret or shown == true
    end

    local function MirrorStateUsesCooldownCountText(m)
        return SafeBoolean(m and m.wasSetFromCooldown) == true
            and SafeBoolean(m and m.wasSetFromCharges) ~= true
            and MirrorStateChargeCountShown(m) == true
    end

    local function ResolveMirrorStackTextFromState(m, cooldownChargeAuthority)
        local mirrorIsCharge = SafeBoolean(m.charges) == true
            or SafeBoolean(m.hasCharges) == true
            or SafeBoolean(m.wasSetFromCharges) == true
        local cooldownCountText = MirrorStateUsesCooldownCountText(m)
            and not mirrorIsCharge

        local chargeCountShown = MirrorStateChargeCountShown(m)
        local cooldownChargesShown, cooldownChargesShownSecret =
            MirrorStateEffectiveCooldownChargesShown(m)
        local chargeTextOwnerShown, chargeTextOwnerShownSecret =
            BooleanOrSecret(m.chargeTextOwnerShown)
        local chargeCountFrameShown, chargeCountFrameShownSecret =
            BooleanOrSecret(m.chargeCountFrameShown)

        local stackText = m.stackText
        local stackSource = m.stackTextSource
        local stackIsVisible = SafeBoolean(m.stackTextShown) ~= false
        local countText = m.cooldownChargesCount
        local countTextPresent = controller:ValueIsPresent(countText)
        local stackChargeTextPresent = stackSource == "ChargeCount"
            and stackIsVisible
            and controller:ValueIsPresent(stackText)
        if cooldownChargeAuthority then
            if chargeCountShown == true then
                if countTextPresent then
                        return countText, "ChargeCount", nil, true
                end
                if stackChargeTextPresent then
                    return stackText, "ChargeCount", nil, true
                end
            end

            if stackSource == "ChargeCount"
                or countTextPresent
                or BooleanOrSecretIsPresent(cooldownChargesShown, cooldownChargesShownSecret)
                or BooleanOrSecretIsPresent(chargeTextOwnerShown, chargeTextOwnerShownSecret)
                or BooleanOrSecretIsPresent(chargeCountFrameShown, chargeCountFrameShownSecret) then
                return nil, "ChargeCount", true, true
            end
            return nil, nil, true, true
        end

        if m.stackTextSource == "ChargeCount" and chargeCountShown ~= true then
            return nil, m.stackTextSource, true, true
        end

        if stackIsVisible and controller:ValueIsPresent(stackText) then
            return stackText, m.stackTextSource or "Applications", nil, true
        end

        if countTextPresent
            and chargeCountShown == true then
            return countText, "ChargeCount", nil, true
        end

        if SafeBoolean(m.stackTextShown) == false then
            return nil, m.stackTextSource, true, true
        end

        return nil, m.stackTextSource, nil, true
    end

    local function StampIconMirrorCountFields(icon, m)
        if not icon then return end
        if not m then
            icon.cooldownChargesCount = nil
            icon.cooldownChargesShown = nil
            icon.chargeCountFrameShown = nil
            icon.chargeTextOwnerShown = nil
            icon.stackText = nil
            icon.stackTextSource = nil
            icon.stackTextShown = nil
            icon.stackTextEpoch = nil
            icon.wasSetFromCooldown = nil
            icon.wasSetFromCharges = nil
            return
        end

        icon.cooldownChargesCount = m.cooldownChargesCount
        icon.cooldownChargesShown = MirrorStateEffectiveCooldownChargesShown(m)
        icon.chargeCountFrameShown = m.chargeCountFrameShown
        icon.chargeTextOwnerShown = m.chargeTextOwnerShown
        icon.stackText = m.stackText
        icon.stackTextSource = m.stackTextSource
        icon.stackTextShown = m.stackTextShown
        icon.stackTextEpoch = m.stackTextEpoch
        icon.wasSetFromCooldown = m.wasSetFromCooldown
        icon.wasSetFromCharges = m.wasSetFromCharges
    end

    function controller:TextHasDisplay(text)
        local sink = Sink()
        if sink and sink.TextHasDisplay then
            return sink.TextHasDisplay(text)
        end
        return DefaultTextHasDisplay(text)
    end

    function controller:ValueIsPresent(value)
        local sink = Sink()
        if sink and sink.ValueIsPresent then
            return sink.ValueIsPresent(value)
        end
        if issecretvalue(value) then
            return true
        end
        return value ~= nil
    end

    function controller:ValueIsMissing(value)
        return not controller:ValueIsPresent(value)
    end

    function controller:Clear(icon)
        local sink = Sink()
        if sink and sink.Clear then
            sink.Clear(icon)
            return
        end
        if not icon or not icon.StackText then return end
        icon.StackText.SetText(icon.StackText, "")
        icon.StackText.Hide(icon.StackText)
        icon._stackTextSource = nil
    end

    function controller:GetDisplayableAuraApplicationsFromData(auraData)
        if not auraData then return nil end

        local apps = auraData.applications
        if apps == nil then return nil end
        if issecretvalue(apps) then
            return nil
        end

        local appType = type(apps)
        if appType == "number" then
            return apps > 1 and apps or nil
        end
        if appType == "string" then
            if apps == "" or apps == "0" or apps == "1" then
                return nil
            end
            return apps
        end

        return nil
    end

    function controller:GetAuraApplicationsFromData(auraData, unit, source)
        if not auraData then return nil end

        local apps = controller:GetDisplayableAuraApplicationsFromData(auraData)
        if controller:ValueIsPresent(apps) then
            return apps, source
        end

        local auraInstanceID = callbacks.getAuraDataInstanceID
            and callbacks.getAuraDataInstanceID(auraData)
            or auraData.auraInstanceID
        local sources = Sources()
        if auraInstanceID and sources and sources.QueryAuraApplicationDisplayCount then
            local stacks = sources.QueryAuraApplicationDisplayCount(unit or "player", auraInstanceID, 2, 99)
            if stacks ~= nil then
                return stacks, "display-count"
            end
        end

        return nil
    end

    function controller:ResolveAuraApplicationsForEntry(spellID, entry, icon)
        if not (spellID and entry) then
            return nil
        end

        local auraRuntime = AuraRuntime()
        if not (auraRuntime and auraRuntime.ResolveState) then
            return nil
        end

        local p = icon and icon._stackAuraParams or {}
        if icon then icon._stackAuraParams = p end
        p.spellID = spellID
        p.entrySpellID = entry.spellID
        p.entryID = entry.id
        p.entryName = entry.name
        p.entryKind = entry.kind
        p.entryType = entry.type
        p.entryIsAura = IsAuraEntry(entry)
        p.entryTexture = callbacks.getEntryTexture and callbacks.getEntryTexture(entry) or nil
        p.viewerType = entry.viewerType
        p.totemSlot = callbacks.isTotemSlotEntry and callbacks.isTotemSlotEntry(entry) and entry._totemSlot or nil
        p.disableLooseVisibilityFallback = true

        local r = auraRuntime.ResolveState(p)
        if not r then
            return nil
        end

        if r.isActive and not r.isTotemInstance then
            local count = r.count
            if count and count.shown == true and controller:ValueIsPresent(count.sinkText) then
                return count.sinkText, count.source
            end
            if count and count.shown == true and controller:ValueIsPresent(count.value) then
                return count.value, count.source
            end
            return controller:GetAuraApplicationsFromData(r.auraData, r.auraUnit, "resolved-data")
        end

        return nil
    end

    function controller:TryAuraApplicationsBySpellID(auraID, source)
        if auraID == nil then return nil end
        local sources = Sources()
        if not sources then return nil end

        local function queryPlayerAuraData(spellID)
            if not spellID then return nil end
            if sources.QueryUnitAuraBySpellID then
                local auraData = sources.QueryUnitAuraBySpellID("player", spellID)
                if auraData then return auraData end
            end
            if sources.QueryPlayerAuraBySpellID then
                local auraData = sources.QueryPlayerAuraBySpellID(spellID)
                if auraData then return auraData end
            end
            return nil
        end

        if sources.QueryCooldownAuraBySpellID then
            local passiveAuraID = sources.QueryCooldownAuraBySpellID(auraID)
            if passiveAuraID then
                local auraData = queryPlayerAuraData(passiveAuraID)
                if auraData then
                    local apps, appSource = controller:GetAuraApplicationsFromData(
                        auraData, "player", (source or "spell") .. "-cooldown-aura")
                    if controller:ValueIsPresent(apps) then
                        return apps, appSource
                    end
                end
            end
        end

        local auraData = queryPlayerAuraData(auraID)
        if auraData then
            local apps, appSource = controller:GetAuraApplicationsFromData(
                auraData, "player", (source or "spell") .. "-player-spell")
            if controller:ValueIsPresent(apps) then
                return apps, appSource
            end
        end

        return nil
    end

    function controller:TryLinkedAuraApplications(linkedSpellIDs, entry, icon, seenIDs, source)
        if type(linkedSpellIDs) ~= "table" then
            return nil
        end

        for _, linkedID in ipairs(linkedSpellIDs) do
            local queryID = linkedID
            local auraID = type(linkedID) == "number" and linkedID or nil

            if queryID and (not auraID or (auraID > 0 and not seenIDs[auraID])) then
                if auraID then
                    seenIDs[auraID] = true
                end

                local apps, appSource = controller:TryAuraApplicationsBySpellID(queryID, source or "linked")
                if controller:ValueIsPresent(apps) then
                    if _G.QUI_CDM_CHARGE_DEBUG and callbacks.chargeDebug then
                        callbacks.chargeDebug(entry and entry.name, "AURA linked stack",
                            "auraID=", auraID or "dynamic", "source=", appSource or "nil")
                    end
                    return apps, appSource
                end

                if auraID then
                    apps, appSource = controller:ResolveAuraApplicationsForEntry(auraID, entry, icon)
                    if controller:ValueIsPresent(apps) then
                        if _G.QUI_CDM_CHARGE_DEBUG and callbacks.chargeDebug then
                            callbacks.chargeDebug(entry and entry.name, "AURA linked resolve",
                                "auraID=", auraID, "source=", appSource or "nil")
                        end
                        return apps, appSource or (source or "linked")
                    end
                end
            end
        end

        return nil
    end

    local function TryActionButtonSpellCount(spellID, seenIDs, icon)
        if type(spellID) ~= "number" then return nil end
        if seenIDs[spellID] then return nil end
        seenIDs[spellID] = true

        local spellCount
        if callbacks.querySpellCount then
            spellCount = callbacks.querySpellCount(spellID, icon)
        end
        if controller:ValueIsMissing(spellCount) then return nil end

        if issecretvalue(spellCount) then
            return spellCount, "spell-cast-count"
        end

        if type(spellCount) ~= "number" then return nil end
        if spellCount <= 0 then return nil end

        local displayText = spellCount
        if C_StringUtil and C_StringUtil.TruncateWhenZero then
            displayText = C_StringUtil.TruncateWhenZero(spellCount)
        end
        if not controller:TextHasDisplay(displayText) then
            return nil
        end
        return spellCount, "spell-cast-count"
    end

    function controller:GetSpellCountForEntry(spellID, entry, icon)
        local seenIDs = icon and icon._spellCountSeenIDs or {}
        if icon then icon._spellCountSeenIDs = seenIDs end
        wipe(seenIDs)

        local function tryID(id)
            local count, source = TryActionButtonSpellCount(id, seenIDs, icon)
            if controller:ValueIsPresent(count) then return count, source end

            if type(id) == "number" and callbacks.queryOverrideSpell then
                local overrideID = callbacks.queryOverrideSpell(id)
                count, source = TryActionButtonSpellCount(overrideID, seenIDs, icon)
                if controller:ValueIsPresent(count) then return count, source end
            end
            return nil
        end

        local count, source = tryID(spellID)
        if controller:ValueIsPresent(count) then return count, source end

        if entry then
            count, source = tryID(entry.overrideSpellID)
            if controller:ValueIsPresent(count) then return count, source end
            count, source = tryID(entry.spellID)
            if controller:ValueIsPresent(count) then return count, source end
            count, source = tryID(entry.id)
            if controller:ValueIsPresent(count) then return count, source end
        end

        return nil
    end

    function controller:GetAuraApplicationsForSpell(spellID, entryOrName, icon)
        local entry = type(entryOrName) == "table" and entryOrName or nil
        local spellName = entry and entry.name or entryOrName
        local sources = Sources()
        if controller:ValueIsMissing(spellID) or not sources then
            return nil
        end

        if entry and not IsAuraEntry(entry) then
            local spellCount, countSource = controller:GetSpellCountForEntry(spellID, entry, icon)
            if controller:ValueIsPresent(spellCount) then
                return spellCount, countSource
            end
        end

        local seenIDs = icon and icon._stackAuraSeenIDs or {}
        if icon then icon._stackAuraSeenIDs = seenIDs end
        wipe(seenIDs)
        seenIDs[spellID] = true

        local directApps, directSource = controller:TryAuraApplicationsBySpellID(spellID, "spell")
        if controller:ValueIsPresent(directApps) then
            return directApps, directSource
        end

        local auraID = spellID
        local auraRuntime = AuraRuntime()
        local mapped, remapped
        if auraRuntime and auraRuntime.ResolveAbilityAuraSpellID then
            mapped, remapped = auraRuntime.ResolveAbilityAuraSpellID(auraID)
        end
        if remapped == true and mapped then
            auraID = mapped
        end
        if auraID and not seenIDs[auraID] then
            seenIDs[auraID] = true
            local mappedApps, mappedSource = controller:TryAuraApplicationsBySpellID(auraID, "mapped")
            if controller:ValueIsPresent(mappedApps) then
                return mappedApps, mappedSource
            end
        end

        if not (entry and IsBuiltinAuraContainerKey(entry.viewerType)) then
            local linkedApps, linkedSource = controller:TryLinkedAuraApplications(
                entry and entry.linkedSpellIDs, entry, icon, seenIDs, "entry-linked")
            if controller:ValueIsPresent(linkedApps) then return linkedApps, linkedSource end
        end

        if not sources.QueryAuraDataBySpellName then
            return controller:ResolveAuraApplicationsForEntry(spellID, entry, icon)
        end

        local nameToUse = spellName
        if nameToUse == nil or nameToUse == "" then
            nameToUse = callbacks.getCachedSpellName and callbacks.getCachedSpellName(spellID) or nil
        end
        if (nameToUse == nil or nameToUse == "") and sources.QuerySpellInfo then
            local info = sources.QuerySpellInfo(spellID)
            if info then
                nameToUse = info.name
            end
        end
        if controller:ValueIsPresent(nameToUse) then
            local nad = sources.QueryAuraDataBySpellName("player", nameToUse, "HELPFUL")
            if nad then
                local apps, source = controller:GetAuraApplicationsFromData(nad, "player", "name-player")
                if controller:ValueIsPresent(apps) then return apps, source end
            end
        end

        local resolvedApps, resolvedSource = controller:ResolveAuraApplicationsForEntry(spellID, entry, icon)
        if controller:ValueIsPresent(resolvedApps) then
            return resolvedApps, resolvedSource
        end

        return nil
    end

    function controller:ResolveMirrorStackText(icon)
        local mirror = Mirror()
        local cooldownID = icon and icon._blizzMirrorCooldownID
        local category = icon and icon._blizzMirrorCategory
        local resolvedState
        if cooldownID == nil then
            local entry = icon and icon._spellEntry
            if callbacks.resolveMirrorIdentityState and entry then
                local identity = callbacks.resolveMirrorIdentityState(entry)
                if identity then
                    cooldownID = identity.cooldownID
                    category = identity.category
                    resolvedState = identity.state
                end
            end
            if cooldownID == nil then
                StampIconMirrorCountFields(icon, nil)
                return nil, nil, false
            end
        end
        if not (mirror and mirror.GetStateByCooldownID) then
            StampIconMirrorCountFields(icon, nil)
            return nil, nil, true
        end

        local m = resolvedState
        if not m and callbacks.getCachedMirrorStateForIcon then
            m = callbacks.getCachedMirrorStateForIcon(icon)
        end
        if not m and callbacks.refreshCachedMirrorStateForIcon then
            m = callbacks.refreshCachedMirrorStateForIcon(icon)
        end
        if not m then
            m = mirror.GetStateByCooldownID(cooldownID, category)
        end
        if not m then
            StampIconMirrorCountFields(icon, nil)
            return nil, nil, true, nil, false
        end
        StampIconMirrorCountFields(icon, m)
        local entry = icon and icon._spellEntry
        local cooldownChargeAuthority = not (entry and IsAuraEntry(entry))
        local stackText, stackSource, stackHidden, hasState =
            ResolveMirrorStackTextFromState(m, cooldownChargeAuthority)
        return stackText, stackSource, true, stackHidden, hasState
    end

    function controller:ResolveIconStackText(icon)
        if not icon or not icon._spellEntry then
            return nil, nil
        end
        local entry = icon._spellEntry

        if IsAuraEntry(entry) then
            local active, auraUnit, instID
            if callbacks.resolveAuraActiveState then
                active, auraUnit, instID = callbacks.resolveAuraActiveState(entry)
            end
            local auraRuntime = AuraRuntime()
            if active and instID and auraRuntime and auraRuntime.GetApplications then
                local resolved, stacks = auraRuntime.GetApplications(auraUnit or "player", instID)
                if resolved and stacks ~= nil then
                    return stacks, "Applications"
                end
            end
            return nil, nil
        end

        local sid = icon._runtimeSpellID
            or (entry.overrideSpellID or entry.spellID or entry.id)
        if not sid then
            return nil, nil
        end
        if callbacks.queryOverrideSpell then
            local overrideID = callbacks.queryOverrideSpell(sid)
            if overrideID then sid = overrideID end
        end

        local mirrorText, mirrorSource, mirrorBacked, mirrorStackHidden =
            controller:ResolveMirrorStackText(icon)
        if controller:ValueIsPresent(mirrorText) then
            return mirrorText, mirrorSource, true, mirrorStackHidden
        end
        if mirrorBacked then
            return nil, mirrorSource, true, mirrorStackHidden
        end

        local svDB = callbacks.getChargeMetadataDB and callbacks.getChargeMetadataDB() or nil
        local maxC = svDB and svDB[sid]
        if not maxC or maxC <= 1 then
            return nil, nil
        end

        local text
        if callbacks.queryDisplayCount then
            text = callbacks.queryDisplayCount(sid, icon)
        end
        if controller:ValueIsMissing(text) then return nil, nil end
        return text, "ChargeCount"
    end

    function controller:ShouldHideIconStackText(icon, containerDB)
        local row = icon and icon._rowConfig
        if row and row.hideStackText == true then return true end
        return containerDB and containerDB.hideStackText == true
    end

    function controller:ShowIconStackText(icon, value, containerDB, reason)
        if not icon or not icon.StackText then return end
        if controller:ShouldHideIconStackText(icon, containerDB) then
            if callbacks.debugStackText then
                callbacks.debugStackText(icon, "hide", value, reason or "setting-hide-stack-text")
            end
            controller:Clear(icon)
            return
        end

        local sink = Sink()
        local setOk, setErr, showOk, showErr
        if sink and sink.Show then
            setOk, setErr, showOk, showErr = sink.Show(icon, value, reason)
        else
            setOk = true; setErr = icon.StackText.SetText(icon.StackText, value)
            if not setOk and icon.StackText.SetFormattedText then
                setOk = true; setErr = icon.StackText.SetFormattedText(icon.StackText, "%s", value)
            end
            showOk = false
            if setOk then
                showOk = true; showErr = icon.StackText.Show(icon.StackText)
            end
            icon._stackTextSource = reason
        end
        if _G.QUI_CDM_CHARGE_DEBUG then
            if callbacks.debugStackText then
                callbacks.debugStackText(icon, setOk and "show" or "show-failed", value, reason)
            end
            if callbacks.chargeDebug then
                callbacks.chargeDebug(icon._spellEntry and icon._spellEntry.name,
                    "STACKTEXT apply", "reason=", reason or "nil",
                    "setOk=", tostring(setOk), "setErr=", tostring(setErr),
                    "showOk=", tostring(showOk), "showErr=", tostring(showErr))
            end
        end
    end

    function controller:HideIconStackText(icon, reason)
        if not icon or not icon.StackText then return end
        if callbacks.debugStackText then
            callbacks.debugStackText(icon, "hide", nil, reason)
        end
        controller:Clear(icon)
    end

    function controller:ApplyAuraCountText(icon, count, showZero, preserveWhenMissing)
        if not icon or not icon.StackText then return end

        if not count or count.shown ~= true then
            if not preserveWhenMissing then
                controller:Clear(icon)
            end
            return
        end

        local entry = icon._spellEntry
        local stackSettings = callbacks.getTrackerSettings
            and callbacks.getTrackerSettings(entry and entry.viewerType)
            or nil
        if controller:ShouldHideIconStackText(icon, stackSettings) then
            controller:Clear(icon)
            return
        end

        local stackValue = count.sinkText
        if controller:ValueIsMissing(stackValue) then
            stackValue = count.value
        end

        if controller:ValueIsMissing(stackValue) then
            if not preserveWhenMissing then
                controller:Clear(icon)
            end
            return
        end

        if controller:ValueIsPresent(count.sinkText) or showZero then
            if showZero or controller:TextHasDisplay(stackValue) then
                local sink = Sink()
                if sink and sink.Show then
                    sink.Show(icon, stackValue, count.source or "Applications", count.visibilityGate)
                else
                    icon.StackText.SetText(icon.StackText, stackValue)
                    icon.StackText.Show(icon.StackText)
                    icon._stackTextSource = count.source or "Applications"
                end
            else
                controller:Clear(icon)
            end
            return
        end

        local displayText = stackValue
        if type(stackValue) == "number" and C_StringUtil and C_StringUtil.TruncateWhenZero then
            displayText = C_StringUtil.TruncateWhenZero(stackValue)
        end

        if controller:TextHasDisplay(displayText) then
            local sink = Sink()
            if sink and sink.Show then
                sink.Show(icon, displayText, count.source or "Applications", count.visibilityGate)
            else
                icon.StackText.SetText(icon.StackText, displayText)
                icon.StackText.Show(icon.StackText)
                icon._stackTextSource = count.source or "Applications"
            end
        else
            controller:Clear(icon)
        end
    end

    function controller:ApplyMirrorStackText(icon, mirrorState, showZero)
        if not (icon and mirrorState) then
            return false
        end

        StampIconMirrorCountFields(icon, mirrorState)
        local entry = icon and icon._spellEntry
        local cooldownChargeAuthority = not (entry and IsAuraEntry(entry))
        local stackText, stackSource, stackHidden =
            ResolveMirrorStackTextFromState(mirrorState, cooldownChargeAuthority)
        if stackHidden or controller:ValueIsMissing(stackText) then
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
        count.source = stackSource or "Applications"
        count.visibilityGate = MirrorStateEffectiveCooldownChargesShown(mirrorState)

        controller:ApplyAuraCountText(icon, count, showZero, true)
        icon._lastMirrorStackTextEpoch = mirrorState.stackTextEpoch
        return true
    end

    return controller
end
end

do
-- Inlined from cdm_icon_mirror_index.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Mirror Index
--
-- Private controller used by CDMIcons to target mirror-backed icon refreshes.
-- It owns the weak icon index, pending mirror refresh queue, and mirror
-- refresh stats; CDMIcons keeps the public lifecycle methods.
---------------------------------------------------------------------------

local CDMIconMirrorIndex = {}
ns.CDMIconMirrorIndex = CDMIconMirrorIndex

local pairs = pairs
local ipairs = ipairs
local setmetatable = setmetatable
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function CountPendingKeys(pendingByCategory)
    local count = 0
    for _, byCooldownID in pairs(pendingByCategory or {}) do
        for _ in pairs(byCooldownID) do
            count = count + 1
        end
    end
    return count
end

function CDMIconMirrorIndex.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        byCategory = {},
        pendingByCategory = {},
        refreshPending = false,
        stats = {
            targeted = 0,
            fallback = 0,
            maxBatch = 0,
        },
        refreshFrame = nil,
        refreshElapsed = 0,
        refreshDelay = 0,
    }

    do
        local mp = ns._memprobes or {}; ns._memprobes = mp
        mp[#mp + 1] = {
            name = "CDM_mirrorRefreshUnscopedSkips",
            counter = true,
            fn = function()
                return controller.stats.fallback or 0
            end,
        }
    end

    local function getIconSet(category, cooldownID, create)
        if not (category and cooldownID) then return nil end
        local byCategory = controller.byCategory[category]
        if not byCategory then
            if not create then return nil end
            byCategory = {}
            controller.byCategory[category] = byCategory
        end

        local iconSet = byCategory[cooldownID]
        if not iconSet then
            if not create then return nil end
            iconSet = setmetatable({}, { __mode = "k" })
            byCategory[cooldownID] = iconSet
        end
        return iconSet
    end

    function controller:RemoveIcon(icon)
        if not icon then return end
        local category = icon._blizzMirrorIndexCategory
        local cooldownID = icon._blizzMirrorIndexCooldownID
        if category and cooldownID then
            local iconSet = getIconSet(category, cooldownID, false)
            if iconSet then
                iconSet[icon] = nil
            end
        end
        icon._blizzMirrorIndexCategory = nil
        icon._blizzMirrorIndexCooldownID = nil
        if callbacks.storeMirrorStateForIcon then
            callbacks.storeMirrorStateForIcon(icon)
        end
    end

    function controller:Rebuild(iconPools)
        wipe(controller.byCategory)
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                if icon and icon._blizzMirrorCooldownID and icon._blizzMirrorCategory then
                    local category = icon._blizzMirrorCategory
                    local cooldownID = icon._blizzMirrorCooldownID
                    local iconSet = getIconSet(
                        category,
                        cooldownID,
                        true)
                    iconSet[icon] = true
                    icon._blizzMirrorIndexCategory = category
                    icon._blizzMirrorIndexCooldownID = cooldownID
                    if callbacks.storeMirrorStateForIcon then
                        local state = callbacks.getMirrorStateByCooldownID
                            and callbacks.getMirrorStateByCooldownID(cooldownID, category)
                            or nil
                        callbacks.storeMirrorStateForIcon(icon, cooldownID, category, state)
                    end
                end
            end
        end
    end

    function controller:BindIcon(icon, cooldownID, category)
        if not icon then return end
        controller:RemoveIcon(icon)
        if cooldownID and category then
            local iconSet = getIconSet(category, cooldownID, true)
            iconSet[icon] = true
            icon._blizzMirrorIndexCategory = category
            icon._blizzMirrorIndexCooldownID = cooldownID
            if callbacks.storeMirrorStateForIcon then
                local state = callbacks.getMirrorStateByCooldownID
                    and callbacks.getMirrorStateByCooldownID(cooldownID, category)
                    or nil
                callbacks.storeMirrorStateForIcon(icon, cooldownID, category, state)
            end
        end
        if callbacks.onBound then
            callbacks.onBound(icon, cooldownID, category)
        end
    end

    function controller:UnbindIcon(icon)
        controller:RemoveIcon(icon)
        if callbacks.onUnbound then
            callbacks.onUnbound(icon)
        end
    end

    function controller:Count()
        local mirrorIndexKeys = 0
        local mirrorIndexIcons = 0
        for _, byCooldownID in pairs(controller.byCategory) do
            for _, iconSet in pairs(byCooldownID) do
                mirrorIndexKeys = mirrorIndexKeys + 1
                for icon in pairs(iconSet) do
                    if icon then
                        mirrorIndexIcons = mirrorIndexIcons + 1
                    end
                end
            end
        end
        return mirrorIndexKeys, mirrorIndexIcons
    end


    function controller:PendingKeyCount()
        return CountPendingKeys(controller.pendingByCategory)
    end

    function controller:GetStats()
        return controller.stats
    end

    local function drainRefreshQueue()
        controller.refreshPending = false
        local pendingByCategory = controller.pendingByCategory
        controller.pendingByCategory = {}

        local batchKeys = CountPendingKeys(pendingByCategory)
        if batchKeys == 0 then return end

        local stats = controller.stats
        if batchKeys > stats.maxBatch then
            stats.maxBatch = batchKeys
        end

        local refreshed = 0
        local effectiveKeys = 0
        local editMode, ncdm, ncdmContainers, inCombat
        local batchStarted = false

        for category, byCooldownID in pairs(pendingByCategory) do
            for cooldownID in pairs(byCooldownID) do
                local iconSet = getIconSet(category, cooldownID, false)
                if iconSet then
                    local mirrorState = callbacks.getMirrorStateByCooldownID
                        and callbacks.getMirrorStateByCooldownID(cooldownID, category)
                        or nil
                    local keyHadIcon = false
                    for icon in pairs(iconSet) do
                        if icon
                            and icon._blizzMirrorCooldownID == cooldownID
                            and icon._blizzMirrorCategory == category
                            and callbacks.refreshIcon then
                            if callbacks.storeMirrorStateForIcon then
                                callbacks.storeMirrorStateForIcon(icon, cooldownID, category, mirrorState)
                            end
                            if not keyHadIcon then
                                effectiveKeys = effectiveKeys + 1
                                keyHadIcon = true
                            end
                            if not batchStarted then
                                if callbacks.prepareBatch then
                                    editMode, ncdm, ncdmContainers, inCombat = callbacks.prepareBatch()
                                end
                                if callbacks.setStackTextWrites then
                                    callbacks.setStackTextWrites(true)
                                end
                                if callbacks.beginBatch then
                                    callbacks.beginBatch()
                                end
                                batchStarted = true
                            end
                            if callbacks.refreshIcon(icon, editMode, ncdm, ncdmContainers, inCombat) then
                                refreshed = refreshed + 1
                            end
                        end
                    end
                end
            end
        end

        stats.targeted = stats.targeted + effectiveKeys

        if batchStarted then
            if callbacks.setStackTextWrites then
                callbacks.setStackTextWrites(false)
            end
            if callbacks.endBatch then
                callbacks.endBatch()
            end
        end

        if refreshed > 0 and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
    end

    local function drainRefreshFrame(_, elapsed)
        controller.refreshElapsed = controller.refreshElapsed + (elapsed or 0)
        if controller.refreshElapsed < controller.refreshDelay then return end
        if controller.refreshFrame then
            controller.refreshFrame:SetScript("OnUpdate", nil)
            controller.refreshFrame:Hide()
        end
        drainRefreshQueue()
    end

    function controller:RequestRefresh(cooldownID, category)
        if callbacks.isRuntimeEnabled and not callbacks.isRuntimeEnabled() then return end

        if not (cooldownID and category) then
            controller.stats.fallback = controller.stats.fallback + 1
            return
        end

        local byCooldownID = controller.pendingByCategory[category]
        if not byCooldownID then
            byCooldownID = {}
            controller.pendingByCategory[category] = byCooldownID
        end
        byCooldownID[cooldownID] = true

        if controller.refreshPending then return end
        controller.refreshPending = true
        if InCombatLockdown and InCombatLockdown() then
            controller.refreshElapsed = 0
            controller.refreshDelay = callbacks.getCombatDelay and callbacks.getCombatDelay() or 0.2
            if not controller.refreshFrame then
                controller.refreshFrame = CreateFrame("Frame")
                controller.refreshFrame:Hide()
            end
            controller.refreshFrame:SetScript("OnUpdate", drainRefreshFrame)
            controller.refreshFrame:Show()
            return
        end

        if not (C_Timer and C_Timer.After) then
            drainRefreshQueue()
            return
        end

        C_Timer.After(0, drainRefreshQueue)
    end

    function controller:IsRefreshPending()
        return controller.refreshPending == true
    end

    return controller
end
end

do
-- Inlined from cdm_icon_runtime_refresh.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Runtime Refresh
--
-- Private controller for CDMIcons event/runtime refresh dispatch. CDMIcons
-- owns renderer callbacks; this module owns the event branching shape,
-- scoped icon walking, and combat refresh queues.
---------------------------------------------------------------------------

local CDMIconRuntimeRefresh = {}
ns.CDMIconRuntimeRefresh = CDMIconRuntimeRefresh

local pairs = pairs
local ipairs = ipairs
local type = type
local tonumber = tonumber
local next = next

local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local UPDATE_COOLDOWN = "cooldown"
local UPDATE_FULL = "full"

local runtimeRefreshStats = {
    catalogScopeRefreshes = 0,
    catalogScopeQueued = 0,
    castStartCooldownSkips = 0,
    castStartCooldownFallbacks = 0,
    castSucceededCooldownSkips = 0,
    chargeCooldownSkips = 0,
    deferredFullRefreshes = 0,
    deferredFullDrains = 0,
    hotfixDeferredFulls = 0,
    spellsChangedScoped = 0,
    unitSpellcastCooldownSkips = 0,
    unitSpellcastCooldownFallbacks = 0,
}

do
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_catalogScopeRefreshes", counter = true, fn = function() return runtimeRefreshStats.catalogScopeRefreshes end }
    mp[#mp + 1] = { name = "CDM_catalogScopeQueued", counter = true, fn = function() return runtimeRefreshStats.catalogScopeQueued end }
    mp[#mp + 1] = { name = "CDM_castStartCooldownSkips", counter = true, fn = function() return runtimeRefreshStats.castStartCooldownSkips end }
    mp[#mp + 1] = { name = "CDM_castStartCooldownFallbacks", counter = true, fn = function() return runtimeRefreshStats.castStartCooldownFallbacks end }
    mp[#mp + 1] = { name = "CDM_castSucceededCooldownSkips", counter = true, fn = function() return runtimeRefreshStats.castSucceededCooldownSkips end }
    mp[#mp + 1] = { name = "CDM_chargeCooldownSkips", counter = true, fn = function() return runtimeRefreshStats.chargeCooldownSkips end }
    mp[#mp + 1] = { name = "CDM_deferredFullRefreshes", counter = true, fn = function() return runtimeRefreshStats.deferredFullRefreshes end }
    mp[#mp + 1] = { name = "CDM_deferredFullDrains", counter = true, fn = function() return runtimeRefreshStats.deferredFullDrains end }
    mp[#mp + 1] = { name = "CDM_hotfixDeferredFulls", counter = true, fn = function() return runtimeRefreshStats.hotfixDeferredFulls end }
    mp[#mp + 1] = { name = "CDM_spellsChangedScoped", counter = true, fn = function() return runtimeRefreshStats.spellsChangedScoped end }
    mp[#mp + 1] = { name = "CDM_unitSpellcastCooldownSkips", counter = true, fn = function() return runtimeRefreshStats.unitSpellcastCooldownSkips end }
    mp[#mp + 1] = { name = "CDM_unitSpellcastCooldownFallbacks", counter = true, fn = function() return runtimeRefreshStats.unitSpellcastCooldownFallbacks end }
end

local function isRuntimeEnabled(callbacks)
    return not callbacks.isRuntimeEnabled or callbacks.isRuntimeEnabled() ~= false
end

local function normalizeSpellIdentifier(callbacks, value)
    if callbacks.isSecretValue and callbacks.isSecretValue(value) then return nil end
    if value == nil then return nil end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return value
    end
    return nil
end

local function addSpellIdentifierToSet(callbacks, set, rawID)
    if not set then return false end
    local normalized = normalizeSpellIdentifier(callbacks, rawID)
    if normalized == nil then return false end

    set[normalized] = true
    if type(normalized) == "string" then
        local numeric = tonumber(normalized)
        if numeric then set[numeric] = true end
    end
    return true
end

local function spellIdentifierSetHas(callbacks, set, rawID)
    if not set then return false end
    local normalized = normalizeSpellIdentifier(callbacks, rawID)
    if normalized == nil then return false end
    if set[normalized] == true then return true end

    if type(normalized) == "string" then
        local numeric = tonumber(normalized)
        return numeric and set[numeric] == true or false
    end
    return false
end

local function spellIDIsGCD(callbacks, spellID)
    local normalized = normalizeSpellIdentifier(callbacks, spellID)
    if normalized == nil then return false end
    local gcdSpellID = callbacks.gcdSpellID or 61304
    if normalized == gcdSpellID then return true end
    if type(normalized) == "string" then
        return tonumber(normalized) == gcdSpellID
    end
    return false
end

local function getIconPools(callbacks)
    return (callbacks.getIconPools and callbacks.getIconPools()) or {}
end

local function isAuraEntry(callbacks, entry)
    return callbacks.isAuraEntry and callbacks.isAuraEntry(entry) or false
end

local function isItemEntry(entry)
    local entryType = entry and entry.type
    return entryType == "item" or entryType == "trinket" or entryType == "slot"
end

local function resolveContainer(callbacks, entry, ncdm, ncdmContainers)
    if callbacks.resolveContainerDBAndType then
        return callbacks.resolveContainerDBAndType(entry, ncdm, ncdmContainers)
    end
    return nil, nil
end

local function beginBatch(callbacks, reason)
    local editMode, ncdm, ncdmContainers, inCombat
    if callbacks.prepareBatch then
        editMode, ncdm, ncdmContainers, inCombat = callbacks.prepareBatch()
    end
    if callbacks.beginBatch then
        callbacks.beginBatch(reason)
    end
    return editMode, ncdm, ncdmContainers, inCombat
end

local function setStackTextWrites(callbacks, enabled)
    if callbacks.setStackTextWrites then
        callbacks.setStackTextWrites(enabled == true)
    end
end

local function clearAuraDurationBinding(callbacks, icon)
    if not icon then return false end
    local mode = icon._lastResolvedMode
    local key = icon._lastDurObjKey
    if mode ~= "aura"
        and not (type(key) == "string" and key:sub(1, 5) == "aura:") then
        return false
    end

    if callbacks.clearDurationBinding then
        callbacks.clearDurationBinding(icon)
    else
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
        icon._lastResolvedMode = nil
        icon._lastResolvedSourceID = nil
        icon._lastResolvedSpellID = nil
    end
    return true
end

local function endBatch(callbacks)
    if callbacks.endBatch then
        callbacks.endBatch()
    end
end

local function entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs)
    if not hasSpellIDs or not entry then return false end
    if spellIdentifierSetHas(callbacks, spellIDs, icon and icon._runtimeSpellID) then return true end
    if spellIdentifierSetHas(callbacks, spellIDs, entry.overrideSpellID) then return true end
    if spellIdentifierSetHas(callbacks, spellIDs, entry.spellID) then return true end
    if spellIdentifierSetHas(callbacks, spellIDs, entry.id) then return true end

    local linked = entry.linkedSpellIDs
    if type(linked) == "table" then
        for _, linkedID in ipairs(linked) do
            if spellIdentifierSetHas(callbacks, spellIDs, linkedID) then return true end
        end
    end
    return false
end

local function itemEntryMatchesAuraSpellIdentifierSet(callbacks, entry, spellIDs, hasSpellIDs)
    if not hasSpellIDs or not (entry and callbacks.queryItemSpell) then return false end
    local itemID = callbacks.getItemIDForEntry and callbacks.getItemIDForEntry(entry)
    if normalizeSpellIdentifier(callbacks, itemID) == nil then return false end

    local _, itemSpellID = callbacks.queryItemSpell(itemID)
    itemSpellID = normalizeSpellIdentifier(callbacks, itemSpellID)
    if not itemSpellID then return false end
    if spellIdentifierSetHas(callbacks, spellIDs, itemSpellID) then return true end

    if callbacks.queryCooldownAuraBySpellID then
        local auraSpellID = callbacks.queryCooldownAuraBySpellID(itemSpellID)
        return spellIdentifierSetHas(callbacks, spellIDs, auraSpellID)
    end
    return false
end

function CDMIconRuntimeRefresh.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        auraDeltaInstanceIDs = {},
        auraDeltaSpellIDs = {},
        applySpellIDScratch = {},
        -- Scratch option tables reused across drain calls so the queue-drain
        -- hot path doesn't allocate `{ refreshRuntime = ... }` /
        -- `{ includeItems = ... }` literals every fire. ApplyItemScope and
        -- friends do `options = options or {}` so they must receive a
        -- non-nil table; these are mutated just before each Apply* call.
        itemScopeOptionsScratch = { refreshRuntime = false },
        catalogScopeOptionsScratch = { includeItems = false },
        spellScopeRefreshOptionsScratch = { refreshRuntime = true },
        itemScopeRefreshOptionsScratch = { refreshRuntime = true },
        spellQueue = {
            ids = {},
            frame = nil,
            elapsed = 0,
            scheduled = false,
            delay = callbacks.getCombatQueueDelay and callbacks.getCombatQueueDelay() or 0.3,
        },
        usabilityQueue = {
            frame = nil,
            elapsed = 0,
            scheduled = false,
            delay = callbacks.getCombatQueueDelay and callbacks.getCombatQueueDelay() or 0.3,
        },
        itemQueue = {
            frame = nil,
            elapsed = 0,
            scheduled = false,
            refreshRuntime = false,
            delay = callbacks.getCombatQueueDelay and callbacks.getCombatQueueDelay() or 0.3,
        },
        catalogQueue = {
            frame = nil,
            elapsed = 0,
            scheduled = false,
            includeItems = false,
            delay = callbacks.getCombatQueueDelay and callbacks.getCombatQueueDelay() or 0.3,
        },
        deferredFullRefresh = false,
    }

    local function inCombat()
        if callbacks.isPlayerInCombat then
            return callbacks.isPlayerInCombat() == true
        end
        return InCombatLockdown and InCombatLockdown() or false
    end

    local function armQueue(state, onUpdate)
        state.scheduled = true
        state.elapsed = 0
        if not state.frame then
            state.frame = CreateFrame("Frame")
            if state.frame.Hide then state.frame:Hide() end
        end
        state.frame:SetScript("OnUpdate", onUpdate)
        if state.frame.Show then state.frame:Show() end
    end

    local function disarmQueue(state)
        state.scheduled = false
        state.elapsed = 0
        if state.frame then
            state.frame:SetScript("OnUpdate", nil)
            if state.frame.Hide then state.frame:Hide() end
        end
    end

    function controller:AddSpellIdentifierToSet(set, rawID)
        return addSpellIdentifierToSet(callbacks, set, rawID)
    end

    function controller:SpellIdentifierSetHas(set, rawID)
        return spellIdentifierSetHas(callbacks, set, rawID)
    end

    function controller:EntryMatchesSpellIdentifierSet(icon, entry, spellIDs, hasSpellIDs)
        return entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs)
    end

    function controller:ItemEntryMatchesAuraSpellIdentifierSet(entry, spellIDs, hasSpellIDs)
        return itemEntryMatchesAuraSpellIdentifierSet(callbacks, entry, spellIDs, hasSpellIDs)
    end

    function controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
        if callbacks.applyAuraScopedResolvedCooldown then
            return callbacks.applyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
        end
        if callbacks.applyResolvedCooldown then
            callbacks.applyResolvedCooldown(icon)
            return true
        end
        return false
    end

    function controller:ApplyAuraScope(options)
        options = options or {}
        local includeItems = options.includeItems == true
        local editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "auraScope")
        local refreshed = 0
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry
                    and (isAuraEntry(callbacks, entry)
                        or icon._auraActive == true
                        or (includeItems and isItemEntry(entry))) then
                    clearAuraDurationBinding(callbacks, icon)
                    if controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState) then
                        if includeItems and isItemEntry(entry) then
                            local containerDB = select(1, resolveContainer(callbacks, entry, ncdm, ncdmContainers))
                            if callbacks.updateContainerVisibility then
                                callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                            end
                            if callbacks.syncCooldownBling then
                                callbacks.syncCooldownBling(icon)
                            end
                        end
                        refreshed = refreshed + 1
                    end
                end
            end
        end
        endBatch(callbacks)
        return refreshed
    end

    function controller:ApplyItemScope(options)
        options = options or {}
        local refreshRuntime = options.refreshRuntime == true
        local batchStarted = false
        local refreshed = false
        local stackTextWritesEnabled = false
        local editMode, ncdm, ncdmContainers, inCombatState
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if isItemEntry(entry) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "itemScope")
                        batchStarted = true
                    end
                    if refreshRuntime and callbacks.updateIconCooldown then
                        -- updateIconCooldown's entry.type=="item" branch gates
                        -- the QueryItemCount → ShowIconStackText write on
                        -- stackTextWritesAllowed; without flipping it here the
                        -- bag-count badge silently never refreshes after
                        -- BAG_UPDATE_DELAYED / ITEM_COUNT_CHANGED. Mirrors the
                        -- same gating in ApplySpellScope.
                        if not stackTextWritesEnabled then
                            setStackTextWrites(callbacks, true)
                            stackTextWritesEnabled = true
                        end
                        callbacks.updateIconCooldown(icon)
                    elseif callbacks.applyResolvedCooldown then
                        callbacks.applyResolvedCooldown(icon)
                    end
                    local containerDB = select(1, resolveContainer(callbacks, entry, ncdm, ncdmContainers))
                    if callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                    end
                    if callbacks.syncCooldownBling then
                        callbacks.syncCooldownBling(icon)
                    end
                    refreshed = true
                end
            end
        end
        if stackTextWritesEnabled then
            setStackTextWrites(callbacks, false)
        end
        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:ApplySpellScope(options)
        options = options or {}
        local refreshRuntime = options.refreshRuntime == true
        local batchStarted = false
        local refreshed = false
        local stackTextWritesEnabled = false
        local editMode, ncdm, ncdmContainers, inCombatState
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and not isAuraEntry(callbacks, entry) and not isItemEntry(entry) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "spellScope")
                        batchStarted = true
                    end
                    if refreshRuntime and callbacks.updateIconCooldown then
                        if not stackTextWritesEnabled then
                            setStackTextWrites(callbacks, true)
                            stackTextWritesEnabled = true
                        end
                        callbacks.updateIconCooldown(icon)
                    elseif callbacks.applyResolvedCooldown then
                        callbacks.applyResolvedCooldown(icon)
                    end
                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" and callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                    end
                    if callbacks.syncCooldownBling then
                        callbacks.syncCooldownBling(icon)
                    end
                    refreshed = true
                end
            end
        end
        if stackTextWritesEnabled then
            setStackTextWrites(callbacks, false)
        end
        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:ApplyCatalogScope(options)
        options = options or {}
        runtimeRefreshStats.catalogScopeRefreshes = runtimeRefreshStats.catalogScopeRefreshes + 1
        local refreshed = controller:ApplySpellScope(controller.spellScopeRefreshOptionsScratch) == true
        if options.includeItems then
            refreshed = controller:ApplyItemScope(controller.itemScopeRefreshOptionsScratch) == true or refreshed
        end
        return refreshed
    end

    function controller:InvalidateGCDOnlyBindings()
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local lk = icon and icon._lastDurObjKey
                if icon
                    and (icon._lastResolvedMode == "gcd-only"
                        or (type(lk) == "string" and lk:sub(1, 9) == "gcd-only:")) then
                    if callbacks.clearDurationBinding then
                        callbacks.clearDurationBinding(icon)
                    else
                        icon._lastDurObjKey = nil
                        icon._lastDurObj = nil
                        icon._lastResolvedMode = nil
                        icon._lastResolvedSourceID = nil
                        icon._lastResolvedSpellID = nil
                    end
                end
            end
        end
    end

    function controller:InvalidateSpellCooldownBinding(spellID)
        local ids = {}
        if not addSpellIdentifierToSet(callbacks, ids, spellID) then return end
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                local lk = icon and icon._lastDurObjKey
                if entry and lk and entryMatchesSpellIdentifierSet(callbacks, icon, entry, ids, true) then
                    local mode = icon._lastResolvedMode
                    local isCooldownKey = mode == "cooldown"
                        or mode == "gcd-only"
                        or mode == "item-cooldown"
                    if not isCooldownKey and type(lk) == "string" then
                        isCooldownKey = lk:sub(1, 9) == "cooldown:"
                            or lk:sub(1, 9) == "gcd-only:"
                            or lk:sub(1, 14) == "item-cooldown:"
                    end
                    if isCooldownKey then
                        if callbacks.clearDurationBinding then
                            callbacks.clearDurationBinding(icon)
                        else
                            icon._lastDurObjKey = nil
                            icon._lastDurObj = nil
                            icon._lastResolvedMode = nil
                            icon._lastResolvedSourceID = nil
                            icon._lastResolvedSpellID = nil
                        end
                    end
                end
            end
        end
    end

    function controller:ApplySpellID(eventSpellID, eventBaseSpellID)
        local spellIDs = controller.applySpellIDScratch
        wipe(spellIDs)
        local hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventSpellID)
        hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventBaseSpellID) or hasSpellIDs
        if not hasSpellIDs then return false end

        local batchStarted = false
        local refreshed = false
        local stackTextWritesEnabled = false
        local editMode, ncdm, ncdmContainers, inCombatState
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "spellID")
                        batchStarted = true
                    end
                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if isAuraEntry(callbacks, entry) or cType == "aura" or cType == "auraBar" then
                        controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
                    else
                        if callbacks.updateIconCooldown then
                            if not stackTextWritesEnabled then
                                setStackTextWrites(callbacks, true)
                                stackTextWritesEnabled = true
                            end
                            callbacks.updateIconCooldown(icon)
                        elseif callbacks.applyResolvedCooldown then
                            callbacks.applyResolvedCooldown(icon)
                        end
                        -- Visibility + bling for matched (cast) icon. These were
                        -- previously done by an ApplySpellScope() walk over EVERY
                        -- spell icon on cast_succeeded; scoping them to the matched
                        -- icons here lets that broader walk be removed entirely.
                        if callbacks.updateContainerVisibility then
                            callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                        end
                        if callbacks.syncCooldownBling then
                            callbacks.syncCooldownBling(icon)
                        end
                    end
                    refreshed = true
                end
            end
        end
        if stackTextWritesEnabled then
            setStackTextWrites(callbacks, false)
        end
        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:ApplyAuraInstances(unit, updateInfo)
        if not updateInfo or updateInfo.isFullUpdate then return nil end

        local ids = controller.auraDeltaInstanceIDs
        wipe(ids)
        local hasIDs = false

        local spellIDs = controller.auraDeltaSpellIDs
        wipe(spellIDs)
        local hasSpellIDs = false

        if updateInfo.addedAuras then
            for _, auraData in ipairs(updateInfo.addedAuras) do
                local auraInstanceID = auraData and auraData.auraInstanceID
                if auraInstanceID ~= nil then
                    ids[auraInstanceID] = true
                    hasIDs = true
                end
                if auraData then
                    hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, auraData.spellId) or hasSpellIDs
                    hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, auraData.spellID) or hasSpellIDs
                end
            end
        end
        if updateInfo.updatedAuraInstanceIDs then
            for _, auraInstanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if auraInstanceID ~= nil then
                    ids[auraInstanceID] = true
                    hasIDs = true
                end
            end
        end
        if updateInfo.removedAuraInstanceIDs then
            for _, auraInstanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
                if auraInstanceID ~= nil then
                    ids[auraInstanceID] = true
                    hasIDs = true
                end
            end
        end

        if not hasIDs and not hasSpellIDs then return 0 end

        local refreshed = 0
        local batchStarted = false
        local editMode, ncdm, ncdmContainers, inCombatState
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                local iconAuraInstanceID = icon and icon._auraInstanceID
                local matches = iconAuraInstanceID
                    and ids[iconAuraInstanceID]
                    and (not unit or icon._auraUnit == unit)
                if not matches and icon and icon._blizzMirrorCooldownID and callbacks.getMirrorStateByCooldownID then
                    local state = callbacks.getMirrorStateByCooldownID(icon._blizzMirrorCooldownID, icon._blizzMirrorCategory)
                    local mirrorAuraInstanceID = state and state.auraInstanceID
                    matches = mirrorAuraInstanceID
                        and ids[mirrorAuraInstanceID]
                        and (not unit or state.auraUnit == unit or icon._auraUnit == unit)
                end
                if not matches
                    and entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs) then
                    matches = true
                end
                if not matches
                    and itemEntryMatchesAuraSpellIdentifierSet(callbacks, entry, spellIDs, hasSpellIDs) then
                    matches = true
                end
                if matches and entry then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "auraDelta")
                        batchStarted = true
                    end
                    clearAuraDurationBinding(callbacks, icon)
                    if controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState) then
                        refreshed = refreshed + 1
                    end
                end
            end
        end
        if batchStarted then
            endBatch(callbacks)
        end

        return refreshed
    end

    function controller:IconNeedsUsabilityCooldownRefresh(icon)
        local entry = icon and icon._spellEntry
        if not entry then return false end
        if isAuraEntry(callbacks, entry) then return false end
        if entry.kind == "aura" or entry.kind == "auraBar" then return false end
        if isItemEntry(entry) then return false end
        if icon._hasCooldownActive == true or icon._hasRealCooldownActive == true then return true end
        if icon._showingRealCooldownSwipe or icon._showingGCDSwipe then return true end
        if icon._lastDurObjKey ~= nil or icon._cooldownExpiryTimerKey ~= nil then return true end
        if icon._isOnGCD ~= nil or icon._cdDesaturated then return true end
        return false
    end

    local function IconHasGCDRenderLock(icon)
        return icon
            and icon._showingGCDSwipe == true
            and icon._showingRealCooldownSwipe ~= true
            and icon._hasRealCooldownActive ~= true
    end

    function controller:ApplyUsabilityRefresh()
        local refreshed = 0
        local editMode, ncdm, ncdmContainers, inCombatState
        local batchStarted = false
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and controller:IconNeedsUsabilityCooldownRefresh(icon) then
                    if not batchStarted then
                        if callbacks.prepareBatch then
                            editMode, ncdm, ncdmContainers, inCombatState = callbacks.prepareBatch()
                        end
                        if callbacks.beginBatch then
                            callbacks.beginBatch("usability")
                        end
                        batchStarted = true
                    end
                    local skipCooldownApply = IconHasGCDRenderLock(icon)
                        and icon._cdDesaturated ~= true
                    if not skipCooldownApply and callbacks.applyResolvedCooldown then
                        callbacks.applyResolvedCooldown(icon)
                    end

                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" and callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                    end
                    refreshed = refreshed + 1
                end
            end
        end

        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed > 0 and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:RunUsabilityRefresh()
        controller:ApplyUsabilityRefresh()
        if callbacks.updateIconRangesForUsabilityEvent then
            callbacks.updateIconRangesForUsabilityEvent()
        end
    end

    function controller:RefreshCooldownVisualsForSpellID(eventSpellID, eventBaseSpellID)
        local spellIDs = {}
        local hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventSpellID)
        hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventBaseSpellID) or hasSpellIDs
        if not hasSpellIDs then return false end

        local editMode, ncdm, ncdmContainers, inCombatState
        if callbacks.prepareBatch then
            editMode, ncdm, ncdmContainers, inCombatState = callbacks.prepareBatch()
        end
        local refreshed = false

        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs) then
                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" and callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                        refreshed = true
                    end
                end
            end
        end

        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end

        return refreshed
    end

    local function drainSpellQueue()
        local state = controller.spellQueue
        disarmQueue(state)
        if next(state.ids) == nil then return end

        local editMode, ncdm, ncdmContainers, inCombatState
        local refreshed = false
        local batchStarted = false
        local stackTextWritesEnabled = false
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entryMatchesSpellIdentifierSet(callbacks, icon, entry, state.ids, true) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "spellID")
                        batchStarted = true
                    end
                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if isAuraEntry(callbacks, entry) or cType == "aura" or cType == "auraBar" then
                        controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
                    else
                        if callbacks.updateIconCooldown then
                            if not stackTextWritesEnabled then
                                setStackTextWrites(callbacks, true)
                                stackTextWritesEnabled = true
                            end
                            callbacks.updateIconCooldown(icon)
                        elseif callbacks.applyResolvedCooldown then
                            callbacks.applyResolvedCooldown(icon)
                        end
                        if callbacks.updateContainerVisibility then
                            callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                        end
                    end
                    refreshed = true
                end
            end
        end
        if stackTextWritesEnabled then
            setStackTextWrites(callbacks, false)
        end
        if batchStarted then
            endBatch(callbacks)
        end
        wipe(state.ids)

        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
    end

    -- Memaudit instrumentation: drain runs on a dynamic OnUpdate frame outside
    -- QUI_PerfRegistry. Reassigning (not redeclaring) the local lets the
    -- spellQueueOnUpdate upvalue pick up the wrapped version.
    local _drainSpellQueueImpl = drainSpellQueue
    drainSpellQueue = function(...)
        local measure = ns.MemAuditProfilerMeasure
        if measure then return measure("CDM_drainSpellQueue", _drainSpellQueueImpl, ...) end
        return _drainSpellQueueImpl(...)
    end

    local function spellQueueOnUpdate(_, elapsed)
        local state = controller.spellQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainSpellQueue()
    end

    function controller:QueueResolvedCooldownForSpellID(eventSpellID, eventBaseSpellID)
        if not inCombat() then
            -- ApplySpellID now folds in visibility + bling for matched icons,
            -- so the separate RefreshCooldownVisualsForSpellID call that used
            -- to follow here is redundant. Kept defined for the public API.
            controller:ApplySpellID(eventSpellID, eventBaseSpellID)
            return
        end

        local state = controller.spellQueue
        local added = addSpellIdentifierToSet(callbacks, state.ids, eventSpellID)
        added = addSpellIdentifierToSet(callbacks, state.ids, eventBaseSpellID) or added
        if not added then return end

        if state.scheduled then return end
        armQueue(state, spellQueueOnUpdate)
    end

    local function drainUsabilityQueue()
        disarmQueue(controller.usabilityQueue)
        controller:RunUsabilityRefresh()
    end

    local _drainUsabilityQueueImpl = drainUsabilityQueue
    drainUsabilityQueue = function(...)
        local measure = ns.MemAuditProfilerMeasure
        if measure then return measure("CDM_drainUsabilityQueue", _drainUsabilityQueueImpl, ...) end
        return _drainUsabilityQueueImpl(...)
    end

    local function usabilityQueueOnUpdate(_, elapsed)
        local state = controller.usabilityQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainUsabilityQueue()
    end

    function controller:QueueUsabilityRefresh()
        if not inCombat() then
            controller:RunUsabilityRefresh()
            return
        end

        local state = controller.usabilityQueue
        if state.scheduled then return end
        armQueue(state, usabilityQueueOnUpdate)
    end

    local function drainItemQueue()
        local state = controller.itemQueue
        local refreshRuntime = state.refreshRuntime == true
        state.refreshRuntime = false
        disarmQueue(state)
        local opts = controller.itemScopeOptionsScratch
        opts.refreshRuntime = refreshRuntime
        controller:ApplyItemScope(opts)
    end

    local _drainItemQueueImpl = drainItemQueue
    drainItemQueue = function(...)
        local measure = ns.MemAuditProfilerMeasure
        if measure then return measure("CDM_drainItemQueue", _drainItemQueueImpl, ...) end
        return _drainItemQueueImpl(...)
    end

    local function itemQueueOnUpdate(_, elapsed)
        local state = controller.itemQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainItemQueue()
    end

    function controller:QueueItemScopeRefresh(options)
        options = options or {}
        if not inCombat() then
            controller:ApplyItemScope(options)
            return
        end

        local state = controller.itemQueue
        if options.refreshRuntime then
            state.refreshRuntime = true
        end
        if state.scheduled then return end
        armQueue(state, itemQueueOnUpdate)
    end

    local function drainCatalogQueue()
        local state = controller.catalogQueue
        local includeItems = state.includeItems == true
        state.includeItems = false
        disarmQueue(state)
        local opts = controller.catalogScopeOptionsScratch
        opts.includeItems = includeItems
        controller:ApplyCatalogScope(opts)
    end

    local _drainCatalogQueueImpl = drainCatalogQueue
    drainCatalogQueue = function(...)
        local measure = ns.MemAuditProfilerMeasure
        if measure then return measure("CDM_drainCatalogQueue", _drainCatalogQueueImpl, ...) end
        return _drainCatalogQueueImpl(...)
    end

    local function catalogQueueOnUpdate(_, elapsed)
        local state = controller.catalogQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainCatalogQueue()
    end

    function controller:QueueCatalogScopeRefresh(options)
        options = options or {}
        if not inCombat() then
            controller:ApplyCatalogScope(options)
            return
        end

        local state = controller.catalogQueue
        if options.includeItems then
            state.includeItems = true
        end
        if state.scheduled then return end
        runtimeRefreshStats.catalogScopeQueued = runtimeRefreshStats.catalogScopeQueued + 1
        armQueue(state, catalogQueueOnUpdate)
    end

    function controller:DeferFullRefresh()
        if not controller.deferredFullRefresh then
            runtimeRefreshStats.deferredFullRefreshes = runtimeRefreshStats.deferredFullRefreshes + 1
        end
        controller.deferredFullRefresh = true
    end

    function controller:DrainDeferredFullRefresh()
        if not controller.deferredFullRefresh then return false end
        controller.deferredFullRefresh = false
        runtimeRefreshStats.deferredFullDrains = runtimeRefreshStats.deferredFullDrains + 1
        if callbacks.scheduleUpdate then
            callbacks.scheduleUpdate(true, UPDATE_FULL, nil, "deferred")
        end
        return true
    end

    function controller:NoteChargeDurationObjectsUpdated()
        if callbacks.noteChargeDurationObjectsUpdated then
            callbacks.noteChargeDurationObjectsUpdated()
        end
    end

    function controller:ApplyTargetScope(event)
        if callbacks.chargeDebug then
            callbacks.chargeDebug(nil, "EVENT", event, "target-scope-refresh")
        end
        if callbacks.updateAllIconRanges then
            callbacks.updateAllIconRanges()
        end
        local refreshed = controller:ApplyAuraScope()
        if refreshed > 0 then
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
        end
        controller:QueueUsabilityRefresh()
    end

    function controller:HandleAuraRefresh(unit, updateInfo)
        if not isRuntimeEnabled(callbacks) then return end
        if callbacks.eventTracePrint then
            callbacks.eventTracePrint("aura-pre", "UNIT_AURA", unit, nil, nil,
                callbacks.eventTraceAuraInfo and callbacks.eventTraceAuraInfo(updateInfo))
        end

        if callbacks.requestStackTextUpdate then
            callbacks.requestStackTextUpdate()
        end

        if not updateInfo or updateInfo.isFullUpdate then
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            controller:ApplyAuraScope({ includeItems = unit == "player" })
            if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
        else
            local refreshed = controller:ApplyAuraInstances(unit, updateInfo) or 0
            if refreshed > 0 then
                if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
                if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
            end
        end

        if callbacks.eventTracePrint then
            callbacks.eventTracePrint("aura-post", "UNIT_AURA", unit, nil, nil,
                callbacks.eventTraceAuraInfo and callbacks.eventTraceAuraInfo(updateInfo))
        end
    end

    function controller:HandleFrameEvent(frame, event, arg1, arg2, arg3)
        if not isRuntimeEnabled(callbacks) then
            if callbacks.onRuntimeDisabled then
                callbacks.onRuntimeDisabled(frame)
            end
            return
        end

        if event == "UNIT_SPELLCAST_STOP"
           or event == "UNIT_SPELLCAST_CHANNEL_START"
           or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            local isPlayerUnit = not (callbacks.isSecretValue and callbacks.isSecretValue(arg1))
                and arg1 == "player"
            if isPlayerUnit then
                if normalizeSpellIdentifier(callbacks, arg3) ~= nil then
                    runtimeRefreshStats.unitSpellcastCooldownSkips = runtimeRefreshStats.unitSpellcastCooldownSkips + 1
                    controller:QueueResolvedCooldownForSpellID(arg3, nil)
                elseif callbacks.scheduleUpdate then
                    runtimeRefreshStats.unitSpellcastCooldownFallbacks = runtimeRefreshStats.unitSpellcastCooldownFallbacks + 1
                    callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, nil, "unit_spellcast")
                end
            end
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then
            controller:ApplyTargetScope(event)
            return
        end
        if event == "PLAYER_SOFT_ENEMY_CHANGED" then
            controller:ApplyTargetScope(event)
            return
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            if arg1 == 13 or arg1 == 14 then
                controller:QueueItemScopeRefresh({ refreshRuntime = true })
            end
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            controller:DrainDeferredFullRefresh()
            return
        end
        if event == "UPDATE_MACROS" then
            if callbacks.invalidateMacroCache then
                callbacks.invalidateMacroCache()
            end
            return
        end
        if event == "SPELL_RANGE_CHECK_UPDATE" then
            if callbacks.updateIconsForSpellRangeEvent then
                callbacks.updateIconsForSpellRangeEvent(arg1, arg2, arg3)
            end
            return
        end
        if event == "SPELL_UPDATE_USABLE" then
            controller:QueueUsabilityRefresh()
            return
        end
        if event == "SPELLS_CHANGED" then
            if callbacks.clearTextureCycleCache then
                callbacks.clearTextureCycleCache()
            end
            if callbacks.clearDurationBindingKeyCache then
                callbacks.clearDurationBindingKeyCache()
            end
            if callbacks.clearStableCaches then
                callbacks.clearStableCaches()
            end
            runtimeRefreshStats.spellsChangedScoped = runtimeRefreshStats.spellsChangedScoped + 1
            controller:QueueCatalogScopeRefresh({ includeItems = true })
            return
        end
        if event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
            if inCombat() then
                runtimeRefreshStats.hotfixDeferredFulls = runtimeRefreshStats.hotfixDeferredFulls + 1
                controller:DeferFullRefresh()
                return
            end
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_FULL, nil, "hotfix")
            end
            return
        end
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
           or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            if arg1 then
                controller:QueueResolvedCooldownForSpellID(arg1, nil)
            end
            return
        end
        if event == "BAG_UPDATE_COOLDOWN" then
            controller:QueueItemScopeRefresh()
            return
        end
        if event == "BAG_UPDATE_DELAYED" or event == "ITEM_COUNT_CHANGED" then
            controller:QueueItemScopeRefresh({ refreshRuntime = true })
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
            return
        end
    end

    function controller:Handle(event, arg1, arg2, arg3, frame)
        if event == "UNIT_AURA" then
            return controller:HandleAuraRefresh(arg1, arg2)
        end
        return controller:HandleFrameEvent(frame, event, arg1, arg2, arg3)
    end

    function controller:HandleCooldownChanged(_, spellID, baseSpellID, kind)
        if not isRuntimeEnabled(callbacks) then return end
        if kind == "scanner_item" then
            controller:ApplyItemScope()
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
        elseif kind == "scanner_spell" then
            controller:ApplySpellScope()
        elseif kind == "refresh" then
            local gcdChanged = callbacks.captureTrustedGCDState and callbacks.captureTrustedGCDState() or false
            local comparableSpellID = normalizeSpellIdentifier(callbacks, spellID) ~= nil
            local spellIDIsGCDSpell = comparableSpellID and spellIDIsGCD(callbacks, spellID) or false
            if callbacks.setTrustIsOnGCDForBatch then
                callbacks.setTrustIsOnGCDForBatch(true)
            end
            if comparableSpellID and not spellIDIsGCDSpell and not gcdChanged then
                -- SPELL_UPDATE_COOLDOWN with a payload is Blizzard's
                -- canonical "this spell's cooldown lane just changed"
                -- signal. Apply directly instead of going through
                -- QueueResolvedCooldownForSpellID — that path's combat
                -- queue stalls the rebind by up to 0.3s (queue delay
                -- in CDMIconRuntimeRefresh.Create at line 2152), and
                -- in-game traces showed proc-window rebinds lagging
                -- 2+ seconds behind the SUC fire because the queue
                -- drain kept getting pre-empted by the next SUC tick.
                -- Skipping the queue collapses the lag to one frame;
                -- ApplySpellID at line 2414 already iterates only
                -- matching icons, so the extra work is bounded.
                controller:ApplySpellID(spellID, baseSpellID)
            elseif gcdChanged or spellIDIsGCDSpell then
                -- Real GCD edge: GCD-only icons must re-resolve to show the
                -- new GCD swipe. The broad walk is the catch-all for now;
                -- a follow-up should replace it with a GCD-only icon index.
                controller:InvalidateGCDOnlyBindings()
                controller:ApplySpellScope()
                -- A specific spellID can arrive alongside a GCD edge —
                -- e.g., a cast that puts the spell on a real cooldown
                -- AND starts the GCD. ApplySpellScope handles the GCD
                -- icons; the targeted bind for the named spell would
                -- otherwise have to wait for the next aura tick.
                if comparableSpellID and not spellIDIsGCDSpell then
                    controller:ApplySpellID(spellID, baseSpellID)
                end
            end
            -- Else: nil spellID with no GCD edge — Blizzard's "something
            -- changed somewhere" fallback. Real changes that need handling
            -- already fire specific events (UNIT_SPELLCAST_* with spellID,
            -- SPELL_UPDATE_CHARGES/USES, BAG_UPDATE_COOLDOWN). Walking every
            -- icon defensively here is pure churn.
            if callbacks.setTrustIsOnGCDForBatch then
                callbacks.setTrustIsOnGCDForBatch(false)
            end
        elseif kind == "cast_start" then
            if normalizeSpellIdentifier(callbacks, spellID) ~= nil then
                runtimeRefreshStats.castStartCooldownSkips = runtimeRefreshStats.castStartCooldownSkips + 1
                controller:QueueResolvedCooldownForSpellID(spellID, baseSpellID)
            elseif callbacks.scheduleUpdate then
                runtimeRefreshStats.castStartCooldownFallbacks = runtimeRefreshStats.castStartCooldownFallbacks + 1
                callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, nil, "cast_start")
            end
        elseif kind == "cast_succeeded" then
            if callbacks.recordRecentPlayerSpellCast then
                callbacks.recordRecentPlayerSpellCast(spellID)
            end
            controller:InvalidateGCDOnlyBindings()
            controller:InvalidateSpellCooldownBinding(spellID)
            -- ApplySpellScope() removed: it walked every spell icon doing
            -- updateContainerVisibility + syncCooldownBling. Those are now
            -- folded into ApplySpellID below, scoped to the cast spell's
            -- matching icons (which is what we actually changed).
            controller:ApplySpellID(spellID, nil)
            if callbacks.requestStackTextUpdate then
                callbacks.requestStackTextUpdate()
            end
            runtimeRefreshStats.castSucceededCooldownSkips = runtimeRefreshStats.castSucceededCooldownSkips + 1
            local highlighter = callbacks.getHighlighter and callbacks.getHighlighter()
            if highlighter and highlighter.OnPlayerCastSucceeded then
                highlighter.OnPlayerCastSucceeded(spellID)
            end
        end
    end

    function controller:HandleChargesChanged(_, spellID)
        if not isRuntimeEnabled(callbacks) then return end
        controller:NoteChargeDurationObjectsUpdated()
        if callbacks.requestStackTextUpdate then
            callbacks.requestStackTextUpdate()
        end
        if normalizeSpellIdentifier(callbacks, spellID) ~= nil then
            runtimeRefreshStats.chargeCooldownSkips = runtimeRefreshStats.chargeCooldownSkips + 1
            controller:QueueResolvedCooldownForSpellID(spellID, nil)
        else
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(nil, UPDATE_COOLDOWN, false)
            end
            controller:ApplySpellScope()
        end
    end

    return controller
end
end

do
-- Inlined from cdm_icon_update_scheduler.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Update Scheduler
--
-- Private controller used by CDMIcons. It owns icon refresh cadence, fallback
-- frame coalescing, merged GCD trust state, and bar-dirty draining.
---------------------------------------------------------------------------

local CDMIconUpdateScheduler = {}
ns.CDMIconUpdateScheduler = CDMIconUpdateScheduler

local UPDATE_COOLDOWN = "cooldown"
local UPDATE_FULL = "full"

local MIN_UPDATE_INTERVAL_IDLE = 0.05
local MIN_UPDATE_INTERVAL_COMBAT = 0.20
local MIN_UPDATE_INTERVAL_RAID_COMBAT = 0.30
local FAST_UPDATE_INTERVAL = 0
local FAST_FULL_UPDATE_INTERVAL = MIN_UPDATE_INTERVAL_IDLE

function CDMIconUpdateScheduler.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        frame = CreateFrame("Frame"),
        pending = false,
        elapsed = 0,
        delay = MIN_UPDATE_INTERVAL_IDLE,
        mode = UPDATE_COOLDOWN,
        pendingTrustIsOnGCD = false,
        barsDirty = false,
        lastUpdateTime = 0,
    }

    local function isRuntimeEnabled()
        return not callbacks.isRuntimeEnabled or callbacks.isRuntimeEnabled() ~= false
    end

    local function getTime()
        if callbacks.getTime then
            return callbacks.getTime()
        end
        return GetTime and GetTime() or 0
    end

    function controller:GetDelay(fast, mode)
        if fast then
            if mode == UPDATE_COOLDOWN then
                return FAST_UPDATE_INTERVAL
            end
            return FAST_FULL_UPDATE_INTERVAL
        end
        local inCombat
        if callbacks.isInCombat then
            inCombat = callbacks.isInCombat()
        else
            inCombat = InCombatLockdown and InCombatLockdown()
        end
        if not inCombat then
            return MIN_UPDATE_INTERVAL_IDLE
        end
        local inRaid
        if callbacks.isInRaid then
            inRaid = callbacks.isInRaid()
        else
            inRaid = IsInRaid and IsInRaid()
        end
        if inRaid then
            return MIN_UPDATE_INTERVAL_RAID_COMBAT
        end
        return MIN_UPDATE_INTERVAL_COMBAT
    end

    function controller:GetCombatQueueDelay()
        return MIN_UPDATE_INTERVAL_RAID_COMBAT
    end

    function controller:SetBarsDirty(dirty)
        controller.barsDirty = dirty == true
    end

    function controller:IsBarsDirty()
        return controller.barsDirty == true
    end

    function controller:RunDirtyBarUpdate()
        if not controller.barsDirty then return end
        local bars = callbacks.getBars and callbacks.getBars()
        if bars and bars.UpdateOwnedBars then
            controller.barsDirty = false
            bars:UpdateOwnedBars()
        end
    end

    function controller:Cancel()
        controller.frame:SetScript("OnUpdate", nil)
        controller.pending = false
        controller.elapsed = 0
        controller.mode = UPDATE_COOLDOWN
        controller.pendingTrustIsOnGCD = false
        local scheduler = callbacks.getScheduler and callbacks.getScheduler()
        if scheduler and scheduler.CancelRuntimeUpdate then
            scheduler.CancelRuntimeUpdate()
        end
    end

    function controller:Run(modeOverride, trustOverride)
        controller.pending = false
        local mode = modeOverride or controller.mode or UPDATE_COOLDOWN
        controller.mode = UPDATE_COOLDOWN
        local trustIsOnGCD
        if trustOverride ~= nil then
            trustIsOnGCD = trustOverride == true
        else
            trustIsOnGCD = controller.pendingTrustIsOnGCD == true
        end
        controller.pendingTrustIsOnGCD = false

        if not isRuntimeEnabled() then
            return
        end

        controller.lastUpdateTime = getTime()
        if callbacks.setTrustIsOnGCDForBatch then
            callbacks.setTrustIsOnGCDForBatch(trustIsOnGCD)
        end

        if mode == UPDATE_FULL then
            if callbacks.updateAllCooldowns then
                callbacks.updateAllCooldowns()
            end
        elseif callbacks.updateCooldownOnly then
            callbacks.updateCooldownOnly()
        end

        controller:RunDirtyBarUpdate()

        if callbacks.setTrustIsOnGCDForBatch then
            callbacks.setTrustIsOnGCDForBatch(false)
        end
    end

    local function onUpdate(self, elapsed)
        controller.elapsed = controller.elapsed + (elapsed or 0)
        if controller.elapsed < controller.delay then return end
        self:SetScript("OnUpdate", nil)
        controller:Run()
    end

    function controller:Schedule(fast, mode, trustIsOnGCD)
        if not isRuntimeEnabled() then
            controller:Cancel()
            return
        end

        mode = (mode == UPDATE_FULL) and UPDATE_FULL or UPDATE_COOLDOWN

        local scheduler = callbacks.getScheduler and callbacks.getScheduler()
        if scheduler and scheduler.ScheduleRuntimeUpdate then
            scheduler.ScheduleRuntimeUpdate(fast, mode, trustIsOnGCD)
            return
        end

        local delay = controller:GetDelay(fast, mode)

        if controller.pending then
            if mode == UPDATE_FULL then
                controller.mode = UPDATE_FULL
            end
            if trustIsOnGCD then
                controller.pendingTrustIsOnGCD = true
            end
            if delay < controller.delay then
                controller.delay = delay
            end
            return
        end

        controller.pending = true
        controller.elapsed = 0
        controller.delay = delay
        controller.mode = mode
        controller.pendingTrustIsOnGCD = trustIsOnGCD == true
        controller.frame:SetScript("OnUpdate", onUpdate)
    end

    function controller:ScheduleFull(fast, trustIsOnGCD)
        controller:Schedule(fast, UPDATE_FULL, trustIsOnGCD)
    end

    function controller:ScheduleCooldown(fast, trustIsOnGCD)
        controller:Schedule(fast, UPDATE_COOLDOWN, trustIsOnGCD)
    end

    function controller:RegisterSchedulerHandler()
        local scheduler = callbacks.getScheduler and callbacks.getScheduler()
        if not (scheduler and scheduler.SetRuntimeUpdateHandler) then return end
        scheduler.SetRuntimeUpdateHandler({
            run = function(mode, trustIsOnGCD)
                return controller:Run(mode, trustIsOnGCD)
            end,
            getDelay = function(fast, mode)
                return controller:GetDelay(fast, mode)
            end,
            isEnabled = isRuntimeEnabled,
            onCancel = function()
                controller.pending = false
                controller.pendingTrustIsOnGCD = false
            end,
        })
    end

    function controller:GetStats()
        local scheduler = callbacks.getScheduler and callbacks.getScheduler()
        local schedulerPending = scheduler
            and scheduler.IsRuntimeUpdatePending
            and scheduler.IsRuntimeUpdatePending()
        return {
            barsDirty = controller.barsDirty == true,
            updatePending = (schedulerPending ~= nil and schedulerPending)
                or (controller.pending == true),
            updateMode = controller.mode,
            trustIsOnGCD = controller.pendingTrustIsOnGCD == true,
            lastUpdateTime = controller.lastUpdateTime,
        }
    end

    controller:RegisterSchedulerHandler()
    return controller
end
end

do
-- Inlined from cdm_icon_refresh_batch.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Refresh Batch
--
-- Private controller used by CDMIcons. It owns runtime-query batch accounting,
-- per-refresh DB/time hoists, edit/combat batch preparation, and stack-text
-- write requests that are consumed by cooldown-only refreshes.
---------------------------------------------------------------------------

local CDMIconRefreshBatch = {}
ns.CDMIconRefreshBatch = CDMIconRefreshBatch

local pairs = pairs

local DEFAULT_REASONS = {
    updateAll = true,
    cooldownOnly = true,
    type = true,
    placed = true,
    auraScope = true,
    itemScope = true,
    spellScope = true,
    spellID = true,
    auraDelta = true,
    usability = true,
    mirror = true,
    other = true,
}

local function createStats()
    local stats = {}
    for reason in pairs(DEFAULT_REASONS) do
        stats[reason] = 0
    end
    return stats
end

function CDMIconRefreshBatch.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        stats = createStats(),
        ncdm = nil,
        batchTime = 0,
        pendingStackTextUpdate = false,
    }

    local function getTime()
        if callbacks.getTime then
            return callbacks.getTime()
        end
        return GetTime and GetTime() or 0
    end

    local function registerMemProbes()
        local getMemProbes = callbacks.getMemProbes
        if not getMemProbes then return end
        local mp = getMemProbes()
        if not mp then return end
        for reason in pairs(DEFAULT_REASONS) do
            mp[#mp + 1] = {
                name = "CDM_iconBatch_" .. reason,
                counter = true,
                fn = function()
                    return controller.stats[reason] or 0
                end,
            }
        end
    end

    function controller:Prepare()
        local editMode = false
        if callbacks.isEditModeActive and callbacks.isEditModeActive() then
            editMode = true
        elseif callbacks.isLayoutModeActive and callbacks.isLayoutModeActive() then
            editMode = true
        elseif callbacks.isGlobalEditModeActive and callbacks.isGlobalEditModeActive() then
            editMode = true
        end

        local ncdm = callbacks.getNCDM and callbacks.getNCDM() or nil
        controller.ncdm = ncdm
        controller.batchTime = getTime()

        if callbacks.refreshSwipeBatchSettings then
            callbacks.refreshSwipeBatchSettings()
        end

        local inCombat
        if callbacks.isInCombat then
            inCombat = callbacks.isInCombat()
        else
            inCombat = InCombatLockdown and InCombatLockdown() or false
        end

        return editMode, ncdm, ncdm and ncdm.containers, inCombat
    end

    function controller:GetNCDM()
        return controller.ncdm
    end

    function controller:GetTime()
        return controller.batchTime
    end

    function controller:Begin(reason)
        if reason and controller.stats[reason] ~= nil then
            controller.stats[reason] = controller.stats[reason] + 1
        else
            controller.stats.other = controller.stats.other + 1
        end
        if callbacks.beginRuntimeQueryBatch then
            callbacks.beginRuntimeQueryBatch()
        end
    end

    function controller:End()
        if callbacks.endRuntimeQueryBatch then
            callbacks.endRuntimeQueryBatch()
        end
    end

    function controller:SetStackTextWrites(enabled)
        if callbacks.setStackTextWrites then
            callbacks.setStackTextWrites(enabled == true)
        end
    end

    function controller:RequestStackTextUpdate()
        controller.pendingStackTextUpdate = true
    end

    function controller:ConsumeStackTextWriteRequest()
        local requested = controller.pendingStackTextUpdate == true
        controller.pendingStackTextUpdate = false
        return requested
    end

    function controller:GetStats()
        return controller.stats
    end

    registerMemProbes()
    return controller
end
end

do
-- Inlined from cdm_icon_refresh_walker.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Refresh Walker
--
-- Private controller used by CDMIcons. It owns broad icon-pool traversal for
-- runtime refresh passes while CDMIcons supplies renderer mutation callbacks.
---------------------------------------------------------------------------

local CDMIconRefreshWalker = {}
ns.CDMIconRefreshWalker = CDMIconRefreshWalker

local pairs = pairs
local ipairs = ipairs

local function getIconPools(callbacks)
    return (callbacks.getIconPools and callbacks.getIconPools()) or {}
end

local function isAuraContainerType(containerType)
    return containerType == "aura" or containerType == "auraBar"
end

function CDMIconRefreshWalker.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}

    function controller:RefreshAll(context)
        local refreshed = 0
        local measure = ns.MemAuditProfilerMeasure
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                if callbacks.refreshAllIcon then
                    if measure then
                        measure("CDM_walkAllIcon", callbacks.refreshAllIcon, icon, context)
                    else
                        callbacks.refreshAllIcon(icon, context)
                    end
                    refreshed = refreshed + 1
                end
            end
        end
        return refreshed
    end

    function controller:RefreshCooldownOnly(context)
        context = context or {}
        local refreshed = 0
        local measure = ns.MemAuditProfilerMeasure
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry then
                    local containerDB, containerType
                    if callbacks.resolveContainerDBAndType then
                        if measure then
                            containerDB, containerType = measure(
                                "CDM_walkResolve",
                                callbacks.resolveContainerDBAndType,
                                entry,
                                context.ncdm,
                                context.ncdmContainers)
                        else
                            containerDB, containerType = callbacks.resolveContainerDBAndType(
                                entry, context.ncdm, context.ncdmContainers)
                        end
                    end
                    if not isAuraContainerType(containerType) then
                        if callbacks.refreshCooldownOnlyIcon then
                            if measure then
                                measure("CDM_walkCooldownIcon", callbacks.refreshCooldownOnlyIcon, icon, entry, context)
                            else
                                callbacks.refreshCooldownOnlyIcon(icon, entry, context)
                            end
                        end
                        if callbacks.updateIconVisibility then
                            if measure then
                                measure(
                                    "CDM_walkVisibility",
                                    callbacks.updateIconVisibility,
                                    icon,
                                    entry,
                                    containerDB,
                                    context.editMode,
                                    context.inCombat)
                            else
                                callbacks.updateIconVisibility(
                                    icon, entry, containerDB, context.editMode, context.inCombat)
                            end
                        end
                        refreshed = refreshed + 1
                    end
                end
            end
        end
        return refreshed
    end

    function controller:RefreshType(viewerType, context)
        local pool = getIconPools(callbacks)[viewerType]
        if not pool then return 0 end

        local refreshed = 0
        local measure = ns.MemAuditProfilerMeasure
        for _, icon in ipairs(pool) do
            if callbacks.refreshTypeIcon then
                if measure then
                    measure("CDM_walkTypeIcon", callbacks.refreshTypeIcon, icon, context)
                else
                    callbacks.refreshTypeIcon(icon, context)
                end
                refreshed = refreshed + 1
            end
        end
        return refreshed
    end

    return controller
end
end

do
-- Inlined from cdm_icon_item_visual_policy.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Item Visual Policy
--
-- Private renderer policy used by CDMIcons. It owns item texture refreshes
-- and profession-quality overlays for item, trinket, and slot icons.
---------------------------------------------------------------------------

local CDMIconItemVisualPolicy = {}
ns.CDMIconItemVisualPolicy = CDMIconItemVisualPolicy

local PROFESSION_QUALITY_DRAW_LAYER = "ARTWORK"
local PROFESSION_QUALITY_DRAW_SUBLEVEL = 1

local function isItemBackedEntry(entry)
    local entryType = entry and entry.type
    return entryType == "item" or entryType == "trinket" or entryType == "slot"
end

function CDMIconItemVisualPolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}

    local function getTradeSkillUI()
        if callbacks.getTradeSkillUI then
            return callbacks.getTradeSkillUI()
        end
        return C_TradeSkillUI
    end

    local function getNCDM()
        return callbacks.getNCDM and callbacks.getNCDM() or nil
    end

    local function getUseAtlasSize()
        if callbacks.getUseAtlasSize then
            return callbacks.getUseAtlasSize()
        end
        return (TextureKitConstants and TextureKitConstants.UseAtlasSize) or true
    end

    local function resolveBestOwnedItemVariant(itemID)
        if callbacks.resolveBestOwnedItemVariant then
            return callbacks.resolveBestOwnedItemVariant(itemID)
        end
        return itemID
    end

    local function getProfessionQualityInfoForItem(itemIDOrLink)
        local tradeSkillUI = getTradeSkillUI()
        if not itemIDOrLink or not tradeSkillUI then return nil end
        if tradeSkillUI.GetItemReagentQualityInfo then
            local info = tradeSkillUI.GetItemReagentQualityInfo(itemIDOrLink)
            if info then return info end
        end
        if tradeSkillUI.GetItemCraftedQualityInfo then
            return tradeSkillUI.GetItemCraftedQualityInfo(itemIDOrLink)
        end
        return nil
    end

    local function getProfessionQualityParent(icon)
        if icon and icon.TextOverlay and icon.TextOverlay.CreateTexture then
            return icon.TextOverlay
        end
        return icon
    end

    function controller:GetItemTexture(itemID)
        if not itemID then return nil end
        local texture = callbacks.queryItemIconByID and callbacks.queryItemIconByID(itemID)
        if not texture and callbacks.queryItemInfoInstant then
            local _, _, _, _, instantTexture = callbacks.queryItemInfoInstant(itemID)
            texture = instantTexture
        end
        return texture
    end

    function controller:ClearProfessionQuality(icon)
        if icon and icon._professionQualityOverlay then
            icon._professionQualityOverlay:Hide()
        end
    end

    function controller:UpdateProfessionQuality(icon)
        if not (icon and icon._spellEntry) then
            controller:ClearProfessionQuality(icon)
            return
        end

        local entry = icon._spellEntry
        local entryType = entry.type
        if not isItemBackedEntry(entry) then
            controller:ClearProfessionQuality(icon)
            return
        end

        local ncdm = getNCDM()
        local viewerType = entry.viewerType
        local containerDB = ncdm and viewerType
            and (ncdm[viewerType] or (ncdm.containers and ncdm.containers[viewerType]))
        if containerDB and containerDB.showProfessionQuality == false then
            controller:ClearProfessionQuality(icon)
            return
        end

        local lookupID
        if entryType == "item" then
            lookupID = resolveBestOwnedItemVariant(entry.id)
        else
            if callbacks.queryInventoryItemLink then
                lookupID = callbacks.queryInventoryItemLink("player", entry.id)
            end
            if not lookupID and callbacks.queryInventoryItemID then
                lookupID = callbacks.queryInventoryItemID("player", entry.id)
            end
        end

        local qualityInfo = lookupID and getProfessionQualityInfoForItem(lookupID)
        local atlas = qualityInfo and qualityInfo.iconInventory
        if not atlas then
            controller:ClearProfessionQuality(icon)
            return
        end

        local overlayParent = getProfessionQualityParent(icon)
        if not (overlayParent and overlayParent.CreateTexture) then
            controller:ClearProfessionQuality(icon)
            return
        end

        local overlay = icon._professionQualityOverlay
        if overlay and overlay.GetParent and overlay:GetParent() ~= overlayParent then
            overlay:Hide()
            overlay = nil
            icon._professionQualityOverlay = nil
        end
        if not overlay then
            overlay = overlayParent:CreateTexture(
                nil, PROFESSION_QUALITY_DRAW_LAYER, nil, PROFESSION_QUALITY_DRAW_SUBLEVEL)
            overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 2)
            icon._professionQualityOverlay = overlay
        end
        if overlay.SetDrawLayer then
            overlay:SetDrawLayer(PROFESSION_QUALITY_DRAW_LAYER, PROFESSION_QUALITY_DRAW_SUBLEVEL)
        end
        overlay:SetAtlas(atlas, getUseAtlasSize())
        overlay:Show()
    end

    function controller:RefreshInventoryItemVisuals(icon, entry, itemID)
        if not (icon and entry and itemID and icon.Icon) then return false end
        local texture = controller:GetItemTexture(itemID)
        if texture and texture ~= icon._lastTexture then
            icon.Icon:SetTexture(texture)
            icon._lastTexture = texture
            controller:UpdateProfessionQuality(icon)
            return true
        end
        return false
    end

    function controller:RefreshItemVisuals(icon, entry, itemID)
        if not (icon and entry and itemID) then return false end

        local changed = false
        if icon._lastItemVisualItemID ~= itemID then
            icon._lastItemVisualItemID = itemID
            changed = true
        end

        if icon.Icon then
            local texture = controller:GetItemTexture(itemID)
            if texture and texture ~= icon._lastTexture then
                icon.Icon:SetTexture(texture)
                icon._lastTexture = texture
                changed = true
            end
        end

        if changed then
            entry.itemID = itemID
            controller:UpdateProfessionQuality(icon)
            if callbacks.updateSecureAttributes then
                callbacks.updateSecureAttributes(icon, entry, entry.viewerType)
            end
        end

        return changed
    end

    return controller
end
end

do
-- Inlined from cdm_icon_visibility_policy.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Visibility Policy
--
-- Private controller used by CDMIcons. It owns container-level visibility
-- filters, dynamic-layout dirty tracking, and show/hide/alpha application.
---------------------------------------------------------------------------

local CDMIconVisibilityPolicy = {}
ns.CDMIconVisibilityPolicy = CDMIconVisibilityPolicy

local ipairs = ipairs
local next = next
local pairs = pairs
local type = type
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local DRAIN_MAX_ROUNDS = 3

function CDMIconVisibilityPolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        layoutNeedsRefresh = {},
        buffIconLayoutRefreshPending = false,
        drainingLayoutDirty = false,
    }

    function controller:ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
        if not containerDB then return false end

        if callbacks.isCustomBarContainer and callbacks.isCustomBarContainer(containerDB) then
            local visibility = callbacks.computeCustomBarVisibility
                and callbacks.computeCustomBarVisibility(icon, entry, containerDB)
                or nil
            return not (visibility and visibility.layoutVisible)
        end

        local cooldownState = callbacks.resolveCooldownActivityState
            and callbacks.resolveCooldownActivityState(icon, entry, containerDB)
            or {}
        local effectiveOnCD = cooldownState.isOnCooldown or cooldownState.rechargeActive

        if containerDB.showOnlyInCombat and not inCombat then
            return true
        end

        if containerDB.showOnlyOnCooldown and not effectiveOnCD then
            return true
        end

        if containerDB.showOnlyWhenOffCooldown and effectiveOnCD then
            return true
        end

        if containerDB.showOnlyWhenActive and not icon._auraActive then
            return true
        end

        if containerDB.hideNonUsable then
            if entry.type == "item" then
                local count = callbacks.queryItemCount
                    and callbacks.queryItemCount(entry.id, false, false, nil)
                    or nil
                if not count or count <= 0 then return true end
            elseif entry.type == "trinket" or entry.type == "slot" then
                local equippedItemID = callbacks.queryInventoryItemID
                    and callbacks.queryInventoryItemID("player", entry.id)
                    or nil
                if not equippedItemID then return true end
                if entry.id == 13 or entry.id == 14 then
                    local spellName = callbacks.queryItemSpell
                        and callbacks.queryItemSpell(equippedItemID)
                        or nil
                    if not spellName then return true end
                end
            else
                local sid = icon._runtimeSpellID or entry.spellID or entry.id
                if sid then
                    local known = callbacks.isSpellKnown and callbacks.isSpellKnown(sid)
                    if known == false then
                        return true
                    end
                    if callbacks.querySpellUsable then
                        local usable = callbacks.querySpellUsable(sid)
                        if type(usable) == "boolean" and usable == false then return true end
                    end
                end
            end
        end

        return false
    end

    function controller:ShouldPlaceLayoutIcon(icon, entry, containerDB, inCombat)
        if not icon or not entry then return true end
        local filterHides = controller:ComputeFilterHides(
            icon, entry, containerDB, inCombat, icon._hasCooldownActive or false)
        if callbacks.debugLayoutFilter then
            callbacks.debugLayoutFilter(icon, filterHides, containerDB, icon._hasCooldownActive or false)
        end
        icon._lastLayoutFilterHidden = filterHides and true or false
        return not filterHides
    end

    function controller:WakeBuffIconContainer()
        if callbacks.isHiddenByAnchor and callbacks.isHiddenByAnchor("buffIcon") then
            return
        end

        local container = callbacks.getContainer and callbacks.getContainer("buff")
        if container and container.Show then
            container:Show()
        end
    end

    function controller:RequestBuffIconLayoutRefresh()
        controller:WakeBuffIconContainer()
        if controller.buffIconLayoutRefreshPending then return end
        controller.buffIconLayoutRefreshPending = true
        local schedule = callbacks.scheduleAfter
        if not schedule then return end
        schedule(0, function()
            controller.buffIconLayoutRefreshPending = false
            controller:WakeBuffIconContainer()
            if callbacks.onBuffLayoutReady then
                callbacks.onBuffLayoutReady()
            end
        end)
    end

    function controller:MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
        if not (entry and entry.viewerType) then return end
        if not containerDB or containerDB.dynamicLayout == false then return end
        local previously = icon._lastLayoutFilterHidden
        if previously == nil then return end
        if filterHidesNow ~= previously then
            controller.layoutNeedsRefresh[entry.viewerType] = true
        end
    end

    function controller:DrainLayoutDirty()
        if controller.drainingLayoutDirty then return end
        if next(controller.layoutNeedsRefresh) == nil then return end
        controller.drainingLayoutDirty = true
        if not callbacks.forceLayoutContainer then
            wipe(controller.layoutNeedsRefresh)
            controller.drainingLayoutDirty = false
            return
        end

        local toProcess = {}
        for _ = 1, DRAIN_MAX_ROUNDS do
            if next(controller.layoutNeedsRefresh) == nil then break end
            wipe(toProcess)
            for trackerKey in pairs(controller.layoutNeedsRefresh) do
                toProcess[#toProcess + 1] = trackerKey
            end
            wipe(controller.layoutNeedsRefresh)
            for _, trackerKey in ipairs(toProcess) do
                callbacks.forceLayoutContainer(trackerKey)
            end
        end
        wipe(controller.layoutNeedsRefresh)
        controller.drainingLayoutDirty = false
    end

    local function getIconRowOpacity(icon)
        local opacity = icon and icon._rowOpacity
        if opacity == nil then
            return 1
        end
        return opacity
    end

    local function setIconRowAlpha(icon, multiplier)
        if not icon then return end
        icon:SetAlpha(getIconRowOpacity(icon) * (multiplier or 1))
    end

    function controller:ApplyIconVisibility(icon, shouldShow, dynamicLayout)
        if dynamicLayout == false then
            if not icon:IsShown() then icon:Show() end
            icon:SetAlpha(shouldShow and getIconRowOpacity(icon) or 0)
        else
            if shouldShow then
                if not icon:IsShown() then icon:Show() end
                setIconRowAlpha(icon)
            else
                if icon:IsShown() then icon:Hide() end
            end
        end
    end

    return controller
end
end

do
-- Inlined from cdm_icon_range_policy.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Range Policy
--
-- Private controller used by CDMIcons. It owns spell range registration,
-- range/usability tint caches, and event-targeted visual refresh.
---------------------------------------------------------------------------

local CDMIconRangePolicy = {}
ns.CDMIconRangePolicy = CDMIconRangePolicy

local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local type = type
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local issecretvalue = issecretvalue or function() return false end

local function normalizeSpellIdentifier(value)
    if value == nil then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return value
    end
    return nil
end

local function spellIdentifiersMatch(a, b)
    a = normalizeSpellIdentifier(a)
    b = normalizeSpellIdentifier(b)
    if a == nil or b == nil then return false end
    return a == b or tostring(a) == tostring(b)
end

function CDMIconRangePolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        rangeCycleCache = {},
        hasRangeCycleCache = {},
        usableCycleCache = {},
        enabledRangeSpellChecks = {},
        desiredRangeSpellChecks = {},
        stackTextWritesForBatch = false,
    }

    local function getRangeUnit()
        if UnitExists("target") then return "target" end
        if UnitExists("softenemy") then return "softenemy" end
        return nil
    end

    local function queryReadableSpellInRange(spellID, unit)
        if not spellID or not unit or not callbacks.querySpellInRange then return nil end
        local inRange = callbacks.querySpellInRange(spellID, unit)
        if inRange == false then return false end
        if inRange == true then return true end
        return nil
    end

    local function queryReadableSpellUsable(spellID)
        if not spellID or not callbacks.querySpellUsable then return true, false end
        local usable, noMana = callbacks.querySpellUsable(spellID)
        local noManaBool = type(noMana) == "boolean" and noMana or false
        if type(usable) == "boolean" and usable == false then return false, noManaBool end
        if type(usable) == "boolean" and usable == true then return true, noManaBool end
        return true, noManaBool
    end

    function controller:SetStackTextWritesForBatch(enabled)
        controller.stackTextWritesForBatch = enabled == true
    end

    function controller:ShouldAllowStackTextWrites()
        return controller.stackTextWritesForBatch == true
    end

    function controller:GetIconRangeSpellID(icon, entry)
        entry = entry or (icon and icon._spellEntry)
        if not entry then return nil end
        return normalizeSpellIdentifier(icon and icon._runtimeSpellID or entry.spellID or entry.id)
    end

    local function resetIconVisuals(icon)
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon._rangeTinted = nil
        icon._usabilityTinted = nil
    end

    local function updateIconVisualState(icon, cachedDB, rangeEventSpellID, rangeEventInRange, rangeEventChecksRange)
        if not icon or not icon._spellEntry then return end
        local entry = icon._spellEntry
        local viewerType = entry.viewerType
        if not viewerType then return end

        local settings = callbacks.resolveSettings
            and callbacks.resolveSettings(viewerType, cachedDB)
            or nil
        if not settings then
            if icon._rangeTinted or icon._usabilityTinted then
                icon._lastVisualState = nil
                resetIconVisuals(icon)
            end
            return
        end

        local rangeEnabled = settings.rangeIndicator
        local usabilityEnabled = settings.usabilityIndicator

        if not rangeEnabled and not usabilityEnabled then
            if icon._rangeTinted or icon._usabilityTinted then
                icon._lastVisualState = nil
                resetIconVisuals(icon)
            end
            return
        end

        if viewerType == "buff" then return end
        if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then return end

        local spellID = controller:GetIconRangeSpellID(icon, entry)
        if not spellID then return end

        local newVisualState = "normal"
        local cooldownVisualPriority = false

        local rangeUnit = rangeEnabled and getRangeUnit() or nil
        if rangeUnit then
            local hasRange
            local inRange
            if rangeEventSpellID ~= nil then
                hasRange = rangeEventChecksRange == true
                inRange = hasRange and (rangeEventInRange == true) or nil
            else
                hasRange = controller.hasRangeCycleCache[spellID]
                if hasRange == nil then
                    hasRange = callbacks.querySpellHasRange and callbacks.querySpellHasRange(spellID)
                    if type(hasRange) ~= "boolean" then
                        hasRange = nil
                    end
                    if hasRange == nil then hasRange = true end
                    controller.hasRangeCycleCache[spellID] = hasRange and true or false
                end
                if hasRange then
                    local cached = controller.rangeCycleCache[spellID]
                    if cached ~= nil then
                        inRange = cached ~= "nil" and cached or nil
                    else
                        inRange = queryReadableSpellInRange(spellID, rangeUnit)
                        controller.rangeCycleCache[spellID] = inRange == nil and "nil" or inRange
                    end
                end
            end
            if hasRange and inRange == false then
                newVisualState = "oor"
            end
        end

        if newVisualState == "normal" then
            cooldownVisualPriority = callbacks.cooldownHasVisualPriority
                and callbacks.cooldownHasVisualPriority(icon, entry, settings)
                or false
            if cooldownVisualPriority and icon._usabilityTinted then
                icon.Icon:SetVertexColor(1, 1, 1, 1)
                icon._usabilityTinted = nil
                icon._lastVisualState = nil
            end
        end

        if newVisualState == "normal" and usabilityEnabled and not cooldownVisualPriority then
            local isUsable = controller.usableCycleCache[spellID]
            if isUsable == nil then
                isUsable = queryReadableSpellUsable(spellID)
                controller.usableCycleCache[spellID] = isUsable
            end
            if not isUsable then
                local chargeState = callbacks.resolveCooldownActivityState
                    and callbacks.resolveCooldownActivityState(icon, entry, settings)
                    or {}
                if chargeState.hasCharges and chargeState.isOnCooldown ~= true then
                    isUsable = true
                end
            end
            if not isUsable then
                newVisualState = "unusable"
            end
        end

        if icon._lastVisualState == newVisualState then
            if newVisualState == "unusable"
               and not icon._usabilityTinted
               and not cooldownVisualPriority then
                icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
                icon._usabilityTinted = true
            end
            return
        end
        icon._lastVisualState = newVisualState

        if newVisualState == "oor" then
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

        if icon._rangeTinted then
            icon.Icon:SetVertexColor(1, 1, 1, 1)
            icon._rangeTinted = nil
        end

        if newVisualState == "unusable" then
            icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
            icon._usabilityTinted = true
            return
        end

        if icon._usabilityTinted then
            icon.Icon:SetVertexColor(1, 1, 1, 1)
            icon._usabilityTinted = nil
        end
    end

    function controller:IconNeedsUsabilityVisualRefresh(icon, cachedDB)
        local entry = icon and icon._spellEntry
        if not entry then return false end
        if callbacks.isAuraEntry and callbacks.isAuraEntry(entry) then return false end
        if entry.kind == "aura" or entry.kind == "auraBar" then return false end
        if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then return false end

        if icon._rangeTinted or icon._usabilityTinted then
            return true
        end

        local viewerType = entry.viewerType
        if not viewerType or viewerType == "buff" then return false end

        local settings = callbacks.resolveSettings
            and callbacks.resolveSettings(viewerType, cachedDB)
            or nil
        return settings and settings.usabilityIndicator or false
    end

    local function resetCycleCaches()
        wipe(controller.rangeCycleCache)
        wipe(controller.hasRangeCycleCache)
        wipe(controller.usableCycleCache)
    end

    function controller:UpdateIconRangesForUsabilityEvent(iconPools)
        resetCycleCaches()
        local db = callbacks.getDB and callbacks.getDB() or nil
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                if controller:IconNeedsUsabilityVisualRefresh(icon, db) then
                    updateIconVisualState(icon, db)
                end
            end
        end
    end

    function controller:UpdateAllIconRanges(iconPools)
        resetCycleCaches()
        local db = callbacks.getDB and callbacks.getDB() or nil
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                updateIconVisualState(icon, db)
            end
        end
    end

    function controller:SyncSpellRangeChecks(iconPools)
        wipe(controller.desiredRangeSpellChecks)
        local db = callbacks.getDB and callbacks.getDB() or nil

        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and entry.viewerType and entry.viewerType ~= "buff"
                    and entry.type ~= "item" and entry.type ~= "trinket" and entry.type ~= "slot" then
                    local settings = callbacks.resolveSettings
                        and callbacks.resolveSettings(entry.viewerType, db)
                        or nil
                    if settings and settings.rangeIndicator then
                        local spellID = controller:GetIconRangeSpellID(icon, entry)
                        if spellID then
                            controller.desiredRangeSpellChecks[spellID] = true
                        end
                    end
                end
            end
        end

        if not callbacks.enableSpellRangeCheck then
            wipe(controller.enabledRangeSpellChecks)
            return
        end

        for spellID in pairs(controller.enabledRangeSpellChecks) do
            if not controller.desiredRangeSpellChecks[spellID] then
                callbacks.enableSpellRangeCheck(spellID, false)
                controller.enabledRangeSpellChecks[spellID] = nil
            end
        end

        for spellID in pairs(controller.desiredRangeSpellChecks) do
            if not controller.enabledRangeSpellChecks[spellID] then
                if callbacks.enableSpellRangeCheck(spellID, true) then
                    controller.enabledRangeSpellChecks[spellID] = true
                end
            end
        end
    end

    function controller:DisableSpellRangeChecks()
        if callbacks.enableSpellRangeCheck then
            for spellID in pairs(controller.enabledRangeSpellChecks) do
                callbacks.enableSpellRangeCheck(spellID, false)
            end
        end
        wipe(controller.enabledRangeSpellChecks)
        wipe(controller.desiredRangeSpellChecks)
    end

    function controller:UpdateIconsForSpellRangeEvent(iconPools, spellIdentifier, isInRange, checksRange)
        local eventSpellID = normalizeSpellIdentifier(spellIdentifier)
        if not eventSpellID then return end

        local db = callbacks.getDB and callbacks.getDB() or nil
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and spellIdentifiersMatch(eventSpellID, controller:GetIconRangeSpellID(icon, entry)) then
                    local settings = callbacks.resolveSettings
                        and callbacks.resolveSettings(entry.viewerType, db)
                        or nil
                    if settings and settings.rangeIndicator and checksRange == true and isInRange == false
                        and icon.Icon and icon.Icon.SetVertexColor then
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
                        icon._lastVisualState = "oor"
                    else
                        updateIconVisualState(icon, db, eventSpellID, isInRange == true, checksRange == true)
                    end
                end
            end
        end
    end

    return controller
end
end

do
-- Inlined from cdm_icon_cooldown_policy.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Cooldown Policy
--
-- Private controller used by CDMIcons. It owns icon-local GCD swipe flags,
-- trusted GCD capture, mirror state lookup, and mirror charge-cycle memory.
---------------------------------------------------------------------------

local CDMIconCooldownPolicy = {}
ns.CDMIconCooldownPolicy = CDMIconCooldownPolicy

local ipairs = ipairs
local pairs = pairs
local type = type
local issecretvalue = issecretvalue

function CDMIconCooldownPolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}
    local hasQueryCooldown = type(callbacks.queryCooldown) == "function"

    local function QueryOverrideSpell(spellID)
        return callbacks.queryOverrideSpell and callbacks.queryOverrideSpell(spellID) or nil
    end

    local function QueryCooldown(spellID, owner)
        return callbacks.queryCooldown and callbacks.queryCooldown(spellID, owner) or nil
    end

    local function SafeBoolean(value)
        if issecretvalue and issecretvalue(value) then return nil end
        if value == true then return true end
        if value == false then return false end
        return nil
    end

    local function SafeString(value)
        if issecretvalue and issecretvalue(value) then return nil end
        if type(value) == "string" then return value end
        return nil
    end

    local function ValueIsPresent(value)
        if issecretvalue and issecretvalue(value) then return true end
        return value ~= nil
    end

    local UNKNOWN_GCD_STATE = {}

    local function AddIconCooldownIdentifier(candidates, seen, spellID)
        if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
            return
        end
        local sidType = type(spellID)
        if sidType ~= "number" and sidType ~= "string" then
            return
        end
        if seen[spellID] then
            return
        end
        seen[spellID] = true
        candidates[#candidates + 1] = spellID
    end

    local function GetIconCooldownIdentifiers(icon)
        local entry = icon and icon._spellEntry
        if not entry then return nil end

        local candidates = {}
        local seen = {}
        local base = entry.spellID or entry.id
        AddIconCooldownIdentifier(candidates, seen, base)
        AddIconCooldownIdentifier(candidates, seen, entry.overrideSpellID)
        if base then
            local overrideID = QueryOverrideSpell(base)
            AddIconCooldownIdentifier(candidates, seen, overrideID)
        end
        if #candidates == 0 then
            return nil
        end
        return candidates
    end

    local function ReadCachedTrustedGCD(spellState, spellID)
        if not spellState then return nil, false end
        local cached = spellState[spellID]
        if type(cached) == "boolean" then
            return cached, true
        end
        if cached == UNKNOWN_GCD_STATE then
            return nil, true
        end
        return nil, false
    end

    function controller:MarkGCDSwipe(icon)
        if not icon then return end
        icon._showingGCDSwipe = true
        icon._showingRealCooldownSwipe = nil
    end

    function controller:ClearGCDSwipe(icon)
        if not icon then return end
        icon._showingGCDSwipe = nil
    end

    function controller:GetIconMirrorState(icon)
        if not (icon and icon._blizzMirrorCooldownID) then
            return nil
        end
        if callbacks.getCachedMirrorStateForIcon then
            local state = callbacks.getCachedMirrorStateForIcon(icon)
            if state then return state end
        end
        if callbacks.refreshCachedMirrorStateForIcon then
            local state = callbacks.refreshCachedMirrorStateForIcon(icon)
            if state then return state end
        end
        local mirror = callbacks.getMirror and callbacks.getMirror() or nil
        if not (mirror and mirror.GetStateByCooldownID) then return nil end
        return mirror.GetStateByCooldownID(icon._blizzMirrorCooldownID, icon._blizzMirrorCategory)
    end

    function controller:MirrorStateIsActive(state)
        if not state then return false end
        if SafeBoolean(state.childIsActive) == true then return true end
        if state.auraInstanceID then return true end
        if state.totemSlot or state.auraDurObj or state.totemDurObj then return true end
        return false
    end

    function controller:ClearIconChargeMirrorCycle(icon)
        if not icon then return end
        icon._lastChargeMirrorCooldownID = nil
        icon._lastChargeMirrorCategory = nil
        icon._lastChargeRuntimeSpellID = nil
    end

    function controller:RememberIconChargeMirrorCycle(icon, runtimeSpellID)
        if not (icon and icon._blizzMirrorCooldownID) then return end
        icon._lastChargeMirrorCooldownID = icon._blizzMirrorCooldownID
        icon._lastChargeMirrorCategory = icon._blizzMirrorCategory
        icon._lastChargeRuntimeSpellID = runtimeSpellID
    end

    function controller:UpdateIconChargeMirrorCycle(icon, mode, runtimeSpellID, hasCharges)
        if not icon then return end
        -- Resolver no longer emits mode=="charge"; charge spells now flow as
        -- mode=="cooldown" with the recharge timer in state.durObj. The
        -- "is a charge spell" signal is the entry-level hasCharges flag,
        -- threaded from the call site.
        if mode == "cooldown" and hasCharges == true then
            controller:RememberIconChargeMirrorCycle(icon, runtimeSpellID)
        elseif mode == "inactive"
            and not controller:MirrorStateIsActive(controller:GetIconMirrorState(icon)) then
            controller:ClearIconChargeMirrorCycle(icon)
        end
    end

    function controller:MirrorPayloadHasChargeState(mirrorPayload)
        if not mirrorPayload then return false end
        local state = mirrorPayload.state
        if not state then return false end
        if SafeBoolean(state.charges) == true
            or SafeBoolean(state.cooldownChargesShown) == true
            or SafeBoolean(state.chargeCountFrameShown) == true then
            return true
        end
        return SafeString(state.stackTextSource) == "ChargeCount"
            and SafeBoolean(state.stackTextShown) ~= false
    end

    function controller:MirrorPayloadMatchesRecentChargeCycle(icon, mirrorPayload)
        if not (icon and mirrorPayload and icon._lastChargeMirrorCooldownID) then
            return false
        end
        if mirrorPayload.active ~= true then return false end
        local state = mirrorPayload.state
        if not state then return false end
        local cooldownID = mirrorPayload.cooldownID or state.cooldownID or icon._blizzMirrorCooldownID
        if issecretvalue and issecretvalue(cooldownID) then
            return false
        end
        if cooldownID ~= icon._lastChargeMirrorCooldownID then
            return false
        end
        local category = mirrorPayload.category or state.viewerCategory or icon._blizzMirrorCategory
        if issecretvalue and issecretvalue(category) then
            return false
        end
        return icon._lastChargeMirrorCategory == nil or category == icon._lastChargeMirrorCategory
    end

    function controller:CaptureTrustedGCDStateForIcon(icon, spellState, stamp)
        if not icon or not icon._spellEntry then return false end

        local candidates = GetIconCooldownIdentifiers(icon)
        local prev = icon._isOnGCD

        if not candidates or not hasQueryCooldown then
            if prev ~= nil then
                icon._isOnGCD = nil
                icon._isOnGCDTrustedAt = nil
                return true
            end
            icon._isOnGCD = nil
            icon._isOnGCDTrustedAt = nil
            return false
        end

        local trusted
        local sawTrusted = false
        for _, sid in ipairs(candidates) do
            local candidateTrusted, cached = ReadCachedTrustedGCD(spellState, sid)
            if not cached then
                local cdInfo = QueryCooldown(sid, icon)
                local onGCD = cdInfo and cdInfo.isOnGCD
                if type(onGCD) == "boolean" then
                    candidateTrusted = onGCD
                    if spellState then
                        spellState[sid] = onGCD
                    end
                elseif spellState then
                    spellState[sid] = UNKNOWN_GCD_STATE
                end
            end
            if type(candidateTrusted) == "boolean" then
                sawTrusted = true
                if candidateTrusted == true then
                    trusted = true
                elseif trusted ~= true then
                    trusted = false
                end
            end
        end

        if sawTrusted then
            icon._isOnGCD = trusted
            icon._isOnGCDTrustedAt = stamp
            return prev ~= trusted
        end

        icon._isOnGCD = nil
        icon._isOnGCDTrustedAt = nil
        return prev ~= nil
    end

    function controller:CaptureTrustedGCDState(iconPools, spellState, stamp)
        if not hasQueryCooldown then
            return false
        end

        local anyChanged = false
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                if controller:CaptureTrustedGCDStateForIcon(icon, spellState, stamp) then
                    anyChanged = true
                end
            end
        end
        return anyChanged
    end

    return controller
end
end

do
-- Inlined from cdm_icon_custom_bar_policy.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Custom-Bar Policy
--
-- Private controller used by CDMIcons. It owns custom-bar active-state
-- adaptation, usability filtering, visibility decisions, recharge swipe
-- styling, and active glow lifecycle.
---------------------------------------------------------------------------

local CDMIconCustomBarPolicy = {}
ns.CDMIconCustomBarPolicy = CDMIconCustomBarPolicy

local math = math
local type = type

function CDMIconCustomBarPolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}

    local function Sources()
        return callbacks.getSources and callbacks.getSources() or ns.CDMSources
    end

    local function SpellData()
        return callbacks.getSpellData and callbacks.getSpellData() or ns.CDMSpellData
    end

    local function GlowLib()
        return callbacks.getGlowLib and callbacks.getGlowLib() or nil
    end

    local function GetTimeNow()
        if callbacks.getTime then
            return callbacks.getTime()
        end
        return GetTime and GetTime() or 0
    end

    local function GetTrackerSettings(viewerType)
        return callbacks.getTrackerSettings and callbacks.getTrackerSettings(viewerType) or nil
    end

    local function IsCustomBarContainer(containerDB)
        return callbacks.isCustomBarContainer
            and callbacks.isCustomBarContainer(containerDB)
            or false
    end

    local function GetVisibilityMode(containerDB)
        if callbacks.getCustomBarVisibilityMode then
            return callbacks.getCustomBarVisibilityMode(containerDB)
        end
        return "always"
    end

    local function ResolveMacro(entry)
        if callbacks.resolveMacro then
            return callbacks.resolveMacro(entry)
        end
        return nil
    end

    local function ResolveSpellActiveState(spellID, icon, entry)
        if callbacks.resolveSpellActiveState then
            return callbacks.resolveSpellActiveState(spellID, icon, entry)
        end
        return false
    end

    local function ResolveCooldownActivityState(icon, entry, containerDB, now)
        local resolver = callbacks.resolveCooldownActivityState
        if not resolver then return nil end
        return resolver(icon, entry, containerDB, now)
    end

    local function ReapplySwipeStyle(cooldown, icon)
        if callbacks.reapplySwipeStyle then
            callbacks.reapplySwipeStyle(cooldown, icon)
        end
    end

    local function IsPlayerInCombat()
        if callbacks.isPlayerInCombat then
            return callbacks.isPlayerInCombat()
        end
        return UnitAffectingCombat and UnitAffectingCombat("player") or false
    end

    local function DebugIconEvent(...)
        if callbacks.debugIconEvent then
            callbacks.debugIconEvent(...)
        end
    end

    local function After(delay, callback)
        if callbacks.after then
            return callbacks.after(delay, callback)
        end
        if C_Timer and C_Timer.After then
            return C_Timer.After(delay, callback)
        end
        callback()
    end

    local function IsItemLikeEntry(entry)
        return entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
    end

    local function IsReadableNumber(value)
        if issecretvalue and issecretvalue(value) then return false end
        return type(value) == "number"
    end

    local function ResolveEntryItemID(entry)
        if not entry then return nil end
        if entry.type == "item" then
            local sources = Sources()
            if sources and sources.QueryBestOwnedItemVariant then
                return sources.QueryBestOwnedItemVariant(entry.id) or entry.id
            end
            return entry.id
        elseif entry.type == "trinket" or entry.type == "slot" then
            local sources = Sources()
            return sources and sources.QueryInventoryItemID
                and sources.QueryInventoryItemID("player", entry.id)
                or nil
        end
        return nil
    end

    function controller:ResolveItemActiveState(itemID, icon, entry)
        local sources = Sources()
        if not itemID then return false end
        local itemSpellID
        if sources and sources.QueryItemSpell then
            local _, spellID = sources.QueryItemSpell(itemID)
            itemSpellID = spellID
        end
        if sources and sources.QueryScannedItemAuraInfo then
            local scanned = sources.QueryScannedItemAuraInfo(itemID, itemSpellID)
            if scanned and scanned.active == true then
                local expiration = scanned.expiration
                local duration = scanned.duration
                if IsReadableNumber(expiration) and IsReadableNumber(duration) then
                    return true, expiration - duration, duration, "buff"
                end
                return true, nil, nil, "buff"
            end
        end
        if itemSpellID then
            return ResolveSpellActiveState(itemSpellID, icon, entry)
        end
        return false
    end

    function controller:CooldownHasVisualPriority(icon, entry, containerDB, now)
        if not icon or not entry then return false end
        if icon._cdDesaturated or icon._hasCooldownActive or icon._showingRealCooldownSwipe then
            return true
        end

        local state = ResolveCooldownActivityState(icon, entry, containerDB, now or GetTimeNow())
        return state and state.isOnCooldown == true
    end

    function controller:ResolveActiveState(entry, icon, now)
        local containerDB = GetTrackerSettings(entry and entry.viewerType)
        if not IsCustomBarContainer(containerDB) then
            return icon and icon._auraActive or false
        end
        if containerDB.showActiveState == false then
            return false
        end

        if entry.type == "macro" then
            local resolvedID, resolvedType = ResolveMacro(entry)
            if resolvedID then
                if resolvedType == "item" then
                    return controller:ResolveItemActiveState(resolvedID, icon, entry)
                end
                return ResolveSpellActiveState(resolvedID, icon, entry)
            end
            return false
        end

        if IsItemLikeEntry(entry) then
            local itemID = ResolveEntryItemID(entry)
            if itemID then
                return controller:ResolveItemActiveState(itemID, icon, entry)
            end
            return false
        end

        local spellID = icon and icon._runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id
        return ResolveSpellActiveState(spellID, icon, entry)
    end

    function controller:ResolveCooldownState(entry, icon, containerDB, now)
        return ResolveCooldownActivityState(icon, entry, containerDB, now)
    end

    function controller:ResolveUsability(entry, containerDB, cooldownState)
        if not entry then return true end

        if entry.type == "macro" then
            local resolvedID, resolvedType = ResolveMacro(entry)
            if not resolvedID then return true end
            if resolvedType == "item" then
                return controller:ResolveUsability({ type = "item", id = resolvedID }, containerDB, cooldownState)
            end
            return controller:ResolveUsability({ type = "spell", id = resolvedID, spellID = resolvedID }, containerDB, cooldownState)
        end

        local sources = Sources()
        if entry.type == "item" then
            local itemID = ResolveEntryItemID(entry)
            if sources and sources.QueryItemInfoInstant and Enum and Enum.ItemClass then
                local instantItemID, instantItemType, instantItemSubType, instantEquipLoc, instantIcon, classID =
                    sources.QueryItemInfoInstant(itemID)
                if instantItemID and (classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon) then
                    local equipped = sources.QueryIsEquippedItem and sources.QueryIsEquippedItem(itemID)
                    if equipped ~= nil then
                        return equipped == true
                    end
                end
            end
            if sources and sources.QueryItemCount then
                local count = sources.QueryItemCount(itemID, false, containerDB and containerDB.showItemCharges == true, true)
                if issecretvalue and issecretvalue(count) then
                    return true
                end
                return count and count > 0
            end
            return true
        elseif entry.type == "trinket" or entry.type == "slot" then
            local equippedItemID = sources and sources.QueryInventoryItemID and sources.QueryInventoryItemID("player", entry.id)
            if not equippedItemID then return false end
            -- Trinket slots (13/14) track the slot rather than a specific item,
            -- so passive equipped items with no on-use spell should still fail
            -- custom-bar hideNonUsable checks.
            if entry.id == 13 or entry.id == 14 then
                local spellName = sources and sources.QueryItemSpell and sources.QueryItemSpell(equippedItemID)
                if not spellName then return false end
            end
            return true
        end

        local sid = entry.spellID or entry.overrideSpellID or entry.id
        if sid then
            local spellData = SpellData()
            if spellData and type(spellData.IsSpellKnown) == "function"
               and not spellData:IsSpellKnown(sid) then
                return false
            end
            -- Known spells remain usable for visibility while their cooldown
            -- or recharge is active, even when the live usability query says
            -- false during that cooldown window.
            if cooldownState and (cooldownState.isOnCooldown or cooldownState.rechargeActive) then
                return true
            end
            if sources and sources.QuerySpellUsable then
                local usable = sources.QuerySpellUsable(sid)
                if type(usable) == "boolean" and usable == false then return false end
            end
        end

        return true
    end

    function controller:ComputeVisibility(icon, entry, containerDB, now)
        local cooldown = controller:ResolveCooldownState(entry, icon, containerDB, now) or {}
        local isActive = (icon and icon._customBarActive) or (icon and icon._auraActive) or false
        local usable = controller:ResolveUsability(entry, containerDB, cooldown)
        local baseVisible = usable or not (containerDB and containerDB.hideNonUsable)
        local mode = GetVisibilityMode(containerDB)
        local layoutVisible = baseVisible

        if layoutVisible then
            if mode == "onCooldown" then
                layoutVisible = cooldown.isOnCooldown or cooldown.rechargeActive
            elseif mode == "active" then
                layoutVisible = isActive
            elseif mode == "offCooldown" then
                layoutVisible = (not cooldown.isOnCooldown)
                    and (not isActive or cooldown.hasChargesRemaining)
            end
        end

        local combatVisible = not (containerDB and containerDB.showOnlyInCombat) or IsPlayerInCombat()

        if _G.QUI_CDM_ICON_DEBUG then
            DebugIconEvent(icon, "visibility",
                "mode=", mode,
                "layout=", tostring((layoutVisible and true) or false),
                "render=", tostring(((layoutVisible and combatVisible) and true) or false),
                "base=", tostring((baseVisible and true) or false),
                "usable=", tostring((usable and true) or false),
                "onCD=", tostring((cooldown.isOnCooldown and true) or false),
                "recharge=", tostring((cooldown.rechargeActive and true) or false),
                "active=", tostring((isActive and true) or false),
                "gcdOnly=", tostring(cooldown.gcdOnly and true or false),
                "hideNonUsable=", tostring(containerDB and containerDB.hideNonUsable),
                "showOnlyOnCooldown=", tostring(containerDB and containerDB.showOnlyOnCooldown))
        end
        return {
            baseVisible = baseVisible,
            layoutVisible = layoutVisible and true or false,
            renderVisible = layoutVisible and combatVisible and true or false,
            isActive = isActive and true or false,
            isUsable = usable and true or false,
            isOnCooldown = cooldown.isOnCooldown and true or false,
            rechargeActive = cooldown.rechargeActive and true or false,
            hasChargesRemaining = cooldown.hasChargesRemaining and true or false,
            visibilityMode = mode,
        }
    end

    function controller:StartActiveGlow(icon, containerDB)
        local LCG = GlowLib()
        if not icon or not LCG or not containerDB or containerDB.activeGlowEnabled == false then return end
        if icon._customBarActiveGlowShown or icon._customBarActiveGlowPending then return end
        local width, height = icon:GetSize()
        if not width or not height or width < 10 or height < 10 then return end

        local glowType = containerDB.activeGlowType or "Pixel Glow"
        local color = containerDB.activeGlowColor or {1, 0.85, 0.3, 1}
        local lines = containerDB.activeGlowLines or 8
        local frequency = containerDB.activeGlowFrequency or 0.25
        local thickness = containerDB.activeGlowThickness or 2
        local scale = containerDB.activeGlowScale or 1.0

        if glowType == "Proc Glow" then
            local duration = 1.0 / ((frequency or 0.25) * 4)
            duration = math.max(0.5, math.min(2.0, duration))
            if icon.Border and icon.Border.IsShown and icon.Border:IsShown() then
                icon._customBarBorderWasShown = true
                icon.Border:Hide()
            end
            if icon.Icon and icon.CreateMaskTexture then
                if not icon._customBarProcGlowMask then
                    icon._customBarProcGlowMask = icon:CreateMaskTexture()
                    icon._customBarProcGlowMask:SetTexture("Interface\\AddOns\\QUI\\assets\\iconskin\\ProcGlowMask")
                    icon._customBarProcGlowMask:SetAllPoints(icon.Icon)
                end
                icon.Icon.AddMaskTexture(icon.Icon, icon._customBarProcGlowMask)
            end
            icon._customBarActiveGlowPending = true
            After(0, function()
                icon._customBarActiveGlowPending = nil
                if not icon or not icon:IsShown() or icon._customBarActiveGlowShown or not icon._customBarActive then return end
                LCG.ProcGlow_Start(icon, {
                    color = color,
                    duration = duration,
                    startAnim = true,
                    key = "_QUIActiveGlow",
                })
                icon._customBarActiveGlowShown = true
                icon._customBarActiveGlowType = glowType
            end)
        elseif glowType == "Autocast Shine" then
            LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, "_QUIActiveGlow")
            icon._customBarActiveGlowShown = true
            icon._customBarActiveGlowType = glowType
        else
            LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, "_QUIActiveGlow")
            icon._customBarActiveGlowShown = true
            icon._customBarActiveGlowType = "Pixel Glow"
        end
    end

    function controller:StopActiveGlow(icon)
        local LCG = GlowLib()
        if not icon or not LCG then return end
        icon._customBarActiveGlowPending = nil
        local glowWasShown = icon._customBarActiveGlowShown

        local glowType = icon._customBarActiveGlowType or "Pixel Glow"
        if glowWasShown and glowType == "Proc Glow" then
            LCG.ProcGlow_Stop(icon, "_QUIActiveGlow")
        elseif glowWasShown and glowType == "Autocast Shine" then
            LCG.AutoCastGlow_Stop(icon, "_QUIActiveGlow")
        elseif glowWasShown then
            LCG.PixelGlow_Stop(icon, "_QUIActiveGlow")
        end
        if icon.Icon and icon._customBarProcGlowMask then
            icon.Icon.RemoveMaskTexture(icon.Icon, icon._customBarProcGlowMask)
        end
        if icon._customBarBorderWasShown and icon.Border then
            icon.Border:Show()
        end
        icon._customBarBorderWasShown = nil
        icon._customBarActiveGlowShown = nil
        icon._customBarActiveGlowType = nil
    end

    function controller:ApplySwipeStyle(icon, containerDB, cooldownState)
        if not icon or not icon.Cooldown or not icon._spellEntry then return end
        local entry = icon._spellEntry
        containerDB = containerDB or GetTrackerSettings(entry.viewerType)
        if not IsCustomBarContainer(containerDB) then return end

        cooldownState = cooldownState or controller:ResolveCooldownState(entry, icon, containerDB, GetTimeNow())
        local showRecharge = cooldownState and cooldownState.rechargeActive and containerDB.showRechargeSwipe == true
        if cooldownState and (cooldownState.hasCharges or cooldownState.rechargeActive) then
            icon.Cooldown:SetDrawSwipe(showRecharge)
            icon.Cooldown:SetDrawEdge(false)
            if showRecharge then
                icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
                icon.Cooldown:SetSwipeColor(0, 0, 0, 0.6)
            else
                icon.Cooldown:SetSwipeColor(0, 0, 0, 0)
            end
        elseif not icon._customBarActive then
            icon.Cooldown:SetDrawSwipe(false)
            icon.Cooldown:SetDrawEdge(false)
            icon.Cooldown:SetSwipeColor(0, 0, 0, 0)
        end
    end

    function controller:ApplyActiveState(icon, entry, containerDB)
        if not icon or not entry or not IsCustomBarContainer(containerDB) then return end

        local wasActive = icon._customBarActive
        local wasActiveType = icon._customBarActiveType
        local active, startTime, duration, activeType = controller:ResolveActiveState(entry, icon, GetTimeNow())
        icon._customBarActive = active and true or false
        icon._customBarActiveType = activeType
        icon._customBarActiveStart = startTime
        icon._customBarActiveDuration = duration

        if icon.Cooldown
           and (wasActive ~= icon._customBarActive or wasActiveType ~= icon._customBarActiveType) then
            ReapplySwipeStyle(icon.Cooldown, icon)
        end

        controller:ApplySwipeStyle(icon, containerDB)
    end

    function controller:ApplyActiveGlow(icon, containerDB, visibility)
        if visibility and visibility.renderVisible and visibility.isActive
           and visibility.visibilityMode ~= "onCooldown" then
            controller:StartActiveGlow(icon, containerDB)
        else
            controller:StopActiveGlow(icon)
        end
    end

    return controller
end
end

do
-- Inlined from cdm_icon_renderer.lua
--[[
    QUI CDM Icon Factory

    Creates and manages addon-owned icon frames for the CDM system.
    All icons are simple Frame objects (not Buttons) with no protected
    attributes, eliminating all combat taint concerns for frame operations.

    Absorbs cdm_custom.lua functionality — custom entries use the same
    icon pool as harvested entries.
]]

local _, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local LSM = ns.LSM
local Shared = ns.CDMShared

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMIcons = {}
ns.CDMIcons = CDMIcons
CDMIcons.ChargeDebug = function() end
CDMIcons.DebugStackText = function() end
CDMIcons.DebugSpellEvent = function() end
CDMIcons.DebugIconEvent = function() end
CDMIcons.DebugEntryBuild = function() end
CDMIcons.DebugLayoutFilter = function() end
CDMIcons.EventTracePrint = function() end
CDMIcons.EventTraceAuraInfo = function() return nil end

---------------------------------------------------------------------------
-- IMPORTS
---------------------------------------------------------------------------
local Resolvers = ns.CDMResolvers
local RuntimeQueries = ns.CDMRuntimeQueries
local Sources = ns.CDMSources
local QueryCharges = RuntimeQueries.QueryCharges
local QueryCooldown = RuntimeQueries.QueryCooldown
local QueryDuration = RuntimeQueries.QueryDuration
local QueryOverrideSpell = RuntimeQueries.QueryOverrideSpell
local QueryDisplayCount = RuntimeQueries.QueryDisplayCount
local QuerySpellCount = RuntimeQueries.QuerySpellCount
local _textureCycleCache = Resolvers._textureCycleCache
local GetSpellTexture = Resolvers.GetSpellTexture
local ResolveMacro = Resolvers.ResolveMacro
local GetEntryTexture = Resolvers.GetEntryTexture
local IsAuraEntry = Resolvers.IsAuraEntry
local ResolveAuraActiveState = Resolvers.ResolveAuraActiveState
local GetChargeMetadataDB = RuntimeQueries.GetChargeMetadataDB

local durationBindingStats = { keyBuilds = 0, keyCacheHits = 0, resolvedStateReuses = 0 }
local fullUpdateScheduleStats = {
    total = 0,
    request = 0,
    mirrorFallback = 0,
    runtime = 0,
    deferred = 0,
    hotfix = 0,
    other = 0,
}

do
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_durationBindingKeys", counter = true, fn = function() return durationBindingStats.keyBuilds end }
    mp[#mp + 1] = { name = "CDM_durationBindingKeyCacheHits", counter = true, fn = function() return durationBindingStats.keyCacheHits end }
    mp[#mp + 1] = { name = "CDM_applyResolvedStateReuses", counter = true, fn = function() return durationBindingStats.resolvedStateReuses end }
    mp[#mp + 1] = { name = "CDM_fullUpdateSchedules", counter = true, fn = function() return fullUpdateScheduleStats.total end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleRequest", counter = true, fn = function() return fullUpdateScheduleStats.request end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleMirrorFallback", counter = true, fn = function() return fullUpdateScheduleStats.mirrorFallback end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleRuntime", counter = true, fn = function() return fullUpdateScheduleStats.runtime end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleDeferred", counter = true, fn = function() return fullUpdateScheduleStats.deferred end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleHotfix", counter = true, fn = function() return fullUpdateScheduleStats.hotfix end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleOther", counter = true, fn = function() return fullUpdateScheduleStats.other end }
end

local function GetBuiltinContainerType(containerKey)
    return Shared and Shared.GetBuiltinContainerType
        and Shared.GetBuiltinContainerType(containerKey)
        or nil
end

local function GetBuiltinContainerEntryKind(containerKey)
    return Shared and Shared.GetBuiltinContainerEntryKind
        and Shared.GetBuiltinContainerEntryKind(containerKey)
        or nil
end

local function IsBuiltinCooldownContainerKey(containerKey)
    if Shared and Shared.IsBuiltinCooldownContainerKey then
        return Shared.IsBuiltinCooldownContainerKey(containerKey)
    end
    return GetBuiltinContainerEntryKind(containerKey) == "cooldown"
end

local function IsBuiltinAuraContainerKey(containerKey)
    if Shared and Shared.IsBuiltinAuraContainerKey then
        return Shared.IsBuiltinAuraContainerKey(containerKey)
    end
    return GetBuiltinContainerEntryKind(containerKey) == "aura"
end

local function IsCustomBarContainer(containerDB)
    return Shared and Shared.IsCustomBarContainer
        and Shared.IsCustomBarContainer(containerDB)
        or false
end

local function GetCustomBarVisibilityMode(containerDB)
    return Shared and Shared.GetCustomBarVisibilityMode
        and Shared.GetCustomBarVisibilityMode(containerDB)
        or "always"
end

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local CDMCooldown = ns.CDMCooldown or {}
ns.CDMCooldown = CDMCooldown

function CDMIcons:IsRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

-- CustomCDM exposed on CDMIcons for engine access (provider wires to ns.CustomCDM)
local CustomCDM = {}
CDMIcons.CustomCDM = CustomCDM

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local CreateFrame = CreateFrame
local GetTime = GetTime
local wipe = wipe
local select = select
local tostring = tostring
local InCombatLockdown = InCombatLockdown
local C_StringUtil = C_StringUtil
local issecretvalue = issecretvalue

local function IsSafeNumeric(val)
    if issecretvalue and issecretvalue(val) then return false end
    return Shared and Shared.IsSafeNumeric(val) or type(val) == "number"
end

local _resolverRuntimePolicy = {}

local function SafeBoolean(val)
    if issecretvalue and issecretvalue(val) then
        return nil
    end
    if Shared and Shared.SafeBoolean then
        return Shared.SafeBoolean(val)
    end
    if type(val) == "boolean" then
        return val
    end
    return nil
end

function _resolverRuntimePolicy.ApplyDurationObjectCooldown(cd, durObj, clearWhenZero, reverse)
    if ns.CDMRenderers and ns.CDMRenderers.ApplyDurationObjectCooldown then
        return ns.CDMRenderers.ApplyDurationObjectCooldown(cd, durObj, clearWhenZero, reverse)
    end

    if not cd or not durObj or not cd.SetCooldownFromDurationObject then
        return false
    end

    if clearWhenZero == nil then
        clearWhenZero = true
    end

local applied = true; cd.SetCooldownFromDurationObject(cd, durObj, clearWhenZero)
    if reverse ~= nil and cd.SetReverse then
        cd.SetReverse(cd, reverse and true or false)
    end
    return applied and true or false
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
local DEFAULT_ICON_SIZE = 39
local BASE_CROP = 0.08
local ICON_FRAME_LEVEL_OFFSET = 1
local COOLDOWN_FRAME_LEVEL_OFFSET = 1
local TEXT_OVERLAY_FRAME_LEVEL_OFFSET = 6
local GCD_SPELL_ID = 61304
local COOLDOWN_EXPIRY_REFRESH_FUDGE = 0.2
local COOLDOWN_EXPIRY_RESCHEDULE_EPSILON = 0.1

---------------------------------------------------------------------------
-- POOL STATE ALIASES
-- iconPools and recyclePool live in cdm_icon_factory.lua; aliased here as
-- upvalues so direct references in this file resolve without a mass rewrite.
---------------------------------------------------------------------------
local iconPools   = ns.CDMIconFactory._iconPools
local recyclePool = ns.CDMIconFactory._recyclePool
local Factory = ns.CDMIconFactory
local SyncCooldownBling  = Factory.SyncCooldownBling
local UpdateIconCooldown
local UpdateIconSecureAttributes
local SetStackTextWritesForBatch
local SyncSpellRangeChecks
local DisableSpellRangeChecks
local GetTrackerSettings
local stackPolicy
local GetAuraApplicationsForSpell
local customBarPolicy
local refreshBatch
local refreshWalker
local itemVisualPolicy
local ApplyVisibleMirrorStackTextIfNeeded
local GetCachedMirrorStateForIcon
local RefreshCachedMirrorStateForIcon

local cooldownPolicy = ns.CDMIconCooldownPolicy and ns.CDMIconCooldownPolicy.Create({
    getMirror = function()
        return ns.CDMBlizzMirror
    end,
    getCachedMirrorStateForIcon = function(icon)
        return GetCachedMirrorStateForIcon and GetCachedMirrorStateForIcon(icon) or nil
    end,
    refreshCachedMirrorStateForIcon = function(icon)
        return RefreshCachedMirrorStateForIcon and RefreshCachedMirrorStateForIcon(icon) or nil
    end,
    queryCooldown = function(spellID, owner)
        return QueryCooldown and QueryCooldown(spellID, owner) or nil
    end,
    queryOverrideSpell = function(spellID)
        return QueryOverrideSpell and QueryOverrideSpell(spellID) or nil
    end,
})

local function CreateIconRefreshBatch()
    local module = ns.CDMIconRefreshBatch
    if not (module and module.Create) then return nil end
    return module.Create({
        getMemProbes = function()
            local mp = ns._memprobes or {}
            ns._memprobes = mp
            return mp
        end,
        isEditModeActive = function()
            return Helpers.IsEditModeActive()
        end,
        isLayoutModeActive = function()
            return Helpers.IsLayoutModeActive()
        end,
        isGlobalEditModeActive = function()
            return _G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive()
        end,
        getNCDM = function()
            return ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
        end,
        getTime = function()
            return GetTime()
        end,
        isInCombat = function()
            return InCombatLockdown()
        end,
        refreshSwipeBatchSettings = function()
            return _resolverRuntimePolicy.RefreshSwipeBatchSettings()
        end,
        beginRuntimeQueryBatch = function()
            if RuntimeQueries and RuntimeQueries.BeginRuntimeQueryBatch then
                RuntimeQueries.BeginRuntimeQueryBatch()
            end
        end,
        endRuntimeQueryBatch = function()
            if RuntimeQueries and RuntimeQueries.EndRuntimeQueryBatch then
                RuntimeQueries.EndRuntimeQueryBatch()
            end
        end,
        setStackTextWrites = function(enabled)
            if SetStackTextWritesForBatch then
                SetStackTextWritesForBatch(enabled)
            end
        end,
    })
end

refreshBatch = CreateIconRefreshBatch()

_resolverRuntimePolicy.eventProfileStats = {}
_resolverRuntimePolicy.eventProfileLast = {
    time = GetTime and GetTime() or 0,
    counts = {},
    ms = {},
}

function CDMIcons.RecordEventProfile(event, elapsedMS)
    if not event then return end
    local stats = _resolverRuntimePolicy.eventProfileStats[event]
    if not stats then
        stats = { calls = 0, ms = 0 }
        _resolverRuntimePolicy.eventProfileStats[event] = stats
    end
    stats.calls = stats.calls + 1
    stats.ms = stats.ms + (elapsedMS or 0)
end

function CDMIcons.SnapshotEventProfile(limit)
    local now = GetTime and GetTime() or 0
    local last = _resolverRuntimePolicy.eventProfileLast
    local elapsed = now - (last.time or now)
    if elapsed <= 0 then elapsed = 1 end

    local rows = {}
    for event, stats in pairs(_resolverRuntimePolicy.eventProfileStats) do
        local prevCalls = last.counts[event] or 0
        local prevMS = last.ms[event] or 0
        local calls = (stats.calls or 0) - prevCalls
        local ms = (stats.ms or 0) - prevMS
        if calls > 0 or ms > 0 then
            rows[#rows + 1] = {
                event = event,
                calls = calls,
                ms = ms,
                callsPerSec = calls / elapsed,
                msPerSec = ms / elapsed,
            }
        end
        last.counts[event] = stats.calls or 0
        last.ms[event] = stats.ms or 0
    end
    last.time = now

    table.sort(rows, function(a, b)
        if a.ms ~= b.ms then return a.ms > b.ms end
        return a.calls > b.calls
    end)
    limit = limit or 5
    while #rows > limit do
        rows[#rows] = nil
    end
    return rows, elapsed
end

---------------------------------------------------------------------------
-- DEBUG: Charge/stack transform debugging.
-- Enable via:  /run QUI_CDM_CHARGE_DEBUG = true
-- Disable via: /run QUI_CDM_CHARGE_DEBUG = false
-- Optionally filter to a specific spell name:
--   /run QUI_CDM_CHARGE_DEBUG = "Holy Bulwark"
-- Implementation lives in the load-on-demand debug addon. The placeholder
-- below is rebound by cdm_debug.lua's BindAll() when loaded.
---------------------------------------------------------------------------
local ChargeDebug = function() end
CDMIcons._ShouldDebugBlizzEntry = function() return false end
CDMIcons._FormatMirrorState     = function() return "nil" end
CDMIcons._DebugBlizzEntry       = function() end

---------------------------------------------------------------------------
-- DYNAMIC CHILD LOOKUP: Scan ALL viewer children to find the one with
-- auraInstanceID matching a tracked spell.  Blizzard recycles children
-- across auras, so the child→spell assignment changes at runtime.
-- Child lookup infrastructure lives in cdm_spelldata.lua (shared by icons + bars).
---------------------------------------------------------------------------
local function IsTotemSlotEntry(entry)
    return entry and entry._isTotemInstance and entry._totemSlot ~= nil
end

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetLegacyCustomData(trackerKey)
    if QUICore and QUICore.db and QUICore.db.char and QUICore.db.char.ncdm
        and QUICore.db.char.ncdm[trackerKey] and QUICore.db.char.ncdm[trackerKey].customEntries then
        return QUICore.db.char.ncdm[trackerKey].customEntries
    end
    return nil
end

local function GetCustomData(trackerKey)
    if type(trackerKey) ~= "string" or trackerKey == "" then
        return nil
    end

    if Helpers and Helpers.GetNCDMCustomEntries then
        local activeData = Helpers.GetNCDMCustomEntries(trackerKey)
        if activeData then
            return activeData
        end
    end

    return GetLegacyCustomData(trackerKey)
end

---------------------------------------------------------------------------
-- PROFESSION QUALITY OVERLAY
-- Renders a crafted/reagent quality badge atop item/trinket/slot icons when
-- the container opts in via showProfessionQuality.
---------------------------------------------------------------------------
local function CreateIconItemVisualPolicy()
    local module = ns.CDMIconItemVisualPolicy
    if not (module and module.Create) then return nil end
    return module.Create({
        getNCDM = function()
            return ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
        end,
        resolveBestOwnedItemVariant = function(itemID)
            return (Sources and Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(itemID)) or itemID
        end,
        queryInventoryItemLink = function(unit, slotID)
            return Sources and Sources.QueryInventoryItemLink and Sources.QueryInventoryItemLink(unit, slotID)
        end,
        queryInventoryItemID = function(unit, slotID)
            return Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID(unit, slotID)
        end,
        queryItemIconByID = function(itemID)
            return Sources and Sources.QueryItemIconByID and Sources.QueryItemIconByID(itemID)
        end,
        queryItemInfoInstant = function(itemID)
            if Sources and Sources.QueryItemInfoInstant then
                return Sources.QueryItemInfoInstant(itemID)
            end
        end,
        updateSecureAttributes = function(icon, entry, viewerType)
            if UpdateIconSecureAttributes then
                UpdateIconSecureAttributes(icon, entry, viewerType)
            end
        end,
    })
end

itemVisualPolicy = CreateIconItemVisualPolicy()

local function ClearIconProfessionQuality(icon)
    if itemVisualPolicy then
        itemVisualPolicy:ClearProfessionQuality(icon)
    end
end

local function UpdateIconProfessionQuality(icon)
    if itemVisualPolicy then
        itemVisualPolicy:UpdateProfessionQuality(icon)
    end
end

local function QueryItemVisualTexture(itemID)
    if itemVisualPolicy then
        return itemVisualPolicy:GetItemTexture(itemID)
    end
    if Sources and Sources.QueryItemIconByID then
        local texture = Sources.QueryItemIconByID(itemID)
        if texture then return texture end
    end
    if Sources and Sources.QueryItemInfoInstant then
        local _, _, _, _, texture = Sources.QueryItemInfoInstant(itemID)
        return texture
    end
    return nil
end
---------------------------------------------------------------------------
-- ITEM COOLDOWN RESOLUTION
---------------------------------------------------------------------------

local function GetItemCooldown(itemID)
    if not itemID or not (Sources and Sources.QueryItemCooldown) then return nil, nil, nil end
    return Sources.QueryItemCooldown(itemID)
end

local function GetSlotCooldown(slotID)
    if not slotID or not GetInventoryItemCooldown then return nil, nil, nil end
    local ok, startTime, duration, enabled = pcall(GetInventoryItemCooldown, "player", slotID)
    if not ok then return nil, nil, nil end
    return startTime, duration, enabled
end

function _resolverRuntimePolicy.MarkGCDSwipe(icon)
    if cooldownPolicy then
        cooldownPolicy:MarkGCDSwipe(icon)
    end
end

function _resolverRuntimePolicy.ClearGCDSwipe(icon)
    if cooldownPolicy then
        cooldownPolicy:ClearGCDSwipe(icon)
    end
end

-- Expose inventory cooldown adapters for cdm_resolvers.lua + cdm_bar_renderer.lua.
CDMCooldown.GetItemCooldown = GetItemCooldown
CDMCooldown.GetSlotCooldown = GetSlotCooldown

---------------------------------------------------------------------------
-- SWIPE STYLING
---------------------------------------------------------------------------

-- Re-apply QUI swipe styling to the addon-owned CooldownFrame.
local function ReapplySwipeStyle(cd, icon)
    if not cd then return end
    if cd.SetSwipeTexture then
        cd.SetSwipeTexture(cd, "Interface\\Buttons\\WHITE8X8")
    end
    local CooldownSwipe = ns._OwnedSwipe or (QUI and QUI.CooldownSwipe)
    if CooldownSwipe and CooldownSwipe.ApplyToIcon then
        CooldownSwipe.ApplyToIcon(icon)
    end
    if _resolverRuntimePolicy.ApplyCustomBarSwipeStyle then
        _resolverRuntimePolicy.ApplyCustomBarSwipeStyle(icon)
    end
end

local function IsGCDSwipeEnabled()
    local swipe = ns._OwnedSwipe
    local settings = swipe and swipe.GetSettings and swipe.GetSettings()
    return settings and settings.showGCDSwipe == true
end
CDMIcons.IsGCDSwipeEnabled = IsGCDSwipeEnabled

local function GetAuraDataInstanceID(auraData)
    if not auraData then return nil end
    return auraData.auraInstanceID
end

local function GetAuraDisplaySourceID(r, fallbackID)
    if not r then return fallbackID end
    local sourceID = r.auraInstanceID or r.totemSlot
    return sourceID or fallbackID
end

local function ClearPandemicStateForIcon(icon)
    if not icon then return end
    icon._blizzPandemicActive = nil
    icon._blizzPandemicStateKnown = nil

    local glows = ns._OwnedGlows
    if glows and glows.ClearPandemicState then
        glows.ClearPandemicState(icon)
    elseif icon.PandemicGlow then
        icon.PandemicGlow:SetAlpha(0)
    end
end

local function ClearAuraStateForIcon(icon, entry)
    if not icon then return end
    local hadAuraState = icon._auraActive == true
        or icon._lastAuraDurObj ~= nil
        or icon._blizzPandemicStateKnown == true
        or icon.PandemicGlow ~= nil
    icon._auraActive = false
    icon._auraUnit = nil
    icon._auraInstanceID = nil
    icon._totemSlot = entry and entry._totemSlot or nil
    icon._isTotemInstance = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
    icon._activeAuraSpellID = nil
    icon._auraIsHarmful = nil
    if hadAuraState then
        ClearPandemicStateForIcon(icon)
    end
end

local function ApplyAuraStateToIcon(icon, entry, sid, r)
    if not r then
        ClearAuraStateForIcon(icon, entry)
        return nil, false, nil
    end

    local auraActive = r.auraActive
    if auraActive == nil then
        auraActive = r.isActive
    end

    if auraActive then
        local sourceID = GetAuraDisplaySourceID(r, sid)
        icon._auraActive = true
        icon._auraUnit = r.auraUnit
        icon._auraInstanceID = r.auraInstanceID
        icon._totemSlot = r.totemSlot or entry._totemSlot or nil
        icon._isTotemInstance = r.isTotemInstance and true or nil
        icon._activeAuraSpellID = r.resolvedAuraSpellID
        if not icon._activeAuraSpellID and r.auraData then
            local sid2 = r.auraData.spellId
            if type(sid2) == "number" and sid2 > 0 then
                icon._activeAuraSpellID = sid2
            end
        end
        if not icon._activeAuraSpellID and sid then
            icon._activeAuraSpellID = sid
        end

        -- Capture aura type (harmful vs helpful) for pandemic glow gating.
        -- isHarmful is treated as non-secret in this codebase (see
        -- cdm_spelldata.lua's GetUnitAuraBySpellID comment). When auraData
        -- is nil under combat lockdown, preserve any prior value rather
        -- than clobbering — the type doesn't change for a given aura
        -- instance.
        if r.auraData then
            local harmful = r.auraData.isHarmful
            if type(harmful) == "boolean" then
                icon._auraIsHarmful = harmful and true or false
            end
        end

        if r.durObj then
            icon._lastAuraDurObj = r.durObj
            icon._lastAuraSourceID = sourceID
            return r.durObj, true, sourceID
        end

        if r.durationStateUnknown and icon._lastAuraDurObj then
            return icon._lastAuraDurObj, true, icon._lastAuraSourceID or sourceID
        end

        icon._lastAuraDurObj = nil
        icon._lastAuraSourceID = sourceID
        return nil, true, sourceID
    end

    ClearAuraStateForIcon(icon, entry)
    return nil, false, nil
end

local function ApplyMirrorPayloadToIcon(icon, entry, sid, payload)
    if not (icon and payload and payload.mirrorBacked == true) then
        return
    end

    if payload.mode == "aura" then
        local r = icon._mirrorAuraResult
        if not r then
            r = {}
            icon._mirrorAuraResult = r
        end
        r.isActive = payload.active == true
        r.auraActive = payload.auraActive
        if r.auraActive == nil then
            r.auraActive = payload.active == true
        end
        r.auraInstanceID = payload.auraInstanceID
        r.auraUnit = payload.auraUnit
        r.durObj = payload.durObj
        r.auraData = payload.auraData
        -- payload.count is a singleton scratch (BuildMirrorCountPayload pool),
        -- not safe to alias across calls — copy fields into a per-icon table.
        local rc = r.count
        if not rc then
            rc = {}
            r.count = rc
        end
        local pc = payload.count
        if pc then
            rc.value = pc.value
            rc.sinkText = pc.sinkText
            rc.shown = pc.shown
            rc.source = pc.source
        else
            rc.value = nil
            rc.sinkText = nil
            rc.shown = false
            rc.source = nil
        end
        r.resolvedAuraSpellID = payload.spellID
        r.hasExpirationTime = payload.hasExpirationTime
        r.hideDurationText = payload.hideDurationText
        r.durationStateUnknown = payload.durationStateUnknown
        r.totemSlot = payload.totemSlot
        r.totemName = payload.totemName
        r.totemIcon = payload.totemIcon
        r.isTotemInstance = payload.isTotemInstance and true or false
        ApplyAuraStateToIcon(icon, entry, sid, r)
    else
        ClearAuraStateForIcon(icon, entry)
    end
end

---------------------------------------------------------------------------
-- ResolveIconStackText: kind-dispatched stack/charge text resolver.
-- Returns (text, source) where:
--   text   = string for FontString:SetText (may be secret in combat — DO
--            NOT compare in Lua, only forward to SetText)
--   source = "Applications" | "ChargeCount" | nil (informational; drives
--            styling decisions equivalent to the legacy hook source)
-- Aura-kind: stacks via the CDMAuraRuntime application getter, which wraps
-- C_UnitAuras.GetAuraApplicationDisplayCount with IsSecretValue-aware caching.
-- Cooldown-kind: mirror-backed icons trust Blizzard's charge-count fields
-- as authoritative. Non-mirrored multi-charge fallback still uses
-- C_Spell.GetSpellDisplayCount, gated by cached maxCharges > 1.
---------------------------------------------------------------------------
function _resolverRuntimePolicy.ResolveIconStackText(icon)
    if stackPolicy then
        return stackPolicy:ResolveIconStackText(icon)
    end
    return nil
end

function _resolverRuntimePolicy.ResolveMirrorStackText(icon)
    if stackPolicy then
        return stackPolicy:ResolveMirrorStackText(icon)
    end
    return nil
end

local function ResolveTrackerSettingsNow(viewerType)
    if type(GetTrackerSettings) == "function" then
        return GetTrackerSettings(viewerType)
    end
    local db = GetDB and GetDB()
    if not db or not viewerType then return nil end
    return db[viewerType] or (db.containers and db.containers[viewerType]) or nil
end

local function IsCustomBarSettingsNow(settings)
    return IsCustomBarContainer(settings)
end

-- For a multi-charge spell where the recharge IS the cooldown (DK Death
-- Charge is the reference case), the resolver classifies mode=cooldown
-- both at 1+ charges (recharge rolling, spell castable) and at 0 charges
-- (real cooldown, spell uncastable). cdInfo.isActive on
-- C_Spell.GetSpellCooldown distinguishes them:
--   false → 1+ charges available → saturated
--   true  → all charges spent     → desaturated
-- cdInfo.isActive is NeverSecret (see cdm_blizz_mirror.lua:300), so a
-- direct Lua comparison is safe; no curve indirection needed. Returns
-- true when this gate decided the spell should stay saturated.
local function ChargeSpellShouldStaySaturated(icon, entry)
    local sid = icon and icon._runtimeSpellID
    if not sid and entry then
        sid = entry.spellID or entry.overrideSpellID or entry.id
    end
    if not sid then return false end
    local cdInfo = QueryCooldown(sid)
    if not cdInfo then return false end
    return cdInfo.isActive == false
end

local function ApplyCooldownDesaturation(icon, entry, settings, resolvedMode)
    if not icon or not entry or not icon.Icon or not icon.Icon.SetDesaturated then
        return
    end

    settings = settings or ResolveTrackerSettingsNow(entry.viewerType)

    local showOnlyCooldownMode = settings and settings.showOnlyOnCooldown == true
    local customBar = IsCustomBarSettingsNow(settings)
    local auraBlocks = (icon._auraActive or (customBar and icon._customBarActive))
        and not icon._desaturateIgnoreAura
        and not showOnlyCooldownMode

    local shouldDesaturate = settings and settings.desaturateOnCooldown
    local desatOverride = icon._spellOverrideDesaturate
    if desatOverride == true then
        shouldDesaturate = true
    elseif desatOverride == false then
        shouldDesaturate = false
    end

    resolvedMode = resolvedMode or icon._resolvedCooldownMode
    local hasRealCD = icon._hasCooldownActive == true
        and resolvedMode ~= "aura"
        and resolvedMode ~= "gcd-only"
        and resolvedMode ~= "inactive"

    if _G.QUI_CDM_CHARGE_DEBUG then
        ChargeDebug(entry.name, "DESAT result: hasRealCD=", hasRealCD,
            "_hasCooldownActive=", icon._hasCooldownActive,
            "mode=", tostring(resolvedMode),
            "entryHasCharges=", entry.hasCharges,
            "viewerType=", entry.viewerType)
    end

    -- Charge spells: stay saturated while at least one charge is
    -- available. Matches Blizzard CooldownViewer
    -- CheckCacheCooldownValuesFromCharges (sets cooldownDesaturated=false
    -- when displayChargeCooldown). cdInfo.isActive is NeverSecret so we
    -- can compare directly.
    if shouldDesaturate
       and (entry.hasCharges == true or entry.charges == true)
       and ChargeSpellShouldStaySaturated(icon, entry) then
        shouldDesaturate = false
    end

    -- Desaturation gate: range and usability tints are independent visual
    -- layers and must not factor in here (range red on top of a
    -- desaturated icon is the intended composite).
    if entry.viewerType ~= "buff"
       and not auraBlocks
       and shouldDesaturate
       and hasRealCD then
        icon.Icon:SetDesaturated(true)
        icon._cdDesaturated = true
    else
        icon.Icon:SetDesaturated(false)
        icon._cdDesaturated = nil
    end
end

local ResolverRuntime = RuntimeQueries

function _resolverRuntimePolicy.CaptureTrustedGCDStateForIcon(icon, spellState, stamp)
    return cooldownPolicy
        and cooldownPolicy:CaptureTrustedGCDStateForIcon(icon, spellState, stamp)
        or false
end

function _resolverRuntimePolicy.CaptureTrustedGCDState()
    local spellState, stamp = ResolverRuntime.ResetTrustedGCDSnapshot(GetTime())
    return cooldownPolicy
        and cooldownPolicy:CaptureTrustedGCDState(iconPools, spellState, stamp)
        or false
end

local GetRecentCastAliasForEntry
local RecordRecentPlayerSpellCast
local ApplyResolvedCooldown

local function CancelCooldownExpiryRefresh(icon)
    if not icon then return end

    local timer = icon._cooldownExpiryTimer
    if timer and timer.Cancel then
        timer.Cancel(timer)
    end
    icon._cooldownExpiryTimer = nil
    icon._cooldownExpiryTimerKey = nil
    icon._cooldownExpiryAt = nil
end
local function ScheduleCooldownExpiryRefreshAt(icon, key, expiresAt)
    if not icon or not key or not C_Timer then return end
    if not GetTime or not IsSafeNumeric(expiresAt) then return end
    if not (C_Timer.NewTimer or C_Timer.After) then return end

    local delta = icon._cooldownExpiryAt and (icon._cooldownExpiryAt - expiresAt) or nil
    if delta and delta < 0 then delta = -delta end
    if icon._cooldownExpiryTimerKey == key
       and delta
       and delta <= COOLDOWN_EXPIRY_RESCHEDULE_EPSILON then
        return
    end

    local existing = icon._cooldownExpiryTimer
    if existing and existing.Cancel then
        existing.Cancel(existing)
    end

    local delay = expiresAt - GetTime()
    if delay < 0 then delay = 0 end
    delay = delay + COOLDOWN_EXPIRY_REFRESH_FUDGE

    icon._cooldownExpiryTimerKey = key
    icon._cooldownExpiryAt = expiresAt

    local function refresh()
        if icon._cooldownExpiryTimerKey ~= key
           or icon._cooldownExpiryAt ~= expiresAt then
            return
        end
        icon._cooldownExpiryTimer = nil
        icon._cooldownExpiryTimerKey = nil
        icon._cooldownExpiryAt = nil
        -- Re-resolve this icon after its scheduled cooldown expiry. Runtime
        -- spell queries are fresh; the invalidation call is now compatibility.
        if ApplyResolvedCooldown then
            ApplyResolvedCooldown(icon)
        end
    end

    if C_Timer.NewTimer then
        icon._cooldownExpiryTimer = C_Timer.NewTimer(delay, refresh)
    elseif C_Timer.After then
        icon._cooldownExpiryTimer = nil
        C_Timer.After(delay, refresh)
    end
end

local function ScheduleCooldownExpiryRefresh(icon, key, cdInfo)
    if not icon or not key or not cdInfo or not C_Timer then return end
    if not GetTime then return end

    -- cdInfo.startTime / cdInfo.duration may be secret whenever the Blizzard
    -- CDM data feed is active (CVar=1) — combat lockdown is not a tight enough
    -- proxy because tainted execution can persist across UNIT_AURA / event
    -- coalesce edges OOC. Skip scheduling and let event-driven refresh
    -- (SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_USABLE) handle completion. The
    -- C-side DurationObject still drives the visible swipe; this Lua timer
    -- is just a fast-path for clearing _hasCooldownActive after expiry.
    local getCooldownInfoField = Resolvers and Resolvers.GetCooldownInfoField
    if not getCooldownInfoField then return end

    local start = getCooldownInfoField(cdInfo, "startTime")
    if start == nil then
        start = getCooldownInfoField(cdInfo, "start")
    end
    local duration = getCooldownInfoField(cdInfo, "duration")
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then
        if icon._cooldownExpiryTimerKey and icon._cooldownExpiryTimerKey ~= key then
            CancelCooldownExpiryRefresh(icon)
        end
        return
    end
    if type(start) ~= "number" or type(duration) ~= "number" then
        if icon._cooldownExpiryTimerKey and icon._cooldownExpiryTimerKey ~= key then
            CancelCooldownExpiryRefresh(icon)
        end
        return
    end
    if start <= 0 or duration <= 0 then
        CancelCooldownExpiryRefresh(icon)
        return
    end

    ScheduleCooldownExpiryRefreshAt(icon, key, start + duration)
end

function _resolverRuntimePolicy.GetIconMirrorState(icon)
    return cooldownPolicy and cooldownPolicy:GetIconMirrorState(icon) or nil
end

function _resolverRuntimePolicy.MirrorStateIsActive(state)
    return cooldownPolicy and cooldownPolicy:MirrorStateIsActive(state) or false
end

function _resolverRuntimePolicy.ClearIconChargeMirrorCycle(icon)
    if cooldownPolicy then
        cooldownPolicy:ClearIconChargeMirrorCycle(icon)
    end
end

function _resolverRuntimePolicy.RememberIconChargeMirrorCycle(icon, runtimeSpellID)
    if cooldownPolicy then
        cooldownPolicy:RememberIconChargeMirrorCycle(icon, runtimeSpellID)
    end
end

function _resolverRuntimePolicy.UpdateIconChargeMirrorCycle(icon, mode, runtimeSpellID, hasCharges)
    if cooldownPolicy then
        cooldownPolicy:UpdateIconChargeMirrorCycle(icon, mode, runtimeSpellID, hasCharges)
    end
end

function _resolverRuntimePolicy.MirrorPayloadHasChargeState(mirrorPayload)
    return cooldownPolicy and cooldownPolicy:MirrorPayloadHasChargeState(mirrorPayload) or false
end

function _resolverRuntimePolicy.MirrorPayloadMatchesRecentChargeCycle(icon, mirrorPayload)
    return cooldownPolicy
        and cooldownPolicy:MirrorPayloadMatchesRecentChargeCycle(icon, mirrorPayload)
        or false
end

function _resolverRuntimePolicy.IsRealCooldownDurationMode(mode)
    return mode == "cooldown"
        or mode == "item-cooldown"
end

local function BuildDurationBindingKey(mode, sourceID)
    local sourceType = type(sourceID)
    if (sourceType == "number" or sourceType == "string")
        and type(mode) == "string"
        and not (issecretvalue and issecretvalue(sourceID))
        and (mode == "gcd-only" or _resolverRuntimePolicy.IsRealCooldownDurationMode(mode)) then
        local cache = _resolverRuntimePolicy.durationBindingKeyCache
        if not cache then
            cache = {}
            _resolverRuntimePolicy.durationBindingKeyCache = cache
        end
        local modeCache = cache[mode]
        if not modeCache then
            modeCache = {}
            cache[mode] = modeCache
        end
        local typeCache = modeCache[sourceType]
        if not typeCache then
            typeCache = {}
            modeCache[sourceType] = typeCache
        end
        local key = typeCache[sourceID]
        if key then
            durationBindingStats.keyCacheHits = durationBindingStats.keyCacheHits + 1
            return key
        end
        key = mode .. ":" .. tostring(sourceID)
        typeCache[sourceID] = key
        durationBindingStats.keyBuilds = durationBindingStats.keyBuilds + 1
        return key
    end

    durationBindingStats.keyBuilds = durationBindingStats.keyBuilds + 1
    return mode .. ":" .. tostring(sourceID)
end

function _resolverRuntimePolicy.ClearDurationBindingKeyCache()
    _resolverRuntimePolicy.durationBindingKeyCache = nil
end

local function DurationBindingSourceCanCompare(sourceID)
    return not (issecretvalue and issecretvalue(sourceID))
end

function _resolverRuntimePolicy.DurationBindingSourcesMatch(left, right)
    if not DurationBindingSourceCanCompare(left)
        or not DurationBindingSourceCanCompare(right) then
        return false
    end

    local leftType = type(left)
    local rightType = type(right)
    if leftType == rightType then
        return left == right
    end
    if leftType == "number" and rightType == "string" then
        return tonumber(right) == left
    end
    if leftType == "string" and rightType == "number" then
        return tonumber(left) == right
    end
    return false
end

function _resolverRuntimePolicy.DurationBindingFieldMatches(icon, mode, sourceID)
    return icon
        and icon._lastResolvedMode == mode
        and _resolverRuntimePolicy.DurationBindingSourcesMatch(icon._lastResolvedSourceID, sourceID)
end

function _resolverRuntimePolicy.DurationBindingLegacyKeyMatches(icon, mode, sourceID)
    local key = icon and icon._lastDurObjKey
    if type(key) ~= "string" or type(mode) ~= "string" then return false end
    if not DurationBindingSourceCanCompare(sourceID) then return false end

    local modeLength = #mode
    local sourceStart = modeLength + 2
    if key:byte(modeLength + 1) ~= 58 then return false end
    if key:find(mode, 1, true) ~= 1 then return false end

    local sourceType = type(sourceID)
    if sourceType == "string" then
        if key:find(sourceID, sourceStart, true) ~= sourceStart then return false end
        if sourceStart + #sourceID - 1 ~= #key then return false end
    elseif sourceType == "number" then
        local numericSource = tonumber(key:sub(sourceStart))
        if numericSource ~= sourceID then return false end
    else
        return false
    end

    icon._lastResolvedMode = mode
    icon._lastResolvedSourceID = sourceID
    return true
end

local function DurationBindingMatches(icon, mode, sourceID, durObj, mirrorBackedDuration)
    if not icon then return false end

    local sameBinding = _resolverRuntimePolicy.DurationBindingFieldMatches(icon, mode, sourceID)
        or _resolverRuntimePolicy.DurationBindingLegacyKeyMatches(icon, mode, sourceID)

    if not sameBinding then return false end
    if mode == "aura" then
        return durObj == icon._lastDurObj
    end
    if mode == "gcd-only" and mirrorBackedDuration == true then
        if issecretvalue and (issecretvalue(durObj) or issecretvalue(icon._lastDurObj)) then
            return false
        end
        return durObj == icon._lastDurObj
    end
    return true
end

local function GetDurationBindingKey(icon, mode, sourceID)
    local key = icon and icon._lastDurObjKey
    if type(key) == "string"
        and (_resolverRuntimePolicy.DurationBindingFieldMatches(icon, mode, sourceID)
            or _resolverRuntimePolicy.DurationBindingLegacyKeyMatches(icon, mode, sourceID)) then
        return key
    end
    return BuildDurationBindingKey(mode, sourceID)
end

local _iconCooldownStateContextOptions = {
    mirrorIdentityPolicy = "frame-or-entry",
}

local function NormalizeIconMirrorCategory(category)
    if Shared and Shared.NormalizeMirrorCategory then
        return Shared.NormalizeMirrorCategory(category)
    end
    if category == "essential"
        or category == "utility"
        or category == "buff"
        or category == "trackedBar" then
        return category
    end
    return nil
end

local function ResolveIconMirrorCategory(icon)
    local entry = icon and icon._spellEntry
    return NormalizeIconMirrorCategory(icon and icon._blizzMirrorCategory)
        or NormalizeIconMirrorCategory(entry and entry.blizzardMirrorCategory)
        or NormalizeIconMirrorCategory(entry and entry.viewerCategory)
        or NormalizeIconMirrorCategory(entry and entry.viewerType)
end

local function StoreCachedMirrorStateForIcon(icon, cooldownID, category, state)
    if not icon then return end
    if state and cooldownID and category then
        local epoch = state.mirrorEpoch
        icon._blizzMirrorState = state
        icon._blizzMirrorStateCooldownID = cooldownID
        icon._blizzMirrorStateCategory = category
        if icon._blizzMirrorSourceCooldownID ~= cooldownID
            or icon._blizzMirrorSourceEpoch ~= epoch then
            icon._blizzMirrorSourceID = "mirror:" .. tostring(cooldownID) .. ":" .. tostring(epoch)
            icon._blizzMirrorSourceCooldownID = cooldownID
            icon._blizzMirrorSourceEpoch = epoch
        end
    else
        icon._blizzMirrorState = nil
        icon._blizzMirrorStateCooldownID = nil
        icon._blizzMirrorStateCategory = nil
        icon._blizzMirrorSourceID = nil
        icon._blizzMirrorSourceCooldownID = nil
        icon._blizzMirrorSourceEpoch = nil
    end
end

GetCachedMirrorStateForIcon = function(icon)
    if not icon then return nil end
    local cooldownID = icon._blizzMirrorCooldownID
    local category = ResolveIconMirrorCategory(icon)
    if not (cooldownID and category) then return nil end

    if icon._blizzMirrorStateCooldownID == cooldownID
        and icon._blizzMirrorStateCategory == category then
        return icon._blizzMirrorState
    end
    return nil
end

RefreshCachedMirrorStateForIcon = function(icon)
    if not icon then return nil end
    local cooldownID = icon._blizzMirrorCooldownID
    local category = ResolveIconMirrorCategory(icon)
    if not (cooldownID and category) then return nil end

    local mirror = ns.CDMBlizzMirror
    if mirror and mirror.GetStateByCooldownID then
        local state = mirror.GetStateByCooldownID(cooldownID, category)
        StoreCachedMirrorStateForIcon(icon, cooldownID, category, state)
        return state
    end

    return GetCachedMirrorStateForIcon(icon)
end

local function BuildIconCooldownStateContext(icon, entry, runtimeSpellID, useBuffSwipe, skipAuraPhase, totemSlot)
    local builder = Resolvers and Resolvers.BuildCooldownStateContext
    if not builder then return nil end

    local options = _iconCooldownStateContextOptions
    options.containerKey = entry and entry.viewerType
    options.totemSlot = totemSlot or (icon and icon._totemSlot)
    options.useBuffSwipe = useBuffSwipe
    options.skipAuraPhase = skipAuraPhase == true
    options.showGCDSwipe = IsGCDSwipeEnabled()
    options.lastChargeMirrorCooldownID = icon and icon._lastChargeMirrorCooldownID
    options.lastChargeMirrorCategory = icon and icon._lastChargeMirrorCategory
    options.lastChargeRuntimeSpellID = icon and icon._lastChargeRuntimeSpellID
    local cachedMirrorState = GetCachedMirrorStateForIcon(icon)
    options.cachedMirrorState = cachedMirrorState
    options.cachedMirrorSourceID = cachedMirrorState and icon and icon._blizzMirrorSourceID or nil
    return builder(icon, entry, runtimeSpellID, options)
end

function _resolverRuntimePolicy.ResolvedAuraStateIsActive(state)
    if not state then return false end
    if state.auraActive ~= nil then
        return state.auraActive == true
    end
    return state.isActive == true
end

function _resolverRuntimePolicy.ResolveResolvedStateForIcon(icon, entry, runtimeSpellID, useBuffSwipe, skipAuraPhase)
    if not (Resolvers.ResolveCooldownState and icon and entry) then
        return nil
    end

    local totemSlot = icon._totemSlot
    if IsTotemSlotEntry(entry) then
        totemSlot = entry._totemSlot
    end

    local context = BuildIconCooldownStateContext(
        icon, entry, runtimeSpellID, useBuffSwipe, skipAuraPhase, totemSlot)
    if not context then return nil end

    return Resolvers.ResolveCooldownState(context)
end

function _resolverRuntimePolicy.ResolveAuraFactsForIcon(icon, entry, runtimeSpellID, useBuffSwipe)
    local state = _resolverRuntimePolicy.ResolveResolvedStateForIcon(icon, entry, runtimeSpellID, useBuffSwipe, false)
    if not state then return nil end
    if state.auraResolved == true or state.mode == "aura" or state.auraActive ~= nil then
        return state
    end
    return nil
end

function _resolverRuntimePolicy.StoreIconRuntimeState(icon, mode, sourceID, spellID, durObj,
                                                       resolvedStart, resolvedDuration, cdActive,
                                                       hasNumericCooldown, rechargeActive,
                                                       hasCharges, hasChargesRemaining,
                                                       mirrorBackedDuration, mirrorPayload,
                                                       resolvedState)
    local store = ns.CDMRuntimeStore
    if not (store and store.SetIconState) then return end

    local state = _resolverRuntimePolicy.iconRuntimeStateScratch
    if not state then
        state = {}
        _resolverRuntimePolicy.iconRuntimeStateScratch = state
    end

    state.mode = mode
    state.sourceID = sourceID
    state.spellID = spellID
    state.durObj = durObj
    state.start = resolvedStart
    state.duration = resolvedDuration
    state.active = cdActive
    state.numericCooldownActive = hasNumericCooldown
    state.isOnCooldown = cdActive
    state.rechargeActive = rechargeActive == true
    state.hasCharges = hasCharges == true
    state.hasChargesRemaining = hasChargesRemaining == true
    state.gcdOnly = mode == "gcd-only"
    state.key = nil
    state.mirrorBacked = mirrorBackedDuration == true
    state.mirrorState = mirrorPayload and mirrorPayload.state or nil
    state.mirrorCooldownID = resolvedState and resolvedState.mirrorCooldownID or nil
    state.mirrorCategory = resolvedState and resolvedState.mirrorCategory or nil
    state.auraActive = resolvedState and resolvedState.auraActive or nil
    state.auraInstanceID = resolvedState and resolvedState.auraInstanceID or nil
    state.auraUnit = resolvedState and resolvedState.auraUnit or nil
    state.resolvedAuraSpellID = resolvedState and resolvedState.resolvedAuraSpellID or nil
    state.hasExpirationTime = resolvedState and resolvedState.hasExpirationTime or nil
    state.hideDurationText = resolvedState and resolvedState.hideDurationText or nil
    state.durationStateUnknown = resolvedState and resolvedState.durationStateUnknown or nil
    state.countValue = resolvedState and resolvedState.countValue or nil
    state.countSinkText = resolvedState and resolvedState.countSinkText or nil
    state.countShown = resolvedState and resolvedState.countShown == true or false
    state.countSource = resolvedState and resolvedState.countSource or nil
    state.countMirrorBacked = resolvedState and resolvedState.countMirrorBacked or nil

    store.SetIconState(icon, state)
end

local function ClearIconDurationBinding(icon, addonCD)
    icon._lastDurObjKey = nil
    icon._lastDurObj = nil
    icon._lastResolvedMode = nil
    icon._lastResolvedSourceID = nil
    icon._lastResolvedSpellID = nil
    CancelCooldownExpiryRefresh(icon)
    if addonCD then
        if ns.CDMRenderers and ns.CDMRenderers.ClearCooldown then
            ns.CDMRenderers.ClearCooldown(addonCD, false)
        else
            if addonCD.SetReverse then
                addonCD.SetReverse(addonCD, false)
            end
            addonCD:Clear()
        end
    end
end

-- Mirrored aura icons must render the exact cooldownID mirror state already
-- synchronized onto the icon; generic aura resolution can match another unit.
local function ApplySyncedMirrorAuraCooldown(icon, entry)
    local addonCD = icon and icon.Cooldown
    if not (icon and entry and addonCD) then return false end

    local active = icon._auraActive == true
    local durObj = active and icon._lastAuraDurObj or nil
    local mode = active and "aura" or "inactive"
    local sourceID = icon._lastAuraSourceID
    local spellID = icon._activeAuraSpellID
        or icon._runtimeSpellID
        or entry.overrideSpellID
        or entry.spellID
        or entry.id

    icon._resolvedCooldownMode = mode
    icon._hasCooldownActive = false
    icon._hasRealCooldownActive = false
    ApplyCooldownDesaturation(icon, entry, nil, mode)

    local resolvedState = _resolverRuntimePolicy.syncedMirrorAuraStateScratch
    if not resolvedState then
        resolvedState = {}
        _resolverRuntimePolicy.syncedMirrorAuraStateScratch = resolvedState
    end
    resolvedState.mode = mode
    resolvedState.sourceID = sourceID
    resolvedState.spellID = spellID
    resolvedState.durObj = durObj
    resolvedState.auraActive = active
    resolvedState.auraInstanceID = icon._auraInstanceID
    resolvedState.auraUnit = icon._auraUnit
    resolvedState.resolvedAuraSpellID = spellID
    resolvedState.hasRenderableCooldown = durObj ~= nil
    resolvedState.durationStateUnknown = nil
    resolvedState.countValue = nil
    resolvedState.countSinkText = nil
    resolvedState.countShown = nil
    resolvedState.countSource = nil
    resolvedState.countMirrorBacked = nil
    _resolverRuntimePolicy.StoreIconRuntimeState(
        icon, mode, sourceID, spellID, durObj,
        nil, nil, false, false, false, false, false,
        true, nil, resolvedState)

    if not durObj then
        if icon._lastDurObjKey ~= nil
            or icon._lastDurObj ~= nil
            or icon._lastResolvedMode ~= nil then
            ClearIconDurationBinding(icon, addonCD)
        else
            CancelCooldownExpiryRefresh(icon)
        end
        _resolverRuntimePolicy.ClearGCDSwipe(icon)
        icon._showingRealCooldownSwipe = nil
        ReapplySwipeStyle(addonCD, icon)
        return false
    end

    if DurationBindingMatches(icon, mode, sourceID, durObj, true) then
        icon._lastResolvedMode = mode
        icon._lastResolvedSourceID = sourceID
        icon._lastResolvedSpellID = spellID
        icon._showingRealCooldownSwipe = true
        _resolverRuntimePolicy.ClearGCDSwipe(icon)
        ReapplySwipeStyle(addonCD, icon)
        return true
    end

    local key = BuildDurationBindingKey(mode, sourceID)
    icon._lastDurObjKey = key
    icon._lastDurObj = durObj
    icon._lastResolvedMode = mode
    icon._lastResolvedSourceID = sourceID
    icon._lastResolvedSpellID = spellID

    local applied = _resolverRuntimePolicy.ApplyDurationObjectCooldown(addonCD, durObj, true, true)
    if not applied then
        ClearIconDurationBinding(icon, nil)
        return false
    end

    CancelCooldownExpiryRefresh(icon)
    icon._showingRealCooldownSwipe = true
    _resolverRuntimePolicy.ClearGCDSwipe(icon)
    ReapplySwipeStyle(addonCD, icon)
    return true
end

-- Single-writer cooldown apply: ask the resolver, bind icon.Cooldown to the
-- returned DurationObject. Item entries may fall back to SetCooldown only
-- with verified non-secret numeric item timing. SetCooldownFromDurationObject
-- creates a live C-side binding; numeric item fallback gets a one-shot expiry
-- refresh through this same writer. Flags are derived from the classifier —
-- no Blizzard frame state mirroring.
-- See docs/blizzard/cdm-api-reference.md for the cooldown setter policy.
ApplyResolvedCooldown = function(icon, preResolvedState)
    local addonCD = icon and icon.Cooldown
    if not addonCD then return false end

    local entry = icon._spellEntry
    local useBuffSwipe = _resolverRuntimePolicy.ShouldUseBuffSwipeForIcon(icon, entry)
    local skipAuraPhase = _resolverRuntimePolicy.ShouldSkipAuraPhaseForCooldownIcon(icon, entry)
    local measure = ns.MemAuditProfilerMeasure
    local stateContext
    local resolvedState = preResolvedState
    if resolvedState then
        durationBindingStats.resolvedStateReuses = durationBindingStats.resolvedStateReuses + 1
    else
        if measure then
            stateContext = measure(
                "CDM_applyBuildContext",
                BuildIconCooldownStateContext,
                icon, entry, icon._runtimeSpellID, useBuffSwipe, skipAuraPhase)
        else
            stateContext = BuildIconCooldownStateContext(
                icon, entry, icon._runtimeSpellID, useBuffSwipe, skipAuraPhase)
        end
        if not stateContext then return false end

        if measure then
            resolvedState = measure("CDM_applyResolveState", Resolvers.ResolveCooldownState, stateContext)
        else
            resolvedState = Resolvers.ResolveCooldownState(stateContext)
        end
    end
    if not resolvedState then return false end
    local entryIsAura = entry and IsAuraEntry(entry)
    local itemEntryForCooldown = entry
        and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
    if resolvedState
       and resolvedState.hasRenderableCooldown ~= true
       and not entryIsAura
       and not itemEntryForCooldown then
        local aliasID = GetRecentCastAliasForEntry(entry)
        local runtimeSpellID = stateContext and stateContext.runtimeSpellID or icon._runtimeSpellID
        if aliasID and aliasID ~= runtimeSpellID then
            local aliasContext
            if measure then
                aliasContext = measure(
                    "CDM_applyBuildContext",
                    BuildIconCooldownStateContext,
                    icon, entry, aliasID, useBuffSwipe, skipAuraPhase)
            else
                aliasContext = BuildIconCooldownStateContext(
                    icon, entry, aliasID, useBuffSwipe, skipAuraPhase)
            end
            local aliasState
            if aliasContext and measure then
                aliasState = measure("CDM_applyResolveState", Resolvers.ResolveCooldownState, aliasContext)
            elseif aliasContext then
                aliasState = Resolvers.ResolveCooldownState(aliasContext)
            end
            if aliasState and aliasState.hasRenderableCooldown == true then
                resolvedState = aliasState
                icon._runtimeSpellID = aliasID
            end
        end
    end
    local durObj = resolvedState.durObj
    local mode = resolvedState.mode
    local sourceID = resolvedState.sourceID
    local resolvedStart = resolvedState.start
    local resolvedDuration = resolvedState.duration
    local resolvedSpellID = resolvedState.spellID
    local mirrorBackedDuration = resolvedState.mirrorBacked == true
    local mirrorPayload = mirrorBackedDuration and resolvedState or nil
    icon._resolvedCooldownMode = mode

    local sid = resolvedSpellID
    if not sid and entry and not itemEntryForCooldown then
        sid = icon._runtimeSpellID
            or entry.overrideSpellID or entry.spellID or entry.id
    end
    if sid and not entryIsAura then
        sid = QueryOverrideSpell(sid) or sid
    end
    if mirrorBackedDuration == true then
        ApplyMirrorPayloadToIcon(icon, entry, sid or resolvedSpellID, mirrorPayload)
    elseif resolvedState.auraResolved == true then
        local auraDur, auraActive, auraSourceID =
            ApplyAuraStateToIcon(icon, entry, sid or resolvedSpellID, resolvedState)
        if mode == "aura" then
            durObj = auraDur
            sourceID = auraSourceID or sourceID
            resolvedState.durObj = durObj
            resolvedState.sourceID = sourceID
            if auraActive ~= true then
                mode = "inactive"
                resolvedState.mode = mode
                icon._resolvedCooldownMode = mode
            end
        end
    elseif mode ~= "aura" then
        ClearAuraStateForIcon(icon, entry)
    end

    local entryHasCharges = entry and (entry.hasCharges == true or entry.charges == true) or false
    _resolverRuntimePolicy.UpdateIconChargeMirrorCycle(icon, mode, sid or resolvedSpellID, entryHasCharges)

    local cdActive = mode ~= "inactive" and resolvedState.isOnCooldown == true
    local resolvedCdInfo = resolvedState.cooldownInfo
    local _dbgIsActive = resolvedState.cooldownInfoActive
    local _dbgIsOnGCD = resolvedState.cooldownInfoOnGCD

    -- Diagnostic: log every isActive/isOnGCD transition for icons whose
    -- name matches CDMIcons._desatTraceName. Set via /cdmdebug spell <name> trace.
    if CDMIcons._desatTraceName and entry and entry.name == CDMIcons._desatTraceName then
        local prevActive = icon._desatTracePrev
        if prevActive ~= cdActive then
            icon._desatTracePrev = cdActive
            print(string.format(
                "|cffff8800[desat]|r %s sid=%s cd.isActive=%s cd.isOnGCD=%s -> cdActive=%s",
                tostring(entry.name), tostring(sid),
                tostring(_dbgIsActive), tostring(_dbgIsOnGCD),
                tostring(cdActive)))
        end
    end
    icon._hasCooldownActive = cdActive
    icon._hasRealCooldownActive = cdActive
    -- Resolver is the single writer of desaturation. Action depends on
    -- the resolved mode (ApplyCooldownDesaturation's hasRealCD gate at
    -- cdm_icon_renderer.lua:1217-1220 makes the call):
    --   * real-CD modes (cooldown / charge / item-cooldown) → desat ON
    --   * aura / inactive / gcd-only                        → desat OFF
    -- gcd-only means the visible swipe is a GCD, not a real CD
    -- (feedback_blizz_cd_state_signals). If the resolver returns gcd-only
    -- the real CD is either over or shorter than the remaining GCD, so the
    -- spell is effectively usable and the icon must not be desaturated.
    -- Without this call the prior real-CD desat=true persists through the
    -- entire GCD-after-CD-end chain (mode stays gcd-only until GCDs stop),
    -- leaving the icon greyed out for seconds after the real CD ended.
    ApplyCooldownDesaturation(icon, entry, nil, mode)

    local hasNumericCooldown = resolvedState.numericCooldownActive == true
    local keySource = sourceID
    local hasCharges = resolvedState.hasCharges == true
    local rechargeActive = resolvedState.rechargeActive == true
    local hasChargesRemaining = resolvedState.hasChargesRemaining == true
    local hasRenderableCooldown = resolvedState.hasRenderableCooldown
    if hasRenderableCooldown == nil then
        hasRenderableCooldown = durObj ~= nil or hasNumericCooldown == true
    end
    if measure then
        measure(
            "CDM_applyStoreState",
            _resolverRuntimePolicy.StoreIconRuntimeState,
            icon, mode, sourceID, sid or resolvedSpellID, durObj,
            resolvedStart, resolvedDuration, cdActive, hasNumericCooldown,
            rechargeActive, hasCharges, hasChargesRemaining,
            mirrorBackedDuration, mirrorPayload, resolvedState)
    else
        _resolverRuntimePolicy.StoreIconRuntimeState(
            icon, mode, sourceID, sid or resolvedSpellID, durObj,
            resolvedStart, resolvedDuration, cdActive, hasNumericCooldown,
            rechargeActive, hasCharges, hasChargesRemaining,
            mirrorBackedDuration, mirrorPayload, resolvedState)
    end

    local stackTextWritesAllowed = CDMIcons.ShouldAllowStackTextWrites
        and CDMIcons.ShouldAllowStackTextWrites() == true
    if not stackTextWritesAllowed and ApplyVisibleMirrorStackTextIfNeeded then
        ApplyVisibleMirrorStackTextIfNeeded(icon, entry)
    end

    if hasRenderableCooldown ~= true or mode == "inactive" then
        CancelCooldownExpiryRefresh(icon)
        if mode == "aura"
           and InCombatLockdown()
           and icon._lastAuraDurObj
           and DurationBindingMatches(icon, mode, keySource, durObj, mirrorBackedDuration)
        then
            icon._showingRealCooldownSwipe = true
            _resolverRuntimePolicy.ClearGCDSwipe(icon)
            return true
        end
        if mode == "aura" then
            icon._lastDurObjKey = nil
            icon._lastDurObj = nil
            icon._lastResolvedMode = nil
            icon._lastResolvedSourceID = nil
            icon._lastResolvedSpellID = nil
            if ns.CDMRenderers and ns.CDMRenderers.ClearCooldown then
                ns.CDMRenderers.ClearCooldown(addonCD, false)
            else
                if addonCD.SetReverse then
                    addonCD.SetReverse(addonCD, false)
                end
                addonCD:Clear()
            end
            _resolverRuntimePolicy.ClearGCDSwipe(icon)
            icon._showingRealCooldownSwipe = nil
            return false
        end
        if icon._lastDurObjKey ~= nil then
            icon._lastDurObjKey = nil
            icon._lastDurObj = nil
            icon._lastResolvedMode = nil
            icon._lastResolvedSourceID = nil
            icon._lastResolvedSpellID = nil
            if ns.CDMRenderers and ns.CDMRenderers.ClearCooldown then
                ns.CDMRenderers.ClearCooldown(addonCD, false)
            else
                if addonCD.SetReverse then
                    addonCD.SetReverse(addonCD, false)
                end
                addonCD:Clear()
            end
        end
        _resolverRuntimePolicy.ClearGCDSwipe(icon)
        icon._showingRealCooldownSwipe = nil
        return false
    end

    -- Dedupe: only re-bind when the source DurObj changes (mode swap, override
    -- swap, aura→CD transition, etc.). Re-binding on every event restarts the
    -- C-side sweep + countdown text — visible as text vanishing briefly.
    -- Aura mode also compares the DurationObject userdata identity: aura
    -- refreshes retain the same auraInstanceID (so the key is stable) but
    -- C_UnitAuras.GetAuraDuration returns a new userdata wrapper, which is
    -- our refresh signal. Same C-userdata identity check the bar path uses
    -- in cdm_bar_renderer.lua — safe in combat, no secret values.
    local shouldScheduleExpiry = (mode == "aura" and hasNumericCooldown == true)
        or (cdActive == true
            and (resolvedCdInfo ~= nil or hasNumericCooldown)
            and (mode == "cooldown" or mode == "item-cooldown"))
    local sameDurationBinding = DurationBindingMatches(icon, mode, keySource, durObj, mirrorBackedDuration)
    if sameDurationBinding then
        if shouldScheduleExpiry then
            local key = GetDurationBindingKey(icon, mode, keySource)
            if resolvedCdInfo then
                ScheduleCooldownExpiryRefresh(icon, key, resolvedCdInfo)
            else
                ScheduleCooldownExpiryRefreshAt(icon, key, resolvedStart + resolvedDuration)
            end
        else
            CancelCooldownExpiryRefresh(icon)
        end
        if mode == "aura" or mode == "cooldown" or mode == "item-cooldown" then
            icon._lastResolvedMode = mode
            icon._lastResolvedSourceID = sourceID
            icon._lastResolvedSpellID = sid or resolvedSpellID
            icon._showingRealCooldownSwipe = true
            _resolverRuntimePolicy.ClearGCDSwipe(icon)
        elseif mode == "gcd-only" then
            _resolverRuntimePolicy.MarkGCDSwipe(icon)
        end
        if measure then
            measure("CDM_applySwipeStyle", ReapplySwipeStyle, addonCD, icon)
        else
            ReapplySwipeStyle(addonCD, icon)
        end
        return true
    end
    local key = BuildDurationBindingKey(mode, keySource)
    icon._lastDurObjKey = key
    icon._lastDurObj = durObj
    icon._lastResolvedMode = mode
    icon._lastResolvedSourceID = sourceID
    icon._lastResolvedSpellID = sid or resolvedSpellID

    local applied
    if durObj then
        if measure then
            applied = measure(
                "CDM_applyCooldownFrame",
                _resolverRuntimePolicy.ApplyDurationObjectCooldown,
                addonCD, durObj, true, mode == "aura")
        else
            applied = _resolverRuntimePolicy.ApplyDurationObjectCooldown(addonCD, durObj, true, mode == "aura")
        end
    elseif hasNumericCooldown then
        if ns.CDMRenderers and ns.CDMRenderers.ApplyNumericCooldown then
            if measure then
                applied = measure(
                    "CDM_applyCooldownFrame",
                    ns.CDMRenderers.ApplyNumericCooldown,
                    addonCD, resolvedStart, resolvedDuration, mode == "aura")
            else
                applied = ns.CDMRenderers.ApplyNumericCooldown(addonCD, resolvedStart, resolvedDuration, mode == "aura")
            end
        end
    end
    if not applied then
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
        icon._lastResolvedMode = nil
        icon._lastResolvedSourceID = nil
        icon._lastResolvedSpellID = nil
        CancelCooldownExpiryRefresh(icon)
        return false
    end

    if shouldScheduleExpiry then
        if resolvedCdInfo then
            ScheduleCooldownExpiryRefresh(icon, key, resolvedCdInfo)
        else
            ScheduleCooldownExpiryRefreshAt(icon, key, resolvedStart + resolvedDuration)
        end
    else
        CancelCooldownExpiryRefresh(icon)
    end

    if mode == "aura" or mode == "cooldown" or mode == "item-cooldown" then
        icon._showingRealCooldownSwipe = true
        _resolverRuntimePolicy.ClearGCDSwipe(icon)
    elseif mode == "gcd-only" then
        icon._showingRealCooldownSwipe = nil
        _resolverRuntimePolicy.MarkGCDSwipe(icon)
    end
    if measure then
        measure("CDM_applySwipeStyle", ReapplySwipeStyle, addonCD, icon)
    else
        ReapplySwipeStyle(addonCD, icon)
    end

    return true
end

local function UnmirrorBlizzCooldown(icon)
    if not icon then return end
    icon._blizzCooldown = nil
    icon._auraActive = nil
    icon._auraUnit = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
    icon._activeAuraSpellID = nil
end
CDMIcons.ApplyResolvedCooldown = function(icon) return ApplyResolvedCooldown(icon) end

---------------------------------------------------------------------------
-- BLIZZARD STACK/CHARGE TEXT HOOK
-- Mirrors charge counts and application stacks from Blizzard's hidden
-- viewer children to our addon-owned icon.StackText via hooksecurefunc.
-- Polling IsShown()/GetText() is unreliable — child frames under hidden
-- Blizzard viewers may return secret values during combat.  Hook parameters
-- come from Blizzard's secure calling code and are clean.
-- No initial seeding — hooks fire when Blizzard
-- first updates the frames (next charge/aura change after BuildIcons).
---------------------------------------------------------------------------


local function HookTextHasDisplay(text)
    if stackPolicy then
        return stackPolicy:TextHasDisplay(text)
    end
    return text ~= nil
end
function _resolverRuntimePolicy.ValueIsPresent(value)
    if stackPolicy then
        return stackPolicy:ValueIsPresent(value)
    end
    return value ~= nil
end

function _resolverRuntimePolicy.ValueIsMissing(value)
    return stackPolicy and stackPolicy:ValueIsMissing(value)
        or not _resolverRuntimePolicy.ValueIsPresent(value)
end

local function ClearIconStackText(icon)
    if stackPolicy then
        stackPolicy:Clear(icon)
    elseif icon and icon.StackText then
        icon.StackText.SetText(icon.StackText, "")
        icon.StackText.Hide(icon.StackText)
        icon._stackTextSource = nil
    end
end

-- Persistent spell-name cache. C_Spell.GetSpellInfo can return a secret
-- value in info.name during combat, and a secret name silently breaks
-- GetAuraDataBySpellName downstream. Resolve OOC and cache per-spell so
-- subsequent in-combat rebuilds (BuildSpellEntryFromCustom fired by the
-- filter-flip relayout when hideNonUsable's verdict crosses 0/1 stacks)
-- read a clean string instead of a fresh, possibly-secret one. Cache
-- entries are stable across the session — spell names don't mutate.
local _spellNameCache = {}

-- Returns ONLY clean (non-secret) names so the cache value is safe to
-- compare against "" downstream (cdm_bar_renderer.lua, cdm_frame_writes.lua, profile_io.lua
-- all do `entry.name ~= ""`). Skips GetSpellInfo entirely in combat —
-- info.name there could be secret, and we don't want a secret leaking
-- onto entry.name and tainting unrelated comparison sites.
local function GetCachedSpellName(spellID)
    if not spellID then return nil end
    local cached = _spellNameCache[spellID]
    if cached then return cached end
    if InCombatLockdown() then return nil end
    if not (Sources and Sources.QuerySpellInfo) then return nil end
    local info = Sources.QuerySpellInfo(spellID)
    if not info then return nil end
    local name = info.name
    if name == nil then return nil end
    _spellNameCache[spellID] = name
    return name
end

local _recentCastSpellByName = {}
local RECENT_CAST_ALIAS_TTL = 600

local function NormalizeSpellAliasName(name)
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    return string.lower(name)
end

local function GetSpellNameForAlias(spellID)
    if not spellID then return nil end
    local cached = GetCachedSpellName(spellID)
    if cached then return cached end
    if Sources and Sources.QuerySpellName then
        local name = Sources.QuerySpellName(spellID)
        if name and not (issecretvalue and issecretvalue(name)) then
            return name
        end
    end
    if not (Sources and Sources.QuerySpellInfo) then return nil end
    local info = Sources.QuerySpellInfo(spellID)
    local name = info and info.name
    if name and not (issecretvalue and issecretvalue(name)) then
        return name
    end
    return nil
end

RecordRecentPlayerSpellCast = function(spellID)
    if not spellID then return end
    local key = NormalizeSpellAliasName(GetSpellNameForAlias(spellID))
    if not key then return end
    _recentCastSpellByName[key] = {
        spellID = spellID,
        time = GetTime(),
    }
end

GetRecentCastAliasForEntry = function(entry)
    if not entry then return nil end
    local key = NormalizeSpellAliasName(entry.name)
    if not key then
        key = NormalizeSpellAliasName(GetSpellNameForAlias(entry.spellID or entry.overrideSpellID or entry.id))
    end
    local rec = key and _recentCastSpellByName[key]
    if not rec then return nil end
    if (GetTime() - (rec.time or 0)) > RECENT_CAST_ALIAS_TTL then
        _recentCastSpellByName[key] = nil
        return nil
    end
    return rec.spellID
end

-- Shared with cdm_spelldata.lua's ResolveOwnedEntry so harvested spell
-- entries (essential/utility/buff ownedSpells) and Composer-built custom
-- entries draw from the same cache.
ns._GetCachedSpellName = GetCachedSpellName

stackPolicy = ns.CDMIconStackPolicy and ns.CDMIconStackPolicy.Create({
    getSink = function()
        return ns.CDMIconStackText
    end,
    getSources = function()
        return Sources
    end,
    getAuraRuntime = function()
        return ns.CDMAuraRuntime
    end,
    getMirror = function()
        return ns.CDMBlizzMirror
    end,
    getCachedMirrorStateForIcon = function(icon)
        return GetCachedMirrorStateForIcon and GetCachedMirrorStateForIcon(icon) or nil
    end,
    refreshCachedMirrorStateForIcon = function(icon)
        return RefreshCachedMirrorStateForIcon and RefreshCachedMirrorStateForIcon(icon) or nil
    end,
    safeBoolean = SafeBoolean,
    isAuraEntry = IsAuraEntry,
    isBuiltinAuraContainerKey = IsBuiltinAuraContainerKey,
    isTotemSlotEntry = IsTotemSlotEntry,
    resolveAuraActiveState = function(entry)
        return ResolveAuraActiveState(entry)
    end,
    resolveMirrorIdentityState = function(entry)
        return Resolvers and Resolvers.ResolveBlizzardMirrorIdentityState
            and Resolvers.ResolveBlizzardMirrorIdentityState(entry)
            or nil
    end,
    getChargeMetadataDB = function()
        return GetChargeMetadataDB and GetChargeMetadataDB() or nil
    end,
    queryOverrideSpell = function(spellID)
        return QueryOverrideSpell and QueryOverrideSpell(spellID) or nil
    end,
    queryDisplayCount = function(spellID, owner)
        if QueryDisplayCount then
            return QueryDisplayCount(spellID, owner)
        end
        return nil
    end,
    querySpellCount = function(spellID, owner)
        if QuerySpellCount then
            return QuerySpellCount(spellID, owner)
        end
        return nil
    end,
    getEntryTexture = function(entry)
        return GetEntryTexture and GetEntryTexture(entry) or nil
    end,
    getAuraDataInstanceID = GetAuraDataInstanceID,
    getCachedSpellName = GetCachedSpellName,
    getTrackerSettings = function(viewerType)
        return GetTrackerSettings and GetTrackerSettings(viewerType) or nil
    end,
    debugStackText = function(icon, op, value, reason)
        return CDMIcons.DebugStackText(icon, op, value, reason)
    end,
    chargeDebug = ChargeDebug,
})

function _resolverRuntimePolicy.GetAuraApplicationsFromData(auraData, unit, source)
    if stackPolicy then
        return stackPolicy:GetAuraApplicationsFromData(auraData, unit, source)
    end
    return nil
end

function _resolverRuntimePolicy.TryAuraApplicationsBySpellID(auraID, source)
    if stackPolicy then
        return stackPolicy:TryAuraApplicationsBySpellID(auraID, source)
    end
    return nil
end

function _resolverRuntimePolicy.TryLinkedAuraApplications(linkedSpellIDs, entry, icon, seenIDs, source)
    if stackPolicy then
        return stackPolicy:TryLinkedAuraApplications(linkedSpellIDs, entry, icon, seenIDs, source)
    end
    return nil
end

function _resolverRuntimePolicy.GetSpellCountForEntry(spellID, entry, icon)
    if stackPolicy then
        return stackPolicy:GetSpellCountForEntry(spellID, entry, icon)
    end
    return nil
end

function _resolverRuntimePolicy.ResolveAuraApplicationsForEntry(spellID, entry, icon)
    if stackPolicy then
        return stackPolicy:ResolveAuraApplicationsForEntry(spellID, entry, icon)
    end
    return nil
end

GetAuraApplicationsForSpell = function(spellID, entryOrName, icon)
    if stackPolicy then
        return stackPolicy:GetAuraApplicationsForSpell(spellID, entryOrName, icon)
    end
    return nil
end

local function ApplyAuraCountText(icon, count, showZero, preserveWhenMissing)
    if stackPolicy then
        stackPolicy:ApplyAuraCountText(icon, count, showZero, preserveWhenMissing)
    end
end

---------------------------------------------------------------------------
-- CAST-BASED STALE STACK DETECTION — DISABLED
-- Previously listened for UNIT_SPELLCAST_SUCCEEDED to detect when stacks
-- drop to 0 (Blizzard may not call SetText/Hide on the viewer child).
-- Removed because the hook for the charge change fires BEFORE the cast
-- event in the same frame, making it impossible to distinguish "hook
-- confirmed new count" from "hook hasn't fired yet."  The 0.3s deferred
-- clear + apiOverride mechanism caused visible flicker after every
-- charge-consuming cast — both in and out of combat.
-- Stale stacks from zero-charge edge cases are now handled by the
-- ChargeCount Hide hook (which Blizzard does fire for most abilities)
-- and by the OOC API fallback in UpdateIconCooldown.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- BLIZZARD BUFF VISIBILITY
-- Buff icon visibility is driven by the rescan mechanism: aura events
-- trigger ScanCooldownViewer → LayoutContainer which rebuilds the icon
-- pool.  Icons start at alpha=1 on init; during normal gameplay the
-- update ticker mirrors the Blizzard child's alpha (multiplied by row
-- opacity).  During Edit Mode, icons stay at full visibility.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- CLICK-TO-CAST: Secure overlay button for CDM icons
-- Creates a SecureActionButtonTemplate child that receives clicks and
-- forwards them to the WoW secure action system.  The parent icon
-- stays as a plain Frame so layout/pooling remain taint-free.
---------------------------------------------------------------------------
local function SyncClickButtonFrameLevel(icon)
    if not icon or not icon.clickButton or not icon.TextOverlay then return end
    if InCombatLockdown() then return end
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
    if icon.GetFrameLevel then
        local baselineLevel = icon:GetFrameLevel() + TEXT_OVERLAY_FRAME_LEVEL_OFFSET
        if not requiredLevel or requiredLevel < baselineLevel then
            requiredLevel = baselineLevel
        end
    end

    if requiredLevel and icon.TextOverlay:GetFrameLevel() < requiredLevel then
        icon.TextOverlay:SetFrameLevel(requiredLevel)
    end

    SyncClickButtonFrameLevel(icon)
end

local function NormalizeIconFrameLevels(icon)
    if not icon then return end

    local parent = icon.GetParent and icon:GetParent()
    if parent and parent.GetFrameLevel and icon.GetFrameLevel and icon.SetFrameLevel then
        local requiredIconLevel = parent:GetFrameLevel() + ICON_FRAME_LEVEL_OFFSET
        if icon:GetFrameLevel() < requiredIconLevel then
            icon:SetFrameLevel(requiredIconLevel)
        end
    end

    if icon.Cooldown and icon.GetFrameLevel
        and icon.Cooldown.GetFrameLevel and icon.Cooldown.SetFrameLevel then
        local requiredCooldownLevel = icon:GetFrameLevel() + COOLDOWN_FRAME_LEVEL_OFFSET
        if icon.Cooldown:GetFrameLevel() < requiredCooldownLevel then
            icon.Cooldown:SetFrameLevel(requiredCooldownLevel)
        end
    end

    CDMIcons:EnsureTextOverlayLevel(icon)
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
        GameTooltip.Hide(GameTooltip)
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

-- Session cache: spellID → macroName or false. Invalidated on UPDATE_MACROS.
local _macroCache = {}
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "CDM_macroCache", tbl = _macroCache } end

local function InvalidateMacroCache()
    wipe(_macroCache)
end

local function FindMacroForSpell(spellID, overrideSpellID)
    if not spellID and not overrideSpellID then return nil end

    -- Check session cache (keyed on primary spellID)
    local cacheKey = spellID or overrideSpellID
    local cached = _macroCache[cacheKey]
    if cached ~= nil then return cached or nil end

    -- Build lowercase spell name set for matching
    local names = {}
    if spellID and Sources and Sources.QuerySpellInfo then
        local info = Sources.QuerySpellInfo(spellID)
        local name = info and info.name
        if type(name) == "string" then names[name:lower()] = true end
    end
    if overrideSpellID and overrideSpellID ~= spellID and Sources and Sources.QuerySpellInfo then
        local info = Sources.QuerySpellInfo(overrideSpellID)
        local name = info and info.name
        if type(name) == "string" then names[name:lower()] = true end
    end
    if not next(names) then
        _macroCache[cacheKey] = false
        return nil
    end

    -- Pass 1: GetMacroSpell (WoW-resolved tooltip spell ID)
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local macroName = GetMacroInfo(i)
        if macroName then
            local macroSpell = GetMacroSpell(i)
            if macroSpell and (macroSpell == spellID or macroSpell == overrideSpellID) then
                _macroCache[cacheKey] = macroName
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
                _macroCache[cacheKey] = macroName
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
                -- Skip if the macro's tooltip names a spell that's not in `names`.
                if (not tooltipSpell) or names[tooltipSpell] then
                    local lowerBody = body:lower()
                    for name in pairs(names) do
                        if lowerBody:find(name, 1, true) then
                            _macroCache[cacheKey] = macroName
                            return macroName
                        end
                    end
                end
            end
        end
    end
    _macroCache[cacheKey] = false
    return nil
end

---------------------------------------------------------------------------
-- SECURE ATTRIBUTE MANAGEMENT
-- Sets or clears the click-to-cast secure button attributes on a CDM icon.
---------------------------------------------------------------------------
UpdateIconSecureAttributes = function(icon, entry, viewerType)
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

    -- Built-in containers live at ncdm[viewerType]; custom bars live at
    -- ncdm.containers[viewerType]. GetTrackerSettings handles both.
    local viewerDB = GetTrackerSettings and GetTrackerSettings(viewerType)

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
    elseif entry.type == "trinket" or entry.type == "slot" then
        local itemID = entry.itemID
        if not itemID and Sources and Sources.QueryInventoryItemID then
            itemID = Sources.QueryInventoryItemID("player", entry.id)
        end
        if itemID then
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
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
        local itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
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
            local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(spellID)
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

local function RefreshItemIconVisuals(icon, entry, itemID)
    return itemVisualPolicy and itemVisualPolicy:RefreshItemVisuals(icon, entry, itemID) or false
end

local function RefreshInventoryItemVisuals(icon, entry, itemID)
    return itemVisualPolicy and itemVisualPolicy:RefreshInventoryItemVisuals(icon, entry, itemID) or false
end

---------------------------------------------------------------------------
-- ICON CONFIGURATION
-- Applies size, border, zoom, texcoord, text styling to an icon.
---------------------------------------------------------------------------
local BLIZZ_ICON_CHROME_ATLASES = {
    ["UI-HUD-CoolDownManager-IconOverlay"] = true,
    ["UI-CooldownManager-OORshadow"] = true,
}

local function IsIconChromeTexture(region)
    if not (region and region.GetAtlas) then return false end
    local atlas = region:GetAtlas()
    return atlas and BLIZZ_ICON_CHROME_ATLASES[atlas] or false
end

local function BuildTexCoord(zoom, aspectRatioCrop)
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

    return left, right, top, bottom
end

local function ApplyTexCoordToTexture(texture, left, right, top, bottom)
    if not (texture and texture.SetTexCoord) then return end
    if IsIconChromeTexture(texture) then return end
    texture.SetTexCoord(texture, left, right, top, bottom)
end

local function ApplyTexCoordToTarget(target, left, right, top, bottom, visited)
    if not target then return end
    visited = visited or {}
    if visited[target] then return end
    visited[target] = true

    local objType
    if target.GetObjectType then
        objType = target:GetObjectType()
    end
    if objType == "Texture" then
        ApplyTexCoordToTexture(target, left, right, top, bottom)
        return
    end

    if target.Icon and target.Icon ~= target then
        ApplyTexCoordToTarget(target.Icon, left, right, top, bottom, visited)
    end
    if target.IconTexture and target.IconTexture ~= target then
        ApplyTexCoordToTarget(target.IconTexture, left, right, top, bottom, visited)
    end
    if target.Texture and target.Texture ~= target then
        ApplyTexCoordToTarget(target.Texture, left, right, top, bottom, visited)
    end

    if target.GetRegions then
        local regions = { target:GetRegions() }
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                ApplyTexCoordToTexture(region, left, right, top, bottom)
            end
        end
    end

    if target.GetChildren then
        local children = { target:GetChildren() }
        for _, child in ipairs(children) do
            local childType
            if child and child.GetObjectType then
                childType = child:GetObjectType()
            end
            if childType ~= "Cooldown" then
                ApplyTexCoordToTarget(child, left, right, top, bottom, visited)
            end
        end
    end
end

local function ApplyTexCoord(icon, zoom, aspectRatioCrop)
    if not icon then return end
    local left, right, top, bottom = BuildTexCoord(zoom, aspectRatioCrop)

    ApplyTexCoordToTarget(icon.Icon, left, right, top, bottom)
end

local function ConfigureIcon(icon, rowConfig)
    if not icon or not rowConfig then return end
    icon._rowConfig = rowConfig

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
    NormalizeIconFrameLevels(icon)

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
    local durationFont = generalFont
    local stackFont = generalFont
    if LSM and rowConfig.durationFont and rowConfig.durationFont ~= "" then
        durationFont = LSM:Fetch("font", rowConfig.durationFont) or durationFont
    end
    if LSM and rowConfig.stackFont and rowConfig.stackFont ~= "" then
        stackFont = LSM:Fetch("font", rowConfig.stackFont) or stackFont
    end

    local durationSize = rowConfig.durationSize or 14
    local hideDurationText = rowConfig.hideDurationText
    if durationSize > 0 and not hideDurationText then
        local dtc = rowConfig.durationTextColor or {1, 1, 1, 1}
        local dAnchor = rowConfig.durationAnchor or "CENTER"
        local dox = rowConfig.durationOffsetX or 0
        local doy = rowConfig.durationOffsetY or 0

        -- Helper: style any FontString regions inside a Cooldown frame.
        -- Blizzard-mirrored icons use QUI's native icon.Cooldown.
        local function styleDurationFontString(region)
            if not (region and region.GetObjectType and region:GetObjectType() == "FontString") then return end
            region:SetFont(durationFont, durationSize, generalOutline)
            region:SetTextColor(dtc[1], dtc[2], dtc[3], dtc[4] or 1)
            region:Show()

;(function()
                region:ClearAllPoints()
                region:SetPoint(dAnchor, icon, dAnchor, dox, doy)
                region:SetDrawLayer("OVERLAY", 7)
            end)()
        end

        local function styleCDFontStrings(cd)
            if not cd then return end
            if cd.SetHideCountdownNumbers then
                cd.SetHideCountdownNumbers(cd, false)
            end
            local regions = { cd:GetRegions() }
            for _, region in ipairs(regions) do
                styleDurationFontString(region)
            end
        end

        -- Style QUI's native cooldown text
        styleCDFontStrings(icon.Cooldown)

        -- Also style our DurationText
        icon.DurationText:SetFont(durationFont, durationSize, generalOutline)
        icon.DurationText:SetTextColor(dtc[1], dtc[2], dtc[3], dtc[4] or 1)
        icon.DurationText:ClearAllPoints()
        icon.DurationText:SetPoint(dAnchor, icon, dAnchor, dox, doy)
        icon.DurationText:Show()
    elseif hideDurationText then
        -- Helper: hide FontStrings inside a Cooldown frame
        local function hideDurationFontString(region)
            if region and region.GetObjectType
               and region:GetObjectType() == "FontString"
               and region.Hide then
                region:Hide()
            end
        end

        local function hideCDFontStrings(cd)
            if not cd then return end
            if cd.SetHideCountdownNumbers then
                cd.SetHideCountdownNumbers(cd, true)
            end
            local regions = { cd:GetRegions() }
            for _, region in ipairs(regions) do
                hideDurationFontString(region)
            end
        end
        hideCDFontStrings(icon.Cooldown)
        icon.DurationText:Hide()
    end

    -- Stack text styling
    local stackSize = rowConfig.stackSize or 14
    local hideStackText = rowConfig.hideStackText
    if stackSize > 0 and not hideStackText then
        local stc = rowConfig.stackTextColor or {1, 1, 1, 1}
        local sAnchor = rowConfig.stackAnchor or "BOTTOMRIGHT"
        local sox = rowConfig.stackOffsetX or 0
        local soy = rowConfig.stackOffsetY or 0

        icon.StackText:SetFont(stackFont, stackSize, generalOutline)
        icon.StackText:SetTextColor(stc[1], stc[2], stc[3], stc[4] or 1)
        icon.StackText:ClearAllPoints()
        icon.StackText:SetPoint(sAnchor, icon, sAnchor, sox, soy)
        icon.StackText:SetDrawLayer("OVERLAY", 7)

    elseif hideStackText then
        icon.StackText:Hide()
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

        -- hideDurationText: per-spell duration text visibility override.
        -- true  → force-hide on this spell only
        -- false → force-show (overrides a row-level Hide Duration Text)
        -- nil   → inherit row default
        if spellOvr.hideDurationText == true then
            local function hideDurationForCooldown(cd)
                if not cd then return end
                if cd.SetHideCountdownNumbers then
                    cd.SetHideCountdownNumbers(cd, true)
                end
                local regions = { cd:GetRegions() }
                for _, region in ipairs(regions) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        region:Hide()
                    end
                end
            end
            hideDurationForCooldown(icon.Cooldown)
            icon.DurationText:Hide()
        elseif spellOvr.hideDurationText == false then
            if icon.Cooldown and icon.Cooldown.SetHideCountdownNumbers then
                icon.Cooldown.SetHideCountdownNumbers(icon.Cooldown, false)
            end
            icon.DurationText:Show()
        end

        -- customBorderColor: per-spell border color override
        if spellOvr.customBorderColor and icon.Border and icon.Border:IsShown() then
            local bc = spellOvr.customBorderColor
            icon.Border:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
        end

        -- desaturate: cache for UpdateIconCooldown to use per-icon
        icon._spellOverrideDesaturate = spellOvr.desaturate

        -- desaturateIgnoreAura: when true, aura-active state does not suppress
        -- cooldown desaturation — the icon desaturates based on charge/CD state
        -- even while the spell's debuff/buff is ticking on the target.
        icon._desaturateIgnoreAura = spellOvr.desaturateIgnoreAura or nil
    else
        icon._spellOverrideDesaturate = nil
        icon._desaturateIgnoreAura = nil
    end

    SyncCooldownBling(icon)
end

---------------------------------------------------------------------------
-- COOLDOWN UPDATE
-- Update cooldown state for a single icon.
---------------------------------------------------------------------------
function GetTrackerSettings(viewerType)
    if Shared and Shared.GetContainerDB then
        local containerDB = Shared.GetContainerDB(viewerType)
        if containerDB then return containerDB end
    end

    local db = GetDB()
    if not db or not viewerType then return nil end
    if db[viewerType] then return db[viewerType] end
    return db.containers and db.containers[viewerType] or nil
end

customBarPolicy = ns.CDMIconCustomBarPolicy and ns.CDMIconCustomBarPolicy.Create({
    getSources = function()
        return Sources
    end,
    getSpellData = function()
        return ns.CDMSpellData
    end,
    getGlowLib = function()
        return LCG
    end,
    getTime = function()
        return GetTime()
    end,
    getTrackerSettings = function(viewerType)
        return GetTrackerSettings and GetTrackerSettings(viewerType) or nil
    end,
    isCustomBarContainer = IsCustomBarContainer,
    getCustomBarVisibilityMode = GetCustomBarVisibilityMode,
    resolveMacro = function(entry)
        return ResolveMacro(entry)
    end,
    resolveSpellActiveState = function(spellID, icon, entry)
        return Resolvers and Resolvers.ResolveSpellActiveState
            and Resolvers.ResolveSpellActiveState(spellID, icon, entry)
            or false
    end,
    resolveCooldownActivityState = function(icon, entry, containerDB, now)
        return _resolverRuntimePolicy.ResolveIconCooldownActivityState(icon, entry, containerDB, now)
    end,
    reapplySwipeStyle = function(cooldown, icon)
        return ReapplySwipeStyle(cooldown, icon)
    end,
    isPlayerInCombat = function()
        return UnitAffectingCombat and UnitAffectingCombat("player") or false
    end,
    debugIconEvent = function(...)
        return CDMIcons.DebugIconEvent and CDMIcons.DebugIconEvent(...)
    end,
    after = function(delay, callback)
        if C_Timer and C_Timer.After then
            return C_Timer.After(delay, callback)
        end
        callback()
    end,
})

function _resolverRuntimePolicy.ResolveItemActiveState(itemID, icon, entry)
    return customBarPolicy
        and customBarPolicy:ResolveItemActiveState(itemID, icon, entry)
        or false
end

function _resolverRuntimePolicy.CooldownHasVisualPriority(icon, entry, containerDB, now)
    return customBarPolicy
        and customBarPolicy:CooldownHasVisualPriority(icon, entry, containerDB, now)
        or false
end

function _resolverRuntimePolicy.ResolveCustomBarActiveState(entry, icon, now)
    return customBarPolicy
        and customBarPolicy:ResolveActiveState(entry, icon, now)
        or false
end

function _resolverRuntimePolicy.ResolveCustomBarCooldownState(entry, icon, containerDB, now)
    return customBarPolicy
        and customBarPolicy:ResolveCooldownState(entry, icon, containerDB, now)
        or nil
end

function _resolverRuntimePolicy.ResolveCustomBarUsability(entry, containerDB, cooldownState)
    return not customBarPolicy
        or customBarPolicy:ResolveUsability(entry, containerDB, cooldownState)
end

function _resolverRuntimePolicy.ComputeCustomBarVisibility(icon, entry, containerDB, now)
    return customBarPolicy
        and customBarPolicy:ComputeVisibility(icon, entry, containerDB, now)
        or {
            baseVisible = true,
            layoutVisible = true,
            renderVisible = true,
            isActive = false,
            isUsable = true,
            isOnCooldown = false,
            rechargeActive = false,
            hasChargesRemaining = false,
            visibilityMode = "always",
        }
end

function _resolverRuntimePolicy.StartCustomBarActiveGlow(icon, containerDB)
    if customBarPolicy then
        customBarPolicy:StartActiveGlow(icon, containerDB)
    end
end

function _resolverRuntimePolicy.StopCustomBarActiveGlow(icon)
    if customBarPolicy then
        customBarPolicy:StopActiveGlow(icon)
    end
end

function _resolverRuntimePolicy.ApplyCustomBarSwipeStyle(icon, containerDB, cooldownState)
    if customBarPolicy then
        customBarPolicy:ApplySwipeStyle(icon, containerDB, cooldownState)
    end
end

function _resolverRuntimePolicy.ApplyCustomBarActiveState(icon, entry, containerDB)
    if customBarPolicy then
        customBarPolicy:ApplyActiveState(icon, entry, containerDB)
    end
end

function _resolverRuntimePolicy.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
    if customBarPolicy then
        customBarPolicy:ApplyActiveGlow(icon, containerDB, visibility)
    end
end

function _resolverRuntimePolicy.ShouldHideIconStackText(icon, containerDB)
    return stackPolicy and stackPolicy:ShouldHideIconStackText(icon, containerDB) or false
end

-- CDMIcons.DebugStackText is rebound by the load-on-demand debug addon.

function _resolverRuntimePolicy.ShowIconStackText(icon, value, containerDB, reason)
    if stackPolicy then
        stackPolicy:ShowIconStackText(icon, value, containerDB, reason)
    end
end

function _resolverRuntimePolicy.HideIconStackText(icon, reason)
    if stackPolicy then
        stackPolicy:HideIconStackText(icon, reason)
    end
end

local function GetRefreshBatchTime()
    if refreshBatch then
        return refreshBatch:GetTime()
    end
    return GetTime and GetTime() or 0
end

-- _showGCDSwipe is hoisted once per batch from swipe module settings.
-- When true, GCD-only cooldowns are allowed through to the CooldownFrame
-- instead of being cleared, so the GCD swipe animation can render.
local _showGCDSwipe = false
-- _showBuffSwipe is hoisted once per batch from swipe module settings.
-- _showCooldownIconAuraPhase controls whether cooldown-kind icons can enter
-- aura phase before charge/cooldown phase.
local _showBuffSwipe = true
local _showCooldownIconAuraPhase = true

function _resolverRuntimePolicy.RefreshSwipeBatchSettings()
    local swipeMod = ns._OwnedSwipe
    local swipeSettings = swipeMod and swipeMod.GetSettings and swipeMod.GetSettings()
    _showGCDSwipe = swipeSettings and swipeSettings.showGCDSwipe or false
    _showBuffSwipe = swipeSettings and (swipeSettings.showBuffSwipe ~= false) or false
    if swipeSettings then
        _showCooldownIconAuraPhase = swipeSettings.showCooldownIconAuraPhase ~= false
    else
        _showCooldownIconAuraPhase = true
    end
end

function _resolverRuntimePolicy.ShouldSkipAuraPhaseForCooldownIcon(icon, entry)
    if not entry then return false end
    if IsAuraEntry(entry) then return false end
    return _showCooldownIconAuraPhase == false
end

function _resolverRuntimePolicy.ShouldUseBuffSwipeForIcon(icon, entry)
    if not entry then return false end
    if not _showBuffSwipe then return false end
    if _resolverRuntimePolicy.ShouldSkipAuraPhaseForCooldownIcon(icon, entry) then
        return false
    end
    local settings = ResolveTrackerSettingsNow(entry and entry.viewerType)
    if settings and settings.showOnlyOnCooldown == true then
        return false
    end
    if IsCustomBarContainer(settings) then
        if settings.showActiveState == false then
            return false
        end
    end
    return true
end

function _resolverRuntimePolicy.ResolveIconCooldownActivityState(icon, entry, containerDB, now)
    local runtimeStore = ns.CDMRuntimeStore
    local storedState = runtimeStore and runtimeStore.GetFrameState
        and runtimeStore.GetFrameState(icon)
    local fromResolved = storedState
        and Resolvers
        and Resolvers.ResolveCooldownActivityStateFromResolvedState
        and Resolvers.ResolveCooldownActivityStateFromResolvedState(entry, storedState)
    if fromResolved then
        return fromResolved
    end

    local resolver = Resolvers and Resolvers.ResolveCooldownActivityState
    if not resolver then return nil end
    local options = _resolverRuntimePolicy
    options.useBuffSwipe = _resolverRuntimePolicy.ShouldUseBuffSwipeForIcon(icon, entry)
    options.skipAuraPhase = _resolverRuntimePolicy.ShouldSkipAuraPhaseForCooldownIcon(icon, entry)
    options.showGCDSwipe = IsGCDSwipeEnabled()
    return resolver(icon, entry, containerDB, now, options)
end

function _resolverRuntimePolicy.ApplyMirrorStackText(icon, mirrorState, showZero)
    return stackPolicy and stackPolicy:ApplyMirrorStackText(icon, mirrorState, showZero) or false
end

function _resolverRuntimePolicy.DebugBlizzSyncSnapshot(enabled, icon, entry, mirrorState, resolvedState,
                                                       active, mirrorActive, fallbackFoundAura,
                                                       durObj, durObjSource)
    if not enabled or not icon then return end

    local function debugSafeShown(frame)
        if frame and frame.IsShown then
            return frame:IsShown() and true or false
        end
        return nil
    end

    local function debugSafeAlpha(frame)
        if frame and frame.GetAlpha then
            return frame:GetAlpha()
        end
        return nil
    end

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
        tostring(debugSafeShown(icon)),
        tostring(debugSafeAlpha(icon)),
    }, "|")

    if icon._lastBlizzSyncTraceSig == signature then return end
    icon._lastBlizzSyncTraceSig = signature

    CDMIcons._DebugBlizzEntry(enabled, entry, "state-sync-trace",
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
        "hostShown=", tostring(debugSafeShown(icon)),
        "hostAlpha=", tostring(debugSafeAlpha(icon)),
        CDMIcons._FormatMirrorState(mirrorState))
end

function _resolverRuntimePolicy.SyncBlizzMirrorIconState(icon)
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
        debugBlizz = CDMIcons._ShouldDebugBlizzEntry(entry, {
            runtimeSid,
            entry.spellID,
            entry.overrideSpellID,
            entry.id,
        })
    end

    local m = GetCachedMirrorStateForIcon(icon)
    if not m then
        m = RefreshCachedMirrorStateForIcon(icon)
    end
    if not m then
        if debugBlizz then
            CDMIcons._DebugBlizzEntry(debugBlizz, entry, "state-sync-missing", "cdID=", tostring(cooldownID))
        end
        return false
    end

    local isAuraBacked = IsAuraEntry(entry)
        or m.viewerCategory == "buff"
        or m.viewerCategory == "trackedBar"
    if not isAuraBacked then
        if debugBlizz then
            CDMIcons._DebugBlizzEntry(debugBlizz, entry, "state-sync-skip-cooldown", CDMIcons._FormatMirrorState(m))
        end
        return false
    end

    local r = runtimeSid and _resolverRuntimePolicy.ResolveAuraFactsForIcon(icon, entry, runtimeSid, true) or nil

    -- Mirror is authoritative for Blizzard-mirrored icons. `m` is the mirror
    -- state for the exact cdID this icon is bound to.
    -- Resolved aura facts can still come from a different cdID when
    -- spellID->cdID maps collide. Trusting them for this icon's display
    -- would let an unrelated aura's state, including its durObj, leak onto
    -- this icon. Use the exact mirror state for rendering.
    local mirrorActive = (m.auraInstanceID and true or false)
        or SafeBoolean(m.childIsActive) == true
        or (m.totemSlot and true or false)
        or (m.auraDurObj and true or false)
        or (m.totemDurObj and true or false)
    local auraUnit = (m.selfAura == false) and "target" or "player"

    local mirrorMod = ns.CDMBlizzMirror
    if _G.QUI_CDM_TAINT_DEBUG and mirrorMod and mirrorMod.TaintLog then
        mirrorMod.TaintLog("Sync.in",
            "cdID", cooldownID,
            "runtimeSid", runtimeSid,
            "m.childIsActive", m.childIsActive,
            "m.selfAura", m.selfAura,
            "m.hasAura", m.hasAura,
            "m.spellID", m.spellID,
            "m.overrideTooltipSpellID", m.overrideTooltipSpellID,
            "m.auraDurObj", m.auraDurObj,
            "m.hasAuraInstanceID", m.hasAuraInstanceID,
            "m.auraUnit", m.auraUnit,
            "r.isActive", r and r.isActive,
            "r.auraActive", r and r.auraActive,
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
    -- fallback. Icon sync is a pure consumer: if no aura duration is known,
    -- render the active aura without a swipe and wait for the next stamp.
    local durObj = m.auraDurObj
    local durObjSource = durObj and (m.auraDurObjSource or "mirror") or nil
    local fallbackFoundAura = false
    local fallbackInstID

    -- Activeness is "is the aura on the unit", NOT "do we have a swipe
    -- duration". A durationless aura (form, stance, permanent buff) is
    -- active without a durObj, so the icon should display without a countdown.
    local active = mirrorActive or fallbackFoundAura or (durObj and true or false)
    _resolverRuntimePolicy.DebugBlizzSyncSnapshot(debugBlizz, icon, entry, m, r, active, mirrorActive,
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

    local mirrorStackApplied = _resolverRuntimePolicy.ApplyMirrorStackText(icon, m, entry.hasCharges)
    if active then
        if not mirrorStackApplied and SafeBoolean(m.stackTextShown) == false then
            ClearIconStackText(icon)
            icon._lastMirrorStackTextEpoch = m.stackTextEpoch
        elseif not mirrorStackApplied
            and IsAuraEntry(entry)
            and _resolverRuntimePolicy.ResolvedAuraStateIsActive(r) and not r.isTotemInstance then
            local preserveMissingCount = InCombatLockdown()
            ApplyAuraCountText(icon, r.count, entry.hasCharges, preserveMissingCount)
            icon._lastMirrorStackTextEpoch = m.stackTextEpoch
        elseif not mirrorStackApplied and not InCombatLockdown() then
            ClearIconStackText(icon)
        end
    else
        if not mirrorStackApplied then
            ClearIconStackText(icon)
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
       and _resolverRuntimePolicy.RequestBuffIconLayoutRefresh then
        _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    end
    local durationSourceChanged = priorSrcCat ~= newSrcCat
        or priorSrcCDID ~= newSrcCDID
        or priorSrcEpoch ~= newSrcEpoch
        or priorHadAuraDurObj ~= (durObj and true or false)
    if debugBlizz and (priorActive ~= active or priorEpoch ~= epoch or durationSourceChanged) then
        CDMIcons._DebugBlizzEntry(debugBlizz, entry, "state-sync",
            CDMIcons._FormatMirrorState(m),
            "runtimeSid=", tostring(runtimeSid),
            "durObjSource=", tostring(durObjSource),
            "fallbackInstID=", tostring(fallbackInstID),
            "source=", tostring(icon._lastAuraSourceID),
            "durationSourceChanged=", tostring(durationSourceChanged))
    end
    return priorActive ~= active or priorEpoch ~= epoch or durationSourceChanged
end

-- Set an item-type icon to the inactive state without consulting the
-- use-cooldown resolver. Symmetric to ClearItemBarInactive in
-- cdm_bar_renderer.lua. Called when kind="aura" (built-in buff/trackedBar
-- containers) or displayMode="auraOnly" (custom containers) and the item's
-- buff is not currently active.
local function ClearItemIconInactive(icon, entry, itemID)
    ClearAuraStateForIcon(icon, entry)
    icon._resolvedCooldownMode = "inactive"
    icon._hasCooldownActive = false
    icon._hasRealCooldownActive = false
    ApplyCooldownDesaturation(icon, entry, nil, "inactive")
    _resolverRuntimePolicy.StoreIconRuntimeState(
        icon, "inactive", nil,
        itemID or (entry and (entry.id or entry.spellID)),
        nil, nil, nil, false, false, false, false, false,
        false, nil, nil)
end

local function UpdateIconCooldownOwned(icon)
    if not icon or not icon._spellEntry then return end
    -- Blizzard-mirrored aura icons render with QUI-native widgets from the
    -- exact cID mirror. The Blizzard child stays in its own viewer.
    if icon._blizzMirrorCooldownID and IsAuraEntry(icon._spellEntry) then
        local entry = icon._spellEntry
        local refreshSwipe = _resolverRuntimePolicy.SyncBlizzMirrorIconState(icon)
        local resolvedSwipe = ApplySyncedMirrorAuraCooldown(icon, entry) == true
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
    local auraCountAppliedThisTick = false
    local preResolvedCooldownState = nil

    -- Runtime override: resolve from the base spell each tick so dynamic
    -- transforms are always current. Shared across all paths in this function.
    local _runtimeSid = entry.spellID or entry.overrideSpellID or entry.id
    if _runtimeSid and not IsAuraEntry(entry) then
        local ovId = QueryOverrideSpell(_runtimeSid)
        if ovId then _runtimeSid = ovId end
    end
    icon._runtimeSpellID = _runtimeSid

    local macroResolvedID, macroResolvedType, macroFallbackTex
    if entry.type == "macro" then
        macroResolvedID, macroResolvedType, macroFallbackTex = ResolveMacro(entry)
        if macroResolvedID and macroResolvedType == "spell" then
            _runtimeSid = macroResolvedID
            icon._runtimeSpellID = macroResolvedID
        end
    end

    do
        if IsAuraEntry(entry) then
            local auraSpellID = _runtimeSid
            if not auraSpellID then
                return
            end

            local r = _resolverRuntimePolicy.ResolveAuraFactsForIcon(icon, entry, auraSpellID, true)
            if not r then
                -- For item-type entries with kind="aura" (items placed in
                -- built-in buff/trackedBar containers), the aura-facts
                -- resolver returns nil when the item's buff is not active.
                -- Explicitly store the inactive state so the icon correctly
                -- reflects that the buff is absent rather than silently
                -- keeping whatever state it last had.
                if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then
                    local _auraNilItemID
                    if entry.type == "slot" or entry.type == "trinket" then
                        _auraNilItemID = Sources and Sources.QueryInventoryItemID
                            and Sources.QueryInventoryItemID("player", entry.id)
                    else
                        _auraNilItemID = (Sources and Sources.QueryBestOwnedItemVariant
                            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
                    end
                    ClearItemIconInactive(icon, entry, _auraNilItemID)
                end
                return
            end
            icon._totemSlot = entry._totemSlot or nil

            if _resolverRuntimePolicy.ResolvedAuraStateIsActive(r) then
                ApplyAuraStateToIcon(icon, entry, auraSpellID, r)

                if r.isTotemInstance then
                    ClearIconStackText(icon)
                else
                    ApplyAuraCountText(icon, r.count, entry.hasCharges, InCombatLockdown())
                end

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
                    if not mirrored and not r.isTotemInstance then
                        local auraIcon = r.auraData and r.auraData.icon
                        if auraIcon then
                            icon._desiredTexture = nil
                            icon.Icon.SetTexture(icon.Icon, auraIcon)
                            icon._lastTexture = nil
                            mirrored = true
                        end
                        if not mirrored then
                            local texID = GetSpellTexture(r.resolvedAuraSpellID or auraSpellID)
                            if texID and texID ~= icon._lastTexture then
                                icon.Icon:SetTexture(texID)
                                icon._lastTexture = texID
                            end
                        end
                    end
                end

                ApplyResolvedCooldown(icon, r)
                ReapplySwipeStyle(icon.Cooldown, icon)
                return
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

                ClearIconStackText(icon)
                if wasAuraActive then
                    ApplyResolvedCooldown(icon, r)
                end
                return
            end
        end
    end

    if entry.type == "macro" then
        local newTex
        if macroResolvedID then
            if macroResolvedType == "item" then
                newTex = QueryItemVisualTexture(macroResolvedID)
            else
                newTex = GetSpellTexture(macroResolvedID)
            end
        else
            newTex = macroFallbackTex
        end
        if newTex and icon.Icon and newTex ~= icon._lastTexture then
            icon.Icon:SetTexture(newTex)
            icon._lastTexture = newTex
            UpdateIconProfessionQuality(icon)
        end
    elseif entry.type == "trinket" or entry.type == "slot" then
        local slotID = entry.id
        local itemID
        if Sources and Sources.QueryInventoryItemID then
            itemID = Sources.QueryInventoryItemID("player", slotID)
        end
        if itemID and icon.Icon then
            RefreshInventoryItemVisuals(icon, entry, itemID)
        end
        if stackTextWritesAllowed then
            _resolverRuntimePolicy.HideIconStackText(icon, "slot-clear")
        end
    elseif entry.type == "item" then
        local itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
        RefreshItemIconVisuals(icon, entry, itemID)
        if stackTextWritesAllowed and Sources and Sources.QueryItemCount then
            local containerDB = GetTrackerSettings(entry.viewerType)
            local includeUses = containerDB and containerDB.showItemCharges == true
            local count = Sources.QueryItemCount(itemID, false, includeUses, true)
            if count then
                local stackColor = icon._rowConfig and icon._rowConfig.stackTextColor or {1, 1, 1, 1}
                local numericCount = count or 0
                if numericCount > 1 then
                    if icon.StackText.SetTextColor then
                        icon.StackText:SetTextColor(stackColor[1], stackColor[2], stackColor[3], stackColor[4] or 1)
                    end
                    _resolverRuntimePolicy.ShowIconStackText(icon, tostring(numericCount), containerDB, "item-count")
                elseif numericCount == 1 then
                    _resolverRuntimePolicy.HideIconStackText(icon, "item-count-one")
                else
                    if icon.StackText.SetTextColor then
                        icon.StackText:SetTextColor((stackColor[1] or 1) * 0.5, (stackColor[2] or 1) * 0.5, (stackColor[3] or 1) * 0.5, stackColor[4] or 1)
                    end
                    _resolverRuntimePolicy.ShowIconStackText(icon, "0", containerDB, "item-count-zero")
                end
            else
                _resolverRuntimePolicy.ShowIconStackText(icon, "0", containerDB, "item-count-fallback")
            end
        end
    else
        local _chargedAuraActive = false
        local _chargedTotemTexture = nil
        local useBuffSwipe = _resolverRuntimePolicy.ShouldUseBuffSwipeForIcon(icon, entry)
        if useBuffSwipe then
            local _cBaseID = _runtimeSid
            local r = _resolverRuntimePolicy.ResolveAuraFactsForIcon(icon, entry, _cBaseID, true)
            preResolvedCooldownState = r
            if _resolverRuntimePolicy.ResolvedAuraStateIsActive(r) then
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
                if icon.Cooldown and r.durObj then
                    _chargedAuraActive = true
                    ReapplySwipeStyle(icon.Cooldown, icon)
                end
                local mirrorStackHasState = false
                if icon._blizzMirrorCooldownID and _resolverRuntimePolicy.ResolveMirrorStackText then
                    local _, _, _, _, mirrorHasState =
                        _resolverRuntimePolicy.ResolveMirrorStackText(icon)
                    mirrorStackHasState = mirrorHasState == true
                end
                if not entry.hasCharges and not IsTotemSlotEntry(entry) and not mirrorStackHasState then
                    local count = r.count
                    auraCountAppliedThisTick = count and count.shown == true or false
                    ApplyAuraCountText(icon, r.count, false, InCombatLockdown())
                end
            elseif r then
                local wasAuraActive = icon._auraActive
                ApplyAuraStateToIcon(icon, entry, _cBaseID, r)
                if wasAuraActive and icon.Cooldown then
                    ReapplySwipeStyle(icon.Cooldown, icon)
                end
            end
        elseif icon._auraActive then
            ClearAuraStateForIcon(icon, entry)
            if icon.Cooldown then ReapplySwipeStyle(icon.Cooldown, icon) end
        end

        if icon.Icon and _chargedAuraActive and _chargedTotemTexture then
            icon._desiredTexture = nil
            icon.Icon.SetTexture(icon.Icon, _chargedTotemTexture)
            icon._lastTexture = _chargedTotemTexture
        elseif icon.Icon and not entry.isAura then
            local texID = GetSpellTexture(_runtimeSid)
            if texID and icon._desiredTexture ~= texID then
                icon._desiredTexture = texID
                icon.Icon.SetTexture(icon.Icon, texID)
            end
        elseif icon.Icon then
            icon._desiredTexture = nil
        end
    end

    -- For aura-kind entries (items in built-in buff/trackedBar containers)
    -- and for entries with displayMode="auraOnly" (custom containers, item
    -- types only), do NOT fall through to the cooldown resolver when the
    -- item's buff is inactive — go inactive instead.
    -- Mirrors UpdateItemBarCooldown's ClearItemBarInactive gate in
    -- cdm_bar_renderer.lua.
    if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then
        local _coerceItemID
        if entry.type == "slot" or entry.type == "trinket" then
            _coerceItemID = Sources and Sources.QueryInventoryItemID
                and Sources.QueryInventoryItemID("player", entry.id)
        else
            _coerceItemID = (Sources and Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
        end
        local _isAuraKind = entry.kind == "aura"
        local _coerceContainerDB = GetTrackerSettings(entry.viewerType)
        local _isCustom = IsCustomBarContainer(_coerceContainerDB)
        local _isAuraOnlyOverride = _isCustom
            and entry.displayMode == "auraOnly"
        if _isAuraKind or _isAuraOnlyOverride then
            -- Check whether the item's buff is currently active.
            local _auraIsActive = false
            if Sources and Sources.QueryScannedItemAuraInfo and _coerceItemID then
                local scanned = Sources.QueryScannedItemAuraInfo(_coerceItemID)
                if scanned and scanned.active == true then
                    local readableDuration = type(scanned.duration) == "number"
                        and scanned.duration or nil
                    local readableExpiration = type(scanned.expiration) == "number"
                        and scanned.expiration or nil
                    if readableDuration and readableDuration > 0
                       and readableExpiration
                       and (readableExpiration - GetTime()) > 0 then
                        _auraIsActive = true
                    end
                end
            end
            if not _auraIsActive then
                ClearItemIconInactive(icon, entry, _coerceItemID)
                return
            end
        end
    end

    local resolvedApplied = ApplyResolvedCooldown(icon, preResolvedCooldownState) == true
    local resolvedState = ns.CDMRuntimeStore and ns.CDMRuntimeStore.GetFrameState
        and ns.CDMRuntimeStore.GetFrameState(icon) or nil
    local startTime = resolvedState and resolvedState.start
    local duration = resolvedState and resolvedState.duration
    local durObj = resolvedState and resolvedState.durObj
    local resolvedMode = resolvedState and resolvedState.mode or icon._resolvedCooldownMode
    local resolvedActive = resolvedState and resolvedState.active == true
        or icon._hasCooldownActive == true
    local runtimeHasCharges = entry.hasCharges == true
        or (resolvedState and resolvedState.hasCharges == true)

    if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
        CDMIcons.DebugIconEvent(icon, "resolve",
            "sid=", tostring(_runtimeSid),
            "mode=", tostring(resolvedMode),
            "start=", tostring(startTime),
            "duration=", tostring(duration),
            "durObj=", durObj and "yes" or "no",
            "active=", tostring(resolvedActive),
            "isOnGCD=", tostring(icon._isOnGCD),
            "hasCharges=", tostring(runtimeHasCharges),
            "entryHasCharges=", tostring(entry.hasCharges),
            "kind=", tostring(entry.kind),
            "type=", tostring(entry.type))
    end

    local hasSafeStart = IsSafeNumeric(startTime)
    local hasSafeDuration = IsSafeNumeric(duration)
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
    if not startTime and not duration then
        icon._lastStart = 0
        icon._lastDuration = 0
    end

    if icon.Cooldown then
        local realCooldownActive = icon._hasCooldownActive == true
            and _resolverRuntimePolicy.IsRealCooldownDurationMode(resolvedMode)
        local trustIsOnGCD = ResolverRuntime.IsTrustingGCDForBatch()
        local gcdStateTrusted = trustIsOnGCD
            and icon._isOnGCDTrustedAt == ResolverRuntime.GetTrustedGCDStamp()
        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
            CDMIcons.DebugIconEvent(icon, "classify",
                "real=", tostring(realCooldownActive),
                "gcdOnly=", tostring(resolvedMode == "gcd-only"),
                "gcdTrusted=", tostring(trustIsOnGCD),
                "gcdSnapshot=", tostring(gcdStateTrusted),
                "resolvedActive=", tostring(resolvedActive),
                "durObj=", durObj and "yes" or "no")
        end

        local prevGCD = icon._wasShowingGCDSwipe or false
        local curGCD = icon._showingGCDSwipe or false
        local prevActive = icon._wasResolvedCooldownActive
        local curActive = icon._hasCooldownActive == true
        if resolvedApplied or prevGCD ~= curGCD or prevActive ~= curActive then
            icon._wasShowingGCDSwipe = curGCD
            icon._wasResolvedCooldownActive = curActive
            ReapplySwipeStyle(icon.Cooldown, icon)
        end

        if _resolverRuntimePolicy.IsRealCooldownDurationMode(resolvedMode) and icon._usabilityTinted then
            icon.Icon:SetVertexColor(1, 1, 1, 1)
            icon._usabilityTinted = nil
            icon._lastVisualState = nil
        end
    end

    do
        local containerDB = GetTrackerSettings(entry.viewerType)
        if IsCustomBarContainer(containerDB) then
            _resolverRuntimePolicy.ApplyCustomBarActiveState(icon, entry, containerDB)
        else
            icon._customBarActive = nil
            _resolverRuntimePolicy.StopCustomBarActiveGlow(icon)
        end
    end

    local _cachedChargeInfo = nil
    local _cachedChargeInfoQueried = false

    local _stackTextResolved = false
    local _stackVal
    local _stackSource
    local _stackMirrorBacked = false
    local _stackMirrorEmpty = false
    local _stackMirrorHidden = false

    if stackTextWritesAllowed and entry.type == "spell" and _resolverRuntimePolicy.ResolveIconStackText then
        _stackVal, _stackSource, _stackMirrorBacked, _stackMirrorHidden = _resolverRuntimePolicy.ResolveIconStackText(icon)
        _stackTextResolved = true
        if _stackMirrorBacked and _resolverRuntimePolicy.ValueIsMissing(_stackVal) then
            _stackMirrorEmpty = true
            if (_stackMirrorHidden and (runtimeHasCharges or not auraCountAppliedThisTick))
               or ((not _stackMirrorHidden) and not auraCountAppliedThisTick and not runtimeHasCharges) then
                _resolverRuntimePolicy.HideIconStackText(icon, _stackMirrorHidden and "mirror-stack-hidden" or "mirror-stack-empty")
                icon._stackTextSource = nil
            end
        end
    end

    local _chargeCountForwarded = false
    local _allowChargeCountForwarder = not _stackMirrorBacked
        or (runtimeHasCharges and _stackMirrorEmpty and not _stackMirrorHidden and not InCombatLockdown())
    if stackTextWritesAllowed and entry.type == "spell" and _allowChargeCountForwarder then
        local chargeQueryID = _runtimeSid
        local baseSid = entry.spellID or entry.id
        if chargeQueryID and not _cachedChargeInfoQueried then
            _cachedChargeInfo = QueryCharges(chargeQueryID)
            _cachedChargeInfoQueried = true
        end
        local ci = _cachedChargeInfo
        local ciMax = ci and ci.maxCharges
        local ciMaxIsMulti = IsSafeNumeric(ciMax) and ciMax > 1
        if (not ciMaxIsMulti)
            and baseSid
            and baseSid ~= chargeQueryID then
            local bci = QueryCharges(baseSid)
            local bciMax = bci and bci.maxCharges
            if IsSafeNumeric(bciMax) and bciMax > 1 then
                ci = bci
                ciMax = bciMax
                ciMaxIsMulti = true
                chargeQueryID = baseSid
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "FWD base fallback: baseSid=", baseSid,
                        "maxCharges=", bciMax, "currentCharges=", bci.currentCharges)
                end
            end
        end
        if (not ciMaxIsMulti)
            and entry.overrideSpellID
            and entry.overrideSpellID ~= chargeQueryID
            and entry.overrideSpellID ~= baseSid then
            local oci = QueryCharges(entry.overrideSpellID)
            local ociMax = oci and oci.maxCharges
            if IsSafeNumeric(ociMax) and ociMax > 1 then
                ci = oci
                ciMax = ociMax
                ciMaxIsMulti = true
                chargeQueryID = entry.overrideSpellID
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "FWD override fallback: overrideSpellID=", entry.overrideSpellID,
                        "maxCharges=", ociMax, "currentCharges=", oci.currentCharges)
                end
            end
        end
        if ci and (ciMaxIsMulti or runtimeHasCharges) then
            local ccc = ci.currentCharges
            local cccIsSecret = issecretvalue and issecretvalue(ccc)
            if _G.QUI_CDM_CHARGE_DEBUG then
                local _dbgCccSource = (cccIsSecret or ccc ~= nil) and "api" or nil
                ChargeDebug(entry.name, "FWD path: baseSid=", baseSid,
                    "runtimeSid=", _runtimeSid,
                    "chargeQueryID=", chargeQueryID,
                    "maxCharges=", ciMax, "currentCharges=", ci.currentCharges,
                    "ccc=", ccc, "cccSource=", _dbgCccSource or "nil",
                    "hasCharges=", runtimeHasCharges,
                    "entryHasCharges=", entry.hasCharges,
                    "overrideSpellID=", entry.overrideSpellID)
            end
            if (cccIsSecret or ccc ~= nil) and stackTextWritesAllowed then
                _resolverRuntimePolicy.ShowIconStackText(icon, ccc, GetTrackerSettings(entry.viewerType), "fwd-charge-count")
                _chargeCountForwarded = true
            end
        end
    end

    if _G.QUI_CDM_CHARGE_DEBUG and _chargeCountForwarded then
        ChargeDebug(entry.name, "SKIP API path: chargeCountForwarded=", _chargeCountForwarded)
    end
    -- Item stack text was already set above; only spell entries need work here.
    if not _chargeCountForwarded and stackTextWritesAllowed and entry.type == "spell" then
            local spellID = _runtimeSid
            local stackVal = _stackVal
            local stackSource = _stackSource
            local stackMirrorBacked = _stackMirrorBacked
            local stackMirrorEmpty = _stackMirrorEmpty
            local stackMirrorHidden = _stackMirrorHidden

            if not _stackTextResolved and _resolverRuntimePolicy.ResolveIconStackText then
                stackVal, stackSource, stackMirrorBacked, stackMirrorHidden = _resolverRuntimePolicy.ResolveIconStackText(icon)
            end

            local cachedMaxCharges = _cachedChargeInfo and _cachedChargeInfo.maxCharges
            local isMultiCharge = IsSafeNumeric(cachedMaxCharges) and cachedMaxCharges > 1
            local allowAPIStackFallback = not stackMirrorBacked or (not stackMirrorHidden and not InCombatLockdown())

            if stackMirrorBacked and _resolverRuntimePolicy.ValueIsMissing(stackVal) and (stackMirrorHidden or not runtimeHasCharges) then
                if not stackMirrorEmpty then
                    stackMirrorEmpty = true
                    _resolverRuntimePolicy.HideIconStackText(icon, stackMirrorHidden and "mirror-stack-hidden" or "mirror-stack-empty")
                    icon._stackTextSource = nil
                end
            elseif allowAPIStackFallback
                and _resolverRuntimePolicy.ValueIsMissing(stackVal)
                and (isMultiCharge or runtimeHasCharges) then
                local ccc = _cachedChargeInfo and _cachedChargeInfo.currentCharges
                local cccIsSecret = issecretvalue and issecretvalue(ccc)
                if cccIsSecret or ccc ~= nil then
                    stackVal = ccc
                    stackSource = "spell-charge-count"
                elseif spellID then
                    stackVal = QueryDisplayCount(spellID)
                    if _resolverRuntimePolicy.ValueIsPresent(stackVal) then
                        stackSource = "spell-display-count"
                    end
                end
                if _G.QUI_CDM_CHARGE_DEBUG then
                    local dbgChargeInfo = _cachedChargeInfo or {}
                    ChargeDebug(entry.name, "API path: spellID=", spellID,
                        "maxCharges=", dbgChargeInfo.maxCharges,
                        "currentCharges=", dbgChargeInfo.currentCharges,
                        "displayCount=", stackVal, "isMultiCharge=", isMultiCharge)
                end
            elseif _resolverRuntimePolicy.ValueIsMissing(stackVal) then
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "no stack text: spellID=", spellID,
                        "mirrorBacked=", tostring(stackMirrorBacked),
                        "isMultiCharge=", tostring(isMultiCharge))
                end
            end

            if _resolverRuntimePolicy.ValueIsPresent(stackVal) then
                if isMultiCharge then
                    _resolverRuntimePolicy.ShowIconStackText(icon, stackVal, GetTrackerSettings(entry.viewerType), "api-charge-count")
                    if stackMirrorBacked then
                        icon._lastMirrorStackTextEpoch = icon.stackTextEpoch
                    end
                else
                    local displayText
                    if type(stackVal) == "number" then
                        if stackSource == "ChargeCount" or stackSource == "spell-charge-count" then
                            displayText = tostring(stackVal)
                        else
                            displayText = C_StringUtil.TruncateWhenZero(stackVal)
                        end
                    else
                        displayText = stackVal
                    end
                    local hasText = HookTextHasDisplay(displayText)
                    if hasText then
                        _resolverRuntimePolicy.ShowIconStackText(icon, displayText, GetTrackerSettings(entry.viewerType), stackSource or "api-aura-stack")
                        if stackMirrorBacked then
                            icon._lastMirrorStackTextEpoch = icon.stackTextEpoch
                        end
                    else
                        _resolverRuntimePolicy.HideIconStackText(icon, "api-aura-stack-empty")
                    end
                end
            elseif stackMirrorEmpty then
                -- Mirror-backed icons with no mirror stack text and no charge fallback stay empty.
                if runtimeHasCharges then
                    _resolverRuntimePolicy.HideIconStackText(icon, stackMirrorHidden and "mirror-stack-hidden" or "charge-count-empty")
                    icon._stackTextSource = nil
                end
            elseif not InCombatLockdown() and not runtimeHasCharges then
                _resolverRuntimePolicy.HideIconStackText(icon, "api-stack-nil")
            end
        elseif entry.type ~= "item" then
            -- Item entries set their bag-count badge above (item-count /
            -- item-count-zero / item-count-fallback writes). Falling
            -- through to the harvested-aura fallback would call
            -- HideIconStackText("harvested-stack-nil") for items — their
            -- itemID-as-spellID never resolves an aura — silently
            -- clobbering the count immediately after it was shown.
            -- Trinket/slot/macro/spell still need this branch: trinket
            -- and slot already cleared their text so a re-clear is a
            -- no-op; macro entries in aura-family containers rely on
            -- this path to clear; spell entries are the primary use.
            local stackVal = GetAuraApplicationsForSpell(_runtimeSid, entry, icon)
            if _resolverRuntimePolicy.ValueIsPresent(stackVal) then
                local displayText
                if type(stackVal) == "number" then
                    displayText = C_StringUtil.TruncateWhenZero(stackVal)
                else
                    displayText = stackVal
                end
                local hasText = HookTextHasDisplay(displayText)
                if hasText then
                    _resolverRuntimePolicy.ShowIconStackText(icon, displayText, GetTrackerSettings(entry.viewerType), "harvested-aura-stack")
                else
                    _resolverRuntimePolicy.HideIconStackText(icon, "harvested-aura-stack-empty")
                end
            elseif not InCombatLockdown() then
                _resolverRuntimePolicy.HideIconStackText(icon, "harvested-stack-nil")
            end
    end

    if icon._lastVisualState == "unusable"
       and not icon._usabilityTinted
       and not _resolverRuntimePolicy.CooldownHasVisualPriority(icon, entry, GetTrackerSettings(entry.viewerType), GetRefreshBatchTime()) then
        icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
        icon._usabilityTinted = true
    end
end

UpdateIconCooldown = function(icon)
    if RuntimeQueries and RuntimeQueries.WithRuntimeQueryOwner then
        return RuntimeQueries.WithRuntimeQueryOwner(icon, UpdateIconCooldownOwned, icon)
    end
    return UpdateIconCooldownOwned(icon)
end

---------------------------------------------------------------------------
-- IsCustomBarEntryUsableOnCurrentClass: cross-class filter for the
-- customBar build-time render path.  A QUI profile is often shared across
-- multiple classes; entries added on one class persist in db.entries and
-- would otherwise spawn runtime icons for spells the current character
-- cannot cast.
--
-- Mirrors the composer's IsEntryUsableOnCurrentPlayer predicate so the
-- two views agree on which entries are "for this character":
--   * non-spell types (item/macro/slot)     → always pass (not class-bound)
--   * aura-kind spell entries               → always pass (buff IDs aren't
--                                              in the spellbook; runtime
--                                              aura resolution decides)
--   * cooldown-kind spell entries           → IsSpellKnown gate
---------------------------------------------------------------------------
local function IsCustomBarEntryUsableOnCurrentClass(entry)
    if type(entry) ~= "table" then return true end
    if entry.type ~= "spell" then return true end
    if type(entry.id) ~= "number" then return true end
    if entry.kind == "aura" then return true end
    local spellData = ns.CDMSpellData
    if not spellData or type(spellData.IsSpellKnown) ~= "function" then
        return true
    end
    return spellData:IsSpellKnown(entry.id) == true
end

---------------------------------------------------------------------------
-- Build a spellEntry record from a user-curated custom entry.
-- Used by both legacy essential/utility custom merges (Phase G) and
-- Phase B.3 custom-container rendering (customBar / user-created cooldown).
-- Returns a fully-populated spellEntry or nil if the entry is unusable.
---------------------------------------------------------------------------
local function BuildSpellEntryFromCustom(entry, idx, viewerType)
    if type(entry) ~= "table" or entry.id == nil then return nil end
    local isSpellType = (entry.type ~= "item" and entry.type ~= "trinket" and entry.type ~= "slot")
    -- Forward the entry's stamped kind onto the synthesized spellEntry so
    -- downstream IsAuraEntry / visibility / ID-correction code branches per
    -- entry instead of per container. Falls through to viewerType-based
    -- classification when the legacy entry lacks an explicit kind.
    local kind = entry.kind
    if not (kind == "aura" or kind == "cooldown") then
        if not isSpellType then
            kind = "cooldown"
        else
            local impliedKind = Shared and Shared.GetContainerEntryKind
                and Shared.GetContainerEntryKind(viewerType)
                or GetBuiltinContainerEntryKind(viewerType)
            if impliedKind then
                kind = impliedKind
            else
                local CDMSpellData = ns.CDMSpellData
                kind = (CDMSpellData and CDMSpellData.ResolveEntryKind
                    and CDMSpellData.ResolveEntryKind(entry, viewerType)) or "cooldown"
            end
        end
    end
    local isAuraEntry = (kind == "aura")
    local itemID = (entry.type == "item")
        and ((Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id)
        or nil
    local spellEntry = {
        spellID = isSpellType and entry.id or nil,
        overrideSpellID = isSpellType and entry.id or nil,
        name = "",
        isAura = isAuraEntry or false,
        kind = kind,
        layoutIndex = 99000 + (idx or 0),
        viewerType = viewerType,
        type = entry.type,
        id = itemID or entry.id,
        itemID = itemID,
        _isCustomEntry = true,
        _sourceSpecID = entry._sourceSpecID,
    }
    if entry.type == "macro" then
        spellEntry.macroName = entry.macroName
        spellEntry.name = entry.macroName or ""
        local resolvedID = ResolveMacro(spellEntry)
        if resolvedID then
            spellEntry.spellID = resolvedID
            spellEntry.overrideSpellID = resolvedID
        end
    elseif entry.type == "trinket" or entry.type == "slot" then
        local itemID = Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID("player", entry.id)
        if itemID then
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
            spellEntry.name = itemName or ""
        end
    elseif entry.type == "item" then
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(spellEntry.id)
        spellEntry.name = itemName or ""
    else
        local storedName = entry.name
        if type(storedName) == "string" and true and storedName ~= "" then
            spellEntry.name = storedName
        else
            spellEntry.name = GetCachedSpellName(entry.id) or ""
        end
    end
    if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugEntryBuild then
        CDMIcons.DebugEntryBuild(entry, spellEntry, viewerType)
    end
    return spellEntry
end

local function AppendSignaturePart(parts, value)
    parts[#parts + 1] = tostring(value == nil and "" or value)
end

local function AppendEntrySignature(parts, prefix, entry, idx)
    AppendSignaturePart(parts, prefix)
    AppendSignaturePart(parts, idx)
    if type(entry) ~= "table" then
        AppendSignaturePart(parts, "nil")
        return
    end
    AppendSignaturePart(parts, entry.type or "spell")
    AppendSignaturePart(parts, entry.kind)
    AppendSignaturePart(parts, entry.id)
    AppendSignaturePart(parts, entry.spellID)
    AppendSignaturePart(parts, entry.overrideSpellID)
    AppendSignaturePart(parts, entry.isAura and 1 or 0)
    AppendSignaturePart(parts, entry.enabled == false and 0 or 1)
    AppendSignaturePart(parts, entry.position)
    AppendSignaturePart(parts, entry.row)
    AppendSignaturePart(parts, entry._assignedRow)
    AppendSignaturePart(parts, entry._instanceKey)
    AppendSignaturePart(parts, entry._sourceSpecID)
end

local function AppendEntryListSignature(parts, prefix, list)
    if type(list) ~= "table" then
        AppendSignaturePart(parts, prefix)
        AppendSignaturePart(parts, "none")
        return
    end
    AppendSignaturePart(parts, prefix)
    AppendSignaturePart(parts, #list)
    for idx, entry in ipairs(list) do
        AppendEntrySignature(parts, prefix, entry, idx)
    end
end

local function BuildIconListSignature(viewerType, container, spellData)
    local parts = {}
    AppendSignaturePart(parts, viewerType)
    AppendEntryListSignature(parts, "harvested", spellData)

    local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    local cDB = ncdm and ncdm.containers and ncdm.containers[viewerType]
    if cDB and cDB.builtIn == false then
        AppendSignaturePart(parts, "container")
        AppendSignaturePart(parts, cDB.specSpecific and 1 or 0)
        local entryList
        if cDB.specSpecific and ns.CDMSpellData and ns.CDMSpellData.GetSpecEntries then
            entryList = ns.CDMSpellData:GetSpecEntries(viewerType)
        end
        if type(entryList) ~= "table" then
            entryList = cDB.entries
        end
        AppendEntryListSignature(parts, "containerEntries", entryList)
        -- IsCustomBarEntryUsableOnCurrentClass verdicts can flip across
        -- a respec (talent-gated spells appear/disappear from the
        -- spellbook). Class doesn't change in-session, but specID does;
        -- stamp it so the pool rebuilds when SPELLS_CHANGED fires after
        -- a spec swap and known-spell state shifts.
        local specID = GetSpecialization and GetSpecialization()
        AppendSignaturePart(parts, "spec")
        AppendSignaturePart(parts, specID or "")
    end

    if IsBuiltinCooldownContainerKey(viewerType) then
        local customData = GetCustomData(viewerType)
        AppendSignaturePart(parts, "legacyCustom")
        AppendSignaturePart(parts, customData and customData.enabled and 1 or 0)
        AppendSignaturePart(parts, customData and customData.placement or "")
        AppendEntryListSignature(parts, "legacyEntries", customData and customData.entries)
    end

    return table.concat(parts, "|")
end

local function PoolMatchesContainer(pool, container)
    if not pool or not container or #pool == 0 then return false end
    for _, icon in ipairs(pool) do
        if icon and icon.GetParent and icon:GetParent() ~= container then
            return false
        end
    end
    return true
end

local _customPositionedScratch = {}
local _customUnpositionedScratch = {}

---------------------------------------------------------------------------
-- BUILD ICONS: Create icons from harvested spell data + custom entries
---------------------------------------------------------------------------
function CDMIcons:BuildIcons(viewerType, container)
    if not container then return {} end

    local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList(viewerType) or {}
    local signature = BuildIconListSignature(viewerType, container, spellData)
    local pool = Factory:GetIconPool(viewerType)
    local reusePool = pool
        and container._lastBuildSignature == signature
        and container._lastBuildPool == pool
        and PoolMatchesContainer(pool, container)

    if not reusePool then
        pool = Factory:ClearPool(viewerType)
        pool = Factory:EnsurePool(viewerType)

        -- Create icons from harvested spell data
        for _, entry in ipairs(spellData) do
            local icon = Factory:AcquireIcon(container, entry)
            pool[#pool + 1] = icon
        end

        -- Phase B.3: Custom containers (non-built-in) render their own entries.
        -- Covers customBar containers (migrated from legacy trackers) and any
        -- user-created cooldown / aura container from the Composer.  Entries
        -- live on the container itself under `entries`, or under a per-spec
        -- table in db.global.ncdm.specTrackerSpells when specSpecific is set.
        do
            local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
            local cDB = ncdm and ncdm.containers and ncdm.containers[viewerType]
            if cDB and cDB.builtIn == false then
                local entryList
                if cDB.specSpecific and ns.CDMSpellData and ns.CDMSpellData.GetSpecEntries then
                    entryList = ns.CDMSpellData:GetSpecEntries(viewerType)
                end
                if type(entryList) ~= "table" then
                    entryList = cDB.entries
                end
                if type(entryList) == "table" then
                    for idx, entry in ipairs(entryList) do
                        if entry and entry.enabled ~= false
                            and IsCustomBarEntryUsableOnCurrentClass(entry) then
                            local spellEntry = BuildSpellEntryFromCustom(entry, idx, viewerType)
                            if spellEntry then
                                local icon = Factory:AcquireIcon(container, spellEntry)
                                pool[#pool + 1] = icon
                            end
                        end
                    end
                end
            end
        end

        -- Merge custom entries for built-in cooldown containers.
        if IsBuiltinCooldownContainerKey(viewerType) then
            local customData = GetCustomData(viewerType)
            if customData and customData.enabled and customData.entries then
                local placement = customData.placement or "after"

                -- Separate positioned and unpositioned custom entries
                local positioned = _customPositionedScratch
                local unpositioned = _customUnpositionedScratch
                wipe(positioned)
                wipe(unpositioned)
                for idx, entry in ipairs(customData.entries) do
                    if entry.enabled ~= false then
                        local spellEntry = BuildSpellEntryFromCustom(entry, idx, viewerType)
                        if spellEntry then
                            if entry.position and entry.position > 0 then
                                positioned[#positioned + 1] = { entry = spellEntry, position = entry.position, origIndex = idx }
                            else
                                unpositioned[#unpositioned + 1] = spellEntry
                            end
                        end
                    end
                end

                -- Insert unpositioned entries (before or after harvested icons)
                if #unpositioned > 0 then
                    if placement == "before" then
                        local prefixCount = #unpositioned
                        for i = #pool, 1, -1 do
                            pool[i + prefixCount] = pool[i]
                        end
                        for i, entry in ipairs(unpositioned) do
                            pool[i] = Factory:AcquireIcon(container, entry)
                        end
                    else
                        for _, entry in ipairs(unpositioned) do
                            local icon = Factory:AcquireIcon(container, entry)
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
                    local icon = Factory:AcquireIcon(container, item.entry)
                    local insertAt = math.min(item.position, #pool + 1)
                    table.insert(pool, insertAt, icon)
                end
                wipe(positioned)
                wipe(unpositioned)
            end
        end
    end

    container._lastBuildSignature = signature
    container._lastBuildPool = pool

    -- Initialize owned icons: configure addon CD and mark aura containers
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry then
            local containerDB = GetTrackerSettings(entry.viewerType)
            local tooltipContext = containerDB and containerDB.tooltipContext
            if IsCustomBarContainer(containerDB) then
                tooltipContext = tooltipContext or "customTrackers"
            end
            icon._quiTooltipContext = tooltipContext or "cdm"
            icon.__quiTooltipContext = icon._quiTooltipContext
            icon.__customTrackerIcon = icon._quiTooltipContext == "customTrackers" or nil

            local addonCD = icon.Cooldown
            if addonCD then
                addonCD:SetDrawSwipe(true)
                addonCD:SetHideCountdownNumbers(false)
                addonCD:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
                addonCD:SetSwipeColor(0, 0, 0, 0.8)
                addonCD:Show()
            end
            -- Mark aura entries so visibility handling works correctly
            if IsAuraEntry(entry) then
                icon._auraActive = false  -- will be set true by UpdateIconCooldown when aura present
                icon._auraUnit = nil
            end
        end
    end

    -- Buff icons are aura containers, but the active state must still
    -- come from UpdateIconCooldown/runtime aura resolution. Pre-marking them
    -- active here makes empty rows render as active-looking.
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry and entry.viewerType == "buff" then
            icon._auraActive = false
            icon._auraUnit = nil
        end
    end

    -- Update click-to-cast secure attributes for cooldown icons.
    -- AcquireIcon sets attrs per-icon for fresh acquisitions; when the pool
    -- is reused (signature match), AcquireIcon is skipped — so a
    -- clickableIcons toggle on essential/utility would otherwise not take
    -- effect until /reload. Run a full pass on reuse, and a pending-only
    -- pass otherwise to catch combat-deferred rebuilds via PLAYER_REGEN_ENABLED.
    if reusePool then
        for _, icon in ipairs(pool) do
            local entry = icon._spellEntry
            if entry and entry.viewerType ~= "buff" then
                UpdateIconSecureAttributes(icon, entry, entry.viewerType or viewerType)
            end
        end
    else
        for _, icon in ipairs(pool) do
            if icon._pendingSecureUpdate then
                local entry = icon._spellEntry
                if entry and entry.viewerType ~= "buff" then
                    UpdateIconSecureAttributes(icon, entry, entry.viewerType or viewerType)
                end
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
-- VISIBILITY FILTERS (Phase B.3)
-- Container-level filters that override display-mode visibility based on
-- runtime state. Enabled per-container via settings; all default to off so
-- existing containers behave identically to pre-filter builds.
---------------------------------------------------------------------------

local visibilityPolicy = ns.CDMIconVisibilityPolicy and ns.CDMIconVisibilityPolicy.Create({
    isCustomBarContainer = function(containerDB)
        return IsCustomBarContainer(containerDB)
    end,
    computeCustomBarVisibility = function(icon, entry, containerDB)
        return _resolverRuntimePolicy.ComputeCustomBarVisibility(icon, entry, containerDB, GetTime())
    end,
    resolveCooldownActivityState = function(icon, entry, containerDB)
        return _resolverRuntimePolicy.ResolveIconCooldownActivityState(icon, entry, containerDB, GetTime())
    end,
    queryItemCount = function(...)
        return Sources and Sources.QueryItemCount and Sources.QueryItemCount(...)
    end,
    queryInventoryItemID = function(...)
        return Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID(...)
    end,
    queryItemSpell = function(...)
        return Sources and Sources.QueryItemSpell and Sources.QueryItemSpell(...)
    end,
    querySpellUsable = function(...)
        return Sources and Sources.QuerySpellUsable and Sources.QuerySpellUsable(...)
    end,
    isSpellKnown = function(spellID)
        local spellData = ns.CDMSpellData
        if spellData and type(spellData.IsSpellKnown) == "function" then
            return spellData:IsSpellKnown(spellID) == true
        end
        return nil
    end,
    debugLayoutFilter = function(icon, filterHides, containerDB, isOnCD)
        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugLayoutFilter then
            CDMIcons.DebugLayoutFilter(icon, filterHides, containerDB, isOnCD)
        end
    end,
    isHiddenByAnchor = function(anchorKey)
        return _G.QUI_IsFrameHiddenByAnchor and _G.QUI_IsFrameHiddenByAnchor(anchorKey)
    end,
    getContainer = function(containerKey)
        return ns.CDMContainers and ns.CDMContainers.GetContainer
            and ns.CDMContainers.GetContainer(containerKey)
    end,
    scheduleAfter = function(delay, callback)
        if C_Timer and C_Timer.After then
            C_Timer.After(delay, callback)
        end
    end,
    onBuffLayoutReady = function()
        if ns.CDMBuffLayout and ns.CDMBuffLayout.OnLayoutReady then
            ns.CDMBuffLayout:OnLayoutReady()
        end
    end,
    forceLayoutContainer = function(trackerKey)
        if _G.QUI_ForceLayoutContainer then
            _G.QUI_ForceLayoutContainer(trackerKey)
        end
    end,
})

local function ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
    return visibilityPolicy and visibilityPolicy:ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
        or false
end

function CDMIcons.ShouldContainerLayoutPlaceIcon(icon, entry, containerDB, inCombat)
    return not visibilityPolicy
        or visibilityPolicy:ShouldPlaceLayoutIcon(icon, entry, containerDB, inCombat)
end

function _resolverRuntimePolicy.WakeBuffIconContainer()
    if visibilityPolicy then
        visibilityPolicy:WakeBuffIconContainer()
    end
end

function _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    if visibilityPolicy then
        visibilityPolicy:RequestBuffIconLayoutRefresh()
    end
end

local function MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
    if visibilityPolicy then
        visibilityPolicy:MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
    end
end

local function DrainLayoutDirty()
    if visibilityPolicy then
        visibilityPolicy:DrainLayoutDirty()
    end
end

local function ApplyIconVisibility(icon, shouldShow, dynamicLayout)
    if visibilityPolicy then
        visibilityPolicy:ApplyIconVisibility(icon, shouldShow, dynamicLayout)
    end
end

local function ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
    if not entry then return nil, "cooldown" end

    local containerDB = ncdm and (ncdm[entry.viewerType] or (ncdmContainers and ncdmContainers[entry.viewerType]))
    local cType = containerDB and containerDB.containerType
    if not cType then
        local vt = entry.viewerType
        cType = Shared and Shared.GetContainerType
            and Shared.GetContainerType(vt, containerDB)
            or GetBuiltinContainerType(vt)
            or "cooldown"
    end

    return containerDB, cType
end

local function PrepareCooldownUpdateBatch()
    if refreshBatch then
        return refreshBatch:Prepare()
    end

    local editMode = Helpers.IsEditModeActive()
        or Helpers.IsLayoutModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())
    local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    _resolverRuntimePolicy.RefreshSwipeBatchSettings()
    return editMode, ncdm, ncdm and ncdm.containers, InCombatLockdown()
end

local function BeginIconRefreshBatch(reason)
    if refreshBatch then
        refreshBatch:Begin(reason)
    elseif RuntimeQueries and RuntimeQueries.BeginRuntimeQueryBatch then
        RuntimeQueries.BeginRuntimeQueryBatch()
    end
end

local function EndIconRefreshBatch()
    if refreshBatch then
        refreshBatch:End()
    elseif RuntimeQueries and RuntimeQueries.EndRuntimeQueryBatch then
        RuntimeQueries.EndRuntimeQueryBatch()
    end
end

local function SetRefreshBatchStackTextWrites(enabled)
    if refreshBatch then
        refreshBatch:SetStackTextWrites(enabled)
    elseif SetStackTextWritesForBatch then
        SetStackTextWritesForBatch(enabled)
    end
end

local function ConsumeStackTextWriteRequest()
    return refreshBatch and refreshBatch:ConsumeStackTextWriteRequest() or false
end

local function RequestStackTextUpdate()
    if refreshBatch then
        refreshBatch:RequestStackTextUpdate()
    end
end

local function UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    local spellOvr = (not editMode) and GetIconSpellOverride(icon) or nil
    local isHiddenOverride = spellOvr and spellOvr.hidden

    if isHiddenOverride then
        if icon:IsShown() then icon:Hide() end
        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
            CDMIcons.DebugIconEvent(icon, "hidden-override",
                "auraActive=", tostring(icon._auraActive == true),
                "shown=", tostring(icon:IsShown()))
        end
        SyncCooldownBling(icon)
        return
    end

    if editMode then
        icon:SetAlpha(1)
        icon:Show()
        SyncCooldownBling(icon)
        return
    end

    local entryIsAura = IsAuraEntry(entry)
    if IsCustomBarContainer(containerDB) then
        local visibility = _resolverRuntimePolicy.ComputeCustomBarVisibility(icon, entry, containerDB, GetRefreshBatchTime())
        local effectiveMode = containerDB and containerDB.iconDisplayMode or "always"
        if effectiveMode == "combat" then
            effectiveMode = (UnitAffectingCombat and UnitAffectingCombat("player")) and "always" or "active"
        end

        local shouldShow = visibility.renderVisible
        if effectiveMode == "active" and not visibility.isOnCooldown and not visibility.rechargeActive then
            local keepForGlow = false
            if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
            end
            shouldShow = shouldShow and keepForGlow
        elseif effectiveMode ~= "always" and effectiveMode ~= "active" then
            shouldShow = false
        end

        local filterHidesNow = not visibility.layoutVisible
        MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
        ApplyIconVisibility(icon, shouldShow, containerDB.dynamicLayout == true)
        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
            CDMIcons.DebugIconEvent(icon, "show",
                "shouldShow=", tostring(shouldShow),
                "shown=", tostring(icon:IsShown()),
                "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                "effectiveMode=", tostring(effectiveMode),
                "filterHidden=", tostring(filterHidesNow),
                "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
        end
        _resolverRuntimePolicy.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
        SyncCooldownBling(icon)
        return
    end

    if entryIsAura then
        local isActive = icon._auraActive == true
        local effectiveMode = containerDB and containerDB.iconDisplayMode or "always"
        if effectiveMode == "combat" then
            effectiveMode = inCombat and "always" or "active"
        end

        if effectiveMode == "always" then
            ApplyIconVisibility(icon, true, containerDB and containerDB.dynamicLayout)
        elseif effectiveMode == "active" then
            if isActive then
                ApplyIconVisibility(icon, true, containerDB and containerDB.dynamicLayout)
            else
                if icon:IsShown() then icon:Hide() end
            end
        else
            if icon:IsShown() then icon:Hide() end
        end

        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
            CDMIcons.DebugIconEvent(icon, "aura-show",
                "active=", tostring(isActive),
                "shown=", tostring(icon:IsShown()),
                "effectiveMode=", tostring(effectiveMode),
                "containerType=", tostring(containerDB and containerDB.containerType))
        end
        SyncCooldownBling(icon)
        return
    end

    local cooldownState = _resolverRuntimePolicy.ResolveIconCooldownActivityState(
        icon, entry, containerDB, GetRefreshBatchTime())
    local isOnCD = cooldownState.isOnCooldown or cooldownState.rechargeActive

    local effectiveMode = containerDB and containerDB.iconDisplayMode or "always"
    if effectiveMode == "combat" then
        effectiveMode = inCombat and "always" or "active"
    end

    local shouldShow
    if effectiveMode == "always" then
        shouldShow = true
    elseif effectiveMode == "active" then
        if isOnCD then
            shouldShow = true
        else
            local keepForGlow = false
            if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
            end
            shouldShow = keepForGlow
        end
    else
        shouldShow = false
    end

    -- Compute filter unconditionally (not gated on shouldShow) so the
    -- mismatch detector sees the latest verdict even when display mode has
    -- already hidden the icon.
    local filterHidesNow = ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
    if filterHidesNow then shouldShow = false end
    MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)

    ApplyIconVisibility(icon, shouldShow, containerDB and containerDB.dynamicLayout)
    if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
        CDMIcons.DebugIconEvent(icon, "show",
            "shouldShow=", tostring(shouldShow),
            "shown=", tostring(icon:IsShown()),
            "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
            "displayMode=", tostring(containerDB and containerDB.iconDisplayMode),
            "effectiveMode=", tostring(effectiveMode),
            "filterHidden=", tostring(filterHidesNow),
            "isOnCD=", tostring(isOnCD),
            "isOnCooldown=", tostring(cooldownState and cooldownState.isOnCooldown),
            "rechargeActive=", tostring(cooldownState and cooldownState.rechargeActive),
            "hasChargesRemaining=", tostring(cooldownState and cooldownState.hasChargesRemaining),
            "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
    end
    SyncCooldownBling(icon)
end

local function RefreshAllIcon(icon, context)
    context = context or {}
    local entry = icon and icon._spellEntry
    local wasAuraActive = icon and icon._auraActive == true

    -- Update cooldown/aura state before visibility so resolved runtime facts
    -- are fresh for Show/Hide decisions.
    UpdateIconCooldown(icon)

    if entry and entry.viewerType == "buff"
       and wasAuraActive ~= (icon._auraActive == true) then
        _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    end

    local editMode = context.editMode
    local ncdm = context.ncdm
    local ncdmContainers = context.ncdmContainers
    local inCombat = context.inCombat

    -- Per-spell hidden override: always hide regardless of display mode.
    local spellOvr = (not editMode) and GetIconSpellOverride(icon) or nil
    local isHiddenOverride = spellOvr and spellOvr.hidden

    if entry then
        -- Visibility branches per entry kind (aura vs cooldown). Container
        -- shape (icon vs bar) is decoupled — a cooldown entry on a bar-shaped
        -- container takes the cooldown branch, aura entries on an icon-shaped
        -- container take the aura branch.
        local containerDB = ncdm
            and (ncdm[entry.viewerType] or (ncdmContainers and ncdmContainers[entry.viewerType]))
        local displayMode = containerDB and containerDB.iconDisplayMode or "always"
        local entryIsAura = IsAuraEntry(entry)

        if isHiddenOverride then
            if icon:IsShown() then icon:Hide() end
        elseif editMode then
            icon:SetAlpha(1)
            icon:Show()
        elseif entryIsAura then
            local isActive = icon._auraActive
            local effectiveMode = displayMode
            if effectiveMode == "combat" then
                effectiveMode = inCombat and "always" or "active"
            end

            if IsCustomBarContainer(containerDB) then
                local visibility = _resolverRuntimePolicy.ComputeCustomBarVisibility(
                    icon, entry, containerDB, GetRefreshBatchTime())
                local shouldShow = visibility.renderVisible
                if effectiveMode == "active" and not isActive then
                    local keepForGlow = false
                    if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                        keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
                    end
                    shouldShow = shouldShow and keepForGlow
                elseif effectiveMode ~= "always" and effectiveMode ~= "active" then
                    shouldShow = false
                end

                local filterHidesNow = not visibility.layoutVisible
                MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
                ApplyIconVisibility(icon, shouldShow, containerDB.dynamicLayout == true)
                if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
                    CDMIcons.DebugIconEvent(icon, "show",
                        "shouldShow=", tostring(shouldShow),
                        "shown=", tostring(icon:IsShown()),
                        "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                        "displayMode=", tostring(displayMode),
                        "effectiveMode=", tostring(effectiveMode),
                        "filterHidden=", tostring(filterHidesNow),
                        "auraActive=", tostring(isActive),
                        "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
                end
                _resolverRuntimePolicy.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
                SyncCooldownBling(icon)
            else
                if effectiveMode == "always" then
                    local rowOpacity = icon._rowOpacity or 1
                    icon:SetAlpha(rowOpacity)
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
            end
        else
            local cooldownState = _resolverRuntimePolicy.ResolveIconCooldownActivityState(
                icon, entry, containerDB, GetRefreshBatchTime())
            local isOnCD = cooldownState.isOnCooldown or cooldownState.rechargeActive

            local effectiveMode = displayMode
            if effectiveMode == "combat" then
                effectiveMode = (UnitAffectingCombat and UnitAffectingCombat("player")) and "always" or "active"
            end

            if IsCustomBarContainer(containerDB) then
                local visibility = _resolverRuntimePolicy.ComputeCustomBarVisibility(
                    icon, entry, containerDB, GetRefreshBatchTime())
                local shouldShow = visibility.renderVisible
                if effectiveMode == "active" and not visibility.isOnCooldown and not visibility.rechargeActive then
                    local keepForGlow = false
                    if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                        keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
                    end
                    shouldShow = shouldShow and keepForGlow
                elseif effectiveMode ~= "always" and effectiveMode ~= "active" then
                    shouldShow = false
                end

                local filterHidesNow = not visibility.layoutVisible
                MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
                ApplyIconVisibility(icon, shouldShow, containerDB.dynamicLayout == true)
                if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
                    CDMIcons.DebugIconEvent(icon, "show",
                        "shouldShow=", tostring(shouldShow),
                        "shown=", tostring(icon:IsShown()),
                        "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                        "effectiveMode=", tostring(effectiveMode),
                        "filterHidden=", tostring(filterHidesNow),
                        "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
                end
                _resolverRuntimePolicy.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
                SyncCooldownBling(icon)
            else
                local shouldShow
                if effectiveMode == "always" then
                    shouldShow = true
                elseif effectiveMode == "active" then
                    if isOnCD then
                        shouldShow = true
                    else
                        local keepForGlow = false
                        if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                            keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
                        end
                        shouldShow = keepForGlow
                    end
                else
                    shouldShow = false
                end

                local filterHidesNow = ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
                if filterHidesNow then shouldShow = false end
                MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
                ApplyIconVisibility(icon, shouldShow, containerDB and containerDB.dynamicLayout)
                if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
                    CDMIcons.DebugIconEvent(icon, "show",
                        "shouldShow=", tostring(shouldShow),
                        "shown=", tostring(icon:IsShown()),
                        "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                        "effectiveMode=", tostring(effectiveMode),
                        "filterHidden=", tostring(filterHidesNow),
                        "isOnCD=", tostring(isOnCD),
                        "isOnCooldown=", tostring(cooldownState and cooldownState.isOnCooldown),
                        "rechargeActive=", tostring(cooldownState and cooldownState.rechargeActive),
                        "hasChargesRemaining=", tostring(cooldownState and cooldownState.hasChargesRemaining),
                        "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
                end
            end

            local greyOutDebuffs = containerDB and containerDB.greyOutInactive
            local greyOutBuffs = containerDB and containerDB.greyOutInactiveBuffs
            local shouldGreyOut = false
            if (greyOutDebuffs or greyOutBuffs) and icon.Icon and icon.Icon.SetDesaturated then
                local hasAbilityAuraMapping = false
                local AuraRuntime = ns.CDMAuraRuntime
                if AuraRuntime and AuraRuntime.HasAbilityAuraMapping then
                    hasAbilityAuraMapping = AuraRuntime.HasAbilityAuraMapping(entry.id)
                end
                local hasAuraLink = entry.linkedSpellIDs
                    or (icon._spellEntry and icon._spellEntry.linkedSpellIDs)
                    or hasAbilityAuraMapping
                    or icon._auraActive ~= nil
                if hasAuraLink then
                    local spellName = entry.name
                    if not spellName then
                        local sid = icon._runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id
                        if sid then
                            local info = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
                            spellName = info and info.name
                        end
                    end

                    if not icon._greyType and spellName then
                        local isHarm = Sources and Sources.QuerySpellHarmful and Sources.QuerySpellHarmful(spellName)
                        local isHelp = Sources and Sources.QuerySpellHelpful and Sources.QuerySpellHelpful(spellName)
                        if isHarm then
                            icon._greyType = "debuff"
                        elseif isHelp then
                            icon._greyType = "buff"
                        end
                    end

                    if greyOutDebuffs and icon._greyType == "debuff" then
                        local hasTarget = UnitExists("target")
                            and not UnitIsDead("target")
                            and UnitCanAttack("player", "target")
                        if hasTarget and not icon._auraActive then
                            shouldGreyOut = true
                        end
                    end
                    if not shouldGreyOut and greyOutBuffs and icon._greyType == "buff" then
                        if not icon._auraActive then
                            shouldGreyOut = true
                        end
                    end
                end
            end
            if shouldGreyOut then
                if not icon._greyedOut then
                    if icon.Icon then icon.Icon:SetAlpha(0.4) end
                    if icon.Cooldown then icon.Cooldown:SetAlpha(0.4) end
                    if icon.Border then icon.Border:SetAlpha(0.4) end
                    if icon.DurationText then icon.DurationText:SetAlpha(0.4) end
                    if icon.StackText then icon.StackText:SetAlpha(0.4) end
                    if not icon._cdDesaturated then
                        icon.Icon:SetDesaturated(true)
                    end
                    icon._greyedOut = true
                end
            elseif icon._greyedOut then
                if icon.Icon then icon.Icon:SetAlpha(1) end
                if icon.Cooldown then icon.Cooldown:SetAlpha(1) end
                if icon.Border then icon.Border:SetAlpha(1) end
                if icon.DurationText then icon.DurationText:SetAlpha(1) end
                if icon.StackText then icon.StackText:SetAlpha(1) end
                if icon.Icon and icon.Icon.SetDesaturated and not icon._cdDesaturated then
                    icon.Icon:SetDesaturated(false)
                end
                icon._greyedOut = nil
            end
        end
        SyncCooldownBling(icon)
    end
end

ApplyVisibleMirrorStackTextIfNeeded = function(icon, entry)
    if not (icon and entry and icon._blizzMirrorCooldownID and icon._blizzMirrorCategory) then
        return false
    end
    if IsAuraEntry(entry) then
        return false
    end
    if not _resolverRuntimePolicy.ApplyMirrorStackText then
        return false
    end
    if _resolverRuntimePolicy.ShouldHideIconStackText(icon, GetTrackerSettings(entry.viewerType)) then
        return false
    end

    local mirrorState = GetCachedMirrorStateForIcon(icon)
        or RefreshCachedMirrorStateForIcon(icon)
    if not mirrorState then
        return false
    end

    if _resolverRuntimePolicy.ResolveMirrorStackText then
        local mirrorText, _, mirrorBacked, mirrorHidden =
            _resolverRuntimePolicy.ResolveMirrorStackText(icon)
        if mirrorBacked
            and mirrorHidden == true
            and _resolverRuntimePolicy.ValueIsMissing(mirrorText) then
            ClearIconStackText(icon, "mirror-stack-hidden")
            icon._lastMirrorStackTextEpoch = mirrorState.stackTextEpoch
            return true
        end
    end

    local stackShown = icon.StackText and icon.StackText.IsShown and icon.StackText:IsShown() == true
    local stackEpoch = mirrorState.stackTextEpoch
    if stackShown and (stackEpoch == nil or icon._lastMirrorStackTextEpoch == stackEpoch) then
        return false
    end

    return _resolverRuntimePolicy.ApplyMirrorStackText(icon, mirrorState, entry.hasCharges) == true
end

local function UpdateCooldownOnlyIcon(icon, entry)
    if icon._blizzMirrorCooldownID and not IsAuraEntry(entry) then
        if CDMIcons.ShouldAllowStackTextWrites and CDMIcons.ShouldAllowStackTextWrites() == true then
            UpdateIconCooldown(icon)
            return
        end
        ApplyResolvedCooldown(icon)
        SyncCooldownBling(icon)
        return
    end
    UpdateIconCooldown(icon)
end

local function CreateIconRefreshWalker()
    local module = ns.CDMIconRefreshWalker
    if not (module and module.Create) then return nil end
    return module.Create({
        getIconPools = function()
            return iconPools
        end,
        refreshAllIcon = RefreshAllIcon,
        resolveContainerDBAndType = ResolveContainerDBAndType,
        refreshCooldownOnlyIcon = UpdateCooldownOnlyIcon,
        updateIconVisibility = UpdateCooldownContainerVisibility,
        refreshTypeIcon = function(icon)
            UpdateIconCooldown(icon)
        end,
    })
end

local function GetIconRefreshWalker()
    if not refreshWalker then
        refreshWalker = CreateIconRefreshWalker()
    end
    return refreshWalker
end

---------------------------------------------------------------------------
-- UPDATE ALL COOLDOWNS
---------------------------------------------------------------------------
function CDMIcons:UpdateAllCooldowns()
    local editMode, _ncdm, _ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    SetRefreshBatchStackTextWrites(true)
    BeginIconRefreshBatch("updateAll")

    local context = {
        editMode = editMode,
        ncdm = _ncdm,
        ncdmContainers = _ncdmContainers,
        inCombat = inCombat,
    }
    local walker = GetIconRefreshWalker()
    if walker then
        walker:RefreshAll(context)
    else
        for _, pool in pairs(iconPools) do
            for _, icon in ipairs(pool) do
                RefreshAllIcon(icon, context)
            end
        end
    end

    -- After the per-icon visibility loop, relayout any container whose
    -- filter verdict flipped since the last layout pass.
    SetRefreshBatchStackTextWrites(false)
    SyncSpellRangeChecks()
    EndIconRefreshBatch()
    DrainLayoutDirty()
end

function CDMIcons:UpdateCooldownOnly()
    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    local allowStackTextWrites = ConsumeStackTextWriteRequest()
    SetRefreshBatchStackTextWrites(allowStackTextWrites)
    BeginIconRefreshBatch("cooldownOnly")

    local context = {
        editMode = editMode,
        ncdm = ncdm,
        ncdmContainers = ncdmContainers,
        inCombat = inCombat,
    }
    local walker = GetIconRefreshWalker()
    if walker then
        walker:RefreshCooldownOnly(context)
    else
        for _, pool in pairs(iconPools) do
            for _, icon in ipairs(pool) do
                local entry = icon._spellEntry
                if entry then
                    local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" then
                        UpdateCooldownOnlyIcon(icon, entry)
                        UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
                    end
                end
            end
        end
    end

    -- After the per-icon visibility loop, relayout any container whose
    -- filter verdict flipped since the last layout pass.
    SetRefreshBatchStackTextWrites(false)
    EndIconRefreshBatch()
    DrainLayoutDirty()
end

function CDMIcons:UpdateCooldownsForType(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        PrepareCooldownUpdateBatch()
        SetRefreshBatchStackTextWrites(true)
        BeginIconRefreshBatch("type")
        local walker = GetIconRefreshWalker()
        if walker then
            walker:RefreshType(viewerType)
        else
            for _, icon in ipairs(pool) do
                UpdateIconCooldown(icon)
            end
        end
        SetRefreshBatchStackTextWrites(false)
        SyncSpellRangeChecks()
        EndIconRefreshBatch()
    end
end

function CDMIcons.OnContainerIconPlaced(icon, rowConfig)
    if not icon then return end
    ConfigureIcon(icon, rowConfig)
    BeginIconRefreshBatch("placed")
    UpdateIconCooldown(icon)
    EndIconRefreshBatch()
end

function CDMIcons.OnIconRowConfigApplied(icon, rowConfig)
    ConfigureIcon(icon, rowConfig)
end

function CDMIcons.OnFactoryIconCreated(icon, entry)
    if not icon then return end
    UpdateIconProfessionQuality(icon)
end

function CDMIcons.OnFactoryIconAcquired(icon, entry, reused)
    if not icon then return end
    if reused then
        CancelCooldownExpiryRefresh(icon)
        _resolverRuntimePolicy.StopCustomBarActiveGlow(icon)
        UpdateIconProfessionQuality(icon)
    end
    if _G.QUI_CDM_CHARGE_DEBUG then
        ChargeDebug(entry and entry.name, "ACQUIRE",
            reused and "reused" or "new",
            "viewerType=", entry and entry.viewerType)
    end
    if entry and entry.viewerType ~= "buff" then
        UpdateIconSecureAttributes(icon, entry, entry.viewerType)
    end
    if CDMIcons.EventTraceMaybeProbeIcon then
        CDMIcons.EventTraceMaybeProbeIcon(icon)
    end
end

function CDMIcons.OnFactoryIconReleased(icon)
    if not icon then return end
    local entry = icon._spellEntry
    if _G.QUI_CDM_CHARGE_DEBUG then
        ChargeDebug(entry and entry.name, "RELEASE",
            "viewerType=", entry and entry.viewerType,
            "shown=", icon.IsShown and icon:IsShown())
    end
    CancelCooldownExpiryRefresh(icon)
    if ns.CDMRuntimeStore and ns.CDMRuntimeStore.ClearFrame then
        ns.CDMRuntimeStore.ClearFrame(icon)
    end
    UnmirrorBlizzCooldown(icon)
    if ns._OwnedGlows and ns._OwnedGlows.ClearPandemicState then
        ns._OwnedGlows.ClearPandemicState(icon)
    end
    -- Keybind and rotation-helper overlays are parented to pooled icons.
    -- Clear them before the factory recycles the frame into another viewer.
    if _G.QUI_ClearKeybindIconState then
        _G.QUI_ClearKeybindIconState(icon)
    end
    _resolverRuntimePolicy.StopCustomBarActiveGlow(icon)
    ClearIconProfessionQuality(icon)
    if icon.clickButton and not InCombatLockdown() then
        ClearClickButtonAttributes(icon.clickButton)
        icon.clickButton:Hide()
    end
end

function CDMIcons.OnContainerIconInteractionRestored(icon, viewerType)
    if not icon then return end
    UpdateIconSecureAttributes(icon, icon._spellEntry, viewerType)
end

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
        local itemID = Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID("player", entry.id)
        if itemID then
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
            return itemName or "Trinket (Slot " .. tostring(entry.id) .. ")"
        end
        return "Trinket (Slot " .. tostring(entry.id) .. ")"
    end
    if entry.type == "item" then
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(entry.id)
        return itemName or "Item #" .. tostring(entry.id)
    end
    local info = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(entry.id)
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

    -- Resolve the active profile/spec-aware bucket so the options UI, runtime
    -- renderer, and mutations all operate on the same saved table.
    local customData = GetCustomData(trackerKey)
    if not customData then return false end
    if customData.enabled == nil then customData.enabled = true end
    if customData.placement ~= "before" and customData.placement ~= "after" then
        customData.placement = "after"
    end
    if type(customData.entries) ~= "table" then
        customData.entries = {}
    end

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

function CustomCDM:SetEntryPosition(trackerKey, entryIndex, position)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries or not customData.entries[entryIndex] then return false end

    if position ~= nil then
        position = tonumber(position)
        if not position or position < 1 then
            return false
        end
        position = math.floor(position + 0.5)
    end

    customData.entries[entryIndex].position = position
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
    return true
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
    local fromData = GetCustomData(fromTrackerKey)
    if not fromData or not fromData.entries then return end
    if entryIndex < 1 or entryIndex > #fromData.entries then return end

    local entry = fromData.entries[entryIndex]

    local toData = GetCustomData(toTrackerKey)
    if not toData then return end
    if not toData.entries then toData.entries = {} end

    -- Duplicate check in destination
    for _, existing in ipairs(toData.entries) do
        if entry.type == "macro" then
            if existing.type == "macro" and existing.macroName == entry.macroName then return end
        else
            if existing.type == entry.type and existing.id == entry.id then return end
        end
    end

    table.remove(fromData.entries, entryIndex)
    toData.entries[#toData.entries + 1] = entry

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end


-- Legacy compat: GetIcons returns the pool for a viewer name.
-- Return empty for unknown viewer names so external callers cannot adopt and
-- reposition addon-owned icons onto the Blizzard viewers.
function CustomCDM:GetIcons(viewerName)
    -- Only return icons when asked for addon-owned container names.
    if viewerName == "QUI_EssentialContainer" then
        return iconPools["essential"] or {}
    elseif viewerName == "QUI_UtilityContainer" then
        return iconPools["utility"] or {}
    end
    return {}
end

function CustomCDM:UpdateAllCooldowns() CDMIcons:UpdateAllCooldowns() end

---------------------------------------------------------------------------
-- RANGE INDICATOR
-- Tints CDM icon textures red when the spell/item is out of range,
-- matching action-bar behavior. Uses C_Spell.IsSpellInRange for spells.
-- Event-driven only; no periodic range/usability OnUpdate is installed.
---------------------------------------------------------------------------
local rangePolicy = ns.CDMIconRangePolicy and ns.CDMIconRangePolicy.Create({
    getDB = GetDB,
    resolveSettings = function(viewerType, cachedDB)
        return (cachedDB and (cachedDB[viewerType] or (cachedDB.containers and cachedDB.containers[viewerType])))
            or GetTrackerSettings(viewerType)
    end,
    querySpellInRange = function(...)
        return Sources and Sources.QuerySpellInRange and Sources.QuerySpellInRange(...)
    end,
    querySpellUsable = function(...)
        return Sources and Sources.QuerySpellUsable and Sources.QuerySpellUsable(...)
    end,
    querySpellHasRange = function(...)
        return Sources and Sources.QuerySpellHasRange and Sources.QuerySpellHasRange(...)
    end,
    enableSpellRangeCheck = function(...)
        return Sources and Sources.EnableSpellRangeCheck and Sources.EnableSpellRangeCheck(...)
    end,
    cooldownHasVisualPriority = function(icon, entry, settings)
        return _resolverRuntimePolicy.CooldownHasVisualPriority(icon, entry, settings, GetTime())
    end,
    resolveCooldownActivityState = function(icon, entry, settings)
        return _resolverRuntimePolicy.ResolveIconCooldownActivityState(icon, entry, settings, GetTime())
    end,
    isAuraEntry = function(entry)
        return IsAuraEntry and IsAuraEntry(entry)
    end,
})

SetStackTextWritesForBatch = function(enabled)
    if rangePolicy then
        rangePolicy:SetStackTextWritesForBatch(enabled)
    end
end

function CDMIcons.ShouldAllowStackTextWrites()
    return rangePolicy and rangePolicy:ShouldAllowStackTextWrites() or false
end

function _resolverRuntimePolicy.IconNeedsUsabilityVisualRefresh(icon, cachedDB)
    return rangePolicy and rangePolicy:IconNeedsUsabilityVisualRefresh(icon, cachedDB) or false
end

function _resolverRuntimePolicy.UpdateIconRangesForUsabilityEvent()
    if rangePolicy then
        rangePolicy:UpdateIconRangesForUsabilityEvent(iconPools)
    end
end

function CDMIcons:UpdateAllIconRanges()
    if rangePolicy then
        rangePolicy:UpdateAllIconRanges(iconPools)
    end
end

SyncSpellRangeChecks = function()
    if rangePolicy then
        rangePolicy:SyncSpellRangeChecks(iconPools)
    end
end

DisableSpellRangeChecks = function()
    if rangePolicy then
        rangePolicy:DisableSpellRangeChecks()
    end
end

local function UpdateIconsForSpellRangeEvent(spellIdentifier, isInRange, checksRange)
    if rangePolicy then
        rangePolicy:UpdateIconsForSpellRangeEvent(iconPools, spellIdentifier, isInRange, checksRange)
    end
end

local function GetItemIDForEntry(entry)
    if not entry then return nil end
    local entryType = entry.type
    if entryType == "item" then
        return (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
    end
    if (entryType == "trinket" or entryType == "slot")
        and Sources and Sources.QueryInventoryItemID then
        return Sources.QueryInventoryItemID("player", entry.id)
    end
    return nil
end

---------------------------------------------------------------------------
-- EVENT HANDLING: Update cooldowns on relevant events
---------------------------------------------------------------------------
local cdEventFrame = CreateFrame("Frame")
cdEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
cdEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
cdEventFrame:RegisterEvent("ITEM_COUNT_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
cdEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
cdEventFrame:RegisterEvent("UPDATE_MACROS")
cdEventFrame:RegisterEvent("SPELLS_CHANGED")
cdEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
cdEventFrame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
cdEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
cdEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
-- Server-side cooldown table hotfix. User /cdm composer edits flow through
-- the resolver bus CATALOG_REBUILT path, not this event.
cdEventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
-- SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_CHARGES / SPELL_UPDATE_USES,
-- UNIT_SPELLCAST_START, and
-- UNIT_SPELLCAST_SUCCEEDED are owned by cdm_resolvers.lua, which publishes
-- CDM:COOLDOWN_CHANGED / CDM:CHARGES_CHANGED. UNIT_AURA is owned by
-- cdm_spelldata.lua so the full batched aura payload is processed before
-- icons/bars refresh.

local CDM_UPDATE_COOLDOWN = "cooldown"
local CDM_UPDATE_FULL = "full"
local updateScheduler

-- Frame-based coalescing for cooldown/aura events lives in the private icon
-- update scheduler. CDMIcons keeps only a narrow scheduling adapter here.
local function CreateIconUpdateScheduler()
    local module = ns.CDMIconUpdateScheduler
    if not (module and module.Create) then return nil end
    return module.Create({
        isRuntimeEnabled = function()
            return CDMIcons:IsRuntimeEnabled()
        end,
        getTime = function()
            return GetTime()
        end,
        isInCombat = function()
            return InCombatLockdown()
        end,
        isInRaid = function()
            return IsInRaid and IsInRaid()
        end,
        getScheduler = function()
            return ns.CDMScheduler
        end,
        setTrustIsOnGCDForBatch = function(value)
            return ResolverRuntime.SetTrustIsOnGCDForBatch(value)
        end,
        updateAllCooldowns = function()
            CDMIcons:UpdateAllCooldowns()
        end,
        updateCooldownOnly = function()
            CDMIcons:UpdateCooldownOnly()
        end,
        getBars = function()
            return ns.CDMBars
        end,
    })
end

updateScheduler = CreateIconUpdateScheduler()

local function NoteFullUpdateSchedule(reason)
    fullUpdateScheduleStats.total = fullUpdateScheduleStats.total + 1
    if reason == "request" then
        fullUpdateScheduleStats.request = fullUpdateScheduleStats.request + 1
    elseif reason == "mirrorFallback" then
        fullUpdateScheduleStats.mirrorFallback = fullUpdateScheduleStats.mirrorFallback + 1
    elseif reason == "runtime" then
        fullUpdateScheduleStats.runtime = fullUpdateScheduleStats.runtime + 1
    elseif reason == "deferred" then
        fullUpdateScheduleStats.deferred = fullUpdateScheduleStats.deferred + 1
    elseif reason == "hotfix" then
        fullUpdateScheduleStats.hotfix = fullUpdateScheduleStats.hotfix + 1
    else
        fullUpdateScheduleStats.other = fullUpdateScheduleStats.other + 1
    end
end

local function ScheduleCDMUpdate(fast, mode, trustIsOnGCD, reason)
    if mode == CDM_UPDATE_FULL then
        NoteFullUpdateSchedule(reason)
    end
    if updateScheduler then
        updateScheduler:Schedule(fast, mode, trustIsOnGCD)
    end
end

local function GetCDMUpdateDelay(fast, mode)
    if updateScheduler then
        return updateScheduler:GetDelay(fast, mode)
    end
    if fast then
        return 0
    end
    return 0.05
end

local function RunDirtyBarUpdate()
    if updateScheduler then
        updateScheduler:RunDirtyBarUpdate()
    end
end

function _resolverRuntimePolicy.RefreshIndexedMirrorIcon(icon, editMode, ncdm, ncdmContainers, inCombat)
    local entry = icon and icon._spellEntry
    if not entry then return false end

    local wasAuraActive = icon._auraActive == true
    UpdateIconCooldown(icon)
    if entry.viewerType == "buff"
        and wasAuraActive ~= (icon._auraActive == true) then
        _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    end

    local containerDB = ncdm and (ncdm[entry.viewerType]
        or (ncdmContainers and ncdmContainers[entry.viewerType]))
    UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    return true
end

-- Scoping rule for event-driven broad resolves: every event that triggers
-- a broad re-resolve walks ONLY the icons whose state can be affected by
-- what that event reports on. Sweeping every icon on every event propagates
-- transient API inconsistencies (e.g., C_Spell.GetSpellCooldown briefly
-- returning isActive=false isOnGCD=nil mid-GCD, surfaced via /cdmdebug spell events)
-- into icons that should not be touched, producing visible cooldown-swipe
-- flicker on unrelated cooldown-only spells. Three scoped variants cover
-- the three event families:
--   * Aura  — UNIT_AURA pipeline
--   * Item  — BAG_UPDATE_COOLDOWN, BAG_UPDATE_DELAYED, ITEM_COUNT_CHANGED,
--             PLAYER_EQUIPMENT_CHANGED (trinket slots)
--   * Spell — CDM:COOLDOWN_CHANGED broad fallback, UNIT_SPELLCAST_SUCCEEDED,
--             CDM:CHARGES_CHANGED
--
-- The three scopes are mutually exclusive per entry: an entry is aura, item,
-- or spell. There is no unscoped "walk all" helper — that anti-pattern was
-- removed so all future event handlers have to declare what they affect.
--
-- Pipeline follow-up: ideally these helpers wouldn't iterate icons at all —
-- events would refresh the relevant pipeline state (mirror cache, bag CD
-- cache, etc.) once and icons would re-resolve via subscription. Today the
-- only state→icon notification is a direct walk, so we scope the walk by
-- entry shape instead.

-- Aura-delta scope: UNIT_AURA pipeline. An aura delta is structurally
-- relevant ONLY to aura-kind entries or cooldown-kind entries that are
-- currently in an aura-active state. Cooldown-only icons (Death Coil, any
-- spell with no aura tracking) are owned by SPELL_UPDATE_COOLDOWN /
-- SPELL_UPDATE_USABLE / cast events.
function _resolverRuntimePolicy.ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombat)
    if not (icon and entry) then return false end

    if icon._blizzMirrorCooldownID and IsAuraEntry(entry) then
        return _resolverRuntimePolicy.RefreshIndexedMirrorIcon(
            icon, editMode, ncdm, ncdmContainers, inCombat)
    end

    local wasAuraActive = icon._auraActive == true
    ApplyResolvedCooldown(icon)

    local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
    if IsAuraEntry(entry) or cType == "aura" or cType == "auraBar" then
        UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    end

    if entry.viewerType == "buff"
       and wasAuraActive ~= (icon._auraActive == true)
       and _resolverRuntimePolicy.RequestBuffIconLayoutRefresh then
        _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    end

    return true
end

-- EventTrace* helpers are provided by the load-on-demand debug addon. Runtime
-- event classification, scoped walks, and combat queues live in
-- CDMIconRuntimeRefresh; CDMIcons supplies renderer mutations as callbacks.

cdEventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    local profileStart = debugprofilestop and debugprofilestop()
    -- arg4 is forwarded for the event trace only — SPELL_UPDATE_COOLDOWN
    -- carries (spellID, baseSpellID, category, startRecoveryCategory) per
    -- SpellBookDocumentation.lua:859. The runtime refresh path stays on
    -- the 3-arg shape; only the debug trace needs startRecoveryCategory
    -- (133 = GCD) to filter out GCD-only fires.
    CDMIcons.EventTracePrint("frame-pre", event, arg1, arg2, arg3, arg4)
    _resolverRuntimePolicy.HandleRuntimeRefresh(event, arg1, arg2, arg3, self)
    CDMIcons.EventTracePrint("frame-post", event, arg1, arg2, arg3, arg4)
    if profileStart and debugprofilestop then
        CDMIcons.RecordEventProfile(event, debugprofilestop() - profileStart)
    else
        CDMIcons.RecordEventProfile(event, 0)
    end
end)

-- /cdm spell add/remove now flows through the composer-driven CATALOG_REBUILT
-- bus event subscribed below; QUI no longer listens for Blizzard's standalone
-- CooldownManager settings callback because that path is unrelated to the
-- composer's owned catalog.

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Icons", frame = cdEventFrame }

-- Exporters for /qui cdm_cache reset / status.
function CDMIcons:ClearTextureCycleCache()
    wipe(_textureCycleCache)
end

function CDMIcons:RequestFullUpdate()
    if not CDMIcons:IsRuntimeEnabled() then return end
    if updateScheduler then
        updateScheduler:SetBarsDirty(true)
    end
    ScheduleCDMUpdate(true, CDM_UPDATE_FULL, nil, "request")
end

do
    local mirrorController = ns.CDMIconMirrorIndex and ns.CDMIconMirrorIndex.Create({
        isRuntimeEnabled = function()
            return CDMIcons:IsRuntimeEnabled()
        end,
        getCombatDelay = function()
            return GetCDMUpdateDelay(nil, CDM_UPDATE_COOLDOWN)
        end,
        requestFullRefresh = function()
            ScheduleCDMUpdate(true, CDM_UPDATE_FULL, nil, "mirrorFallback")
        end,
        getMirrorStateByCooldownID = function(cooldownID, category)
            local mirror = ns.CDMBlizzMirror
            return mirror and mirror.GetStateByCooldownID
                and mirror.GetStateByCooldownID(cooldownID, category)
                or nil
        end,
        storeMirrorStateForIcon = StoreCachedMirrorStateForIcon,
        prepareBatch = PrepareCooldownUpdateBatch,
        setStackTextWrites = SetRefreshBatchStackTextWrites,
        beginBatch = function()
            BeginIconRefreshBatch("mirror")
        end,
        endBatch = EndIconRefreshBatch,
        drainLayoutDirty = DrainLayoutDirty,
        refreshIcon = function(icon, editMode, ncdm, ncdmContainers, inCombat)
            return _resolverRuntimePolicy.RefreshIndexedMirrorIcon(
                icon, editMode, ncdm, ncdmContainers, inCombat)
        end,
        onBound = function(icon)
            if icon._rowConfig then
                ConfigureIcon(icon, icon._rowConfig)
            end

            local entry = icon._spellEntry
            if not entry or IsAuraEntry(entry) or not _resolverRuntimePolicy.ResolveIconStackText then return end
            local stackText, stackSource, mirrorBacked = _resolverRuntimePolicy.ResolveIconStackText(icon)
            if not mirrorBacked then return end
            if _resolverRuntimePolicy.ValueIsPresent(stackText) then
                local settings = GetTrackerSettings
                    and GetTrackerSettings(entry.viewerType)
                    or nil
                _resolverRuntimePolicy.ShowIconStackText(
                    icon, stackText, settings, stackSource or "mirror-bind-stack")
                icon._lastMirrorStackTextEpoch = icon.stackTextEpoch
            else
                ClearIconStackText(icon, "mirror-bind-empty")
            end
        end,
    })

    function CDMIcons.RebuildBlizzMirrorIconIndex()
        if mirrorController then
            mirrorController:Rebuild(iconPools)
        end
    end

    function CDMIcons.OnFactoryMirrorBound(icon, cooldownID, category)
        if mirrorController then
            mirrorController:BindIcon(icon, cooldownID, category)
        end
    end

    function CDMIcons.OnFactoryMirrorUnbound(icon)
        if mirrorController then
            mirrorController:UnbindIcon(icon)
        end
    end

    function CDMIcons:RequestMirrorTextRefresh(cooldownID, category)
        if mirrorController then
            mirrorController:RequestRefresh(cooldownID, category)
        end
    end

    function CDMIcons:GetCacheStats()
        local n = 0
        for _ in pairs(_textureCycleCache) do n = n + 1 end
        local activePools = 0
        local activeIcons = 0
        for _, pool in pairs(iconPools) do
            activePools = activePools + 1
            activeIcons = activeIcons + #pool
        end
        local mirrorIndexKeys, mirrorIndexIcons = 0, 0
        local mirrorRefreshStats = { targeted = 0, fallback = 0, maxBatch = 0 }
        local mirrorRefreshPending = false
        local mirrorRefreshPendingKeys = 0
        if mirrorController then
            mirrorIndexKeys, mirrorIndexIcons = mirrorController:Count()
            mirrorRefreshStats = mirrorController:GetStats()
            mirrorRefreshPending = mirrorController:IsRefreshPending()
            mirrorRefreshPendingKeys = mirrorController:PendingKeyCount()
        end
        local updateStats = updateScheduler and updateScheduler:GetStats() or {}
        local iconEventProfileTop, iconEventProfileWindow = CDMIcons.SnapshotEventProfile(5)
        return {
            textureCycleCache = n,
            activeIconPools    = activePools,
            activeIcons        = activeIcons,
            recycleIcons       = #recyclePool,
            barsDirty         = updateStats.barsDirty == true,
            updatePending     = updateStats.updatePending == true,
            mirrorIndexKeys    = mirrorIndexKeys,
            mirrorIndexIcons   = mirrorIndexIcons,
            mirrorRefreshPending = mirrorRefreshPending,
            mirrorRefreshPendingKeys = mirrorRefreshPendingKeys,
            mirrorRefreshTargeted = mirrorRefreshStats.targeted,
            mirrorRefreshFallback = mirrorRefreshStats.fallback,
            mirrorRefreshMaxBatch = mirrorRefreshStats.maxBatch,
            iconEventProfileTop = iconEventProfileTop,
            iconEventProfileWindow = iconEventProfileWindow,
        }
    end
end

-- Bus subscribers — replace direct Blizzard events.
-- The resolver owns runtime event registration and publishes CDM:* events
-- when state changes. We subscribe and call the same render functions the
-- old direct path called.
--
-- Aura events set the scheduler's bar-dirty flag only when a matching icon/bar may have changed.
-- Pure cooldown events deliberately do NOT set the flag — bar fill is driven
-- by barTimerGroup independently of ScheduleCDMUpdate.
local runtimeRefresh
do
    runtimeRefresh = ns.CDMIconRuntimeRefresh and ns.CDMIconRuntimeRefresh.Create({
        isRuntimeEnabled = function()
            return CDMIcons:IsRuntimeEnabled()
        end,
        getIconPools = function()
            return iconPools
        end,
        isSecretValue = function(value)
            return issecretvalue and issecretvalue(value) or false
        end,
        gcdSpellID = GCD_SPELL_ID,
        eventTracePrint = function(...)
            return CDMIcons.EventTracePrint(...)
        end,
        eventTraceAuraInfo = function(updateInfo)
            return CDMIcons.EventTraceAuraInfo(updateInfo)
        end,
        setBarsDirty = function(dirty)
            if updateScheduler then
                updateScheduler:SetBarsDirty(dirty == true)
            end
        end,
        scheduleFullUpdate = function()
            ScheduleCDMUpdate(true, CDM_UPDATE_FULL, nil, "runtime")
        end,
        scheduleUpdate = function(fast, mode, trustIsOnGCD, reason)
            ScheduleCDMUpdate(fast, mode, trustIsOnGCD, reason or "runtime")
        end,
        prepareBatch = PrepareCooldownUpdateBatch,
        beginBatch = function(reason)
            BeginIconRefreshBatch(reason)
        end,
        endBatch = EndIconRefreshBatch,
        setStackTextWrites = SetRefreshBatchStackTextWrites,
        applyResolvedCooldown = ApplyResolvedCooldown,
        updateIconCooldown = UpdateIconCooldown,
        applyAuraScopedResolvedCooldown = function(icon, entry, editMode, ncdm, ncdmContainers, inCombat)
            return _resolverRuntimePolicy.ApplyAuraScopedResolvedCooldown(
                icon, entry, editMode, ncdm, ncdmContainers, inCombat)
        end,
        resolveContainerDBAndType = ResolveContainerDBAndType,
        updateContainerVisibility = UpdateCooldownContainerVisibility,
        syncCooldownBling = SyncCooldownBling,
        drainLayoutDirty = DrainLayoutDirty,
        isAuraEntry = function(entry)
            return IsAuraEntry and IsAuraEntry(entry)
        end,
        getMirrorStateByCooldownID = function(cooldownID, category)
            local mirror = ns.CDMBlizzMirror
            return mirror and mirror.GetStateByCooldownID
                and mirror.GetStateByCooldownID(cooldownID, category)
        end,
        getItemIDForEntry = GetItemIDForEntry,
        queryItemSpell = function(itemID)
            if Sources and Sources.QueryItemSpell then
                return Sources.QueryItemSpell(itemID)
            end
        end,
        queryCooldownAuraBySpellID = function(spellID)
            if Sources and Sources.QueryCooldownAuraBySpellID then
                return Sources.QueryCooldownAuraBySpellID(spellID)
            end
        end,
        clearDurationBinding = function(icon)
            icon._lastDurObjKey = nil
            icon._lastDurObj = nil
            icon._lastResolvedMode = nil
            icon._lastResolvedSourceID = nil
            icon._lastResolvedSpellID = nil
        end,
        updateIconRangesForUsabilityEvent = function()
            _resolverRuntimePolicy.UpdateIconRangesForUsabilityEvent()
        end,
        resetTrustedGCDSnapshot = function()
            return ResolverRuntime.ResetTrustedGCDSnapshot(GetTime())
        end,
        captureTrustedGCDStateForIcon = function(icon, spellState, stamp)
            return _resolverRuntimePolicy.CaptureTrustedGCDStateForIcon(icon, spellState, stamp)
        end,
        captureTrustedGCDState = function()
            return _resolverRuntimePolicy.CaptureTrustedGCDState()
        end,
        setTrustIsOnGCDForBatch = function(value)
            return ResolverRuntime.SetTrustIsOnGCDForBatch(value)
        end,
        requestStackTextUpdate = function()
            RequestStackTextUpdate()
        end,
        noteChargeDurationObjectsUpdated = function()
            if RuntimeQueries and RuntimeQueries.NoteChargeDurationObjectsUpdated then
                RuntimeQueries.NoteChargeDurationObjectsUpdated()
            end
        end,
        recordRecentPlayerSpellCast = function(spellID)
            if RecordRecentPlayerSpellCast then
                RecordRecentPlayerSpellCast(spellID)
            end
        end,
        getHighlighter = function()
            return ns._OwnedHighlighter
        end,
        runDirtyBarUpdate = RunDirtyBarUpdate,
        onRuntimeDisabled = function(frame)
            frame = frame or cdEventFrame
            if frame and frame.SetScript then
                frame:SetScript("OnUpdate", nil)
            end
            if updateScheduler then
                updateScheduler:Cancel()
            end
            DisableSpellRangeChecks()
        end,
        updateAllIconRanges = function()
            CDMIcons:UpdateAllIconRanges()
        end,
        chargeDebug = function(...)
            if _G.QUI_CDM_CHARGE_DEBUG then
                ChargeDebug(...)
            end
        end,
        invalidateMacroCache = InvalidateMacroCache,
        updateIconsForSpellRangeEvent = UpdateIconsForSpellRangeEvent,
        clearTextureCycleCache = function()
            wipe(_textureCycleCache)
        end,
        clearDurationBindingKeyCache = function()
            _resolverRuntimePolicy.ClearDurationBindingKeyCache()
        end,
        clearStableCaches = function()
            if RuntimeQueries and RuntimeQueries.ClearStableCaches then
                RuntimeQueries.ClearStableCaches()
            end
        end,
        isPlayerInCombat = function()
            return InCombatLockdown and InCombatLockdown() or false
        end,
        getCombatQueueDelay = function()
            return updateScheduler and updateScheduler:GetCombatQueueDelay() or 0.3
        end,
    })

    function _resolverRuntimePolicy.HandleRuntimeRefresh(event, arg1, arg2, arg3, frame)
        if runtimeRefresh then
            return runtimeRefresh:Handle(event, arg1, arg2, arg3, frame)
        end
    end
end

function CDMIcons.HandleRuntimeRefresh(event, arg1, arg2, arg3)
    return _resolverRuntimePolicy.HandleRuntimeRefresh(event, arg1, arg2, arg3)
end

local function OnCDMCooldownChanged(_, spellID, baseSpellID, kind)
    if runtimeRefresh then
        return runtimeRefresh:HandleCooldownChanged(_, spellID, baseSpellID, kind)
    end
end

local function OnCDMChargesChanged(_, spellID)
    if runtimeRefresh then
        return runtimeRefresh:HandleChargesChanged(_, spellID)
    end
end

ns.CDMResolvers.Subscribe("CDM:COOLDOWN_CHANGED", OnCDMCooldownChanged)
ns.CDMResolvers.Subscribe("CDM:CHARGES_CHANGED", OnCDMChargesChanged)

-- The event frame never owns a periodic visual poller.
cdEventFrame:SetScript("OnUpdate", nil)

function CDMIcons:DisableRuntime()
    cdEventFrame:UnregisterAllEvents()
    cdEventFrame:SetScript("OnEvent", nil)
    cdEventFrame:SetScript("OnUpdate", nil)
    if updateScheduler then
        updateScheduler:Cancel()
        updateScheduler:SetBarsDirty(false)
    end
    DisableSpellRangeChecks()
end

---------------------------------------------------------------------------
-- DEBUG IMPORT BINDING
-- ChargeDebug is a placeholder until the load-on-demand debug addon rebinds it
-- via BindAll(). Hot-path callers keep their existing `ChargeDebug(...)`
-- upvalue calls.
---------------------------------------------------------------------------
function CDMIcons._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        ChargeDebug           = d.Charge or ChargeDebug
        CDMIcons._ShouldDebugBlizzEntry = d.ShouldBlizz or CDMIcons._ShouldDebugBlizzEntry
        CDMIcons._FormatMirrorState     = d.FormatMirrorState or CDMIcons._FormatMirrorState
        CDMIcons._DebugBlizzEntry       = d.Blizz or CDMIcons._DebugBlizzEntry
    end
end
end
