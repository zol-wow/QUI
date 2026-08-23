-- luacheck: read globals ColorManager ITEM_QUALITY_COLORS SplitGuildBankItem
-- luacheck: read globals HandleModifiedItemClick GetGuildBankItemLink IsModifiedClick CursorHasItem
-- luacheck: read globals GetGuildBankItemInfo StackSplitFrame DepositGuildBankMoney
-- luacheck: read globals AutoStoreGuildBankItem PickupGuildBankItem DropCursorMoney SetItemButtonTexture
-- luacheck: read globals SetItemButtonCount SetItemButtonDesaturated
-- luacheck: read globals SetItemButtonOverlay ClearItemButtonOverlay
-- luacheck: read globals C_AuctionHouse ItemButtonUtil ItemLocation
-- luacheck: read globals ContainerFrameItemButtonMixin
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local UIKit = ns.UIKit
local Helpers = ns.Helpers

local function CJKFont(fs, p, s, f)
    if Bags.CJKFont then return Bags.CJKFont(fs, p, s, f) end
    fs:SetFont(p, s, f)
end

local ItemButtons = {}
Bags.ItemButtons = ItemButtons

local GetSettings = Helpers.CreateDBGetter("bags")

local SEARCH_DIM = 0.3

function ItemButtons.SetSearchDim(button, searchResult)
    button:SetAlpha(searchResult == false and SEARCH_DIM or 1)
end

local function GetQualityColor(quality)
    local c
    if ColorManager and ColorManager.GetColorDataForItemQuality then
        c = ColorManager.GetColorDataForItemQuality(quality)
    end
    if not c then
        c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    end
    if c then return c.r, c.g, c.b end
    return 0.5, 0.5, 0.5
end
ItemButtons.GetQualityColor = GetQualityColor

local function ApplyIconOverlay(button, entry)
    if entry and entry.link then
        SetItemButtonOverlay(button, entry.link, entry.quality)
    else
        ClearItemButtonOverlay(button)
    end
end

function ItemButtons.CreateHolder(parent, bagID)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetID(bagID)
    holder:SetAllPoints(parent)
    return holder
end

function ItemButtons.AddSlotBackground(button)
    if button._quiSlotBg then return end
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    button._quiSlotBg = bg
end

local function AuctionContextMatchResult(button)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return nil end
    if ItemButtonUtil.GetItemContext() ~= nil then return nil end
    local bagID, slot = button:GetBagID(), button:GetID()
    if not C_Container.GetContainerItemInfo(bagID, slot) then
        return ItemButtonUtil.ItemContextMatchResult.DoesNotApply
    end
    local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not (loc and loc:IsValid()) then
        return ItemButtonUtil.ItemContextMatchResult.DoesNotApply
    end
    return C_AuctionHouse.IsSellItemValid(loc, false)
        and ItemButtonUtil.ItemContextMatchResult.Match
        or ItemButtonUtil.ItemContextMatchResult.Mismatch
end

local function LiveGetItemContextMatchResult(button)
    local auction = AuctionContextMatchResult(button)
    if auction ~= nil then return auction end
    return ContainerFrameItemButtonMixin.GetItemContextMatchResult(button)
end

local function StopNewItemGlow(button)
    if button.NewItemTexture then button.NewItemTexture:Hide() end
    if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
    if button.flashAnim and button.flashAnim:IsPlaying() then
        button.flashAnim:Stop()
    end
    if button.newitemglowAnim and button.newitemglowAnim:IsPlaying() then
        button.newitemglowAnim:Stop()
    end
end

function ItemButtons.DismissNewItemGlow(button)
    if not button then return end
    local guid = button._newItemGuid
    if guid and Bags.NewItems then Bags.NewItems.MarkSlotSeen(guid) end
    button._newItemGuid = nil
    StopNewItemGlow(button)
end

function ItemButtons.CreateLive(holder, bagID)
    local button = CreateFrame("ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")
    button:SetBagID(bagID)
    button.GetItemContextMatchResult = LiveGetItemContextMatchResult
    if button.IconBorder then button.IconBorder:SetAlpha(0) end
    if button.IconOverlay then
        button.IconOverlay:ClearAllPoints()
        button.IconOverlay:SetAllPoints(button)
    end
    if button.IconOverlay2 then
        button.IconOverlay2:ClearAllPoints()
        button.IconOverlay2:SetAllPoints(button)
    end
    button.noProfessionQualityOverlay = true
    if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
    if button.ClearNormalTexture then button:ClearNormalTexture() end
    button.emptyBackgroundAtlas = nil
    ItemButtons.AddSlotBackground(button)
    UIKit.CreateBorderLines(button)
    button:HookScript("OnEnter", function(self)
        ItemButtons.DismissNewItemGlow(self)
    end)
    return button
end

-- luacheck: read globals BattlePetToolTip_ShowLink BattlePetTooltip
function ItemButtons.ShowItemTooltip(owner, link, itemID)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if type(link) == "string" and link:find("battlepet:", 1, true)
        and type(BattlePetToolTip_ShowLink) == "function" then
        BattlePetToolTip_ShowLink(link)
        return
    end
    if itemID then
        GameTooltip:SetItemByID(itemID)
    elseif link then
        GameTooltip:SetHyperlink(link)
    end
    GameTooltip:Show()
end

function ItemButtons.HideItemTooltip()
    GameTooltip:Hide()
    if BattlePetTooltip then BattlePetTooltip:Hide() end
end

function ItemButtons.CreateCached(parent)
    local button = CreateFrame("Button", nil, parent)
    ItemButtons.AddSlotBackground(button)
    button._icon = button:CreateTexture(nil, "ARTWORK")
    button._icon:SetAllPoints()
    button.IconOverlay = button:CreateTexture(nil, "OVERLAY", nil, 1)
    button.IconOverlay:SetAllPoints(button._icon)
    button.IconOverlay:Hide()
    button.noProfessionQualityOverlay = true
    button._count = button:CreateFontString(nil, "OVERLAY")
    button._count:SetPoint("BOTTOMRIGHT", -2, 2)
    CJKFont(button._count, Helpers.GetGeneralFont(), 11, "OUTLINE")
    UIKit.CreateBorderLines(button)
    button:SetScript("OnEnter", function(self)
        if self._link then
            ItemButtons.ShowItemTooltip(self, self._link, nil)
        end
    end)
    button:SetScript("OnLeave", function() ItemButtons.HideItemTooltip() end)
    return button
end

local craftQualityCache = {}
local function CraftQualityAtlas(entry)
    if not (entry and (entry.link or entry.itemID)) then return nil end
    if not (C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo) then return nil end
    local key = entry.link or entry.itemID
    local hit = craftQualityCache[key]
    if hit ~= nil then return hit or nil end
    local info = C_TradeSkillUI.GetItemReagentQualityInfo(key)
        or (C_TradeSkillUI.GetItemCraftedQualityInfo
            and C_TradeSkillUI.GetItemCraftedQualityInfo(key))
    local atlas = info and info.iconSmall or false
    craftQualityCache[key] = atlas
    return atlas or nil
end

function ItemButtons.DressCached(button, entry, searchResult)
    local appearance = GetSettings().appearance
    if entry then
        button._link = entry.link
        button._icon:SetTexture(entry.icon)
        button._icon:Show()
        button._count:SetText("")
        local r, g, b = GetQualityColor(entry.quality or 1)
        UIKit.UpdateBorderLines(button, 1, r, g, b, 1)
        ApplyIconOverlay(button, entry)
        button._icon:SetDesaturated(
            (appearance and appearance.greyJunk and entry.quality == 0) or false)
        ItemButtons.SetUnusableTint(button,
            appearance and appearance.markUnusable
            and ItemButtons.IsUnusable(nil, nil, entry.link))
        if Bags.CornerWidgets then
            Bags.CornerWidgets.Apply(button, {
                entry = entry,
                details = Bags.Details and Bags.Details.Build(entry) or nil,
                isJunk = entry.quality == 0,
                inSet = false,
                qualityColorText = appearance and appearance.qualityColorText or false,
                craftQualityAtlas = CraftQualityAtlas(entry),
            }, appearance)
        end
    else
        button._link = nil
        button._icon:Hide()
        button._count:SetText("")
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(button, 1, sr, sg, sb, 0.35)
        ApplyIconOverlay(button, nil)
        ItemButtons.SetUnusableTint(button, false)
        if Bags.CornerWidgets then Bags.CornerWidgets.Apply(button, nil, appearance) end
    end
    ItemButtons.SetSearchDim(button, searchResult)
end

function ItemButtons.CreateGuildLive(parent)
    local button = CreateFrame("Button", nil, parent)
    ItemButtons.AddSlotBackground(button)
    button._icon = button:CreateTexture(nil, "ARTWORK")
    button._icon:SetAllPoints()
    button.IconOverlay = button:CreateTexture(nil, "OVERLAY", nil, 1)
    button.IconOverlay:SetAllPoints(button._icon)
    button.IconOverlay:Hide()
    button.noProfessionQualityOverlay = true
    button._count = button:CreateFontString(nil, "OVERLAY")
    button._count:SetPoint("BOTTOMRIGHT", -2, 2)
    CJKFont(button._count, Helpers.GetGeneralFont(), 11, "OUTLINE")
    UIKit.CreateBorderLines(button)

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button.SplitStack = function(self, split)
        SplitGuildBankItem(self._tab, self._slot, split)
    end

    button:SetScript("OnClick", function(self, mouseButton)
        if HandleModifiedItemClick(GetGuildBankItemLink(self._tab, self._slot)) then
            return
        end
        if IsModifiedClick("SPLITSTACK") then
            if not CursorHasItem() then
                local _, count, locked = GetGuildBankItemInfo(self._tab, self._slot)
                if not locked and count and count > 1 and StackSplitFrame then
                    StackSplitFrame:OpenStackSplitFrame(count, self, "BOTTOMLEFT", "TOPLEFT")
                end
            end
            return
        end
        local cursorType, money = GetCursorInfo()
        if cursorType == "money" then
            DepositGuildBankMoney(money)
            ClearCursor()
        elseif cursorType == "guildbankmoney" then
            DropCursorMoney()
            ClearCursor()
        elseif mouseButton == "RightButton" then
            AutoStoreGuildBankItem(self._tab, self._slot)
        else
            PickupGuildBankItem(self._tab, self._slot)
        end
    end)
    button:SetScript("OnDragStart", function(self)
        PickupGuildBankItem(self._tab, self._slot)
    end)
    button:SetScript("OnReceiveDrag", function(self)
        PickupGuildBankItem(self._tab, self._slot)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if Bags.GuildTakeover and Bags.GuildTakeover.IsLive() then
            GameTooltip:SetGuildBankItem(self._tab, self._slot)
        elseif self._link then
            GameTooltip:SetHyperlink(self._link)
        else
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnHide", function(self)
        if self.hasStackSplit == 1 and StackSplitFrame then
            StackSplitFrame:Hide()
        end
    end)
    return button
end

function ItemButtons.DressGuildLive(button, tab, slot, entry, searchResult)
    button._tab, button._slot = tab, slot
    local appearance = GetSettings().appearance
    if entry then
        button._link = entry.link
        button._icon:SetTexture(entry.icon)
        button._icon:Show()
        button._count:SetText("")
        local r, g, b = GetQualityColor(entry.quality or 1)
        UIKit.UpdateBorderLines(button, 1, r, g, b, 1)
        ApplyIconOverlay(button, entry)
        local _, _, locked = GetGuildBankItemInfo(tab, slot)
        local isJunk = entry.quality == 0
        button._icon:SetDesaturated((locked or false)
            or (appearance and appearance.greyJunk and isJunk) or false)
        ItemButtons.SetUnusableTint(button,
            appearance and appearance.markUnusable
            and ItemButtons.IsUnusable(nil, nil, entry.link))
        if Bags.CornerWidgets then
            Bags.CornerWidgets.Apply(button, {
                entry = entry,
                details = Bags.Details and Bags.Details.Build(entry) or nil,
                isJunk = isJunk,
                inSet = false,
                qualityColorText = appearance and appearance.qualityColorText or false,
                craftQualityAtlas = CraftQualityAtlas(entry),
            }, appearance)
        end
    else
        button._link = nil
        button._icon:Hide()
        button._count:SetText("")
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(button, 1, sr, sg, sb, 0.35)
        ApplyIconOverlay(button, nil)
        button._icon:SetDesaturated(false)
        ItemButtons.SetUnusableTint(button, false)
        if Bags.CornerWidgets then Bags.CornerWidgets.Apply(button, nil, appearance) end
    end
    ItemButtons.SetSearchDim(button, searchResult)
end

local function WantsCornerWidget(appearance, id)
    local c = appearance and appearance.corners
    if not c then return false end
    return c.tl1 == id or c.tl2 == id or c.tr1 == id or c.tr2 == id
        or c.bl1 == id or c.bl2 == id or c.br1 == id or c.br2 == id
end

function ItemButtons.Dress(button, entry, searchResult, newGuid)
    local appearance = GetSettings().appearance
    if entry then
        SetItemButtonTexture(button, entry.icon)
        SetItemButtonCount(button, 0)
        local r, g, b = GetQualityColor(entry.quality or 1)
        ApplyIconOverlay(button, entry)
        local start, duration, enable = C_Container.GetContainerItemCooldown(button:GetBagID(), button:GetID())
        CooldownFrame_Set(button.Cooldown, start, duration, enable)
        local live = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
        local junkCfg = GetSettings().behavior.junk
        local isJunk = (Bags.Junk and live
            and Bags.Junk.IsJunk(live, button:GetBagID(), junkCfg and junkCfg.exclusions))
            and true or false
        SetItemButtonDesaturated(button, (live and live.isLocked)
            or (appearance and appearance.greyJunk and isJunk) or false)
        local inSet = false
        if (not appearance or appearance.equipmentSetMark ~= false)
            and C_Container.GetContainerItemEquipmentSetInfo then
            inSet = C_Container.GetContainerItemEquipmentSetInfo(
                button:GetBagID(), button:GetID())
        end
        if appearance and appearance.equipmentSetBorder and inSet then
            UIKit.UpdateBorderLines(button, 1, 0.25, 0.85, 1, 1)
        else
            UIKit.UpdateBorderLines(button, 1, r, g, b, 1)
        end
        ItemButtons.SetUnusableTint(button,
            appearance and appearance.markUnusable
            and ItemButtons.IsUnusable(button:GetBagID(), button:GetID(), entry.link))
        local upgradeTrack
        if WantsCornerWidget(appearance, "upgrade_track")
            and entry.link and C_Item and C_Item.GetItemUpgradeInfo then
            local okU, u = ns.SafeCall("best-effort-style", C_Item.GetItemUpgradeInfo, entry.link)
            if okU and u and u.trackString and u.trackString ~= ""
                and u.currentLevel and u.maxLevel then
                local abbrev = u.trackString:match("^[%z\1-\127\194-\244][\128-\191]*") or ""
                upgradeTrack = {
                    text = abbrev .. u.currentLevel .. "/" .. u.maxLevel,
                    r = 1, g = 1, b = 1,
                }
            end
        end
        if Bags.CornerWidgets then
            Bags.CornerWidgets.Apply(button, {
                entry = entry,
                details = Bags.Details and Bags.Details.Build(entry) or nil,
                isJunk = isJunk,
                inSet = inSet and true or false,
                qualityColorText = appearance and appearance.qualityColorText or false,
                craftQualityAtlas = CraftQualityAtlas(entry),
                upgradeTrack = upgradeTrack,
            }, appearance)
        end
    else
        SetItemButtonTexture(button, nil)
        SetItemButtonCount(button, 0)
        ApplyIconOverlay(button, nil)
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(button, 1, sr, sg, sb, 0.35)
        button.Cooldown:Hide()
        SetItemButtonDesaturated(button, false)
        ItemButtons.SetUnusableTint(button, false)
        if Bags.CornerWidgets then Bags.CornerWidgets.Apply(button, nil, appearance) end
    end
    if button.JunkIcon then button.JunkIcon:Hide() end
    if button.IconQuestTexture then button.IconQuestTexture:Hide() end
    if appearance and appearance.contextFading == false then
        if button.ItemContextOverlay then button.ItemContextOverlay:SetAlpha(0) end
    else
        if button.ItemContextOverlay then button.ItemContextOverlay:SetAlpha(1) end
        if button.UpdateItemContextMatching then
            button:UpdateItemContextMatching()
        end
    end
    button._newItemGuid = newGuid
    if button.NewItemTexture then
        if newGuid then
            local atlas
            if ColorManager and ColorManager.GetAtlasDataForNewItemQuality then
                atlas = ColorManager.GetAtlasDataForNewItemQuality(entry and entry.quality)
            end
            button.NewItemTexture:SetAtlas(atlas or "bags-glow-white")
            button.NewItemTexture:Show()
            if button.flashAnim and button.newitemglowAnim
                and not button.flashAnim:IsPlaying()
                and not button.newitemglowAnim:IsPlaying() then
                button.flashAnim:Play()
                button.newitemglowAnim:Play()
            end
        else
            StopNewItemGlow(button)
        end
    end
    if button.UpgradeIcon then button.UpgradeIcon:Hide() end
    ItemButtons.SetSearchDim(button, searchResult)
end

local unusableCache = {}

function ItemButtons.InvalidateUnusableCache()
    wipe(unusableCache)
end

function ItemButtons.IsUnusable(bagID, slot, link)
    if link and unusableCache[link] ~= nil then return unusableCache[link] end
    local data
    if bagID and C_TooltipInfo and C_TooltipInfo.GetBagItem then
        data = C_TooltipInfo.GetBagItem(bagID, slot)
    elseif link and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        data = C_TooltipInfo.GetHyperlink(link)
    end
    local unusable = false
    if data and data.lines then
        for _, row in ipairs(data.lines) do
            local lc, rc = row.leftColor, row.rightColor
            if lc and lc.r == 1 and lc.g < 0.2 and lc.b < 0.2
                and row.leftText ~= _G.ITEM_SCRAPABLE_NOT
                and row.leftText ~= _G.CANNOT_UNEQUIP_COMBAT
                and row.leftText ~= _G.ITEM_DISENCHANT_NOT_DISENCHANTABLE then
                unusable = true
                break
            end
            if rc and rc.r == 1 and rc.g < 0.2 and rc.b < 0.2 then
                unusable = true
                break
            end
        end
    end
    if link then unusableCache[link] = unusable end
    return unusable
end

function ItemButtons.SetUnusableTint(button, unusable)
    local icon = button.icon or button._icon
    if not icon then return end
    if unusable then
        icon:SetVertexColor(1, 0.35, 0.35)
    else
        icon:SetVertexColor(1, 1, 1)
    end
end

function ItemButtons.SetFreeCount(button, n)
    if button.Count then
        button.Count:SetText(n)
        button.Count:Show()
    elseif button._count then
        button._count:SetText(n)
    end
end

function ItemButtons.SetBagHighlight(button, on)
    if not on and not button._quiBagHighlight then return end
    local hl = button._quiBagHighlight
    if not hl then
        hl = button:CreateTexture(nil, "OVERLAY")
        hl:SetPoint("TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", -1, 1)
        hl:SetAtlas("bags-glow-heirloom")
        button._quiBagHighlight = hl
    end
    hl:SetShown(on and true or false)
end

function ItemButtons.SetFocusFlash(button, on)
    if not on then
        if button._quiFocusGlow then
            button._quiFocusAnim:Stop()
            button._quiFocusGlow:Hide()
        end
        return
    end
    if not button._quiFocusGlow then
        local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
        glow:SetAllPoints()
        glow:SetTexture("Interface\\Buttons\\WHITE8x8")
        glow:SetVertexColor(1, 0.82, 0.1, 0.4)
        if UIKit and UIKit.DisablePixelSnap then UIKit.DisablePixelSnap(glow) end
        button._quiFocusGlow = glow
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local alpha = ag:CreateAnimation("Alpha")
        alpha:SetFromAlpha(1)
        alpha:SetToAlpha(0.1)
        alpha:SetDuration(0.45)
        button._quiFocusAnim = ag
    end
    button._quiFocusGlow:Show()
    if not button._quiFocusAnim:IsPlaying() then
        button._quiFocusAnim:Play()
    end
end

function ItemButtons.SetSelectedOverlay(button, on)
    if not on then
        if button._quiSelected then button._quiSelected:Hide() end
        return
    end
    if not button._quiSelected then
        local sel = button:CreateTexture(nil, "OVERLAY", nil, 5)
        sel:SetAllPoints()
        sel:SetTexture("Interface\\Buttons\\WHITE8x8")
        sel:SetVertexColor(0.2, 0.9, 0.4, 0.35)
        if UIKit and UIKit.DisablePixelSnap then UIKit.DisablePixelSnap(sel) end
        button._quiSelected = sel
    end
    button._quiSelected:Show()
end
