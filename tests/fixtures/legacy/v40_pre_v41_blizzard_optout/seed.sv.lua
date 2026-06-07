-- Pre-v41 profile with the released default pairing (enabled = true +
-- explicit displayMode = "blizzard"): never opted into the custom display.
-- The v41 translation must hand it STOCK chat (enabled = false) instead of
-- silently switching it into the takeover. (The no-chat-table variant is
-- the sibling fixture v40_pre_v41_untouched.)
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            _schemaVersion = 40,
            chat = {
                enabled = true,
                displayMode = "blizzard",
                timestamps = { enabled = true, format = "24h" },
            },
        },
    },
}
