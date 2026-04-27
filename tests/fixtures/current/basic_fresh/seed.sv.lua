-- A minimal fresh-install profile shape under today's defaults.
-- Round-trip should be lossless: expected.sv.lua should equal this.
QUI_DB = {
    profileKeys = {
        ["TestChar - TestRealm"] = "Default",
    },
    profiles = {
        Default = {
            -- Empty profile — AceDB serves everything from defaults.
            -- After migrations + strip, the only key persisted should be
            -- whatever migrations explicitly stamp (e.g. _schemaVersion if
            -- it differs from the default).
        },
    },
}
QUIDB = {}
