local _, ns = ...
local Helpers = ns.Helpers
local Resolvers = ns.CDMResolvers
local Sources = ns.CDMSources

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local CDMIconFactory = {}
ns.CDMIconFactory = CDMIconFactory

local function GetIcons()
    return ns.CDMIcons
end

local GetGeneralFont        = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local GetEntryTexture       = Resolvers.GetEntryTexture
local GetSpellTexture       = Resolvers.GetSpellTexture

local InCombatLockdown = InCombatLockdown
local CreateFrame      = CreateFrame
local type             = type

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

local function ResolveTooltipContext(owner, fallbackContext)
    if not owner then return fallbackContext or "cdm" end
    return owner._quiTooltipContext
        or owner.__quiTooltipContext
        or (owner.__customTrackerIcon and "customTrackers")
        or fallbackContext
        or "cdm"
end

function CDMIconFactory.HideEntryTooltip()
    if GameTooltip and GameTooltip.Hide then
        GameTooltip.Hide(GameTooltip)
    end
end

local function AnchorEntryTooltip(owner, tooltipSettings)
    if tooltipSettings and tooltipSettings.anchorToCursor then
        local anchorTooltip = ns.QUI_AnchorTooltipToCursor
        if anchorTooltip then
            anchorTooltip(GameTooltip, owner, tooltipSettings)
        else
            GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        end
    else
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    end
end

local WoW_IsSecretValue = issecretvalue

local function AuraCarrierFields(frame)
    if WoW_IsSecretValue and WoW_IsSecretValue(frame) then return nil end -- @secret-policy: reject-secret-value (a secret frame ref cannot be indexed for aura fields)
    if type(frame) ~= "table" then return nil end
    local auraInstanceID = frame.auraInstanceID
    if WoW_IsSecretValue and WoW_IsSecretValue(auraInstanceID) then return nil end -- @secret-policy: reject-secret-ids (secret in combat; tooltip accessor would hard-error)
    if type(auraInstanceID) == "nil" then return nil end
    local unit = frame.auraDataUnit
    if WoW_IsSecretValue and WoW_IsSecretValue(unit) then return nil end -- @secret-policy: reject-secret-value
    if type(unit) ~= "string" then return nil end
    return unit, auraInstanceID
end

local function ResolveAuraCarrier(owner)
    local unit, auraInstanceID = AuraCarrierFields(owner)
    if unit then return unit, auraInstanceID end
    unit, auraInstanceID = AuraCarrierFields(owner._quiCdmLive)
    if unit then return unit, auraInstanceID end
    if owner.GetParent then
        unit, auraInstanceID = AuraCarrierFields(owner:GetParent())
        if unit then return unit, auraInstanceID end
    end
    return nil
end

function CDMIconFactory.ShowEntryTooltip(owner, entry, tooltipContext)
    if not (owner and entry and GameTooltip) then return false end
    if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return false end

    tooltipContext = ResolveTooltipContext(owner, tooltipContext)
    local tooltipProvider = ns.TooltipProvider
    if tooltipProvider then
        if tooltipProvider.IsOwnerFadedOut
           and tooltipProvider:IsOwnerFadedOut(owner)
           and not IsMouseoverRevealContext(tooltipContext) then
            CDMIconFactory.HideEntryTooltip()
            return false
        end
        if tooltipProvider.ShouldShowTooltip
           and not tooltipProvider:ShouldShowTooltip(tooltipContext) then
            CDMIconFactory.HideEntryTooltip()
            return false
        end
    end

    local tooltipSettings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.tooltip
    if (not tooltipProvider) and tooltipSettings and tooltipSettings.hideInCombat and InCombatLockdown() then
        return false
    end
    AnchorEntryTooltip(owner, tooltipSettings)

    local auraShown = false
    local setAuraByInstance = GameTooltip.SetUnitAuraByAuraInstanceID
    if setAuraByInstance then
        local auraUnit, auraInstanceID = ResolveAuraCarrier(owner)
        if auraUnit then
            -- Auras can be secret in combat; from tainted execution the
            -- accessor hard-errors instead of returning nil.
            local ok, shown = pcall(setAuraByInstance, GameTooltip, auraUnit, auraInstanceID,
                "INCLUDE_NAME_PLATE_ONLY")
            auraShown = (ok and shown) and true or false
            if not auraShown then
                AnchorEntryTooltip(owner, tooltipSettings)
            end
        end
    end

    if not auraShown then
        local sid = owner._activeAuraSpellID
        if not sid then
            sid = owner._runtimeSpellID
        end
        if not sid and ns.CDMSpellData and ns.CDMSpellData.ResolveDisplaySpellID then
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
    end

    local srcSpecID = entry._sourceSpecID
    if type(srcSpecID) == "number" and GetSpecializationInfoByID then
        local _, specName, _, _, _, classToken = GetSpecializationInfoByID(srcSpecID)
        if specName then
            local label = classToken and ("%s %s"):format(specName, classToken) or specName
            local formatText = (ns.L and ns.L["Source: %s"]) or "Source: %s"
            GameTooltip.AddLine(GameTooltip, formatText:format(label), 0.75, 0.85, 1, true)
        end
    end
    GameTooltip.Show(GameTooltip)
    return true
end

local iconPools = {
    essential = {},
    utility   = {},
    buff      = {},
}
local recyclePool = {}
local recycleProtectedPool = {}
local iconCounter = 0

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_iconRecyclePool", tbl = recyclePool }
    mp[#mp + 1] = { name = "CDM_iconRecycleProtectedPool", tbl = recycleProtectedPool }
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
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

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
        local kept
        for _, icon in ipairs(pool) do
            if self:ReleaseIcon(icon) == false then
                kept = kept or {}
                kept[#kept + 1] = icon
            end
        end
        wipe(pool)
        if kept then
            for i = 1, #kept do
                pool[i] = kept[i]
            end
        end
    else
        iconPools[viewerType] = CreateIconPool()
    end
    return iconPools[viewerType]
end

function CDMIconFactory:PoolHasProtectedIcon(viewerType)
    local pool = iconPools[viewerType]
    if not pool then return false end
    for i = 1, #pool do
        local icon = pool[i]
        if icon and icon.clickButton ~= nil then
            return true
        end
    end
    return false
end

CDMIconFactory._iconPools   = iconPools
CDMIconFactory._recyclePool = recyclePool
CDMIconFactory._recycleProtectedPool = recycleProtectedPool

local function CreateIconBare(parent, spellEntry)
    iconCounter = iconCounter + 1
    local frameName = "QUICDMIcon" .. iconCounter

    local icon = CreateFrame("Frame", frameName, parent)
    local size = DEFAULT_ICON_SIZE
    icon:SetSize(size, size)

    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetAllPoints(icon)

    icon.Cooldown = CreateFrame("Cooldown", frameName .. "Cooldown", icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints(icon)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)
    icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    icon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    icon.Cooldown:SetDrawBling(false)
    icon._drawBlingEnabled = false
    icon.Cooldown:EnableMouse(false)

    icon.TextOverlay = CreateFrame("Frame", nil, icon)
    icon.TextOverlay:SetAllPoints(icon)
    icon.TextOverlay:SetFrameLevel(icon.Cooldown:GetFrameLevel() + 2)
    icon.TextOverlay:EnableMouse(false)

    icon.Border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    icon.Border:Hide()

    icon.DurationText = icon.TextOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.DurationText:SetPoint("CENTER")

    icon.StackText = icon.TextOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.StackText:SetPoint("BOTTOMRIGHT")

    icon.AbsorbText = icon.TextOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.AbsorbText:SetPoint("BOTTOM")
    icon.AbsorbText:Hide()

    local defaultFont = GetGeneralFont()
    local defaultOutline = GetGeneralFontOutline()
    CJKFont(icon.DurationText, defaultFont, 10, defaultOutline)
    CJKFont(icon.StackText, defaultFont, 10, defaultOutline)
    CJKFont(icon.AbsorbText, defaultFont, 10, defaultOutline)

    icon._spellEntry = spellEntry
    icon._isQUICDMIcon = true

    if spellEntry then
        local texID
        if spellEntry.type then
            texID = GetEntryTexture(spellEntry)
        else
            texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
        end
        if texID then
            icon.Icon:SetTexture(texID)
            if not spellEntry.isAura then
                icon._desiredTexture = texID
            end
        end
    end

    return icon
end

local function CreateIcon(parent, spellEntry)
    local icon = CreateIconBare(parent, spellEntry)

    if ns.HookFrameForMouseover then
        ns.HookFrameForMouseover(icon)
    end

    if spellEntry then
        local icons = GetIcons()
        if icons and icons.OnFactoryIconCreated then
            icons.OnFactoryIconCreated(icon, spellEntry)
        end
    end

    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        CDMIconFactory.ShowEntryTooltip(self, self._spellEntry)
    end)
    icon:SetScript("OnLeave", function()
        CDMIconFactory.HideEntryTooltip()
    end)

    icon:Hide()
    return icon
end

function CDMIconFactory:AcquireIcon(parent, spellEntry, clickable)
    local icons = GetIcons()
    local icon
    if clickable and ((not InCombatLockdown()) or (ns and ns._inInitSafeWindow)) then
        icon = table.remove(recycleProtectedPool)
    end
    if not icon then
        icon = table.remove(recyclePool)
    end
    if icon then
        icon:SetParent(parent)
        icon:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
        icon._spellEntry = spellEntry
        icon._isQUICDMIcon = true
        icon._lastStart = nil
        icon._lastDuration = nil
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
        icon._lastResolvedMode = nil
        icon._lastResolvedSourceID = nil
        icon._lastResolvedSpellID = nil
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

        local texID
        if spellEntry.type then
            texID = GetEntryTexture(spellEntry)
        else
            texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
        end
        if icon.Icon then
            if texID then
                icon.Icon:SetTexture(texID)
                icon._desiredTexture = (not spellEntry.isAura) and texID or nil
            else
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
        if ns._onIconAssigned then ns._onIconAssigned(icon) end
        return icon
    end
    local newIcon = CreateIcon(parent, spellEntry)
    if icons and icons.OnFactoryIconAcquired then
        icons.OnFactoryIconAcquired(newIcon, spellEntry, false)
    end
    if ns._onIconAssigned then ns._onIconAssigned(newIcon) end
    return newIcon
end

function CDMIconFactory:ReleaseIcon(icon)
    if not icon then return end
    if icon.clickButton and InCombatLockdown and InCombatLockdown()
        and not (ns and ns._inInitSafeWindow) then
        return false
    end
    local icons = GetIcons()
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
    icon._lastDurObjKey = nil
    icon._lastDurObj = nil
    icon._lastResolvedMode = nil
    icon._lastResolvedSourceID = nil
    icon._lastResolvedSpellID = nil
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

    if icon.clickButton ~= nil then
        icon:SetParent(UIParent)
        recycleProtectedPool[#recycleProtectedPool + 1] = icon
    elseif #recyclePool < MAX_RECYCLE_POOL_SIZE then
        icon:SetParent(UIParent)
        recyclePool[#recyclePool + 1] = icon
    end
    return true
end

local function SyncCooldownBling(icon)
    if not icon or not icon.Cooldown or not icon.Cooldown.SetDrawBling then return end
    if icon._drawBlingEnabled ~= false then
        icon._drawBlingEnabled = false
        icon.Cooldown:SetDrawBling(false)
    end
end

CDMIconFactory.SyncCooldownBling = SyncCooldownBling

function CDMIconFactory.AcquireForPreview(parent, spellEntry)
    local icon = CreateIconBare(parent, spellEntry)
    icon._isPreview = true
    icon:EnableMouse(false)
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
end
