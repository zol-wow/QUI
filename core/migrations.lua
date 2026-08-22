local ADDON_NAME, ns = ...

local Migrations = ns.Migrations or {}
ns.Migrations = Migrations
if _G.QUI then _G.QUI.Migrations = Migrations end

local _currentGlobalDB     = nil
local _currentProfileKey   = nil

local CURRENT_SCHEMA_VERSION = 62

local MIN_SUPPORTED_SCHEMA = 47

Migrations.CURRENT_SCHEMA_VERSION = CURRENT_SCHEMA_VERSION
Migrations.MIN_SUPPORTED_SCHEMA = MIN_SUPPORTED_SCHEMA

local function CloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nestedValue in pairs(value) do
        copy[key] = CloneValue(nestedValue)
    end
    return copy
end

local SPEC_ID_CLASS_TOKEN = {
    [62] = "MAGE", [63] = "MAGE", [64] = "MAGE",
    [65] = "PALADIN", [66] = "PALADIN", [70] = "PALADIN",
    [71] = "WARRIOR", [72] = "WARRIOR", [73] = "WARRIOR",
    [102] = "DRUID", [103] = "DRUID", [104] = "DRUID", [105] = "DRUID",
    [250] = "DEATHKNIGHT", [251] = "DEATHKNIGHT", [252] = "DEATHKNIGHT",
    [253] = "HUNTER", [254] = "HUNTER", [255] = "HUNTER",
    [256] = "PRIEST", [257] = "PRIEST", [258] = "PRIEST",
    [259] = "ROGUE", [260] = "ROGUE", [261] = "ROGUE",
    [262] = "SHAMAN", [263] = "SHAMAN", [264] = "SHAMAN",
    [265] = "WARLOCK", [266] = "WARLOCK", [267] = "WARLOCK",
    [268] = "MONK", [269] = "MONK", [270] = "MONK",
    [577] = "DEMONHUNTER", [581] = "DEMONHUNTER",
    [1467] = "EVOKER", [1468] = "EVOKER", [1473] = "EVOKER",
}

local function ParseSpecKey(value)
    if type(value) == "number" then
        return value, nil
    end
    if type(value) ~= "string" then
        return nil, nil
    end

    local classToken, specText = value:match("^([A-Z]+)%-(%d+)$")
    if specText then
        return tonumber(specText), classToken
    end
    local numeric = tonumber(value)
    if numeric then
        return numeric, nil
    end
    return nil, nil
end

local function GetClassTokenForSpecID(specID)
    if type(specID) ~= "number" then return nil end
    if GetSpecializationInfoByID then
        local result = { pcall(GetSpecializationInfoByID, specID) }
        local classToken = result[7]
        if result[1] and type(classToken) == "string" and classToken ~= "" then
            return classToken
        end
    end
    return SPEC_ID_CLASS_TOKEN[specID]
end

local function GetCanonicalSpecKey(value)
    local specID, classToken = ParseSpecKey(value)
    if not specID then
        return value, nil
    end
    classToken = classToken or GetClassTokenForSpecID(specID)
    if classToken then
        return classToken .. "-" .. tostring(specID), specID
    end
    return tostring(specID), specID
end

local function GetLiveSpecID()
    if not GetSpecialization or not GetSpecializationInfo then return nil end
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return type(specID) == "number" and specID or nil
end

local function GetProfileSourceSpecID(profile)
    local fromProfile = profile and profile.ncdm and profile.ncdm._lastSpecID
    if type(fromProfile) == "number" and fromProfile > 0 then
        return fromProfile
    end
    return GetLiveSpecID()
end

local function RecordSpecKeyAlias(container, fromKey, toKey)
    if type(container) ~= "table" or fromKey == nil or toKey == nil or fromKey == toKey then return end
    if type(container._legacySpecKeyAliases) ~= "table" then
        container._legacySpecKeyAliases = {}
    end
    container._legacySpecKeyAliases[tostring(fromKey)] = tostring(toKey)
end

local function StampLegacySpecEntry(entry, sourceSpecID, sourceSpecKey, opts)
    if type(entry) ~= "table" then return entry end
    if type(sourceSpecID) == "number" and sourceSpecID > 0 and entry._sourceSpecID == nil then
        entry._sourceSpecID = sourceSpecID
    end
    if sourceSpecKey ~= nil and entry._legacySourceSpecKey == nil then
        entry._legacySourceSpecKey = tostring(sourceSpecKey)
    end
    if opts and opts.legacySpellbookSlot
       and entry.type == "spell"
       and type(entry.id) == "number"
       and entry._legacySpellbookSlot == nil
    then
        entry._legacySpellbookSlot = entry.id
    end
    return entry
end

local function EntriesEquivalent(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.type == b.type
       and a.id == b.id
       and a.macroName == b.macroName
       and a.customName == b.customName
end

local function DeduplicateEntryList(entries)
    if type(entries) ~= "table" then return false end
    local seen = {}
    local kept = {}
    local changed = false
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local key = tostring(entry.type or "") .. "\031"
                .. tostring(entry.id or "") .. "\031"
                .. tostring(entry.macroName or "") .. "\031"
                .. tostring(entry.customName or "")
            if not seen[key] then
                seen[key] = true
                kept[#kept + 1] = entry
            else
                changed = true
            end
        else
            kept[#kept + 1] = entry
        end
    end
    if changed then
        for i = 1, math.max(#entries, #kept) do
            entries[i] = kept[i]
        end
    end
    return changed
end

local function MergeSpecEntryLists(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    local changed = false
    for _, entry in ipairs(src) do
        local exists = false
        for _, existing in ipairs(dst) do
            if EntriesEquivalent(existing, entry) then
                exists = true
                break
            end
        end
        if not exists then
            dst[#dst + 1] = entry
            changed = true
        end
    end
    if DeduplicateEntryList(dst) then
        changed = true
    end
    return changed
end

local PromoteLegacyContainerEntriesToPerSpec

local function IsPlaceholderAnchorEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    local parent = entry.parent
    local point = entry.point
    local relative = entry.relative
    local offsetX = tonumber(entry.offsetX) or 0
    local offsetY = tonumber(entry.offsetY) or 0
    local widthAdjust = tonumber(entry.widthAdjust) or 0
    local heightAdjust = tonumber(entry.heightAdjust) or 0

    if parent ~= nil and parent ~= "screen" then
        return false
    end
    if point ~= nil and point ~= "CENTER" then
        return false
    end
    if relative ~= nil and relative ~= "CENTER" then
        return false
    end
    if offsetX ~= 0 or offsetY ~= 0 or widthAdjust ~= 0 or heightAdjust ~= 0 then
        return false
    end
    if entry.hideWithParent or entry.keepInPlace or entry.autoWidth or entry.autoHeight then
        return false
    end

    for key, value in pairs(entry) do
        if key ~= "parent"
            and key ~= "point"
            and key ~= "relative"
            and key ~= "offsetX"
            and key ~= "offsetY"
            and key ~= "sizeStable"
            and key ~= "sizeStableAnchoring"
            and key ~= "hideWithParent"
            and key ~= "keepInPlace"
            and key ~= "autoWidth"
            and key ~= "autoHeight"
            and key ~= "widthAdjust"
            and key ~= "heightAdjust"
            and key ~= "enabled"
            and value ~= nil
        then
            return false
        end
    end

    return true
end

local function MigLog(fmt, ...)
    if not _G.QUI_MIGRATION_LOG then _G.QUI_MIGRATION_LOG = {} end
    local line
    if select("#", ...) > 0 then
        local ok, msg = ns.SafeCall("report", string.format, fmt, ...)
        line = ok and msg or fmt
    else
        line = fmt
    end
    _G.QUI_MIGRATION_LOG[#_G.QUI_MIGRATION_LOG + 1] = line
end

function Migrations.ResetCastbarPreviewModes(profile)
    if not profile or not profile.quiUnitFrames then
        return
    end

    for _, unitKey in ipairs({ "player", "target", "focus", "pet", "targettarget" }) do
        local unitDB = profile.quiUnitFrames[unitKey]
        if unitDB and unitDB.castbar then
            unitDB.castbar.previewMode = false
        end
    end

    for i = 1, 8 do
        local bossDB = profile.quiUnitFrames["boss" .. i]
        if bossDB and bossDB.castbar then
            bossDB.castbar.previewMode = false
        end
    end
end

function Migrations.RestoreBuffDebuffSplit(profile)
    local bb = profile and profile.buffBorders
    if type(bb) == "table" then
        if bb.debuffIconSize == nil then
            bb.debuffIconSize = bb.buffIconSize or 35
        end
        if bb.debuffIconsPerRow == nil then
            bb.debuffIconsPerRow = bb.buffIconsPerRow or 10
        end
        if bb.debuffIconSpacing == nil then
            bb.debuffIconSpacing = bb.buffIconSpacing or 0
        end
        if bb.debuffGrowLeft == nil then
            if bb.buffGrowLeft ~= nil then
                bb.debuffGrowLeft = bb.buffGrowLeft
            else
                bb.debuffGrowLeft = true
            end
        end
        if bb.debuffGrowUp == nil then
            bb.debuffGrowUp = bb.buffGrowUp or false
        end
        if bb.debuffInvertSwipeDarkening == nil then
            bb.debuffInvertSwipeDarkening = bb.buffInvertSwipeDarkening or false
        end
        if bb.debuffRowSpacing == nil then
            bb.debuffRowSpacing = bb.buffRowSpacing or 0
        end
    end

    if type(profile) ~= "table" then return end
    if type(profile.frameAnchoring) ~= "table" then
        profile.frameAnchoring = {}
    end
    local fa = profile.frameAnchoring
    if fa.debuffFrame == nil then
        fa.debuffFrame = {
            point = "TOPRIGHT",
            parent = "buffFrame",
            relative = "BOTTOMRIGHT",
            offsetX = 0,
            offsetY = -5,
            sizeStable = true,
            autoWidth = false,
            autoHeight = false,
            hideWithParent = false,
            keepInPlace = true,
            widthAdjust = 0,
            heightAdjust = 0,
            growAnchor = "TOPRIGHT",
        }
    end
end

function Migrations.PrunePrivateAuras(profile)
    if type(profile) ~= "table" then return end

    local uf = profile.quiUnitFrames
    if type(uf) == "table" then
        for _, unitKey in ipairs({ "player", "target", "focus" }) do
            local unit = uf[unitKey]
            if type(unit) == "table" then
                unit.privateAuras = nil
            end
        end
    end

    local gf = profile.quiGroupFrames
    if type(gf) == "table" then
        for _, contextMode in ipairs({ "party", "raid" }) do
            local contextDB = gf[contextMode]
            if type(contextDB) == "table" then
                contextDB.privateAuras = nil
            end
        end
    end
end

function Migrations.SeedAuraElements(profile)
    local E = _G.QUI and _G.QUI.AuraElements
    if not E then return false end

    local bb = profile.buffBorders
    if type(bb) == "table" then
        local FLAG_KEYS = {
            buff = { buffFilterPlayer = "PLAYER", buffFilterRaid = "RAID",
                     buffFilterCancelable = "CANCELABLE",
                     buffFilterBigDefensive = "BIG_DEFENSIVE" },
            debuff = { debuffFilterPlayer = "PLAYER", debuffFilterRaid = "RAID",
                       debuffFilterIncludeNameplateOnly = "INCLUDE_NAME_PLATE_ONLY",
                       debuffFilterRaidPlayerDispellable = "RAID",
                       debuffFilterCrowdControl = "CROWD_CONTROL" },
        }
        local function seedZone(prefix, storeKey, auraType, enableKey, cancelable)
            if type(bb[storeKey]) == "table" and bb[storeKey].elementsSeeded then return end
            local e = E.NewFilterStripElement(auraType)
            e.id = prefix .. "s"
            e.enabled = (bb[enableKey] ~= false)
            local size = bb[prefix .. "IconSize"]
            if type(size) == "number" then
                e.iconSize = (size > 0) and size or 30
            else
                e.iconSize = 35
            end
            local perRow = bb[prefix .. "IconsPerRow"]
            e.iconsPerRow = (type(perRow) == "number" and perRow > 0) and perRow or 10
            local spacing = bb[prefix .. "IconSpacing"]
            e.spacing = (type(spacing) == "number" and spacing > 0) and spacing or 2
            e.maxIcons = 40
            local growLeft = bb[prefix .. "GrowLeft"]
            if growLeft == nil then growLeft = true end
            local growUp = bb[prefix .. "GrowUp"] == true
            e.growDirection = growLeft and "LEFT" or "RIGHT"
            if growUp then
                e.anchor = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
            else
                e.anchor = growLeft and "TOPRIGHT" or "TOPLEFT"
            end
            e.sortRule = bb[prefix .. "SortRule"] or "INDEX"
            e.sortReverse = bb[prefix .. "SortReverse"] == true
            local flags, any = {}, false
            for dbKey, token in pairs(FLAG_KEYS[prefix]) do
                if bb[dbKey] then flags[token] = true; any = true end
            end
            if prefix == "buff" and bb.buffFilterNotCancelable then
                if flags.CANCELABLE == nil then flags.CANCELABLE = "exclude" end
                any = true
            end
            if any then
                e.filterMode = "flags"
                e.filterFlags = flags
            end
            e.duration.fontSize = (type(bb.fontSize) == "number" and bb.fontSize > 0) and bb.fontSize or 12
            e.duration.anchor = bb[prefix .. "DurationTextAnchor"] or e.duration.anchor
            e.duration.offsetX = bb[prefix .. "DurationTextOffsetX"] or e.duration.offsetX
            e.duration.offsetY = bb[prefix .. "DurationTextOffsetY"] or e.duration.offsetY
            e.stack.fontSize = e.duration.fontSize
            e.stack.anchor = bb[prefix .. "StackTextAnchor"] or e.stack.anchor
            e.stack.offsetX = bb[prefix .. "StackTextOffsetX"] or e.stack.offsetX
            e.stack.offsetY = bb[prefix .. "StackTextOffsetY"] or e.stack.offsetY
            e.rightClickCancel = cancelable
            bb[storeKey] = { elementsSeeded = true, elements = { ["*"] = { e } } }
        end
        seedZone("buff", "buffAuras", "HELPFUL", "enableBuffs", true)
        seedZone("debuff", "debuffAuras", "HARMFUL", "enableDebuffs", false)
        local PRUNE_SUFFIXES = {
            "IconSize", "IconsPerRow", "IconSpacing", "GrowLeft", "GrowUp",
            "SortRule", "SortReverse", "RowSpacing", "InvertSwipeDarkening",
            "DurationTextAnchor", "DurationTextOffsetX", "DurationTextOffsetY",
            "StackTextAnchor", "StackTextOffsetX", "StackTextOffsetY",
        }
        for _, prefix in ipairs({ "buff", "debuff" }) do
            for _, suffix in ipairs(PRUNE_SUFFIXES) do
                bb[prefix .. suffix] = nil
            end
            for dbKey in pairs(FLAG_KEYS[prefix]) do
                bb[dbKey] = nil
            end
            if prefix == "buff" then bb.buffFilterNotCancelable = nil end
        end
    end

    local UF_HEAD_DEFAULTS = {
        player       = { buff = { iconSize = 22, maxIcons = 4,  offsetY = 0 },  debuff = { iconSize = 22, maxIcons = 4,  offsetY = 0 } },
        target       = { buff = { iconSize = 18, maxIcons = 4,  offsetY = 0 },  debuff = { iconSize = 26, maxIcons = 4,  offsetY = 0 } },
        targettarget = { buff = { iconSize = 22, maxIcons = 4,  offsetY = 0 },  debuff = { iconSize = 22, maxIcons = 4,  offsetY = 0 } },
        pet          = { buff = { iconSize = 22, maxIcons = 4,  offsetY = 0 },  debuff = { iconSize = 22, maxIcons = 4,  offsetY = 0 } },
        focus        = { buff = { iconSize = 20, maxIcons = 16, offsetY = -2 }, debuff = { iconSize = 20, maxIcons = 16, offsetY = 2 } },
        boss         = { buff = { iconSize = 22, maxIcons = 4,  offsetY = 0 },  debuff = { iconSize = 22, maxIcons = 4,  offsetY = 0 } },
    }
    local UF_HEAD_FALLBACK = {
        buff = { iconSize = 22, maxIcons = 16, offsetY = -2 },
        debuff = { iconSize = 22, maxIcons = 16, offsetY = 2 },
    }
    local uf = profile.quiUnitFrames
    if type(uf) == "table" then
        for unitKey, unit in pairs(uf) do
            local a = type(unit) == "table" and unit.auras
            if type(a) == "table" and not a.elementsSeeded then
                local unitDefaults = UF_HEAD_DEFAULTS[unitKey] or UF_HEAD_FALLBACK
                local function seedElem(prefix, auraType, showKey)
                    local d = unitDefaults[prefix]
                    local e = E.NewFilterStripElement(auraType)
                    e.id = prefix .. "s"
                    e.enabled = (a[showKey] == true)
                    local size = a[prefix .. "IconSize"] or ((prefix == "debuff") and a.iconSize)
                    e.iconSize = (type(size) == "number" and size > 0) and size or d.iconSize
                    e.anchor = a[prefix .. "Anchor"] or ((prefix == "buff") and "BOTTOMLEFT" or "TOPLEFT")
                    e.growDirection = a[prefix .. "Grow"] or "RIGHT"
                    local m = a[prefix .. "MaxIcons"]
                    e.maxIcons = (type(m) == "number" and m > 0) and m or d.maxIcons
                    e.iconsPerRow = a[prefix .. "MaxPerRow"] or 0
                    e.offsetX = a[prefix .. "OffsetX"] or 0
                    e.offsetY = a[prefix .. "OffsetY"] or d.offsetY
                    e.spacing = a[prefix .. "Spacing"] or a.iconSpacing or 2
                    if a[prefix .. "FilterMode"] == "classification" and type(a[prefix .. "Classifications"]) == "table" then
                        e.filterMode = "classify"
                        e.classifications = a[prefix .. "Classifications"]
                        local c = e.classifications
                        local master = (auraType == "HELPFUL") and "helpful" or "harmful"
                        if c[master] == nil and (c.raid or c.raidInCombat) then
                            c[master] = true
                        end
                    elseif type(a[prefix .. "Filter"]) == "table" then
                        local lf = a[prefix .. "Filter"]
                        local valid = E.VALID_FILTER_TOKENS or {}
                        local flags = {}
                        if type(lf.modifiers) == "table" then
                            for tok, on in pairs(lf.modifiers) do
                                if on == true and valid[tok] then flags[tok] = true end
                            end
                        end
                        if type(lf.exclusive) == "string" and valid[lf.exclusive] then
                            flags[lf.exclusive] = true
                        end
                        for tok, on in pairs(lf) do
                            if on == true and valid[tok] then flags[tok] = true end
                        end
                        local legacyNotCancelable = type(lf.modifiers) == "table"
                            and lf.modifiers.NOT_CANCELABLE == true
                        legacyNotCancelable = legacyNotCancelable
                            or lf.exclusive == "NOT_CANCELABLE"
                            or lf.NOT_CANCELABLE == true
                        if legacyNotCancelable and flags.CANCELABLE == nil then
                            flags.CANCELABLE = "exclude"
                        end
                        if next(flags) then
                            e.filterMode = "flags"
                            e.filterFlags = flags
                        end
                    end
                    local dur = a[prefix .. "Duration"]
                    if type(dur) == "table" then
                        e.duration = { show = dur.show ~= false, fontSize = dur.fontSize or 10,
                                       anchor = dur.anchor or "CENTER", offsetX = dur.offsetX or 0,
                                       offsetY = dur.offsetY or 0, color = dur.color or { 1, 1, 1, 1 } }
                    else
                        e.duration = { show = (prefix == "buff"), fontSize = (prefix == "buff") and 12 or 10,
                                       anchor = "CENTER", offsetX = 0, offsetY = 0, color = { 1, 1, 1, 1 } }
                    end
                    local st = a[prefix .. "Stack"]
                    if type(st) == "table" then
                        e.stack = { show = st.show ~= false, fontSize = st.fontSize or 10,
                                    anchor = st.anchor or "BOTTOMRIGHT", offsetX = st.offsetX or -1,
                                    offsetY = st.offsetY or 1, color = st.color or { 1, 1, 1, 1 } }
                    else
                        e.stack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT",
                                    offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } }
                    end
                    e.hideSwipe = (a[prefix .. "HideSwipe"] == true) or (a.hideSwipe == true)
                    e.reverseSwipe = (a[prefix .. "ReverseSwipe"] == true) or (a.reverseSwipe == true)
                    e.rightClickCancel = (unitKey == "player") and (auraType == "HELPFUL")
                    return e
                end
                local debuff = seedElem("debuff", "HARMFUL", "showDebuffs")
                local buff = seedElem("buff", "HELPFUL", "showBuffs")
                a.elements = { ["*"] = { debuff, buff } }
                a.elementsSeeded = true
                local PRUNE = {
                    "showBuffs", "showDebuffs", "iconSize", "iconSpacing",
                    "hideSwipe", "reverseSwipe",
                    "durationColor", "showDuration", "durationSize", "durationAnchor",
                    "durationOffsetX", "durationOffsetY",
                    "stackColor", "showStack", "stackSize", "stackAnchor",
                    "stackOffsetX", "stackOffsetY",
                }
                for _, k in ipairs(PRUNE) do a[k] = nil end
                for _, prefix in ipairs({ "buff", "debuff" }) do
                    for _, suffix in ipairs({ "IconSize", "Anchor", "Grow", "MaxIcons", "MaxPerRow",
                        "OffsetX", "OffsetY", "Spacing", "FilterMode", "FilterOnlyMine", "Classifications",
                        "Filter", "Duration", "Stack", "ShowStack", "StackSize", "StackAnchor",
                        "StackOffsetX", "StackOffsetY", "StackColor", "BorderSize", "FontSize",
                        "HideSwipe", "ReverseSwipe", "ShowDuration", "DurationSize", "DurationAnchor",
                        "DurationOffsetX", "DurationOffsetY", "DurationColor" }) do
                        a[prefix .. suffix] = nil
                    end
                end
            end
        end
    end

    local gf = profile.quiGroupFrames
    if type(gf) == "table" then
        for _, groupKey in ipairs({ "party", "raid" }) do
            local a = type(gf[groupKey]) == "table" and gf[groupKey].auras
            if type(a) == "table" and type(a.elements) == "table" then
                for _, bucket in pairs(a.elements) do
                    if type(bucket) == "table" then
                        for _, e in ipairs(bucket) do E.NormalizeElement(e) end
                    end
                end
            end
        end
    end
end

local function BuildShippedDefensivesElement(enabled)
    return {
        id = "defensives", enabled = enabled == true, mode = "filterStrip", auraType = "HELPFUL",
        anchor = "BOTTOMRIGHT", growDirection = "LEFT", spacing = 0,
        offsetX = 0, offsetY = 4, iconSize = 15, maxIcons = 3,
        hideSwipe = false, reverseSwipe = true,
        swipeStyle = "radial",
        duration = { show = true, fontSize = 9, anchor = "BOTTOM", offsetX = 0, offsetY = -6, color = { 1, 1, 1, 1 } },
        stack = { show = true, fontSize = 9, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } },
        filterMode = "classify", filterFlags = {},
        classifications = { bigDefensive = true, externalDefensive = true },
        borderColor = { 0, 0.8, 0, 1 },
        whitelist = {}, blacklist = {},
        sortRule = "INDEX", sortReverse = false, rightClickCancel = false,
    }
end

local function IsDefensivesEquivalent(element)
    return type(element) == "table" and (element.id == "defensives"
        or (element.filterMode == "classify"
            and type(element.classifications) == "table"
            and element.classifications.bigDefensive
            and element.classifications.externalDefensive))
end

local function IsAuraOverrideBucketKey(bucketKey)
    return type(bucketKey) == "number"
end

local function StripDedupeFromStore(store)
    local elements = type(store) == "table" and type(store.elements) == "table" and store.elements
    if not elements then return end
    for _, bucket in pairs(elements) do
        if type(bucket) == "table" then
            for _, e in ipairs(bucket) do
                if type(e) == "table" then e.dedupeDefensives = nil end
            end
        end
    end
end

function Migrations.FoldDefensiveIndicatorIntoElements(profile)
    local gf = profile.quiGroupFrames
    if type(gf) == "table" then
        for _, key in ipairs({ "party", "raid" }) do
            local surface = gf[key]
            if type(surface) == "table" then
                local healer = surface.healer
                local di = type(healer) == "table" and healer.defensiveIndicator
                local oldEnabled = type(di) == "table" and di.enabled == true

                local a = surface.auras
                local elements = type(a) == "table" and type(a.elements) == "table" and a.elements
                if elements and a.elementsSeeded then
                    local base
                    local star = elements["*"]
                    if type(star) == "table" then
                        for _, e in ipairs(star) do
                            if type(e) == "table" and e.id == "defensives" then
                                base = e
                                break
                            end
                        end
                        if not base then
                            base = BuildShippedDefensivesElement(oldEnabled)
                            star[#star + 1] = base
                        end
                    end

                    if base then
                        for bucketKey, bucket in pairs(elements) do
                            if IsAuraOverrideBucketKey(bucketKey)
                                and type(bucket) == "table" and #bucket > 0 then
                                local present = false
                                for _, e in ipairs(bucket) do
                                    if IsDefensivesEquivalent(e) then
                                        present = true
                                        break
                                    end
                                end
                                if not present then
                                    bucket[#bucket + 1] = CloneValue(base)
                                end
                            end
                        end
                    end
                end

                StripDedupeFromStore(a)
                if type(healer) == "table" then healer.defensiveIndicator = nil end
            end
        end
    end

    local uf = profile.quiUnitFrames
    if type(uf) == "table" then
        for _, unit in pairs(uf) do
            if type(unit) == "table" then StripDedupeFromStore(unit.auras) end
        end
    end

    local bb = profile.buffBorders
    if type(bb) == "table" then
        StripDedupeFromStore(bb.buffAuras)
        StripDedupeFromStore(bb.debuffAuras)
    end
    return true
end

local CDM_GLOW_SUFFIXES = {
    "PandemicDebuffEnabled", "PandemicBuffEnabled", "PandemicEnabled",
    "Thickness", "Frequency", "GlowType", "XOffset", "YOffset", "Enabled",
    "Color", "Scale", "Lines",
}

function Migrations.PurgeOrphanContainerSatellites(profile)
    local ncdm = profile.ncdm
    local live = {}
    if ncdm and type(ncdm.containers) == "table" then
        for key in pairs(ncdm.containers) do live[key] = true end
    end

    local anchors = profile.frameAnchoring
    if type(anchors) == "table" then
        local toRemove = {}
        for k in pairs(anchors) do
            if type(k) == "string" then
                local key = k:match("^cdmCustom_(.+)$")
                if key and not live[key] then toRemove[#toRemove + 1] = k end
            end
        end
        for _, k in ipairs(toRemove) do anchors[k] = nil end
    end

    local effects = profile.cooldownEffects
    if type(effects) == "table" then
        local toRemove = {}
        for k in pairs(effects) do
            if type(k) == "string" then
                local key = k:match("^hide_(.+)$")
                if key and not live[key] then toRemove[#toRemove + 1] = k end
            end
        end
        for _, k in ipairs(toRemove) do effects[k] = nil end
    end

    local glow = profile.customGlow
    if type(glow) == "table" then
        local toRemove = {}
        for k in pairs(glow) do
            if type(k) == "string" then
                for _, suffix in ipairs(CDM_GLOW_SUFFIXES) do
                    local key = k:match("^(.+)" .. suffix .. "$")
                    if key then
                        if key ~= "essential" and key ~= "utility"
                            and (key:find("^custom_") or key:find("^customBar_"))
                            and not live[key] then
                            toRemove[#toRemove + 1] = k
                        end
                        break
                    end
                end
            end
        end
        for _, k in ipairs(toRemove) do glow[k] = nil end
    end

    return true
end

function Migrations.PurgeLegacyCustomBarShadowStores(profile)
    local ncdm = profile and profile.ncdm
    local containers = ncdm and ncdm.containers
    if type(ncdm) ~= "table" or type(containers) ~= "table" then return false end

    local toRemove = {}
    for key in pairs(ncdm) do
        if type(key) == "string"
            and (key:find("^custom_") or key:find("^customBar_"))
            and type(containers[key]) == "table"
        then
            toRemove[#toRemove + 1] = key
        end
    end
    for _, key in ipairs(toRemove) do
        containers[key] = ncdm[key]
        ncdm[key] = nil
    end
    return #toRemove > 0
end

local CUSTOM_TRACKER_ANCHOR_PREFIX = "customTracker:"
local CDM_CUSTOM_ANCHOR_PREFIX = "cdmCustom_"

local function GetCustomBarContainerKey(legacyId)
    return "customBar_" .. tostring(legacyId)
end

local function GetCustomBarAnchorKey(containerKey)
    return CDM_CUSTOM_ANCHOR_PREFIX .. tostring(containerKey)
end

local function FindCustomBarContainerByLegacyId(containers, legacyId)
    if type(containers) ~= "table" then return nil, nil end
    local destKey = GetCustomBarContainerKey(legacyId)
    if type(containers[destKey]) == "table" then
        return destKey, containers[destKey]
    end
    for key, container in pairs(containers) do
        if type(container) == "table" and container._legacyId == legacyId then
            return key, container
        end
    end
    return nil, nil
end

local function BuildCustomBarRowFromLegacy(bar)
    return {
        iconCount        = bar.maxIcons or 8,
        iconSize         = bar.iconSize or 28,
        borderSize       = bar.borderSize or 2,
        borderColorTable = CloneValue(bar.borderColor or bar.borderColorTable or {0, 0, 0, 1}),
        aspectRatioCrop  = bar.aspectRatioCrop or 1.0,
        zoom             = bar.zoom or 0,
        padding          = bar.spacing or 4,
        xOffset          = 0,
        yOffset          = 0,
        hideDurationText = bar.hideDurationText == true,
        durationFont     = bar.durationFont,
        durationSize     = bar.durationSize or bar.durationTextSize or 13,
        durationOffsetX  = bar.durationOffsetX or 0,
        durationOffsetY  = bar.durationOffsetY or 0,
        durationTextColor = CloneValue(bar.durationColor or bar.durationTextColor or {1, 1, 1, 1}),
        durationAnchor   = bar.durationAnchor or "CENTER",
        stackFont        = bar.stackFont,
        stackSize        = bar.stackSize or bar.stackTextSize or 9,
        stackOffsetX     = bar.stackOffsetX or 3,
        stackOffsetY     = bar.stackOffsetY or -1,
        stackTextColor   = CloneValue(bar.stackColor or bar.stackTextColor or {1, 1, 1, 1}),
        stackAnchor      = bar.stackAnchor or "BOTTOMRIGHT",
        hideStackText    = bar.hideStackText == true,
        opacity          = 1.0,
    }
end

local LEGACY_CUSTOM_TRACKER_COMPAT_FIELDS = {
    "enabled",
    "locked",
    "hideGCD",
    "hideNonUsable",
    "showOnlyOnCooldown",
    "showOnlyWhenActive",
    "showOnlyWhenOffCooldown",
    "showOnlyInCombat",
    "dynamicLayout",
    "clickableIcons",
    "showItemCharges",
    "showRechargeSwipe",
    "noDesaturateWithCharges",
    "showProfessionQuality",
    "showActiveState",
    "activeGlowEnabled",
    "activeGlowType",
    "activeGlowColor",
    "activeGlowLines",
    "activeGlowFrequency",
    "activeGlowThickness",
    "activeGlowScale",
}

local function NormalizeCustomBarVisibilityFlags(container)
    if type(container) ~= "table" then return end

    local mode = "always"
    if container.showOnlyOnCooldown then
        mode = "onCooldown"
        container.showOnlyWhenActive = false
        container.showOnlyWhenOffCooldown = false
    elseif container.showOnlyWhenActive then
        mode = "active"
        container.showOnlyWhenOffCooldown = false
    elseif container.showOnlyWhenOffCooldown then
        mode = "offCooldown"
    end

    container.visibilityMode = mode

    if mode ~= "onCooldown" then
        container.noDesaturateWithCharges = false
    end
end

local function StampCustomBarCompatibilityDefaults(container)
    if type(container) ~= "table" then return end

    container.tooltipContext = container.tooltipContext or "customTrackers"
    container.keybindContext = container.keybindContext or "customTrackers"

    if container.hideGCD == nil then container.hideGCD = true end
    if container.showItemCharges == nil then container.showItemCharges = true end
    if container.showProfessionQuality == nil then container.showProfessionQuality = true end
    if container.showActiveState == nil then container.showActiveState = true end
    if container.activeGlowEnabled == nil then container.activeGlowEnabled = true end
    if container.activeGlowType == nil then container.activeGlowType = "Pixel Glow" end
    if container.activeGlowColor == nil then container.activeGlowColor = {1, 0.85, 0.3, 1} end
    if container.activeGlowLines == nil then container.activeGlowLines = 8 end
    if container.activeGlowFrequency == nil then container.activeGlowFrequency = 0.25 end
    if container.activeGlowThickness == nil then container.activeGlowThickness = 2 end
    if container.activeGlowScale == nil then container.activeGlowScale = 1.0 end

    if container.dynamicLayout == nil then
        container.dynamicLayout = false
    end
    if container.dynamicLayout and container.clickableIcons then
        container.clickableIcons = false
    end

    if type(container.row1) == "table" then
        local row = container.row1
        if row.hideStackText == nil then row.hideStackText = container.hideStackText == true end
        if row.durationFont == nil then row.durationFont = container.durationFont end
        if row.stackFont == nil then row.stackFont = container.stackFont end
    end

    NormalizeCustomBarVisibilityFlags(container)
end

local function CopyLegacyCustomTrackerAnchor(profile, legacyId, containerKey)
    local fa = profile and profile.frameAnchoring
    if type(fa) ~= "table" then return end

    local oldKey = CUSTOM_TRACKER_ANCHOR_PREFIX .. tostring(legacyId)
    local newKey = GetCustomBarAnchorKey(containerKey)

    if type(fa[oldKey]) == "table" and type(fa[newKey]) ~= "table" then
        fa[newKey] = CloneValue(fa[oldKey])
    end

    for _, entry in pairs(fa) do
        if type(entry) == "table" and entry.parent == oldKey then
            entry.parent = newKey
        end
    end
end

local function PortLegacySpecTrackerEntries(globalDB, legacyId, containerKey, container)
    if type(globalDB) ~= "table" then return end
    if type(globalDB.specTrackerSpells) ~= "table" then return end
    local src = globalDB.specTrackerSpells[legacyId]
    if type(src) ~= "table" then return end

    if type(globalDB.ncdm) ~= "table" then globalDB.ncdm = {} end
    if type(globalDB.ncdm.specTrackerSpells) ~= "table" then
        globalDB.ncdm.specTrackerSpells = {}
    end

    local dstRoot = globalDB.ncdm.specTrackerSpells
    if type(dstRoot[containerKey]) ~= "table" then
        dstRoot[containerKey] = {}
    end

    local dst = dstRoot[containerKey]
    local anyPorted = false
    for specKey, specList in pairs(src) do
        local canonicalKey, specID = GetCanonicalSpecKey(specKey)
        canonicalKey = canonicalKey or specKey
        if type(specList) == "table" then
            local copy = {}
            for i, entry in ipairs(specList) do
                copy[i] = StampLegacySpecEntry(CloneValue(entry), specID, specKey)
            end
            if type(dst[canonicalKey]) == "table" then
                if MergeSpecEntryLists(dst[canonicalKey], copy) then
                    anyPorted = true
                end
            else
                dst[canonicalKey] = copy
                anyPorted = true
            end
            RecordSpecKeyAlias(container, specKey, canonicalKey)
        end
    end

    if anyPorted and type(container) == "table" then
        container.specSpecific = true
    end
end

local IsUncustomizedDefaultTrackerBar

function Migrations.EnsureCustomTrackerBarContainer(profile, bar, globalDB)
    if type(profile) ~= "table" or type(bar) ~= "table" then return nil end
    if type(profile.ncdm) ~= "table" then profile.ncdm = {} end
    if type(profile.ncdm.containers) ~= "table" then profile.ncdm.containers = {} end

    local legacyId = bar.id
    if legacyId == nil or legacyId == "" then return nil end
    local sourceLegacyId = bar._importedLegacyId or legacyId

    local containers = profile.ncdm.containers
    local containerKey, container = FindCustomBarContainerByLegacyId(containers, legacyId)
    if not containerKey then
        containerKey = GetCustomBarContainerKey(legacyId)
    end

    if type(container) ~= "table" then
        container = CloneValue(bar)
        containers[containerKey] = container
    end

    container.builtIn = false
    container.containerType = "customBar"
    container.shape = "icon"
    container.name = bar.name or container.name or "Custom Bar"
    container.id = bar.id
    container._migratedFromCustomTrackers = true
    container._legacyId = legacyId
    container._importedLegacyId = nil

    for _, field in ipairs(LEGACY_CUSTOM_TRACKER_COMPAT_FIELDS) do
        if bar[field] ~= nil then
            container[field] = CloneValue(bar[field])
        end
    end

    container.pos = {
        ox = bar.offsetX or 0,
        oy = bar.offsetY or 0,
    }
    container.anchorTo = "disabled"

    container.row1 = BuildCustomBarRowFromLegacy(bar)
    container.row2 = { iconCount = 0 }
    container.row3 = { iconCount = 0 }

    local gd = bar.growDirection or container.growDirection
    container.growDirection = gd or "RIGHT"
    container.layoutDirection = (gd == "UP" or gd == "DOWN") and "VERTICAL" or "HORIZONTAL"

    if type(container.entries) ~= "table" and type(bar.entries) == "table" then
        container.entries = CloneValue(bar.entries)
    end
    if bar.specSpecificSpells == true then
        container.specSpecific = true
    end

    CopyLegacyCustomTrackerAnchor(profile, legacyId, containerKey)
    PortLegacySpecTrackerEntries(globalDB or _currentGlobalDB, sourceLegacyId, containerKey, container)
    StampCustomBarCompatibilityDefaults(container)

    return containerKey, container
end

function Migrations.SyncCustomTrackerBarsToCDM(profile, globalDB)
    local bars = profile and profile.customTrackers and profile.customTrackers.bars
    if type(bars) ~= "table" then return false end

    local any = false
    for _, bar in ipairs(bars) do
        if type(bar) == "table" and not IsUncustomizedDefaultTrackerBar(bar) then
            local key = Migrations.EnsureCustomTrackerBarContainer(profile, bar, globalDB)
            if key then any = true end
        end
    end
    if any and type(Migrations.RepairCustomTrackerSpecStorage) == "function" then
        Migrations.RepairCustomTrackerSpecStorage(profile, globalDB)
    end
    return any
end

function Migrations.RemoveLegacyCustomBarContainers(profile, globalDB)
    local containers = profile and profile.ncdm and profile.ncdm.containers
    if type(containers) ~= "table" then return end

    for key, container in pairs(containers) do
        if type(key) == "string" and type(container) == "table"
           and container.containerType == "customBar"
           and container._migratedFromCustomTrackers
        then
            containers[key] = nil
            if type(globalDB) == "table"
               and type(globalDB.ncdm) == "table"
               and type(globalDB.ncdm.specTrackerSpells) == "table"
            then
                globalDB.ncdm.specTrackerSpells[key] = nil
            end
            local fa = profile.frameAnchoring
            if type(fa) == "table" then
                fa[GetCustomBarAnchorKey(key)] = nil
            end
        end
    end
end

function IsUncustomizedDefaultTrackerBar(bar)
    if type(bar) ~= "table" then return false end
    if bar.id ~= "default_tracker_1" then return false end
    if bar.enabled ~= nil and bar.enabled ~= false then return false end
    if bar.name ~= nil and bar.name ~= "Trinket & Pot" then return false end
    if bar.offsetX ~= nil and bar.offsetX ~= -406 then return false end
    if bar.offsetY ~= nil and bar.offsetY ~= -152 then return false end
    if bar.iconSize ~= nil and bar.iconSize ~= 28 then return false end
    if bar.spacing ~= nil and bar.spacing ~= 4 then return false end

    local entries = bar.entries
    if type(entries) == "table" then
        if #entries ~= 1 then return false end
        local entry = entries[1]
        if type(entry) ~= "table" or entry.type ~= "item" or entry.id ~= 224022 then
            return false
        end
    end

    return true
end

function Migrations.RepairCustomTrackerSpecStorage(profile, globalDB)
    if type(profile) ~= "table" then return false end
    local containers = profile.ncdm and profile.ncdm.containers
    if type(containers) ~= "table" then return false end
    globalDB = globalDB or _currentGlobalDB
    if type(globalDB) ~= "table" then return false end
    if type(globalDB.ncdm) ~= "table" then globalDB.ncdm = {} end
    if type(globalDB.ncdm.specTrackerSpells) ~= "table" then
        globalDB.ncdm.specTrackerSpells = {}
    end

    local root = globalDB.ncdm.specTrackerSpells
    local changed = false

    for containerKey, container in pairs(containers) do
        if type(containerKey) == "string"
           and containerKey:find("^customBar_")
           and type(container) == "table"
        then
            local byContainer = root[containerKey]
            if type(byContainer) == "table" then
                local keys = {}
                for specKey in pairs(byContainer) do
                    keys[#keys + 1] = specKey
                end

                for _, specKey in ipairs(keys) do
                    local list = byContainer[specKey]
                    if type(list) == "table" then
                        local canonicalKey, specID = GetCanonicalSpecKey(specKey)
                        canonicalKey = canonicalKey or specKey
                        if not specID and type(container._sourceSpecID) == "number" then
                            specID = container._sourceSpecID
                        end

                        for _, entry in ipairs(list) do
                            StampLegacySpecEntry(entry, specID, specKey)
                        end
                        if DeduplicateEntryList(list) then
                            changed = true
                        end

                        if canonicalKey ~= specKey then
                            if type(byContainer[canonicalKey]) == "table" then
                                if MergeSpecEntryLists(byContainer[canonicalKey], list) then
                                    changed = true
                                end
                            else
                                byContainer[canonicalKey] = list
                                changed = true
                            end
                            byContainer[specKey] = nil
                            RecordSpecKeyAlias(container, specKey, canonicalKey)
                            changed = true
                        end
                    end
                end
            end

            if container.specSpecific == true
               and type(container.entries) == "table"
               and #container.entries > 0
            then
                PromoteLegacyContainerEntriesToPerSpec(profile, containerKey, container, globalDB)
                container.entries = {}
                changed = true
            end
        end
    end

    return changed
end

PromoteLegacyContainerEntriesToPerSpec = function(profile, containerKey, container, globalDB)
    if type(container) ~= "table" then return false end
    if container.specSpecific ~= true then return false end
    if type(container.entries) ~= "table" or #container.entries == 0 then return false end

    local sourceSpecID = container._sourceSpecID
    if type(sourceSpecID) ~= "number" or sourceSpecID <= 0 then
        sourceSpecID = GetProfileSourceSpecID(profile)
    end
    if type(sourceSpecID) ~= "number" or sourceSpecID <= 0 then
        return false
    end
    if container._sourceSpecID == nil then
        container._sourceSpecID = sourceSpecID
    end

    globalDB = globalDB or _currentGlobalDB
    if type(globalDB) ~= "table" then return false end
    if type(globalDB.ncdm) ~= "table" then globalDB.ncdm = {} end
    if type(globalDB.ncdm.specTrackerSpells) ~= "table" then
        globalDB.ncdm.specTrackerSpells = {}
    end
    local root = globalDB.ncdm.specTrackerSpells
    if type(root[containerKey]) ~= "table" then
        root[containerKey] = {}
    end
    local byContainer = root[containerKey]

    local canonicalKey = GetCanonicalSpecKey(sourceSpecID) or tostring(sourceSpecID)
    if type(byContainer[canonicalKey]) ~= "table" then
        byContainer[canonicalKey] = {}
    end

    local promoted = {}
    for _, entry in ipairs(container.entries) do
        if type(entry) == "table" then
            local clone = CloneValue(entry)
            StampLegacySpecEntry(clone, sourceSpecID, tostring(sourceSpecID),
                { legacySpellbookSlot = true })
            promoted[#promoted + 1] = clone
        end
    end
    MergeSpecEntryLists(byContainer[canonicalKey], promoted)
    DeduplicateEntryList(byContainer[canonicalKey])
    return true
end

local EM_TO_QUI = nil
local function GetEditModeLookup()
    if EM_TO_QUI then return EM_TO_QUI end
    if type(Enum) ~= "table" or type(Enum.EditModeSystem) ~= "table" then
        return nil
    end
    local AB    = Enum.EditModeSystem.ActionBar
    local MICRO = Enum.EditModeSystem.MicroMenu
    local BAGS  = Enum.EditModeSystem.Bags
    if AB == nil or MICRO == nil or BAGS == nil then
        return nil
    end
    EM_TO_QUI = {
        [AB] = {
            [1]  = { fa = "bar1",      frame = "MainActionBar" },
            [2]  = { fa = "bar2",      frame = "MultiBarBottomLeft" },
            [3]  = { fa = "bar3",      frame = "MultiBarBottomRight" },
            [4]  = { fa = "bar4",      frame = "MultiBarRight" },
            [5]  = { fa = "bar5",      frame = "MultiBarLeft" },
            [6]  = { fa = "bar6",      frame = "MultiBar5" },
            [7]  = { fa = "bar7",      frame = "MultiBar6" },
            [8]  = { fa = "bar8",      frame = "MultiBar7" },
            [11] = { fa = "stanceBar", frame = "StanceBar" },
            [12] = { fa = "petBar",    frame = "PetActionBar" },
        },
        [MICRO] = { ["*"] = { fa = "microMenu", frame = "MicroMenuContainer" } },
        [BAGS]  = { ["*"] = { fa = "bagBar",    frame = "BagsBar" } },
    }
    return EM_TO_QUI
end

local function LookupEditModeSystem(sys)
    local lookup = GetEditModeLookup()
    if not lookup then return nil end
    local typeTable = lookup[sys.system]
    if not typeTable then return nil end
    return typeTable[sys.systemIndex] or typeTable["*"]
end

local function MigrateActionBarPositionsFromEditMode(profile)
    if type(profile) ~= "table" then return end
    if profile._abPositionsImportedFromEditMode then
        MigLog("EditMode AB import: sentinel set, skipping")
        return
    end

    if not profile._needsLateAbImport then
        MigLog("EditMode AB import: profile not flagged for late import, stamping sentinel and skipping")
        profile._abPositionsImportedFromEditMode = true
        return
    end

    if not (EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo) then
        MigLog("EditMode AB import: EditModeManagerFrame not ready, will retry")
        return
    end

    local layout = EditModeManagerFrame:GetActiveLayoutInfo()
    if type(layout) ~= "table" or type(layout.systems) ~= "table" then
        MigLog("EditMode AB import: no active layout, will retry")
        return
    end

    profile.frameAnchoring = profile.frameAnchoring or {}
    local fa = profile.frameAnchoring

    local imported, protected, skipped = 0, 0, 0

    for _, sys in ipairs(layout.systems) do
        local mapping = LookupEditModeSystem(sys)
        if mapping then
            local key = mapping.fa
            local existing = fa[key]
            local userHasPosition = (existing ~= nil) and (not IsPlaceholderAnchorEntry(existing))

            if userHasPosition then
                protected = protected + 1
                MigLog("  %s: PROTECTED (user has QUI position)", key)
            else
                local frame = _G[mapping.frame]
                local L = frame and frame.GetLeft and frame:GetLeft()
                local B = frame and frame.GetBottom and frame:GetBottom()
                if type(L) == "number" and type(B) == "number" then
                    fa[key] = {
                        parent   = "screen",
                        point    = "BOTTOMLEFT",
                        relative = "BOTTOMLEFT",
                        offsetX  = L,
                        offsetY  = B,
                    }
                    imported = imported + 1
                    MigLog("  %s: IMPORTED at %.1f, %.1f (from %s, %s)",
                        key, L, B, mapping.frame,
                        sys.isInDefaultPosition and "default" or "moved")
                else
                    skipped = skipped + 1
                    MigLog("  %s: SKIPPED (frame %s not laid out)", key, mapping.frame)
                end
            end
        end
    end

    profile._abPositionsImportedFromEditMode = true
    profile._needsLateAbImport = nil

    MigLog("EditMode AB import done: imported=%d protected=%d skipped=%d",
        imported, protected, skipped)
end

local function ClaimUniqueNameplateProfileName(store, baseName)
    if store[baseName] == nil then return baseName end
    local suffix = 2
    while store[baseName .. " " .. suffix] ~= nil do
        suffix = suffix + 1
    end
    return baseName .. " " .. suffix
end

local function EnsureNameplateProfileStore(globalDB)
    if type(globalDB.nameplateProfiles) ~= "table" then
        globalDB.nameplateProfiles = {}
    end
    return globalDB.nameplateProfiles
end

local function EnsureNameplateAssignments(globalDB)
    local assignments = globalDB.nameplateProfileAssignments
    if type(assignments) ~= "table" then
        assignments = { autoSwitch = false }
        globalDB.nameplateProfileAssignments = assignments
    end
    if type(assignments.specs) ~= "table" then assignments.specs = {} end
    if type(assignments.roles) ~= "table" then assignments.roles = {} end
    return assignments
end

-- Legacy nameplate spec presets were keyed by spec INDEX (1..4), which collides
-- across classes when characters share a profile. The class the snapshot was
-- saved on is unrecoverable, so they become unassigned named profiles in the
-- account-wide store. Without a global DB (profile import path) the legacy
-- keys are stripped instead.
function Migrations.MigrateNameplatePresets(profile, globalDB, profileLabel)
    local np = type(profile) == "table" and profile.nameplates
    if type(np) ~= "table" then return false end

    local changed = false
    local wantsAutoSwitch = np.specAutoSwitch == true

    if type(np.specPresets) == "table" then
        if globalDB then
            local store = EnsureNameplateProfileStore(globalDB)
            for specIndex, snap in pairs(np.specPresets) do
                if type(snap) == "table" and next(snap) ~= nil then
                    local base = ("Migrated spec preset %s"):format(tostring(specIndex))
                    if type(profileLabel) == "string" and profileLabel ~= "" then
                        base = ("%s (%s)"):format(base, profileLabel)
                    end
                    store[ClaimUniqueNameplateProfileName(store, base)] = CloneValue(snap)
                    MigLog("Nameplate presets: converted %s spec preset %s",
                        tostring(profileLabel or "?"), tostring(specIndex))
                end
            end
        end
        np.specPresets = nil
        changed = true
    end

    if np.specAutoSwitch ~= nil then
        np.specAutoSwitch = nil
        changed = true
    end

    if wantsAutoSwitch and globalDB then
        EnsureNameplateAssignments(globalDB).autoSwitch = true
    end

    return changed
end

-- Legacy role presets were already account-wide and unambiguous, so they keep
-- their role assignment as named profiles. Idempotent: the source key is
-- removed after conversion.
function Migrations.MigrateNameplateRolePresets(globalDB)
    if type(globalDB) ~= "table" then return false end
    local rolePresets = globalDB.nameplateRolePresets
    if type(rolePresets) ~= "table" then return false end

    local ROLE_PROFILE_NAMES = {
        { role = "TANK", name = "Tank" },
        { role = "HEALER", name = "Healer" },
        { role = "DAMAGER", name = "Damage" },
    }
    local store = EnsureNameplateProfileStore(globalDB)
    local assignments = EnsureNameplateAssignments(globalDB)

    for _, def in ipairs(ROLE_PROFILE_NAMES) do
        local snap = rolePresets[def.role]
        if type(snap) == "table" and next(snap) ~= nil then
            local name = ClaimUniqueNameplateProfileName(store, def.name)
            store[name] = CloneValue(snap)
            assignments.roles[def.role] = name
            MigLog("Nameplate presets: converted role preset %s -> %s", def.role, name)
        end
    end

    if rolePresets.autoSwitch == true then
        assignments.autoSwitch = true
    end

    globalDB.nameplateRolePresets = nil
    return true
end

function Migrations.RunLate(db)
    if not db then return false end
    local profile = db.profile
    if type(profile) ~= "table" then return false end
    MigrateActionBarPositionsFromEditMode(profile)
    return true
end

local BACKUP_KEY = "_migrationBackup"
local MAX_BACKUP_SLOTS = 1
local BACKUP_EXCLUDED_KEYS = {
    [BACKUP_KEY] = true,
    _shippedDefaults = true,
}

local function DeepCloneExcluding(value, excludedKeys)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        if not excludedKeys[k] then
            copy[k] = DeepCloneExcluding(v, excludedKeys)
        end
    end
    return copy
end

local function GetBackupContainer(profile)
    local b = profile[BACKUP_KEY]
    if type(b) ~= "table" then return nil end
    if type(b.slots) == "table" then
        return b
    end
    if type(b.snapshot) == "table" then
        local upgraded = { slots = { {
            fromVersion = b.fromVersion,
            toVersion   = b.toVersion,
            savedAt     = b.savedAt,
            snapshot    = b.snapshot,
        } } }
        profile[BACKUP_KEY] = upgraded
        return upgraded
    end
    return nil
end

local function CreateBackup(profile, fromVersion)
    local container = GetBackupContainer(profile) or { slots = {} }
    local newEntry = {
        fromVersion = fromVersion or 0,
        toVersion   = CURRENT_SCHEMA_VERSION,
        savedAt     = (time and time()) or 0,
        snapshot    = DeepCloneExcluding(profile, BACKUP_EXCLUDED_KEYS),
    }
    table.insert(container.slots, 1, newEntry)
    while #container.slots > MAX_BACKUP_SLOTS do
        table.remove(container.slots)
    end
    profile[BACKUP_KEY] = container
end

function Migrations.Restore(profile, slotIndex)
    if type(profile) ~= "table" then
        return false, "no profile"
    end
    local container = GetBackupContainer(profile)
    if not container or #container.slots == 0 then
        return false, "no migration backup available for this profile"
    end
    slotIndex = tonumber(slotIndex) or 1
    if slotIndex < 1 or slotIndex > #container.slots then
        return false, ("invalid slot %d (have %d backup(s))"):format(slotIndex, #container.slots)
    end
    local entry = container.slots[slotIndex]
    if type(entry) ~= "table" or type(entry.snapshot) ~= "table" then
        return false, ("backup slot %d is empty or corrupt"):format(slotIndex)
    end

    for k in pairs(profile) do
        if k ~= BACKUP_KEY then
            profile[k] = nil
        end
    end
    for k, v in pairs(entry.snapshot) do
        profile[k] = DeepCloneExcluding(v, BACKUP_EXCLUDED_KEYS)
    end
    return true, entry
end

local function PruneBackupContainer(profile)
    local existing = profile[BACKUP_KEY]
    local container = GetBackupContainer(profile)
    if not container or type(container.slots) ~= "table" then
        if existing ~= nil then
            profile[BACKUP_KEY] = nil
            return true
        end
        return false
    end

    local changed = existing ~= profile[BACKUP_KEY]
    local prunedSlots = {}
    for _, entry in ipairs(container.slots) do
        local snapshot = entry and entry.snapshot
        if type(snapshot) == "table" then
            for excludedKey in pairs(BACKUP_EXCLUDED_KEYS) do
                if snapshot[excludedKey] ~= nil then
                    snapshot[excludedKey] = nil
                    changed = true
                end
            end
            if #prunedSlots < MAX_BACKUP_SLOTS then
                prunedSlots[#prunedSlots + 1] = entry
            else
                changed = true
            end
        else
            changed = true
        end
    end

    if #prunedSlots == 0 then
        changed = changed or profile[BACKUP_KEY] ~= nil
        profile[BACKUP_KEY] = nil
    else
        changed = changed or #container.slots ~= #prunedSlots
        container.slots = prunedSlots
        profile[BACKUP_KEY] = container
    end

    return changed
end

function Migrations.GetBackupInfo(profile)
    if type(profile) ~= "table" then return nil end
    PruneBackupContainer(profile)
    return GetBackupContainer(profile)
end

Migrations.MAX_BACKUP_SLOTS = MAX_BACKUP_SLOTS

local function WipeProfileData(profile)
    for k in pairs(profile) do
        if k ~= BACKUP_KEY then
            profile[k] = nil
        end
    end
end

function Migrations.RunOnProfile(profile)
    if type(profile) ~= "table" then return false end

    local cleanupChanged = PruneBackupContainer(profile)

    local stored = tonumber(profile._schemaVersion) or 0

    if stored > 0 and stored < MIN_SUPPORTED_SCHEMA then
        MigLog("RunOnProfile: stored=%d below floor %d — backup + reseed",
            stored, MIN_SUPPORTED_SCHEMA)
        CreateBackup(profile, stored)
        WipeProfileData(profile)
        profile._needsStarterReseed = true
        profile._schemaVersion = CURRENT_SCHEMA_VERSION
        return true
    end

    if stored == 0 and not profile._abPositionsImportedFromEditMode then
        profile._needsLateAbImport = true
    end

    do
        local faCount = 0
        if type(profile.frameAnchoring) == "table" then
            for _ in pairs(profile.frameAnchoring) do faCount = faCount + 1 end
        end
        MigLog("=== RunOnProfile: stored=%d current=%d faEntries=%d ===",
            stored, CURRENT_SCHEMA_VERSION, faCount)
        if type(profile.frameAnchoring) == "table" and profile.frameAnchoring.debuffFrame then
            local d = profile.frameAnchoring.debuffFrame
            MigLog("  pre-mig debuffFrame: parent=%s point=%s ofs=%s/%s enabled=%s",
                tostring(d.parent), tostring(d.point), tostring(d.offsetX), tostring(d.offsetY), tostring(d.enabled))
        else
            MigLog("  pre-mig debuffFrame: NIL (no raw entry)")
        end
    end

    Migrations.ResetCastbarPreviewModes(profile)

    if stored >= CURRENT_SCHEMA_VERSION then
        MigLog("RunOnProfile: stored >= current, NOTHING TO DO")
        return cleanupChanged
    end

    local hasUserData = false
    for k in pairs(profile) do
        if k ~= "_schemaVersion" and k ~= "_defaultsVersion" and k ~= BACKUP_KEY then
            hasUserData = true
            break
        end
    end

    if hasUserData then
        CreateBackup(profile, stored)
    end

    if stored < CURRENT_SCHEMA_VERSION then
        Migrations.MigrateNameplatePresets(profile, _currentGlobalDB, _currentProfileKey)

        Migrations.RestoreBuffDebuffSplit(profile)

        Migrations.PrunePrivateAuras(profile)

        if Migrations.SeedAuraElements(profile) == false then
            return true
        end

        Migrations.FoldDefensiveIndicatorIntoElements(profile)

        Migrations.PurgeLegacyCustomBarShadowStores(profile)

        Migrations.PurgeOrphanContainerSatellites(profile)
    end

    profile._schemaVersion = CURRENT_SCHEMA_VERSION
    return true
end

function Migrations.Run(db)
    if not db then return false end

    _currentGlobalDB = db.global

    local sv = db.sv

    local profiles = sv and sv.profiles
    if type(profiles) == "table" then
        local any = false
        for profileKey, profile in pairs(profiles) do
            _currentProfileKey = profileKey
            if Migrations.RunOnProfile(profile) then
                any = true
            end
        end
        _currentProfileKey = nil

        Migrations.MigrateNameplateRolePresets(db.global)

        local pins = ns.Settings and ns.Settings.Pins
        if pins then
            if type(pins.PrepareActiveProfileForApply) == "function" then
                pins:PrepareActiveProfileForApply(db)
            end
            if type(pins.ApplyAllForDB) == "function" then
                pins:ApplyAllForDB(db)
            end
        end

        _currentGlobalDB     = nil
        return any
    end

    local result = Migrations.RunOnProfile(db.profile)

    Migrations.MigrateNameplateRolePresets(db.global)

    local pins = ns.Settings and ns.Settings.Pins
    if pins then
        if type(pins.PrepareActiveProfileForApply) == "function" then
            pins:PrepareActiveProfileForApply(db)
        end
        if type(pins.ApplyAllForDB) == "function" then
            pins:ApplyAllForDB(db)
        end
    end

    _currentGlobalDB     = nil
    return result
end
