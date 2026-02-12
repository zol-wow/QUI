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

1. Download the latest release from [Releases](https://github.com/zol-wow/QUI/releases)
2. Extract to `Interface\AddOns\QUI`
3. Enable in-game and reload UI (`/rl` or `/reload`)

### Installation via WowUp

1. Make sure to use the latest BETA(!) version of WowUp (change the update channel in the app settings to beta)
2. Install Addons > Install from URL > paste this repos URL

### Updating via WowUp

Updating addons that have been installed via URL from public github repos is currently broken. This is an issue with WowUp, not QUI. I already submitted a PR for WowUp to fix this issue - until they merge it or fix it themselves, we'll need to wait. So the recommended way on WowUp's end is to delete and repeat the install workflow.

For everyone who wants a bit more automation: MrMime71 created a little updating tool, you'll find it here: https://github.com/zol-wow/QUI/issues/26#issuecomment-3861104336

Eventually this will go up on CurseForge and Wago, I suppose, but currently bugfixing is my top prio.


## License

This project is licensed under the GNU General Public License v3.0 (same as most major WoW UI addons and libraries) - see the [LICENSE](LICENSE) file for details.
