# ace_db_stripped_relative_only

The AceDB-default-stripped variant of the v24/v25 anchor bug: point=nil
(stripped because it matched defaults) but relative=TOPRIGHT with non-zero
offsets. v25's RepairDisabledStaleCornerEntries must catch this fingerprint.

Reference: core/migrations.lua lines 64-68.
