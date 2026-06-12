[![GitHub release](https://img.shields.io/github/v/release/zol-wow/QUI)](https://github.com/zol-wow/QUI/releases)
[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](https://opensource.org/licenses/)
[![Discord](https://img.shields.io/badge/discord-QUI-0da37b?logo=discord&logoColor=white)](https://discord.gg/FFUjA4JXnH)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20me-ff5e5b?logo=ko-fi)](https://ko-fi.com/zol__)

# QUI Community Edition

QUI is a modular World of Warcraft UI suite for Midnight 12.0+. It combines combat HUD tools, layout editing, action bars, unit and group frames, chat, minimap controls, data panels, a native damage meter, profile tools, and quality-of-life helpers under one settings experience.

Current beta: **v4.0.0-beta43**.

## What is New in QUI 4

- **Modular addon suite:** QUI now ships as a core addon plus feature folders such as `QUI_ActionBars`, `QUI_CDM`, `QUI_Chat`, `QUI_Bags`, `QUI_InfoBar`, `QUI_Alts`, and `QUI_Options`.
- **Module Addons page:** enable or disable whole feature addons from `/qui` without digging through the character-select addon list.
- **Opt-in QUI Chat:** custom chat display with multi-window support, conversation tabs, an embedded Combat Log tab, copy window, tab overflow menu, and safer restore behavior.
- **QUI Bags:** optional bag, bank, Warband bank, and guild bank windows with search everywhere, sorting, item badges, currency bar, merchant tools, and cached bank browsing.
- **Info Bar:** optional top or bottom bar that hosts datatext widgets, a micro menu, travel controls, spec swapping, and data-object style plugin feeds.
- **Alts:** optional account-wide character tracker with roster, equipment, professions, reputations, weeklies, currencies, and cross-character item search.
- **Layout Mode improvements:** anchored frames follow live while dragging, anchored chat and damage meter windows keep their anchor pinned while resizing, and mover teardown restores windows cleanly.
- **Damage meter polish:** native meter windows support per-window settings, row popouts, reset keybinds, and an option to hide secondary row values.

## Core Features

- Cooldown Manager with icon, aura, and bar containers plus a spell composer.
- Unit frames for player, target, focus, pet, boss, and related combat frames.
- Opt-in group frames with click-casting, private auras, raid buffs, and party/raid layouts.
- Action bars with mouseover fade, per-bar options, buff borders, pet/stance handling, micro menu, and bag bar controls.
- Minimap, data panels, and shared currency/datatext settings.
- Dungeon tools: M+ timer, party keystones, battle res counter, teleport shortcuts, and combat logging helpers.
- Skinning and frame mover coverage for many Blizzard windows and alerts.
- Profile import/export, selective profile imports, and profile migration backups.

## Installation

### Addon Manager

1. Search for **QUI Community Edition** in your addon manager.
2. Install or update normally.
3. Log in and open `/qui`.

### Manual Install

1. Download the latest release zip from [GitHub Releases](https://github.com/zol-wow/QUI/releases) or [CurseForge](https://www.curseforge.com/wow/addons/qui-community-edition).
2. Extract the zip.
3. Copy every top-level `QUI*` folder from the zip into:
   ```text
   World of Warcraft\_retail_\Interface\AddOns\
   ```
4. Confirm `QUI.toc`, `QUI_Options\QUI_Options.toc`, and the other `QUI_*` `.toc` files sit directly under `Interface\AddOns\`.
5. Back up your `WTF` folder before installing beta builds.

## Documentation

- User guide: https://zol-wow.github.io/QUI/
- Releases: https://github.com/zol-wow/QUI/releases
- Issues: https://github.com/zol-wow/QUI/issues

## Credits

QUI Community Edition continues work originally created by Quazii and expanded by community contributors.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
