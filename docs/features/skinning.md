---
layout: default
title: Skinning
parent: Features
nav_order: 8
---

# Skinning

QUI's skinning system applies a consistent visual theme to Blizzard's default UI frames, bringing them in line with QUI's dark-background, accent-bordered aesthetic. Each skinnable frame can be individually enabled or disabled, and many have their own customization options beyond the global skin settings.

## Overview

The skinning module intercepts and reskins a wide range of Blizzard UI elements -- from the game menu and alert toasts to the loot window, objective tracker, keystone frame, and more. Rather than replacing these frames entirely, QUI overlays its own visual treatment: dark backgrounds, accent-colored borders, consistent fonts, and subtle adjustments to layout and positioning. This means Blizzard functionality is preserved while the visual presentation matches the rest of QUI.

## How to Enable

Skinning is enabled by default for most frames. To configure individual skins:

- Open `/qui` and navigate to the **Skinning** tab.

## Skinnable Frames

### Game Menu (ESC)

The Escape menu can be reskinned with QUI's style, including custom font sizing, a dimmed background overlay, and an optional QUI button for quick access to the options panel.

### Alerts and Toasts

Achievement alerts, loot toasts, and other notification popups are reskinned with QUI's dark theme. Position customization lets you move them away from the default center-screen location.

### Loot Window

A custom-skinned loot window replaces the default. Options include anchoring the loot window to your cursor for faster looting and a transmog marker that highlights items you have not yet collected for their appearance.

### Loot Roll Frames

Custom roll frames for Need/Greed/Disenchant with configurable grow direction (up or down) and spacing between multiple simultaneous rolls.

### Loot History

The GroupLootHistoryFrame receives QUI's dark theme treatment for a consistent look when reviewing recent loot.

### Keystone Insertion

QUI can automatically insert your keystone when interacting with the Font of Power, removing the drag-and-drop step. The keystone insertion frame itself is also skinned.

### M+ Timer

The Mythic Plus timer is reskinned with QUI's style. For full details on the custom timer layout, see [Dungeon Features]({% link features/dungeon-features.md %}).

### Objective Tracker

The quest and objective tracker can be skinned with customizable height, font sizes for module headers, quest titles, and objective text, custom colors, and an option to hide the border entirely.

### Override Action Bar

The vehicle/override action bar that appears during certain encounters and quests can be skinned to match your action bar style.

### Instance Frames

The PVE finder, Dungeon finder, and PVP frames can be skinned for visual consistency when queuing for content.

### Power Bar Alt

The alternate power bar used in certain encounters and quests (e.g., sanity bars, quest-specific resources) is skinned to match QUI's style.

### Character and Inspect Frames

Both frames are skinned as part of the [Character Pane]({% link features/character-pane.md %}) module integration.

### Ready Check

The ready check popup is reskinned with QUI's dark theme for a cleaner appearance during group content.

## Key Features

- **Global background color** -- A single setting controls the background color across all skinned frames for consistent appearance.
- **Per-module border color** -- Each skinned frame can have its border color detached from the global accent color, allowing individual color overrides.
- **Class color accents** -- Option to use your class color as the skin accent instead of the default mint green.
- **Selective skinning** -- Every skinnable frame has its own enable/disable toggle. Skin only the frames you want.
- **Cursor-anchored loot** -- The loot window can follow your cursor, reducing mouse travel when looting.
- **Auto keystone insert** -- Skip the drag-and-drop when starting a Mythic Plus dungeon.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Global background color | Background color for all skinned frames | Dark grey |
| Class color accents | Use class color instead of accent color for borders | Disabled |
| Game menu skinning | Reskin the ESC menu | Enabled |
| Loot window skinning | Use custom loot window | Enabled |
| Loot at cursor | Anchor loot window to cursor position | Disabled |
| Objective tracker skinning | Reskin the quest tracker | Enabled |
| Objective tracker height | Custom height for the tracker | Default |
| Auto insert keystone | Automatically insert keystone at Font of Power | Enabled |
| Override action bar skinning | Reskin the vehicle/override bar | Enabled |

## Tips

{: .note }
If another addon is already handling a specific frame (for example, a dedicated loot addon), you can disable QUI's skinning for just that frame without affecting the rest of the skinning system.

{: .important }
The global background color setting affects all skinned frames simultaneously. If you change it, preview several different frames (game menu, loot window, objective tracker) to make sure the color works well across all contexts.

{: .note }
Per-module border color overrides let you create subtle visual hierarchy. For example, you might use a brighter border on the loot window and objective tracker to make them stand out, while keeping the game menu border more subdued.
