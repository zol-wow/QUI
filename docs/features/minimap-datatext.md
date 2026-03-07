---
layout: default
title: Minimap & Data Panels
parent: Features
nav_order: 9
---

# Minimap & Data Panels

QUI provides extensive minimap customization alongside a data panels system for displaying useful information. The minimap module controls shape, size, border styling, button management, and the various elements surrounding the minimap. The data panels module offers configurable info displays for stats, system performance, and game information.

## Overview

The minimap module goes well beyond simple border skinning. It lets you choose between square and round shapes, manage the clutter of addon buttons through an organized button drawer, customize the clock and coordinate displays, control which Blizzard minimap elements are visible, and reposition the dungeon queue eye. Every visual element around the minimap -- zone text, clock, coordinates -- has independent font, color, and formatting options.

## How to Enable

The minimap module is enabled by default. To configure it:

- Open `/qui` and navigate to the **UI** tab, then select **Minimap**.

## Key Features

### Shape and Size

- **Shape selection** -- Choose between SQUARE and ROUND minimap shapes.
- **Size control** -- Adjust the minimap dimensions to your preference.
- **Scale** -- Overall minimap scale multiplier.
- **Border** -- Customizable border size and color, with options for class color or accent color.
- **Lock position** -- Lock the minimap in place to prevent accidental dragging.

### Button Management

- **Hide addon buttons** -- Cleans up the minimap border by hiding addon buttons, with an option to show them on mouseover.
- **Button drawer** -- Collects addon minimap buttons into an organized drawer panel that expands on demand. Configurable anchor point, button size, spacing, column count, and auto-hide delay after mouse leaves.

### Blizzard Element Visibility

Toggle visibility for each built-in minimap element independently:

- Zoom buttons
- Mail indicator
- Crafting order notification
- Addon compartment button
- Difficulty indicator
- Mission reports
- Calendar
- Tracking button

### Dungeon Eye (Queue Status)

The LFG queue status eye can be repositioned to a minimap corner for a cleaner look, with an adjustable scale.

### Clock

- **Time source** -- Switch between local time and server time.
- **Font customization** -- Font face, size, and color.
- **Class color option** -- Color the clock text by your class.

### Coordinates

- **Precision formats** -- Choose how many decimal places to display.
- **Update interval** -- Control how frequently coordinates refresh.
- **Font customization** -- Independent font face, size, and color.

### Zone Text

- **Font customization** -- Font face, size, and color for the zone name.
- **All caps option** -- Display zone text in uppercase for a stylized look.

### Other Controls

- **Auto zoom out** -- Automatically zooms the minimap back out after 10 seconds when you zoom in.
- **Middle click menu** -- Access a quick menu via middle-clicking the minimap.
- **Hide micro menu** -- Remove the micro menu bar from the UI.
- **Hide bag bar** -- Remove the bag bar from the UI.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Shape | SQUARE or ROUND | Square |
| Size | Minimap dimensions in pixels | Default |
| Border color | Class color or accent color | Accent |
| Lock position | Prevent minimap dragging | Enabled |
| Hide addon buttons | Clean up minimap border | Enabled |
| Show buttons on hover | Reveal hidden buttons on mouseover | Enabled |
| Button drawer | Collect buttons into organized panel | Disabled |
| Auto zoom out | Reset zoom after 10 seconds | Enabled |
| Clock time source | Local or server time | Local |
| Coordinate precision | Decimal places for coordinates | 1 |

## Tips

{: .note }
The button drawer is the recommended way to handle addon minimap buttons. Instead of hiding them entirely or letting them clutter the minimap border, the drawer collects them into a clean panel that you can expand when needed and auto-hides after a configurable delay.

{: .important }
Hiding the micro menu and bag bar frees up significant screen space, but make sure you know the keyboard shortcuts for the functionality they provide (e.g., opening your bags, character pane, spell book) before hiding them.

{: .note }
If you use the square minimap shape, the button drawer and addon button hiding become especially useful since addon buttons do not naturally distribute well around a square border.
