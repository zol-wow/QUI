---
layout: default
title: Dungeon Features
parent: Features
nav_order: 10
---

# Dungeon Features

QUI provides a suite of features specifically designed for Mythic Plus dungeons and group PvE content. From a custom M+ timer with a sleek layout to party keystone visibility, battle res tracking, and automatic combat logging, these tools give you better awareness and convenience during dungeon runs.

## Overview

The dungeon features module combines several related subsystems: a custom Mythic Plus timer that replaces the default Blizzard timer, a party keystones display that shows your group members' key levels, click-to-teleport dungeon icons, a battle res counter, a combat timer, and automatic combat log management. Each feature operates independently and can be enabled or disabled on its own.

## How to Enable

Dungeon features are enabled by default. To configure them:

- Open `/qui` and navigate to the **QoL** tab, then select the relevant sub-option (Party Keystones, etc.), or check the **Dungeon** section.

## Key Features

### Custom M+ Timer

A redesigned Mythic Plus timer with a cleaner layout than Blizzard's default.

- **Sleek layout mode** -- Streamlined visual design with QUI's dark theme.
- **Timer display** -- Shows elapsed time, remaining time, and plus-level thresholds.
- **Border styling** -- Customizable border around the timer frame.
- **Death counter** -- Tracks group deaths and the time penalty they add.
- **Affix display** -- Shows the active dungeon affixes.
- **Objective tracking** -- Displays boss kill and enemy forces progress.
- **Forces bar** -- A progress bar for enemy forces percentage with multiple display modes and text format options.
- **Font customization** -- Control font face and size for timer text.
- **Dungeon name truncation** -- Set a maximum character length for the dungeon name to keep the timer compact.

### Party Keystones

Shows each group member's Mythic Plus keystone level directly on the M+ tab, so you can see what keys your group has available without asking.

- **Font size** -- Adjustable text size for keystone level display.
- **Color customization** -- Custom color for the keystone text.
- **Position and anchor** -- Control where keystone information appears relative to each group member entry.

### Dungeon Teleport

Adds click-to-teleport functionality to dungeon icons on the M+ tab. If you have the teleport for a dungeon (from achieving a sufficient rating or earning the appropriate achievement), clicking the icon will teleport you directly to the dungeon entrance.

### Battle Res Counter

Displays the current number of available battle resurrection charges and the time until the next charge.

- **Frame sizing** -- Configurable width and height for the counter display.
- **Font sizes** -- Independent font size controls for the charge count and timer text.
- **Color coding** -- Red when no charges are available, green when charges are ready.
- **Class color option** -- Use class color for the display border or text.
- **Backdrop and border** -- Full visual customization of the counter frame.
- **Position offset** -- Adjust the counter position relative to its default anchor.

### Combat Timer

A simple elapsed-time display that shows how long you have been in combat.

- **Boss encounter mode** -- Optionally restrict the timer to only show during boss encounters rather than all combat.
- **Font customization** -- Control font face, size, and color.
- **Backdrop and border** -- Visual frame customization.

### Auto Combat Log

Automatically starts and stops combat logging (`/combatlog`) based on your content.

- **M+ logging** -- Automatically log combat in Mythic Plus dungeons.
- **Raid logging** -- Automatically log combat in raid instances.
- Logs are started when you enter the relevant content and stopped when you leave, removing the need to remember to toggle logging manually.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Custom M+ timer | Use QUI's M+ timer instead of Blizzard's | Enabled |
| Forces bar display mode | How enemy forces progress is shown | Bar |
| Death counter | Show death count and time penalty | Enabled |
| Party keystones | Show group keystone levels on M+ tab | Enabled |
| Battle res counter | Display brez charges and timer | Enabled |
| Brez no-charges color | Color when no charges available | Red |
| Brez has-charges color | Color when charges are available | Green |
| Combat timer | Show elapsed combat time | Disabled |
| Boss encounter only | Restrict combat timer to boss fights | Disabled |
| Auto combat log M+ | Auto-log in Mythic Plus | Disabled |
| Auto combat log raids | Auto-log in raids | Disabled |

## Tips

{: .note }
The auto combat log feature pairs well with sites like Warcraft Logs and Wipefest. Enable it for raids and M+ so you never forget to start logging before a pull, and your logs will cleanly start and stop with each instance.

{: .important }
The battle res counter is especially valuable for raid leaders and M+ key holders. The color coding (red for zero charges, green for available charges) makes it immediately obvious whether a battle res is available during a hectic encounter.

{: .note }
Dungeon Teleport only works for dungeons where you have earned the teleport. This is typically tied to completing the dungeon at a certain Mythic Plus level or earning a related achievement. The icons will only be clickable for dungeons you can actually teleport to.

{: .note }
The combat timer's "boss encounter only" mode is useful if you want to track boss kill times without the timer cluttering your screen during trash pulls. Enable it for a cleaner experience focused on the fights that matter.
