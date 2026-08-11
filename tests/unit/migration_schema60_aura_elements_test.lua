-- tests/unit/migration_schema60_aura_elements_test.lua
-- Run: lua5.1 tests/unit/migration_schema60_aura_elements_test.lua
--
-- Schema-60 aura-surface unification via Migrations.SeedAuraElements.
--   * buffborders flat per-strip keys -> buffAuras/debuffAuras element stores.
--   * unit-frame flat per-strip keys  -> auras.elements element stores.
--   * group-frame already-element stores -> NormalizeElement in place.
--
-- The migration must reproduce the RESOLVED pre-migration render behavior (not
-- copy sentinels), heal the UF legacy classification master keys (helpful /
-- harmful) so CompileFilters still emits the pre-merge filter set, and prune
-- only the known migrated flat keys (frame-level survivors stay).
--
-- NOTE (deviation from the original task inventory, verified against the staged
-- Task 4 runtime): buffBorders.enableBuffs / enableDebuffs SURVIVE. The staged
-- QUI_ActionBars/actionbars/buffborders.lua reads settings.enableBuffs /
-- enableDebuffs as FRAME-LEVEL master gates (ApplyConfigPass / ManageBlizzard-
-- Frames), independent of per-element .enabled. Pruning them would banish the
-- Blizzard buff frame for a user who intentionally disabled QUI's takeover. The
-- migration seeds element.enabled FROM them but leaves the keys in place.

local ns = dofile("tools/_addon_env.lua").LoadCore()
local M  = ns.Migrations
local E  = ns.AuraElements

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function deepEqual(a, b, path)
    path = path or "<root>"
    if type(a) ~= type(b) then
        return false, path .. ": type " .. type(a) .. " vs " .. type(b)
    end
    if type(a) ~= "table" then
        if a ~= b then return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return true
    end
    for k, v in pairs(a) do
        local eq, why = deepEqual(v, b[k], path .. "." .. tostring(k))
        if not eq then return false, why end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing in first" end
    end
    return true
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = deepCopy(val) end
    return t
end

-- Compile parity: the engine treats the pipe set as UNORDERED, so compare the
-- sorted token lists, never the raw string.
local function sortedTokens(s)
    local t = {}
    for tok in tostring(s):gmatch("[^|]+") do t[#t + 1] = tok end
    table.sort(t)
    return table.concat(t, "|")
end
local function tokenSetEqual(a, b)
    return sortedTokens(a) == sortedTokens(b)
end
-- Set-equality over an ARRAY of filter strings (classify mode fans out several).
local function filterArraySetEqual(arr, expected)
    if type(arr) ~= "table" or #arr ~= #expected then return false end
    local bag = {}
    for _, s in ipairs(arr) do
        local key = sortedTokens(s)
        bag[key] = (bag[key] or 0) + 1
    end
    for _, s in ipairs(expected) do
        local key = sortedTokens(s)
        if not bag[key] or bag[key] == 0 then return false end
        bag[key] = bag[key] - 1
    end
    for _, n in pairs(bag) do if n ~= 0 then return false end end
    return true
end

local function findByType(bucket, auraType)
    if type(bucket) ~= "table" then return nil end
    for _, e in ipairs(bucket) do
        if type(e) == "table" and e.auraType == auraType then return e end
    end
    return nil
end

----------------------------------------------------------------------------
-- 1) buffborders seed: flat per-strip keys -> buffAuras/debuffAuras stores.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        buffBorders = {
            enableBuffs = true, buffIconSize = 30, buffIconsPerRow = 8, buffIconSpacing = 1,
            buffGrowLeft = false, buffGrowUp = true, buffSortRule = "EXPIRY", buffSortReverse = true,
            buffFilterPlayer = true, buffFilterNotCancelable = true,
            buffDurationTextAnchor = "BOTTOM", buffStackTextAnchor = "TOPLEFT",
            enableDebuffs = false, debuffIconSize = 28,
            iconSkin = "Default", borderSize = 1, fontSize = 12,
        },
    }
    M.RunOnProfile(profile)
    local bb = profile.buffBorders
    local buff = bb.buffAuras and bb.buffAuras.elements and bb.buffAuras.elements["*"]
        and bb.buffAuras.elements["*"][1]
    local debuff = bb.debuffAuras and bb.debuffAuras.elements and bb.debuffAuras.elements["*"]
        and bb.debuffAuras.elements["*"][1]

    check("BB buff element exists", type(buff) == "table", "no buff element")
    check("BB buff iconSize=30", buff and buff.iconSize == 30, buff and tostring(buff.iconSize))
    check("BB buff iconsPerRow=8", buff and buff.iconsPerRow == 8, buff and tostring(buff.iconsPerRow))
    check("BB buff spacing=1", buff and buff.spacing == 1, buff and tostring(buff.spacing))
    check("BB buff growDirection=RIGHT", buff and buff.growDirection == "RIGHT", buff and tostring(buff.growDirection))
    check("BB buff anchor=BOTTOMLEFT", buff and buff.anchor == "BOTTOMLEFT", buff and tostring(buff.anchor))
    check("BB buff sortRule=EXPIRY", buff and buff.sortRule == "EXPIRY", buff and tostring(buff.sortRule))
    check("BB buff sortReverse=true", buff and buff.sortReverse == true, buff and tostring(buff.sortReverse))
    check("BB buff enabled=true", buff and buff.enabled == true, buff and tostring(buff.enabled))
    check("BB buff filterMode=flags", buff and buff.filterMode == "flags", buff and tostring(buff.filterMode))
    check("BB buff filterFlags.PLAYER", buff and buff.filterFlags and buff.filterFlags.PLAYER == true, "no PLAYER")
    check("BB removed NOT_CANCELABLE -> !CANCELABLE", buff and buff.filterFlags
        and buff.filterFlags.CANCELABLE == "exclude", "legacy intent lost")
    check("BB buff duration.anchor=BOTTOM", buff and buff.duration and buff.duration.anchor == "BOTTOM", buff and buff.duration and tostring(buff.duration.anchor))
    check("BB buff stack.anchor=TOPLEFT", buff and buff.stack and buff.stack.anchor == "TOPLEFT", buff and buff.stack and tostring(buff.stack.anchor))
    check("BB buff rightClickCancel=true", buff and buff.rightClickCancel == true, buff and tostring(buff.rightClickCancel))
    check("BB buff id=buffs", buff and buff.id == "buffs", buff and tostring(buff.id))
    check("BB buffAuras.elementsSeeded", bb.buffAuras and bb.buffAuras.elementsSeeded == true, "not seeded")

    check("BB debuff element exists", type(debuff) == "table", "no debuff element")
    check("BB debuff enabled=false", debuff and debuff.enabled == false, debuff and tostring(debuff.enabled))
    check("BB debuff rightClickCancel=false", debuff and debuff.rightClickCancel == false, debuff and tostring(debuff.rightClickCancel))
    check("BB debuff iconSize=28", debuff and debuff.iconSize == 28, debuff and tostring(debuff.iconSize))
    check("BB debuffAuras.elementsSeeded", bb.debuffAuras and bb.debuffAuras.elementsSeeded == true, "not seeded")

    -- Migrated per-strip keys pruned.
    check("BB prune buffIconSize", bb.buffIconSize == nil, tostring(bb.buffIconSize))
    check("BB prune buffIconsPerRow", bb.buffIconsPerRow == nil, tostring(bb.buffIconsPerRow))
    check("BB prune buffIconSpacing", bb.buffIconSpacing == nil, tostring(bb.buffIconSpacing))
    check("BB prune buffGrowLeft", bb.buffGrowLeft == nil, tostring(bb.buffGrowLeft))
    check("BB prune buffGrowUp", bb.buffGrowUp == nil, tostring(bb.buffGrowUp))
    check("BB prune buffSortRule", bb.buffSortRule == nil, tostring(bb.buffSortRule))
    check("BB prune buffSortReverse", bb.buffSortReverse == nil, tostring(bb.buffSortReverse))
    check("BB prune buffFilterPlayer", bb.buffFilterPlayer == nil, tostring(bb.buffFilterPlayer))
    check("BB prune buffFilterNotCancelable", bb.buffFilterNotCancelable == nil,
        tostring(bb.buffFilterNotCancelable))
    check("BB prune buffDurationTextAnchor", bb.buffDurationTextAnchor == nil, tostring(bb.buffDurationTextAnchor))
    check("BB prune buffStackTextAnchor", bb.buffStackTextAnchor == nil, tostring(bb.buffStackTextAnchor))
    check("BB prune debuffIconSize", bb.debuffIconSize == nil, tostring(bb.debuffIconSize))

    -- Frame-level survivors.
    check("BB survive iconSkin", bb.iconSkin == "Default", tostring(bb.iconSkin))
    check("BB survive borderSize", bb.borderSize == 1, tostring(bb.borderSize))
    check("BB survive fontSize", bb.fontSize == 12, tostring(bb.fontSize))
    -- enableBuffs / enableDebuffs are FRAME-LEVEL gates in the staged runtime:
    -- they survive; element.enabled is seeded from them.
    check("BB survive enableBuffs=true", bb.enableBuffs == true, tostring(bb.enableBuffs))
    check("BB survive enableDebuffs=false", bb.enableDebuffs == false, tostring(bb.enableDebuffs))

    check("BB stamped to current (60)", profile._schemaVersion == 60, tostring(profile._schemaVersion))
end

----------------------------------------------------------------------------
-- 1b) buffborders EXPLICIT-sentinel resolution: iconSize PRESENT but <= 0 is
--     the explicit "use default" sentinel — HEAD BuildZoneProfile reset it to
--     DEFAULT_ICON_SIZE (30). perRow/spacing sentinels resolve to 10/2 (same
--     value as the absent path). Parity means reproducing the RESOLVED
--     render, never copying the 0.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        buffBorders = {
            enableBuffs = true, buffIconSize = 0, buffIconsPerRow = 0, buffIconSpacing = 0,
            enableDebuffs = true, debuffIconSize = 0, debuffIconsPerRow = 0, debuffIconSpacing = 0,
        },
    }
    M.RunOnProfile(profile)
    local buff = profile.buffBorders.buffAuras.elements["*"][1]
    local debuff = profile.buffBorders.debuffAuras.elements["*"][1]
    check("BB explicit-0 buff iconSize->30 (BuildZoneProfile reset)", buff.iconSize == 30, tostring(buff.iconSize))
    check("BB explicit-0 buff iconsPerRow->10", buff.iconsPerRow == 10, tostring(buff.iconsPerRow))
    check("BB explicit-0 buff spacing->2", buff.spacing == 2, tostring(buff.spacing))
    check("BB explicit-0 debuff iconSize->30", debuff.iconSize == 30, tostring(debuff.iconSize))
    check("BB explicit-0 debuff spacing->2", debuff.spacing == 2, tostring(debuff.spacing))
end

----------------------------------------------------------------------------
-- 1c) buffborders ABSENT-key resolution. Migrations.Run iterates RAW
--     db.sv.profiles and AceDB never persists unchanged defaults, so an
--     absent key means HEAD rendered the defaults.lua value: iconSize 35,
--     perRow 10, spacing 2, buffGrowLeft=true/GrowUp=false => grow LEFT from
--     a TOPRIGHT origin (the corner UpdateGrowAnchor pins), fontSize 12, and
--     the FIXED BUFF/DEBUFF_MAX_DISPLAY cap (40) — never the element-model
--     defaults (14 / RIGHT / TOPLEFT / 9 / 3).
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        buffBorders = { buffFilterPlayer = true },
    }
    M.RunOnProfile(profile)
    local buff = profile.buffBorders.buffAuras.elements["*"][1]
    local debuff = profile.buffBorders.debuffAuras.elements["*"][1]
    check("BB absent buff iconSize->35 (defaults.lua)", buff.iconSize == 35, tostring(buff.iconSize))
    check("BB absent buff iconsPerRow->10", buff.iconsPerRow == 10, tostring(buff.iconsPerRow))
    check("BB absent buff spacing->2", buff.spacing == 2, tostring(buff.spacing))
    check("BB absent buff growDirection->LEFT (buffGrowLeft default true)", buff.growDirection == "LEFT", tostring(buff.growDirection))
    check("BB absent buff anchor->TOPRIGHT (growLeft + no growUp)", buff.anchor == "TOPRIGHT", tostring(buff.anchor))
    check("BB absent buff maxIcons->40 (fixed BUFF_MAX_DISPLAY)", buff.maxIcons == 40, tostring(buff.maxIcons))
    check("BB absent buff duration.fontSize->12 (defaults.lua)", buff.duration.fontSize == 12, tostring(buff.duration.fontSize))
    check("BB absent buff enabled (enableBuffs default true)", buff.enabled == true, tostring(buff.enabled))
    check("BB absent buff filterFlags.PLAYER carried", buff.filterMode == "flags" and buff.filterFlags.PLAYER == true, tostring(buff.filterMode))
    check("BB absent debuff growDirection->LEFT", debuff.growDirection == "LEFT", tostring(debuff.growDirection))
    check("BB absent debuff anchor->TOPRIGHT", debuff.anchor == "TOPRIGHT", tostring(debuff.anchor))
    check("BB absent debuff iconSize->35", debuff.iconSize == 35, tostring(debuff.iconSize))
    check("BB absent debuff maxIcons->40", debuff.maxIcons == 40, tostring(debuff.maxIcons))
end

----------------------------------------------------------------------------
-- 2) unit-frame seed + legacy-master heal.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiUnitFrames = {
            player = {
                auras = {
                    showBuffs = true, buffIconSize = 24, buffAnchor = "TOPRIGHT", buffGrow = "LEFT",
                    buffMaxIcons = 6, buffMaxPerRow = 3, buffOffsetX = 5, buffOffsetY = -1, buffSpacing = 3,
                    buffFilterMode = "classification", buffClassifications = { cancelable = true },
                    showDebuffs = false, debuffIconSize = 20, debuffFilter = { PLAYER = true },
                    buffDuration = { show = true, fontSize = 10, anchor = "CENTER", offsetX = 0, offsetY = 0, color = { 1, 1, 1, 1 } },
                    portrait = nil,
                },
                portrait = { enabled = true },
            },
            target = {
                auras = {
                    showBuffs = false, buffIconSize = 18, buffAnchor = "BOTTOMLEFT", buffGrow = "RIGHT",
                    showDebuffs = true, iconSize = 26,
                },
            },
            focus = {
                auras = {
                    buffFilterMode = "classification", buffClassifications = { raid = true },
                    debuffFilterMode = "classification", debuffClassifications = { raidInCombat = true },
                },
            },
            pet = {
                auras = {
                    -- The REAL legacy UF filter shape is NESTED (HEAD's
                    -- BuildFilterString read { modifiers = {TOKEN=bool},
                    -- exclusive = "TOKEN"|nil }). The outer container keys must
                    -- NEVER leak into filterFlags as tokens — the old staged converter
                    -- did exactly that ("HARMFUL|modifiers" fails the
                    -- container's IsValidFilterString assert on 12.1).
                    showBuffs = true,
                    buffFilter = { modifiers = {
                        PLAYER = true, RAID = false, NOT_CANCELABLE = true,
                    } },
                    showDebuffs = true,
                    debuffFilter = { modifiers = { PLAYER = false, RAID = false } },
                },
            },
        },
    }
    M.RunOnProfile(profile)

    local pa = profile.quiUnitFrames.player.auras
    local pBuff = findByType(pa.elements and pa.elements["*"], "HELPFUL")
    local pDebuff = findByType(pa.elements and pa.elements["*"], "HARMFUL")

    check("UF player elementsSeeded", pa.elementsSeeded == true, "not seeded")
    check("UF player buff enabled=true", pBuff and pBuff.enabled == true, pBuff and tostring(pBuff.enabled))
    check("UF player buff iconSize=24", pBuff and pBuff.iconSize == 24, pBuff and tostring(pBuff.iconSize))
    check("UF player buff anchor=TOPRIGHT", pBuff and pBuff.anchor == "TOPRIGHT", pBuff and tostring(pBuff.anchor))
    check("UF player buff growDirection=LEFT", pBuff and pBuff.growDirection == "LEFT", pBuff and tostring(pBuff.growDirection))
    check("UF player buff maxIcons=6", pBuff and pBuff.maxIcons == 6, pBuff and tostring(pBuff.maxIcons))
    check("UF player buff iconsPerRow=3", pBuff and pBuff.iconsPerRow == 3, pBuff and tostring(pBuff.iconsPerRow))
    check("UF player buff offsetX=5", pBuff and pBuff.offsetX == 5, pBuff and tostring(pBuff.offsetX))
    check("UF player buff filterMode=classify", pBuff and pBuff.filterMode == "classify", pBuff and tostring(pBuff.filterMode))
    check("UF player buff classifications.cancelable", pBuff and pBuff.classifications and pBuff.classifications.cancelable == true, "no cancelable")
    check("UF player buff duration.fontSize=10", pBuff and pBuff.duration and pBuff.duration.fontSize == 10, pBuff and pBuff.duration and tostring(pBuff.duration.fontSize))

    check("UF player debuff enabled=false", pDebuff and pDebuff.enabled == false, pDebuff and tostring(pDebuff.enabled))
    check("UF player debuff iconSize=20", pDebuff and pDebuff.iconSize == 20, pDebuff and tostring(pDebuff.iconSize))
    check("UF player debuff filterMode=flags", pDebuff and pDebuff.filterMode == "flags", pDebuff and tostring(pDebuff.filterMode))
    check("UF player debuff filterFlags.PLAYER", pDebuff and pDebuff.filterFlags and pDebuff.filterFlags.PLAYER == true, "no PLAYER")

    check("UF player prune buffIconSize", pa.buffIconSize == nil, tostring(pa.buffIconSize))
    check("UF player prune showBuffs", pa.showBuffs == nil, tostring(pa.showBuffs))
    check("UF player prune debuffFilter", pa.debuffFilter == nil, tostring(pa.debuffFilter))
    check("UF player prune buffClassifications", pa.buffClassifications == nil, tostring(pa.buffClassifications))
    check("UF player prune buffDuration", pa.buffDuration == nil, tostring(pa.buffDuration))
    check("UF player sibling portrait survives", profile.quiUnitFrames.player.portrait
        and profile.quiUnitFrames.player.portrait.enabled == true, "portrait clobbered")

    -- Same treatment for a seeded target unit.
    local ta = profile.quiUnitFrames.target.auras
    local tDebuff = findByType(ta.elements and ta.elements["*"], "HARMFUL")
    check("UF target elementsSeeded", ta.elementsSeeded == true, "not seeded")
    check("UF target debuff size uses iconSize fallback=26", tDebuff and tDebuff.iconSize == 26, tDebuff and tostring(tDebuff.iconSize))
    check("UF target prune iconSize", ta.iconSize == nil, tostring(ta.iconSize))
    check("UF target prune showDebuffs", ta.showDebuffs == nil, tostring(ta.showDebuffs))

    -- Legacy-master heal: focus buff {raid=true} must stamp helpful=true so the
    -- classify fan-out still emits BOTH HELPFUL|RAID and HELPFUL|RAID_IN_COMBAT
    -- (pre-merge UF fallback parity).
    local fa = profile.quiUnitFrames.focus.auras
    local fBuff = findByType(fa.elements and fa.elements["*"], "HELPFUL")
    local fDebuff = findByType(fa.elements and fa.elements["*"], "HARMFUL")
    check("UF focus buff classifications.helpful stamped", fBuff and fBuff.classifications and fBuff.classifications.helpful == true,
        fBuff and fBuff.classifications and tostring(fBuff.classifications.helpful))
    check("UF focus buff classifications.raid preserved", fBuff and fBuff.classifications and fBuff.classifications.raid == true, "raid lost")
    check("UF focus buff compile == {HELPFUL|RAID, HELPFUL|RAID_IN_COMBAT}",
        fBuff and filterArraySetEqual(E.CompileFilters(fBuff), { "HELPFUL|RAID", "HELPFUL|RAID_IN_COMBAT" }),
        fBuff and table.concat(E.CompileFilters(fBuff), " , "))
    -- Harmful heal: focus debuff {raidInCombat=true} must stamp harmful=true
    -- (else it degrades to bare-polarity show-everything).
    check("UF focus debuff classifications.harmful stamped", fDebuff and fDebuff.classifications and fDebuff.classifications.harmful == true,
        fDebuff and fDebuff.classifications and tostring(fDebuff.classifications.harmful))
    check("UF focus debuff compile == {HARMFUL|RAID}",
        fDebuff and filterArraySetEqual(E.CompileFilters(fDebuff), { "HARMFUL|RAID" }),
        fDebuff and table.concat(E.CompileFilters(fDebuff), " , "))

    -- Nested legacy filter shape: enabled modifiers + exclusive become flags
    -- tokens; the outer "modifiers"/"exclusive" container keys never leak.
    local peta = profile.quiUnitFrames.pet.auras
    local petBuff = findByType(peta.elements and peta.elements["*"], "HELPFUL")
    local petDebuff = findByType(peta.elements and peta.elements["*"], "HARMFUL")
    check("UF pet buff nested filter -> filterMode=flags", petBuff and petBuff.filterMode == "flags",
        petBuff and tostring(petBuff.filterMode))
    check("UF pet buff filterFlags == {PLAYER, !CANCELABLE}", petBuff and petBuff.filterFlags
        and deepEqual(petBuff.filterFlags, { PLAYER = true, CANCELABLE = "exclude" }),
        petBuff and petBuff.filterFlags and table.concat((function()
            local t = {} for k in pairs(petBuff.filterFlags) do t[#t + 1] = k end
            table.sort(t) return t
        end)(), ","))
    check("UF pet buff no literal 'modifiers' token", petBuff and petBuff.filterFlags
        and petBuff.filterFlags.modifiers == nil, "modifiers leaked")
    check("UF pet buff no literal 'exclusive' token", petBuff and petBuff.filterFlags
        and petBuff.filterFlags.exclusive == nil, "exclusive leaked")
    -- All-false nested modifiers = no enabled token: stays at the element
    -- default filterMode ("off", bare polarity) — never an empty flags mode.
    check("UF pet debuff all-false nested filter stays off", petDebuff and petDebuff.filterMode == "off",
        petDebuff and tostring(petDebuff.filterMode))
    check("UF pet debuff compiles to empty (bare polarity fallback)",
        petDebuff and #E.CompileFilters(petDebuff) == 0,
        petDebuff and table.concat(E.CompileFilters(petDebuff), " , "))

    check("UF stamped to current (60)", profile._schemaVersion == 60, tostring(profile._schemaVersion))
end

----------------------------------------------------------------------------
-- 2b) UF ABSENT-key resolution: raw SavedVariables omit unchanged defaults,
--     so absent geometry must resolve to the HEAD defaults.lua values for
--     THAT unit (per-unit auras blocks), never the element-model defaults
--     (iconSize 14, maxIcons 3). Exact HEAD values: player buff/debuff 22/4;
--     boss 22/4; focus 20/16 with offsetY -2 (buff) / 2 (debuff); duration
--     sub-tables: buff show/fs12, debuff hidden/fs10; stack fs10.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiUnitFrames = {
            player = { auras = { showBuffs = true } },
            boss   = { auras = { showDebuffs = true } },
            focus  = { auras = { showDebuffs = true } },
        },
    }
    M.RunOnProfile(profile)

    local pa = profile.quiUnitFrames.player.auras
    local pBuff = findByType(pa.elements["*"], "HELPFUL")
    local pDebuff = findByType(pa.elements["*"], "HARMFUL")
    check("UF absent player buff iconSize->22", pBuff.iconSize == 22, tostring(pBuff.iconSize))
    check("UF absent player buff maxIcons->4", pBuff.maxIcons == 4, tostring(pBuff.maxIcons))
    check("UF absent player buff anchor->BOTTOMLEFT", pBuff.anchor == "BOTTOMLEFT", tostring(pBuff.anchor))
    check("UF absent player buff grow->RIGHT", pBuff.growDirection == "RIGHT", tostring(pBuff.growDirection))
    check("UF absent player buff spacing->2", pBuff.spacing == 2, tostring(pBuff.spacing))
    check("UF absent player buff offsetY->0", pBuff.offsetY == 0, tostring(pBuff.offsetY))
    check("UF absent player buff iconsPerRow->0", pBuff.iconsPerRow == 0, tostring(pBuff.iconsPerRow))
    check("UF absent player buff duration show/fs12", pBuff.duration.show == true and pBuff.duration.fontSize == 12,
        tostring(pBuff.duration.show) .. "/" .. tostring(pBuff.duration.fontSize))
    check("UF absent player buff stack fs10", pBuff.stack.show == true and pBuff.stack.fontSize == 10,
        tostring(pBuff.stack.fontSize))
    check("UF absent player debuff iconSize->22", pDebuff.iconSize == 22, tostring(pDebuff.iconSize))
    check("UF absent player debuff maxIcons->4", pDebuff.maxIcons == 4, tostring(pDebuff.maxIcons))
    check("UF absent player debuff duration hidden/fs10", pDebuff.duration.show == false and pDebuff.duration.fontSize == 10,
        tostring(pDebuff.duration.show) .. "/" .. tostring(pDebuff.duration.fontSize))

    local ba = profile.quiUnitFrames.boss.auras
    local bDebuff = findByType(ba.elements["*"], "HARMFUL")
    check("UF absent boss debuff iconSize->22", bDebuff.iconSize == 22, tostring(bDebuff.iconSize))
    check("UF absent boss debuff maxIcons->4", bDebuff.maxIcons == 4, tostring(bDebuff.maxIcons))
    check("UF absent boss debuff offsetY->0", bDebuff.offsetY == 0, tostring(bDebuff.offsetY))
    check("UF absent boss debuff anchor->TOPLEFT", bDebuff.anchor == "TOPLEFT", tostring(bDebuff.anchor))

    local fa = profile.quiUnitFrames.focus.auras
    local fBuff = findByType(fa.elements["*"], "HELPFUL")
    local fDebuff = findByType(fa.elements["*"], "HARMFUL")
    check("UF absent focus debuff iconSize->20", fDebuff.iconSize == 20, tostring(fDebuff.iconSize))
    check("UF absent focus debuff maxIcons->16", fDebuff.maxIcons == 16, tostring(fDebuff.maxIcons))
    check("UF absent focus debuff offsetY->2", fDebuff.offsetY == 2, tostring(fDebuff.offsetY))
    check("UF absent focus buff iconSize->20", fBuff.iconSize == 20, tostring(fBuff.iconSize))
    check("UF absent focus buff maxIcons->16", fBuff.maxIcons == 16, tostring(fBuff.maxIcons))
    check("UF absent focus buff offsetY->-2", fBuff.offsetY == -2, tostring(fBuff.offsetY))
end

----------------------------------------------------------------------------
-- 2c) UF orphan prefixed duration scalars (buffDurationSize etc.) were
--     PREVIEW-only at HEAD, never live-rendered: prune, don't map — the
--     seeded duration sub-table must NOT pick their values up.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiUnitFrames = {
            player = {
                auras = {
                    showBuffs = true,
                    buffShowDuration = true, buffDurationSize = 14, buffDurationAnchor = "TOP",
                    buffDurationOffsetX = 7, buffDurationOffsetY = -7, buffDurationColor = { 1, 0, 0, 1 },
                    debuffShowDuration = true, debuffDurationSize = 15, debuffDurationAnchor = "BOTTOM",
                    debuffDurationOffsetX = 8, debuffDurationOffsetY = -8, debuffDurationColor = { 0, 1, 0, 1 },
                },
            },
        },
    }
    M.RunOnProfile(profile)
    local a = profile.quiUnitFrames.player.auras
    for _, k in ipairs({
        "buffShowDuration", "buffDurationSize", "buffDurationAnchor",
        "buffDurationOffsetX", "buffDurationOffsetY", "buffDurationColor",
        "debuffShowDuration", "debuffDurationSize", "debuffDurationAnchor",
        "debuffDurationOffsetX", "debuffDurationOffsetY", "debuffDurationColor",
    }) do
        check("UF orphan scalar pruned: " .. k, a[k] == nil, tostring(a[k]))
    end
    local buff = findByType(a.elements["*"], "HELPFUL")
    check("UF orphan scalars NOT mapped (duration keeps defaults fs12/CENTER)",
        buff.duration.fontSize == 12 and buff.duration.anchor == "CENTER" and buff.duration.offsetX == 0,
        tostring(buff.duration.fontSize) .. "/" .. tostring(buff.duration.anchor))
end

----------------------------------------------------------------------------
-- 3) group-frame normalize-in-place: already element-shaped; NormalizeElement
--    folds the flat duration fields, stamps new fields, leaves the store flag +
--    classifications untouched (GF's HEAD map used split keys, no master heal).
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiGroupFrames = {
            party = {
                auras = {
                    elementsSeeded = true,
                    elements = {
                        ["*"] = {
                            {
                                id = "debuffs", mode = "filterStrip", auraType = "HARMFUL", enabled = true,
                                showDurationText = true, durationFontSize = 9, durationAnchor = "BOTTOM",
                                durationOffsetY = -6, durationColor = { 1, 1, 1, 1 },
                                durationUseTimeColor = true, showExpiringPulse = true,
                                classifications = { raid = true },
                            },
                        },
                    },
                },
            },
        },
    }
    M.RunOnProfile(profile)
    local e = profile.quiGroupFrames.party.auras.elements["*"][1]
    check("GF duration.anchor=BOTTOM", e.duration and e.duration.anchor == "BOTTOM", e.duration and tostring(e.duration.anchor))
    check("GF duration.offsetY=-6", e.duration and e.duration.offsetY == -6, e.duration and tostring(e.duration.offsetY))
    check("GF flat durationAnchor pruned", e.durationAnchor == nil, tostring(e.durationAnchor))
    check("GF flat durationUseTimeColor pruned", e.durationUseTimeColor == nil, tostring(e.durationUseTimeColor))
    check("GF flat showExpiringPulse pruned", e.showExpiringPulse == nil, tostring(e.showExpiringPulse))
    check("GF sortRule stamped INDEX", e.sortRule == "INDEX", tostring(e.sortRule))
    check("GF rightClickCancel stamped true", e.rightClickCancel == true, tostring(e.rightClickCancel))
    check("GF filterFlags table present", type(e.filterFlags) == "table", type(e.filterFlags))
    check("GF elementsSeeded still true", profile.quiGroupFrames.party.auras.elementsSeeded == true, "flag lost")
    check("GF classifications untouched (raid only)", e.classifications and e.classifications.raid == true
        and e.classifications.helpful == nil and e.classifications.harmful == nil, "classifications mutated")
    check("GF stamped to current (60)", profile._schemaVersion == 60, tostring(profile._schemaVersion))
end

----------------------------------------------------------------------------
-- 4) compile-equivalence parity (the hard gate). Set-equality over pipe tokens.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        buffBorders = {
            enableBuffs = true, buffFilterPlayer = true, buffFilterCancelable = true,
        },
        quiUnitFrames = {
            player = {
                auras = {
                    showDebuffs = true, debuffFilter = { PLAYER = true },
                    showBuffs = true, buffFilterMode = "classification", buffClassifications = { cancelable = true },
                },
            },
        },
    }
    M.RunOnProfile(profile)
    local buff = profile.buffBorders.buffAuras.elements["*"][1]
    local bbCompiled = E.CompileFilters(buff)
    check("compile BB buff == HELPFUL|CANCELABLE|PLAYER (set)",
        bbCompiled[1] and tokenSetEqual(bbCompiled[1], "HELPFUL|CANCELABLE|PLAYER"),
        tostring(bbCompiled[1]))

    local pa = profile.quiUnitFrames.player.auras
    local pDebuff = findByType(pa.elements["*"], "HARMFUL")
    local pBuff = findByType(pa.elements["*"], "HELPFUL")
    check("compile UF debuff == HARMFUL|PLAYER (set)",
        filterArraySetEqual(E.CompileFilters(pDebuff), { "HARMFUL|PLAYER" }),
        table.concat(E.CompileFilters(pDebuff), " , "))
    check("compile UF buff classify == {HELPFUL|CANCELABLE}",
        filterArraySetEqual(E.CompileFilters(pBuff), { "HELPFUL|CANCELABLE" }),
        table.concat(E.CompileFilters(pBuff), " , "))
end

----------------------------------------------------------------------------
-- 5) idempotency: re-running the migration (version gate) AND a direct second
--    SeedAuraElements call (elementsSeeded short-circuit) must be no-ops.
----------------------------------------------------------------------------
do
    local input = {
        _schemaVersion = 47,
        buffBorders = {
            enableBuffs = true, buffIconSize = 30, buffIconsPerRow = 8, buffIconSpacing = 1,
            buffGrowLeft = false, buffGrowUp = true, buffSortRule = "EXPIRY", buffSortReverse = true,
            buffFilterPlayer = true, buffFilterCancelable = true,
            enableDebuffs = false, debuffIconSize = 28,
        },
    }
    local profile = deepCopy(input)
    M.RunOnProfile(profile)
    local snapshotBuff = deepCopy(profile.buffBorders.buffAuras)
    local snapshotDebuff = deepCopy(profile.buffBorders.debuffAuras)
    -- Second RunOnProfile (stored now 60 -> version gate returns early).
    M.RunOnProfile(profile)
    -- Direct SeedAuraElements call (bypasses the version gate; must hit the
    -- elementsSeeded short-circuit and change nothing).
    M.SeedAuraElements(profile)
    local eqB, whyB = deepEqual(snapshotBuff, profile.buffBorders.buffAuras, "buffAuras")
    local eqD, whyD = deepEqual(snapshotDebuff, profile.buffBorders.debuffAuras, "debuffAuras")
    check("idempotent buffAuras tree", eqB, whyB)
    check("idempotent debuffAuras tree", eqD, whyD)
    check("idempotent stays at current (60)", profile._schemaVersion == 60, tostring(profile._schemaVersion))
end

-- F5 (re-review): "Hide Duration Swipe" was a real HEAD checkbox writing the
-- per-zone prefixed key (buffHideSwipe/debuffHideSwipe) with a shared
-- a.hideSwipe fallback — it must MAP to element.hideSwipe, not prune-only
-- (element default false would silently re-enable the swipe).
do
    local profile = {
        _schemaVersion = 47,
        quiUnitFrames = {
            player = { auras = { showBuffs = true, buffHideSwipe = true } },
            target = { auras = { showDebuffs = true, hideSwipe = true } },      -- shared fallback
            focus  = { auras = { showBuffs = true } },                           -- neither set
        },
    }
    M.RunOnProfile(profile)
    local function elem(unit, id)
        for _, e in ipairs(profile.quiUnitFrames[unit].auras.elements["*"]) do
            if e.id == id then return e end
        end
    end
    check("F5: buffHideSwipe=true maps to buff element.hideSwipe", elem("player", "buffs").hideSwipe == true)
    check("F5: player debuff (unset) stays false", elem("player", "debuffs").hideSwipe == false)
    check("F5: shared a.hideSwipe fallback maps to both zones",
        elem("target", "debuffs").hideSwipe == true and elem("target", "buffs").hideSwipe == true)
    check("F5: neither set → false", elem("focus", "buffs").hideSwipe == false)
    check("F5: prefixed key still pruned after mapping", profile.quiUnitFrames.player.auras.buffHideSwipe == nil
        and profile.quiUnitFrames.target.auras.hideSwipe == nil)
end

print("migration_schema60_aura_elements_test " .. (failures == 0 and "OK" or "FAILED"))
os.exit(failures == 0 and 0 or 1)
