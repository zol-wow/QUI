-- Idempotency baseline: profile is already at the current schema, so
-- migrations should be a no-op. The fixture's snapshot stability across
-- the export/import roundtrip is the real test; these invariants pin
-- specific properties (schema version, engine value) that must survive
-- import unchanged.
return {
    {
        name = "_schemaVersion stays at CURRENT after re-run",
        assert = function(sv, ctx)
            return sv.QUI_DB.profiles.Default._schemaVersion == 35
        end,
    },
    {
        name = "no migration touched the engine value",
        assert = function(sv, ctx)
            return sv.QUI_DB.profiles.Default.cdm
                and sv.QUI_DB.profiles.Default.cdm.engine == "owned"
        end,
    },
}
