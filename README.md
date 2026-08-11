[![GitHub release](https://img.shields.io/github/v/release/zol-wow/QUI)](https://github.com/zol-wow/QUI/releases)
[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](https://opensource.org/licenses/)

# QUI

QUI is a modular World of Warcraft UI suite for Midnight 12.1+. It combines combat HUD tools, layout editing, action bars, unit and group frames, chat, minimap controls, data panels, a native damage meter, profile tools, and quality-of-life helpers under one settings experience.

## Highlights

- **Modular addon suite:** a core addon plus feature folders such as `QUI_ActionBars`, `QUI_CDM`, `QUI_Chat`, `QUI_Bags`, and `QUI_Options`.
- **Module Addons page:** enable or disable whole feature addons from `/qui` without digging through the character-select addon list.
- **Cooldown Manager:** icon, aura, and bar containers plus a spell composer with custom containers and duplicate placements.
- **Layout Mode:** `/qui layout` moves QUI-managed frames with an edge-docked toolbar and live settings panels.
- **Opt-in Chat:** multi-window support, conversation tabs, an embedded Combat Log tab, copy window, tab overflow menu, and safer restore behavior.
- **Bags:** optional bag, bank, Warband bank, and guild bank windows with search everywhere, sorting, item badges, currency bar, merchant tools, and cached bank browsing.
- **Info Bar:** optional top or bottom bar hosting datatext widgets, a micro menu, travel controls, spec swapping, and data-object plugin feeds.
- **Alts:** optional account-wide character tracker with roster, equipment, professions, reputations, weeklies, currencies, and cross-character item search.
- **Unit and group frames:** player, target, focus, pet, and boss frames, plus opt-in group frames with click-casting, raid buffs, and party/raid layouts.
- **Action bars:** mouseover fade, per-bar options, buff borders, pet/stance handling, micro menu, and bag bar controls.
- **Dungeon tools:** M+ timer, party keystones, battle res counter, teleport shortcuts, and combat logging helpers.
- **Localized options search** across 11 languages.

## Installation

1. Download the latest release zip from [GitHub Releases](https://github.com/zol-wow/QUI/releases).
2. Extract the zip.
3. Copy every top-level `QUI*` folder from the zip into:
   ```text
   World of Warcraft\_retail_\Interface\AddOns\
   ```
4. Confirm `QUI.toc`, `QUI_Options\QUI_Options.toc`, and the other `QUI_*` `.toc` files sit directly under `Interface\AddOns\`.
5. Back up your `WTF` folder before installing alpha or beta builds.

Log in and open `/qui` (or `/qui`) to get started.

## Upgrading from 4.x

Install over the top. There is nothing to move by hand: 5.0 uses the same addon folders and the same saved variables as 4.x (`QUIDB` and `QUI_StorageDB`), so your profiles, layouts and keybinds are already where the addon looks for them.

On first login QUI brings each profile up to the current settings schema, taking a backup of that profile before it changes anything. `/qui migration status` prints the schema version and lists the available backup slots, and `/qui migration restore` rolls back to one if something looks wrong.

Back up your `WTF` folder first if you are installing an alpha or beta build.

## Documentation

- User guide: https://zol-wow.github.io/QUI/
- Releases: https://github.com/zol-wow/QUI/releases
- Issues: https://github.com/zol-wow/QUI/issues

## Credits

QUI began as an addon created by **Quazii**, and was expanded and maintained as QUI Community Edition by **Zol**, **LiQiuDGG**, and **Mondo**. It would not exist without their work.

## License

This project is licensed under the GNU General Public License v3.0, the same license as the upstream project it derives from. See [LICENSE](LICENSE) for details.
