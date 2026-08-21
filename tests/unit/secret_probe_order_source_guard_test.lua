-- tests/unit/secret_probe_order_source_guard_test.lua
--
-- SOURCE GUARDS: probe-before-truth-test / probe-before-nil-compare ordering
-- for secret-capable values (2026-07 external review, findings 1-2).
--
-- In 12.1 a bare boolean test (`if x`, `not x`, `x and ...`) or a nil compare
-- (`x == nil`, `x ~= nil`) on a SecretValue THROWS in-game ("attempt to
-- perform boolean test on ..."). The offline Lua 5.1 harness cannot reproduce
-- either: truthiness is untrappable on plain values and `==` against a
-- different type silently returns false (tools/_addon_env.lua "Simulation
-- limits"). So the ordering can only be pinned at the source level — these
-- guards ARE the spec for the probe-first discipline at each site.
--
-- Run: lua tests/unit/secret_probe_order_source_guard_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local source = fh:read("*a")
    fh:close()
    return source
end

-- Preserve byte offsets while blanking every non-code Lua lexical form, so a
-- guard planted in a comment/string can't satisfy (or trip) an assertion.
-- Same scrubber as actionbars_cooldown_charge_cache_test.lua.
local function stripLuaNonCode(source)
    local chars = {}
    for i = 1, #source do
        chars[i] = source:sub(i, i)
    end

    local function blank(first, last)
        for i = first, last do
            if chars[i] ~= "\n" and chars[i] ~= "\r" then
                chars[i] = " "
            end
        end
    end

    -- Anchored (^) so the scan cost is O(1) per call — the unanchored form
    -- rescans the remainder of the file at every character (O(n^2), which
    -- visibly hangs on cdm_spelldata.lua).
    local function longBracketAt(at)
        local first, last, equals = source:find("^%[(=*)%[", at)
        if first ~= at then return nil end
        return last, equals
    end

    local function longBracketEnd(openEnd, equals)
        local close = "]" .. equals .. "]"
        local closeAt = source:find(close, openEnd + 1, true)
        return closeAt and (closeAt + #close - 1) or #source
    end

    local cursor = 1
    while cursor <= #source do
        local char = source:sub(cursor, cursor)
        if source:sub(cursor, cursor + 1) == "--" then
            local openEnd, equals = longBracketAt(cursor + 2)
            local last
            if openEnd then
                last = longBracketEnd(openEnd, equals)
            else
                last = (source:find("\n", cursor, true) or (#source + 1)) - 1
            end
            blank(cursor, last)
            cursor = last + 1
        elseif char == "'" or char == '"' then
            local at = cursor + 1
            while at <= #source do
                local c = source:sub(at, at)
                if c == "\\" then
                    at = at + 2
                elseif c == char or c == "\n" then
                    break
                else
                    at = at + 1
                end
            end
            blank(cursor, math.min(at, #source))
            cursor = at + 1
        else
            local openEnd, equals = longBracketAt(cursor)
            if openEnd then
                local last = longBracketEnd(openEnd, equals)
                blank(cursor, last)
                cursor = last + 1
            else
                cursor = cursor + 1
            end
        end
    end

    return table.concat(chars)
end

-- Assert `firstSnippet` occurs before `secondSnippet` inside the function
-- whose header is `fnHeader`. `window` bounds the search past the header so
-- an unrelated later occurrence can't satisfy the order.
local function assertOrderInFunction(code, path, fnHeader, firstSnippet, secondSnippet, window)
    local headerAt = code:find(fnHeader, 1, true)
    assert(headerAt, path .. ": function header not found: " .. fnHeader)
    local chunk = code:sub(headerAt, headerAt + (window or 900))
    local firstAt = chunk:find(firstSnippet, 1, true)
    assert(firstAt, path .. " " .. fnHeader .. ": probe missing: " .. firstSnippet)
    local secondAt = chunk:find(secondSnippet, 1, true)
    assert(secondAt, path .. " " .. fnHeader .. ": guarded test missing: " .. secondSnippet)
    assert(firstAt < secondAt,
        path .. " " .. fnHeader .. ": probe must come BEFORE the truth/nil test ("
        .. firstSnippet .. " < " .. secondSnippet .. ")")
end

---------------------------------------------------------------------------
-- modules/trackers/spellscanner.lua — HandleUnitAura probes the whole
-- payload UNCONDITIONALLY (the old `updateInfo and ScannerIsSecretValue(
-- updateInfo)` truth-tested the possibly-whole-secret payload first: the
-- exact round-7 crash idiom, tests/taint/analyzer_test.lua srcG1).
---------------------------------------------------------------------------
do
    local path = "modules/trackers/spellscanner.lua"
    local code = stripLuaNonCode(readFile(path))
    assert(not code:find("updateInfo and ScannerIsSecretValue(updateInfo)", 1, true),
        path .. ": whole-payload probe must not hide behind a truth test of the payload")
    assert(code:find("if ScannerIsSecretValue(updateInfo) then", 1, true),
        path .. ": HandleUnitAura must probe updateInfo unconditionally")
end

---------------------------------------------------------------------------
-- QUI_CDM/cdm/cdm_sources.lua
---------------------------------------------------------------------------
do
    local path = "QUI_CDM/cdm/cdm_sources.lua"
    local code = stripLuaNonCode(readFile(path))
    assert(not code:find("C_UnitAuras", 1, true),
        path .. ": CDM source layer must not reference the restricted aura namespace")
    assert(not code:find("DropAuraMemoKey", 1, true),
        path .. ": deleted aura memo helpers must not return")
end

---------------------------------------------------------------------------
-- QUI_CDM/cdm/cdm_spelldata.lua
---------------------------------------------------------------------------
do
    local path = "QUI_CDM/cdm/cdm_spelldata.lua"
    local code = stripLuaNonCode(readFile(path))

    assertOrderInFunction(code, path, "local function IsUsableTableKey(key)",
        "issecretvalue(key)", "not key")
    -- IsUsableSpellIDKey: the secret-rejecting key check must run before
    -- type() ever sees the value.
    assertOrderInFunction(code, path, "local function IsUsableSpellIDKey(spellID)",
        "IsUsableTableKey(spellID)", "type(spellID)")
    assertOrderInFunction(code, path, "local function GetCleanAuraSpellID(auraData)",
        "issecretvalue(sid)", "not sid")
    assertOrderInFunction(code, path, "local function GetCleanAuraApplications(auraData)",
        "issecretvalue(apps)", "return apps")
    assertOrderInFunction(code, path, "local function CaptureAuraFromPayload(",
        "issecretvalue(instID)", "not instID")
    assert(not code:find("NameMatches", 1, true),
        path .. ": deleted index-scan name matcher must not return")
    assertOrderInFunction(code, path, "local function SafeCountNumber(value)",
        "IsSecretCountValue(value)", "value == nil")
    assertOrderInFunction(code, path, "local function SetAuraCount(",
        "IsSecretCountValue(value)", "value == nil")
    assertOrderInFunction(code, path, "local function SetResolvedAuraSpellID(",
        "issecretvalue(pts)", "pts ~= nil", 1600)
    -- Resolver count call site: apps can be a secret string out of
    -- GetAuraApplications — the shown flag must probe before `apps ~= nil`.
    assert(code:find("IsSecretCountValue(apps) or apps ~= nil", 1, true),
        path .. ": count shown flag must probe apps before the nil compare")
end

---------------------------------------------------------------------------
-- QUI_DamageMeter/damage_meter/damage_meter.lua — 2026-07-19 external
-- review: every category below performed a truth/nil test on a possibly-
-- secret C_DamageMeter value BEFORE its probe (helper-param shapes the
-- analyzer's non-interprocedural boundary can't seed).
---------------------------------------------------------------------------
do
    local path = "QUI_DamageMeter/damage_meter/damage_meter.lua"
    local code = stripLuaNonCode(readFile(path))

    -- ResolveCurrentViewDuration's usable(): the probe must run before
    -- type() ever sees the value (the beta-ported shape truth-tested via
    -- type() first; reordered on alpha to the probe-first idiom).
    assertOrderInFunction(code, path, "local function ResolveCurrentViewDuration(",
        "isSecret(d)", "type(d)")
    assertOrderInFunction(code, path, "local function FormatNumber(amount, format)",
        "IsSecretValue(amount)", "amount == nil")
    assertOrderInFunction(code, path, "local function ShortenName(name)",
        "IsSecretValue(name)", "name == nil")
    assertOrderInFunction(code, path, "local function SafeNumOrZero(v, isSecret)",
        "isSecret(v)", "v == nil")
    assertOrderInFunction(code, path, "local function IsIndexableSpellID(spellID)",
        "IsSecretValue(spellID)", "spellID ~= nil")
    assertOrderInFunction(code, path, "local function isIndexableKey(v)",
        "IsSecret(v)", "v ~= nil")
    assertOrderInFunction(code, path, "local function RankAndMaxAmount(list, isSecret)",
        "isSecret(v)", "v ~= nil")
    assertOrderInFunction(code, path, "local function AggregateSpellsByUnit(",
        "isSecret(name)", "name ~= nil", 1400)
    -- Row name: a secret name must route through the SetFormattedText sink,
    -- never Lua `..`/`or "?"`. (String literals are blanked by the scrubber —
    -- match the call shape only.)
    assert(code:find("row.Name:SetFormattedText(", 1, true),
        path .. ": secret row names must render via the SetFormattedText sink")
    -- Bar fill: no `or 0` truth-test on the possibly-secret fill value.
    assert(not code:find("row.Bar:SetValue(fillValue or 0)", 1, true),
        path .. ": SetValue must take the raw fill value — `or 0` truth-tests a secret")
end

---------------------------------------------------------------------------
-- QUI_ResourceBars/resourcebars/resourcebars.lua — 2026-07-19 external
-- review: unprobed UnitPower/UnitPowerMax reads throughout.
---------------------------------------------------------------------------
do
    local path = "QUI_ResourceBars/resourcebars/resourcebars.lua"
    local code = stripLuaNonCode(readFile(path))

    assertOrderInFunction(code, path, "local function ReadPlayerPowerPair(",
        "IsSecretValue(current)", "return current, max, false", 900)
    -- GetPrimaryResourceValue does no arithmetic on max at all now: it reads the
    -- probed pair helper, presence-tests with type() (safe on secrets), and hands
    -- current/max/percent to C sinks. The old "max <= 0" compare would throw on a
    -- secret max, which is exactly why it is gone.
    assertOrderInFunction(code, path, "local function GetPrimaryResourceValue(",
        "ReadPlayerPowerPair(resource)", "type(max) ==", 1200)
    do
        local headerAt = assert(code:find("local function GetPrimaryResourceValue(", 1, true))
        local bodyEnd = assert(code:find("\nend\n", headerAt, true))
        local body = code:sub(headerAt, bodyEnd)
        assert(not body:find("max <= 0", 1, true) and not body:find("/ max", 1, true),
            path .. ": GetPrimaryResourceValue must not compare or divide a possibly-secret max")
    end
    -- GetPowerPct: unconditional probe before the nil compares on pct.
    assertOrderInFunction(code, path, "local function GetPowerPct(",
        "IsSecretValue(pct)", "pct == nil", 1600)
    -- Event payload unit probe before the ~= compare (string literal is
    -- scrubbed — match the compare shape only).
    assertOrderInFunction(code, path, "function QUICore:OnUnitPowerPointCharge(",
        "IsSecretValue(unit)", "unit and unit ~=", 900)
end

---------------------------------------------------------------------------
-- QUI_GroupFrames — per-spell always-secret auras survive the global
-- AurasAreSecret() gate; dispelName/instID must probe before truth/nil
-- tests. UNIT_IN_RANGE_UPDATE (SecretPayloads = true) must never be routed
-- through payload-keyed dispatch.
---------------------------------------------------------------------------
do
    local path = "QUI_GroupFrames/groupframes/groupframes_auras.lua"
    local code = stripLuaNonCode(readFile(path))
    assertOrderInFunction(code, path, "local function AddDebuffDerivedData(",
        "IsSecretValue(dispelName)", "dispelName ~= nil", 1400)
    assert(not code:find("dispelName ~= nil and not IsSecretValue(dispelName)", 1, true),
        path .. ": dispelName probe must not trail its nil compare")
    assertOrderInFunction(code, path, "local function AppendSlotAuras(",
        "IsSecretValue(auraData)", "if instID then", 1400)
end

do
    local path = "QUI_GroupFrames/groupframes/groupframes.lua"
    local raw = readFile(path)  -- registration assertions need the event-name
                                -- string literals the scrubber blanks; the
                                -- full call shape can't occur in a comment.
    local code = stripLuaNonCode(raw)
    -- The central dispatcher must not consume UNIT_IN_RANGE_UPDATE (its
    -- always-secret payload would hit the unitFrameMap index / :sub prefix
    -- check); per-unit lexical listeners own it.
    assert(not raw:find('eventFrame:RegisterEvent("UNIT_IN_RANGE_UPDATE")', 1, true),
        path .. ": UNIT_IN_RANGE_UPDATE must not be centrally registered")
    assert(raw:find('rangeListener:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit)', 1, true),
        path .. ": per-unit range listeners must own UNIT_IN_RANGE_UPDATE")
    assert(code:find("function _state.HandleRangeUpdate(unit)", 1, true),
        path .. ": lexical-token range handler must exist")
end

do
    local path = "QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"
    local raw = readFile(path)
    assert(not raw:find('snapshotEventFrame:RegisterEvent("UNIT_IN_RANGE_UPDATE")', 1, true),
        path .. ": UNIT_IN_RANGE_UPDATE must not feed RefreshUnit via the secret payload")
    assert(raw:find('listener:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", token)', 1, true),
        path .. ": per-token range listeners must own UNIT_IN_RANGE_UPDATE")
end

do
    local path = "QUI_UnitFrames/unitframes/unitframes.lua"
    local raw = readFile(path)
    local code = stripLuaNonCode(raw)
    assert(raw:find('listener:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", token)', 1, true),
        path .. ": boss range must use per-token listeners")
    assert(code:find("QUI_UF.frames[token]", 1, true),
        path .. ": boss range handler must index frames by the LEXICAL token")
end

---------------------------------------------------------------------------
-- modules/trackers/preytracker.lua — CHAT_MSG_SYSTEM text probe order.
---------------------------------------------------------------------------
do
    local path = "modules/trackers/preytracker.lua"
    local code = stripLuaNonCode(readFile(path))
    assertOrderInFunction(code, path, "local function OnAmbushMessage(message)",
        "IsSecretValue(message)", "not message")
    assert(not code:find("if not message or Helpers.IsSecretValue(message)", 1, true),
        path .. ": message probe must not trail the truth test")
end

---------------------------------------------------------------------------
-- libs/LibOpenRaid/LibOpenRaid.lua — vendored patch: the local cooldown
-- tracker's UNIT_SPELLCAST_SUCCEEDED handler probes unitId/spellId before
-- UnitIsUnit / table indexing.
---------------------------------------------------------------------------
do
    local path = "libs/LibOpenRaid/LibOpenRaid.lua"
    local code = stripLuaNonCode(readFile(path))
    assertOrderInFunction(code, path, "local createLocalCooldownTracker = function()",
        "issecretvalue(unitId) or issecretvalue(spellId)", "UnitIsUnit(unitId,", 2200)
end

---------------------------------------------------------------------------
-- 2026-07-19 second external review (round-15): breakdown ingestion,
-- whole-secret AuraData elements past the global gate, second LibOpenRaid
-- handler, tracked-slot fail-closed parking.
---------------------------------------------------------------------------
do
    local path = "QUI_DamageMeter/damage_meter/damage_meter.lua"
    local code = stripLuaNonCode(readFile(path))
    assertOrderInFunction(code, path, "local function FormatDuration(seconds)",
        "IsSecretValue(seconds)", "not seconds")
    assertOrderInFunction(code, path, "local function FetchSourceSpells(",
        "IsSecretValue(src)", "type(src)", 1200)
    assertOrderInFunction(code, path, "function Data:GetBreakdownView(",
        "IsSecretValue(src)", "type(src)", 1600)
    -- NormalizeSpells: element probe before the first field index.
    assertOrderInFunction(code, path, "local function NormalizeSpells(rawSpells)",
        "IsSecretValue(spell)", "spell.spellID", 1400)
    -- Breakdown spell rows: secret creatureName routes via SetFormattedText.
    assert(code:find("row.Name:SetFormattedText(", 1, true),
        path .. ": secret spell/target names must render via SetFormattedText sinks")
end

do
    local path = "QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"
    local code = stripLuaNonCode(readFile(path))
    assertOrderInFunction(code, path, "local function SafeAuraField(auraData, field)",
        "IsSecretValue(auraData)", "not auraData")
    -- Index scan: probe before `not auraData`, and secret ≠ end-of-list.
    assert(code:find("if IsSecretValue(auraData) then", 1, true)
        and code:find("elseif not auraData then", 1, true),
        path .. ": index-scan entries must probe before the end-of-list truth test")
end

do
    local path = "QUI_GroupFrames/groupframes/groupframes_auras.lua"
    local code = stripLuaNonCode(readFile(path))
    -- Delta fresh-fetch: GetAuraDataByAuraInstanceID can return whole-secret
    -- AuraData; probe before `not freshAura`.
    assertOrderInFunction(code, path, "local freshAura = GetAuraByInstanceID(unit, instID)",
        "IsSecretValue(freshAura)", "not freshAura", 700)
end

do
    local path = "QUI_CDM/cdm/cdm_spelldata.lua"
    local code = stripLuaNonCode(readFile(path))
    assert(not code:find("C_UnitAuras", 1, true),
        path .. ": CDM spell data must not scan the restricted aura namespace")
    assert(not code:find("GetAuraDataByIndex", 1, true),
        path .. ": direct aura index fallback must remain deleted")
    assert(not code:find("AuraUtil.ForEachAura(", 1, true),
        path .. ": CDM must not use an aura index fallback")
end

do
    local path = "QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"
    local code = stripLuaNonCode(readFile(path))
    -- Same ban: MRB scans use probe-first GetAuraDataByIndex loops only.
    assert(not code:find("AuraUtil.ForEachAura(", 1, true),
        path .. ": AuraUtil.ForEachAura is banned — its internal truth-test throws on whole-secret auras")
end

do
    local path = "libs/LibOpenRaid/LibOpenRaid.lua"
    -- The handler key is a string literal the scrubber blanks — order-check
    -- against the RAW source (the probe/index snippets don't occur verbatim
    -- in surrounding comments).
    local raw = readFile(path)
    local headerAt = assert(raw:find('["UNIT_SPELLCAST_SUCCEEDED"] = function(...)', 1, true),
        path .. ": player/pet UNIT_SPELLCAST_SUCCEEDED dispatch entry not found")
    local chunk = raw:sub(headerAt, headerAt + 1400)
    local probeAt = assert(chunk:find("issecretvalue(unitId) or issecretvalue(spellId)", 1, true),
        path .. ": dispatch entry must probe unitId/spellId")
    local indexAt = assert(chunk:find("LIB_OPEN_RAID_SPELL_DEFAULT_IDS[spellId]", 1, true),
        path .. ": DEFAULT_IDS index expected in the dispatch entry")
    assert(probeAt < indexAt,
        path .. ": probe must come BEFORE the DEFAULT_IDS index / UnitIsUnit")
end

do
    local path = "core/aura_slots.lua"
    local code = stripLuaNonCode(readFile(path))
    -- Fail-closed tracked slots: Sync must consult the enforceability
    -- predicate and park (want stays 0) when the engine ignores identity
    -- filters for the unit class/polarity.
    assert(code:find("local function IdentityFilterEnforceable(container, base)", 1, true),
        path .. ": identity-enforceability predicate must exist")
    -- 16d shape: the decision tuple lands in locals; the fail-closed branch
    -- reads `enforceable`, and Sync records the applied probe value.
    assert(code:find("IdentityFilterEnforceable(container, base)", 1, true)
        and code:find("if not enforceable then", 1, true),
        path .. ": Sync must fail closed when identity filters are engine-ignored")
end

---------------------------------------------------------------------------
-- 2026-07-19 third external review (round-16): probe-order blockers +
-- legacy-copy secret-instID retention. Verified standard: documented secret
-- source + reachable illegal consumer (or sibling-code-proven model).
---------------------------------------------------------------------------
do
    local path = "QUI_DamageMeter/damage_meter/damage_meter.lua"
    local code = stripLuaNonCode(readFile(path))
    -- Breakdown click name: probe before the nil compare (== consumes the
    -- secret; the probe one line below arrived too late).
    assertOrderInFunction(code, path, "function Data:GetPlayerTargets(",
        "IsSecret(playerName)", "playerName == nil")
end

do
    local path = "QUI_GroupFrames/groupframes/groupframes.lua"
    local code = stripLuaNonCode(readFile(path))
    -- Dispel type resolver: statement-split probe. The old compound
    -- truth-tested the possibly-secret dispelName before probing it.
    assert(not code:find("dispelAura and dispelAura.dispelName and not IsSecretValue", 1, true),
        path .. ": dispelName probe must not trail its truth test")
    assertOrderInFunction(code, path, "function _dispel.ReadableType(auraData)",
        "IsSecretValue(dispelName)", "if dispelName ==", 900)
end

do
    local path = "QUI_CDM/cdm/cdm_spelldata.lua"
    local code = stripLuaNonCode(readFile(path))
    -- Clean-helper contract: every caller truth-tests the return, so the
    -- helper itself must reject secret instance IDs (raw forwarding is
    -- GetRawAuraInstanceID's job).
    assertOrderInFunction(code, path, "local function GetCleanAuraInstanceID(auraData)",
        "issecretvalue(instID)", "return instID")
    -- Captured-filter polarity flags: AnyDeltaElementSecret's gate probes
    -- identity fields only, not isHelpful/isHarmful — probe before `== true`
    -- (same readable-struct/secret-scalar shape as `applications`).
    assertOrderInFunction(code, path, "local function ResolveCapturedAuraFilter(",
        "issecretvalue(isHelpful)", "isHelpful == true", 1400)
    assertOrderInFunction(code, path, "local function ResolveCapturedAuraFilter(",
        "issecretvalue(isHarmful)", "isHarmful == true", 1400)
end

do
    local path = "QUI_GroupFrames/groupframes/groupframes_auras.lua"
    local code = stripLuaNonCode(readFile(path))
    -- Legacy-copy parity with AppendSlotAuras: a readable entry with a
    -- secret auraInstanceID must be dropped — RemoveAuraFromBucket's reindex
    -- walk truth-tests that field on every retained bucket entry.
    -- (ConditionalSecretContents on GetUnitAuras proves secret ELEMENTS; the
    -- per-field case is defense-in-depth on observed shapes.)
    assertOrderInFunction(code, path, "local function CopyReadableAuras(src, dst)",
        "IsSecretValue(instID)", "dst[n] = auraData", 1400)
end

---------------------------------------------------------------------------
-- 2026-07-19 round-16b (rerun review): UnitIsUnit result probe + tracked-
-- slot live-assist re-drive wiring.
---------------------------------------------------------------------------
do
    local path = "QUI_GroupFrames/groupframes/groupframes.lua"
    local raw = readFile(path)
    local code = stripLuaNonCode(raw)
    -- UnitIsUnit is SecretWhenUnitComparisonRestricted (UnitDocumentation):
    -- probe the result before the self short-circuit branches on it.
    assertOrderInFunction(code, path, "local function CheckUnitRange(unit)",
        "IsSecretValue(isSelf)", "if isSelf then", 900)
    -- Live-assist re-gate: faction flips must reach the tracked-slot gate
    -- (core/aura_slots.lua LiveAssistProbe), and the re-drive helper must
    -- exist for the flags/phase/connection sweeps to call.
    assert(raw:find('eventFrame:RegisterEvent("UNIT_FACTION")', 1, true),
        path .. ": UNIT_FACTION must be registered for the live-assist re-gate")
    assert(code:find("function _state.RefreshTrackedSlotAssist(unit, frames)", 1, true),
        path .. ": tracked-slot assist re-drive helper must exist")
    -- 16d (Codex stop-gate): staleness must be judged against the APPLIED
    -- state Sync records on containers, never a reader-side dedupe cache —
    -- a config pass can re-park slots under a probe value the reader never
    -- observed, leaving them parked with no flip left to see.
    assert(code:find("GFA.TrackedAssistStale(frame)", 1, true),
        path .. ": re-drive must consult the Sync-written applied state")
    assert(not code:find("_state.trackedAssistState", 1, true),
        path .. ": reader-side assist dedupe cache is banned (16d)")
    -- Event-less flips (zone-rule assist changes, visibility drift) have no
    -- unit event — the sweep + zone triggers + safety ticker must exist or
    -- a parked slot stays parked across a zone transition (Codex stop-gate
    -- catch, 2026-07-19).
    assert(code:find("function _state.SweepTrackedSlotAssist()", 1, true),
        path .. ": event-less assist sweep must exist")
    assert(raw:find('eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")', 1, true),
        path .. ": ZONE_CHANGED_NEW_AREA must drive the assist sweep")
    assert(code:find("C_Timer.NewTicker(5, _state.SweepTrackedSlotAssist)", 1, true),
        path .. ": 5s safety ticker must back-stop event-less assist flips")
end

---------------------------------------------------------------------------
-- 2026-07-20 round-22 (eighth external review): default power-skin
-- or-fallbacks, raw UnitIsUnit truth-tests, aura-scan pagination and
-- termination contracts, vendored LibRangeCheck comparison probes.
---------------------------------------------------------------------------

-- modules/skinning/gameplay/powerbaralt.lua — UnitPower/UnitPowerMax are
-- SecretWhenUnitPower(Max)Restricted AND non-nilable (UnitDocumentation):
-- `power or 0` / `maxPower or 0` truth-tested the raw values on the way into
-- the StatusBar sinks. The sinks accept secrets natively — the `or` WAS the
-- throw, and the fallback was dead code.
do
    local path = "modules/skinning/gameplay/powerbaralt.lua"
    local code = stripLuaNonCode(readFile(path))
    assert(not code:find("maxPower or 0", 1, true),
        path .. ": `maxPower or 0` truth-tests a secret-capable value")
    assert(not code:find("power or 0", 1, true),
        path .. ": `power or 0` truth-tests a secret-capable value")
    assertOrderInFunction(code, path, "local function UpdateBar(self)",
        "Helpers.IsSecretValue(power)", "maxPower > 0", 2000)
end

-- QUI_GroupFrames/groupframes/groupframes.lua — UnitIsUnit is
-- SecretWhenUnitComparisonRestricted AND RequiresComparableUnitTokens.
-- The precondition's FailureMode is "ReturnNothing"
-- (SecretPredicatesDocumentation:11) — an incomparable-token call yields
-- NIL, it does NOT throw — so nil-tolerant statement-split shapes
-- (CheckUnitRange, unitframes boss loop, LibRangeCheck isPet) are CORRECT.
-- A 2026-07-21 review claimed the call itself errors and statement-split
-- is unsound — refuted by the FailureMode. The CONTRACT this test pins is
-- probe-before-truth-test ordering plus the nil-tolerant `== true` compare;
-- the helper's pcall is optional defensive belt and deliberately NOT
-- pinned (round-22b review: mandate the behavior, not the implementation).
-- Target-highlight and roster sites route through the contained helpers.
do
    local path = "QUI_GroupFrames/groupframes/groupframes.lua"
    local raw = readFile(path)
    local code = stripLuaNonCode(raw)
    assertOrderInFunction(code, path, "_state.IsUnitTarget = function(unit)",
        "IsSecretValue(isTarget)", "isTarget == true", 900)
    assert(not raw:find('and UnitIsUnit(unit, "target")', 1, true),
        path .. ": raw target-comparison truth-test is banned — use _state.IsUnitTarget")
    assert(code:find("_state.IsUnitTarget(unit)", 1, true),
        path .. ": target-highlight sites must route through _state.IsUnitTarget")
    assert(code:find("unitMatchesRoster and _state.IsPlayerUnit(unit)", 1, true),
        path .. ": roster isPlayer must route through _state.IsPlayerUnit")
end

-- QUI_GroupFrames/groupframes/groupframes_auras.lua — GetAuraSlots is
-- PAGINATED (UnitAuraDocumentation: feed outContinuationToken back until
-- nil); a single capped call silently dropped aura 41+ from dispel
-- overlays, tracked borders, and the health-tint cache. The legacy
-- GetUnitAuras path has no token — its cap is simply omitted (nilable).
do
    local path = "QUI_GroupFrames/groupframes/groupframes_auras.lua"
    local raw = readFile(path)
    local code = stripLuaNonCode(raw)
    assert(code:find("GetAuraSlots(unit, filter, MAX_SCAN_AURAS, token)", 1, true),
        path .. ": slot scan must feed the continuation token back")
    assert(code:find("until token == nil", 1, true),
        path .. ": slot scan must page until the token comes back nil")
    assert(not raw:find('GetAuraSlots(unit, "HARMFUL", MAX_SCAN_AURAS)', 1, true)
        and not raw:find('GetAuraSlots(unit, "HELPFUL", MAX_SCAN_AURAS)', 1, true),
        path .. ": single-shot capped GetAuraSlots calls are banned")
    assert(raw:find('GetUnitAuras(unit, "HARMFUL")', 1, true)
        and raw:find('GetUnitAuras(unit, "HELPFUL")', 1, true),
        path .. ": legacy scan must be uncapped (maxCount omitted)")
    assert(not raw:find('GetUnitAuras(unit, "HARMFUL", MAX_SCAN_AURAS)', 1, true),
        path .. ": legacy capped GetUnitAuras calls are banned")
    -- The continuation token itself is probed before the pager's == nil.
    assertOrderInFunction(code, path, "local function AppendSlotAuras(",
        "IsSecretValue(token)", "return token", 2600)
end

-- modules/qol/consumablecheck.lua + modules/trackers/spellscanner.lua —
-- player-buff scans are UNBOUNDED walks matching the iterator's own
-- termination contract (round-15 canon): plain nil terminates, pcall-fail
-- terminates, a per-spell SECRET entry is skipped (secret ≠ end-of-list).
-- The old `for i = 1, 40` cap silently truncated, and folding a secret
-- entry to nil then breaking ended the scan at the first secret element.
do
    local path = "modules/qol/consumablecheck.lua"
    local code = stripLuaNonCode(readFile(path))
    assert(not code:find("AuraScanCount", 1, true),
        path .. ": the capped scan-bound helper is banned — unbounded walk only")
    assertOrderInFunction(code, path,
        "local function ForEachPlayerHelpfulAura(callback)",
        "while true do", "auraData == nil", 1400)
    assertOrderInFunction(code, path,
        "local function ForEachPlayerHelpfulAura(callback)",
        "Helpers.IsSecretValue(auraData)", "auraData == nil", 1400)
end
do
    local path = "modules/trackers/spellscanner.lua"
    local code = stripLuaNonCode(readFile(path))
    assert(not code:find("AuraScanCount", 1, true),
        path .. ": the capped scan-bound helper is banned — unbounded walk only")
    assertOrderInFunction(code, path,
        "local function ForEachPlayerHelpfulAura(callback)",
        "while true do", "aura == nil", 1400)
    assertOrderInFunction(code, path,
        "local function ForEachPlayerHelpfulAura(callback)",
        "ScannerIsSecretValue(aura)", "aura == nil", 1400)
end

-- modules/trackers/atonement_counter.lua — the GetUnitAuras fast-paths were
-- 40-capped; the unbounded ForEachAura fallback masked the miss only when
-- available, and the last-resort scan had no fallback at all.
do
    local path = "modules/trackers/atonement_counter.lua"
    local raw = readFile(path)
    assert(not raw:find("PLAYER_HELPFUL_FILTER, 40)", 1, true)
        and not raw:find("HELPFUL_FILTER, 40)", 1, true),
        path .. ": capped GetUnitAuras scans are banned (maxCount omitted)")
end

-- libs/LibRangeCheck-3.0 — vendored patch (LibOpenRaid precedent): getRange
-- truth-tested UnitCanAssist/UnitIsDeadOrGhost/UnitCanAttack/UnitIsUnit raw
-- (all secret-capable under restriction) and threw out of the whole range
-- query; InCombatLockdownRestriction `not UnitCanAttack(...)` same class.
-- Each verdict is probed at its own decision point (round-20c rule); a
-- secret verdict returns nil so callers fall back.
do
    local path = "libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua"
    local code = stripLuaNonCode(readFile(path))
    assertOrderInFunction(code, path, "local function getRange(unit, noItems)",
        "issecretvalue(canAssist)", "if deadOrGhost then", 2400)
    assertOrderInFunction(code, path, "local function getRange(unit, noItems)",
        "issecretvalue(deadOrGhost)", "if deadOrGhost then", 2400)
    assertOrderInFunction(code, path, "local function getRange(unit, noItems)",
        "issecretvalue(canAttack)", "if canAttack then", 2400)
    assertOrderInFunction(code, path, "local function getRange(unit, noItems)",
        "issecretvalue(isPet)", "elseif isPet then", 2400)
    assertOrderInFunction(code, path,
        "local InCombatLockdownRestriction = function(unit)",
        "issecretvalue(canAttack)", "return not canAttack", 500)
end

print("OK secret_probe_order_source_guard_test")
