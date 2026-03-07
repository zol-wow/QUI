---
layout: default
title: Chat
parent: Features
nav_order: 5
---

# Chat

QUI enhances the default World of Warcraft chat window with visual and functional improvements. Rather than replacing the chat system entirely, QUI layers quality-of-life upgrades on top of Blizzard's chat frames -- a glass-style background, clickable URLs, timestamps, message fading, and a copy button.

## Overview

The chat module applies a modern look to your chat window while adding features that Blizzard's default implementation lacks. Everything is optional and individually toggleable so you can pick just the enhancements you want.

## How to Enable

Chat enhancements are enabled by default. To access settings, open `/qui` and navigate to the **Chat** tab.

## Key Features

- **Glass effect** -- Applies a semi-transparent background to the chat window with configurable alpha and color. Gives the chat a modern, translucent appearance that blends with your UI.
- **Message fade** -- Messages automatically fade out after a configurable delay. Disabled by default so messages remain visible until you scroll.
- **Font outline** -- Forces an outline on chat text for better readability against busy backgrounds.
- **URL detection** -- Automatically detects URLs in chat messages and makes them clickable. Highlighted in a custom color (blue by default) so they stand out from regular text.
- **UI cleanup** -- Hides the social button, channel button, and scroll buttons from the chat frame for a cleaner appearance.
- **Edit box styling** -- The message input box gets the glass effect treatment with configurable height and an option to position it at the top of the chat window instead of the bottom.
- **Timestamps** -- Adds timestamps to chat messages in 24-hour or 12-hour format with a custom color. Disabled by default.
- **Copy button** -- A button that copies the chat contents. Multiple visibility modes: always visible, visible on hover, hidden, or disabled entirely.
- **Intro message** -- Toggle whether QUI shows its login message when you first log in or reload.
- **Message history** -- Navigate through your previously sent messages using the up and down arrow keys. Stores up to 50 messages.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Glass effect | Semi-transparent chat background | Enabled |
| Glass alpha | Background opacity (0-1) | 0.5 |
| Message fade | Auto-fade messages after delay | Disabled |
| Font outline | Force outline on chat text | Enabled |
| URL detection | Make URLs clickable | Enabled |
| URL color | Color for detected URLs | Blue |
| Hide buttons | Remove social/channel/scroll buttons | Enabled |
| Timestamps | Show message timestamps | Disabled |
| Timestamp format | 24-hour or 12-hour clock | 24h |
| Copy button | Copy button visibility mode | Hover |

## Tips

{: .note }
The glass effect alpha controls how opaque the chat background is. A value of 0 is fully transparent (no background), while 1 is fully opaque. Values around 0.4-0.6 tend to work well for readability without being visually heavy.

{: .note }
Message history using arrow keys works just like a terminal -- press the up arrow to cycle through your last 50 sent messages. This is especially useful for repeating chat commands or re-sending messages.

{: .important }
When URL detection is enabled, clicking a URL in chat opens a small dialog where you can copy the link. WoW does not allow addons to open web browsers directly, so you will need to copy and paste the URL manually.

{: .note }
The edit box "position top" option moves the chat input above the chat window instead of below it. Some players prefer this layout as it keeps the input closer to the center of the screen.
