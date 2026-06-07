# v40 → v41: displayMode translation — the no-chat-table profile

A pre-v41 profile with NO `chat` table at all (fully default chat, or
pre-displayMode era — AceDB strips the "blizzard" default, so absence
means never-opted-in). v41 must create `chat = { enabled = false }` so
the user gets stock chat, not a silent switch into the takeover.
