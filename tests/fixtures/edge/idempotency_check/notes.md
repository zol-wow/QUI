# idempotency_check

Profile already at current schema (_schemaVersion = 33). Verifies migrations
are a no-op when applied to already-migrated data. The invariants.lua file
is a forward-looking artifact — the runner doesn't yet execute invariants
(that's Task 20). For now this fixture's snapshot match suffices; Task 20
will wire invariant execution.
