# v40 → v41: orphaned chat-key purge

Profile at `_schemaVersion = 40` carrying every key the chat takeover
orphaned: `displayMode` (the old blizzard/custom switch), `hideButtons`,
the `chatTab` border-color pair, and the ChatFrame1 `frameSize` /
`framePosition` persistence from the deleted sizing helper.

v41 `PurgeOrphanedChatKeys` must delete all six and leave the live chat
keys (`enabled`, `customDisplay`, `tabs`) untouched.
