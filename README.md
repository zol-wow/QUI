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

## Coming from QUI

QUI stores its settings separately from QUI, under `QUIDB`. There are two ways to bring your QUI configuration across.

**Both ways need QUI disabled or uninstalled on the character you log in with.** Addon enable state is per character, so untick QUI in the AddOns list at character select — or delete the `QUI` folder entirely. QUI refuses to import anything while QUI is still loaded, and tells you so in chat if you try.

### Copy your saved variables file (recommended)

This works even if you have already uninstalled QUI, because the game keeps a saved variables file after the addon folder is gone. Close WoW first, then find your account's saved variables folder:

```text
World of Warcraft\_retail_\WTF\Account\<YOUR ACCOUNT>\SavedVariables\
```

It holds one file per addon. QUI's is `QUI.lua`. QUI's is `QUI.lua`, which only appears once you have played with QUI installed and logged out at least once. Look in the folder and check whether `QUI.lua` is there — that answers which of the two recipes below you want.

**Recipe 1 — there is no `QUI.lua`.** Copy `QUI.lua`, leave the original where it is, and rename the copy to `QUI.lua`.

**Recipe 2 — `QUI.lua` is already there.** Do not replace it. That file *is* your QUI settings, and overwriting it deletes them. Make a backup copy of it first. Then open `QUI.lua` and `QUI.lua` in a plain text editor, copy everything out of `QUI.lua`, paste it at the **end** of `QUI.lua`, and save. Your QUI profiles are then added alongside the ones you already have instead of replacing them, and you pick the one you want under Options → Profiles.

Either way, start the game afterwards with QUI disabled. QUI reads your QUI settings on the next login and tells you in chat when it has. If it instead says the settings look incomplete, the copy or paste was truncated — restore your backup and try again.

### Or import a profile string

If you can still run QUI, export a profile string from it first. Then disable or uninstall QUI, log in with QUI, and paste the string under Options → Import & Export Strings. QUI reads QUI's `QUI1:` strings natively.

Neither way writes to `QUI.lua`, so QUI's own saved variables stay intact and you can keep the addon folder around until you are sure you no longer need it — just leave it disabled.

Slash commands changed: `/qui` is now `/qui` (or `/qui`), and the rest of the `/qui*` family is now `/qui*` — for example `/quibags` is now `/quibags`.

## Documentation

- User guide: https://zol-wow.github.io/QUI/
- Releases: https://github.com/zol-wow/QUI/releases
- Issues: https://github.com/zol-wow/QUI/issues

## Credits

QUI is a derivative work of QUI. The original addon was created by **Quazii**, and QUI Community Edition was expanded and maintained by **Zol**, **LiQiuDGG**, and **Mondo**. This fork would not exist without their work.

## License

This project is licensed under the GNU General Public License v3.0, the same license as the upstream project it derives from. See [LICENSE](LICENSE) for details.
