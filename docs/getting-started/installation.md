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
3. Copy the `QUI` folder into your WoW addons directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\QUI
   ```
4. Make sure the folder structure is correct -- `QUI.toc` should be directly inside the `QUI` folder, not nested in a subfolder.

## Confirm It Loaded Correctly

1. Launch World of Warcraft.
2. On the character select screen, click **AddOns** in the lower-left corner.
3. Confirm that **QUI** appears in the addon list and is enabled.
4. Log in to a character and type `/rl` to reload the UI.
5. Type `/qui` to open the options panel and confirm QUI is running.

## If Something Looks Wrong

- If QUI does not appear in the addon list, check that the folder is not nested twice.
- If `/qui` does nothing, reload once and try again.
- If the addon loads but the screen looks unfinished, continue to [First Setup](first-setup) before assuming anything is broken.

Compatible integrations are detected automatically when they are present, but QUI does not need extra addons to work.
