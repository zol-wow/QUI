local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

-- Local references for shared infrastructure
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent

--------------------------------------------------------------------------------
-- SPEC PROFILES PAGE
--------------------------------------------------------------------------------
local function CreateSpecProfilesPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local y = -15
    local PAD = PADDING
    local FORM_ROW = 32

    local QUICore = _G.QUI and _G.QUI.QUICore
    local db = QUICore and QUICore.db

    local info = GUI:CreateLabel(content, "Manage profiles and auto-switch based on specialization", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    -- =====================================================
    -- CURRENT PROFILE SECTION
    -- =====================================================
    local currentHeader = GUI:CreateSectionHeader(content, "Current Profile")
    currentHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - currentHeader.gap

    -- Forward declare profileDropdown so refresh function can reference it
    local profileDropdown
    -- Collect dropdowns that depend on the profile list so we can refresh them dynamically
    local profileDropdowns_all = {}       -- spec dropdowns: show all profiles
    local profileDropdowns_filtered = {}  -- copy/delete: exclude current profile

    -- Current profile display (form style row)
    local activeContainer = CreateFrame("Frame", nil, content)
    activeContainer:SetHeight(FORM_ROW)
    activeContainer:SetPoint("TOPLEFT", PAD, y)
    activeContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local currentProfileLabel = activeContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentProfileLabel:SetPoint("LEFT", 0, 0)
    currentProfileLabel:SetText("Active Profile")
    currentProfileLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local currentProfileName = activeContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentProfileName:SetPoint("LEFT", activeContainer, "LEFT", 180, 0)
    currentProfileName:SetText("Loading...")
    currentProfileName:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Function to refresh profile display - called on show and via timer
    -- Note: This gets replaced later after profileDropdown is created
    local function RefreshProfileDisplay()
        local QUICore = _G.QUI and _G.QUI.QUICore
        local freshDB = QUICore and QUICore.db
        if freshDB then
            local currentName = freshDB:GetCurrentProfile()
            currentProfileName:SetText(currentName or "Unknown")
        end
    end

    -- Update on show
    content:SetScript("OnShow", RefreshProfileDisplay)

    -- Also update on scroll parent show (in case content is already visible)
    scroll:SetScript("OnShow", RefreshProfileDisplay)

    -- Also use a short timer to catch any race conditions
    C_Timer.After(0.1, RefreshProfileDisplay)

    y = y - FORM_ROW

    -- Reset Profile button (form style row)
    local resetContainer = CreateFrame("Frame", nil, content)
    resetContainer:SetHeight(FORM_ROW)
    resetContainer:SetPoint("TOPLEFT", PAD, y)
    resetContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local resetLabel = resetContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetLabel:SetPoint("LEFT", 0, 0)
    resetLabel:SetText("Reset Profile")
    resetLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local resetBtn = CreateFrame("Button", nil, resetContainer, "BackdropTemplate")
    resetBtn:SetSize(120, 24)
    resetBtn:SetPoint("LEFT", resetContainer, "LEFT", 180, 0)
    resetBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    resetBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    resetBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    local resetBtnText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetBtnText:SetPoint("CENTER")
    resetBtnText:SetText("Reset to Defaults")
    resetBtnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    resetBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    resetBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)
    resetBtn:SetScript("OnClick", function()
        if db then
            GUI:ShowConfirmation({
                title = "Reset Profile?",
                message = "Reset current profile to defaults?",
                warningText = "This cannot be undone.",
                acceptText = "Reset",
                cancelText = "Cancel",
                isDestructive = true,
                onAccept = function()
                    local QUICore = _G.QUI and _G.QUI.QUICore
                    local dbRef = QUICore and QUICore.db
                    if dbRef then
                        dbRef:ResetProfile()
                        print("|cff34D399QUI:|r Profile reset to defaults.")
                        print("|cff34D399QUI:|r Please type |cFFFFD700/reload|r to apply changes.")
                    end
                end,
            })
        end
    end)
    y = y - FORM_ROW - 10

    -- =====================================================
    -- PROFILE SELECTION SECTION
    -- =====================================================
    local selectHeader = GUI:CreateSectionHeader(content, "Switch Profile")
    selectHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - selectHeader.gap

    -- Get existing profiles
    local function GetProfileList()
        local profiles = {}
        if db then
            local profileList = db:GetProfiles()
            for _, name in ipairs(profileList) do
                table.insert(profiles, {value = name, text = name})
            end
        end
        return profiles
    end

    -- Refresh all profile-dependent dropdowns with the current profile list
    local function RefreshProfileDropdowns()
        local allProfiles = GetProfileList()
        local currentProfile = db and db:GetCurrentProfile() or ""
        -- Filtered list excludes the current profile (for copy/delete)
        local filtered = {}
        for _, opt in ipairs(allProfiles) do
            if opt.value ~= currentProfile then
                table.insert(filtered, opt)
            end
        end
        for _, dd in ipairs(profileDropdowns_all) do
            if dd.SetOptions then dd.SetOptions(allProfiles) end
        end
        for _, dd in ipairs(profileDropdowns_filtered) do
            if dd.SetOptions then dd.SetOptions(filtered) end
        end
    end

    -- Profile dropdown - custom styled (matches our form dropdowns)
    local profileDropdownContainer = CreateFrame("Frame", nil, content)
    profileDropdownContainer:SetHeight(FORM_ROW)
    profileDropdownContainer:SetPoint("TOPLEFT", PAD, y)
    profileDropdownContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local profileDropdownLabel = profileDropdownContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileDropdownLabel:SetPoint("LEFT", 0, 0)
    profileDropdownLabel:SetText("Select Profile")
    profileDropdownLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    -- Custom dropdown button (styled to match our form dropdowns)
    local CHEVRON_ZONE_WIDTH = 28
    local CHEVRON_BG_ALPHA = 0.15
    local CHEVRON_BG_ALPHA_HOVER = 0.25
    local CHEVRON_TEXT_ALPHA = 0.8

    profileDropdown = CreateFrame("Button", nil, profileDropdownContainer, "BackdropTemplate")
    profileDropdown:SetHeight(24)
    profileDropdown:SetPoint("LEFT", profileDropdownContainer, "LEFT", 180, 0)
    profileDropdown:SetPoint("RIGHT", profileDropdownContainer, "RIGHT", 0, 0)
    profileDropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    profileDropdown:SetBackdropColor(0.08, 0.08, 0.08, 1)
    profileDropdown:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    -- Chevron zone (right side with accent tint)
    local chevronZone = CreateFrame("Frame", nil, profileDropdown, "BackdropTemplate")
    chevronZone:SetWidth(CHEVRON_ZONE_WIDTH)
    chevronZone:SetPoint("TOPRIGHT", profileDropdown, "TOPRIGHT", -1, -1)
    chevronZone:SetPoint("BOTTOMRIGHT", profileDropdown, "BOTTOMRIGHT", -1, 1)
    chevronZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)

    -- Separator line (left edge of chevron zone)
    local separator = chevronZone:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", chevronZone, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMLEFT", chevronZone, "BOTTOMLEFT", 0, 0)
    separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

    -- Line chevron (two angled lines forming a V pointing DOWN)
    local chevronLeft = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronLeft:SetSize(7, 2)
    chevronLeft:SetPoint("CENTER", chevronZone, "CENTER", -2, -1)
    chevronLeft:SetRotation(math.rad(-45))

    local chevronRight = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronRight:SetSize(7, 2)
    chevronRight:SetPoint("CENTER", chevronZone, "CENTER", 2, -1)
    chevronRight:SetRotation(math.rad(45))

    local profileDropdownText = profileDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileDropdownText:SetFont(GUI.FONT_PATH, 11, "")
    profileDropdownText:SetPoint("LEFT", 8, 0)
    profileDropdownText:SetPoint("RIGHT", chevronZone, "LEFT", -5, 0)
    profileDropdownText:SetJustifyH("LEFT")
    profileDropdownText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    profileDropdown:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA_HOVER)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    profileDropdown:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    end)

    -- Menu frame for profile options
    local profileMenu = CreateFrame("Frame", nil, profileDropdown, "BackdropTemplate")
    profileMenu:SetPoint("TOPLEFT", profileDropdown, "BOTTOMLEFT", 0, -2)
    profileMenu:SetPoint("TOPRIGHT", profileDropdown, "BOTTOMRIGHT", 0, -2)
    profileMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    profileMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
    profileMenu:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    profileMenu:SetFrameStrata("TOOLTIP")
    profileMenu:Hide()

    local function BuildProfileMenu()
        -- Clear existing items
        for _, child in ipairs({profileMenu:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local QUICore = _G.QUI and _G.QUI.QUICore
        local freshDB = QUICore and QUICore.db
        if not freshDB then return end

        local profiles = freshDB:GetProfiles()
        local currentProfile = freshDB:GetCurrentProfile()
        local itemHeight = 20
        local menuHeight = #profiles * itemHeight + 4

        profileMenu:SetHeight(menuHeight)

        for i, profileName in ipairs(profiles) do
            local item = CreateFrame("Button", nil, profileMenu, "BackdropTemplate")
            item:SetHeight(itemHeight)
            item:SetPoint("TOPLEFT", 2, -2 - (i-1) * itemHeight)
            item:SetPoint("TOPRIGHT", -2, -2 - (i-1) * itemHeight)

            local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            itemText:SetFont(GUI.FONT_PATH, 11, "")
            itemText:SetPoint("LEFT", 6, 0)
            itemText:SetText(profileName)

            if profileName == currentProfile then
                itemText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                itemText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            end

            item:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.accent[1] * 0.3, C.accent[2] * 0.3, C.accent[3] * 0.3, 1)
            end)
            item:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0, 0, 0, 0)
            end)
            item:SetScript("OnClick", function()
                if profileName ~= currentProfile then
                    freshDB:SetProfile(profileName)
                    profileDropdownText:SetText(profileName)
                    currentProfileName:SetText(profileName)
                    print("|cff34D399QUI:|r Switched to profile: " .. profileName)
                    RefreshProfileDropdowns()
                end
                profileMenu:Hide()
            end)
        end
    end

    profileDropdown:SetScript("OnClick", function()
        if profileMenu:IsShown() then
            profileMenu:Hide()
        else
            BuildProfileMenu()
            profileMenu:Show()
        end
    end)

    -- Set initial text
    local initCore = _G.QUI and _G.QUI.QUICore
    local initDB = initCore and initCore.db
    local initProfile = initDB and initDB:GetCurrentProfile() or "Default"
    profileDropdownText:SetText(initProfile)

    -- Update RefreshProfileDisplay to use our custom dropdown
    local oldRefresh = RefreshProfileDisplay
    RefreshProfileDisplay = function()
        local QUICore = _G.QUI and _G.QUI.QUICore
        local freshDB = QUICore and QUICore.db
        if freshDB then
            local currentName = freshDB:GetCurrentProfile()
            currentProfileName:SetText(currentName or "Unknown")
            profileDropdownText:SetText(currentName or "Default")
        end
        RefreshProfileDropdowns()
    end

    -- Re-register OnShow scripts with updated function (they were set before replacement)
    content:SetScript("OnShow", RefreshProfileDisplay)
    scroll:SetScript("OnShow", RefreshProfileDisplay)

    -- Refresh display after a short delay to ensure everything is loaded
    C_Timer.After(0.2, RefreshProfileDisplay)
    C_Timer.After(0.5, RefreshProfileDisplay)

    -- Expose refresh function for profile change callbacks
    _G.QUI_RefreshSpecProfilesTab = RefreshProfileDisplay

    y = y - FORM_ROW - 10

    -- =====================================================
    -- CREATE NEW PROFILE SECTION
    -- =====================================================
    local newHeader = GUI:CreateSectionHeader(content, "Create New Profile")
    newHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - newHeader.gap

    -- New profile name input (form style row)
    local newProfileContainer = CreateFrame("Frame", nil, content)
    newProfileContainer:SetHeight(FORM_ROW)
    newProfileContainer:SetPoint("TOPLEFT", PAD, y)
    newProfileContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local newProfileLabel = newProfileContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    newProfileLabel:SetPoint("LEFT", 0, 0)
    newProfileLabel:SetText("Profile Name")
    newProfileLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    -- Custom styled editbox (matches dropdown styling)
    local newProfileBoxBg = CreateFrame("Frame", nil, newProfileContainer, "BackdropTemplate")
    newProfileBoxBg:SetPoint("LEFT", newProfileContainer, "LEFT", 180, 0)
    newProfileBoxBg:SetSize(200, 24)
    newProfileBoxBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    newProfileBoxBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
    newProfileBoxBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local newProfileBox = CreateFrame("EditBox", nil, newProfileBoxBg)
    newProfileBox:SetPoint("LEFT", 8, 0)
    newProfileBox:SetPoint("RIGHT", -8, 0)
    newProfileBox:SetHeight(22)
    newProfileBox:SetAutoFocus(false)
    newProfileBox:SetFont(GUI.FONT_PATH, 11, "")
    newProfileBox:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    newProfileBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    newProfileBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    newProfileBox:SetScript("OnEditFocusGained", function()
        newProfileBoxBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    newProfileBox:SetScript("OnEditFocusLost", function()
        newProfileBoxBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    end)

    -- Create button
    local createBtn = CreateFrame("Button", nil, newProfileContainer, "BackdropTemplate")
    createBtn:SetSize(80, 24)
    createBtn:SetPoint("LEFT", newProfileBoxBg, "RIGHT", 10, 0)
    createBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    createBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    createBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    local createBtnText = createBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    createBtnText:SetPoint("CENTER")
    createBtnText:SetText("Create")
    createBtnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    createBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    createBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)
    createBtn:SetScript("OnClick", function()
        local newName = newProfileBox:GetText()
        if newName and newName ~= "" and db then
            db:SetProfile(newName)
            currentProfileName:SetText(newName)
            profileDropdownText:SetText(newName)
            newProfileBox:SetText("")
            print("|cff34D399QUI:|r Created new profile: " .. newName)
            RefreshProfileDropdowns()
        end
    end)
    y = y - FORM_ROW - 10

    -- =====================================================
    -- COPY FROM PROFILE SECTION
    -- =====================================================
    local copyHeader = GUI:CreateSectionHeader(content, "Copy From Profile")
    copyHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - copyHeader.gap

    local copyInfo = GUI:CreateLabel(content, "Copy settings from another profile into current", 11, C.textMuted)
    copyInfo:SetPoint("TOPLEFT", PAD, y)
    copyInfo:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    copyInfo:SetJustifyH("LEFT")
    y = y - 24

    -- Copy from dropdown (form style)
    local copyWrapper = { selected = "" }
    local copyDropdown = GUI:CreateFormDropdown(content, "Copy From", GetProfileList(), "selected", copyWrapper, function(value)
        if db and value and value ~= "" then
            db:CopyProfile(value)
            print("|cff34D399QUI:|r Copied settings from: " .. value)
            copyWrapper.selected = ""
            RefreshProfileDropdowns()
        end
    end)
    copyDropdown:SetPoint("TOPLEFT", PAD, y)
    copyDropdown:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    table.insert(profileDropdowns_filtered, copyDropdown)
    y = y - FORM_ROW - 10

    -- =====================================================
    -- DELETE PROFILE SECTION
    -- =====================================================
    local deleteHeader = GUI:CreateSectionHeader(content, "Delete Profile")
    deleteHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - deleteHeader.gap

    local deleteInfo = GUI:CreateLabel(content, "Remove unused profiles to save space", 11, C.textMuted)
    deleteInfo:SetPoint("TOPLEFT", PAD, y)
    deleteInfo:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    deleteInfo:SetJustifyH("LEFT")
    y = y - 24

    -- Delete dropdown (form style)
    local deleteWrapper = { selected = "" }
    local deleteDropdown = GUI:CreateFormDropdown(content, "Delete Profile", GetProfileList(), "selected", deleteWrapper, function(value)
        if db and value and value ~= "" then
            local current = db:GetCurrentProfile()
            if value == current then
                print("|cffff0000QUI:|r Cannot delete the active profile!")
                deleteWrapper.selected = ""
            else
                -- Show confirmation dialog
                local profileToDelete = value
                GUI:ShowConfirmation({
                    title = "Delete Profile?",
                    message = string.format("Delete profile '%s'?", profileToDelete),
                    warningText = "This cannot be undone.",
                    acceptText = "Delete",
                    cancelText = "Cancel",
                    isDestructive = true,
                    onAccept = function()
                        db:DeleteProfile(profileToDelete, true)
                        print("|cff34D399QUI:|r Deleted profile: " .. profileToDelete)
                        deleteWrapper.selected = ""
                        RefreshProfileDropdowns()
                    end,
                })
            end
        end
    end)
    deleteDropdown:SetPoint("TOPLEFT", PAD, y)
    deleteDropdown:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    table.insert(profileDropdowns_filtered, deleteDropdown)
    y = y - FORM_ROW - 10

    -- =====================================================
    -- SPEC AUTO-SWITCH SECTION
    -- =====================================================
    local specHeader = GUI:CreateSectionHeader(content, "Spec Auto-Switch")
    specHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - specHeader.gap

    -- Check if LibDualSpec methods are available on db (added by EnhanceDatabase)
    if db and db.IsDualSpecEnabled and db.SetDualSpecEnabled and db.GetDualSpecProfile and db.SetDualSpecProfile then
        -- Enable checkbox (form style)
        local enableWrapper = { enabled = db:IsDualSpecEnabled() }
        local enableCheckbox = GUI:CreateFormCheckbox(content, "Enable Spec Profiles", "enabled", enableWrapper,
            function()
                db:SetDualSpecEnabled(enableWrapper.enabled)
                print("|cff34D399QUI:|r Spec auto-switch " .. (enableWrapper.enabled and "enabled" or "disabled"))
            end)
        enableCheckbox:SetPoint("TOPLEFT", PAD, y)
        enableCheckbox:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local specInfo = GUI:CreateLabel(content, "When enabled, your profile will switch when you change specialization", 11, C.textMuted)
        specInfo:SetPoint("TOPLEFT", PAD, y)
        specInfo:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        specInfo:SetJustifyH("LEFT")
        y = y - 28

        -- Get spec names for current class
        local numSpecs = GetNumSpecializations()
        local currentSpec = GetSpecialization()

        for i = 1, numSpecs do
            local specID, specName = GetSpecializationInfo(i)
            if specName then
                -- Mark active spec
                local displayName = specName
                if i == currentSpec then
                    displayName = specName .. " (Active)"
                end

                -- Get current profile for this spec using LibDualSpec method
                local currentSpecProfile = db:GetDualSpecProfile(i) or ""
                local specWrapper = { selected = currentSpecProfile }

                -- Dropdown for this spec (form style)
                local specDropdown = GUI:CreateFormDropdown(content, displayName, GetProfileList(), "selected", specWrapper, function(value)
                    if value and value ~= "" then
                        db:SetDualSpecProfile(value, i)
                        print("|cff34D399QUI:|r " .. specName .. " will use profile: " .. value)
                    end
                end)
                specDropdown:SetPoint("TOPLEFT", PAD, y)
                specDropdown:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
                table.insert(profileDropdowns_all, specDropdown)

                y = y - FORM_ROW
            end
        end
    else
        local noSpec = GUI:CreateLabel(content, "LibDualSpec not available. Make sure another addon provides it.", 11, C.textMuted)
        noSpec:SetPoint("TOPLEFT", PAD, y)
        noSpec:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        noSpec:SetJustifyH("LEFT")
        y = y - 24

        local noSpec2 = GUI:CreateLabel(content, "Common addons with LibDualSpec: Masque and other action bar addons", 11, C.textMuted)
        noSpec2:SetPoint("TOPLEFT", PAD, y)
        noSpec2:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        noSpec2:SetJustifyH("LEFT")
        y = y - 24
    end

    y = y - 20

    content:SetHeight(math.abs(y) + 20)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_ProfilesOptions = {
    CreateSpecProfilesPage = CreateSpecProfilesPage
}
