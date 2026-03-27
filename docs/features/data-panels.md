---
layout: default
title: Data Panels
parent: Features
nav_order: 20
---

# Data Panels

QUI's data panel system provides configurable information displays that show useful game data at a glance. Available datatexts include gold and currency tracking, durability, FPS, latency, memory and bandwidth statistics, guild information, clock and calendar access, quest progress, and more. Panels can be positioned on the minimap border or placed as standalone panels anywhere on screen.

## Overview

The data panel system is built around a collection of individual datatexts -- small, self-contained information displays that each show a specific piece of game data. These datatexts can be assigned to panel slots on the minimap or placed in standalone data panels elsewhere on your screen. Each datatext updates on a shared one-second ticker for efficient resource usage, and most support left-click and right-click actions for quick access to related functionality (for example, clicking the gold datatext can open your currency panel).

The system supports LibSharedMedia fonts for full typographic control and offers a no-label mode for minimal display when you want just the values without descriptive labels.

## How to Enable

Data panels are configured through multiple entry points depending on panel type:

- For minimap datatexts, enter Layout Mode with `/qui layout` and access the minimap settings through the toolbar or drawer.
- For standalone data panels, configure them through the relevant settings in `/qui`.

## Key Features

### Available Datatexts

- **Gold and currency** -- Displays your current gold with configurable currency ordering options. Shows additional currencies relevant to current content.
- **Durability** -- Shows your current gear durability percentage so you know when repairs are needed.
- **System statistics** -- Displays FPS, latency (home and world), and memory usage in a combined readout for monitoring game performance.
- **Bandwidth** -- Shows network bandwidth usage for tracking connection quality.
- **Guild information** -- Displays guild member count and online status with click access to the guild roster.
- **Clock and calendar** -- Shows the current time with click access to the in-game calendar.
- **Quest tracking** -- Displays active quest count and progress information.

### Panel Configuration

- **Minimap panel slots** -- Assign datatexts to configurable slots around the minimap border for an integrated information display.
- **Standalone data panels** -- Place data panels anywhere on screen, independent of the minimap. These can be locked in position once placed.
- **No-label mode** -- Display only the data values without descriptive labels for a minimal, compact appearance.
- **Font customization** -- Full LibSharedMedia font support for font face, size, and styling across all datatexts.

### Interaction

- **Left-click actions** -- Most datatexts support a left-click action that opens a related panel or provides additional detail.
- **Right-click actions** -- Secondary click actions provide quick access to settings or alternate views.
- **Lockable positions** -- Standalone panels can be locked to prevent accidental repositioning.

### Efficiency

- **Shared update ticker** -- All datatexts update on a single one-second interval rather than running independent timers, reducing CPU overhead.
- **On-demand updates** -- Some datatexts also respond to specific events (e.g., currency changes, durability updates) for immediate feedback when relevant data changes.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Panel slot assignments | Which datatext appears in each panel slot | Varies |
| No-label mode | Hide descriptive labels, show only values | Disabled |
| Font face | LibSharedMedia font for datatext display | Default |
| Font size | Text size for datatext values | Configurable |
| Currency ordering | Order in which currencies are displayed | Default |
| Lock panels | Prevent standalone panels from being moved | Enabled |

## Tips

{: .note }
The system statistics datatext (FPS, latency, memory) serves a similar purpose to the Performance Monitor but in a lightweight, always-visible format. Keep it on your minimap for passive performance awareness, and use the full Performance Monitor (`/qui perf`) when you need to investigate a specific issue.

{: .important }
Data panels complement the minimap display but are not limited to it. Standalone panels can be placed anywhere on screen, which is useful if you run a minimal minimap setup but still want quick access to system stats or currency information.

{: .note }
The no-label mode is a good option if you are already familiar with what each panel slot shows. Removing the labels gives you a cleaner look and saves horizontal space, especially when running multiple datatexts on the minimap border.
