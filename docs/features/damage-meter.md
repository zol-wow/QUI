---
layout: default
title: Damage Meter
parent: Features
nav_order: 21
---

# Damage Meter

QUI ships a native damage meter built on Blizzard's `C_DamageMeter` API (Midnight 12.0+). It replaces both the stock Blizzard meter (suppressed via CVar) and QUI's earlier skin-the-Blizzard-meter approach.

## How to Enable

Enabled by default. To disable, open `/qui` and navigate to **Appearance > Damage Meter (Native)** and set Visibility to *Hidden*. Re-enable by switching back to *Always* or *In Combat*.

When QUI's meter is enabled, Blizzard's stock damage meter is hidden (we flip the `damageMeterEnabled` CVar to 0 on login). Toggling QUI's meter off restores the Blizzard meter on the next login.

## What you see by default

A single window appears at screen center on first login. It shows:

- Live **Damage Done** for the current combat session
- One row per source, sorted descending by damage
- Class-colored bars, spec icon on the left, "*rank*. *name*" + value on the right
- Session timer in the header (`[M:SS]` while in combat)
- A gear (config) button in the header to switch type / session

The window updates every 0.5s in combat / 2s idle. Both rates are user-tunable.

The window is positionable via QUI's Layout Mode (the same handle system used by every other QUI element). Drag any meter window to reposition; changes persist across reloads.

## In-window controls

Click the **gear button** in the header to open a context menu:

- **Meter Type** radios (11 total, grouped by metric family): Damage Done, DPS, Healing Done, HPS, Absorbs, Damage Taken, Avoidable Damage Taken, Enemy Damage Taken, Interrupts, Dispels, Deaths. Per-second views (DPS, HPS) rank BY per-second rather than total — a late-joining damage dealer can rank low by Damage Done but high by DPS, which is the question those views answer. Both views always show both numbers: the primary metric large, the secondary in parens (e.g. `2.4M (180K)` for Damage Done, `180K (2.4M)` for DPS).
- **Session** radios: Current, Overall

Selections persist across reloads.

Click any **row** to open a per-source spell breakdown popup, listing every spell that source used in the current view. The popup follows the row by default (mirrors to the opposite side when it would clip off-screen), updates live on the same ticker as the parent window, and dismisses on any outside click.

**Hover** a row to see a GameTooltip with class-colored name, the source's class, the full total in "Complete" formatting, per-second, and percent of the top source.

## Settings (`/qui` → Appearance > Damage Meter (Native))

### Behavior

| Setting | Description |
|---|---|
| Visibility | *Always* / *In Combat* / *Hidden*. |
| Refresh Rate (Combat) | Seconds between refreshes during combat (0.1–2.0). |
| Refresh Rate (Idle) | Seconds between refreshes outside combat (0.5–5.0). |
| Show Hover Tooltip | Toggles the per-row tooltip on hover. |
| Show Pinned Self | When the local player isn't in the visible top-N, show them at the bottom anyway. |
| Number Format | *Minimal* (1K / 2M) / *Compact* (1.5K / 2.4M) / *Complete* (1,500 / 2,400,000). |
| Icon Style | *Spec icon* / *Class icon* / *None*. |
| Breakdown Popup Position | *Next to row* / *Center of screen*. |

### Appearance: Bars

Bar height (12–30), spacing (0–8), LSM texture, fill alpha (0.1–1.0), and three color modes (Use Class Color / Use Accent Color / Custom Bar Color) with explicit priority. Optional bar-fill animations with a configurable duration (0.1–0.5s; off by default for performance).

### Appearance: Fonts

Three independently configurable font slots: Row Name, Row Value, Header. Each has its own LSM font dropdown, size slider (8–22), and outline dropdown (None / Outline / Thick Outline).

### Appearance: Colors

Window background, header text, row name, row value, and border. All accept any `{r, g, b, a}` color via the standard QUI color picker. Header text and border default to the QUI accent (nil); pick a custom color to override.

### Windows

Lists every spawned window with type/session info. Each row has **Hide** and **Delete** controls:

- **Hide** — hides the window frame (state preserved across reload; type/session/position not lost). Useful for stashing a window without deleting it.
- **Delete** — removes the window permanently; the windowID is never reused.

"+ Add Window" creates a new window (capped at 5).

### Per-window overrides

At the top of the page, an **Editing Window** dropdown sets what your edits affect:

- **Global** (default) — every Appearance widget edits the shared appearance applied to every window.
- **Window N** — each Appearance widget shows an "Override?" checkbox on its left. Off = the widget displays the global value but is greyed and not editable (so this window inherits global). On = widget is enabled; the current global value is copied into `appearance.perWindow[N]` as the starting point, and any edits land in that override.

Toggling Override OFF deletes the override key for that field — the window resumes inheriting from global. The Editing dropdown's options include every spawned window; switching rebuilds the page so widget values display the new target.

Coverage:
- **Bars:** every widget is override-aware (height, spacing, texture, fill alpha, class/accent toggles, custom color, animation toggle/duration).
- **Fonts:** override is at the slot level (rowName / rowValue / header) — one Override toggle per slot gates all three sub-widgets (font, size, outline) within it. Override on copies the whole `{name, size, outline}` slot from global.
- **Colors:** every color picker is override-aware (bg, headerText, rowName, rowValue, border).
- **Behavior:** Number Format and Icon Style (the two `appearance.global.*` items in Behavior) are override-aware. The other Behavior items (Visibility, Refresh Rates, Show Hover Tooltip, Show Pinned Self, Breakdown Popup Position) are window-collection-level and stay global only.

## Architecture notes

For developers / curious users:

- Data layer reads from `C_DamageMeter.GetCombatSessionFromType` on a throttled ticker, not inline in event handlers. This sidesteps a class of combat-taint bugs that the old skinner had to engineer around.
- Window state lives at `db.profile.damageMeter.native.*` per profile. Per-window appearance overrides at `db.profile.damageMeter.native.appearance.perWindow[id]` are read by `QUI_DamageMeter.ResolveAppearance(windowID, ...path)`, which falls back to `.appearance.global` per-field.
- The legacy skinner namespace at `db.profile.damageMeter.{enabled,visibility,style,...}` was retired by schema migration v37; existing profiles have those keys nilled on first load post-update.
- Spec: `docs/superpowers/specs/2026-05-22-damage-meter-design.md`
- API reference (Blizzard side): `docs/blizzard/damage-meter-frames.md`

## Tips

{: .note }
The meter only renders rows during/after combat. Hit a target dummy for a few seconds to see it populate.

{: .note }
If you need to restore Blizzard's stock meter (e.g. for comparison), set Visibility to *Hidden* in QUI's settings and run `/console damageMeterEnabled 1`, then `/reload`.

{: .note }
Per-window appearance overrides have a working back end but no dedicated UI surface yet — set them directly via SavedVariables (e.g. `/run QUI.db.profile.damageMeter.native.appearance.perWindow[2] = { barHeight = 24 }` then `/reload`).
