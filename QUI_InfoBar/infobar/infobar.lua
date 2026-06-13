--- QUI Info Bar — full-width top/bottom bar hosting datatext widgets in
--- three zones (left / center / right). Each zone is an ordered, unbounded
--- list of widget ids; widgets auto-size to content (per-widget minWidth),
--- and trailing widgets hide instead of overlapping a neighbor zone.

local _, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local LSM = ns.LSM

local max = math.max
local floor = math.floor

local InfoBar = {}
QUICore.InfoBar = InfoBar

local ZONES = { "left", "center", "right" }

local bar
local zoneFrames = {}
local fadeTicker

local function GetDB()
    local db = QUICore.db and QUICore.db.profile
    return db and db.infobar
end

-- Set whenever a reflow attempt lands in combat; drained at regen by the
-- regen watcher below.
local reflowPendingCombat = false
-- Set whenever ApplyAll lands in combat; drained at regen likewise.
local applyPendingCombat = false

local reflowQueued = false
local function QueueReflow()
    if reflowQueued then return end
    reflowQueued = true
    C_Timer.After(0, function()
        reflowQueued = false
        InfoBar:ReflowAll()
    end)
end

-- Persistent regen watcher draining both combat-deferred flags: rebuild
-- (ApplyAll) first, then layout. Layout goes through QueueReflow (next
-- frame) rather than a direct ReflowAll because with hideInCombat the
-- visibility state driver may not have re-shown the bar yet at
-- PLAYER_REGEN_ENABLED — a direct call would bail on IsShown with the
-- flag already consumed. Created at file scope (not in CreateBar) so an
-- ApplyAll deferred by a combat /reload, before any bar exists, still
-- replays at regen. Each flag is cleared before invoking its action, so
-- a re-deferral from inside the action re-arms cleanly.
local regenWatcher = CreateFrame("Frame")
regenWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
regenWatcher:SetScript("OnEvent", function()
    if applyPendingCombat then
        applyPendingCombat = false
        InfoBar:ApplyAll()
    end
    if reflowPendingCombat then
        reflowPendingCombat = false
        QueueReflow()
    end
end)

---------------------------------------------------------------------------
-- FRAME CONSTRUCTION
---------------------------------------------------------------------------
local function ApplyBackdrop()
    local db = GetDB()
    if not db then return end

    bar.bg:SetColorTexture(0, 0, 0, (db.bgOpacity or 85) / 100)
    if UIKit and UIKit.DisablePixelSnap then
        UIKit.DisablePixelSnap(bar.bg)
    end

    -- Only border drawn is on the screen-inner edge (below a TOP bar,
    -- above a BOTTOM bar).
    local borderSize = db.borderSize or 1
    local bR, bG, bB, bA = Helpers.GetSkinBorderColor(db, "")
    local edge = bar.borderEdge
    edge:SetColorTexture(bR, bG, bB, bA)
    if UIKit and UIKit.DisablePixelSnap then
        UIKit.DisablePixelSnap(edge)
    end
    edge:SetHeight(max(1, borderSize))
    edge:SetShown(borderSize > 0)
    edge:ClearAllPoints()
    if db.position == "BOTTOM" then
        edge:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
        edge:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 0)
    else
        edge:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
        edge:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    end
end

local function ApplyPosition()
    local db = GetDB()
    if not db then return end
    bar:ClearAllPoints()
    if db.position == "BOTTOM" then
        bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    else
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    end
    bar:SetHeight(db.height or 22)
end

local function CreateBar()
    if bar then return end
    bar = CreateFrame("Frame", "QUI_InfoBar", UIParent)
    bar:SetFrameStrata("HIGH")

    -- Width is anchor-derived from UIParent, so resolution/UI-scale changes
    -- arrive here as OnSizeChanged; re-run overflow on the new width.
    bar:SetScript("OnSizeChanged", QueueReflow)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()

    bar.borderEdge = bar:CreateTexture(nil, "BORDER")

    for _, key in ipairs(ZONES) do
        local zf = CreateFrame("Frame", "QUI_InfoBarZone_" .. key, bar)
        zf.slots = {}
        zoneFrames[key] = zf
    end

    -- Hand-rolled 1px edge goes sub-pixel after login scale changes unless
    -- re-applied on scale refresh.
    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(bar, "infobarBackdrop", function()
            if GetDB() then ApplyBackdrop() end
        end)
    end

    -- Layout Mode anchor target: other frames can anchor to the bar ("Info
    -- Bar" under Display). Registered even while the bar is disabled — the
    -- anchoring engine chain-walks hidden parents, and its visibility hooks
    -- re-anchor children when the bar shows/hides. The re-apply below picks
    -- up saved anchors that referenced the bar before this LOD addon loaded.
    if ns.FRAME_ANCHOR_INFO and not ns.FRAME_ANCHOR_INFO.infoBar then
        ns.FRAME_ANCHOR_INFO.infoBar = {
            displayName = "Info Bar", category = "Display", order = 11,
        }
    end
    local anchoring = ns.QUI_Anchoring
    if anchoring and anchoring.RegisterAnchorTarget then
        anchoring:RegisterAnchorTarget("infoBar", bar, {
            displayName = "Info Bar", category = "Display", order = 11,
        })
        if anchoring.ApplyAllFrameAnchors then
            anchoring:ApplyAllFrameAnchors()
        end
    end
end

---------------------------------------------------------------------------
-- SLOTS (pooled: WoW never GCs frames, so abandoning slots on every rebuild
-- leaks them for the session)
---------------------------------------------------------------------------

-- Free list shared by all three zones. Released slots stay parented to their
-- old zone frame (zone frames live as long as the bar, so a hidden child
-- there pins nothing extra); CreateSlot re-parents on reuse. Capped so
-- pathological settings churn stays bounded — beyond the cap a slot is
-- unparented and abandoned exactly as before pooling.
local slotPool = {}
local SLOT_POOL_CAP = 32

local function ReleaseSlots(zf)
    for _, slot in ipairs(zf.slots) do
        if QUICore.Datatexts then
            -- Clears datatextInstance + provider OnClick/OnEnter/OnLeave.
            QUICore.Datatexts:DetachFromSlot(slot)
        end
        -- Field-clearing contract: every per-widget field any host or
        -- provider sets on a slot must be cleared here, or it leaks into the
        -- next widget that reuses this frame. (_quiFixedWidth/_quiLdbName are
        -- already cleared by provider OnDisable; cleared again defensively.)
        slot._quiWidgetId = nil
        slot._quiMinWidth = nil
        slot._quiXOffset = nil
        slot._quiFixedWidth = nil
        slot._quiOverflowHidden = nil
        slot._quiOnWidthDirty = nil
        slot._quiLdbName = nil
        slot.shortLabel = nil
        slot.noLabel = nil
        slot.hideIcon = nil
        slot.clickThrough = nil
        slot.text:SetText("")
        -- Drag-reorder dims the slot to 0.4 alpha mid-drag; a release-during-
        -- drag can pool it dimmed, so reset alpha here as part of the clearing
        -- contract. (Do NOT clear slot._quiDragWired — its OnDragStart/OnDragStop
        -- HookScripts persist across pool reuse and HookScript stacks; the flag
        -- must persist so WireSlotDrag stays a true once-only attach.)
        slot:SetAlpha(1)
        slot:Hide()
        if #slotPool < SLOT_POOL_CAP then
            slotPool[#slotPool + 1] = slot
        else
            slot:SetParent(nil)
        end
    end
    wipe(zf.slots)
end

local function CreateSlot(zf, widgetId)
    local db = GetDB()
    local slot = table.remove(slotPool)
    if slot then
        slot:SetParent(zf)
        -- Pooled slots were hidden on release; fresh frames show by default.
        -- Show here so a state-driver-hidden bar can't strand reused slots
        -- invisible until the 1s ticker reflow.
        slot:Show()
    else
        slot = CreateFrame("Button", nil, zf)
        slot.text = slot:CreateFontString(nil, "OVERLAY")
        slot.text:SetPoint("LEFT", slot, "LEFT", 4, 0)
        slot.text:SetJustifyH("LEFT")
        slot.text:SetWordWrap(false)
    end
    slot:SetHeight(db.height or 22)
    slot:EnableMouse(true)

    -- Re-applied on pooled reuse too: the profile font/size/outline can
    -- change between rebuilds.
    local general = QUICore.db.profile.general or {}
    local fontPath = LSM:Fetch("font", general.font or "Quazii") or "Fonts\\FRIZQT__.TTF"
    QUICore:SafeSetFont(slot.text, fontPath, db.fontSize or 12, general.fontOutline or "OUTLINE")
    slot.text:SetTextColor(1, 1, 1, 1)

    local ws = db.widgetSettings and db.widgetSettings[widgetId]
    slot.shortLabel = ws and ws.shortLabel or false
    slot.noLabel = ws and ws.noLabel or false
    -- Consumed by icon-rendering providers we own (ldb bridge, specswap,
    -- professions). Micromenu/travel are icon-only compound widgets and
    -- deliberately ignore it (hiding their icon would blank them).
    slot.hideIcon = ws and ws.hideIcon or false
    -- Click-through disables clicks AND tooltips for this widget (both ride
    -- on slot mouse input). Applied after AttachToSlot in ApplyAll because
    -- providers re-EnableMouse(true) in OnEnable; the flag here is the record.
    -- Micromenu/travel create their own child Buttons which keep mouse — the
    -- toggle targets text datatexts, that partial coverage is acceptable.
    slot.clickThrough = ws and ws.clickThrough or false
    slot._quiMinWidth = ws and ws.minWidth or 0
    slot._quiXOffset = ws and ws.xOffset or 0
    slot._quiWidgetId = widgetId
    slot._quiOnWidthDirty = QueueReflow

    return slot
end

---------------------------------------------------------------------------
-- LAYOUT
---------------------------------------------------------------------------
local function SlotNaturalWidth(slot)
    local w = slot._quiFixedWidth
    if not w then
        w = (slot.text and slot.text:GetStringWidth() or 0) + 8
    end
    return max(w, slot._quiMinWidth or 0)
end

local function ReflowZone(key)
    local db = GetDB()
    if not db then return end
    local zf = zoneFrames[key]
    local spacing = db.widgetSpacing or 12
    local x = 0
    for _, slot in ipairs(zf.slots) do
        if not slot._quiOverflowHidden then
            local w = SlotNaturalWidth(slot)
            slot:SetWidth(max(1, floor(w + 0.5)))
            slot:SetHeight(db.height or 22)
            slot:ClearAllPoints()
            -- Per-widget xOffset is a pure visual nudge: positive always
            -- moves the widget toward screen-right (the right zone anchors
            -- RIGHT with a negated accumulator, so the offset stays ADDED).
            -- It is excluded from the running x accumulator, so neighbor
            -- spacing is unaffected.
            local off = slot._quiXOffset or 0
            if key == "right" then
                slot:SetPoint("RIGHT", zf, "RIGHT", -x + off, 0)
            else
                slot:SetPoint("LEFT", zf, "LEFT", x + off, 0)
            end
            x = x + slot:GetWidth() + spacing
            slot:Show()
        else
            slot:Hide()
        end
    end
    zf:SetWidth(max(1, x > 0 and (x - spacing) or 1))
    zf:SetHeight(db.height or 22)
end

-- Hide trailing widgets of zones that would collide. Pure arithmetic on the
-- widths we just computed — no GetLeft/GetRight (avoids one-frame staleness).
-- Assumes ReflowAll just reset _quiOverflowHidden and reflowed all zones.
local function ResolveOverflow()
    local db = GetDB()
    if not db then return end
    local pad = db.zonePadding or 8
    local spacing = db.widgetSpacing or 12
    local barW = bar:GetWidth()
    if not barW or barW <= 0 then return end

    local function zoneW(key) return zoneFrames[key]:GetWidth() end
    local function trimTrailing(key)
        local slots = zoneFrames[key].slots
        for i = #slots, 1, -1 do
            if not slots[i]._quiOverflowHidden then
                slots[i]._quiOverflowHidden = true
                return true
            end
        end
        return false
    end

    local guard = 0
    while guard < 100 do
        guard = guard + 1
        local leftEnd = pad + zoneW("left")
        local rightStart = barW - pad - zoneW("right")
        local cW = zoneW("center")
        local cStart = (barW - cW) / 2
        local cEnd = cStart + cW
        local collide
        if cW > 1 then
            collide = (leftEnd + spacing > cStart and trimTrailing("left"))
                or (cEnd + spacing > rightStart and trimTrailing("right"))
                or ((leftEnd + spacing > cStart or cEnd + spacing > rightStart)
                    and trimTrailing("center"))
        else
            collide = (leftEnd + spacing > rightStart)
                and (trimTrailing("left") or trimTrailing("right"))
        end
        if not collide then break end
        for _, key in ipairs(ZONES) do ReflowZone(key) end
    end
end

-- Exposed for the drag-reorder companion (dragreorder.lua): it walks live
-- slots after each ApplyAll to attach Shift-drag handlers. Returns the live
-- zoneFrames table (zoneFrames[key].slots[i] mirrors db.zones[key][i]).
function InfoBar:GetZoneFrames()
    return zoneFrames
end

function InfoBar:ReflowAll()
    if not bar then return end
    -- Protected secure children (travel's hearth button / flyout) make their
    -- ancestors' geometry combat-locked: the SetWidth/ClearAllPoints/SetPoint/
    -- Show/Hide below on slots would be ADDON_ACTION_BLOCKED. Defer the whole
    -- pass to regen (flag drained by the file-scope regen watcher). Always set
    -- the flag so the bar self-heals even if no further dirty events arrive.
    if InCombatLockdown() then
        reflowPendingCombat = true
        return
    end
    if not bar:IsShown() then return end
    -- Fresh pass: unhide everything, lay out at natural widths, then let
    -- ResolveOverflow trim trailing widgets until nothing collides.
    for _, key in ipairs(ZONES) do
        for _, slot in ipairs(zoneFrames[key].slots) do
            slot._quiOverflowHidden = nil
        end
        ReflowZone(key)
    end
    ResolveOverflow()
end

---------------------------------------------------------------------------
-- VISIBILITY: mouseover fade + combat hide (state driver — secure children)
---------------------------------------------------------------------------
local function ApplyVisibilityRules()
    local db = GetDB()
    if not db then return end

    if db.hideInCombat then
        RegisterStateDriver(bar, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(bar, "visibility")
        bar:Show()
    end

    if fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
    if db.mouseoverFade then
        local rest = (db.fadeRestOpacity or 0) / 100
        fadeTicker = C_Timer.NewTicker(0.1, function()
            local target = bar:IsMouseOver() and 1 or rest
            local cur = bar:GetAlpha()
            if math.abs(cur - target) < 0.02 then
                if cur ~= target then bar:SetAlpha(target) end
            else
                bar:SetAlpha(cur + (target - cur) * 0.35)
            end
        end)
    else
        bar:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- APPLY / REFRESH
---------------------------------------------------------------------------

-- One-time starter layout. Defaults ship zones EMPTY because AceDB's
-- removeDefaults strips array entries equal-by-index to defaults at
-- logout/profile-switch — a user-shortened list matching a default prefix
-- would be wiped and the full default layout would resurrect next login.
-- The seeded flag (false in defaults) persists fine and gates this forever.
local function SeedDefaultZones(db)
    if db.zonesSeeded then return end
    db.zones = db.zones or {}
    -- Respects zone edits made before the first ApplyAll (e.g. while the
    -- module addon was disabled): never overwrite a non-empty layout.
    for _, key in ipairs(ZONES) do
        local list = db.zones[key]
        if list and #list > 0 then
            db.zonesSeeded = true
            return
        end
    end
    db.zones.left   = { "micromenu" }
    db.zones.center = { "time" }
    db.zones.right  = { "durability", "latency", "fps", "gold" }
    db.zonesSeeded = true
end

function InfoBar:ApplyAll()
    local db = GetDB()
    if not db then return end

    -- Seed before the enabled check so the settings page (same db) shows the
    -- starter layout even while the bar is still disabled.
    SeedDefaultZones(db)

    -- Secure widget providers (travel) write secure attributes during attach.
    -- Defer to regen; drained by the file-scope regen watcher.
    if InCombatLockdown() then
        applyPendingCombat = true
        return
    end

    CreateBar()

    if not db.enabled then
        UnregisterStateDriver(bar, "visibility")
        if fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
        if QUICore.Datatexts then
            QUICore.Datatexts:UnregisterSharedTicker(bar)
        end
        for _, key in ipairs(ZONES) do ReleaseSlots(zoneFrames[key]) end
        bar:Hide()
        return
    end

    ApplyPosition()
    ApplyBackdrop()

    local pad = db.zonePadding or 8
    local zl, zc, zr = zoneFrames.left, zoneFrames.center, zoneFrames.right
    zl:ClearAllPoints(); zl:SetPoint("LEFT", bar, "LEFT", pad, 0)
    zc:ClearAllPoints(); zc:SetPoint("CENTER", bar, "CENTER", 0, 0)
    zr:ClearAllPoints(); zr:SetPoint("RIGHT", bar, "RIGHT", -pad, 0)

    local Datatexts = QUICore.Datatexts
    for _, key in ipairs(ZONES) do
        local zf = zoneFrames[key]
        ReleaseSlots(zf)
        local list = db.zones and db.zones[key] or {}
        for _, widgetId in ipairs(list) do
            local slot = CreateSlot(zf, widgetId)
            if Datatexts then
                Datatexts:AttachToSlot(slot, widgetId, db)
            end
            -- After attach: providers EnableMouse(true) in OnEnable, so the
            -- click-through disable only sticks when applied last.
            if slot.clickThrough then slot:EnableMouse(false) end
            zf.slots[#zf.slots + 1] = slot
        end
    end

    bar:Show()
    ApplyVisibilityRules()
    InfoBar:ReflowAll()
    QueueReflow()  -- second pass next frame: strings settle after first render

    -- width re-check piggybacks the shared 1s datatext ticker (covers
    -- built-in providers that don't call the width-dirty hook)
    if Datatexts then
        Datatexts:RegisterSharedTicker(bar, function()
            if bar:IsShown() then InfoBar:ReflowAll() end
        end)
    end
end

_G.QUI_RefreshInfoBar = function()
    InfoBar:ApplyAll()
end

if ns.Registry then
    ns.Registry:Register("infobar", {
        refresh = _G.QUI_RefreshInfoBar,
        priority = 41,
        group = "data",
        importCategories = { "infobar" },
    })
    -- Companion skinning registration (see skin_refresh_group_companion_test):
    -- the bar's edge border tracks the global skin via GetSkinBorderColor, but
    -- a live skin/accent recolor fires only Registry:RefreshAll("skinning") —
    -- group "data" would stay stale until /reload. Light repaint only (no
    -- slot rebuild): ApplyBackdrop re-reads the border color.
    ns.Registry:Register("infobarSkin", {
        refresh = function()
            if bar and GetDB() then ApplyBackdrop() end
        end,
        priority = 41,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

-- LOD catch-up init (PEW already fired before this addon loads). The bar
-- reads no game APIs at build time, so no warm-up delay is needed.
if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        -- next frame: let same-login sibling files finish registering providers
        C_Timer.After(0, function() InfoBar:ApplyAll() end)
    end)
end
