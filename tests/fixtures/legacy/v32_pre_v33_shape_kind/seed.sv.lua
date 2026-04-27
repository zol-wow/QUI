-- Profile at _schemaVersion = 32, before the v33 MigrateContainerShapeAndEntryKind
-- migration ran.
--
-- Exercises:
--   * Container.shape stamping from legacy containerType across all four
--     legacy values (aura → icon, auraBar → bar, cooldown → icon,
--     customBar → icon).
--   * Entry.kind stamping for spell vs non-spell entries on previously-
--     aura containers (aura/auraBar) — spell entries stamped kind="aura",
--     items/trinkets/slots/macros stamped kind="cooldown".
--   * Entry.kind stamping on previously-cooldown / customBar containers —
--     non-spell entries stamped kind="cooldown", spell entries left nil
--     for the runtime classifier.
--   * Per-spec entry storage walk (db.global.ncdm.specTrackerSpells)
--     receives the same stamping logic.
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            _schemaVersion = 32,

            ncdm = {
                enabled = true,
                containers = {
                    -- Custom user-created cooldown container (icons, multi-row).
                    -- Migration: shape="icon"; spell entry kind left nil for runtime.
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

                    -- Custom user-created aura container (icons).
                    -- Migration: shape="icon"; spell entries get kind="aura"
                    -- (because container was aura-flavored pre-v33);
                    -- non-spell entries get kind="cooldown".
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

                    -- Custom user-created aura BAR container (real StatusBar).
                    -- Migration: shape="bar"; spell entries get kind="aura".
                    custom_bar = {
                        builtIn = false,
                        containerType = "auraBar",
                        name = "Custom Aura Bars",
                        enabled = true,
                        ownedSpells = {
                            { type = "spell", id = 55555 },
                        },
                    },

                    -- Legacy customBar (already migrated by v32 from
                    -- customTrackers.bars[]). Migration: shape="icon" (these
                    -- always rendered as single-row icons). Spell entries
                    -- left nil; non-spell stamped cooldown.
                    customBar_legacy_one = {
                        _legacyId = "legacy_one",
                        _migratedFromCustomTrackers = true,
                        builtIn = false,
                        containerType = "customBar",
                        name = "Legacy Bar One",
                        enabled = true,
                        anchorTo = "disabled",
                        iconSize = 32,
                        spacing = 4,
                        borderSize = 1,
                        borderColor = { 0, 0, 0, 1 },
                        layoutDirection = "HORIZONTAL",
                        pos = { ox = 100, oy = -100 },
                        row1 = { iconCount = 6, iconSize = 32 },
                        row2 = { iconCount = 0 },
                        row3 = { iconCount = 0 },
                        entries = {
                            { type = "spell", id = 77777 },
                            { type = "item",  id = 444 },
                        },
                    },

                    -- Spec-specific customBar with entries already in per-spec
                    -- storage (post-v32 d). Migration walks those too.
                    customBar_specced = {
                        _legacyId = "specced",
                        _migratedFromCustomTrackers = true,
                        _sourceSpecID = 250,
                        _specEntriesPortedB3 = true,
                        builtIn = false,
                        containerType = "customBar",
                        name = "Spec Bar",
                        enabled = true,
                        anchorTo = "disabled",
                        iconSize = 36,
                        spacing = 2,
                        specSpecific = true,
                        layoutDirection = "VERTICAL",
                        pos = { ox = -200, oy = 50 },
                        row1 = { iconCount = 8, iconSize = 36 },
                        row2 = { iconCount = 0 },
                        row3 = { iconCount = 0 },
                        entries = {},
                    },
                },
            },
        },
    },
    global = {
        ncdm = {
            specTrackerSpells = {
                customBar_specced = {
                    ["250"] = {
                        { type = "spell", id = 88888, _sourceSpecID = 250 },
                        { type = "trinket", id = 14, _sourceSpecID = 250 },
                    },
                },
            },
        },
    },
}

QUIDB = {}
