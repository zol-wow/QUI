-- Profile at _schemaVersion = 31, before the v32 OptionsV2BranchConsolidated
-- migration ran. Exercises all five sub-transforms:
--
--   (a) MigrateCustomTrackersToContainers:
--       customTrackers.bars[] -> ncdm.containers["customBar_<id>"]
--       Two bars: one plain (no spec), one spec-specific with entries.
--
--   (b) RemovePartyTrackerData:
--       quiGroupFrames.party.partyTracker and .raid.partyTracker stripped.
--
--   (c) FinalizeCustomBarContainers:
--       row1 synthesised from flat iconSize/spacing/etc.;
--       QUIDB.specTrackerSpells["test_bar_spec"]["250"] ported to
--       QUIDB.ncdm.specTrackerSpells["customBar_test_bar_spec"]["250"].
--
--   (d) FinalizeLegacyTrackerSpecState:
--       specSpecificSpells=true promoted to specSpecific=true;
--       _sourceSpecID stamped from ncdm._lastSpecID = 250;
--       container.entries moved into QUIDB.ncdm.specTrackerSpells per-spec.
--
--   (e) MigrateContainerShapeAndEntryKind:
--       Stamps container.shape from legacy containerType (aura → icon,
--       auraBar → bar, cooldown → icon, customBar → icon). Stamps
--       entry.kind on entries: spell entries on previously-aura
--       containers (aura/auraBar) get kind="aura"; non-spell entries
--       (item/trinket/macro) get kind="cooldown" everywhere; spell
--       entries on cooldown/customBar containers are left for the
--       runtime classifier. Walks both per-container entries and the
--       global per-spec entry storage. Three standalone containers
--       (custom_cd / custom_aura / custom_bar) seeded directly under
--       ncdm.containers exercise the cooldown/aura/auraBar branches;
--       the customBar branch is exercised via the customBar_*
--       containers that transforms (a)/(c)/(d) synthesise above.
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            _schemaVersion = 31,

            -- ----------------------------------------------------------------
            -- Input for transform (a): legacy custom tracker bars
            -- ----------------------------------------------------------------
            customTrackers = {
                bars = {
                    -- Bar 1: plain bar, no spec specificity, has offsetX/offsetY
                    {
                        id            = "test_bar_1",
                        name          = "Test Bar One",
                        enabled       = true,
                        iconSize      = 32,
                        spacing       = 4,
                        growDirection = "RIGHT",
                        maxIcons      = 6,
                        borderSize    = 1,
                        borderColor   = { 0, 0, 0, 1 },
                        aspectRatioCrop = 1.25,
                        zoom          = 0.08,
                        durationSize  = 17,
                        durationColor = { 0.8, 0.9, 1, 0.95 },
                        durationAnchor = "TOP",
                        durationOffsetX = 2,
                        durationOffsetY = -3,
                        hideDurationText = true,
                        stackSize     = 11,
                        stackColor    = { 1, 0.7, 0.2, 1 },
                        stackAnchor   = "BOTTOMLEFT",
                        stackOffsetX  = -2,
                        stackOffsetY  = 4,
                        hideStackText = true,
                        offsetX       = 120,
                        offsetY       = -80,
                        entries = {
                            { type = "spell", id = 12345 },
                            { type = "spell", id = 67890 },
                        },
                    },
                    -- Bar 2: spec-specific bar; entries here exercise transform (d)
                    -- (the drag-drop-bug path where entries were stored in bar.entries
                    -- rather than in global specTrackerSpells).
                    {
                        id                 = "test_bar_spec",
                        name               = "Spec Bar",
                        enabled            = true,
                        iconSize           = 36,
                        spacing            = 2,
                        growDirection      = "DOWN",
                        maxIcons           = 8,
                        borderSize         = 2,
                        borderColor        = { 0.2, 0.2, 0.2, 1 },
                        offsetX            = -200,
                        offsetY            = 50,
                        specSpecificSpells = true,
                        entries = {
                            { type = "spell", id = 11111 },
                            { type = "spell", id = 22222 },
                        },
                    },
                },
            },

            customTrackersVisibility = {
                showAlways = false,
                showWhenTargetExists = true,
                showInCombat = true,
                showInGroup = false,
                showInInstance = true,
                showOnMouseover = true,
                fadeDuration = 0.35,
                fadeOutAlpha = 0.25,
                hideWhenMounted = false,
                hideWhenFlying = true,
                hideWhenSkyriding = false,
                dontHideInDungeonsRaids = true,
            },

            -- ----------------------------------------------------------------
            -- ncdm block: _lastSpecID used by transforms (c) and (d).
            -- Standalone containers below are pre-existing user containers
            -- that v32(e) walks for shape/kind stamping.
            -- ----------------------------------------------------------------
            ncdm = {
                enabled    = true,
                _lastSpecID = 250,
                containers = {
                    -- containerType=cooldown → shape="icon"; spell entries
                    -- left without kind (runtime classifier handles them);
                    -- non-spell entries get kind="cooldown".
                    custom_cd = {
                        builtIn = false,
                        containerType = "cooldown",
                        name = "Custom Cooldowns",
                        enabled = true,
                        ownedSpells = {
                            { type = "spell", id = 11111 },
                            { type = "item",  id = 222 },
                            { type = "trinket", id = 13 },
                        },
                    },

                    -- containerType=aura → shape="icon"; spell entries get
                    -- kind="aura"; non-spell entries get kind="cooldown".
                    custom_aura = {
                        builtIn = false,
                        containerType = "aura",
                        name = "Custom Auras",
                        enabled = true,
                        ownedSpells = {
                            { type = "spell", id = 33333 },
                            { type = "spell", id = 44444 },
                            { type = "macro", id = 1, macroName = "Defensives" },
                        },
                    },

                    -- containerType=auraBar → shape="bar"; spell entries
                    -- get kind="aura".
                    custom_bar = {
                        builtIn = false,
                        containerType = "auraBar",
                        name = "Custom Aura Bars",
                        enabled = true,
                        ownedSpells = {
                            { type = "spell", id = 55555 },
                        },
                    },
                },
            },

            frameAnchoring = {
                ["customTracker:test_bar_1"] = {
                    point = "BOTTOMRIGHT",
                    parent = "playerFrame",
                    relative = "TOPRIGHT",
                    offsetX = 5,
                    offsetY = 7,
                    sizeStable = true,
                    autoWidth = false,
                    autoHeight = false,
                    hideWithParent = true,
                    keepInPlace = true,
                    widthAdjust = 3,
                    heightAdjust = -1,
                },
                combatTimer = {
                    point = "TOP",
                    parent = "customTracker:test_bar_1",
                    relative = "BOTTOM",
                    offsetX = 1,
                    offsetY = -2,
                    sizeStable = true,
                    autoWidth = false,
                    autoHeight = false,
                    hideWithParent = false,
                    keepInPlace = true,
                    widthAdjust = 0,
                    heightAdjust = 0,
                },
            },

            -- ----------------------------------------------------------------
            -- Input for transform (b): orphan partyTracker under group frames
            -- ----------------------------------------------------------------
            quiGroupFrames = {
                party = {
                    enabled = true,
                    partyTracker = {
                        enabled          = true,
                        someStaleField   = "should be gone after migration",
                        kickTimerEnabled = true,
                    },
                },
                raid = {
                    enabled = true,
                    partyTracker = {
                        enabled        = true,
                        anotherOrphan  = "also gone after migration",
                    },
                },
            },
        },
    },
}

-- QUIDB is the SavedVariable name used by QUICore:OnInitialize in WoW, but
-- the headless harness creates its AceDB via QUI_DB (not QUIDB).  The global
-- DB table (db.global, i.e. QUI_DB.global) is where _currentGlobalDB points.
-- Put specTrackerSpells there so transform (c)'s per-spec entry port fires.
QUIDB = {}

-- Extend QUI_DB with a global section carrying the legacy spec-tracker data.
-- AceDB reads QUI_DB.global for db.global.
QUI_DB.global = {
    specTrackerSpells = {
        -- transform (c): FinalizeCustomBarContainers copies
        -- global.specTrackerSpells["test_bar_spec"]["250"]
        -- -> global.ncdm.specTrackerSpells["customBar_test_bar_spec"]["250"]
        test_bar_spec = {
            ["250"] = {
                { type = "spell", id = 33333 },
                { type = "spell", id = 44444 },
            },
        },
    },
}
