# Damage Meter Session History Design

## Verified Blizzard API Surface

Local generated docs in `tests/api-docs/blizzard/DamageMeterDocumentation.lua` say:

- `GetAvailableCombatSessions`: "Returns a list of combat sessions currently being tracked." It returns `availableSessions` as a non-nil table of `DamageMeterAvailableCombatSession`.
- `DamageMeterAvailableCombatSession` fields are `sessionID` (number, non-nil), `name` (cstring, non-nil, not marked `NeverSecret`), and `durationSeconds` (number, nilable, not marked `NeverSecret`).
- `GetCombatSessionFromID` is `SecretWhenInCombat = true`, `SecretArguments = "AllowedWhenUntainted"`, takes non-nil `sessionID` and non-nil `DamageMeterType`, and returns non-nil `DamageMeterCombatSession`.
- `GetCombatSessionSourceFromID` is `SecretWhenInCombat = true`, `SecretArguments = "AllowedWhenUntainted"`, takes non-nil `sessionID`, non-nil `DamageMeterType`, nilable `sourceGUID`, nilable `sourceCreatureID`, and returns non-nil `DamageMeterCombatSessionSource`.
- `DamageMeterSessionType` has `Overall = 0`, `Current = 1`, and `Expired = 2`.

Design implication: QUI can support previous combat sessions without parsing combat logs. Blizzard owns the historical session list; QUI only stores the selected session ID in runtime window state and routes view fetches through the ID-based API.

## Goal

Add historical session selection to the native QUI damage meter while keeping the existing right-click header menu and per-window model. The user-facing session menu should show `Current`, `Overall`, and a `Previous` submenu. The submenu entries should use Blizzard's session `name` field.

Historical selection is runtime-only. Reloading the UI or recreating a window restores the saved `sessionType` (`Current` or `Overall`) and clears any selected previous session.

## User Experience

Right-clicking a damage meter window header opens the existing context menu.

The `Session` section becomes:

- `Current`: radio item. Clears any runtime previous-session selection, sets `sessionType = Current`, persists that session type, and refreshes.
- `Overall`: radio item. Clears any runtime previous-session selection, sets `sessionType = Overall`, persists that session type, and refreshes.
- `Previous`: submenu. Built from `C_DamageMeter.GetAvailableCombatSessions()` at menu-open time. Each row passes the returned session `name` directly as the menu label. The docs mark `name` non-nil but do not mark it `NeverSecret`, so QUI should not compare, concatenate, or `tostring()` it in Lua.

Selecting a previous session sets `window.sessionID` only and refreshes the window. It must not write `sessionID` to saved variables.

If the returned session table is empty, the `Previous` submenu shows a disabled `No previous sessions` row.

## Data Model

Each live `Window` instance gains `sessionID`, initialized to `nil` in `Window.New`.

Saved window state remains unchanged:

```lua
windows[id] = {
    damageMeterType = ...,
    sessionType = ...,
    size = ...,
    hidden = ...,
    name = ...,
}
```

No migration is required because no persisted schema is added.

## Data Fetching

Introduce a session selector helper, conceptually:

```lua
local function SessionKey(sessionType, sessionID)
    return sessionID and ("id:" .. tostring(sessionID)) or ("type:" .. tostring(sessionType))
end
```

The view cache changes from `Data._cache[sessionType][damageMeterType]` to a cache keyed by selector string, then meter type. This avoids collisions between enum values and arbitrary session IDs.

Fetch rules:

- `sessionID ~= nil`: call `C_DamageMeter.GetCombatSessionFromID(sessionID, damageMeterType)`.
- `sessionID == nil`: call `C_DamageMeter.GetCombatSessionFromType(sessionType, damageMeterType)`.

Breakdown rules mirror the window view:

- `sessionID ~= nil`: call `C_DamageMeter.GetCombatSessionSourceFromID(sessionID, damageMeterType, sourceGUID, sourceCreatureID)`.
- `sessionID == nil`: call `C_DamageMeter.GetCombatSessionSourceFromType(sessionType, damageMeterType, sourceGUID, sourceCreatureID)`.

Target reconstruction for Enemy Damage Taken also accepts the same selector so targets and attackers match the selected previous session.

## Duration And Labels

Previous session duration can come from the fetched combat session's `durationSeconds` in the same places the current code already renders session timers. Do not add duration text to `Previous` menu labels in this change: `DamageMeterAvailableCombatSession.durationSeconds` is nilable and not marked `NeverSecret`, so formatting it for menu text would require Lua-side checks and concatenation.

The header should continue showing the meter type label. A previous-session selection can be indicated through the menu active state without adding new persisted header text.

## Dirty And Reset Behavior

`DAMAGE_METER_COMBAT_SESSION_UPDATED(type, sessionID)` should mark:

- all type-backed views for that damage meter type dirty, preserving current behavior;
- the matching `id:<sessionID>` view dirty if it is cached.

`DAMAGE_METER_CURRENT_SESSION_UPDATED` continues to mark `Current` type-backed views dirty.

`DAMAGE_METER_RESET` clears all cached views, clears runtime `sessionID` on every live window, and refreshes. Saved `sessionType` remains intact.

## Testing

Add focused Lua tests for pure/helper behavior and static source guarantees:

- Session cache keys distinguish `type:1` from `id:1`.
- Runtime previous session selection is initialized to `nil` and is not written to defaults.
- The config menu contains `Current`, `Overall`, and `Previous`.
- Source includes guarded calls to `GetAvailableCombatSessions`, `GetCombatSessionFromID`, and `GetCombatSessionSourceFromID`.
- Existing duration/rate tests continue to pass for Current and Overall.

Run `luacheck` after `.lua` edits and run the damage meter unit tests touched by the change.
