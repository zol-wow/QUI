-- Each `do -- Inlined from X ... end` block is a self-contained chunk that

do
-- Inlined from cdm_icon_stack_text.lua
local _, ns = ...

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
        return true -- @secret-policy: route-to-text-sink
    end
    if type(text) == "string" then
        return text ~= ""
    end
    return text ~= nil
end

function CDMIconStackText.ValueIsPresent(value)
    if issecretvalue(value) then
        return true -- @secret-policy: opaque-value-present
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
    icon.StackText.SetText(icon.StackText, value)
    icon.StackText.Show(icon.StackText)

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

    return true
end
end

do
-- Inlined from cdm_icon_stack_policy.lua
local _, ns = ...

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
        return true -- @secret-policy: route-to-text-sink
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

    local function IsAuraEntry(entry)
        return callbacks.isAuraEntry and callbacks.isAuraEntry(entry) or false
    end

    local function IsBuiltinAuraContainerKey(containerKey)
        return callbacks.isBuiltinAuraContainerKey
            and callbacks.isBuiltinAuraContainerKey(containerKey)
            or false
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
            return true -- @secret-policy: opaque-value-present
        end
        return value ~= nil
    end

    function controller:ValueIsMissing(value)
        return not controller:ValueIsPresent(value)
    end

    local function AuraCountTextHasDisplay(value)
        if issecretvalue(value) then
            return true -- @secret-policy: route-to-text-sink
        end
        if type(value) == "number" then
            return value > 0
        end
        if type(value) == "string" then
            return value ~= "" and value ~= "0"
        end
        return value ~= nil
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
        if issecretvalue(apps) then
            return nil -- @secret-policy: reject-secret-value
        end
        if apps == nil then return nil end

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

        return nil
    end

    function controller:GetAuraApplicationsForInstance(unit, auraInstanceID, source, minApplications)
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
            local displayText = spellCount
            if C_StringUtil and C_StringUtil.TruncateWhenZero then
                displayText = C_StringUtil.TruncateWhenZero(spellCount)
            end
            return displayText, "spell-cast-count"
        end

        if type(spellCount) ~= "number" then return nil end
        if spellCount <= 0 then return nil end

        local displayText = spellCount
        if C_StringUtil and C_StringUtil.TruncateWhenZero then
            displayText = C_StringUtil.TruncateWhenZero(spellCount)
        end
        if not controller:TextHasDisplay(displayText) then -- @secret-safe: TextHasDisplay probes issecretvalue before any truth-test (round-13 hand-audit)
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
        if controller:ValueIsMissing(spellID) then
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

        local resolvedApps, resolvedSource = controller:ResolveAuraApplicationsForEntry(spellID, entry, icon)
        if controller:ValueIsPresent(resolvedApps) then
            return resolvedApps, resolvedSource
        end

        return nil
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
                if resolved and AuraCountTextHasDisplay(stacks) then
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

        local svDB = callbacks.getChargeMetadataDB and callbacks.getChargeMetadataDB() or nil
        local maxC = svDB and svDB[sid]
        if not maxC or maxC <= 1 then
            return controller:GetSpellCountForEntry(sid, entry, icon)
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
        if sink and sink.Show then
            sink.Show(icon, value, reason)
        else
            icon.StackText.SetText(icon.StackText, value)
            icon.StackText.Show(icon.StackText)
            icon._stackTextSource = reason
        end
        if _G.QUI_CDM_CHARGE_DEBUG then
            if callbacks.debugStackText then
                callbacks.debugStackText(icon, "show", value, reason)
            end
            if callbacks.chargeDebug then
                callbacks.chargeDebug(icon._spellEntry and icon._spellEntry.name,
                    "STACKTEXT apply", "reason=", reason or "nil")
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
            if showZero or AuraCountTextHasDisplay(stackValue) then
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

        if AuraCountTextHasDisplay(displayText) then
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

    return controller
end
end

do
-- Inlined from cdm_icon_item_visual_policy.lua
local _, ns = ...

local CDMIconItemVisualPolicy = {}
ns.CDMIconItemVisualPolicy = CDMIconItemVisualPolicy
local Shared = ns.CDMShared

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
        local containerDB = Shared and Shared.GetContainerDB
            and Shared.GetContainerDB(viewerType)
        if not containerDB and ncdm and ncdm.containers then
            containerDB = ncdm.containers[viewerType]
        end
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

    local function applyItemTextureIfChanged(icon, itemID)
        local texture = controller:GetItemTexture(itemID)
        if texture and texture ~= icon._lastTexture then
            icon.Icon:SetTexture(texture)
            icon._lastTexture = texture
            return true
        end
        return false
    end

    function controller:RefreshInventoryItemVisuals(icon, entry, itemID)
        if not (icon and entry and itemID and icon.Icon) then return false end
        if applyItemTextureIfChanged(icon, itemID) then
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
            if applyItemTextureIfChanged(icon, itemID) then
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

        if containerDB.showOnlyInCombat and not inCombat then
            return true
        end

        if containerDB.showOnlyOnCooldown or containerDB.showOnlyWhenOffCooldown then
            local cooldownState = callbacks.resolveCooldownActivityState
                and callbacks.resolveCooldownActivityState(icon, entry, containerDB)
                or {}
            local effectiveOnCD = cooldownState.gcdOnly ~= true
                and (cooldownState.isOnCooldown or cooldownState.rechargeActive)

            if containerDB.showOnlyOnCooldown and not effectiveOnCD then
                return true
            end

            if containerDB.showOnlyWhenOffCooldown and effectiveOnCD then
                return true
            end
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
        icon._lastLayoutFilterHidden = filterHidesNow and true or false
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
    if issecretvalue and issecretvalue(value) then return nil end -- @secret-policy: reject-secret-ids
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
        itemUsableCycleCache = {},
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

    local function queryReadableUsable(query, id)
        if not id or not query then return true, false end
        local usable, noMana = query(id)
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
            local usabilityID = spellID
            local usabilityQuery = callbacks.querySpellUsable
            local usabilityCache = controller.usableCycleCache
            if entry.type == "consumable" and callbacks.queryItemUsable and callbacks.getItemIDForEntry then
                local itemID = callbacks.getItemIDForEntry(entry)
                if itemID then
                    usabilityID = itemID
                    usabilityQuery = callbacks.queryItemUsable
                    usabilityCache = controller.itemUsableCycleCache
                end
            end

            local isUsable = usabilityCache[usabilityID]
            if isUsable == nil then
                isUsable = queryReadableUsable(usabilityQuery, usabilityID)
                usabilityCache[usabilityID] = isUsable
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
        wipe(controller.itemUsableCycleCache)
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

local CDMIconCooldownPolicy = {}
ns.CDMIconCooldownPolicy = CDMIconCooldownPolicy

function CDMIconCooldownPolicy.Create()
    local controller = {}

    function controller:MarkGCDSwipe(icon)
        if not icon then return end
        icon._showingGCDSwipe = true
        icon._showingRealCooldownSwipe = nil
    end

    function controller:ClearGCDSwipe(icon)
        if not icon then return end
        icon._showingGCDSwipe = nil
    end

    return controller
end
end

do
-- Inlined from cdm_icon_custom_bar_policy.lua
local _, ns = ...

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
        if issecretvalue and issecretvalue(value) then return false end -- @secret-policy: reject-secret-value
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
        if entry.type == "consumable" then
            local itemID = sources and sources.QueryConsumableCategoryItem
                and sources.QueryConsumableCategoryItem(entry.id)
            itemID = itemID
                or (ns.CDMCatalog and ns.CDMCatalog.GetConsumableCategoryItemID
                    and ns.CDMCatalog.GetConsumableCategoryItemID(entry.id))
            if itemID and sources and sources.QueryItemCount then
                local count = sources.QueryItemCount(itemID, false, containerDB and containerDB.showItemCharges == true, true)
                if issecretvalue and issecretvalue(count) then
                    return true -- @secret-policy: opaque-value-present
                end
                if type(count) == "number" then
                    return count > 0
                end
            end
            return true
        elseif entry.type == "item" then
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
                    return true -- @secret-policy: keep-visible-when-unknown
                end
                return count and count > 0
            end
            return true
        elseif entry.type == "trinket" or entry.type == "slot" then
            local equippedItemID = sources and sources.QueryInventoryItemID and sources.QueryInventoryItemID("player", entry.id)
            if not equippedItemID then return false end
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
                layoutVisible = cooldown.gcdOnly ~= true
                    and (cooldown.isOnCooldown or cooldown.rechargeActive)
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
                    icon._customBarProcGlowMask:SetTexture((ns.Helpers and ns.Helpers.AssetPath or "Interface\\AddOns\\QUI\\assets\\") .. "iconskin\\ProcGlowMask")
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
                icon.Cooldown:SetSwipeColor(0, 0, 0, 0.6)
            else
                icon.Cooldown:SetSwipeColor(0, 0, 0, 0)
            end
        elseif (icon._customBarActive or icon._resolvedCooldownMode == "aura")
            and icon._lastAuraDurObj and containerDB.showAuraSwipe == true
            and ns.CDMRenderers and ns.CDMRenderers.ApplyDurationObjectCooldown then
            icon.Cooldown:SetDrawEdge(false)
            icon.Cooldown:SetSwipeColor(0, 0, 0, 0.6)
            icon.Cooldown:SetDrawSwipe(true)
            ns.CDMRenderers.ApplyDurationObjectCooldown(icon.Cooldown, icon._lastAuraDurObj, true, false)
        elseif not icon._customBarActive
            and not (cooldownState and cooldownState.isOnCooldown == true) then
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
