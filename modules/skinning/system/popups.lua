local _, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local SkinBase = ns.SkinBase

local FONT_SIZE = 12

-- Text ladder from the shared palette (core/theme.lua): rest = tabHover (white
-- .85), hover = text (white 1), disabled = disabled (white .30).
local function ThemeRole(name, fallback)
    local gui = _G.QUI and _G.QUI.GUI
    local role = gui and gui.Colors and gui.Colors[name] or fallback
    return role[1], role[2], role[3], role[4] or 1
end
local BUTTON_REST_FALLBACK = { 1, 1, 1, 0.85 }
local BUTTON_DISABLED_FALLBACK = { 1, 1, 1, 0.30 }
local BUTTON_HOVER_FALLBACK = { 1, 1, 1, 1 }

local menuCallbacks = Helpers.CreateStateTable()

local function Defer(fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, fn)
    else
        fn()
    end
end

local function GetGeneralSettings()
    local core = GetCore()
    return core and core.db and core.db.profile and core.db.profile.general
end

local function StaticPopupsEnabled()
    local settings = GetGeneralSettings()
    return settings and settings.skinStaticPopups ~= false
end

local function ContextMenusEnabled()
    local settings = GetGeneralSettings()
    return settings and settings.skinContextMenus ~= false
end

local function IsForbidden(frame)
    return frame and frame.IsForbidden and frame:IsForbidden()
end

local function SafeFrameLevel(frame)
    local level = frame and frame.GetFrameLevel and frame:GetFrameLevel()
    if type(level) ~= "number" then return 0 end
    return level
end

local function GetColors(prefix)
    local settings = GetGeneralSettings()
    return SkinBase.GetWindowColors(settings, prefix)
end

local function ApplyBackdrop(frame, prefix, bgBoost, bgAlpha, radius)
    if not frame or IsForbidden(frame) then return nil end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors(prefix)
    local boost = bgBoost or 0
    local ar = math.min((bgr or 0) + boost, 1)
    local ag = math.min((bgg or 0) + boost, 1)
    local ab = math.min((bgb or 0) + boost, 1)
    local aa = bgAlpha or bga

    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, ar, ag, ab, aa, radius or 8)

    local backdrop = SkinBase.GetBackdrop(frame)
    if backdrop then
        backdrop:SetFrameLevel(math.max(0, SafeFrameLevel(frame) - 1))
    end

    return backdrop, sr, sg, sb, sa, ar, ag, ab, aa
end

local function HideRegionTexture(region)
    if not region or not region.IsObjectType or not region:IsObjectType("Texture") then return end
    if SkinBase.GetFrameData(region, "systemPopupOwned") then return end
    if region.SetAlpha then region:SetAlpha(0) end
end

local function HideDecorativeTextures(frame)
    if not frame or IsForbidden(frame) or not frame.GetRegions then return end

    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            local layer = region.GetDrawLayer and region:GetDrawLayer()
            if layer == "BACKGROUND" or layer == "BORDER" then
                HideRegionTexture(region)
            end
        end
    end

    for _, key in ipairs({
        "BG", "Bg", "Background", "Border", "NineSlice", "Inset", "TopTileStreaks",
        "LeftBorder", "RightBorder", "TopBorder", "BottomBorder",
        "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
        "PortraitContainer", "TitleContainer",
    }) do
        local region = frame[key]
        if region and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
end

local function HideButtonTexture(texture)
    if not texture or not texture.SetAlpha then return end
    texture:SetAlpha(0)

    if not SkinBase.GetFrameData(texture, "systemPopupAlphaHooked") then
        SkinBase.SetFrameData(texture, "systemPopupAlphaHooked", true)
        hooksecurefunc(texture, "SetAlpha", function(self, alpha)
            if alpha and alpha > 0 then
                self:SetAlpha(0)
            end
        end)
    end
end

local function StripButtonTextures(button)
    if not button or IsForbidden(button) then return end

    for _, key in ipairs({ "Left", "Right", "Middle", "Center", "LeftSeparator", "RightSeparator" }) do
        HideButtonTexture(button[key])
    end

    if button.GetNormalTexture then HideButtonTexture(button:GetNormalTexture()) end
    if button.GetPushedTexture then HideButtonTexture(button:GetPushedTexture()) end
    if button.GetHighlightTexture then HideButtonTexture(button:GetHighlightTexture()) end
    if button.GetDisabledTexture then HideButtonTexture(button:GetDisabledTexture()) end

    if button.GetRegions then
        for i = 1, button:GetNumRegions() do
            HideRegionTexture(select(i, button:GetRegions()))
        end
    end

    if button.NineSlice then button.NineSlice:SetAlpha(0) end
end

local function RefreshButtonState(button)
    if not button or IsForbidden(button) then return end

    local enabled = not button.IsEnabled or button:IsEnabled()
    local backdrop = SkinBase.GetBackdrop(button)
    local normalBg = SkinBase.GetFrameData(button, "systemPopupNormalBg")
    local disabledBg = SkinBase.GetFrameData(button, "systemPopupDisabledBg")
    local border = SkinBase.GetFrameData(button, "systemPopupBorder")

    if backdrop then
        local bg = enabled and normalBg or disabledBg
        local borderColor = border and { border[1], border[2], border[3], enabled and border[4] or 0.35 } or nil
        SkinBase.SetBackdropColors(backdrop, borderColor, bg)
    end

    local text = button.GetFontString and button:GetFontString()
    if text then
        if enabled then
            text:SetTextColor(ThemeRole("tabHover", BUTTON_REST_FALLBACK))
        else
            text:SetTextColor(ThemeRole("disabled", BUTTON_DISABLED_FALLBACK))
        end
    end
end

local function StyleButton(button, prefix)
    if not button or IsForbidden(button) then return end

    local flash = button.Flash
    if flash then
        SkinBase.SetFrameData(flash, "systemPopupOwned", true)
        flash:SetTexture("Interface\\Buttons\\WHITE8x8")
        flash:SetTexCoord(0, 1, 0, 1)
        flash:ClearAllPoints()
        flash:SetAllPoints(button)
        local r, g, b = GetColors(prefix)
        flash:SetVertexColor(r, g, b, 0.15)
        SkinBase.RoundBarTexture(button, flash)
    end
    StripButtonTextures(button)

    local _, sr, sg, sb, sa, bgr, bgg, bgb, bga = ApplyBackdrop(button, prefix, SkinBase.CHROME.BUTTON_BOOST, 1, 5)

    SkinBase.SetFrameData(button, "systemPopupNormalBg", { bgr, bgg, bgb, bga })
    SkinBase.SetFrameData(button, "systemPopupHoverBg", {
        math.min(bgr + 0.12, 1),
        math.min(bgg + 0.12, 1),
        math.min(bgb + 0.12, 1),
        bga,
    })
    SkinBase.SetFrameData(button, "systemPopupDisabledBg", {
        math.max(bgr - 0.02, 0),
        math.max(bgg - 0.02, 0),
        math.max(bgb - 0.02, 0),
        0.45,
    })
    SkinBase.SetFrameData(button, "systemPopupBorder", { sr, sg, sb, sa })

    SkinBase.ApplyButtonFontObjects(button, { size = FONT_SIZE })

    if not SkinBase.GetFrameData(button, "systemPopupHooks") then
        SkinBase.SetFrameData(button, "systemPopupHooks", true)
        button:HookScript("OnEnter", function(self)
            local bd = SkinBase.GetBackdrop(self)
            local hoverBg = SkinBase.GetFrameData(self, "systemPopupHoverBg")
            local border = SkinBase.GetFrameData(self, "systemPopupBorder")
            if bd then SkinBase.SetBackdropColors(bd, border, hoverBg) end
            local text = self:GetFontString()
            if text and (not self.IsEnabled or self:IsEnabled()) then text:SetTextColor(ThemeRole("text", BUTTON_HOVER_FALLBACK)) end
        end)
        button:HookScript("OnLeave", RefreshButtonState)
        button:HookScript("OnEnable", RefreshButtonState)
        button:HookScript("OnDisable", RefreshButtonState)
    end

    RefreshButtonState(button)
end

local function StyleEditBox(editBox, prefix)
    if not editBox or IsForbidden(editBox) then return end

    HideDecorativeTextures(editBox)
    ApplyBackdrop(editBox, prefix, 0.02, 0.92, 4)

    if editBox.GetFont then
        SkinBase.SkinFontString(editBox, { size = FONT_SIZE, color = { 0.92, 0.92, 0.92, 1 } })
    end
end

local function StyleStaticMoney(popup)
    if not popup or IsForbidden(popup) or not StaticPopupsEnabled() then return end
    local input = popup.MoneyInputFrame
    if input and not IsForbidden(input) then
        for _, key in ipairs({ "gold", "silver", "copper" }) do
            StyleEditBox(input[key], "staticPopup")
        end
    end
    SkinBase.SkinFrameText(popup.MoneyFrame, { recurse = true })
end

local function StyleStaticItem(itemFrame)
    if not itemFrame or IsForbidden(itemFrame) or not StaticPopupsEnabled() then return end
    local popup = itemFrame.GetParent and itemFrame:GetParent()
    if IsForbidden(popup) then return end
    local item = itemFrame.Item
    if not item or IsForbidden(item) then return end
    SkinBase.ClampTextureHidden(itemFrame.NameFrame, true)
    ApplyBackdrop(itemFrame, "staticPopup", 0, nil, 4)
    SkinBase.SkinFontString(itemFrame.Text, { fontOnly = true })
    SkinBase.SkinFontString(item.Count, { fontOnly = true })
    local icon = item.Icon or item.icon
    local normal = item.GetNormalTexture and item:GetNormalTexture()
    if normal ~= icon then SkinBase.ClampTextureHidden(normal, true) end
    ApplyBackdrop(item, "staticPopup", 0, nil, 4)
    local border = SkinBase.SkinIcon(icon, { parent = item })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
    SkinBase.RoundIconTexture(item, icon)
    local nativeBorder = item.IconBorder
    SkinBase.HandleIconBorder(nativeBorder, border)
    if nativeBorder and border then
        local function reset()
            if not StaticPopupsEnabled() or IsForbidden(itemFrame) or IsForbidden(item) then return end
            local r, g, b, a = GetColors("staticPopup")
            SkinBase.SetBackdropColors(border, { r, g, b, a }, nil)
        end
        if not SkinBase.GetFrameData(nativeBorder, "systemPopupQualityHooked") then
            hooksecurefunc(nativeBorder, "Hide", reset)
            hooksecurefunc(nativeBorder, "SetShown", function(_, shown) if not shown then reset() end end)
            SkinBase.SetFrameData(nativeBorder, "systemPopupQualityHooked", true)
        end
        if nativeBorder:IsShown() then
            local r, g, b, a = nativeBorder:GetVertexColor()
            SkinBase.SetBackdropColors(border, { r, g, b, a }, nil)
        else
            reset()
        end
    end
    if not SkinBase.GetFrameData(itemFrame, "systemPopupItemHooked") then
        for _, method in ipairs({ "DisplayInfo", "DisplayInfoFromStandardCallback" }) do
            if type(itemFrame[method]) == "function" then hooksecurefunc(itemFrame, method, StyleStaticItem) end
        end
        SkinBase.SetFrameData(itemFrame, "systemPopupItemHooked", true)
    end
end

local function StyleStaticProgress(popup)
    if not popup or IsForbidden(popup) or not StaticPopupsEnabled() then return end
    local border, fill = popup.ProgressBarBorder, popup.ProgressBarFill
    if not border or not fill then return end
    SkinBase.SetFrameData(fill, "systemPopupOwned", true)
    SkinBase.ClampTextureHidden(border, true)
    local track = SkinBase.GetFrameData(popup, "systemPopupProgressTrack")
    if not track then
        track = CreateFrame("Frame", nil, popup)
        track.ignoreInLayout = true
        track:SetAllPoints(border)
        track:EnableMouse(false)
        local owner = CreateFrame("Frame", nil, popup)
        owner.ignoreInLayout = true
        owner:SetAllPoints(fill)
        owner:EnableMouse(false)
        SkinBase.RoundBarTexture(owner, fill)
        SkinBase.SetFrameData(popup, "systemPopupProgressTrack", track)
    end
    ApplyBackdrop(track, "staticPopup", 0, nil, 3)
    SkinBase.GetBackdrop(track):SetFrameLevel(math.max(0, SafeFrameLevel(popup) - 1))
    track:SetShown(border:IsShown())
end

local function StyleStaticClose(popup)
    if not popup or IsForbidden(popup) or not StaticPopupsEnabled() then return end
    local button = popup.CloseButton
    if not button or IsForbidden(button) then return end
    local _, r, g, b, a, br, bg, bb, ba = ApplyBackdrop(button, "staticPopup", 0.06, 1, 4)
    SkinBase.SetFrameData(button, "systemPopupBorder", { r, g, b, a })
    SkinBase.SetFrameData(button, "systemPopupNormalBg", { br, bg, bb, ba })
    SkinBase.SetFrameData(button, "systemPopupDisabledBg", { br, bg, bb, 0.45 })
    SkinBase.RoundIconTexture(button, button:GetNormalTexture())
    SkinBase.RoundIconTexture(button, button:GetPushedTexture())
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        highlight:ClearAllPoints()
        highlight:SetAllPoints(button)
        highlight:SetVertexColor(r, g, b, 0.15)
        SkinBase.RoundIconTexture(button, highlight)
    end
    if not SkinBase.GetFrameData(button, "systemPopupCloseHooked") then
        button:HookScript("OnLeave", RefreshButtonState)
        button:HookScript("OnEnable", RefreshButtonState)
        button:HookScript("OnDisable", RefreshButtonState)
        for _, method in ipairs({ "SetupCloseButton", "SetCloseButtonToHide", "SetCloseButtonToMinimize" }) do
            if type(popup[method]) == "function" then hooksecurefunc(popup, method, StyleStaticClose) end
        end
        SkinBase.SetFrameData(button, "systemPopupCloseHooked", true)
    end
    RefreshButtonState(button)
end

local function StyleStaticDropdown(popup)
    if not popup or IsForbidden(popup) or not StaticPopupsEnabled() then return end
    local dropdown = popup.Dropdown
    if not dropdown or IsForbidden(dropdown) then return end
    SkinBase.SkinDropdown(dropdown, { skinArrow = true, belowChildren = true })
    SkinBase.RefreshWidget(dropdown)
end

local function SkinStaticPopup(popup)
    if not popup or IsForbidden(popup) or not StaticPopupsEnabled() then return end

    if popup.ProgressBarFill then SkinBase.SetFrameData(popup.ProgressBarFill, "systemPopupOwned", true) end
    HideDecorativeTextures(popup)
    ApplyBackdrop(popup, "staticPopup", 0, nil)
    StyleStaticProgress(popup)
    StyleStaticClose(popup)
    StyleStaticDropdown(popup)

    local name = popup.GetName and popup:GetName()
    for i = 1, 4 do
        local button = (popup.GetButton and popup:GetButton(i))
            or popup["button" .. i] or (name and _G[name .. "Button" .. i])
        StyleButton(button, "staticPopup")
    end
    StyleButton(popup.ExtraButton or (name and _G[name .. "ExtraButton"]), "staticPopup")

    StyleEditBox((popup.GetEditBox and popup:GetEditBox())
        or popup.editBox or (name and _G[name .. "EditBox"]), "staticPopup")
    StyleStaticMoney(popup)
    StyleStaticItem(popup.ItemFrame)
    SkinBase.SkinFrameText(popup, { recurse = true })
    if type(popup.SetupMoneyFrame) == "function" and not SkinBase.GetFrameData(popup, "systemPopupMoneyHooked") then
        hooksecurefunc(popup, "SetupMoneyFrame", StyleStaticMoney)
        SkinBase.SetFrameData(popup, "systemPopupMoneyHooked", true)
    end

    if type(popup.SetupButtons) == "function" and not SkinBase.GetFrameData(popup, "systemPopupButtonsHooked") then
        for _, method in ipairs({ "SetupButtons", "SetupExtraButton" }) do
            if type(popup[method]) == "function" then hooksecurefunc(popup, method, SkinStaticPopup) end
        end
        SkinBase.SetFrameData(popup, "systemPopupButtonsHooked", true)
    end

    if type(popup.SetupProgressBar) == "function" and not SkinBase.GetFrameData(popup, "systemPopupProgressHooked") then
        hooksecurefunc(popup, "SetupProgressBar", StyleStaticProgress)
        SkinBase.SetFrameData(popup, "systemPopupProgressHooked", true)
    end

    if type(popup.SetupDropdown) == "function" and not SkinBase.GetFrameData(popup, "systemPopupDropdownHooked") then
        hooksecurefunc(popup, "SetupDropdown", StyleStaticDropdown)
        SkinBase.SetFrameData(popup, "systemPopupDropdownHooked", true)
    end

    if popup.SubText then SkinBase.LockFontObject(popup.SubText, { fontOnly = true }) end
    if popup.Text then SkinBase.LockFontObject(popup.Text, { fontOnly = true }) end

    if popup.UpdateRecapButton and not SkinBase.GetFrameData(popup, "systemPopupRecapHooked") then
        SkinBase.SetFrameData(popup, "systemPopupRecapHooked", true)
        hooksecurefunc(popup, "UpdateRecapButton", function(self)
            if not StaticPopupsEnabled() or IsForbidden(self) then return end
            local recapName = self.GetName and self:GetName()
            for i = 1, 4 do
                RefreshButtonState((self.GetButton and self:GetButton(i))
                    or self["button" .. i] or (recapName and _G[recapName .. "Button" .. i]))
            end
            RefreshButtonState(self.ExtraButton or (recapName and _G[recapName .. "ExtraButton"]))
        end)
    end
end

local function HookStaticPopups()
    local maxDialogs = _G.STATICPOPUP_NUMDIALOGS or 4
    for i = 1, maxDialogs do
        local popup = _G["StaticPopup" .. i]
        if popup and not SkinBase.GetFrameData(popup, "systemPopupShowHooked") then
            SkinBase.SetFrameData(popup, "systemPopupShowHooked", true)
            popup:HookScript("OnShow", SkinStaticPopup)
            if popup:IsShown() then SkinStaticPopup(popup) end
        end
    end
    return true
end

local function StyleMenuDecorations(frame, depth)
    if not frame or IsForbidden(frame) or depth < 0 then return end
    if frame.MinLevel and frame.MaxLevel then
        for _, key in ipairs({ "MinLevel", "MaxLevel" }) do
            local field = frame[key]
            local kind = type(field)
            if (kind == "table" or kind == "userdata") and not IsForbidden(field)
                and field.IsObjectType and field:IsObjectType("EditBox") then
                SkinBase.SkinEditBox(field, { font = false })
                SkinBase.RefreshWidget(field)
            end
        end
    end
    if frame.arrow and frame.arrow.SetDesaturated then
        frame.arrow:SetDesaturated(true)
        frame.arrow:SetVertexColor(0.9, 0.9, 0.9, 1)
    end
    if frame.GetRegions then
        for i = 1, frame:GetNumRegions() do
            local region = select(i, frame:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                local r, g, b, a = region:GetTextColor()
                if r > 0.9 and g > 0.65 and g < 0.95 and b < 0.2 then
                    region:SetTextColor(0.9, 0.9, 0.9, a)
                end
            end
        end
    end
    if frame.GetChildren then
        for i = 1, (frame:GetNumChildren() or 0) do
            StyleMenuDecorations(select(i, frame:GetChildren()), depth - 1)
        end
    end
end

local function SkinContextMenuFrame(frame, isCompositorMenu)
    if not frame or IsForbidden(frame) or not ContextMenusEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors("contextMenu")

    if frame.GetRegions then
        for i = 1, frame:GetNumRegions() do
            local region = select(i, frame:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end
    end

    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end

    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga, 6)
    local backdrop = SkinBase.GetBackdrop(frame)
    if backdrop then
        backdrop:SetFrameLevel(math.max(0, SafeFrameLevel(frame) - 1))
    end
    StyleMenuDecorations(frame, 4)
    if not isCompositorMenu then
        if SkinBase.ApplyButtonFontObjectsDeep then
            SkinBase.ApplyButtonFontObjectsDeep(frame, 3)
        end
    end
end

local function SkinLegacyDropdowns()
    if not ContextMenusEnabled() then return end

    local maxLevels = _G.UIDROPDOWNMENU_MAXLEVELS or 3
    for level = 1, maxLevels do
        local frame = _G["DropDownList" .. level]
        if frame and frame:IsShown() then
            SkinContextMenuFrame(frame)
        end
    end
end

local legacyDropdownHooksInstalled = false

local function HookLegacyDropdowns()
    if legacyDropdownHooksInstalled then return true end
    if not _G.ToggleDropDownMenu then return false end

    legacyDropdownHooksInstalled = true
    hooksecurefunc("ToggleDropDownMenu", function()
        Defer(SkinLegacyDropdowns)
    end)
    return true
end

local function OnMenuOpen(manager, _, menuDescription)
    if not ContextMenusEnabled() then return end

    Defer(function()
        local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
        if menu then
            SkinContextMenuFrame(menu, true)
        end

        if menuDescription and menuDescription.AddMenuAcquiredCallback and not menuCallbacks[menuDescription] then
            menuCallbacks[menuDescription] = true
            menuDescription:AddMenuAcquiredCallback(function(frame)
                Defer(function()
                    SkinContextMenuFrame(frame, true)
                end)
            end)
        end

        SkinLegacyDropdowns()
    end)
end

local function HookContextMenus()
    if not _G.Menu or not _G.Menu.GetManager then return false end
    local manager = _G.Menu.GetManager()
    if not manager then return false end
    if SkinBase.GetFrameData(manager, "quiContextMenuHooks") then return true end

    SkinBase.SetFrameData(manager, "quiContextMenuHooks", true)
    if manager.OpenMenu then
        hooksecurefunc(manager, "OpenMenu", function(self, ownerRegion, menuDescription)
            OnMenuOpen(self, ownerRegion, menuDescription)
        end)
    end
    if manager.OpenContextMenu then
        hooksecurefunc(manager, "OpenContextMenu", function(self, ownerRegion, menuDescription)
            OnMenuOpen(self, ownerRegion, menuDescription)
        end)
    end
    return true
end

local function RefreshOpenStaticPopups()
    local maxDialogs = _G.STATICPOPUP_NUMDIALOGS or 4
    for i = 1, maxDialogs do
        local popup = _G["StaticPopup" .. i]
        if popup and popup:IsShown() then
            SkinStaticPopup(popup)
        end
    end
end

local function RefreshOpenContextMenus()
    if _G.Menu and _G.Menu.GetManager then
        local manager = _G.Menu.GetManager()
        local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
        if menu then SkinContextMenuFrame(menu, true) end
    end
    SkinLegacyDropdowns()
end

_G.QUI_RefreshSystemPopupSkins = function()
    RefreshOpenStaticPopups()
    RefreshOpenContextMenus()
end

if ns.Registry then
    ns.Registry:Register("skinStaticPopups", {
        refresh = _G.QUI_RefreshSystemPopupSkins,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
    ns.Registry:Register("skinContextMenus", {
        refresh = _G.QUI_RefreshSystemPopupSkins,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local startupHooksComplete = false
local function InstallStartupHooks()
    if startupHooksComplete then return true end

    HookStaticPopups()
    local contextReady = HookContextMenus()
    local legacyReady = HookLegacyDropdowns()
    startupHooksComplete = contextReady and legacyReady
    return startupHooksComplete
end

if ns.WhenLoggedIn then ns.WhenLoggedIn(InstallStartupHooks) end
