local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local function Enabled()
    local s = GetSettings()
    return s and s.autoUnwrapCollections == true
end

local function StopCollectionAlert()
    local button = _G.CollectionsMicroButton
    if button and MainMenuMicroButton_HideAlert then
        MainMenuMicroButton_HideAlert(button)
    end
    if CollectionsMicroButton_SetAlertShown then
        CollectionsMicroButton_SetAlertShown(false)
    end
end

local function ClearMountFanfare()
    if not (C_MountJournal and C_MountJournal.GetNumMountsNeedingFanfare) then return false end
    if C_MountJournal.GetNumMountsNeedingFanfare() <= 0 then return false end
    if LE_MOUNT_JOURNAL_FILTER_COLLECTED == nil or LE_MOUNT_JOURNAL_FILTER_UNUSABLE == nil then return false end

    local saved = {}
    for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
        saved[i] = C_MountJournal.GetCollectedFilterSetting(i) and true or false
        C_MountJournal.SetCollectedFilterSetting(i, i == LE_MOUNT_JOURNAL_FILTER_COLLECTED)
    end

    for i = 1, C_MountJournal.GetNumDisplayedMounts() do
        local mountID = C_MountJournal.GetDisplayedMountID(i)
        if mountID and C_MountJournal.NeedsFanfare(mountID) then
            C_MountJournal.ClearFanfare(mountID)
        end
    end

    for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
        C_MountJournal.SetCollectedFilterSetting(i, saved[i])
    end
    return true
end

local function ClearPetFanfare()
    local PJ = C_PetJournal
    if not (PJ and PJ.GetNumPetsNeedingFanfare and PJ.GetOwnedPetIDs and PJ.PetNeedsFanfare and PJ.ClearFanfare) then
        return false
    end
    if (PJ.GetNumPetsNeedingFanfare() or 0) == 0 then return false end
    local cleared = false
    for _, petID in ipairs(PJ.GetOwnedPetIDs() or {}) do
        if petID and PJ.PetNeedsFanfare(petID) then
            PJ.ClearFanfare(petID)
            cleared = true
        end
    end
    return cleared
end

local function ClearToyFanfare()
    if not (C_ToyBoxInfo and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.ClearFanfare) then return false end
    local cleared = false

    local toyBoxFrame = _G.ToyBox
    if toyBoxFrame and type(toyBoxFrame.fanfareToys) == "table" then
        for toyID, needs in pairs(toyBoxFrame.fanfareToys) do
            if needs and toyID and C_ToyBoxInfo.NeedsFanfare(toyID) then
                C_ToyBoxInfo.ClearFanfare(toyID)
                cleared = true
            end
        end
        if cleared then return true end
    end

    if C_ToyBox and C_ToyBox.GetNumToys and C_ToyBox.GetToyFromIndex then
        for i = 1, C_ToyBox.GetNumToys() do
            local toyID = C_ToyBox.GetToyFromIndex(i)
            if toyID and toyID > 0 and C_ToyBoxInfo.NeedsFanfare(toyID) then
                C_ToyBoxInfo.ClearFanfare(toyID)
                cleared = true
            end
        end
    end
    return cleared
end

local pending = false
local function ClearAllSoon()
    if not Enabled() or pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        if not Enabled() then return end
        local any = ClearMountFanfare()
        any = ClearPetFanfare() or any
        any = ClearToyFanfare() or any
        if any then StopCollectionAlert() end
    end)
end

hooksecurefunc("MainMenuMicroButton_ShowAlert", function(_, text)
    if text == COLLECTION_UNOPENED_PLURAL or text == COLLECTION_UNOPENED_SINGULAR then
        ClearAllSoon()
    end
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("NEW_MOUNT_ADDED")
frame:RegisterEvent("NEW_PET_ADDED")
frame:RegisterEvent("NEW_TOY_ADDED")
frame:SetScript("OnEvent", function()
    ClearAllSoon()
end)

ns.RefreshCollectionFanfare = ClearAllSoon

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(ClearAllSoon)
end
