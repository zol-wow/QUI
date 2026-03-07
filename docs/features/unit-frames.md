---
layout: default
title: Unit Frames
parent: Features
nav_order: 2
---

# Unit Frames

QUI replaces Blizzard's default unit frames with fully customizable alternatives. Every aspect of the frames -- size, textures, colors, text formatting, and ancillary elements like castbars and auras -- is configurable through the options panel.

## Overview

QUI provides custom frames for Player, Target, Target of Target, Pet, Focus, and Boss units. Each frame can be independently styled and positioned. The frames support class coloring, hostility coloring, dark mode, absorb shield overlays, heal prediction, portraits, and per-unit castbars.

## How to Enable

Unit frames are controlled per-frame in the QUI options panel. Open `/qui` and navigate to the **Frames > Unit Frames** tab. Each unit type has its own enable toggle.

To reposition frames, use `/qui editmode` to enter the drag-and-drop edit mode.

## Key Features

- **Per-unit customization** -- Player, Target, Target of Target, Pet, Focus, and Boss frames each have independent width, height, texture, and border settings.
- **Health bar** -- Display styles include percent, absolute value, or both. Supports class colors, custom colors, and dark mode with separate background opacity.
- **Power bar** -- Optional power bar beneath health with configurable height and power-type-specific colors (mana, rage, energy, etc.).
- **Power text** -- Formats include percent, current value, or both. Anchor position is adjustable.
- **Name text** -- Optional class coloring, configurable font size, anchor position, and maximum length truncation to prevent overflow.
- **Portrait** -- Optional unit portrait on the left or right side with border options.
- **Castbar** -- Per-unit castbar with configurable width, height, color, and spell icon. Can be anchored to its unit frame or placed standalone. Highlights interruptible casts and displays channel tick marks.
- **Target inline ToT** -- On the target frame, shows the target-of-target name inline as ">> TotName" after the target's name.
- **Auras (buffs/debuffs)** -- Configurable icon size, anchor position, growth direction, maximum icon count, and duration/stack text.
- **Indicators** -- Rested indicator, combat indicator, stance indicator (player only), target marker (raid icons), and leader/assistant icons.
- **Absorb shields** -- Visual overlay on the health bar showing absorb amounts with configurable opacity and texture.
- **Heal prediction** -- Incoming heal overlay on the health bar.
- **Dark mode** -- Separate health and background colors with independent opacity controls for a subdued visual style.
- **Player castbar standalone mode** -- The player castbar can function independently even when QUI unit frames are not enabled, giving you a custom castbar without replacing your frames.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Frame width/height | Dimensions for each unit frame type | Varies by unit |
| Health display | Percent, absolute, or both | Percent |
| Class colors | Color health bars by class | Enabled |
| Dark mode | Use subdued health/background colors | Disabled |
| Power bar | Show power bar below health | Enabled |
| Portrait | Show unit portrait | Disabled |
| Castbar | Show castbar per unit | Enabled |
| Aura max icons | Maximum buffs/debuffs shown | Varies by unit |
| Absorb overlay | Show absorb shield on health bar | Enabled |

## Visibility Rules

Unit frames support several visibility modes:

- Always visible
- In combat only
- When target exists
- While in a group or instance
- On mouseover
- While mounted or flying

These can be combined to create the exact behavior you want -- for example, showing the player frame only in combat or when you have a target.

## Tips

{: .note }
The player castbar standalone mode is useful if you prefer Blizzard's default unit frames (or another addon's frames) but still want QUI's castbar styling and positioning.

{: .important }
When repositioning unit frames with `/qui editmode`, make sure you are out of combat. Frame movement during combat is blocked by WoW's secure frame protection.

{: .note }
Target inline ToT (">> TotName") is a space-efficient alternative to a separate Target of Target frame. You can use both simultaneously or choose one or the other.
