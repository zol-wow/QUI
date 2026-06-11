---------------------------------------------------------------------------
-- Bags views: live item buttons. Pools ContainerFrameItemButtonTemplate
-- buttons under per-bag holder frames (SetID protocol — the Blizzard mixin
-- resolves bagID via GetParent():GetID(), slot via self:GetID()), giving
-- native click/drag/split/use/tooltip/context behavior with zero secure-
-- frame surgery. QUI dressing: quality 1px border, search dim, lock desat,
-- cooldown.
---------------------------------------------------------------------------
-- luacheck: read globals ColorManager ITEM_QUALITY_COLORS SplitGuildBankItem
-- luacheck: read globals HandleModifiedItemClick GetGuildBankItemLink IsModifiedClick CursorHasItem
-- luacheck: read globals GetGuildBankItemInfo StackSplitFrame DepositGuildBankMoney
-- luacheck: read globals AutoStoreGuildBankItem PickupGuildBankItem SetItemButtonTexture
-- luacheck: read globals SetItemButtonCount SetItemButtonDesaturated
-- luacheck: read globals C_AuctionHouse ItemButtonUtil ItemLocation
-- luacheck: read globals ContainerFrameItemButtonMixin
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local UIKit = ns.UIKit
local Helpers = ns.Helpers

local ItemButtons = {}
Bags.ItemButtons = ItemButtons

local GetSettings = Helpers.CreateDBGetter("bags")

local SEARCH_DIM = 0.3

local function GetQualityColor(quality)
    -- 12.0 modern path: ColorManager wraps quality colors (incl. user
    -- accessibility overrides); the ITEM_QUALITY_COLORS global still exists
    -- (Blizzard_Colors/ColorConstants.lua) and is kept as fallback.
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
-- shared with the search-everywhere window's quality-colored name rows
ItemButtons.GetQualityColor = GetQualityColor

--- One holder per (parent window, bagID): carries the bag ID for the mixin.
function ItemButtons.CreateHolder(parent, bagID)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetID(bagID)
    holder:SetAllPoints(parent)
    return holder
end

--- Flat slot fill behind the icon, shared by every button flavor (live,
--- cached, guild) so occupied and empty slots read as one QUI surface
--- instead of the Blizzard slot art.
function ItemButtons.AddSlotBackground(button)
    if button._quiSlotBg then return end
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    button._quiSlotBg = bg
end

--- Auction-house sell-context match. Stock bags' context list (vendored
--- ItemUtil.lua GetItemContext) has NO auctioneer entry, so the template
--- pipeline never fades anything at the AH — QUI adds it: while the auction
--- house is open, an occupied slot whose item fails
--- C_AuctionHouse.IsSellItemValid renders the stock Mismatch treatment
--- (black 0.8 ItemContextOverlay), the same darkening the scrapper/upgrade
--- UIs get. This MUST live inside the stock pipeline as a per-button
--- GetItemContextMatchResult override (installed in CreateLive), NOT as a
--- manual overlay write: the intrinsic's PostOnShow runs
--- UpdateItemContextMatching after every pooled re-Show (vendored
--- ItemButtonTemplate.lua:16) and reverts any hand-set overlay state.
--- → nil when the auction context doesn't apply (defer to stock matching),
--- else an ItemButtonUtil.ItemContextMatchResult value.
local function AuctionContextMatchResult(button)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return nil end
    -- a real context UI open alongside the AH keeps priority (mirrors stock:
    -- an active GetItemContext owns the overlay)
    if ItemButtonUtil.GetItemContext() ~= nil then return nil end
    local bagID, slot = button:GetBagID(), button:GetID()
    if not C_Container.GetContainerItemInfo(bagID, slot) then
        return ItemButtonUtil.ItemContextMatchResult.DoesNotApply -- empty slot
    end
    local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not (loc and loc:IsValid()) then
        return ItemButtonUtil.ItemContextMatchResult.DoesNotApply
    end
    return C_AuctionHouse.IsSellItemValid(loc, false)
        and ItemButtonUtil.ItemContextMatchResult.Match
        or ItemButtonUtil.ItemContextMatchResult.Mismatch
end

--- CreateLive installs this over the container mixin's method; every stock
--- consumer (PostOnShow, the ItemContextChanged callback, QUI's Dress call
--- to UpdateItemContextMatching) then computes the auction fade natively.
local function LiveGetItemContextMatchResult(button)
    local auction = AuctionContextMatchResult(button)
    if auction ~= nil then return auction end
    return ContainerFrameItemButtonMixin.GetItemContextMatchResult(button)
end

--- Create one live button under a holder. NOT pooled across bags (a button's
--- holder fixes its bagID); pooled per holder by the window.
function ItemButtons.CreateLive(holder, bagID)
    local button = CreateFrame("ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")
    button:SetBagID(bagID)
    -- AH sell fade rides the stock context pipeline through this override —
    -- a plain data method (NOT a secure script handler; the OnClick
    -- replacement prohibition doesn't apply), consulted by the mixin's
    -- UpdateItemContextMatching from PostOnShow and context callbacks.
    button.GetItemContextMatchResult = LiveGetItemContextMatchResult
    -- Blizzard's IconBorder is replaced by the QUI pixel border
    if button.IconBorder then button.IconBorder:SetAlpha(0) end
    -- The template ships BattlepayItemTexture VISIBLE by default — it is the
    -- only overlay in ContainerFrame.xml with no hidden=/alpha=0 attribute.
    -- Stock bags hide it on every UpdateNewItem pass, which Dress REPLACES,
    -- so without this one-time hide every button permanently wears the store
    -- highlight ("everything looks new", surviving reloads — hover hides it
    -- per button via the mixin's hover handler, masquerading as the
    -- new-item glow). QUI never renders the battlepay highlight.
    if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
    -- Strip the rest of the Blizzard slot chrome QUI replaces: the quickslot
    -- ring (NormalTexture renders larger than the button and overlaps
    -- neighbors once spacing shrinks) and the stock empty-slot art (the
    -- ItemButton mixin falls back to emptyBackgroundAtlas whenever no item
    -- texture is set). QUI draws its own pixel border + flat fill instead.
    if button.ClearNormalTexture then button:ClearNormalTexture() end
    button.emptyBackgroundAtlas = nil
    ItemButtons.AddSlotBackground(button)
    UIKit.CreateBorderLines(button)
    -- New-item glow seen-marking. HookScript is sanctioned here: the
    -- template wires OnEnter as a plain function script ("NOTE: Tutorials
    -- hook this" — vendored ContainerFrame.xml:76), and Blizzard's own
    -- handler (Mixin:OnEnter → OnUpdate, ContainerFrame.lua:1538-1548)
    -- already hides NewItemTexture + stops the anims before this post-hook
    -- runs — so the hook only persists the seen state in the char store;
    -- the next Dress then keeps the glow off.
    button:HookScript("OnEnter", function(self)
        if self._newItemGuid then
            if Bags.NewItems then Bags.NewItems.MarkSlotSeen(self._newItemGuid) end
            self._newItemGuid = nil
        end
    end)
    return button
end

--- Shared cached-surface tooltip. battlepet: hyperlinks (caged pets — the
--- container API hands the cage's hyperlink over in this form) cannot be
--- rendered by GameTooltip:SetHyperlink; they route through
--- BattlePetToolTip_ShowLink, which anchors BattlePetTooltip to
--- GameTooltip's point — so the owner anchor is set FIRST either way (the
--- AH caller idiom, vendored Blizzard_AuctionHouseSharedTemplates.lua:25).
--- The battlepet check outranks itemID: SetItemByID(82800) would show the
--- generic cage tooltip instead of the pet.
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

--- Leave-path counterpart: BattlePetTooltip is a separate frame that
--- GameTooltip:Hide() never touches — a zombie pet tooltip survives
--- otherwise.
function ItemButtons.HideItemTooltip()
    GameTooltip:Hide()
    if BattlePetTooltip then BattlePetTooltip:Hide() end
end

--- Inert browse button (cached/offline viewing): icon/count/quality border +
--- hyperlink tooltip. NOT a ContainerFrameItemButtonTemplate — no live ops.
function ItemButtons.CreateCached(parent)
    local button = CreateFrame("Button", nil, parent)
    ItemButtons.AddSlotBackground(button)
    button._icon = button:CreateTexture(nil, "ARTWORK")
    button._icon:SetAllPoints()
    button._count = button:CreateFontString(nil, "OVERLAY")
    button._count:SetPoint("BOTTOMRIGHT", -2, 2)
    button._count:SetFont(Helpers.GetGeneralFont(), 11, "OUTLINE")
    UIKit.CreateBorderLines(button)
    button:SetScript("OnEnter", function(self)
        if self._link then
            ItemButtons.ShowItemTooltip(self, self._link, nil)
        end
    end)
    button:SetScript("OnLeave", function() ItemButtons.HideItemTooltip() end)
    return button
end

-- Crafting-quality tier badge (reagent r1–r5, crafted gear rank) for the
-- crafting_quality corner widget. Blizzard's lookup order (vendored
-- ItemButtonTemplate.lua:322-335): GetItemReagentQualityInfo first, then
-- GetItemCraftedQualityInfo; both → CraftingQualityInfo (nilable) whose
-- iconSmall atlas fits the 12px corner slot. Static per item link, so the
-- result (including misses, as false) memoizes by link-or-itemID.
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

--- Dress a cached button from a cache slot entry (nil entry = empty slot).
--- searchResult: true (match) | false (dim) | nil (no active search).
--- Cached surfaces have no live junk/equipment-set facts: junk falls back
--- to quality 0, the set glyph is live-only.
function ItemButtons.DressCached(button, entry, searchResult)
    local appearance = GetSettings().appearance
    if entry then
        button._link = entry.link
        button._icon:SetTexture(entry.icon)
        button._icon:Show()
        button._count:SetText("") -- the quantity corner widget owns the number
        local r, g, b = GetQualityColor(entry.quality or 1)
        UIKit.UpdateBorderLines(button, 1, r, g, b, 1)
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
        ItemButtons.SetUnusableTint(button, false)
        if Bags.CornerWidgets then Bags.CornerWidgets.Apply(button, nil, appearance) end
    end
    button:SetAlpha(searchResult == false and SEARCH_DIM or 1)
end

---------------------------------------------------------------------------
-- Guild live buttons. ContainerFrameItemButtonTemplate is unusable for
-- guild slots (its mixin routes everything through C_Container bag/slot
-- IDs; guild slots have none), so these are plain buttons wired straight
-- to the legacy guild cursor APIs — the exact handler set Blizzard's
-- GuildBankItemButtonMixin uses (vendored Blizzard_GuildBankUI.lua:676-746).
-- The button carries _tab/_slot (set by DressGuildLive) instead of the
-- SetID protocol.
---------------------------------------------------------------------------

--- Create one live guild button: CreateCached's visual base (icon, count,
--- QUI border) + cursor-API interaction handlers.
function ItemButtons.CreateGuildLive(parent)
    local button = CreateFrame("Button", nil, parent)
    ItemButtons.AddSlotBackground(button)
    button._icon = button:CreateTexture(nil, "ARTWORK")
    button._icon:SetAllPoints()
    button._count = button:CreateFontString(nil, "OVERLAY")
    button._count:SetPoint("BOTTOMRIGHT", -2, 2)
    button._count:SetFont(Helpers.GetGeneralFont(), 11, "OUTLINE")
    UIKit.CreateBorderLines(button)

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    -- StackSplitFrame owner protocol (Blizzard_GuildBankUI.lua:681-683):
    -- the okay button calls owner.SplitStack(owner, split)
    -- (StackSplitFrame.lua:237-238); the split lands on the cursor.
    button.SplitStack = function(self, split)
        SplitGuildBankItem(self._tab, self._slot, split)
    end

    button:SetScript("OnClick", function(self, mouseButton)
        -- Modified clicks first (chat link / dressing room / split), then
        -- cursor-money, then the pickup/withdraw pair — Blizzard's exact
        -- OnClick order (Blizzard_GuildBankUI.lua:687-715).
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
            -- gold on the cursor dropped onto a slot deposits it (parity)
            DepositGuildBankMoney(money)
            ClearCursor()
        elseif mouseButton == "RightButton" then
            AutoStoreGuildBankItem(self._tab, self._slot) -- withdraw to bags
        else
            PickupGuildBankItem(self._tab, self._slot)
        end
    end)
    button:SetScript("OnDragStart", function(self)
        PickupGuildBankItem(self._tab, self._slot)
    end)
    button:SetScript("OnReceiveDrag", function(self)
        PickupGuildBankItem(self._tab, self._slot) -- drop INTO the slot
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if Bags.GuildTakeover and Bags.GuildTakeover.IsLive() then
            -- live tooltip incl. per-slot withdraw info (vendored :719)
            GameTooltip:SetGuildBankItem(self._tab, self._slot)
        elseif self._link then
            GameTooltip:SetHyperlink(self._link)
        else
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnHide", function(self)
        -- a hidden owner must drop its split popup (vendored :728-732)
        if self.hasStackSplit == 1 and StackSplitFrame then
            StackSplitFrame:Hide()
        end
    end)
    return button
end

--- Dress a guild live button from a cache slot entry (nil = empty slot).
--- tab/slot bind the cursor APIs; searchResult: true | false (dim) | nil.
function ItemButtons.DressGuildLive(button, tab, slot, entry, searchResult)
    button._tab, button._slot = tab, slot
    local appearance = GetSettings().appearance
    if entry then
        button._link = entry.link
        button._icon:SetTexture(entry.icon)
        button._icon:Show()
        button._count:SetText("") -- the quantity corner widget owns the number
        local r, g, b = GetQualityColor(entry.quality or 1)
        UIKit.UpdateBorderLines(button, 1, r, g, b, 1)
        -- Lock state is live (not cached): GetGuildBankItemInfo →
        -- texture, itemCount, locked (3rd return); query at dress time.
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
        button._icon:SetDesaturated(false)
        ItemButtons.SetUnusableTint(button, false)
        if Bags.CornerWidgets then Bags.CornerWidgets.Apply(button, nil, appearance) end
    end
    button:SetAlpha(searchResult == false and SEARCH_DIM or 1)
end

--- Dress a live button from a cache slot entry (nil entry = empty slot).
--- searchResult: true (match) | false (dim) | nil (no active search).
--- newGuid: glow-eligible item GUID | nil (bag window live mode passes
--- NewItems.CheckSlot's result; every other caller leaves it nil → no glow).
function ItemButtons.Dress(button, entry, searchResult, newGuid)
    local appearance = GetSettings().appearance
    if entry then
        SetItemButtonTexture(button, entry.icon)
        -- native count stays off: the quantity corner widget owns the number
        SetItemButtonCount(button, 0)
        local r, g, b = GetQualityColor(entry.quality or 1)
        local start, duration, enable = C_Container.GetContainerItemCooldown(button:GetBagID(), button:GetID())
        CooldownFrame_Set(button.Cooldown, start, duration, enable)
        -- Lock state is live (not cached): query at dress time.
        local live = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
        local junkCfg = GetSettings().behavior.junk
        local isJunk = (junkCfg and junkCfg.dim and Bags.Junk and live
            and Bags.Junk.IsJunk(live, button:GetBagID(), junkCfg.exclusions))
            and true or false
        SetItemButtonDesaturated(button, (live and live.isLocked)
            or (appearance and appearance.greyJunk and isJunk) or false)
        -- Equipment-set lookup (live dressing only — the API answers the
        -- player's own containers; cached/guild dressing never lands here).
        -- Doc: GetContainerItemEquipmentSetInfo(bag, slot) → inSet bool,
        -- setList string (both Nilable=false).
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
        if Bags.CornerWidgets then
            Bags.CornerWidgets.Apply(button, {
                entry = entry,
                details = Bags.Details and Bags.Details.Build(entry) or nil,
                isJunk = isJunk,
                inSet = inSet and true or false,
                qualityColorText = appearance and appearance.qualityColorText or false,
                craftQualityAtlas = CraftQualityAtlas(entry),
            }, appearance)
        end
    else
        SetItemButtonTexture(button, nil)
        SetItemButtonCount(button, 0)
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(button, 1, sr, sg, sb, 0.35)
        button.Cooldown:Hide()
        SetItemButtonDesaturated(button, false)
        ItemButtons.SetUnusableTint(button, false)
        if Bags.CornerWidgets then Bags.CornerWidgets.Apply(button, nil, appearance) end
    end
    -- the corner system owns the junk coin now; the template's stays off
    if button.JunkIcon then button.JunkIcon:Hide() end
    if button.IconQuestTexture then button.IconQuestTexture:Hide() end
    -- Item-context matching (socketing/upgrade/scrapping UIs + the QUI
    -- auction-sell fade via LiveGetItemContextMatchResult): the template
    -- mixin fades non-matching slots on its own via the ItemContextChanged
    -- callback (PostOnShow), but a content change re-dressed by OUR Refresh
    -- bypasses the mixin's SetItem path — re-evaluate here so the overlay
    -- tracks the slot's CURRENT item while a context applies. The
    -- contextFading toggle suppresses the overlay via alpha (the mixin's
    -- own PostOnShow pass keeps SetShown-ing it); re-assert alpha 1 when
    -- enabled or a toggle off→on would stay invisible until reload.
    if appearance and appearance.contextFading == false then
        if button.ItemContextOverlay then button.ItemContextOverlay:SetAlpha(0) end
    else
        if button.ItemContextOverlay then button.ItemContextOverlay:SetAlpha(1) end
        if button.UpdateItemContextMatching then
            button:UpdateItemContextMatching()
        end
    end
    -- New-item glow: the template's reserved NewItemTexture + its two anim
    -- groups, driven exactly like Blizzard's UpdateNewItem (vendored
    -- ContainerFrame.lua:1688-1719): quality atlas when ColorManager has
    -- one, "bags-glow-white" fallback; flash plays only when the looping
    -- glow starts (the IsPlaying guard), both stop when eligibility ends.
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
            button.NewItemTexture:Hide()
            if button.flashAnim and button.flashAnim:IsPlaying() then
                button.flashAnim:Stop()
            end
            if button.newitemglowAnim and button.newitemglowAnim:IsPlaying() then
                button.newitemglowAnim:Stop()
            end
        end
    end
    if button.UpgradeIcon then button.UpgradeIcon:Hide() end
    if searchResult == false then
        button:SetAlpha(SEARCH_DIM)
    else
        button:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- Equipment-set mark: a small gear glyph in the slot's top-left corner for
-- items that belong to a saved equipment set. QUI-owned overlay (stock bags
-- have no such marker); atlas "questlog-icon-setting" is the small gear
-- used by Blizzard's quest-log settings button (verified in vendored XML).
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Unusable marking: red-tint the icon when the item's own tooltip carries
-- red (unusable) text — the only API surface that knows proficiency.
-- C_TooltipInfo (TooltipInfoDocumentation: GetBagItem(bag, slot),
-- GetHyperlink(link)) returns plain line tables; colors are not secrets.
-- Cached per link: proficiency changes are rare (level-ups), and a stale
-- verdict only mistints until the next session.
---------------------------------------------------------------------------
local unusableCache = {} -- [itemLink] = true|false

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
            -- red left text that isn't one of the benign "can't right now"
            -- lines (same exclusion set the stock red-text rendering uses
            -- for non-proficiency reasons)
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

--- Red usability tint on the icon (live template `icon` or custom `_icon`).
function ItemButtons.SetUnusableTint(button, unusable)
    local icon = button.icon or button._icon
    if not icon then return end
    if unusable then
        icon:SetVertexColor(1, 0.35, 0.35)
    else
        icon:SetVertexColor(1, 1, 1)
    end
end

--- Free-slot counter for the grouped-empty-slots cell (flat mode): the one
--- surviving empty button shows how many free slots it stands in for.
function ItemButtons.SetFreeCount(button, n)
    if button.Count then
        button.Count:SetText(n)
        button.Count:Show()
    elseif button._count then
        button._count:SetText(n)
    end
end

---------------------------------------------------------------------------
-- Search-focus flash: a pulsing accent overlay on the slot a search-
-- everywhere navigation landed on. Window code calls this from its grid
-- loop (on = entry.itemID == the window's focus item). Works on live,
-- cached, and guild buttons alike — the overlay is QUI-owned (no template
-- fields touched). BOUNCE alpha loop; the WINDOW clears focus state, this
-- only renders it.
---------------------------------------------------------------------------
--- Container-membership highlight: shown while a bank tab button is
--- hovered so the unified (All) grid reveals which slots belong to that
--- tab. Lazy overlay texture; bags-glow-heirloom reads as a soft gold
--- wash over the icon without hiding quality borders.
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

---------------------------------------------------------------------------
-- Selection overlay: steady accent tint while the bag window's select mode
-- has the slot marked for a batch send. QUI-owned overlay, sits below the
-- focus flash (sublevel 5 < 7).
---------------------------------------------------------------------------
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
