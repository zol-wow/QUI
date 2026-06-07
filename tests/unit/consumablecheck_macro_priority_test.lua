-- tests/unit/consumablecheck_macro_priority_test.lua
-- Run: lua tests/unit/consumablecheck_macro_priority_test.lua

local function noop() end

local settings = {
    consumablePreferredFlask = 241325,
    consumablePreferredRune = 243191,
}

local function newFrame()
    local frame = { shown = false }
    local methods = {}

    function methods:SetSize(...) self.size = { ... } end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:ClearAllPoints() self.point = nil end
    function methods:SetAllPoints(...) self.allPoints = { ... } end
    function methods:SetColorTexture(...) self.color = { ... } end
    function methods:SetTexture(texture) self.texture = texture end
    function methods:SetText(text) self.text = text end
    function methods:SetTextColor(...) self.textColor = { ... } end
    function methods:SetFont(...) self.font = { ... } end
    function methods:SetJustifyH(value) self.justifyH = value end
    function methods:SetBackdrop(...) self.backdrop = { ... } end
    function methods:SetBackdropColor(...) self.backdropColor = { ... } end
    function methods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
    function methods:SetFrameStrata(value) self.frameStrata = value end
    function methods:SetFrameLevel(value) self.frameLevel = value end
    function methods:SetClampedToScreen(value) self.clampedToScreen = value end
    function methods:SetScale(value) self.scale = value end
    function methods:SetAlpha(value) self.alpha = value end
    function methods:SetParent(parent) self.parent = parent end
    function methods:SetAttribute(key, value) self[key] = value end
    function methods:RegisterForClicks(...) self.clicks = { ... } end
    function methods:EnableMouse(value) self.mouse = value end
    function methods:RegisterEvent(event)
        local events = rawget(self, "events") or {}
        rawset(self, "events", events)
        events[event] = true
    end
    function methods:RegisterUnitEvent(event)
        local events = rawget(self, "events") or {}
        rawset(self, "events", events)
        events[event] = true
    end
    function methods:UnregisterEvent(event)
        local events = rawget(self, "events")
        if events then events[event] = nil end
    end
    function methods:UnregisterAllEvents() rawset(self, "events", {}) end
    function methods:SetScript(script, handler)
        local scripts = rawget(self, "scripts") or {}
        rawset(self, "scripts", scripts)
        scripts[script] = handler
    end
    function methods:Hide() self.shown = false end
    function methods:Show() self.shown = true end
    function methods:IsShown() return self.shown end
    function methods:CreateTexture() return newFrame() end
    function methods:CreateFontString() return newFrame() end
    function methods:GetStringWidth() return #(self.text or "") * 6 end

    return setmetatable(frame, {
        __index = function(_, key)
            return methods[key] or noop
        end,
    })
end

function CreateFrame()
    return newFrame()
end

function LibStub()
    return nil
end

function UnitClass()
    return "Mage", "MAGE"
end

function InCombatLockdown()
    return false
end

UIParent = newFrame()
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NUM_BAG_SLOTS = 0
Enum = {
    ItemClass = {
        Consumable = 0,
    },
    ItemConsumableSubclass = {
        FoodAndDrink = 5,
        Flask = 3,
        Phial = 3,
    },
}

local bagItems = {
    [1] = 245930, -- Gold Fleeting Blood Knights
    [2] = 241325, -- Silver Crafted Blood Knights
}

local itemCounts = {
    [259085] = 1, -- Void-Touched Augment Rune
    [243191] = 1, -- Ethereal Augment Rune
}

C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and #bagItems or 0
    end,
    GetContainerItemID = function(bag, slot)
        if bag ~= 0 then return nil end
        return bagItems[slot]
    end,
    GetContainerItemInfo = function(bag, slot)
        if bag ~= 0 or not bagItems[slot] then return nil end
        return { stackCount = slot }
    end,
}

C_Item = {
    GetItemSpell = function()
        return nil, nil
    end,
    GetItemInfoInstant = function(itemID)
        return nil, nil, nil, nil, 100000 + itemID
    end,
    GetItemInfo = function(itemID)
        if itemID == 241325 then return "A Silver Crafted Flask" end
        if itemID == 245930 then return "Z Gold Fleeting Flask" end
        if itemID == 243191 then return "A Ethereal Augment Rune" end
        if itemID == 259085 then return "Z Void-Touched Augment Rune" end
        return "item:" .. tostring(itemID)
    end,
    GetItemCount = function(itemID)
        return itemCounts[itemID] or 0
    end,
    GetItemIconByID = function(itemID)
        return 100000 + itemID
    end,
}

C_Spell = {
    GetSpellTexture = function()
        return nil
    end,
}

C_UnitAuras = {
    GetAuraDataByIndex = function()
        return nil
    end,
}

C_Timer = {
    After = function(_, callback) if callback then callback() end end,
    NewTicker = function() return { Cancel = noop } end,
}

local ns = {
    __test = true,
    Helpers = {
        CreateDBGetter = function()
            return function()
                return settings
            end
        end,
    },
    ConsumableMacros = {
        GetVariantOrderForItem = function(itemID)
            if itemID == 245930 or itemID == 245931 or itemID == 241324 or itemID == 241325 then
                return { 245930, 245931, 241324, 241325 }
            end
            return nil
        end,
    },
    Utils = {
        IsInInstancedContent = function()
            return true
        end,
    },
}

assert(loadfile("QUI_QoL/qol/consumablecheck.lua"))("QUI", ns)

local check = assert(ns.ConsumableCheckTest, "consumable check test seam should be exported")
assert(check.RuneIconFallback == "Interface\\Icons\\inv_10_enchanting_crystal_color2",
    "default rune fallback icon should match the current Midnight augment rune")

local ownedFlasks = check.GetOwnedItemsForButton("flask")

assert(#ownedFlasks == 2, "fleeting flasks should be included in the checker's owned flask list")
assert(ownedFlasks[1].itemID == 245930,
    "owned flask list should use macro variant priority before alphabetical name order")

local selected = check.ResolveSelectedOwnedItem("flask", ownedFlasks)
assert(selected and selected.itemID == 245930,
    "a saved lower-quality preferred flask should resolve to the best owned sibling")

settings.consumablePreferredFlask = nil
selected = check.ResolveSelectedOwnedItem("flask", ownedFlasks)
assert(selected and selected.itemID == 245930,
    "default flask selection should prefer the highest-priority owned variant")

local ownedRunes = check.GetOwnedItemsForButton("rune")
assert(#ownedRunes == 2, "owned rune list should include current and legacy augment runes")
assert(ownedRunes[1].itemID == 259085,
    "owned rune list should preserve explicit current-before-legacy priority before alphabetical name order")

local selectedRune = check.ResolveSelectedOwnedItem("rune", ownedRunes)
assert(selectedRune and selectedRune.itemID == 259085,
    "a saved legacy preferred rune should resolve to the current owned rune")

itemCounts[259085] = 0
ownedRunes = check.GetOwnedItemsForButton("rune")
selectedRune = check.ResolveSelectedOwnedItem("rune", ownedRunes)
assert(selectedRune and selectedRune.itemID == 243191,
    "legacy augment rune should remain the fallback when no current rune is owned")

print("OK: consumablecheck_macro_priority_test")
