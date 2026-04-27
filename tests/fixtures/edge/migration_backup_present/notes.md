# migration_backup_present

Pins behavior: `_migrationBackup` is a per-profile rollback buffer that
must NOT leak through export/import. Profile_io.lua strips it during
export. This fixture's expected.sv.lua should NOT contain `_migrationBackup`
under `profiles.Default` after the round trip — proving the strip works.

Originally seeded after the linear schema versioning + migration
backup/restore work (commit 63a2a614).
