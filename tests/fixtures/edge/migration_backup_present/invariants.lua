return {
    {
        name = "migration backup absent or trimmed after migration",
        assert = function(sv, ctx)
            local backup = ctx.postMigration and ctx.postMigration._migrationBackup
            local slots = backup and backup.slots
            return slots == nil or (type(slots) == "table" and #slots <= 1)
        end,
    },
    {
        name = "migration backup snapshot excludes shipped defaults when present",
        assert = function(sv, ctx)
            local backup = ctx.postMigration and ctx.postMigration._migrationBackup
            local slot = backup and backup.slots and backup.slots[1]
            if not slot then return true end
            local snapshot = slot and slot.snapshot
            return type(snapshot) == "table" and snapshot._shippedDefaults == nil
        end,
    },
}
