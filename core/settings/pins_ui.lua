local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Pins = Settings.Pins
if not Pins then
    return
end

local ipairs = ipairs
local math_abs = math.abs
local pairs = pairs
local pcall = pcall
local string_find = string.find
local string_format = string.format
local string_gsub = string.gsub
local string_lower = string.lower
local tostring = tostring
local type = type
local wipe = wipe

local PIN_ICON_TEXTURE = ns.Helpers.AssetPath .. "pin_icon.png"

local function CloneValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, nestedValue in pairs(value) do
        copy[CloneValue(key, seen)] = CloneValue(nestedValue, seen)
    end
    return copy
end

local function GetGUI()
    return _G.QUI and _G.QUI.GUI or nil
end

local function GetColors()
    local gui = GetGUI()
    return gui and gui.Colors or nil
end

local function GetAccentColor()
    local C = GetColors()
    return (C and C.accent) or { 0.204, 0.827, 0.6, 1 }
end

local function GetMutedColor()
    local C = GetColors()
    return (C and C.textMuted) or { 0.62, 0.66, 0.72, 1 }
end

local function GetTextColor()
    local C = GetColors()
    return (C and C.text) or { 1, 1, 1, 1 }
end

local function GetDangerColor()
    return { 0.92, 0.42, 0.35, 1 }
end

local function GetStaleColor()
    return { 0.92, 0.62, 0.28, 1 }
end

local function SetFont(fontString, size, color)
    if not fontString then
        return
    end

    local gui = GetGUI()
    local uiKit = ns.UIKit
    local fontPath
    if gui and uiKit and type(uiKit.ResolveFontPath) == "function" and type(gui.GetFontPath) == "function" then
        fontPath = uiKit.ResolveFontPath(gui:GetFontPath())
    end
    fontString:SetFont(fontPath or select(1, fontString:GetFont()), size, "")

    color = color or GetTextColor()
    fontString:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local function StyleSurface(frame, backgroundAlpha, borderColor, borderAlpha, backgroundColor)
    if not frame then
        return
    end

    local uiKit = ns.UIKit
    local C = GetColors() or {}
    local bg = backgroundColor or C.bgContent or { 0.08, 0.09, 0.11, 1 }
    borderColor = borderColor or (C.border or { 1, 1, 1, 0.2 })
    borderAlpha = borderAlpha or borderColor[4] or 1

    if uiKit and uiKit.CreateBackground and uiKit.CreateBorderLines and uiKit.UpdateBorderLines then
        if not frame._quiPinsBg then
            frame._quiPinsBg = uiKit.CreateBackground(frame, bg[1], bg[2], bg[3], backgroundAlpha or 0.1)
            uiKit.CreateBorderLines(frame)
        elseif frame._quiPinsBg.SetVertexColor then
            frame._quiPinsBg:SetVertexColor(bg[1], bg[2], bg[3], backgroundAlpha or 0.1)
        end

        uiKit.UpdateBorderLines(
            frame,
            1,
            borderColor[1] or 1,
            borderColor[2] or 1,
            borderColor[3] or 1,
            borderAlpha,
            false
        )
        return
    end

    if not frame.SetBackdrop then
        return
    end

    local px = (ns.Addon and ns.Addon.GetPixelSize and ns.Addon:GetPixelSize(frame)) or 1
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], backgroundAlpha or 0.1)
    frame:SetBackdropBorderColor(borderColor[1] or 1, borderColor[2] or 1, borderColor[3] or 1, borderAlpha)
end

local function CleanupChildren(frame)
    if not frame or not frame.GetChildren then
        return
    end

    local gui = GetGUI()
    if gui and type(gui.CleanupWidgetTree) == "function" then
        gui:CleanupWidgetTree(frame)
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        if child.Hide then child:Hide() end
        if child.ClearAllPoints then child:ClearAllPoints() end
        if child.SetParent then child:SetParent(nil) end
    end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.Hide then region:Hide() end
            if region.SetParent then region:SetParent(nil) end
        end
    end
end

local function NormalizeSearch(text)
    text = string_lower(tostring(text or ""))
    text = string_gsub(text, "%s+", " ")
    text = string_gsub(text, "^%s+", "")
    text = string_gsub(text, "%s+$", "")
    return text
end

local function GetBindingPath(binding)
    if type(binding) ~= "table" then
        return nil
    end

    local path = binding.path
    if type(path) == "string" and path ~= "" then
        return path
    end

    if type(Pins.GetResolvedWidgetPath) == "function" then
        path = Pins:GetResolvedWidgetPath(binding)
        if type(path) == "string" and path ~= "" then
            binding.path = path
            return path
        end
    end

    return nil
end

local function GetBindingValue(binding)
    if type(binding) ~= "table" then
        return nil
    end

    if type(binding.dbTable) == "table" and type(binding.dbKey) == "string" and binding.dbKey ~= "" then
        local value = binding.dbTable[binding.dbKey]
        if value ~= nil then
            return CloneValue(value)
        end
    end

    local widget = binding.widget
    if widget and binding.kind == "color" and type(widget.GetColor) == "function" then
        local r, g, b, a = widget:GetColor()
        return { r, g, b, a }
    end
    if widget and type(widget.GetValue) == "function" then
        local value = widget:GetValue()
        if value ~= nil then
            return CloneValue(value)
        end
    end

    if binding.kind == "checkbox" then
        if widget and widget.checked ~= nil then
            return widget.checked and true or false
        end
        return false
    end

    return nil
end

local function BuildBindingDescriptor(binding, includeValue)
    if type(binding) ~= "table" then
        return nil
    end

    local descriptor = {
        kind = binding.kind,
        label = binding.label,
        pinLabel = binding.pinLabel,
        tabIndex = binding.tabIndex,
        tabName = binding.tabName,
        subTabIndex = binding.subTabIndex,
        subTabName = binding.subTabName,
        sectionName = binding.sectionName,
        tileId = binding.tileId,
        subPageIndex = binding.subPageIndex,
        featureId = binding.featureId,
        surfaceTabKey = binding.surfaceTabKey,
        surfaceUnitKey = binding.surfaceUnitKey,
    }

    if includeValue then
        descriptor.value = GetBindingValue(binding)
    end

    local db = _G.QUI and _G.QUI.db or nil
    if db and type(db.profile) == "table" then
        descriptor.sourceProfile = db.profile
    end

    return descriptor
end

local function UpdateBoundEntryMetadata(binding)
    local path = GetBindingPath(binding)
    if not path then
        return nil
    end

    local entry = Pins:GetEntry(path)
    if entry then
        Pins:UpdateEntryMetadata(entry, BuildBindingDescriptor(binding, false))
    end
    return entry
end

local function GetBindingFromFrame(frame)
    if not frame then
        return nil
    end

    local widget = frame._quiPinWidget or frame
    return widget and widget._quiPinBinding or nil
end

local function ShouldShowTooltips()
    local db = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    return not (db and db.general and db.general.showOptionTooltips == false)
end

local function ShowPinButtonTooltip(button)
    if not button or not GameTooltip or not ShouldShowTooltips() then
        return
    end

    local binding = GetBindingFromFrame(button)
    local path = GetBindingPath(binding)
    local entry = path and Pins:GetEntry(path) or nil
    local accent = GetAccentColor()

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry and entry.disabled then
        GameTooltip:SetText("Remove stale pin", accent[1], accent[2], accent[3], 1)
        GameTooltip:AddLine("This path no longer resolves. Click to remove it.", 1, 1, 1, true)
    elseif entry then
        GameTooltip:SetText("Pinned globally", accent[1], accent[2], accent[3], 1)
        GameTooltip:AddLine("Click to unpin. Edits affect all profiles.", 1, 1, 1, true)
    else
        GameTooltip:SetText("Pin across all profiles", accent[1], accent[2], accent[3], 1)
        GameTooltip:AddLine("Capture the current value and keep it across profile switches.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function AttachPinnedTooltip(target, widget)
    if not target or type(target.HookScript) ~= "function" then
        return
    end

    target._quiPinWidget = widget
    target._quiTooltipAugment = function(self, tooltip)
        if not tooltip or not ShouldShowTooltips() then
            return
        end

        local binding = GetBindingFromFrame(self)
        local path = GetBindingPath(binding)
        local entry = path and Pins:GetEntry(path) or nil
        if not entry then
            return
        end

        local accent = GetAccentColor()
        if entry.disabled then
            tooltip:AddLine("Pinned path unavailable. Click the pin to remove it.", 1, 0.82, 0.62, true)
        else
            tooltip:AddLine("Pinned globally. Edits affect all profiles.", accent[1], accent[2], accent[3], true)
        end
    end

    if target._quiHasBaseTooltip or target._quiPinsTooltipHooked then
        return
    end

    target._quiPinsTooltipHooked = true
    target:HookScript("OnEnter", function(self)
        if not GameTooltip or not ShouldShowTooltips() then
            return
        end

        local binding = GetBindingFromFrame(self)
        local path = GetBindingPath(binding)
        local entry = path and Pins:GetEntry(path) or nil
        if not entry then
            return
        end

        local accent = GetAccentColor()
        if not GameTooltip:IsOwned(self) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(binding and binding.label or "Pinned setting", accent[1], accent[2], accent[3], 1)
        end

        if type(self._quiTooltipAugment) == "function" then
            self._quiTooltipAugment(self, GameTooltip)
        end
        GameTooltip:Show()
    end)

    target:HookScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
end

local function EnsurePinAccent(widget, host)
    if not widget or not host then
        return nil
    end

    local accent = widget._quiPinAccent
    if not accent then
        accent = host:CreateTexture(nil, "ARTWORK")
        widget._quiPinAccent = accent
    end

    if accent:GetParent() ~= host then
        accent:SetParent(host)
    end

    accent:ClearAllPoints()
    accent:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -2)
    accent:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 2)
    accent:SetWidth(2)
    return accent
end

local function SetPinIconColor(button, color)
    if not button or not button._icon then
        return
    end

    color = color or GetTextColor()
    button._icon:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local INLINE_LABEL_PIN_RESERVE = 22

local function UsesInlineWidgetLabel(widget, host, interactive)
    if not widget or not host or not interactive then
        return false
    end
    if host ~= widget or interactive == host then
        return false
    end

    local label = widget.label
    return label
        and label.GetObjectType
        and label:GetObjectType() == "FontString"
        and label:GetParent() == widget
end

local function CapturePoints(frame)
    if not frame or type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then
        return nil
    end

    local points = {}
    local count = frame:GetNumPoints() or 0
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        points[#points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x or 0,
            y = y or 0,
        }
    end

    return points
end

local function RestorePoints(frame, points)
    if not frame or type(frame.ClearAllPoints) ~= "function" or type(points) ~= "table" or #points == 0 then
        return false
    end

    frame:ClearAllPoints()
    for _, info in ipairs(points) do
        frame:SetPoint(info.point, info.relativeTo, info.relativePoint, info.x or 0, info.y or 0)
    end
    return true
end

local function AdjustInlineInteractiveLayout(widget, host, interactive, enabled)
    if not interactive then
        return false
    end

    if not UsesInlineWidgetLabel(widget, host, interactive) then
        if interactive._quiPinOriginalPoints then
            RestorePoints(interactive, interactive._quiPinOriginalPoints)
            interactive._quiPinLayoutReserved = false
        end
        return false
    end

    if not interactive._quiPinOriginalPoints then
        interactive._quiPinOriginalPoints = CapturePoints(interactive)
    end
    if type(interactive._quiPinOriginalPoints) ~= "table" or #interactive._quiPinOriginalPoints == 0 then
        return false
    end

    if not enabled then
        RestorePoints(interactive, interactive._quiPinOriginalPoints)
        interactive._quiPinLayoutReserved = false
        return false
    end

    if interactive._quiPinLayoutReserved then
        return true
    end

    local adjusted = {}
    for _, info in ipairs(interactive._quiPinOriginalPoints) do
        local copy = {
            point = info.point,
            relativeTo = info.relativeTo,
            relativePoint = info.relativePoint,
            x = info.x or 0,
            y = info.y or 0,
        }

        if copy.relativeTo == host
            and type(copy.relativePoint) == "string"
            and copy.relativePoint:find("LEFT", 1, true) then
            copy.x = copy.x + INLINE_LABEL_PIN_RESERVE
        end

        adjusted[#adjusted + 1] = copy
    end

    RestorePoints(interactive, adjusted)
    interactive._quiPinLayoutReserved = true
    return true
end

local function RaisePinButton(button, host, interactive)
    if not button then
        return
    end

    local strata = interactive and interactive.GetFrameStrata and interactive:GetFrameStrata() or nil
    if type(strata) ~= "string" or strata == "" then
        strata = host and host.GetFrameStrata and host:GetFrameStrata() or nil
    end
    if type(strata) == "string" and strata ~= "" then
        button:SetFrameStrata(strata)
    end

    local frameLevel = 0
    if host and host.GetFrameLevel then
        frameLevel = math.max(frameLevel, host:GetFrameLevel() or 0)
    end
    if interactive and interactive.GetFrameLevel then
        frameLevel = math.max(frameLevel, interactive:GetFrameLevel() or 0)
    end

    local parent = button.GetParent and button:GetParent() or nil
    if parent and parent.GetFrameLevel then
        frameLevel = math.max(frameLevel, parent:GetFrameLevel() or 0)
    end

    button:SetFrameLevel(frameLevel + 8)
end

local function EnsurePinButton(widget, host, interactive)
    if not widget or not host then
        return nil
    end

    local button = widget._quiPinButton
    if not button then
        button = CreateFrame("Button", nil, host)
        button:SetSize(15, 15)
        button:SetHitRectInsets(-4, -4, -4, -4)

        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(button)
        button._bg = bg

        local icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetSize(11, 11)
        icon:SetPoint("CENTER", 0, 0)
        icon:SetTexture(PIN_ICON_TEXTURE)
        button._icon = icon

        button:SetScript("OnClick", function(self)
            local binding = GetBindingFromFrame(self)
            local path = GetBindingPath(binding)
            if not path then
                return
            end

            local entry = Pins:GetEntry(path)
            if entry and entry.disabled then
                Pins:DropPath(path)
            elseif entry then
                Pins:Unpin(path)
            else
                local descriptor = BuildBindingDescriptor(binding, true)
                if descriptor and descriptor.value ~= nil then
                    local ok = Pins:Pin(path, descriptor)
                    if ok then
                        Pins:RefreshRuntime()
                    end
                end
            end

            if self._quiPinWidget and type(Pins.RefreshWidgetChrome) == "function" then
                Pins:RefreshWidgetChrome(self._quiPinWidget)
            end
        end)

        button:SetScript("OnEnter", function(self)
            self._quiHovered = true
            if self._quiPinWidget and type(Pins.RefreshWidgetChrome) == "function" then
                Pins:RefreshWidgetChrome(self._quiPinWidget)
            end
            ShowPinButtonTooltip(self)
        end)

        button:SetScript("OnLeave", function(self)
            self._quiHovered = false
            if GameTooltip and GameTooltip:IsOwned(self) then
                GameTooltip:Hide()
            end
            if self._quiPinWidget and type(Pins.RefreshWidgetChrome) == "function" then
                Pins:RefreshWidgetChrome(self._quiPinWidget)
            end
        end)

        widget._quiPinButton = button
    end

    if button:GetParent() ~= host then
        button:SetParent(host)
    end

    button._quiPinWidget = widget
    AdjustInlineInteractiveLayout(widget, host, interactive, true)
    button:ClearAllPoints()
    if interactive then
        button:SetPoint("CENTER", interactive, "LEFT", -10, 0)
    else
        button:SetPoint("RIGHT", host, "RIGHT", -4, 0)
    end
    RaisePinButton(button, host, interactive)

    return button
end

function Pins:RefreshWidgetChrome(widget)
    local binding = widget and widget._quiPinBinding or nil
    if type(binding) ~= "table" then
        return false
    end

    local path = GetBindingPath(binding)
    local value = GetBindingValue(binding)
    local canPin = path and self:IsPathPinnable(path, binding.kind, value) or false
    local button = widget._quiPinButton
    local accent = widget._quiPinAccent

    if not canPin then
        AdjustInlineInteractiveLayout(widget, widget._quiPinHost or widget, widget._quiPinInteractive or binding.interactiveFrame or widget, false)
        if button then button:Hide() end
        if accent then accent:Hide() end
        return false
    end

    local entry = UpdateBoundEntryMetadata(binding)
    local isPinned = entry ~= nil
    local isDisabled = entry and entry.disabled == true
    local accentColor = isDisabled and GetStaleColor() or GetAccentColor()
    local buttonIcon = button and button._icon or nil
    local buttonBg = button and button._bg or nil
    local muted = GetMutedColor()

    if accent then
        accent:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], isPinned and 0.95 or 0)
        accent:SetShown(isPinned)
    end

    if button then
        AdjustInlineInteractiveLayout(widget, widget._quiPinHost or widget, widget._quiPinInteractive or binding.interactiveFrame or widget, true)
        button:Show()
        if isDisabled then
            button:SetAlpha(1)
            buttonBg:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.22)
            if buttonIcon then
                SetPinIconColor(button, accentColor)
            end
        elseif isPinned then
            local activeColor = button._quiHovered and GetDangerColor() or accentColor
            button:SetAlpha(1)
            buttonBg:SetColorTexture(activeColor[1], activeColor[2], activeColor[3], button._quiHovered and 0.22 or 0.14)
            if buttonIcon then
                SetPinIconColor(button, activeColor)
            end
        else
            local alpha = button._quiHovered and 0.18 or 0.06
            button:SetAlpha(button._quiHovered and 1 or 0.7)
            buttonBg:SetColorTexture(muted[1], muted[2], muted[3], alpha)
            if buttonIcon then
                SetPinIconColor(button, { muted[1], muted[2], muted[3], button._quiHovered and 1 or 0.8 })
            end
        end
    end

    return true
end

function Pins:BindWidget(widget, binding)
    if not widget or type(binding) ~= "table" then
        return false
    end

    widget._quiPinBinding = widget._quiPinBinding or {}
    local current = widget._quiPinBinding
    for key, value in pairs(binding) do
        current[key] = value
    end
    current.widget = widget

    local path = GetBindingPath(current)
    current.path = path

    if current.interactiveFrame then
        AttachPinnedTooltip(current.interactiveFrame, widget)
    end

    if path and not widget._quiPinToken and type(self.Subscribe) == "function" then
        widget._quiPinToken = self:Subscribe(path, function()
            self:RefreshWidgetChrome(widget)
        end, widget)
    end

    UpdateBoundEntryMetadata(current)
    return true
end

function Pins:AttachWidgetChrome(widget, host, interactiveFrame, labelOverride)
    local binding = widget and widget._quiPinBinding or nil
    if type(binding) ~= "table" then
        return false
    end

    if type(labelOverride) == "string" and labelOverride ~= "" then
        binding.label = labelOverride
    end
    if interactiveFrame then
        binding.interactiveFrame = interactiveFrame
        AttachPinnedTooltip(interactiveFrame, widget)
    end

    local path = GetBindingPath(binding)
    local value = GetBindingValue(binding)
    if not path or not self:IsPathPinnable(path, binding.kind, value) then
        if widget._quiPinButton then widget._quiPinButton:Hide() end
        if widget._quiPinAccent then widget._quiPinAccent:Hide() end
        return false
    end

    widget._quiPinHost = host or widget
    widget._quiPinInteractive = interactiveFrame or binding.interactiveFrame or widget

    EnsurePinAccent(widget, widget._quiPinHost)
    EnsurePinButton(widget, widget._quiPinHost, widget._quiPinInteractive)
    self:RefreshWidgetChrome(widget)
    return true
end

function Pins:AttachSettingRow(cell, widget, labelText)
    if not cell or not widget then
        return false
    end

    if not self:AttachWidgetChrome(widget, cell, widget._quiPinInteractive or widget._quiPinBinding and widget._quiPinBinding.interactiveFrame or widget, labelText) then
        return false
    end

    local anchor = (widget._quiPinButton and widget._quiPinButton:IsShown()) and widget._quiPinButton or widget
    if cell._label and anchor then
        cell._label:ClearAllPoints()
        cell._label:SetPoint("LEFT", cell, "LEFT", 0, cell._desc and 5 or 0)
        cell._label:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    end

    if cell._desc and anchor then
        cell._desc:ClearAllPoints()
        cell._desc:SetPoint("TOPLEFT", cell._label, "BOTTOMLEFT", 0, -1)
        cell._desc:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    end

    return true
end

local function BuildBreadcrumb(item)
    -- Prefer stored tabName/subTabName, but fall back to deriving them from
    -- tileId/subPageIndex via the tile registry. Pins captured inside a
    -- BuildFeatureStackPage iteration sometimes have no tabName/subTabName
    -- stored (only tileId/subPageIndex), which would otherwise collapse the
    -- breadcrumb to just the sectionName ("Behavior") with no useful context.
    local tabName, subTabName = item.tabName, item.subTabName
    local needLookup = (type(tabName) ~= "string" or tabName == "")
        or (type(subTabName) ~= "string" or subTabName == "")
    if needLookup and type(item.tileId) == "string" and item.tileId ~= "" then
        local gui = _G.QUI and _G.QUI.GUI or nil
        local frame = gui and gui.MainFrame or nil
        if frame and type(gui.FindV2TileByID) == "function" then
            local tile = gui:FindV2TileByID(frame, item.tileId)
            if tile and tile.config then
                if (type(tabName) ~= "string" or tabName == "")
                    and type(tile.config.name) == "string" and tile.config.name ~= "" then
                    tabName = tile.config.name
                end
                if (type(subTabName) ~= "string" or subTabName == "")
                    and type(item.subPageIndex) == "number" and tile.config.subPages then
                    local sp = tile.config.subPages[item.subPageIndex]
                    if sp and type(sp.name) == "string" and sp.name ~= "" then
                        subTabName = sp.name
                    end
                end
            end
        end
    end

    local parts = {}
    if type(tabName) == "string" and tabName ~= "" then
        parts[#parts + 1] = tabName
    end
    if type(subTabName) == "string" and subTabName ~= "" and subTabName ~= tabName then
        parts[#parts + 1] = subTabName
    end

    -- Stacked feature pages (e.g. Gameplay > Combat) host many features under
    -- one sub-tab. Surface the feature's display label between the sub-tab
    -- and the sectionName so the crumb tells the user which feature card
    -- the pin lives under.
    if type(item.featureId) == "string" and item.featureId ~= "" then
        local RenderAdapters = Settings and Settings.RenderAdapters
        local featureLabel
        if RenderAdapters and type(RenderAdapters.GetProviderLabel) == "function" then
            featureLabel = RenderAdapters.GetProviderLabel(item.featureId, nil)
        end
        if type(featureLabel) == "string" and featureLabel ~= ""
            and featureLabel ~= subTabName and featureLabel ~= tabName then
            parts[#parts + 1] = featureLabel
        end
    end

    if type(item.sectionName) == "string" and item.sectionName ~= "" then
        parts[#parts + 1] = item.sectionName
    end

    return #parts > 0 and table.concat(parts, " > ") or "Pinned setting"
end

local function SortItems(items, mode)
    table.sort(items, function(a, b)
        if mode == "name" then
            local aName = string_lower(tostring(a.label or a.path))
            local bName = string_lower(tostring(b.label or b.path))
            if aName ~= bName then
                return aName < bName
            end
        elseif mode == "feature" then
            local aCrumb = string_lower(BuildBreadcrumb(a))
            local bCrumb = string_lower(BuildBreadcrumb(b))
            if aCrumb ~= bCrumb then
                return aCrumb < bCrumb
            end
            local aName = string_lower(tostring(a.label or a.path))
            local bName = string_lower(tostring(b.label or b.path))
            if aName ~= bName then
                return aName < bName
            end
        else
            local aPinnedAt = tonumber(a.pinnedAt) or 0
            local bPinnedAt = tonumber(b.pinnedAt) or 0
            if aPinnedAt ~= bPinnedAt then
                return aPinnedAt > bPinnedAt
            end
        end

        return tostring(a.path) < tostring(b.path)
    end)
end

local function CreateSearchBox(parent, width, onChanged)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, 24)
    StyleSurface(frame, 0.08, GetMutedColor(), 0.22)

    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -2)
    editBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 2)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(2, 2, 0, 0)
    SetFont(editBox, 10, GetTextColor())

    local placeholder = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(placeholder, 10, GetMutedColor())
    placeholder:SetText("Search pinned settings")
    placeholder:SetPoint("LEFT", editBox, "LEFT", 2, 0)
    placeholder:SetJustifyH("LEFT")
    frame.placeholder = placeholder

    editBox:SetScript("OnTextChanged", function(self, userInput)
        placeholder:SetShown((self:GetText() or "") == "")
        if userInput and type(onChanged) == "function" then
            onChanged(self:GetText() or "")
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        placeholder:SetShown(true)
        if type(onChanged) == "function" then
            onChanged("")
        end
    end)

    frame.editBox = editBox
    return frame
end

local function CreateValuePreview(parent, item)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(132, 18)

    if item.kind == "color" and type(item.value) == "table" then
        local swatch = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        swatch:SetSize(16, 16)
        swatch:SetPoint("LEFT", frame, "LEFT", 0, 0)
        StyleSurface(swatch, 1, { 1, 1, 1, 0.35 }, 0.35)
        if swatch._quiPinsBg and swatch._quiPinsBg.SetVertexColor then
            swatch._quiPinsBg:SetVertexColor(item.value[1] or 1, item.value[2] or 1, item.value[3] or 1, item.value[4] or 1)
        elseif swatch.SetBackdropColor then
            swatch:SetBackdropColor(item.value[1] or 1, item.value[2] or 1, item.value[3] or 1, item.value[4] or 1)
        end

        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(valueText, 10, GetTextColor())
        valueText:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
        valueText:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        valueText:SetJustifyH("LEFT")
        valueText:SetText(Pins:FormatValue(item.value))
        return frame
    end

    local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(valueText, 10, item.disabled and GetStaleColor() or GetTextColor())
    valueText:SetPoint("LEFT", frame, "LEFT", 0, 0)
    valueText:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetText(item.disabled and "Unavailable" or Pins:FormatValue(item.value))
    return frame
end

local function BuildPopupRows(chip)
    local popup = chip and chip._quiPopup or nil
    if not popup or not popup.content then
        return
    end

    CleanupChildren(popup.content)

    local items = Pins:List()
    local y = -6
    if #items == 0 then
        local empty = popup.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(empty, 10, GetMutedColor())
        empty:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 4, y)
        empty:SetPoint("RIGHT", popup.content, "RIGHT", -4, 0)
        empty:SetJustifyH("LEFT")
        empty:SetJustifyV("TOP")
        empty:SetText("No pinned settings yet.")
        popup.content:SetHeight(48)
        return
    end

    for index, item in ipairs(items) do
        local row = CreateFrame("Button", nil, popup.content)
        row:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", popup.content, "TOPRIGHT", -4, y)
        row:SetHeight(30)

        if (index % 2) == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            bg:SetColorTexture(1, 1, 1, 0.025)
        end

        local hover = row:CreateTexture(nil, "ARTWORK")
        hover:SetAllPoints(row)
        hover:SetColorTexture(GetAccentColor()[1], GetAccentColor()[2], GetAccentColor()[3], 0.08)
        hover:Hide()

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(title, 10, item.disabled and GetStaleColor() or GetTextColor())
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
        title:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        title:SetJustifyH("LEFT")
        title:SetText(item.label or item.path)

        local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(value, 9, GetMutedColor())
        value:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 4)
        value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        value:SetJustifyH("LEFT")
        value:SetText(item.disabled and "Unavailable" or Pins:FormatValue(item.value))

        row:SetScript("OnEnter", function() hover:Show() end)
        row:SetScript("OnLeave", function() hover:Hide() end)
        row:SetScript("OnClick", function()
            popup:Hide()
            Pins:NavigateToPinned(item.path)
        end)

        y = y - 32
    end

    popup.content:SetHeight(math.max(1, math_abs(y) + 2))
end

local function EnsurePopup(chip)
    if not chip then
        return nil
    end

    if chip._quiPopup then
        return chip._quiPopup
    end

    local gui = GetGUI()
    if not gui then
        return nil
    end

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(292, 248)
    popup:SetFrameStrata("TOOLTIP")
    popup:Hide()
    StyleSurface(popup, 0.96, GetAccentColor(), 0.22, (GetColors() or {}).bg or { 0.051, 0.067, 0.09, 1 })

    local headerBg = popup:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -1)
    headerBg:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -1)
    headerBg:SetHeight(24)
    headerBg:SetColorTexture(GetAccentColor()[1], GetAccentColor()[2], GetAccentColor()[3], 0.08)

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(title, 11, GetTextColor())
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -10)
    title:SetText("Pinned Settings")

    local body = CreateFrame("Frame", nil, popup)
    body:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -28)
    body:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -8, -28)
    body:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -8, 34)

    local scroll, content = ns.QUI_Options.CreateScrollableContent(body)
    popup.scroll = scroll
    popup.content = content

    local clearBtn = gui:CreateButton(popup, "Clear All", 74, 20, function()
        gui:ShowConfirmation({
            title = "Remove all pins?",
            message = "Unpin every globally pinned setting?",
            warningText = "Each affected profile will restore its shadowed value where available.",
            acceptText = "Unpin All",
            cancelText = "Cancel",
            isDestructive = true,
            onAccept = function()
                Pins:UnpinAll()
            end,
        })
    end)
    clearBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 8, 8)

    local openBtn = gui:CreateButton(popup, "Open Full List", 100, 20, function()
        popup:Hide()
        Pins:OpenManagePage()
    end)
    openBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -8, 8)

    popup:HookScript("OnShow", function(self)
        self:SetPoint("TOPRIGHT", chip, "BOTTOMRIGHT", 0, -6)
        local elapsedOut = 0
        self:SetScript("OnUpdate", function(inner, elapsed)
            if chip:IsMouseOver() or inner:IsMouseOver() then
                elapsedOut = 0
                return
            end

            elapsedOut = elapsedOut + elapsed
            if elapsedOut > 0.18 then
                inner:Hide()
            end
        end)
    end)

    popup:HookScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    chip._quiPopup = popup
    return popup
end

function Pins:AttachCountChip(header)
    if not header then
        return false
    end

    local chip = header._quiPinChip
    if not chip then
        chip = CreateFrame("Button", nil, header, "BackdropTemplate")
        chip:SetHeight(22)
        chip:SetPoint("TOPRIGHT", header, "TOPRIGHT", -2, -2)
        StyleSurface(chip, 0.08, GetMutedColor(), 0.22)

        local text = chip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 10, GetMutedColor())
        text:SetPoint("CENTER", 0, 0)
        chip.text = text

        chip:SetScript("OnClick", function(self)
            local popup = EnsurePopup(self)
            if not popup then
                return
            end

            if popup:IsShown() then
                popup:Hide()
                return
            end

            BuildPopupRows(self)
            popup:Show()
        end)

        chip:SetScript("OnEnter", function(self)
            local popup = self._quiPopup
            if popup and popup:IsShown() then
                return
            end
            StyleSurface(self, 0.12, GetAccentColor(), 0.35)
        end)

        chip:SetScript("OnLeave", function(self)
            Pins:AttachCountChip(header)
        end)

        chip._quiPinToken = self:Subscribe("*", function()
            self:AttachCountChip(header)
        end, chip)

        header._quiPinChip = chip
    end

    local count = self:GetCount()
    local accent = GetAccentColor()
    local muted = GetMutedColor()
    local textColor = count > 0 and accent or muted
    local borderColor = count > 0 and accent or muted
    local borderAlpha = count > 0 and 0.3 or 0.18
    local bgAlpha = count > 0 and 0.1 or 0.04

    chip:SetWidth(count >= 100 and 70 or 62)
    chip.text:SetText(string_format("Pin %d", count))
    chip.text:SetTextColor(textColor[1], textColor[2], textColor[3], count > 0 and 1 or 0.9)
    StyleSurface(chip, bgAlpha, borderColor, borderAlpha)

    if chip._quiPopup and chip._quiPopup:IsShown() then
        BuildPopupRows(chip)
    end

    return true
end

local function BuildPinnedGlobalsRows(state)
    local gui = GetGUI()
    if not state or not state.rowsHost or not gui then
        return
    end

    CleanupChildren(state.rowsHost)

    local items = Pins:List()
    local query = NormalizeSearch(state.search)
    local filtered = {}
    local disabledCount = 0
    for _, item in ipairs(items) do
        if item.disabled then
            disabledCount = disabledCount + 1
        end

        if query == "" then
            filtered[#filtered + 1] = item
        else
            local haystack = NormalizeSearch((item.label or item.path or "") .. " " .. BuildBreadcrumb(item) .. " " .. (item.path or ""))
            if string_find(haystack, query, 1, true) then
                filtered[#filtered + 1] = item
            end
        end
    end

    SortItems(filtered, state.sortMode or "recent")

    if disabledCount > 0 then
        state.staleBanner:Show()
        state.staleText:SetText(string_format("%d stale pin%s detected.", disabledCount, disabledCount == 1 and "" or "s"))
        state.rowsHost:ClearAllPoints()
        state.rowsHost:SetPoint("TOPLEFT", state.staleBanner, "BOTTOMLEFT", 0, -10)
        state.rowsHost:SetPoint("TOPRIGHT", state.staleBanner, "BOTTOMRIGHT", 0, -10)
    else
        state.staleBanner:Hide()
        state.rowsHost:ClearAllPoints()
        state.rowsHost:SetPoint("TOPLEFT", state.toolbar, "BOTTOMLEFT", 0, -12)
        state.rowsHost:SetPoint("TOPRIGHT", state.toolbar, "BOTTOMRIGHT", 0, -12)
    end

    local y = 0
    if #filtered == 0 then
        local empty = state.rowsHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(empty, 11, GetMutedColor())
        empty:SetPoint("TOPLEFT", state.rowsHost, "TOPLEFT", 0, 0)
        empty:SetPoint("RIGHT", state.rowsHost, "RIGHT", 0, 0)
        empty:SetJustifyH("LEFT")
        empty:SetText(query == "" and "No pinned settings yet." or "No pinned settings match this search.")
        state.rowsHost:SetHeight(32)
        state.content:SetHeight(220)
        return
    end

    for index, item in ipairs(filtered) do
        local row = CreateFrame("Frame", nil, state.rowsHost)
        row:SetPoint("TOPLEFT", state.rowsHost, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", state.rowsHost, "TOPRIGHT", 0, y)
        row:SetHeight(44)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        if item.disabled then
            bg:SetColorTexture(GetStaleColor()[1], GetStaleColor()[2], GetStaleColor()[3], 0.07)
        elseif (index % 2) == 0 then
            bg:SetColorTexture(1, 1, 1, 0.025)
        else
            bg:SetColorTexture(0, 0, 0, 0)
        end

        local accentBar = row:CreateTexture(nil, "ARTWORK")
        accentBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
        accentBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 4)
        accentBar:SetWidth(2)
        if item.disabled then
            accentBar:SetColorTexture(GetStaleColor()[1], GetStaleColor()[2], GetStaleColor()[3], 1)
        else
            local accent = GetAccentColor()
            accentBar:SetColorTexture(accent[1], accent[2], accent[3], 1)
        end

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(label, 11, item.disabled and GetStaleColor() or GetTextColor())
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -6)
        label:SetPoint("RIGHT", row, "RIGHT", -278, 0)
        label:SetJustifyH("LEFT")
        label:SetText(item.label or item.path)

        local crumb = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(crumb, 9, GetMutedColor())
        crumb:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        crumb:SetPoint("RIGHT", row, "RIGHT", -278, 0)
        crumb:SetJustifyH("LEFT")
        crumb:SetText(item.disabled and (BuildBreadcrumb(item) .. "  |  stale") or BuildBreadcrumb(item))

        local valuePreview = CreateValuePreview(row, item)
        valuePreview:SetPoint("RIGHT", row, "RIGHT", -146, 0)

        local jumpBtn = gui:CreateButton(row, "Jump", 52, 20, function()
            Pins:NavigateToPinned(item.path)
        end)
        jumpBtn:SetPoint("RIGHT", row, "RIGHT", -74, 0)

        local unpinBtn = gui:CreateButton(row, item.disabled and "Remove" or "Unpin", 62, 20, function()
            if item.disabled then
                Pins:DropPath(item.path)
            else
                Pins:Unpin(item.path)
            end
        end)
        unpinBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

        y = y - 46
    end

    state.rowsHost:SetHeight(math.max(1, math_abs(y)))
    state.content:SetHeight(math.max(220, 132 + math_abs(y)))
end

local function BuildPinnedGlobalsContent(content, stateHost, scrollFrame)
    local gui = GetGUI()
    if not content or not gui then
        return
    end

    stateHost = stateHost or content

    if stateHost._quiPinnedGlobalsState
        and stateHost._quiPinnedGlobalsState.content == content
        and stateHost._quiPinnedGlobalsState.rowsHost
        and stateHost._quiPinnedGlobalsState.rowsHost.GetParent
        and stateHost._quiPinnedGlobalsState.rowsHost:GetParent() then
        BuildPinnedGlobalsRows(stateHost._quiPinnedGlobalsState)
        return
    end

    stateHost._quiPinnedGlobalsState = nil
    local state = {
        parent = stateHost,
        scroll = scrollFrame,
        content = content,
        search = "",
        sortMode = "recent",
    }
    stateHost._quiPinnedGlobalsState = state

    local intro = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(intro, 11, GetMutedColor())
    intro:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -8)
    intro:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Pinned settings override the active profile across switches, imports, and resets.")

    local toolbar = CreateFrame("Frame", nil, content)
    toolbar:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
    toolbar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -12)
    toolbar:SetHeight(26)
    state.toolbar = toolbar

    local searchBox = CreateSearchBox(toolbar, 228, function(text)
        state.search = text or ""
        BuildPinnedGlobalsRows(state)
    end)
    searchBox:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    state.searchBox = searchBox

    local sortState = { value = "recent" }
    local sortOptions = {
        { value = "recent", text = "Most recent" },
        { value = "name", text = "Name" },
        { value = "feature", text = "Feature" },
    }
    local sortDropdown = gui:CreateFormDropdown(toolbar, nil, sortOptions, "value", sortState, function(value)
        state.sortMode = value or "recent"
        BuildPinnedGlobalsRows(state)
    end, nil, { width = 124 })
    sortDropdown:SetWidth(124)
    sortDropdown:SetPoint("RIGHT", toolbar, "RIGHT", -96, 0)
    if sortDropdown.SetValue then
        sortDropdown:SetValue("recent", true)
    end
    state.sortDropdown = sortDropdown

    local unpinAll = gui:CreateButton(toolbar, "Unpin All", 82, 20, function()
        gui:ShowConfirmation({
            title = "Remove all pins?",
            message = "Unpin every globally pinned setting?",
            warningText = "Each affected profile will restore its shadowed value where available.",
            acceptText = "Unpin All",
            cancelText = "Cancel",
            isDestructive = true,
            onAccept = function()
                Pins:UnpinAll()
            end,
        })
    end)
    unpinAll:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    state.unpinAll = unpinAll

    local staleBanner = CreateFrame("Frame", nil, content, "BackdropTemplate")
    staleBanner:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -10)
    staleBanner:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -10)
    staleBanner:SetHeight(28)
    StyleSurface(staleBanner, 0.08, GetStaleColor(), 0.28)
    staleBanner:Hide()
    state.staleBanner = staleBanner

    local staleText = staleBanner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(staleText, 10, GetStaleColor())
    staleText:SetPoint("LEFT", staleBanner, "LEFT", 10, 0)
    staleText:SetJustifyH("LEFT")
    state.staleText = staleText

    local clearStale = gui:CreateButton(staleBanner, "Remove stale", 92, 18, function()
        for _, item in ipairs(Pins:List()) do
            if item.disabled then
                Pins:DropPath(item.path)
            end
        end
    end)
    clearStale:SetPoint("RIGHT", staleBanner, "RIGHT", -6, 0)
    state.clearStale = clearStale

    local rowsHost = CreateFrame("Frame", nil, content)
    rowsHost:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -12)
    rowsHost:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -12)
    rowsHost:SetHeight(1)
    state.rowsHost = rowsHost

    state.token = Pins:Subscribe("*", function()
        BuildPinnedGlobalsRows(state)
    end, stateHost)

    stateHost:SetScript("OnShow", function()
        BuildPinnedGlobalsRows(state)
    end)
    if scrollFrame then
        scrollFrame:SetScript("OnShow", function()
            BuildPinnedGlobalsRows(state)
        end)
    end

    BuildPinnedGlobalsRows(state)
end

local function BuildPinnedGlobalsPage(parent)
    if not parent or not ns.QUI_Options or not ns.QUI_Options.CreateScrollableContent then
        return
    end

    local scroll, content = ns.QUI_Options.CreateScrollableContent(parent)
    BuildPinnedGlobalsContent(content, parent, scroll)
end

ns.QUI_PinnedSettingsOptions = {
    BuildPinnedGlobalsContent = BuildPinnedGlobalsContent,
    BuildPinnedGlobalsPage = BuildPinnedGlobalsPage,
}

do
    local settings = ns.Settings
    local registry = settings and settings.Registry
    local schema = settings and settings.Schema
    if registry and schema
        and type(registry.RegisterFeature) == "function"
        and type(schema.Feature) == "function"
        and type(schema.Section) == "function" then
        registry:RegisterFeature(schema.Feature({
            id = "pinnedGlobalsPage",
            moverKey = "pinnedGlobals",
            category = "global",
            nav = { tileId = "global", subPageIndex = 2 },
            sections = {
                schema.Section({
                    id = "settings",
                    kind = "page",
                    minHeight = 80,
                    build = function(host)
                        return BuildPinnedGlobalsContent(host, host)
                    end,
                }),
            },
        }))
    end
end
