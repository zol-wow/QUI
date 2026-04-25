local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local QUICore = ns.Addon
local Helpers = ns.Helpers
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetCore = Helpers.GetCore

local SECTION_GAP = 14

local function BuildSpecProfilesContent(content)
    local PAD = PADDING
    local y = -10

    -- Description
    local info = GUI:CreateLabel(content, "Manage profiles and auto-switch based on specialization", 11, C.textMuted)
    info:SetJustifyH("LEFT")
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - 24

    -- Shared state
    local profileDropdown
    local profileDropdowns_all = {}
    local profileDropdowns_withPresets = {}
    local profileDropdowns_filtered = {}
    local currentProfileName

    -- Build a lookup of preset profile names → preset definitions
    local presetsByName = {}
    for _, preset in ipairs(QUI._presetProfiles or {}) do
        presetsByName[preset.profileName] = preset
    end

    local function GetProfileList(includePresets)
        local profiles = {}
        local core = GetCore()
        local dbRef = core and core.db
        local seen = {}
        if dbRef then
            for _, name in ipairs(dbRef:GetProfiles()) do
                table.insert(profiles, {value = name, text = name})
                seen[name] = true
            end
        end
        if includePresets then
            for _, preset in ipairs(QUI._presetProfiles or {}) do
                if not seen[preset.profileName] then
                    table.insert(profiles, {
                        value = preset.profileName,
                        text = preset.profileName .. "  |cff34D399(Preset)|r",
                    })
                end
            end
        end
        return profiles
    end

    local function RefreshProfileDropdowns()
        local allProfiles = GetProfileList(false)
        local allWithPresets = GetProfileList(true)
        local core = GetCore()
        local dbRef = core and core.db
        local currentProfile = dbRef and dbRef:GetCurrentProfile() or ""
        local filtered = {}
        for _, opt in ipairs(allProfiles) do
            if opt.value ~= currentProfile then table.insert(filtered, opt) end
        end
        for _, dd in ipairs(profileDropdowns_all) do
            if dd.SetOptions then dd.SetOptions(allProfiles) end
        end
        for _, dd in ipairs(profileDropdowns_withPresets) do
            if dd.SetOptions then dd.SetOptions(allWithPresets) end
        end
        for _, dd in ipairs(profileDropdowns_filtered) do
            if dd.SetOptions then dd.SetOptions(filtered) end
        end
    end

    local function RefreshProfileDisplay()
        local core = GetCore()
        local freshDB = core and core.db
        if freshDB then
            local currentName = freshDB:GetCurrentProfile()
            if currentProfileName then currentProfileName:SetText(currentName or "Unknown") end
            if profileDropdown and profileDropdown.SetValue then
                profileDropdown:SetValue(currentName or "Default", true)
            end
        end
        RefreshProfileDropdowns()
    end

    ---------------------------------------------------------------------------
    -- Current Profile
    ---------------------------------------------------------------------------
    Shared.CreateAccentDotLabel(content, "Current Profile", y); y = y - 22

    local currentCard = Shared.CreateSettingsCardGroup(content, y)

    -- Active profile display: static label left, live value right.
    local activeCell = CreateFrame("Frame", nil, currentCard.frame)
    activeCell:SetHeight(28)
    local activeLabel = activeCell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeLabel:SetPoint("LEFT", activeCell, "LEFT", 0, 0)
    activeLabel:SetText("Active Profile")
    activeLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    currentProfileName = activeCell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentProfileName:SetPoint("RIGHT", activeCell, "RIGHT", 0, 0)
    currentProfileName:SetText("Loading...")
    currentProfileName:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
    currentCard.AddRow(activeCell)

    local function ResetButtonCell(label, onClick)
        local cell = CreateFrame("Frame", nil, currentCard.frame)
        cell:SetHeight(28)
        local lbl = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", cell, "LEFT", 0, 0)
        lbl:SetText(label)
        lbl:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        local btn = GUI:CreateButton(cell, "Reset", 100, 22, onClick)
        btn:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
        return cell
    end

    local resetProfileCell = ResetButtonCell("Reset Profile", function()
        GUI:ShowConfirmation({
            title = "Reset Profile?", message = "Reset current profile to defaults?",
            warningText = "This cannot be undone.", acceptText = "Reset", cancelText = "Cancel", isDestructive = true,
            onAccept = function()
                local core = GetCore(); local dbRef = core and core.db
                if dbRef then dbRef:ResetProfile(); print("|cff60A5FAQUI:|r Profile reset. Please /reload.") end
            end,
        })
    end)
    currentCard.AddRow(resetProfileCell)

    local resetMoversCell = ResetButtonCell("Reset All Positions", function()
        GUI:ShowConfirmation({
            title = "Reset All Movers?", message = "Reset all frame positions to defaults?",
            warningText = "This resets CDM, unit frames, minimap, action bars, data panels, trackers, Blizzard UI Mover panel positions, and all other movable elements. Requires /reload.", acceptText = "Reset All", cancelText = "Cancel", isDestructive = true,
            onAccept = function()
                local core = GetCore(); local dbRef = core and core.db
                if not dbRef then return end
                local p = dbRef.profile
                if p.ncdm then for _, k in ipairs({"essential","utility","buff"}) do if p.ncdm[k] then p.ncdm[k].pos = nil end end end
                if p.quiUnitFrames then
                    for _, u in ipairs({"player","target","targettarget","pet","focus","boss"}) do if p.quiUnitFrames[u] then p.quiUnitFrames[u].offsetX = nil; p.quiUnitFrames[u].offsetY = nil end end
                    for _, u in ipairs({"player","target","focus"}) do if p.quiUnitFrames[u] and p.quiUnitFrames[u].castbar then p.quiUnitFrames[u].castbar.offsetX = nil; p.quiUnitFrames[u].castbar.offsetY = nil end end
                end
                if p.minimap then p.minimap.position = nil end
                if p.actionBars and p.actionBars.bars then
                    if p.actionBars.bars.extraActionButton then p.actionBars.bars.extraActionButton.position = nil end
                    if p.actionBars.bars.zoneAbility then p.actionBars.bars.zoneAbility.position = nil end
                end
                if p.quiDatatexts and type(p.quiDatatexts.panels) == "table" then for _, panel in ipairs(p.quiDatatexts.panels) do if panel then panel.position = nil end end end
                if p.mplusTimer then p.mplusTimer.position = nil end
                if p.raidBuffs then p.raidBuffs.position = nil end
                if p.customTrackers and type(p.customTrackers.bars) == "table" then for _, bar in ipairs(p.customTrackers.bars) do if bar then bar.offsetX = nil; bar.offsetY = nil end end end
                if p.totemBar then p.totemBar.offsetX = nil; p.totemBar.offsetY = nil end
                if p.loot then p.loot.position = nil end
                if p.lootRoll then p.lootRoll.position = nil end
                if p.alerts then p.alerts.alertPosition = nil; p.alerts.toastPosition = nil; p.alerts.bnetToastPosition = nil end
                if type(p.frameAnchoring) == "table" then local hw = p.frameAnchoring.hudMinWidth; wipe(p.frameAnchoring); p.frameAnchoring.hudMinWidth = hw end
                if p.blizzardMover and type(p.blizzardMover.frames) == "table" then for _, row in pairs(p.blizzardMover.frames) do if type(row) == "table" then row.point = nil; row.x = nil; row.y = nil; row.scale = nil end end end
                local bmm = ns.QUI_BlizzardMover; if bmm and bmm.functions and bmm.functions.ClearSessionPositions then bmm.functions.ClearSessionPositions() end
                print("|cff60A5FAQUI:|r All positions reset. Please /reload.")
            end,
        })
    end)
    currentCard.AddRow(resetMoversCell)

    -- Factory Reset — label styled destructive, uses red button text.
    local factoryCell = CreateFrame("Frame", nil, currentCard.frame)
    factoryCell:SetHeight(28)
    local factoryLabel = factoryCell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    factoryLabel:SetPoint("LEFT", factoryCell, "LEFT", 0, 0)
    factoryLabel:SetText("Factory Reset")
    factoryLabel:SetTextColor(0.9, 0.3, 0.3, 1)
    local factoryBtn = GUI:CreateButton(factoryCell, "Erase All", 100, 22, function()
        GUI:ShowConfirmation({
            title = "Reset All Data?", message = "Erase ALL QUI data and restore fresh-install defaults?",
            warningText = "Deletes every profile, all global data, and character data. Cannot be undone.",
            acceptText = "Erase Everything", cancelText = "Cancel", isDestructive = true,
            onAccept = function()
                local core = GetCore(); local dbRef = core and core.db
                if dbRef then dbRef:ResetDB(true); print("|cff60A5FAQUI:|r All data erased."); QUI:SafeReload() end
            end,
        })
    end)
    factoryBtn:SetPoint("RIGHT", factoryCell, "RIGHT", 0, 0)
    if factoryBtn.text then factoryBtn.text:SetTextColor(0.9, 0.3, 0.3, 1) end
    currentCard.AddRow(factoryCell)

    currentCard.Finalize()
    y = y - currentCard.frame:GetHeight() - SECTION_GAP

    ---------------------------------------------------------------------------
    -- Switch Profile
    ---------------------------------------------------------------------------
    Shared.CreateAccentDotLabel(content, "Switch Profile", y); y = y - 22

    local switchCard = Shared.CreateSettingsCardGroup(content, y)
    local profileWrapper = { selected = "" }
    profileDropdown = GUI:CreateFormDropdown(switchCard.frame, nil, GetProfileList(true), "selected", profileWrapper, function(value)
        local core = GetCore(); local freshDB = core and core.db
        if freshDB and value and value ~= "" then
            local current = freshDB:GetCurrentProfile()
            if value == current then return end

            local preset = presetsByName[value]
            if preset then
                local exists = false
                for _, name in ipairs(freshDB:GetProfiles()) do
                    if name == value then exists = true; break end
                end
                if not exists then
                    local importData = QUI.imports[preset.key]
                    if not importData or not importData.data then
                        print("|cffff0000QUI:|r Preset data not found for: " .. value)
                        return
                    end
                    local ok, msg = core:ImportProfileFromString(importData.data, preset.profileName)
                    if ok then
                        print("|cff60A5FAQUI:|r Installed and switched to preset profile: " .. value)
                    else
                        print("|cffff0000QUI:|r Failed to install preset: " .. (msg or "unknown error"))
                        if freshDB:GetCurrentProfile() ~= current then
                            pcall(freshDB.SetProfile, freshDB, current)
                        end
                    end
                    if currentProfileName then currentProfileName:SetText(freshDB:GetCurrentProfile()) end
                    RefreshProfileDropdowns()
                    return
                end
            end

            freshDB:SetProfile(value)
            if currentProfileName then currentProfileName:SetText(value) end
            print("|cff60A5FAQUI:|r Switched to profile: " .. value)
            RefreshProfileDropdowns()
        end
    end, { description = "Switch to a different profile. Entries tagged (Preset) are installed from QUI's bundled presets on first pick." })
    table.insert(profileDropdowns_withPresets, profileDropdown)
    switchCard.AddRow(Shared.BuildSettingRow(switchCard.frame, "Profile", profileDropdown))
    switchCard.Finalize()

    local initCore = GetCore(); local initDB = initCore and initCore.db
    local initProfile = initDB and initDB:GetCurrentProfile() or "Default"
    profileWrapper.selected = initProfile
    if profileDropdown.SetValue then profileDropdown:SetValue(initProfile, true) end

    y = y - switchCard.frame:GetHeight() - SECTION_GAP

    ---------------------------------------------------------------------------
    -- Create New Profile — editbox + create action in paired row.
    ---------------------------------------------------------------------------
    Shared.CreateAccentDotLabel(content, "Create New Profile", y); y = y - 22

    local createCard = Shared.CreateSettingsCardGroup(content, y)
    local newProfileInput = GUI:CreateFormEditBox(createCard.frame, nil, nil, nil, nil, {
        width = 200, commitOnEnter = false, commitOnFocusLost = false,
        onEscapePressed = function(self) self:ClearFocus() end,
    }, { description = "Name for a new profile. Click Create to add it and switch to it immediately." })
    createCard.AddRow(Shared.BuildSettingRow(createCard.frame, "Profile Name", newProfileInput))

    local createCell = CreateFrame("Frame", nil, createCard.frame)
    createCell:SetHeight(28)
    local createBtn = GUI:CreateButton(createCell, "Create", 100, 22, function()
        local core = GetCore(); local dbRef = core and core.db
        local newName = newProfileInput.editBox and newProfileInput.editBox:GetText()
        if newName and newName ~= "" and dbRef then
            dbRef:SetProfile(newName)
            if currentProfileName then currentProfileName:SetText(newName) end
            if profileDropdown and profileDropdown.SetValue then profileDropdown:SetValue(newName, true) end
            newProfileInput.editBox:SetText("")
            print("|cff60A5FAQUI:|r Created new profile: " .. newName)
            RefreshProfileDropdowns()
        end
    end)
    createBtn:SetPoint("RIGHT", createCell, "RIGHT", 0, 0)
    createCard.AddRow(createCell)
    createCard.Finalize()
    y = y - createCard.frame:GetHeight() - SECTION_GAP

    ---------------------------------------------------------------------------
    -- Copy From Profile
    ---------------------------------------------------------------------------
    Shared.CreateAccentDotLabel(content, "Copy From Profile", y); y = y - 22

    local copyCard = Shared.CreateSettingsCardGroup(content, y)
    local copyWrapper = { selected = "" }
    local copyDropdown = GUI:CreateFormDropdown(copyCard.frame, nil, GetProfileList(), "selected", copyWrapper, function(value)
        local core = GetCore(); local dbRef = core and core.db
        if dbRef and value and value ~= "" then
            dbRef:CopyProfile(value)
            print("|cff60A5FAQUI:|r Copied settings from: " .. value)
            copyWrapper.selected = ""
            RefreshProfileDropdowns()
        end
    end, { description = "Copy every setting from the selected profile into the current profile. Replaces all matching keys in this profile." })
    table.insert(profileDropdowns_filtered, copyDropdown)
    copyCard.AddRow(Shared.BuildSettingRow(copyCard.frame, "Copy From", copyDropdown))
    copyCard.Finalize()
    y = y - copyCard.frame:GetHeight() - SECTION_GAP

    ---------------------------------------------------------------------------
    -- Delete Profile
    ---------------------------------------------------------------------------
    Shared.CreateAccentDotLabel(content, "Delete Profile", y); y = y - 22

    local deleteCard = Shared.CreateSettingsCardGroup(content, y)
    local deleteWrapper = { selected = "" }
    local deleteDropdown = GUI:CreateFormDropdown(deleteCard.frame, nil, GetProfileList(), "selected", deleteWrapper, function(value)
        local core = GetCore(); local dbRef = core and core.db
        if dbRef and value and value ~= "" then
            if value == dbRef:GetCurrentProfile() then
                print("|cffff0000QUI:|r Cannot delete the active profile!")
                deleteWrapper.selected = ""
            else
                local profileToDelete = value
                GUI:ShowConfirmation({
                    title = "Delete Profile?", message = string.format("Delete profile '%s'?", profileToDelete),
                    warningText = "This cannot be undone.", acceptText = "Delete", cancelText = "Cancel", isDestructive = true,
                    onAccept = function()
                        local core2 = GetCore(); local dbRef2 = core2 and core2.db
                        if dbRef2 then dbRef2:DeleteProfile(profileToDelete, true); print("|cff60A5FAQUI:|r Deleted: " .. profileToDelete) end
                        deleteWrapper.selected = ""
                        RefreshProfileDropdowns()
                    end,
                })
            end
        end
    end, { description = "Select a profile to delete. The currently active profile can't be deleted — switch to another profile first." })
    table.insert(profileDropdowns_filtered, deleteDropdown)
    deleteCard.AddRow(Shared.BuildSettingRow(deleteCard.frame, "Delete Profile", deleteDropdown))
    deleteCard.Finalize()
    y = y - deleteCard.frame:GetHeight() - SECTION_GAP

    ---------------------------------------------------------------------------
    -- Spec Auto-Switch
    ---------------------------------------------------------------------------
    Shared.CreateAccentDotLabel(content, "Spec Auto-Switch", y); y = y - 22

    local specCore = GetCore()
    local specDB = specCore and specCore.db
    local numSpecs = GetNumSpecializations()

    if specDB and specDB.IsDualSpecEnabled and specDB.SetDualSpecEnabled and specDB.GetDualSpecProfile and specDB.SetDualSpecProfile then
        local specCard = Shared.CreateSettingsCardGroup(content, y)

        local enableWrapper = { enabled = specDB:IsDualSpecEnabled() }
        local enableW = GUI:CreateFormCheckbox(specCard.frame, nil, "enabled", enableWrapper, function()
            local core = GetCore(); local dbRef = core and core.db
            if dbRef and dbRef.SetDualSpecEnabled then
                dbRef:SetDualSpecEnabled(enableWrapper.enabled)
                print("|cff60A5FAQUI:|r Spec auto-switch " .. (enableWrapper.enabled and "enabled" or "disabled"))
            end
        end, { description = "Automatically switch to a mapped profile whenever you change specialization. Map each spec to a profile below." })
        specCard.AddRow(Shared.BuildSettingRow(specCard.frame, "Enable Spec Profiles", enableW))

        local currentSpec = GetSpecialization()
        for i = 1, numSpecs do
            local specID, specName = GetSpecializationInfo(i)
            if specName then
                local displayName = specName .. (i == currentSpec and " (Active)" or "")
                local currentSpecProfile = specDB:GetDualSpecProfile(i) or ""
                local specWrapper = { selected = currentSpecProfile }
                local specDropdown = GUI:CreateFormDropdown(specCard.frame, nil, GetProfileList(), "selected", specWrapper, function(value)
                    local core = GetCore(); local dbRef = core and core.db
                    if dbRef and dbRef.SetDualSpecProfile and value and value ~= "" then
                        dbRef:SetDualSpecProfile(value, i)
                        print("|cff60A5FAQUI:|r " .. specName .. " will use profile: " .. value)
                    end
                end, { description = "Profile to activate whenever you swap into the " .. specName .. " specialization." })
                table.insert(profileDropdowns_all, specDropdown)
                specCard.AddRow(Shared.BuildSettingRow(specCard.frame, displayName, specDropdown))
            end
        end

        specCard.Finalize()
        y = y - specCard.frame:GetHeight() - SECTION_GAP
    else
        local noSpec = GUI:CreateLabel(content, "LibDualSpec not available.", 11, C.textMuted)
        noSpec:SetPoint("TOPLEFT", PAD, y)
        y = y - 24
    end

    -- Setup refresh hooks
    content:SetScript("OnShow", RefreshProfileDisplay)
    C_Timer.After(0.2, RefreshProfileDisplay)
    C_Timer.After(0.5, RefreshProfileDisplay)
    _G.QUI_RefreshSpecProfilesTab = RefreshProfileDisplay

    content:SetHeight(math.abs(y) + 20)
end

local function CreateSpecProfilesPage(parent)
    local _, content = CreateScrollableContent(parent)
    BuildSpecProfilesContent(content)
end

ns.QUI_ProfilesOptions = {
    BuildSpecProfilesContent = BuildSpecProfilesContent,
    CreateSpecProfilesPage = CreateSpecProfilesPage
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "profilesPage",
        moverKey = "profiles",
        category = "global",
        nav = { tileId = "global", subPageIndex = 1 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildSpecProfilesContent,
            }),
        },
    }))
end
