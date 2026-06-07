# v40 → v41: displayMode translation (the opt-OUT side)

Adversarial-review High: v41 must not silently flip non-opted-in users
into the chat takeover. Two profiles at `_schemaVersion = 40`:

- `Default`: explicit `displayMode = "blizzard"` with `enabled = true`
  (the released default pairing) → post-migration `chat.enabled = false`
  (persisted: non-default), `displayMode` gone.
- `Untouched`: no `chat` table at all (fully default / pre-displayMode
  profile — AceDB strips the "blizzard" default, so absence means
  never-opted-in) → post-migration `chat = { enabled = false }`.

The opt-IN side (`displayMode = "custom"` keeps the takeover) is covered
by the sibling fixture `v40_pre_v41_chat_keys`.
