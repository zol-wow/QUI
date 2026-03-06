---
layout: default
title: Custom Trackers
parent: Settings Reference
nav_order: 9
---

# Custom Trackers

Custom Trackers allow you to define personal spell and item tracking bars that display cooldowns, buffs, debuffs, and item availability. Settings are managed through the `/qui` > Custom Trackers tab. Tracker definitions are stored per-profile.

Individual tracker definitions -- including spell IDs, item IDs, bar appearance, colors, and display behavior -- are configured entirely through the in-game GUI and are not covered here. This page documents the global visibility and display settings that apply to all custom trackers.

---

## Visibility Settings

Controls when custom tracker bars are shown or hidden. Found in `db.profile.customTrackersVisibility`.

### Show Conditions

At least one show condition must be satisfied for the trackers to appear. When `showAlways` is enabled, the other show conditions are ignored.

| Setting | Type | Default | Description |
|---|---|---|---|
| `showAlways` | boolean | `true` | Always show trackers regardless of other conditions |
| `showWhenTargetExists` | boolean | `false` | Show trackers when you have a target |
| `showInCombat` | boolean | `false` | Show trackers while in combat |
| `showInGroup` | boolean | `false` | Show trackers while in a party or raid |
| `showInInstance` | boolean | `false` | Show trackers while in a dungeon or raid instance |
| `showOnMouseover` | boolean | `false` | Show trackers on mouseover |

### Fade Behavior

| Setting | Type | Default | Description |
|---|---|---|---|
| `fadeDuration` | number | `0.2` | Duration of the fade in/out animation in seconds |
| `fadeOutAlpha` | number | `0` | Alpha value when trackers are faded out (0 = fully hidden) |

### Hide Overrides

These conditions force trackers to hide even when a show condition is met.

| Setting | Type | Default | Description |
|---|---|---|---|
| `hideWhenMounted` | boolean | `false` | Hide trackers while mounted |
| `hideWhenFlying` | boolean | `false` | Hide trackers while flying |
| `hideWhenSkyriding` | boolean | `false` | Hide trackers while skyriding |
| `dontHideInDungeonsRaids` | boolean | `false` | Override hide conditions inside dungeons and raids |

---

## Keybind Display

| Setting | Type | Default | Description |
|---|---|---|---|
| `keybindOverridesEnabledTrackers` | boolean | `true` | Show keybind text on custom tracker bars |

---

## Notes

- Tracker definitions (spell IDs, item IDs, bar appearance, icons, colors) are configured through the in-game GUI and stored as per-profile data arrays.
- The visibility system uses a priority model: hide overrides take precedence over show conditions, except when `dontHideInDungeonsRaids` is enabled inside instanced content.
- Mouseover detection (`showOnMouseover`) uses the fade duration and fade-out alpha settings to control the transition.
