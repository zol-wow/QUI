-- Pre-v41 profile with no chat table (fully default chat / pre-displayMode).
-- v41 must hand it STOCK chat (chat.enabled = false), not the takeover.
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            _schemaVersion = 40,
            cdm = { engine = "owned" },
        },
    },
}
