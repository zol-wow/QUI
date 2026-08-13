local ADDON_NAME, ns = ...
local S = ns.AuraSlots or {}

local function AurasAreSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end
ns.AuraSlots = S
_G.QUI = _G.QUI or {}
_G.QUI.AuraSlots = S

local E, AuraSkin, Helpers
local function Deps()
    E = E or ns.AuraElements
    AuraSkin = AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
    Helpers = Helpers or ns.Helpers
    return E and AuraSkin and ns.AuraGlue
end

local PARK_FILTER = { maxDuration = 0 }

local function TokenReactionClass(unit)
    if type(unit) ~= "string" then return nil end
    if unit == "player" or unit == "pet" then return "assist" end
    local p4 = unit:sub(1, 4)
    if p4 == "part" or p4 == "raid" then return "assist" end
    if p4 == "boss" then return "hostile" end
    return nil
end

local function LiveAssistProbe(unit)
    if unit == "player" or unit == "pet" then return true end
    local ok, trusted = pcall(function()
        if not (UnitIsConnected(unit)
            and not UnitIsDeadOrGhost(unit)
            and UnitCanAssist("player", unit)
            and UnitIsVisible(unit)) then
            return false
        end
        local phase = UnitPhaseReason(unit)
        if issecretvalue and issecretvalue(phase) then return false end -- @secret-policy: reject-secret-value — fail-closed park
        return not phase
    end)
    return ok and trusted == true -- @secret-policy: reject-secret-value — fail-closed park
end
S.LiveAssistProbe = LiveAssistProbe

function S.LivePolarityMismatch(unit, auraType)
    if TokenReactionClass(unit) ~= nil then return false end
    local harmful = type(auraType) == "string" and auraType:find("HARMFUL", 1, true) ~= nil
    local assist = LiveAssistProbe(unit)
    if harmful then return assist end
    return not assist
end

local function SpellNeverSecret(spellID)
    local CS = C_Secrets
    if not (CS and CS.GetSpellAuraSecrecy and Enum and Enum.SecrecyLevel) then
        return false
    end
    local ok, level = pcall(CS.GetSpellAuraSecrecy, spellID)
    -- @secret-safe: level is a plain enum for a literal spellID argument
    return ok and level == Enum.SecrecyLevel.NeverSecret
end

local function IdentityFilterEnforceable(container, base)
    local ok, unit = pcall(function()
        return container.GetUnit and container:GetUnit()
    end)
    if not ok then return true, false, nil end
    local class = TokenReactionClass(unit)
    if class == nil then return true, false, nil end
    local harmful = type(base) == "string" and base:find("HARMFUL", 1, true) ~= nil
    if harmful then
        return class ~= "assist", false, nil
    end
    if class == "hostile" then return false, false, nil end
    if unit == "player" or unit == "pet" then return true, false, nil end
    local live = LiveAssistProbe(unit)
    return live, true, live
end

local function SlotCandidateFilters(element, spellID)
    local cf = { includeSpellIDs = { [spellID] = true } }
    if E.EffectiveOnlyMine(element, spellID) then
        cf.isFromPlayerOrPlayerPet = true
    end
    return cf
end

-- Mine-only slots carry PLAYER in the filter string too: the engine enforces
-- it on secret (in-combat) aura data, where the Lua-side candidate filter
-- above cannot discriminate.
local function SlotFilterString(element, spellID)
    local base = element.auraType or "HELPFUL"
    if E.EffectiveOnlyMine(element, spellID) then
        return base .. "|PLAYER"
    end
    return base
end

local function StyleSlot(frame, element, index, profileOverrides)
    local profile = ns.AuraGlue.ElementProfile(element, profileOverrides)
    if element.displayType == "square" or element.displayType == "bar" then
        profile.externalSkinning = false
        profile.iconSkin = "Default"
    end
    AuraSkin.WireButton(frame, profile)

    local isBar = (element.displayType == "bar")
    local barCfg = element.bar or {}
    local size = profile.iconSize
    if isBar then
        frame:SetSize(barCfg.length or 48, barCfg.thickness or 12)
    else
        frame:SetSize(size, size)
    end

    local icon = frame.Icon
    local blockColor = element.color or { 1, 1, 1 }
    if element.displayType == "square" or isBar then
        if icon then icon:SetAlpha(0) end
        local block = frame._quiBorder
        if block then
            local trackDim = isBar and 0.25 or 1
            block:SetColorTexture((blockColor[1] or 1) * trackDim,
                (blockColor[2] or 1) * trackDim, (blockColor[3] or 1) * trackDim, 1)
            if block.DisablePixelSnap then block:DisablePixelSnap() end
        end
    else
        if icon then icon:SetAlpha(1) end
    end

    local cd = frame._quiCooldown
    local wantsLinear = isBar or element.swipeStyle == "horizontal" or element.swipeStyle == "vertical"
    if wantsLinear then
        if cd and cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
        local fill = frame._quiDurationBar
        if not fill and InCombatLockdown() then
            return false
        end
        if not fill then
            fill = CreateFrame("StatusBar", nil, frame)
            fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            fill:SetAllPoints(frame)
            frame._quiDurationBar = fill
        end
        frame:SetDurationBar(fill, {
            direction = (element.reverseSwipe and Enum.StatusBarTimerDirection.ElapsedTime)
                or Enum.StatusBarTimerDirection.RemainingTime,
            interpolation = Enum.StatusBarInterpolation.Immediate,
        })
        local vertical = (element.swipeStyle == "vertical")
            or (isBar and element.swipeStyle ~= "horizontal" and (barCfg.thickness or 12) >= (barCfg.length or 48))
        fill:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        fill:SetStatusBarColor(blockColor[1] or 1, blockColor[2] or 1, blockColor[3] or 1, 1)
        fill:Show()
    else
        if frame._quiDurationBar then frame._quiDurationBar:Hide() end
        if cd and Helpers and Helpers.ApplyCooldownSwipeStyle then
            Helpers.ApplyCooldownSwipeStyle(cd, element)
        end
    end
    return true
end

local function AnchorSlot(frame, container, element, index, total)
    local profile = ns.AuraGlue.ElementProfile(element)
    local grow = element.growDirection or "RIGHT"
    local isBar = (element.displayType == "bar")
    local barCfg = element.bar or {}
    local w = isBar and (barCfg.length or 48) or profile.iconSize
    local h = isBar and (barCfg.thickness or 12) or profile.iconSize
    local step = (index - 1)
    local perRow = profile.maxPerRow or 0
    local col, rowI = step, 0
    if perRow > 0 then
        col  = step % perRow
        rowI = math.floor(step / perRow)
    end
    local dx, dy = 0, 0
    if grow == "RIGHT" then dx = col * (w + profile.spacing)
    elseif grow == "LEFT" then dx = -col * (w + profile.spacing)
    elseif grow == "UP" then dy = col * (h + profile.spacing)
    elseif grow == "DOWN" then dy = -col * (h + profile.spacing)
    elseif grow == "CENTER" then
        local rowN = total or 1
        if perRow > 0 then
            local rowsTotal = math.ceil((total or 1) / perRow)
            rowN = (rowI < rowsTotal - 1) and perRow or ((total or 1) - perRow * (rowsTotal - 1))
        end
        dx = (col - (rowN - 1) / 2) * (w + profile.spacing)
    end
    if rowI > 0 then
        local vert = (grow == "UP" or grow == "DOWN")
        if vert then
            local anchorRight = tostring(profile.anchor or ""):find("RIGHT", 1, true)
            dx = dx + (anchorRight and -1 or 1) * rowI * (w + profile.spacing)
        else
            local anchorTop = tostring(profile.anchor or ""):find("TOP", 1, true)
            dy = dy + (anchorTop and -1 or 1) * rowI * (h + profile.spacing)
        end
    end
    frame:ClearAllPoints()
    frame:SetPoint(profile.anchor, container, element.anchor or "TOPLEFT", dx, dy)
end

local function ParkSlot(container, slot)
    if slot.parked then return end
    slot.parked = true
    container:SetAuraSlotCandidateFilters(slot.key, PARK_FILTER)
end

function S.Sync(container, element, allowCreate, profileOverrides)
    if not Deps() then return false end
    local pool = container._quiSlots
    if not pool then
        pool = {}
        container._quiSlots = pool
    end
    local spells = (element.enabled ~= false) and element.spells or nil
    local complete = true
    local want = 0
    container._quiAssistApplied = nil
    local parkAll = false
    if spells then
        local base = element.auraType or "HELPFUL"
        local enforceable, liveGoverned, live = IdentityFilterEnforceable(container, base)
        if liveGoverned then
            container._quiAssistApplied = live
        end
        if not enforceable then
            if liveGoverned then
                parkAll = true
            else
                spells = nil
            end
        end
    end
    if spells then
        local base = element.auraType or "HELPFUL"
        local total = 0
        for i = 1, #spells do
            if type(spells[i]) == "number" then total = total + 1 end
        end
        local cap = element.maxIcons
        if cap and cap > 0 and cap < total then total = cap end
        for i = 1, #spells do
            if want >= total then break end
            local spellID = spells[i]
            if type(spellID) == "number" then
                want = want + 1
                local slot = pool[want]
                local parkThis = parkAll and not SpellNeverSecret(spellID)
                if slot then
                    if parkThis then
                        ParkSlot(container, slot)
                    else
                        container:SetAuraSlotFilterString(slot.key, SlotFilterString(element, spellID))
                        container:SetAuraSlotCandidateFilters(slot.key, SlotCandidateFilters(element, spellID))
                        slot.parked = false
                    end
                elseif allowCreate then
                    local key = "t" .. tostring(want)
                    local slotIndex, slotTotal = want, total
                    local birthFilters = parkThis and PARK_FILTER or SlotCandidateFilters(element, spellID)
                    local frame = container:AddAuraSlot(key, SlotFilterString(element, spellID), {
                        candidateFilters = birthFilters,
                        initializeFrame = function(f)
                            StyleSlot(f, element, slotIndex, profileOverrides)
                            AnchorSlot(f, container, element, slotIndex, slotTotal)
                        end,
                    })
                    slot = { key = key, frame = frame, parked = parkThis }
                    pool[want] = slot
                else
                    complete = false
                end
                if slot and slot.frame then
                    if AurasAreSecret() then
                        complete = false
                    else
                        if StyleSlot(slot.frame, element, want, profileOverrides) == false then
                            complete = false
                        end
                        if not InCombatLockdown() then
                            AnchorSlot(slot.frame, container, element, want, total)
                        else
                            complete = false
                        end
                    end
                end
            end
        end
    end
    for i = want + 1, #pool do
        ParkSlot(container, pool[i])
    end
    return complete
end

function S.Park(container)
    container._quiAssistApplied = nil
    local pool = container._quiSlots
    if not pool then return end
    for i = 1, #pool do
        ParkSlot(container, pool[i])
    end
end

return S
