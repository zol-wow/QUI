---
layout: default
title: Damage Meter
parent: Features
nav_order: 21
---

# Damage Meter

QUI skins Blizzard's built-in damage meter (introduced in WoW Midnight 12.0+) with a dark, accent-bordered treatment that matches the rest of the addon. Beyond the visual reskin, QUI exposes the meter's behavior controls (visibility, bar layout, alpha) and a set of customization options for textures and fonts.

## How to Enable

The damage meter is part of Blizzard's UI and must be turned on in WoW's **Gameplay Enhancements** options. QUI's skin treatment is enabled by default; configure it from the addon options:

- Open `/qui` and navigate to **Appearance > Damage Meter**.

## Behavior Controls

| Setting | Description |
|---------|-------------|
| Enable Damage Meter | Master toggle for Blizzard's built-in meter; mirrors the `damageMeterEnabled` CVar. |
| Visibility | Always shown / In Combat only / Hidden. |
| Style | Bar layout: Default, Bordered, or Thin. |
| Number Display | Minimal, Compact, or Complete value formatting. |
| Use Class Colors | Color each row's bar by the player's class color. |
| Show Bar Icons | Show the spec or class icon on the left side of each row. |
| Bar Height / Bar Spacing | Pixel sizing for rows. |
| Text Size | Text size as a percentage of default (50-150). |
| Window Alpha / Background Alpha | Transparency for window chrome and row backgrounds. |

## Textures

Three LSM-backed pickers let you swap the meter's textures:

- **Bar Texture** — the fill texture on each row's bar.
- **Background Texture** — the row background fill behind each bar.
- **Border Texture** — the 1px border around each row.

Any LSM-registered statusbar / background / border texture is selectable. Leave a control unset to keep the default QUI look.

## Fonts

Each of three text surfaces (Row Name, Row Value, Session Window Header) has its own font picker, size slider (`0` = preserve default), and outline dropdown. Outline can inherit the global QUI outline preference, be `None`, `Thin`, or `Thick`.

Defaults preserve QUI's existing rendering for row text — the customization is opt-in. The session window header is the one place defaults shift: previously unstyled by QUI, the header text now uses QUI's general font/outline by default to match the rest of the addon's text. Pick "Inherit (global outline)" to keep the global setting, or pick a different font/size/outline to override.

## Tips

{: .note }
The damage meter only renders rows during/after combat. Bar texture and row font changes are most visible while combat data is on screen.

{: .note }
Settings apply live to the visible meter — there is no separate preview frame. Pop the meter open and adjust in real time.
