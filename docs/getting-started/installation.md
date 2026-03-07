---
layout: default
title: Installation
parent: Getting Started
nav_order: 1
---

# Installation

QUI requires **World of Warcraft Midnight (12.0+)**. It supports Interface versions `120000` and `120001`.

## Option 1: CurseForge or WoWUp App

The easiest way to install QUI is through an addon manager.

1. Open the **CurseForge** or **WoWUp** application.
2. Search for **"QUI Community Edition"**.
3. Click **Install**.
4. The app handles updates automatically.

## Option 2: Manual Installation

1. Download the latest release from one of these sources:
   - [GitHub Releases](https://github.com/zol-wow/QUI/releases)
   - [CurseForge](https://www.curseforge.com/wow/addons/qui-community-edition)
2. Extract the downloaded zip file.
3. Copy the `QUI` folder into your WoW addons directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\QUI
   ```
4. Make sure the folder structure is correct -- `QUI.toc` should be directly inside the `QUI` folder, not nested in a subfolder.

## Verifying the Installation

1. Launch World of Warcraft.
2. On the character select screen, click **AddOns** in the lower-left corner.
3. Confirm that **QUI** appears in the addon list and is enabled.
4. Log in to a character and type `/rl` to reload the UI.
5. Type `/qui` to open the options panel and confirm QUI is running.

## Optional Dependencies

QUI works as a standalone addon, but it can integrate with the following addons if they are installed:

| Addon | Integration |
|-------|-------------|
| **DandersFrames** | Frame anchoring integration for enhanced layout control. |
| **BigWigs** | Anchoring integration and pull timer coordination. |

These addons are not required. QUI will detect them automatically and enable integration features when they are present.
