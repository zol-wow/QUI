---
layout: default
title: Cooldown Manager
parent: Features
nav_order: 1
---

# Cooldown Manager

The Cooldown Manager, or **CDM**, is the feature most players think of first when they think of QUI. It keeps your most important abilities, buffs, and procs near the center of your screen so you can stop glancing down at action bars every few seconds.

![Actual QUI Cooldown Manager Entries page]({{ '/assets/images/qui-cdm-entries.png' | relative_url }})
_The Entries tab is where you confirm what each container tracks and add or remove spells from the live preview list._

## Why Players Use It

- Your core rotation is easier to track near your character.
- Important utility and defensive cooldowns get their own space.
- Tracked buffs, debuffs, and aura bars can live in the same visual system.
- It works well for DPS, healing, support, and utility-heavy playstyles.

## Where To Configure It

- Open `/qui` and select **Cooldown Manager**.
- Type `/cdm` if you want to jump straight there.
- Use **Edit in Layout Mode** only when you want to move the container on screen.

## Best First Setup

1. Move the **Essential** container to the spot your eyes naturally return to.
2. Place **Utility** close enough to read, but far enough away that it does not compete with your main rotation.
3. Open the **Entries** page and confirm the spells you care about are present.
4. Adjust icon size before you change anything more advanced.
5. Add custom entries only after the core setup already feels good.

## How CDM Is Organized

- **Essential** is your main combat bar for rotation and high-priority abilities.
- **Utility** is usually where defensives, movement tools, interrupts, and situational buttons go.
- **Aura containers** track buffs and debuffs as icons.
- **Aura bars** track longer effects as bars when that reads better than icons.

The system automatically knows your class and specialization, then lets you refine the list from there.

## What You Can Customize

- Container size, rows, spacing, and growth direction
- Which spells appear, and in what order, through the **Entries** page
- Per-spell overrides for visibility and effects
- Glow, swipe, range, usability, and desaturation behaviors
- Keybind display and optional click interaction
- Visibility rules so bars appear only when you want them

![Actual QUI Cooldown Manager Appearance page]({{ '/assets/images/qui-cdm-appearance.png' | relative_url }})
_The Appearance tab is where you change icon size, layout direction, padding, text placement, and other container-level presentation choices._

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Essential icon size | Pixel size of Essential container icons | 39 |
| Essential icons per row | Number of icons before wrapping to a new row | 8 |
| Essential rows | Maximum number of rows (1-3) | 3 |
| Utility icon size | Pixel size of Utility container icons | 30 |
| Utility icons per row | Number of icons before wrapping | 6 |
| Layout direction | HORIZONTAL or VERTICAL | HORIZONTAL |
| Range indicator | Tint out-of-range icons red | Enabled |
| Desaturation | Desaturate icons on cooldown | Enabled |
| Show keybinds | Display keybind text on icons | Enabled |
| Clickable icons | Enable click-to-cast on CDM icons | Disabled |

## Common CDM Styles

{: .note }
- **Minimal combat HUD**: one Essential row, one Utility row, very little else.

{: .note }
- **Aura-heavy setup**: add icon or bar containers for tracked buffs and debuffs.

{: .note }
- **Role-based setup**: keep healing or support cooldowns in Utility so the main bar stays readable.

## Good To Know

{: .note }
Custom entries are stored per character, so a trinket or utility spell you add on one character will not automatically appear on another.

{: .note }
The **Entries** page is the fastest way to make CDM feel personal. Use it before chasing tiny spacing tweaks.

{: .note }
If you are unsure whether to track something as an icon or a bar, start with icons. Move to aura bars when duration readability matters more than button-like recognition.
