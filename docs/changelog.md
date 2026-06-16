---
layout: default
title: Changelog
nav_order: 5
---

# Changelog

This page summarizes the user-facing changes since the last mainline release. For every beta entry and technical fix, see the full [CHANGELOG.md](https://github.com/zol-wow/QUI/blob/main/CHANGELOG.md).

## Current Beta: v4.0.0-beta56 - 2026-06-16

QUI 4 is a major beta update over v3.5.11. The biggest change is that QUI now ships as a modular suite: a core addon plus feature folders you can manage from `/qui` > **Module Addons**. The most recent betas add full interface localization, per-frame unit-frame border colors, a Volume datatext control panel, and a large round of Group Frames, Layout Mode, and Bags refinements.

{: .important }
Back up your `WTF` folder before installing beta builds. Manual installs must copy every `QUI*` folder from the release zip into `Interface\AddOns\`.

## Latest Updates (beta44–beta56)

These are the user-facing changes since beta43. None of these betas require a profile migration past beta47, and your settings carry over.

### Localization (beta56)

- **QUI's interface is now translated into 11 languages** — English plus German, Spanish (Spain & Mexico), French, Italian, Korean, Portuguese (Brazil), Russian, and Simplified & Traditional Chinese. The language follows your WoW client automatically; English clients see no change.
- **CJK font rendering** picks a font fallback for Korean and Chinese automatically, so those glyphs display correctly. (Options search stays English for now.) See [Localization](features/localization).

### Unit & Group Frames

- **Per-frame Unit Frame border color (beta52).** Each frame (player, target, pet, focus, target-of-target, boss) can pick its own border color — Inherit, Theme, Class, or Custom — instead of all frames sharing one skin border.
- **Group Frames unified aura model (beta47).** Buff/debuff auras, pinned auras, and indicators now share one Auras model with a reworked live preview and a faster in-combat render path.
- **Group Frames fixes.** Power-bar space is reclaimed when power bars are off; dispel/defensive indicators no longer stay lit after the aura ends; bottom-anchored defensive indicators no longer overlap the power bar.

### Info Bar & Datatexts

- **Volume datatext control panel (beta44).** Left-click opens a themed popup with Master/SFX/Music/Ambience/Dialog sliders and a Mute-all toggle. Audio settings moved to middle-click.
- **Travel widget label & tooltip and a per-widget "Hide Text" (icon-only) toggle (beta51).**
- **Shift-drag to reorder datatexts (beta47),** including the Volume widget (beta56 fix).

### Bags, Alts & Chat

- **Bags: "Pack to bottom" sort (beta46)** and reagent-bag sorting parity (beta47).
- **Alts: right-click to untrack** currency and reputation rows (beta46).
- **Chat: saved-tab right-click Filter/Tab Settings menus (beta45),** Blizzard whisper pop-out routing, and stable sender class colors (beta55).

### Layout Mode

- **Opens collapsed (beta54)** with the toolbar and frames drawer tucked away.
- **Anchored windows and castbars** position correctly in Layout Mode, and resizing an anchored window keeps its anchor pinned (beta42–54).

### Setup & Profiles

- **New profiles seed from QUI's shipped defaults automatically (beta47);** the old first-run welcome popup is gone. Profiles older than schema v31 (pre-3.5.11) are backed up, reset, and reseeded at login; 3.5.11+ profiles migrate unchanged.

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
