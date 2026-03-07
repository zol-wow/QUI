---
layout: default
title: Keybinds & Integrations
parent: Features
nav_order: 17
---

# Keybinds & Integrations

QUI includes a built-in keybind management system powered by LibKeyBound and integrates with several popular third-party addons. The keybind system gives you visual keybind text on your CDM icons, action bars, and tracker bars, while the integrations let QUI work alongside other addons as part of a cohesive UI.

## Overview

The keybind features cover two areas: binding keys to abilities (via LibKeyBound's hover-and-press system) and displaying those bindings as text overlays on icons. The integration features connect QUI to external addons for frame positioning, nameplate styling, profile switching, and shared media resources.

## How to Enable

Keybind features are available by default. To configure display options:

- Open `/qui` and navigate to the **Utility > Keybinds** tab.
- Type `/kb` in chat to toggle keybind mode for hover-and-press binding.

Third-party integrations are configured in their respective tabs within `/qui`, and most activate automatically when the relevant addon is detected.

## Keybind Features

### LibKeyBound Integration

- **Hover-and-press binding** -- Type `/kb` to enter keybind mode. Hover over any bindable icon (CDM, action bar, tracker) and press the key you want to assign. Press the key again to unbind. Press Escape or type `/kb` again to exit.
- **Visual feedback** -- While in keybind mode, hoverable elements highlight to indicate they accept bindings.

### Keybind Display on CDM Icons

- **Text overlay** -- Each CDM icon can show its keybind as text, positioned on the icon face.
- **Font size** -- Configurable text size for readability at different icon sizes.
- **Text color** -- Defaults to gold for contrast against icon art. Fully customizable.
- **Anchor point and offset** -- Control where the keybind text sits on the icon (top-left, center, bottom-right, etc.) with pixel offsets for fine adjustment.

### Keybind Display on Action Bars

- **Per-bar customization** -- Each action bar can independently enable or disable keybind text and adjust its appearance.
- **Consistent styling** -- Uses the same font, color, and anchor options as CDM keybind text for a unified look.

### Keybind Overrides

- **Per-character and per-spec storage** -- Keybind overrides are saved per character and per specialization, so switching specs automatically loads the correct bindings.
- **Separate toggles** -- CDM keybind overrides and Custom Tracker keybind overrides can be enabled or disabled independently.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Show keybinds on CDM | Display keybind text on CDM icons | Enabled |
| Keybind font size | Text size for keybind display | Configurable |
| Keybind color | Color of keybind text | Gold |
| Keybind anchor | Position of text on the icon | Configurable |
| Keybind offset X/Y | Pixel offset from the anchor point | 0, 0 |
| CDM overrides | Enable per-character keybind overrides for CDM | Disabled |
| Tracker overrides | Enable per-character keybind overrides for trackers | Disabled |

## Third-Party Integrations

### DandersFrames

QUI detects DandersFrames automatically and enables frame anchoring integration:

- **Anchor party and raid frames** -- Position DandersFrames' party and raid group frames relative to QUI elements using the anchoring system.
- **Anchor pinned frames** -- DandersFrames pinned (bookmarked) frames can also be anchored to QUI elements.
- **Target unitframe as anchor target** -- The QUI Target unit frame is available as an anchor target for DandersFrames elements.
- **Container anchoring** -- DandersFrames preview frame containers can be anchored to QUI elements for consistent positioning during configuration.

### BigWigs

- **Frame anchoring** -- When BigWigs is installed, QUI elements can be anchored to the BigWigs bar display. This lets you position your CDM or other elements relative to boss timers, keeping your encounter HUD organized.

### Plater and Platynator

- **Bundled import strings** -- QUI ships with pre-built Plater and Platynator nameplate profiles that complement QUI's visual style. These are available in the **Core > Import** tab and can be applied with one click.

### LibDualSpec

- **Automatic profile switching** -- LibDualSpec integration lets QUI automatically switch to a different profile when you change specializations. Configure which profile maps to each spec in the **Core > Profiles** tab.

### LibSharedMedia

- **Shared media resources** -- QUI registers its fonts, textures, and status bar textures with LibSharedMedia, making them available to other addons. Conversely, any fonts or textures registered by other addons via LibSharedMedia are available in QUI's texture and font dropdowns.

## Tips

{: .note }
The `/kb` keybind mode works on any LibKeyBound-compatible frame, not just QUI elements. If other addons in your setup use LibKeyBound, you can bind their frames in the same session.

{: .important }
Keybind overrides are stored per character and per spec. If you change a keybind override on your Retribution Paladin, it will not affect your Holy spec's overrides on the same character. This is intentional -- different specs often use different keybind layouts.

{: .note }
The DandersFrames and BigWigs integrations require those addons to be installed and loaded. QUI checks for their presence at startup and only enables the relevant anchoring options when they are detected. No manual activation is needed.

{: .note }
LibSharedMedia integration is bidirectional. Installing a font or texture pack that registers with LibSharedMedia will automatically make those resources available in QUI's dropdowns without any additional configuration.
