--[[
    QUI Group Frames - Aura Indicators
    Simple icon-row aura tracking on group frames.
    Tracked spells are configured via the Designer UI (trackedSpells table).
    Display uses the same container pattern as buffs/debuffs: icon size,
    anchor, grow direction, spacing, max count.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local LSM = LibStub("LibSharedMedia-3.0")
local QUICore = ns.Addon
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFI = {}
ns.QUI_GroupFrameIndicators = QUI_GFI

---------------------------------------------------------------------------
-- ICON POOL
---------------------------------------------------------------------------
local iconPool = {}
local POOL_SIZE = 40

local function GetFontPath()
    local db = GetDB()
    local vdb = db and (db.party or db)
    local general = vdb and vdb.general
    local fontName = general and general.font or "Quazii"
    return LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
end

local function CreateIconIndicator(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(16, 16)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = tex

    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    frame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- Cooldown swipe
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    frame.cooldown = cd

    -- Stack text
    local stackText = frame:CreateFontString(nil, "OVERLAY")
    stackText:SetFont(GetFontPath(), 9, "OUTLINE")
    stackText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 0)
    stackText:SetJustifyH("RIGHT")
    frame.stackText = stackText

    frame:Hide()
    return frame
end

local function AcquireIcon(parent)
    local item = table.remove(iconPool)
    if item then
        item:SetParent(parent)
        item:ClearAllPoints()
        return item
    end
    return CreateIconIndicator(parent)
end

local function ReleaseIcon(item)
    item:Hide()
    item:ClearAllPoints()
    if item.cooldown then item.cooldown:Clear() end
    if item.stackText then item.stackText:SetText("") end
    if #iconPool < POOL_SIZE then
        table.insert(iconPool, item)
    end
end

---------------------------------------------------------------------------
-- GET TRACKED SPELL IDS from DB
---------------------------------------------------------------------------
local function GetTrackedSpellIDs(isRaid)
    local db = GetDB()
    if not db then return nil end
    local vdb = (isRaid and db.raid or db.party) or db
    if not vdb.auraIndicators or not vdb.auraIndicators.enabled then
        return nil
    end

    local tracked = vdb.auraIndicators.trackedSpells
    if not tracked then return nil end

    -- Build list of enabled spell IDs
    local spells = {}
    for spellID, enabled in pairs(tracked) do
        if enabled then
            spells[#spells + 1] = tonumber(spellID) or spellID
        end
    end

    return #spells > 0 and spells or nil
end

---------------------------------------------------------------------------
-- INDICATOR STATE per frame
---------------------------------------------------------------------------
local frameIndicatorState = setmetatable({}, { __mode = "k" })

local function GetIndicatorState(frame)
    local state = frameIndicatorState[frame]
    if not state then
        state = { icons = {}, container = nil }
        frameIndicatorState[frame] = state
    end
    return state
end

---------------------------------------------------------------------------
-- ENSURE CONTAINER: Create/update the icon container on a group frame
---------------------------------------------------------------------------
local function EnsureContainer(frame)
    local state = GetIndicatorState(frame)
    if state.container then return state.container end

    local container = CreateFrame("Frame", nil, frame)
    container:SetSize(1, 1)
    container:SetFrameLevel(frame:GetFrameLevel() + 8)
    state.container = container
    return container
end

local function PositionContainer(frame)
    local db = GetDB()
    if not db then return end
    local isRaid = frame._isRaid
    local vdb = (isRaid and db.raid or db.party) or db
    local ai = vdb.auraIndicators
    if not ai then return end

    local state = GetIndicatorState(frame)
    local container = state.container
    if not container then return end

    local anchor = ai.anchor or "TOPLEFT"
    local offX = ai.anchorOffsetX or 0
    local offY = ai.anchorOffsetY or 0

    container:ClearAllPoints()
    if anchor:find("BOTTOM") then offY = offY + (frame._bottomPad or 0) end
    container:SetPoint(anchor, frame, anchor, offX, offY)
end

---------------------------------------------------------------------------
-- CLEAR all indicators from a frame
---------------------------------------------------------------------------
local function ClearIndicators(frame)
    local state = frameIndicatorState[frame]
    if not state then return end

    for _, icon in ipairs(state.icons) do
        ReleaseIcon(icon)
    end
    wipe(state.icons)
end

---------------------------------------------------------------------------
-- UPDATE: Process indicators for a single frame
---------------------------------------------------------------------------
local function UpdateFrameIndicators(frame)
    if not frame or not frame.unit then return end

    local isRaid = frame._isRaid
    local trackedSpells = GetTrackedSpellIDs(isRaid)
    if not trackedSpells then
        ClearIndicators(frame)
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        ClearIndicators(frame)
        return
    end

    local db = GetDB()
    if not db then
        ClearIndicators(frame)
        return
    end
    local vdb = (isRaid and db.raid or db.party) or db
    local ai = vdb.auraIndicators
    if not ai then
        ClearIndicators(frame)
        return
    end

    local iconSize = ai.iconSize or 14
    local growDir = ai.growDirection or "RIGHT"
    local spacing = ai.spacing or 2
    local maxIcons = ai.maxIndicators or 5
    local anchor = ai.anchor or "TOPLEFT"

    -- Build a set of active auras on the unit from shared cache
    local activeAuras = {} -- [spellID] = auraData
    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    if cache then
        if cache.helpful then
            for _, auraData in ipairs(cache.helpful) do
                local spellID = SafeValue(auraData.spellId, nil)
                if spellID then activeAuras[spellID] = auraData end
            end
        end
        if cache.harmful then
            for _, auraData in ipairs(cache.harmful) do
                local spellID = SafeValue(auraData.spellId, nil)
                if spellID then activeAuras[spellID] = auraData end
            end
        end
    else
        -- Fallback: direct scan if cache not populated
        if C_UnitAuras and C_UnitAuras.GetUnitAuras then
            for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
                local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, filter, 40)
                if ok and auras then
                    for _, auraData in ipairs(auras) do
                        local spellID = SafeValue(auraData.spellId, nil)
                        if spellID then activeAuras[spellID] = auraData end
                    end
                end
            end
        end
    end

    -- Clear previous icons
    local state = GetIndicatorState(frame)
    for _, icon in ipairs(state.icons) do
        ReleaseIcon(icon)
    end
    wipe(state.icons)

    -- Render matching auras as icons in a row
    local container = EnsureContainer(frame)
    PositionContainer(frame)

    -- Expose active indicator auraInstanceIDs for buff deduplication
    if not frame._indicatorAuraIDs then frame._indicatorAuraIDs = {} end
    wipe(frame._indicatorAuraIDs)

    local count = 0
    for _, spellID in ipairs(trackedSpells) do
        if count >= maxIcons then break end

        local auraData = activeAuras[spellID]
        if auraData then
            -- Skip if already shown as a defensive indicator
            local defIDs = frame._defensiveAuraIDs
            if not (defIDs and auraData.auraInstanceID and defIDs[auraData.auraInstanceID]) then
                -- Track for buff dedup
                if auraData.auraInstanceID then
                    frame._indicatorAuraIDs[auraData.auraInstanceID] = true
                end
                count = count + 1
                local icon = AcquireIcon(container)
                icon:SetSize(iconSize, iconSize)

                -- Position in row
                icon:ClearAllPoints()
                local vertPart = anchor:find("TOP") and "TOP" or (anchor:find("BOTTOM") and "BOTTOM" or "")
                local firstHoriz = growDir == "LEFT" and "RIGHT" or "LEFT"
                local firstAnchor = vertPart .. firstHoriz

                if count == 1 then
                    icon:SetPoint(firstAnchor, container, firstAnchor, 0, 0)
                else
                    local prev = state.icons[count - 1]
                    if prev then
                        if growDir == "LEFT" then
                            icon:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
                        else
                            icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                        end
                    end
                end

                -- Icon texture (C-side handles secret values)
                if icon.icon and auraData.icon then
                    icon.icon:SetTexture(auraData.icon)
                end

                -- Cooldown swipe
                if icon.cooldown and auraData then
                    local dur = auraData.duration
                    local expTime = auraData.expirationTime
                    if dur and expTime then
                        if unit and auraData.auraInstanceID
                           and C_UnitAuras and C_UnitAuras.GetAuraDuration
                           and icon.cooldown.SetCooldownFromDurationObject then
                            local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                            if ok and durationObj then
                                pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, durationObj)
                            elseif icon.cooldown.SetCooldownFromExpirationTime then
                                pcall(icon.cooldown.SetCooldownFromExpirationTime, icon.cooldown, expTime, dur)
                            else
                                pcall(function() icon.cooldown:SetCooldown(expTime - dur, dur) end)
                            end
                        elseif icon.cooldown.SetCooldownFromExpirationTime then
                            pcall(icon.cooldown.SetCooldownFromExpirationTime, icon.cooldown, expTime, dur)
                        else
                            pcall(function() icon.cooldown:SetCooldown(expTime - dur, dur) end)
                        end
                    end
                end

                -- Stacks
                if icon.stackText and auraData then
                    local stacks = SafeToNumber(auraData.applications, 0)
                    icon.stackText:SetText(stacks > 1 and stacks or "")
                end

                icon:Show()
                state.icons[count] = icon
            end
        end
    end

    -- CENTER: reposition all icons centered around the container's anchor
    if growDir == "CENTER" and count > 0 then
        local totalSpan = count * iconSize + math.max(count - 1, 0) * spacing
        local startX = -totalSpan / 2
        local vertPart = anchor:find("TOP") and "TOP" or (anchor:find("BOTTOM") and "BOTTOM" or "")
        local iconPoint = vertPart == "" and "LEFT" or (vertPart .. "LEFT")
        for idx = 1, count do
            local ic = state.icons[idx]
            if ic then
                ic:ClearAllPoints()
                ic:SetPoint(iconPoint, container, anchor, startX + (idx - 1) * (iconSize + spacing), 0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- EVENT HOOKUP
-- UNIT_AURA is driven by the shared aura scan in groupframes_auras.lua
-- (FlushPendingAuras calls GFI:RefreshFrame) to ensure indicators update
-- before buffs, enabling buff deduplication.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        QUI_GFI:RefreshAll()
    end
end)

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function QUI_GFI:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    for _, frame in pairs(GF.unitFrameMap) do
        if frame and frame:IsShown() then
            UpdateFrameIndicators(frame)
        end
    end
end

function QUI_GFI:RefreshFrame(frame)
    UpdateFrameIndicators(frame)
end
