local ADDON_NAME, ns = ...

local AuraDefaults = ns.QUI_GroupFramesAuraDefaults or {}
ns.QUI_GroupFramesAuraDefaults = AuraDefaults

local FALLBACK_ICON = 134400

local SPEC_AURA_PRESETS = {
    {
        name = "Restoration Druid",
        specID = 105,
        classFile = "DRUID",
        source = ns.L["Spec Defaults"],
        spells = {
            { id = 774, name = "Rejuvenation", icon = 136081 },
            { id = 8936, name = "Regrowth", icon = 136085 },
            { id = 33763, name = "Lifebloom", icon = 134206 },
            { id = 155777, name = "Germination", icon = 1033478 },
            { id = 48438, name = "Wild Growth", icon = 236153 },
            { id = 474754, name = "Symbiotic Relationship", icon = 1408837 },
            { id = 439530, name = "Symbiotic Blooms", icon = 463540 },
            { id = 102342, name = "Ironbark", icon = 572025, secret = true },
        },
    },
    {
        name = "Restoration Shaman",
        specID = 264,
        classFile = "SHAMAN",
        source = ns.L["Spec Defaults"],
        spells = {
            { id = 61295, name = "Riptide", icon = 252995 },
            { id = 383648, name = "Earth Shield", icon = 136089 },
            { id = 974, name = "Earth Shield", icon = 136089 },
            { id = 207400, name = "Ancestral Vigor", icon = 237574 },
            { id = 382024, name = "Earthliving Weapon", icon = 237578 },
            { id = 444490, name = "Hydrobubble", icon = 1320371 },
        },
    },
    {
        name = "Holy Paladin",
        specID = 65,
        classFile = "PALADIN",
        source = ns.L["Spec Defaults"],
        spells = {
            { id = 156910, name = "Beacon of Faith", icon = 1030095 },
            { id = 156322, name = "Eternal Flame", icon = 135433 },
            { id = 53563, name = "Beacon of Light", icon = 236247 },
            { id = 1244893, name = "Beacon of the Savior", icon = 7514188 },
            { id = 200025, name = "Beacon of Virtue", icon = 1030094 },
            { id = 1022, name = "Blessing of Protection", icon = 135964, secret = true },
            { id = 432502, name = "Holy Armaments", icon = 5927636, secret = true },
            { id = 6940, name = "Blessing of Sacrifice", icon = 135966, secret = true },
            { id = 1044, name = "Blessing of Freedom", icon = 135968, secret = true },
            { id = 431381, name = "Dawnlight", icon = 5927633, secret = true },
        },
    },
    {
        name = "Discipline Priest",
        specID = 256,
        classFile = "PRIEST",
        source = ns.L["Spec Defaults"],
        spells = {
            { id = 17, name = "Power Word: Shield", icon = 135940 },
            { id = 194384, name = "Atonement", icon = 458720 },
            { id = 1253593, name = "Void Shield", icon = 7514191 },
            { id = 41635, name = "Prayer of Mending", icon = 135944 },
            { id = 33206, name = "Pain Suppression", icon = 135936, secret = true },
            { id = 10060, name = "Power Infusion", icon = 135939, secret = true },
        },
    },
    {
        name = "Holy Priest",
        specID = 257,
        classFile = "PRIEST",
        source = ns.L["Spec Defaults"],
        spells = {
            { id = 139, name = "Renew", icon = 135953 },
            { id = 77489, name = "Echo of Light", icon = 237537 },
            { id = 41635, name = "Prayer of Mending", icon = 135944 },
            { id = 47788, name = "Guardian Spirit", icon = 237542, secret = true },
            { id = 10060, name = "Power Infusion", icon = 135939, secret = true },
        },
    },
    {
        name = "Mistweaver Monk",
        specID = 270,
        classFile = "MONK",
        source = ns.L["Spec Defaults"],
        spells = {
            { id = 119611, name = "Renewing Mist", icon = 627487 },
            { id = 124682, name = "Enveloping Mist", icon = 775461 },
            { id = 115175, name = "Soothing Mist", icon = 606550 },
            { id = 450769, name = "Aspect of Harmony", icon = 5927638 },
            { id = 116849, name = "Life Cocoon", icon = 627485, secret = true },
            { id = 443113, name = "Strength of the Black Ox", icon = 615340, secret = true },
        },
    },
    {
        name = "Preservation Evoker",
        specID = 1468,
        classFile = "EVOKER",
        source = ns.L["Spec Defaults"],
        spells = {
            { id = 364343, name = "Echo", icon = 4622456 },
            { id = 366155, name = "Reversion", icon = 4630467 },
            { id = 367364, name = "Echo Reversion", icon = 4630469 },
            { id = 355941, name = "Dream Breath", icon = 4622454 },
            { id = 376788, name = "Echo Dream Breath", icon = 7439198 },
            { id = 363502, name = "Dream Flight", icon = 4622455 },
            { id = 373267, name = "Lifebind", icon = 4630453 },
            { id = 357170, name = "Time Dilation", icon = 4622478, secret = true },
            { id = 363534, name = "Rewind", icon = 4622474, secret = true },
            { id = 409895, name = "Verdant Embrace", icon = 4622471, secret = true },
        },
    },
    {
        name = "Augmentation Evoker",
        specID = 1473,
        classFile = "EVOKER",
        source = ns.L["Spec Defaults"],
        spells = {
            { id = 410089, name = "Prescience", icon = 5199639 },
            { id = 413984, name = "Shifting Sands", icon = 5199633 },
            { id = 360827, name = "Blistering Scales", icon = 5199621 },
            { id = 410263, name = "Inferno's Blessing", icon = 5199632 },
            { id = 410686, name = "Symbiotic Bloom", icon = 4554354 },
            { id = 395152, name = "Ebon Might", icon = 5061347 },
            { id = 369459, name = "Source of Magic", icon = 4630412 },
            { id = 361022, name = "Sense Power", icon = 132160, secret = true },
        },
    },
}

local SPEC_TO_PRESET = {}
for _, preset in ipairs(SPEC_AURA_PRESETS) do
    SPEC_TO_PRESET[preset.specID] = preset
end

local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex and GetSpecializationInfo then
        return GetSpecializationInfo(specIndex)
    end
    return nil
end

local function ResolveSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

local function ResolveSpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and icon then
            return icon
        end
    end
    return nil
end

local function SpellKey(spellID)
    local numeric = tonumber(spellID)
    if numeric then
        return "n:" .. tostring(numeric)
    end
    return "s:" .. tostring(spellID)
end

local function CopySpell(spell, preset, sourceOverride)
    local spellID = spell and (spell.id or spell.spellID)
    if not spellID then
        return nil
    end

    return {
        id = spellID,
        name = spell.name or ResolveSpellName(spellID) or ("Spell " .. tostring(spellID)),
        icon = spell.icon or ResolveSpellIcon(spellID) or FALLBACK_ICON,
        source = sourceOverride or spell.source or preset.source,
        specID = spell.specID or preset.specID,
        classFile = spell.classFile or preset.classFile,
        secret = spell.secret == true,
    }
end

local function AddSuggestion(result, added, assigned, spell, preset, sourceOverride)
    local copied = CopySpell(spell, preset or {}, sourceOverride)
    if not copied then
        return
    end

    local key = SpellKey(copied.id)
    if assigned[key] or added[key] then
        return
    end

    result[#result + 1] = copied
    added[key] = true
end

local function BuildAssignedSet(entries)
    local assigned = {}
    for _, entry in ipairs(entries or {}) do
        local spellID = entry and (entry.spellID or entry.id)
        if spellID then
            assigned[SpellKey(spellID)] = true
        end
    end
    return assigned
end

local function GetCDMAuraEntries()
    local composer = ns.CDMComposer
    if not composer or type(composer.GetAvailableSpellsForContainer) ~= "function" then
        return {}
    end
    return composer.GetAvailableSpellsForContainer("buff", "aura", {}, nil) or {}
end

local function IsKnownCDMSuggestion(entry)
    -- CDM exposes the full Blizzard catalog here; only known entries belong in
    -- this class/spec suggestion strip.
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
    local specID = options.specID or GetPlayerSpecID()
    local cdmEntries = options.cdmAuraEntries
    if cdmEntries == nil then
        cdmEntries = GetCDMAuraEntries()
    end

    local presets = {}
    if specID and SPEC_TO_PRESET[specID] then
        presets[#presets + 1] = SPEC_TO_PRESET[specID]
    end

    local cdmPreset = BuildCDMPreset(cdmEntries)
    if cdmPreset then
        presets[#presets + 1] = cdmPreset
    end

    return DeduplicatePresets(presets)
end

function AuraDefaults.BuildSuggestionList(options)
    options = options or {}
    local entries = options.existingEntries or options.entries or {}
    local assigned = BuildAssignedSet(entries)
    local added = {}
    local suggestions = {}

    local presets = options.staticPresets
    if not presets then
        presets = AuraDefaults.GetDefaultPresets({
            specID = options.specID,
            cdmAuraEntries = options.cdmAuraEntries,
        })
    end

    for _, preset in ipairs(presets or {}) do
        for _, spell in ipairs(preset.spells or {}) do
            AddSuggestion(suggestions, added, assigned, spell, preset)
        end
    end

    for _, spell in ipairs(options.staticEntries or {}) do
        AddSuggestion(suggestions, added, assigned, spell, { source = ns.L["Static"] })
    end

    return suggestions
end

function AuraDefaults.GetSuggestionSpells(existingEntries)
    return AuraDefaults.BuildSuggestionList({
        existingEntries = existingEntries,
    })
end
