-- tests/.taintrc.lua
-- Combat-taint analyzer config. See
-- docs/superpowers/specs/2026-05-04-taint-analyzer-design.md.
return {
    strict_paths = {
        -- Directories ratcheted into CI enforcement. Findings under these
        -- prefixes are classified strict (CI-blocking) instead of advisory.
        -- Add only after auditing — promoted findings must be either fixed
        -- or annotated with `-- @secret-safe: <reason>` to keep CI green.
        --
        -- 2026-07-21 FULL-REPO RATCHET: the advisory sweep burned the
        -- advisory tier to ZERO repo-wide, so every remaining analyzable
        -- prefix was promoted at zero finding-cost — from here on, any new
        -- finding anywhere in QUI-authored code is CI-blocking, never
        -- invisible-advisory. (libs/tests/importstrings/meta stay out via
        -- ignore_paths; review-tier `<unwrap>` census classification is
        -- unaffected by this list.)
        "QUI_ActionBars/",
        "QUI_Bags/",
        "QUI_CDM/",
        "QUI_Chat/",
        "QUI_DamageMeter/",
        "QUI_Debug/",
        "QUI_GroupFrames/",
        "QUI_Logger/",
        -- Strict from day one (greenfield; plates are the most secret-hostile
        -- surface in 12.0).
        "QUI_Nameplates/",
        "QUI_Options/",
        -- (The generated search index used to need its own QUI_OptionsSearch/
        -- entry; it is QUI_Options/search_cache.lua now, covered above. The
        -- ten per-locale overlay trees are likewise retired — their chunks are
        -- covered by the "core/" entry below.)
        "QUI_ResourceBars/",
        "QUI_UnitFrames/",
        "core/",
        "modules/",
        "init.lua",
    },
    aspect_paths = {
        -- Directories where aspect-returning widget getters (api-index
        -- secretReturnsForAspect: GetText, GetAlpha, IsShown, …) taint their
        -- results. Opt-in per directory: aspect secrets only materialize on
        -- objects whose aspect was secretized (CDM/aura surfaces), so
        -- repo-wide coverage would flood the tiers.
        -- STATUS (2026-07 round-7): still empty — a diagnostic enable of
        -- "QUI_CDM/cdm/" produced 218 strict findings, overwhelmingly aspect
        -- getters on QUI-created chrome frames whose aspects are never
        -- secretized. Blanket enablement needs receiver PROVENANCE (taint
        -- only getters on Blizzard-owned viewer icons/children), which the
        -- analyzer does not model yet — see the 12.1 review follow-up before
        -- adding a path here. KNOWN COST of leaving this empty: the
        -- cdm_buff_layout IsTrackedBarActive IsShown()-secret defect (fixed
        -- round-7 via ReadBoolean) was invisible to the strict scan — aspect
        -- getters on Blizzard viewer children go unanalyzed until provenance
        -- lands. Grep new viewer-child code for bare IsShown()/GetAlpha()
        -- truth-tests during review instead.
    },
    strict_unwrap_paths = {
        -- Safe* unwrap helpers are stricter in CDM: cooldown-secret values
        -- must stay opaque unless they are passed to approved C-side sinks.
        "QUI_CDM/cdm/",
    },
    ignore_paths = {
        "libs/",
        "tests/",
        "importstrings/",
        "meta/",  -- LuaLS editor-only ---@meta stubs; never loaded in-game
    },
    precondition_only_paths = {
        -- Vendored libraries stay out of the taint tiers (third-party code,
        -- ignore_paths above) but DO get the raw guarded-call scan: the
        -- 2026-07 external review found unguarded RequiresUnitAuraAccess
        -- walks in LibOpenRaid that the libs/ blanket ignore hid.
        "libs/",
    },
    strict_precondition_paths = {
        -- LibOpenRaid's guarded-call sites are all fixed or @secret-safe
        -- annotated (2026-07); promote its precondition findings to strict
        -- so a future lib bump that regresses fails CI instead of hiding
        -- at review tier.
        "libs/LibOpenRaid/",
    },
    event_payload_params = {
        -- UNIT_AURA (SecretWhenAurasRestricted in the api-index): the
        -- OnEvent signature is (self, event, unit, updateInfo). BOTH payload
        -- args can be secret — 12.1 PTR 68569 made the unit token itself
        -- secret under restriction (see
        -- tests/unit/aura_events_secret_boundary_test.lua R1/R2: the
        -- payload unit arg is never trusted, only the registered token). A
        -- handler is detected by its `event == "UNIT_AURA"` comparison (see
        -- analyzer secretEventParamHits for the documented gaps).
        UNIT_AURA = { 3, 4 },
        -- UNIT_AURA_BLOCKED: (self, event, unitTarget, auraInstanceID) —
        -- ONLY auraInstanceID carries SecretValue in the 68675 payload docs
        -- (tests/api-docs/blizzard/UnitAuraDocumentation.lua). The event has
        -- no SecretWhenAurasRestricted flag, so unitTarget is NOT secret here
        -- (unlike UNIT_AURA's whole-payload restriction) — marking it tainted
        -- produced false positives on plain unit-token use.
        -- gateGoverned = false: the payload is ALWAYS secret, not
        -- restriction-conditional — a falsy C_Secrets.ShouldAurasBeSecret
        -- gate proves nothing about auraInstanceID, so the analyzer's
        -- aura-gate clears and wildcard proofs must not bless it.
        UNIT_AURA_BLOCKED = { 4, gateGoverned = false },
        -- UNIT_IN_RANGE_UPDATE: SecretPayloads = true (UnitDocumentation) —
        -- the WHOLE payload (unitTarget pos 3, isInRange pos 4) is ALWAYS
        -- secret, not restriction-conditional, and RegisterUnitEvent
        -- filtering does not declassify it. gateGoverned = false: the aura
        -- gate proves nothing about range payloads. Production handlers use
        -- per-unit lexical-token listeners and never touch the payload
        -- (groupframes _state.HandleRangeUpdate, MRB range listeners,
        -- unitframes boss listeners).
        UNIT_IN_RANGE_UPDATE = { 3, 4, gateGoverned = false },
        -- UNIT_POWER_POINT_CHARGE: SecretWhenUnitPowerRestricted — payload
        -- unitTarget (pos 3) secretizes under power restriction. The aura
        -- gate does not govern power secrecy → gateGoverned = false.
        UNIT_POWER_POINT_CHARGE = { 3, gateGoverned = false },
        -- UNIT_SPELLCAST_* family: SecretWhenUnitSpellCastRestricted —
        -- unitTarget (3), castGUID (4), spellID (5) secretize on every
        -- member; castBarID is NeverSecret wherever it appears (last
        -- position). Extra members per payload doc
        -- (tests/api-docs/blizzard/UnitDocumentation.lua 4431-4680):
        -- CHANNEL_STOP/INTERRUPTED add interruptedBy (6); EMPOWER_STOP adds
        -- complete (6) + interruptedBy (7); SENT has target cstring
        -- (ConditionalSecret, 4) shifting castGUID/spellID to 5/6.
        -- INTERRUPTIBLE/NOT_INTERRUPTIBLE carry NO SecretWhen flag
        -- (unitTarget-only payload) — deliberately unwired. The spellcast
        -- class is not aura-gate governed → gateGoverned = false on all.
        UNIT_SPELLCAST_SUCCEEDED = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_START = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_STOP = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_CHANNEL_START = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_CHANNEL_UPDATE = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_DELAYED = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_FAILED = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_FAILED_QUIET = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_EMPOWER_START = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_EMPOWER_UPDATE = { 3, 4, 5, gateGoverned = false },
        UNIT_SPELLCAST_CHANNEL_STOP = { 3, 4, 5, 6, gateGoverned = false },
        UNIT_SPELLCAST_INTERRUPTED = { 3, 4, 5, 6, gateGoverned = false },
        UNIT_SPELLCAST_EMPOWER_STOP = { 3, 4, 5, 6, 7, gateGoverned = false },
        UNIT_SPELLCAST_SENT = { 3, 4, 5, 6, gateGoverned = false },
        -- GUILD_MOTD / READY_CHECK: SecretInChatMessagingLockdown
        -- (GuildInfoDocumentation:450 / PartyInfoDocumentation:841) — the
        -- whole payload secretizes under chat-messaging lockdown, which the
        -- aura gate does not govern.
        GUILD_MOTD = { 3, gateGoverned = false },
        READY_CHECK = { 3, 4, gateGoverned = false },
        -- RUNE_POWER_UPDATE: SecretPayloads = true (UnitDocumentation:3873)
        -- — ALWAYS secret, not restriction-conditional (the
        -- UNIT_IN_RANGE_UPDATE class).
        RUNE_POWER_UPDATE = { 3, 4, gateGoverned = false },
        -- CHAT_MSG_* (every QUI-registered member): SecretInChatMessaging-
        -- Lockdown with an IDENTICAL 18-member payload across the family
        -- (ChatInfoDocumentation). Secret-capable positions: text (3),
        -- playerName (4), playerName2 (7), guid (14), bnSenderID (15),
        -- discordInfo (20); every other member is NeverSecret. Chat
        -- lockdown is not aura-gate governed.
        CHAT_MSG_WHISPER = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_BN_WHISPER = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_SYSTEM = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_CHANNEL = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_CHANNEL_NOTICE = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_COMMUNITIES_CHANNEL = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_BN_INLINE_TOAST_ALERT = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_BN_INLINE_TOAST_BROADCAST = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE = { 3, 4, 7, 14, 15, 20, gateGoverned = false },
        -- COVERAGE GAP: CLOSED 2026-07-21 — every QUI-registered event
        -- carrying a Secret* flag in the api-index is wired above
        -- (round-22b recount 26 → spellcast family 13 → chat family +
        -- GUILD_MOTD/READY_CHECK/RUNE_POWER_UPDATE → 0). Count methodology
        -- for future audits: direct RegisterEvent/RegisterUnitEvent
        -- literals + the chat capture frame's EXTRA_EVENTS/SYSTEM_EVENTS
        -- lists + the explicit CHAT_MSG_CHANNEL_NOTICE handler
        -- (message_capture). Registering a NEW secret-flagged event without
        -- wiring it here re-opens the gap — grep the api-index for
        -- Secret* flags on any event you add.
        -- The capture frame ALSO registers every CHAT_MSG_* in Blizzard's
        -- ChatTypeGroupInverted at runtime (47 secret-flagged in the index),
        -- but those all route through the ONE generic capture handler whose
        -- probe discipline is audited directly — the analyzer keys on
        -- per-event comparisons, so they are not separate gaps. Earlier
        -- counts (45, 2026-07-19) included families with ZERO remaining
        -- references in QUI source (VOICE_CHAT_CHANNEL_*, UNIT_DISTANCE_
        -- CHECK_UPDATE, UNIT_MAX_HEALTH_MODIFIERS_CHANGED, ARENA_CROWD_
        -- CONTROL_SPELL_UPDATE, PLAYER_SOFT_INTERACT_CHANGED, START/CANCEL_
        -- PLAYER_COUNTDOWN) — unregistered events have no handlers to
        -- analyze and do not belong in this count.
        -- Wiring an event here requires reading its Payload doc for WHICH
        -- positions secretize and whether the class is gate-governed — wrong
        -- positions flood false positives. Add per-family as handlers are
        -- audited; do not bulk-enable.
    },
    coverage = {
        secretWhenCooldownsRestricted = true,
        -- Generic 12.1 restriction class: ANY SecretWhen*Restricted flag
        -- (aura, spellcast, stats, identity, power, health-max, comparison,
        -- threat, ...). Before this key existed only the cooldown flag made
        -- an API a taint source — unguarded UnitCastingInfo / UnitHealthMax /
        -- GetUnitSpeed truth-tests all scanned green.
        secretWhenRestricted = true,
        isSecretReturn = true,
        secretArguments_restricted = true,
    },
    extra_safe_sinks = {},
    extra_restriction_gates = {
        -- Module-local wrappers around C_Secrets.ShouldAurasBeSecret. The
        -- analyzer is non-interprocedural, so wrapper CALLS must be
        -- registered by name (round-4 alias resolution surfaced the hoisted
        -- C_UnitAuras refs these wrappers gate).
        "AurasAreSecret",           -- groupframes_auras / groupframes_missing_raid_buffs
        "AreAurasSecret",           -- cdm_sources local re-import
        "CDMSources.AreAurasSecret",
    },
    -- ==================================================================
    -- LANDED (round-13/13b, 2026-07-18 — closes out Drew's "secret-to-
    -- state collapse" audit). "Strict" today = recognized findings
    -- promoted to CI-blocking; it is NOT strict information-flow
    -- enforcement — see REMAINING below for what's still open.
    --  1. <secret-collapse> rule (round-13b): guard-secret-dominated
    --     branches flag literal returns/state-writes; sanctioned shapes
    --     carry `-- @secret-policy: <name>` — the ONLY suppression for
    --     that sink; `@secret-safe` deliberately does not apply. 127
    --     named policy annotations across strict paths (vocab:
    --     reject-secret-value, reject-secret-ids, opaque-value-present,
    --     route-to-text-sink, keep-visible-when-unknown, keep-native-
    --     when-unknown, empty-table-degrade, empty-text-degrade,
    --     neutral-color-degrade, readable-only-scan, skip-capture-when-
    --     unknown, skip-update-when-unknown, report-secret-detected,
    --     report-unreadable-defer, evict-when-unreadable, encode-secret-
    --     as-placeholder, probe-charges-when-unknown, assume-cooldown-
    --     when-unknown).
    --  2. Unknown METHOD consumers default-reject (round-13); documented
    --     `SecretArguments` restrictions reject on both tracks; sink
    --     allowlist GENERATED FROM THE API INDEX
    --     (secretArgumentsAnyTainted / durationObjectArg / scriptObject,
    --     cross-system most-restrictive merge — see
    --     tests/taint/index_load.lua); hand-kept builtins trimmed to the
    --     argless trio, pinned as a subset-of-index by registry_test.
    --  3. strict_paths now includes QUI_UnitFrames/unitframes/,
    --     modules/qol/, modules/combat/, modules/skinning/,
    --     modules/trackers/ (163 promoted findings burned down).
    --  5. Offline throw-semantics instrumentation:
    --     tests/helpers/secret_instrument.lua (truthiness/`==`/`~=`/`#`
    --     splices; cross-type `==` throws offline now) — 11 boundary
    --     tests load modules through SecretSentinel.LoadInstrumented; it
    --     already caught 2 strict-green live crashes.
    --
    -- REMAINING:
    --  4. Aspect analysis still disabled (aspect_paths = {}), pending
    --     receiver PROVENANCE — the registered secret-event payload gap
    --     (26 events as of the 2026-07-21 recount — see the
    --     event_payload_params COVERAGE GAP note) remains unwired.
    --  - RequiresComparableUnitTokens is DELIBERATELY not in
    --    restriction_preconditions: its FailureMode is "ReturnNothing"
    --    (SecretPredicatesDocumentation:11) — incomparable-token calls
    --    yield nil, they do not error — so the precondition scan's
    --    hard-error premise does not apply and wiring it would FP every
    --    nil-tolerant statement-split site (CheckUnitRange, unitframes
    --    boss-target loop, LibRangeCheck isPet). The secret-RETURN axis
    --    (SecretWhenUnitComparisonRestricted) is covered by probe rules.
    --    Only FailureMode = "Error" predicates (RequiresUnitAuraAccess)
    --    belong in restriction_preconditions.
    --  - conditionalSecretContents (round-22): the extractor now captures
    --    per-return ConditionalSecretContents (GetUnitAuras' auras table:
    --    container readable, ELEMENTS secretize) into the index; the key
    --    is deliberately non-source in index_load (container truth-tests
    --    are safe — whole-call sourcing would FP every `if auras`).
    --    Element-level hazard modeling ("secret contents of a safe
    --    container": flag unprobed element/field use of such returns) is
    --    WIRED as of round-23: marker-based element taint on flagged
    --    returns, driven by two config keys — element_secret_functions
    --    (call-site spellings of wrapper functions whose result 1 carries
    --    the hazard; C_UnitAuras.GetUnitAuras itself stays index-wired,
    --    not listed here) and element_container_params (helper name ->
    --    declared-param positions, for helpers that receive an
    --    already-tainted container as an argument rather than a call
    --    result). Adding a wrapper requires the spelling audit: grep every
    --    call-site spelling of the wrapper across the repo and list each
    --    distinct one; value-copy aliases (`local Get =
    --    C_UnitAuras.GetUnitAuras`, incl. `A and A.f` chains) resolve
    --    automatically and must NOT be listed, but receiver-import
    --    spellings (`Sources.QueryUnitAuras` where `Sources` is a local
    --    table alias, not a function-value copy) do NOT resolve and MUST
    --    be listed individually — a missed spelling is a silent false
    --    negative the strict scan cannot surface on its own. Runtime
    --    choke-point probes remain defense-in-depth (round-16 canon).
    --  - Round-13b collapse-rule NON-GOALS (known and accepted): bare
    --    `Show()`/`Hide()` calls inside guard-secret branches are
    --    unflagged (call-shaped defer is indistinguishable from
    --    call-shaped state manufacture); literals laundered through a
    --    local (`local v = true ... return v`) evade the scan;
    --    stored-boolean guards (`local b = G(x)`) are invisible;
    --    terminating untaint-then fall-through (`if not G(x) then ...
    --    return end; return 0` — the fall-through IS the secret region)
    --    is unflagged; plain undocumented FUNCTION consumers remain
    --    traversal-only (non-interprocedural boundary — hand-audit
    --    helpers).
    --  - Two instrumentation-discovered analyzer-gap classes (2026-07-18,
    --    both were strict-green live crashes until Task 7's boundary
    --    tests caught them): (a) helper-PARAM probe-order blindness —
    --    `param == nil` before probe inside a helper function body
    --    escapes seeding (focuscastalert.lua:179 class; non-
    --    interprocedural); (b) availability-compound probe inside one
    --    condition — `x and not (G and G(x))` truth-tests x before the
    --    in-expression probe (reticle.lua:439 class).
    --
    -- A green strict scan is still not information-flow PROOF — it now
    -- polices the collapse class, with the enumerated non-goals above.
    -- ==================================================================
    extra_guards = {
        -- Module-local wrappers around Helpers.IsSecretValue. The analyzer is
        -- non-interprocedural, so wrapper FUNCTIONS (not bare aliases) must be
        -- registered by name to participate in guard proofs.
        "IsSecret",              -- QUI_Chat convention (11 files)
        "ResolverIsSecretValue", -- cdm_resolvers
        "ScannerIsSecretValue",  -- spellscanner local issecretvalue wrapper
        "IsSecretSpellcastPayload", -- resourcebars UNIT_SPELLCAST_SUCCEEDED payload probe (spellID, castGUID)
        "IsPreviewSecretValue",  -- action_bars_preview_driver Helpers.IsSecretValue wrapper
                                 -- (renamed from a bare IsSecretValue local: builtin guard
                                 -- names bound to function literals read as impostors under
                                 -- the direct-hit shadow rule)
        "RenderIsSecretValue",   -- groupframes_aura_render wrapper (same rename rationale;
                                 -- also had a dead duplicate or-chain binding that poisoned
                                 -- the bare name outright)
    },
    -- Round-23 element-taint class (conditionalSecretContents): wrapper
    -- functions whose RESULT 1 is a readable container with secret-capable
    -- ELEMENTS. Entries are CALL-SITE spellings (literal matching) — when
    -- adding a wrapper, grep every call spelling and list each; a missed
    -- spelling is a silent FN the strict scan cannot surface. Value-copy
    -- aliases (`local Get = C_UnitAuras.GetUnitAuras`) resolve
    -- automatically; receiver-import spellings (`Sources.QueryUnitAuras`)
    -- do not and must be listed.
    element_secret_functions = {
        "Sources.QueryUnitAuras",
        -- Definition-spelling (cdm_sources.lua:676); zero live call sites
        -- use it today — kept as future-proofing for direct callers.
        "CDMSources.QueryUnitAuras",
        -- Task-6 audit (2026-07-21): grep across QUI_ActionBars, QUI_Bags,
        -- QUI_CDM, QUI_Chat, QUI_DamageMeter, QUI_Debug, QUI_GroupFrames,
        -- QUI_Logger, QUI_Options, QUI_ResourceBars, QUI_UnitFrames, core,
        -- modules, init.lua surfaced no further QueryUnitAuras receiver
        -- spellings beyond the two above; C_UnitAuras.GetUnitAuras is
        -- index-wired (excluded) and _C_GetUnitAuras (cdm_sources.lua:454,
        -- `local _C_GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras`)
        -- is a value-copy alias (analyzer-resolved, excluded).
    },
    -- Helper PARAMS holding element-secret containers (positions index
    -- the DECLARED parameter list; colon-method self is not counted).
    element_container_params = {
        CopyReadableAuras = { 1 }, -- groupframes_auras.lua:780 (src)
        ScanAuraListForAtonement = { 2 }, -- atonement_counter.lua:201 (auraList)
    },
    extra_unwraps = {
        -- QUI imports Helpers.Safe* as bare locals at file scope and calls
        -- them by short name. Register the short forms so the analyzer
        -- recognizes those call sites as unwraps (review-tier findings).
        "SafeValue",
        "SafeToNumber",
        "SafeToString",
        "SafeCompare",
        "SafeNumberOrNil",
    },
    clean_fields = {
        -- Field names that are always non-secret per Blizzard's API contract.
        -- When the analyzer sees `tainted_local.<field>` for any of these,
        -- it treats the read as clean instead of propagating taint.
        -- Every entry must carry NeverSecret = true on EVERY structure field
        -- of that name in tests/api-docs/blizzard/ that belongs to a
        -- secret-guarded structure; tests/unit/taint_clean_fields_test.lua
        -- enforces that against the generated docs.
        "isOnGCD",  -- SpellCooldownInfo.isOnGCD
        "isActive",  -- SpellCooldownInfo / SpellChargeInfo / SpellLossOfControlInfo
        "isEnabled",  -- SpellCooldownInfo.isEnabled
        "maxCharges",  -- SpellChargeInfo.maxCharges
        "shouldReplaceNormalCooldown",  -- SpellLossOfControlInfo
    },
}
