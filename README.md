[![GitHub release](https://img.shields.io/github/v/release/zol-wow/QUI)](https://github.com/zol-wow/QUI/releases)
[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](https://opensource.org/licenses/)
[![Discord](https://img.shields.io/badge/discord-QUI_2.0-0da37b?logo=discord&logoColor=white)](https://discord.gg/FFUjA4JXnH)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20me-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/zol__)
[![Ko-fi](https://img.shields.io/badge/PayPal-Support%20me-142c8e?logo=paypal&logoColor=white)](https://paypal.me/ZolQUI)

# QUI 2.0 – QuaziiUI continued and kept alive

### Why This Exists

Quazii created one of the most loved and polished UI packages for World of Warcraft – especially in the pre-Midnight era. Many players (myself included) still rely on its design philosophy: minimalism, performance in high-end content (Mythic+, Raiding), and pixel-perfect scaling without the bloat.

After the recent drama involving code disputes, monetization concerns, and Quazii's decision to retire from the scene, the original QUI is no longer being updated or supported. This repo aims to:

- Preserve the core vision and feel of QuaziiUI
- Make it freely available to everyone (no Patreon, no paid installers – pure open-source)
- Fix compatibility issues for current WoW patches (e.g., Midnight 12.0+)
- Use public, community-approved libraries to avoid any past controversies (rewrote scaling logic from scratch)
- Keep the UI as a free resource for the community that Quazii once built it for

For the base of this I cleaned up and re-organized the code base, removed the controversial PixelPerfect code snippets, in part likely copied from ElvUI, and merged some of the open feature branches from before Quazii's exit. The rest of the base is basically the state of **QuaziiUI v1.99b**.

Since then I added a few features and fixes important to me, and I will continue doing that for at least until a while into Midnight. Feel free to raise issues or create pull requests, I will try to get to them as quickly as possible.

### Credits & Thanks

- **Original Creator**: Quazii – for the vision, the clean design, the performance optimizations, and the countless hours of work that made QUI special.
- **Original Co-Developers & Contributors**: All the people who helped shape QUI behind the scenes (you know who you are, let me know if you want to be mentioned). Your code, ideas, and testing live on here.
- **Special Thanks**: To everyone who reached out after the fallout, shared ideas, or simply kept using the UI. This repo exists because of you.

### Features (Inherited + Improvements)

- Clean, modern UI layout
- Strong performance focus (Mythic+, Raiding)
- Pixel-perfect scaling
- Customizable bars, frames, cooldowns, etc.
- Ongoing fixes for Midnight patch compatibility

### Installation

#### Manual Installation

1. Download the latest release from [Releases](https://github.com/zol-wow/QUI/releases) or CurseForge: (https://www.curseforge.com/wow/addons/qui-community-edition)
2. Extract to `Interface\AddOns\QUI`
3. Enable in-game and reload UI (`/rl` or `/reload`)

#### Installation via WoWUp or CurseForge

1. Go to "Get Addons"
2. Search for "QUI Community Edition"
2. Press Install


## License

This project is licensed under the GNU General Public License v3.0 (same as most major WoW UI addons and libraries) - see the [LICENSE](LICENSE) file for details.
