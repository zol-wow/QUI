local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local MAX_SALES_PER_VISIT = 12

-- <<< QUI_TEST_EXTRACT decide_sale
local function DecideSale(cfg, facts)
    if facts.hasNoValue then return false end
    if facts.protected then return false end
    if facts.inSet then return false end
    if facts.upgradable then return false end
    if facts.unboundTradable then return false end

    if facts.forced then return true end

    if facts.classID ~= 2 and facts.classID ~= 4 then return false end
    if type(facts.quality) ~= "number" then return false end
    if facts.quality > (cfg.maxQuality or 0) then return false end
    local maxIlvl = cfg.maxIlvl or 0
    if maxIlvl > 0 then
        if type(facts.ilvl) ~= "number" then return false end
        if facts.ilvl >= maxIlvl then return false end
    end
    return true
end
-- <<< QUI_TEST_EXTRACT decide_sale

local function ParseIDList(text)
    local set = {}
    if type(text) == "string" then
        for id in text:gmatch("%d+") do
            set[tonumber(id)] = true
        end
    end
    return set
end

local function GatherFacts(info, bag, slot, forceSet, neverSet)
    local facts = {
        quality = info.quality,
        hasNoValue = info.hasNoValue and true or false,
        forced = (info.itemID and forceSet[info.itemID]) and true or false,
        protected = (info.itemID and neverSet[info.itemID]) and true or false,
        inSet = false,
        upgradable = false,
        unboundTradable = false,
        classID = nil,
        ilvl = nil,
    }

    if C_Container.GetContainerItemEquipmentSetInfo then
        facts.inSet = C_Container.GetContainerItemEquipmentSetInfo(bag, slot) and true or false
    end

    local link = info.hyperlink
    if link then
        local okI, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, link)
        if okI then facts.classID = classID end

        if C_Item.GetItemUpgradeInfo then
            local okU, u = pcall(C_Item.GetItemUpgradeInfo, link)
            if okU and u and u.currentLevel and u.maxLevel and u.currentLevel < u.maxLevel then
                facts.upgradable = true
            end
        end

        if C_Item.GetDetailedItemLevelInfo then
            local okL, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
            if okL and type(ilvl) == "number" then facts.ilvl = ilvl end
        end
    end

    if info.isBound == false and (facts.classID == 2 or facts.classID == 4) then
        facts.unboundTradable = true
    end

    return facts
end

local function RunRules()
    local settings = GetSettings()
    local cfg = settings and settings.vendorRules
    if not cfg or not cfg.enabled then return end

    local forceSet = ParseIDList(cfg.forceSell)
    local neverSet = ParseIDList(cfg.neverSell)
    local preview = cfg.previewOnly ~= false
    local sold = 0

    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if sold >= MAX_SALES_PER_VISIT then break end
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not info.isLocked then
                local facts = GatherFacts(info, bag, slot, forceSet, neverSet)
                if DecideSale(cfg, facts) then
                    sold = sold + 1
                    if preview then
                        print("|cff60A5FAQUI Vendor Rules (preview):|r would sell "
                            .. (info.hyperlink or ("item " .. tostring(info.itemID))))
                    else
                        C_Container.UseContainerItem(bag, slot)
                    end
                end
            end
        end
        if sold >= MAX_SALES_PER_VISIT then break end
    end

    if sold > 0 then
        if preview then
            print(("|cff60A5FAQUI Vendor Rules:|r preview mode — %d item(s) matched. Disable preview in QoL > Merchant to sell for real."):format(sold))
        else
            print(("|cff60A5FAQUI Vendor Rules:|r sold %d item(s)%s."):format(sold,
                sold >= MAX_SALES_PER_VISIT and " (per-visit cap reached)" or ""))
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function()
    C_Timer.After(0, RunRules)
end)

ns.RunVendorRules = RunRules
