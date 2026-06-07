-- Profile at _schemaVersion = 40 carrying every chat key orphaned by the
-- takeover. v41 PurgeOrphanedChatKeys must remove all nine (incl. the
-- nested hyperlinks.interactiveNames) and leave the live keys (enabled,
-- customDisplay, tabs, hyperlinks.coordinates) untouched.
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            _schemaVersion = 40,
            chat = {
                enabled = true,
                displayMode = "custom",
                hideButtons = false,
                chatTabBorderColor = { 0.1, 0.2, 0.3, 1 },
                chatTabBorderColorSource = "custom",
                frameSize = { w = 512, h = 256 },
                copyHistorySource = "persisted",
                scrollbackLines = 2500,
                hyperlinks = { coordinates = true, friendlyURLs = false, interactiveNames = true },
                framePosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 32, y = 48 },
                customDisplay = {
                    width = 430,
                    height = 190,
                    tabs = {
                        { name = "Guild", groups = { GUILD = true }, invert = false },
                    },
                },
                tabs = {
                    [1] = { customized = true, groups = { "SAY", "GUILD" }, channels = {} },
                },
            },
        },
    },
}
