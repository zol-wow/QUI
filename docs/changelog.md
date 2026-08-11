---
layout: default
title: Changelog
nav_order: 5
---

# Changelog

This page summarizes the user-facing changes since the last mainline release. For every beta entry and technical fix, see the full [CHANGELOG.md](https://github.com/zol-wow/QUI/blob/main/CHANGELOG.md).

## Current Release: 5.0.0

{: .warning }
**WoW 12.1 only.** This build targets patch 12.1 (interface 120100) and will not load on the 12.0.x client.

QUI 5.0 rebuilds nameplates as their own addon, puts nameplates, group frames and unit frames on one shared aura engine, and cuts the suite from 22 addon folders to 11. It is also the release that adapts to 12.1's stricter rules about what an addon may read.

{: .important }
Back up your `WTF` folder before installing beta builds. Manual installs must copy every `QUI*` folder from the release zip into `Interface\AddOns\`.

## What's New in 5.0

### Nameplates

- **Nameplates are their own addon**, with a setup wizard and a settings preview that renders a real plate 1:1 and follows whatever you are editing.
- **Every plate type gets its own config** — pets and minions, friendly units, bosses and elites, minor and trivial units, enemy players and enemy NPCs — picked from a dropdown with a Copy From control.
- **Target indicators** (arrow, brackets, glow line), class power pips on the target plate, execute-threshold health colouring, and threat colour mapping.
- **A Visibility tab** with an enemy-plate master toggle, friendly NPCs exposed, and Minions nesting Guardians, Pets and Totems. `Show In Instances` is a never / name-only / always choice.
- **Name-only is a real render mode** — QUI draws the name and hides the bar and aura containers rather than restyling Blizzard's text.

### Auras

- **One aura engine drives nameplates, group frames and unit frames**, so an element configured on one behaves the same on the others.
- **Pandemic glow** flashes an icon as its aura enters the refresh window, driven by the game's own pandemic region rather than a timer QUI approximates.
- **Dispel borders and stealable buffs come from the game.** An aura element can be set to `Debuffs + Stealable Buffs` or `All Auras`.

### Speed and size

- **The suite is 11 addon folders instead of 22.** Locales ship packed, so only the language in use is ever compiled, and login memory drops by roughly 2.3 MB.
- **Settings search is 2.5–3x faster.** One English index ships instead of ten translated copies; typing the English term still finds the translated row on non-English clients.
- **The options panel opens instantly**, building on the first frame after login, and moving between settings tabs reuses the page it already built.

### Localization

- **Every non-English locale is actually translated now.** Nine of the ten had been falling back to English for roughly 900 strings each.

### Adapting to 12.1

- **Atonement tracking no longer reads the combat log** — 12.1 closed combat log events to addons, so the counter watches auras directly.
- **The Brez counter lost its resurrection list** for the same reason. The charge count, recharge timer and per-pull tally are unaffected.

## Major Additions

### Modular QUI Suite

- QUI is now split into feature addon folders.
- The **Module Addons** page controls whole modules such as Chat, Bags, Info Bar, Alts, Group Frames, Damage Meter, Datatexts, Minimap, and Quality of Life.
- Several large beta modules are off by default so existing setups can stay conservative.
- The settings panel builds on the first frame after login, so it opens instantly.

### QUI Chat

- Optional QUI-owned chat display.
- Multi-window chat, saved tabs, whisper conversation tabs, copy window, custom scrollbar, and tab overflow menu.
- Combat Log can be embedded as a pinned chat tab.
- Copy Chat preserves visible colors and readable link text.
- Reply keybind, Battle.net notices, channel colors, guild message of the day, and cross-realm sender display received follow-up fixes.

### QUI Bags

- Optional bag, bank, Warband bank, and guild bank windows.
- Search Everywhere across cached storage.
- Item badges, category layout, sorting, junk tools, new-item glow, tooltip item counts, and optional currency bar.
- Auction-house right-click selling support.
- Guild bank **All** tab and cached bank/guild-bank browsing away from the bank.

### Info Bar And Datatexts

- Optional top or bottom Info Bar with left, center, and right widget zones.
- Right-click empty Info Bar space to add, remove, arrange, or configure widgets.
- New datatexts include Reputation, Great Vault, Mail, Professions, and Alts.
- Currencies list is shared across Info Bar, minimap/data panels, Bags, and datatext surfaces.

### Alts

- Optional account-wide character tracker.
- Roster, equipment, professions, reputations, weeklies, currencies, and item search tabs.
- Equipment tab compares gear across characters.
- Currency and reputation filters are available in-window and in settings.
- Character storage moved into core so data collection can run independently of the Alts or Bags UI.

### Damage Meter

- Native QUI damage meter windows.
- Per-window appearance editing, row breakdown popups, pinned self row, automatic key-start reset, current/overall/previous sessions, and reset command.
- New toggle to hide secondary row values.

## Important Improvements

- Layout Mode anchored frames now follow live while dragging.
- Anchored chat and damage meter windows keep their anchor pinned while resizing.
- Chat windows no longer lose pending Layout Mode moves when chat settings change.
- Minimap drawer now keeps collected buttons inside the drawer, including late-created buttons.
- Action bars gained clearer enable toggles for micro menu and bag bar.
- M+ timer gained objective alignment and bar-height controls.
- Group frames gained private-aura text scale and additional stability work.
- Character pane enchant and tooltip behavior received beta fixes.
- CDM no longer auto-removes tracked spells just because the game temporarily reports them unknown; unusable entries go dormant and return when available.
- Keyboard click-cast binds now activate only while hovering registered unit frames.

## Upgrade Notes

- **4.x to 5.0 is an install over the top.** Same addon folders, same saved variables (`QUIDB` and `QUI_StorageDB`) — nothing to move by hand. Profiles migrate to the current schema on first login and are backed up beforehand; `/qui migration status` and `/qui migration restore` expose those backups.
- Back up your `WTF` folder before installing an alpha or beta build.
- Manual installs must copy every top-level `QUI*` folder from the release zip, not only the `QUI` folder.
- **If you hand-installed 5.0.0-alpha29 or earlier**, the eleven `QUI_OptionsSearch` folders are left behind after updating. Nothing loads them — delete them.
- If a feature does not open, check `/qui` > **Module Addons** before troubleshooting settings.
- Some account-cache data, especially offline inventory and equipment, repopulates as each character logs in.
