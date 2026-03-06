---
layout: default
title: Character Pane
parent: Features
nav_order: 7
---

# Character Pane

QUI enhances the default Character and Inspect frames with detailed equipment overlays, stat formatting options, and visual customization. At a glance you can see item levels with upgrade tracks, enchant status, gem indicators, and durability -- all directly on the character panel without needing external addons or mouseover tooltips.

## Overview

The character pane module adds information-dense overlays to each equipment slot on both your own character frame and the inspect frame when viewing other players. Item names, item levels with upgrade track indicators, enchant status with warnings for missing enchants, gem socket indicators, and durability bars are all rendered directly on top of the equipment slots. The module also reformats the stats panel with customizable text sizing, secondary stat display formats, and color options.

## How to Enable

The character pane enhancements are enabled by default. To configure them:

- Open `/qui` and navigate to the **Character** tab.

## Key Features

- **Item level overlays** -- Displays the item level on each equipment slot, including the upgrade track indicator (e.g., "Hero 4/6") in gold text.
- **Enchant status** -- Shows enchant text on enchantable slots. Missing enchants display a "No Enchant" warning in red.
- **Gem indicators** -- Visual indicators for gem sockets on applicable items.
- **Durability bars** -- Small durability bars on each equipment slot showing remaining durability at a glance.
- **Inspect frame support** -- All overlays also appear when inspecting other players, so you can quickly evaluate their gear.
- **Stats display customization** -- Control text size, color, and formatting for your stats panel. Secondary stats can be shown as percentage, rating, or both.
- **Compact mode** -- Condensed stats layout for players who prefer a minimal stats panel.
- **Header styling** -- Class color or custom color option for section headers in the stats panel.
- **Panel scale** -- Adjust the overall character frame scale from 0.75x to 1.5x.
- **Overlay scale** -- Independent scale control for the equipment slot overlays.
- **Custom background color** -- Set a custom background color for the character and inspect frames.
- **Model background toggle** -- Show or hide the 3D model background behind your character.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Panel scale | Overall character frame scale (0.75-1.5x) | 1.0 |
| Overlay scale | Scale for equipment slot info overlays | 1.0 |
| Secondary stat format | Percent, rating, or both | Both |
| Compact mode | Condensed stats layout | Disabled |
| Header color | Class color or custom color for section headers | Class color |
| Enchant text color | Class color or custom color for enchant names | Custom |
| No Enchant warning color | Color for missing enchant warnings | Red |
| Upgrade track color | Color for upgrade track text | Gold |
| Model background | Show/hide 3D model background | Enabled |

## Tips

{: .note }
The inspect frame overlays use the same configuration as your own character frame. This makes it easy to compare gear -- the same information is presented in the same format whether you are looking at your own character or inspecting someone else.

{: .important }
The "No Enchant" warning is intentionally prominent (red text) to help you catch missing enchants before entering content. If an equipment slot supports enchants and none is applied, the warning will appear. This is especially useful after equipping new gear.

{: .note }
The secondary stat format "both" option shows values like "25.3% (1,240)" so you can see the effective percentage alongside the raw rating. This is helpful for understanding stat breakpoints and diminishing returns.
