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

-- healthTint "feeder" slots: invisible secure aura slots whose engine-driven
-- visibility IS the aura-presence signal. Lua must never observe it: the
-- engine refuses SetShown() with secret aura presence on buttons carrying
-- script handlers ("Cannot be called with secrets due to existing script
-- handlers"), so NO scripts may exist anywhere in the slot's subtree.
-- Instead the ns.AuraFeederAttach seam parents passive, scriptless art (the
-- tint overlay) into the slot — the engine's secret show/hide then decides
-- whether that art renders, and the tint keeps working in combat where the
-- Lua-side scan cache is frozen by ShouldAurasBeSecret.
local function StyleFeederSlot(frame, element)
    frame._quiFeederActive = true
    frame._quiFeederElement = element
    frame:SetAlpha(0)
    frame:SetSize(1, 1)
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
    local attach = ns.AuraFeederAttach
    if attach then attach(frame, element) end
    return true
end

local function RetireFeederSlot(frame)
    if not frame._quiFeederActive then return end
    frame._quiFeederActive = false
    local detach = ns.AuraFeederDetach
    if detach then detach(frame, frame._quiFeederElement) end
    frame._quiFeederElement = nil
    frame:SetAlpha(1)
    if frame.EnableMouse then frame:EnableMouse(true) end
end

-- Tracked "bar" display geometry. An explicit barCfg.orientation decides the
-- long axis (VERTICAL bars are thickness wide x length tall); profiles saved
-- before orientation existed keep the legacy length x thickness box, where
-- thickness >= length reads as a vertical bar.
local function BarSize(barCfg, host)
    local thickness = barCfg.thickness or 12
    local length = barCfg.length or 48
    local vertical = barCfg.orientation == "VERTICAL"
    local w, h
    if vertical then
        w, h = thickness, length
    else
        w, h = length, thickness
    end
    if barCfg.matchFrameSize == true and host then
        -- @secret-policy: reject-secret-value — frame rects can be secret in combat
        if vertical then
            h = Helpers.SafeToNumber(host:GetHeight(), h)
        else
            w = Helpers.SafeToNumber(host:GetWidth(), w)
        end
    end
    return w, h
end

local function BarBorderInset(barCfg)
    if barCfg.hideBorder == true then return 0 end
    return math.max(1, Helpers.SafeToNumber(barCfg.borderSize, 1))
end

local function StyleSlot(frame, element, index, profileOverrides)
    if element.displayType == "healthTint" then
        return StyleFeederSlot(frame, element)
    end
    RetireFeederSlot(frame)
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
        local container = frame:GetParent()
        frame:SetSize(BarSize(barCfg, container and container:GetParent()))
    else
        frame:SetSize(size, size)
    end

    local barInset = isBar and BarBorderInset(barCfg) or 0
    local icon = frame.Icon
    local blockColor = element.color or { 1, 1, 1 }
    if element.displayType == "square" or isBar then
        if icon then icon:SetAlpha(0) end
        local block = frame._quiBorder
        if block then
            local bg = isBar and barCfg.backgroundColor or nil
            if type(bg) == "table" then
                block:SetColorTexture(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 1)
            else
                local trackDim = isBar and 0.25 or 1
                block:SetColorTexture((blockColor[1] or 1) * trackDim,
                    (blockColor[2] or 1) * trackDim, (blockColor[3] or 1) * trackDim, 1)
            end
            if block.DisablePixelSnap then block:DisablePixelSnap() end
            -- Bars inset the track so the border texture below shows through
            -- as a frame around the bar; everything else keeps the full-button
            -- track the skin wired up.
            block:ClearAllPoints()
            if barInset > 0 then
                block:SetPoint("TOPLEFT", frame, "TOPLEFT", barInset, -barInset)
                block:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -barInset, barInset)
            else
                block:SetAllPoints(frame)
            end
        end
        local btex = frame._quiBarBorder
        if isBar and barCfg.hideBorder ~= true then
            if not btex then
                btex = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
                btex:SetAllPoints(frame)
                if btex.DisablePixelSnap then btex:DisablePixelSnap() end
                frame._quiBarBorder = btex
            end
            local bc = barCfg.borderColor
            btex:SetColorTexture((type(bc) == "table" and bc[1]) or 0,
                (type(bc) == "table" and bc[2]) or 0,
                (type(bc) == "table" and bc[3]) or 0,
                (type(bc) == "table" and bc[4]) or 1)
            btex:Show()
        elseif btex then
            btex:Hide()
        end
    else
        if icon then icon:SetAlpha(1) end
        if frame._quiBarBorder then frame._quiBarBorder:Hide() end
        local block = frame._quiBorder
        if block then
            block:ClearAllPoints()
            block:SetAllPoints(frame)
        end
    end

    local cd = frame._quiCooldown
    local wantsLinear = isBar or element.swipeStyle == "horizontal" or element.swipeStyle == "vertical"
    if wantsLinear then
        if cd and cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
        -- With the swipe off, the cooldown widget still paints its rotating
        -- edge (the yellow line) and finish bling over the linear fill.
        if cd and cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd and cd.SetDrawBling then cd:SetDrawBling(false) end
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
        fill:ClearAllPoints()
        if barInset > 0 then
            fill:SetPoint("TOPLEFT", frame, "TOPLEFT", barInset, -barInset)
            fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -barInset, barInset)
        else
            fill:SetAllPoints(frame)
        end
        frame:SetDurationBar(fill, {
            direction = (element.reverseSwipe and Enum.StatusBarTimerDirection.ElapsedTime)
                or Enum.StatusBarTimerDirection.RemainingTime,
            interpolation = Enum.StatusBarInterpolation.Immediate,
        })
        local vertical
        if isBar and barCfg.orientation == "VERTICAL" then
            vertical = true
        elseif isBar and barCfg.orientation == "HORIZONTAL" then
            vertical = false
        else
            vertical = (element.swipeStyle == "vertical")
                or (isBar and element.swipeStyle ~= "horizontal" and (barCfg.thickness or 12) >= (barCfg.length or 48))
        end
        fill:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        fill:SetStatusBarColor(blockColor[1] or 1, blockColor[2] or 1, blockColor[3] or 1, 1)
        fill:Show()
        -- Low-time recolor: a cover in the expiring color anchored to the
        -- fill's texture region (its rect tracks the timer C-side), with its
        -- Shown aspect handed to the engine's refresh-window driver via
        -- AddPandemicRegion — no time is ever read Lua-side. BIND-ONCE:
        -- Blizzard owns the cover's visibility from the bind onward, so QUI
        -- must never Show/Hide it; disabling the option restyles it to
        -- alpha 0 instead (slots cannot be rebuilt to shed the bind).
        local lowColor = isBar and barCfg.lowTimeColor or nil
        local lowCover = fill._quiLowTimeCover
        if type(lowColor) == "table" and frame.AddPandemicRegion then
            if not lowCover then
                lowCover = fill:CreateTexture(nil, "OVERLAY")
                local fillTex = fill.GetStatusBarTexture and fill:GetStatusBarTexture()
                if fillTex then
                    lowCover:SetAllPoints(fillTex)
                else
                    lowCover:SetAllPoints(fill)
                end
                if lowCover.DisablePixelSnap then lowCover:DisablePixelSnap() end
                fill._quiLowTimeCover = lowCover
                frame:AddPandemicRegion(lowCover)
            end
            lowCover:SetColorTexture(lowColor[1] or 1, lowColor[2] or 0.35, lowColor[3] or 0.2, 1)
            lowCover:SetAlpha(lowColor[4] or 1)
        elseif lowCover then
            lowCover:SetAlpha(0)
        end
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
    local w, h
    if isBar then
        w, h = BarSize(barCfg, container:GetParent())
    else
        w, h = profile.iconSize, profile.iconSize
    end
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

-- Feeder elements sync ONE slot with the UNION of their spell IDs instead of
-- a slot per spell: the tint is a presence signal, and two translucent covers
-- drawn at once composite darker (DandersFrames measured 25% -> 44% -> 58%
-- over stacked chains), so exactly one visual must ever render per element.
local function FeederSpellMap(element)
    local spells = element.spells
    if type(spells) ~= "table" then return nil end
    local map, n = nil, 0
    for i = 1, #spells do
        local sid = spells[i]
        if type(sid) == "number" then
            map = map or {}
            map[sid] = true
            n = n + 1
        end
    end
    return map, n
end

-- PLAYER-gate the union slot only when EVERY spell is effectively mine-only;
-- a mixed set must stay loose or the engine would hide the tint for auras the
-- user asked to see from anyone.
local function FeederOnlyMine(element)
    local spells = element.spells
    if type(spells) ~= "table" then return false end
    for i = 1, #spells do
        local sid = spells[i]
        if type(sid) == "number" and not E.EffectiveOnlyMine(element, sid) then
            return false
        end
    end
    return true
end

local function SyncFeederElement(container, element, allowCreate, pool)
    container._quiAssistApplied = nil
    local spells = (element.enabled ~= false) and FeederSpellMap(element) or nil
    local base = element.auraType or "HELPFUL"
    local parkAll = false
    if spells then
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
    local complete = true
    if spells then
        local parkThis = parkAll
        if parkThis then
            local allNeverSecret = true
            for sid in pairs(spells) do
                if not SpellNeverSecret(sid) then
                    allNeverSecret = false
                    break
                end
            end
            if allNeverSecret then parkThis = false end
        end
        local onlyMine = FeederOnlyMine(element)
        local filterStr = onlyMine and (base .. "|PLAYER") or base
        local cf = { includeSpellIDs = spells }
        if onlyMine then cf.isFromPlayerOrPlayerPet = true end
        local slot = pool[1]
        if slot then
            if parkThis then
                ParkSlot(container, slot)
            else
                container:SetAuraSlotFilterString(slot.key, filterStr)
                container:SetAuraSlotCandidateFilters(slot.key, cf)
                slot.parked = false
            end
        elseif allowCreate then
            local frame = container:AddAuraSlot("t1", filterStr, {
                candidateFilters = parkThis and PARK_FILTER or cf,
                initializeFrame = function(f)
                    StyleFeederSlot(f, element)
                end,
            })
            slot = { key = "t1", frame = frame, parked = parkThis }
            pool[1] = slot
        else
            complete = false
        end
        if slot and slot.frame then
            if AurasAreSecret() then
                complete = false
            else
                StyleFeederSlot(slot.frame, element)
            end
        end
        for i = 2, #pool do
            ParkSlot(container, pool[i])
        end
    else
        for i = 1, #pool do
            ParkSlot(container, pool[i])
        end
    end
    return complete
end

function S.Sync(container, element, allowCreate, profileOverrides)
    if not Deps() then return false end
    local pool = container._quiSlots
    if not pool then
        pool = {}
        container._quiSlots = pool
    end
    if element.displayType == "healthTint" then
        return SyncFeederElement(container, element, allowCreate, pool)
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
