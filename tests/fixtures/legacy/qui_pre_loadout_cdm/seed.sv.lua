-- LDTS-02: Pre-loadout _specProfilesByProfile shape (3-dim).
--
-- This fixture pins the storage shape used by QUI before the per-loadout
-- CDM milestone added a 4th dimension keyed by loadoutID. The container
-- keys (essential, utility, buff, trackedBar) sit DIRECTLY under
-- store[profileName][specID] — there is no integer loadoutID intermediate.
--
-- In-game, the new GetSpecLoadoutProfileStore helper detects this shape on
-- first access and re-wraps the data under sentinel slot 0:
--   store[profileName][specID] = { [0] = <legacy specSlot> }
--
-- The headless harness in tools/test_profiles.lua does NOT call
-- GetSpecLoadoutProfileStore. It only runs BackwardsCompat() (db.profile
-- migrations) and round-trips db.profile through export/import. The
-- db.char section (where this fixture's data lives) round-trips verbatim.
-- expected.sv.lua therefore mirrors this seed for the char section.
--
-- The migration LOGIC is asserted to exist in code by the LDTS-01 grep
-- assertions in tests/cdm_spec_tracking_persistence_test.lua.
--
-- Spec 65 = Affliction Warlock (chosen arbitrarily; any positive specID works).
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            -- No _schemaVersion change is required for this fixture:
            -- db.char (where this data lives) is outside Migrations.Run scope.
        },
    },
    char = {
        ["TestChar - TestRealm"] = {
            ncdm = {
                _specProfilesByProfile = {
                    Default = {
                        [65] = {
                            -- LEGACY 3-DIM SHAPE: container keys directly under specID
                            essential = {
                                ownedSpells   = { 686, 980, 48181 },
                                removedSpells = {},
                                dormantSpells = {},
                                dormantSequence = 0,
                            },
                            utility = {
                                ownedSpells   = { 5697 },
                                removedSpells = {},
                                dormantSpells = {},
                                dormantSequence = 0,
                            },
                        },
                    },
                },
            },
        },
    },
}
QUIDB = {}
