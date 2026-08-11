-- luacheck: read globals LootWonAlertFrame_SetUp MoneyWonAlertFrame_SetUp BonusRollFrame_StartBonusRoll BonusRollFrame

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local Alerts = {}
QUICore.Alerts = Alerts

local QUI_TEXT_COLOR = { 0.953, 0.957, 0.965, 1 }

local ICON_TEX_COORDS = { 0.08, 0.92, 0.08, 0.92 }

local function GetGeneralSettings()
    return Helpers.GetModuleDB("general") or {}
end

local function GetAlertSettings()
    local alerts = Helpers.GetModuleDB("alerts") or {}
    return alerts, GetGeneralSettings().skinAlerts
end

local function GetThemeColors()
    return SkinBase.GetSkinColors(GetGeneralSettings(), "alerts")
end

local _forceAlphaActive = {}
local _forceAlphaCallbacks = Helpers.CreateStateTable()

local function ForceAlpha(frame)
    if _forceAlphaActive[frame] then return end
    local cb = _forceAlphaCallbacks[frame]
    if not cb then
        cb = function()
            if frame and frame.SetAlpha and frame:GetAlpha() ~= 1 then
                _forceAlphaActive[frame] = true
                frame:SetAlpha(1)
                _forceAlphaActive[frame] = nil
            end
        end
        _forceAlphaCallbacks[frame] = cb
    end
    C_Timer.After(0, cb)
end

local function CreateAlertBackdrop(frame, xOffset1, yOffset1, xOffset2, yOffset2)
    local existing = SkinBase.GetFrameData(frame, "backdrop")
    if existing then return existing end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    backdrop:SetFrameLevel(frame:GetFrameLevel())
    backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset1 or 0, yOffset1 or 0)
    backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", xOffset2 or 0, yOffset2 or 0)
    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, false)
    Helpers.SetFrameBackdropColor(backdrop, bgr, bgg, bgb, bga)
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)

    SkinBase.SetFrameData(frame, "backdrop", backdrop)
    return backdrop
end

local function CreateIconAnchoredBackdrop(frame, anchorFrame, inset)
    if SkinBase.GetFrameData(frame, "backdrop") or not anchorFrame then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    backdrop:SetFrameLevel(frame:GetFrameLevel())
    backdrop:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", -inset, inset)
    backdrop:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 180, -inset)
    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, false)
    Helpers.SetFrameBackdropColor(backdrop, bgr, bgg, bgb, bga)
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)
    SkinBase.SetFrameData(frame, "backdrop", backdrop)
    return backdrop
end

local function GetQualityColor(hyperlink)
    if not hyperlink then return nil end
    local quality = C_Item.GetItemQualityByID(hyperlink)
    if quality and quality >= 1 then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        return { r = r, g = g, b = b }
    end
    return nil
end

local function CreateIconBorder(icon, parent, qualityColor)
    local sr, sg, sb, sa = GetThemeColors()

    local existingBorder = SkinBase.GetFrameData(icon, "border")
    if existingBorder then
        if qualityColor then
            Helpers.SetFrameBackdropBorderColor(existingBorder, qualityColor.r or qualityColor[1], qualityColor.g or qualityColor[2], qualityColor.b or qualityColor[3], 1)
        else
            Helpers.SetFrameBackdropBorderColor(existingBorder, sr, sg, sb, sa)
        end
        if parent then SkinBase.SetFrameData(parent, "iconBorder", existingBorder) end
        return existingBorder
    end

    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetFrameLevel(parent:GetFrameLevel() + 1)
    SkinBase.SetExpandedPixelPoints(border, icon, 2)
    SkinBase.ApplyPixelBackdrop(border, 1, false, false)

    if qualityColor then
        Helpers.SetFrameBackdropBorderColor(border, qualityColor.r or qualityColor[1], qualityColor.g or qualityColor[2], qualityColor.b or qualityColor[3], 1)
    else
        Helpers.SetFrameBackdropBorderColor(border, sr, sg, sb, sa)
    end

    SkinBase.SetFrameData(icon, "border", border)
    if parent then SkinBase.SetFrameData(parent, "iconBorder", border) end
    return border
end

local function StyleIcon(icon, parent, qualityColor)
    if not icon then return end

    icon:SetTexCoord(unpack(ICON_TEX_COORDS))
    icon:SetDrawLayer("ARTWORK")

    CreateIconBorder(icon, parent, qualityColor)
end

local function Kill(obj)
    if obj then
        if obj.UnregisterAllEvents then
            obj:UnregisterAllEvents()
        end
        if obj.SetAlpha then
            obj:SetAlpha(0)
        end
        if obj.Hide then
            obj:Hide()
        end
        if obj.SetTexture then
            obj:SetTexture(nil)
        end
    end
end

local function SkinAchievementAlert(frame)
    if frame and frame.Shield and frame.Shield.Points then
        SkinBase.LockFontObject(frame.Shield.Points, { fontOnly = true })
    end
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, -2, -6, -2, 6)

    Kill(frame.Background)
    Kill(frame.glow)
    Kill(frame.shine)
    Kill(frame.GuildBanner)
    Kill(frame.GuildBorder)

    if frame.Unlocked then
        frame.Unlocked:SetTextColor(unpack(QUI_TEXT_COLOR))
    end
    if frame.Name then
        frame.Name:SetTextColor(1, 0.82, 0)
    end

    if frame.Icon and frame.Icon.Texture then
        Kill(frame.Icon.Overlay)
        StyleIcon(frame.Icon.Texture, frame)
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinCriteriaAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, -2, -6, -2, 6)

    Kill(frame.Background)
    Kill(frame.glow)
    Kill(frame.shine)
    Kill(frame.Icon.Bling)
    Kill(frame.Icon.Overlay)

    if frame.Unlocked then frame.Unlocked:SetTextColor(unpack(QUI_TEXT_COLOR)) end
    if frame.Name then frame.Name:SetTextColor(1, 1, 0) end

    StyleIcon(frame.Icon.Texture, frame)

    SkinBase.MarkSkinned(frame)
end

local function RefreshAlertQualityColor(frame, icon)
    if not frame or not icon then return end
    local lootItem = frame.lootItem or frame
    local qualityColor = GetQualityColor(frame.hyperlink or (lootItem and lootItem.hyperlink))
    CreateIconBorder(icon, frame, qualityColor)
end

local function SuppressLootWonArt(frame, lootItem)
    Kill(frame.Background)
    Kill(frame.glow)
    Kill(frame.shine)
    Kill(frame.BGAtlas)
    Kill(frame.PvPBackground)
    Kill(lootItem.IconBorder)
    Kill(lootItem.SpecRing)
end

local function SkinLootWonAlert(frame)
    if not frame then return end
    local lootItem = frame.lootItem or frame

    if SkinBase.IsSkinned(frame) then
        SuppressLootWonArt(frame, lootItem)
        RefreshAlertQualityColor(frame, lootItem.Icon)
        return
    end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    SuppressLootWonArt(frame, lootItem)

    local qualityColor = GetQualityColor(frame.hyperlink or (lootItem and lootItem.hyperlink))

    StyleIcon(lootItem.Icon, frame, qualityColor)

    CreateIconAnchoredBackdrop(frame, SkinBase.GetFrameData(lootItem.Icon, "border"), 4)

    SkinBase.MarkSkinned(frame)
end

local function SkinLootUpgradeAlert(frame)
    if not frame then return end

    if SkinBase.IsSkinned(frame) then
        RefreshAlertQualityColor(frame, frame.Icon)
        return
    end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    Kill(frame.Background)
    Kill(frame.Sheen)
    Kill(frame.BorderGlow)

    frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
    frame.Icon:SetDrawLayer("BORDER", 5)

    local qualityColor = GetQualityColor(frame.hyperlink)

    CreateIconBorder(frame.Icon, frame, qualityColor)

    CreateIconAnchoredBackdrop(frame, SkinBase.GetFrameData(frame.Icon, "border"), 8)

    SkinBase.MarkSkinned(frame)
end

local function SkinMoneyWonAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    if frame.Background then frame.Background:SetAlpha(0) end
    if frame.IconBorder then frame.IconBorder:SetAlpha(0) end

    if frame.Icon then
        frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
    end

    if not SkinBase.GetFrameData(frame, "backdrop") then
        local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
        backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        SkinBase.ApplyPixelBackdrop(backdrop, 1, true, false)
        Helpers.SetFrameBackdropColor(backdrop, bgr, bgg, bgb, bga)
        Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)
        SkinBase.SetFrameData(frame, "backdrop", backdrop)
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinHonorAwardedAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    Kill(frame.Background)
    Kill(frame.IconBorder)

    StyleIcon(frame.Icon, frame)

    CreateIconAnchoredBackdrop(frame, SkinBase.GetFrameData(frame.Icon, "border"), 4)

    SkinBase.MarkSkinned(frame)
end

local function SkinNewRecipeLearnedAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, 19, -6, -23, 6)

    Kill(frame.glow)
    Kill(frame.shine)

    local regions = { frame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            Kill(region)
            break
        end
    end

    if frame.Icon then
        frame.Icon:SetMask("")
        frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.Icon:SetDrawLayer("BORDER", 5)
        frame.Icon:ClearAllPoints()
        frame.Icon:SetPoint("LEFT", SkinBase.GetFrameData(frame, "backdrop"), 9, 0)

        CreateIconBorder(frame.Icon, frame)
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinDungeonCompletionAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, -2, -6, -2, 6)

    if frame.glowFrame then
        Kill(frame.glowFrame)
        if frame.glowFrame.glow then Kill(frame.glowFrame.glow) end
    end

    Kill(frame.shine)
    Kill(frame.raidArt)
    Kill(frame.heroicIcon)
    Kill(frame.dungeonArt)
    Kill(frame.dungeonArt1)
    Kill(frame.dungeonArt2)
    Kill(frame.dungeonArt3)
    Kill(frame.dungeonArt4)

    if frame.dungeonTexture then
        frame.dungeonTexture:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.dungeonTexture:SetDrawLayer("OVERLAY")
        frame.dungeonTexture:ClearAllPoints()
        frame.dungeonTexture:SetPoint("LEFT", frame, 7, 0)

        CreateIconBorder(frame.dungeonTexture, frame)
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinScenarioAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, 4, 4, -7, 6)

    local regions = { frame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            local atlas = region:GetAtlas()
            if atlas == "Toast-IconBG" or atlas == "Toast-Frame" then
                Kill(region)
            end
        end
    end

    Kill(frame.shine)
    Kill(frame.glowFrame)
    if frame.glowFrame then Kill(frame.glowFrame.glow) end

    if frame.dungeonTexture then
        frame.dungeonTexture:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.dungeonTexture:ClearAllPoints()
        frame.dungeonTexture:SetPoint("LEFT", SkinBase.GetFrameData(frame, "backdrop"), 9, 0)
        frame.dungeonTexture:SetDrawLayer("OVERLAY")

        CreateIconBorder(frame.dungeonTexture, frame)
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinWorldQuestCompleteAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, 10, -6, -14, 6)

    Kill(frame.shine)
    Kill(frame.ToastBackground)

    if frame.QuestTexture then
        frame.QuestTexture:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.QuestTexture:SetDrawLayer("ARTWORK")

        CreateIconBorder(frame.QuestTexture, frame)
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinLegendaryItemAlert(frame, itemLink)
    if not frame then return end

    if SkinBase.IsSkinned(frame) then
        if frame.Icon and itemLink then
            local quality = C_Item.GetItemQualityByID(itemLink)
            if quality then
                local r, g, b = C_Item.GetItemQualityColor(quality)
                local border = SkinBase.GetFrameData(frame.Icon, "border")
                if border then Helpers.SetFrameBackdropBorderColor(border, r, g, b, 1) end
            end
        end
        return
    end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    Kill(frame.Background)
    Kill(frame.Background2)
    Kill(frame.Background3)
    Kill(frame.Ring1)
    Kill(frame.Particles3)
    Kill(frame.Particles2)
    Kill(frame.Particles1)
    Kill(frame.Starglow)
    Kill(frame.glow)
    Kill(frame.shine)

    CreateAlertBackdrop(frame, 20, -20, -20, 20)

    if frame.Icon then
        frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.Icon:SetDrawLayer("ARTWORK")

        local border = CreateIconBorder(frame.Icon, frame)

        if itemLink then
            local quality = C_Item.GetItemQualityByID(itemLink)
            if quality then
                local r, g, b = C_Item.GetItemQualityColor(quality)
                Helpers.SetFrameBackdropBorderColor(border, r, g, b, 1)
            end
        end
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinMiscAlert(frame)
    if not frame then return end

    if frame.Icon then
        CreateIconBorder(frame.Icon, frame, nil)
    end

    if SkinBase.IsSkinned(frame) then
        Kill(frame.IconBorder)
        return
    end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    Kill(frame.Background)
    Kill(frame.IconBorder)

    if frame.Icon then
        frame.Icon:SetMask("")
        frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.Icon:SetDrawLayer("BORDER", 5)

        CreateIconAnchoredBackdrop(frame, SkinBase.GetFrameData(frame.Icon, "border"), 8)
    end

    SkinBase.MarkSkinned(frame)
end

local function RestyleEntitlementAlertText(frame)
    if not frame or not frame.Title then return end
    SkinBase.SkinFontString(frame.Title, { fontOnly = true })
    SkinBase.LockFontObject(frame.Title, { fontOnly = true })
end

local function SkinEntitlementAlert(frame)
    if not frame then return end
    RestyleEntitlementAlertText(frame)
    if SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, 10, -6, -14, 6)

    Kill(frame.Background)
    Kill(frame.StandardBackground)
    Kill(frame.glow)
    Kill(frame.shine)

    if frame.Icon then
        frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.Icon:ClearAllPoints()
        frame.Icon:SetPoint("LEFT", SkinBase.GetFrameData(frame, "backdrop"), 9, 0)

        CreateIconBorder(frame.Icon, frame)
    end

    RestyleEntitlementAlertText(frame)
    SkinBase.MarkSkinned(frame)
end

local function SkinDigsiteCompleteAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, -16, -6, 13, 6)

    Kill(frame.glow)
    Kill(frame.shine)

    local regions = { frame:GetRegions() }
    if regions[1] then Kill(regions[1]) end

    if frame.DigsiteTypeTexture then
        frame.DigsiteTypeTexture:SetPoint("LEFT", -10, -14)
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinGuildChallengeAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, -2, -6, -2, 6)

    local region = select(2, frame:GetRegions())
    if region and region:IsObjectType("Texture") then
        if region:GetTexture() == [[Interface\GuildFrame\GuildChallenges]] then
            Kill(region)
        end
    end

    Kill(frame.glow)
    Kill(frame.shine)
    Kill(frame.EmblemBorder)

    if frame.EmblemIcon then
        CreateIconBorder(frame.EmblemIcon, frame)
        SetLargeGuildTabardTextures("player", frame.EmblemIcon)
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinInvasionAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    CreateAlertBackdrop(frame, 4, 4, -7, 6)

    if frame.GetRegions then
        local region, icon = frame:GetRegions()
        if region and region:IsObjectType("Texture") then
            if region:GetAtlas() == "legioninvasion-Toast-Frame" then
                Kill(region)
            end
        end

        if icon and icon:IsObjectType("Texture") then
            if icon:GetTexture() == 236293 then
                CreateIconBorder(icon, frame)
                icon:SetDrawLayer("OVERLAY")
                icon:SetTexCoord(unpack(ICON_TEX_COORDS))
            end
        end
    end

    SkinBase.MarkSkinned(frame)
end

local function SkinBonusRollPromptButton(btn)
    if not btn or SkinBase.IsStyled(btn) then return end
    local sr, sg, sb, sa = GetThemeColors()
    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetFrameLevel(btn:GetFrameLevel() + 1)
    border:SetAllPoints()
    SkinBase.ApplyPixelBackdrop(border, 1, false, false)
    Helpers.SetFrameBackdropBorderColor(border, sr, sg, sb, sa)
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl then hl:SetColorTexture(sr, sg, sb, 0.25) end
    SkinBase.MarkStyled(btn)
end

local function SkinBonusRollPrompt(frame)
    if not frame then return end
    local prompt = frame.PromptFrame
    if not prompt then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    if not SkinBase.IsSkinned(frame) then
        Kill(frame.Background)
        Kill(frame.IconBorder)
        Kill(frame.LootSpinnerBG)

        if not SkinBase.GetFrameData(frame, "backdrop") then
            local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            backdrop:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
            backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
            backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
            SkinBase.ApplyPixelBackdrop(backdrop, 1, true, false)
            Helpers.SetFrameBackdropColor(backdrop, bgr, bgg, bgb, bga)
            Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(frame, "backdrop", backdrop)
        end

        if prompt.Timer then
            prompt.Timer:SetStatusBarColor(sr, sg, sb, 1)
        end

        if prompt.InfoFrame then
            SkinBase.SkinFontString(prompt.InfoFrame.Label)
            SkinBase.SkinFontString(prompt.InfoFrame.Cost)
        end
        if frame.CurrentCountFrame then SkinBase.SkinFontString(frame.CurrentCountFrame.Text) end
        if frame.RollingFrame then
            SkinBase.SkinFontString(frame.RollingFrame.Label)
            if frame.RollingFrame.LootSpinnerFinalText then
                SkinBase.SkinFontString(frame.RollingFrame.LootSpinnerFinalText)
            end
        end

        SkinBonusRollPromptButton(prompt.RollButton)
        SkinBonusRollPromptButton(prompt.PassButton)

        SkinBase.MarkSkinned(frame)
    end

    if prompt.Icon then
        StyleIcon(prompt.Icon, prompt)
    end
end

local bonusRollHooked = false
local function HookBonusRollFrames()
    local _, enabled = GetAlertSettings()
    if not enabled or bonusRollHooked then return end

    local hooked = false
    if type(LootWonAlertFrame_SetUp) == "function" then
        hooksecurefunc("LootWonAlertFrame_SetUp", function(frame)
            if frame == BonusRollLootWonFrame then SkinLootWonAlert(frame) end
        end)
        hooked = true
    end
    if type(MoneyWonAlertFrame_SetUp) == "function" then
        hooksecurefunc("MoneyWonAlertFrame_SetUp", function(frame)
            if frame == BonusRollMoneyWonFrame then SkinMoneyWonAlert(frame) end
        end)
        hooked = true
    end
    if type(BonusRollFrame_StartBonusRoll) == "function" then
        hooksecurefunc("BonusRollFrame_StartBonusRoll", function()
            SkinBonusRollPrompt(BonusRollFrame)
        end)
        hooked = true
    end
    bonusRollHooked = hooked
end

local alertHolder = nil
local alertMover = nil

local POSITION, ANCHOR_POINT, Y_OFFSET = "TOP", "BOTTOM", -5

local function GetAlertAnchorRelativeFrame(relativeAlert)
    if not alertHolder then return relativeAlert end
    if relativeAlert == AlertFrame then return alertHolder end
    if AlertFrame and relativeAlert == AlertFrame.baseAnchorFrame then return alertHolder end
    return relativeAlert
end

local function AdjustQueuedAnchors(self, relativeAlert)
    relativeAlert = GetAlertAnchorRelativeFrame(relativeAlert)
    for alert in self.alertFramePool:EnumerateActive() do
        alert:ClearAllPoints()
        alert:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, Y_OFFSET)
        relativeAlert = alert
    end
    return relativeAlert
end

local function AdjustSimpleAnchors(self, relativeAlert)
    relativeAlert = GetAlertAnchorRelativeFrame(relativeAlert)
    local alert = self.alertFrame
    if alert:IsShown() then
        alert:ClearAllPoints()
        alert:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, Y_OFFSET)
        return alert
    end
    return relativeAlert
end

local function AdjustAnchorFrameAnchors(self, relativeAnchor)
    relativeAnchor = GetAlertAnchorRelativeFrame(relativeAnchor)
    local anchor = self.anchorFrame
    if anchor:IsShown() then
        anchor:ClearAllPoints()
        anchor:SetPoint(POSITION, relativeAnchor, ANCHOR_POINT, 0, Y_OFFSET)
        return anchor
    end
    return relativeAnchor
end

local function IsTalkingHeadSubSystem(alertFrameSubSystem)
    if alertFrameSubSystem.anchorFrame == TalkingHeadFrame then return true end
    if alertFrameSubSystem.alertFrame == TalkingHeadFrame then return true end
    local frame = alertFrameSubSystem.anchorFrame or alertFrameSubSystem.alertFrame
    if frame and frame:GetName() and frame:GetName():find("TalkingHead") then return true end
    return false
end

local function ReplaceSubSystemAnchors(alertFrameSubSystem)
    if IsTalkingHeadSubSystem(alertFrameSubSystem) then return end

    if alertFrameSubSystem.alertFramePool then
        alertFrameSubSystem.AdjustAnchors = AdjustQueuedAnchors
    elseif not alertFrameSubSystem.anchorFrame then
        alertFrameSubSystem.AdjustAnchors = AdjustSimpleAnchors
    else
        alertFrameSubSystem.AdjustAnchors = AdjustAnchorFrameAnchors
    end
end

local function PostAlertMove()
    if not alertHolder then return end

    AlertFrame:ClearAllPoints()
    AlertFrame:SetAllPoints(alertHolder)

    if GroupLootContainer then
        GroupLootContainer:ClearAllPoints()
        GroupLootContainer:SetPoint(POSITION, alertHolder, ANCHOR_POINT, 0, Y_OFFSET)
    end
end

local alertHolderHooked = false
local function CreateAlertMover()
    if not alertHolder then
        alertHolder = CreateFrame("Frame", "QUI_AlertFrameHolder", UIParent)
        alertHolder:SetSize(180, 20)
        alertHolder:SetPoint("TOP", UIParent, "TOP", 0, -20)
        alertHolder:SetMovable(true)
        alertHolder:SetClampedToScreen(true)

        alertMover = CreateFrame("Frame", "QUI_AlertFrameMover", alertHolder, "BackdropTemplate")
        alertMover:SetAllPoints(alertHolder)
        SkinBase.ApplyPixelBackdrop(alertMover, 1, true, false)
        Helpers.SetFrameBackdropColor(alertMover, 0.2, 0.8, 0.8, 0.5)
        Helpers.SetFrameBackdropBorderColor(alertMover, 0.2, 0.8, 0.8, 1)
        alertMover:EnableMouse(true)
        alertMover:SetMovable(true)
        alertMover:RegisterForDrag("LeftButton")
        alertMover:SetFrameStrata("FULLSCREEN_DIALOG")
        alertMover:Hide()

        local text = alertMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(ns.L["Alert Frames"])
        SkinBase.SkinFontString(text)
        alertMover.text = text

        alertMover:SetScript("OnDragStart", function(self)
            alertHolder:StartMoving()
        end)

        alertMover:SetScript("OnDragStop", function(self)
            alertHolder:StopMovingOrSizing()
        end)
    end

    for _, alertFrameSubSystem in ipairs(AlertFrame.alertFrameSubSystems) do
        ReplaceSubSystemAnchors(alertFrameSubSystem)
    end

    if not alertHolderHooked then
        alertHolderHooked = true
        hooksecurefunc(AlertFrame, "AddAlertFrameSubSystem", function(_, alertFrameSubSystem)
            C_Timer.After(0, function()
                ReplaceSubSystemAnchors(alertFrameSubSystem)
            end)
        end)
        hooksecurefunc(AlertFrame, "UpdateAnchors", function()
            C_Timer.After(0, PostAlertMove)
        end)
    end

    -- showingFrames ref can't drive a later Layout pass (taint hazard) -- mirrors
    if GroupLootContainer then
        GroupLootContainer:EnableMouse(false)
        C_Timer.After(0, function()
            if not GroupLootContainer then return end
            local mgr = GroupLootContainer.layoutParent
            ns.SafeCallMethodIfPresent("best-effort-style", mgr, "RemoveManagedFrame", GroupLootContainer)
            GroupLootContainer.ignoreFramePositionManager = true
            GroupLootContainer.ignoreInLayout = true
        end)
    end

    if WorldQuestCompleteAlertSystem and LootAlertSystem then
        AlertFrame:SetSubSystemAnchorPriority(WorldQuestCompleteAlertSystem, 100)
        AlertFrame:SetSubSystemAnchorPriority(LootAlertSystem, 200)
    end
end

local toastHolder = nil
local toastMover = nil
local eventToastHooked = false

local function AnchorEventToastToHolder()
    if EventToastManagerFrame and toastHolder then
        EventToastManagerFrame:ClearAllPoints()
        EventToastManagerFrame:SetPoint("TOP", toastHolder, "TOP")
    end
end

local function HookEventToastFrame()
    if eventToastHooked then return end
    if not EventToastManagerFrame then return false end

    local redirecting = false
    hooksecurefunc(EventToastManagerFrame, "SetPoint", function()
        if redirecting or not toastHolder then return end
        C_Timer.After(0, function()
            if not toastHolder then return end
            redirecting = true
            AnchorEventToastToHolder()
            redirecting = false
        end)
    end)

    eventToastHooked = true
    AnchorEventToastToHolder()
    return true
end

local function CreateEventToastMover()
    if not toastHolder then
        toastHolder = CreateFrame("Frame", "QUI_EventToastHolder", UIParent)
        toastHolder:SetSize(300, 20)
        toastHolder:SetPoint("TOP", UIParent, "TOP", 0, -150)
        toastHolder:SetMovable(true)
        toastHolder:SetClampedToScreen(true)

        toastMover = CreateFrame("Frame", "QUI_EventToastMover", toastHolder, "BackdropTemplate")
        toastMover:SetAllPoints(toastHolder)
        SkinBase.ApplyPixelBackdrop(toastMover, 1, true, false)
        Helpers.SetFrameBackdropColor(toastMover, 0.8, 0.6, 0.2, 0.5)
        Helpers.SetFrameBackdropBorderColor(toastMover, 0.8, 0.6, 0.2, 1)
        toastMover:EnableMouse(true)
        toastMover:SetMovable(true)
        toastMover:RegisterForDrag("LeftButton")
        toastMover:SetFrameStrata("FULLSCREEN_DIALOG")
        toastMover:Hide()

        local text = toastMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(ns.L["Event Toasts"])
        SkinBase.SkinFontString(text)
        toastMover.text = text

        toastMover:SetScript("OnDragStart", function(self)
            toastHolder:StartMoving()
        end)

        toastMover:SetScript("OnDragStop", function(self)
            toastHolder:StopMovingOrSizing()
            AnchorEventToastToHolder()
        end)
    end

    if not HookEventToastFrame() then
        local retries = 0
        local ticker
        ticker = C_Timer.NewTicker(0.5, function()
            retries = retries + 1
            if HookEventToastFrame() or retries >= 20 then
                ticker:Cancel()
            end
        end)
    end
end

local bnetToastHolder = nil
local bnetToastMover = nil
local bnetToastHooked = false

local function AnchorBNetToastToHolder()
    if BNToastFrame and bnetToastHolder then
        BNToastFrame:ClearAllPoints()
        BNToastFrame:SetPoint("TOP", bnetToastHolder, "TOP")
    end
end

local function HookBNetToastFrame()
    if bnetToastHooked then return end
    if not BNToastFrame then return false end

    local redirecting = false
    hooksecurefunc(BNToastFrame, "SetPoint", function()
        if redirecting or not bnetToastHolder then return end
        C_Timer.After(0, function()
            if not bnetToastHolder then return end
            redirecting = true
            AnchorBNetToastToHolder()
            redirecting = false
        end)
    end)

    bnetToastHooked = true
    AnchorBNetToastToHolder()
    return true
end

local function CreateBNetToastMover()
    if not bnetToastHolder then
        bnetToastHolder = CreateFrame("Frame", "QUI_BNetToastHolder", UIParent)
        bnetToastHolder:SetSize(300, 50)
        bnetToastHolder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -80)
        bnetToastHolder:SetMovable(true)
        bnetToastHolder:SetClampedToScreen(true)

        bnetToastMover = CreateFrame("Frame", "QUI_BNetToastMover", bnetToastHolder, "BackdropTemplate")
        bnetToastMover:SetAllPoints(bnetToastHolder)
        SkinBase.ApplyPixelBackdrop(bnetToastMover, 1, true, false)
        Helpers.SetFrameBackdropColor(bnetToastMover, 0.2, 0.6, 1.0, 0.5)
        Helpers.SetFrameBackdropBorderColor(bnetToastMover, 0.2, 0.6, 1.0, 1)
        bnetToastMover:EnableMouse(true)
        bnetToastMover:SetMovable(true)
        bnetToastMover:RegisterForDrag("LeftButton")
        bnetToastMover:SetFrameStrata("FULLSCREEN_DIALOG")
        bnetToastMover:Hide()

        local text = bnetToastMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(ns.L["Battle.Net Toasts"])
        SkinBase.SkinFontString(text)
        bnetToastMover.text = text

        bnetToastMover:SetScript("OnDragStart", function(self)
            bnetToastHolder:StartMoving()
        end)

        bnetToastMover:SetScript("OnDragStop", function(self)
            bnetToastHolder:StopMovingOrSizing()
            AnchorBNetToastToHolder()
        end)
    end

    if not HookBNetToastFrame() then
        local retries = 0
        local ticker
        ticker = C_Timer.NewTicker(0.5, function()
            retries = retries + 1
            if HookBNetToastFrame() or retries >= 20 then
                ticker:Cancel()
            end
        end)
    end
end

local function RefreshAlertColors()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    local alertSystems = {
        AchievementAlertSystem,
        CriteriaAlertSystem,
        MonthlyActivityAlertSystem,
        DungeonCompletionAlertSystem,
        GuildChallengeAlertSystem,
        InvasionAlertSystem,
        ScenarioAlertSystem,
        WorldQuestCompleteAlertSystem,
        HonorAwardedAlertSystem,
        LegendaryItemAlertSystem,
        LootAlertSystem,
        LootUpgradeAlertSystem,
        MoneyWonAlertSystem,
        EntitlementDeliveredAlertSystem,
        RafRewardDeliveredAlertSystem,
        DigsiteCompleteAlertSystem,
        NewRecipeLearnedAlertSystem,
        NewPetAlertSystem,
        NewMountAlertSystem,
        NewToyAlertSystem,
        NewCosmeticAlertFrameSystem,
        NewWarbandSceneAlertSystem,
    }

    for _, system in ipairs(alertSystems) do
        if system and system.alertFramePool then
            for frame in system.alertFramePool:EnumerateActive() do
                local bd = SkinBase.GetFrameData(frame, "backdrop")
                if bd then
                    Helpers.SetFrameBackdropColor(bd, bgr, bgg, bgb, bga)
                    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
                end
                local ib = SkinBase.GetFrameData(frame, "iconBorder")
                if ib then
                    Helpers.SetFrameBackdropBorderColor(ib, sr, sg, sb, sa)
                end
            end
        end
    end

    local moneyBd = BonusRollMoneyWonFrame and SkinBase.GetFrameData(BonusRollMoneyWonFrame, "backdrop")
    if moneyBd then
        Helpers.SetFrameBackdropColor(moneyBd, bgr, bgg, bgb, bga)
        Helpers.SetFrameBackdropBorderColor(moneyBd, sr, sg, sb, sa)
    end
    local lootBd = BonusRollLootWonFrame and SkinBase.GetFrameData(BonusRollLootWonFrame, "backdrop")
    if lootBd then
        Helpers.SetFrameBackdropColor(lootBd, bgr, bgg, bgb, bga)
        Helpers.SetFrameBackdropBorderColor(lootBd, sr, sg, sb, sa)
    end
end

_G.QUI_RefreshAlertColors = RefreshAlertColors

if ns.Registry then
    ns.Registry:Register("skinAlerts", {
        refresh = _G.QUI_RefreshAlertColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key      = "alerts",
        label    = ns.L["Skin Alerts"],
        category = "Skinning",
        prefix   = "alerts",
        db       = function(p) return p.general end,
        refresh  = function() if _G.QUI_RefreshAlertColors then _G.QUI_RefreshAlertColors() end end,
        legacy   = {},
    })
end

function Alerts:HookAlertSystems()
    local _, enabled = GetAlertSettings()
    if not enabled then return end

    local function DeferredHook(system, skinFunc)
        if system then
            hooksecurefunc(system, "setUpFunction", function(frame, ...)
                local args = { ... }
                local n = select("#", ...)
                C_Timer.After(0, function()
                    skinFunc(frame, unpack(args, 1, n))
                end)
            end)
        end
    end

    DeferredHook(AchievementAlertSystem, SkinAchievementAlert)
    DeferredHook(CriteriaAlertSystem, SkinCriteriaAlert)
    DeferredHook(MonthlyActivityAlertSystem, SkinCriteriaAlert)

    DeferredHook(DungeonCompletionAlertSystem, SkinDungeonCompletionAlert)
    DeferredHook(GuildChallengeAlertSystem, SkinGuildChallengeAlert)
    DeferredHook(InvasionAlertSystem, SkinInvasionAlert)
    DeferredHook(ScenarioAlertSystem, SkinScenarioAlert)
    DeferredHook(WorldQuestCompleteAlertSystem, SkinWorldQuestCompleteAlert)

    DeferredHook(HonorAwardedAlertSystem, SkinHonorAwardedAlert)

    DeferredHook(LegendaryItemAlertSystem, SkinLegendaryItemAlert)
    DeferredHook(LootAlertSystem, SkinLootWonAlert)
    DeferredHook(LootUpgradeAlertSystem, SkinLootUpgradeAlert)
    DeferredHook(MoneyWonAlertSystem, SkinMoneyWonAlert)
    DeferredHook(EntitlementDeliveredAlertSystem, SkinEntitlementAlert)
    DeferredHook(RafRewardDeliveredAlertSystem, SkinEntitlementAlert)

    DeferredHook(DigsiteCompleteAlertSystem, SkinDigsiteCompleteAlert)
    DeferredHook(NewRecipeLearnedAlertSystem, SkinNewRecipeLearnedAlert)

    DeferredHook(NewPetAlertSystem, SkinMiscAlert)
    DeferredHook(NewMountAlertSystem, SkinMiscAlert)
    DeferredHook(NewToyAlertSystem, SkinMiscAlert)
    DeferredHook(NewCosmeticAlertFrameSystem, SkinMiscAlert)
    DeferredHook(NewWarbandSceneAlertSystem, SkinMiscAlert)

    DeferredHook(GarrisonBuildingAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonMissionAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonShipMissionAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonRandomMissionAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonFollowerAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonShipFollowerAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonTalentAlertSystem, SkinMiscAlert)

    DeferredHook(NewRuneforgePowerAlertSystem, SkinMiscAlert)
    DeferredHook(SkillLineSpecsUnlockedAlertSystem, SkinMiscAlert)
    DeferredHook(GuildRenameAlertSystem, SkinMiscAlert)

    HookBonusRollFrames()
end

function Alerts:Initialize()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    local _, enabled = GetAlertSettings()
    local controlAnchors = GetGeneralSettings().controlAlertAnchors
    if enabled or controlAnchors then
        CreateAlertMover()
        CreateEventToastMover()
        CreateBNetToastMover()
    end

    if not enabled then return end

    self:HookAlertSystems()
end
