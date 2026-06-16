---
layout: default
title: Info Bar
parent: Features
nav_order: 11
---

# Info Bar

The Info Bar is an optional beta module that adds a full-width bar at the top or bottom of the screen. It hosts datatext widgets, micro menu buttons, travel tools, spec switching, and plugin-style data feeds in one predictable strip.

{: .important }
Info Bar is off by default. Enable it under `/qui` > **Module Addons**. It depends on the Datatexts module; if Datatexts is disabled, widget lists will be empty.

## Why Players Use It

- Keep utility information outside the combat HUD.
- Replace scattered micro buttons with a tidy bar.
- Put gold, currencies, time, durability, mail, professions, spec, and system stats in one place.
- Manage left, center, and right widget zones independently.

## How To Enable

1. Open `/qui`.
2. Go to **Module Addons**.
3. Enable **Info Bar**.
4. Open the **Info Bar** tile.
5. Turn on **Enable Info Bar** and choose **Top** or **Bottom**.

## Widget Zones

The bar has three zones:

| Zone | Best for |
|------|----------|
| Left | Micro menu, travel, or frequently clicked tools |
| Center | Time, spec, or compact status widgets |
| Right | Gold, currencies, mail, durability, system stats |

Right-click empty space on the Info Bar to add, remove, arrange, or configure widgets for the zone under your cursor.

## Widget Options

Most widgets support compact display controls:

- Hide icon
- Short label
- No label
- Hide text (icon-only)
- Minimum width
- X offset
- Click-through for text-only widgets

**Hide text** blanks a widget's label and keeps only its icon, reclaiming the freed width so the rest of the zone tightens up. It sits alongside **No label** and **Hide icon**, and is available both in the right-click **Configure Widget** menu and in the Info Bar settings panel.

The bar also has shared height, font size, background opacity, border size, and border color settings.

## Reordering Widgets

Hold **Shift** and drag a datatext slot to reorder it live within its zone. The slot moves as you drag, so you can fine-tune order without opening a menu. This works for every widget, including the volume widget.

## Volume Widget

The volume datatext gives quick control over game audio:

- **Left-click** opens a compact themed popup with sliders for **Master**, **SFX**, **Music**, **Ambience**, and **Dialog** volume, plus a **Mute all** checkbox. The popup follows your skin accent and font.
- **Middle-click** opens Blizzard's audio settings.
- **Scroll** over the widget to adjust volume, and **right-click** to mute.

## Travel / Hearth Widget

The travel widget shows a **Travel** label and a **Left click to hearth** tooltip line. The label honors both **No label** and the new **Hide text** toggle, so you can run it as text, icon-only, or hidden-label to taste.

## Shared Currency Settings

The Info Bar uses the same Currencies list as datatext panels, the minimap panel, and Bags. Reorder or hide a currency once, and every Currencies surface follows.

## Good To Know

- Widget lists come from the Datatexts module.
- Plugin-style data feeds appear in the same widget picker when available.
- The Info Bar is meant for repeated scanning, not combat-critical alerts; keep your main combat HUD near the center of the screen.
