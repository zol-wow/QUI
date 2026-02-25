--[[
    QUI CDM
    Hooks Blizzard's EssentialCooldownViewer and UtilityCooldownViewer
    and re-layouts icons based on per-row configuration.
    
    Uses OnUpdate rescan approach to keep icons properly styled.
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local UIKit = ns.UIKit

-- Enable CDM immediately when file loads (before any events fire)
pcall(function() SetCVar("cooldownViewerEnabled", 1) end)

---------------------------------------------------------------------------
-- HELPER: Get font from general settings (uses shared helpers)
---------------------------------------------------------------------------
local Helpers = ns.Helpers
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local VIEWER_ESSENTIAL = "EssentialCooldownViewer"
local VIEWER_UTILITY = "UtilityCooldownViewer"
local HUD_MIN_WIDTH_DEFAULT = Helpers.HUD_MIN_WIDTH_DEFAULT or 200

-- Aspect ratios
local ASPECT_RATIOS = {
    square = { w = 1, h = 1 },      -- 1:1
    rectangle = { w = 4, h = 3 },   -- 4:3 (wider)
}

-- Forward declaration for mouseover hook (defined later in visibility section)
local HookFrameForMouseover

-- Migrate old 'shape' setting to 'aspectRatioCrop' for CDM rows
local function MigrateRowAspect(rowData)
    if rowData and rowData.aspectRatioCrop == nil and rowData.shape then
        if rowData.shape == "rectangle" or rowData.shape == "flat" then
            rowData.aspectRatioCrop = 1.33  -- 4:3 aspect ratio
        else
            rowData.aspectRatioCrop = 1.0   -- square
        end
    end
    return rowData.aspectRatioCrop or 1.0
end

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local NCDM = {
    hooked = {},           -- Track which viewers are hooked
    applying = {},         -- Prevent re-entry during layout
    initialized = false,
    pendingIcons = {},     -- Icons queued for skinning after combat
    pendingTicker = nil,   -- Single ticker for pending icons (self-cancels when empty)
    settingsVersion = {},  -- Track settings changes per tracker (for optimization)
}

---------------------------------------------------------------------------
-- TAINT SAFETY: Weak-keyed tables for per-viewer and per-icon state
-- Previously stored as viewer.__cdm*, icon._ncdm*, etc. which taints
-- Blizzard frames in the Midnight (12.0) taint model.
---------------------------------------------------------------------------
local _viewerState, getViewerState = Helpers.CreateStateTable()
local _iconState, getIconState     = Helpers.CreateStateTable()
local _mouseoverHooked             = Helpers.CreateStateTable()
local _keepVisibleSelections       = setmetatable({}, { __mode = "k" })

-- Combat-stable parent used for "Utility below Essential" anchoring.
-- Out of combat this proxy follows Essential; in combat it stays fixed.
local UtilityAnchorProxy = nil
local FrameDriftDebug = {
    sessions = {}, -- key -> session
    frameToKey = Helpers.CreateStateTable(),
    defaultInterval = 0.10,
    defaultThreshold = 0.5,
    defaultMaxEntries = 120,
}

local function ResolveDebugFrame(frameOrName)
    if type(frameOrName) == "table" and frameOrName.GetObjectType then
        local label = frameOrName.GetName and frameOrName:GetName() or tostring(frameOrName)
        return frameOrName, label
    end
    if type(frameOrName) == "string" then
        local frame = _G[frameOrName]
        if frame then
            return frame, frameOrName
        end
    end
    return nil, nil
end

local function ResolveDebugSession(frameOrName)
    if frameOrName == nil then
        for _, session in pairs(FrameDriftDebug.sessions) do
            if session.enabled then
                return session
            end
        end
        return nil
    end
    if type(frameOrName) == "string" then
        local byKey = FrameDriftDebug.sessions[frameOrName]
        if byKey then return byKey end
        local frame = _G[frameOrName]
        if frame then
            local key = FrameDriftDebug.frameToKey[frame]
            return key and FrameDriftDebug.sessions[key] or nil
        end
    elseif type(frameOrName) == "table" then
        local key = FrameDriftDebug.frameToKey[frameOrName]
        return key and FrameDriftDebug.sessions[key] or nil
    end
    return nil
end

local function SessionLog(session, message)
    if not session or not session.enabled then return end
    local line = string.format("[%.3f] %s", GetTime(), tostring(message))
    table.insert(session.history, line)
    if #session.history > (session.maxEntries or FrameDriftDebug.defaultMaxEntries) then
        table.remove(session.history, 1)
    end
    print("|cff34D399QUI Drift|r [" .. tostring(session.label) .. "] " .. tostring(message))
end

local function EnsureSessionHooks(session)
    if not session or session.hooked or not session.frame then return end
    local frame = session.frame

    if frame.SetPoint then
        hooksecurefunc(frame, "SetPoint", function(_, point, relativeTo, relativePoint, xOfs, yOfs)
            if not session.enabled then return end
            local relName = relativeTo and relativeTo.GetName and relativeTo:GetName() or tostring(relativeTo)
            SessionLog(session, string.format(
                "SetPoint %s -> %s %s (%.1f, %.1f)",
                tostring(point), tostring(relName), tostring(relativePoint), Helpers.SafeToNumber(xOfs, 0), Helpers.SafeToNumber(yOfs, 0)
            ))
        end)
    end

    if frame.ClearAllPoints then
        hooksecurefunc(frame, "ClearAllPoints", function()
            if not session.enabled then return end
            local stack = debugstack and debugstack(3, 1, 0) or "no stack"
            SessionLog(session, "ClearAllPoints caller=" .. tostring(stack))
        end)
    end

    if frame.HookScript then
        frame:HookScript("OnSizeChanged", function(_, w, h)
            if not session.enabled then return end
            SessionLog(session, string.format("OnSizeChanged %.1fx%.1f", Helpers.SafeToNumber(w, 0), Helpers.SafeToNumber(h, 0)))
        end)
    end

    session.hooked = true
end

local function StartSessionTicker(session)
    if not session or session.ticker then return end
    session.ticker = C_Timer.NewTicker(session.interval or FrameDriftDebug.defaultInterval, function()
        if not session.enabled or not session.frame then return end
        local x, y = session.frame:GetCenter()
        if not x or not y then return end

        if session.lastX and session.lastY then
            local dx = x - session.lastX
            local dy = y - session.lastY
            local threshold = session.threshold or FrameDriftDebug.defaultThreshold
            if math.abs(dx) > threshold or math.abs(dy) > threshold then
                local point, relTo, relPoint, ox, oy = session.frame:GetPoint(1)
                local relName = relTo and relTo.GetName and relTo:GetName() or tostring(relTo)
                SessionLog(session, string.format(
                    "center moved (dx=%.2f, dy=%.2f) combat=%s p1=%s -> %s %s (%.1f, %.1f)",
                    dx, dy, tostring(InCombatLockdown()), tostring(point), tostring(relName), tostring(relPoint),
                    Helpers.SafeToNumber(ox, 0), Helpers.SafeToNumber(oy, 0)
                ))
            end
        end

        session.lastX = x
        session.lastY = y
    end)
end

local function StopSessionTicker(session)
    if session and session.ticker then
        session.ticker:Cancel()
        session.ticker = nil
    end
end

local function DriftLog(message)
    local utilViewer = _G[VIEWER_UTILITY]
    if not utilViewer then return end
    local key = FrameDriftDebug.frameToKey[utilViewer]
    if not key then return end
    SessionLog(FrameDriftDebug.sessions[key], message)
end

_G.QUI_FrameDriftDebugEnable = function(frameOrName, opts)
    local frame, defaultLabel = ResolveDebugFrame(frameOrName)
    if not frame then
        print("|cff34D399QUI Drift|r enable failed: invalid frame")
        return false
    end

    opts = type(opts) == "table" and opts or {}
    local label = opts.label or defaultLabel or tostring(frame)
    local key = label
    local session = FrameDriftDebug.sessions[key]
    if not session then
        session = {
            key = key,
            label = label,
            frame = frame,
            history = {},
            hooked = false,
        }
        FrameDriftDebug.sessions[key] = session
    end

    session.frame = frame
    session.label = label
    session.maxEntries = tonumber(opts.maxEntries) or session.maxEntries or FrameDriftDebug.defaultMaxEntries
    session.threshold = tonumber(opts.threshold) or session.threshold or FrameDriftDebug.defaultThreshold
    session.interval = tonumber(opts.interval) or session.interval or FrameDriftDebug.defaultInterval
    session.enabled = true
    session.history = {}
    session.lastX = nil
    session.lastY = nil

    FrameDriftDebug.frameToKey[frame] = key
    EnsureSessionHooks(session)
    StopSessionTicker(session)
    StartSessionTicker(session)
    SessionLog(session, "enabled")
    return true
end

_G.QUI_FrameDriftDebugDisable = function(frameOrName)
    local session = ResolveDebugSession(frameOrName)
    if not session then
        print("|cff34D399QUI Drift|r disable: no active session")
        return false
    end
    session.enabled = false
    StopSessionTicker(session)
    print("|cff34D399QUI Drift|r [" .. tostring(session.label) .. "] disabled")
    return true
end

_G.QUI_FrameDriftDebugDump = function(frameOrName)
    local session = ResolveDebugSession(frameOrName)
    if not session then
        print("|cff34D399QUI Drift|r dump: no active session")
        return false
    end
    print("|cff34D399QUI Drift|r [" .. tostring(session.label) .. "] dump begin (" .. tostring(#session.history) .. " entries)")
    for _, line in ipairs(session.history) do
        print("|cff34D399QUI Drift|r [" .. tostring(session.label) .. "] " .. line)
    end
    print("|cff34D399QUI Drift|r [" .. tostring(session.label) .. "] dump end")
    return true
end

local function GetUtilityAnchorProxy()
    if not UtilityAnchorProxy then
        UtilityAnchorProxy = UIKit.CreateAnchorProxy(nil, {
            mirrorVisibility = false,
            sizeResolver = function(source)
                local vs = _viewerState[source]
                local width = (vs and vs.cdmIconWidth) or source:GetWidth() or 0
                local height = (vs and vs.cdmTotalHeight) or source:GetHeight() or 0
                return width, height
            end,
        })
    end
    return UtilityAnchorProxy
end

local function UpdateUtilityAnchorProxy()
    local proxy = GetUtilityAnchorProxy()
    local essViewer = _G[VIEWER_ESSENTIAL]
    if not essViewer then
        return proxy
    end
    proxy:SetSourceFrame(essViewer)
    proxy:Sync()
    return proxy
end

-- Combat-safe frame level setter. If in combat, defer until next out-of-combat layout.
local function SetFrameLevelSafe(frame, level)
    if not frame or not frame.SetFrameLevel or type(level) ~= "number" then
        return false
    end

    local fs = getViewerState(frame)
    if InCombatLockdown() then
        fs.cdmPendingFrameLevel = level
        return false
    end

    local ok = pcall(frame.SetFrameLevel, frame, level)
    if ok then
        fs.cdmPendingFrameLevel = nil
    end
    return ok
end

-- Combat-safe size setter for protected Blizzard CDM frames.
local function SetSizeSafe(frame, width, height)
    if not frame or not frame.SetSize or type(width) ~= "number" or type(height) ~= "number" then
        return false
    end

    local fs = getViewerState(frame)
    if InCombatLockdown() then
        fs.cdmPendingWidth = width
        fs.cdmPendingHeight = height
        return false
    end

    local ok = pcall(frame.SetSize, frame, width, height)
    if ok then
        fs.cdmPendingWidth = nil
        fs.cdmPendingHeight = nil
    end
    return ok
end

local function SyncViewerSelectionSafe(viewer)
    if not viewer or not viewer.Selection then
        return false
    end

    local vs = getViewerState(viewer)
    if InCombatLockdown() then
        vs.cdmPendingSelectionSync = true
        return false
    end

    -- Skip during Edit Mode: manipulating .Selection on protected CDM viewers
    -- in Edit Mode taints Blizzard's execution path, causing CompactUnitFrame
    -- "secret number value tainted by 'QUI'" errors on Edit Mode exit.
    if Helpers.IsEditModeActive() then
        vs.cdmPendingSelectionSync = true
        return false
    end

    local ok = pcall(function()
        viewer.Selection:ClearAllPoints()
        viewer.Selection:SetPoint("TOPLEFT", viewer, "TOPLEFT", 0, 0)
        viewer.Selection:SetPoint("BOTTOMRIGHT", viewer, "BOTTOMRIGHT", 0, 0)
    end)
    SetFrameLevelSafe(viewer.Selection, viewer:GetFrameLevel())

    if ok then
        vs.cdmPendingSelectionSync = nil
    end
    return ok
end

---------------------------------------------------------------------------
-- HELPER: Get database
---------------------------------------------------------------------------
-- DB accessor using shared helpers
local GetDB = Helpers.CreateDBGetter("ncdm")

---------------------------------------------------------------------------
-- HELPER: Get settings for a tracker (essential/utility)
---------------------------------------------------------------------------
local function GetTrackerSettings(trackerKey)
    local db = GetDB()
    if db and db[trackerKey] then
        return db[trackerKey]
    end
    return nil
end

local function IsHUDAnchoredToCDM()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    if Helpers and Helpers.IsHUDAnchoredToCDM then
        return Helpers.IsHUDAnchoredToCDM(profile)
    end
    return false
end

local function GetHUDMinWidth()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    if Helpers and Helpers.GetHUDMinWidthSettingsFromProfile then
        return Helpers.GetHUDMinWidthSettingsFromProfile(profile)
    end
    return false, HUD_MIN_WIDTH_DEFAULT
end

-- Shared helper exports so other modules (anchoring, buffbar) can use the
-- exact same min-width and HUD-anchor semantics.
_G.QUI_IsHUDAnchoredToCDM = IsHUDAnchoredToCDM
_G.QUI_GetHUDMinWidthSettings = GetHUDMinWidth

---------------------------------------------------------------------------
-- HELPER: Update Blizzard cooldownViewerEnabled CVar based on settings
---------------------------------------------------------------------------
local function UpdateCooldownViewerCVar()
    local db = GetDB()
    if not db then return end

    local essentialEnabled = db.essential and db.essential.enabled
    local utilityEnabled = db.utility and db.utility.enabled
    local buffEnabled = db.buff and db.buff.enabled

    -- If all relevant CDM displays are disabled, turn off Blizzard CVar.
    -- Include Buff CDM so buff-only setups don't get auto-disabled after combat.
    if essentialEnabled or utilityEnabled or buffEnabled then
        pcall(function() SetCVar("cooldownViewerEnabled", 1) end)
    else
        pcall(function() SetCVar("cooldownViewerEnabled", 0) end)
    end
end

---------------------------------------------------------------------------
-- HELPER: Check if a child frame is a cooldown icon
---------------------------------------------------------------------------
local function IsIconFrame(child)
    if not child then return false end
    return (child.Icon or child.icon) and (child.Cooldown or child.cooldown)
end

---------------------------------------------------------------------------
-- HELPER: Iterate visible icon children of a viewer (skips Selection)
-- Callback receives (child); return true from callback to stop early.
---------------------------------------------------------------------------
local function ForEachVisibleIcon(viewer, callback)
    local sel = viewer.Selection
    for i = 1, viewer:GetNumChildren() do
        local child = select(i, viewer:GetChildren())
        if child and child ~= sel and child:IsShown() and IsIconFrame(child) then
            if callback(child) then return end
        end
    end
end

---------------------------------------------------------------------------
-- HELPER: Check if an icon has a valid spell texture (not an empty placeholder)
---------------------------------------------------------------------------
local function HasValidTexture(icon)
    local tex = icon.Icon or icon.icon
    if tex and tex.GetTexture then
        local texID = tex:GetTexture()
        if texID == nil then return false end
        if type(issecretvalue) == "function" and issecretvalue(texID) then
            return true -- secret texture values imply a real texture exists
        end
        return texID ~= 0 and texID ~= ""
    end
    return false
end

---------------------------------------------------------------------------
-- HELPER: Update locked power bars and castbars for a given tracker type
---------------------------------------------------------------------------
local function UpdateLockedBarsForViewer(trackerKey)
    if trackerKey == "essential" then
        if _G.QUI_UpdateLockedPowerBar then _G.QUI_UpdateLockedPowerBar() end
        if _G.QUI_UpdateLockedSecondaryPowerBar then _G.QUI_UpdateLockedSecondaryPowerBar() end
        if _G.QUI_UpdateLockedCastbarToEssential then _G.QUI_UpdateLockedCastbarToEssential() end
    elseif trackerKey == "utility" then
        if _G.QUI_UpdateLockedPowerBarToUtility then _G.QUI_UpdateLockedPowerBarToUtility() end
        if _G.QUI_UpdateLockedSecondaryPowerBarToUtility then _G.QUI_UpdateLockedSecondaryPowerBarToUtility() end
        if _G.QUI_UpdateLockedCastbarToUtility then _G.QUI_UpdateLockedCastbarToUtility() end
    end
end

local function UpdateAllLockedBars()
    UpdateLockedBarsForViewer("essential")
    UpdateLockedBarsForViewer("utility")
end

---------------------------------------------------------------------------
-- HELPER: Get total icon capacity from row settings
---------------------------------------------------------------------------
local function GetTotalIconCapacity(settings)
    local total = 0
    for i = 1, 3 do
        local rowKey = "row" .. i
        if settings[rowKey] and settings[rowKey].iconCount then
            total = total + settings[rowKey].iconCount
        end
    end
    return total
end

---------------------------------------------------------------------------
-- HELPER: Strip Blizzard's overlay texture
---------------------------------------------------------------------------
local function StripBlizzardOverlay(icon)
    if not icon or not icon.GetRegions then return end

    for _, region in ipairs({ icon:GetRegions() }) do
        if region:IsObjectType("Texture") and region.GetAtlas then
            local ok, atlas = pcall(region.GetAtlas, region)
            if ok and atlas == "UI-HUD-CoolDownManager-IconOverlay" then
                region:SetTexture("")
                region:Hide()
                Helpers.DeferredHideOnShow(region)
            end
        end
    end
end

---------------------------------------------------------------------------
-- HELPER: Proactively block atlas borders (CPU attribution shifts to Blizzard)
---------------------------------------------------------------------------
local blockedAtlasTextures = Helpers.CreateStateTable()

local function PreventAtlasBorder(texture)
    if not texture or blockedAtlasTextures[texture] then return end
    blockedAtlasTextures[texture] = true

    -- Hook future SetAtlas calls to block border re-application
    Helpers.DeferredSetAtlasBlock(texture)
    -- Clear current state (only outside combat)
    if not InCombatLockdown() then
        if texture.SetTexture then texture:SetTexture(nil) end
        if texture.SetAlpha then texture:SetAlpha(0) end
    end
end

---------------------------------------------------------------------------
-- HELPER: Apply TexCoord to icon texture (with aspect ratio cropping)
---------------------------------------------------------------------------
local function ApplyTexCoord(icon)
    if not icon then return end
    local is = _iconState[icon]
    local z = (is and is.ncdmZoom) or 0
    local aspectRatio = (is and is.ncdmAspectRatio) or 1.0
    local baseCrop = 0.08

    -- Start with base crop + zoom
    local left = baseCrop + z
    local right = 1 - baseCrop - z
    local top = baseCrop + z
    local bottom = 1 - baseCrop - z

    -- Apply aspect ratio crop ON TOP of existing crop
    if aspectRatio > 1.0 then
        -- Wider: crop MORE from top/bottom
        local cropAmount = 1.0 - (1.0 / aspectRatio)
        local availableHeight = bottom - top
        local offset = (cropAmount * availableHeight) / 2.0
        top = top + offset
        bottom = bottom - offset
    end

    local tex = icon.Icon or icon.icon
    if tex and tex.SetTexCoord then
        tex:SetTexCoord(left, right, top, bottom)
    end
end

---------------------------------------------------------------------------
-- HELPER: One-time setup (things that only need to happen once per icon)
---------------------------------------------------------------------------
local function SetupIconOnce(icon)
    if not icon then return end
    local is = getIconState(icon)
    if is.ncdmSetup then return end
    is.ncdmSetup = true
    
    -- Remove Blizzard's mask textures
    local textures = { icon.Icon, icon.icon }
    for _, tex in ipairs(textures) do
        if tex and tex.GetMaskTexture and tex.RemoveMaskTexture then
            for i = 1, 10 do
                local mask = tex:GetMaskTexture(i)
                if mask then
                    tex:RemoveMaskTexture(mask)
                end
            end
        end
    end
    
    -- Strip Blizzard's overlay texture
    StripBlizzardOverlay(icon)
    
    -- Hide NormalTexture border
    if icon.NormalTexture then
        icon.NormalTexture:SetAlpha(0)
    end
    if icon.GetNormalTexture then
        local normalTex = icon:GetNormalTexture()
        if normalTex then
            normalTex:SetAlpha(0)
        end
    end

    -- Block atlas borders (shifts CPU attribution to Blizzard's SetAtlas)
    if icon.DebuffBorder then PreventAtlasBorder(icon.DebuffBorder) end
    if icon.BuffBorder then PreventAtlasBorder(icon.BuffBorder) end
    if icon.TempEnchantBorder then PreventAtlasBorder(icon.TempEnchantBorder) end

    -- NOTE: Removed SetTexCoord hook to avoid taint during combat
    -- TexCoord is now applied via the Layout hook instead (v1.34 approach)
end

-- Weak-keyed table to track which CooldownFlash frames have been hooked
local hookedCooldownFlash = Helpers.CreateStateTable()

---------------------------------------------------------------------------
-- HELPER: Apply icon styling
---------------------------------------------------------------------------
local function SkinIcon(icon, size, aspectRatioCrop, zoom, borderSize, borderColorTable)
    if not icon then return end
    if InCombatLockdown() then return true end

    -- Store zoom and aspect ratio for the texture coordinate calculation
    local is = getIconState(icon)
    is.ncdmZoom = zoom or 0
    is.ncdmAspectRatio = aspectRatioCrop or 1.0

    -- One-time setup (mask removal, overlay strip, SetTexCoord hook)
    SetupIconOnce(icon)

    -- Calculate dimensions (higher aspect ratio = flatter icon)
    local aspectRatio = aspectRatioCrop or 1.0
    local width = size
    local height = size / aspectRatio

    -- Pixel-snap icon dimensions to prevent sub-pixel edge rounding
    if QUICore and QUICore.PixelRound then
        width = QUICore:PixelRound(width, icon)
        height = QUICore:PixelRound(height, icon)
    end

    -- Set icon frame size
    icon:SetSize(width, height)

    -- Border (BACKGROUND texture approach)
    borderSize = borderSize or 0
    if borderSize > 0 then
        -- Convert border pixel count to exact virtual coordinates
        local bs = (QUICore and QUICore.Pixels) and QUICore:Pixels(borderSize, icon) or borderSize

        if not is.ncdmBorder then
            is.ncdmBorder = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
        end
        local bc = borderColorTable or {0, 0, 0, 1}
        is.ncdmBorder:SetColorTexture(bc[1], bc[2], bc[3], bc[4])

        is.ncdmBorder:ClearAllPoints()
        is.ncdmBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -bs, bs)
        is.ncdmBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", bs, -bs)
        is.ncdmBorder:Show()

        -- Expand hit area to include border for mouseover detection
        icon:SetHitRectInsets(-bs, -bs, -bs, -bs)
    else
        if is.ncdmBorder then
            is.ncdmBorder:Hide()
        end
        -- Reset hit area when no border
        icon:SetHitRectInsets(0, 0, 0, 0)
    end
    
    -- One-time setup for textures and flash
    if not is.ncdmPositioned then
        is.ncdmPositioned = true

        local textures = { icon.Icon, icon.icon }
        for _, tex in ipairs(textures) do
            if tex then
                tex:ClearAllPoints()
                tex:SetAllPoints(icon)
            end
        end

        -- Hide CooldownFlash entirely to fix the square flash on ability ready
        if icon.CooldownFlash then
            icon.CooldownFlash:SetAlpha(0)
            -- Hook Show to keep it hidden
            if not hookedCooldownFlash[icon.CooldownFlash] then
                hookedCooldownFlash[icon.CooldownFlash] = true
                hooksecurefunc(icon.CooldownFlash, "Show", function(self)
                    C_Timer.After(0, function()
                        if InCombatLockdown() then return end
                        self:SetAlpha(0)
                    end)
                end)
            end
        end
    end

    -- Always re-anchor cooldown frame to match current icon size
    local cooldown = icon.Cooldown or icon.cooldown
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(icon)
        -- Use simple stretchable texture so swipe fills entire frame
        cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        cooldown:SetSwipeColor(0, 0, 0, 0.8)
    end
    
    -- Always apply TexCoord (this is lightweight)
    ApplyTexCoord(icon)

    -- Hook for mouseover detection (handles dynamically created icons)
    icon:EnableMouse(true)  -- Ensure icon receives mouse events
    HookFrameForMouseover(icon)

    return true  -- Successfully skinned
end

---------------------------------------------------------------------------
-- HELPER: Apply only frame size (combat-safe lightweight path)
---------------------------------------------------------------------------
local function ApplyIconSizeOnly(icon, size, aspectRatioCrop)
    if not icon or not size or size <= 0 then return end

    local aspectRatio = aspectRatioCrop or 1.0
    local width = size
    local height = size / aspectRatio

    -- Pixel-snap icon dimensions to prevent sub-pixel edge rounding
    if QUICore and QUICore.PixelRound then
        width = QUICore:PixelRound(width, icon)
        height = QUICore:PixelRound(height, icon)
    end

    pcall(icon.SetSize, icon, width, height)
end

---------------------------------------------------------------------------
-- HELPER: Process pending icons after combat ends
---------------------------------------------------------------------------
local function ProcessPendingIcons()
    if InCombatLockdown() then return end
    if not next(NCDM.pendingIcons) then
        -- Queue is empty - cancel ticker to save CPU
        if NCDM.pendingTicker then
            NCDM.pendingTicker:Cancel()
            NCDM.pendingTicker = nil
        end
        return
    end

    for icon, data in pairs(NCDM.pendingIcons) do
        local processed = false
        if icon and icon:IsShown() then
            local success = pcall(SkinIcon, icon, data.size, data.aspectRatioCrop, data.zoom, data.borderSize, data.borderColorTable)
            if success then
                pcall(ApplyIconTextSizes, icon, data.durationSize, data.stackSize,
                    data.durationOffsetX, data.durationOffsetY, data.stackOffsetX, data.stackOffsetY,
                    data.durationTextColor, data.durationAnchor, data.stackTextColor, data.stackAnchor)
                local pis = getIconState(icon)
                pis.cdmSkinned = true
                pis.cdmSkinPending = nil
                processed = true
            end
        end
        -- If icon was hidden or skinning failed, clear pending flag so
        -- LayoutViewer can queue/skin it again on the next pass.
        if icon and not processed then
            getIconState(icon).cdmSkinPending = nil
        end
        NCDM.pendingIcons[icon] = nil
    end

    -- After processing, cancel ticker if queue is now empty
    if not next(NCDM.pendingIcons) and NCDM.pendingTicker then
        NCDM.pendingTicker:Cancel()
        NCDM.pendingTicker = nil
    end
end

-- Register for combat end to process pending icons and refresh layouts
local combatEndFrame = CreateFrame("Frame")
combatEndFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEndFrame:SetScript("OnEvent", function()
    ProcessPendingIcons()
    -- Re-apply Utility anchor after combat if it was deferred.
    C_Timer.After(0.05, function()
        if not InCombatLockdown() and _G.QUI_ApplyUtilityAnchor then
            _G.QUI_ApplyUtilityAnchor()
        end
    end)
    -- Force layout refresh after combat (layouts were skipped for CPU efficiency)
    -- Use global refresh which is defined later in the file
    C_Timer.After(0.1, function()
        if not InCombatLockdown() and _G.QUI_RefreshNCDM then
            _G.QUI_RefreshNCDM()
        end
    end)
end)

---------------------------------------------------------------------------
-- HELPER: Queue icon for skinning after combat
---------------------------------------------------------------------------
local function QueueIconForSkinning(icon, size, aspectRatioCrop, zoom, borderSize, borderColorTable, durationSize, stackSize, durationOffsetX, durationOffsetY, stackOffsetX, stackOffsetY, durationTextColor, durationAnchor, stackTextColor, stackAnchor)
    if not icon then return end

    getIconState(icon).cdmSkinPending = true
    NCDM.pendingIcons[icon] = {
        size = size,
        aspectRatioCrop = aspectRatioCrop,
        zoom = zoom,
        borderSize = borderSize,
        borderColorTable = borderColorTable or {0, 0, 0, 1},
        durationSize = durationSize,
        stackSize = stackSize,
        durationOffsetX = durationOffsetX or 0,
        durationOffsetY = durationOffsetY or 0,
        stackOffsetX = stackOffsetX or 0,
        stackOffsetY = stackOffsetY or 0,
        durationTextColor = durationTextColor or {1, 1, 1, 1},
        durationAnchor = durationAnchor or "CENTER",
        stackTextColor = stackTextColor or {1, 1, 1, 1},
        stackAnchor = stackAnchor or "BOTTOMRIGHT",
    }

    -- Start pending ticker if not already running (self-cancels when queue is empty)
    if not NCDM.pendingTicker then
        NCDM.pendingTicker = C_Timer.NewTicker(1.0, function()
            ProcessPendingIcons()
        end)
    end
end

---------------------------------------------------------------------------
-- HELPER: Apply text sizes and offsets
---------------------------------------------------------------------------
local function ApplyIconTextSizes(icon, durationSize, stackSize, durationOffsetX, durationOffsetY, stackOffsetX, stackOffsetY, durationTextColor, durationAnchor, stackTextColor, stackAnchor)
    if not icon then return end

    -- Get font from general settings
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()

    -- Default offsets to 0
    durationOffsetX = durationOffsetX or 0
    durationOffsetY = durationOffsetY or 0
    stackOffsetX = stackOffsetX or 0
    stackOffsetY = stackOffsetY or 0

    -- Default colors to white
    durationTextColor = durationTextColor or {1, 1, 1, 1}
    stackTextColor = stackTextColor or {1, 1, 1, 1}

    -- Default anchors
    durationAnchor = durationAnchor or "CENTER"
    stackAnchor = stackAnchor or "BOTTOMRIGHT"

    -- Duration text - always apply position with offset and color
    local cooldown = icon.Cooldown or icon.cooldown
    if cooldown and durationSize and durationSize > 0 then
        if cooldown.text then
            cooldown.text:SetFont(generalFont, durationSize, generalOutline)
            cooldown.text:SetTextColor(durationTextColor[1], durationTextColor[2], durationTextColor[3], durationTextColor[4] or 1)
            pcall(function()
                cooldown.text:ClearAllPoints()
                cooldown.text:SetPoint(durationAnchor, icon, durationAnchor, durationOffsetX, durationOffsetY)
                cooldown.text:SetDrawLayer("OVERLAY", 7)
            end)
        end

        local ok, regions = pcall(function() return { cooldown:GetRegions() } end)
        if ok and regions then
            for _, region in ipairs(regions) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    region:SetFont(generalFont, durationSize, generalOutline)
                    region:SetTextColor(durationTextColor[1], durationTextColor[2], durationTextColor[3], durationTextColor[4] or 1)
                    pcall(function()
                        region:ClearAllPoints()
                        region:SetPoint(durationAnchor, icon, durationAnchor, durationOffsetX, durationOffsetY)
                        region:SetDrawLayer("OVERLAY", 7)
                    end)
                end
            end
        end
    end

    -- Stack text - elevate existing Blizzard fontstring above glows
    if stackSize and stackSize > 0 then
        local foundFS = nil

        -- Find the original fontstring from various Blizzard locations
        local chargeFrame = icon.ChargeCount
        if chargeFrame then
            foundFS = chargeFrame.Current or chargeFrame.Count or chargeFrame.count
            if not foundFS and chargeFrame.GetRegions then
                pcall(function()
                    for _, region in ipairs({ chargeFrame:GetRegions() }) do
                        if region:GetObjectType() == "FontString" then
                            foundFS = region
                            break
                        end
                    end
                end)
            end
        end

        if not foundFS then
            foundFS = icon.Count or icon.count
        end

        if not foundFS and icon.GetChildren then
            pcall(function()
                for _, child in ipairs({ icon:GetChildren() }) do
                    if child then
                        local fs = child.Current or child.Count or child.count
                        if fs and fs.SetFont then
                            foundFS = fs
                            break
                        end
                    end
                end
            end)
        end

        -- Style and elevate the existing fontstring (don't create new one)
        if foundFS and foundFS.SetFont then
            pcall(function()
                foundFS:SetFont(generalFont, stackSize, generalOutline)
                foundFS:SetTextColor(stackTextColor[1], stackTextColor[2], stackTextColor[3], stackTextColor[4] or 1)
                foundFS:ClearAllPoints()
                foundFS:SetPoint(stackAnchor, icon, stackAnchor, stackOffsetX, stackOffsetY)
                foundFS:SetDrawLayer("OVERLAY", 7)

                -- Elevate parent frame to render above glow effects
                local parentFrame = foundFS:GetParent()
                if parentFrame and parentFrame.SetFrameLevel and icon.GetFrameLevel then
                    local iconLevel = icon:GetFrameLevel() or 0
                    local currentLevel = parentFrame:GetFrameLevel() or 0
                    SetFrameLevelSafe(parentFrame, math.max(currentLevel, iconLevel + 10))
                end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- HELPER: Get custom entries data for a tracker
---------------------------------------------------------------------------
local function GetCustomData(trackerKey)
    if QUICore and QUICore.db and QUICore.db.char and QUICore.db.char.ncdm
        and QUICore.db.char.ncdm[trackerKey] and QUICore.db.char.ncdm[trackerKey].customEntries then
        return QUICore.db.char.ncdm[trackerKey].customEntries
    end
    return nil
end

---------------------------------------------------------------------------
-- HELPER: Collect visible icons from viewer (stable order using layoutIndex)
---------------------------------------------------------------------------
local function CollectIcons(viewer, trackerKey)
    local icons = {}
    if not viewer or not viewer.GetNumChildren then return icons end

    local numChildren = viewer:GetNumChildren()
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        -- Skip custom CDM icons from child enumeration (we inject them separately)
        if child and child ~= viewer.Selection and not child._isCustomCDMIcon and IsIconFrame(child) then
            local cis = _iconState[child]
            if child:IsShown() or (cis and cis.ncdmHidden) then
                if HasValidTexture(child) then
                    -- Track that this icon had a valid texture (last-known-good state)
                    getIconState(child).ncdmHadTexture = true
                    table.insert(icons, child)
                elseif InCombatLockdown() and cis and cis.ncdmHadTexture then
                    -- During combat, keep icons that previously had a valid texture.
                    -- Spell morphs (e.g. Devourer DH) momentarily strip the texture;
                    -- we trust the icon will get its texture back shortly.
                    table.insert(icons, child)
                else
                    -- Clear flags on textureless frames out of combat so they
                    -- aren't perpetually re-collected; Blizzard will Show() them when ready
                    if cis then
                        cis.ncdmHidden = nil
                        cis.ncdmHadTexture = nil
                    end
                end
            end
        end
    end

    -- Sort by Blizzard's layoutIndex (stable order)
    table.sort(icons, function(a, b)
        local indexA = a.layoutIndex or 9999
        local indexB = b.layoutIndex or 9999
        return indexA < indexB
    end)

    -- Inject custom CDM icons: positioned entries at specific slots,
    -- unpositioned entries via before/after placement logic
    if ns.CustomCDM and trackerKey then
        local viewerName = (viewer == _G[VIEWER_ESSENTIAL]) and VIEWER_ESSENTIAL or VIEWER_UTILITY
        local customIcons = ns.CustomCDM:GetIcons(viewerName)
        if #customIcons > 0 then
            local customData = GetCustomData(trackerKey)
            local placement = customData and customData.placement or "after"

            -- Phase 1: Separate into positioned and unpositioned
            local positioned = {}
            local unpositioned = {}
            for idx, ci in ipairs(customIcons) do
                local entry = ci._customCDMEntry
                if entry and entry.position and entry.position > 0 then
                    table.insert(positioned, { icon = ci, origIndex = idx })
                else
                    table.insert(unpositioned, ci)
                end
            end

            -- Phase 2: Insert unpositioned using existing before/after logic
            if #unpositioned > 0 then
                if placement == "before" then
                    local merged = {}
                    for _, ci in ipairs(unpositioned) do table.insert(merged, ci) end
                    for _, bi in ipairs(icons) do table.insert(merged, bi) end
                    icons = merged
                else
                    for _, ci in ipairs(unpositioned) do table.insert(icons, ci) end
                end
            end

            -- Phase 3: Insert positioned entries at their specified slots
            -- Sort by descending position so earlier inserts don't shift later ones
            -- Tie-break by original array order (ascending) for stable results
            table.sort(positioned, function(a, b)
                local posA = a.icon._customCDMEntry and a.icon._customCDMEntry.position or 0
                local posB = b.icon._customCDMEntry and b.icon._customCDMEntry.position or 0
                if posA ~= posB then return posA > posB end
                return a.origIndex < b.origIndex
            end)
            for _, item in ipairs(positioned) do
                local pos = item.icon._customCDMEntry.position
                local insertAt = math.min(pos, #icons + 1)
                table.insert(icons, insertAt, item.icon)
            end
        end
    end

    return icons
end

---------------------------------------------------------------------------
-- CORE: Layout and skin icons for a viewer
---------------------------------------------------------------------------
local function LayoutViewer(viewerName, trackerKey)
    local viewer = _G[viewerName]
    if not viewer then return end

    -- Never layout during Edit Mode — user is manually resizing/positioning.
    -- LayoutViewer recalculates icon positions and viewer size, which would
    -- fight the user's manual resize and snap the viewer back.
    if Helpers.IsEditModeActive() then return end

    local settings = GetTrackerSettings(trackerKey)
    if not settings or not settings.enabled then return end
    -- Allow re-layout in combat so spell morphs/procs don't leave the bars in a
    -- Blizzard-sized state until combat ends. Skinning work still defers in combat.

    -- Prevent re-entry during layout
    if NCDM.applying[trackerKey] then return end
    local vs = getViewerState(viewer)
    if vs.cdmLayoutRunning then return end

    NCDM.applying[trackerKey] = true
    vs.cdmLayoutRunning = true

    -- Apply HUD layer priority
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering[trackerKey] or 5
    if QUICore and QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
        SetFrameLevelSafe(viewer, frameLevel)
    end
    local vfs = _viewerState[viewer]
    if not InCombatLockdown() and vfs and vfs.cdmPendingFrameLevel then
        SetFrameLevelSafe(viewer, vfs.cdmPendingFrameLevel)
    end

    -- Check for vertical layout mode
    local layoutDirection = settings.layoutDirection or "HORIZONTAL"
    local isVertical = (layoutDirection == "VERTICAL")

    -- Store layout direction on viewer for power bar snap detection
    vs.cdmLayoutDirection = layoutDirection

    local allIcons = CollectIcons(viewer, trackerKey)
    local totalCapacity = GetTotalIconCapacity(settings)
    
    -- Icons to layout
    local iconsToLayout = {}
    for i = 1, math.min(#allIcons, totalCapacity) do
        local icon = allIcons[i]
        iconsToLayout[i] = icon
        getIconState(icon).ncdmHidden = nil
        icon:Show()
    end

    -- Hide overflow
    for i = totalCapacity + 1, #allIcons do
        local icon = allIcons[i]
        if icon then
            getIconState(icon).ncdmHidden = true
            icon:Hide()
            icon:ClearAllPoints()
        end
    end
    
    if #iconsToLayout == 0 then
        NCDM.applying[trackerKey] = false
        vs.cdmLayoutRunning = nil
        return
    end
    
    -- Build row config
    local rows = {}
    for i = 1, 3 do
        local rowKey = "row" .. i
        if settings[rowKey] and settings[rowKey].iconCount and settings[rowKey].iconCount > 0 then
            -- Migrate old shape setting to aspectRatioCrop if needed
            MigrateRowAspect(settings[rowKey])
            table.insert(rows, {
                count = settings[rowKey].iconCount,
                size = settings[rowKey].iconSize or 50,
                borderSize = settings[rowKey].borderSize or 2,
                borderColorTable = settings[rowKey].borderColorTable or {0, 0, 0, 1},
                aspectRatioCrop = settings[rowKey].aspectRatioCrop or 1.0,
                zoom = settings[rowKey].zoom or 0,
                padding = settings[rowKey].padding or 0,
                yOffset = settings[rowKey].yOffset or 0,
                xOffset = settings[rowKey].xOffset or 0,
                durationSize = settings[rowKey].durationSize or 14,
                durationOffsetX = settings[rowKey].durationOffsetX or 0,
                durationOffsetY = settings[rowKey].durationOffsetY or 0,
                durationTextColor = settings[rowKey].durationTextColor or {1, 1, 1, 1},
                durationAnchor = settings[rowKey].durationAnchor or "CENTER",
                stackSize = settings[rowKey].stackSize or 14,
                stackOffsetX = settings[rowKey].stackOffsetX or 0,
                stackOffsetY = settings[rowKey].stackOffsetY or 0,
                stackTextColor = settings[rowKey].stackTextColor or {1, 1, 1, 1},
                stackAnchor = settings[rowKey].stackAnchor or "BOTTOMRIGHT",
                opacity = settings[rowKey].opacity or 1.0,
            })
        end
    end

    -- Calculate potential row widths based on SETTINGS (not actual icons)
    -- Used by power bars and castbars that lock to CDM
    local potentialRow1Width = 0
    local potentialBottomRowWidth = 0
    if rows[1] then
        local iconWidth = rows[1].size
        local iconCount = rows[1].count
        local padding = rows[1].padding or 0
        potentialRow1Width = (iconCount * iconWidth) + ((iconCount - 1) * padding)
    end
    if rows[#rows] then
        local iconWidth = rows[#rows].size
        local iconCount = rows[#rows].count
        local padding = rows[#rows].padding or 0
        potentialBottomRowWidth = (iconCount * iconWidth) + ((iconCount - 1) * padding)
    end

    if #rows == 0 then
        NCDM.applying[trackerKey] = false
        vs.cdmLayoutRunning = nil
        return
    end
    
    -- Calculate row/column dimensions for centering
    local iconIndex = 1
    local maxRowWidth = 0
    local maxColHeight = 0
    local rowWidths = {}
    local colHeights = {}
    local tempIndex = 1
    local rowGap = 5

    for rowNum, rowConfig in ipairs(rows) do
        local iconsInRow = math.min(rowConfig.count, #iconsToLayout - tempIndex + 1)
        if iconsInRow <= 0 then break end

        local iconWidth = rowConfig.size
        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconHeight = rowConfig.size / aspectRatio

        if isVertical then
            -- Vertical: icons stack vertically in each "column"
            local colHeight = (iconsInRow * iconHeight) + ((iconsInRow - 1) * rowConfig.padding)
            colHeights[rowNum] = colHeight
            rowWidths[rowNum] = iconWidth
            if colHeight > maxColHeight then
                maxColHeight = colHeight
            end
        else
            -- Horizontal: icons spread in each row
            local rowWidth = (iconsInRow * iconWidth) + ((iconsInRow - 1) * rowConfig.padding)
            rowWidths[rowNum] = rowWidth
            if rowWidth > maxRowWidth then
                maxRowWidth = rowWidth
            end
        end
        tempIndex = tempIndex + iconsInRow
    end

    -- Calculate total width/height for CENTER-based positioning
    local totalHeight = 0
    local totalWidth = 0
    local rowHeights = {}
    local numRowsUsed = 0
    local tempIdx = 1

    for rowNum, rowConfig in ipairs(rows) do
        local iconsInRow = math.min(rowConfig.count, #iconsToLayout - tempIdx + 1)
        if iconsInRow <= 0 then break end

        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconHeight = rowConfig.size / aspectRatio
        local iconWidth = rowConfig.size
        rowHeights[rowNum] = iconHeight

        numRowsUsed = numRowsUsed + 1

        if isVertical then
            -- Vertical: columns stack horizontally
            totalWidth = totalWidth + iconWidth
            if numRowsUsed > 1 then
                totalWidth = totalWidth + rowGap
            end
        else
            -- Horizontal: rows stack vertically
            totalHeight = totalHeight + iconHeight
            if numRowsUsed > 1 then
                totalHeight = totalHeight + rowGap
            end
        end
        tempIdx = tempIdx + iconsInRow
    end

    -- For vertical, use max column height; for horizontal, use max row width
    if isVertical then
        totalHeight = maxColHeight
        maxRowWidth = totalWidth
    end

    -- Optional floor for HUD layouts anchored to CDM (player/target spacing safety).
    -- Apply this to container/anchor widths, but keep row layout widths untouched so
    -- icon spacing remains visually centered.
    local minWidthEnabled, minWidth = GetHUDMinWidth()
    local applyHUDMinWidth = minWidthEnabled and IsHUDAnchoredToCDM()
    if applyHUDMinWidth then
        maxRowWidth = math.max(maxRowWidth, minWidth)
        potentialRow1Width = math.max(potentialRow1Width, minWidth)
        potentialBottomRowWidth = math.max(potentialBottomRowWidth, minWidth)
    end
    
    -- Position icons using CENTER-based anchoring (more stable, less flicker)
    local currentY = totalHeight / 2  -- Start from top (positive Y from center)
    local currentX = -totalWidth / 2  -- Start from left (negative X from center) for vertical

    for rowNum, rowConfig in ipairs(rows) do
        local rowIcons = {}
        local iconsInRow = 0

        for i = 1, rowConfig.count do
            if iconIndex <= #iconsToLayout then
                table.insert(rowIcons, iconsToLayout[iconIndex])
                iconIndex = iconIndex + 1
                iconsInRow = iconsInRow + 1
            end
        end

        if iconsInRow == 0 then break end

        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconWidth = rowConfig.size
        local iconHeight = rowConfig.size / aspectRatio
        local rowWidth = rowWidths[rowNum] or (iconsInRow * iconWidth) + ((iconsInRow - 1) * rowConfig.padding)
        local colHeight = colHeights[rowNum] or (iconsInRow * iconHeight) + ((iconsInRow - 1) * rowConfig.padding)

        for i, icon in ipairs(rowIcons) do
            local x, y

            if isVertical then
                -- Vertical: icons stack top-to-bottom within each column
                -- Columns stack left-to-right
                local colCenterX = currentX + (iconWidth / 2)
                local colStartY = totalHeight / 2 - iconHeight / 2
                y = colStartY - ((i - 1) * (iconHeight + rowConfig.padding)) + rowConfig.yOffset
                x = colCenterX + (rowConfig.xOffset or 0)
            else
                -- Horizontal: icons spread left-to-right within each row
                -- Rows stack top-to-bottom
                local rowCenterY = currentY - (iconHeight / 2) + rowConfig.yOffset
                local rowStartX = -rowWidth / 2 + iconWidth / 2
                x = rowStartX + ((i - 1) * (iconWidth + rowConfig.padding)) + (rowConfig.xOffset or 0)
                y = rowCenterY
            end

            -- Only skin if not already skinned with these settings
            local lis = getIconState(icon)
            if not lis.cdmSkinned then
                if InCombatLockdown() then
                    -- Combat-safe immediate size inheritance so custom icons do not
                    -- temporarily display at their creation size.
                    ApplyIconSizeOnly(icon, rowConfig.size, rowConfig.aspectRatioCrop)
                    -- Queue for after combat
                    QueueIconForSkinning(icon, rowConfig.size, rowConfig.aspectRatioCrop, rowConfig.zoom,
                        rowConfig.borderSize, rowConfig.borderColorTable, rowConfig.durationSize, rowConfig.stackSize,
                        rowConfig.durationOffsetX, rowConfig.durationOffsetY,
                        rowConfig.stackOffsetX, rowConfig.stackOffsetY,
                        rowConfig.durationTextColor, rowConfig.durationAnchor,
                        rowConfig.stackTextColor, rowConfig.stackAnchor)
                else
                    local success = pcall(SkinIcon, icon, rowConfig.size, rowConfig.aspectRatioCrop, rowConfig.zoom, rowConfig.borderSize, rowConfig.borderColorTable)
                    if success then
                        pcall(ApplyIconTextSizes, icon, rowConfig.durationSize, rowConfig.stackSize,
                            rowConfig.durationOffsetX, rowConfig.durationOffsetY,
                            rowConfig.stackOffsetX, rowConfig.stackOffsetY,
                            rowConfig.durationTextColor, rowConfig.durationAnchor,
                            rowConfig.stackTextColor, rowConfig.stackAnchor)
                        lis.cdmSkinned = true
                    end
                end
            end

            -- Position using CENTER anchor (more stable than TOPLEFT)
            -- Pixel-snap position so icon/border edges land on pixel boundaries
            if QUICore and QUICore.PixelRound then
                x = QUICore:PixelRound(x, viewer)
                y = QUICore:PixelRound(y, viewer)
            end
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", viewer, "CENTER", x, y)
            icon:Show()

            -- Apply row opacity
            local opacity = rowConfig.opacity or 1.0
            icon:SetAlpha(opacity)
        end

        if isVertical then
            currentX = currentX + iconWidth + rowGap
        else
            currentY = currentY - iconHeight - rowGap
        end
    end
    
    -- Store dimensions — prefer bounds-corrected values if they exist for the
    -- same icon count (prevents feedback loop between formula and measurement).
    if vs._boundsCorrectedIconCount == #iconsToLayout
        and vs._boundsCorrectedW and vs._boundsCorrectedH
        and math.abs(maxRowWidth - vs._boundsCorrectedW) < 5
        and math.abs(totalHeight - vs._boundsCorrectedH) < 5 then
        maxRowWidth = vs._boundsCorrectedW
        totalHeight = vs._boundsCorrectedH
    else
        -- Icon count changed or formula diverged significantly — clear stale correction
        vs._boundsCorrectedW = nil
        vs._boundsCorrectedH = nil
        vs._boundsCorrectedIconCount = nil
    end
    vs.cdmIconWidth = maxRowWidth
    vs.cdmTotalHeight = totalHeight
    if QUI and QUI.DebugPrint then
        local rowDbg = ""
        for rn, rc in ipairs(rows) do
            local actual = math.min(rc.count, #iconsToLayout - (function()
                local idx = 1
                for ri = 1, rn - 1 do idx = idx + math.min(rows[ri].count, #iconsToLayout - idx + 1) end
                return idx
            end)() + 1)
            rowDbg = rowDbg .. format(" r%d(%d/%d sz=%d pad=%d w=%d)",
                rn, actual, rc.count, rc.size, rc.padding or 0, rowWidths[rn] or 0)
        end
        QUI:DebugPrint(format("|cff34D399CDM|r LayoutViewer %s: icons=%d maxRowW=%.0f totalH=%.0f%s",
            trackerKey, #iconsToLayout, maxRowWidth, totalHeight, rowDbg))
    end
    vs.cdmRow1IconHeight = rows[1] and (rows[1].size / (rows[1].aspectRatioCrop or 1.0)) or 0
    vs.cdmRow1BorderSize = rows[1] and rows[1].borderSize or 0
    vs.cdmBottomRowBorderSize = rows[#rows] and rows[#rows].borderSize or 0
    vs.cdmBottomRowYOffset = rows[#rows] and rows[#rows].yOffset or 0
    -- In vertical mode, use total width for all row width vars so power bars span full viewer width
    if isVertical then
        vs.cdmRow1Width = maxRowWidth
        vs.cdmBottomRowWidth = maxRowWidth
        vs.cdmPotentialRow1Width = maxRowWidth
        vs.cdmPotentialBottomRowWidth = maxRowWidth
    else
        local row1Width = rowWidths[1] or maxRowWidth
        local bottomRowWidth = rowWidths[#rows] or maxRowWidth
        if applyHUDMinWidth then
            row1Width = math.max(row1Width, minWidth)
            bottomRowWidth = math.max(bottomRowWidth, minWidth)
        end
        vs.cdmRow1Width = row1Width  -- Row 1 specifically for power bar snap
        vs.cdmBottomRowWidth = bottomRowWidth  -- Bottom row for Utility snap
        vs.cdmPotentialRow1Width = potentialRow1Width  -- Based on settings, not actual icons
        vs.cdmPotentialBottomRowWidth = potentialBottomRowWidth
    end

    -- Schedule a delayed bounds correction: Blizzard's own CDM layout may
    -- reposition icons after our SetSize, so we measure actual icon bounds
    -- after a short delay and correct viewer state + proxy if they differ.
    if not InCombatLockdown() then
        if vs._boundsCorrectionTimer then
            vs._boundsCorrectionTimer:Cancel()
        end
        vs._boundsCorrectionTimer = C_Timer.NewTimer(0.15, function()
            vs._boundsCorrectionTimer = nil
            if InCombatLockdown() then return end
            local boundsL, boundsR, boundsT, boundsB
            local iconCount = 0
            ForEachVisibleIcon(viewer, function(child)
                local il, ir, it, ib = child:GetLeft(), child:GetRight(), child:GetTop(), child:GetBottom()
                if il and ir and it and ib then
                    iconCount = iconCount + 1
                    boundsL = boundsL and math.min(boundsL, il) or il
                    boundsR = boundsR and math.max(boundsR, ir) or ir
                    boundsT = boundsT and math.max(boundsT, it) or it
                    boundsB = boundsB and math.min(boundsB, ib) or ib
                end
            end)
            if iconCount >= 1 and boundsL and boundsR and boundsT and boundsB then
                local measuredW = boundsR - boundsL
                local measuredH = boundsT - boundsB
                -- Convert screen-space bounds to viewer-local coordinate space.
                -- GetLeft/GetRight return UIParent-unit values; viewer state stores
                -- viewer-local values.  When the viewer has a non-1.0 scale (Blizzard
                -- "Icon Size" slider), screen bounds are larger by that scale factor.
                local viewerToScreen = viewer:GetEffectiveScale()
                local uiParentScale = UIParent:GetEffectiveScale()
                if viewerToScreen and uiParentScale and uiParentScale > 0 then
                    local scaleRatio = viewerToScreen / uiParentScale
                    if scaleRatio > 0 and math.abs(scaleRatio - 1.0) > 0.001 then
                        measuredW = measuredW / scaleRatio
                        measuredH = measuredH / scaleRatio
                    end
                end
                if measuredW > 1 and measuredH > 1 then
                    local curW = vs.cdmIconWidth or 0
                    local curH = vs.cdmTotalHeight or 0
                    if math.abs(curW - measuredW) > 1 or math.abs(curH - measuredH) > 1 then
                        vs.cdmIconWidth = measuredW
                        vs.cdmTotalHeight = measuredH
                        vs.cdmRow1Width = measuredW
                        vs.cdmBottomRowWidth = measuredW
                        vs.cdmPotentialRow1Width = measuredW
                        vs.cdmPotentialBottomRowWidth = measuredW
                        vs._boundsCorrectedW = measuredW
                        vs._boundsCorrectedH = measuredH
                        vs._boundsCorrectedIconCount = iconCount
                        if QUI and QUI.DebugPrint then
                            local vLocalScale = viewer:GetScale() or 0
                            local vl, vr = viewer:GetLeft(), viewer:GetRight()
                            local viewerScreenW = (vl and vr) and (vr - vl) or 0
                            QUI:DebugPrint(format("|cff34D399CDM|r BoundsCorrection %s: formula=%.0fx%.0f actual=%.0fx%.0f icons=%d viewerScale=%.3f viewerScreenW=%.1f",
                                trackerKey, curW, curH, measuredW, measuredH, iconCount, vLocalScale, viewerScreenW))
                        end
                        if _G.QUI_UpdateCDMAnchorProxyFrames then
                            _G.QUI_UpdateCDMAnchorProxyFrames()
                        end
                    end
                end
            end
        end)
    end

    -- Resize viewer (suppress OnSizeChanged triggering another layout)
    if maxRowWidth > 0 and totalHeight > 0 then
        if InCombatLockdown() then
            SetSizeSafe(viewer, maxRowWidth, totalHeight)
        else
            vs.cdmLayoutSuppressed = (vs.cdmLayoutSuppressed or 0) + 1
            SetSizeSafe(viewer, maxRowWidth, totalHeight)
            vs.cdmLayoutSuppressed = vs.cdmLayoutSuppressed - 1
            if vs.cdmLayoutSuppressed <= 0 then
                vs.cdmLayoutSuppressed = nil
            end
        end
        SyncViewerSelectionSafe(viewer)
    end

    -- Keep frame-anchoring CDM proxy parents up to date when safe.
    -- In combat, the proxy layer now freezes and schedules a post-combat refresh
    -- to avoid edge-anchor drift on dependent frames.
    if _G.QUI_UpdateCDMAnchorProxyFrames then
        _G.QUI_UpdateCDMAnchorProxyFrames()
    end

    NCDM.applying[trackerKey] = false
    vs.cdmLayoutRunning = nil

    -- If Essential just finished layout and anchor mode is on, reposition Utility
    if trackerKey == "essential" then
        local db = GetDB()
        if db and db.utility and db.utility.anchorBelowEssential then
            C_Timer.After(0.05, function()
                if _G.QUI_ApplyUtilityAnchor then
                    _G.QUI_ApplyUtilityAnchor()
                end
            end)
        end
    end

    -- Update locked power bars, castbars, and unit frames after layout completes
    -- Debounced to prevent spam during rapid layout changes.
    -- Skip entirely during combat: Blizzard mutates viewer sizes so
    -- GetCenter()-based position math drifts.  Post-combat RefreshAll
    -- will trigger a full update with correct frame geometry.
    if not vs.cdmUpdatePending and not InCombatLockdown() then
        vs.cdmUpdatePending = true
        C_Timer.After(0.05, function()
            vs.cdmUpdatePending = nil
            UpdateLockedBarsForViewer(trackerKey)
            -- Unit frames anchored to CDM (can be anchored to either Essential or Utility)
            if _G.QUI_UpdateCDMAnchoredUnitFrames then
                _G.QUI_UpdateCDMAnchoredUnitFrames()
            end
            -- Update keybind text on CDM icons
            if _G.QUI_UpdateViewerKeybinds then
                _G.QUI_UpdateViewerKeybinds(viewerName)
            end
        end)
    end
end


---------------------------------------------------------------------------
-- HOOK: Setup viewer with OnUpdate rescan
---------------------------------------------------------------------------
local function HookViewer(viewerName, trackerKey)
    local viewer = _G[viewerName]
    if not viewer then return end
    if NCDM.hooked[trackerKey] then return end

    NCDM.hooked[trackerKey] = true

    local hvs = getViewerState(viewer)

    -- Step 1 & 3: OnShow hook - enable polling and single deferred layout
    viewer:HookScript("OnShow", function(self)
        -- Enable polling when viewer becomes visible (restore handler if we cleared it on Hide)
        local svs = _viewerState[self]
        if svs and svs.ncdmUpdateFrame then
            if svs.ncdmUpdateHandler then
                svs.ncdmUpdateFrame:SetScript("OnUpdate", svs.ncdmUpdateHandler)
            end
            svs.ncdmUpdateFrame:Show()
        end
        -- Single deferred layout
        C_Timer.After(0.02, function()
            if self:IsShown() then
                LayoutViewer(viewerName, trackerKey)
                -- Apply anchor for Utility viewer after layout
                if trackerKey == "utility" and _G.QUI_ApplyUtilityAnchor then
                    _G.QUI_ApplyUtilityAnchor()
                end
            end
        end)
    end)

    -- Step 1: OnHide hook - disable polling to save CPU (SetScript nil stops OnUpdate entirely)
    viewer:HookScript("OnHide", function(self)
        local svs = _viewerState[self]
        if svs and svs.ncdmUpdateFrame then
            svs.ncdmUpdateFrame:SetScript("OnUpdate", nil)
            svs.ncdmUpdateFrame:Hide()
        end
    end)

    -- Hook SetScale: Blizzard's CDM "Icon Size" slider may call SetScale on
    -- the viewer.  SetScale does NOT fire OnSizeChanged, so the proxy would
    -- never learn about the scale change.  Trigger a proxy refresh so the
    -- effective-scale comparison in GetCDMAnchorProxy can adjust dimensions.
    hooksecurefunc(viewer, "SetScale", function(self, newScale)
        if QUI and QUI.DebugPrint then
            local w, h = self:GetWidth(), self:GetHeight()
            local effScale = self:GetEffectiveScale()
            local parentEffScale = UIParent:GetEffectiveScale()
            local boundsL, boundsR = self:GetLeft(), self:GetRight()
            local boundsW = (boundsL and boundsR) and (boundsR - boundsL) or 0
            QUI:DebugPrint(format("|cffFF4444CDM SetScale|r %s: newScale=%.3f effScale=%.3f parentEffScale=%.3f logical=%.0fx%.0f boundsW=%.0f",
                viewerName == VIEWER_ESSENTIAL and "Ess" or "Util",
                newScale, effScale, parentEffScale, w, h, boundsW))
        end
        -- Refresh proxy dimensions to account for the new scale
        if not InCombatLockdown() and _G.QUI_UpdateCDMAnchorProxyFrames then
            _G.QUI_UpdateCDMAnchorProxyFrames()
        end
    end)

    -- Helper: measure icon bounding box (icons can extend beyond viewer frame).
    -- Returns boundsW, boundsH in screen-space coords, or nil if no icons.
    local function MeasureViewerIconBounds(v)
        local boundsL, boundsR, boundsT, boundsB
        local iconCount = 0
        ForEachVisibleIcon(v, function(child)
            local cl, cr, ct, cb = child:GetLeft(), child:GetRight(), child:GetTop(), child:GetBottom()
            if cl and cr and ct and cb then
                iconCount = iconCount + 1
                boundsL = boundsL and math.min(boundsL, cl) or cl
                boundsR = boundsR and math.max(boundsR, cr) or cr
                boundsT = boundsT and math.max(boundsT, ct) or ct
                boundsB = boundsB and math.min(boundsB, cb) or cb
            end
        end)
        if iconCount > 0 and boundsL and boundsR and boundsT and boundsB then
            return boundsR - boundsL, boundsT - boundsB, iconCount
        end
        return nil, nil, 0
    end

    -- Step 5: OnSizeChanged hook - increment layout counter
    viewer:HookScript("OnSizeChanged", function(self)
        local svs = getViewerState(self)

        -- Debug: log every OnSizeChanged call (before any guards)
        local isEditMode = Helpers.IsEditModeActive()
        if QUI and QUI.DebugPrint then
            local w, h = self:GetWidth(), self:GetHeight()
            local suppressed = svs.cdmLayoutSuppressed
            local running = svs.cdmLayoutRunning
            QUI:DebugPrint(format("|cffFFFF00CDM OnSizeChanged|r %s: w=%.1f h=%.1f suppressed=%s running=%s editMode=%s",
                viewerName == VIEWER_ESSENTIAL and "Ess" or "Util",
                w or 0, h or 0, tostring(suppressed), tostring(running), tostring(isEditMode)))
        end

        if svs.cdmLayoutSuppressed or svs.cdmLayoutRunning then
            svs.ncdmBlizzardLayoutCount = (svs.ncdmBlizzardLayoutCount or 0) + 1
            return
        end

        -- During Edit Mode: skip full layout (would fight user's manual resize),
        -- just update cached viewer state dimensions from actual frame size so
        -- anchor proxies AND size-stable center offset math pick up the new size.
        -- Selection overlay is managed by Blizzard's AnchorSelectionFrame during
        -- Edit Mode — addon manipulation of .Selection causes taint.
        if Helpers.IsEditModeActive() then
            svs._wasInEditMode = true  -- Track for exit transition detection
            -- Blizzard resets viewers to ~1x1 between each Edit Mode layout
            -- pass.  Detect transient resets using the LOGICAL viewer size
            -- (before icon measurement) so we don't corrupt state.
            local logicalW, logicalH = self:GetWidth(), self:GetHeight()
            if not logicalW or not logicalH or logicalW < 2 or logicalH < 2 then
                return
            end
            -- Blizzard's "Icon Size" slider changes the viewer frame size
            -- (logical size) immediately but doesn't re-lay-out icons until
            -- later.  Icon bounds are STALE from QUI's previous LayoutViewer
            -- and create a dead zone where the state can't shrink below the
            -- old icon extent.  Use LOGICAL size so the slider tracks in
            -- real-time in both directions.  Keep icon bounds for diagnostics.
            local iconW, iconH, iconCount = MeasureViewerIconBounds(self)
            local w = logicalW
            local h = logicalH
            -- Update ALL viewer state fields that the anchoring system reads.
            -- GetParentAnchorRect / GetFrameAnchorRect prefer row1Width over
            -- iconWidth, so we must update row1Width too or the center offset
            -- math uses stale values and dependent frames don't move.
            svs.cdmIconWidth = w
            svs.cdmRow1Width = w
            svs.cdmBottomRowWidth = w
            svs.cdmPotentialRow1Width = w
            svs.cdmPotentialBottomRowWidth = w
            svs.cdmTotalHeight = h
            -- Update proxy sizes
            if _G.QUI_UpdateCDMAnchorProxyFrames then
                _G.QUI_UpdateCDMAnchorProxyFrames()
            end
            -- DO NOT call QUI_ApplyFrameAnchor on CDM viewers during Edit Mode:
            -- they are protected Blizzard system frames (system=20) and
            -- ClearAllPoints/SetPoint causes Blizzard to reset the viewer,
            -- breaking Selection and fighting Edit Mode's position control.
            -- Position is corrected on Edit Mode exit via the exit callback.
            local anchorKey = viewerName == VIEWER_ESSENTIAL and "cdmEssential" or "cdmUtility"
            -- Re-anchor THIS viewer to its configured parent (position-only,
            -- no auto-sizing — user's manual resize must be preserved).
            -- Keeps the viewer anchored correctly in its chain during resize.
            if _G.QUI_ReanchorFramePositionOnly then
                _G.QUI_ReanchorFramePositionOnly(anchorKey)
            end
            -- When Essential resizes, also reposition Utility via legacy anchor
            -- (anchorBelowEssential). Safe outside combat (pcall-wrapped SetPoint).
            if viewerName == VIEWER_ESSENTIAL and _G.QUI_ApplyUtilityAnchor then
                _G.QUI_ApplyUtilityAnchor()
            end
            -- Re-anchor DEPENDENT frames (boss frames, objective tracker, unit
            -- frames, power bars, cast bars, etc.) via BFS chain walk
            if _G.QUI_UpdateFramesAnchoredTo then
                _G.QUI_UpdateFramesAnchoredTo(anchorKey)
            end
            -- Update power bar WIDTH to match viewer (position is handled by
            -- QUI_UpdateFramesAnchoredTo above, but width is separate).
            UpdateLockedBarsForViewer(viewerName == VIEWER_ESSENTIAL and "essential" or "utility")
            -- Anchor chain diagnostic: CDM viewer → viewer state → proxy → power bars
            local proxyFrame = _G.QUI_GetCDMAnchorProxyFrame and _G.QUI_GetCDMAnchorProxyFrame(anchorKey)
            local proxyW, proxyH = proxyFrame and proxyFrame:GetWidth() or 0, proxyFrame and proxyFrame:GetHeight() or 0
            local shortName = viewerName == VIEWER_ESSENTIAL and "Ess" or "Util"
            local diagMsg = format("|cff34D399CDM|r EditMode %s chain: viewer=%.0fx%.0f(logical=%.0fx%.0f iconBounds=%.0fx%.0f icons=%d) → state(iconW=%.0f row1W=%.0f) → proxy=%.0fx%.0f",
                shortName,
                w, h, logicalW, logicalH, iconW or 0, iconH or 0, iconCount or 0,
                svs.cdmIconWidth or 0, svs.cdmRow1Width or 0,
                proxyW, proxyH)
            if QUICore and QUICore.db then
                local pCfg = QUICore.db.profile and QUICore.db.profile.powerBar
                if pCfg then
                    local pBar = QUICore.powerBar
                    local pBarW = pBar and pBar:GetWidth() or 0
                    local lockedTo = pCfg.lockedToEssential and "ess" or (pCfg.lockedToUtility and "util" or "no")
                    diagMsg = diagMsg .. format(" → |cffFF9900primary pbar|r(cfgW=%.0f frameW=%.0f locked=%s)", pCfg.width or 0, pBarW, lockedTo)
                end
                local sCfg = QUICore.db.profile and QUICore.db.profile.secondaryPowerBar
                if sCfg then
                    local sBar = QUICore.secondaryPowerBar
                    local sBarW = sBar and sBar:GetWidth() or 0
                    local sLockedTo = sCfg.lockedToEssential and "ess" or (sCfg.lockedToUtility and "util" or "no")
                    diagMsg = diagMsg .. format(" → |cffFF6600secondary pbar|r(cfgW=%.0f frameW=%.0f locked=%s)", sCfg.width or 0, sBarW, sLockedTo)
                end
            end
            -- Show Utility position when Essential resizes (anchored chain)
            if viewerName == VIEWER_ESSENTIAL then
                local utilViewer = _G[VIEWER_UTILITY]
                if utilViewer and utilViewer.GetCenter then
                    local ux, uy = utilViewer:GetCenter()
                    diagMsg = diagMsg .. format(" → util-center=%.0f,%.0f", ux or 0, uy or 0)
                end
            end
            if QUI and QUI.DebugPrint then QUI:DebugPrint(diagMsg) end
            return
        end

        -- Detect Edit Mode → normal transition.  RegisterEditModeExit fires
        -- AFTER Blizzard's OnSizeChanged events, so we must detect the
        -- transition here (first OnSizeChanged with editMode=false after
        -- it was true) and set the capture flag before LayoutViewer runs.
        if not isEditMode and svs._wasInEditMode then
            svs._wasInEditMode = nil
            svs._captureBlizzardIconSize = true
        end

        -- After Edit Mode exit, Blizzard fires OnSizeChanged with the
        -- slider's logical dimensions.  Icon children are STALE (still at
        -- QUI's previous iconSize from LayoutViewer), so we derive iconSize
        -- from the viewer's LOGICAL dimensions instead of reading children.
        --
        -- For single-row horizontal viewers (Essential): height = iconSize.
        -- For multi-row viewers (Utility): height >> width/iconCount, so
        -- fall back to icon child width (correct when slider wasn't touched).
        if svs._captureBlizzardIconSize then
            local w, h = self:GetWidth(), self:GetHeight()
            if not w or not h or w < 2 or h < 2 then
                -- Transient 1x1 reset — wait for Blizzard's real layout.
                return
            end
            svs._captureBlizzardIconSize = nil
            -- Count visible icon children
            local iconCount = 0
            ForEachVisibleIcon(self, function() iconCount = iconCount + 1 end)
            local capturedSize
            local method = "none"
            if iconCount > 0 then
                -- First check if the viewer width matches QUI's expected layout
                -- (i.e., the user did NOT touch Blizzard's Icon Size slider).
                -- QUI's LayoutViewer sets the viewer to:
                --   iconCount * iconSize + (iconCount - 1) * padding
                -- If Blizzard picks up this padded width and feeds it back on
                -- exit, dividing by iconCount would inflate iconSize by
                -- ~padding*(iconCount-1)/iconCount each cycle.  Detect the
                -- "unchanged" case and preserve the current iconSize.
                local curSettings = GetTrackerSettings(trackerKey)
                local curRow1 = curSettings and curSettings.row1
                local curIconSize = curRow1 and curRow1.iconSize
                local curPadding = curRow1 and curRow1.padding or 0
                if curIconSize and curIconSize > 1 then
                    local expectedW = iconCount * curIconSize + math.max(iconCount - 1, 0) * curPadding
                    if math.abs(w - expectedW) <= math.max(iconCount, 2) then
                        capturedSize = curIconSize
                        method = "unchanged"
                    end
                end

                if not capturedSize then
                    local perIconW = w / iconCount
                    if h <= perIconW * 1.5 then
                        -- Single-row: derive iconSize from viewer HEIGHT (which
                        -- equals the icon height) so padding between icons is not
                        -- conflated with icon size.
                        local ar = curRow1 and curRow1.aspectRatioCrop or 1.0
                        capturedSize = math.floor(h * ar + 0.5)
                        method = "height"
                    else
                        -- Multi-row: can't derive iconSize from dimensions alone.
                        -- Icon children reflect QUI's current iconSize which is
                        -- correct when the slider wasn't changed for this viewer.
                        ForEachVisibleIcon(self, function(child)
                            local cw = child:GetWidth()
                            if cw and cw > 1 then
                                capturedSize = math.floor(cw + 0.5)
                                method = "child"
                                return true -- stop early
                            end
                        end)
                    end
                end -- if not capturedSize
            end
            -- Do NOT write capturedSize to settings — QUI's configured icon
            -- size is the sole source of truth.  Blizzard's slider affects the
            -- viewer scale (handled by SetScale hook + effective-scale conversion
            -- in the proxy), not QUI's layout formula.
            if QUI and QUI.DebugPrint and capturedSize and capturedSize > 1 then
                QUI:DebugPrint(format("|cff34D399CDM|r CapturedBlizzardIconSize %s: size=%d method=%s viewer=%.0fx%.0f icons=%d (not written)",
                    viewerName == VIEWER_ESSENTIAL and "Ess" or "Util",
                    capturedSize, method, w, h, iconCount))
            end
            svs._captureJustCompleted = true
            -- Fall through to LayoutViewer which uses QUI's configured iconSize
        end

        -- During combat, Blizzard fires transient 1x1 resets on CDM viewers.
        -- These can't be corrected (SetSizeSafe defers) and trigger wasteful
        -- LayoutViewer calls whose debounced callbacks read incorrect
        -- GetCenter() positions, causing power bar / anchor drift.
        if InCombatLockdown() then
            local cw, ch = self:GetWidth(), self:GetHeight()
            if not cw or not ch or cw < 2 or ch < 2 then
                return
            end
        end

        -- Increment layout counter so OnUpdate polling knows Blizzard changed
        -- something. NOT incremented during Edit Mode — the OnUpdate loop
        -- would call LayoutViewer which fights the user's manual resize.
        svs.ncdmBlizzardLayoutCount = (svs.ncdmBlizzardLayoutCount or 0) + 1
        LayoutViewer(viewerName, trackerKey)

        -- After a capture, LayoutViewer has re-laid-out icons with the new
        -- iconSize and updated viewer state (cdmIconWidth, cdmRow1Width).
        -- Update proxies, power bars, and all anchored frames so their
        -- widths and positions match the new layout.  Call ALL power bar
        -- update variants unconditionally — each checks its own lock flag
        -- and returns early if not applicable, so this is safe for any
        -- anchor chain configuration.
        if svs._captureJustCompleted then
            svs._captureJustCompleted = nil
            -- LayoutViewer has re-laid-out icons and set viewer dimensions
            -- including QUI's inter-icon padding.  Do NOT override the viewer
            -- size or state back to Blizzard's raw dimensions — that would
            -- discard padding, causing power bars to be narrower than the
            -- actual icon layout.  LayoutViewer's values are the source of
            -- truth for where icons actually are on screen.
            if _G.QUI_UpdateCDMAnchorProxyFrames then
                _G.QUI_UpdateCDMAnchorProxyFrames()
            end
            -- Update ALL power bar variants (each checks its own lock flag)
            UpdateAllLockedBars()
            -- Snap Utility position relative to Essential (legacy anchor)
            if _G.QUI_ApplyUtilityAnchor then
                _G.QUI_ApplyUtilityAnchor()
            end
            if _G.QUI_UpdateAnchoredUnitFrames then
                _G.QUI_UpdateAnchoredUnitFrames()
            end
            -- BFS walk from this viewer's anchor key to reposition dependents
            local anchorKey = viewerName == VIEWER_ESSENTIAL and "cdmEssential" or "cdmUtility"
            if _G.QUI_UpdateFramesAnchoredTo then
                _G.QUI_UpdateFramesAnchoredTo(anchorKey)
            end
            -- Post-capture diagnostic: confirm the update chain fired
            if QUI and QUI.DebugPrint then
                local shortName = viewerName == VIEWER_ESSENTIAL and "Ess" or "Util"
                local viewerW = self:GetWidth() or 0
                local proxyFrame = _G.QUI_GetCDMAnchorProxyFrame and _G.QUI_GetCDMAnchorProxyFrame(anchorKey)
                local proxyW = proxyFrame and proxyFrame:GetWidth() or 0
                local diagMsg = format("|cff34D399CDM|r PostCapture %s: viewer=%.0f state(iconW=%.0f row1W=%.0f) proxy=%.0f",
                    shortName, viewerW, svs.cdmIconWidth or 0, svs.cdmRow1Width or 0, proxyW)
                if QUICore and QUICore.db then
                    local pCfg = QUICore.db.profile and QUICore.db.profile.powerBar
                    if pCfg then
                        local pBar = QUICore.powerBar
                        diagMsg = diagMsg .. format(" → pbar(cfgW=%.0f frameW=%.0f)", pCfg.width or 0, pBar and pBar:GetWidth() or 0)
                    end
                    local sCfg = QUICore.db.profile and QUICore.db.profile.secondaryPowerBar
                    if sCfg then
                        local sBar = QUICore.secondaryPowerBar
                        diagMsg = diagMsg .. format(" → sbar(cfgW=%.0f frameW=%.0f)", sCfg.width or 0, sBar and sBar:GetWidth() or 0)
                    end
                end
                QUI:DebugPrint(diagMsg)
            end
        end
    end)

    -- Step 2: Layout hook REMOVED (was causing cascade calls)

    -- Step 1: Dedicated update frame (can be shown/hidden to completely stop polling)
    local updateFrame = CreateFrame("Frame")
    hvs.ncdmUpdateFrame = updateFrame

    local lastIconCount = 0
    local lastSettingsVersion = 0
    local lastBlizzardLayoutCount = 0
    -- Fallback polling intervals (events handle immediate cooldown updates)
    local combatInterval = 1.0   -- 1000ms in combat (can't do work anyway, events blocked)
    local idleInterval = 0.5     -- 500ms out of combat (events handle immediate needs)

    updateFrame:SetScript("OnUpdate", function(self, elapsed)
        local uvs = getViewerState(viewer)
        uvs.ncdmElapsed = (uvs.ncdmElapsed or 0) + elapsed

        -- Adaptive throttle - slower polling since events handle immediate updates
        local updateInterval = UnitAffectingCombat("player") and combatInterval or idleInterval

        -- Step 4: Check event flag to skip throttle (immediate response to cooldown changes)
        if uvs.ncdmEventFired then
            uvs.ncdmEventFired = nil
            uvs.ncdmElapsed = 0
        elseif uvs.ncdmElapsed < updateInterval then
            return
        else
            uvs.ncdmElapsed = 0
        end

        if NCDM.applying[trackerKey] then return end

        -- Skip expensive icon collection during combat for CPU efficiency
        if InCombatLockdown() then return end

        -- Skip layout during Edit Mode — user is manually resizing; LayoutViewer
        -- would fight their resize and snap the viewer back to calculated size.
        if Helpers.IsEditModeActive() then return end

        -- Step 5: Check if Blizzard layout changed or settings changed
        local currentBlizzardCount = uvs.ncdmBlizzardLayoutCount or 0
        local currentVersion = NCDM.settingsVersion[trackerKey] or 0

        -- Grace period: skip early-exit for 2 seconds after zone change to catch late Blizzard scrambles
        local inGracePeriod = uvs.ncdmGraceUntil and GetTime() < uvs.ncdmGraceUntil
        -- Clear expired grace period
        if uvs.ncdmGraceUntil and GetTime() >= uvs.ncdmGraceUntil then
            uvs.ncdmGraceUntil = nil
        end

        -- Collect visible Blizzard icons (lightweight: ~10-20 children)
        -- Excludes custom CDM icons to avoid phantom count changes
        -- Also excludes empty placeholder frames without a spell texture
        local icons = {}
        for i = 1, viewer:GetNumChildren() do
            local child = select(i, viewer:GetChildren())
            if child and child ~= viewer.Selection and not child._isCustomCDMIcon and IsIconFrame(child) and child:IsShown() and HasValidTexture(child) then
                table.insert(icons, child)
            end
        end
        local count = #icons

        -- Early-exit if nothing changed (skip during grace period to catch late Blizzard scrambles)
        if not inGracePeriod then
            if currentBlizzardCount == lastBlizzardLayoutCount and currentVersion == lastSettingsVersion and count == lastIconCount then
                return
            end
        end
        lastBlizzardLayoutCount = currentBlizzardCount

        local needsLayout = false

        -- Check if count or settings version changed
        if count ~= lastIconCount or currentVersion ~= lastSettingsVersion then
            needsLayout = true
            -- Reset skinned/pending flags on all icons when settings change
            if currentVersion ~= lastSettingsVersion then
                for _, icon in ipairs(icons) do
                    local ris = _iconState[icon]
                    if ris then
                        ris.cdmSkinned = nil
                        ris.cdmSkinPending = nil
                    end
                    NCDM.pendingIcons[icon] = nil
                end
            end
        end

        -- Check if first icon's anchor is wrong (Blizzard reset it)
        -- We use CENTER anchor, Blizzard uses different anchors
        if not needsLayout and count > 0 then
            local firstIcon = icons[1]
            if firstIcon then
                local point = firstIcon:GetPoint(1)
                -- If first icon isn't anchored to CENTER, Blizzard broke our layout
                if point and point ~= "CENTER" then
                    needsLayout = true
                end
            end
        end

        if needsLayout then
            lastIconCount = count
            lastSettingsVersion = currentVersion
            LayoutViewer(viewerName, trackerKey)
        end
    end)
    hvs.ncdmUpdateHandler = updateFrame:GetScript("OnUpdate")

    -- Step 1: Initially show update frame only if viewer is visible
    if viewer:IsShown() then
        updateFrame:Show()
    else
        updateFrame:Hide()
    end

    -- Step 4: Event-driven layout trigger - simplified flag approach
    local layoutEventFrame = CreateFrame("Frame")
    layoutEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    layoutEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    layoutEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    layoutEventFrame:SetScript("OnEvent", function()
        -- Skip during combat - layout will catch up when combat ends
        if InCombatLockdown() then return end
        -- Set flag for OnUpdate to check (no timer overhead)
        if viewer:IsShown() then
            hvs.ncdmEventFired = true
        end
    end)

    -- Pending icon ticker is now global and self-canceling (started in QueueIconForSkinning)
    -- Clean up any old per-viewer ticker from previous versions (legacy property on frame)
    if viewer.__pendingTicker then
        viewer.__pendingTicker:Cancel()
        -- NOTE: We intentionally nil-out this legacy property (one-time cleanup).
        -- This write is acceptable because it only clears an addon-created property
        -- that was set by a previous QUI version, not a Blizzard property.
        viewer.__pendingTicker = nil
    end

    -- Step 3: Initial layout - single deferred layout
    C_Timer.After(0.02, function()
        LayoutViewer(viewerName, trackerKey)
    end)
end

---------------------------------------------------------------------------
-- PUBLIC: Increment settings version (called by options panel)
-- This triggers the OnUpdate to re-layout without expensive string.format
---------------------------------------------------------------------------
local function IncrementSettingsVersion(trackerKey)
    if trackerKey then
        NCDM.settingsVersion[trackerKey] = (NCDM.settingsVersion[trackerKey] or 0) + 1
    else
        -- Increment both if no specific tracker
        NCDM.settingsVersion["essential"] = (NCDM.settingsVersion["essential"] or 0) + 1
        NCDM.settingsVersion["utility"] = (NCDM.settingsVersion["utility"] or 0) + 1
    end
end

---------------------------------------------------------------------------
-- PUBLIC: Force refresh all layouts
---------------------------------------------------------------------------
local function RefreshAll()
    UpdateCooldownViewerCVar()
    NCDM.applying["essential"] = false
    NCDM.applying["utility"] = false

    -- Rebuild custom CDM icons before layout
    if ns.CustomCDM then
        ns.CustomCDM:RebuildIcons(VIEWER_ESSENTIAL, "essential")
        ns.CustomCDM:RebuildIcons(VIEWER_UTILITY, "utility")
    end

    -- Increment settings versions to trigger re-layout
    IncrementSettingsVersion()

    -- Double layout pattern for stability
    C_Timer.After(0.01, function()
        LayoutViewer(VIEWER_ESSENTIAL, "essential")
    end)
    C_Timer.After(0.02, function()
        LayoutViewer(VIEWER_UTILITY, "utility")
    end)
    -- Second pass
    C_Timer.After(0.03, function()
        LayoutViewer(VIEWER_ESSENTIAL, "essential")
    end)
    C_Timer.After(0.04, function()
        LayoutViewer(VIEWER_UTILITY, "utility")
        -- Apply anchor after final Utility layout
        if _G.QUI_ApplyUtilityAnchor then
            _G.QUI_ApplyUtilityAnchor()
        end
    end)

    -- Update locked power bars and castbars after all layouts complete
    C_Timer.After(0.10, function()
        UpdateAllLockedBars()
        -- Unit frames anchored to CDM
        if _G.QUI_UpdateCDMAnchoredUnitFrames then
            _G.QUI_UpdateCDMAnchoredUnitFrames()
        end
        -- Re-hook icons for mouseover visibility (covers newly rebuilt custom icons).
        if _G.QUI_RefreshCDMMouseover then
            _G.QUI_RefreshCDMMouseover()
        end
    end)
end

---------------------------------------------------------------------------
-- UTILITY ANCHOR: Position Utility viewer below Essential when enabled
---------------------------------------------------------------------------
local function ApplyUtilityAnchor()
    local db = GetDB()
    if not db or not db.utility then return end

    local utilSettings = db.utility
    local utilViewer = _G[VIEWER_UTILITY]
    if not utilViewer then return end

    local uvs = getViewerState(utilViewer)

    -- Respect centralized frame anchoring overrides.
    -- When cdmUtility is overridden in frame anchoring, this legacy anchor flow
    -- must not mutate points or it will fight the new anchoring system.
    if _G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(utilViewer) then
        uvs.cdmAnchoredToEssential = nil
        uvs.cdmAnchorPendingAfterCombat = nil
        DriftLog("ApplyUtilityAnchor: skipped (frame anchoring override)")
        return
    end

    if not utilSettings.anchorBelowEssential then
        uvs.cdmAnchoredToEssential = nil
        -- Stabilize unanchored Utility at current CENTER so combat-time
        -- Blizzard size changes do not visually shift its position.
        if InCombatLockdown() then
            uvs.cdmAnchorPendingAfterCombat = true
            DriftLog("ApplyUtilityAnchor: disabled (deferred center stabilize)")
        else
            uvs.cdmAnchorPendingAfterCombat = nil
            local ux, uy = utilViewer:GetCenter()
            local sx, sy = UIParent:GetCenter()
            if ux and uy and sx and sy then
                local ox = ux - sx
                local oy = uy - sy
                pcall(function()
                    utilViewer:ClearAllPoints()
                    utilViewer:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                end)
            end
            DriftLog("ApplyUtilityAnchor: disabled (center stabilized)")
        end
        return
    end

    -- Freeze Utility position during combat (proxy stays fixed), then re-anchor after.
    if InCombatLockdown() then
        uvs.cdmAnchorPendingAfterCombat = true
        DriftLog("ApplyUtilityAnchor: deferred (combat)")
        return
    end

    local essViewer = _G[VIEWER_ESSENTIAL]
    if not essViewer then return end

    local utilityTopBorder = utilSettings.row1 and utilSettings.row1.borderSize or 0
    local totalOffset = (utilSettings.anchorGap or 0) - utilityTopBorder

    -- Save current anchor points so we can restore on failure
    local numPoints = utilViewer:GetNumPoints()
    local savedPoints = {}
    for i = 1, numPoints do
        savedPoints[i] = { utilViewer:GetPoint(i) }
    end

    local anchorParent = UpdateUtilityAnchorProxy() or essViewer

    utilViewer:ClearAllPoints()
    local ok = pcall(utilViewer.SetPoint, utilViewer, "TOP", anchorParent, "BOTTOM", 0, -totalOffset)
    if ok then
        uvs.cdmAnchoredToEssential = true
        uvs.cdmAnchorPendingAfterCombat = nil
        local parentName = anchorParent and anchorParent.GetName and anchorParent:GetName() or tostring(anchorParent)
        DriftLog("ApplyUtilityAnchor: anchored to " .. tostring(parentName))
    else
        -- SetPoint failed (circular anchor dependency) - restore previous position
        -- Saved points may also reference essViewer, so protect the restore too
        local restored = false
        if #savedPoints > 0 then
            restored = pcall(function()
                for _, pt in ipairs(savedPoints) do
                    utilViewer:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end)
        end
        if not restored then
            utilViewer:ClearAllPoints()
            utilViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        uvs.cdmAnchoredToEssential = nil
        uvs.cdmAnchorPendingAfterCombat = nil
        -- Disable the setting so this doesn't repeat on every reload
        utilSettings.anchorBelowEssential = false
        print("|cff34D399QUI:|r Anchor Utility below Essential failed (circular dependency). Setting has been disabled. Reposition via Edit Mode.")
    end
end

_G.QUI_RefreshNCDM = RefreshAll
_G.QUI_IncrementNCDMVersion = IncrementSettingsVersion
_G.QUI_ApplyUtilityAnchor = ApplyUtilityAnchor
_G.QUI_IsSelectionKeepVisible = function(sel) return _keepVisibleSelections[sel] or false end

-- Expose viewer layout state for resource bars, castbars, anchoring, etc.
-- Reads from _viewerState weak-keyed table (previously __cdm* properties on frames).
-- Reuses a per-viewer snapshot table to avoid allocating a new table per call.
local _stateSnapshots = setmetatable({}, { __mode = "k" })
_G.QUI_GetCDMViewerState = function(viewer)
    if not viewer then return nil end
    local vs = _viewerState[viewer]
    if not vs or not vs.cdmIconWidth then return nil end
    local snap = _stateSnapshots[viewer]
    if not snap then
        snap = {}
        _stateSnapshots[viewer] = snap
    end
    snap.iconWidth              = vs.cdmIconWidth
    snap.totalHeight            = vs.cdmTotalHeight
    snap.row1Width              = vs.cdmRow1Width
    snap.bottomRowWidth         = vs.cdmBottomRowWidth
    snap.potentialRow1Width     = vs.cdmPotentialRow1Width
    snap.potentialBottomRowWidth = vs.cdmPotentialBottomRowWidth
    snap.row1IconHeight         = vs.cdmRow1IconHeight
    snap.row1BorderSize         = vs.cdmRow1BorderSize
    snap.bottomRowBorderSize    = vs.cdmBottomRowBorderSize
    snap.bottomRowYOffset       = vs.cdmBottomRowYOffset
    snap.layoutDir              = vs.cdmLayoutDirection
    return snap
end

-- Update viewer state dimensions from externally-measured icon bounds.
-- Called by the Edit Mode ticker in anchoring.lua when Blizzard's slider
-- changes icon size without firing SetScale/OnSizeChanged on the viewer.
_G.QUI_SetCDMViewerBounds = function(viewer, boundsW, boundsH)
    if not viewer then return end
    local vs = getViewerState(viewer)
    -- Update internal viewer state (used by proxy system, anchor calculations,
    -- and QUI_GetCDMViewerState which resource bars should use).
    -- Do NOT write __cdm* properties on the viewer frame — that taints
    -- Blizzard protected frames in the Midnight (12.0) taint model.
    vs.cdmIconWidth = boundsW
    vs.cdmRow1Width = boundsW
    vs.cdmBottomRowWidth = boundsW
    vs.cdmPotentialRow1Width = boundsW
    vs.cdmPotentialBottomRowWidth = boundsW
    vs.cdmTotalHeight = boundsH
end

-- Refresh proxies and dependent frames after Edit Mode exit.
-- LayoutViewer's formula is the authoritative source for viewer state
-- dimensions — this function just ensures proxies and dependent frames
-- are re-synced without overriding viewer state from icon bounds.
_G.QUI_RefreshCDMViewerFromBounds = function(viewer, trackerKey)
    if not viewer then return end
    -- Update proxies
    if _G.QUI_UpdateCDMAnchorProxyFrames then
        _G.QUI_UpdateCDMAnchorProxyFrames()
    end
    -- Update power bars
    UpdateLockedBarsForViewer(trackerKey)
    -- Update anchored frames
    if _G.QUI_UpdateAnchoredUnitFrames then
        _G.QUI_UpdateAnchoredUnitFrames()
    end
    local proxyKey = trackerKey == "essential" and "cdmEssential" or "cdmUtility"
    if _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo(proxyKey)
    end
end

-- Expose icon state accessor for other modules (cdm_custom, cdm_manager, options).
_G.QUI_GetIconState = function(icon)
    if not icon then return nil end
    return _iconState[icon]
end

-- Clear icon state (used by cdm_custom when rebuilding icons).
_G.QUI_ClearIconState = function(icon)
    if not icon then return end
    _iconState[icon] = nil
end

---------------------------------------------------------------------------
-- FORCE LOAD CDM: Open settings panel invisibly to force Blizzard init
-- Shows at alpha 0 so OnShow scripts fire but user sees nothing
---------------------------------------------------------------------------
local function ForceLoadCDM()
    if InCombatLockdown() then return end
    local settingsFrame = _G["CooldownViewerSettings"]
    if settingsFrame then
        settingsFrame:SetAlpha(0)
        settingsFrame:Show()

        -- One frame tick is enough for Blizzard to create child frames
        -- let's be safe at .2 seconds though
        C_Timer.After(0.2, function()
            if settingsFrame then
                settingsFrame:Hide()
                settingsFrame:SetAlpha(1)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
local function Initialize()
    if NCDM.initialized then return end
    NCDM.initialized = true

    if _G[VIEWER_ESSENTIAL] then
        HookViewer(VIEWER_ESSENTIAL, "essential")
    end

    if _G[VIEWER_UTILITY] then
        HookViewer(VIEWER_UTILITY, "utility")
    end

    -- Build custom CDM icons and start their update ticker
    if ns.CustomCDM then
        ns.CustomCDM:RebuildIcons(VIEWER_ESSENTIAL, "essential")
        ns.CustomCDM:RebuildIcons(VIEWER_UTILITY, "utility")
        ns.CustomCDM:StartUpdateTicker()
    end

    -- Hook BuffIcon/BuffBar for Edit Mode resize (refresh anchor proxies so dependent frames follow).
    local buffViewerNames = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    for _, bvName in ipairs(buffViewerNames) do
        local bv = _G[bvName]
        if bv and not NCDM.hooked[bvName] then
            NCDM.hooked[bvName] = true
            -- On Edit Mode enter: show Selection (invisible) so we can read its size.
            -- _keepVisibleSelections flag prevents nudge.lua from re-hiding it.
            if QUICore and QUICore.RegisterEditModeEnter then
                QUICore:RegisterEditModeEnter(function()
                    local sel = bv.Selection
                    if sel then
                        _keepVisibleSelections[sel] = true
                        sel:Show()
                        sel:SetAlpha(0)
                    end
                end)
            end
            bv:HookScript("OnSizeChanged", function(self)
                if Helpers.IsEditModeActive() then
                    local w = Helpers.SafeValue(self:GetWidth(), 0)
                    local h = Helpers.SafeValue(self:GetHeight(), 0)
                    if w < 2 or h < 2 then return end

                    local sel = self.Selection
                    local selW = Helpers.SafeValue(sel and sel:GetWidth(), 0)
                    local selH = Helpers.SafeValue(sel and sel:GetHeight(), 0)
                    local proxyKey = bvName == "BuffIconCooldownViewer" and "buffIcon" or "buffBar"
                    local bvs = getViewerState(self)

                    -- Defer icon measurement by one frame — Blizzard resizes the
                    -- viewer first, then scales icons on the next frame.
                    -- Proxy and overlay both use scale-corrected icon dimensions.
                    local viewerRef = self
                    C_Timer.After(0, function()
                        if not viewerRef or not Helpers.IsEditModeActive() then return end
                        local overlay = _G.QUI_GetCDMViewerOverlay and _G.QUI_GetCDMViewerOverlay(bvName)

                        -- Measure actual visual bounds of icon children (includes padding).
                        -- GetLeft/GetRight/GetTop/GetBottom account for child scale,
                        -- so the bounding box reflects the true visual extent.
                        local iconCount = 0
                        local boundsL, boundsR, boundsT, boundsB
                        local iconScale = 1
                        for i = 1, viewerRef:GetNumChildren() do
                            local child = select(i, viewerRef:GetChildren())
                            if child and child ~= viewerRef.Selection and IsIconFrame(child)
                                and child:IsShown() then
                                iconCount = iconCount + 1
                                local cl = child:GetLeft()
                                local cr = child:GetRight()
                                local ct = child:GetTop()
                                local cb = child:GetBottom()
                                if cl and cr and ct and cb then
                                    boundsL = boundsL and math.min(boundsL, cl) or cl
                                    boundsR = boundsR and math.max(boundsR, cr) or cr
                                    boundsT = boundsT and math.max(boundsT, ct) or ct
                                    boundsB = boundsB and math.min(boundsB, cb) or cb
                                end
                                if iconCount == 1 then
                                    iconScale = Helpers.SafeValue(child:GetScale(), 1)
                                end
                            end
                        end

                        local totalIconW = (boundsL and boundsR) and (boundsR - boundsL) or 0
                        local maxIconH = (boundsT and boundsB) and (boundsT - boundsB) or 0

                        -- Update overlay with visual icon bounds (includes padding)
                        if overlay and totalIconW > 1 and maxIconH > 1 then
                            overlay:ClearAllPoints()
                            overlay:SetPoint("CENTER", viewerRef, "CENTER", 0, 0)
                            overlay:SetSize(totalIconW, maxIconH)
                        end

                        -- Update viewer state and proxies with visual bounds
                        local iconW = totalIconW > 1 and totalIconW or Helpers.SafeValue(viewerRef:GetWidth(), 0)
                        local iconH = maxIconH > 1 and maxIconH or Helpers.SafeValue(viewerRef:GetHeight(), 0)
                        bvs.cdmIconWidth = iconW
                        bvs.cdmRow1Width = iconW
                        bvs.cdmBottomRowWidth = iconW
                        bvs.cdmPotentialRow1Width = iconW
                        bvs.cdmPotentialBottomRowWidth = iconW
                        bvs.cdmTotalHeight = iconH
                        if _G.QUI_UpdateCDMAnchorProxyFrames then
                            _G.QUI_UpdateCDMAnchorProxyFrames()
                        end
                        -- Update frames anchored TO this viewer (via proxy)
                        if _G.QUI_UpdateFramesAnchoredTo then
                            _G.QUI_UpdateFramesAnchoredTo(proxyKey)
                        end

                        local vScale = Helpers.SafeValue(viewerRef:GetScale(), 1)
                        if QUI and QUI.DebugPrint then QUI:DebugPrint(format("|cff34D399CDM|r EditMode %s: viewer=%.0fx%.0f(s=%.3f) icons=%d bounds=%.0fx%.0f(s=%.3f) overlay=%s",
                            bvName, Helpers.SafeValue(viewerRef:GetWidth(), 0),
                            Helpers.SafeValue(viewerRef:GetHeight(), 0), vScale,
                            iconCount, totalIconW, maxIconH, iconScale,
                            overlay and format("%.0fx%.0f", overlay:GetWidth(), overlay:GetHeight()) or "nil")) end
                    end)
                end
            end)
        end
    end

    -- On Edit Mode exit: full cleanup — sync Selection overlays, relayout icons,
    -- refresh anchor proxies, and re-anchor all dependent frames.
    -- DebouncedReapplyOverrides is suppressed during Edit Mode, so we must do
    -- the full re-anchor here to pick up any changes the user made.
    if QUICore and QUICore.RegisterEditModeExit then
        QUICore:RegisterEditModeExit(function()
            if InCombatLockdown() then return end
            local allViewers = {
                { name = VIEWER_ESSENTIAL },
                { name = VIEWER_UTILITY },
                { name = "BuffIconCooldownViewer" },
                { name = "BuffBarCooldownViewer" },
            }
            for _, entry in ipairs(allViewers) do
                local viewer = _G[entry.name]
                if viewer then
                    SyncViewerSelectionSafe(viewer)
                end
            end
            -- NOTE: LayoutViewer is NOT called here.  The capture mechanism in
            -- OnSizeChanged detects the Edit Mode → normal transition (via
            -- _wasInEditMode flag) and captures Blizzard's icon size before
            -- falling through to LayoutViewer with the updated settings.
            -- By the time this exit callback fires, OnSizeChanged has already
            -- handled the transition.
            -- Refresh proxies and re-anchor all dependent frames
            if _G.QUI_UpdateCDMAnchorProxyFrames then
                _G.QUI_UpdateCDMAnchorProxyFrames()
            end
            -- Snap Utility back to correct position relative to Essential
            -- (legacy anchorBelowEssential — not handled by ApplyAllFrameAnchors)
            if _G.QUI_ApplyUtilityAnchor then
                _G.QUI_ApplyUtilityAnchor()
            end
            if _G.QUI_ApplyAllFrameAnchors then
                _G.QUI_ApplyAllFrameAnchors()
            end
            -- Blizzard applies the new icon size from the Edit Mode slider
            -- AFTER our exit handler.  Schedule delayed re-measurements so
            -- proxies, power bars, and anchored frames match the new icons.
            for _, delay in ipairs({0.15, 0.5, 1.0}) do
                C_Timer.After(delay, function()
                    if InCombatLockdown() then return end
                    -- Fallback: clean up transition state and ensure LayoutViewer
                    -- has run at least once after Edit Mode exit.
                    for _, vn in ipairs({VIEWER_ESSENTIAL, VIEWER_UTILITY}) do
                        local v = _G[vn]
                        if v then
                            local vvs = getViewerState(v)
                            vvs._wasInEditMode = nil  -- clean up stale flags
                            if vvs._captureBlizzardIconSize then
                                vvs._captureBlizzardIconSize = nil
                                local tk = vn == VIEWER_ESSENTIAL and "essential" or "utility"
                                LayoutViewer(vn, tk)
                                if QUI and QUI.DebugPrint then
                                    QUI:DebugPrint(format("|cff34D399CDM|r Capture fallback: LayoutViewer for %s (delay=%.2f)", tk, delay))
                                end
                            end
                        end
                    end
                    if _G.QUI_RefreshCDMViewerFromBounds then
                        _G.QUI_RefreshCDMViewerFromBounds(_G[VIEWER_ESSENTIAL], "essential")
                        _G.QUI_RefreshCDMViewerFromBounds(_G[VIEWER_UTILITY], "utility")
                    end
                    -- Padding is NOT measured or written here — QUI's
                    -- configured padding setting is the sole source of truth.
                    -- LayoutViewer applies it when it runs after this timer.
                end)
            end
            -- Restore BuffIcon/BuffBar overlays to SetAllPoints and clear
            -- cached Selection state from the Edit Mode session.
            for _, bvName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
                local bv = _G[bvName]
                if bv then
                    local bvs = getViewerState(bv)
                    bvs._lastSelW = nil
                    bvs._lastSelH = nil
                    -- Clear keep-visible flag
                    local sel = bv.Selection
                    if sel then
                        _keepVisibleSelections[sel] = nil
                    end

                    -- Read Blizzard's Edit Mode padding from icon positions and
                    -- save to QUI settings so LayoutBuffIcons/LayoutBuffBars uses
                    -- the padding the user set in Edit Mode.
                    local icons = {}
                    for i = 1, bv:GetNumChildren() do
                        local child = select(i, bv:GetChildren())
                        if child and child ~= bv.Selection
                            and (child.icon or child.Icon) and child:IsShown() then
                            icons[#icons + 1] = child
                        end
                    end
                    if #icons >= 2 then
                        -- Sort left-to-right by screen position
                        table.sort(icons, function(a, b)
                            return (a:GetLeft() or 0) < (b:GetLeft() or 0)
                        end)
                        local r1 = icons[1]:GetRight()
                        local l2 = icons[2]:GetLeft()
                        if r1 and l2 then
                            local gap = l2 - r1
                            local ncdmDB = QUI.db and QUI.db.profile and QUI.db.profile.ncdm
                            if ncdmDB then
                                if bvName == "BuffBarCooldownViewer" and ncdmDB.trackedBar then
                                    ncdmDB.trackedBar.spacing = math.floor(gap + 0.5)
                                    QUI:DebugPrint(format("|cff34D399CDM|r EditMode exit: saved BuffBar spacing = %d", ncdmDB.trackedBar.spacing))
                                end
                            end
                        end
                    end
                end
                local ov = _G.QUI_GetCDMViewerOverlay and _G.QUI_GetCDMViewerOverlay(bvName)
                if ov and bv then
                    ov:ClearAllPoints()
                    ov:SetAllPoints(bv)
                end
            end
            -- Re-layout BuffIcon/BuffBar with saved settings (including new padding)
            local buffBar = ns and ns.BuffBar
            if buffBar then
                if buffBar.LayoutIcons then buffBar.LayoutIcons() end
                if buffBar.LayoutBars then buffBar.LayoutBars() end
            end
        end)
    end

    -- Single delayed refresh (consolidated from 3 calls at 1s/2s/4s to reduce CPU spike)
    C_Timer.After(2.5, RefreshAll)
end

_G.QUI_CDMDriftDebugEnable = function()
    return _G.QUI_FrameDriftDebugEnable(VIEWER_UTILITY, { label = "UtilityCooldownViewer" })
end

_G.QUI_CDMDriftDebugDisable = function()
    return _G.QUI_FrameDriftDebugDisable(VIEWER_UTILITY)
end

_G.QUI_CDMDriftDebugDump = function()
    return _G.QUI_FrameDriftDebugDump(VIEWER_UTILITY)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Force load CDM first, then initialize our hooks
        C_Timer.After(0.3, ForceLoadCDM)
        C_Timer.After(0.5, Initialize)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        -- Skip on initial login/reload (Initialize already schedules RefreshAll at 2.5s)
        -- But DO refresh on zone changes (M+ dungeons, instance portals, etc.)
        if not isLogin and not isReload then
            -- Zone change: enable 2-second grace period for anchor checking
            for _, viewerName in ipairs({VIEWER_ESSENTIAL, VIEWER_UTILITY}) do
                local viewer = _G[viewerName]
                if viewer then
                    getViewerState(viewer).ncdmGraceUntil = GetTime() + 2.0
                    -- Clear icon state flags for fresh layout in new zone
                    for i = 1, viewer:GetNumChildren() do
                        local child = select(i, viewer:GetChildren())
                        if child and child ~= viewer.Selection then
                            local cis = _iconState[child]
                            if cis then
                                cis.cdmSkinned = nil
                                cis.cdmSkinPending = nil
                            end
                        end
                    end
                end
            end
            C_Timer.After(0.3, RefreshAll)
        end
    elseif event == "CHALLENGE_MODE_START" then
        -- M+ keystone: enable grace period to catch scenario-related scrambles
        for _, viewerName in ipairs({VIEWER_ESSENTIAL, VIEWER_UTILITY}) do
            local viewer = _G[viewerName]
            if viewer then
                getViewerState(viewer).ncdmGraceUntil = GetTime() + 2.0
            end
        end
        C_Timer.After(0.5, RefreshAll)
    end
end)

C_Timer.After(0, function()
    if _G[VIEWER_ESSENTIAL] or _G[VIEWER_UTILITY] then
        Initialize()
    end
end)

---------------------------------------------------------------------------
-- VISIBILITY CONTROLLERS (CDM and Unitframes - Independent)
---------------------------------------------------------------------------

-- Helper: Check if player is in a group (party or raid)
local function IsPlayerInGroup()
    return IsInGroup() or IsInRaid()
end

-- Housing instance types - excluded from "Show in Instance" detection
local HOUSING_INSTANCE_TYPES = {
    ["neighborhood"] = true,  -- Founder's Point, Razorwind Shores
    ["interior"] = true,      -- Inside player houses
}

-- Helper: Check if player is in an instance (dungeon, raid, arena, pvp, scenario)
-- Excludes housing zones which are technically instances but shouldn't trigger "Show In Instance"
local function IsPlayerInInstance()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "none" or instanceType == nil then
        return false
    end
    -- Exclude housing from instance detection
    if HOUSING_INSTANCE_TYPES[instanceType] then
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- CDM VISIBILITY CONTROLLER
---------------------------------------------------------------------------
local CDMVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    hoverCount = 0,
    leaveTimer = nil,
}

-- Get CDM frames (viewers + power bars)
local function GetCDMFrames()
    local frames = {}

    -- Blizzard CDM frames
    if _G.EssentialCooldownViewer then
        table.insert(frames, _G.EssentialCooldownViewer)
    end
    if _G.UtilityCooldownViewer then
        table.insert(frames, _G.UtilityCooldownViewer)
    end
    if _G.BuffIconCooldownViewer then
        table.insert(frames, _G.BuffIconCooldownViewer)
    end
    if _G.BuffBarCooldownViewer then
        table.insert(frames, _G.BuffBarCooldownViewer)
    end

    return frames
end

-- Get cdmVisibility settings from profile
local function GetCDMVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility then
        return QUICore.db.profile.cdmVisibility
    end
    return nil
end

-- Determine if CDM should be visible (SHOW logic)
local function ShouldCDMBeVisible()
    local vis = GetCDMVisibilitySettings()
    if not vis then return true end

    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        -- Hide rules override show conditions.
        if vis.hideWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    -- Show Always overrides all other conditions
    if vis.showAlways then return true end

    -- OR logic: visible if ANY enabled condition is met
    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and CDMVisibility.mouseOver then return true end

    return false  -- No condition met = hidden
end

-- OnUpdate handler for CDM fade animation
local function OnCDMFadeUpdate(self, elapsed)
    local vis = GetCDMVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2

    local now = GetTime()
    local elapsedTime = now - CDMVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    -- Linear interpolation
    local alpha = CDMVisibility.fadeStartAlpha +
        (CDMVisibility.fadeTargetAlpha - CDMVisibility.fadeStartAlpha) * progress

    -- Apply to CDM frames
    local frames = GetCDMFrames()
    for _, frame in ipairs(frames) do
        frame:SetAlpha(alpha)
    end

    -- Check if fade complete
    if progress >= 1 then
        CDMVisibility.isFading = false
        CDMVisibility.currentlyHidden = (CDMVisibility.fadeTargetAlpha < 1)
        self:SetScript("OnUpdate", nil)
    end
end

-- Start CDM fade animation
local function StartCDMFade(targetAlpha)
    local frames = GetCDMFrames()
    if #frames == 0 then return end

    -- Get current alpha from first frame
    local currentAlpha = frames[1]:GetAlpha()

    -- Skip if already at target
    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        CDMVisibility.currentlyHidden = (targetAlpha < 1)
        return
    end

    CDMVisibility.isFading = true
    CDMVisibility.fadeStart = GetTime()
    CDMVisibility.fadeStartAlpha = currentAlpha
    CDMVisibility.fadeTargetAlpha = targetAlpha

    -- Create fade frame if needed
    if not CDMVisibility.fadeFrame then
        CDMVisibility.fadeFrame = CreateFrame("Frame")
    end
    CDMVisibility.fadeFrame:SetScript("OnUpdate", OnCDMFadeUpdate)
end

-- Update CDM visibility
local function UpdateCDMVisibility()
    -- During Edit Mode, force CDM frames fully visible so overlays (which are
    -- children and inherit parent alpha) remain visible for repositioning.
    if Helpers.IsEditModeActive() then
        StartCDMFade(1)
        return
    end

    local shouldShow = ShouldCDMBeVisible()
    local vis = GetCDMVisibilitySettings()

    if shouldShow then
        StartCDMFade(1)  -- Fade in
    else
        StartCDMFade(vis and vis.fadeOutAlpha or 0)  -- Fade to configured alpha
    end

    -- Resource bars own their positioning/visibility logic in resourcebars.lua.
    -- Refresh them explicitly so CDM visibility changes apply immediately
    -- without alpha conflicts that can expose fallback center positions.
    if QUICore then
        if QUICore.UpdatePowerBar then
            QUICore:UpdatePowerBar()
        end
        if QUICore.UpdateSecondaryPowerBar then
            QUICore:UpdateSecondaryPowerBar()
        end
    end
end

-- Helper: Hook a single frame for mouseover detection
HookFrameForMouseover = function(frame)
    if not frame or _mouseoverHooked[frame] then return end

    _mouseoverHooked[frame] = true

    frame:HookScript("OnEnter", function()
        local vis = GetCDMVisibilitySettings()
        if not vis or vis.showAlways or not vis.showOnMouseover then return end

        -- Cancel any pending leave timer
        if CDMVisibility.leaveTimer then
            CDMVisibility.leaveTimer:Cancel()
            CDMVisibility.leaveTimer = nil
        end

        CDMVisibility.hoverCount = CDMVisibility.hoverCount + 1
        if CDMVisibility.hoverCount == 1 then
            CDMVisibility.mouseOver = true
            UpdateCDMVisibility()
        end
    end)

    frame:HookScript("OnLeave", function()
        local vis = GetCDMVisibilitySettings()
        if not vis or vis.showAlways or not vis.showOnMouseover then return end

        CDMVisibility.hoverCount = math.max(0, CDMVisibility.hoverCount - 1)

        if CDMVisibility.hoverCount == 0 then
            -- Cancel any existing timer
            if CDMVisibility.leaveTimer then
                CDMVisibility.leaveTimer:Cancel()
            end

            -- Delay fade to allow OnEnter on next icon to fire first
            CDMVisibility.leaveTimer = C_Timer.After(0.5, function()
                CDMVisibility.leaveTimer = nil
                -- Re-check hoverCount - may have been incremented by OnEnter
                if CDMVisibility.hoverCount == 0 then
                    CDMVisibility.mouseOver = false
                    UpdateCDMVisibility()
                end
            end)
        end
    end)
end

-- Setup CDM mouseover detector
local function SetupCDMMouseoverDetector()
    local vis = GetCDMVisibilitySettings()

    -- Remove existing detector
    if CDMVisibility.mouseoverDetector then
        CDMVisibility.mouseoverDetector:SetScript("OnUpdate", nil)
        CDMVisibility.mouseoverDetector:Hide()
        CDMVisibility.mouseoverDetector = nil
    end

    -- Cancel any pending leave timer
    if CDMVisibility.leaveTimer then
        CDMVisibility.leaveTimer:Cancel()
        CDMVisibility.leaveTimer = nil
    end

    CDMVisibility.mouseOver = false
    CDMVisibility.hoverCount = 0  -- Reset counter

    -- Only create if mouseover is enabled and showAlways is disabled
    if not vis or vis.showAlways or not vis.showOnMouseover then
        return
    end

    -- Hook container frames
    local cdmFrames = GetCDMFrames()
    for _, frame in ipairs(cdmFrames) do
        HookFrameForMouseover(frame)
    end

    -- Hook existing icons from each viewer
    local viewerToTracker = {
        EssentialCooldownViewer = "essential",
        UtilityCooldownViewer = "utility",
    }
    local viewers = {"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer"}
    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer then
            local icons = CollectIcons(viewer, viewerToTracker[viewerName])
            for _, icon in ipairs(icons) do
                HookFrameForMouseover(icon)
            end
        end
    end

    -- Create minimal detector frame (just for cleanup tracking, no OnUpdate)
    local detector = CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
    CDMVisibility.mouseoverDetector = detector
end

---------------------------------------------------------------------------
-- UNITFRAMES VISIBILITY CONTROLLER
---------------------------------------------------------------------------
local UnitframesVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    leaveTimer = nil,
}

-- Get unitframesVisibility settings from profile
local function GetUnitframesVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.unitframesVisibility then
        return QUICore.db.profile.unitframesVisibility
    end
    return nil
end

-- Get unit frames and castbars for visibility control
local function GetUnitframeFrames()
    local frames = {}

    -- Collect unit frames
    if _G.QUI_UnitFrames then
        for unitKey, frame in pairs(_G.QUI_UnitFrames) do
            if frame then
                table.insert(frames, frame)
            end
        end
    end

    -- Collect castbars unless "Always Show Castbars" is enabled
    local vis = GetUnitframesVisibilitySettings()
    if not (vis and vis.alwaysShowCastbars) then
        if _G.QUI_Castbars then
            for unitKey, castbar in pairs(_G.QUI_Castbars) do
                if castbar then
                    table.insert(frames, castbar)
                end
            end
        end
    end

    return frames
end

local function ApplyUnitframeVisibilityAlpha(frame, alpha)
    if not frame then return end

    -- Respect castbar runtime visibility state so HUD visibility logic doesn't
    -- resurrect inactive castbars (especially player castbar alpha-fallback mode).
    -- Only castbars using alpha-fallback mode should be forced hidden this way.
    if frame._quiCastbar and frame._quiUseAlphaVisibility and frame._quiDesiredVisible == false then
        frame:SetAlpha(0)
        return
    end

    frame:SetAlpha(alpha)
end

-- Determine if Unitframes should be visible (SHOW logic)
local function ShouldUnitframesBeVisible()
    local vis = GetUnitframesVisibilitySettings()
    if not vis then return true end

    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        -- Hide rules override show conditions.
        if vis.hideWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    -- Show Always overrides all other conditions
    if vis.showAlways then return true end

    -- OR logic: visible if ANY enabled condition is met
    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and UnitframesVisibility.mouseOver then return true end

    return false  -- No condition met = hidden
end

-- OnUpdate handler for Unitframes fade animation
local function OnUnitframesFadeUpdate(self, elapsed)
    local vis = GetUnitframesVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2

    local now = GetTime()
    local elapsedTime = now - UnitframesVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    -- Linear interpolation
    local alpha = UnitframesVisibility.fadeStartAlpha +
        (UnitframesVisibility.fadeTargetAlpha - UnitframesVisibility.fadeStartAlpha) * progress

    -- Apply to unit frames
    local frames = GetUnitframeFrames()
    for _, frame in ipairs(frames) do
        ApplyUnitframeVisibilityAlpha(frame, alpha)
    end

    -- Check if fade complete
    if progress >= 1 then
        UnitframesVisibility.isFading = false
        UnitframesVisibility.currentlyHidden = (UnitframesVisibility.fadeTargetAlpha < 1)
        self:SetScript("OnUpdate", nil)
    end
end

-- Start Unitframes fade animation
local function StartUnitframesFade(targetAlpha)
    local frames = GetUnitframeFrames()
    if #frames == 0 then return end

    -- Get current alpha from first frame
    local currentAlpha = frames[1]:GetAlpha()

    -- Skip if already at target
    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        UnitframesVisibility.currentlyHidden = (targetAlpha < 1)
        return
    end

    UnitframesVisibility.isFading = true
    UnitframesVisibility.fadeStart = GetTime()
    UnitframesVisibility.fadeStartAlpha = currentAlpha
    UnitframesVisibility.fadeTargetAlpha = targetAlpha

    -- Create fade frame if needed
    if not UnitframesVisibility.fadeFrame then
        UnitframesVisibility.fadeFrame = CreateFrame("Frame")
    end
    UnitframesVisibility.fadeFrame:SetScript("OnUpdate", OnUnitframesFadeUpdate)
end

-- Update Unitframes visibility
local function UpdateUnitframesVisibility()
    -- During Edit Mode, force unit frames fully visible so overlays (which are
    -- children and inherit parent alpha) remain visible for repositioning.
    if _G.QUI_IsUnitFrameEditModeActive and _G.QUI_IsUnitFrameEditModeActive() then
        StartUnitframesFade(1)
        return
    end

    local vis = GetUnitframesVisibilitySettings()
    local shouldShow = ShouldUnitframesBeVisible()

    -- Sync castbar alpha based on "Always Show Castbars" setting
    if _G.QUI_Castbars then
        local targetAlpha = 1  -- Default to visible

        if vis and vis.alwaysShowCastbars then
            targetAlpha = 1  -- Always visible when enabled
        else
            -- Match unit frame alpha when disabled
            if _G.QUI_UnitFrames then
                for _, frame in pairs(_G.QUI_UnitFrames) do
                    if frame then
                        targetAlpha = frame:GetAlpha()
                        break
                    end
                end
            end
        end

        for unitKey, castbar in pairs(_G.QUI_Castbars) do
            if castbar then
                ApplyUnitframeVisibilityAlpha(castbar, targetAlpha)
            end
        end
    end

    if shouldShow then
        StartUnitframesFade(1)  -- Fade in
    else
        StartUnitframesFade(vis and vis.fadeOutAlpha or 0)  -- Fade to configured alpha
    end
end

-- Setup Unitframes mouseover detector
local function SetupUnitframesMouseoverDetector()
    local vis = GetUnitframesVisibilitySettings()

    -- Remove existing detector
    if UnitframesVisibility.mouseoverDetector then
        UnitframesVisibility.mouseoverDetector:SetScript("OnUpdate", nil)
        UnitframesVisibility.mouseoverDetector:Hide()
        UnitframesVisibility.mouseoverDetector = nil
    end

    if UnitframesVisibility.leaveTimer then
        UnitframesVisibility.leaveTimer:Cancel()
        UnitframesVisibility.leaveTimer = nil
    end
    UnitframesVisibility.mouseOver = false

    -- Only create if mouseover is enabled and showAlways is disabled
    if not vis or vis.showAlways or not vis.showOnMouseover then
        return
    end

    -- Performance: Use OnEnter/OnLeave hooks instead of 50ms polling
    -- This is event-driven and more efficient
    local ufFrames = GetUnitframeFrames()
    local hoverCount = 0

    for _, frame in ipairs(ufFrames) do
        if frame and not _mouseoverHooked[frame] then
            _mouseoverHooked[frame] = true

            -- Hook OnEnter
            frame:HookScript("OnEnter", function()
                if UnitframesVisibility.leaveTimer then
                    UnitframesVisibility.leaveTimer:Cancel()
                    UnitframesVisibility.leaveTimer = nil
                end
                hoverCount = hoverCount + 1
                if hoverCount == 1 then
                    UnitframesVisibility.mouseOver = true
                    UpdateUnitframesVisibility()
                end
            end)

            -- Hook OnLeave
            frame:HookScript("OnLeave", function()
                hoverCount = math.max(0, hoverCount - 1)
                if hoverCount == 0 then
                    if UnitframesVisibility.leaveTimer then
                        UnitframesVisibility.leaveTimer:Cancel()
                    end
                    UnitframesVisibility.leaveTimer = C_Timer.After(0.5, function()
                        UnitframesVisibility.leaveTimer = nil
                        if hoverCount == 0 then
                            UnitframesVisibility.mouseOver = false
                            UpdateUnitframesVisibility()
                        end
                    end)
                end
            end)
        end
    end

    -- Create minimal detector frame (just for cleanup tracking, no OnUpdate)
    local detector = CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
    UnitframesVisibility.mouseoverDetector = detector
end

---------------------------------------------------------------------------
-- SHARED EVENT HANDLING
---------------------------------------------------------------------------
local visibilityEventFrame = CreateFrame("Frame")
visibilityEventFrame:RegisterEvent("PLAYER_LOGIN")
visibilityEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visibilityEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visibilityEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visibilityEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visibilityEventFrame:RegisterEvent("GROUP_JOINED")
visibilityEventFrame:RegisterEvent("GROUP_LEFT")
visibilityEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visibilityEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
visibilityEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visibilityEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
visibilityEventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
visibilityEventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")

visibilityEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_FLAGS_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end
    end

    if event == "PLAYER_LOGIN" then
        -- Delay initial check to ensure frames exist
        C_Timer.After(1.5, function()
            SetupCDMMouseoverDetector()
            SetupUnitframesMouseoverDetector()
            UpdateCDMVisibility()
            UpdateUnitframesVisibility()
        end)
    else
        -- All other events: update both controllers
        UpdateCDMVisibility()
        UpdateUnitframesVisibility()
    end
end)

-- Global refresh functions for options panel
_G.QUI_RefreshCDMVisibility = UpdateCDMVisibility
_G.QUI_RefreshUnitframesVisibility = UpdateUnitframesVisibility
_G.QUI_RefreshCDMMouseover = SetupCDMMouseoverDetector
_G.QUI_RefreshUnitframesMouseover = SetupUnitframesMouseoverDetector
_G.QUI_ShouldCDMBeVisible = ShouldCDMBeVisible

---------------------------------------------------------------------------
-- EXPOSE MODULE
---------------------------------------------------------------------------
NCDM.Refresh = RefreshAll
NCDM.LayoutViewer = LayoutViewer
ns.NCDM = NCDM
