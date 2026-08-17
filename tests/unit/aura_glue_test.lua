-- tests/unit/aura_glue_test.lua
-- Run: lua5.1 tests/unit/aura_glue_test.lua
_G.AuraContainerSortMethod = { Default = 0, BigDefensive = 1, UnitFrameDebuff = 2,
    ImportantOnly = 3, Expiration = 4, ExpirationOnly = 5, Name = 6, NameOnly = 7,
    AuraInstanceIDOnly = 8 }
_G.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
local ns = dofile("tools/_addon_env.lua").LoadCore()
local G = ns.AuraGlue
local E = ns.AuraElements

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

-- ElementProfile -----------------------------------------------------------
do
    local e = E.NewFilterStripElement("HARMFUL")   -- anchor BOTTOMRIGHT, grow LEFT
    e.iconSize = 20; e.spacing = 3; e.maxIcons = 5; e.iconsPerRow = 4
    local p = G.ElementProfile(e)
    check("profile: layout fields map", p.iconSize == 20 and p.spacing == 3
        and p.maxIcons == 5 and p.maxPerRow == 4 and p.grow == "LEFT" and p.anchor == "BOTTOMRIGHT")
    check("profile: BOTTOM anchor wraps UP", p.wrap == "UP")
    check("profile: offsets folded", p.offsetX == e.offsetX and p.offsetY == e.offsetY)
    check("profile: duration/stack passed through", p.duration == e.duration and p.stack == e.stack)
    check("profile: swipe fields", p.hideSwipe == false and p.reverseSwipe == false)

    local top = E.NewFilterStripElement("HELPFUL") -- anchor TOPLEFT
    check("profile: TOP anchor wraps DOWN", G.ElementProfile(top).wrap == "DOWN")

    local zero = E.NewFilterStripElement("HELPFUL")
    zero.maxIcons = 0
    check("profile: maxIcons 0 (unlimited) → 40 cap for the engine", G.ElementProfile(zero).maxIcons == 40)

    local tracked = E.NewTrackedElement({ 101, 102 }, "icon")
    tracked.maxIcons = 0
    check("tracked profile: maxIcons follows the spell count",
        G.ElementProfile(tracked).maxIcons == 2)
    tracked.maxIcons = 1
    check("tracked profile: old saved maxIcons cannot truncate spells",
        G.ElementProfile(tracked).maxIcons == 2)

    local o = G.ElementProfile(top, { attachPoint = "BOTTOMLEFT", wrap = "UP", offsetX = 7 })
    check("profile: overrides win", o.attachPoint == "BOTTOMLEFT" and o.wrap == "UP" and o.offsetX == 7)
end

-- ElementGroups ------------------------------------------------------------
do
    local e = E.NewFilterStripElement("HELPFUL")
    e.filterMode = "classify"
    -- `helpful = false` explicitly disables the legacy flat-toggle fallback in
    -- E.CompileFilters' IsClassificationEnabled (aura_elements.lua): with it
    -- absent, an unset "helpful" key falls back to `raid or raidInCombat`,
    -- which would fold in HELPFUL|RAID_IN_COMBAT any time raid=true even
    -- though raidInCombat is off — surfacing a THIRD filter here. Setting it
    -- false isolates the two classifications this test actually exercises.
    e.classifications = { helpful = false, raid = true, cancelable = true }
    e.sortRule = "EXPIRY"; e.sortReverse = true
    local p = G.ElementProfile(e)
    local groups = G.ElementGroups("player", e, p, true)
    check("groups: one per compiled filter", #groups == 2)
    local filters = {}
    for _, g in ipairs(groups) do filters[g.filter] = g end
    -- Wave 4 Task 2b: raid outranks cancelable in the fixed priority order, so
    -- cancelable's compiled (and canonicalized) string embeds a !RAID
    -- negation to stay exclusive against the higher-priority raid group.
    check("groups: filters carried (cancelable embeds the raid exclusivity negation)",
        filters["HELPFUL|RAID"] ~= nil and filters["HELPFUL|CANCELABLE|!RAID"] ~= nil)
    check("groups: sort translated per element", groups[1].sortMethod == 4
        and groups[1].sortDirection == 1)
    check("groups: cancel on eligible HELPFUL", groups[1].cancelButtons == "RightButtonUp")
    check("groups: maxFrameCount from profile", groups[1].maxFrameCount == p.maxIcons)
    check("groups: keys are pipe-free + unique", groups[1].key ~= groups[2].key
        and not groups[1].key:find("|", 1, true))

    e.rightClickCancel = false
    check("groups: per-element cancel opt-out", G.ElementGroups("player", e, p, true)[1].cancelButtons == nil)

    local d = E.NewFilterStripElement("HARMFUL")
    local dp = G.ElementProfile(d)
    local dgroups = G.ElementGroups("player", d, dp, true)
    check("groups: off mode falls back to bare polarity", #dgroups == 1 and dgroups[1].filter == "HARMFUL")
    check("groups: no cancel on HARMFUL even when eligible", dgroups[1].cancelButtons == nil)

    local w = E.NewFilterStripElement("HELPFUL")
    w.filterMode = "whitelist"; w.whitelist = { [17] = true }
    local wgroups = G.ElementGroups("player", w, G.ElementProfile(w), false)
    check("groups: whitelist mode = bare polarity + includeSpellIDs candidates",
        wgroups[1].filter == "HELPFUL" and wgroups[1].candidateFilters
        and wgroups[1].candidateFilters.includeSpellIDs[17] == true)
    check("groups: ineligible host never cancels", wgroups[1].cancelButtons == nil)
end

-- SORT_TRANSLATIONS coverage -------------------------------------------------
do
    for rule, want in pairs({ INDEX = 8, DEFAULT = 0, EXPIRY = 4, EXPIRY_ONLY = 5,
                              NAME = 6, NAME_ONLY = 7, BIG_DEFENSIVE = 1 }) do
        local e = E.NewFilterStripElement("HELPFUL")
        e.sortRule = rule
        local g = G.ElementGroups("player", e, G.ElementProfile(e), false)
        check("sort: " .. rule, g[1].sortMethod == want, tostring(g[1].sortMethod))
    end
end

-- Filter expansion: new sort methods ---------------------------------------
do
    local e = E.NewFilterStripElement("HELPFUL")
    e.sortRule = "IMPORTANT_ONLY"
    local groups = G.ElementGroups("player", e, G.ElementProfile(e), false)
    check("sort: IMPORTANT_ONLY maps to ImportantOnly",
        groups[1].sortMethod == _G.AuraContainerSortMethod.ImportantOnly)
    e.sortRule = "UF_DEBUFF"
    groups = G.ElementGroups("player", e, G.ElementProfile(e), false)
    check("sort: UF_DEBUFF maps to UnitFrameDebuff",
        groups[1].sortMethod == _G.AuraContainerSortMethod.UnitFrameDebuff)
end

-- FilterStringUsable: restriction-aware probe (review blocker 1) ------------
-- GetUnitAuras is RequiresUnitAuraAccess-guarded (FailureMode=Error); under
-- encounter/M+/PvP restrictions the probe throws for EVERY string. That must
-- never be read as "invalid filter" (it retired live classified groups and
-- broadened their fallbacks to bare polarity mid-pull). Contract:
--   1. AuraUtil.IsValidFilterString rejection always wins.
--   2. Unrestricted probe verdicts are cached per string.
--   3. Restricted + cached  -> cached verdict, probe not re-run.
--   4. Restricted + uncached -> fail OPEN (string already passed Lua check).
do
    local restricted = false
    local calls = 0
    _G.C_UnitAuras = { GetUnitAuras = function(_, filter)
        calls = calls + 1
        if restricted then error("Unit aura access denied") end
        if filter == "BOGUS_COMBO" then error("invalid filter combo") end
        return {}
    end }
    _G.AuraUtil = { IsValidFilterString = function(s) return s ~= "LUA_REJECT" end }
    _G.C_Secrets = { ShouldAurasBeSecret = function() return restricted end }

    check("probe: lua-side reject wins", G.FilterStringUsable("player", "LUA_REJECT") == false)
    check("probe: valid string accepted", G.FilterStringUsable("player", "HELPFUL") == true)
    local before = calls
    check("probe: verdict cached (no second C call)",
        G.FilterStringUsable("player", "HELPFUL") == true and calls == before, tostring(calls - before))
    check("probe: invalid combo rejected + cached", G.FilterStringUsable("player", "BOGUS_COMBO") == false)

    restricted = true
    check("probe: restricted + cached true stays true", G.FilterStringUsable("player", "HELPFUL") == true)
    check("probe: restricted + cached false stays false", G.FilterStringUsable("player", "BOGUS_COMBO") == false)
    before = calls
    check("probe: restricted + uncached fails OPEN, no C call",
        G.FilterStringUsable("player", "HELPFUL|RAID") == true and calls == before, tostring(calls - before))
    restricted = false

    _G.C_UnitAuras = nil
    _G.AuraUtil = nil
    _G.C_Secrets = nil
end

-- FilterStringUsable failure attribution (2026-07 re-review): a transient
-- probe failure (e.g. a restriction racing in after the gate check) must not
-- cache false — the restricted branch trusts cached verdicts, so a poisoned
-- false would retire a valid group for the whole encounter. The baseline
-- re-probe discriminates: baseline also fails = environment (fail OPEN,
-- uncached); baseline passes = deterministic C-parser rejection (cache it).
do
    local raceActive = false
    local restricted = false
    local calls = 0
    _G.C_UnitAuras = { GetUnitAuras = function(_, filter)
        calls = calls + 1
        if raceActive then error("Unit aura access denied") end
        if filter == "BOGUS_COMBO_2" then error("invalid filter combo") end
        return {}
    end }
    _G.AuraUtil = { IsValidFilterString = function() return true end }
    _G.C_Secrets = { ShouldAurasBeSecret = function() return restricted end }

    -- Transient environment failure: string AND baseline both fail.
    raceActive = true
    check("attribution: transient failure fails OPEN",
        G.FilterStringUsable("player", "HELPFUL|RAID2") == true)

    -- The reviewer's exact scenario: restriction begins before the next
    -- unrestricted probe. Uncached -> restricted branch fails OPEN too.
    restricted = true
    local before = calls
    check("attribution: restricted after transient failure stays OPEN (no poisoned cache)",
        G.FilterStringUsable("player", "HELPFUL|RAID2") == true and calls == before,
        tostring(calls - before))
    restricted = false

    -- Environment recovers: the string re-probes (nothing was cached) and is
    -- accepted permanently.
    raceActive = false
    before = calls
    check("attribution: clean re-probe after recovery accepts",
        G.FilterStringUsable("player", "HELPFUL|RAID2") == true and calls > before)

    -- String-specific rejection: baseline passes, string fails on the retry
    -- too -> cached (deterministic C-parser verdict).
    check("attribution: string-specific rejection still caches false",
        G.FilterStringUsable("player", "BOGUS_COMBO_2") == false)
    restricted = true
    check("attribution: cached rejection honored under restriction",
        G.FilterStringUsable("player", "BOGUS_COMBO_2") == false)
    restricted = false

    -- One-shot candidate failure (restriction window closing between the
    -- candidate probe and the baseline): baseline passes AND the retry
    -- passes -> accepted + cached true, NOT poisoned false (2026-07
    -- re-review round 2).
    local failOnce = true
    _G.C_UnitAuras = { GetUnitAuras = function(_, filter)
        calls = calls + 1
        if filter == "HELPFUL|RAID3" and failOnce then
            failOnce = false
            error("Unit aura access denied")
        end
        return {}
    end }
    check("attribution: one-shot failure recovered by retry",
        G.FilterStringUsable("player", "HELPFUL|RAID3") == true)
    restricted = true
    check("attribution: recovered verdict cached true under restriction",
        G.FilterStringUsable("player", "HELPFUL|RAID3") == true)
    restricted = false

    _G.C_UnitAuras = nil
    _G.AuraUtil = nil
    _G.C_Secrets = nil
end

-- QueueRegenWork restriction boundary (68675): AuraButton children deny
-- tainted access while auras are secret, so the replay queue must not fire
-- on regen alone — it re-checks ShouldAurasBeSecret and polls until clear.
do
    local ran = 0
    _G.InCombatLockdown = function() return false end
    _G.C_Secrets = { ShouldAurasBeSecret = function() return true end }
    local timers = {}
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

    G.QueueRegenWork("owner1", function() ran = ran + 1 end)
    check("queue: OOC-but-restricted defers instead of running", ran == 0)
    check("queue: restriction poll armed", #timers == 1, tostring(#timers))

    timers[1]()
    check("queue: still-restricted poll re-arms without running",
        ran == 0 and #timers == 2, tostring(ran) .. "/" .. tostring(#timers))

    _G.C_Secrets = { ShouldAurasBeSecret = function() return false end }
    timers[2]()
    check("queue: flushes once the restriction clears", ran == 1, tostring(ran))

    G.QueueRegenWork("owner2", function() ran = ran + 1 end)
    check("queue: immediate when unrestricted and OOC", ran == 2, tostring(ran))

    _G.C_Timer = nil
    _G.InCombatLockdown = nil
    _G.C_Secrets = nil
end

print("aura_glue_test " .. (failures == 0 and "OK" or "FAILED"))
os.exit(failures == 0 and 0 or 1)
