-- Profile already at v32 with a spec-specific custom-tracker bar in V2 shape.
-- Per-spec entries live in db.global.ncdm.specTrackerSpells and must round-trip
-- through QUI1 export -> fresh-install import via the _quiBundledGlobals carrier.

QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            _schemaVersion = 32,
            cdm = { engine = "owned" },

            ncdm = {
                enabled = true,
                _lastSpecID = 256,  -- Discipline Priest
                containers = {
                    customBar_test_roundtrip = {
                        builtIn = false,
                        containerType = "customBar",
                        shape = "icon",
                        name = "Roundtrip Bar",
                        enabled = true,
                        specSpecific = true,
                        _sourceSpecID = 256,
                        _legacyId = "test_roundtrip",
                        _migratedFromCustomTrackers = true,
                        iconSize = 32,
                        spacing = 4,
                        growDirection = "RIGHT",
                        offsetX = 0,
                        offsetY = 0,
                        entries = {},  -- post-v32(d): cleared on spec-specific bars
                    },
                },
            },
        },
    },
}

-- The harness AceDB binds to _G.QUI_DB, so db.global corresponds to
-- QUI_DB.global (NOT QUIDB, which the live game uses but the harness ignores).
-- Per-spec entries on the V2 canonical path. Real retail Discipline Priest
-- cooldowns picked so runtime-side validation would accept them as
-- IsPlayerSpell on a Disc Priest character.
QUI_DB.global = {
    ncdm = {
        specTrackerSpells = {
            customBar_test_roundtrip = {
                ["PRIEST-256"] = {
                    { type = "spell", id = 33206 },  -- Pain Suppression
                    { type = "spell", id = 47788 },  -- Guardian Spirit
                    { type = "spell", id = 62618 },  -- Power Word: Barrier
                },
            },
        },
    },
}

QUIDB = {}
