-- QUI_GroupFrames/groupframes/groupframes_aura_model.lua
local ADDON_NAME, ns = ...
local Model = ns.QUI_GroupFramesAuraModel or {}
ns.QUI_GroupFramesAuraModel = Model

local idCounter = 0
local function nextId()
    idCounter = idCounter + 1
    return "e" .. tostring(idCounter)
end

local function deepCopyTable(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = deepCopyTable(val) end
    return t
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

-- The shipped default filter strips (debuffs + buffs) for the all-specs ("*")
-- bucket. Single source of truth now that the strips are SEEDED ONCE per
-- profile context (see Model.EnsureSeeded) instead of living in defaults.lua as
-- an AceDB array default — that default's copyDefaults pass re-filled deleted
-- array indices on every reload, so deleting a strip never stuck. Fixed string
-- ids ("debuffs"/"buffs") match the historical shipped values. Returns a fresh
-- table each call (safe to write straight into a profile bucket).
function Model.DefaultStripBucket()
    return {
        {
            id = "debuffs", enabled = true, mode = "filterStrip", auraType = "HARMFUL",
            anchor = "BOTTOMRIGHT", growDirection = "LEFT", spacing = 2,
            offsetX = -2, offsetY = -18, iconSize = 16, maxIcons = 3,
            hideSwipe = false, reverseSwipe = false,
            showDurationText = true, durationFontSize = 9,
            durationAnchor = "BOTTOM", durationOffsetX = 0, durationOffsetY = -6,
            durationColor = { 1, 1, 1, 1 }, durationUseTimeColor = true,
            showDurationColor = true, showExpiringPulse = true,
            filterMode = "off",
            classifications = { raid = true, raidInCombat = false, crowdControl = true, important = true },
            whitelist = {}, blacklist = {},
        },
        {
            id = "buffs", enabled = false, mode = "filterStrip", auraType = "HELPFUL",
            anchor = "TOPLEFT", growDirection = "RIGHT", spacing = 2,
            offsetX = 2, offsetY = 16, iconSize = 14, maxIcons = 0,
            hideSwipe = false, reverseSwipe = false,
            showDurationText = true, durationFontSize = 9,
            durationAnchor = "BOTTOM", durationOffsetX = 0, durationOffsetY = -6,
            durationColor = { 1, 1, 1, 1 }, durationUseTimeColor = true,
            showDurationColor = true, showExpiringPulse = true,
            filterMode = "off", onlyMine = false, hidePermanent = false, dedupeDefensives = true,
            classifications = { raid = false, raidInCombat = false, cancelable = false, notCancelable = false, important = false, bigDefensive = false, externalDefensive = false },
            whitelist = {}, blacklist = {},
        },
    }
end

function Model.DefaultElements()
    return { ["*"] = Model.DefaultStripBucket() }
end

-- Seed the shared "*" bucket with the shipped strips exactly ONCE per profile
-- context (party / raid each get their own seed into their own store). Guarded
-- by auras.elementsSeeded so deleting every strip does NOT re-seed on reload —
-- that flag, not the presence of the bucket, is the "already seeded" signal, so
-- an emptied bucket stays empty. Cheap (boolean check) + idempotent; safe to
-- call from the render path and the editor. Per-spec buckets (elements[specID])
-- are never seeded — they are purely user-additive.
function Model.EnsureSeeded(auras)
    if type(auras) ~= "table" then return end

    -- One-time transition cleanup (own flag, so it runs even on profiles already
    -- seeded by the earlier fix): drop EMPTY spec buckets left by the old
    -- auto-create-on-view. Under override semantics an empty spec bucket would
    -- wrongly suppress All Specs to "nothing"; a real empty override is only ever
    -- created via the toggle going forward.
    if not auras._specBucketsNormalized and type(auras.elements) == "table" then
        auras._specBucketsNormalized = true
        local drop = {}
        for key, bucket in pairs(auras.elements) do
            if key ~= "*" and type(bucket) == "table" and #bucket == 0 then
                drop[#drop + 1] = key
            end
        end
        for _, key in ipairs(drop) do
            auras.elements[key] = nil
        end
    end

    if auras.elementsSeeded then return end
    auras.elementsSeeded = true
    auras.elements = auras.elements or {}
    if auras.elements["*"] == nil then
        auras.elements["*"] = Model.DefaultStripBucket()
    end
end

-- OVERRIDE (either/or) semantics: a present spec bucket REPLACES the All Specs
-- ("*") bucket entirely for that spec — never a union. Absent spec bucket →
-- inherit "*". An empty spec bucket is a valid intentional "show nothing".
-- Spec-bucket presence is controlled by the editor's per-spec override toggle
-- (Model.EnableSpecOverride / DisableSpecOverride), not by merely viewing a spec.
-- `out` (optional): a caller-supplied array to fill instead of allocating a
-- fresh table -- the per-frame render path passes a reusable scratch to stay
-- zero-alloc in the combat fan-out. Cleared here so callers needn't pre-wipe.
function Model.ActiveElementsForSpec(auras, specID, out)
    if out then
        for i = #out, 1, -1 do out[i] = nil end
    else
        out = {}
    end
    local elements = auras and auras.elements
    if not elements then return out end
    local bucket
    if specID ~= nil and elements[specID] ~= nil then
        bucket = elements[specID]
    else
        bucket = elements["*"]
    end
    if bucket then
        for _, e in ipairs(bucket) do
            if e.enabled ~= false then out[#out + 1] = e end
        end
    end
    return out
end

-- A spec override is active iff a non-"*" bucket exists for that key.
function Model.HasSpecOverride(elements, bucketKey)
    return bucketKey ~= nil and bucketKey ~= "*"
        and type(elements) == "table" and elements[bucketKey] ~= nil
end

-- Enable override for a spec: seed its bucket as an independent DeepCopy of the
-- current "*" bucket (fresh element ids) so nothing visibly changes until the
-- user edits it. No-op if already overriding or if bucketKey is "*"/nil.
function Model.EnableSpecOverride(auras, bucketKey)
    if type(auras) ~= "table" or bucketKey == nil or bucketKey == "*" then return end
    auras.elements = auras.elements or {}
    if auras.elements[bucketKey] ~= nil then return end
    local src = auras.elements["*"] or {}
    local copy = {}
    for _, e in ipairs(src) do
        local c = deepCopyTable(e)
        c.id = nextId()
        copy[#copy + 1] = c
    end
    auras.elements[bucketKey] = copy
end

-- Disable override for a spec: delete its bucket so it inherits "*" again.
function Model.DisableSpecOverride(auras, bucketKey)
    if type(auras) ~= "table" or bucketKey == nil or bucketKey == "*" then return end
    if type(auras.elements) == "table" then
        auras.elements[bucketKey] = nil
    end
end

-- `out` (optional): reusable `{ [spellID] = auraData }` map to fill instead of
-- allocating, for the zero-alloc render path. Cleared here.
function Model.PopulateElementMatches(element, cache, out)
    local matches = out or {}
    if out then
        for k in pairs(matches) do matches[k] = nil end
    end
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
