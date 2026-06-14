-- QUI_GroupFrames/groupframes/groupframes_aura_model.lua
local ADDON_NAME, ns = ...
local Model = ns.QUI_GroupFramesAuraModel or {}
ns.QUI_GroupFramesAuraModel = Model

local idCounter = 0
local function nextId()
    idCounter = idCounter + 1
    return "e" .. tostring(idCounter)
end

local DISPLAY_TYPES = { icon = true, square = true, bar = true, healthTint = true }

local function defaultClassifications(auraType)
    if auraType == "HARMFUL" then
        return { raid = true, raidInCombat = false, crowdControl = true, important = true }
    end
    return { raid = false, raidInCombat = false, cancelable = false, notCancelable = false,
             important = false, bigDefensive = false, externalDefensive = false }
end

function Model.NewFilterStripElement(auraType)
    return {
        id = nextId(), enabled = true, mode = "filterStrip",
        auraType = auraType or "HELPFUL",
        anchor = (auraType == "HARMFUL") and "BOTTOMRIGHT" or "TOPLEFT",
        offsetX = 0, offsetY = 0,
        growDirection = (auraType == "HARMFUL") and "LEFT" or "RIGHT",
        spacing = 2, iconSize = 14, maxIcons = 3,
        hideSwipe = false, reverseSwipe = false,
        showDurationText = true, durationFontSize = 9,
        showDurationColor = true, showExpiringPulse = true,
        filterMode = "off", onlyMine = false, hidePermanent = false, dedupeDefensives = true,
        classifications = defaultClassifications(auraType),
        whitelist = {}, blacklist = {},
    }
end

function Model.NewTrackedElement(spells, displayType)
    return {
        id = nextId(), enabled = true, mode = "tracked",
        spells = spells or {}, onlyMine = false, onlyMineSpells = {},
        displayType = displayType or "icon",
        anchor = "TOPLEFT", offsetX = 0, offsetY = 0,
        growDirection = "RIGHT", spacing = 2, iconSize = 16,
        hideSwipe = false, reverseSwipe = false,
        showDurationText = false, durationFontSize = 9,
        color = { 1, 1, 1 },
        -- Seed a visible bar config up front: the bar displayType otherwise
        -- falls back to a ~4px-thin renderer default that's near-invisible the
        -- moment a tracked bar is added.
        bar = { thickness = 12, length = 48 },
    }
end

function Model.Validate(e)
    if type(e) ~= "table" then return false end
    if e.mode == "filterStrip" then
        return e.auraType == "HELPFUL" or e.auraType == "HARMFUL"
    elseif e.mode == "tracked" then
        if not DISPLAY_TYPES[e.displayType] then return false end
        return type(e.spells) == "table" and #e.spells > 0
    end
    return false
end

function Model.EffectiveOnlyMine(e, spellID)
    if e.onlyMineSpells and e.onlyMineSpells[spellID] ~= nil then
        return e.onlyMineSpells[spellID]
    end
    return e.onlyMine == true
end

function Model.DefaultElements()
    local buff = Model.NewFilterStripElement("HELPFUL")
    buff.enabled = false
    buff.maxIcons = 0
    local debuff = Model.NewFilterStripElement("HARMFUL")
    debuff.enabled = true
    debuff.maxIcons = 3
    return { ["*"] = { debuff, buff } }
end

function Model.ActiveElementsForSpec(auras, specID)
    local out = {}
    local function add(bucket)
        if not bucket then return end
        for _, e in ipairs(bucket) do if e.enabled ~= false then out[#out + 1] = e end end
    end
    local elements = auras and auras.elements
    if elements then
        add(elements["*"])
        if specID then add(elements[specID]) end
    end
    return out
end

function Model.PopulateElementMatches(element, cache)
    local matches = {}
    if element.mode == "tracked" and cache then
        for _, sid in ipairs(element.spells or {}) do
            local data = (cache.buffsBySpellID and cache.buffsBySpellID[sid])
                      or (cache.debuffsBySpellID and cache.debuffsBySpellID[sid])
            if data then matches[sid] = data end
        end
    end
    return matches
end

return Model
