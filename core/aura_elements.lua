local ADDON_NAME, ns = ...
local E = ns.AuraElements or {}
ns.AuraElements = E
_G.QUI = _G.QUI or {}
_G.QUI.AuraElements = E

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

local DISPLAY_TYPES = { icon = true, square = true, bar = true, healthTint = true, border = true }
local DEFAULT_MISSING_RAID_BUFF_CHECKS = {
    intellect = true, stamina = true, attackPower = true,
    versatility = true, skyfury = true, bronze = true,
}

local function IsUsableTrackedSpellID(spellID)
    return type(spellID) == "number" and spellID > 0
end

function E.ResolveTrackedSpellID(spellID)
    if not IsUsableTrackedSpellID(spellID) then return spellID end

    local runtime = ns.CDMAuraRuntime
    if runtime and runtime.ResolveAbilityAuraSpellID then
        local ok, mapped, remapped
        if ns.SafeCall then
            ok, mapped, remapped = ns.SafeCall(
                "best-effort-style", runtime.ResolveAbilityAuraSpellID, spellID)
        end
        if ok and remapped == true and IsUsableTrackedSpellID(mapped) then
            return mapped
        end
    end

    local spellData = ns.CDMSpellData
    if spellData and spellData.GetAuraIDsForSpell then
        local ok, auraIDs
        if ns.SafeCall then
            ok, auraIDs = ns.SafeCall(
                "best-effort-style", spellData.GetAuraIDsForSpell, spellData, spellID)
        end
        if ok and type(auraIDs) == "table" then
            for _, auraID in ipairs(auraIDs) do
                if IsUsableTrackedSpellID(auraID) and auraID ~= spellID then
                    return auraID
                end
            end
        end
    end

    return spellID
end

function E.TrackedSpellCandidates(spellID)
    local candidates = {}
    if not IsUsableTrackedSpellID(spellID) then return candidates end
    candidates[spellID] = true

    local resolved = E.ResolveTrackedSpellID(spellID)
    if IsUsableTrackedSpellID(resolved) then candidates[resolved] = true end

    local spellData = ns.CDMSpellData
    if spellData and spellData.GetAuraIDsForSpell then
        local ok, auraIDs
        if ns.SafeCall then
            ok, auraIDs = ns.SafeCall(
                "best-effort-style", spellData.GetAuraIDsForSpell, spellData, spellID)
        end
        if ok and type(auraIDs) == "table" then
            for _, auraID in ipairs(auraIDs) do
                if IsUsableTrackedSpellID(auraID) then candidates[auraID] = true end
            end
        end
    end

    return candidates
end

local BUFF_CLASSIFICATION_MAP = {
    helpful           = { "HELPFUL|RAID", "HELPFUL|RAID_IN_COMBAT" },
    raid              = "HELPFUL|RAID",
    raidInCombat      = "HELPFUL|RAID_IN_COMBAT",
    cancelable        = "HELPFUL|CANCELABLE",
    notCancelable     = "HELPFUL|!CANCELABLE",
    bigDefensive      = "HELPFUL|BIG_DEFENSIVE",
    externalDefensive = "HELPFUL|EXTERNAL_DEFENSIVE",
    important         = "HELPFUL|IMPORTANT",
}
local DEBUFF_CLASSIFICATION_MAP = {
    harmful      = { "HARMFUL|RAID" },
    raid         = "HARMFUL|RAID",
    important    = "HARMFUL|IMPORTANT",
    dispellable  = "HARMFUL|RAID",
    crowdControl = "HARMFUL|CROWD_CONTROL",
}

local BUFF_CLASSIFICATION_PRIORITY = {
    "raid", "raidInCombat", "cancelable", "notCancelable", "bigDefensive", "externalDefensive",
    "important",
}
local DEBUFF_CLASSIFICATION_PRIORITY = {
    "raid", "crowdControl",
    "important",
}

local function ClassificationComponent(entry)
    local fs = type(entry) == "string" and entry or nil
    if not fs then return nil end
    local comp = fs:match("^[A-Z_]+|(.+)$")
    return comp
end

local function NegateComponent(comp)
    if comp:sub(1, 1) == "!" then
        return comp:sub(2), true
    end
    return comp, false
end

local function IsClassificationEnabled(classifications, key)
    return classifications[key] == true
end

local function defaultClassifications(auraType)
    if auraType == "HARMFUL" then
        return { raid = true, crowdControl = true }
    end
    return { raid = false, raidInCombat = false, cancelable = false, notCancelable = false,
             bigDefensive = false, externalDefensive = false }
end

local function defaultDuration()
    return { show = true, fontSize = 9, anchor = "CENTER", offsetX = 0, offsetY = 0,
             color = { 1, 1, 1, 1 } }
end
local function defaultStack()
    return { show = true, fontSize = 9, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1,
             color = { 1, 1, 1, 1 } }
end

function E.NewFilterStripElement(auraType)
    return {
        id = nextId(), enabled = true, mode = "filterStrip",
        auraType = auraType or "HELPFUL",
        applyToRoles = "all",
        anchor = (auraType == "HARMFUL") and "BOTTOMRIGHT" or "TOPLEFT",
        offsetX = 0, offsetY = 0,
        growDirection = (auraType == "HARMFUL") and "LEFT" or "RIGHT",
        spacing = 2, iconSize = 14, maxIcons = 3, iconsPerRow = 0,
        hideSwipe = false, reverseSwipe = false,
        swipeStyle = "radial",
        duration = defaultDuration(),
        stack = defaultStack(),
        filterMode = "off", filterFlags = {},
        onlyMine = false, hidePermanent = false,
        classifications = defaultClassifications(auraType),
        whitelist = {}, blacklist = {},
        dispelFilterMode = "off", dispelTypes = {},
        maxDurationSec = 0,
        sortRule = "INDEX", sortReverse = false,
        rightClickCancel = true,
    }
end

function E.NewTrackedElement(spells, displayType)
    local normalizedSpells = {}
    for i, spellID in ipairs(spells or {}) do
        normalizedSpells[i] = E.ResolveTrackedSpellID(spellID)
    end
    return {
        id = nextId(), enabled = true, mode = "tracked",
        auraType = "HELPFUL",
        spells = normalizedSpells, onlyMine = false, onlyMineSpells = {},
        displayType = displayType or "icon",
        applyToRoles = "all",
        anchor = "TOPLEFT", offsetX = 0, offsetY = 0,
        growDirection = "RIGHT", spacing = 2, iconSize = 16, iconsPerRow = 0,
        hideSwipe = false, reverseSwipe = false,
        swipeStyle = "radial",
        duration = { show = false, fontSize = 9, anchor = "CENTER", offsetX = 0, offsetY = 0,
                     color = { 1, 1, 1, 1 } },
        stack = defaultStack(),
        color = { 1, 1, 1 },
        bar = { thickness = 12, length = 48 },
        border = { thickness = 2 },
    }
end

function E.TrackedSpellCount(element)
    local spells = type(element) == "table" and element.spells
    if type(spells) ~= "table" then return 0 end
    local count = 0
    for i = 1, #spells do
        if type(spells[i]) == "number" then count = count + 1 end
    end
    return count
end

function E.NewMissingRaidBuffElement()
    local checks = {}
    for key, value in pairs(DEFAULT_MISSING_RAID_BUFF_CHECKS) do checks[key] = value end
    return {
        id = nextId(), enabled = true, mode = "missingRaidBuff",
        applyToRoles = "all",
        classDetection = true, buffChecks = checks,
        anchor = "CENTER", offsetX = 0, offsetY = 0,
        growDirection = "RIGHT", spacing = 2, iconSize = 16, maxIcons = 1, iconsPerRow = 0,
        hideSwipe = true, reverseSwipe = false,
        swipeStyle = "radial",
        duration = { show = false, fontSize = 9, anchor = "CENTER", offsetX = 0, offsetY = 0,
                     color = { 1, 1, 1, 1 } },
        stack = defaultStack(),
    }
end

function E.Validate(e)
    if type(e) ~= "table" then return false end
    if e.mode == "filterStrip" then
        return e.auraType == "HELPFUL" or e.auraType == "HARMFUL"
    elseif e.mode == "tracked" then
        if not DISPLAY_TYPES[e.displayType] then return false end
        return type(e.spells) == "table" and #e.spells > 0
    elseif e.mode == "missingRaidBuff" then
        return true
    end
    return false
end

function E.EffectiveOnlyMine(e, spellID)
    if e.onlyMineSpells and e.onlyMineSpells[spellID] ~= nil then
        return e.onlyMineSpells[spellID]
    end
    return e.onlyMine == true
end

function E.NormalizeElement(e)
    if type(e) ~= "table" then return e end
    if type(e.duration) ~= "table" then
        e.duration = {
            show     = (e.showDurationText ~= false),
            fontSize = e.durationFontSize or 9,
            anchor   = e.durationAnchor or "CENTER",
            offsetX  = e.durationOffsetX or 0,
            offsetY  = e.durationOffsetY or 0,
            color    = e.durationColor or { 1, 1, 1, 1 },
        }
    end
    if type(e.stack) ~= "table" then
        e.stack = defaultStack()
    end
    e.showDurationText = nil
    e.durationFontSize = nil
    e.durationAnchor = nil
    e.durationOffsetX = nil
    e.durationOffsetY = nil
    e.durationColor = nil
    e.durationUseTimeColor = nil
    e.showDurationColor = nil
    e.showExpiringPulse = nil
    if e.mode == "filterStrip" then
        if e.sortRule == nil then e.sortRule = "INDEX" end
        if e.sortReverse == nil then e.sortReverse = false end
        if e.rightClickCancel == nil then e.rightClickCancel = true end
        if e.filterFlags == nil then e.filterFlags = {} end
        for tok, v in pairs(e.filterFlags) do
            if v ~= true and v ~= "exclude" then
                e.filterFlags[tok] = v and true or nil
            end
        end
        if e.filterFlags.NOT_CANCELABLE ~= nil then
            if e.filterFlags.NOT_CANCELABLE == true and e.filterFlags.CANCELABLE == nil then
                e.filterFlags.CANCELABLE = "exclude"
            end
            e.filterFlags.NOT_CANCELABLE = nil
        end
        if e.filterFlags.INCLUDE_NAME_PLATE_ONLY ~= nil then
            if e.filterFlags.INCLUDE_NAME_PLATE_ONLY == true and e.nameplateOnly == nil then
                e.nameplateOnly = true
            end
            e.filterFlags.INCLUDE_NAME_PLATE_ONLY = nil
        end
        if e.dispelFilterMode == nil then e.dispelFilterMode = "off" end
        if type(e.dispelTypes) ~= "table" and e.dispelTypes ~= "mine" then e.dispelTypes = {} end
        if type(e.maxDurationSec) ~= "number" then e.maxDurationSec = 0 end
        if e.filterMode == "classification" then e.filterMode = "classify" end
    elseif e.mode == "tracked" then
        if e.auraType == nil then e.auraType = "HELPFUL" end
        if type(e.border) ~= "table" then e.border = { thickness = 2 } end
        local trackedSpellIDs = {}
        if type(e.spells) == "table" then
            for i, spellID in ipairs(e.spells) do
                e.spells[i] = E.ResolveTrackedSpellID(spellID)
                if type(e.spells[i]) == "number" then
                    trackedSpellIDs[e.spells[i]] = true
                end
            end
        end
        if type(e.onlyMineSpells) == "table" then
            local normalizedOnlyMine = {}
            for spellID, value in pairs(e.onlyMineSpells) do
                normalizedOnlyMine[E.ResolveTrackedSpellID(spellID)] = value
            end
            e.onlyMineSpells = normalizedOnlyMine
        end
        if type(e.auraSounds) == "table" then
            local normalizedAuraSounds = {}
            for spellID, sounds in pairs(e.auraSounds) do
                local resolvedID = E.ResolveTrackedSpellID(tonumber(spellID) or spellID)
                if trackedSpellIDs[resolvedID] and type(sounds) == "table" then
                    normalizedAuraSounds[resolvedID] = sounds
                end
            end
            e.auraSounds = next(normalizedAuraSounds) and normalizedAuraSounds or nil
        end
    end
    if e.dispelBorderMode ~= "stealable" and e.dispelBorderMode ~= "all" then
        e.dispelBorderMode = "debuffs"
    end
    local dur = e.duration
    if type(dur) == "table" and type(dur.pandemicColor) == "table" then
        if e.pandemicGlow == nil then
            local c = dur.pandemicColor
            e.pandemicGlow = { color = { c[1] or 1, c[2] or 0.85, c[3] or 0.2, 1 } }
        end
        dur.pandemicColor = nil
    end
    if e.applyToRoles == nil then e.applyToRoles = "all" end
    return e
end

local ROLE_GATE_TO_ASSIGNED = { tank = "TANK", healer = "HEALER", dps = "DAMAGER" }
function E.ElementAppliesToRole(element, frameRole, isSelf)
    local gate = element and element.applyToRoles
    if gate == nil or gate == "all" then return true end
    if gate == "me" then return isSelf == true end
    local want = ROLE_GATE_TO_ASSIGNED[gate]
    if not want then return true end
    return frameRole == want
end

local WHAT_TO_SHOW_KEYS = {
    HELPFUL = { "all", "mine", "defensives", "important", "purgeable", "whitelist" },
    HARMFUL = { "all", "dispellable", "crowdControl", "important", "boss", "roleBoss", "whitelist" },
}

function E.WhatToShowKeys(auraType)
    return WHAT_TO_SHOW_KEYS[auraType] or WHAT_TO_SHOW_KEYS.HELPFUL
end

local function clearShowFields(e)
    e.filterMode = "off"
    e.filterFlags = {}
    e.classifications = defaultClassifications(e.auraType)
    e.onlyMine = false
    e.dispelFilterMode = "off"
    e.dispelTypes = {}
    e.gateStealable = nil
    e.gateBossAura = nil
    e.gatePriorityAura = nil
    e.gateRoleAura = nil
    e.gateBossOrRoleAura = nil
end

function E.ApplyWhatToShow(element, key)
    clearShowFields(element)
    if key == "mine" then
        element.onlyMine = true
    elseif key == "defensives" then
        element.filterMode = "classify"
        element.classifications = { bigDefensive = true, externalDefensive = true }
    elseif key == "important" then
        element.filterMode = "classify"
        element.classifications = { important = true }
    elseif key == "purgeable" then
        element.gateStealable = true
    elseif key == "dispellable" then
        element.filterMode = "classify"
        element.classifications = { dispellable = true }
    elseif key == "crowdControl" then
        element.filterMode = "classify"
        element.classifications = { crowdControl = true }
    elseif key == "boss" then
        element.gateBossAura = true
    elseif key == "roleBoss" then
        element.gateBossOrRoleAura = true
    elseif key == "whitelist" then
        element.filterMode = "whitelist"
    end
    return element
end

local function onlyClassKeys(tbl, wanted)
    local want = {}
    for _, k in ipairs(wanted) do want[k] = true; if tbl[k] ~= true then return false end end
    for k, v in pairs(tbl) do
        if v == true and not want[k] then return false end
    end
    return true
end

function E.DeriveWhatToShow(element)
    local mode = element.filterMode or "off"
    if mode == "whitelist" then return "whitelist" end
    if mode == "flags" then return "custom" end
    if mode == "classify" then
        local c = element.classifications or {}
        if onlyClassKeys(c, { "bigDefensive", "externalDefensive" }) then return "defensives" end
        if onlyClassKeys(c, { "important" }) then return "important" end
        if onlyClassKeys(c, { "crowdControl" }) then return "crowdControl" end
        if onlyClassKeys(c, { "dispellable" }) then return "dispellable" end
        return "custom"
    end
    if next(element.filterFlags or {}) ~= nil then return "custom" end
    if element.dispelFilterMode == "exclude" then return "custom" end
    if element.gatePriorityAura == true or element.gateRoleAura == true then return "custom" end
    local mods = {}
    if element.onlyMine == true then mods[#mods + 1] = "mine" end
    if element.gateStealable == true then mods[#mods + 1] = "purgeable" end
    if element.gateBossAura == true then mods[#mods + 1] = "boss" end
    if element.gateBossOrRoleAura == true then mods[#mods + 1] = "roleBoss" end
    if element.dispelFilterMode == "include" then mods[#mods + 1] = "dispellable" end
    if #mods == 0 then return "all" end
    if #mods == 1 then return mods[1] end
    return "custom"
end

local HELPFUL_ONLY_TOKENS = { RAID_IN_COMBAT = true }

local VALID_FILTER_TOKENS = {
    HELPFUL = true, HARMFUL = true, RAID = true, INCLUDE_NAME_PLATE_ONLY = true,
    PLAYER = true, CANCELABLE = true, MAW = true,
    EXTERNAL_DEFENSIVE = true, CROWD_CONTROL = true, RAID_IN_COMBAT = true,
    RAID_PLAYER_DISPELLABLE = true, BIG_DEFENSIVE = true,
    IMPORTANT = true, DISPELLABLE = true,
}
E.VALID_FILTER_TOKENS = VALID_FILTER_TOKENS

local NON_NEGATABLE_TOKENS = { INCLUDE_NAME_PLATE_ONLY = true, MAW = true }

local function IsKnownFilterString(filterString)
    if type(filterString) ~= "string" or filterString == "" then return false end
    local any = false
    for component in filterString:gmatch("[^| ]+") do
        any = true
        local negated = component:sub(1, 1) == "!"
        local tok = negated and component:sub(2) or component
        if tok == "" then return false end
        if not VALID_FILTER_TOKENS[tok] then return false end
    end
    return any
end
E.IsKnownFilterString = IsKnownFilterString

function E.CanonicalizeFilterString(filterString)
    if not IsKnownFilterString(filterString) then
        return filterString
    end
    local reqSeen, excSeen = {}, {}
    local req, exc = {}, {}
    local polarity
    for component in filterString:gmatch("[^| ]+") do
        local negated = component:sub(1, 1) == "!"
        local tok = (negated and component:sub(2) or component):upper()
        if negated then
            if not excSeen[tok] then excSeen[tok] = true; exc[#exc + 1] = tok end
        elseif (tok == "HELPFUL" or tok == "HARMFUL") and not polarity then
            polarity = tok
        elseif not reqSeen[tok] then
            reqSeen[tok] = true; req[#req + 1] = tok
        end
    end
    table.sort(req)
    table.sort(exc)
    local parts = {}
    if polarity then parts[#parts + 1] = polarity end
    for i = 1, #req do parts[#parts + 1] = req[i] end
    for i = 1, #exc do parts[#parts + 1] = "!" .. exc[i] end
    return table.concat(parts, "|")
end

local function AppendNameplateOnly(element, out)
    if not element.nameplateOnly then return out end
    for i = 1, #out do
        if not out[i]:find("INCLUDE_NAME_PLATE_ONLY", 1, true) then
            out[i] = out[i] .. "|INCLUDE_NAME_PLATE_ONLY"
        end
    end
    if #out == 0 then
        out[1] = (element.auraType or "HELPFUL") .. "|INCLUDE_NAME_PLATE_ONLY"
    end
    return out
end

local function HasFilterToken(filterString, want)
    for component in filterString:gmatch("[^| ]+") do
        if component == want then return true end
    end
    return false
end

-- onlyMine must ride the filter string, not just candidate filters: the
-- engine enforces PLAYER on secret (in-combat) aura data, while the Lua-side
-- isFromPlayerOrPlayerPet candidate filter cannot discriminate there.
local function AppendPlayerOnly(element, out)
    if element.onlyMine ~= true then return out end
    for i = 1, #out do
        if not HasFilterToken(out[i], "PLAYER") then
            out[i] = out[i] .. "|PLAYER"
        end
    end
    if #out == 0 then
        out[1] = (element.auraType or "HELPFUL") .. "|PLAYER"
    end
    return out
end

function E.CompileFilters(element)
    local out = {}
    if element.filterMode == "flags" then
        local flags = element.filterFlags or {}
        local harmful = (element.auraType == "HARMFUL")
        local req, exc = {}, {}
        for tok, v in pairs(flags) do
            if VALID_FILTER_TOKENS[tok] and not (harmful and HELPFUL_ONLY_TOKENS[tok]) then
                if v == true then
                    req[#req + 1] = tok
                elseif v == "exclude" and not NON_NEGATABLE_TOKENS[tok] then
                    exc[#exc + 1] = "!" .. tok
                end
            end
        end
        if #req > 0 or #exc > 0 then
            table.sort(req)
            table.sort(exc)
            local parts = { element.auraType or "HELPFUL" }
            for i = 1, #req do parts[#parts + 1] = req[i] end
            for i = 1, #exc do parts[#parts + 1] = exc[i] end
            out[1] = table.concat(parts, "|")
        end
        return AppendPlayerOnly(element, AppendNameplateOnly(element, out))
    end
    if element.filterMode ~= "classify" then return AppendPlayerOnly(element, AppendNameplateOnly(element, out)) end
    local harmful = (element.auraType == "HARMFUL")
    local map = harmful and DEBUFF_CLASSIFICATION_MAP or BUFF_CLASSIFICATION_MAP
    local priority = harmful and DEBUFF_CLASSIFICATION_PRIORITY or BUFF_CLASSIFICATION_PRIORITY
    local classifications = element.classifications or {}
    local seen = {}
    local handled = {}
    local requireAcc, excludeAcc = {}, {}
    for _, key in ipairs(priority) do
        handled[key] = true
        local comp = ClassificationComponent(map[key])
        if comp and IsClassificationEnabled(classifications, key) then
            local reqSeen, excSeen = {}, {}
            local req, exc = {}, {}
            local ownNegated = comp:sub(1, 1) == "!"
            local ownTok = ownNegated and comp:sub(2) or comp
            if ownNegated then
                excSeen[ownTok] = true; exc[#exc + 1] = ownTok
            else
                reqSeen[ownTok] = true; req[#req + 1] = ownTok
            end
            for tok in pairs(requireAcc) do
                if not reqSeen[tok] then reqSeen[tok] = true; req[#req + 1] = tok end
            end
            for tok in pairs(excludeAcc) do
                if not excSeen[tok] then excSeen[tok] = true; exc[#exc + 1] = tok end
            end
            local unsatisfiable = false
            for i = 1, #req do
                if excSeen[req[i]] then unsatisfiable = true; break end
            end
            if not unsatisfiable then
                table.sort(req)
                table.sort(exc)
                local parts = { element.auraType or "HELPFUL" }
                for i = 1, #req do parts[#parts + 1] = req[i] end
                for i = 1, #exc do parts[#parts + 1] = "!" .. exc[i] end
                local fs = table.concat(parts, "|")
                if not seen[fs] then seen[fs] = true; out[#out + 1] = fs end
            end

            local negTok, becomesRequired = NegateComponent(comp)
            if becomesRequired then
                requireAcc[negTok] = true
            else
                excludeAcc[negTok] = true
            end
        end
    end
    for key, entry in pairs(map) do
        if not handled[key] and IsClassificationEnabled(classifications, key) then
            if type(entry) == "table" then
                for _, fs in ipairs(entry) do
                    if not seen[fs] then seen[fs] = true; out[#out + 1] = fs end
                end
            else
                if not seen[entry] then seen[entry] = true; out[#out + 1] = entry end
            end
        end
    end
    return AppendPlayerOnly(element, AppendNameplateOnly(element, out))
end

function E.CompileCandidateFilters(element)
    local cf = nil
    local function ensure()
        if not cf then cf = {} end
        return cf
    end
    if element.onlyMine == true then
        ensure().isFromPlayerOrPlayerPet = true
    end
    local maxDur = tonumber(element.maxDurationSec) or 0
    if maxDur > 0 then
        ensure().maxDuration = maxDur
    elseif element.hidePermanent == true then
        ensure().maxDuration = 999999
    end
    if element.filterMode == "whitelist" and type(element.whitelist) == "table" and next(element.whitelist) then
        local inc = {}
        for sid, on in pairs(element.whitelist) do
            if on then inc[sid] = true end
        end
        if next(inc) then ensure().includeSpellIDs = inc end
    end
    if type(element.blacklist) == "table" and next(element.blacklist) then
        local exc = {}
        for sid, on in pairs(element.blacklist) do
            if on then exc[sid] = true end
        end
        if next(exc) then ensure().excludeSpellIDs = exc end
    end
    local dmode = element.dispelFilterMode
    if dmode == "include" or dmode == "exclude" then
        local types = element.dispelTypes
        if types == "mine" then
            local DR = ns and ns.QUI_DispelRoles
            local ok, mine = false, nil
            if DR and type(DR.PlayerDispelSchools) == "function" then
                ok, mine = pcall(DR.PlayerDispelSchools)
            end
            types = (ok and type(mine) == "table" and mine)
                or { Magic = true, Curse = true, Disease = true, Poison = true }
            if dmode == "include" and next(types) == nil then
                types = { ["QUI-none"] = true }
            end
        end
        if type(types) == "table" then
            local set = {}
            for name, on in pairs(types) do
                if on then set[name] = true end
            end
            if next(set) then
                if dmode == "include" then
                    ensure().includeDispelTypes = set
                else
                    ensure().excludeDispelTypes = set
                end
            end
        end
    end
    if element.gateStealable == true then ensure().isStealable = true end
    if element.gateBossAura == true then ensure().isBossAura = true end
    if element.gatePriorityAura == true then ensure().isPriorityAura = true end
    if element.gateRoleAura == true then ensure().isRoleAura = true end
    if element.gateBossOrRoleAura == true then ensure().isBossOrRoleAura = true end
    return cf
end

function E.EnsureSeeded(auras, defaultBucketFn)
    if type(auras) ~= "table" then return end

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

    if not auras._elementIDsBackfilled and type(auras.elements) == "table" then
        auras._elementIDsBackfilled = true
        local seen = {}
        for _, bucket in pairs(auras.elements) do
            if type(bucket) == "table" then
                for _, e in ipairs(bucket) do
                    local id = type(e) == "table" and e.id
                    if id ~= nil then
                        seen[id] = true
                        local n = type(id) == "string" and tonumber(id:match("^e(%d+)$"))
                        if n and n > idCounter then idCounter = n end
                    end
                end
            end
        end
        for _, bucket in pairs(auras.elements) do
            if type(bucket) == "table" then
                local inBucket = {}
                for _, e in ipairs(bucket) do
                    if type(e) == "table" then
                        if e.id == nil or inBucket[e.id] then
                            local newId = nextId()
                            while seen[newId] do newId = nextId() end
                            e.id = newId
                            seen[newId] = true
                        end
                        inBucket[e.id] = true
                    end
                end
            end
        end
    end

    if type(auras.elements) == "table" then
        for _, bucket in pairs(auras.elements) do
            if type(bucket) == "table" then
                for _, e in ipairs(bucket) do E.NormalizeElement(e) end
            end
        end
    end

    if auras.elementsSeeded then return end
    auras.elementsSeeded = true
    auras.elements = auras.elements or {}
    if auras.elements["*"] == nil then
        local bucket = defaultBucketFn and defaultBucketFn() or {}
        for _, e in ipairs(bucket) do E.NormalizeElement(e) end
        auras.elements["*"] = bucket
    end
end

function E.NormalizeSingleStripBucket(store, auraType)
    if type(store) ~= "table" or type(store.elements) ~= "table" then
        return false
    end
    local bucket = store.elements["*"]
    if type(bucket) ~= "table" then
        return false
    end
    local firstIndex
    for i = 1, #bucket do
        local e = bucket[i]
        if type(e) == "table" and e.mode == "filterStrip" then
            firstIndex = i
            break
        end
    end
    if not firstIndex then
        return false
    end
    local changed = false
    for i = #bucket, firstIndex + 1, -1 do
        local e = bucket[i]
        if type(e) == "table" and e.mode == "filterStrip" then
            table.remove(bucket, i)
            changed = true
        end
    end
    local strip = bucket[firstIndex]
    if auraType and strip.auraType ~= auraType then
        strip.auraType = auraType
        changed = true
    end
    if strip.enabled ~= true then
        strip.enabled = true
        changed = true
    end
    return changed
end

function E.ActiveElementsForSpec(auras, specID, out)
    if out then
        for i = #out, 1, -1 do out[i] = nil end
    else
        out = {}
    end
    local elements = auras and auras.elements
    if not elements then return out end
    local bucket
    if specID ~= nil and elements[specID] ~= nil then bucket = elements[specID]
    else bucket = elements["*"] end
    if bucket then
        for _, e in ipairs(bucket) do
            if e.enabled ~= false then out[#out + 1] = e end
        end
    end
    return out
end

function E.MaxBucketElementCount(auras)
    local elements = auras and auras.elements
    if type(elements) ~= "table" then return 0 end
    local max = 0
    for key, bucket in pairs(elements) do
        if (key == "*" or type(key) == "number")
            and type(bucket) == "table" and #bucket > max then
            max = #bucket
        end
    end
    return max
end

function E.HasSpecOverride(elements, bucketKey)
    return bucketKey ~= nil and bucketKey ~= "*"
        and type(elements) == "table" and elements[bucketKey] ~= nil
end

function E.EnableSpecOverride(auras, bucketKey)
    if type(auras) ~= "table" or bucketKey == nil or bucketKey == "*" then return end
    auras.elements = auras.elements or {}
    if auras.elements[bucketKey] ~= nil then return end
    local src = auras.elements["*"] or {}
    local copy = {}
    for _, e in ipairs(src) do
        local c = deepCopyTable(e)
        if type(c.id) ~= "string" or c.id:match("^e%d+$") then
            c.id = nextId()
        end
        copy[#copy + 1] = c
    end
    auras.elements[bucketKey] = copy
end

function E.DisableSpecOverride(auras, bucketKey)
    if type(auras) ~= "table" or bucketKey == nil or bucketKey == "*" then return end
    if type(auras.elements) == "table" then
        auras.elements[bucketKey] = nil
    end
end

return E
