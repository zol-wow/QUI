---
layout: default
title: Group Frames
parent: Features
nav_order: 3
---

# Group Frames

QUI Group Frames are an opt-in replacement for Blizzard's party and raid frames. They are disabled by default and must be explicitly enabled. Once active, they provide auto-scaling layouts, extensive healer-focused features, click-casting, and fine-grained control over indicators and auras.

## Overview

Group frames automatically adapt their size based on your current group composition. In a 5-player party they are larger and more detailed; in a 40-player raid they shrink to keep everything visible. The frames support role-based sorting, group-based organization, click-casting bindings, dispel overlays, and custom aura indicators per specialization.

## How to Enable

Group frames are **disabled by default**. To enable them:

1. Open `/qui` and navigate to **Frames > Group Frames**.
2. Toggle the **Enable Group Frames** option.
3. Reload your UI when prompted.

## Key Features

- **Auto-scaling dimensions** -- Frame sizes adjust by context: party (200x40), small raid (180x36), medium raid (160x30), large raid (140x24).
- **Layout controls** -- Grow direction (up/down), group grow direction (left/right), spacing between frames, and sorting by role, index, or name.
- **Group organization** -- Group by GROUP, ROLE, or CLASS.
- **Health display** -- Styles include percent, absolute, both, or deficit (showing missing health).
- **Power bar** -- Optional, with power-type-specific coloring.
- **Name text** -- Class color option and maximum length truncation.
- **Indicators** -- Role icon, ready check, resurrection status, summon pending, leader/assistant, target marker (raid icons), threat border, and phase icon.
- **Healer features** -- Dispel overlay highlighting dispellable debuffs, target highlight showing your current target in the group, my-buff indicator for tracking your own HoTs/shields, and defensive indicator for tracking external cooldowns.
- **Click-casting** -- Customizable mouse-button bindings per specialization. Includes smart resurrection that picks the correct res spell for your class.
- **Auras** -- Debuff icons (default 3 max), buff icons, duration-based coloring, and expiring pulse animation when a buff is about to fall off.
- **Custom aura indicators** -- Per-specialization presets for tracking specific buffs and debuffs with custom positioning on the frame.
- **Spotlight** -- Pin specific group members by role or name to a separate group, useful for keeping tanks or key players always visible in a consistent location.
- **Range check** -- Out-of-range players fade to a configurable alpha, giving you instant visual feedback on who you can reach.
- **Class power pips** -- Optional display of combo points, holy power, chi, etc.
- **Castbar** -- Optional per-unit castbar. Disabled by default for performance in large groups.
- **Portrait** -- Optional unit portrait on each frame.
- **Pet frames** -- Optional frames for group members' pets.
- **Test mode** -- Preview group frames with configurable party or raid counts without needing an actual group.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Enable | Master toggle for group frames | Disabled |
| Sort by | Role, index, or name | Role |
| Group by | GROUP, ROLE, or CLASS | GROUP |
| Health display | Percent, absolute, both, or deficit | Percent |
| Max debuff icons | Number of debuff icons shown per frame | 3 |
| Range check alpha | Opacity for out-of-range members | 0.4 |
| Click-casting | Enable click-cast bindings | Disabled |
| Spotlight | Pin members by role/name | Disabled |
| Castbar | Show castbars on group frames | Disabled |
| Pet frames | Show pet frames | Disabled |

## Tips

{: .important }
Group frames require a UI reload when first enabled or disabled. This is because they replace Blizzard's secure group frame headers, which can only be swapped at load time.

{: .note }
Click-casting bindings are stored per-specialization. If you play multiple specs (e.g., Holy and Retribution on a Paladin), each spec can have completely different click-cast setups.

{: .note }
Test mode is invaluable for configuring raid frames. You can preview how your frames look with 5, 10, 20, or 40 players without needing to join an actual group. Access it from the Group Frames settings.

{: .important }
Enabling castbars on group frames in a 40-player raid can impact performance. If you notice frame rate drops in large groups, consider disabling group frame castbars.
