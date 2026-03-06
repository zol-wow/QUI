---
layout: default
title: Skyriding
parent: Features
nav_order: 13
---

# Skyriding

QUI replaces the default Skyriding HUD with a fully customizable vigor bar, giving you precise control over how vigor charges, recharge progress, and flight speed are displayed. If you spend any amount of time in the air, this module turns the vigor system from a small default UI element into a clear, readable display that fits your HUD.

## Overview

The Skyriding module provides a segmented vigor bar that shows each vigor charge as a distinct segment, a Second Wind recharge indicator, and an optional speed readout. Every visual element -- colors, textures, font sizes, and bar dimensions -- is configurable. The module also detects the Thrill of the Skies buff and changes the bar color to signal when you have bonus vigor regeneration active.

Visibility is handled automatically by default: the bar appears when you are flying and fades out when you land. You can override this to keep the bar visible at all times or define custom visibility conditions.

## How to Enable

The Skyriding module is enabled by default when flying is available. To configure it:

- Open `/qui` and navigate to the **QoL > Skyriding** tab.

To reposition the bar, unlock it in the Skyriding settings and drag it to your preferred location.

## Key Features

- **Segmented vigor bar** -- Each vigor charge is displayed as a separate segment within the bar, making it easy to see exactly how many charges you have at a glance.
- **Second Wind indicator** -- Shows recharge progress toward your next vigor charge. Can be displayed as a mini-bar beneath the vigor bar or as a scaled overlay within the main bar.
- **Speed display** -- Shows your current flight speed as a percentage with configurable font size.
- **Vigor text** -- Displays your vigor charges in fraction format (e.g., "3/6") with configurable font size.
- **Thrill of the Skies detection** -- Automatically changes the bar color (orange by default) when the Thrill of the Skies buff is active, giving you a clear visual signal that vigor is regenerating faster.
- **Full color control** -- Bar fill color, background color, segment divider color, recharge bar color, and border color are all independently configurable. Class color option available for the main bar fill.
- **Bar texture selection** -- Choose from any LibSharedMedia status bar texture for the vigor bar appearance.
- **Automatic fade** -- When you land, the bar fades out after a configurable delay with a configurable fade duration, keeping your ground HUD clean.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Visibility mode | When the bar appears: flying only, always, or custom | Flying only |
| Fade delay | Seconds to wait after landing before fading | Configurable |
| Fade duration | How long the fade-out animation takes | Configurable |
| Bar width | Width of the vigor bar in pixels | Varies |
| Vigor height | Height of the main vigor bar | Varies |
| Second Wind height | Height of the recharge indicator bar | Varies |
| Speed font size | Font size for the speed percentage display | Varies |
| Vigor font size | Font size for the charge fraction text | Varies |
| Thrill color | Bar color when Thrill of the Skies is active | Orange |
| Class color | Use your class color for the bar fill | Disabled |
| Lock position | Prevent the bar from being moved | Enabled |

## Tips

{: .note }
The Thrill of the Skies color change is a useful cue to adjust your flying style. When the bar turns orange, you are regenerating vigor faster -- a good time to use vigor-heavy maneuvers like climbing or dashing.

{: .important }
If you set visibility to "always," the bar will remain on screen even when you are on the ground. This can be useful if you frequently mount and dismount, but most players prefer "flying only" to keep the ground HUD uncluttered.

{: .note }
The Second Wind mini-bar is especially helpful during extended flights where you need to track exactly when your next vigor charge will be ready. It fills progressively as the recharge timer counts down.
