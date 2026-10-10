local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function StyleDressUpGlyph(button, glyph)
    if not button then return end
    SkinBase.SkinButton(button, { strip = true, font = false })
    local text = SkinBase.GetFrameData(button, "qDressUpGlyph")
    if not text then
        text = button:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER", button, "CENTER", 0, 0)
        SkinBase.SetFrameData(button, "qDressUpGlyph", text)
    end
    SkinBase.SkinFontString(text, { size = 16, color = { 1, 1, 1, 1 } })
    text:SetText(glyph)
end

local function StyleDressUpHeader(frame)
    local title = frame.GetTitleText and frame:GetTitleText() or frame.TitleText or _G.DressUpFrameTitleText
    if title then SkinBase.SkinFontString(title, { color = { 1, 1, 1, 1 } }) end
    local maxMin = frame.MaximizeMinimizeFrame
    if maxMin then
        StyleDressUpGlyph(maxMin.MaximizeButton, "+")
        StyleDressUpGlyph(maxMin.MinimizeButton, "-")
    end
    StyleDressUpGlyph(frame.ToggleCustomSetDetailsButton, "=")
end

local function StyleTabardFrame(frame)
    if not IsSettingEnabled("skinTabard") or not frame then return end
    local preserved = {}
    for _, suffix in ipairs({ "TopRight", "TopLeft", "BottomRight", "BottomLeft" }) do
        local emblem = _G["TabardFrameEmblem" .. suffix]
        if emblem then preserved[emblem] = true end
    end
    local portrait = _G.TabardFramePortrait
    if portrait then preserved[portrait] = true end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" and not preserved[region] then region:SetAlpha(0) end
    end
    if portrait then SkinBase.RoundIconTexture(frame, portrait) end
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    SkinBase.SkinFrameText(frame, { chrome = true, color = { 0.953, 0.957, 0.965, 1 } })
    local customization = _G.TabardFrameCustomizationFrame
    if customization then SkinBase.StripTextures(customization) end
    for index = 1, 5 do
        local prefix = "TabardFrameCustomization" .. index
        local row = _G[prefix]
        if row then
            SkinBase.StripTextures(row)
            SkinBase.CreateBackdrop(row, sr, sg, sb, sa, r, g, b, a, 4)
            SkinBase.GetBackdrop(row):SetFrameLevel(math.max(0, row:GetFrameLevel() - 1))
            local label = _G[prefix .. "Text"]
            if label then
                label:ClearAllPoints()
                label:SetPoint("CENTER", row, "CENTER", 0, 0)
                label:SetWidth(math.max(1, row:GetWidth() - 48))
                label:SetHeight(row:GetHeight())
                label:SetWordWrap(false)
                SkinBase.SkinFontString(label, { color = { 0.953, 0.957, 0.965, 1 } })
            end
            for _, side in ipairs({ "Left", "Right" }) do
                local button = _G[prefix .. side .. "Button"]
                if button then
                    StyleDressUpGlyph(button, side == "Left" and "<" or ">")
                    button:SetSize(20, 20)
                    button:ClearAllPoints()
                    local point = side == "Left" and "LEFT" or "RIGHT"
                    button:SetPoint(point, row, point, 0, 0)
                    SkinBase.RefreshWidget(button)
                end
            end
        end
    end
    local left, right = _G.TabardCharacterModelRotateLeftButton, _G.TabardCharacterModelRotateRightButton
    if left then
        StyleDressUpGlyph(left, "<")
        left:SetSize(24, 24)
        SkinBase.RefreshWidget(left)
    end
    if right then
        StyleDressUpGlyph(right, ">")
        right:SetSize(24, 24)
        if left then
            right:ClearAllPoints()
            right:SetPoint("LEFT", left, "RIGHT", 4, 0)
        end
        SkinBase.RefreshWidget(right)
    end
    for _, name in ipairs({ "TabardFrameCostFrame", "TabardFrameMoneyBg" }) do
        local panel = _G[name]
        if panel then
            if name == "TabardFrameCostFrame" and panel.SetBackdrop then panel:SetBackdrop(nil) end
            SkinBase.StripTextures(panel)
            SkinBase.KillNineSlice(panel.NineSlice, true)
            SkinBase.CreateBackdrop(panel, sr, sg, sb, sa, r, g, b, a, 4)
        end
    end
    local moneyInset = _G.TabardFrameMoneyInset
    if moneyInset then
        SkinBase.StripTextures(moneyInset)
        SkinBase.KillNineSlice(moneyInset.NineSlice, true)
    end
    for _, name in ipairs({ "TabardFrameCostMoneyFrame", "TabardFrameMoneyFrame" }) do
        if _G[name] then SkinBase.SkinFrameText(_G[name], { recurse = true }) end
    end
    SkinBase.RefreshWidget(_G.TabardFrameAcceptButton)
    SkinBase.RefreshWidget(_G.TabardFrameCancelButton)
end

local function StyleRegistrarFrame(frame)
    if not IsSettingEnabled("skinGuildRegistrar") or not frame then return end
    local color = { 0.953, 0.957, 0.965, 1 }
    SkinBase.SkinFrameText(frame, { chrome = true, color = color })
    if frame.ScrollBar then SkinBase.SkinTrimScrollBar(frame.ScrollBar) end
    local petition = frame == _G.PetitionFrame
    if petition then
        for _, name in ipairs({
            "PetitionFrameCancelButton", "PetitionFrameSignButton", "PetitionFrameRequestButton", "PetitionFrameRenameButton",
        }) do
            local button = _G[name]
            if button then
                SkinBase.SkinButton(button, { strip = true, font = true })
                SkinBase.RefreshWidget(button)
            end
        end
    else
        for _, name in ipairs({ "GuildRegistrarGreetingFrame", "GuildRegistrarPurchaseFrame" }) do
            local page = _G[name]
            if page then SkinBase.SkinFrameText(page, { chrome = true, color = color }) end
        end
        for index = 1, 3 do
            local button = _G["GuildRegistrarButton" .. index]
            if button then
                SkinBase.SkinButton(button, { strip = false, font = true, radius = 4 })
                SkinBase.RefreshWidget(button)
            end
        end
        if _G.GuildRegistrarMoneyFrame then
            SkinBase.SkinFrameText(_G.GuildRegistrarMoneyFrame, { recurse = true })
        end
    end
    local npcName = _G[petition and "PetitionFrameNpcNameText" or "GuildRegistrarFrameNpcNameText"]
    if npcName then SkinBase.SkinFontString(npcName, { color = color }) end
    local portrait = _G[petition and "PetitionFramePortrait" or "GuildRegistrarFramePortrait"]
    if portrait then SkinBase.RoundIconTexture(frame, portrait) end
end

local function StyleTradeItem(side, index)
    if not IsSettingEnabled("skinTrade") then return end
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    local prefix = "Trade" .. side .. "Item" .. index
    local row, button, label = _G[prefix], _G[prefix .. "ItemButton"], _G[prefix .. "Name"]
    local name, _, _, quality, usable
    if side == "Recipient" and type(_G.GetTradeTargetItemInfo) == "function" then
        name, _, _, quality, usable = GetTradeTargetItemInfo(index)
    elseif side == "Player" and type(_G.GetTradePlayerItemInfo) == "function" then
        name, _, _, quality = GetTradePlayerItemInfo(index)
    end
    local rr, rg, rb = sr, sg, sb
    if side == "Recipient" and name and not usable then rr, rg, rb = 0.9, 0, 0 end
    if row then
        for _, region in ipairs({ row:GetRegions() }) do
            if region == row.SlotTexture or region == _G[prefix .. "NameFrame"] then region:SetAlpha(0) end
        end
        SkinBase.CreateBackdrop(row, rr, rg, rb, sa, r, g, b, a, 4)
        SkinBase.GetBackdrop(row):SetFrameLevel(math.max(0, row:GetFrameLevel() - 1))
    end
    if button then
        local qr, qg, qb = sr, sg, sb
        if quality and quality > 1 and C_Item and C_Item.GetItemQualityColor then
            qr, qg, qb = C_Item.GetItemQualityColor(quality)
            qr, qg, qb = qr or sr, qg or sg, qb or sb
        end
        SkinBase.CreateBackdrop(button, qr, qg, qb, sa, r, g, b, a, 4)
        SkinBase.GetBackdrop(button):SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
        if button.IconBorder then button.IconBorder:SetAlpha(0) end
        local normal = button.GetNormalTexture and button:GetNormalTexture()
        if normal then normal:SetAlpha(0) end
        SkinBase.RoundIconTexture(button, button.icon or button.Icon)
    end
    SkinBase.SkinFontString(label, { fontOnly = true })
end

local function StyleTradeWarning()
    if not IsSettingEnabled("skinTrade") then return end
    local action = _G.TradeFrameTradeButton
    if action and action.WarningIcon then action.WarningIcon:SetAlpha(1) end
    SkinBase.RefreshWidget(action)
end

local function StyleTradeFrame(frame)
    if not IsSettingEnabled("skinTrade") or not frame then return end
    SkinBase.StripTextures(frame)
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    for _, name in ipairs({
        "TradePlayerItemsInset", "TradeRecipientItemsInset", "TradePlayerEnchantInset",
        "TradeRecipientEnchantInset", "TradePlayerInputMoneyInset", "TradeRecipientMoneyInset", "TradeRecipientMoneyBg",
    }) do
        local panel = _G[name]
        if panel then
            if name == "TradeRecipientMoneyBg" then panel:SetAlpha(1) end
            SkinBase.StripTextures(panel)
            SkinBase.KillNineSlice(panel.NineSlice, true)
            SkinBase.CreateBackdrop(panel, sr, sg, sb, sa, r, g, b, a, 4)
        end
    end
    for _, name in ipairs({
        "TradeHighlightPlayer", "TradeHighlightRecipient", "TradeHighlightPlayerEnchant", "TradeHighlightRecipientEnchant",
    }) do
        local highlight = _G[name]
        if highlight then
            SkinBase.StripTextures(highlight)
            SkinBase.CreateBackdrop(highlight, 0.2, 0.8, 0.3, 1, 0.2, 0.8, 0.3, 0.12, 4)
        end
    end
    for _, side in ipairs({ "Player", "Recipient" }) do
        for index = 1, _G.MAX_TRADE_ITEMS or 7 do StyleTradeItem(side, index) end
    end
    for _, name in ipairs({ "TradeFramePlayerNameText", "TradeFrameRecipientNameText" }) do
        SkinBase.SkinFontString(_G[name], { color = { 0.953, 0.957, 0.965, 1 } })
    end
    local overlay = frame.RecipientOverlay
    if overlay then
        if overlay.portraitFrame then overlay.portraitFrame:SetAlpha(0) end
        SkinBase.RoundIconTexture(overlay, overlay.portrait)
    end
    SkinBase.SkinFrameText(_G.TradeRecipientMoneyFrame, { recurse = true })
    StyleTradeWarning()
    SkinBase.RefreshWidget(_G.TradeFrameCancelButton)
end

local function StyleItemUpgradeFrame(frame)
    if not IsSettingEnabled("skinItemUpgrade") or not frame then return end
    for _, key in ipairs({ "TopBG", "BottomBG", "BottomBGShadow", "IdleGlow", "MicaFleckSheen" }) do
        local texture = frame[key]
        if texture then texture:SetAlpha(0) end
    end
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    local slot = frame.UpgradeItemButton
    if slot then
        if slot.ButtonFrame then slot.ButtonFrame:SetAlpha(0) end
        if slot.IconBorder then slot.IconBorder:SetAlpha(0) end
        local qr, qg, qb = sr, sg, sb
        local quality = frame.upgradeInfo and frame.upgradeInfo.displayQuality
        if frame.upgradeAnimationsInProgress and frame.targetUpgradeLevelInfo then
            quality = frame.targetUpgradeLevelInfo.displayQuality
        end
        if quality and quality > 1 and C_Item and C_Item.GetItemQualityColor then
            qr, qg, qb = C_Item.GetItemQualityColor(quality)
            qr, qg, qb = qr or sr, qg or sg, qb or sb
        end
        SkinBase.CreateBackdrop(slot, qr, qg, qb, sa, r, g, b, a, 4)
        SkinBase.GetBackdrop(slot):SetFrameLevel(math.max(0, slot:GetFrameLevel() - 1))
        SkinBase.RoundIconTexture(slot, slot.icon or slot.Icon)
    end
    local cost = frame.UpgradeCostFrame
    if cost then
        if cost.BGTex then cost.BGTex:SetAlpha(0) end
        SkinBase.CreateBackdrop(cost, sr, sg, sb, sa, r, g, b, a, 4)
        SkinBase.SkinFrameText(cost, { recurse = true })
    end
    local currencies = frame.PlayerCurrenciesBorder
    if currencies then
        SkinBase.StripTextures(currencies)
        SkinBase.KillNineSlice(currencies.NineSlice, true)
        SkinBase.CreateBackdrop(currencies, sr, sg, sb, sa, r, g, b, a, 4)
    end
    SkinBase.SkinFrameText(frame.PlayerCurrencies, { recurse = true })
    SkinBase.SkinFrameText(frame.ItemInfo)
    SkinBase.SkinFontString(frame.MissingDescription, { color = { 0.953, 0.957, 0.965, 1 } })
    SkinBase.SkinFontString(frame.FrameErrorText, { fontOnly = true })
    for _, key in ipairs({ "LeftItemPreviewFrame", "RightItemPreviewFrame", "ItemHoverPreviewFrame" }) do
        local preview = frame[key]
        if preview then
            SkinBase.SkinWindow(preview, { noClose = true, noButtonFonts = true, radius = 4 })
            SkinBase.SkinFrameText(preview)
            if type(preview.GeneratePreviewTooltip) == "function"
                and not SkinBase.GetFrameData(preview, "qUpgradePreviewHooked") then
                hooksecurefunc(preview, "GeneratePreviewTooltip", function()
                    StyleItemUpgradeFrame(frame)
                end)
                SkinBase.SetFrameData(preview, "qUpgradePreviewHooked", true)
            end
        end
    end
    SkinBase.RefreshWidget(frame.UpgradeButton)
end

local function StyleSocketingFrame(frame)
    if not IsSettingEnabled("skinSocket") or not frame then return end
    SkinBase.StripTextures(frame)
    SkinBase.SkinFrameText(frame, { chrome = true, color = { 0.953, 0.957, 0.965, 1 } })
    local scroll = frame.ScrollFrame
    SkinBase.SkinTrimScrollBar(scroll and scroll.ScrollBar)
    local container = frame.SocketingContainer or frame
    local action = container.ApplySocketsButton or frame.ApplySocketsButton
    SkinBase.SkinButton(action, { strip = true, font = true })
    SkinBase.RefreshWidget(action)
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    for _, socket in ipairs(container.SocketFrames or {}) do
        local highlight = socket.GetHighlightTexture and socket:GetHighlightTexture()
        local pushed = socket.GetPushedTexture and socket:GetPushedTexture()
        for _, region in ipairs({ socket:GetRegions() }) do
            if region:GetObjectType() == "Texture" and region ~= socket.Icon and region ~= socket.Background
                and region ~= highlight and region ~= pushed then
                region:SetAlpha(0)
            end
        end
        SkinBase.CreateBackdrop(socket, sr, sg, sb, sa, r, g, b, a, 4)
        SkinBase.GetBackdrop(socket):SetFrameLevel(math.max(0, socket:GetFrameLevel() - 1))
        SkinBase.RoundIconTexture(socket, socket.Icon)
        local bracket = socket.BracketFrame
        SkinBase.SkinFontString(bracket and bracket.ColorText, { fontOnly = true })
    end
end

local function SkinStandardFrame(frame, settingKey)
    if not IsSettingEnabled(settingKey) then return end
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    local controls = {
        skinDressUp = { "DressUpFrameCancelButton", "DressUpFrameResetButton" },
        skinTrade = { "TradeFrameTradeButton", "TradeFrameCancelButton" },
        skinTabard = { "TabardFrameAcceptButton", "TabardFrameCancelButton" },
        skinGuildRegistrar = { "GuildRegistrarFrameGoodbyeButton", "GuildRegistrarFrameCancelButton", "GuildRegistrarFramePurchaseButton" },
    }
    for _, name in ipairs(controls[settingKey] or {}) do
        if _G[name] then SkinBase.SkinButton(_G[name], { strip = true, font = true }) end
    end
    if settingKey == "skinDressUp" then
        StyleDressUpHeader(frame)
        if frame.HookScript then frame:HookScript("OnShow", function() StyleDressUpHeader(frame) end) end
        if type(frame.SetTitle) == "function" then
            hooksecurefunc(frame, "SetTitle", function() StyleDressUpHeader(frame) end)
        end
        SkinBase.SkinButton(frame.ResetButton, { strip = true, font = true })
        SkinBase.SkinButton(frame.LinkButton, { strip = true, font = true })
        SkinBase.SkinDropdown(frame.CustomSetDropdown, { skinArrow = true })
        local sets = frame.CustomSetDropdown
        SkinBase.SkinButton(sets and sets.SaveButton, { strip = true, font = true })
        for _, panel in pairs({ frame.CustomSetDetailsPanel, frame.SetSelectionPanel }) do
            SkinBase.StripTextures(panel)
            SkinBase.KillNineSlice(panel.NineSlice, true)
            local sr, sg, sb, sa, r, g, b, alpha = SkinBase.GetWindowColors()
            SkinBase.CreateBackdrop(panel, sr, sg, sb, sa, r, g, b, alpha, 8)
            SkinBase.SkinFrameText(panel, { recurse = true })
            if type(panel.Refresh) == "function" then
                hooksecurefunc(panel, "Refresh", function(self) SkinBase.SkinFrameText(self, { recurse = true }) end)
            end
        end
    elseif settingKey == "skinTabard" then
        StyleTabardFrame(frame)
        if frame.HookScript then frame:HookScript("OnShow", function() StyleTabardFrame(frame) end) end
        if type(_G.TabardFrame_UpdateButtons) == "function" then
            hooksecurefunc("TabardFrame_UpdateButtons", function() StyleTabardFrame(frame) end)
        end
    elseif settingKey == "skinTrade" then
        StyleTradeFrame(frame)
        if type(_G.TradeFrame_UpdatePlayerItem) == "function" then
            hooksecurefunc("TradeFrame_UpdatePlayerItem", function(index) StyleTradeItem("Player", index) end)
        end
        if type(_G.TradeFrame_UpdateTargetItem) == "function" then
            hooksecurefunc("TradeFrame_UpdateTargetItem", function(index) StyleTradeItem("Recipient", index) end)
        end
        if type(_G.TradeFrame_UpdateWarnings) == "function" then
            hooksecurefunc("TradeFrame_UpdateWarnings", StyleTradeWarning)
        end
    elseif settingKey == "skinItemUpgrade" then
        SkinBase.SkinButton(frame.UpgradeButton, { strip = true, font = true })
        local upgrade = frame.ItemInfo
        SkinBase.SkinDropdown(upgrade and upgrade.Dropdown, { skinArrow = true })
        StyleItemUpgradeFrame(frame)
        for _, method in ipairs({ "UpdateUpgradeItemInfo", "ApplyTargetUpgradeLevel", "PopulatePreviewFrames", "PlayUpgradedCelebration" }) do
            if type(frame[method]) == "function" then
                hooksecurefunc(frame, method, function() StyleItemUpgradeFrame(frame) end)
            end
        end
    elseif settingKey == "skinSocket" then
        StyleSocketingFrame(frame)
        local container = frame.SocketingContainer
        if container and type(container.Update) == "function" then
            hooksecurefunc(container, "Update", function() StyleSocketingFrame(frame) end)
        end
    elseif settingKey == "skinGuildRegistrar" then
        if frame ~= _G.PetitionFrame and _G.GuildRegistrarFrameEditBox then
            SkinBase.SkinEditBox(_G.GuildRegistrarFrameEditBox)
        end
        StyleRegistrarFrame(frame)
        if frame == _G.PetitionFrame then
            if type(_G.PetitionFrame_Update) == "function" then
                hooksecurefunc("PetitionFrame_Update", function() StyleRegistrarFrame(frame) end)
            end
        else
            for _, method in ipairs({ "GuildRegistrar_OnShow", "GuildRegistrar_ShowPurchaseFrame" }) do
                if type(_G[method]) == "function" then
                    hooksecurefunc(method, function() StyleRegistrarFrame(frame) end)
                end
            end
        end
    end
    SkinBase.MarkSkinned(frame)
end

local function register(key, getFrame)
    if ns.Registry then
        ns.Registry:Register(key, {
            refresh = function()
                local frame = getFrame()
                SkinBase.RefreshFrameBackdropColors(frame)
                if SkinBase.IsSkinned(frame) then
                    if key == "skinSocket" then StyleSocketingFrame(frame)
                    elseif key == "skinItemUpgrade" then StyleItemUpgradeFrame(frame)
                    elseif key == "skinTrade" then StyleTradeFrame(frame)
                    elseif key == "skinGuildRegistrar" or key == "skinPetition" then StyleRegistrarFrame(frame)
                    elseif key == "skinTabard" then StyleTabardFrame(frame) end
                end
            end,
            priority = 80,
            group = "skinning",
            importCategories = { "skinning", "theme" },
        })
    end
end

register("skinDressUp", function() return _G.DressUpFrame end)
register("skinTrade", function() return _G.TradeFrame end)
register("skinItemUpgrade", function() return _G.ItemUpgradeFrame end)
register("skinSocket", function() return _G.ItemSocketingFrame end)
register("skinTabard", function() return _G.TabardFrame end)
register("skinGuildRegistrar", function() return _G.GuildRegistrarFrame end)
register("skinPetition", function() return _G.PetitionFrame end)

local function CanStyleLegacyText(object)
    local root = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not root or not object then return false end
    local owner = object
    while owner do
        if owner.IsForbidden and owner:IsForbidden() then return false end
        if owner == root then return true end
        owner = owner.GetParent and owner:GetParent()
    end
    return false
end

local function SkinLegacyText(frame)
    if not CanStyleLegacyText(frame) then return end
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 6, { fontOnly = true, guard = CanStyleLegacyText })
end

local function SkinLegacySideTabs()
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    for _, tab in ipairs(frame.Tabs or {}) do
        if tab.Icon and tab.SelectedTexture and tab:GetParent() == frame
            and not (tab.IsForbidden and tab:IsForbidden()) then
            SkinBase.ClampTextureHidden(tab.Background, true)
            SkinBase.ClampTextureHidden(tab.SelectedTexture, true)
            local r, g, b, a, br, bg, bb, ba = SkinBase.GetWindowColors()
            SkinBase.CreateBackdrop(tab, r, g, b, a, br, bg, bb, ba, 5)
            local chrome = SkinBase.GetBackdrop(tab)
            if chrome then chrome:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1)) end
            local ar, ag, ab = SkinBase.GetSkinColors()
            for _, key in ipairs({ "HighlightTexture", "TabGlow" }) do
                local texture = tab[key]
                if texture then
                    texture:SetColorTexture(ar, ag, ab, 0.08)
                    texture:ClearAllPoints()
                    texture:SetAllPoints(tab)
                    SkinBase.RoundIconTexture(tab, texture)
                end
            end
            local marker = SkinBase.GetFrameData(tab, "qLegacySideTabMarker")
            if not marker then
                marker = tab:CreateTexture(nil, "OVERLAY")
                SkinBase.SetFrameData(tab, "qLegacySideTabMarker", marker)
                SkinBase.RegisterScaleRefresh(tab, "legacySideTab", SkinLegacySideTabs)
            end
            local px = SkinBase.GetPixelSize(tab, 1)
            marker:SetColorTexture(ar, ag, ab, 1)
            marker:SetWidth(px)
            marker:ClearAllPoints()
            marker:SetPoint("TOPLEFT", tab, "TOPLEFT", px, -px)
            marker:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", px, px)
            marker:SetShown(tab.SelectedTexture:IsShown())
            if not SkinBase.GetFrameData(tab, "qLegacySideTabHooked") then
                hooksecurefunc(tab, "SetChecked", SkinLegacySideTabs)
                SkinBase.SetFrameData(tab, "qLegacySideTabHooked", true)
            end
        end
    end
end

local function SkinLegacyPageChrome()
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    for _, key in ipairs({ "RewardTrackPage", "ChallengesPage", "TreePage" }) do
        local page = frame[key]
        if page and not (page.IsForbidden and page:IsForbidden()) then
            SkinBase.ClampTextureHidden(page.Background, true)
            local divider = page.VerticalDivider
            if divider and not (divider.IsForbidden and divider:IsForbidden()) then
                local line = SkinBase.GetFrameData(divider, "qLegacyDividerLine")
                for _, region in ipairs({ divider:GetRegions() }) do
                    if region ~= line and region:IsObjectType("Texture") then SkinBase.ClampTextureHidden(region, true) end
                end
                if not line then
                    line = divider:CreateTexture(nil, "BORDER")
                    SkinBase.SetFrameData(divider, "qLegacyDividerLine", line)
                    SkinBase.RegisterScaleRefresh(divider, "legacyDivider", SkinLegacyPageChrome)
                end
                local r, g, b, a = SkinBase.GetWindowColors()
                line:SetColorTexture(r, g, b, a)
                line:SetAlpha(1)
                line:SetWidth(SkinBase.GetPixelSize(divider, 1))
                line:ClearAllPoints()
                line:SetPoint("TOP", divider, "TOP", 0, 0)
                line:SetPoint("BOTTOM", divider, "BOTTOM", 0, 0)
            end
        end
    end
end

local function SkinLegacyChallengePoints()
    local frame = _G.LegacySystemFrame
    local page = frame and frame.ChallengesPage
    local summary = page and page.LegacyChallengePointSummary
    local bar = summary and summary.PointsBar
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or not summary or not bar
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden())
        or (summary.IsForbidden and summary:IsForbidden())
        or (bar.IsForbidden and bar:IsForbidden()) then return end
    SkinBase.ClampTextureHidden(summary.ProgressBarBackground, true)
    SkinBase.ClampTextureHidden(bar.ProgressBarFrame, true)
    SkinBase.SkinStatusBar(bar, { backdrop = false })
    local r, g, b, a = SkinBase.GetSkinBarColor()
    bar:SetStatusBarColor(r, g, b, a)
    SkinBase.RoundBarTexture(bar, bar:GetStatusBarTexture())
    SkinBase.ApplyChromeBackdrop(bar, { radius = 4, withBackground = true })
    SkinBase.SkinFontString(bar.Text, { fontOnly = true })
    local shield = summary.Shield
    if shield and not (shield.IsForbidden and shield:IsForbidden()) then
        SkinBase.SkinFontString(shield.Points, { fontOnly = true })
    end
    if not SkinBase.GetFrameData(bar, "qLegacyChallengePointsHooked") and type(bar.Update) == "function" then
        hooksecurefunc(bar, "Update", SkinLegacyChallengePoints)
        SkinBase.SetFrameData(bar, "qLegacyChallengePointsHooked", true)
    end
end

local function SkinLegacyChallengeMeasurement()
    local frame = _G.LegacySystemFrame
    local page = frame and frame.ChallengesPage
    local list = page and page.DetailPane
    local box = list and list.ScrollBox
    local placeholder = _G.AchievementFrame and _G.AchievementFrame.PlaceholderHiddenDescription
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or not list or not box or not placeholder
        or list.buttonMixin ~= _G.LegacyChallengeTemplateMixin
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden())
        or (list.IsForbidden and list:IsForbidden())
        or (box.IsForbidden and box:IsForbidden())
        or (placeholder.IsForbidden and placeholder:IsForbidden()) then return end
    local view = box.GetView and box:GetView()
    if not view or type(view.GetElementExtentCalculator) ~= "function"
        or type(view.SetElementExtentCalculator) ~= "function" then return end
    local calculator = view:GetElementExtentCalculator()
    if type(calculator) ~= "function" then return end
    if not SkinBase.GetFrameData(placeholder, "qLegacyMeasurementHooked") then
        hooksecurefunc(placeholder, "SetFontObject", function(self, fontObject)
            local context = SkinBase.GetFrameData(self, "qLegacyMeasurementContext")
            if context and not context.applied and fontObject == "SystemFont_Shadow_Med1" then
                context.applied = true
                self:SetWidth(400)
                SkinBase.SkinFontString(self, { fontOnly = true })
            end
        end)
        SkinBase.SetFrameData(placeholder, "qLegacyMeasurementHooked", true)
    end
    local wrapper = SkinBase.GetFrameData(view, "qLegacyMeasurementCalculator")
    if calculator ~= wrapper then
        wrapper = function(dataIndex, elementData)
            if not IsSettingEnabled("skinLegacySystem") or _G.LegacySystemFrame ~= frame
                or frame.ChallengesPage ~= page or page.DetailPane ~= list
                or (frame.IsForbidden and frame:IsForbidden())
                or (page.IsForbidden and page:IsForbidden())
                or (list.IsForbidden and list:IsForbidden())
                or (box.IsForbidden and box:IsForbidden())
                or (placeholder.IsForbidden and placeholder:IsForbidden()) then
                return calculator(dataIndex, elementData)
            end
            local previous = SkinBase.GetFrameData(placeholder, "qLegacyMeasurementContext")
            local fontObject = placeholder:GetFontObject()
            local width = placeholder:GetWidth()
            SkinBase.SetFrameData(placeholder, "qLegacyMeasurementContext", {})
            local ok, extent = pcall(calculator, dataIndex, elementData)
            SkinBase.SetFrameData(placeholder, "qLegacyMeasurementContext", previous)
            placeholder:SetWidth(width)
            if not ok then
                if fontObject then placeholder:SetFontObject(fontObject) end
                error(extent, 0)
            end
            return extent
        end
        SkinBase.SetFrameData(view, "qLegacyMeasurementCalculator", wrapper)
    end
    view:SetElementExtentCalculator(wrapper)
    if type(view.GetDataProvider) == "function" and view:GetDataProvider() and type(box.Rebuild) == "function" then
        box:Rebuild(true)
    end
end

local function StyleLegacyCategoryRow(button)
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or not button
        or (frame.IsForbidden and frame:IsForbidden())
        or (button.IsForbidden and button:IsForbidden()) then return end
    local notification = button.NotificationIcon
    local alpha = notification and notification:GetAlpha()
    SkinBase.SkinCategoryButton(button, {
        isSelected = function(row) return row.selected == true end,
        selectedTextColor = { 1, 1, 1, 1 },
        textColor = { 0.92, 0.92, 0.92, 1 },
    })
    if notification then notification:SetAlpha(alpha) end
    SkinBase.ClampTextureHidden(button:GetNormalTexture(), true)
    SkinBase.ClampTextureHidden(button:GetHighlightTexture(), true)
    local backdrop = SkinBase.GetBackdrop(button)
    if backdrop then backdrop:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1)) end
    SkinBase.RefreshWidget(button)
    SkinBase.RefreshCategorySelected(button)
    if not SkinBase.GetFrameData(button, "qLegacyCategoryHooked") then
        for _, method in ipairs({ "Init", "SetSelected" }) do
            if type(button[method]) == "function" then
                hooksecurefunc(button, method, StyleLegacyCategoryRow)
            end
        end
        if type(button.CheckHighlightTitle) == "function" then
            hooksecurefunc(button, "CheckHighlightTitle", function(row)
                if IsSettingEnabled("skinLegacySystem")
                    and not (frame.IsForbidden and frame:IsForbidden())
                    and not (row.IsForbidden and row:IsForbidden()) then
                    SkinBase.RefreshCategorySelected(row)
                end
            end)
        end
        SkinBase.SetFrameData(button, "qLegacyCategoryHooked", true)
    end
end

local function StyleLegacyChallengeCard(button)
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or not button
        or (frame.IsForbidden and frame:IsForbidden())
        or (button.IsForbidden and button:IsForbidden()) then return end
    local list = frame.ChallengesPage and frame.ChallengesPage.DetailPane
    local owner = button:GetParent()
    local owned = false
    while owner do
        if owner == list then owned = true; break end
        owner = owner.GetParent and owner:GetParent()
    end
    if not owned then return end
    for _, key in ipairs({ "Background", "BackgroundTop", "BackgroundMiddle", "BackgroundBottom" }) do
        SkinBase.ClampTextureHidden(button[key], true)
    end
    local r, g, b, a = SkinBase.GetWindowColors()
    if button.IsSelected and button:IsSelected() then r, g, b, a = SkinBase.GetSkinColors() end
    local br, bg, bb, ba = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(button, r, g, b, a, br, bg, bb, ba, 5)
    SkinBase.GetBackdrop(button):SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
    SkinBase.SkinFrameText(button, { recurse = true })
    local tracked = button.Tracked
    if tracked and not (tracked.IsForbidden and tracked:IsForbidden()) then
        SkinBase.SkinCheckBox(tracked)
        local chrome = SkinBase.GetBackdrop(tracked)
        if chrome then
            local tr, tg, tb, ta = SkinBase.GetWindowColors()
            local ar, ag, ab, aa = SkinBase.GetSkinColors()
            if SkinBase.GetFrameData(tracked, "qLegacyTrackedHover") and tracked:IsEnabled() then
                tr, tg, tb, ta = ar, ag, ab, aa
            end
            SkinBase.ApplyChromeBackdrop(chrome, { radius = 3, withBackground = true, borderColor = { tr, tg, tb, ta } })
            chrome:SetFrameLevel(math.max(0, tracked:GetFrameLevel() - 1))
            local checked = tracked:GetCheckedTexture()
            if checked then checked:SetVertexColor(ar, ag, ab, 1) end
            local disabled = tracked:GetDisabledCheckedTexture()
            if disabled then disabled:SetVertexColor(ar * 0.5, ag * 0.5, ab * 0.5, 1) end
        end
        if not SkinBase.GetFrameData(tracked, "qLegacyTrackedHooked") then
            tracked:HookScript("OnEnter", function()
                SkinBase.SetFrameData(tracked, "qLegacyTrackedHover", true)
                StyleLegacyChallengeCard(button)
            end)
            tracked:HookScript("OnLeave", function()
                SkinBase.SetFrameData(tracked, "qLegacyTrackedHover", false)
                StyleLegacyChallengeCard(button)
            end)
            tracked:HookScript("OnDisable", function()
                SkinBase.SetFrameData(tracked, "qLegacyTrackedHover", false)
                StyleLegacyChallengeCard(button)
            end)
            tracked:HookScript("OnEnable", function() StyleLegacyChallengeCard(button) end)
            SkinBase.SetFrameData(tracked, "qLegacyTrackedHooked", true)
        end
    end
    local icon = button.Icon
    if icon and not (icon.IsForbidden and icon:IsForbidden()) and icon.texture then
        SkinBase.ClampTextureHidden(icon.frame, true)
        local border = SkinBase.SkinIcon(icon.texture, { parent = icon, crop = false, border = { r, g, b, a } })
        SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false, borderColor = { r, g, b, a } })
    end
    local shield = button.Shield
    if shield and not (shield.IsForbidden and shield:IsForbidden()) and shield.CheckBackground then
        shield.CheckBackground:SetColorTexture(br, bg, bb, ba)
        SkinBase.RoundIconTexture(shield, shield.CheckBackground)
    end
    SkinBase.RoundIconTexture(button, button.TitleBar)
    local selected = button.SelectedOverlay
    if selected then
        local ar, ag, ab = SkinBase.GetSkinColors()
        selected:SetColorTexture(ar, ag, ab, 0.08)
        SkinBase.RoundIconTexture(button, selected)
    end
    if not SkinBase.GetFrameData(button, "qLegacyCardHooked") then
        for _, method in ipairs({ "Init", "RefreshStateArt", "UpdateBackgroundForHeight", "Saturate", "Desaturate" }) do
            if type(button[method]) == "function" then hooksecurefunc(button, method, StyleLegacyChallengeCard) end
        end
        SkinBase.SetFrameData(button, "qLegacyCardHooked", true)
    end
end

local function StyleLegacyCriteria(criteria)
    local frame, objectives = _G.LegacySystemFrame, _G.LegacyChallengeObjectives
    if not IsSettingEnabled("skinLegacySystem") or not frame or not objectives or not criteria
        or criteria:GetParent() ~= objectives
        or (objectives.IsForbidden and objectives:IsForbidden())
        or (frame.IsForbidden and frame:IsForbidden())
        or (criteria.IsForbidden and criteria:IsForbidden()) then return end
    SkinBase.SkinFrameText(criteria, { recurse = true })
    local background = criteria.Background
    if background then
        local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
        background:SetColorTexture(r, g, b, a)
        SkinBase.RoundIconTexture(criteria, background)
    end
    local bar = criteria.ProgressBar
    if bar and not (bar.IsForbidden and bar:IsForbidden()) then
        SkinBase.ClampTextureHidden(criteria.ProgressBarBackground, true)
        SkinBase.ClampTextureHidden(bar.ProgressBarFrame, true)
        SkinBase.SkinStatusBar(bar, { backdrop = false })
        local r, g, b, a = SkinBase.GetSkinBarColor()
        bar:SetStatusBarColor(r, g, b, a)
        SkinBase.RoundBarTexture(bar, bar:GetStatusBarTexture())
        SkinBase.ApplyChromeBackdrop(bar, { radius = 4, withBackground = true })
    end
    if not SkinBase.GetFrameData(criteria, "qLegacyCriteriaHooked") and type(criteria.Init) == "function" then
        hooksecurefunc(criteria, "Init", StyleLegacyCriteria)
        SkinBase.SetFrameData(criteria, "qLegacyCriteriaHooked", true)
    end
end

local function SkinLegacyObjectives()
    local frame, objectives = _G.LegacySystemFrame, _G.LegacyChallengeObjectives
    if not IsSettingEnabled("skinLegacySystem") or not frame or not objectives
        or (frame.IsForbidden and frame:IsForbidden())
        or (objectives.IsForbidden and objectives:IsForbidden()) then return end
    local pool = objectives.criteriaPool
    if pool and type(pool.EnumerateActive) == "function" then
        for criteria in pool:EnumerateActive() do StyleLegacyCriteria(criteria) end
    end
end

local function SkinLegacyTrackNavigation(page)
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or page ~= frame.RewardTrackPage
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden()) then return end
    local track = page.LegacyRewardProgressFrame
    if not track or (track.IsForbidden and track:IsForbidden()) then return end
    for _, key in ipairs({ "LeftButton", "RightButton", "JumpLeftButton", "JumpRightButton" }) do
        local button = track[key]
        if button and not (button.IsForbidden and button:IsForbidden()) then
            local right = key == "RightButton" or key == "JumpRightButton"
            SkinBase.SkinNextPrevButton(button, right and "right" or "left", { inset = 2, size = 12 })
            local glyph = SkinBase.GetFrameData(button, "nextPrevGlyph")
            if glyph then
                if key == "JumpLeftButton" then glyph:SetText("«")
                elseif key == "JumpRightButton" then glyph:SetText("»") end
                glyph:SetAlpha(button:IsEnabled() and 1 or 0.35)
            end
            SkinBase.RefreshWidget(button)
            if not SkinBase.GetFrameData(button, "qLegacyNavigationHooked") then
                for _, script in ipairs({ "OnEnable", "OnDisable" }) do
                    button:HookScript(script, function() SkinLegacyTrackNavigation(page) end)
                end
                SkinBase.SetFrameData(button, "qLegacyNavigationHooked", true)
            end
        end
    end
end

local function StyleLegacyRewardCard(button, actualLevel, displayLevel, selected)
    local frame = _G.LegacySystemFrame
    local page = frame and frame.RewardTrackPage
    local track = page and page.LegacyRewardProgressFrame
    local clip = track and track.ClipFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or not track or not clip
        or not button or not button.GetParent or button:GetParent() ~= clip or not button.RewardCardBG
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden())
        or (track.IsForbidden and track:IsForbidden())
        or (clip.IsForbidden and clip:IsForbidden())
        or (button.IsForbidden and button:IsForbidden()) then return end
    if actualLevel ~= nil and displayLevel ~= nil then
        SkinBase.SetFrameData(button, "qLegacyRewardSelected", selected == true)
    end
    local isSelected = SkinBase.GetFrameData(button, "qLegacyRewardSelected")
    if isSelected == nil and track.GetCenterIndex and page.IsScrollingTrack then
        isSelected = page:IsScrollingTrack() and not track.moving and track:GetCenterIndex() == button.index
    end
    local r, g, b, a = SkinBase.GetWindowColors()
    local atlas = button.RewardCardBG:GetAtlas()
    if isSelected then
        r, g, b, a = SkinBase.GetSkinColors()
    elseif atlas and atlas == button.lastEarnedBackgroundFrameAtlas then
        r, g, b, a = 0.2, 0.7, 0.35, 1
    end
    SkinBase.ClampTextureHidden(button.RewardCardBG, true)
    local br, bg, bb, ba = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(button, r, g, b, a, br, bg, bb, ba, 5)
    SkinBase.GetBackdrop(button):SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
    SkinBase.SkinFrameText(button, { recurse = true })
    SkinBase.ClampTextureHidden(button.IconBorder, true)
    for _, key in ipairs({ "Icon", "LevelSquare" }) do
        local texture = button[key]
        if texture then
            if key == "LevelSquare" then texture:SetColorTexture(br, bg, bb, ba) end
            SkinBase.RoundIconTexture(button, texture)
            local border = SkinBase.SkinIcon(texture, { parent = button, crop = false, border = { r, g, b, a } })
            SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false, borderColor = { r, g, b, a } })
        end
    end
    if not SkinBase.GetFrameData(button, "qLegacyRewardCardHooked") and type(button.Refresh) == "function" then
        hooksecurefunc(button, "Refresh", StyleLegacyRewardCard)
        if type(button.SetInfo) == "function" then
            hooksecurefunc(button, "SetInfo", function(self)
                SkinBase.SetFrameData(self, "qLegacyRewardSelected", nil)
            end)
        end
        SkinBase.SetFrameData(button, "qLegacyRewardCardHooked", true)
    end
end

local function SkinLegacyRewardCards(page)
    local track = page and page.LegacyRewardProgressFrame
    if track and type(track.GetElements) == "function" then
        for _, button in ipairs(track:GetElements() or {}) do StyleLegacyRewardCard(button) end
    end
end

local function SkinLegacyParagon(page)
    local frame = _G.LegacySystemFrame
    local track = page and page.LegacyRewardProgressFrame
    local clip = track and track.ClipFrame
    local paragon = clip and clip.ParagonLevelFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or page ~= frame.RewardTrackPage
        or not track or not clip or not paragon
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden())
        or (track.IsForbidden and track:IsForbidden())
        or (clip.IsForbidden and clip:IsForbidden())
        or (paragon.IsForbidden and paragon:IsForbidden()) then return end
    SkinBase.ClampTextureHidden(paragon.Divider, true)
    SkinBase.ClampTextureHidden(paragon.IconBorder, true)
    local r, g, b, a = SkinBase.GetWindowColors()
    local br, bg, bb, ba = SkinBase.GetDepthColor("SUBPANEL")
    local background = paragon.LabelBackground
    if background then
        SkinBase.ClampTextureHidden(background, true)
        SkinBase.CreateBackdrop(paragon, r, g, b, a, br, bg, bb, ba, 4)
        local chrome = SkinBase.GetBackdrop(paragon)
        chrome:ClearAllPoints()
        chrome:SetPoint("TOPLEFT", background, "TOPLEFT", 0, 0)
        chrome:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", 0, 0)
        chrome:SetFrameLevel(math.max(0, paragon:GetFrameLevel() - 1))
    end
    SkinBase.SkinFrameText(paragon, { recurse = true })
    for _, key in ipairs({ "Icon", "LevelFrame" }) do
        local texture = paragon[key]
        if texture then
            if key == "LevelFrame" then texture:SetColorTexture(br, bg, bb, ba) end
            SkinBase.RoundIconTexture(paragon, texture)
            local border = SkinBase.SkinIcon(texture, { parent = paragon, crop = false, border = { r, g, b, a } })
            SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false, borderColor = { r, g, b, a } })
        end
    end
    local highlight = paragon.HighlightTexture
    if highlight then
        local ar, ag, ab = SkinBase.GetSkinColors()
        highlight:SetColorTexture(ar, ag, ab, 0.08)
        SkinBase.RoundIconTexture(paragon, highlight)
    end
    if not SkinBase.GetFrameData(track, "qLegacyParagonHooked") and type(track.Init) == "function" then
        hooksecurefunc(track, "Init", function() SkinLegacyParagon(page) end)
        SkinBase.SetFrameData(track, "qLegacyParagonHooked", true)
    end
end

local function SkinLegacyRewardTrack(page)
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or page ~= frame.RewardTrackPage
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden()) then return end
    SkinLegacyTrackNavigation(page)
    SkinLegacyRewardCards(page)
    SkinLegacyParagon(page)
    local bar = page.LegacyRewardProgressBar
    if not bar or (bar.IsForbidden and bar:IsForbidden()) then return end
    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetTexture("Interface\\Buttons\\WHITE8x8")
        SkinBase.RoundBarTexture(bar, fill)
    end
    local r, g, b, a = SkinBase.GetSkinBarColor()
    bar:SetStatusBarColor(r, g, b, a)
    SkinBase.ClampTextureHidden(page.ProgressBarBackground, true)
    SkinBase.ClampTextureHidden(bar.ProgressBarFrame, true)
    local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(bar, sr, sg, sb, sa, br, bg, bb, ba, 4)
    local chrome = SkinBase.GetBackdrop(bar)
    chrome:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    local textures = page.progressBarMaskTextures
    if type(textures) == "table" then
        local registered = {}
        for _, texture in ipairs(textures) do registered[texture] = true end
        local track = page.LegacyRewardProgressFrame
        local mask = track and track.ClipFrame and track.ClipFrame.Mask
        for _, texture in ipairs({ chrome:GetRegions() }) do
            if texture:IsObjectType("Texture") and not registered[texture] then
                textures[#textures + 1] = texture
                if mask and page.progressBarMasked then texture:AddMaskTexture(mask) end
            end
        end
    end
end

local function StyleLegacyTreeSelector(button)
    local frame = _G.LegacySystemFrame
    local page = frame and frame.TreePage
    local panel = page and page.LegacyTreeSelectionPanel
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or not panel or not button
        or not panel.TreeSelections or button:GetParent() ~= panel.TreeSelections
        or (panel.TreeSelections.IsForbidden and panel.TreeSelections:IsForbidden())
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden())
        or (panel.IsForbidden and panel:IsForbidden())
        or (button.IsForbidden and button:IsForbidden()) then return end
    SkinBase.ClampTextureHidden(button.Background, true)
    SkinBase.ClampTextureHidden(button.Ring, true)
    SkinBase.ClampTextureHidden(button.SelectedGlow, true)
    local r, g, b, a = SkinBase.GetWindowColors()
    if button:GetChecked() then r, g, b, a = SkinBase.GetSkinColors() end
    local br, bg, bb, ba = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(button, r, g, b, a, br, bg, bb, ba, 5)
    SkinBase.GetBackdrop(button):SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
    SkinBase.SkinFrameText(button, { recurse = true })
    local highlight = button.HighlightTexture
    if highlight then
        local ar, ag, ab = SkinBase.GetSkinColors()
        highlight:SetColorTexture(ar, ag, ab, 0.08)
        highlight:ClearAllPoints()
        highlight:SetAllPoints(button)
        SkinBase.RoundIconTexture(button, highlight)
    end
    if not SkinBase.GetFrameData(button, "qLegacyTreeSelectorHooked") then
        for _, method in ipairs({ "SetupLegacyTreeButton", "RefreshSelectionVisuals", "SetEnabledState" }) do
            if type(button[method]) == "function" then hooksecurefunc(button, method, StyleLegacyTreeSelector) end
        end
        SkinBase.SetFrameData(button, "qLegacyTreeSelectorHooked", true)
    end
end

local function SkinLegacyTreeSelectors()
    local frame = _G.LegacySystemFrame
    local page = frame and frame.TreePage
    local panel = page and page.LegacyTreeSelectionPanel
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or not panel
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden())
        or (panel.IsForbidden and panel:IsForbidden()) then return end
    for _, button in ipairs(panel.treeButtons or {}) do StyleLegacyTreeSelector(button) end
    if not SkinBase.GetFrameData(panel, "qLegacyTreeSelectionHooked") then
        for _, method in ipairs({ "RefreshTreeButtons", "UpdateSelection" }) do
            if type(panel[method]) == "function" then hooksecurefunc(panel, method, SkinLegacyTreeSelectors) end
        end
        SkinBase.SetFrameData(panel, "qLegacyTreeSelectionHooked", true)
    end
end

local function SkinLegacyPointSummary()
    local frame = _G.LegacySystemFrame
    local page = frame and frame.TreePage
    local summary = page and page.LegacyTreePointSummary
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or not summary
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden())
        or (summary.IsForbidden and summary:IsForbidden()) then return end
    local border = summary.Border
    if border then
        SkinBase.ClampTextureHidden(border, true)
        local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
        SkinBase.CreateBackdrop(summary, sr, sg, sb, sa, br, bg, bb, ba, 4)
        local chrome = SkinBase.GetBackdrop(summary)
        chrome:ClearAllPoints()
        chrome:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
        chrome:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
        chrome:SetFrameLevel(math.max(0, summary:GetFrameLevel() - 1))
    end
    SkinBase.SkinFontString(summary.AvailablePointsLabel, { fontOnly = true })
    local shield = summary.Shield
    if shield and not (shield.IsForbidden and shield:IsForbidden()) then
        SkinBase.SkinFontString(shield.Points, { fontOnly = true })
    end
    if not SkinBase.GetFrameData(summary, "qLegacyPointSummaryHooked") and type(summary.RefreshText) == "function" then
        hooksecurefunc(summary, "RefreshText", SkinLegacyPointSummary)
        SkinBase.SetFrameData(summary, "qLegacyPointSummaryHooked", true)
    end
end

local function SkinLegacySpentPoints(tree)
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or not tree
        or not frame.TreePage or tree ~= frame.TreePage.LegacyTreeTraitPanel
        or (frame.IsForbidden and frame:IsForbidden())
        or (tree.IsForbidden and tree:IsForbidden()) then return end
    local points = tree.SpentPointsFrame
    if not points or (points.IsForbidden and points:IsForbidden()) then return end
    SkinBase.ClampTextureHidden(points.Background, true)
    local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(points, sr, sg, sb, sa, br, bg, bb, ba, 4)
    SkinBase.GetBackdrop(points):SetFrameLevel(math.max(0, points:GetFrameLevel() - 1))
    SkinBase.SkinFontString(points.Text, { fontOnly = true })
end

local function SkinLegacySelectedTreeIcon(tree)
    local frame = _G.LegacySystemFrame
    local page = frame and frame.TreePage
    local icon = tree and tree.SelectedTreeIcon
    if not IsSettingEnabled("skinLegacySystem") or not frame or not page or not tree
        or tree ~= page.LegacyTreeTraitPanel or not icon
        or (frame.IsForbidden and frame:IsForbidden())
        or (page.IsForbidden and page:IsForbidden())
        or (tree.IsForbidden and tree:IsForbidden())
        or (icon.IsForbidden and icon:IsForbidden()) then return end
    SkinBase.ClampTextureHidden(icon.Ring, true)
    local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(icon, sr, sg, sb, sa, br, bg, bb, ba, 5)
    SkinBase.GetBackdrop(icon):SetFrameLevel(math.max(0, icon:GetFrameLevel() - 1))
    SkinBase.SkinFontString(icon.SelectedTreeLabel, { fontOnly = true })
    for _, key in ipairs({ "HighlightTexture", "CheckedTexture" }) do
        local texture = icon[key]
        if texture then
            local r, g, b = SkinBase.GetSkinColors()
            texture:SetColorTexture(r, g, b, key == "HighlightTexture" and 0.08 or 0.12)
            texture:ClearAllPoints()
            texture:SetAllPoints(icon)
            SkinBase.RoundIconTexture(icon, texture)
        end
    end
    if not SkinBase.GetFrameData(icon, "qLegacySelectedTreeIconHooked") then
        for _, method in ipairs({ "SetIconAtlas", "SetEnabledState", "UpdateHighlightTexture", "OnMouseDown", "OnMouseUp" }) do
            if type(icon[method]) == "function" then
                hooksecurefunc(icon, method, function() SkinLegacySelectedTreeIcon(tree) end)
            end
        end
        SkinBase.SetFrameData(icon, "qLegacySelectedTreeIconHooked", true)
    end
end

local function SkinLegacyTreeControls(tree)
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or not tree
        or not frame.TreePage or tree ~= frame.TreePage.LegacyTreeTraitPanel
        or (frame.IsForbidden and frame:IsForbidden())
        or (tree.IsForbidden and tree:IsForbidden()) then return end
    for _, key in ipairs({ "ApplyButton", "UndoButton", "ResetButton" }) do
        local button = tree[key]
        if button and not (button.IsForbidden and button:IsForbidden()) then
            local icon = button.Icon
            local alpha = icon and icon:GetAlpha()
            SkinBase.SkinButton(button, { strip = true, font = key == "ApplyButton", belowChildren = true })
            if icon then icon:SetAlpha(alpha) end
            SkinBase.RefreshWidget(button)
        end
    end
    SkinLegacySelectedTreeIcon(tree)
    SkinLegacySpentPoints(tree)
    if not SkinBase.GetFrameData(tree, "qLegacySpentPointsHooked") and type(tree.UpdateTreeCurrencyInfo) == "function" then
        hooksecurefunc(tree, "UpdateTreeCurrencyInfo", SkinLegacySpentPoints)
        SkinBase.SetFrameData(tree, "qLegacySpentPointsHooked", true)
    end
    if not SkinBase.GetFrameData(tree, "qLegacyTreeControlsHooked") and type(tree.UpdateConfigButtonsState) == "function" then
        hooksecurefunc(tree, "UpdateConfigButtonsState", SkinLegacyTreeControls)
        SkinBase.SetFrameData(tree, "qLegacyTreeControlsHooked", true)
    end
end

local function SkinLegacySystem()
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or SkinBase.IsSkinned(frame)
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    SkinBase.SkinWindow(frame, { depth = 6 })
    SkinLegacySideTabs()
    for _, page in ipairs(frame.Pages or {}) do SkinLegacyText(page) end
    SkinLegacyPageChrome()
    SkinLegacyChallengePoints()
    SkinLegacyObjectives()
    local objectives = _G.LegacyChallengeObjectives
    if objectives and type(objectives.Display) == "function" then
        hooksecurefunc(objectives, "Display", SkinLegacyObjectives)
    end
    local rewards = frame.RewardTrackPage
    SkinLegacyRewardTrack(rewards)
    if rewards then
        for _, method in ipairs({ "SetupRewardTrack", "SetupProgressDetails" }) do
            if type(rewards[method]) == "function" then
                hooksecurefunc(rewards, method, function(page)
                    if method == "SetupRewardTrack" then SkinLegacyText(page) end
                    SkinLegacyRewardTrack(page)
                end)
            end
        end
    end
    local challenges = frame.ChallengesPage
    if challenges then
        for _, key in ipairs({ "CategoryList", "DetailPane" }) do
            local list = challenges[key]
            if list then
                SkinBase.HookScrollBoxRowFonts(list.ScrollBox, 5)
                SkinBase.SkinTrimScrollBar(list.ScrollBar)
            end
        end
        if challenges.DetailPane then
            SkinLegacyChallengeMeasurement()
            SkinBase.HookScrollBoxAcquired(challenges.DetailPane.ScrollBox, StyleLegacyChallengeCard)
        end
        if challenges.CategoryList then
            SkinBase.HookScrollBoxAcquired(challenges.CategoryList.ScrollBox, StyleLegacyCategoryRow)
            SkinBase.SkinEditBox(challenges.CategoryList.SearchBox)
            SkinBase.SkinDropdown(challenges.CategoryList.FilterDropdown)
        end
    end
    SkinLegacyTreeSelectors()
    SkinLegacyPointSummary()
    local tree = frame.TreePage and frame.TreePage.LegacyTreeTraitPanel
    if tree then
        SkinLegacyTreeControls(tree)
        SkinBase.SkinEditBox(tree.SearchBox)
        local event = TalentFrameBaseMixin and TalentFrameBaseMixin.Event
            and TalentFrameBaseMixin.Event.TalentButtonAcquired
        if tree.RegisterCallback and event then
            tree:RegisterCallback(event, function(_, button)
                local page = frame.TreePage
                if not IsSettingEnabled("skinLegacySystem") or _G.LegacySystemFrame ~= frame
                    or not page or page.LegacyTreeTraitPanel ~= tree or not button
                    or (frame.IsForbidden and frame:IsForbidden())
                    or (page.IsForbidden and page:IsForbidden())
                    or (tree.IsForbidden and tree:IsForbidden())
                    or (button.IsForbidden and button:IsForbidden()) then return end
                local owner = button:GetParent()
                while owner do
                    if owner == tree then SkinLegacyText(button); return end
                    owner = owner.GetParent and owner:GetParent()
                end
            end, frame)
        end
    end
    SkinBase.MarkSkinned(frame)
end

if ns.Registry then
    ns.Registry:Register("skinLegacySystem", {
        refresh = function()
            local frame = _G.LegacySystemFrame
            if not IsSettingEnabled("skinLegacySystem") or not frame or not SkinBase.IsSkinned(frame)
                or (frame.IsForbidden and frame:IsForbidden()) then return end
            SkinBase.RefreshFrameBackdropColors(frame)
            SkinLegacySideTabs()
            for _, page in ipairs(frame.Pages or {}) do SkinLegacyText(page) end
            SkinLegacyPageChrome()
            SkinLegacyChallengePoints()
            SkinLegacyObjectives()
            SkinLegacyRewardTrack(frame.RewardTrackPage)
            local category = frame.ChallengesPage and frame.ChallengesPage.CategoryList
            if category then
                SkinBase.ForEachScrollBoxFrame(category.ScrollBox, StyleLegacyCategoryRow)
                SkinBase.RefreshWidget(category.SearchBox)
                SkinBase.RefreshWidget(category.FilterDropdown)
            end
            local detail = frame.ChallengesPage and frame.ChallengesPage.DetailPane
            if detail then
                SkinLegacyChallengeMeasurement()
                SkinBase.ForEachScrollBoxFrame(detail.ScrollBox, StyleLegacyChallengeCard)
            end
            SkinLegacyTreeSelectors()
            SkinLegacyPointSummary()
            local tree = frame.TreePage and frame.TreePage.LegacyTreeTraitPanel
            if tree then
                SkinLegacyTreeControls(tree)
                SkinBase.RefreshWidget(tree.SearchBox)
            end
        end,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_LegacySystem", SkinLegacySystem, 0)

local function StyleStableSlot(slot)
    local frame = _G.PetStableFrame
    if not IsSettingEnabled("skinStable") or not frame or not slot
        or (frame.IsForbidden and frame:IsForbidden())
        or (slot.IsForbidden and slot:IsForbidden()) then return end
    local name = slot:GetName()
    local icon = name and _G[name .. "IconTexture"]
    if not icon then return end
    local r, g, b, a = SkinBase.GetWindowColors()
    local background = slot.background
    if background and background.GetVertexColor then
        local nr, ng, nb = background:GetVertexColor()
        if nr == 1 and ng == 0.1 and nb == 0.1 then r, g, b, a = nr, ng, nb, 1 end
    end
    SkinBase.RoundIconTexture(slot, icon)
    local border = SkinBase.SkinIcon(icon, { parent = slot, crop = false, border = { r, g, b, a } })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false, borderColor = { r, g, b, a } })
    SkinBase.ClampTextureHidden(background, true)
    SkinBase.ClampTextureHidden(slot:GetNormalTexture(), true)
    for _, method in ipairs({ "GetHighlightTexture", "GetCheckedTexture", "GetPushedTexture" }) do
        local texture = slot[method] and slot[method](slot)
        if texture then
            texture:SetColorTexture(1, 1, 1, method == "GetHighlightTexture" and 0.12 or 0.2)
            texture:ClearAllPoints()
            texture:SetAllPoints(icon)
            SkinBase.RoundIconTexture(slot, texture)
        end
    end
    if not SkinBase.GetFrameData(slot, "qStableSlotHooked") and type(slot.Update) == "function" then
        hooksecurefunc(slot, "Update", StyleStableSlot)
        SkinBase.SetFrameData(slot, "qStableSlotHooked", true)
    end
end

local function StyleStableSlots()
    for _, name in ipairs({ "PetStableCurrentPet", "PetStableStabledPet1", "PetStableStabledPet2" }) do
        StyleStableSlot(_G[name])
    end
end

local function StyleStableModelControls()
    local frame = _G.PetStableFrame
    if not IsSettingEnabled("skinStable") or not frame
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    local scene = frame.modelScene
    local controls = scene and scene.ControlFrame
    if not controls or (scene.IsForbidden and scene:IsForbidden())
        or (controls.IsForbidden and controls:IsForbidden()) then return end
    for _, key in ipairs({ "zoomInButton", "zoomOutButton", "rotateLeftButton", "rotateRightButton", "resetButton" }) do
        local button = controls[key]
        if button and not (button.IsForbidden and button:IsForbidden()) then
            local icon = button.Icon
            local alpha = icon and icon:GetAlpha()
            SkinBase.SkinButton(button, { strip = true, font = false, belowChildren = true })
            if icon then icon:SetAlpha(alpha) end
            SkinBase.RefreshWidget(button)
        end
    end
end

local function StyleStableFooter()
    local frame = _G.PetStableFrame
    if not IsSettingEnabled("skinStable") or not frame
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    for _, name in ipairs({ "PetStableMoneyFrame", "PetStableCostMoneyFrame" }) do
        local money = _G[name]
        if money and not (money.IsForbidden and money:IsForbidden()) then
            SkinBase.SkinFrameText(money, { recurse = true })
            SkinBase.LockFrameTextObjects(money, 2)
            local border = money.Border
            if border and not (border.IsForbidden and border:IsForbidden()) then
                for _, key in ipairs({ "Left", "Right", "Middle" }) do
                    SkinBase.ClampTextureHidden(border[key], true)
                end
                SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = true })
                border:SetFrameLevel(money:GetFrameLevel())
            end
        end
    end
end

local function SkinStable()
    if not (ns.Client and ns.Client.isForever) then return end
    local frame = _G.PetStableFrame
    if not IsSettingEnabled("skinStable") or not frame or SkinBase.IsSkinned(frame)
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    SkinBase.SkinWindow(frame, { noButtonFonts = true })
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 4)
    SkinBase.SkinButton(frame.purchaseButton, { font = true })
    StyleStableSlots()
    StyleStableModelControls()
    StyleStableFooter()
    if frame.modelScene and frame.modelScene.Inset then
        SkinBase.KillNineSlice(frame.modelScene.Inset.NineSlice, true)
    end
    SkinBase.MarkSkinned(frame)
end

if ns.Registry then
    ns.Registry:Register("skinStable", {
        refresh = function()
            local frame = _G.PetStableFrame
            if not IsSettingEnabled("skinStable") or not frame or not SkinBase.IsSkinned(frame)
                or (frame.IsForbidden and frame:IsForbidden()) then return end
            SkinBase.RefreshFrameBackdropColors(frame)
            SkinBase.RefreshWidget(frame.purchaseButton)
            StyleStableSlots()
            StyleStableModelControls()
            StyleStableFooter()
        end,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_StableUI", SkinStable, 0)

SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
    SkinStandardFrame(_G.DressUpFrame, "skinDressUp")
    SkinStandardFrame(_G.TradeFrame, "skinTrade")
    SkinStandardFrame(_G.TabardFrame, "skinTabard")
    SkinStandardFrame(_G.GuildRegistrarFrame, "skinGuildRegistrar")
    SkinStandardFrame(_G.PetitionFrame, "skinGuildRegistrar")
end, 0)

SkinBase.OnAddOnLoaded("Blizzard_ItemUpgradeUI", function()
    SkinStandardFrame(_G.ItemUpgradeFrame, "skinItemUpgrade")
end, 0)

SkinBase.OnAddOnLoaded("Blizzard_ItemSocketingUI", function()
    SkinStandardFrame(_G.ItemSocketingFrame, "skinSocket")
end, 0)

local mirrorTimers = ns.Helpers.CreateStateTable()

local function StyleMirrorTimer(frame, legacy)
    if not IsSettingEnabled("skinMirrorTimers") or not frame then return end
    local name = legacy and frame:GetName()
    local bar = frame.StatusBar or (name and _G[name .. "StatusBar"])
    local text = frame.Text or (name and _G[name .. "Text"])
    if not bar then return end
    mirrorTimers[frame] = legacy or false
    ns.Helpers.ApplyBarStyle(bar, "Interface\\Buttons\\WHITE8x8")
    if not legacy then
        bar:SetStatusBarColor(SkinBase.GetSkinBarColor())
    end
    SkinBase.RoundBarTexture(bar, bar:GetStatusBarTexture())
    SkinBase.SkinFontString(text, { color = { 0.953, 0.957, 0.965, 1 } })
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            if legacy or region == frame.Border or region == frame.TextBorder
                or atlas == "ui-castingbar-background" then
                region:SetAlpha(0)
            end
        end
    end
    local backdrop = SkinBase.GetFrameData(frame, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetAllPoints(frame)
        backdrop:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(frame, "backdrop", backdrop)
    end
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    SkinBase.ApplyChromeBackdrop(backdrop, { radius = 4, borderPixels = 1, withBackground = true })
    ns.Helpers.SetFrameBackdropColor(backdrop, r, g, b, a)
    ns.Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)
end

local function RefreshMirrorTimers()
    for frame, legacy in pairs(mirrorTimers) do StyleMirrorTimer(frame, legacy) end
end

SkinBase.OnAddOnLoaded("Blizzard_MirrorTimer", function()
    local container = _G.MirrorTimerContainer
    for _, frame in ipairs(container and container.mirrorTimers or {}) do
        if frame.Setup and not SkinBase.GetFrameData(frame, "qMirrorHooked") then
            hooksecurefunc(frame, "Setup", function(self)
                StyleMirrorTimer(self, false)
            end)
            SkinBase.SetFrameData(frame, "qMirrorHooked", true)
        end
        StyleMirrorTimer(frame, false)
    end
    if type(_G.MirrorTimer_Show) == "function" and not SkinBase.GetFrameData(SkinBase, "qClassicMirrorHooked") then
        hooksecurefunc("MirrorTimer_Show", function()
            for index = 1, _G.MIRRORTIMER_NUMTIMERS or 3 do
                local frame = _G["MirrorTimer" .. index]
                if frame and frame:IsShown() then StyleMirrorTimer(frame, true) end
            end
        end)
        SkinBase.SetFrameData(SkinBase, "qClassicMirrorHooked", true)
    end
end, 0)
if ns.Registry then
    ns.Registry:Register("skinMirrorTimers", {
        refresh = RefreshMirrorTimers,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
