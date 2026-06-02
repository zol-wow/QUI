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
---@type fun(...)
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
