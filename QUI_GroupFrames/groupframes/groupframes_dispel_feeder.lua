local ADDON_NAME, ns = ...

-- Dispel overlay feeder: engine-driven presence for the healer dispel overlay
-- and cleanse glow. The Lua aura cache freezes whenever ShouldAurasBeSecret
-- (instanced combat), which is exactly when dispels matter, so — like the
-- healthTint feeders in aura_slots — the overlay art is parented into hidden
-- secure aura slots and the engine's (possibly secret) show/hide of the slot
-- decides whether it renders. Colors ride AddDispelTypeTexture with a custom
-- per-type color map, so the engine also picks the right user color without
-- Lua ever observing the aura's dispel type.
--
-- Slot buttons carry DenyTaintedAccessWhenAurasAreSecret: writes into the
-- slot subtree are refused while auras are secret, and no addon script
-- handler may exist anywhere in it or the engine refuses SetShown with
-- secret presence. Consequently ALL art creation/styling happens out of
-- secrecy (Sync reports incomplete otherwise and the caller requeues), and
-- the art is scriptless. CustomAuraButtonTemplate has no visual regions of
-- its own, so the slots are NOT alpha-muted (unlike aura_slots' pooled
-- healthTint feeders, which must smother leftover art from other display
-- styles) — the art inherits the group frame's alpha and follows
-- out-of-range/offline fading exactly like the legacy overlay did.
local F = {}
ns.QUI_GFDispelFeeder = F

local Chrome = ns.QUI_GroupFrameChrome
local LEVELS = (Chrome and Chrome.LEVELS) or { DISPEL = 8 }

local DISPEL_STYLES = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
local STYLE_PRESERVE_ASSET = (DISPEL_STYLES and DISPEL_STYLES.PreserveAsset) or 3
local STYLE_ICON = (DISPEL_STYLES and DISPEL_STYLES.Icon) or 2

-- An aura can never have a max duration of 0, so this candidate filter keeps
-- an unwanted slot permanently empty (slots are add-only; same trick as
-- aura_slots' PARK_FILTER).
local PARK_FILTER = { maxDuration = 0 }

-- RAID on harmful auras means "the player can dispel" (AuraUtil.AuraFilters),
-- matching ClassifyDispellable's HARMFUL|RAID probe and the PLAYER_DISPELLABLE
-- scope's promise. RAID_PLAYER_DISPELLABLE is broader — "someone in the
-- player's raid can dispel" — and would light non-actionable overlays.
local BY_ME_FILTER = "HARMFUL|RAID"
local ALL_TYPED_FILTER = "HARMFUL"
-- Enrage rides along like the legacy _dispel.ReadableType did (it renders in
-- the Bleed color via the map alias below).
local ALL_TYPED_CF = {
    includeDispelTypes = {
        Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true,
        Enrage = true,
    },
}

local DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed" }

local function AurasAreSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- Overlay config colors are stored as {r, g, b, a} arrays; the engine's
-- customDispelColorMap wants {r=, g=, b=} keyed by dispel type name. "None"
-- mirrors the legacy fallback-to-Magic for auras without a readable type,
-- and Enrage aliases Bleed exactly like _dispel.ReadableType did.
function F.BuildColorMap(colors)
    if type(colors) ~= "table" then return nil end
    local map = {}
    for _, typeName in ipairs(DISPEL_TYPES) do
        local c = colors[typeName]
        if type(c) == "table" then
            map[typeName] = { r = c[1] or 1, g = c[2] or 1, b = c[3] or 1 }
        end
    end
    if map.Bleed then map.Enrage = map.Bleed end
    if map.Magic then map.None = map.Magic end
    if next(map) == nil then return nil end
    return map
end

local function PixelSize(frame)
    local QUICore = ns.Addon
    local px = QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(frame)
    if type(px) == "number" and px > 0 then return px end
    return 1
end

-- Scriptless slot hygiene. No alpha muting: the template carries no visual
-- regions, and an untouched slot alpha lets the attached art inherit the
-- group frame's fading (out of range, offline) like the legacy overlay.
local function PrepareSlot(slot)
    slot:SetSize(1, 1)
    if slot.EnableMouse then slot:EnableMouse(false) end
    if slot.SetMouseClickEnabled then slot:SetMouseClickEnabled(false) end
end

local function EnsureArtTexture(slot, art, key, layer)
    local tex = art[key]
    if not tex then
        tex = slot:CreateTexture(nil, layer)
        if tex.DisablePixelSnap then tex:DisablePixelSnap() end
        art[key] = tex
    end
    return tex
end

local BORDER_ANCHORS = {
    top    = { { "TOPLEFT", "TOPLEFT" }, { "TOPRIGHT", "TOPRIGHT" } },
    bottom = { { "BOTTOMLEFT", "BOTTOMLEFT" }, { "BOTTOMRIGHT", "BOTTOMRIGHT" } },
    left   = { { "TOPLEFT", "TOPLEFT" }, { "BOTTOMLEFT", "BOTTOMLEFT" } },
    right  = { { "TOPRIGHT", "TOPRIGHT" }, { "BOTTOMRIGHT", "BOTTOMRIGHT" } },
}

-- Build/refresh the overlay art inside the visual slot and (re)bind it to the
-- engine's dispel-type tinting. Must only run while auras are not secret.
local function StyleVisualSlot(slot, host, dispelCfg, borderOn, iconOn)
    PrepareSlot(slot)
    local art = slot._quiDispelArt
    if not art then
        art = {}
        slot._quiDispelArt = art
    end

    local colorMap = F.BuildColorMap(dispelCfg and dispelCfg.colors)
    local opacity = (dispelCfg and dispelCfg.opacity) or 0.8
    local fillOpacity = (dispelCfg and dispelCfg.fillOpacity) or 0
    local borderSize = PixelSize(host) * ((dispelCfg and dispelCfg.borderSize) or 3)

    if slot.ClearDispelTypeTextures then slot:ClearDispelTypeTextures() end

    local borderOpts = {
        style = STYLE_PRESERVE_ASSET,
        showWhenHarmful = true,
        showWhenHelpful = false,
        showWithoutDispelType = true,
    }
    if colorMap then borderOpts.customDispelColorMap = colorMap end

    for edge, points in pairs(BORDER_ANCHORS) do
        local tex = EnsureArtTexture(slot, art, edge, "BORDER")
        tex:SetColorTexture(1, 1, 1, 1)
        tex:ClearAllPoints()
        for i = 1, #points do
            tex:SetPoint(points[i][1], host, points[i][2], 0, 0)
        end
        if edge == "top" or edge == "bottom" then
            tex:SetHeight(borderSize)
        else
            tex:SetWidth(borderSize)
        end
        tex:SetAlpha(borderOn and opacity or 0)
        if slot.AddDispelTypeTexture then
            slot:AddDispelTypeTexture(tex, borderOpts)
        end
        tex:Show()
    end

    local fill = EnsureArtTexture(slot, art, "fill", "BACKGROUND")
    fill:SetColorTexture(1, 1, 1, 1)
    fill:ClearAllPoints()
    fill:SetAllPoints(host)
    fill:SetAlpha(borderOn and fillOpacity or 0)
    if slot.AddDispelTypeTexture then
        slot:AddDispelTypeTexture(fill, borderOpts)
    end
    fill:Show()

    local icon = EnsureArtTexture(slot, art, "icon", "ARTWORK")
    if iconOn then
        local size = tonumber(dispelCfg and dispelCfg.iconSize) or 20
        local anchor = (dispelCfg and dispelCfg.iconAnchor) or "TOPRIGHT"
        icon:ClearAllPoints()
        icon:SetPoint(anchor, host, anchor,
            tonumber(dispelCfg and dispelCfg.iconOffsetX) or 0,
            tonumber(dispelCfg and dispelCfg.iconOffsetY) or 0)
        icon:SetSize(size, size)
        icon:SetAlpha(tonumber(dispelCfg and dispelCfg.iconOpacity) or 1)
        if slot.AddDispelTypeTexture then
            slot:AddDispelTypeTexture(icon, {
                style = STYLE_ICON,
                showWhenHarmful = true,
                showWhenHelpful = false,
            })
        end
        icon:Show()
    else
        icon:SetAlpha(0)
        icon:Hide()
    end
end

local function StyleGlowSlot(slot, host, glowCfg)
    PrepareSlot(slot)
    local art = slot._quiDispelArt
    if not art then
        art = {}
        slot._quiDispelArt = art
    end
    local isNew = art.glow == nil
    local tex = EnsureArtTexture(slot, art, "glow", "OVERLAY")
    if isNew then
        tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        if tex.SetBlendMode then tex:SetBlendMode("ADD") end
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", host, "TOPLEFT", -4, 4)
    tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 4, -4)
    local c = glowCfg and glowCfg.color
    tex:SetVertexColor((c and c[1]) or 0.1, (c and c[2]) or 1.0, (c and c[3]) or 0.1, (c and c[4]) or 1.0)
    tex:Show()
end

local function SetSlotFilters(state, container, key, filter, cf)
    local slot = state.slots[key]
    if not slot then return false end
    if slot.filter ~= filter then
        container:SetAuraSlotFilterString(key, filter)
        slot.filter = filter
    end
    -- Candidate filters are always re-applied: parking and unparking swap the
    -- table, and the engine securecopies it so identity comparisons lie.
    container:SetAuraSlotCandidateFilters(key, cf or nil)
    slot.parked = (cf == PARK_FILTER)
    return true
end

local function EnsureSlot(state, container, key, filter, cf)
    if state.slots[key] then
        return SetSlotFilters(state, container, key, filter, cf)
    end
    local frame = container:AddAuraSlot(key, filter, {
        candidateFilters = cf or nil,
        initializeFrame = PrepareSlot,
    })
    if not frame then return false end
    state.slots[key] = { frame = frame, filter = filter, parked = (cf == PARK_FILTER) }
    return true
end

-- Container visibility = configured AND alive. Aura presence stays fully
-- engine-driven inside the slots; this only mirrors the legacy rule that a
-- nonexistent or dead/ghost unit wears no dispel visuals. Show/Hide touch the
-- QUI-owned container, not the slot subtree, so they are safe under secrecy.
local function ApplyShown(state)
    if state.configShown and state.alive ~= false then
        state.container:Show()
    else
        state.container:Hide()
    end
end

-- Life-state gate, driven from the health/connection update path in
-- groupframes.lua (UpdateHealth), which already normalizes secret unit flags
-- fail-open toward alive.
function F.SetLifeGate(frame, alive)
    local state = frame and frame._quiDispelFeeder
    if not state then return end
    alive = alive == true
    if state.alive == alive then return end
    state.alive = alive
    ApplyShown(state)
end

-- Synchronize the feeder with the current healer settings. Returns true when
-- fully applied; false means structural or styling work is still pending and
-- the caller must requeue (QueueRegenWork polls until out of combat/secrecy).
function F.Sync(frame, unit, allowCreate, healerSettings)
    if not frame or type(unit) ~= "string" then return true end

    local dispelCfg = healerSettings and healerSettings.dispelOverlay
    local glowCfg = healerSettings and healerSettings.cleanseGlow
    local borderOn = dispelCfg ~= nil and dispelCfg.enabled ~= false
    local iconOn = dispelCfg ~= nil and dispelCfg.showIcon == true
    local glowOn = glowCfg ~= nil and glowCfg.enabled == true
    local anyOn = borderOn or iconOn or glowOn

    local state = frame._quiDispelFeeder
    if not state then
        if not anyOn then
            frame._quiDispelFeederActive = nil
            return true
        end
        if not allowCreate or InCombat() or not CreateFrame then return false end
        local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
        if not container then return false end
        container:SetSize(1, 1)
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        state = { container = container, slots = {}, alive = true }
        frame._quiDispelFeeder = state
    end

    local container = state.container
    container:SetUnit(unit)

    if not anyOn then
        -- Feature off: park everything and let the (hidden) legacy path rest.
        SetSlotFilters(state, container, "visual", BY_ME_FILTER, PARK_FILTER)
        SetSlotFilters(state, container, "glow", BY_ME_FILTER, PARK_FILTER)
        container:SetEnabled(false)
        state.configShown = false
        ApplyShown(state)
        frame._quiDispelFeederActive = true
        return true
    end

    local complete = true

    local visualFilter, visualCF
    if dispelCfg and dispelCfg.scope == "ALL_TYPED" then
        visualFilter, visualCF = ALL_TYPED_FILTER, ALL_TYPED_CF
    else
        visualFilter, visualCF = BY_ME_FILTER, nil
    end
    local wantVisual = borderOn or iconOn

    -- Explicit branches: a live slot's candidate-filter set may legitimately
    -- be nil, so `wanted and cf or PARK_FILTER` would park it by accident.
    local slotFilter, slotCF = BY_ME_FILTER, PARK_FILTER
    if wantVisual then
        slotFilter, slotCF = visualFilter, visualCF
    end
    if not EnsureSlot(state, container, "visual", slotFilter, slotCF) then
        complete = false
    end
    local glowSlotCF
    if not glowOn then glowSlotCF = PARK_FILTER end
    if not EnsureSlot(state, container, "glow", BY_ME_FILTER, glowSlotCF) then
        complete = false
    end

    -- Styling writes into the slot subtree, which the engine refuses while
    -- auras are secret; report incomplete so the caller retries at regen.
    if AurasAreSecret() then
        complete = false
    else
        local visualSlot = state.slots.visual
        if wantVisual and visualSlot and visualSlot.frame then
            StyleVisualSlot(visualSlot.frame, frame, dispelCfg, borderOn, iconOn)
        end
        local glowSlot = state.slots.glow
        if glowOn and glowSlot and glowSlot.frame then
            StyleGlowSlot(glowSlot.frame, frame, glowCfg)
        end
    end

    if not InCombat() then
        container:SetFrameLevel(frame:GetFrameLevel() + (LEVELS.DISPEL or 8))
    elseif container:GetFrameLevel() ~= frame:GetFrameLevel() + (LEVELS.DISPEL or 8) then
        complete = false
    end

    container:SetEnabled(true)
    state.configShown = true
    ApplyShown(state)
    frame._quiDispelFeederActive = true
    return complete
end

return F
