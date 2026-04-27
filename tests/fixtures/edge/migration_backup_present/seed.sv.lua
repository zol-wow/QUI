-- A profile carrying a _migrationBackup buffer in the seed. Verifies that
-- the export path strips it (see core/profile_io.lua line ~1860) and that
-- import doesn't restore it.
QUI_DB = {
    profileKeys = {
        ["TestChar - TestRealm"] = "Default",
    },
    profiles = {
        Default = {
            _schemaVersion = 32,
            _migrationBackup = {
                slots = {
                    { stamp = 1700000000, profile = { _schemaVersion = 30, custom = "snapshot" } },
                },
            },
        },
    },
}
QUIDB = {}
