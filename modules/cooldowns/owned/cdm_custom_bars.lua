--[[
    QUI Custom CDM Bars

    User-created cooldown bars that track explicitly configured spells.
    Each bar is an independent container frame with its own icon pool,
    layout, and positioning. Uses the custom entry code path (direct API
    polling) — no Blizzard CDM viewer backing.

    Loaded before cdm_containers.lua so ns.CDMCustomBars is available
    when ownedEngine:Initialize() runs.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local MAX_CUSTOM_BARS = 8
local POOL_KEY_PREFIX = "customBar_"
local FRAME_NAME_PREFIX = "QUI_CustomBar_"

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local customContainers = {}   -- barID -> frame
local customViewerState = {}  -- frame -> { width, height }
local initialized = false

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local function GetDB()
    return QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
end

local function GetBarDefs()
    local db = GetDB()
    return db and db.customBars and db.customBars.bars or {}
end

local function GetBarDefByID(barID)
    for _, barDef in ipairs(GetBarDefs()) do
        if barDef.id == barID then return barDef end
    end
    return nil
end

local function GetBarEntries(barID)
    local charDB = QUICore and QUICore.db and QUICore.db.char
    if charDB and charDB.ncdm and charDB.ncdm.customBars
        and charDB.ncdm.customBars[barID] and charDB.ncdm.customBars[barID].entries then
        return charDB.ncdm.customBars[barID].entries
    end
    return {}
end

local function EnsureCharEntries(barID)
    local charDB = QUICore and QUICore.db and QUICore.db.char
    if not charDB then return end
    if not charDB.ncdm then charDB.ncdm = {} end
    if not charDB.ncdm.customBars then charDB.ncdm.customBars = {} end
    if not charDB.ncdm.customBars[barID] then
        charDB.ncdm.customBars[barID] = { entries = {} }
    end
    if not charDB.ncdm.customBars[barID].entries then
        charDB.ncdm.customBars[barID].entries = {}
    end
end

---------------------------------------------------------------------------
-- CONTAINER CREATION
---------------------------------------------------------------------------
local function CreateCustomContainer(barDef)
    local name = FRAME_NAME_PREFIX .. barDef.id
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(1, 1)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetAlpha(0)  -- hud_visibility manages fade-in
    frame:Show()
    customViewerState[frame] = {}
    return frame
end

---------------------------------------------------------------------------
-- POSITION SAVE / RESTORE
---------------------------------------------------------------------------
local function SaveBarPosition(barID)
    local container = customContainers[barID]
    if not container then return end
    local barDef = GetBarDefByID(barID)
    if not barDef then return end

    local cx, cy = container:GetCenter()
    local sx, sy = UIParent:GetCenter()
    if cx and cy and sx and sy then
        barDef.pos = { ox = cx - sx, oy = cy - sy }
    end
end

local function RestoreBarPosition(barID)
    local container = customContainers[barID]
    if not container then return end
    local barDef = GetBarDefByID(barID)
    if not barDef or not barDef.pos then return end

    local ox = barDef.pos.ox
    local oy = barDef.pos.oy
    if ox and oy then
        container:ClearAllPoints()
        container:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
    end
end

---------------------------------------------------------------------------
-- ICON BUILDING
---------------------------------------------------------------------------
local function BuildBarIcons(barID)
    local container = customContainers[barID]
    if not container then return {} end
    local barDef = GetBarDefByID(barID)
    if not barDef or not barDef.enabled then return {} end

    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return {} end

    -- Release old pool
    local poolKey = POOL_KEY_PREFIX .. barID
    CDMIcons:UnregisterExternalPool(poolKey)

    local entries = GetBarEntries(barID)
    local pool = {}
    local iconCount = barDef.iconCount or 0  -- 0 = no limit

    for idx, entry in ipairs(entries) do
        if entry.enabled ~= false then
            if iconCount > 0 and #pool >= iconCount then break end

            local spellEntry = {
                spellID = entry.id,
                overrideSpellID = entry.id,
                name = "",
                isAura = false,
                layoutIndex = 99000 + idx,
                viewerType = poolKey,
                type = entry.type,
                id = entry.id,
                _isCustomEntry = true,
            }

            -- Resolve name and IDs per entry type
            if entry.type == "macro" then
                spellEntry.macroName = entry.macroName
                spellEntry.name = entry.macroName or ""
            elseif entry.type == "trinket" then
                local itemID = GetInventoryItemID("player", entry.id)
                if itemID then
                    local itemName = C_Item.GetItemNameByID(itemID)
                    spellEntry.name = itemName or ""
                end
            elseif entry.type == "item" then
                local itemName = C_Item.GetItemNameByID(entry.id)
                spellEntry.name = itemName or ""
            else
                local spellInfo = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.id)
                spellEntry.name = spellInfo and spellInfo.name or ""
            end

            local icon = CDMIcons:AcquireIcon(container, spellEntry)
            pool[#pool + 1] = icon
        end
    end

    -- Register with CDMIcons so the 0.5s ticker updates cooldowns
    CDMIcons:RegisterExternalPool(poolKey, pool)

    -- Immediate cooldown update
    CDMIcons:UpdateCooldownsForType(poolKey)

    return pool
end

---------------------------------------------------------------------------
-- LAYOUT
---------------------------------------------------------------------------
local function LayoutBar(barID)
    local container = customContainers[barID]
    if not container then return end
    local barDef = GetBarDefByID(barID)
    if not barDef then return end

    if not barDef.enabled then
        container:Hide()
        return
    end

    -- Skip during combat (rebuild on PLAYER_REGEN_ENABLED via RefreshAll)
    if InCombatLockdown() then return end

    container:Show()

    -- Build icons
    local pool = BuildBarIcons(barID)
    if #pool == 0 then
        container:SetSize(1, 1)
        customViewerState[container] = { width = 1, height = 1 }
        return
    end

    -- Read config
    local iconSize = barDef.iconSize or 39
    local borderSize = barDef.borderSize or 1
    local aspectRatio = barDef.aspectRatioCrop or 1.0
    local zoom = barDef.zoom or 0
    local padding = barDef.padding or 2
    local direction = barDef.growthDirection or "RIGHT"
    local opacity = barDef.opacity or 1.0

    local iconWidth = iconSize
    local iconHeight = iconSize / aspectRatio

    -- Build a rowConfig for ConfigureIcon
    local rowConfig = {
        size = iconSize,
        borderSize = borderSize,
        borderColorTable = barDef.borderColorTable or {0, 0, 0, 1},
        aspectRatioCrop = aspectRatio,
        zoom = zoom,
        padding = padding,
        durationSize = barDef.durationSize or 14,
        durationOffsetX = barDef.durationOffsetX or 0,
        durationOffsetY = barDef.durationOffsetY or 0,
        durationTextColor = barDef.durationTextColor or {1, 1, 1, 1},
        durationAnchor = barDef.durationAnchor or "CENTER",
        stackSize = barDef.stackSize or 12,
        stackOffsetX = barDef.stackOffsetX or 0,
        stackOffsetY = barDef.stackOffsetY or 0,
        stackTextColor = barDef.stackTextColor or {1, 1, 1, 1},
        stackAnchor = barDef.stackAnchor or "BOTTOMRIGHT",
        opacity = opacity,
    }

    -- Position icons
    local count = #pool
    local totalW, totalH

    if direction == "CENTERED_HORIZONTAL" then
        totalW = (count * iconWidth) + ((count - 1) * padding)
        totalH = iconHeight
        local startX = -totalW / 2 + iconWidth / 2
        for i, icon in ipairs(pool) do
            ns.CDMIcons.ConfigureIcon(icon, rowConfig)
            icon:ClearAllPoints()
            local x = startX + ((i - 1) * (iconWidth + padding))
            icon:SetPoint("CENTER", container, "CENTER", x, 0)
            icon:Show()
            ns.CDMIcons.UpdateIconCooldown(icon)
        end
    elseif direction == "LEFT" then
        totalW = (count * iconWidth) + ((count - 1) * padding)
        totalH = iconHeight
        local startX = totalW / 2 - iconWidth / 2
        for i, icon in ipairs(pool) do
            ns.CDMIcons.ConfigureIcon(icon, rowConfig)
            icon:ClearAllPoints()
            local x = startX - ((i - 1) * (iconWidth + padding))
            icon:SetPoint("CENTER", container, "CENTER", x, 0)
            icon:Show()
            ns.CDMIcons.UpdateIconCooldown(icon)
        end
    elseif direction == "UP" then
        totalW = iconWidth
        totalH = (count * iconHeight) + ((count - 1) * padding)
        local startY = -totalH / 2 + iconHeight / 2
        for i, icon in ipairs(pool) do
            ns.CDMIcons.ConfigureIcon(icon, rowConfig)
            icon:ClearAllPoints()
            local y = startY + ((i - 1) * (iconHeight + padding))
            icon:SetPoint("CENTER", container, "CENTER", 0, y)
            icon:Show()
            ns.CDMIcons.UpdateIconCooldown(icon)
        end
    elseif direction == "DOWN" then
        totalW = iconWidth
        totalH = (count * iconHeight) + ((count - 1) * padding)
        local startY = totalH / 2 - iconHeight / 2
        for i, icon in ipairs(pool) do
            ns.CDMIcons.ConfigureIcon(icon, rowConfig)
            icon:ClearAllPoints()
            local y = startY - ((i - 1) * (iconHeight + padding))
            icon:SetPoint("CENTER", container, "CENTER", 0, y)
            icon:Show()
            ns.CDMIcons.UpdateIconCooldown(icon)
        end
    else -- RIGHT (default)
        totalW = (count * iconWidth) + ((count - 1) * padding)
        totalH = iconHeight
        local startX = -totalW / 2 + iconWidth / 2
        for i, icon in ipairs(pool) do
            ns.CDMIcons.ConfigureIcon(icon, rowConfig)
            icon:ClearAllPoints()
            local x = startX + ((i - 1) * (iconWidth + padding))
            icon:SetPoint("CENTER", container, "CENTER", x, 0)
            icon:Show()
            ns.CDMIcons.UpdateIconCooldown(icon)
        end
    end

    -- Account for border in container size
    local bs = borderSize
    container:SetSize(math.max(totalW + bs * 2, 1), math.max(totalH + bs * 2, 1))
    customViewerState[container] = { width = totalW + bs * 2, height = totalH + bs * 2 }

    -- Update keybind text on icons
    local poolKey = POOL_KEY_PREFIX .. barID
    if _G.QUI_UpdateViewerKeybinds then
        _G.QUI_UpdateViewerKeybinds(poolKey)
    end
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
local CDMCustomBars = {}

function CDMCustomBars:Initialize()
    if initialized then return end
    initialized = true

    local bars = GetBarDefs()
    for _, barDef in ipairs(bars) do
        if barDef.id and barDef.enabled then
            EnsureCharEntries(barDef.id)
            customContainers[barDef.id] = CreateCustomContainer(barDef)
            RestoreBarPosition(barDef.id)
        end
    end
end

function CDMCustomBars:RefreshAll()
    local bars = GetBarDefs()
    -- Create containers for newly enabled bars, destroy disabled ones
    for _, barDef in ipairs(bars) do
        if barDef.id then
            if barDef.enabled then
                EnsureCharEntries(barDef.id)
                if not customContainers[barDef.id] then
                    customContainers[barDef.id] = CreateCustomContainer(barDef)
                    RestoreBarPosition(barDef.id)
                end
                LayoutBar(barDef.id)
            else
                if customContainers[barDef.id] then
                    customContainers[barDef.id]:Hide()
                end
            end
        end
    end
end

function CDMCustomBars:RefreshBar(barID)
    if not barID then return end
    EnsureCharEntries(barID)
    if not customContainers[barID] then
        local barDef = GetBarDefByID(barID)
        if barDef and barDef.enabled then
            customContainers[barID] = CreateCustomContainer(barDef)
            RestoreBarPosition(barID)
        end
    end
    LayoutBar(barID)
end

function CDMCustomBars:GetContainerFrames()
    local frames = {}
    for _, frame in pairs(customContainers) do
        if frame then frames[#frames + 1] = frame end
    end
    return frames
end

function CDMCustomBars:GetContainerByKey(key)
    -- key format: "customBar_custom_1" or just "custom_1"
    local barID = key
    if barID:sub(1, #POOL_KEY_PREFIX) == POOL_KEY_PREFIX then
        barID = barID:sub(#POOL_KEY_PREFIX + 1)
    end
    return customContainers[barID]
end

function CDMCustomBars:GetViewerEntries()
    local entries = {}
    for _, barDef in ipairs(GetBarDefs()) do
        if barDef.id and barDef.enabled and customContainers[barDef.id] then
            entries[#entries + 1] = {
                key = POOL_KEY_PREFIX .. barDef.id,
                name = FRAME_NAME_PREFIX .. barDef.id,
                anchorKey = "cdmCustom_" .. barDef.id,
                displayLabel = barDef.name or barDef.id,
            }
        end
    end
    return entries
end

function CDMCustomBars:SaveBarPosition(barID)
    SaveBarPosition(barID)
end

function CDMCustomBars:SaveAllPositions()
    for barID, _ in pairs(customContainers) do
        SaveBarPosition(barID)
    end
end

function CDMCustomBars:DestroyBar(barID)
    if not barID then return end
    -- Release icons
    local CDMIcons = ns.CDMIcons
    if CDMIcons then
        CDMIcons:UnregisterExternalPool(POOL_KEY_PREFIX .. barID)
    end
    -- Destroy container
    local container = customContainers[barID]
    if container then
        container:Hide()
        container:SetParent(nil)
        customViewerState[container] = nil
    end
    customContainers[barID] = nil
end

function CDMCustomBars:CreateBarDef(name)
    local db = GetDB()
    if not db or not db.customBars then return nil end
    local bars = db.customBars.bars

    if #bars >= MAX_CUSTOM_BARS then return nil end

    -- Generate unique ID
    local nextNum = #bars + 1
    local id = "custom_" .. nextNum
    -- Ensure uniqueness
    while GetBarDefByID(id) do
        nextNum = nextNum + 1
        id = "custom_" .. nextNum
    end

    local barDef = {
        id = id,
        name = name or ("Custom Bar " .. nextNum),
        enabled = true,
        iconCount = 0,
        iconSize = 39,
        borderSize = 1,
        borderColorTable = {0, 0, 0, 1},
        aspectRatioCrop = 1.0,
        zoom = 0,
        padding = 2,
        growthDirection = "RIGHT",
        opacity = 1.0,
        desaturateOnCooldown = true,
        pos = nil,
        durationSize = 14,
        durationOffsetX = 0,
        durationOffsetY = 0,
        durationTextColor = {1, 1, 1, 1},
        durationAnchor = "CENTER",
        stackSize = 12,
        stackOffsetX = 0,
        stackOffsetY = 0,
        stackTextColor = {1, 1, 1, 1},
        stackAnchor = "BOTTOMRIGHT",
        -- Per-bar effects
        effects = {
            showCooldownSwipe = true,
            showGCDSwipe = false,
            showBuffSwipe = false,
            overlayColorMode = "default",
            overlayColor = {1, 1, 1, 1},
            swipeColorMode = "default",
            swipeColor = {1, 1, 1, 1},
            -- Keybind settings (same keys as db.profile.viewers.*.keybind*)
            keybinds = {
                showKeybinds = false,
                keybindTextSize = 12,
                keybindTextColor = {1, 0.82, 0, 1},
                keybindAnchor = "TOPLEFT",
                keybindOffsetX = 2,
                keybindOffsetY = 2,
            },
            -- Glow sub-table uses PascalCase keys for CreateGlowSection compat
            glow = {
                Enabled = false,
                GlowType = "Pixel Glow",
                Color = {0.95, 0.95, 0.32, 1},
                Lines = 14,
                Frequency = 0.25,
                Thickness = 2,
                Scale = 1,
                XOffset = 0,
                YOffset = 0,
            },
        },
    }

    bars[#bars + 1] = barDef
    EnsureCharEntries(id)

    -- Create container immediately if engine is initialized
    if initialized then
        customContainers[id] = CreateCustomContainer(barDef)
        -- Container starts at alpha=0 for the init path (hud_visibility fades
        -- all frames together). At runtime, StartCDMFade skips if existing
        -- frames are already at target alpha, so set alpha directly.
        customContainers[id]:SetAlpha(1)
        if _G.QUI_RefreshCDMVisibility then _G.QUI_RefreshCDMVisibility() end
    end

    -- Re-register anchoring targets so new bar appears in dropdowns
    if ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAllFrameTargets then
        ns.QUI_Anchoring:RegisterAllFrameTargets()
    end

    -- Rebuild nudge viewer list so new bar is draggable in Edit Mode
    if ns.RebuildCDMViewers then ns.RebuildCDMViewers() end

    return barDef
end

function CDMCustomBars:RemoveBarDef(barID)
    local db = GetDB()
    if not db or not db.customBars then return false end
    local bars = db.customBars.bars

    self:DestroyBar(barID)

    -- Remove from profile
    for i = #bars, 1, -1 do
        if bars[i].id == barID then
            table.remove(bars, i)
            break
        end
    end

    -- Clean up char-scope entries
    local charDB = QUICore and QUICore.db and QUICore.db.char
    if charDB and charDB.ncdm and charDB.ncdm.customBars then
        charDB.ncdm.customBars[barID] = nil
    end

    -- Refresh visibility and anchoring after removal
    if _G.QUI_RefreshCDMVisibility then _G.QUI_RefreshCDMVisibility() end

    if ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAllFrameTargets then
        ns.QUI_Anchoring:RegisterAllFrameTargets()
    end

    if ns.RebuildCDMViewers then ns.RebuildCDMViewers() end

    return true
end

function CDMCustomBars:GetMaxBars()
    return MAX_CUSTOM_BARS
end

function CDMCustomBars:IsInitialized()
    return initialized
end

function CDMCustomBars:GetBarEffects(viewerType)
    local barID = viewerType
    if barID:sub(1, #POOL_KEY_PREFIX) == POOL_KEY_PREFIX then
        barID = barID:sub(#POOL_KEY_PREFIX + 1)
    end
    local barDef = GetBarDefByID(barID)
    if not barDef or not barDef.effects then return nil end

    -- Migrate pre-refactor flat glow keys → nested glow sub-table
    local fx = barDef.effects
    if not fx.glow then fx.glow = {} end
    if fx.glowEnabled ~= nil then
        fx.glow.Enabled    = fx.glowEnabled
        fx.glow.GlowType   = fx.glowType
        fx.glow.Color       = fx.glowColor
        fx.glow.Lines       = fx.glowLines
        fx.glow.Frequency   = fx.glowFrequency
        fx.glow.Thickness   = fx.glowThickness
        fx.glow.Scale       = fx.glowScale
        fx.glow.XOffset     = fx.glowXOffset
        fx.glow.YOffset     = fx.glowYOffset
        fx.glowEnabled = nil;  fx.glowType = nil;  fx.glowColor = nil
        fx.glowLines = nil;    fx.glowFrequency = nil
        fx.glowThickness = nil; fx.glowScale = nil
        fx.glowXOffset = nil;  fx.glowYOffset = nil
    end

    return fx
end

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
ns.CDMCustomBars = CDMCustomBars
