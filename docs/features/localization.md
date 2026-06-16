---
layout: default
title: Localization
parent: Features
nav_order: 22
---

# Localization

QUI's interface is translated into 11 languages. The language follows your WoW client automatically — there is nothing to configure, and English clients see no change.

## Supported Languages

| Language | Client locale |
|----------|---------------|
| English | enUS / enGB |
| German | deDE |
| Spanish (Spain) | esES |
| Spanish (Mexico) | esMX |
| French | frFR |
| Italian | itIT |
| Korean | koKR |
| Portuguese (Brazil) | ptBR |
| Russian | ruRU |
| Chinese (Simplified) | zhCN |
| Chinese (Traditional) | zhTW |

## What Gets Translated

QUI translates its own interface text, including:

- Layout Mode and frame movers
- Datatexts and Info Bar widget names and context menus
- Tooltips and alerts
- Chat
- The damage meter

{: .note }
Options search currently remains in English. Blizzard's own UI text is unaffected — QUI only translates the text it owns.

## CJK Font Rendering

Korean and Chinese use writing systems that QUI's display font does not include glyphs for. On those clients QUI automatically selects a font fallback that can render the script, so Korean and Chinese text displays correctly without any manual toggle.

## How the Language Is Chosen

QUI reads your WoW client language and loads the matching translation at login. To change QUI's language, change your game client language; there is no separate language setting inside `/qui`.
