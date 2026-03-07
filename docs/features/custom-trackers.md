---
layout: default
title: Custom Trackers
parent: Features
nav_order: 12
---

# Custom Trackers

Custom Trackers let you create personal tracking bars for any spell or item in the game. If the Cooldown Manager tracks your rotation abilities automatically, Custom Trackers are where you define exactly what else you want to watch -- a specific trinket proc, a raid buff, a consumable cooldown, or anything with a spell or item ID.

## Overview

Each tracker bar displays one spell or item as a status bar with an icon, optional keybind text, and configurable layout. You can create as many tracker bars as you need, and each one has its own size, icon, and positioning options. Tracker bars support two layout modes -- a dynamic layout that automatically arranges icons, and a clickable icon mode that lets you interact with the icons directly. These two modes are mutually exclusive; you choose one or the other per bar.

Tracker bars can be positioned freely on screen, or snapped and locked to existing frames -- including non-QUI frames like Blizzard's default player and target unit frames. This makes it easy to build a compact HUD even if you are mixing QUI with other addons.

## How to Enable

Custom Trackers are configured per-character. To create and manage trackers:

- Open `/qui` and navigate to the **Trackers > Custom Trackers** tab.
- Click **Add Tracker** and enter a spell ID or item ID.

Visibility rules for all tracker bars are managed in the **Custom Trackers Visibility** tab under **UI > HUD Visibility**.

## Key Features

- **User-defined spell and item tracking** -- Track any spell or item by entering its ID. Each tracker bar displays the icon, cooldown progress, and duration as a status bar.
- **Dynamic layout** -- Automatically arranges tracker icons in a row or column with configurable growth direction and spacing.
- **Clickable icons** -- Icons function as clickable buttons, letting you use the tracked ability directly from the tracker bar.
- **Snap and lock to frames** -- Anchor tracker bars to Blizzard's default player or target unit frames, or to other QUI elements, without requiring QUI unit frames to be active.
- **Visibility rules** -- Tracker bars share the same visibility rule system used by the CDM and Unit Frames: always visible, in combat, when target exists, in group, in instance, on mouseover, and conditional hide rules for mounted, flying, and skyriding states.
- **Keybind display** -- Shows the keybind for the tracked ability on its icon, using the same formatting and positioning system as CDM keybinds.
- **Per-bar customization** -- Each tracker bar can have independent width, height, icon size, and bar texture settings.

{: .important }
Dynamic layout and clickable icons are mutually exclusive. When dynamic layout is active, icons are positioned automatically and cannot be clicked. When clickable icons are active, you interact with the icons directly but lose automatic arrangement. Choose the mode that fits your use case.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Spell/Item ID | The spell or item to track | -- |
| Dynamic layout | Auto-arrange icons in a row or column | Disabled |
| Clickable icons | Make tracker icons interactive buttons | Disabled |
| Snap to frame | Anchor the tracker bar to a player/target frame | None |
| Lock position | Prevent accidental repositioning | Disabled |
| Show keybinds | Display keybind text on tracker icons | Enabled |
| Visibility rules | When to show/hide all tracker bars | Always |

## Tips

{: .note }
Custom Trackers are stored per-character, not per-profile. Each character maintains its own set of tracked spells and items, so you can tailor the trackers to each character's kit without affecting your other characters.

{: .important }
All custom tracker bars share a single set of visibility rules, configured in the Custom Trackers Visibility tab. You cannot set different visibility rules for individual tracker bars -- they all show and hide together.

{: .note }
If you want to track a trinket or on-use item, use the item ID rather than the spell ID of its effect. This ensures the tracker correctly monitors the item's cooldown and displays the correct icon.
