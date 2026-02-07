local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

local function GetCore()
    return (_G.QUI and _G.QUI.QUICore) or ns.Addon
end

local QUICore = GetCore()

-- Local references for shared infrastructure
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList

-- Helper: Get char-scope custom entries for a tracker
local function GetCharCustomEntries(trackerKey)
    local QUICore = ns.Addon
    if QUICore and QUICore.db and QUICore.db.char and QUICore.db.char.ncdm
        and QUICore.db.char.ncdm[trackerKey] then
        return QUICore.db.char.ncdm[trackerKey].customEntries
    end
    return nil
end

--------------------------------------------------------------------------------
-- Refresh callback for NCDM changes
--------------------------------------------------------------------------------
local function RefreshNCDM()
    if _G.QUI_RefreshNCDM then
        _G.QUI_RefreshNCDM()
    end
end

--------------------------------------------------------------------------------
-- Initialize NCDM defaults for existing profiles that don't have them
--------------------------------------------------------------------------------
local function EnsureNCDMDefaults(db)
    if not db then return end

    -- Default row settings
    local defaultRow = {
        iconCount = 4,
        iconSize = 50,
        borderSize = 2,
        shape = "square",
        zoom = 0,
        padding = -8,
        yOffset = 0,
        opacity = 1.0,
    }

    -- Ensure ncdm table exists
    if not db.ncdm then
        db.ncdm = {}
    end

    -- Ensure essential exists
    if not db.ncdm.essential then
        db.ncdm.essential = { enabled = true }
    end
    for i = 1, 3 do
        local rowKey = "row" .. i
        if not db.ncdm.essential[rowKey] then
            db.ncdm.essential[rowKey] = {}
            for k, v in pairs(defaultRow) do
                db.ncdm.essential[rowKey][k] = v
            end
            -- Row 3 disabled by default
            if i == 3 then
                db.ncdm.essential[rowKey].iconCount = 0
            end
        end
    end

    -- Ensure utility exists
    if not db.ncdm.utility then
        db.ncdm.utility = { enabled = true }
    end
    for i = 1, 3 do
        local rowKey = "row" .. i
        if not db.ncdm.utility[rowKey] then
            db.ncdm.utility[rowKey] = {}
            for k, v in pairs(defaultRow) do
                db.ncdm.utility[rowKey][k] = v
            end
            db.ncdm.utility[rowKey].iconSize = 42
            db.ncdm.utility[rowKey].iconCount = 6
            db.ncdm.utility[rowKey].zoom = 0.08
            -- Row 3 disabled by default
            if i == 3 then
                db.ncdm.utility[rowKey].iconCount = 0
            end
        end
    end

    -- Ensure char-scope customEntries exist for both trackers + one-time migration from profile
    local QUICore = ns.Addon
    local charDB = QUICore and QUICore.db and QUICore.db.char
    if charDB then
        if not charDB.ncdm then charDB.ncdm = {} end
        for _, key in ipairs({"essential", "utility"}) do
            if not charDB.ncdm[key] then charDB.ncdm[key] = {} end
            if not charDB.ncdm[key].customEntries then
                charDB.ncdm[key].customEntries = { enabled = true, placement = "after", entries = {} }
            end
            local charCustom = charDB.ncdm[key].customEntries
            if not charCustom.entries then charCustom.entries = {} end
            if charCustom.placement == nil then charCustom.placement = "after" end

            -- One-time migration: copy from profile to char if char is empty and profile has data
            local profileTracker = db.ncdm[key]
            if profileTracker and profileTracker.customEntries then
                local profileEntries = profileTracker.customEntries.entries
                if profileEntries and #profileEntries > 0 and #charCustom.entries == 0 then
                    -- Copy entries from profile to char
                    for _, entry in ipairs(profileEntries) do
                        table.insert(charCustom.entries, {
                            id = entry.id,
                            type = entry.type,
                            enabled = entry.enabled,
                            position = entry.position,
                        })
                    end
                    -- Copy enabled/placement preferences
                    if profileTracker.customEntries.enabled ~= nil then
                        charCustom.enabled = profileTracker.customEntries.enabled
                    end
                    if profileTracker.customEntries.placement then
                        charCustom.placement = profileTracker.customEntries.placement
                    end
                    -- Clear profile entries to prevent re-migration
                    wipe(profileTracker.customEntries.entries)
                end
            end

            -- Sanitize entries: ensure 'enabled' field and valid position values
            for _, entry in ipairs(charCustom.entries) do
                if entry.enabled == nil then entry.enabled = true end
                if entry.position ~= nil and (type(entry.position) ~= "number" or entry.position < 1) then
                    entry.position = nil
                end
            end
        end
    end

    -- Ensure buff exists with required defaults
    if not db.ncdm.buff then
        db.ncdm.buff = {}
    end
    local buffData = db.ncdm.buff
    if buffData.enabled == nil then buffData.enabled = true end
    if buffData.iconSize == nil then buffData.iconSize = 32 end
    if buffData.borderSize == nil then buffData.borderSize = 1 end
    if buffData.shape == nil then buffData.shape = "square" end -- deprecated
    if buffData.aspectRatioCrop == nil then buffData.aspectRatioCrop = 1.0 end
    if buffData.growthDirection == nil then buffData.growthDirection = "CENTERED_HORIZONTAL" end
    if buffData.zoom == nil then buffData.zoom = 0 end
    if buffData.padding == nil then buffData.padding = 4 end
    if buffData.durationSize == nil then buffData.durationSize = 14 end
    if buffData.durationOffsetX == nil then buffData.durationOffsetX = 0 end
    if buffData.durationOffsetY == nil then buffData.durationOffsetY = 8 end
    if buffData.durationAnchor == nil then buffData.durationAnchor = "TOP" end
    if buffData.stackSize == nil then buffData.stackSize = 14 end
    if buffData.stackOffsetX == nil then buffData.stackOffsetX = 0 end
    if buffData.stackOffsetY == nil then buffData.stackOffsetY = -8 end
    if buffData.stackAnchor == nil then buffData.stackAnchor = "BOTTOM" end
    if buffData.opacity == nil then buffData.opacity = 1.0 end

    -- Ensure trackedBar exists with required defaults
    if not db.ncdm.trackedBar then
        db.ncdm.trackedBar = {}
    end
    local trackedData = db.ncdm.trackedBar
    if trackedData.enabled == nil then trackedData.enabled = true end
    if trackedData.hideIcon == nil then trackedData.hideIcon = false end
    if trackedData.barHeight == nil then trackedData.barHeight = 25 end
    if trackedData.barWidth == nil then trackedData.barWidth = 215 end
    if trackedData.texture == nil then trackedData.texture = "Quazii v5" end
    if trackedData.useClassColor == nil then trackedData.useClassColor = true end
    if trackedData.barColor == nil then trackedData.barColor = {0.204, 0.827, 0.6, 1} end
    if trackedData.barOpacity == nil then trackedData.barOpacity = 1.0 end
    if trackedData.borderSize == nil then trackedData.borderSize = 2 end
    if trackedData.bgColor == nil then trackedData.bgColor = {0, 0, 0, 1} end
    if trackedData.bgOpacity == nil then trackedData.bgOpacity = 0.5 end
    if trackedData.textSize == nil then trackedData.textSize = 14 end
    if trackedData.spacing == nil then trackedData.spacing = 2 end
    if trackedData.growUp == nil then trackedData.growUp = true end
    if trackedData.hideText == nil then trackedData.hideText = false end
    if trackedData.orientation == nil then trackedData.orientation = "horizontal" end
    if trackedData.fillDirection == nil then trackedData.fillDirection = "UP" end
    if trackedData.iconPosition == nil then trackedData.iconPosition = "top" end
    if trackedData.showTextOnVertical == nil then trackedData.showTextOnVertical = false end
end

--------------------------------------------------------------------------------
-- CreateCDMSetupPage - Main page builder for CDM Setup & Class Bars tab
--------------------------------------------------------------------------------
local function CreateCDMSetupPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local db = GetDB()

    -- Ensure NCDM tables exist for this profile
    EnsureNCDMDefaults(db)

    -- Helper to copy all settings from one row to another
    local function CopyRowSettings(sourceRow, targetRow)
        if not sourceRow or not targetRow then return end

        -- Copy all numeric and string settings
        local keys = {"iconCount", "iconSize", "borderSize", "shape", "zoom", "padding", "yOffset",
                      "durationSize", "durationOffsetX", "durationOffsetY", "durationAnchor",
                      "stackSize", "stackOffsetX", "stackOffsetY", "stackAnchor", "opacity"}
        for _, key in ipairs(keys) do
            if sourceRow[key] ~= nil then
                targetRow[key] = sourceRow[key]
            end
        end

        -- Copy color tables (deep copy)
        if sourceRow.durationTextColor then
            targetRow.durationTextColor = {sourceRow.durationTextColor[1], sourceRow.durationTextColor[2], sourceRow.durationTextColor[3], sourceRow.durationTextColor[4]}
        end
        if sourceRow.stackTextColor then
            targetRow.stackTextColor = {sourceRow.stackTextColor[1], sourceRow.stackTextColor[2], sourceRow.stackTextColor[3], sourceRow.stackTextColor[4]}
        end
    end

    -- Helper to build a single row's settings (form layout - single column)
    -- trackerData is the parent table (e.g., db.ncdm.essential) containing row1, row2, row3
    local function BuildRowSettings(tabContent, rowNum, rowData, trackerName, trackerData, rebuildCallback)
        local y = tabContent._currentY or -10
        local PAD = 10
        local FORM_ROW = 32

        -- Ensure offset and text size defaults exist
        if rowData.xOffset == nil then rowData.xOffset = 0 end
        if rowData.durationSize == nil then rowData.durationSize = 14 end
        if rowData.durationOffsetX == nil then rowData.durationOffsetX = 0 end
        if rowData.durationOffsetY == nil then rowData.durationOffsetY = 0 end
        if rowData.durationTextColor == nil then rowData.durationTextColor = {1, 1, 1, 1} end
        if rowData.durationAnchor == nil then rowData.durationAnchor = "CENTER" end
        if rowData.stackSize == nil then rowData.stackSize = 14 end
        if rowData.stackOffsetX == nil then rowData.stackOffsetX = 0 end
        if rowData.stackOffsetY == nil then rowData.stackOffsetY = 0 end
        if rowData.stackTextColor == nil then rowData.stackTextColor = {1, 1, 1, 1} end
        if rowData.stackAnchor == nil then rowData.stackAnchor = "BOTTOMRIGHT" end
        if rowData.opacity == nil then rowData.opacity = 1.0 end

        -- Row Header
        local rowHeader = GUI:CreateSectionHeader(tabContent, string.format("Row %d Configuration", rowNum))
        rowHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - rowHeader.gap

        -- Icon settings
        local countSlider = GUI:CreateFormSlider(tabContent, "Icons in Row", 0, 20, 1, "iconCount", rowData, RefreshNCDM)
        countSlider:SetPoint("TOPLEFT", PAD, y)
        countSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local sizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 5, 80, 1, "iconSize", rowData, RefreshNCDM)
        sizeSlider:SetPoint("TOPLEFT", PAD, y)
        sizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 5, 1, "borderSize", rowData, RefreshNCDM)
        borderSlider:SetPoint("TOPLEFT", PAD, y)
        borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColorTable", rowData, RefreshNCDM)
        borderColorPicker:SetPoint("TOPLEFT", PAD, y)
        borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local zoomSlider = GUI:CreateFormSlider(tabContent, "Icon Zoom", 0, 0.2, 0.01, "zoom", rowData, RefreshNCDM)
        zoomSlider:SetPoint("TOPLEFT", PAD, y)
        zoomSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local paddingSlider = GUI:CreateFormSlider(tabContent, "Padding", -20, 20, 1, "padding", rowData, RefreshNCDM)
        paddingSlider:SetPoint("TOPLEFT", PAD, y)
        paddingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local yOffsetSlider = GUI:CreateFormSlider(tabContent, "Row Y-Offset", -500, 500, 1, "yOffset", rowData, RefreshNCDM)
        yOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        yOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local xOffsetSlider = GUI:CreateFormSlider(tabContent, "Row X-Offset", -500, 500, 1, "xOffset", rowData, RefreshNCDM)
        xOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        xOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local opacitySlider = GUI:CreateFormSlider(tabContent, "Row Opacity", 0, 1.0, 0.05, "opacity", rowData, RefreshNCDM)
        opacitySlider:SetPoint("TOPLEFT", PAD, y)
        opacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local anchorOptions = {
            {value = "TOPLEFT", text = "Top Left"},
            {value = "TOP", text = "Top"},
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "LEFT", text = "Left"},
            {value = "CENTER", text = "Center"},
            {value = "RIGHT", text = "Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
            {value = "BOTTOM", text = "Bottom"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }

        local durationSlider = GUI:CreateFormSlider(tabContent, "Duration Text Size", 8, 50, 1, "durationSize", rowData, RefreshNCDM)
        durationSlider:SetPoint("TOPLEFT", PAD, y)
        durationSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationAnchorDD = GUI:CreateFormDropdown(tabContent, "Anchor Duration To", anchorOptions, "durationAnchor", rowData, RefreshNCDM)
        durationAnchorDD:SetPoint("TOPLEFT", PAD, y)
        durationAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationXSlider = GUI:CreateFormSlider(tabContent, "Duration X-Offset", -80, 80, 1, "durationOffsetX", rowData, RefreshNCDM)
        durationXSlider:SetPoint("TOPLEFT", PAD, y)
        durationXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationYSlider = GUI:CreateFormSlider(tabContent, "Duration Y-Offset", -80, 80, 1, "durationOffsetY", rowData, RefreshNCDM)
        durationYSlider:SetPoint("TOPLEFT", PAD, y)
        durationYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationColorPicker = GUI:CreateFormColorPicker(tabContent, "Duration Text Color", "durationTextColor", rowData, RefreshNCDM)
        durationColorPicker:SetPoint("TOPLEFT", PAD, y)
        durationColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackSlider = GUI:CreateFormSlider(tabContent, "Stack Text Size", 8, 50, 1, "stackSize", rowData, RefreshNCDM)
        stackSlider:SetPoint("TOPLEFT", PAD, y)
        stackSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackAnchorDD = GUI:CreateFormDropdown(tabContent, "Anchor Stack To", anchorOptions, "stackAnchor", rowData, RefreshNCDM)
        stackAnchorDD:SetPoint("TOPLEFT", PAD, y)
        stackAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackXSlider = GUI:CreateFormSlider(tabContent, "Stack X-Offset", -80, 80, 1, "stackOffsetX", rowData, RefreshNCDM)
        stackXSlider:SetPoint("TOPLEFT", PAD, y)
        stackXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackYSlider = GUI:CreateFormSlider(tabContent, "Stack Y-Offset", -80, 80, 1, "stackOffsetY", rowData, RefreshNCDM)
        stackYSlider:SetPoint("TOPLEFT", PAD, y)
        stackYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackColorPicker = GUI:CreateFormColorPicker(tabContent, "Stack Text Color", "stackTextColor", rowData, RefreshNCDM)
        stackColorPicker:SetPoint("TOPLEFT", PAD, y)
        stackColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeSlider = GUI:CreateFormSlider(tabContent, "Icon Shape", 1.0, 2.0, 0.01, "aspectRatioCrop", rowData, RefreshNCDM)
        shapeSlider:SetPoint("TOPLEFT", PAD, y)
        shapeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeTip = GUI:CreateLabel(tabContent, "Higher values imply flatter icons.", 11, C.textMuted)
        shapeTip:SetPoint("TOPLEFT", PAD, y)
        shapeTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        shapeTip:SetJustifyH("LEFT")
        y = y - 20

        -- Copy from dropdown (if trackerData is provided)
        if trackerData then
            local copyOptions = {}
            for i = 1, 3 do
                if i ~= rowNum then
                    table.insert(copyOptions, {value = "row" .. i, text = "Row " .. i})
                end
            end

            -- Copy Settings From - using form dropdown with Apply button
            local copyWrapper = { selected = copyOptions[1] and copyOptions[1].value or nil }
            local copyRow = CreateFrame("Frame", nil, tabContent)
            copyRow:SetHeight(FORM_ROW)
            copyRow:SetPoint("TOPLEFT", PAD, y)
            copyRow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

            local applyBtn = GUI:CreateButton(copyRow, "Apply", 60, 24, function()
                if copyWrapper.selected and trackerData[copyWrapper.selected] then
                    CopyRowSettings(trackerData[copyWrapper.selected], rowData)
                    RefreshNCDM()
                    if rebuildCallback then rebuildCallback() end
                end
            end)
            applyBtn:SetPoint("RIGHT", copyRow, "RIGHT", 0, 2)

            local copyDropdown = GUI:CreateFormDropdown(copyRow, "Copy Settings From", copyOptions, "selected", copyWrapper, nil)
            copyDropdown:SetPoint("TOPLEFT", 0, 0)
            copyDropdown:SetPoint("RIGHT", applyBtn, "LEFT", -8, 0)

            y = y - FORM_ROW
        end

        -- Add spacing between rows
        y = y - 15

        tabContent._currentY = y
        return y
    end

    ---------------------------------------------------------------------------
    -- TeardownTabContent: Shared helper to clear and recycle tab content
    ---------------------------------------------------------------------------
    local function TeardownTabContent(tabContent)
        for _, child in pairs({tabContent:GetChildren()}) do
            if child.Release then
                child:Release()
            elseif child.Recycle then
                child:Recycle()
            else
                if child.UnregisterAllEvents then
                    child:UnregisterAllEvents()
                end
                if child.SetScript and child.HasScript then
                    if child:HasScript("OnUpdate") then child:SetScript("OnUpdate", nil) end
                    if child:HasScript("OnClick") then child:SetScript("OnClick", nil) end
                    if child:HasScript("OnEnter") then child:SetScript("OnEnter", nil) end
                    if child:HasScript("OnLeave") then child:SetScript("OnLeave", nil) end
                    if child:HasScript("OnEvent") then child:SetScript("OnEvent", nil) end
                end
                if child.EnableMouse then
                    child:EnableMouse(false)
                end
                if child.ClearAllPoints then
                    child:ClearAllPoints()
                end
                child:Hide()
                child:SetParent(nil)
            end
        end
        for _, region in pairs({tabContent:GetRegions()}) do
            if region.SetTexture and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:SetTexture(nil)
            elseif region.SetText and region.GetObjectType and region:GetObjectType() == "FontString" then
                region:SetText("")
            end
            if region.SetScript and region.HasScript then
                if region:HasScript("OnUpdate") then region:SetScript("OnUpdate", nil) end
                if region:HasScript("OnEnter") then region:SetScript("OnEnter", nil) end
                if region:HasScript("OnLeave") then region:SetScript("OnLeave", nil) end
                if region:HasScript("OnEvent") then region:SetScript("OnEvent", nil) end
            end
            if region.ClearAllPoints then
                region:ClearAllPoints()
            end
            if region.Hide then
                region:Hide()
            end
            if region.SetParent then
                region:SetParent(nil)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- RenderBarPreview: Render a single bar's preview (extracted helper)
    -- Returns updated y position
    ---------------------------------------------------------------------------
    local function RenderBarPreview(tabContent, trackerKey, y, PAD)
        local customDataNow = GetCharCustomEntries(trackerKey)
        local entriesNow = (customDataNow and customDataNow.entries) or {}

        -- Re-read tracker settings
        local trackerSettings = db.ncdm[trackerKey]
        if not trackerSettings then return y end

        -- Gather row configs
        local rowConfigs = {}
        local totalSlots = 0
        for ri = 1, 3 do
            local rowKey = "row" .. ri
            local rd = trackerSettings[rowKey]
            if rd and rd.iconCount and rd.iconCount > 0 then
                table.insert(rowConfigs, {
                    count = rd.iconCount,
                    size = rd.iconSize or 50,
                    aspectRatioCrop = rd.aspectRatioCrop or 1.0,
                    padding = rd.padding or 0,
                    borderSize = rd.borderSize or 2,
                })
                totalSlots = totalSlots + rd.iconCount
            end
        end
        if totalSlots <= 0 then totalSlots = 12 end
        if #rowConfigs == 0 then
            rowConfigs = {{ count = totalSlots, size = 50, aspectRatioCrop = 1.0, padding = 0, borderSize = 2 }}
        end

        -- Collect actual Blizzard icon textures from the live viewer
        local vName = (trackerKey == "essential") and "EssentialCooldownViewer" or "UtilityCooldownViewer"
        local viewer = _G[vName]
        local blizzardTextures = {}
        if viewer and viewer.GetChildren then
            local blizzIcons = {}
            local children = { viewer:GetChildren() }
            for _, child in ipairs(children) do
                if child and child ~= viewer.Selection and not child._isCustomCDMIcon then
                    local iconTex = child.Icon or child.icon
                    if iconTex and (child.Cooldown or child.cooldown) then
                        if child:IsShown() or child._ncdmHidden then
                            table.insert(blizzIcons, child)
                        end
                    end
                end
            end
            table.sort(blizzIcons, function(a, b)
                return (a.layoutIndex or 9999) < (b.layoutIndex or 9999)
            end)
            for _, icon in ipairs(blizzIcons) do
                local tex = icon.Icon or icon.icon
                local texID = tex and tex.GetTexture and tex:GetTexture()
                table.insert(blizzardTextures, texID or "Interface\\Icons\\INV_Misc_QuestionMark")
            end
        end

        -- Build merged slot list mirroring CollectIcons logic
        local placement = (customDataNow and customDataNow.placement) or "after"

        local positioned = {}
        local unpositioned = {}
        local enabledEntries = {}
        for ei, entry in ipairs(entriesNow) do
            if entry.enabled ~= false then
                table.insert(enabledEntries, entry)
                if entry.position and entry.position > 0 then
                    table.insert(positioned, { entry = entry, origIndex = ei })
                else
                    table.insert(unpositioned, entry)
                end
            end
        end

        local blizzardSlotCount = #blizzardTextures
        if blizzardSlotCount == 0 then
            blizzardSlotCount = math.max(0, totalSlots - #enabledEntries)
        end
        local previewSlots = {}
        for n = 1, blizzardSlotCount do
            table.insert(previewSlots, {
                type = "blizzard",
                num = n,
                texture = blizzardTextures[n] or nil,
            })
        end

        if placement == "before" then
            local merged = {}
            for _, entry in ipairs(unpositioned) do
                table.insert(merged, { type = "custom", entry = entry })
            end
            for _, slot in ipairs(previewSlots) do
                table.insert(merged, slot)
            end
            previewSlots = merged
        else
            for _, entry in ipairs(unpositioned) do
                table.insert(previewSlots, { type = "custom", entry = entry })
            end
        end

        table.sort(positioned, function(a, b)
            local posA = a.entry.position or 0
            local posB = b.entry.position or 0
            if posA ~= posB then return posA > posB end
            return a.origIndex < b.origIndex
        end)
        for _, item in ipairs(positioned) do
            local pos = item.entry.position
            local insertAt = math.min(pos, #previewSlots + 1)
            table.insert(previewSlots, insertAt, { type = "custom", entry = item.entry })
        end

        while #previewSlots > totalSlots do
            table.remove(previewSlots)
        end

        -- Calculate scale
        local availableWidth = 680 - (PAD * 2)
        local maxNativeWidth = 0
        for _, rc in ipairs(rowConfigs) do
            local rowWidth = (rc.count * rc.size) + ((rc.count - 1) * math.max(rc.padding, 0))
            if rowWidth > maxNativeWidth then maxNativeWidth = rowWidth end
        end
        local scale = 1
        if maxNativeWidth > 0 then
            scale = math.min(1, availableWidth / maxNativeWidth)
            local maxIconSize = 36
            for _, rc in ipairs(rowConfigs) do
                if rc.size * scale > maxIconSize then
                    scale = math.min(scale, maxIconSize / rc.size)
                end
            end
        end

        -- Calculate total preview height
        local ROW_GAP = 14
        local previewHeight = 0
        for ri, rc in ipairs(rowConfigs) do
            local aspect = rc.aspectRatioCrop or 1.0
            local iconH = (rc.size / aspect) * scale
            previewHeight = previewHeight + iconH
            if ri > 1 then previewHeight = previewHeight + ROW_GAP end
        end
        previewHeight = previewHeight + 12

        local previewContainer = CreateFrame("Frame", nil, tabContent)
        previewContainer:SetHeight(previewHeight)
        previewContainer:SetPoint("TOPLEFT", PAD, y)
        previewContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        -- Render rows
        local slotIdx = 1
        local rowY = 0
        local globalSlot = 0

        for ri, rc in ipairs(rowConfigs) do
            local aspect = rc.aspectRatioCrop or 1.0
            local iconW = rc.size * scale
            local iconH = (rc.size / aspect) * scale
            local padding = rc.padding * scale
            local borderSz = math.max(1, math.floor(rc.borderSize * scale + 0.5))

            local iconsInRow = math.min(rc.count, #previewSlots - slotIdx + 1)
            if iconsInRow <= 0 then break end

            local rowWidth = (iconsInRow * iconW) + ((iconsInRow - 1) * padding)
            local rowStartX = (availableWidth - rowWidth) / 2

            for i = 1, iconsInRow do
                local slot = previewSlots[slotIdx]
                if not slot then break end
                globalSlot = globalSlot + 1

                local x = rowStartX + (i - 1) * (iconW + padding)

                local slotFrame = CreateFrame("Frame", nil, previewContainer, "BackdropTemplate")
                slotFrame:SetSize(iconW, iconH)
                slotFrame:SetPoint("TOPLEFT", x, -rowY)

                local isCustom = (slot.type == "custom")

                slotFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = borderSz,
                })
                slotFrame:SetBackdropColor(0, 0, 0, 1)
                if isCustom then
                    slotFrame:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                else
                    slotFrame:SetBackdropBorderColor(0, 0, 0, 1)
                end

                local tex = slotFrame:CreateTexture(nil, "ARTWORK")
                tex:SetPoint("TOPLEFT", borderSz, -borderSz)
                tex:SetPoint("BOTTOMRIGHT", -borderSz, borderSz)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                if isCustom then
                    local texPath = "Interface\\Icons\\INV_Misc_QuestionMark"
                    if slot.entry.type == "spell" then
                        local info = C_Spell.GetSpellInfo(slot.entry.id)
                        if info and info.iconID then texPath = info.iconID end
                    elseif slot.entry.type == "item" then
                        local ic = C_Item.GetItemIconByID(slot.entry.id)
                        if ic then texPath = ic end
                    elseif slot.entry.type == "trinket" then
                        local itemID = GetInventoryItemID("player", slot.entry.id)
                        if itemID then
                            local ic = C_Item.GetItemIconByID(itemID)
                            if ic then texPath = ic end
                        end
                    end
                    tex:SetTexture(texPath)
                else
                    if slot.texture then
                        tex:SetTexture(slot.texture)
                    else
                        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                        tex:SetDesaturated(true)
                        tex:SetAlpha(0.4)
                    end
                end

                local slotNum = previewContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                slotNum:SetPoint("TOP", slotFrame, "BOTTOM", 0, -1)
                slotNum:SetText(tostring(globalSlot))
                if isCustom then
                    slotNum:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
                else
                    slotNum:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.6)
                end
                slotNum:SetFont(slotNum:GetFont(), 8)

                slotFrame:EnableMouse(true)
                local slotLabel = globalSlot
                if isCustom then
                    local entryRef = slot.entry
                    slotFrame:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local name = ns.CustomCDM and ns.CustomCDM:GetEntryName(entryRef) or "Custom"
                        local posText = (entryRef.position and entryRef.position > 0) and (" (pos " .. entryRef.position .. ")") or " (auto)"
                        GameTooltip:SetText("Slot " .. slotLabel .. ": " .. name .. posText)
                        GameTooltip:Show()
                    end)
                else
                    slotFrame:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Slot " .. slotLabel .. ": Blizzard Icon")
                        GameTooltip:Show()
                    end)
                end
                slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

                slotIdx = slotIdx + 1
            end

            rowY = rowY + iconH + ROW_GAP
        end

        y = y - previewHeight - 4
        return y
    end

    ---------------------------------------------------------------------------
    -- BuildCustomEntriesTab: Dedicated sub-tab for custom spell/item management
    ---------------------------------------------------------------------------
    local function BuildCustomEntriesTab(tabContent)
        tabContent._currentY = -10
        local PAD = 10
        local y = tabContent._currentY
        local FORM_ROW = 32

        -- Set search context for auto-registration
        GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 3, subTabName = "Custom Entries"})

        -- Rebuild callback
        local function rebuildCustomEntries()
            TeardownTabContent(tabContent)
            BuildCustomEntriesTab(tabContent)
        end

        local essCustom = GetCharCustomEntries("essential")
        local utilCustom = GetCharCustomEntries("utility")

        if not essCustom or not utilCustom then
            local info = GUI:CreateLabel(tabContent, "Custom entries settings not found. Please reload UI.", 12, C.accentLight)
            info:SetPoint("TOPLEFT", PAD, y)
            tabContent:SetHeight(math.abs(y) + 50)
            return
        end

        -- Essential Bar Settings section
        local essHeader = GUI:CreateSectionHeader(tabContent, "Essential Bar Settings")
        essHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - essHeader.gap

        local essEnableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Essential Custom Entries", "enabled", essCustom, function()
            RefreshNCDM()
        end)
        essEnableCheck:SetPoint("TOPLEFT", PAD, y)
        essEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local placementOptions = {
            {value = "before", text = "Before Blizzard Icons"},
            {value = "after", text = "After Blizzard Icons"},
        }
        local essPlacement = GUI:CreateFormDropdown(tabContent, "Essential Icon Placement", placementOptions, "placement", essCustom, function()
            RefreshNCDM()
        end)
        essPlacement:SetPoint("TOPLEFT", PAD, y)
        essPlacement:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Utility Bar Settings section
        local utilHeader = GUI:CreateSectionHeader(tabContent, "Utility Bar Settings")
        utilHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - utilHeader.gap

        local utilEnableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Utility Custom Entries", "enabled", utilCustom, function()
            RefreshNCDM()
        end)
        utilEnableCheck:SetPoint("TOPLEFT", PAD, y)
        utilEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilPlacement = GUI:CreateFormDropdown(tabContent, "Utility Icon Placement", placementOptions, "placement", utilCustom, function()
            RefreshNCDM()
        end)
        utilPlacement:SetPoint("TOPLEFT", PAD, y)
        utilPlacement:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Drop zone for spells/items (defaults to essential)
        local dropHeader = GUI:CreateSectionHeader(tabContent, "Add Custom Entries")
        dropHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - dropHeader.gap

        local dropZone = CreateFrame("Button", nil, tabContent, "BackdropTemplate")
        dropZone:SetHeight(50)
        dropZone:SetPoint("TOPLEFT", PAD, y)
        dropZone:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        dropZone:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        dropZone:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.8)
        dropZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

        local dropLabel = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dropLabel:SetPoint("CENTER", 0, 0)
        dropLabel:SetText("Drop Spells or Items Here (adds to Essential)")
        dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

        local defaultTracker = "essential"

        dropZone:SetScript("OnReceiveDrag", function(self)
            local cursorType, id1, id2, id3, id4 = GetCursorInfo()
            if cursorType == "item" then
                local itemID = id1
                if itemID and ns.CustomCDM then
                    ns.CustomCDM:AddEntry(defaultTracker, "item", itemID)
                    ClearCursor()
                    rebuildCustomEntries()
                end
            elseif cursorType == "spell" then
                local slotIndex = id1
                local bookType = id2 or "spell"
                local spellID = id4

                if not spellID and slotIndex then
                    local spellBank = (bookType == "pet") and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                    local spellBookInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                    if spellBookInfo then
                        spellID = spellBookInfo.spellID
                    end
                end

                if spellID then
                    local overrideID = C_Spell.GetOverrideSpell(spellID)
                    if overrideID and overrideID ~= spellID then
                        spellID = overrideID
                    end
                end

                if spellID and ns.CustomCDM then
                    ns.CustomCDM:AddEntry(defaultTracker, "spell", spellID)
                    ClearCursor()
                    rebuildCustomEntries()
                end
            end
        end)

        dropZone:SetScript("OnMouseUp", function(self)
            local cursorType = GetCursorInfo()
            if cursorType == "item" or cursorType == "spell" then
                local handler = dropZone:GetScript("OnReceiveDrag")
                if handler then handler(self) end
            end
        end)

        dropZone:SetScript("OnEnter", function(self)
            local cursorType = GetCursorInfo()
            if cursorType == "item" or cursorType == "spell" then
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                dropLabel:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
            end
        end)
        dropZone:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
            dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end)

        y = y - 58

        -- Trinket buttons row
        local trinketRow = CreateFrame("Frame", nil, tabContent)
        trinketRow:SetHeight(28)
        trinketRow:SetPoint("TOPLEFT", PAD, y)
        trinketRow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local trinket1Btn = GUI:CreateButton(trinketRow, "Add Trinket 1 (Slot 13)", 180, 24, function()
            if ns.CustomCDM then
                local added = ns.CustomCDM:AddEntry(defaultTracker, "trinket", 13)
                if added then rebuildCustomEntries() end
            end
        end)
        trinket1Btn:SetPoint("LEFT", 0, 0)

        local trinket2Btn = GUI:CreateButton(trinketRow, "Add Trinket 2 (Slot 14)", 180, 24, function()
            if ns.CustomCDM then
                local added = ns.CustomCDM:AddEntry(defaultTracker, "trinket", 14)
                if added then rebuildCustomEntries() end
            end
        end)
        trinket2Btn:SetPoint("LEFT", trinket1Btn, "RIGHT", 8, 0)

        y = y - FORM_ROW

        -- Combined entry list with section headers
        local barDropdownOptions = {
            {value = "essential", text = "Essential"},
            {value = "utility", text = "Utility"},
        }

        local function BuildEntryRow(trackerKey, entry, entryIndex, trackerLabel)
            local entryRow = CreateFrame("Frame", nil, tabContent, "BackdropTemplate")
            entryRow:SetHeight(28)
            entryRow:SetPoint("TOPLEFT", PAD, y)
            entryRow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            entryRow:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })
            entryRow:SetBackdropColor(0.12, 0.12, 0.15, 0.6)

            -- Icon texture
            local iconTex = entryRow:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(20, 20)
            iconTex:SetPoint("LEFT", 6, 0)

            local texturePath = "Interface\\Icons\\INV_Misc_QuestionMark"
            if entry.type == "spell" then
                local info = C_Spell.GetSpellInfo(entry.id)
                if info and info.iconID then texturePath = info.iconID end
            elseif entry.type == "item" then
                local icon = C_Item.GetItemIconByID(entry.id)
                if icon then texturePath = icon end
            elseif entry.type == "trinket" then
                local itemID = GetInventoryItemID("player", entry.id)
                if itemID then
                    local icon = C_Item.GetItemIconByID(itemID)
                    if icon then texturePath = icon end
                end
            end
            iconTex:SetTexture(texturePath)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Name label
            local nameLabel = entryRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
            nameLabel:SetPoint("RIGHT", entryRow, "RIGHT", -280, 0)
            nameLabel:SetJustifyH("LEFT")
            local entryName = ns.CustomCDM and ns.CustomCDM:GetEntryName(entry) or "Unknown"
            local typeTag = entry.type == "trinket" and "[T]" or (entry.type == "item" and "[I]" or "[S]")
            nameLabel:SetText(typeTag .. " " .. entryName)
            nameLabel:SetTextColor(0.9, 0.9, 0.9, 1)

            -- Bar dropdown (QUI-styled inline)
            local CHEVRON_W = 20
            local barSelect = CreateFrame("Button", nil, entryRow, "BackdropTemplate")
            barSelect:SetSize(90, 20)
            barSelect:SetPoint("RIGHT", entryRow, "RIGHT", -195, 0)
            barSelect:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            barSelect:SetBackdropColor(0.08, 0.08, 0.08, 1)
            barSelect:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

            local barText = barSelect:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            barText:SetPoint("LEFT", 6, 0)
            barText:SetPoint("RIGHT", barSelect, "RIGHT", -CHEVRON_W - 2, 0)
            barText:SetJustifyH("CENTER")
            barText:SetText(trackerLabel)
            barText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            barText:SetFont(barText:GetFont(), 10)

            -- Chevron zone
            local chevZone = CreateFrame("Frame", nil, barSelect, "BackdropTemplate")
            chevZone:SetWidth(CHEVRON_W)
            chevZone:SetPoint("TOPRIGHT", barSelect, "TOPRIGHT", -1, -1)
            chevZone:SetPoint("BOTTOMRIGHT", barSelect, "BOTTOMRIGHT", -1, 1)
            chevZone:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
            chevZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)

            local chevSep = chevZone:CreateTexture(nil, "ARTWORK")
            chevSep:SetWidth(1)
            chevSep:SetPoint("TOPLEFT", chevZone, "TOPLEFT", 0, 0)
            chevSep:SetPoint("BOTTOMLEFT", chevZone, "BOTTOMLEFT", 0, 0)
            chevSep:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

            local chevL = chevZone:CreateTexture(nil, "OVERLAY")
            chevL:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
            chevL:SetSize(5, 1)
            chevL:SetPoint("CENTER", chevZone, "CENTER", -2, -1)
            chevL:SetRotation(math.rad(-45))

            local chevR = chevZone:CreateTexture(nil, "OVERLAY")
            chevR:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
            chevR:SetSize(5, 1)
            chevR:SetPoint("CENTER", chevZone, "CENTER", 2, -1)
            chevR:SetRotation(math.rad(45))

            -- Menu frame
            local barMenu = CreateFrame("Frame", nil, barSelect, "BackdropTemplate")
            barMenu:SetPoint("TOPLEFT", barSelect, "BOTTOMLEFT", 0, -2)
            barMenu:SetPoint("TOPRIGHT", barSelect, "BOTTOMRIGHT", 0, -2)
            barMenu:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            barMenu:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
            barMenu:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            barMenu:SetFrameStrata("TOOLTIP")
            barMenu:SetHeight(4 + #barDropdownOptions * 20)
            barMenu:Hide()

            for mi, opt in ipairs(barDropdownOptions) do
                local mBtn = CreateFrame("Button", nil, barMenu, "BackdropTemplate")
                mBtn:SetHeight(20)
                mBtn:SetPoint("TOPLEFT", 2, -2 - (mi - 1) * 20)
                mBtn:SetPoint("TOPRIGHT", -2, -2 - (mi - 1) * 20)

                local mText = mBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                mText:SetPoint("LEFT", 6, 0)
                mText:SetText(opt.text)
                mText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                mText:SetFont(mText:GetFont(), 10)

                mBtn:SetScript("OnEnter", function(self)
                    pcall(function()
                        self:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                        self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
                    end)
                end)
                mBtn:SetScript("OnLeave", function(self)
                    pcall(function() self:SetBackdrop(nil) end)
                end)
                mBtn:SetScript("OnClick", function()
                    barMenu:Hide()
                    if opt.value ~= trackerKey and ns.CustomCDM then
                        ns.CustomCDM:TransferEntry(trackerKey, entryIndex, opt.value)
                        rebuildCustomEntries()
                    end
                end)
            end

            barSelect:SetScript("OnClick", function()
                if barMenu:IsShown() then
                    barMenu:Hide()
                else
                    barMenu:Show()
                end
            end)
            barSelect:SetScript("OnEnter", function(self)
                pcall(self.SetBackdropBorderColor, self, C.accent[1], C.accent[2], C.accent[3], 1)
                chevZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
                chevSep:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
                chevL:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                chevR:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            end)
            barSelect:SetScript("OnLeave", function(self)
                if not barMenu:IsShown() then
                    pcall(self.SetBackdropBorderColor, self, 0.35, 0.35, 0.35, 1)
                    chevZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
                    chevSep:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
                    chevL:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                    chevR:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                end
            end)

            -- Auto-close when mouse leaves both
            barMenu:SetScript("OnShow", function(self)
                self._closeTimer = 0
                self:SetScript("OnUpdate", function(self, elapsed)
                    local overBtn = barSelect:IsMouseOver()
                    local overMenu = self:IsMouseOver()
                    if overBtn or overMenu then
                        self._closeTimer = 0
                    else
                        self._closeTimer = (self._closeTimer or 0) + elapsed
                        if self._closeTimer > 0.15 then
                            self:Hide()
                        end
                    end
                end)
            end)
            barMenu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                pcall(barSelect.SetBackdropBorderColor, barSelect, 0.35, 0.35, 0.35, 1)
                chevZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
                chevSep:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
                chevL:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                chevR:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
            end)

            -- Position EditBox
            local posBox = CreateFrame("EditBox", nil, entryRow, "BackdropTemplate")
            posBox:SetSize(36, 20)
            posBox:SetPoint("RIGHT", entryRow, "RIGHT", -158, 0)
            posBox:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            posBox:SetBackdropColor(0.1, 0.1, 0.12, 0.8)
            posBox:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
            posBox:SetFontObject("GameFontHighlightSmall")
            posBox:SetJustifyH("CENTER")
            posBox:SetAutoFocus(false)
            posBox:SetNumeric(false)
            posBox:SetMaxLetters(3)

            if entry.position and entry.position > 0 then
                posBox:SetText(tostring(entry.position))
            else
                posBox:SetText("")
            end

            local placeholder = posBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            placeholder:SetPoint("CENTER", 0, 0)
            placeholder:SetText("Auto")
            placeholder:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.6)
            if posBox:GetText() ~= "" then placeholder:Hide() end

            posBox:SetScript("OnTextChanged", function(self, userInput)
                if self:GetText() == "" then
                    placeholder:Show()
                else
                    placeholder:Hide()
                end
            end)

            posBox:SetScript("OnEnterPressed", function(self)
                local text = self:GetText()
                local val = tonumber(text)
                if text ~= "" and val == nil then
                    self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
                    C_Timer.After(0.4, function()
                        if self:HasFocus() then
                            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                        else
                            self:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
                        end
                    end)
                    if entry.position and entry.position > 0 then
                        self:SetText(tostring(entry.position))
                    else
                        self:SetText("")
                    end
                    self:ClearFocus()
                    return
                end
                if ns.CustomCDM then
                    if text == "" then
                        ns.CustomCDM:SetEntryPosition(trackerKey, entryIndex, nil)
                    else
                        ns.CustomCDM:SetEntryPosition(trackerKey, entryIndex, val)
                    end
                    rebuildCustomEntries()
                end
                self:ClearFocus()
            end)

            posBox:SetScript("OnEscapePressed", function(self)
                if entry.position and entry.position > 0 then
                    self:SetText(tostring(entry.position))
                else
                    self:SetText("")
                end
                self:ClearFocus()
            end)

            posBox:SetScript("OnEditFocusGained", function(self)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            end)
            posBox:SetScript("OnEditFocusLost", function(self)
                self:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
            end)

            posBox:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Position (Slot)")
                GameTooltip:AddLine("Set a specific slot number in the bar.\nLeave empty for automatic placement.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            posBox:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            -- Enable/disable toggle
            local toggleBtn = GUI:CreateButton(entryRow, entry.enabled ~= false and "On" or "Off", 32, 20, function()
                if ns.CustomCDM then
                    local newState = not (entry.enabled ~= false)
                    ns.CustomCDM:SetEntryEnabled(trackerKey, entryIndex, newState)
                    rebuildCustomEntries()
                end
            end)
            toggleBtn:SetPoint("RIGHT", entryRow, "RIGHT", -126, 0)

            -- Move up button
            local upBtn = GUI:CreateButton(entryRow, "^", 24, 20, function()
                if ns.CustomCDM then
                    ns.CustomCDM:MoveEntry(trackerKey, entryIndex, -1)
                    rebuildCustomEntries()
                end
            end)
            upBtn:SetPoint("RIGHT", entryRow, "RIGHT", -96, 0)

            -- Move down button
            local downBtn = GUI:CreateButton(entryRow, "v", 24, 20, function()
                if ns.CustomCDM then
                    ns.CustomCDM:MoveEntry(trackerKey, entryIndex, 1)
                    rebuildCustomEntries()
                end
            end)
            downBtn:SetPoint("RIGHT", entryRow, "RIGHT", -68, 0)

            -- Remove button
            local removeBtn = GUI:CreateButton(entryRow, "X", 24, 20, function()
                if ns.CustomCDM then
                    ns.CustomCDM:RemoveEntry(trackerKey, entryIndex)
                    rebuildCustomEntries()
                end
            end)
            removeBtn:SetPoint("RIGHT", entryRow, "RIGHT", -6, 0)

            y = y - 30
        end

        -- Essential Entries section
        local essEntries = essCustom.entries or {}
        local utilEntries = utilCustom.entries or {}
        local totalEntries = #essEntries + #utilEntries

        if totalEntries > 0 then
            -- Column headers
            local headerRow = CreateFrame("Frame", nil, tabContent)
            headerRow:SetHeight(16)
            headerRow:SetPoint("TOPLEFT", PAD, y)
            headerRow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

            local barHeader = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            barHeader:SetPoint("RIGHT", headerRow, "RIGHT", -220, 0)
            barHeader:SetText("Bar")
            barHeader:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
            barHeader:SetFont(barHeader:GetFont(), 10)

            local posHeader = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            posHeader:SetPoint("RIGHT", headerRow, "RIGHT", -160, 0)
            posHeader:SetText("Pos")
            posHeader:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
            posHeader:SetFont(posHeader:GetFont(), 10)

            y = y - 18
        end

        -- Essential entries
        if #essEntries > 0 then
            local essLabel = GUI:CreateLabel(tabContent, "Essential Entries", 11, C.accentLight)
            essLabel:SetPoint("TOPLEFT", PAD, y)
            essLabel:SetJustifyH("LEFT")
            y = y - 16

            for i, entry in ipairs(essEntries) do
                BuildEntryRow("essential", entry, i, "Essential")
            end
        end

        -- Utility entries
        if #utilEntries > 0 then
            local utilLabel = GUI:CreateLabel(tabContent, "Utility Entries", 11, C.accentLight)
            utilLabel:SetPoint("TOPLEFT", PAD, y)
            utilLabel:SetJustifyH("LEFT")
            y = y - 16

            for i, entry in ipairs(utilEntries) do
                BuildEntryRow("utility", entry, i, "Utility")
            end
        end

        if totalEntries == 0 then
            local noEntries = GUI:CreateLabel(tabContent, "No custom entries. Drag spells or items above, or add trinkets.", 11, C.textMuted)
            noEntries:SetPoint("TOPLEFT", PAD, y)
            noEntries:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            noEntries:SetJustifyH("LEFT")
            y = y - 20
        end

        -- Combined preview sections (always visible)
        y = y - 8

        -- Essential bar preview
        local essPreviewLabel = GUI:CreateLabel(tabContent, "Essential Bar Preview:", 10, C.textMuted)
        essPreviewLabel:SetPoint("TOPLEFT", PAD, y)
        essPreviewLabel:SetJustifyH("LEFT")
        y = y - 16

        y = RenderBarPreview(tabContent, "essential", y, PAD)
        y = y - 10

        -- Utility bar preview
        local utilPreviewLabel = GUI:CreateLabel(tabContent, "Utility Bar Preview:", 10, C.textMuted)
        utilPreviewLabel:SetPoint("TOPLEFT", PAD, y)
        utilPreviewLabel:SetJustifyH("LEFT")
        y = y - 16

        y = RenderBarPreview(tabContent, "utility", y, PAD)
        y = y - 10

        y = y - 10
        tabContent._currentY = y
        tabContent:SetHeight(math.abs(tabContent._currentY) + 50)
    end

    -- Build Essential sub-tab
    local function BuildEssentialTab(tabContent)
        tabContent._currentY = -10
        local PAD = 10
        local y = tabContent._currentY

        -- Set search context for auto-registration
        GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 1, subTabName = "Essential"})

        if db and db.ncdm and db.ncdm.essential then
            local ess = db.ncdm.essential

            -- Rebuild callback to refresh the tab after copying
            local function rebuildEssential()
                TeardownTabContent(tabContent)
                BuildEssentialTab(tabContent)
            end

            -- Enable checkbox
            local FORM_ROW = 32
            local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Essential Cooldowns Display", "enabled", ess, RefreshNCDM)
            enableCheck:SetPoint("TOPLEFT", PAD, y)
            enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Layout Direction dropdown
            ess.layoutDirection = ess.layoutDirection or "HORIZONTAL"
            local directionOptions = {
                {value = "HORIZONTAL", text = "Horizontal"},
                {value = "VERTICAL", text = "Vertical"},
            }
            local directionDropdown = GUI:CreateFormDropdown(tabContent, "Layout Direction", directionOptions, "layoutDirection", ess, RefreshNCDM)
            directionDropdown:SetPoint("TOPLEFT", PAD, y)
            directionDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Hint text
            local hintText = GUI:CreateLabel(tabContent, "Tip: Set Icon Size to 100% in Edit Mode for best results.", 11, C.textMuted)
            hintText:SetPoint("TOPLEFT", PAD, y)
            hintText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            hintText:SetJustifyH("LEFT")
            y = y - 24
            tabContent._currentY = y

            -- Row 1
            if ess.row1 then
                BuildRowSettings(tabContent, 1, ess.row1, "Essential", ess, rebuildEssential)
            end

            -- Row 2
            if ess.row2 then
                BuildRowSettings(tabContent, 2, ess.row2, "Essential", ess, rebuildEssential)
            end

            -- Row 3
            if ess.row3 then
                BuildRowSettings(tabContent, 3, ess.row3, "Essential", ess, rebuildEssential)
            end
        else
            local info = GUI:CreateLabel(tabContent, "NCDM Essential settings not found. Please reload UI.", 12, C.accentLight)
            info:SetPoint("TOPLEFT", PAD, y)
        end

        tabContent:SetHeight(math.abs(tabContent._currentY) + 50)
    end

    -- Build Utility sub-tab
    local function BuildUtilityTab(tabContent)
        tabContent._currentY = -10
        local PAD = 10
        local y = tabContent._currentY

        -- Set search context for auto-registration
        GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 2, subTabName = "Utility"})

        if db and db.ncdm and db.ncdm.utility then
            local util = db.ncdm.utility

            -- Rebuild callback to refresh the tab after copying
            local function rebuildUtility()
                TeardownTabContent(tabContent)
                BuildUtilityTab(tabContent)
            end

            -- Enable checkbox
            local FORM_ROW = 32
            local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Utility Cooldowns Display", "enabled", util, RefreshNCDM)
            enableCheck:SetPoint("TOPLEFT", PAD, y)
            enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Anchor Below Essential toggle
            local anchorCheck = GUI:CreateFormCheckbox(tabContent, "Anchor Below Essential Rows", "anchorBelowEssential", util, function()
                RefreshNCDM()
                if _G.QUI_ApplyUtilityAnchor then
                    _G.QUI_ApplyUtilityAnchor()
                end
            end)
            anchorCheck:SetPoint("TOPLEFT", PAD, y)
            anchorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Anchor Gap slider
            local gapSlider = GUI:CreateFormSlider(tabContent, "Anchor Gap", -200, 200, 1, "anchorGap", util, function()
                RefreshNCDM()
                if _G.QUI_ApplyUtilityAnchor then
                    _G.QUI_ApplyUtilityAnchor()
                end
            end)
            gapSlider:SetPoint("TOPLEFT", PAD, y)
            gapSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Layout Direction dropdown
            util.layoutDirection = util.layoutDirection or "HORIZONTAL"
            local directionOptions = {
                {value = "HORIZONTAL", text = "Horizontal"},
                {value = "VERTICAL", text = "Vertical"},
            }
            local directionDropdown = GUI:CreateFormDropdown(tabContent, "Layout Direction", directionOptions, "layoutDirection", util, RefreshNCDM)
            directionDropdown:SetPoint("TOPLEFT", PAD, y)
            directionDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Hint text
            local hintText = GUI:CreateLabel(tabContent, "Tip: Set Icon Size to 100% in Edit Mode for best results.", 11, C.textMuted)
            hintText:SetPoint("TOPLEFT", PAD, y)
            hintText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            hintText:SetJustifyH("LEFT")
            y = y - 24
            tabContent._currentY = y

            -- Row 1
            if util.row1 then
                BuildRowSettings(tabContent, 1, util.row1, "Utility", util, rebuildUtility)
            end

            -- Row 2
            if util.row2 then
                BuildRowSettings(tabContent, 2, util.row2, "Utility", util, rebuildUtility)
            end

            -- Row 3
            if util.row3 then
                BuildRowSettings(tabContent, 3, util.row3, "Utility", util, rebuildUtility)
            end
        else
            local info = GUI:CreateLabel(tabContent, "NCDM Utility settings not found. Please reload UI.", 12, C.accentLight)
            info:SetPoint("TOPLEFT", PAD, y)
        end

        tabContent:SetHeight(math.abs(tabContent._currentY) + 50)
    end

    -- Build Buff sub-tab with customization options
    local function BuildBuffTab(tabContent)
        local PAD = 10
        local y = -10

        -- Set search context for widget auto-registration
        GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 4, subTabName = "Buff"})

        -- Ensure buff settings exist with all required fields
        if not db.ncdm then db.ncdm = {} end
        if not db.ncdm.buff then db.ncdm.buff = {} end

        -- Ensure all fields exist with defaults
        local buffData = db.ncdm.buff
        if buffData.enabled == nil then buffData.enabled = true end
        if buffData.iconSize == nil then buffData.iconSize = 42 end
        if buffData.borderSize == nil then buffData.borderSize = 2 end
        if buffData.shape == nil then buffData.shape = "square" end  -- DEPRECATED
        if buffData.aspectRatioCrop == nil then buffData.aspectRatioCrop = 1.0 end
        if buffData.growthDirection == nil then buffData.growthDirection = "CENTERED_HORIZONTAL" end
        if buffData.zoom == nil then buffData.zoom = 0 end
        if buffData.padding == nil then buffData.padding = 0 end
        if buffData.durationSize == nil then buffData.durationSize = 12 end
        if buffData.stackSize == nil then buffData.stackSize = 12 end
        if buffData.opacity == nil then buffData.opacity = 1.0 end

        -- Callback to refresh buff bar
        local function RefreshBuff()
            if _G.QUI_RefreshBuffBar then
                _G.QUI_RefreshBuffBar()
            end
        end

        -- Header
        local FORM_ROW = 32
        local header = GUI:CreateSectionHeader(tabContent, "Buff Icon Settings")
        header:SetPoint("TOPLEFT", PAD, y)
        y = y - 24

        local enableCb = GUI:CreateFormCheckbox(tabContent, "Enable Buff Icon Styling", "enabled", buffData, RefreshBuff)
        enableCb:SetPoint("TOPLEFT", PAD, y)
        enableCb:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local sizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 20, 80, 1, "iconSize", buffData, RefreshBuff)
        sizeSlider:SetPoint("TOPLEFT", PAD, y)
        sizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 8, 1, "borderSize", buffData, RefreshBuff)
        borderSlider:SetPoint("TOPLEFT", PAD, y)
        borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local zoomSlider = GUI:CreateFormSlider(tabContent, "Icon Zoom", 0, 0.2, 0.01, "zoom", buffData, RefreshBuff)
        zoomSlider:SetPoint("TOPLEFT", PAD, y)
        zoomSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local paddingSlider = GUI:CreateFormSlider(tabContent, "Icon Padding", -20, 20, 1, "padding", buffData, RefreshBuff)
        paddingSlider:SetPoint("TOPLEFT", PAD, y)
        paddingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local opacitySlider = GUI:CreateFormSlider(tabContent, "Buff Opacity", 0, 1.0, 0.05, "opacity", buffData, RefreshBuff)
        opacitySlider:SetPoint("TOPLEFT", PAD, y)
        opacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationSlider = GUI:CreateFormSlider(tabContent, "Duration Size", 8, 50, 1, "durationSize", buffData, RefreshBuff)
        durationSlider:SetPoint("TOPLEFT", PAD, y)
        durationSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local anchorOptions = {
            {value = "TOPLEFT", text = "Top Left"},
            {value = "TOP", text = "Top"},
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "LEFT", text = "Left"},
            {value = "CENTER", text = "Center"},
            {value = "RIGHT", text = "Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
            {value = "BOTTOM", text = "Bottom"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }

        local durationAnchorDD = GUI:CreateFormDropdown(tabContent, "Anchor Duration To", anchorOptions, "durationAnchor", buffData, RefreshBuff)
        durationAnchorDD:SetPoint("TOPLEFT", PAD, y)
        durationAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationXSlider = GUI:CreateFormSlider(tabContent, "Duration X Offset", -20, 20, 1, "durationOffsetX", buffData, RefreshBuff)
        durationXSlider:SetPoint("TOPLEFT", PAD, y)
        durationXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationYSlider = GUI:CreateFormSlider(tabContent, "Duration Y Offset", -20, 20, 1, "durationOffsetY", buffData, RefreshBuff)
        durationYSlider:SetPoint("TOPLEFT", PAD, y)
        durationYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackSlider = GUI:CreateFormSlider(tabContent, "Stack Size", 8, 50, 1, "stackSize", buffData, RefreshBuff)
        stackSlider:SetPoint("TOPLEFT", PAD, y)
        stackSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackAnchorDD = GUI:CreateFormDropdown(tabContent, "Anchor Stack To", anchorOptions, "stackAnchor", buffData, RefreshBuff)
        stackAnchorDD:SetPoint("TOPLEFT", PAD, y)
        stackAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackXSlider = GUI:CreateFormSlider(tabContent, "Stack X Offset", -20, 20, 1, "stackOffsetX", buffData, RefreshBuff)
        stackXSlider:SetPoint("TOPLEFT", PAD, y)
        stackXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackYSlider = GUI:CreateFormSlider(tabContent, "Stack Y Offset", -20, 20, 1, "stackOffsetY", buffData, RefreshBuff)
        stackYSlider:SetPoint("TOPLEFT", PAD, y)
        stackYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local growthDropdown = GUI:CreateFormDropdown(tabContent, "Growth Direction", {
            {value = "CENTERED_HORIZONTAL", text = "Centered"},
            {value = "UP", text = "Grow Up"},
            {value = "DOWN", text = "Grow Down"},
        }, "growthDirection", buffData, RefreshBuff)
        growthDropdown:SetPoint("TOPLEFT", PAD, y)
        growthDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeSlider = GUI:CreateFormSlider(tabContent, "Icon Shape", 1.0, 2.0, 0.01, "aspectRatioCrop", buffData, RefreshBuff)
        shapeSlider:SetPoint("TOPLEFT", PAD, y)
        shapeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeTip = GUI:CreateLabel(tabContent, "Higher values imply flatter icons.", 11, C.textMuted)
        shapeTip:SetPoint("TOPLEFT", PAD, y)
        shapeTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        shapeTip:SetJustifyH("LEFT")
        y = y - 20

        y = y - 10 -- Spacer

        local info = GUI:CreateLabel(tabContent, "Position the Buff Icons using Edit Mode (Esc > Edit Mode).", 11, C.textMuted)
        info:SetPoint("TOPLEFT", PAD, y)
        info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        info:SetJustifyH("LEFT")
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- TRACKED BAR SECTION
        -----------------------------------------------------------------------

        -- Ensure trackedBar settings exist with defaults
        if not db.ncdm.trackedBar then db.ncdm.trackedBar = {} end
        local trackedData = db.ncdm.trackedBar
        if trackedData.enabled == nil then trackedData.enabled = true end
        if trackedData.hideIcon == nil then trackedData.hideIcon = false end
        if trackedData.barHeight == nil then trackedData.barHeight = 24 end
        if trackedData.barWidth == nil then trackedData.barWidth = 200 end
        if trackedData.texture == nil then trackedData.texture = "Quazii v5" end
        if trackedData.useClassColor == nil then trackedData.useClassColor = true end
        if trackedData.barColor == nil then trackedData.barColor = {0.204, 0.827, 0.6, 1} end
        if trackedData.barOpacity == nil then trackedData.barOpacity = 1.0 end
        if trackedData.borderSize == nil then trackedData.borderSize = 1 end
        if trackedData.bgColor == nil then trackedData.bgColor = {0, 0, 0, 1} end
        if trackedData.bgOpacity == nil then trackedData.bgOpacity = 0.7 end
        if trackedData.textSize == nil then trackedData.textSize = 12 end
        if trackedData.spacing == nil then trackedData.spacing = 4 end
        if trackedData.growUp == nil then trackedData.growUp = true end
        if trackedData.hideText == nil then trackedData.hideText = false end
        -- Vertical bar settings
        if trackedData.orientation == nil then trackedData.orientation = "horizontal" end
        if trackedData.fillDirection == nil then trackedData.fillDirection = "up" end
        if trackedData.iconPosition == nil then trackedData.iconPosition = "top" end
        if trackedData.showTextOnVertical == nil then trackedData.showTextOnVertical = false end

        y = y - 10 -- Extra spacing before new section

        local trackedHeader = GUI:CreateSectionHeader(tabContent, "Tracked Bar")
        trackedHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - trackedHeader.gap

        -- Description text
        local trackedDesc = GUI:CreateLabel(tabContent, "Controls the appearance of buff duration bars for spells under 'Tracked Bars' of your CDM. Hint: Most players will opt to display buffs via the Buff Icon section above.", 11, C.textMuted)
        trackedDesc:SetPoint("TOPLEFT", PAD, y)
        trackedDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        trackedDesc:SetJustifyH("LEFT")
        trackedDesc:SetWordWrap(true)
        trackedDesc:SetHeight(30)
        y = y - 40

        -- Enable toggle
        local trackedEnable = GUI:CreateFormCheckbox(tabContent, "Enable Tracked Bar Styling", "enabled", trackedData, RefreshBuff)
        trackedEnable:SetPoint("TOPLEFT", PAD, y)
        trackedEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Hide Icon toggle
        local hideIconCheck = GUI:CreateFormCheckbox(tabContent, "Hide Icon", "hideIcon", trackedData, RefreshBuff)
        hideIconCheck:SetPoint("TOPLEFT", PAD, y)
        hideIconCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Height
        local heightSlider = GUI:CreateFormSlider(tabContent, "Bar Height", 2, 48, 1, "barHeight", trackedData, RefreshBuff)
        heightSlider:SetPoint("TOPLEFT", PAD, y)
        heightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Width
        local widthSlider = GUI:CreateFormSlider(tabContent, "Bar Width", 100, 400, 1, "barWidth", trackedData, RefreshBuff)
        widthSlider:SetPoint("TOPLEFT", PAD, y)
        widthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Texture
        local textureDropdown = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", trackedData, RefreshBuff)
        textureDropdown:SetPoint("TOPLEFT", PAD, y)
        textureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Forward reference for orientation change callback
        local updateVerticalStates

        -- Bar Orientation
        local orientationDropdown = GUI:CreateFormDropdown(tabContent, "Bar Orientation", {
            {value = "horizontal", text = "Horizontal"},
            {value = "vertical", text = "Vertical"},
        }, "orientation", trackedData, function()
            RefreshBuff()
            if updateVerticalStates then updateVerticalStates() end
            GUI:ShowConfirmation({
                title = "Reload Required",
                message = "Changing bar orientation requires a UI reload to take full effect.",
                acceptText = "Reload Now",
                cancelText = "Later",
                isDestructive = false,
                onAccept = function()
                    QUI:SafeReload()
                end,
            })
        end)
        orientationDropdown:SetPoint("TOPLEFT", PAD, y)
        orientationDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Stack Direction (renamed from Growth Direction, context-dependent)
        local growthDropdown = GUI:CreateFormDropdown(tabContent, "Stack Direction", {
            {value = true, text = "Up / Right"},
            {value = false, text = "Down / Left"},
        }, "growUp", trackedData, RefreshBuff)
        growthDropdown:SetPoint("TOPLEFT", PAD, y)
        growthDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackTip = GUI:CreateLabel(tabContent, "Up/Down for horizontal bars, Right/Left for vertical bars.", 11, C.textMuted)
        stackTip:SetPoint("TOPLEFT", PAD, y)
        stackTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        stackTip:SetJustifyH("LEFT")
        y = y - 20

        -- Fill Direction (Vertical only)
        local fillDropdown = GUI:CreateFormDropdown(tabContent, "Fill Direction (Vertical)", {
            {value = "up", text = "Fill Up"},
            {value = "down", text = "Fill Down"},
        }, "fillDirection", trackedData, RefreshBuff)
        fillDropdown:SetPoint("TOPLEFT", PAD, y)
        fillDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local fillTip = GUI:CreateLabel(tabContent, "Direction the progress bar fills as buff duration decreases.", 11, C.textMuted)
        fillTip:SetPoint("TOPLEFT", PAD, y)
        fillTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        fillTip:SetJustifyH("LEFT")
        y = y - 20

        -- Icon Position (Vertical only)
        local iconPosDropdown = GUI:CreateFormDropdown(tabContent, "Icon Position (Vertical)", {
            {value = "top", text = "Top"},
            {value = "bottom", text = "Bottom"},
        }, "iconPosition", trackedData, RefreshBuff)
        iconPosDropdown:SetPoint("TOPLEFT", PAD, y)
        iconPosDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconPosTip = GUI:CreateLabel(tabContent, "Where the spell icon appears on vertical bars.", 11, C.textMuted)
        iconPosTip:SetPoint("TOPLEFT", PAD, y)
        iconPosTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        iconPosTip:SetJustifyH("LEFT")
        y = y - 20

        -- Show Text (Vertical only)
        local showTextCheck = GUI:CreateFormCheckbox(tabContent, "Show Text (Vertical)", "showTextOnVertical", trackedData, RefreshBuff)
        showTextCheck:SetPoint("TOPLEFT", PAD, y)
        showTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textTip = GUI:CreateLabel(tabContent, "Text hidden by default on vertical bars. Enable for bars 48+ pixels wide.", 11, C.textMuted)
        textTip:SetPoint("TOPLEFT", PAD, y)
        textTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textTip:SetJustifyH("LEFT")
        y = y - 20

        -- UX: Dim vertical-only options when horizontal
        updateVerticalStates = function()
            local isVertical = trackedData.orientation == "vertical"
            local alpha = isVertical and 1.0 or 0.4
            fillDropdown:SetAlpha(alpha)
            iconPosDropdown:SetAlpha(alpha)
            showTextCheck:SetAlpha(alpha)
            -- Swap height/width labels based on orientation
            if heightSlider.label and widthSlider.label then
                if isVertical then
                    heightSlider.label:SetText("Bar Width")
                    widthSlider.label:SetText("Bar Length")
                else
                    heightSlider.label:SetText("Bar Height")
                    widthSlider.label:SetText("Bar Width")
                end
            end
        end
        updateVerticalStates()  -- Initial state

        -- Use Class Color
        local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", trackedData, RefreshBuff)
        classColorCheck:SetPoint("TOPLEFT", PAD, y)
        classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Color (fallback)
        local barColorPicker = GUI:CreateFormColorPicker(tabContent, "Bar Color (Fallback)", "barColor", trackedData, RefreshBuff)
        barColorPicker:SetPoint("TOPLEFT", PAD, y)
        barColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Opacity
        local barOpacitySlider = GUI:CreateFormSlider(tabContent, "Bar Opacity", 0, 1, 0.05, "barOpacity", trackedData, RefreshBuff)
        barOpacitySlider:SetPoint("TOPLEFT", PAD, y)
        barOpacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Border Size
        local trackedBorderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 4, 1, "borderSize", trackedData, RefreshBuff)
        trackedBorderSlider:SetPoint("TOPLEFT", PAD, y)
        trackedBorderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Background Color
        local bgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", trackedData, RefreshBuff)
        bgColorPicker:SetPoint("TOPLEFT", PAD, y)
        bgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Background Opacity
        local bgOpacitySlider = GUI:CreateFormSlider(tabContent, "Background Opacity", 0, 1, 0.1, "bgOpacity", trackedData, RefreshBuff)
        bgOpacitySlider:SetPoint("TOPLEFT", PAD, y)
        bgOpacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Text Size
        local trackedTextSlider = GUI:CreateFormSlider(tabContent, "Text Size", 8, 24, 1, "textSize", trackedData, RefreshBuff)
        trackedTextSlider:SetPoint("TOPLEFT", PAD, y)
        trackedTextSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Hide Text
        local hideTextCheck = GUI:CreateFormCheckbox(tabContent, "Hide Text", "hideText", trackedData, RefreshBuff)
        hideTextCheck:SetPoint("TOPLEFT", PAD, y)
        hideTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Spacing
        local spacingSlider = GUI:CreateFormSlider(tabContent, "Bar Spacing", 0, 20, 1, "spacing", trackedData, RefreshBuff)
        spacingSlider:SetPoint("TOPLEFT", PAD, y)
        spacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        tabContent:SetHeight(math.abs(y) + 20)
    end


    -- Build Powerbar general settings sub-section
    local function BuildPowerbarGeneralSettings(tabContent, ctx, y)
        local PAD = ctx.PAD
        local FORM_ROW = ctx.FORM_ROW
        local primary = ctx.primary
        local secondary = ctx.secondary
        local RefreshPowerBars = ctx.RefreshPowerBars

        -- =====================================================
        -- GENERAL SETTINGS
        -- =====================================================
        local generalHeader = GUI:CreateSectionHeader(tabContent, "General")
        generalHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - generalHeader.gap

        -- Reload prompt for enable/standalone toggles
        local function PromptResourceBarReload()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Changing resource bar settings requires a UI reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end

        -- Enable toggles
        local enablePrimary = GUI:CreateFormToggle(tabContent, "Enable Primary Class Resource Bar", "enabled", primary, PromptResourceBarReload)
        enablePrimary:SetPoint("TOPLEFT", PAD, y)
        enablePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local enableSecondary = GUI:CreateFormToggle(tabContent, "Enable Secondary Class Resource Bar", "enabled", secondary, PromptResourceBarReload)
        enableSecondary:SetPoint("TOPLEFT", PAD, y)
        enableSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Visibility mode dropdowns
        local visibilityOptions = {
            {value = "always",  text = "Always"},
            {value = "combat",  text = "In Combat"},
            {value = "hostile", text = "Hostile Target"},
        }

        local visPrimary = GUI:CreateFormDropdown(tabContent, "Primary Visibility", visibilityOptions, "visibility", primary, RefreshPowerBars)
        visPrimary:SetPoint("TOPLEFT", PAD, y)
        visPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local visSecondary = GUI:CreateFormDropdown(tabContent, "Secondary Visibility", visibilityOptions, "visibility", secondary, RefreshPowerBars)
        visSecondary:SetPoint("TOPLEFT", PAD, y)
        visSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Standalone toggles
        local standalonePrimary = GUI:CreateFormToggle(tabContent, "Primary Standalone Mode", "standaloneMode", primary, PromptResourceBarReload)
        standalonePrimary:SetPoint("TOPLEFT", PAD, y)
        standalonePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local standaloneSecondary = GUI:CreateFormToggle(tabContent, "Secondary Standalone Mode", "standaloneMode", secondary, PromptResourceBarReload)
        standaloneSecondary:SetPoint("TOPLEFT", PAD, y)
        standaloneSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local secondaryImptText = GUI:CreateLabel(tabContent, "IMPT: If you choose NOT to display a Primary Bar, and ONLY want a Secondary Bar, toggle this ON. Else it will not show.", 11, C.warning)
        secondaryImptText:SetPoint("TOPLEFT", PAD, y)
        secondaryImptText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        secondaryImptText:SetJustifyH("LEFT")
        y = y - 25

        local standaloneDesc = GUI:CreateLabel(tabContent, "Standalone Mode: Bar won't fade or hide with CDM visibility. Use if you don't use Essential/Utility cooldown displays.", 11, C.textMuted)
        standaloneDesc:SetPoint("TOPLEFT", PAD, y)
        standaloneDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        standaloneDesc:SetJustifyH("LEFT")
        y = y - 25

        -- Unthrottled CPU Use toggle (affects both primary and secondary)
        local unthrottledToggle = GUI:CreateFormToggle(tabContent, "Unthrottled CPU Use", "unthrottledCPU", primary, RefreshPowerBars)
        unthrottledToggle:SetPoint("TOPLEFT", PAD, y)
        unthrottledToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local unthrottledDesc = GUI:CreateLabel(tabContent, "Remove throttle on the number of updates per second. Toggle on for smoother updates, but higher CPU Usage.", 11, C.textMuted)
        unthrottledDesc:SetPoint("TOPLEFT", PAD, y)
        unthrottledDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        unthrottledDesc:SetJustifyH("LEFT")
        y = y - 25

        return y
    end

    -- Build Primary power bar configuration sub-section
    local function BuildPrimaryPowerbarConfig(tabContent, ctx, y)
        local PAD = ctx.PAD
        local FORM_ROW = ctx.FORM_ROW
        local primary = ctx.primary
        local RefreshPowerBars = ctx.RefreshPowerBars
        local CalculateSnapPosition = ctx.CalculateSnapPosition

        -- Forward declare slider references
        local widthPrimarySlider
        local yOffsetPrimarySlider

        -- =====================================================
        -- PRIMARY POWER BAR SECTION
        -- =====================================================
        local primaryHeader = GUI:CreateSectionHeader(tabContent, "Primary Class Resource Bar")
        primaryHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - primaryHeader.gap

        local primaryDesc = GUI:CreateLabel(tabContent, "Customize individual resource colors in the Resource Colors section at the bottom. Applied when 'Use Resource Type Color' is enabled.", 11, C.textMuted)
        primaryDesc:SetPoint("TOPLEFT", PAD, y)
        primaryDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        primaryDesc:SetJustifyH("LEFT")
        y = y - 20

        local primaryWarning = GUI:CreateLabel(tabContent, "Designed for horizontal layouts used by most players. Vertical mode requires extra setup (row offsets, orientation toggles).", 11, C.warning)
        primaryWarning:SetPoint("TOPLEFT", PAD, y)
        primaryWarning:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        primaryWarning:SetJustifyH("LEFT")
        y = y - 20

        -- Orientation dropdown
        local orientationOptions = {
            {value = "HORIZONTAL", text = "Horizontal"},
            {value = "VERTICAL", text = "Vertical"},
        }
        local orientationPrimary = GUI:CreateFormDropdown(tabContent, "Orientation", orientationOptions, "orientation", primary, RefreshPowerBars)
        orientationPrimary:SetPoint("TOPLEFT", PAD, y)
        orientationPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Snap to Essential button (form style with label)
        local snapPrimaryContainer = CreateFrame("Frame", nil, tabContent)
        snapPrimaryContainer:SetHeight(FORM_ROW)
        snapPrimaryContainer:SetPoint("TOPLEFT", PAD, y)
        snapPrimaryContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local snapPrimaryLabel = snapPrimaryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapPrimaryLabel:SetPoint("LEFT", 0, 0)
        snapPrimaryLabel:SetText("Quick Position")
        snapPrimaryLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local snapPrimaryBtn = CreateFrame("Button", nil, snapPrimaryContainer, "BackdropTemplate")
        snapPrimaryBtn:SetSize(115, 24)
        snapPrimaryBtn:SetPoint("LEFT", snapPrimaryContainer, "LEFT", 180, 0)
        local pxSnapPrimary = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(snapPrimaryBtn)) or 1
        snapPrimaryBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxSnapPrimary,
        })
        snapPrimaryBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapPrimaryBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapPrimaryText = snapPrimaryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapPrimaryText:SetPoint("CENTER")
        snapPrimaryText:SetText("Snap to Essentials")
        snapPrimaryText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapPrimaryBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapPrimaryBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapPrimaryBtn:SetScript("OnClick", function()
            -- Force CDM refresh to ensure __cdmIconWidth is current
            if _G.QUI_RefreshNCDM then
                _G.QUI_RefreshNCDM()
            end
            local offsetX, offsetY, width, err = CalculateSnapPosition(_G.EssentialCooldownViewer, primary, "essential", primary.orientation)
            if err then
                print(err)
                return
            end

            primary.offsetX = offsetX
            primary.offsetY = offsetY
            primary.width = width
            primary.autoAttach = false
            primary.useRawPixels = true
            RefreshPowerBars()

            if widthPrimarySlider and widthPrimarySlider.SetValue then
                widthPrimarySlider.SetValue(primary.width, true)
            end
            if yOffsetPrimarySlider and yOffsetPrimarySlider.SetValue then
                yOffsetPrimarySlider.SetValue(primary.offsetY, true)
            end
        end)

        -- Snap to Utility button (side by side with Essential)
        local snapUtilityBtn = CreateFrame("Button", nil, snapPrimaryContainer, "BackdropTemplate")
        snapUtilityBtn:SetSize(115, 24)
        snapUtilityBtn:SetPoint("LEFT", snapPrimaryBtn, "RIGHT", 5, 0)
        local pxSnapUtil = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(snapUtilityBtn)) or 1
        snapUtilityBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxSnapUtil,
        })
        snapUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapUtilityText = snapUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapUtilityText:SetPoint("CENTER")
        snapUtilityText:SetText("Snap to Utility")
        snapUtilityText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapUtilityBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapUtilityBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapUtilityBtn:SetScript("OnClick", function()
            -- Force CDM refresh to ensure dimensions are current
            if _G.QUI_RefreshNCDM then
                _G.QUI_RefreshNCDM()
            end
            local offsetX, offsetY, width, err = CalculateSnapPosition(_G.UtilityCooldownViewer, primary, "utility", primary.orientation)
            if err then
                print(err)
                return
            end

            primary.offsetX = offsetX
            primary.offsetY = offsetY
            primary.width = width
            primary.autoAttach = false
            primary.useRawPixels = true
            RefreshPowerBars()

            if widthPrimarySlider and widthPrimarySlider.SetValue then
                widthPrimarySlider.SetValue(primary.width, true)
            end
            if yOffsetPrimarySlider and yOffsetPrimarySlider.SetValue then
                yOffsetPrimarySlider.SetValue(primary.offsetY, true)
            end
        end)
        y = y - FORM_ROW

        -- Lock buttons (auto-resize when CDM changes)
        local lockContainer = CreateFrame("Frame", nil, tabContent)
        lockContainer:SetHeight(FORM_ROW)
        lockContainer:SetPoint("TOPLEFT", PAD, y)
        lockContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local lockLabel = lockContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockLabel:SetPoint("LEFT", 0, 0)
        lockLabel:SetText("Auto-Resize")
        lockLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Essentials button
        local lockEssentialBtn = CreateFrame("Button", nil, lockContainer, "BackdropTemplate")
        lockEssentialBtn:SetSize(115, 24)
        lockEssentialBtn:SetPoint("LEFT", lockContainer, "LEFT", 180, 0)
        local pxLockEss = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(lockEssentialBtn)) or 1
        lockEssentialBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxLockEss,
        })
        lockEssentialBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)

        local lockEssentialText = lockEssentialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockEssentialText:SetPoint("CENTER")
        lockEssentialText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Utility button
        local lockUtilityBtn = CreateFrame("Button", nil, lockContainer, "BackdropTemplate")
        lockUtilityBtn:SetSize(115, 24)
        lockUtilityBtn:SetPoint("LEFT", lockEssentialBtn, "RIGHT", 5, 0)
        local pxLockUtil = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(lockUtilityBtn)) or 1
        lockUtilityBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxLockUtil,
        })
        lockUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)

        local lockUtilityText = lockUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockUtilityText:SetPoint("CENTER")
        lockUtilityText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local function UpdateLockButtonStates()
            -- Essential button state
            if primary.lockedToEssential then
                lockEssentialText:SetText("Unlock Essential")
                lockEssentialBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockEssentialText:SetText("Lock to Essential")
                lockEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Utility button state
            if primary.lockedToUtility then
                lockUtilityText:SetText("Unlock Utility")
                lockUtilityBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockUtilityText:SetText("Lock to Utility")
                lockUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Disable Width slider when locked
            if widthPrimarySlider and widthPrimarySlider.SetEnabled then
                widthPrimarySlider:SetEnabled(not primary.lockedToEssential and not primary.lockedToUtility)
            end
        end
        UpdateLockButtonStates()

        -- Essential button hover
        lockEssentialBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockEssentialBtn:SetScript("OnLeave", function(self)
            if not primary.lockedToEssential then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)

        -- Utility button hover
        lockUtilityBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockUtilityBtn:SetScript("OnLeave", function(self)
            if not primary.lockedToUtility then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)

        -- Lock to Essentials click handler
        lockEssentialBtn:SetScript("OnClick", function()
            if primary.lockedToEssential then
                -- Unlock
                primary.lockedToEssential = false
                UpdateLockButtonStates()
            else
                -- Lock: do snap first, then enable lock
                if _G.QUI_RefreshNCDM then
                    _G.QUI_RefreshNCDM()
                end
                local offsetX, offsetY, width, err = CalculateSnapPosition(_G.EssentialCooldownViewer, primary, "essential", primary.orientation)
                if err then
                    print(err)
                    return
                end

                primary.offsetX = offsetX
                primary.offsetY = offsetY
                primary.width = width
                primary.autoAttach = false
                primary.useRawPixels = true
                primary.lockedToEssential = true
                primary.lockedToUtility = false  -- Mutually exclusive

                RefreshPowerBars()
                UpdateLockButtonStates()

                if widthPrimarySlider and widthPrimarySlider.SetValue then
                    widthPrimarySlider.SetValue(primary.width, true)
                end
                if yOffsetPrimarySlider and yOffsetPrimarySlider.SetValue then
                    yOffsetPrimarySlider.SetValue(primary.offsetY, true)
                end
            end
        end)

        -- Lock to Utility click handler
        lockUtilityBtn:SetScript("OnClick", function()
            if primary.lockedToUtility then
                -- Unlock
                primary.lockedToUtility = false
                UpdateLockButtonStates()
            else
                -- Lock: do snap first, then enable lock
                if _G.QUI_RefreshNCDM then
                    _G.QUI_RefreshNCDM()
                end
                local offsetX, offsetY, width, err = CalculateSnapPosition(_G.UtilityCooldownViewer, primary, "utility", primary.orientation)
                if err then
                    print(err)
                    return
                end

                primary.offsetX = offsetX
                primary.offsetY = offsetY
                primary.width = width
                primary.autoAttach = false
                primary.useRawPixels = true
                primary.lockedToUtility = true
                primary.lockedToEssential = false  -- Mutually exclusive

                RefreshPowerBars()
                UpdateLockButtonStates()

                if widthPrimarySlider and widthPrimarySlider.SetValue then
                    widthPrimarySlider.SetValue(primary.width, true)
                end
                if yOffsetPrimarySlider and yOffsetPrimarySlider.SetValue then
                    yOffsetPrimarySlider.SetValue(primary.offsetY, true)
                end
            end
        end)
        y = y - FORM_ROW

        -- Color options (form style) - radio-button behavior: clicking one turns off the others
        local customColorPickerPrimary

        local powerColorPrimary = GUI:CreateFormCheckbox(tabContent, "Use Resource Type Color", "usePowerColor", primary, function()
            if primary.usePowerColor then
                primary.useClassColor = false
                primary.useCustomColor = false
                primary.colorMode = "power"
            else
                -- Fallback: if turning off and nothing else is on, re-enable this
                if not primary.useClassColor and not primary.useCustomColor then
                    primary.usePowerColor = true
                end
            end
            if customColorPickerPrimary then
                customColorPickerPrimary:SetEnabled(primary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        powerColorPrimary:SetPoint("TOPLEFT", PAD, y)
        powerColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local resourceColorDescPrimary = GUI:CreateLabel(tabContent, "Uses per-resource colors from the Resource Colors section below.", 11)
        resourceColorDescPrimary:SetPoint("TOPLEFT", PAD, y + 4)
        resourceColorDescPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        resourceColorDescPrimary:SetJustifyH("LEFT")
        resourceColorDescPrimary:SetTextColor(0.6, 0.6, 0.6)
        y = y - FORM_ROW

        local classColorPrimary = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", primary, function()
            if primary.useClassColor then
                primary.usePowerColor = false
                primary.useCustomColor = false
                primary.colorMode = "class"
            else
                -- Fallback: if turning off and nothing else is on, enable Resource Type Color
                if not primary.usePowerColor and not primary.useCustomColor then
                    primary.usePowerColor = true
                end
            end
            if customColorPickerPrimary then
                customColorPickerPrimary:SetEnabled(primary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        classColorPrimary:SetPoint("TOPLEFT", PAD, y)
        classColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local bgColorPrimary = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", primary, RefreshPowerBars)
        bgColorPrimary:SetPoint("TOPLEFT", PAD, y)
        bgColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local customColorOverridePrimary = GUI:CreateFormCheckbox(tabContent, "Custom Color Override", "useCustomColor", primary, function()
            if primary.useCustomColor then
                primary.usePowerColor = false
                primary.useClassColor = false
                primary.colorMode = "custom"
            else
                -- Fallback: if turning off and nothing else is on, enable Resource Type Color
                if not primary.usePowerColor and not primary.useClassColor then
                    primary.usePowerColor = true
                end
            end
            if customColorPickerPrimary then
                customColorPickerPrimary:SetEnabled(primary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        customColorOverridePrimary:SetPoint("TOPLEFT", PAD, y)
        customColorOverridePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        customColorPickerPrimary = GUI:CreateFormColorPicker(tabContent, "Custom Color", "customColor", primary, RefreshPowerBars)
        customColorPickerPrimary:SetPoint("TOPLEFT", PAD, y)
        customColorPickerPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        customColorPickerPrimary:SetEnabled(primary.useCustomColor)
        y = y - FORM_ROW

        -- Text display options
        local showTextPrimary = GUI:CreateFormCheckbox(tabContent, "Show Number", "showText", primary, RefreshPowerBars)
        showTextPrimary:SetPoint("TOPLEFT", PAD, y)
        showTextPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showPercentPrimary = GUI:CreateFormCheckbox(tabContent, "Show as Percent", "showPercent", primary, RefreshPowerBars)
        showPercentPrimary:SetPoint("TOPLEFT", PAD, y)
        showPercentPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Tick marks
        local showTicksPrimary = GUI:CreateFormCheckbox(tabContent, "Show Tick Marks", "showTicks", primary, RefreshPowerBars)
        showTicksPrimary:SetPoint("TOPLEFT", PAD, y)
        showTicksPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tickThicknessPrimary = GUI:CreateFormSlider(tabContent, "Tick Thickness", 1, 4, 1, "tickThickness", primary, RefreshPowerBars)
        tickThicknessPrimary:SetPoint("TOPLEFT", PAD, y)
        tickThicknessPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tickColorPrimary = GUI:CreateFormColorPicker(tabContent, "Tick Color", "tickColor", primary, RefreshPowerBars)
        tickColorPrimary:SetPoint("TOPLEFT", PAD, y)
        tickColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Size sliders (form style)
        widthPrimarySlider = GUI:CreateFormSlider(tabContent, "Width", 0, 2000, 1, "width", primary, RefreshPowerBars)
        widthPrimarySlider:SetPoint("TOPLEFT", PAD, y)
        widthPrimarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widthPrimarySlider:SetEnabled(not primary.lockedToEssential and not primary.lockedToUtility)  -- Disabled when locked
        y = y - FORM_ROW

        local heightPrimary = GUI:CreateFormSlider(tabContent, "Height", 1, 100, 1, "height", primary, RefreshPowerBars)
        heightPrimary:SetPoint("TOPLEFT", PAD, y)
        heightPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderPrimary = GUI:CreateFormSlider(tabContent, "Border Size", 0, 8, 1, "borderSize", primary, RefreshPowerBars)
        borderPrimary:SetPoint("TOPLEFT", PAD, y)
        borderPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Position sliders
        local xOffsetPrimarySlider = GUI:CreateFormSlider(tabContent, "X Offset", -1000, 1000, 1, "offsetX", primary, RefreshPowerBars)
        xOffsetPrimarySlider:SetPoint("TOPLEFT", PAD, y)
        xOffsetPrimarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        yOffsetPrimarySlider = GUI:CreateFormSlider(tabContent, "Y Offset", -1000, 1000, 1, "offsetY", primary, RefreshPowerBars)
        yOffsetPrimarySlider:SetPoint("TOPLEFT", PAD, y)
        yOffsetPrimarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Register sliders for real-time sync during Edit Mode
        if QUICore and QUICore.RegisterPowerBarEditModeSliders then
            QUICore:RegisterPowerBarEditModeSliders("primary", xOffsetPrimarySlider, yOffsetPrimarySlider)
        end

        -- Text sliders
        local textSizePrimary = GUI:CreateFormSlider(tabContent, "Text Size", 8, 50, 1, "textSize", primary, RefreshPowerBars)
        textSizePrimary:SetPoint("TOPLEFT", PAD, y)
        textSizePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textXPrimary = GUI:CreateFormSlider(tabContent, "Text X Offset", -500, 500, 1, "textX", primary, RefreshPowerBars)
        textXPrimary:SetPoint("TOPLEFT", PAD, y)
        textXPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textYPrimary = GUI:CreateFormSlider(tabContent, "Text Y Offset", -500, 500, 1, "textY", primary, RefreshPowerBars)
        textYPrimary:SetPoint("TOPLEFT", PAD, y)
        textYPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Text color settings
        local textCustomColorPrimary  -- Forward declare for mutual reference

        local textUseClassColorPrimary = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Text", "textUseClassColor", primary, function()
            if textCustomColorPrimary then
                textCustomColorPrimary:SetEnabled(not primary.textUseClassColor)
            end
            RefreshPowerBars()
        end)
        textUseClassColorPrimary:SetPoint("TOPLEFT", PAD, y)
        textUseClassColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        textCustomColorPrimary = GUI:CreateFormColorPicker(tabContent, "Custom Text Color", "textCustomColor", primary, RefreshPowerBars)
        textCustomColorPrimary:SetPoint("TOPLEFT", PAD, y)
        textCustomColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textCustomColorPrimary:SetEnabled(not primary.textUseClassColor)  -- Initial state
        y = y - FORM_ROW

        local texturePrimary = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", primary, RefreshPowerBars)
        texturePrimary:SetPoint("TOPLEFT", PAD, y)
        texturePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        return y
    end

    -- Build Secondary power bar configuration sub-section
    local function BuildSecondaryPowerbarConfig(tabContent, ctx, y)
        local PAD = ctx.PAD
        local FORM_ROW = ctx.FORM_ROW
        local secondary = ctx.secondary
        local RefreshPowerBars = ctx.RefreshPowerBars
        local CalculateSnapPosition = ctx.CalculateSnapPosition

        -- Forward declare slider references
        local widthSecondarySlider
        local yOffsetSecondarySlider

        -- =====================================================
        -- SECONDARY POWER BAR SECTION
        -- =====================================================
        local secondaryHeader = GUI:CreateSectionHeader(tabContent, "Secondary Class Resource Bar")
        secondaryHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - secondaryHeader.gap

        local secondaryDesc = GUI:CreateLabel(tabContent, "Customize individual resource colors in the Resource Colors section at the bottom. Applied when 'Use Resource Type Color' is enabled.", 11, C.textMuted)
        secondaryDesc:SetPoint("TOPLEFT", PAD, y)
        secondaryDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        secondaryDesc:SetJustifyH("LEFT")
        y = y - 20

        local secondaryWarning = GUI:CreateLabel(tabContent, "Designed for horizontal layouts used by most players. Vertical mode requires extra setup (row offsets, orientation toggles).", 11, C.warning)
        secondaryWarning:SetPoint("TOPLEFT", PAD, y)
        secondaryWarning:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        secondaryWarning:SetJustifyH("LEFT")
        y = y - 20

        -- Orientation dropdown
        local orientationOptionsSecondary = {
            {value = "HORIZONTAL", text = "Horizontal"},
            {value = "VERTICAL", text = "Vertical"},
        }
        local orientationSecondary = GUI:CreateFormDropdown(tabContent, "Orientation", orientationOptionsSecondary, "orientation", secondary, RefreshPowerBars)
        orientationSecondary:SetPoint("TOPLEFT", PAD, y)
        orientationSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Quick Position row with 3 buttons: Snap to Essentials, Snap to Utility, Snap to Primary
        local snapSecondaryContainer = CreateFrame("Frame", nil, tabContent)
        snapSecondaryContainer:SetHeight(FORM_ROW)
        snapSecondaryContainer:SetPoint("TOPLEFT", PAD, y)
        snapSecondaryContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local snapSecondaryLabel = snapSecondaryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapSecondaryLabel:SetPoint("LEFT", 0, 0)
        snapSecondaryLabel:SetText("Quick Position")
        snapSecondaryLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Snap to Essentials button
        local snapSecEssentialBtn = CreateFrame("Button", nil, snapSecondaryContainer, "BackdropTemplate")
        snapSecEssentialBtn:SetSize(100, 24)
        snapSecEssentialBtn:SetPoint("LEFT", snapSecondaryContainer, "LEFT", 180, 0)
        local pxSnapSecEss = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(snapSecEssentialBtn)) or 1
        snapSecEssentialBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxSnapSecEss,
        })
        snapSecEssentialBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapSecEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapSecEssentialText = snapSecEssentialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapSecEssentialText:SetPoint("CENTER")
        snapSecEssentialText:SetText("Essentials")
        snapSecEssentialText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapSecEssentialBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapSecEssentialBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapSecEssentialBtn:SetScript("OnClick", function()
            if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
            local offsetX, offsetY, width, err = CalculateSnapPosition(_G.EssentialCooldownViewer, secondary, "essential", secondary.orientation)
            if err then
                print(err)
                return
            end

            secondary.lockedBaseX = offsetX
            secondary.lockedBaseY = offsetY
            secondary.width = width
            secondary.offsetX = 0  -- Reset user adjustment
            secondary.offsetY = 0
            secondary.autoAttach = false
            secondary.useRawPixels = true
            RefreshPowerBars()
            if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
            if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
        end)

        -- Snap to Utility button
        local snapSecUtilityBtn = CreateFrame("Button", nil, snapSecondaryContainer, "BackdropTemplate")
        snapSecUtilityBtn:SetSize(100, 24)
        snapSecUtilityBtn:SetPoint("LEFT", snapSecEssentialBtn, "RIGHT", 5, 0)
        local pxSnapSecUtil = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(snapSecUtilityBtn)) or 1
        snapSecUtilityBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxSnapSecUtil,
        })
        snapSecUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapSecUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapSecUtilityText = snapSecUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapSecUtilityText:SetPoint("CENTER")
        snapSecUtilityText:SetText("Utility")
        snapSecUtilityText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapSecUtilityBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapSecUtilityBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapSecUtilityBtn:SetScript("OnClick", function()
            if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
            local offsetX, offsetY, width, err = CalculateSnapPosition(_G.UtilityCooldownViewer, secondary, "utility", secondary.orientation)
            if err then
                print(err)
                return
            end

            secondary.lockedBaseX = offsetX
            secondary.lockedBaseY = offsetY
            secondary.width = width
            secondary.offsetX = 0  -- Reset user adjustment
            secondary.offsetY = 0
            secondary.autoAttach = false
            secondary.useRawPixels = true
            RefreshPowerBars()
            if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
            if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
        end)

        -- Snap to Primary button
        local snapSecPrimaryBtn = CreateFrame("Button", nil, snapSecondaryContainer, "BackdropTemplate")
        snapSecPrimaryBtn:SetSize(100, 24)
        snapSecPrimaryBtn:SetPoint("LEFT", snapSecUtilityBtn, "RIGHT", 5, 0)
        local pxSnapSecPri = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(snapSecPrimaryBtn)) or 1
        snapSecPrimaryBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxSnapSecPri,
        })
        snapSecPrimaryBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapSecPrimaryBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapSecPrimaryText = snapSecPrimaryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapSecPrimaryText:SetPoint("CENTER")
        snapSecPrimaryText:SetText("Primary")
        snapSecPrimaryText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapSecPrimaryBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapSecPrimaryBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapSecPrimaryBtn:SetScript("OnClick", function()
            local primaryBar = QUICore and QUICore.powerBar
            local primaryCfg = QUICore and QUICore.db and QUICore.db.profile.powerBar
            if primaryBar and primaryBar:IsShown() and primaryCfg then
                local primaryCenterX, primaryCenterY = primaryBar:GetCenter()
                local screenCenterX, screenCenterY = UIParent:GetCenter()
                if primaryCenterX and primaryCenterY and screenCenterX and screenCenterY then
                    primaryCenterX = math.floor(primaryCenterX + 0.5)
                    primaryCenterY = math.floor(primaryCenterY + 0.5)
                    screenCenterX = math.floor(screenCenterX + 0.5)
                    screenCenterY = math.floor(screenCenterY + 0.5)
                    local primaryHeight = primaryCfg.height or 8
                    local primaryWidth = primaryCfg.width or primaryBar:GetWidth() or 300
                    local primaryBorderSize = primaryCfg.borderSize or 1
                    local secondaryHeight = secondary.height or 8
                    local secondaryBorderSize = secondary.borderSize or 1
                    local isVertical = secondary.orientation == "VERTICAL"

                    if isVertical then
                        -- Vertical secondary: goes to the RIGHT of Primary
                        local primaryActualWidth = primaryBar:GetWidth()
                        local primaryVisualRight = primaryCenterX + (primaryActualWidth / 2)
                        local secondaryBarCenterX = primaryVisualRight + (secondaryHeight / 2)
                        local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                        secondary.lockedBaseX = math.floor(secondaryBarCenterX - screenCenterX + 0.5)
                        secondary.lockedBaseY = math.floor(primaryCenterY - screenCenterY + 0.5)
                        secondary.width = math.floor(targetWidth + 0.5)
                    else
                        -- Horizontal bar: Secondary goes ABOVE Primary
                        local primaryVisualTop = primaryCenterY + (primaryHeight / 2) + primaryBorderSize
                        local secondaryBarCenterY = primaryVisualTop + (secondaryHeight / 2) + secondaryBorderSize
                        local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                        secondary.lockedBaseY = math.floor(secondaryBarCenterY - screenCenterY + 0.5) - 1
                        secondary.lockedBaseX = math.floor(primaryCenterX - screenCenterX + 0.5)
                        secondary.width = math.floor(targetWidth + 0.5)
                    end

                    secondary.offsetX = 0  -- Reset user adjustment
                    secondary.offsetY = 0
                    secondary.autoAttach = false
                    secondary.useRawPixels = true
                    RefreshPowerBars()
                    if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                    if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
                else
                    print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                end
            else
                print("|cFF56D1FFQUI:|r Primary Class Resource Bar not found or not visible. Enable it first.")
            end
        end)
        y = y - FORM_ROW

        -- Auto-Resize row with 3 buttons: Lock to Essential, Lock to Utility, Lock to Primary
        local lockSecContainer = CreateFrame("Frame", nil, tabContent)
        lockSecContainer:SetHeight(FORM_ROW)
        lockSecContainer:SetPoint("TOPLEFT", PAD, y)
        lockSecContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local lockSecLabel = lockSecContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockSecLabel:SetPoint("LEFT", 0, 0)
        lockSecLabel:SetText("Auto-Resize")
        lockSecLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Essential button
        local lockSecEssentialBtn = CreateFrame("Button", nil, lockSecContainer, "BackdropTemplate")
        lockSecEssentialBtn:SetSize(100, 24)
        lockSecEssentialBtn:SetPoint("LEFT", lockSecContainer, "LEFT", 180, 0)
        local pxLockSecEss = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(lockSecEssentialBtn)) or 1
        lockSecEssentialBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxLockSecEss,
        })
        lockSecEssentialBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        lockSecEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local lockSecEssentialText = lockSecEssentialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockSecEssentialText:SetPoint("CENTER")
        lockSecEssentialText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Utility button
        local lockSecUtilityBtn = CreateFrame("Button", nil, lockSecContainer, "BackdropTemplate")
        lockSecUtilityBtn:SetSize(100, 24)
        lockSecUtilityBtn:SetPoint("LEFT", lockSecEssentialBtn, "RIGHT", 5, 0)
        local pxLockSecUtil = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(lockSecUtilityBtn)) or 1
        lockSecUtilityBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxLockSecUtil,
        })
        lockSecUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        lockSecUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local lockSecUtilityText = lockSecUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockSecUtilityText:SetPoint("CENTER")
        lockSecUtilityText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Primary button
        local lockSecPrimaryBtn = CreateFrame("Button", nil, lockSecContainer, "BackdropTemplate")
        lockSecPrimaryBtn:SetSize(100, 24)
        lockSecPrimaryBtn:SetPoint("LEFT", lockSecUtilityBtn, "RIGHT", 5, 0)
        local pxLockSecPri = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(lockSecPrimaryBtn)) or 1
        lockSecPrimaryBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxLockSecPri,
        })
        lockSecPrimaryBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        lockSecPrimaryBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local lockSecPrimaryText = lockSecPrimaryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockSecPrimaryText:SetPoint("CENTER")
        lockSecPrimaryText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Function to update lock button states (visual + width slider)
        local function UpdateSecLockButtonStates()
            -- Essential button state
            if secondary.lockedToEssential then
                lockSecEssentialText:SetText("Unlock")
                lockSecEssentialBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockSecEssentialText:SetText("Essential")
                lockSecEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Utility button state
            if secondary.lockedToUtility then
                lockSecUtilityText:SetText("Unlock")
                lockSecUtilityBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockSecUtilityText:SetText("Utility")
                lockSecUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Primary button state
            if secondary.lockedToPrimary then
                lockSecPrimaryText:SetText("Unlock")
                lockSecPrimaryBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockSecPrimaryText:SetText("Primary")
                lockSecPrimaryBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Disable Width slider when any lock is active
            if widthSecondarySlider and widthSecondarySlider.SetEnabled then
                widthSecondarySlider:SetEnabled(not secondary.lockedToEssential and not secondary.lockedToUtility and not secondary.lockedToPrimary)
            end
        end

        -- Hover effects (preserve lock state color on leave)
        lockSecEssentialBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockSecEssentialBtn:SetScript("OnLeave", function(self)
            if not secondary.lockedToEssential then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)
        lockSecUtilityBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockSecUtilityBtn:SetScript("OnLeave", function(self)
            if not secondary.lockedToUtility then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)
        lockSecPrimaryBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockSecPrimaryBtn:SetScript("OnLeave", function(self)
            if not secondary.lockedToPrimary then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)

        -- Lock to Essential click handler
        lockSecEssentialBtn:SetScript("OnClick", function()
            if secondary.lockedToEssential then
                secondary.lockedToEssential = false
                UpdateSecLockButtonStates()
            else
                if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
                local offsetX, offsetY, width, err = CalculateSnapPosition(_G.EssentialCooldownViewer, secondary, "essential", secondary.orientation)
                if err then
                    print(err)
                    return
                end

                secondary.lockedBaseX = offsetX
                secondary.lockedBaseY = offsetY
                secondary.width = width
                secondary.offsetX = 0  -- Reset user adjustment
                secondary.offsetY = 0
                secondary.autoAttach = false
                secondary.useRawPixels = true
                secondary.lockedToEssential = true
                secondary.lockedToUtility = false
                secondary.lockedToPrimary = false
                RefreshPowerBars()
                UpdateSecLockButtonStates()
                if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
            end
        end)

        -- Lock to Utility click handler
        lockSecUtilityBtn:SetScript("OnClick", function()
            if secondary.lockedToUtility then
                secondary.lockedToUtility = false
                UpdateSecLockButtonStates()
            else
                if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
                local offsetX, offsetY, width, err = CalculateSnapPosition(_G.UtilityCooldownViewer, secondary, "utility", secondary.orientation)
                if err then
                    print(err)
                    return
                end

                secondary.lockedBaseX = offsetX
                secondary.lockedBaseY = offsetY
                secondary.width = width
                secondary.offsetX = 0  -- Reset user adjustment
                secondary.offsetY = 0
                secondary.autoAttach = false
                secondary.useRawPixels = true
                secondary.lockedToUtility = true
                secondary.lockedToEssential = false
                secondary.lockedToPrimary = false
                RefreshPowerBars()
                UpdateSecLockButtonStates()
                if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
            end
        end)

        -- Lock to Primary click handler
        lockSecPrimaryBtn:SetScript("OnClick", function()
            if secondary.lockedToPrimary then
                secondary.lockedToPrimary = false
                UpdateSecLockButtonStates()
            else
                local primaryBar = QUICore and QUICore.powerBar
                local primaryCfg = QUICore and QUICore.db and QUICore.db.profile.powerBar
                if primaryBar and primaryBar:IsShown() and primaryCfg then
                    local primaryCenterX, primaryCenterY = primaryBar:GetCenter()
                    local screenCenterX, screenCenterY = UIParent:GetCenter()
                    if primaryCenterX and primaryCenterY and screenCenterX and screenCenterY then
                        primaryCenterX = math.floor(primaryCenterX + 0.5)
                        primaryCenterY = math.floor(primaryCenterY + 0.5)
                        screenCenterX = math.floor(screenCenterX + 0.5)
                        screenCenterY = math.floor(screenCenterY + 0.5)
                        local primaryHeight = primaryCfg.height or 8
                        local primaryWidth = primaryCfg.width or primaryBar:GetWidth() or 300
                        local primaryBorderSize = primaryCfg.borderSize or 1
                        local secondaryHeight = secondary.height or 8
                        local secondaryBorderSize = secondary.borderSize or 1
                        local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                        secondary.width = math.floor(targetWidth + 0.5)
                    end

                    -- Reset user adjustment (base position is calculated live from primary bar)
                    secondary.offsetX = 0
                    secondary.offsetY = 0
                    secondary.lockedToPrimary = true
                    secondary.lockedToEssential = false
                    secondary.lockedToUtility = false
                    secondary.autoAttach = false
                    secondary.useRawPixels = true
                    RefreshPowerBars()
                    UpdateSecLockButtonStates()
                    if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                    if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
                else
                    print("|cFF56D1FFQUI:|r Primary Class Resource Bar not found or not visible. Enable it first.")
                end
            end
        end)

        -- Initialize button states
        UpdateSecLockButtonStates()
        y = y - FORM_ROW

        -- Color options (form style) - radio-button behavior: clicking one turns off the others
        local customColorPickerSecondary

        local powerColorSecondary = GUI:CreateFormCheckbox(tabContent, "Use Resource Type Color", "usePowerColor", secondary, function()
            if secondary.usePowerColor then
                secondary.useClassColor = false
                secondary.useCustomColor = false
                secondary.colorMode = "power"
            else
                -- Fallback: if turning off and nothing else is on, re-enable this
                if not secondary.useClassColor and not secondary.useCustomColor then
                    secondary.usePowerColor = true
                end
            end
            if customColorPickerSecondary then
                customColorPickerSecondary:SetEnabled(secondary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        powerColorSecondary:SetPoint("TOPLEFT", PAD, y)
        powerColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local resourceColorDescSecondary = GUI:CreateLabel(tabContent, "Uses per-resource colors from the Resource Colors section below.", 11)
        resourceColorDescSecondary:SetPoint("TOPLEFT", PAD, y + 4)
        resourceColorDescSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        resourceColorDescSecondary:SetJustifyH("LEFT")
        resourceColorDescSecondary:SetTextColor(0.6, 0.6, 0.6)
        y = y - FORM_ROW

        local classColorSecondary = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", secondary, function()
            if secondary.useClassColor then
                secondary.usePowerColor = false
                secondary.useCustomColor = false
                secondary.colorMode = "class"
            else
                -- Fallback: if turning off and nothing else is on, enable Resource Type Color
                if not secondary.usePowerColor and not secondary.useCustomColor then
                    secondary.usePowerColor = true
                end
            end
            if customColorPickerSecondary then
                customColorPickerSecondary:SetEnabled(secondary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        classColorSecondary:SetPoint("TOPLEFT", PAD, y)
        classColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local bgColorSecondary = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", secondary, RefreshPowerBars)
        bgColorSecondary:SetPoint("TOPLEFT", PAD, y)
        bgColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local customColorOverrideSecondary = GUI:CreateFormCheckbox(tabContent, "Custom Color Override", "useCustomColor", secondary, function()
            if secondary.useCustomColor then
                secondary.usePowerColor = false
                secondary.useClassColor = false
                secondary.colorMode = "custom"
            else
                -- Fallback: if turning off and nothing else is on, enable Resource Type Color
                if not secondary.usePowerColor and not secondary.useClassColor then
                    secondary.usePowerColor = true
                end
            end
            if customColorPickerSecondary then
                customColorPickerSecondary:SetEnabled(secondary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        customColorOverrideSecondary:SetPoint("TOPLEFT", PAD, y)
        customColorOverrideSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        customColorPickerSecondary = GUI:CreateFormColorPicker(tabContent, "Custom Color", "customColor", secondary, RefreshPowerBars)
        customColorPickerSecondary:SetPoint("TOPLEFT", PAD, y)
        customColorPickerSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        customColorPickerSecondary:SetEnabled(secondary.useCustomColor)
        y = y - FORM_ROW

        -- Text display options
        local showTextSecondary = GUI:CreateFormCheckbox(tabContent, "Show Number", "showText", secondary, RefreshPowerBars)
        showTextSecondary:SetPoint("TOPLEFT", PAD, y)
        showTextSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showPercentSecondary = GUI:CreateFormCheckbox(tabContent, "Show as Percent", "showPercent", secondary, RefreshPowerBars)
        showPercentSecondary:SetPoint("TOPLEFT", PAD, y)
        showPercentSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showRuneTextSecondary = GUI:CreateFormCheckbox(tabContent, "Show Rune CD Text (DKs)", "showFragmentedPowerBarText", secondary, RefreshPowerBars)
        showRuneTextSecondary:SetPoint("TOPLEFT", PAD, y)
        showRuneTextSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        local _, playerClass = UnitClass("player")
        showRuneTextSecondary:SetEnabled(playerClass == "DEATHKNIGHT")
        y = y - FORM_ROW

        -- Tick marks
        local showTicksSecondary = GUI:CreateFormCheckbox(tabContent, "Show Tick Marks", "showTicks", secondary, RefreshPowerBars)
        showTicksSecondary:SetPoint("TOPLEFT", PAD, y)
        showTicksSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tickThicknessSecondary = GUI:CreateFormSlider(tabContent, "Tick Thickness", 1, 4, 1, "tickThickness", secondary, RefreshPowerBars)
        tickThicknessSecondary:SetPoint("TOPLEFT", PAD, y)
        tickThicknessSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tickColorSecondary = GUI:CreateFormColorPicker(tabContent, "Tick Color", "tickColor", secondary, RefreshPowerBars)
        tickColorSecondary:SetPoint("TOPLEFT", PAD, y)
        tickColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Size sliders (form style)
        widthSecondarySlider = GUI:CreateFormSlider(tabContent, "Width", 0, 2000, 1, "width", secondary, RefreshPowerBars)
        widthSecondarySlider:SetPoint("TOPLEFT", PAD, y)
        widthSecondarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local heightSecondary = GUI:CreateFormSlider(tabContent, "Height", 1, 100, 1, "height", secondary, RefreshPowerBars)
        heightSecondary:SetPoint("TOPLEFT", PAD, y)
        heightSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderSecondary = GUI:CreateFormSlider(tabContent, "Border Size", 0, 8, 1, "borderSize", secondary, RefreshPowerBars)
        borderSecondary:SetPoint("TOPLEFT", PAD, y)
        borderSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Position sliders
        local xOffsetSecondarySlider = GUI:CreateFormSlider(tabContent, "X Offset", -1000, 1000, 1, "offsetX", secondary, RefreshPowerBars)
        xOffsetSecondarySlider:SetPoint("TOPLEFT", PAD, y)
        xOffsetSecondarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        yOffsetSecondarySlider = GUI:CreateFormSlider(tabContent, "Y Offset", -1000, 1000, 1, "offsetY", secondary, RefreshPowerBars)
        yOffsetSecondarySlider:SetPoint("TOPLEFT", PAD, y)
        yOffsetSecondarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Register sliders for real-time sync during Edit Mode
        if QUICore and QUICore.RegisterPowerBarEditModeSliders then
            QUICore:RegisterPowerBarEditModeSliders("secondary", xOffsetSecondarySlider, yOffsetSecondarySlider)
        end

        -- Text sliders
        local textSizeSecondary = GUI:CreateFormSlider(tabContent, "Text Size", 8, 50, 1, "textSize", secondary, RefreshPowerBars)
        textSizeSecondary:SetPoint("TOPLEFT", PAD, y)
        textSizeSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textXSecondary = GUI:CreateFormSlider(tabContent, "Text X Offset", -500, 500, 1, "textX", secondary, RefreshPowerBars)
        textXSecondary:SetPoint("TOPLEFT", PAD, y)
        textXSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textYSecondary = GUI:CreateFormSlider(tabContent, "Text Y Offset", -500, 500, 1, "textY", secondary, RefreshPowerBars)
        textYSecondary:SetPoint("TOPLEFT", PAD, y)
        textYSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Text color settings
        local textCustomColorSecondary  -- Forward declare for mutual reference

        local textUseClassColorSecondary = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Text", "textUseClassColor", secondary, function()
            if textCustomColorSecondary then
                textCustomColorSecondary:SetEnabled(not secondary.textUseClassColor)
            end
            RefreshPowerBars()
        end)
        textUseClassColorSecondary:SetPoint("TOPLEFT", PAD, y)
        textUseClassColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        textCustomColorSecondary = GUI:CreateFormColorPicker(tabContent, "Custom Text Color", "textCustomColor", secondary, RefreshPowerBars)
        textCustomColorSecondary:SetPoint("TOPLEFT", PAD, y)
        textCustomColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textCustomColorSecondary:SetEnabled(not secondary.textUseClassColor)  -- Initial state
        y = y - FORM_ROW

        local textureSecondary = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", secondary, RefreshPowerBars)
        textureSecondary:SetPoint("TOPLEFT", PAD, y)
        textureSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        return y
    end

    -- Build Powerbar color settings sub-section
    local function BuildPowerbarColorSettings(tabContent, ctx, y)
        local PAD = ctx.PAD
        local FORM_ROW = ctx.FORM_ROW
        local db = ctx.db
        local RefreshPowerBars = ctx.RefreshPowerBars

        -- =====================================================
        -- POWER COLORS (Global - affects both bars)
        -- =====================================================
        y = y - 20  -- Spacer between sections

        local powerColorsHeader = GUI:CreateSectionHeader(tabContent, "Reset Resource Bar Colors To Default")
        powerColorsHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - powerColorsHeader.gap

        -- Get powerColors DB table
        local pc = db.powerColors
        if not pc then
            db.powerColors = {}
            pc = db.powerColors
        end

        -- Default power colors (used for Reset button)
        local defaultPowerColors = {
            rage = { 1.00, 0.00, 0.00, 1 },
            energy = { 1.00, 1.00, 0.00, 1 },
            mana = { 0.00, 0.00, 1.00, 1 },
            focus = { 1.00, 0.50, 0.25, 1 },
            runicPower = { 0.00, 0.82, 1.00, 1 },
            fury = { 0.79, 0.26, 0.99, 1 },
            insanity = { 0.40, 0.00, 0.80, 1 },
            maelstrom = { 0.00, 0.50, 1.00, 1 },
            maelstromWeapon = { 0.00, 0.69, 1.00, 1 },
            lunarPower = { 0.30, 0.52, 0.90, 1 },
            holyPower = { 0.95, 0.90, 0.60, 1 },
            chi = { 0.00, 1.00, 0.59, 1 },
            comboPoints = { 1.00, 0.96, 0.41, 1 },
            soulShards = { 0.58, 0.51, 0.79, 1 },
            arcaneCharges = { 0.10, 0.10, 0.98, 1 },
            essence = { 0.20, 0.58, 0.50, 1 },
            stagger = { 0.00, 1.00, 0.59, 1 },
            soulFragments = { 0.64, 0.19, 0.79, 1 },
            runes = { 0.77, 0.12, 0.23, 1 },
            bloodRunes = { 0.77, 0.12, 0.23, 1 },
            frostRunes = { 0.00, 0.82, 1.00, 1 },
            unholyRunes = { 0.00, 0.80, 0.00, 1 },
        }

        -- Initialize defaults if missing
        for key, value in pairs(defaultPowerColors) do
            if pc[key] == nil then pc[key] = {value[1], value[2], value[3], value[4]} end
        end

        -- Store widget references for Reset button
        local powerColorWidgets = {}

        -- Reset to Defaults button
        local resetPowerColorsContainer = CreateFrame("Frame", nil, tabContent)
        resetPowerColorsContainer:SetHeight(FORM_ROW)
        resetPowerColorsContainer:SetPoint("TOPLEFT", PAD, y)
        resetPowerColorsContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local resetPowerColorsLabel = resetPowerColorsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resetPowerColorsLabel:SetPoint("LEFT", 0, 0)
        resetPowerColorsLabel:SetText("Reset Colors")
        resetPowerColorsLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local resetPowerColorsBtn = CreateFrame("Button", nil, resetPowerColorsContainer, "BackdropTemplate")
        resetPowerColorsBtn:SetSize(140, 24)
        resetPowerColorsBtn:SetPoint("LEFT", resetPowerColorsContainer, "LEFT", 180, 0)
        local pxResetPower = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(resetPowerColorsBtn)) or 1
        resetPowerColorsBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxResetPower,
        })
        resetPowerColorsBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        resetPowerColorsBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local resetPowerColorsText = resetPowerColorsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resetPowerColorsText:SetPoint("CENTER")
        resetPowerColorsText:SetText("Reset to Defaults")
        resetPowerColorsText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        resetPowerColorsBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        resetPowerColorsBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        resetPowerColorsBtn:SetScript("OnClick", function()
            for key, value in pairs(defaultPowerColors) do
                pc[key] = {value[1], value[2], value[3], value[4]}
            end
            -- Refresh color swatches
            for _, widget in ipairs(powerColorWidgets) do
                if widget.swatch and pc[widget.dbKey] then
                    local col = pc[widget.dbKey]
                    widget.swatch:SetBackdropColor(col[1], col[2], col[3], col[4] or 1)
                end
            end
            RefreshPowerBars()
            print("|cFF56D1FFQUI:|r Resource colors reset to defaults.")
        end)
        y = y - FORM_ROW

        -- =====================================================
        -- SUB-SECTION: Core Resources
        -- =====================================================
        y = y - 8
        local coreHeader = GUI:CreateSectionHeader(tabContent, "Bar Colors for Core Resources")
        coreHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - coreHeader.gap

        local rageColor = GUI:CreateFormColorPicker(tabContent, "Rage", "rage", pc, RefreshPowerBars)
        rageColor:SetPoint("TOPLEFT", PAD, y)
        rageColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        rageColor.dbKey = "rage"
        table.insert(powerColorWidgets, rageColor)
        y = y - FORM_ROW

        local energyColor = GUI:CreateFormColorPicker(tabContent, "Energy", "energy", pc, RefreshPowerBars)
        energyColor:SetPoint("TOPLEFT", PAD, y)
        energyColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        energyColor.dbKey = "energy"
        table.insert(powerColorWidgets, energyColor)
        y = y - FORM_ROW

        local manaColor = GUI:CreateFormColorPicker(tabContent, "Mana", "mana", pc, RefreshPowerBars)
        manaColor:SetPoint("TOPLEFT", PAD, y)
        manaColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        manaColor.dbKey = "mana"
        table.insert(powerColorWidgets, manaColor)
        y = y - FORM_ROW

        local focusColor = GUI:CreateFormColorPicker(tabContent, "Focus", "focus", pc, RefreshPowerBars)
        focusColor:SetPoint("TOPLEFT", PAD, y)
        focusColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        focusColor.dbKey = "focus"
        table.insert(powerColorWidgets, focusColor)
        y = y - FORM_ROW

        local runicPowerColor = GUI:CreateFormColorPicker(tabContent, "Runic Power", "runicPower", pc, RefreshPowerBars)
        runicPowerColor:SetPoint("TOPLEFT", PAD, y)
        runicPowerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        runicPowerColor.dbKey = "runicPower"
        table.insert(powerColorWidgets, runicPowerColor)
        y = y - FORM_ROW

        local furyColor = GUI:CreateFormColorPicker(tabContent, "Fury", "fury", pc, RefreshPowerBars)
        furyColor:SetPoint("TOPLEFT", PAD, y)
        furyColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        furyColor.dbKey = "fury"
        table.insert(powerColorWidgets, furyColor)
        y = y - FORM_ROW

        local insanityColor = GUI:CreateFormColorPicker(tabContent, "Insanity", "insanity", pc, RefreshPowerBars)
        insanityColor:SetPoint("TOPLEFT", PAD, y)
        insanityColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        insanityColor.dbKey = "insanity"
        table.insert(powerColorWidgets, insanityColor)
        y = y - FORM_ROW

        local maelstromColor = GUI:CreateFormColorPicker(tabContent, "Maelstrom", "maelstrom", pc, RefreshPowerBars)
        maelstromColor:SetPoint("TOPLEFT", PAD, y)
        maelstromColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        maelstromColor.dbKey = "maelstrom"
        table.insert(powerColorWidgets, maelstromColor)
        y = y - FORM_ROW

        local maelstromWeaponColor = GUI:CreateFormColorPicker(tabContent, "Maelstrom Weapon", "maelstromWeapon", pc, RefreshPowerBars)
        maelstromWeaponColor:SetPoint("TOPLEFT", PAD, y)
        maelstromWeaponColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        maelstromWeaponColor.dbKey = "maelstromWeapon"
        table.insert(powerColorWidgets, maelstromWeaponColor)
        y = y - FORM_ROW

        local lunarPowerColor = GUI:CreateFormColorPicker(tabContent, "Astral Power", "lunarPower", pc, RefreshPowerBars)
        lunarPowerColor:SetPoint("TOPLEFT", PAD, y)
        lunarPowerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        lunarPowerColor.dbKey = "lunarPower"
        table.insert(powerColorWidgets, lunarPowerColor)
        y = y - FORM_ROW

        -- =====================================================
        -- SUB-SECTION: Builder Resources
        -- =====================================================
        y = y - 8
        local builderHeader = GUI:CreateSectionHeader(tabContent, "Bar Colors for Builder Resources")
        builderHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - builderHeader.gap

        local holyPowerColor = GUI:CreateFormColorPicker(tabContent, "Holy Power", "holyPower", pc, RefreshPowerBars)
        holyPowerColor:SetPoint("TOPLEFT", PAD, y)
        holyPowerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        holyPowerColor.dbKey = "holyPower"
        table.insert(powerColorWidgets, holyPowerColor)
        y = y - FORM_ROW

        local chiColor = GUI:CreateFormColorPicker(tabContent, "Chi", "chi", pc, RefreshPowerBars)
        chiColor:SetPoint("TOPLEFT", PAD, y)
        chiColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        chiColor.dbKey = "chi"
        table.insert(powerColorWidgets, chiColor)
        y = y - FORM_ROW

        local comboPointsColor = GUI:CreateFormColorPicker(tabContent, "Combo Points", "comboPoints", pc, RefreshPowerBars)
        comboPointsColor:SetPoint("TOPLEFT", PAD, y)
        comboPointsColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        comboPointsColor.dbKey = "comboPoints"
        table.insert(powerColorWidgets, comboPointsColor)
        y = y - FORM_ROW

        local soulShardsColor = GUI:CreateFormColorPicker(tabContent, "Soul Shards", "soulShards", pc, RefreshPowerBars)
        soulShardsColor:SetPoint("TOPLEFT", PAD, y)
        soulShardsColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        soulShardsColor.dbKey = "soulShards"
        table.insert(powerColorWidgets, soulShardsColor)
        y = y - FORM_ROW

        local arcaneChargesColor = GUI:CreateFormColorPicker(tabContent, "Arcane Charges", "arcaneCharges", pc, RefreshPowerBars)
        arcaneChargesColor:SetPoint("TOPLEFT", PAD, y)
        arcaneChargesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        arcaneChargesColor.dbKey = "arcaneCharges"
        table.insert(powerColorWidgets, arcaneChargesColor)
        y = y - FORM_ROW

        local essenceColor = GUI:CreateFormColorPicker(tabContent, "Essence", "essence", pc, RefreshPowerBars)
        essenceColor:SetPoint("TOPLEFT", PAD, y)
        essenceColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        essenceColor.dbKey = "essence"
        table.insert(powerColorWidgets, essenceColor)
        y = y - FORM_ROW

        -- =====================================================
        -- SUB-SECTION: Specialized Resources
        -- =====================================================
        y = y - 8
        local specialHeader = GUI:CreateSectionHeader(tabContent, "Bar Colors for Specialized Resources")
        specialHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - specialHeader.gap

        local staggerColor = GUI:CreateFormColorPicker(tabContent, "Stagger (Fallback)", "stagger", pc, RefreshPowerBars)
        staggerColor:SetPoint("TOPLEFT", PAD, y)
        staggerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        staggerColor.dbKey = "stagger"
        table.insert(powerColorWidgets, staggerColor)
        y = y - FORM_ROW

        local useStaggerLevels = GUI:CreateFormCheckbox(tabContent, "Use Stagger Level Colors", "useStaggerLevelColors", pc, RefreshPowerBars)
        useStaggerLevels:SetPoint("TOPLEFT", PAD, y)
        useStaggerLevels:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local staggerLightColor = GUI:CreateFormColorPicker(tabContent, "Stagger - Light (0-30%)", "staggerLight", pc, RefreshPowerBars)
        staggerLightColor:SetPoint("TOPLEFT", PAD, y)
        staggerLightColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        staggerLightColor.dbKey = "staggerLight"
        table.insert(powerColorWidgets, staggerLightColor)
        y = y - FORM_ROW

        local staggerModerateColor = GUI:CreateFormColorPicker(tabContent, "Stagger - Moderate (30-60%)", "staggerModerate", pc, RefreshPowerBars)
        staggerModerateColor:SetPoint("TOPLEFT", PAD, y)
        staggerModerateColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        staggerModerateColor.dbKey = "staggerModerate"
        table.insert(powerColorWidgets, staggerModerateColor)
        y = y - FORM_ROW

        local staggerHeavyColor = GUI:CreateFormColorPicker(tabContent, "Stagger - Heavy (60%+)", "staggerHeavy", pc, RefreshPowerBars)
        staggerHeavyColor:SetPoint("TOPLEFT", PAD, y)
        staggerHeavyColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        staggerHeavyColor.dbKey = "staggerHeavy"
        table.insert(powerColorWidgets, staggerHeavyColor)
        y = y - FORM_ROW

        local soulFragmentsColor = GUI:CreateFormColorPicker(tabContent, "Soul Fragments", "soulFragments", pc, RefreshPowerBars)
        soulFragmentsColor:SetPoint("TOPLEFT", PAD, y)
        soulFragmentsColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        soulFragmentsColor.dbKey = "soulFragments"
        table.insert(powerColorWidgets, soulFragmentsColor)
        y = y - FORM_ROW

        local runesColor = GUI:CreateFormColorPicker(tabContent, "Runes (Generic)", "runes", pc, RefreshPowerBars)
        runesColor:SetPoint("TOPLEFT", PAD, y)
        runesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        runesColor.dbKey = "runes"
        table.insert(powerColorWidgets, runesColor)
        y = y - FORM_ROW

        local bloodRunesColor = GUI:CreateFormColorPicker(tabContent, "Blood Runes", "bloodRunes", pc, RefreshPowerBars)
        bloodRunesColor:SetPoint("TOPLEFT", PAD, y)
        bloodRunesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        bloodRunesColor.dbKey = "bloodRunes"
        table.insert(powerColorWidgets, bloodRunesColor)
        y = y - FORM_ROW

        local frostRunesColor = GUI:CreateFormColorPicker(tabContent, "Frost Runes", "frostRunes", pc, RefreshPowerBars)
        frostRunesColor:SetPoint("TOPLEFT", PAD, y)
        frostRunesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        frostRunesColor.dbKey = "frostRunes"
        table.insert(powerColorWidgets, frostRunesColor)
        y = y - FORM_ROW

        local unholyRunesColor = GUI:CreateFormColorPicker(tabContent, "Unholy Runes", "unholyRunes", pc, RefreshPowerBars)
        unholyRunesColor:SetPoint("TOPLEFT", PAD, y)
        unholyRunesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        unholyRunesColor.dbKey = "unholyRunes"
        table.insert(powerColorWidgets, unholyRunesColor)
        y = y - FORM_ROW

        return y
    end

    -- Build Powerbar sub-tab (orchestrator)
    local function BuildPowerbarTab(tabContent)
        local PAD = 10
        local y = -10

        -- Set search context for widget auto-registration
        GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 5, subTabName = "Class Resource Bar"})

        -- Ensure powerBar settings exist
        if not db.powerBar then db.powerBar = {} end
        if not db.secondaryPowerBar then db.secondaryPowerBar = {} end

        -- Ensure all fields exist with defaults
        local primary = db.powerBar
        if primary.enabled == nil then primary.enabled = true end
        if primary.visibility == nil then primary.visibility = "always" end
        if primary.autoAttach == nil then primary.autoAttach = true end
        if primary.width == nil then primary.width = 310 end
        if primary.height == nil then primary.height = 8 end
        if primary.offsetX == nil then primary.offsetX = 0 end
        if primary.offsetY == nil then primary.offsetY = 25 end
        if primary.texture == nil then primary.texture = "Solid" end
        if primary.colorMode == nil then primary.colorMode = "power" end  -- "power", "class", or "custom"
        if primary.usePowerColor == nil then primary.usePowerColor = true end  -- Default to power type color
        if primary.useClassColor == nil then primary.useClassColor = false end
        if primary.useCustomColor == nil then primary.useCustomColor = false end
        if primary.customColor == nil then primary.customColor = {0.2, 0.6, 1.0, 1} end
        if primary.bgColor == nil then primary.bgColor = {0.1, 0.1, 0.1, 0.8} end
        if primary.showText == nil then primary.showText = true end
        if primary.showPercent == nil then primary.showPercent = true end
        if primary.textSize == nil then primary.textSize = 14 end
        if primary.textX == nil then primary.textX = 0 end
        if primary.textY == nil then primary.textY = 2 end
        if primary.borderSize == nil then primary.borderSize = 1 end
        if primary.orientation == nil then primary.orientation = "AUTO" end
        if primary.snapGap == nil then primary.snapGap = 5 end

        local secondary = db.secondaryPowerBar
        if secondary.enabled == nil then secondary.enabled = true end
        if secondary.visibility == nil then secondary.visibility = "always" end
        if secondary.autoAttach == nil then secondary.autoAttach = true end
        if secondary.width == nil then secondary.width = 310 end
        if secondary.height == nil then secondary.height = 8 end
        if secondary.lockedBaseX == nil then secondary.lockedBaseX = 0 end
        if secondary.lockedBaseY == nil then secondary.lockedBaseY = 0 end
        if secondary.offsetX == nil then secondary.offsetX = 0 end
        if secondary.offsetY == nil then secondary.offsetY = 0 end
        if secondary.texture == nil then secondary.texture = "Solid" end
        if secondary.colorMode == nil then secondary.colorMode = "power" end  -- "power", "class", or "custom"
        if secondary.usePowerColor == nil then secondary.usePowerColor = true end  -- Default to power type color
        if secondary.useClassColor == nil then secondary.useClassColor = false end
        if secondary.useCustomColor == nil then secondary.useCustomColor = false end
        if secondary.customColor == nil then secondary.customColor = {1.0, 0.8, 0.2, 1} end
        if secondary.bgColor == nil then secondary.bgColor = {0.1, 0.1, 0.1, 0.8} end
        if secondary.showText == nil then secondary.showText = true end
        if secondary.showPercent == nil then secondary.showPercent = false end
        if secondary.showFragmentedPowerBarText == nil then secondary.showFragmentedPowerBarText = true end
        if secondary.textSize == nil then secondary.textSize = 14 end
        if secondary.textX == nil then secondary.textX = 0 end
        if secondary.textY == nil then secondary.textY = 2 end
        if secondary.borderSize == nil then secondary.borderSize = 1 end
        if secondary.orientation == nil then secondary.orientation = "AUTO" end
        if secondary.snapGap == nil then secondary.snapGap = 5 end

        -- Callback to refresh power bars
        local function RefreshPowerBars()
            if _G.QUI and _G.QUI.QUICore then
                local QUICore = _G.QUI.QUICore
                if QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
                if QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
            end
        end

        local function CalculateSnapPosition(viewer, barConfig, targetType, orientation)
            local viewerLabel = targetType == "essential" and "Essential Cooldowns" or "Utility Cooldowns"
            if targetType ~= "essential" and targetType ~= "utility" then
                return nil, nil, nil, "|cFF56D1FFQUI:|r Invalid snap target."
            end

            if not viewer or not viewer.IsShown or not viewer:IsShown() then
                return nil, nil, nil, ("|cFF56D1FFQUI:|r " .. viewerLabel .. " viewer not found or not visible.")
            end

            local rawCenterX, rawCenterY = viewer:GetCenter()
            local rawScreenX, rawScreenY = UIParent:GetCenter()
            if not rawCenterX or not rawCenterY or not rawScreenX or not rawScreenY then
                return nil, nil, nil, "|cFF56D1FFQUI:|r Could not get screen positions. Try again."
            end

            local viewerCenterX = math.floor(rawCenterX + 0.5)
            local viewerCenterY = math.floor(rawCenterY + 0.5)
            local screenCenterX = math.floor(rawScreenX + 0.5)
            local screenCenterY = math.floor(rawScreenY + 0.5)
            local barBorderSize = barConfig.borderSize or 1
            local isVertical = (orientation or barConfig.orientation) == "VERTICAL"

            local offsetX
            local offsetY
            local width

            if targetType == "essential" then
                if isVertical then
                    -- Vertical bar: goes to the RIGHT of Essential, length matches total height
                    local totalHeight = viewer.__cdmTotalHeight or viewer:GetHeight() or 100
                    local topBottomBorderSize = viewer.__cdmRow1BorderSize or 0
                    local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
                    local totalWidth = viewer.__cdmIconWidth or viewer:GetWidth()
                    local barThickness = barConfig.height or 8
                    local rightColBorderSize = viewer.__cdmBottomRowBorderSize or 0
                    local cdmVisualRight = viewerCenterX + (totalWidth / 2) + rightColBorderSize
                    local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize
                    offsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) - 4
                    offsetY = math.floor(viewerCenterY - screenCenterY + 0.5)
                    width = math.floor(targetWidth + 0.5)
                else
                    -- Horizontal bar: goes ABOVE Essential, width matches row width
                    local rowWidth = viewer.__cdmRow1Width or viewer.__cdmIconWidth or 300
                    local totalHeight = viewer.__cdmTotalHeight or viewer:GetHeight() or 100
                    local row1BorderSize = viewer.__cdmRow1BorderSize or 2
                    local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
                    local barHeight = barConfig.height or 8
                    local cdmVisualTop = viewerCenterY + (totalHeight / 2) + row1BorderSize
                    local powerBarCenterY = cdmVisualTop + (barHeight / 2) + barBorderSize
                    offsetY = math.floor(powerBarCenterY - screenCenterY + 0.5) - 1
                    offsetX = math.floor(viewerCenterX - screenCenterX + 0.5)
                    width = math.floor(targetWidth + 0.5)
                end
            else
                if isVertical then
                    -- Vertical bar: goes to the LEFT of Utility, length matches total height
                    local totalHeight = viewer.__cdmTotalHeight or viewer:GetHeight() or 100
                    local topBottomBorderSize = viewer.__cdmRow1BorderSize or 0
                    local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
                    local totalWidth = viewer.__cdmIconWidth or viewer:GetWidth()
                    local barThickness = barConfig.height or 8
                    local row1BorderSize = viewer.__cdmRow1BorderSize or 0
                    local cdmVisualLeft = viewerCenterX - (totalWidth / 2) - row1BorderSize
                    local powerBarCenterX = cdmVisualLeft - (barThickness / 2) - barBorderSize
                    offsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) + 1
                    offsetY = math.floor(viewerCenterY - screenCenterY + 0.5)
                    width = math.floor(targetWidth + 0.5)
                else
                    -- Horizontal bar: goes BELOW Utility, width matches row width
                    local rowWidth = viewer.__cdmBottomRowWidth or viewer.__cdmIconWidth or 300
                    local totalHeight = viewer.__cdmTotalHeight or viewer:GetHeight() or 100
                    local bottomRowBorderSize = viewer.__cdmBottomRowBorderSize or 2
                    local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
                    local barHeight = barConfig.height or 8
                    local cdmVisualBottom = viewerCenterY - (totalHeight / 2) - bottomRowBorderSize
                    local powerBarCenterY = cdmVisualBottom - (barHeight / 2) - barBorderSize
                    offsetY = math.floor(powerBarCenterY - screenCenterY + 0.5) + 1
                    offsetX = math.floor(viewerCenterX - screenCenterX + 0.5)
                    width = math.floor(targetWidth + 0.5)
                end
            end

            return offsetX, offsetY, width
        end

        local FORM_ROW = 32

        -- Shared context for powerbar builders
        local ctx = {
            PAD = PAD,
            FORM_ROW = FORM_ROW,
            primary = primary,
            secondary = secondary,
            db = db,
            RefreshPowerBars = RefreshPowerBars,
            CalculateSnapPosition = CalculateSnapPosition,
        }

        y = BuildPowerbarGeneralSettings(tabContent, ctx, y)
        y = y - 10  -- Spacer before Primary section
        y = BuildPrimaryPowerbarConfig(tabContent, ctx, y)
        y = y - 15  -- Spacer between sections
        y = BuildSecondaryPowerbarConfig(tabContent, ctx, y)
        y = BuildPowerbarColorSettings(tabContent, ctx, y)

        -- Extra padding at bottom for dropdown menus to expand into
        tabContent:SetHeight(math.abs(y) + 60)
    end

    -- Create sub-tabs
    local subTabs = {
        {name = "Essential", builder = BuildEssentialTab},
        {name = "Utility", builder = BuildUtilityTab},
        {name = "Custom Entries", builder = BuildCustomEntriesTab},
        {name = "Buff", builder = BuildBuffTab},
        {name = "Class Resource Bar", builder = BuildPowerbarTab},
    }

    if ns.QUI_CDMEffectsOptions and ns.QUI_CDMEffectsOptions.BuildEffectsTab then
        table.insert(subTabs, {name = "Effects", builder = ns.QUI_CDMEffectsOptions.BuildEffectsTab, isSeparator = true})
    end

    if ns.QUI_KeybindsOptions and ns.QUI_KeybindsOptions.BuildKeybindsTab then
        table.insert(subTabs, {name = "Keybinds", builder = ns.QUI_KeybindsOptions.BuildKeybindsTab})
    end

    if ns.QUI_KeybindsOptions and ns.QUI_KeybindsOptions.BuildRotationAssistTab then
        table.insert(subTabs, {name = "Rotation Assist", builder = ns.QUI_KeybindsOptions.BuildRotationAssistTab})
    end

    GUI:CreateSubTabs(content, subTabs)

    content:SetHeight(700)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_NCDMOptions = {
    CreateCDMSetupPage = CreateCDMSetupPage,
    EnsureNCDMDefaults = EnsureNCDMDefaults,
    RefreshNCDM = RefreshNCDM,
}
