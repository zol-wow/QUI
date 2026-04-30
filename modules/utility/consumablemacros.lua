---------------------------------------------------------------------------
-- Consumable Macros
-- Auto-creates and maintains per-character macros for Flasks, Potions,
-- Health Potions, and Weapon Consumables with quality-priority fallback
-- chains. Scans bags for the best available variant and keeps each macro
-- body updated as inventory changes.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local ConsumableMacros = {}
ns.ConsumableMacros = ConsumableMacros

---------------------------------------------------------------------------
-- Item definitions
-- variants are ordered by quality priority: Gold Fleeting > Silver Fleeting
-- > Gold Crafted > Silver Crafted.  Items without fleeting variants list
-- Gold Crafted > Silver Crafted only.
---------------------------------------------------------------------------

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
    -- Oils (applied to main hand via /use 16)
    phoenix_oil = {
        label = "Thalassian Phoenix Oil (Crit + Haste)",
        applyToSlot = 16,  -- INVSLOT_MAINHAND
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
    -- Stones (applied to main hand via /use 16)
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
    -- Ranged ammo (auto-applies, no slot target needed)
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

---------------------------------------------------------------------------
-- Dropdown option arrays (exported for the options panel)
---------------------------------------------------------------------------

ConsumableMacros.FLASK_OPTIONS = {
    { value = "none", text = "None" },
    { value = "blood_knights", text = "Blood Knights (Haste)" },
    { value = "shattered_sun", text = "Shattered Sun (Crit)" },
    { value = "magisters", text = "Magisters (Mastery)" },
    { value = "resistance", text = "Thalassian Resistance (Vers)" },
}

ConsumableMacros.POTION_OPTIONS = {
    { value = "none", text = "None" },
    { value = "recklessness", text = "Recklessness (Secondary)" },
    { value = "rampant_abandon", text = "Rampant Abandon (Primary)" },
    { value = "lights_potential", text = "Light's Potential (Primary, safe)" },
    { value = "zealotry", text = "Zealotry (Single-target)" },
    { value = "mana", text = "Mana Potion" },
}

ConsumableMacros.HEALTH_OPTIONS = {
    { value = "none", text = "None" },
    { value = "silvermoon", text = "Silvermoon Health Potion" },
}

ConsumableMacros.HEALTHSTONE_OPTIONS = {
    { value = "none", text = "None" },
    { value = "healthstone", text = "Healthstone" },
}

ConsumableMacros.AUGMENT_OPTIONS = {
    { value = "none", text = "None" },
    { value = "void_touched", text = "Void-Touched Augment Rune" },
}

ConsumableMacros.VANTUS_OPTIONS = {
    { value = "none", text = "None" },
    { value = "radiant", text = "Vantus Rune: Radiant (Vers)" },
}

ConsumableMacros.WEAPON_OPTIONS = {
    { value = "none", text = "None" },
    { value = "phoenix_oil", text = "Phoenix Oil (Crit + Haste)" },
    { value = "oil_of_dawn", text = "Oil of Dawn (Absorb Shield)" },
    { value = "smugglers_edge", text = "Smuggler's Edge (Arcane Damage)" },
    { value = "whetstone", text = "Whetstone (AP, bladed)" },
    { value = "weightstone", text = "Weightstone (AP, blunt)" },
    { value = "hawkeye", text = "Hawkeye (Crit, ranged)" },
    { value = "lynxeye", text = "Lynxeye (Mastery, ranged)" },
    { value = "zoomshots", text = "Laced Zoomshots (Nature DoT, ranged)" },
    { value = "boomshots", text = "Weighted Boomshots (AoE Fire, ranged)" },
}

---------------------------------------------------------------------------
-- Macro definitions: { dbKey, macroName, defsTable, displayLabel }
---------------------------------------------------------------------------

local MACRO_SLOTS = {
    { dbKey = "selectedFlask",   macroName = "QUI_Flask",  defs = FLASK_DEFS,  label = "Flask" },
    { dbKey = "selectedPotion",  macroName = "QUI_Pot",    defs = POTION_DEFS, label = "Potion" },
    { dbKey = "selectedHealth",       macroName = "QUI_Health", defs = HEALTH_DEFS,       label = "Health Potion" },
    { dbKey = "selectedHealthstone", macroName = "QUI_Stone",  defs = HEALTHSTONE_DEFS, label = "Healthstone" },
    { dbKey = "selectedAugment",     macroName = "QUI_Rune",   defs = AUGMENT_DEFS,     label = "Augment Rune" },
    { dbKey = "selectedVantus",      macroName = "QUI_Vantus", defs = VANTUS_DEFS,      label = "Vantus Rune" },
    { dbKey = "selectedWeapon",      macroName = "QUI_Weapon", defs = WEAPON_DEFS,      label = "Weapon" },
}

---------------------------------------------------------------------------
-- Constants and state
---------------------------------------------------------------------------

local MACRO_ICON = 134400  -- INV_Misc_QuestionMark; #showtooltip overrides display

local pendingUpdate  = false
local debounceTimer  = nil
local initialized    = false

-- Per-slot caches: lastBody[macroName], lastBest[macroName]
local lastBody = {}
local lastBest = {}

---------------------------------------------------------------------------
-- Database access
---------------------------------------------------------------------------

local GetDB = Helpers.GetConsumableMacrosDB

---------------------------------------------------------------------------
-- Core logic
---------------------------------------------------------------------------

--- Build a macro body string from the selected type's variants.
-- Returns bodyString, bestItemID (first owned variant or nil).
-- If the def has applyToSlot, appends "/use <slot>" to auto-apply to
-- the equipment slot (e.g., 16 = main hand for weapon oils/stones).
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
        end
    end

    -- If nothing owned, still produce a placeholder so the macro exists
    if #lines == 1 then
        lines[#lines + 1] = "/use item:" .. def.variants[1].itemID
    end

    -- Auto-apply to equipment slot (e.g., oils/stones → main hand)
    if def.applyToSlot then
        lines[#lines + 1] = "/use " .. def.applyToSlot
    end

    return table.concat(lines, "\n"), bestID
end

--- Ensure a named per-character macro exists with the given body.
-- Returns true if created or edited, false if unchanged or skipped.
local function EnsureMacro(macroName, body)
    if not body then return false end

    local index = GetMacroIndexByName(macroName)
    if index == 0 then
        -- Macro does not exist — create it
        local numGlobal, numChar = GetNumMacros()
        if numChar >= MAX_CHARACTER_MACROS then
            local msg = "|cffff6666[QUI]|r Could not create macro '" .. macroName
                .. "': per-character macro slots full (" .. numChar .. "/" .. MAX_CHARACTER_MACROS .. ")."
            DEFAULT_CHAT_FRAME:AddMessage(msg)
            return false
        end
        CreateMacro(macroName, MACRO_ICON, body, true)
        return true
    end

    -- Macro exists — update body if changed
    local _, _, existingBody = GetMacroInfo(index)
    if existingBody == body then return false end

    EditMacro(index, nil, nil, body)
    return true
end

--- Print a chat notification when the active item changes.
local function NotifyChange(macroType, newBestID, oldBestID)
    local db = GetDB()
    if not db or not db.chatNotifications then return end
    if not newBestID or newBestID == oldBestID then return end

    local item = Item:CreateFromItemID(newBestID)
    item:ContinueOnItemLoad(function()
        local name = item:GetItemName()
        if name then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff60A5FA[QUI]|r " .. macroType .. " macro updated: |cffffffff" .. name .. "|r"
            )
        end
    end)
end

--- Delete all QUI consumable macros (called when the feature is disabled).
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

--- Main update — rebuild and apply all macros.
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
        if body and body ~= lastBody[slot.macroName] then
            if EnsureMacro(slot.macroName, body) then
                NotifyChange(slot.label, bestID, lastBest[slot.macroName])
            end
            lastBody[slot.macroName] = body
            lastBest[slot.macroName] = bestID
        end
    end
end

--- Public API for the options panel.
function ConsumableMacros:ForceRefresh()
    initialized = true
    -- Reset caches so the next update always writes
    wipe(lastBody)
    wipe(lastBest)

    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    self:UpdateMacros()
end

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local db = GetDB()
    if not db or not db.enabled then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if isLogin or isReload then
            initialized = true
            C_Timer.After(2, function()
                ConsumableMacros:UpdateMacros()
            end)
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
