--- QUI Alert & Toast Skinning
--- Skins Blizzard alert frames with QUI styling and adds movers

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers

-- Module reference
local Alerts = {}
QUICore.Alerts = Alerts

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------

-- Text color
local QUI_TEXT_COLOR = { 0.953, 0.957, 0.965, 1 }

-- Icon styling
local ICON_TEX_COORDS = { 0.08, 0.92, 0.08, 0.92 }

---------------------------------------------------------------------------
-- HELPER FUNCTIONS
---------------------------------------------------------------------------

local function GetDB()
    return Helpers.GetProfile() or {}
end

local function GetGeneralSettings()
    return Helpers.GetModuleDB("general") or {}
end

local function GetAlertSettings()
    local alerts = Helpers.GetModuleDB("alerts") or {}
    local general = GetGeneralSettings()
    alerts.enabled = general.skinAlerts
    return alerts
end

--- Get theme colors from QUI skinning system
local function GetThemeColors()
    return Helpers.GetSkinColors()
end

--- Force alpha to 1 (prevents Blizzard fade animations)
local function ForceAlpha(frame, alpha, forced)
    if alpha ~= 1 and forced ~= true then
        frame:SetAlpha(1, true)
    end
end

--- Create QUI-styled backdrop for alert frames
local function CreateAlertBackdrop(frame, xOffset1, yOffset1, xOffset2, yOffset2)
    if frame.quiBackdrop then return frame.quiBackdrop end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    backdrop:SetFrameLevel(frame:GetFrameLevel())
    backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset1 or 0, yOffset1 or 0)
    backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", xOffset2 or 0, yOffset2 or 0)
    backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    backdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    frame.quiBackdrop = backdrop
    return backdrop
end

--- Update existing backdrop colors (for theme changes)
local function UpdateBackdropColors(frame)
    if not frame.quiBackdrop then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()
    frame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    frame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
end

--- Create icon border frame with optional quality color
--- @param icon texture The icon texture
--- @param parent frame The parent frame
--- @param qualityColor table|nil Optional {r, g, b} quality color for rarity border
local function CreateIconBorder(icon, parent, qualityColor)
    local sr, sg, sb, sa = GetThemeColors()

    -- If border already exists (pooled frame), just update the color
    if icon.quiBorder then
        if qualityColor then
            icon.quiBorder:SetBackdropBorderColor(qualityColor.r or qualityColor[1], qualityColor.g or qualityColor[2], qualityColor.b or qualityColor[3], 1)
        else
            icon.quiBorder:SetBackdropBorderColor(sr, sg, sb, sa)
        end
        return icon.quiBorder
    end

    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetFrameLevel(parent:GetFrameLevel() + 1)
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    -- Use quality color if provided, otherwise use skin accent
    if qualityColor then
        border:SetBackdropBorderColor(qualityColor.r or qualityColor[1], qualityColor.g or qualityColor[2], qualityColor.b or qualityColor[3], 1)
    else
        border:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    icon.quiBorder = border
    return border
end

--- Style an icon with tex coords and border
local function StyleIcon(icon, parent, qualityColor)
    if not icon then return end

    icon:SetTexCoord(unpack(ICON_TEX_COORDS))
    icon:SetDrawLayer("ARTWORK")

    local border = CreateIconBorder(icon, parent, qualityColor)
    icon:SetParent(border)
end

--- Kill (hide) a frame or texture
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

---------------------------------------------------------------------------
-- ALERT SKINNING FUNCTIONS
---------------------------------------------------------------------------

--- Skin Achievement Alert
local function SkinAchievementAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    -- Create backdrop
    CreateAlertBackdrop(frame, -2, -6, -2, 6)

    -- Kill Blizzard artwork
    Kill(frame.Background)
    Kill(frame.glow)
    Kill(frame.shine)
    Kill(frame.GuildBanner)
    Kill(frame.GuildBorder)

    -- Style text
    if frame.Unlocked then
        frame.Unlocked:SetTextColor(unpack(QUI_TEXT_COLOR))
    end
    if frame.Name then
        frame.Name:SetTextColor(1, 0.82, 0)  -- Gold for achievement name
    end

    -- Style icon
    if frame.Icon and frame.Icon.Texture then
        Kill(frame.Icon.Overlay)
        StyleIcon(frame.Icon.Texture, frame)
    end

    frame.quiSkinned = true
end

--- Skin Criteria Alert (achievement criteria)
local function SkinCriteriaAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
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

    frame.quiSkinned = true
end

--- Skin Loot Won Alert
local function SkinLootWonAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    Kill(frame.Background)
    Kill(frame.glow)
    Kill(frame.shine)
    Kill(frame.BGAtlas)
    Kill(frame.PvPBackground)

    local lootItem = frame.lootItem or frame
    Kill(lootItem.IconBorder)
    Kill(lootItem.SpecRing)

    -- Get quality color from item link
    local qualityColor = nil
    local hyperlink = frame.hyperlink or (lootItem and lootItem.hyperlink)
    if hyperlink then
        local quality = C_Item.GetItemQualityByID(hyperlink)
        if quality and quality >= 1 then
            local r, g, b = GetItemQualityColor(quality)
            qualityColor = { r = r, g = g, b = b }
        end
    end

    StyleIcon(lootItem.Icon, frame, qualityColor)

    -- Create backdrop anchored to icon
    if not frame.quiBackdrop and lootItem.Icon.quiBorder then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

        local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:SetPoint("TOPLEFT", lootItem.Icon.quiBorder, "TOPLEFT", -4, 4)
        backdrop:SetPoint("BOTTOMRIGHT", lootItem.Icon.quiBorder, "BOTTOMRIGHT", 180, -4)
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        frame.quiBackdrop = backdrop
    end

    frame.quiSkinned = true
end

--- Skin Loot Upgrade Alert
local function SkinLootUpgradeAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    Kill(frame.Background)
    Kill(frame.Sheen)
    Kill(frame.BorderGlow)

    frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
    frame.Icon:SetDrawLayer("BORDER", 5)

    -- Get quality color from item link
    local qualityColor = nil
    local hyperlink = frame.hyperlink
    if hyperlink then
        local quality = C_Item.GetItemQualityByID(hyperlink)
        if quality and quality >= 1 then
            local r, g, b = GetItemQualityColor(quality)
            qualityColor = { r = r, g = g, b = b }
        end
    end

    local border = CreateIconBorder(frame.Icon, frame, qualityColor)
    frame.Icon:SetParent(border)

    -- Create backdrop
    if not frame.quiBackdrop and frame.Icon.quiBorder then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

        local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:SetPoint("TOPLEFT", frame.Icon.quiBorder, "TOPLEFT", -8, 8)
        backdrop:SetPoint("BOTTOMRIGHT", frame.Icon.quiBorder, "BOTTOMRIGHT", 180, -8)
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        frame.quiBackdrop = backdrop
    end

    frame.quiSkinned = true
end

--- Skin Money Won Alert
local function SkinMoneyWonAlert(frame)
    if not frame or frame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    -- Hide Blizzard textures
    if frame.Background then frame.Background:SetAlpha(0) end
    if frame.IconBorder then frame.IconBorder:SetAlpha(0) end

    -- Style icon
    if frame.Icon then
        frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
    end

    -- Create backdrop
    if not frame.quiBackdrop then
        local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
        backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        frame.quiBackdrop = backdrop
    end

    frame.quiSkinned = true
end

--- Skin Honor Awarded Alert
local function SkinHonorAwardedAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    Kill(frame.Background)
    Kill(frame.IconBorder)

    StyleIcon(frame.Icon, frame)

    if not frame.quiBackdrop and frame.Icon.quiBorder then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

        local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:SetPoint("TOPLEFT", frame.Icon.quiBorder, "TOPLEFT", -4, 4)
        backdrop:SetPoint("BOTTOMRIGHT", frame.Icon.quiBorder, "BOTTOMRIGHT", 180, -4)
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        frame.quiBackdrop = backdrop
    end

    frame.quiSkinned = true
end

--- Skin New Recipe Learned Alert
local function SkinNewRecipeLearnedAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    CreateAlertBackdrop(frame, 19, -6, -23, 6)

    Kill(frame.glow)
    Kill(frame.shine)

    -- Kill background texture (first region)
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
        frame.Icon:SetPoint("LEFT", frame.quiBackdrop, 9, 0)

        local border = CreateIconBorder(frame.Icon, frame)
        frame.Icon:SetParent(border)
    end

    frame.quiSkinned = true
end

--- Skin Dungeon Completion Alert
local function SkinDungeonCompletionAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
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

        local border = CreateIconBorder(frame.dungeonTexture, frame)
        frame.dungeonTexture:SetParent(border)
    end

    frame.quiSkinned = true
end

--- Skin Scenario Alert
local function SkinScenarioAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    CreateAlertBackdrop(frame, 4, 4, -7, 6)

    -- Kill atlas backgrounds
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
        frame.dungeonTexture:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        frame.dungeonTexture:ClearAllPoints()
        frame.dungeonTexture:SetPoint("LEFT", frame.quiBackdrop, 9, 0)
        frame.dungeonTexture:SetDrawLayer("OVERLAY")

        local border = CreateIconBorder(frame.dungeonTexture, frame)
        frame.dungeonTexture:SetParent(border)
    end

    frame.quiSkinned = true
end

--- Skin World Quest Complete Alert
local function SkinWorldQuestCompleteAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    CreateAlertBackdrop(frame, 10, -6, -14, 6)

    Kill(frame.shine)
    Kill(frame.ToastBackground)

    if frame.QuestTexture then
        frame.QuestTexture:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.QuestTexture:SetDrawLayer("ARTWORK")

        local border = CreateIconBorder(frame.QuestTexture, frame)
        frame.QuestTexture:SetParent(border)
    end

    frame.quiSkinned = true
end

--- Skin Legendary Item Alert
local function SkinLegendaryItemAlert(frame, itemLink)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
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
        frame.Icon:SetParent(border)

        -- Color border by item quality
        if itemLink then
            local quality = C_Item.GetItemQualityByID(itemLink)
            if quality then
                local r, g, b = GetItemQualityColor(quality)
                border:SetBackdropBorderColor(r, g, b, 1)
            end
        end
    end

    frame.quiSkinned = true
end

--- Get quality color for misc alerts (mounts, toys, pets)
--- Returns nil to use the user's skin accent color
local function GetMiscAlertQuality(frame)
    -- Just use the user's skin accent color for mounts/toys/pets
    -- Quality detection is unreliable, accent color is cleaner and consistent
    return nil
end

--- Skin Misc Alerts (Pets, Mounts, Toys, Cosmetics, Warband)
local function SkinMiscAlert(frame)
    if not frame then return end

    -- Always update quality color (frames are pooled and reused)
    local qualityColor = nil
    if frame.Icon then
        qualityColor = GetMiscAlertQuality(frame)
        -- Update existing border color or create new one
        CreateIconBorder(frame.Icon, frame, qualityColor)
    end

    -- Skip structural changes if already skinned (pooled frame)
    if frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    Kill(frame.Background)
    Kill(frame.IconBorder)

    if frame.Icon then
        frame.Icon:SetMask("")
        frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
        frame.Icon:SetDrawLayer("BORDER", 5)

        local border = frame.Icon.quiBorder
        frame.Icon:SetParent(border)

        if not frame.quiBackdrop then
            local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

            local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            backdrop:SetFrameLevel(frame:GetFrameLevel())
            backdrop:SetPoint("TOPLEFT", border, "TOPLEFT", -8, 8)
            backdrop:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 180, -8)
            backdrop:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
            backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
            frame.quiBackdrop = backdrop
        end
    end

    frame.quiSkinned = true
end

--- Skin Entitlement/RAF Delivered Alert
local function SkinEntitlementAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    CreateAlertBackdrop(frame, 10, -6, -14, 6)

    Kill(frame.Background)
    Kill(frame.StandardBackground)
    Kill(frame.glow)
    Kill(frame.shine)

    if frame.Icon then
        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        frame.Icon:ClearAllPoints()
        frame.Icon:SetPoint("LEFT", frame.quiBackdrop, 9, 0)

        local border = CreateIconBorder(frame.Icon, frame)
        frame.Icon:SetParent(border)
    end

    frame.quiSkinned = true
end

--- Skin Digsite Complete Alert
local function SkinDigsiteCompleteAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    CreateAlertBackdrop(frame, -16, -6, 13, 6)

    Kill(frame.glow)
    Kill(frame.shine)

    -- Hide background region
    local regions = { frame:GetRegions() }
    if regions[1] then Kill(regions[1]) end

    if frame.DigsiteTypeTexture then
        frame.DigsiteTypeTexture:SetPoint("LEFT", -10, -14)
    end

    frame.quiSkinned = true
end

--- Skin Guild Challenge Alert
local function SkinGuildChallengeAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    CreateAlertBackdrop(frame, -2, -6, -2, 6)

    -- Kill guild challenge background
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
        local border = CreateIconBorder(frame.EmblemIcon, frame)
        frame.EmblemIcon:SetParent(border)
        SetLargeGuildTabardTextures("player", frame.EmblemIcon)
    end

    frame.quiSkinned = true
end

--- Skin Invasion Alert
local function SkinInvasionAlert(frame)
    if not frame or frame.quiSkinned then return end

    frame:SetAlpha(1)
    if not frame.quiHooked then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        frame.quiHooked = true
    end

    CreateAlertBackdrop(frame, 4, 4, -7, 6)

    -- Kill invasion background
    if frame.GetRegions then
        local region, icon = frame:GetRegions()
        if region and region:IsObjectType("Texture") then
            if region:GetAtlas() == "legioninvasion-Toast-Frame" then
                Kill(region)
            end
        end

        if icon and icon:IsObjectType("Texture") then
            if icon:GetTexture() == 236293 then  -- interface\icons\ability_warlock_demonicpower
                local border = CreateIconBorder(icon, frame)
                icon:SetParent(border)
                icon:SetDrawLayer("OVERLAY")
                icon:SetTexCoord(unpack(ICON_TEX_COORDS))
            end
        end
    end

    frame.quiSkinned = true
end

---------------------------------------------------------------------------
-- BONUS ROLL FRAMES (Not part of AlertSystem)
---------------------------------------------------------------------------

local function SkinBonusRollFrames()
    local db = GetAlertSettings()
    if not db.enabled then return end

    -- BonusRollMoneyWonFrame
    local moneyFrame = BonusRollMoneyWonFrame
    if moneyFrame and not moneyFrame.quiSkinned then
        moneyFrame:SetAlpha(1)
        hooksecurefunc(moneyFrame, "SetAlpha", ForceAlpha)

        Kill(moneyFrame.Background)
        Kill(moneyFrame.IconBorder)

        StyleIcon(moneyFrame.Icon, moneyFrame)

        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()
        local backdrop = CreateFrame("Frame", nil, moneyFrame, "BackdropTemplate")
        backdrop:SetFrameLevel(moneyFrame:GetFrameLevel())
        backdrop:SetPoint("TOPLEFT", moneyFrame.Icon.quiBorder, "TOPLEFT", -4, 4)
        backdrop:SetPoint("BOTTOMRIGHT", moneyFrame.Icon.quiBorder, "BOTTOMRIGHT", 180, -4)
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        moneyFrame.quiBackdrop = backdrop
        moneyFrame.quiSkinned = true
    end

    -- BonusRollLootWonFrame
    local lootFrame = BonusRollLootWonFrame
    if lootFrame and not lootFrame.quiSkinned then
        lootFrame:SetAlpha(1)
        hooksecurefunc(lootFrame, "SetAlpha", ForceAlpha)

        Kill(lootFrame.Background)
        Kill(lootFrame.glow)
        Kill(lootFrame.shine)

        local lootItem = lootFrame.lootItem or lootFrame
        lootItem.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
        Kill(lootItem.IconBorder)

        local border = CreateIconBorder(lootItem.Icon, lootFrame)
        lootItem.Icon:SetParent(border)

        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()
        local backdrop = CreateFrame("Frame", nil, lootFrame, "BackdropTemplate")
        backdrop:SetFrameLevel(lootFrame:GetFrameLevel())
        backdrop:SetPoint("TOPLEFT", border, "TOPLEFT", -4, 4)
        backdrop:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 180, -4)
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        lootFrame.quiBackdrop = backdrop
        lootFrame.quiSkinned = true
    end
end

---------------------------------------------------------------------------
-- ALERT FRAME MOVER
---------------------------------------------------------------------------

local alertHolder = nil
local alertMover = nil

-- Positioning constants (grow down from anchor)
local POSITION, ANCHOR_POINT, Y_OFFSET = "TOP", "BOTTOM", -5

-- Custom AdjustAnchors for queued alert systems (most alerts)
local function AdjustQueuedAnchors(self, relativeAlert)
    -- Only use our holder for the first subsystem in the chain
    -- (when relativeAlert is AlertFrame itself, not a previous alert)
    if alertHolder and relativeAlert == AlertFrame then
        relativeAlert = alertHolder
    end
    for alert in self.alertFramePool:EnumerateActive() do
        alert:ClearAllPoints()
        alert:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, Y_OFFSET)
        relativeAlert = alert
    end
    return relativeAlert
end

-- Custom AdjustAnchors for simple alert systems
local function AdjustSimpleAnchors(self, relativeAlert)
    -- Only use our holder for the first subsystem in the chain
    if alertHolder and relativeAlert == AlertFrame then
        relativeAlert = alertHolder
    end
    local alert = self.alertFrame
    if alert:IsShown() then
        alert:ClearAllPoints()
        alert:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, Y_OFFSET)
        return alert
    end
    return relativeAlert
end

-- Custom AdjustAnchors for anchor frame systems
local function AdjustAnchorFrameAnchors(self, relativeAnchor)
    -- Only use our holder for the first subsystem in the chain
    if alertHolder and relativeAnchor == AlertFrame then
        relativeAnchor = alertHolder
    end
    local anchor = self.anchorFrame
    if anchor:IsShown() then
        anchor:ClearAllPoints()
        anchor:SetPoint(POSITION, relativeAnchor, ANCHOR_POINT, 0, Y_OFFSET)
        return anchor
    end
    return relativeAnchor
end

-- Check if subsystem is TalkingHeadFrame (should not be repositioned)
local function IsTalkingHeadSubSystem(alertFrameSubSystem)
    if alertFrameSubSystem.anchorFrame == TalkingHeadFrame then return true end
    if alertFrameSubSystem.alertFrame == TalkingHeadFrame then return true end
    local frame = alertFrameSubSystem.anchorFrame or alertFrameSubSystem.alertFrame
    if frame and frame:GetName() and frame:GetName():find("TalkingHead") then return true end
    return false
end

-- Replace AdjustAnchors on an alert subsystem
local function ReplaceSubSystemAnchors(alertFrameSubSystem)
    -- Skip TalkingHeadFrame - it has its own positioning
    if IsTalkingHeadSubSystem(alertFrameSubSystem) then return end

    if alertFrameSubSystem.alertFramePool then
        -- Queued alert system (most common)
        alertFrameSubSystem.AdjustAnchors = AdjustQueuedAnchors
    elseif not alertFrameSubSystem.anchorFrame then
        -- Simple alert system
        alertFrameSubSystem.AdjustAnchors = AdjustSimpleAnchors
    else
        -- Anchor frame system
        alertFrameSubSystem.AdjustAnchors = AdjustAnchorFrameAnchors
    end
end

-- Called after AlertFrame:UpdateAnchors to reposition to our holder
local function PostAlertMove()
    if not alertHolder then return end

    AlertFrame:ClearAllPoints()
    AlertFrame:SetAllPoints(alertHolder)

    if GroupLootContainer then
        GroupLootContainer:ClearAllPoints()
        GroupLootContainer:SetPoint(POSITION, alertHolder, ANCHOR_POINT, 0, Y_OFFSET)
    end
end

local function CreateAlertMover()
    local db = GetAlertSettings()
    if not db.enabled then return end

    -- Create holder frame
    if not alertHolder then
        alertHolder = CreateFrame("Frame", "QUI_AlertFrameHolder", UIParent)
        alertHolder:SetSize(180, 20)
        -- Load saved position or use default
        local pos = db.alertPosition
        if pos and pos.point then
            alertHolder:SetPoint(pos.point, UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or -20)
        else
            alertHolder:SetPoint("TOP", UIParent, "TOP", 0, -20)
        end
        alertHolder:SetMovable(true)
        alertHolder:SetClampedToScreen(true)

        -- Create mover overlay
        alertMover = CreateFrame("Frame", "QUI_AlertFrameMover", alertHolder, "BackdropTemplate")
        alertMover:SetAllPoints(alertHolder)
        alertMover:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        alertMover:SetBackdropColor(0.2, 0.8, 0.8, 0.5)
        alertMover:SetBackdropBorderColor(0.2, 0.8, 0.8, 1)
        alertMover:EnableMouse(true)
        alertMover:SetMovable(true)
        alertMover:RegisterForDrag("LeftButton")
        alertMover:SetFrameStrata("FULLSCREEN_DIALOG")
        alertMover:Hide()

        -- Mover text
        local text = alertMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText("Alert Frames")
        alertMover.text = text

        -- Drag handlers
        alertMover:SetScript("OnDragStart", function(self)
            alertHolder:StartMoving()
        end)

        alertMover:SetScript("OnDragStop", function(self)
            alertHolder:StopMovingOrSizing()
            -- Save position to database
            local point, _, relPoint, x, y = alertHolder:GetPoint()
            local alertDB = GetAlertSettings()
            alertDB.alertPosition = { point = point, relPoint = relPoint, x = x, y = y }
        end)
    end

    -- Replace AdjustAnchors on all existing alert subsystems
    for _, alertFrameSubSystem in ipairs(AlertFrame.alertFrameSubSystems) do
        ReplaceSubSystemAnchors(alertFrameSubSystem)
    end

    -- Hook for any new subsystems added later
    hooksecurefunc(AlertFrame, "AddAlertFrameSubSystem", function(_, alertFrameSubSystem)
        ReplaceSubSystemAnchors(alertFrameSubSystem)
    end)

    -- Hook UpdateAnchors to reposition after Blizzard updates
    hooksecurefunc(AlertFrame, "UpdateAnchors", PostAlertMove)

    -- Disable mouse on GroupLootContainer for cleaner interaction
    if GroupLootContainer then
        GroupLootContainer:EnableMouse(false)
        GroupLootContainer.ignoreInLayout = true
    end

    -- Set alert subsystem priorities (lower = appears first/top)
    -- Ensures WQ completion appears above loot alerts
    if WorldQuestCompleteAlertSystem and LootAlertSystem then
        AlertFrame:SetSubSystemAnchorPriority(WorldQuestCompleteAlertSystem, 100)
        AlertFrame:SetSubSystemAnchorPriority(LootAlertSystem, 200)
    end
end

---------------------------------------------------------------------------
-- EVENT TOAST MOVER
---------------------------------------------------------------------------

local toastHolder = nil
local toastMover = nil

local function CreateEventToastMover()
    local db = GetAlertSettings()
    if not db.enabled then return end
    if not EventToastManagerFrame then return end

    -- Create holder frame
    if not toastHolder then
        toastHolder = CreateFrame("Frame", "QUI_EventToastHolder", UIParent)
        toastHolder:SetSize(300, 20)
        -- Load saved position or use default
        local pos = db.toastPosition
        if pos and pos.point then
            toastHolder:SetPoint(pos.point, UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or -150)
        else
            toastHolder:SetPoint("TOP", UIParent, "TOP", 0, -150)
        end
        toastHolder:SetMovable(true)
        toastHolder:SetClampedToScreen(true)

        -- Create mover overlay
        toastMover = CreateFrame("Frame", "QUI_EventToastMover", toastHolder, "BackdropTemplate")
        toastMover:SetAllPoints(toastHolder)
        toastMover:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        toastMover:SetBackdropColor(0.8, 0.6, 0.2, 0.5)
        toastMover:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)
        toastMover:EnableMouse(true)
        toastMover:SetMovable(true)
        toastMover:RegisterForDrag("LeftButton")
        toastMover:SetFrameStrata("FULLSCREEN_DIALOG")
        toastMover:Hide()

        -- Mover text
        local text = toastMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText("Event Toasts")
        toastMover.text = text

        -- Drag handlers
        toastMover:SetScript("OnDragStart", function(self)
            toastHolder:StartMoving()
        end)

        toastMover:SetScript("OnDragStop", function(self)
            toastHolder:StopMovingOrSizing()
            -- Save position to database
            local point, _, relPoint, x, y = toastHolder:GetPoint()
            local alertDB = GetAlertSettings()
            alertDB.toastPosition = { point = point, relPoint = relPoint, x = x, y = y }
            -- Reposition toast frame
            EventToastManagerFrame:ClearAllPoints()
            EventToastManagerFrame:SetPoint("TOP", toastHolder, "TOP")
        end)
    end

    -- Hook EventToastManagerFrame:UpdateAnchor instead of SetPoint (avoids recursion)
    hooksecurefunc(EventToastManagerFrame, "UpdateAnchor", function(self)
        self:ClearAllPoints()
        self:SetPoint("TOP", toastHolder, "TOP")
    end)

    -- Initial positioning
    EventToastManagerFrame:ClearAllPoints()
    EventToastManagerFrame:SetPoint("TOP", toastHolder, "TOP")
end

---------------------------------------------------------------------------
-- MOVER TOGGLE (called from options)
---------------------------------------------------------------------------

function Alerts:ShowMovers()
    if alertMover then alertMover:Show() end
    if toastMover then toastMover:Show() end
end

function Alerts:HideMovers()
    if alertMover then alertMover:Hide() end
    if toastMover then toastMover:Hide() end
end

function Alerts:ToggleMovers()
    local isShown = (alertMover and alertMover:IsShown()) or (toastMover and toastMover:IsShown())
    if isShown then
        self:HideMovers()
    else
        self:ShowMovers()
    end
end

---------------------------------------------------------------------------
-- REFRESH FUNCTION (for live color updates from options panel)
---------------------------------------------------------------------------

local function RefreshAlertColors()
    -- Get current colors
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    -- Update all skinned alert backdrops
    -- Since alerts are pooled and created dynamically, we iterate through known alert systems
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
                if frame.quiBackdrop then
                    frame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
                    frame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
                end
                -- Update icon borders
                if frame.Icon and frame.Icon.quiBorder then
                    frame.Icon.quiBorder:SetBackdropBorderColor(sr, sg, sb, sa)
                end
            end
        end
    end

    -- Update bonus roll frames
    if BonusRollMoneyWonFrame and BonusRollMoneyWonFrame.quiBackdrop then
        BonusRollMoneyWonFrame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        BonusRollMoneyWonFrame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end
    if BonusRollLootWonFrame and BonusRollLootWonFrame.quiBackdrop then
        BonusRollLootWonFrame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        BonusRollLootWonFrame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end
end

-- Expose refresh function globally
_G.QUI_RefreshAlertColors = RefreshAlertColors

---------------------------------------------------------------------------
-- MAIN INITIALIZATION
---------------------------------------------------------------------------

function Alerts:HookAlertSystems()
    local db = GetAlertSettings()
    if not db.enabled then return end

    -- Achievements
    if AchievementAlertSystem then
        hooksecurefunc(AchievementAlertSystem, "setUpFunction", SkinAchievementAlert)
    end
    if CriteriaAlertSystem then
        hooksecurefunc(CriteriaAlertSystem, "setUpFunction", SkinCriteriaAlert)
    end
    if MonthlyActivityAlertSystem then
        hooksecurefunc(MonthlyActivityAlertSystem, "setUpFunction", SkinCriteriaAlert)
    end

    -- Encounters
    if DungeonCompletionAlertSystem then
        hooksecurefunc(DungeonCompletionAlertSystem, "setUpFunction", SkinDungeonCompletionAlert)
    end
    if GuildChallengeAlertSystem then
        hooksecurefunc(GuildChallengeAlertSystem, "setUpFunction", SkinGuildChallengeAlert)
    end
    if InvasionAlertSystem then
        hooksecurefunc(InvasionAlertSystem, "setUpFunction", SkinInvasionAlert)
    end
    if ScenarioAlertSystem then
        hooksecurefunc(ScenarioAlertSystem, "setUpFunction", SkinScenarioAlert)
    end
    if WorldQuestCompleteAlertSystem then
        hooksecurefunc(WorldQuestCompleteAlertSystem, "setUpFunction", SkinWorldQuestCompleteAlert)
    end

    -- Honor
    if HonorAwardedAlertSystem then
        hooksecurefunc(HonorAwardedAlertSystem, "setUpFunction", SkinHonorAwardedAlert)
    end

    -- Loot
    if LegendaryItemAlertSystem then
        hooksecurefunc(LegendaryItemAlertSystem, "setUpFunction", SkinLegendaryItemAlert)
    end
    if LootAlertSystem then
        hooksecurefunc(LootAlertSystem, "setUpFunction", SkinLootWonAlert)
    end
    if LootUpgradeAlertSystem then
        hooksecurefunc(LootUpgradeAlertSystem, "setUpFunction", SkinLootUpgradeAlert)
    end
    if MoneyWonAlertSystem then
        hooksecurefunc(MoneyWonAlertSystem, "setUpFunction", SkinMoneyWonAlert)
    end
    if EntitlementDeliveredAlertSystem then
        hooksecurefunc(EntitlementDeliveredAlertSystem, "setUpFunction", SkinEntitlementAlert)
    end
    if RafRewardDeliveredAlertSystem then
        hooksecurefunc(RafRewardDeliveredAlertSystem, "setUpFunction", SkinEntitlementAlert)
    end

    -- Professions
    if DigsiteCompleteAlertSystem then
        hooksecurefunc(DigsiteCompleteAlertSystem, "setUpFunction", SkinDigsiteCompleteAlert)
    end
    if NewRecipeLearnedAlertSystem then
        hooksecurefunc(NewRecipeLearnedAlertSystem, "setUpFunction", SkinNewRecipeLearnedAlert)
    end

    -- Collections (Pets/Mounts/Toys/Cosmetics/Warband)
    if NewPetAlertSystem then
        hooksecurefunc(NewPetAlertSystem, "setUpFunction", SkinMiscAlert)
    end
    if NewMountAlertSystem then
        hooksecurefunc(NewMountAlertSystem, "setUpFunction", SkinMiscAlert)
    end
    if NewToyAlertSystem then
        hooksecurefunc(NewToyAlertSystem, "setUpFunction", SkinMiscAlert)
    end
    if NewCosmeticAlertFrameSystem then
        hooksecurefunc(NewCosmeticAlertFrameSystem, "setUpFunction", SkinMiscAlert)
    end
    if NewWarbandSceneAlertSystem then
        hooksecurefunc(NewWarbandSceneAlertSystem, "setUpFunction", SkinMiscAlert)
    end

    -- Skin bonus roll frames
    SkinBonusRollFrames()
end

function Alerts:Initialize()
    local db = GetAlertSettings()
    if not db.enabled then return end

    -- Hook all alert systems for skinning
    self:HookAlertSystems()

    -- Create movers for custom alert positioning
    CreateAlertMover()
    CreateEventToastMover()
end
