---
layout: default
title: Unit Frames
parent: Features
nav_order: 2
---

# Unit Frames

QUI's Unit Frames replace the default combat frames with cleaner, more readable versions that are easier to position around your central HUD.

## What You Get

- Player, target, focus, pet, boss, and target-of-target frames
- Optional castbars, portraits, auras, absorb overlays, and heal prediction
- Flexible sizing and text formats for health, power, and names
- A darker visual style that pairs well with QUI's CDM and action bars

## Best For

- Players who want their health and target information close to the middle of the screen
- Anyone building a cleaner PvE or PvP HUD
- Users who want a custom castbar even if they keep other parts of the UI fairly simple

## Where To Configure Them

- Open `/qui` and go to the **Unit Frames** section.
- Use `/qui layout` if you want to reposition them visually.

## Best First Tweaks

1. Move the player and target frames until they sit comfortably around your CDM.
2. Decide how much text you really want to read in combat.
3. Turn portraits on only if they help you.
4. Keep aura counts modest at first so the frames stay readable.

## What You Can Customize

- Size, texture, colors, and border styling for each frame type
- Health and power display styles
- Name formatting and class coloring
- Castbars with interrupt and channel support
- Aura placement, icon count, growth direction, duration text, stack text, and Blizzard-style Helpful/Harmful classification filters
- Heal prediction, absorb shields, indicators, and class resources
- Inline target-of-target text, classification icons, reverse target health fill, and show-below-100% health behavior
- Per-frame border color independent of the global skin border
- Resource bar breakpoints, charged combo points, secondary resource swaps, and class utility bars
- Optional standalone player castbar mode

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

## Per-Frame Border Color

Each unit frame can pick its own border color instead of sharing one skin border with every other frame.

- Open the frame's **Appearance** panel and set **Border Color Source** to one of:
  - **Inherit** — use the global skin border color (the original shared behavior).
  - **Theme accent** — use your current theme's accent color.
  - **Class color** — color the border by class.
  - **Custom** — use the **Custom Border Color** picker right below it.
- The same controls are mirrored under **Appearance > Border Coloring > Unit Frames > "Frame"** if you prefer to set them all from one place.
- This applies to the player, target, pet, focus, target-of-target, and boss frames.

{: .note }
Frames left on **Inherit** keep following the global skin border color exactly as before, so you only need to touch the frames you want to stand out.

## Good To Know

{: .note }
The player castbar standalone mode is useful if you want QUI's castbar feel without fully committing to QUI unit frames.

{: .important }
When repositioning unit frames, make sure you are out of combat. Protected frame movement is blocked during combat.

{: .note }
If your target frame feels crowded, try the inline target-of-target option before enabling another full frame.
