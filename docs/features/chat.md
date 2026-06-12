---
layout: default
title: Chat
parent: Features
nav_order: 5
---

# Chat

QUI offers two chat paths: lightweight styling for Blizzard chat, or the opt-in **QUI Chat** module that replaces the visible chat display with QUI-owned windows and tabs.

## Overview

The default path keeps Blizzard chat and applies readability features such as cleaner chrome, font handling, URLs, timestamps, sound alerts, and message history.

The QUI Chat module is a larger beta feature. It owns the visible chat display, supports multiple chat windows, saved tabs, whisper conversation tabs, copy tools, a custom scrollbar, tab overflow, and an embedded Combat Log tab.

## How to Enable

Stock-chat styling is configured from `/qui` > **Chat & Tooltips**.

To use QUI Chat:

1. Open `/qui` > **Module Addons**.
2. Enable **Chat**.
3. Reload if prompted.
4. Open `/qui` > **Chat & Tooltips** to configure windows, tabs, copy behavior, history, and readability options.

## Key Features

### QUI Chat

- **Multiple windows** -- configure more than one QUI chat window and position them in Layout Mode.
- **Saved tabs** -- create custom tabs with their own channel filters.
- **Whisper conversation tabs** -- show direct conversations as extra tabs without removing whispers from your normal tabs.
- **Tab overflow menu** -- extra tabs fold into a `>>` menu when the tab bar runs out of room.
- **Combat Log tab** -- embed the Combat Log as a pinned tab in the first chat window.
- **Copy window** -- copy visible chat lines with readable link text and preserved colors.
- **Reply support** -- incoming whispers register as reply targets for the normal reply keybind.
- **Cross-realm names** -- optional setting to show `Name-Realm` sender names.

### Shared Chat Polish

- **Glass effect** -- semi-transparent chat background with configurable alpha and color.
- **Message fade** -- optional auto-fade after a configurable delay.
- **Font outline** -- stronger readability against busy backgrounds.
- **URL detection** -- clickable copy dialog for detected URLs.
- **Edit box styling** -- configurable height and top/bottom placement.
- **Timestamps** -- optional 24-hour or 12-hour timestamps.
- **Sound alerts** -- configurable alerts for incoming message types.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Enable Chat module | Use QUI-owned chat display | Off |
| Glass effect | Semi-transparent chat background | Enabled |
| Glass alpha | Background opacity (0-1) | 0.5 |
| Message fade | Auto-fade messages after delay | Disabled |
| Font outline | Force outline on chat text | Enabled |
| URL detection | Make URLs clickable | Enabled |
| URL color | Color for detected URLs | Blue |
| Timestamps | Show message timestamps | Disabled |
| Timestamp format | 24-hour or 12-hour clock | 24h |
| Copy button | Copy button visibility mode | Hover |
| Combat Log tab | Embed the Combat Log in QUI Chat | Enabled when QUI Chat is enabled |
| Show realm names | Show `Name-Realm` chat senders | Disabled |

## Tips

{: .note }
The glass effect alpha controls how opaque the chat background is. A value of 0 is fully transparent (no background), while 1 is fully opaque. Values around 0.4-0.6 tend to work well for readability without being visually heavy.

{: .note }
Message history using arrow keys works just like a terminal -- press the up arrow to cycle through your last 50 sent messages. This is especially useful for repeating chat commands or re-sending messages.

{: .important }
When URL detection is enabled, clicking a URL in chat opens a small dialog where you can copy the link. WoW does not allow addons to open web browsers directly, so you will need to copy and paste the URL manually.

{: .note }
The edit box "position top" option moves the chat input above the chat window instead of below it. Some players prefer this layout as it keeps the input closer to the center of the screen.

{: .important }
QUI Chat is a beta takeover module. If you prefer the stock chat flow, leave the Chat module disabled and use the styling options only.
