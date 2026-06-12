---
layout: default
title: Damage Meter
parent: Features
nav_order: 21
---

# Damage Meter

QUI ships a native damage meter for Midnight 12.0+. It provides QUI-styled meter windows with Layout Mode placement, selectable views, row breakdowns, and per-window appearance controls.

## How to Enable

Enabled by default. To disable, open `/qui` and navigate to **Appearance > Damage Meter (Native)** and set Visibility to *Hidden*. Re-enable by switching back to *Always* or *In Combat*.

When QUI's meter is enabled, the stock damage meter is hidden. Toggling QUI's meter off restores the stock meter on the next login.

## What you see by default

A single window appears at screen center on first login. It shows:

- Live **Damage Done** for the current combat session
- One row per source, sorted descending by damage
- Class-colored bars, spec icon on the left, "*rank*. *name*" + value on the right
- Session timer in the header (`[M:SS]` while in combat)
- Header right-click options to switch type / session
- Optional secondary value in parentheses

The window updates every 0.5s in combat / 2s idle. Both rates are user-tunable.

The window is positionable via QUI's Layout Mode. Drag any meter window to reposition; changes persist across reloads. Anchored meter windows keep their anchor pinned when resized.

## In-window controls

Right-click the header to open a context menu:

- **Meter Type** radios (11 total, grouped by metric family): Damage Done, DPS, Healing Done, HPS, Absorbs, Damage Taken, Avoidable Damage Taken, Enemy Damage Taken, Interrupts, Dispels, Deaths. Per-second views (DPS, HPS) rank by per-second values rather than total values. When secondary values are shown, Damage Done can display total plus per-second, and DPS can display per-second plus total.
- **Session** -- choose `Current`, `Overall`, or `Previous`. `Previous` opens a submenu of Blizzard-tracked combat sessions by name; selecting one changes only the live window state and is cleared by reload or reset.

Meter Type and `Current` / `Overall` choices persist across reloads.

Click any **row** to open a per-source spell breakdown popup, listing every spell that source used in the current view. The popup follows the row by default (mirrors to the opposite side when it would clip off-screen), updates live on the same ticker as the parent window, and dismisses on any outside click.

**Hover** a row to see a GameTooltip with class-colored name, the source's class, the full total in "Complete" formatting, per-second, and percent of the top source.

## Settings (`/qui` -> Appearance > Damage Meter (Native))

### Behavior

| Setting | Description |
|---|---|
| Visibility | *Always* / *In Combat* / *Hidden*. |
| Refresh Rate (Combat) | Seconds between refreshes during combat (0.1-2.0). |
| Refresh Rate (Idle) | Seconds between refreshes outside combat (0.5-5.0). |
| Show Hover Tooltip | Toggles the per-row tooltip on hover. |
| Show Pinned Self | When the local player isn't in the visible top-N, show them at the bottom anyway. |
| Show Secondary Value | Shows or hides the parenthetical secondary value on rows. |
| Auto Reset on Key Start | Clears all stored meter sessions when a Mythic+ key starts, so Overall begins at zero for that run. |
| Auto Swap Current/Overall | Optional: windows showing Overall switch to Current when a key starts, then Current switches back to Overall when the key completes. |
| Number Format | *Minimal* (1K / 2M) / *Compact* (1.5K / 2.4M) / *Complete* (1,500 / 2,400,000). |
| Icon Style | *Spec icon* / *Class icon* / *None*. |
| Breakdown Popup Position | *Next to row* / *Center of screen*. |

### Appearance: Bars

Bar height (12-30), spacing (0-8), LSM texture, fill alpha (0.1-1.0), and three color modes (Use Class Color / Use Accent Color / Custom Bar Color) with explicit priority. Optional bar-fill animations with a configurable duration (0.1-0.5s; off by default for performance).

### Appearance: Fonts

Three independently configurable font slots: Row Name, Row Value, Header. Each has its own LSM font dropdown, size slider (8-22), and outline dropdown (None / Outline / Thick Outline).

### Appearance: Colors

Window background, header text, row name, row value, and border. All accept any `{r, g, b, a}` color via the standard QUI color picker. Header text and border default to the QUI accent (nil); pick a custom color to override.

### Windows

Lists every spawned window with type/session info. Each row has **Hide** and **Delete** controls:

- **Hide** -- hides the window frame (state preserved across reload; type/session/position not lost). Useful for stashing a window without deleting it.
- **Delete** -- removes the window permanently; the windowID is never reused.

"+ Add Window" creates a new window (capped at 5).

### Per-window overrides

At the top of the page, an **Editing Window** dropdown sets what your edits affect:

- **Global** (default) -- every Appearance widget edits the shared appearance applied to every window.
- **Window N** -- each Appearance widget shows an "Override?" checkbox on its left. Off = the widget displays the global value but is greyed and not editable (so this window inherits global). On = widget is enabled; the current global value is copied into `appearance.perWindow[N]` as the starting point, and any edits land in that override.

Toggling Override OFF deletes the override key for that field -- the window resumes inheriting from global. The Editing dropdown's options include every spawned window; switching rebuilds the page so widget values display the new target.

Coverage:
- **Bars:** every widget is override-aware (height, spacing, texture, fill alpha, class/accent toggles, custom color, animation toggle/duration).
- **Fonts:** override is at the slot level (rowName / rowValue / header) -- one Override toggle per slot gates all three sub-widgets (font, size, outline) within it. Override on copies the whole `{name, size, outline}` slot from global.
- **Colors:** every color picker is override-aware (bg, headerText, rowName, rowValue, border).
- **Behavior:** Number Format and Icon Style (the two `appearance.global.*` items in Behavior) are override-aware. The other Behavior items (Visibility, Refresh Rates, Show Hover Tooltip, Show Pinned Self, Breakdown Popup Position) are window-collection-level and stay global only.

## Slash Command

| Command | Description |
|---------|-------------|
| `/quidmreset` | Reset the current damage meter session. |

## Tips

{: .note }
The meter only renders rows during/after combat. Hit a target dummy for a few seconds to see it populate.

{: .note }
If you want a quieter meter, turn off **Show Secondary Value** so each row shows only the primary number for the selected view.
