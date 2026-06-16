---
layout: default
title: Bags
parent: Features
nav_order: 6
---

# Bags

QUI Bags is an optional beta module that replaces the bag, bank, Warband bank, and guild bank windows with QUI-styled inventory tools.

{: .important }
Bags is off by default. Enable it under `/qui` > **Module Addons** when you want to test it. If you disable it, QUI hands bag windows back to Blizzard while the shared account storage cache keeps collecting data in the background.

## What It Covers

- Backpack and reagent bags
- Character bank and Warband bank
- Guild bank, including an **All** tab for browsing every tab at once
- Search Everywhere across cached characters and storage locations
- Currency bar using the same shared currency list as datatext panels and the Info Bar
- Tooltip item counts across your characters

## How To Enable

1. Open `/qui`.
2. Go to **Module Addons**.
3. Enable **Bags**.
4. Reload if prompted.
5. Use `/quibags` or your normal bag keybind.

## Main Window Tools

- **Flat or category layout** -- choose a simple grid or grouped item sections.
- **Corner badges** -- show item level, quality, stack count, binding, expansion, equipment set, and other item states.
- **Search** -- filter the current window or open Search Everywhere.
- **Sorting** -- sort by quality, type, name, item level, or expansion.
- **Pack to bottom** -- a sort-menu checkbox that packs the sorted run into the bottom slots of the grid so empty slots float to the top, while keeping best-to-worst reading order. If your bags overflow, it falls back to filling from the top.
- **Junk tools** -- dim junk and sell junk at merchants.
- **New item glow** -- mark newly acquired items until you clear them.

## Bank And Guild Bank

At the bank, QUI opens its own bank window and supports Warband reagent deposit flows. Away from the bank, cached browsing lets you inspect the last known bank contents from the bag window or `/quibags bank`.

At a guild bank, QUI opens a styled guild vault window. The **All** tab shows all visible tabs together, and hovering a tab button highlights its slots in the grid. Away from the vault, `/quibags guild` opens cached guild-bank data for quick lookup.

## Auction House Support

With the auction house open, right-clicking an auctionable item in QUI Bags stages it in the sell panel. Items that cannot be sold there dim while the sell panel is open.

## Slash Commands

| Command | Description |
|---------|-------------|
| `/quibags` | Toggle the bag window. |
| `/quibags search` | Open Search Everywhere. |
| `/quibags bank` | Open live or cached bank browsing. |
| `/quibags guild` | Open live or cached guild-bank browsing. |
| `/quibags clearnew` | Clear all new-item glow markers. |

## Good To Know

- Bags is newer beta functionality. Keep normal bag muscle memory handy while testing it.
- Bag-modifying operations cancel when combat starts.
- Offline character inventory fills in as characters log in and the shared storage cache learns their current state.
- Currency visibility and order are shared with the Currencies datatext, minimap panel, and Info Bar.
- Sorting packs crafting reagents into the universal reagent bag, matching Blizzard's own sort behavior.
- Item-level corner text stays on gear and no longer shows on consumables or reagents.
