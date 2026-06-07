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
        local chargeCountFrameShown, chargeCountFrameShownSecret =
            BooleanOrSecret(m and m.chargeCountFrameShown)
        local chargeTextOwnerShown, chargeTextOwnerShownSecret =
            BooleanOrSecret(m and m.chargeTextOwnerShown)
        -- Secret show gates are not decoded here. Keep them intact so the
        -- FontString alpha sink can evaluate them with C_CurveUtil and avoid
        -- hiding valid cast-count text from a stale clean parent frame state.
        if BooleanOrSecretIsPresent(cooldownChargesShown, cooldownChargesShownSecret) then
            return cooldownChargesShown, cooldownChargesShownSecret
        end
        if BooleanOrSecretIsPresent(chargeTextOwnerShown, chargeTextOwnerShownSecret) then
            return chargeTextOwnerShown, chargeTextOwnerShownSecret
        end
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

    -- The borrowed cross-category aura applications value is captured from the
    -- source child via two owners -- the raw SetText(number) argument and the
    -- rendered owner:GetText() string -- which alternate per UNIT_AURA. Returning
    -- a numeric value verbatim makes the essential icon's count flip secret-number
    -- <-> secret-string every refresh (a visible flicker). Coerce a numeric value
    -- to the rendered string the buff icon shows (C_StringUtil.TruncateWhenZero,
    -- the secret-safe number->display path the working aura-stack write uses), so
    -- consecutive frames write a stable glyph. type() is safe on secret values.
    -- NOTE: scoped to the carried aura value only -- coercing the resolver's other
    -- return paths regressed the buff icon and the host ChargeCount, so don't.
    local function StabilizeMirrorAuraStackText(value)
        if type(value) == "number" and C_StringUtil and C_StringUtil.TruncateWhenZero then
            return C_StringUtil.TruncateWhenZero(value)
        end
        return value
    end

    local function ResolveMirrorStackTextFromState(m, cooldownChargeAuthority, auraRenderActive)
        -- Cross-category aura: the host child carries only its own (chargeless)
        -- ChargeCount text, but the borrowed aura's real applications text was
        -- captured from the source child onto auraStackText (see
        -- CaptureAuraInstanceFromChildFrame). Prefer it so the essential icon
        -- shows the same count the buff/tracked icon shows. A secret value
        -- renders fine via SetText (the source icon proves it); only the
        -- chargeless ChargeCount secret paints blank.
        --
        -- Gated on auraRenderActive: the carried count belongs to the borrowed
        -- aura, so it must only show while the icon is actually rendering that
        -- aura. When the icon is on cooldown (debuff still up but the spell's
        -- own cooldown is showing) or the viewer is configured not to show the
        -- aura phase, the resolved mode is not "aura" and the count stays off.
        if auraRenderActive
            and controller:ValueIsPresent(m.auraStackText)
            and SafeBoolean(m.auraStackTextShown) ~= false then
            return StabilizeMirrorAuraStackText(m.auraStackText),
                m.auraStackTextSource or "Applications", nil, true, m.auraStackTextShown
        end

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
            local source = m.stackTextSource or "Applications"
            local visibilityGate
            if source ~= "ChargeCount" then
                visibilityGate = m.stackTextShown
            end
            return stackText, source, nil, true, visibilityGate
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

    local function AuraCountTextHasDisplay(value)
        if issecretvalue(value) then
            return true
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

        -- C-side display-count sink first: it accepts the (possibly secret) instance
        -- ID and returns a secret-safe display string we forward verbatim to SetText
        -- -- a secret applications value is never Lua-compared. minDisplayCount = 1 so
        -- abilities that count from 1 (e.g. Reaper's Mark) show their stack.
        local auraInstanceID = callbacks.getAuraDataInstanceID
            and callbacks.getAuraDataInstanceID(auraData)
            or auraData.auraInstanceID
        local sources = Sources()
        if auraInstanceID and sources and sources.QueryAuraApplicationDisplayCount then
            local stacks = sources.QueryAuraApplicationDisplayCount(unit or "player", auraInstanceID, 1, 99)
            if AuraCountTextHasDisplay(stacks) then
                return stacks, "display-count"
            end
        end

        -- No instance to query (out-of-combat name/data fallbacks only): a confirmed
        -- non-secret count. GetDisplayableAuraApplicationsFromData secret-guards before
        -- its Lua comparison, so a secret value never reaches a Lua compare here either.
        local apps = controller:GetDisplayableAuraApplicationsFromData(auraData)
        if controller:ValueIsPresent(apps) then
            return apps, source
        end

        return nil
    end

    function controller:GetAuraApplicationsForInstance(unit, auraInstanceID, source, minApplications)
        local sources = Sources()
        if not (unit and auraInstanceID and sources and sources.QueryAuraApplicationDisplayCount) then
            return nil
        end

        local stacks = sources.QueryAuraApplicationDisplayCount(unit, auraInstanceID, minApplications or 1, 99)
        if AuraCountTextHasDisplay(stacks) then
            return stacks, source or "display-count"
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
        local auraRenderActive = icon and icon._resolvedCooldownMode == "aura"
        local stackText, stackSource, stackHidden, hasState =
            ResolveMirrorStackTextFromState(m, cooldownChargeAuthority, auraRenderActive)
        return stackText, stackSource, true, stackHidden, hasState
    end

    function controller:ResolveIconStackText(icon)
        if not icon or not icon._spellEntry then
            return nil, nil
        end
        local entry = icon._spellEntry

        if IsAuraEntry(entry) then
            -- Mirror-primary. A mirror-backed aura's captured frame text is the
            -- authoritative source in combat: target-debuff C_UnitAuras data is
            -- restricted there, so the live GetApplications query returns nothing
            -- even for a debuff that genuinely stacks (e.g. Reaper's Mark). The
            -- Blizzard CDM mirror child captured the rendered count, so prefer it.
            -- The secret stack value forwards verbatim to the FontString -- it is
            -- never Lua-compared (a secret applications value can't be). This is
            -- the same frame text the essential icon borrows via the cross-category
            -- carry; the live query below is only the out-of-combat / non-mirrored
            -- fallback.
            local mirrorText, mirrorSource, mirrorBacked, mirrorStackHidden =
                controller:ResolveMirrorStackText(icon)
            if controller:TextHasDisplay(mirrorText) then
                return mirrorText, mirrorSource or "Applications", true, mirrorStackHidden
            end

            local mirrorTextKnown = controller:ValueIsPresent(mirrorText)
            if mirrorBacked and (mirrorTextKnown or mirrorStackHidden) then
                return nil, mirrorSource, true, mirrorStackHidden
            end

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

        local mirrorText, mirrorSource, mirrorBacked, mirrorStackHidden =
            controller:ResolveMirrorStackText(icon)
        if controller:TextHasDisplay(mirrorText) then
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
            if showZero or count.mirrorAuthoritative or AuraCountTextHasDisplay(stackValue) then
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

        if count.mirrorAuthoritative or AuraCountTextHasDisplay(displayText) then
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
        local auraRenderActive = icon and icon._resolvedCooldownMode == "aura"
        local stackText, stackSource, stackHidden, _, visibilityGate =
            ResolveMirrorStackTextFromState(mirrorState, cooldownChargeAuthority, auraRenderActive)
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
        count.visibilityGate = visibilityGate
        if not issecretvalue(count.visibilityGate) and count.visibilityGate == nil then
            count.visibilityGate = MirrorStateEffectiveCooldownChargesShown(mirrorState)
        end
        count.mirrorAuthoritative = true

        controller:ApplyAuraCountText(icon, count, showZero, true)
        icon._lastMirrorStackTextEpoch = mirrorState.stackTextEpoch
        return true
    end

    return controller
end
