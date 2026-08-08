local addonName, ns = ...
local Helpers = ns.Helpers

local QuickSalvage = {}
ns.QuickSalvage = QuickSalvage

local SPELL_DISENCHANT = 13262

local COLORS = {
    disenchant = CreateColor(0.7, 0.3, 0.9),
    milling = CreateColor(0.3, 0.8, 0.3),
    prospecting = CreateColor(1.0, 0.6, 0.2),
    salvage = CreateColor(0.2, 0.8, 1.0),
}

local currentModifier = "ALT"

local IsPlayerSpell = C_SpellBook.IsSpellKnown or IsPlayerSpell

local SalvageLookup = {}
local SalvageLookupBuilt = false
local SalvageLookupBuilding = false
local SalvageLookupLastAttempt = 0

local SALVAGE_CACHE_VERSION = 1

local function GetAceDB()
    local QUI = _G.QUI
    return QUI and QUI.db
end

local function LoadSalvageLookupFromDB()
    local db = GetAceDB()
    local global = db and db.global
    local cache = global and global.quickSalvageLookup
    if not (cache and cache.version == SALVAGE_CACHE_VERSION and type(cache.items) == "table") then
        return false
    end

    table.wipe(SalvageLookup)
    local count = 0
    for itemID, entry in pairs(cache.items) do
        if type(itemID) == "number" and type(entry) == "table" and entry.spellID then
            SalvageLookup[itemID] = {
                spellID = entry.spellID,
                required = entry.required,
                action = entry.action,
            }
            count = count + 1
        end
    end

    SalvageLookupBuilt = count > 0
    return SalvageLookupBuilt
end

local function SaveSalvageLookupToDB()
    local db = GetAceDB()
    local global = db and db.global
    if not global then return end

    local items = {}
    local count = 0
    for itemID, entry in pairs(SalvageLookup) do
        if type(itemID) == "number" and type(entry) == "table" and entry.spellID then
            items[itemID] = {
                spellID = entry.spellID,
                required = entry.required,
                action = entry.action,
            }
            count = count + 1
        end
    end

    global.quickSalvageLookup = {
        version = SALVAGE_CACHE_VERSION,
        builtAt = time and time() or nil,
        count = count,
        items = items,
    }
end

local function EnsureProfessionsUI()
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then return false end
    local profLoaded = C_AddOns.IsAddOnLoaded("Blizzard_Professions")
    local tsiLoaded = C_AddOns.IsAddOnLoaded("Blizzard_TradeSkillUI")
    return profLoaded or tsiLoaded
end

local function GetColorForAction(action)
    return COLORS[action] or COLORS.salvage
end

local function RebuildSalvageLookup()
    if SalvageLookupBuilding then return end
    if InCombatLockdown() then return end
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic) then return end
    if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then return end
    if not EnsureProfessionsUI() then return end
    local now = GetTime and GetTime() or 0
    if now > 0 and (now - SalvageLookupLastAttempt) < 10 then return end
    SalvageLookupLastAttempt = now

    SalvageLookupBuilding = true

    local ok = pcall(function()
        table.wipe(SalvageLookup)
        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs() or {}
        local salvageRecipeType = Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Salvage
        local itemRecipeType = Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Item

        for _, recipeID in ipairs(recipeIDs) do
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
            if schematic and (schematic.recipeType == salvageRecipeType or schematic.recipeType == itemRecipeType) then
                local recipeInfo = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
                local recipeSpellID = (recipeInfo and recipeInfo.recipeSpellID) or schematic.recipeSpellID
                if recipeSpellID then
                    local isLearned = (recipeInfo and recipeInfo.learned) or IsPlayerSpell(recipeSpellID)
                    if isLearned then
                        local includeRecipe = false
                        local action = "salvage"
                        if schematic.recipeType == salvageRecipeType then
                            includeRecipe = true
                        elseif recipeInfo and recipeInfo.alternateVerb then
                            if MILLING and recipeInfo.alternateVerb == MILLING then
                                includeRecipe = true
                                action = "milling"
                            elseif PROSPECTING and recipeInfo.alternateVerb == PROSPECTING then
                                includeRecipe = true
                                action = "prospecting"
                            end
                        end

                        if includeRecipe then
                            local didAddFromSlots = false
                            local slots = schematic.reagentSlotSchematics
                            if type(slots) == "table" then
                                for _, slot in ipairs(slots) do
                                    local qty = slot and slot.quantityRequired
                                    local reagents = slot and slot.reagents
                                    if type(reagents) == "table" then
                                        for _, reagent in ipairs(reagents) do
                                            local itemID = reagent and reagent.itemID
                                            if itemID then
                                                SalvageLookup[itemID] = { spellID = recipeSpellID, required = qty, action = action }
                                                didAddFromSlots = true
                                            end
                                        end
                                    end
                                end
                            end

                            if not didAddFromSlots and C_TradeSkillUI.GetSalvagableItemIDs then
                                local itemIDs = C_TradeSkillUI.GetSalvagableItemIDs(recipeID)
                                for _, itemID in ipairs(itemIDs or {}) do
                                    SalvageLookup[itemID] = { spellID = recipeSpellID, required = nil, action = action }
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    if ok then
        SalvageLookupBuilt = next(SalvageLookup) ~= nil
        if SalvageLookupBuilt then
            SaveSalvageLookupToDB()
        end
    else
        SalvageLookupBuilt = false
    end
    SalvageLookupBuilding = false
end

local function EnsureSalvageLookup()
    if SalvageLookupBuilt or SalvageLookupBuilding then return end
    if LoadSalvageLookupFromDB() then return end
    RebuildSalvageLookup()
end

local function GetSettings()
    local general = Helpers.GetModuleDB("general")
    return general and general.quickSalvage
end

local function PlayerHasSpell(spellID)
    return IsPlayerSpell(spellID)
end

local function IsModifierActive()
    if not IsAltKeyDown() then return false end

    if currentModifier == "ALTCTRL" then
        return IsControlKeyDown()
    elseif currentModifier == "ALTSHIFT" then
        return IsShiftKeyDown()
    else
        return not IsControlKeyDown() and not IsShiftKeyDown()
    end
end

local function GetSalvageInfo(itemID, stackCount)
    if not itemID then return nil end

    EnsureSalvageLookup()
    local salvage = SalvageLookup[itemID]
    if salvage and salvage.spellID then
        if salvage.required and stackCount and stackCount < salvage.required then
            return nil, nil, "salvage", salvage.required, true
        end
        local action = salvage.action or "salvage"
        return salvage.spellID, GetColorForAction(action), action, salvage.required
    end

    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not quality or not classID then
        return nil
    end

    if quality < Enum.ItemQuality.Uncommon or quality > Enum.ItemQuality.Epic then
        return nil
    end

    local isRelicGem = (classID == Enum.ItemClass.Gem and Enum.ItemGemSubclass and subClassID == Enum.ItemGemSubclass.Artifactrelic)
    if classID ~= Enum.ItemClass.Weapon
        and classID ~= Enum.ItemClass.Armor
        and classID ~= Enum.ItemClass.Profession
        and not isRelicGem
    then
        return nil
    end

    if equipLoc == "INVTYPE_BODY" then
        return nil
    end

    if C_Item.IsCosmeticItem and C_Item.IsCosmeticItem(itemID) then
        return nil
    end

    if PlayerHasSpell(SPELL_DISENCHANT) then
        return SPELL_DISENCHANT, COLORS.disenchant, "disenchant"
    end

    return nil
end

local TEMPLATES = {
    'SecureActionButtonTemplate',
    'SecureHandlerAttributeTemplate',
    'SecureHandlerEnterLeaveTemplate',
}

local SalvageButton = CreateFrame("Button", "QUI_QuickSalvageButton", UIParent, table.concat(TEMPLATES, ','))
SalvageButton:SetFrameStrata("TOOLTIP")
SalvageButton:EnableMouse(true)
SalvageButton:RegisterForClicks("AnyUp", "AnyDown")
SalvageButton:Hide()

SalvageButton.spellID = nil
SalvageButton.itemLink = nil
SalvageButton._ownerRect = nil

local Glow = SalvageButton:CreateTexture(nil, 'ARTWORK')
Glow:SetPoint('CENTER')
Glow:SetAtlas('UI-HUD-ActionBar-Proc-Loop-Flipbook')
Glow:SetDesaturated(true)

local Animation = SalvageButton:CreateAnimationGroup()
Animation:SetLooping('REPEAT')

local FlipBook = Animation:CreateAnimation('FlipBook')
FlipBook:SetTarget(Glow)
FlipBook:SetDuration(1)
FlipBook:SetFlipBookColumns(5)
FlipBook:SetFlipBookRows(6)
FlipBook:SetFlipBookFrames(30)

local function SetGlowColor(color)
    if color then
        Glow:SetVertexColor(color:GetRGB())
    end

    local width, height = SalvageButton:GetSize()
    if not width or not height or width <= 0 or height <= 0 then
        return
    end
    width = math.min(width, 256)
    height = math.min(height, 256)
    Glow:SetSize(width * 1.4, height * 1.4)
end

SalvageButton:HookScript('OnShow', function()
    Animation:Play()
end)

SalvageButton:HookScript('OnHide', function()
    Animation:Stop()
end)

local function ShowTooltip(self)
    local right = self:GetRight()
    local screenWidth = GetScreenWidth()

    if right and screenWidth and right >= screenWidth / 2 then
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    else
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    end

    local bagID = self:GetAttribute('target-bag')
    local slotID = self:GetAttribute('target-slot')

    if self.itemLink then
        GameTooltip:SetHyperlink(self.itemLink)
    elseif bagID and slotID then
        GameTooltip:SetBagItem(bagID, slotID)
    else
        return
    end

    if self.spellID then
        local spellName = C_Spell.GetSpellName(self.spellID)
        if spellName then
            GameTooltip:AddLine(' ')
            GameTooltip:AddLine('|A:NPE_LeftClick:18:18|a |cff0090ff' .. spellName .. '|r', 1, 1, 1)
        end
    end

    GameTooltip:Show()
end

SalvageButton:HookScript('OnEnter', ShowTooltip)
SalvageButton:HookScript('OnLeave', GameTooltip_Hide)

local MACRO_SALVAGE = '/run C_TradeSkillUI.CraftSalvage(%d, 1, ItemLocation:CreateFromBagAndSlot(%d, %d))'

local function ApplyOwnerRect(self, ownerRect)
    if not ownerRect then return false end

    local left, bottom, width, height = ownerRect[1], ownerRect[2], ownerRect[3], ownerRect[4]
    if not left or not bottom or not width or not height then return false end

    if width < 5 or height < 5 or width > 256 or height > 256 then return false end

    local scaleMultiplier = 1 / UIParent:GetScale()
    self:ClearAllPoints()
    self:SetPoint('BOTTOMLEFT', left * scaleMultiplier, bottom * scaleMultiplier)
    self:SetSize(width * scaleMultiplier, height * scaleMultiplier)
    return true
end

function SalvageButton:ApplySpell(bagID, slotID, itemLink, spellID, color, ownerRect)
    self:SetAttribute('target-bag', bagID)
    self:SetAttribute('target-slot', slotID)
    self.itemLink = itemLink
    self.spellID = spellID
    self._ownerRect = ownerRect

    if not ApplyOwnerRect(self, ownerRect) then
        self._ownerRect = nil
        return
    end

    local typePrefix
    if currentModifier == "ALTCTRL" then
        typePrefix = "alt-ctrl-"
    elseif currentModifier == "ALTSHIFT" then
        typePrefix = "alt-shift-"
    else
        typePrefix = "alt-"
    end

    local spellSlot = FindSpellBookSlotBySpellID and FindSpellBookSlotBySpellID(spellID)

    if spellSlot then
        self:SetAttribute('spell', spellID)
        self:SetAttribute(typePrefix .. 'type1', 'spell')
        self:SetAttribute(typePrefix .. 'spell1', spellID)
        self:SetAttribute(typePrefix .. 'macrotext1', nil)
        self:SetAttribute('type1', nil)
    else
        local macroText = MACRO_SALVAGE:format(spellID, bagID, slotID)
        self:SetAttribute('macrotext', macroText)
        self:SetAttribute(typePrefix .. 'type1', 'macro')
        self:SetAttribute(typePrefix .. 'macrotext1', macroText)
        self:SetAttribute(typePrefix .. 'spell1', nil)
        self:SetAttribute('type1', nil)
    end

    self:Show()
    SetGlowColor(color)
end

function SalvageButton:UpdateAttributeDriver()
    if InCombatLockdown() then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then
        UnregisterStateDriver(self, 'visibility')
        return
    end

    currentModifier = settings.modifier or "ALT"
    UnregisterStateDriver(self, 'visibility')
end

SalvageButton:HookScript('OnShow', function(self)
    ApplyOwnerRect(self, self._ownerRect)
end)

SalvageButton:HookScript('OnShow', function(self)
    self:SetAttribute('_entered', true)
end)

SalvageButton:SetAttribute('_onleave', 'self:ClearAllPoints();self:Hide()')

SalvageButton:SetAttribute('_onattributechanged', [[
    if name == 'visibility' and value == 'hide' and self:IsShown() then
        self:ClearAllPoints()
        self:Hide()
    end
]])

SalvageButton:HookScript('OnHide', function(self)
    self.itemLink = nil
    self.spellID = nil
    self._ownerRect = nil
    if not InCombatLockdown() then
        self:SetAttribute('target-bag', nil)
        self:SetAttribute('target-slot', nil)
        self:SetAttribute('_entered', false)
        self:SetAttribute('type1', nil)
        self:SetAttribute('spell', nil)
        self:SetAttribute('macrotext', nil)
        self:SetAttribute('alt-type1', nil)
        self:SetAttribute('alt-spell1', nil)
        self:SetAttribute('alt-macrotext1', nil)
        self:SetAttribute('alt-ctrl-type1', nil)
        self:SetAttribute('alt-ctrl-spell1', nil)
        self:SetAttribute('alt-ctrl-macrotext1', nil)
        self:SetAttribute('alt-shift-type1', nil)
        self:SetAttribute('alt-shift-spell1', nil)
        self:SetAttribute('alt-shift-macrotext1', nil)
    end
end)

local ERR_COLOR = CreateColor(1, 0.125, 0.125)

local function TooltipHelp(msg, color)
    GameTooltip:AddLine(' ')
    GameTooltip:AddLine(msg, color and color:GetRGB())
    GameTooltip:Show()
end

local function BuildOwnerRect(owner)
    if owner.GetScaledRect and not (owner.IsAnchoringRestricted and owner:IsAnchoringRestricted()) then
        local left, bottom, width, height = owner:GetScaledRect()
        if left and bottom and width and height then
            return { left, bottom, width, height }
        end
    end
    return nil
end

local function OnTooltipSetItem(tooltip, data)
    if not IsModifierActive() then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if InCombatLockdown() then return end

    if tooltip:GetOwner() == SalvageButton then return end

    if (AuctionFrame or AuctionHouseFrame) and (AuctionFrame or AuctionHouseFrame):IsVisible() then return end
    if UnitHasVehicleUI and UnitHasVehicleUI('player') then return end

    local itemID, itemLink
    if data and data.id then
        itemID = data.id
        itemLink = data.hyperlink
    else
        local _, link = tooltip:GetItem()
        if link then
            itemLink = link
            itemID = C_Item.GetItemIDForItemInfo(link)
        end
    end

    if not itemID then return end

    local owner = tooltip:GetOwner()
    if not owner then return end

    local bagID, slotID, stackCount

    if owner.GetSlotAndBagID then
        slotID, bagID = owner:GetSlotAndBagID()
    elseif owner.GetBagID and owner.GetID then
        bagID = owner:GetBagID()
        slotID = owner:GetID()
    end

    if not bagID or not slotID then return end

    local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
    if C_Item and C_Item.GetStackCount and itemLocation then
        stackCount = C_Item.GetStackCount(itemLocation)
    else
        local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
        if itemInfo then
            stackCount = itemInfo.stackCount
        end
    end

    local ownerRect = BuildOwnerRect(owner)
    if not ownerRect then return end

    local spellID, color, actionType, requiredStack, needsMore = GetSalvageInfo(itemID, stackCount)

    if not spellID and not SalvageLookupBuilt then
        TooltipHelp(ns.L["Quick Salvage: open Professions once to initialize prospecting/milling."], CreateColor(1, 1, 0.2))
        return
    end

    if needsMore then
        local itemName = C_Item.GetItemNameByID(itemID) or "item"
        TooltipHelp(SPELL_FAILED_NEED_MORE_ITEMS:format(requiredStack, itemName), ERR_COLOR)
        return
    end

    if spellID then
        if not PlayerHasSpell(spellID) then
            local spellName = C_Spell.GetSpellName(spellID)
            TooltipHelp(ERR_USE_LOCKED_WITH_SPELL_S:format(spellName or "Unknown"), ERR_COLOR)
            return
        end

        SalvageButton:ApplySpell(bagID, slotID, itemLink, spellID, color, ownerRect)
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
eventFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "BAG_UPDATE_DELAYED" then
        if SalvageButton:IsShown() and not InCombatLockdown() then
            SalvageButton:Hide()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function()
            SalvageButton:UpdateAttributeDriver()
        end)
        C_Timer.After(2, function()
            LoadSalvageLookupFromDB()
        end)
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        if not InCombatLockdown() then
            RebuildSalvageLookup()
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if SalvageButton:IsShown() then
            ShowTooltip(SalvageButton)

            if not IsModifierActive() and not InCombatLockdown() then
                SalvageButton:Hide()
            end
        elseif GameTooltip:IsShown() and IsModifierActive() and not InCombatLockdown() then
            local owner = GameTooltip:GetOwner()
            if owner and Helpers.SafeValue(owner:IsMouseOver(), false) then
                if owner.GetSlotAndBagID then
                    local slotID, bagID = owner:GetSlotAndBagID()
                    if bagID and slotID then
                        local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                        if itemInfo and itemInfo.hyperlink then
                            local itemID = C_Item.GetItemIDForItemInfo(itemInfo.hyperlink)
                            if itemID then
                                local spellID, color, actionType, requiredStack, needsMore = GetSalvageInfo(itemID, itemInfo.stackCount)
                                if spellID and not needsMore then
                                    local rect = BuildOwnerRect(owner)
                                    if rect then
                                        SalvageButton:ApplySpell(bagID, slotID, itemInfo.hyperlink, spellID, color, rect)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        C_Timer.After(1, function()
            SalvageButton:UpdateAttributeDriver()
        end)
        C_Timer.After(2, function()
            LoadSalvageLookupFromDB()
        end)
    end)
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)

function _G.QUI_RefreshQuickSalvage()
    if not InCombatLockdown() then
        SalvageButton:UpdateAttributeDriver()
    end
end

QuickSalvage.Button = SalvageButton
QuickSalvage.Refresh = _G.QUI_RefreshQuickSalvage
