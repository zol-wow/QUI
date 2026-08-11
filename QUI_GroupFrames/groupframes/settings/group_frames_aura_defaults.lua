local ADDON_NAME, ns = ...

local AuraDefaults = ns.QUI_GroupFramesAuraDefaults or {}
ns.QUI_GroupFramesAuraDefaults = AuraDefaults

function AuraDefaults.DefaultStripBucket(frameType)
    return ns.QUI_GroupFramesAuraModel.DefaultStripBucket(frameType)
end

local function SpellKey(spellID)
    local numeric = tonumber(spellID)
    if numeric then
        return "n:" .. tostring(numeric)
    end
    return "s:" .. tostring(spellID)
end

local function GetCDMAuraEntries()
    local composer = ns.CDMComposer
    if not composer or type(composer.GetAvailableSpellsForContainer) ~= "function" then
        return {}
    end
    return composer.GetAvailableSpellsForContainer("buff", "aura", {}, nil) or {}
end

local function IsKnownCDMSuggestion(entry)
    return entry and entry.isKnown == true
end

local function BuildCDMPreset(entries)
    if type(entries) ~= "table" or #entries == 0 then
        return nil
    end

    local spells = {}
    for _, entry in ipairs(entries) do
        local spellID = entry.spellID or entry.id
        if spellID and IsKnownCDMSuggestion(entry) then
            spells[#spells + 1] = {
                id = spellID,
                name = entry.name,
                icon = entry.icon,
                source = ns.L["Blizzard CDM"],
            }
        end
    end

    if #spells == 0 then
        return nil
    end

    return {
        name = "Blizzard Aura Suggestions",
        source = ns.L["Blizzard CDM"],
        spells = spells,
    }
end

local function DeduplicatePresets(presets)
    local deduped = {}
    local seen = {}
    for _, preset in ipairs(presets or {}) do
        local copy = {
            name = preset.name,
            specID = preset.specID,
            classFile = preset.classFile,
            source = preset.source,
            spells = {},
        }
        for _, spell in ipairs(preset.spells or {}) do
            local spellID = spell.id or spell.spellID
            if spellID then
                local key = SpellKey(spellID)
                if not seen[key] then
                    seen[key] = true
                    copy.spells[#copy.spells + 1] = spell
                end
            end
        end
        if #copy.spells > 0 then
            deduped[#deduped + 1] = copy
        end
    end
    return deduped
end

function AuraDefaults.GetDefaultPresets(options)
    options = options or {}
    local cdmEntries = options.cdmAuraEntries
    if cdmEntries == nil then
        cdmEntries = GetCDMAuraEntries()
    end

    local presets = {}
    local cdmPreset = BuildCDMPreset(cdmEntries)
    if cdmPreset then
        presets[#presets + 1] = cdmPreset
    end

    return DeduplicatePresets(presets)
end
