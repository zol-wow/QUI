---
layout: default
title: Installation
parent: Getting Started
nav_order: 1
---

# Installation

QUI requires **World of Warcraft Midnight (12.0+)**.

## Fastest Option: Addon Manager

For most players, the easiest path is an addon manager.

1. Open the **CurseForge** or **WoWUp** application.
2. Search for **"QUI Community Edition"**.
3. Click **Install**.
4. The app handles updates automatically.

## Manual Install

1. Download the latest release from one of these sources:
   - [GitHub Releases](https://github.com/zol-wow/QUI/releases)
   - [CurseForge](https://www.curseforge.com/wow/addons/qui-community-edition)
2. Extract the downloaded zip file.
3. Copy every top-level `QUI*` folder from the zip into your WoW addons directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
4. Make sure the folder structure is correct -- `QUI.toc` should be directly inside `Interface\AddOns\QUI\`, `QUI_Options.toc` should be directly inside `Interface\AddOns\QUI_Options\`, and the other `QUI_*` folders should sit beside them.

{: .important }
QUI 4 beta is a multi-folder addon suite. If you manually copy only `QUI`, the options panel and feature modules will be missing.

## Confirm It Loaded Correctly

1. Launch World of Warcraft.
2. On the character select screen, click **AddOns** in the lower-left corner.
3. Confirm that **QUI** and its `QUI_*` modules appear together in the addon list and are enabled as desired.
4. Log in to a character and type `/rl` to reload the UI.
5. Type `/qui` to open the options panel and confirm QUI is running.

## If Something Looks Wrong

- If QUI does not appear in the addon list, check that the folders are not nested twice.
- If `/qui` does nothing, confirm `QUI_Options` is installed and enabled, then reload once and try again.
- If the addon loads but the screen looks unfinished, continue to [First Setup](first-setup) before assuming anything is broken.

Compatible integrations are detected automatically when they are present, but QUI does not need extra addons to work.

## Beta Upgrade Safety

Before installing a beta build, back up your `WTF` folder. QUI takes automatic profile backups for some schema migrations, but a full `WTF` backup is still the safest rollback path.
