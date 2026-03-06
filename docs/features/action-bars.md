---
layout: default
title: Action Bars
parent: Features
nav_order: 4
---

# Action Bars

QUI skins and enhances all 8 standard action bars plus special bars like Pet, Stance, Microbar, and Bags. The action bar module focuses on clean visual styling, mouseover fade for a minimal HUD, and per-bar customization so each bar can look and behave exactly how you want.

## Overview

The action bar module applies visual skinning to your buttons (icon zoom, backdrops, borders) and adds functional enhancements like mouseover fade, range and usability indicators, and customizable text overlays. You can configure settings globally and then override them on a per-bar basis for fine control.

## How to Enable

Action bar enhancements are enabled by default. To access settings, open `/qui` and navigate to the **Frames > Action Bars** tab.

## Key Features

- **Button skinning** -- Icon zoom crops the default icon border, backdrop adds a background behind each button, gloss adds a subtle shine, and borders frame each icon cleanly.
- **Text display** -- Keybind text, macro names, and stack counts are all customizable. Adjust anchor position, font size, and color per bar.
- **Mouseover fade system** -- Bars fade to a configurable alpha when not hovered. Control fade speed, out-of-focus alpha, and hover delay. Bars reappear instantly on mouseover.
- **Per-bar fade** -- Each bar (1-8) can have independent fade settings or inherit from the global configuration.
- **Always show flag** -- Keep specific bars permanently visible even when the fade system is active.
- **Always show in combat** -- Override fade and keep bars visible during combat encounters.
- **Show when Spellbook open** -- Bars become visible when you open the Spellbook, useful for drag-and-drop spell placement.
- **Keep Leave Vehicle button visible** -- Ensures the vehicle exit button is always accessible.
- **Disable below max level** -- Keeps bars visible while leveling so new players are not confused by hidden bars.
- **Linked mouseover (bars 1-8)** -- Hovering any linked bar reveals all linked bars simultaneously.
- **Hide page arrow on bar 1** -- Removes the page-switching arrow from the main action bar for a cleaner look.
- **Per-bar style overrides** -- Each bar 1-8 can override global icon zoom, backdrop, keybind display, and other style settings.
- **Special bars** -- Pet bar, Stance bar, Microbar, and Bags bar support fade behavior but do not have full style override options.
- **Extra Action Button** -- Configurable scale, position, and option to hide default artwork.
- **Zone Ability Button** -- Configurable scale, position, and option to hide default artwork.
- **Global scale** -- Scale all bars uniformly from 0.5x to 2.0x.
- **Button spacing** -- Adjust the gap between buttons on all bars.
- **Hide empty slots** -- Empty action bar slots become invisible for a cleaner look.
- **Lock buttons** -- Prevent accidentally dragging spells off your bars.
- **Range indicator** -- Out-of-range abilities are tinted red on the action bar.
- **Usability indicator** -- Unusable abilities are dimmed or desaturated.
- **Fast usability updates** -- Optional 50ms update interval (default is 250ms) for more responsive usability coloring.
- **Action bar art hiding** -- Remove Blizzard's default action bar artwork and gryphons.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Global scale | Scale multiplier for all bars | 1.0 |
| Button spacing | Gap between buttons in pixels | 2 |
| Icon zoom | Crop icon edges for a cleaner look | Enabled |
| Mouseover fade | Fade bars when not hovered | Disabled |
| Fade out alpha | Opacity when faded (0 = invisible) | 0 |
| Always show in combat | Override fade during combat | Enabled |
| Hide empty slots | Hide buttons with no spell assigned | Disabled |
| Lock buttons | Prevent dragging spells off bars | Enabled |
| Range indicator | Tint out-of-range red | Enabled |
| Fast usability | 50ms usability checks | Disabled |

## Tips

{: .note }
The mouseover fade system pairs well with QUI's Cooldown Manager. With your rotation cooldowns visible via the CDM, you can safely fade your action bars to keep a clean HUD and still know exactly what is available.

{: .important }
The "fast usability updates" option polls every 50ms instead of 250ms. This makes usability coloring more responsive but uses slightly more CPU. Enable it only if the default 250ms feels sluggish for your playstyle.

{: .note }
Per-bar style overrides let you keep a consistent global style while making exceptions -- for example, larger keybind text on bar 1, or no backdrop on your pet bar. Settings that are not overridden fall through to the global defaults.

{: .note }
Linking bars 1-8 for unified mouseover means you can hover any one of your main bars and all of them appear. This is useful when you stack bars vertically or arrange them in a grid.
