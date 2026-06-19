--- QUI Alert & Toast Skinning
--- Skins Blizzard alert frames with QUI styling and adds movers

-- Blizzard FrameXML globals this module post-hooks (declared for luacheck).
-- luacheck: read globals LootWonAlertFrame_SetUp MoneyWonAlertFrame_SetUp BonusRollFrame_StartBonusRoll BonusRollFrame

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local SafeGetPixelSize = SkinBase.GetPixelSize

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
    local general = GetGeneralSettings()
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor(general, "alerts")
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColor()
    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

--- Force alpha to 1 (prevents Blizzard fade animations)
-- TAINT SAFETY: Defer to break taint chain from secure context.
-- Re-entry guard: SetAlpha(1) re-triggers the hooksecurefunc that calls
-- ForceAlpha, which would schedule another redundant timer without this.
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

--- Create QUI-styled backdrop for alert frames
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

--- Create a backdrop anchored to an icon border frame (extends rightward by 180px)
--- @param frame frame Owner frame that stores/keys the backdrop
--- @param anchorFrame frame The icon border to anchor against
--- @param inset number Pixel inset for TOPLEFT/BOTTOMRIGHT corners
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

--- Resolve an item rarity quality color {r,g,b} from a hyperlink, or nil
local function GetQualityColor(hyperlink)
    if not hyperlink then return nil end
    local quality = C_Item.GetItemQualityByID(hyperlink)
    if quality and quality >= 1 then
        local r, g, b = GetItemQualityColor(quality)
        return { r = r, g = g, b = b }
    end
    return nil
end

--- Update existing backdrop colors (for theme changes)
local function UpdateBackdropColors(frame)
    local bd = SkinBase.GetFrameData(frame, "backdrop")
    if not bd then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()
    Helpers.SetFrameBackdropColor(bd, bgr, bgg, bgb, bga)
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
end

--- Create icon border frame with optional quality color
--- @param icon texture The icon texture
--- @param parent frame The parent frame
--- @param qualityColor table|nil Optional {r, g, b} quality color for rarity border
local function CreateIconBorder(icon, parent, qualityColor)
    local sr, sg, sb, sa = GetThemeColors()

    -- If border already exists (pooled frame), just update the color
    local existingBorder = SkinBase.GetFrameData(icon, "border")
    if existingBorder then
        if qualityColor then
            Helpers.SetFrameBackdropBorderColor(existingBorder, qualityColor.r or qualityColor[1], qualityColor.g or qualityColor[2], qualityColor.b or qualityColor[3], 1)
        else
            Helpers.SetFrameBackdropBorderColor(existingBorder, sr, sg, sb, sa)
        end
        return existingBorder
    end

    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetFrameLevel(parent:GetFrameLevel() + 1)
    SkinBase.SetExpandedPixelPoints(border, icon, 2)
    SkinBase.ApplyPixelBackdrop(border, 1, false, false)

    -- Use quality color if provided, otherwise use skin accent
    if qualityColor then
        Helpers.SetFrameBackdropBorderColor(border, qualityColor.r or qualityColor[1], qualityColor.g or qualityColor[2], qualityColor.b or qualityColor[3], 1)
    else
        Helpers.SetFrameBackdropBorderColor(border, sr, sg, sb, sa)
    end

    SkinBase.SetFrameData(icon, "border", border)
    return border
end

--- Style an icon with tex coords and border
local function StyleIcon(icon, parent, qualityColor)
    if not icon then return end

    icon:SetTexCoord(unpack(ICON_TEX_COORDS))
    icon:SetDrawLayer("ARTWORK")

    CreateIconBorder(icon, parent, qualityColor)
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
    -- Shield.Points re-fonts via SetFontObject on every alert setUp; the install
    -- below must run BEFORE the IsSkinned early-return (alerts are recycled, so a
    -- once-only post-return lock would be skipped on later displays). The
    -- LockFontObject hook persists for the frame's lifetime and defeats every
    -- later per-setUp revert.
    if frame and frame.Shield and frame.Shield.Points then
        SkinBase.LockFontObject(frame.Shield.Points, { fontOnly = true })
    end
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
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

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Criteria Alert (achievement criteria)
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

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

-- Refresh per-item quality border color on a pooled alert frame
local function RefreshAlertQualityColor(frame, icon)
    if not frame or not icon then return end
    local lootItem = frame.lootItem or frame
    local qualityColor = GetQualityColor(frame.hyperlink or (lootItem and lootItem.hyperlink))
    CreateIconBorder(icon, frame, qualityColor)
end

-- Blizzard's lootItem:Init / LootWonAlertFrame_SetUp re-Shows the background atlas,
-- IconBorder and SpecRing on EVERY pooled re-use; re-suppress them each time.
local function SuppressLootWonArt(frame, lootItem)
    Kill(frame.Background)
    Kill(frame.glow)
    Kill(frame.shine)
    Kill(frame.BGAtlas)
    Kill(frame.PvPBackground)
    Kill(lootItem.IconBorder)
    Kill(lootItem.SpecRing)
end

--- Skin Loot Won Alert
local function SkinLootWonAlert(frame)
    if not frame then return end
    local lootItem = frame.lootItem or frame

    -- Pooled frames: Blizzard re-shows art + re-SetText's (stock font) on re-use, so
    -- re-suppress the art, re-apply the QUI font, and refresh the quality border.
    if SkinBase.IsSkinned(frame) then
        SuppressLootWonArt(frame, lootItem)
        RefreshAlertQualityColor(frame, lootItem.Icon)
        SkinBase.SkinFrameText(frame, { recurse = true })
        return
    end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
    end

    SuppressLootWonArt(frame, lootItem)

    -- Get quality color from item link
    local qualityColor = GetQualityColor(frame.hyperlink or (lootItem and lootItem.hyperlink))

    StyleIcon(lootItem.Icon, frame, qualityColor)

    -- Create backdrop anchored to icon
    CreateIconAnchoredBackdrop(frame, SkinBase.GetFrameData(lootItem.Icon, "border"), 4)

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Loot Upgrade Alert
local function SkinLootUpgradeAlert(frame)
    if not frame then return end

    -- Pooled frames: refresh quality border + re-apply the QUI font (templates
    -- re-SetText in the stock font on re-use).
    if SkinBase.IsSkinned(frame) then
        RefreshAlertQualityColor(frame, frame.Icon)
        SkinBase.SkinFrameText(frame, { recurse = true })
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

    -- Get quality color from item link
    local qualityColor = GetQualityColor(frame.hyperlink)

    CreateIconBorder(frame.Icon, frame, qualityColor)

    -- Create backdrop
    CreateIconAnchoredBackdrop(frame, SkinBase.GetFrameData(frame.Icon, "border"), 8)

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Money Won Alert
local function SkinMoneyWonAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetThemeColors()

    -- Hide Blizzard textures
    if frame.Background then frame.Background:SetAlpha(0) end
    if frame.IconBorder then frame.IconBorder:SetAlpha(0) end

    -- Style icon
    if frame.Icon then
        frame.Icon:SetTexCoord(unpack(ICON_TEX_COORDS))
    end

    -- Create backdrop
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

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Honor Awarded Alert
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

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin New Recipe Learned Alert
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
        frame.Icon:SetPoint("LEFT", SkinBase.GetFrameData(frame, "backdrop"), 9, 0)

        CreateIconBorder(frame.Icon, frame)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Dungeon Completion Alert
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

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Scenario Alert
local function SkinScenarioAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
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
        frame.dungeonTexture:SetPoint("LEFT", SkinBase.GetFrameData(frame, "backdrop"), 9, 0)
        frame.dungeonTexture:SetDrawLayer("OVERLAY")

        CreateIconBorder(frame.dungeonTexture, frame)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin World Quest Complete Alert
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

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Legendary Item Alert
local function SkinLegendaryItemAlert(frame, itemLink)
    if not frame then return end

    -- Pooled frames: refresh per-item quality border color
    if SkinBase.IsSkinned(frame) then
        if frame.Icon and itemLink then
            local quality = C_Item.GetItemQualityByID(itemLink)
            if quality then
                local r, g, b = GetItemQualityColor(quality)
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

        -- Color border by item quality
        if itemLink then
            local quality = C_Item.GetItemQualityByID(itemLink)
            if quality then
                local r, g, b = GetItemQualityColor(quality)
                Helpers.SetFrameBackdropBorderColor(border, r, g, b, 1)
            end
        end
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Misc Alerts (Pets, Mounts, Toys, Cosmetics, Warband)
local function SkinMiscAlert(frame)
    if not frame then return end

    -- Misc alerts (mounts/toys/pets) use the user's skin accent color: quality
    -- detection is unreliable, accent color is cleaner and consistent (nil border).
    if frame.Icon then
        -- Update existing border color or create new one
        CreateIconBorder(frame.Icon, frame, nil)
    end

    -- Skip structural changes if already skinned (pooled frame), but ItemAlertFrameMixin
    -- :SetUpDisplay re-SetAtlas's IconBorder on every show, reactivating the texture we
    -- killed — so re-suppress it (and re-font) on each pooled re-use.
    if SkinBase.IsSkinned(frame) then
        Kill(frame.IconBorder)
        SkinBase.SkinFrameText(frame, { recurse = true })
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

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RestyleEntitlementAlertText(frame)
    if not frame or not frame.Title then return end
    SkinBase.SkinFontString(frame.Title, { fontOnly = true })
    SkinBase.LockFontObject(frame.Title, { fontOnly = true })
end

--- Skin Entitlement/RAF Delivered Alert
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
        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        frame.Icon:ClearAllPoints()
        frame.Icon:SetPoint("LEFT", SkinBase.GetFrameData(frame, "backdrop"), 9, 0)

        CreateIconBorder(frame.Icon, frame)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    RestyleEntitlementAlertText(frame)
    SkinBase.MarkSkinned(frame)
end

--- Skin Digsite Complete Alert
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

    -- Hide background region
    local regions = { frame:GetRegions() }
    if regions[1] then Kill(regions[1]) end

    if frame.DigsiteTypeTexture then
        frame.DigsiteTypeTexture:SetPoint("LEFT", -10, -14)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Guild Challenge Alert
local function SkinGuildChallengeAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
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
        CreateIconBorder(frame.EmblemIcon, frame)
        SetLargeGuildTabardTextures("player", frame.EmblemIcon)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

--- Skin Invasion Alert
local function SkinInvasionAlert(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    frame:SetAlpha(1)
    if not SkinBase.GetFrameData(frame, "hooked") then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        SkinBase.SetFrameData(frame, "hooked", true)
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
                CreateIconBorder(icon, frame)
                icon:SetDrawLayer("OVERLAY")
                icon:SetTexCoord(unpack(ICON_TEX_COORDS))
            end
        end
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

---------------------------------------------------------------------------
-- BONUS ROLL FRAMES (Not part of AlertSystem)
---------------------------------------------------------------------------

-- The BonusRollFrame PROMPT window (loot spinner + item icon + Roll/Pass buttons +
-- currency cost + timer) is a standalone Blizzard frame that QUI otherwise only
-- positions. Skin it to match the loot-roll / alert look. Taint-safe: only
-- display-only methods on Blizzard regions + QUI-owned child backdrops (weak-keyed
-- via SetFrameData) -- no field writes, OnClick hooks, or secure attributes. The
-- Roll/Pass buttons are plain (insecure) buttons (OnClick just calls
-- Accept/DeclineSpellConfirmationPrompt), so a QUI border is safe.
local function SkinBonusRollPromptButton(btn)
    if not btn or SkinBase.IsStyled(btn) then return end
    local sr, sg, sb, sa = GetThemeColors()
    -- Accent border around the dice/pass icon. A border-only child keeps the
    -- button's own NormalTexture (the dice / pass art) visible underneath.
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
        -- Strip Blizzard LootToast art (OnShow already hides LootSpinnerBG/IconBorder)
        Kill(frame.Background)
        Kill(frame.IconBorder)
        Kill(frame.LootSpinnerBG)

        -- QUI backdrop behind the whole prompt, one level below the content frames
        -- (PromptFrame/RollingFrame use the parent frame level) so it renders behind.
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

        -- Timer bar -> QUI accent tint (keep Blizzard's bar texture)
        if prompt.Timer then
            prompt.Timer:SetStatusBarColor(sr, sg, sb, 1)
        end

        -- Global QUI font on the prompt labels
        if prompt.InfoFrame then
            SkinBase.SkinFontString(prompt.InfoFrame.Label)
            SkinBase.SkinFontString(prompt.InfoFrame.Cost)
        end
        if frame.CurrentCountFrame then SkinBase.SkinFontString(frame.CurrentCountFrame.Text) end
        if frame.RollingFrame then
            SkinBase.SkinFontString(frame.RollingFrame.Label)
            -- The spinner's reward text is a separate fontstring Blizzard SetText's
            -- on roll completion; skin it too or it shows in the stock font.
            if frame.RollingFrame.LootSpinnerFinalText then
                SkinBase.SkinFontString(frame.RollingFrame.LootSpinnerFinalText)
            end
        end

        SkinBonusRollPromptButton(prompt.RollButton)
        SkinBonusRollPromptButton(prompt.PassButton)

        SkinBase.MarkSkinned(frame)
    end

    -- The item icon is re-set on every StartBonusRoll, so re-crop + (re)border it
    -- each roll. StyleIcon just updates the existing QUI border if one is present.
    if prompt.Icon then
        StyleIcon(prompt.Icon, prompt)
    end
end

-- BonusRollLootWonFrame / BonusRollMoneyWonFrame are standalone ContainedAlertFrames
-- that Blizzard sets up by calling the GLOBAL LootWonAlertFrame_SetUp /
-- MoneyWonAlertFrame_SetUp directly (GroupLootFrame.lua) and adds straight to
-- AlertFrame. They never flow through the pooled Loot/MoneyWon alert systems whose
-- setUpFunction we hook in HookAlertSystems -- so a one-shot init skin both races
-- frame creation and is wiped every time Blizzard re-runs SetUp on show. Instead we
-- post-hook the two global setup funcs and route the bonus-roll frames through the
-- exact same idempotent skinners used for the pooled loot/money alerts, so they get
-- (re)skinned on every show.
local bonusRollHooked = false
local function HookBonusRollFrames()
    local db = GetAlertSettings()
    if not db.enabled or bonusRollHooked then return end

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
    -- The bonus-roll PROMPT window is populated/shown via the global
    -- BonusRollFrame_StartBonusRoll; post-hook it so the prompt is (re)skinned on
    -- every roll (the item icon is re-set each time, so this also re-crops it).
    if type(BonusRollFrame_StartBonusRoll) == "function" then
        hooksecurefunc("BonusRollFrame_StartBonusRoll", function()
            SkinBonusRollPrompt(BonusRollFrame)
        end)
        hooked = true
    end
    bonusRollHooked = hooked
end

---------------------------------------------------------------------------
-- ALERT FRAME MOVER
---------------------------------------------------------------------------

local alertHolder = nil
local alertMover = nil

-- Positioning constants (grow down from anchor)
local POSITION, ANCHOR_POINT, Y_OFFSET = "TOP", "BOTTOM", -5

local function GetAlertAnchorRelativeFrame(relativeAlert)
    if not alertHolder then return relativeAlert end
    if relativeAlert == AlertFrame then return alertHolder end
    if AlertFrame and relativeAlert == AlertFrame.baseAnchorFrame then return alertHolder end
    return relativeAlert
end

-- Custom AdjustAnchors for queued alert systems (most alerts)
local function AdjustQueuedAnchors(self, relativeAlert)
    -- Only use our holder for the first subsystem in the chain
    -- (when relativeAlert is AlertFrame or its temporary base anchor, not a previous alert)
    relativeAlert = GetAlertAnchorRelativeFrame(relativeAlert)
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
    relativeAlert = GetAlertAnchorRelativeFrame(relativeAlert)
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
    relativeAnchor = GetAlertAnchorRelativeFrame(relativeAnchor)
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
        -- Default position; ApplyAllFrameAnchors overrides from frameAnchoring DB
        alertHolder:SetPoint("TOP", UIParent, "TOP", 0, -20)
        alertHolder:SetMovable(true)
        alertHolder:SetClampedToScreen(true)

        -- Create mover overlay
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

        -- Mover text
        local text = alertMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(ns.L["Alert Frames"])
        alertMover.text = text

        -- Drag handlers
        alertMover:SetScript("OnDragStart", function(self)
            alertHolder:StartMoving()
        end)

        alertMover:SetScript("OnDragStop", function(self)
            alertHolder:StopMovingOrSizing()
        end)
    end

    -- Replace AdjustAnchors on all existing alert subsystems
    for _, alertFrameSubSystem in ipairs(AlertFrame.alertFrameSubSystems) do
        ReplaceSubSystemAnchors(alertFrameSubSystem)
    end

    -- Hook for any new subsystems added later
    -- TAINT SAFETY: Defer to break taint chain from secure context.
    hooksecurefunc(AlertFrame, "AddAlertFrameSubSystem", function(_, alertFrameSubSystem)
        C_Timer.After(0, function()
            ReplaceSubSystemAnchors(alertFrameSubSystem)
        end)
    end)

    -- Hook UpdateAnchors to reposition after Blizzard updates
    -- TAINT SAFETY: Defer to break taint chain from secure context.
    hooksecurefunc(AlertFrame, "UpdateAnchors", function()
        C_Timer.After(0, PostAlertMove)
    end)

    -- Disable mouse on GroupLootContainer for cleaner interaction, and opt it
    -- out of Blizzard's UIParent frame-position manager.
    --
    -- GroupLootContainer inherits UIParentBottomManagedFrameTemplate, so each
    -- time it shows *from its default position* Blizzard's
    -- UIParentManagedFrameContainerMixin:AddManagedFrame reparents it into the
    -- bottom-managed container and Layout()s it back to screen-bottom-center
    -- (UIParent.lua). Because GroupLootContainer is the HEAD of the alert anchor
    -- chain (AddExternallyAnchoredSubSystem at priority 30, GroupLootFrame.lua),
    -- a roll-won toast chained off it then intermittently lands at that Blizzard
    -- default location instead of QUI's Alert Anchor mover. The correct opt-out
    -- is ignoreFramePositionManager (the flag AddManagedFrame early-returns on) --
    -- NOT ignoreInLayout, which is the unrelated LayoutFrame child-region flag and
    -- does nothing to the position manager. Deregister first so a stale
    -- showingFrames ref can't drive a later Layout pass (taint hazard) -- mirrors
    -- the managed-frame detach in modules/layout/anchoring.lua.
    if GroupLootContainer then
        GroupLootContainer:EnableMouse(false)
        -- TAINT SAFETY: Defer the field writes to break the taint chain.
        C_Timer.After(0, function()
            if not GroupLootContainer then return end
            local mgr = GroupLootContainer.layoutParent
            if mgr and mgr.RemoveManagedFrame then
                pcall(mgr.RemoveManagedFrame, mgr, GroupLootContainer)
            end
            GroupLootContainer.ignoreFramePositionManager = true
            GroupLootContainer.ignoreInLayout = true
        end)
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

    -- Hook SetPoint directly — catches ALL repositioning regardless of code path
    local redirecting = false
    hooksecurefunc(EventToastManagerFrame, "SetPoint", function()
        if redirecting or not toastHolder then return end
        -- TAINT SAFETY: Defer to break taint chain from secure context
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
    local db = GetAlertSettings()
    if not db.enabled then return end

    -- Always create the holder frame so frameAnchoring can position it,
    -- even if EventToastManagerFrame doesn't exist yet
    if not toastHolder then
        toastHolder = CreateFrame("Frame", "QUI_EventToastHolder", UIParent)
        toastHolder:SetSize(300, 20)
        -- Default position; ApplyAllFrameAnchors overrides from frameAnchoring DB
        toastHolder:SetPoint("TOP", UIParent, "TOP", 0, -150)
        toastHolder:SetMovable(true)
        toastHolder:SetClampedToScreen(true)

        -- Create mover overlay
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

        -- Mover text
        local text = toastMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(ns.L["Event Toasts"])
        toastMover.text = text

        -- Drag handlers
        toastMover:SetScript("OnDragStart", function(self)
            toastHolder:StartMoving()
        end)

        toastMover:SetScript("OnDragStop", function(self)
            toastHolder:StopMovingOrSizing()
            AnchorEventToastToHolder()
        end)
    end

    -- Try to hook EventToastManagerFrame now; if it doesn't exist yet, retry periodically
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

---------------------------------------------------------------------------
-- BATTLE.NET TOAST MOVER
---------------------------------------------------------------------------

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

    -- Hook SetPoint directly — this catches ALL repositioning regardless of which
    -- Blizzard function triggers it (UpdateAnchor, AlertFrame, or direct calls).
    -- Use a guard flag to prevent infinite recursion from our own SetPoint calls.
    local redirecting = false
    hooksecurefunc(BNToastFrame, "SetPoint", function()
        if redirecting or not bnetToastHolder then return end
        -- TAINT SAFETY: Defer to break taint chain from secure context
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
    local db = GetAlertSettings()
    if not db.enabled then return end

    -- Always create the holder frame so frameAnchoring can position it,
    -- even if BNToastFrame doesn't exist yet
    if not bnetToastHolder then
        bnetToastHolder = CreateFrame("Frame", "QUI_BNetToastHolder", UIParent)
        bnetToastHolder:SetSize(300, 50)
        -- Default position; ApplyAllFrameAnchors overrides from frameAnchoring DB
        bnetToastHolder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -80)
        bnetToastHolder:SetMovable(true)
        bnetToastHolder:SetClampedToScreen(true)

        -- Create mover overlay
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

        -- Mover text
        local text = bnetToastMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(ns.L["Battle.Net Toasts"])
        bnetToastMover.text = text

        -- Drag handlers
        bnetToastMover:SetScript("OnDragStart", function(self)
            bnetToastHolder:StartMoving()
        end)

        bnetToastMover:SetScript("OnDragStop", function(self)
            bnetToastHolder:StopMovingOrSizing()
            AnchorBNetToastToHolder()
        end)
    end

    -- Try to hook BNToastFrame now; if it doesn't exist yet, retry periodically
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

---------------------------------------------------------------------------
-- MOVER TOGGLE (called from options)
---------------------------------------------------------------------------

function Alerts:ShowMovers()
    if alertMover then alertMover:Show() end
    if toastMover then toastMover:Show() end
    if bnetToastMover then bnetToastMover:Show() end
end

function Alerts:HideMovers()
    if alertMover then alertMover:Hide() end
    if toastMover then toastMover:Hide() end
    if bnetToastMover then bnetToastMover:Hide() end
end

function Alerts:ToggleMovers()
    local isShown = (alertMover and alertMover:IsShown()) or (toastMover and toastMover:IsShown()) or (bnetToastMover and bnetToastMover:IsShown())
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
                local bd = SkinBase.GetFrameData(frame, "backdrop")
                if bd then
                    Helpers.SetFrameBackdropColor(bd, bgr, bgg, bgb, bga)
                    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
                end
                -- Update icon borders
                if frame.Icon then
                    local ib = SkinBase.GetFrameData(frame.Icon, "border")
                    if ib then
                        Helpers.SetFrameBackdropBorderColor(ib, sr, sg, sb, sa)
                    end
                end
            end
        end
    end

    -- Update bonus roll frames
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

-- Expose refresh function globally
_G.QUI_RefreshAlertColors = RefreshAlertColors

if ns.Registry then
    ns.Registry:Register("skinAlerts", {
        refresh = _G.QUI_RefreshAlertColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local Helpers = ns.Helpers
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

---------------------------------------------------------------------------
-- MAIN INITIALIZATION
---------------------------------------------------------------------------

function Alerts:HookAlertSystems()
    local db = GetAlertSettings()
    if not db.enabled then return end

    -- TAINT SAFETY: All setUpFunction hooks defer via C_Timer.After(0) to break taint chain.
    -- Alert system setUpFunction fires from Blizzard's internal alert pool, which can propagate taint.
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

    -- Achievements
    DeferredHook(AchievementAlertSystem, SkinAchievementAlert)
    DeferredHook(CriteriaAlertSystem, SkinCriteriaAlert)
    DeferredHook(MonthlyActivityAlertSystem, SkinCriteriaAlert)

    -- Encounters
    DeferredHook(DungeonCompletionAlertSystem, SkinDungeonCompletionAlert)
    DeferredHook(GuildChallengeAlertSystem, SkinGuildChallengeAlert)
    DeferredHook(InvasionAlertSystem, SkinInvasionAlert)
    DeferredHook(ScenarioAlertSystem, SkinScenarioAlert)
    DeferredHook(WorldQuestCompleteAlertSystem, SkinWorldQuestCompleteAlert)

    -- Honor
    DeferredHook(HonorAwardedAlertSystem, SkinHonorAwardedAlert)

    -- Loot
    DeferredHook(LegendaryItemAlertSystem, SkinLegendaryItemAlert)
    DeferredHook(LootAlertSystem, SkinLootWonAlert)
    DeferredHook(LootUpgradeAlertSystem, SkinLootUpgradeAlert)
    DeferredHook(MoneyWonAlertSystem, SkinMoneyWonAlert)
    DeferredHook(EntitlementDeliveredAlertSystem, SkinEntitlementAlert)
    DeferredHook(RafRewardDeliveredAlertSystem, SkinEntitlementAlert)

    -- Professions
    DeferredHook(DigsiteCompleteAlertSystem, SkinDigsiteCompleteAlert)
    DeferredHook(NewRecipeLearnedAlertSystem, SkinNewRecipeLearnedAlert)

    -- Collections (Pets/Mounts/Toys/Cosmetics/Warband)
    DeferredHook(NewPetAlertSystem, SkinMiscAlert)
    DeferredHook(NewMountAlertSystem, SkinMiscAlert)
    DeferredHook(NewToyAlertSystem, SkinMiscAlert)
    DeferredHook(NewCosmeticAlertFrameSystem, SkinMiscAlert)
    DeferredHook(NewWarbandSceneAlertSystem, SkinMiscAlert)

    -- Garrison / Order Hall (still live in current FrameXML —
    -- AlertFrameSystems.lua:10-16)
    DeferredHook(GarrisonBuildingAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonMissionAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonShipMissionAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonRandomMissionAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonFollowerAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonShipFollowerAlertSystem, SkinMiscAlert)
    DeferredHook(GarrisonTalentAlertSystem, SkinMiscAlert)

    -- Runeforge / Skill specs / Guild rename
    -- (AlertFrameSystems.lua:23, :1056, :1436)
    DeferredHook(NewRuneforgePowerAlertSystem, SkinMiscAlert)
    DeferredHook(SkillLineSpecsUnlockedAlertSystem, SkinMiscAlert)
    DeferredHook(GuildRenameAlertSystem, SkinMiscAlert)

    -- Bonus roll won frames: hook the global setup funcs so they skin on show
    HookBonusRollFrames()
end

function Alerts:Initialize()
    local db = GetAlertSettings()
    if not db.enabled then return end

    -- Hook all alert systems for skinning
    self:HookAlertSystems()

    -- Create movers for custom alert positioning
    CreateAlertMover()
    CreateEventToastMover()
    CreateBNetToastMover()
end
