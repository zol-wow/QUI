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
