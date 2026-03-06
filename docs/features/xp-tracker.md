---
layout: default
title: XP Tracker
parent: Features
nav_order: 14
---

# XP Tracker

QUI's XP Tracker provides a clean, customizable experience bar that replaces or supplements the default Blizzard XP display. It shows your leveling progress at a glance with optional rested XP visualization and a details panel with session statistics.

## Overview

The XP Tracker displays your current experience as a progress bar with configurable colors, textures, and text formatting. A rested XP overlay can be shown on top of the main bar to indicate how much bonus XP you have accumulated. The accompanying details panel provides additional information like XP to next level, percentage complete, and rested amounts, with configurable font sizes and grow direction.

The bar can be positioned anywhere on screen and locked in place once you are satisfied with the layout.

## How to Enable

The XP Tracker is available for characters that are not at maximum level. To configure it:

- Open `/qui` and navigate to the **QoL > XP Tracker** tab.

To reposition the bar, unlock it in the XP Tracker settings and drag it to your preferred location.

## Key Features

- **XP progress bar** -- A status bar showing your current experience toward the next level, with customizable bar texture from LibSharedMedia.
- **Rested XP overlay** -- An optional secondary fill on the progress bar that shows how much rested (bonus) XP you have available, displayed in a distinct color.
- **Details panel** -- An expandable panel showing session XP statistics with configurable header and line font sizes.
- **Grow direction** -- The details panel can grow upward, downward, or automatically based on the bar's screen position.
- **Bar text** -- Optional text overlay on the bar showing XP values or percentages, with a "hide until hover" option to keep the bar visually clean until you mouse over it.
- **Full color control** -- Independent color settings for the bar fill, rested XP overlay, backdrop, and border.
- **Lock and position** -- Drag the bar to any screen position and lock it to prevent accidental movement.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Show bar text | Display XP values on the bar | Enabled |
| Hide text until hover | Only show bar text on mouseover | Disabled |
| Show rested XP | Display rested XP overlay on the bar | Enabled |
| Bar color | Fill color of the XP progress bar | Configurable |
| Rested color | Color of the rested XP overlay | Configurable |
| Backdrop color | Background color behind the bar | Configurable |
| Border color | Color of the bar border | Configurable |
| Bar texture | LibSharedMedia texture for the bar fill | Default |
| Grow direction | Details panel direction: auto, up, or down | Auto |
| Width | Overall width of the XP bar | Configurable |
| Height | Overall height of the XP bar container | Configurable |
| Bar height | Height of the progress bar itself | Configurable |
| Header font size | Font size for the details panel header | Configurable |
| Line font size | Font size for details panel lines | Configurable |
| Lock position | Prevent the bar from being moved | Enabled |

## Tips

{: .note }
The "hide text until hover" option is a good compromise if you want a minimal bar most of the time but still need access to exact numbers. The bar remains visible as a progress indicator, and hovering reveals the precise values.

{: .important }
The XP Tracker is only relevant for characters below maximum level. At max level, the bar has nothing to track and will not display. If you are looking for reputation or honor tracking, those are handled by different systems.

{: .note }
Setting the grow direction to "auto" lets the details panel adapt to the bar's position on screen -- it will grow upward if the bar is near the bottom of the screen and downward if it is near the top, preventing the panel from being clipped off-screen.
