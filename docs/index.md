---
layout: default
title: Home
nav_order: 1
---

# QUI Documentation
{: .fs-9 }

A modular World of Warcraft UI suite for Midnight 12.0+ that you can install, understand, and tune from one settings experience.
{: .fs-6 .fw-300 }

**Current Beta: 4.0.0-beta56**
{: .label .label-purple }

[Get Started](getting-started/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Explore Features](features/){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/zol-wow/QUI){: .btn .fs-5 .mb-4 .mb-md-0 }

![Actual QUI navigation overview]({{ '/assets/images/qui-navigation-overview.png' | relative_url }})
_Actual QUI settings screen showing the main navigation areas._

---

## What is QUI?

QUI is a full UI package for players who want combat information, layout controls, utility tools, inventory helpers, account tracking, and visual polish to live in one place. It brings together a custom combat HUD, modular feature addons, layout editing, minimap and action bar styling, group tools, chat, bags, data panels, quality-of-life automation, and profile management under one settings experience.

QUI's interface is also localized into 11 languages and follows your WoW client language automatically. See [Localization](features/localization).

If you are new to QUI, the easiest way to think about it is this: install all `QUI*` folders, open `/qui`, choose which optional modules you want, then fine-tune the pieces you care about.

{: .important }
QUI 4 beta is a multi-folder addon suite. Addon-manager installs handle this automatically. Manual installs must copy every top-level `QUI*` folder from the release zip into `Interface\AddOns\`, not only the `QUI` folder.

## Why Players Pick QUI

- **One suite, one design language** for combat HUD, utility panels, skinning, chat, bags, and layout controls.
- **Fast to set up** with bundled imports, profile tools, and a dedicated Layout Mode.
- **Easy to grow into** whether you only want the essentials or plan to enable the newer optional modules.
- **Built for real gameplay** with strong support for dungeon, raid, healing, and general-use workflows.

## Start Here

1. Open the [Getting Started](getting-started/) guide.
2. Follow the [Installation](getting-started/installation) steps.
3. Run through the [First Setup](getting-started/first-setup) walkthrough.
4. Review [Module Addons](getting-started/module-addons) so you know which beta modules are opt-in.
5. Use [Layout Mode](features/frame-layout) to place your HUD where it feels natural.
6. Browse the [Features](features/) section to decide what you want QUI to handle for you.

---

## What QUI Covers

### Combat HUD

| Feature | Description |
|:--------|:------------|
| [**Cooldown Manager**](features/cooldown-manager) | Keeps your important abilities, buffs, and procs near the center of your screen so you can stop staring at your bars. |
| [**Unit Frames**](features/unit-frames) | Replaces your combat frames with cleaner, more configurable player, target, focus, pet, and boss frames. |
| [**Group Frames**](features/group-frames) | Adds opt-in party and raid frames built for healing, support, and high-information group play. |
| [**Custom Trackers**](features/custom-trackers) | Lets you build extra bars for trinkets, utility spells, consumables, or niche encounter tracking. |
| [**HUD Visibility**](features/hud-visibility) | Controls when HUD elements appear, fade, or hide so your screen stays clean outside combat. |
| [**Damage Meter**](features/damage-meter) | Adds QUI-styled native damage meter windows with selectable views and layout controls. |

### Action Bars & Interface

| Feature | Description |
|:--------|:------------|
| [**Action Bars**](features/action-bars) | Cleans up your bars, supports mouseover fade, and makes keybinds and ability states easier to read. |
| [**Minimap & Data Panels**](features/minimap-datatext) | Gives you a polished minimap, optional button drawer, and compact information panels for everyday play. |
| [**Chat**](features/chat) | Offers either styling for stock chat or the opt-in QUI Chat display with custom tabs, copy tools, and Combat Log support. |
| [**Tooltips**](features/tooltips) | Restyles tooltips and adds extra context like IDs, rating, guild info, and smart hiding rules. |
| [**Skinning**](features/skinning) | Applies QUI's look to many Blizzard windows so the whole UI feels cohesive. |
| [**Info Bar**](features/info-bar) | Adds an optional top or bottom bar for datatext widgets, micro menu buttons, travel, and spec switching. |
| [**Bags**](features/bags) | Adds optional bag, bank, Warband bank, guild bank, sorting, search, and item-count tools. |

### Dungeon & Group Content

| Feature | Description |
|:--------|:------------|
| [**M+ Timer**](features/dungeon-features) | Tracks timer pressure, deaths, and route progress in a cleaner format. |
| [**Party Keystones**](features/dungeon-features) | Surfaces group key information without extra setup. |
| [**Battle Res Counter**](features/dungeon-features) | Keeps your available battle resurrection charges visible. |
| [**Dungeon Teleport**](features/dungeon-features) | Makes earned dungeon teleports faster to access. |
| [**Auto Combat Log**](features/dungeon-features) | Handles logging automatically for players who review runs or report encounters. |

### Character & Quality of Life

| Feature | Description |
|:--------|:------------|
| [**Character Pane**](features/character-pane) | Adds more gear and stat context to your character and inspect windows. |
| [**Alts**](features/alts) | Tracks account-wide characters, equipment, currencies, reputations, weeklies, professions, and item locations. |
| [**Blizzard Frame Mover**](features/blizzard-frame-mover) | Lets you drag more default UI pieces without relying entirely on Edit Mode. |
| [**Quality of Life**](features/quality-of-life) | Bundles helpful automation, reminders, and convenience tools that save clicks every session. |
| [**Skyriding**](features/skyriding) | Improves Skyriding readability with a clearer vigor and speed display. |
| [**XP Tracker**](features/xp-tracker) | Adds a lightweight XP bar for leveling and casual play. |

### Layout & Configuration

| Feature | Description |
|:--------|:------------|
| [**Layout Mode**](features/frame-layout) | Gives you a visual editor for positioning and tuning major HUD elements without guesswork. |
| [**Frame Anchoring**](features/frame-layout) | Helps related elements move together so your HUD stays organized. |
| [**Keybinds & Integrations**](features/keybinds-integrations) | Makes keybinding faster and improves how QUI works with compatible systems. |
| [**Localization**](features/localization) | Translates QUI's interface into 11 languages with CJK font rendering, following your WoW client language automatically. |
| [**Profiles**](getting-started/profiles) | Lets you keep one setup, per-character setups, or per-spec setups without rebuilding from scratch. |
| [**Performance Monitor**](features/performance-monitor) | Exposes memory and event information when you need to troubleshoot. |

---

## Recommended First Pass

If you want a clean result quickly, start with these pages:

- [**First Setup**](getting-started/first-setup) for the 10-minute setup path.
- [**Module Addons**](getting-started/module-addons) before enabling beta modules like Bags, Info Bar, Alts, or QUI Chat.
- [**Cooldown Manager**](features/cooldown-manager) if you want the signature combat HUD.
- [**Frame Layout**](features/frame-layout) if you want to move, anchor, or refine your screen.
- [**Action Bars**](features/action-bars) and [**Minimap & Data Panels**](features/minimap-datatext) for overall polish.
- [**Quality of Life**](features/quality-of-life) for the everyday conveniences many players end up keeping on.

---

## Documentation Sections

- [**Getting Started**](getting-started/) for installation, first login, profiles, slash commands, and troubleshooting.
- [**Features**](features/) for plain-language walkthroughs of what each part of QUI does in play.
- [**Settings**](settings/) for the deeper, power-user reference pages that mirror the in-game options.

---

## Community

- [GitHub](https://github.com/zol-wow/QUI) for releases, source, and issue tracking.
- [Discord](https://discord.gg/FFUjA4JXnH) for setup help and community discussion.
- [CurseForge](https://www.curseforge.com/wow/addons/qui-community-edition) for downloads and update tracking.
- [Ko-fi](https://ko-fi.com/zol__) to support ongoing maintenance.
