local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local QUICore = ns.Addon
local Helpers = ns.Helpers

local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetCore = Helpers.GetCore

local CreateCollapsiblePage = Shared.CreateCollapsiblePage

local function CreateSpecProfilesPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local PAD = PADDING
    local FORM_ROW = 32
    local P = Helpers.PlaceRow

    -- Description
    local info = GUI:CreateLabel(content, "Manage profiles and auto-switch based on specialization", 11, C.textMuted)
    info:SetJustifyH("LEFT")
    info:SetPoint("TOPLEFT", PAD, -10)
    info:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local sections, relayout, CreateCollapsible = CreateCollapsiblePage(content, PAD, -38)

    -- Shared state
    local profileDropdown
    local profileDropdowns_all = {}
    local profileDropdowns_filtered = {}
    local currentProfileName

    local function GetProfileList()
        local profiles = {}
        local core = GetCore()
        local dbRef = core and core.db
        if dbRef then
            for _, name in ipairs(dbRef:GetProfiles()) do
                table.insert(profiles, {value = name, text = name})
            end
        end
        return profiles
    end

    local function RefreshProfileDropdowns()
        local allProfiles = GetProfileList()
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
    CreateCollapsible("Current Profile", 4 * FORM_ROW + 8, function(body)
        local sy = -4

        -- Active profile display
        local activeRow = CreateFrame("Frame", nil, body)
        activeRow:SetHeight(FORM_ROW)
        activeRow:SetPoint("TOPLEFT", 0, sy)
        activeRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        local activeLabel = activeRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        activeLabel:SetPoint("LEFT", 0, 0)
        activeLabel:SetText("Active Profile")
        activeLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        currentProfileName = activeRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        currentProfileName:SetPoint("LEFT", 180, 0)
        currentProfileName:SetText("Loading...")
        currentProfileName:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        sy = sy - FORM_ROW

        -- Reset Profile
        local resetBtn = GUI:CreateButton(body, "Reset to Defaults", 120, 24, function()
            GUI:ShowConfirmation({
                title = "Reset Profile?", message = "Reset current profile to defaults?",
                warningText = "This cannot be undone.", acceptText = "Reset", cancelText = "Cancel", isDestructive = true,
                onAccept = function()
                    local core = GetCore(); local dbRef = core and core.db
                    if dbRef then dbRef:ResetProfile(); print("|cff60A5FAQUI:|r Profile reset. Please /reload.") end
                end,
            })
        end)
        resetBtn:SetPoint("TOPLEFT", 0, sy)
        sy = sy - FORM_ROW

        -- Reset All Movers
        local moversBtn = GUI:CreateButton(body, "Reset All Positions", 120, 24, function()
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
        moversBtn:SetPoint("TOPLEFT", 0, sy)
        sy = sy - FORM_ROW

        -- Factory Reset
        local factoryBtn = GUI:CreateButton(body, "Factory Reset", 120, 24, function()
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
        factoryBtn:SetPoint("TOPLEFT", 0, sy)
        if factoryBtn.text then factoryBtn.text:SetTextColor(0.9, 0.3, 0.3, 1) end
    end)

    ---------------------------------------------------------------------------
    -- Switch Profile
    ---------------------------------------------------------------------------
    CreateCollapsible("Switch Profile", 1 * FORM_ROW + 8, function(body)
        local sy = -4
        local profileWrapper = { selected = "" }
        profileDropdown = GUI:CreateFormDropdown(body, "Select Profile", GetProfileList(), "selected", profileWrapper, function(value)
            local core = GetCore(); local freshDB = core and core.db
            if freshDB and value and value ~= "" then
                local current = freshDB:GetCurrentProfile()
                if value ~= current then
                    freshDB:SetProfile(value)
                    if currentProfileName then currentProfileName:SetText(value) end
                    print("|cff60A5FAQUI:|r Switched to profile: " .. value)
                    RefreshProfileDropdowns()
                end
            end
        end)
        table.insert(profileDropdowns_all, profileDropdown)
        P(profileDropdown, body, sy)

        local initCore = GetCore(); local initDB = initCore and initCore.db
        local initProfile = initDB and initDB:GetCurrentProfile() or "Default"
        profileWrapper.selected = initProfile
        if profileDropdown.SetValue then profileDropdown:SetValue(initProfile, true) end
    end)

    ---------------------------------------------------------------------------
    -- Create New Profile
    ---------------------------------------------------------------------------
    CreateCollapsible("Create New Profile", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        local newProfileInput = GUI:CreateFormEditBox(body, "Profile Name", nil, nil, nil, {
            width = 200, commitOnEnter = false, commitOnFocusLost = false,
            onEscapePressed = function(self) self:ClearFocus() end,
        })
        sy = P(newProfileInput, body, sy)

        local createBtn = GUI:CreateButton(body, "Create", 80, 24, function()
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
        createBtn:SetPoint("TOPLEFT", 0, sy)
    end)

    ---------------------------------------------------------------------------
    -- Copy From Profile
    ---------------------------------------------------------------------------
    CreateCollapsible("Copy From Profile", 1 * FORM_ROW + 8, function(body)
        local sy = -4
        local copyWrapper = { selected = "" }
        local copyDropdown = GUI:CreateFormDropdown(body, "Copy From", GetProfileList(), "selected", copyWrapper, function(value)
            local core = GetCore(); local dbRef = core and core.db
            if dbRef and value and value ~= "" then
                dbRef:CopyProfile(value)
                print("|cff60A5FAQUI:|r Copied settings from: " .. value)
                copyWrapper.selected = ""
                RefreshProfileDropdowns()
            end
        end)
        table.insert(profileDropdowns_filtered, copyDropdown)
        P(copyDropdown, body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Delete Profile
    ---------------------------------------------------------------------------
    CreateCollapsible("Delete Profile", 1 * FORM_ROW + 8, function(body)
        local sy = -4
        local deleteWrapper = { selected = "" }
        local deleteDropdown = GUI:CreateFormDropdown(body, "Delete Profile", GetProfileList(), "selected", deleteWrapper, function(value)
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
                            local core = GetCore(); local dbRef = core and core.db
                            if dbRef then dbRef:DeleteProfile(profileToDelete, true); print("|cff60A5FAQUI:|r Deleted: " .. profileToDelete) end
                            deleteWrapper.selected = ""
                            RefreshProfileDropdowns()
                        end,
                    })
                end
            end
        end)
        table.insert(profileDropdowns_filtered, deleteDropdown)
        P(deleteDropdown, body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Spec Auto-Switch
    ---------------------------------------------------------------------------
    local specCore = GetCore()
    local specDB = specCore and specCore.db
    local numSpecs = GetNumSpecializations()
    local specRows = 2 + numSpecs  -- enable + info + per-spec dropdowns

    CreateCollapsible("Spec Auto-Switch", specRows * FORM_ROW + 8, function(body)
        local sy = -4
        if specDB and specDB.IsDualSpecEnabled and specDB.SetDualSpecEnabled and specDB.GetDualSpecProfile and specDB.SetDualSpecProfile then
            local enableWrapper = { enabled = specDB:IsDualSpecEnabled() }
            sy = P(GUI:CreateFormCheckbox(body, "Enable Spec Profiles", "enabled", enableWrapper, function()
                local core = GetCore(); local dbRef = core and core.db
                if dbRef and dbRef.SetDualSpecEnabled then
                    dbRef:SetDualSpecEnabled(enableWrapper.enabled)
                    print("|cff60A5FAQUI:|r Spec auto-switch " .. (enableWrapper.enabled and "enabled" or "disabled"))
                end
            end), body, sy)

            local currentSpec = GetSpecialization()
            for i = 1, numSpecs do
                local specID, specName = GetSpecializationInfo(i)
                if specName then
                    local displayName = specName .. (i == currentSpec and " (Active)" or "")
                    local currentSpecProfile = specDB:GetDualSpecProfile(i) or ""
                    local specWrapper = { selected = currentSpecProfile }
                    local specDropdown = GUI:CreateFormDropdown(body, displayName, GetProfileList(), "selected", specWrapper, function(value)
                        local core = GetCore(); local dbRef = core and core.db
                        if dbRef and dbRef.SetDualSpecProfile and value and value ~= "" then
                            dbRef:SetDualSpecProfile(value, i)
                            print("|cff60A5FAQUI:|r " .. specName .. " will use profile: " .. value)
                        end
                    end)
                    table.insert(profileDropdowns_all, specDropdown)
                    sy = P(specDropdown, body, sy)
                end
            end
        else
            local noSpec = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noSpec:SetPoint("TOPLEFT", 4, sy)
            noSpec:SetTextColor(0.6, 0.6, 0.6, 1)
            noSpec:SetText("LibDualSpec not available.")
        end
    end)

    -- Setup refresh hooks
    content:SetScript("OnShow", RefreshProfileDisplay)
    scroll:SetScript("OnShow", RefreshProfileDisplay)
    C_Timer.After(0.2, RefreshProfileDisplay)
    C_Timer.After(0.5, RefreshProfileDisplay)
    _G.QUI_RefreshSpecProfilesTab = RefreshProfileDisplay

    relayout()
end

ns.QUI_ProfilesOptions = {
    CreateSpecProfilesPage = CreateSpecProfilesPage
}
