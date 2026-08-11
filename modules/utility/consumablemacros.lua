local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local ConsumableMacros = {}
ns.ConsumableMacros = ConsumableMacros

local FLASK_DEFS = {
    blood_knights = {
        label = "Flask of the Blood Knights (Haste)",
        variants = {
            { itemID = 245930, tag = "Gold Fleeting" },
            { itemID = 245931, tag = "Silver Fleeting" },
            { itemID = 241324, tag = "Gold Crafted" },
            { itemID = 241325, tag = "Silver Crafted" },
        },
    },
    shattered_sun = {
        label = "Flask of the Shattered Sun (Crit)",
        variants = {
            { itemID = 245928, tag = "Gold Fleeting" },
            { itemID = 245929, tag = "Silver Fleeting" },
            { itemID = 241326, tag = "Gold Crafted" },
            { itemID = 241327, tag = "Silver Crafted" },
        },
    },
    magisters = {
        label = "Flask of the Magisters (Mastery)",
        variants = {
            { itemID = 245932, tag = "Gold Fleeting" },
            { itemID = 245933, tag = "Silver Fleeting" },
            { itemID = 241322, tag = "Gold Crafted" },
            { itemID = 241323, tag = "Silver Crafted" },
        },
    },
    resistance = {
        label = "Flask of Thalassian Resistance (Vers)",
        variants = {
            { itemID = 245926, tag = "Gold Fleeting" },
            { itemID = 245927, tag = "Silver Fleeting" },
            { itemID = 241320, tag = "Gold Crafted" },
            { itemID = 241321, tag = "Silver Crafted" },
        },
    },
}

local POTION_DEFS = {
    recklessness = {
        label = "Potion of Recklessness (Secondary)",
        variants = {
            { itemID = 245902, tag = "Gold Fleeting" },
            { itemID = 245903, tag = "Silver Fleeting" },
            { itemID = 241288, tag = "Gold Crafted" },
            { itemID = 241289, tag = "Silver Crafted" },
        },
    },
    rampant_abandon = {
        label = "Draught of Rampant Abandon (Primary)",
        variants = {
            { itemID = 245910, tag = "Gold Fleeting" },
            { itemID = 245911, tag = "Silver Fleeting" },
            { itemID = 241292, tag = "Gold Crafted" },
            { itemID = 241293, tag = "Silver Crafted" },
        },
    },
    lights_potential = {
        label = "Light's Potential (Primary, safe)",
        variants = {
            { itemID = 245898, tag = "Gold Fleeting" },
            { itemID = 245897, tag = "Silver Fleeting" },
            { itemID = 241308, tag = "Gold Crafted" },
            { itemID = 241309, tag = "Silver Crafted" },
        },
    },
    zealotry = {
        label = "Potion of Zealotry (Single-target)",
        variants = {
            { itemID = 245900, tag = "Gold Fleeting" },
            { itemID = 245901, tag = "Silver Fleeting" },
            { itemID = 241296, tag = "Gold Crafted" },
            { itemID = 241297, tag = "Silver Crafted" },
        },
    },
    mana = {
        label = "Lightfused Mana Potion",
        variants = {
            { itemID = 245916, tag = "Gold Fleeting" },
            { itemID = 245917, tag = "Silver Fleeting" },
            { itemID = 241300, tag = "Gold Crafted" },
            { itemID = 241301, tag = "Silver Crafted" },
        },
    },
}

local HEALTH_DEFS = {
    silvermoon = {
        label = "Silvermoon Health Potion",
        variants = {
            { itemID = 241304, tag = "Gold Crafted" },
            { itemID = 241305, tag = "Silver Crafted" },
        },
    },
}

local HEALTHSTONE_DEFS = {
    healthstone = {
        label = "Healthstone",
        variants = {
            { itemID = 5512, tag = "Healthstone" },
        },
    },
}

local AUGMENT_DEFS = {
    void_touched = {
        label = "Void-Touched Augment Rune (+25 Primary)",
        variants = {
            { itemID = 259085, tag = "Augment Rune" },
        },
    },
}

local VANTUS_DEFS = {
    radiant = {
        label = "Vantus Rune: Radiant (Vers, weekly)",
        variants = {
            { itemID = 245880, tag = "Gold Crafted" },
            { itemID = 245879, tag = "Silver Crafted" },
        },
    },
}

local WEAPON_DEFS = {
    phoenix_oil = {
        label = "Thalassian Phoenix Oil (Crit + Haste)",
        applyToSlot = 16,
        variants = {
            { itemID = 243734, tag = "Gold Crafted" },
            { itemID = 243733, tag = "Silver Crafted" },
        },
    },
    oil_of_dawn = {
        label = "Oil of Dawn (Absorb Shield)",
        applyToSlot = 16,
        variants = {
            { itemID = 243736, tag = "Gold Crafted" },
            { itemID = 243735, tag = "Silver Crafted" },
        },
    },
    smugglers_edge = {
        label = "Smuggler's Enchanted Edge (Arcane Damage)",
        applyToSlot = 16,
        variants = {
            { itemID = 243738, tag = "Gold Crafted" },
            { itemID = 243737, tag = "Silver Crafted" },
        },
    },
    whetstone = {
        label = "Refulgent Whetstone (AP, bladed weapons)",
        applyToSlot = 16,
        variants = {
            { itemID = 237371, tag = "Gold Crafted" },
            { itemID = 237370, tag = "Silver Crafted" },
        },
    },
    weightstone = {
        label = "Refulgent Weightstone (AP, blunt weapons)",
        applyToSlot = 16,
        variants = {
            { itemID = 237369, tag = "Gold Crafted" },
            { itemID = 237367, tag = "Silver Crafted" },
        },
    },
    hawkeye = {
        label = "Farstrider's Hawkeye (Crit)",
        variants = {
            { itemID = 257746, tag = "Gold" },
            { itemID = 257745, tag = "Silver" },
        },
    },
    lynxeye = {
        label = "Smuggler's Lynxeye (Mastery)",
        variants = {
            { itemID = 257748, tag = "Gold" },
            { itemID = 257747, tag = "Silver" },
        },
    },
    zoomshots = {
        label = "Laced Zoomshots (Nature DoT)",
        variants = {
            { itemID = 257750, tag = "Gold" },
            { itemID = 257749, tag = "Silver" },
        },
    },
    boomshots = {
        label = "Weighted Boomshots (AoE Fire)",
        variants = {
            { itemID = 257752, tag = "Gold" },
            { itemID = 257751, tag = "Silver" },
        },
    },
}

local CONSUMABLE_DEF_TABLES = {
    FLASK_DEFS,
    POTION_DEFS,
    HEALTH_DEFS,
    HEALTHSTONE_DEFS,
    AUGMENT_DEFS,
    VANTUS_DEFS,
    WEAPON_DEFS,
}

local itemVariantOrders

local function BuildItemVariantOrders()
    local byItem = {}
    for _, defs in ipairs(CONSUMABLE_DEF_TABLES) do
        for _, def in pairs(defs) do
            local variants = def.variants
            if type(variants) == "table" and #variants > 1 then
                local orderedIDs = {}
                for _, variant in ipairs(variants) do
                    if type(variant.itemID) == "number" then
                        orderedIDs[#orderedIDs + 1] = variant.itemID
                    end
                end
                if #orderedIDs > 1 then
                    for _, itemID in ipairs(orderedIDs) do
                        byItem[itemID] = orderedIDs
                    end
                end
            end
        end
    end
    return byItem
end

function ConsumableMacros.GetVariantOrderForItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if not itemVariantOrders then
        itemVariantOrders = BuildItemVariantOrders()
    end
    return itemVariantOrders[itemID]
end

ConsumableMacros.FLASK_OPTIONS = {
    { value = "none", text = ns.L["None"] },
    { value = "blood_knights", text = ns.L["Blood Knights (Haste)"] },
    { value = "shattered_sun", text = ns.L["Shattered Sun (Crit)"] },
    { value = "magisters", text = ns.L["Magisters (Mastery)"] },
    { value = "resistance", text = ns.L["Thalassian Resistance (Vers)"] },
}

ConsumableMacros.POTION_OPTIONS = {
    { value = "none", text = ns.L["None"] },
    { value = "recklessness", text = ns.L["Recklessness (Secondary)"] },
    { value = "rampant_abandon", text = ns.L["Rampant Abandon (Primary)"] },
    { value = "lights_potential", text = ns.L["Light's Potential (Primary, safe)"] },
    { value = "zealotry", text = ns.L["Zealotry (Single-target)"] },
    { value = "mana", text = ns.L["Mana Potion"] },
}

ConsumableMacros.HEALTH_OPTIONS = {
    { value = "none", text = ns.L["None"] },
    { value = "silvermoon", text = ns.L["Silvermoon Health Potion"] },
}

ConsumableMacros.HEALTHSTONE_OPTIONS = {
    { value = "none", text = ns.L["None"] },
    { value = "healthstone", text = ns.L["Healthstone"] },
}

ConsumableMacros.AUGMENT_OPTIONS = {
    { value = "none", text = ns.L["None"] },
    { value = "void_touched", text = ns.L["Void-Touched Augment Rune"] },
}

ConsumableMacros.VANTUS_OPTIONS = {
    { value = "none", text = ns.L["None"] },
    { value = "radiant", text = ns.L["Vantus Rune: Radiant (Vers)"] },
}

ConsumableMacros.WEAPON_OPTIONS = {
    { value = "none", text = ns.L["None"] },
    { value = "phoenix_oil", text = ns.L["Phoenix Oil (Crit + Haste)"] },
    { value = "oil_of_dawn", text = ns.L["Oil of Dawn (Absorb Shield)"] },
    { value = "smugglers_edge", text = ns.L["Smuggler's Edge (Arcane Damage)"] },
    { value = "whetstone", text = ns.L["Whetstone (AP, bladed)"] },
    { value = "weightstone", text = ns.L["Weightstone (AP, blunt)"] },
    { value = "hawkeye", text = ns.L["Hawkeye (Crit, ranged)"] },
    { value = "lynxeye", text = ns.L["Lynxeye (Mastery, ranged)"] },
    { value = "zoomshots", text = ns.L["Laced Zoomshots (Nature DoT, ranged)"] },
    { value = "boomshots", text = ns.L["Weighted Boomshots (AoE Fire, ranged)"] },
}

local MACRO_SLOTS = {
    { dbKey = "selectedFlask",   macroName = "Flask_DUI",  defs = FLASK_DEFS,  label = "Flask" },
    { dbKey = "selectedPotion",  macroName = "Pot_DUI",    defs = POTION_DEFS, label = "Potion" },
    { dbKey = "selectedHealth",       macroName = "Health_DUI", defs = HEALTH_DEFS,       label = "Health Potion" },
    { dbKey = "selectedHealthstone", macroName = "Stone_DUI",  defs = HEALTHSTONE_DEFS, label = "Healthstone" },
    { dbKey = "selectedAugment",     macroName = "Rune_DUI",   defs = AUGMENT_DEFS,     label = "Augment Rune" },
    { dbKey = "selectedVantus",      macroName = "Vantus_DUI", defs = VANTUS_DEFS,      label = "Vantus Rune" },
    { dbKey = "selectedWeapon",      macroName = "Weapon_DUI", defs = WEAPON_DEFS,      label = "Weapon" },
}

local MACRO_ICON = 134400

local MAX_CHARACTER_MACROS_FALLBACK = 30

local function GetCharacterMacroCap()
    local consts = Constants and Constants.MacroConsts
    local cap = consts and consts.MAX_CHARACTER_MACROS
    if type(cap) ~= "number" then return MAX_CHARACTER_MACROS_FALLBACK end
    return cap
end

local pendingUpdate  = false
local debounceTimer  = nil
local initialized    = false

local lastBody = {}
local lastBest = {}

local GetDB = Helpers.GetConsumableMacrosDB

local DEFS_BY_DBKEY = {}
for _, slot in ipairs(MACRO_SLOTS) do
    DEFS_BY_DBKEY[slot.dbKey] = slot.defs
end

function ConsumableMacros.GetSelectedItem(dbKey)
    local db = GetDB and GetDB()
    if not db then return nil end
    local key = db[dbKey]
    if not key or key == "none" then return nil end
    local defs = DEFS_BY_DBKEY[dbKey]
    local def = defs and defs[key]
    local variant = def and def.variants and def.variants[1]
    if not variant or type(variant.itemID) ~= "number" then return nil end
    return { itemID = variant.itemID, label = def.label }
end

local function BuildMacroBody(typeKey, defs)
    if not typeKey or typeKey == "none" then return nil, nil end
    local def = defs[typeKey]
    if not def then return nil, nil end

    local lines = { "#showtooltip" }
    local bestID = nil
    for _, v in ipairs(def.variants) do
        local count = C_Item.GetItemCount(v.itemID, false, false)
        if count and count > 0 then
            if not bestID then bestID = v.itemID end
            lines[#lines + 1] = "/use item:" .. v.itemID
            if def.applyToSlot then break end
        end
    end

    if #lines == 1 then
        lines[#lines + 1] = "/use item:" .. def.variants[1].itemID
    end

    if def.applyToSlot then
        lines[#lines + 1] = "/use " .. def.applyToSlot
    end

    return table.concat(lines, "\n"), bestID
end

local function EnsureMacro(macroName, body)
    if not body then return false end

    local index = GetMacroIndexByName(macroName)
    if index == 0 then
        local numGlobal, numChar = GetNumMacros()
        local cap = GetCharacterMacroCap()
        numChar = numChar or 0
        if numChar >= cap then
            local msg = ns.L["|cffff6666[QUI]|r Could not create macro '"] .. macroName
                .. ns.L["': per-character macro slots full ("] .. numChar .. "/" .. cap .. ")."
            DEFAULT_CHAT_FRAME:AddMessage(msg)
            return false
        end
        CreateMacro(macroName, MACRO_ICON, body, true)
        return true
    end

    local _, _, existingBody = GetMacroInfo(index)
    if existingBody == body then return false end

    EditMacro(index, nil, nil, body)
    return true
end

local function NotifyChange(macroType, newBestID, oldBestID)
    local db = GetDB()
    if not db or not db.chatNotifications then return end
    if not newBestID or newBestID == oldBestID then return end

    local item = Item:CreateFromItemID(newBestID)
    item:ContinueOnItemLoad(function()
        local name = item:GetItemName()
        if name then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff60A5FA[QUI]|r " .. macroType .. ns.L[" macro updated: |cffffffff"] .. name .. "|r"
            )
        end
    end)
end

function ConsumableMacros:DeleteMacros()
    if InCombatLockdown() then return end
    for _, slot in ipairs(MACRO_SLOTS) do
        local index = GetMacroIndexByName(slot.macroName)
        if index and index > 0 then
            DeleteMacro(index)
        end
    end
    wipe(lastBody)
    wipe(lastBest)
end

function ConsumableMacros:UpdateMacros()
    if not initialized then return end
    local db = GetDB()
    if not db or not db.enabled then return end

    if InCombatLockdown() then
        pendingUpdate = true
        return
    end

    for _, slot in ipairs(MACRO_SLOTS) do
        local body, bestID = BuildMacroBody(db[slot.dbKey], slot.defs)
        if body then
            if body ~= lastBody[slot.macroName] then
                if EnsureMacro(slot.macroName, body) then
                    NotifyChange(slot.label, bestID, lastBest[slot.macroName])
                end
                lastBody[slot.macroName] = body
                lastBest[slot.macroName] = bestID
            end
        else
            local index = GetMacroIndexByName(slot.macroName)
            if index and index > 0 then
                DeleteMacro(index)
            end
            lastBody[slot.macroName] = nil
            lastBest[slot.macroName] = nil
        end
    end
end

function ConsumableMacros:ForceRefresh()
    initialized = true
    wipe(lastBody)
    wipe(lastBest)

    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    self:UpdateMacros()
end

local function RunLoginInit()
    initialized = true
    C_Timer.After(2, function()
        ConsumableMacros:UpdateMacros()
    end)
end

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local db = GetDB()
    if not db or not db.enabled then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if isLogin or isReload then
            RunLoginInit()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if InCombatLockdown() then
            pendingUpdate = true
            return
        end
        if debounceTimer then debounceTimer:Cancel() end
        debounceTimer = C_Timer.NewTimer(0.5, function()
            debounceTimer = nil
            ConsumableMacros:UpdateMacros()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingUpdate then
            pendingUpdate = false
            ConsumableMacros:UpdateMacros()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if debounceTimer then
            debounceTimer:Cancel()
            debounceTimer = nil
        end
    end
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        local db = GetDB()
        if not db or not db.enabled then return end
        RunLoginInit()
    end)
end
