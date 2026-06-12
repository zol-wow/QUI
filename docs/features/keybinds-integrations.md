---
layout: default
title: Keybinds & Integrations
parent: Features
nav_order: 17
---

# Keybinds & Integrations

QUI includes a built-in keybind management system powered by LibKeyBound and integration hooks for compatible UI tools. The keybind system gives you visual keybind text on your CDM icons, action bars, and tracker bars, while integration hooks let QUI fit into a broader UI setup.

## Overview

The keybind features cover two areas: binding keys to abilities through hover-and-press mode and displaying those bindings as text overlays on icons. Integration features cover compatible frame anchoring, profile switching, and shared media resources.

## How to Enable

Keybind features are available by default. To configure display options:

- Open `/qui` -- keybind display settings are within each module's settings.
- Type `/kb` in chat to toggle keybind mode for hover-and-press binding.
- Click-casting settings are in **General > Click-Cast** inside `/qui`.

Compatible integrations are configured through **General > Integrations** and related feature tiles. Most activate automatically when the related tool is detected.

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

## Integrations

### Compatible Frame Anchoring

- **Frame anchoring** -- When compatible timing, frame, or timeline tools are present, QUI can offer them as anchor targets or allow their frames to follow QUI layout elements.
- **Target frame anchor** -- The QUI Target unit frame can be used as an anchor target for compatible frames.
- **Configuration previews** -- Some compatible preview frames can be anchored while configuring layouts so the final setup is easier to judge.

### Profile Switching

- **Automatic profile switching** -- LibDualSpec integration lets QUI automatically switch to a different profile when you change specializations. Configure which profile maps to each spec in **General > Profiles**.

### Shared Media

- **Shared media resources** -- QUI registers its fonts, textures, and status bar textures with the shared media library. Fonts or textures registered by your UI setup are available in QUI's texture and font dropdowns.

## Tips

{: .note }
The `/kb` keybind mode works on any compatible LibKeyBound frame, not just QUI elements.

{: .important }
Keybind overrides are stored per character and per spec. If you change a keybind override on your Retribution Paladin, it will not affect your Holy spec's overrides on the same character. This is intentional -- different specs often use different keybind layouts.

{: .note }
Compatible frame integrations require the related tool to be installed and loaded. QUI checks at startup and only enables relevant anchoring options when they are detected. No manual activation is needed.

{: .note }
Shared media integration is bidirectional. Installing a font or texture pack that registers media resources will automatically make those resources available in QUI's dropdowns without additional configuration.
