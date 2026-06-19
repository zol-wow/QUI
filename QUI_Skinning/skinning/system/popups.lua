local ADDON_NAME, ns = ...

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local SkinBase = ns.SkinBase

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

---------------------------------------------------------------------------
-- Context menu + StaticPopup skinning
--
-- Covers modern right-click menus created by Blizzard's Menu manager and the
-- shared StaticPopup dialogs used for summon confirmations, release spirit,
-- many confirmation prompts, and addon-defined StaticPopup dialogs.
---------------------------------------------------------------------------

local FONT_SIZE = 12
local FONT_FLAGS = "OUTLINE"

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
    return SkinBase.GetSkinColors(settings, prefix)
end

local function ApplyBackdrop(frame, prefix, bgBoost, bgAlpha)
    if not frame or IsForbidden(frame) then return nil end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors(prefix)
    local boost = bgBoost or 0
    local ar = math.min((bgr or 0) + boost, 1)
    local ag = math.min((bgg or 0) + boost, 1)
    local ab = math.min((bgb or 0) + boost, 1)
    local aa = bgAlpha or bga

    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, ar, ag, ab, aa)

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
        "BG", "Bg", "Background", "Border", "NineSlice", "Inset",
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

local function StyleFontString(fontString, size, r, g, b, a)
    if not fontString or not fontString.SetFont then return end
    local fontPath = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    CJKFont(fontString, fontPath, size or FONT_SIZE, FONT_FLAGS)
    if fontString.SetTextColor then
        fontString:SetTextColor(r or 0.9, g or 0.9, b or 0.9, a or 1)
    end
end

local function StyleFrameText(frame)
    if not frame or IsForbidden(frame) or not frame.GetRegions then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("FontString") then
            StyleFontString(region, FONT_SIZE, 0.9, 0.9, 0.9, 1)
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
    if not button then return end

    local enabled = not button.IsEnabled or button:IsEnabled()
    local backdrop = SkinBase.GetBackdrop(button)
    local normalBg = SkinBase.GetFrameData(button, "systemPopupNormalBg")
    local disabledBg = SkinBase.GetFrameData(button, "systemPopupDisabledBg")
    local border = SkinBase.GetFrameData(button, "systemPopupBorder")

    if backdrop then
        local bg = enabled and normalBg or disabledBg
        if bg then backdrop:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
        if border then backdrop:SetBackdropBorderColor(border[1], border[2], border[3], enabled and border[4] or 0.35) end
    end

    local text = button.GetFontString and button:GetFontString()
    if text then
        if enabled then
            text:SetTextColor(0.9, 0.9, 0.9, 1)
        else
            text:SetTextColor(0.45, 0.45, 0.45, 1)
        end
    end
end

local function StyleButton(button, prefix)
    if not button or IsForbidden(button) then return end

    StripButtonTextures(button)

    local _, sr, sg, sb, sa, bgr, bgg, bgb, bga = ApplyBackdrop(button, prefix, 0.07, 1)

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

    -- Drive the button's font OBJECTS so the QUI font face survives hover
    -- (StaticPopupButtonTemplate HighlightFont) and disable (DisabledFont);
    -- RefreshButtonState owns the text COLOR per enable/disable/hover state.
    SkinBase.ApplyButtonFontObjects(button, { size = FONT_SIZE })

    if not SkinBase.GetFrameData(button, "systemPopupHooks") then
        SkinBase.SetFrameData(button, "systemPopupHooks", true)
        button:HookScript("OnEnter", function(self)
            local bd = SkinBase.GetBackdrop(self)
            local hoverBg = SkinBase.GetFrameData(self, "systemPopupHoverBg")
            local border = SkinBase.GetFrameData(self, "systemPopupBorder")
            if bd and hoverBg then bd:SetBackdropColor(hoverBg[1], hoverBg[2], hoverBg[3], hoverBg[4]) end
            if bd and border then bd:SetBackdropBorderColor(border[1], border[2], border[3], border[4]) end
            local text = self:GetFontString()
            if text and (not self.IsEnabled or self:IsEnabled()) then text:SetTextColor(1, 1, 1, 1) end
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
    ApplyBackdrop(editBox, prefix, 0.02, 0.92)

    if editBox.GetFont then
        StyleFontString(editBox, FONT_SIZE, 0.92, 0.92, 0.92, 1)
    end
end

local function SkinStaticPopup(popup)
    if not popup or IsForbidden(popup) or not StaticPopupsEnabled() then return end

    HideDecorativeTextures(popup)
    ApplyBackdrop(popup, "staticPopup", 0, nil)
    StyleFrameText(popup)

    local name = popup.GetName and popup:GetName()
    for i = 1, 4 do
        local button = popup["button" .. i] or (name and _G[name .. "Button" .. i])
        StyleButton(button, "staticPopup")
    end
    StyleButton(popup.ExtraButton or (name and _G[name .. "ExtraButton"]), "staticPopup")

    StyleEditBox(popup.editBox or (name and _G[name .. "EditBox"]), "staticPopup")
    SkinBase.SkinFrameText(popup, { recurse = true })

    -- GameDialogMixin:SetupText re-SetFontObject's SubText/Text on every show; lock
    -- so the QUI face re-applies after each Blizzard re-assert (not only per OnShow).
    if popup.SubText then SkinBase.LockFontObject(popup.SubText, { fontOnly = true }) end
    if popup.Text then SkinBase.LockFontObject(popup.Text, { fontOnly = true }) end

    if popup.UpdateRecapButton and not SkinBase.GetFrameData(popup, "systemPopupRecapHooked") then
        SkinBase.SetFrameData(popup, "systemPopupRecapHooked", true)
        hooksecurefunc(popup, "UpdateRecapButton", function(self)
            -- Resolve buttons the SAME way the main loop does (lowercase parentKey may
            -- not exist on modern popups; fall back to the global capital-B name).
            local recapName = self.GetName and self:GetName()
            for i = 1, 4 do
                RefreshButtonState(self["button" .. i] or (recapName and _G[recapName .. "Button" .. i]))
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

-- isCompositorMenu: the frame belongs to Blizzard's modern Menu manager, whose
-- FontStrings are Compositor-managed and disallow SetFont. Reading or calling
-- SetFont on them reports "Use of function 'SetFont' is disallowed" via assertsafe
-- (which routes to the error handler and does NOT throw, so pcall can't suppress
-- it). For those menus we skin the frame/backdrop only and leave their text alone;
-- legacy DropDownList fontstrings are not Compositor-managed and still get the font.
local function SkinContextMenuFrame(frame, isCompositorMenu)
    if not frame or IsForbidden(frame) or not ContextMenusEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors("contextMenu")

    if frame.GetRegions then
        for i = 1, frame:GetNumRegions() do
            local region = select(i, frame:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                region:SetColorTexture(bgr, bgg, bgb, 1)
                region:SetAlpha(bga)
                SkinBase.SetInsetPixelPoints(region, frame, 1)
            end
        end
    end

    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end

    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local backdrop = SkinBase.GetBackdrop(frame)
    if backdrop then
        backdrop:SetFrameLevel(math.max(0, SafeFrameLevel(frame) - 1))
    end
    -- Compositor menus lock SetFont; skin frame/backdrop only (see note above).
    if not isCompositorMenu then
        SkinBase.SkinFrameText(frame, { recurse = true })
        if SkinBase.LockFrameTextObjects then
            SkinBase.LockFrameTextObjects(frame, 3)
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
local startupHooksComplete = false
local function InstallStartupHooks()
    if startupHooksComplete then return true end

    HookStaticPopups()
    local contextReady = HookContextMenus()
    local legacyReady = HookLegacyDropdowns()
    startupHooksComplete = contextReady and legacyReady
    return startupHooksComplete
end

eventFrame:SetScript("OnEvent", function(self, event, addon)
    if event ~= "ADDON_LOADED" or addon ~= ADDON_NAME then return end
    InstallStartupHooks()
    self:UnregisterEvent("ADDON_LOADED")
end)

-- LOD catch-up: PLAYER_LOGIN already fired before this module loads; the old
-- login-time retry runs immediately instead (idempotent with the handler above).
-- ns.WhenLoggedIn is nil only in the headless test harness, where the old
-- never-firing PLAYER_LOGIN registration was equally inert.
if ns.WhenLoggedIn then ns.WhenLoggedIn(InstallStartupHooks) end
