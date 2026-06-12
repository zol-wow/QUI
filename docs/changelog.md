---
layout: default
title: Changelog
nav_order: 5
---

# Changelog

This page summarizes the user-facing changes since the last mainline release. For every beta entry and technical fix, see the full [CHANGELOG.md](https://github.com/zol-wow/QUI/blob/main/CHANGELOG.md).

## Current Beta: v4.0.0-beta43 - 2026-06-12

QUI 4 is a major beta update over v3.5.11. The biggest change is that QUI now ships as a modular suite: a core addon plus feature folders you can manage from `/qui` > **Module Addons**.

{: .important }
Back up your `WTF` folder before installing beta builds. Manual installs must copy every `QUI*` folder from the release zip into `Interface\AddOns\`.

## Major Additions

### Modular QUI Suite

- QUI is now split into feature addon folders.
- The **Module Addons** page controls whole modules such as Chat, Bags, Info Bar, Alts, Group Frames, Damage Meter, Datatexts, Minimap, and Quality of Life.
- Several large beta modules are off by default so existing setups can stay conservative.
- Options search now loads on demand, reducing first-open cost.

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

- v3.5.11 to QUI 4 beta is a major upgrade. Back up `WTF`, then install all `QUI*` folders.
- If a module is missing, check for a partial manual install first.
- If a feature does not open, check `/qui` > **Module Addons** before troubleshooting settings.
- Some account-cache data, especially offline inventory and equipment, repopulates as each character logs in.
