local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local MAX_ICONS = 8
local ICON_SIZE = 13

local initialized = false
local scanning = false
local classData
local cache = { key = nil, items = nil }

local function Enabled()
    local s = GetSettings()
    return s and s.ejLootSpecIcons == true
end

local function BuildClassData()
    if classData then return classData end
    if not (C_CreatureInfo and C_CreatureInfo.GetClassInfo
        and C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
        and GetSpecializationInfoForClassID) then
        return nil
    end
    classData = { totalSpecs = 0 }
    local numClasses = (GetNumClasses and GetNumClasses()) or 13
    for classID = 1, numClasses do
        local info = C_CreatureInfo.GetClassInfo(classID)
        if info then
            local specs = {}
            local n = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
            for i = 1, n do
                local specID, _, _, icon = GetSpecializationInfoForClassID(classID, i)
                if specID then
                    specs[#specs + 1] = { specID = specID, icon = icon }
                    classData.totalSpecs = classData.totalSpecs + 1
                end
            end
            classData[#classData + 1] = { classID = classID, specs = specs }
        end
    end
    return classData
end

local function CurrentKey()
    local ej = _G.EncounterJournal
    local difficulty = (EJ_GetDifficulty and EJ_GetDifficulty()) or 0
    return tostring(ej and ej.instanceID or 0) .. ":"
        .. tostring(ej and ej.encounterID or 0) .. ":" .. tostring(difficulty)
end

local function BuildSpecMap()
    local data = BuildClassData()
    if not data or not (EJ_SetLootFilter and EJ_GetLootFilter and EJ_GetNumLoot) then return nil end

    local savedClass, savedSpec = EJ_GetLootFilter()
    scanning = true
    local items = {}
    for _, class in ipairs(data) do
        for _, spec in ipairs(class.specs) do
            EJ_SetLootFilter(class.classID, spec.specID)
            for index = 1, EJ_GetNumLoot() do
                local info = C_EncounterJournal.GetLootInfoByIndex(index)
                if info and info.itemID then
                    local rec = items[info.itemID]
                    if not rec then
                        rec = { count = 0, icons = {} }
                        items[info.itemID] = rec
                    end
                    rec.count = rec.count + 1
                    if #rec.icons <= MAX_ICONS then
                        rec.icons[#rec.icons + 1] = spec.icon
                    end
                end
            end
        end
    end
    EJ_SetLootFilter(savedClass or 0, savedSpec or 0)
    scanning = false

    for id, rec in pairs(items) do
        if rec.count >= data.totalSpecs then
            items[id] = false
        end
    end
    return items
end

local function EnsureIcons(row)
    if row._quiSpecIcons then return row._quiSpecIcons end
    local icons = {}
    for i = 1, MAX_ICONS do
        local tex = row:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetSize(ICON_SIZE, ICON_SIZE)
        tex:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6 - (i - 1) * (ICON_SIZE + 1), -3)
        tex:Hide()
        icons[i] = tex
    end
    row._quiSpecIcons = icons
    return icons
end

local function DecorateRow(row)
    if not row or not row.CreateTexture then return end
    local icons = row._quiSpecIcons
    local rec = Enabled() and row.itemID and cache.items and cache.items[row.itemID] or nil
    if not rec or type(rec) ~= "table" then
        if icons then
            for i = 1, MAX_ICONS do icons[i]:Hide() end
        end
        return
    end
    icons = EnsureIcons(row)
    local n = math.min(#rec.icons, MAX_ICONS)
    if #rec.icons > MAX_ICONS then n = 0 end
    for i = 1, MAX_ICONS do
        if i <= n and rec.icons[i] then
            icons[i]:SetTexture(rec.icons[i])
            icons[i]:Show()
        else
            icons[i]:Hide()
        end
    end
end

local function GetLootScrollBox()
    local ej = _G.EncounterJournal
    return ej and ej.encounter and ej.encounter.info
        and ej.encounter.info.LootContainer
        and ej.encounter.info.LootContainer.ScrollBox
end

local function DecorateVisibleRows()
    local scrollBox = GetLootScrollBox()
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(DecorateRow)
    end
end

local function OnLootUpdate()
    if scanning or not initialized then return end
    if not Enabled() then
        DecorateVisibleRows()
        return
    end
    local key = CurrentKey()
    if cache.key ~= key or not cache.items then
        cache.items = BuildSpecMap()
        cache.key = cache.items and key or nil
    end
    DecorateVisibleRows()
end

local function Initialize()
    if initialized then return end
    if not _G.EncounterJournal then return end
    initialized = true

    hooksecurefunc("EncounterJournal_LootUpdate", function()
        if scanning then return end
        C_Timer.After(0, OnLootUpdate)
    end)

    local scrollBox = GetLootScrollBox()
    if scrollBox and scrollBox.RegisterCallback and ScrollBoxListMixin
        and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnAcquiredFrame then
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, function(_, frame)
            if not scanning then DecorateRow(frame) end
        end, {})
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, addonName)
    if addonName == "Blizzard_EncounterJournal" then
        Initialize()
    end
end)

if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
    Initialize()
end

ns.RefreshEJLootSpecIcons = function()
    cache.key, cache.items = nil, nil
    if initialized then OnLootUpdate() end
end
