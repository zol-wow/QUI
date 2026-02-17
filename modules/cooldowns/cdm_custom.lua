--[[
    QUI CDM Custom Entries
    Creates custom icon frames for spells, items, and trinket slots that
    integrate into the CDM viewer layout alongside Blizzard's native icons.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("ncdm")

local GetCore = ns.Helpers.GetCore

local VIEWER_ESSENTIAL = "EssentialCooldownViewer"
local VIEWER_UTILITY = "UtilityCooldownViewer"

---------------------------------------------------------------------------
-- MODULE STATE
---------------------------------------------------------------------------
local CustomCDM = {
    iconPools = {},         -- [viewerName] = { icon1, icon2, ... }
    recyclePool = {},       -- Recycled icon frames for reuse
    updateTicker = nil,
    pendingRebuild = {},    -- [viewerName] = trackerKey (queued for after combat)
    iconCounter = 0,        -- Unique name counter for frames
}
ns.CustomCDM = CustomCDM

---------------------------------------------------------------------------
-- HELPER: Get custom entries data from DB
---------------------------------------------------------------------------
local function GetCustomData(trackerKey)
    local QUICore = GetCore()
    if QUICore and QUICore.db and QUICore.db.char and QUICore.db.char.ncdm
        and QUICore.db.char.ncdm[trackerKey] and QUICore.db.char.ncdm[trackerKey].customEntries then
        return QUICore.db.char.ncdm[trackerKey].customEntries
    end
    return nil
end

---------------------------------------------------------------------------
-- HELPER: Get configured initial icon size for a tracker
-- Uses first active row size, then first available row size, then fallback.
---------------------------------------------------------------------------
local DEFAULT_CUSTOM_ICON_SIZE = 30

local function GetTrackerInitialIconSize(trackerKey)
    local db = GetDB()
    if not db or not trackerKey then
        return DEFAULT_CUSTOM_ICON_SIZE
    end

    local tracker = db[trackerKey]
    if type(tracker) ~= "table" then
        return DEFAULT_CUSTOM_ICON_SIZE
    end

    -- Prefer first active row
    for i = 1, 3 do
        local row = tracker["row" .. i]
        local size = row and tonumber(row.iconSize)
        local count = row and tonumber(row.iconCount)
        if size and size > 0 and count and count > 0 then
            return size
        end
    end

    -- Fallback to first row that has a valid size configured
    for i = 1, 3 do
        local row = tracker["row" .. i]
        local size = row and tonumber(row.iconSize)
        if size and size > 0 then
            return size
        end
    end

    return DEFAULT_CUSTOM_ICON_SIZE
end

---------------------------------------------------------------------------
-- HELPER: Resolve icon texture for an entry
---------------------------------------------------------------------------
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local function IsSecretValue(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function GetEntryTexture(entry)
    if not entry then return FALLBACK_ICON end

    if entry.type == "spell" then
        local info = C_Spell.GetSpellInfo(entry.id)
        if info and info.iconID then
            return info.iconID
        end
    elseif entry.type == "item" then
        local icon = C_Item.GetItemIconByID(entry.id)
        if icon then return icon end
    elseif entry.type == "trinket" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            local icon = C_Item.GetItemIconByID(itemID)
            if icon then return icon end
        end
    end

    return FALLBACK_ICON
end

---------------------------------------------------------------------------
-- HELPER: Resolve spell cooldown across base/override identifiers
---------------------------------------------------------------------------
local function GetBestSpellCooldown(spellID)
    if not spellID then return nil, nil end

    local candidates = { spellID }

    if C_Spell.GetOverrideSpell then
        local overrideID = C_Spell.GetOverrideSpell(spellID)
        if overrideID and overrideID ~= spellID then
            table.insert(candidates, overrideID)
        end
    end

    local bestStart, bestDuration = nil, nil
    local secretStart, secretDuration = nil, nil

    local function IsSafeNumeric(value)
        return type(value) == "number" and not IsSecretValue(value)
    end

    local function Consider(startTime, duration)
        if startTime == nil or duration == nil then
            return
        end

        -- Keep one secret fallback pair (combat-restricted values).
        -- CooldownFrame can still consume these, but we must not compare them.
        if IsSecretValue(startTime) or IsSecretValue(duration) then
            if not secretStart and not secretDuration then
                secretStart, secretDuration = startTime, duration
            end
            return
        end

        if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) or duration <= 0 then
            return
        end

        if not bestDuration or duration > bestDuration then
            bestStart, bestDuration = startTime, duration
        end
    end

    for _, identifier in ipairs(candidates) do
        local cdInfo = C_Spell.GetSpellCooldown(identifier)
        if cdInfo then
            Consider(cdInfo.startTime, cdInfo.duration)
        end

        if C_Spell.GetSpellCharges then
            local chargeInfo = C_Spell.GetSpellCharges(identifier)
            if chargeInfo then
                local currentCharges = chargeInfo.currentCharges
                local maxCharges = chargeInfo.maxCharges
                local canCompareCharges = IsSafeNumeric(currentCharges) and IsSafeNumeric(maxCharges)
                if canCompareCharges and currentCharges < maxCharges then
                    Consider(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration)
                end
            end
        end
    end

    if secretStart and secretDuration then
        return secretStart, secretDuration
    end
    return bestStart, bestDuration
end

---------------------------------------------------------------------------
-- HELPER: Get entry display name (for tooltips / options UI)
---------------------------------------------------------------------------
function CustomCDM:GetEntryName(entry)
    if not entry then return "Unknown" end

    if entry.type == "spell" then
        local info = C_Spell.GetSpellInfo(entry.id)
        return info and info.name or ("Spell " .. entry.id)
    elseif entry.type == "item" then
        local itemName = C_Item.GetItemNameByID(entry.id)
        return itemName or ("Item " .. entry.id)
    elseif entry.type == "trinket" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            local itemName = C_Item.GetItemNameByID(itemID)
            if itemName then return itemName end
        end
        return "Trinket Slot " .. entry.id
    end

    return "Unknown"
end

---------------------------------------------------------------------------
-- ICON CREATION: Build a frame matching Blizzard CDM icon structure
---------------------------------------------------------------------------
local function CreateCustomIcon(parent, entry, initialSize)
    CustomCDM.iconCounter = CustomCDM.iconCounter + 1
    local frameName = "QUICustomCDMIcon" .. CustomCDM.iconCounter

    local icon = CreateFrame("Frame", frameName, parent)
    local size = initialSize or DEFAULT_CUSTOM_ICON_SIZE
    icon:SetSize(size, size)

    -- .Icon texture (matches Blizzard structure for IsIconFrame / SkinIcon)
    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetAllPoints(icon)
    icon.Icon:SetTexture(GetEntryTexture(entry))

    -- .Cooldown frame (matches Blizzard structure)
    icon.Cooldown = CreateFrame("Cooldown", frameName .. "Cooldown", icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints(icon)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)

    -- Custom marker flags
    icon._isCustomCDMIcon = true
    icon._customCDMEntry = entry

    -- High layoutIndex so custom icons sort after Blizzard ones
    icon.layoutIndex = 99000 + CustomCDM.iconCounter

    -- Enable mouse for tooltips and mouseover detection
    icon:EnableMouse(true)

    -- Tooltip support (pcall for secret value safety)
    icon:SetScript("OnEnter", function(self)
        local e = self._customCDMEntry
        if not e then return end

        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if e.type == "spell" then
                GameTooltip:SetSpellByID(e.id)
            elseif e.type == "item" then
                GameTooltip:SetItemByID(e.id)
            elseif e.type == "trinket" then
                local itemID = GetInventoryItemID("player", e.id)
                if itemID then
                    GameTooltip:SetItemByID(itemID)
                else
                    GameTooltip:SetText("Empty Trinket Slot")
                end
            end
            GameTooltip:Show()
        end)
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    icon:Show()
    return icon
end

---------------------------------------------------------------------------
-- COOLDOWN UPDATE: Apply cooldown state to a single icon
---------------------------------------------------------------------------
local function UpdateIconCooldown(icon)
    if not icon or not icon._customCDMEntry then return end
    local entry = icon._customCDMEntry
    local cooldown = icon.Cooldown

    local function ApplyCooldown(startTime, duration, enable)
        if startTime == nil or duration == nil then
            cooldown:Clear()
            return
        end

        -- Item cooldown APIs can report a disabled state (enable == 0).
        if type(enable) == "number" and enable == 0 then
            cooldown:Clear()
            return
        end

        if not IsSecretValue(duration) and type(duration) == "number" and duration <= 0 then
            cooldown:Clear()
            return
        end

        local ok = pcall(cooldown.SetCooldown, cooldown, startTime, duration)
        if not ok then
            cooldown:Clear()
        end
    end

    pcall(function()
        if entry.type == "spell" then
            local startTime, duration = GetBestSpellCooldown(entry.id)
            if not startTime or not duration then
                cooldown:Clear()
                return
            end

            -- Avoid comparing secret values; let CooldownFrame process them.
            if not IsSecretValue(duration) and type(duration) == "number" and duration <= 0 then
                cooldown:Clear()
                return
            end

            local ok = pcall(cooldown.SetCooldown, cooldown, startTime, duration)
            if not ok then
                cooldown:Clear()
            end
        elseif entry.type == "item" then
            local startTime, duration, enable = C_Item.GetItemCooldown(entry.id)
            ApplyCooldown(startTime, duration, enable)
        elseif entry.type == "trinket" then
            local itemID = GetInventoryItemID("player", entry.id)
            if itemID then
                local startTime, duration, enable = C_Item.GetItemCooldown(itemID)
                ApplyCooldown(startTime, duration, enable)
            else
                cooldown:Clear()
            end
        end
    end)
end

---------------------------------------------------------------------------
-- ICON TEXTURE REFRESH: Update textures (for trinket swaps / item cache)
---------------------------------------------------------------------------
local function RefreshIconTextures(viewerName)
    local pool = CustomCDM.iconPools[viewerName]
    if not pool then return end

    for _, icon in ipairs(pool) do
        if icon._customCDMEntry then
            local tex = GetEntryTexture(icon._customCDMEntry)
            if icon.Icon then
                icon.Icon:SetTexture(tex)
            end
        end
    end
end

---------------------------------------------------------------------------
-- ICON POOL MANAGEMENT
---------------------------------------------------------------------------

-- Acquire an icon from the recycle pool or create a new one
function CustomCDM:AcquireIcon(parent, entry, initialSize)
    local icon = table.remove(self.recyclePool)
    if icon then
        -- Reuse recycled frame
        local size = initialSize or DEFAULT_CUSTOM_ICON_SIZE
        icon:SetParent(parent)
        icon:SetSize(size, size)
        icon._isCustomCDMIcon = true
        icon._customCDMEntry = entry
        icon._ncdmSetup = nil      -- Reset skin state so SkinIcon re-processes
        icon.__cdmSkinned = nil
        icon.__cdmSkinPending = nil
        icon._ncdmPositioned = nil
        icon.Icon:SetTexture(GetEntryTexture(entry))
        icon.Cooldown:Clear()
        icon:Show()
        return icon
    end
    return CreateCustomIcon(parent, entry, initialSize)
end

function CustomCDM:RebuildIcons(viewerName, trackerKey)
    -- Gate behind combat lockdown — queue for PLAYER_REGEN_ENABLED
    if InCombatLockdown() then
        self.pendingRebuild[viewerName] = trackerKey
        return
    end

    local viewer = _G[viewerName]
    if not viewer then return end

    -- Recycle existing custom icons for this viewer
    local oldPool = self.iconPools[viewerName]
    if oldPool then
        for _, icon in ipairs(oldPool) do
            icon:Hide()
            icon:ClearAllPoints()
            icon:SetParent(UIParent)  -- Park on UIParent (SetParent(nil) leaks)
            icon._customCDMEntry = nil
            table.insert(self.recyclePool, icon)
        end
    end
    self.iconPools[viewerName] = {}

    -- Read custom entries from DB
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.enabled then return end

    local entries = customData.entries
    if not entries or #entries == 0 then return end

    local initialSize = GetTrackerInitialIconSize(trackerKey)

    -- Create (or recycle) icons for each enabled entry
    local pool = {}
    for _, entry in ipairs(entries) do
        if entry.enabled ~= false then
            local icon = self:AcquireIcon(viewer, entry, initialSize)
            table.insert(pool, icon)
            -- Initial cooldown state
            UpdateIconCooldown(icon)
        end
    end

    self.iconPools[viewerName] = pool
end

function CustomCDM:GetIcons(viewerName)
    return self.iconPools[viewerName] or {}
end

---------------------------------------------------------------------------
-- UPDATE LOOP
---------------------------------------------------------------------------
function CustomCDM:UpdateAllCooldowns()
    for _, pool in pairs(self.iconPools) do
        for _, icon in ipairs(pool) do
            UpdateIconCooldown(icon)
        end
    end
end

function CustomCDM:StartUpdateTicker()
    if self.updateTicker then return end

    self.updateTicker = C_Timer.NewTicker(0.5, function()
        self:UpdateAllCooldowns()
    end)
end

function CustomCDM:StopUpdateTicker()
    if self.updateTicker then
        self.updateTicker:Cancel()
        self.updateTicker = nil
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        CustomCDM:UpdateAllCooldowns()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        -- Only care about trinket slots (13 and 14)
        if slot == 13 or slot == 14 then
            RefreshIconTextures(VIEWER_ESSENTIAL)
            RefreshIconTextures(VIEWER_UTILITY)
            CustomCDM:UpdateAllCooldowns()
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Retry icon textures for items that weren't cached
        RefreshIconTextures(VIEWER_ESSENTIAL)
        RefreshIconTextures(VIEWER_UTILITY)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Process any queued rebuilds from combat lockdown
        for viewerName, trackerKey in pairs(CustomCDM.pendingRebuild) do
            CustomCDM:RebuildIcons(viewerName, trackerKey)
        end
        wipe(CustomCDM.pendingRebuild)
    end
end)

---------------------------------------------------------------------------
-- ENTRY MANAGEMENT API (for options UI)
---------------------------------------------------------------------------
function CustomCDM:AddEntry(trackerKey, entryType, entryID)
    if not entryID or type(entryID) ~= "number" then return false end
    if entryType ~= "spell" and entryType ~= "item" and entryType ~= "trinket" then return false end

    local customData = GetCustomData(trackerKey)
    if not customData then return false end

    if not customData.entries then
        customData.entries = {}
    end

    -- Duplicate check
    for _, entry in ipairs(customData.entries) do
        if entry.type == entryType and entry.id == entryID then
            return false -- already exists
        end
    end

    table.insert(customData.entries, {
        id = entryID,
        type = entryType,
        enabled = true,
    })

    -- RefreshAll handles RebuildIcons + layout for both viewers
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
    return true
end

function CustomCDM:RemoveEntry(trackerKey, entryIndex)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries then return end
    if entryIndex < 1 or entryIndex > #customData.entries then return end

    table.remove(customData.entries, entryIndex)

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end

function CustomCDM:SetEntryEnabled(trackerKey, entryIndex, enabled)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries or not customData.entries[entryIndex] then return end

    customData.entries[entryIndex].enabled = enabled

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end

function CustomCDM:MoveEntry(trackerKey, fromIndex, direction)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries then return end

    local entries = customData.entries
    local toIndex = fromIndex + direction
    if toIndex < 1 or toIndex > #entries then return end

    entries[fromIndex], entries[toIndex] = entries[toIndex], entries[fromIndex]

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end

function CustomCDM:TransferEntry(fromTrackerKey, entryIndex, toTrackerKey)
    if fromTrackerKey == toTrackerKey then return false end

    local fromData = GetCustomData(fromTrackerKey)
    if not fromData or not fromData.entries then return false end
    if entryIndex < 1 or entryIndex > #fromData.entries then return false end

    local toData = GetCustomData(toTrackerKey)
    if not toData then return false end
    if not toData.entries then toData.entries = {} end

    local entry = fromData.entries[entryIndex]

    -- Duplicate check in destination
    for _, existing in ipairs(toData.entries) do
        if existing.type == entry.type and existing.id == entry.id then
            return false -- already exists in destination
        end
    end

    -- Clear position (slot numbers are bar-relative)
    entry.position = nil

    -- Insert into destination first, then remove from source
    table.insert(toData.entries, entry)
    table.remove(fromData.entries, entryIndex)

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
    return true
end

function CustomCDM:SetEntryPosition(trackerKey, entryIndex, position)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries or not customData.entries[entryIndex] then return end

    -- Normalize: 0, nil, or empty = auto (no explicit position)
    if position == nil or position == 0 or position == "" then
        customData.entries[entryIndex].position = nil
    else
        local num = tonumber(position)
        if num then
            customData.entries[entryIndex].position = math.max(1, math.floor(num))
        else
            customData.entries[entryIndex].position = nil
        end
    end

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end
